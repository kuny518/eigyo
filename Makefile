SHELL := /bin/bash
.DEFAULT_GOAL := help

# ---------------------------------------------------------------
# 設定（make deploy REGION=... のように上書き可）
# ---------------------------------------------------------------
PROJECT_ID  ?= eigyo-509504
REGION      ?= asia-northeast1
SERVICE     ?= eigyo
AR_REPO     ?= eigyo
DB_SECRET   ?= database-url
# owner/repo 形式
GITHUB_REPO ?= kuny518/eigyo

WIF_POOL     := github
WIF_PROVIDER := github
RUNTIME_SA   := $(SERVICE)-run@$(PROJECT_ID).iam.gserviceaccount.com
BUILD_SA     := $(SERVICE)-build@$(PROJECT_ID).iam.gserviceaccount.com
DEPLOY_SA    := $(SERVICE)-deploy@$(PROJECT_ID).iam.gserviceaccount.com
SOURCE_BUCKET := gs://$(PROJECT_ID)-cloudbuild-src

# コミット SHA をタグにする。未コミットの変更があれば -dirty を付ける
TAG   ?= $(shell git rev-parse --short HEAD)$(shell git diff --quiet HEAD 2>/dev/null || echo -dirty)
IMAGE := $(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(AR_REPO)/$(SERVICE):$(TAG)

# ローカルの gcloud の既定プロジェクトに関係なく、常にこのプロジェクトを操作する
GCLOUD := gcloud --project=$(PROJECT_ID) --quiet
# 使うときだけ取得する
PROJECT_NUMBER = $(shell gcloud projects describe $(PROJECT_ID) --format='value(projectNumber)')
# リポジトリ名ではなく不変の ID で信頼する（同名リポジトリの再作成による乗っ取りを防ぐ）
GITHUB_REPO_ID = $(shell gh api repos/$(GITHUB_REPO) -q .id)
WIF_PROVIDER_NAME = projects/$(PROJECT_NUMBER)/locations/global/workloadIdentityPools/$(WIF_POOL)/providers/$(WIF_PROVIDER)
# 作成直後のサービスアカウントは IAM への反映に時間がかかるため、権限付与は失敗したらやり直す
RETRY = for i in 1 2 3 4 5 6; do $(1) >/dev/null && break; \
	[ $$i = 6 ] && exit 1; echo "  IAM への反映待ち。10秒後に再試行 ($$i/5)"; sleep 10; done

.PHONY: help setup setup-github secret build deploy url

help: ## ターゲット一覧
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

setup: ## GCP の初期構築（API 有効化・Artifact Registry・サービスアカウント・権限）。何度実行してもよい
	$(GCLOUD) services enable run.googleapis.com artifactregistry.googleapis.com \
		cloudbuild.googleapis.com secretmanager.googleapis.com iam.googleapis.com \
		iamcredentials.googleapis.com sts.googleapis.com
	$(GCLOUD) artifacts repositories describe $(AR_REPO) --location=$(REGION) >/dev/null 2>&1 || \
		$(GCLOUD) artifacts repositories create $(AR_REPO) --location=$(REGION) --repository-format=docker
	$(GCLOUD) storage buckets describe $(SOURCE_BUCKET) >/dev/null 2>&1 || \
		$(GCLOUD) storage buckets create $(SOURCE_BUCKET) --location=$(REGION) --uniform-bucket-level-access
	@for sa in run build deploy; do \
		$(GCLOUD) iam service-accounts describe $(SERVICE)-$$sa@$(PROJECT_ID).iam.gserviceaccount.com >/dev/null 2>&1 || \
			$(GCLOUD) iam service-accounts create $(SERVICE)-$$sa --display-name="$(SERVICE) $$sa"; \
	done
	@# ビルド用: イメージの push、ログ出力、ソースの読み取り
	@echo "権限を付与しています..."
	@$(call RETRY,$(GCLOUD) artifacts repositories add-iam-policy-binding $(AR_REPO) --location=$(REGION) \
		--member=serviceAccount:$(BUILD_SA) --role=roles/artifactregistry.writer)
	@$(call RETRY,$(GCLOUD) projects add-iam-policy-binding $(PROJECT_ID) --condition=None \
		--member=serviceAccount:$(BUILD_SA) --role=roles/logging.logWriter)
	@$(call RETRY,$(GCLOUD) storage buckets add-iam-policy-binding $(SOURCE_BUCKET) \
		--member=serviceAccount:$(BUILD_SA) --role=roles/storage.objectViewer)
	@# デプロイ用（GitHub Actions）: ビルド起動、Cloud Run 更新、ソースのアップロード
	@for role in roles/run.admin roles/cloudbuild.builds.editor roles/logging.viewer roles/serviceusage.serviceUsageConsumer; do \
		$(call RETRY,$(GCLOUD) projects add-iam-policy-binding $(PROJECT_ID) --condition=None \
			--member=serviceAccount:$(DEPLOY_SA) --role=$$role) || exit 1; \
	done
	@$(call RETRY,$(GCLOUD) storage buckets add-iam-policy-binding $(SOURCE_BUCKET) \
		--member=serviceAccount:$(DEPLOY_SA) --role=roles/storage.admin)
	@for sa in $(RUNTIME_SA) $(BUILD_SA); do \
		$(call RETRY,$(GCLOUD) iam service-accounts add-iam-policy-binding $$sa \
			--member=serviceAccount:$(DEPLOY_SA) --role=roles/iam.serviceAccountUser) || exit 1; \
	done
	@echo "setup 完了。続けて make setup-github と make secret を実行してください（手順は doc/DEPLOYMENT.md）"

setup-github: ## GitHub Actions からのキーレス認証（WIF）と GitHub 側の設定（Variables・environment）。何度実行してもよい
	@test -n "$(GITHUB_REPO_ID)" || { echo "gh api repos/$(GITHUB_REPO) に失敗しました（gh auth login を確認）"; exit 1; }
	$(GCLOUD) iam workload-identity-pools describe $(WIF_POOL) --location=global >/dev/null 2>&1 || \
		$(GCLOUD) iam workload-identity-pools create $(WIF_POOL) --location=global --display-name="GitHub Actions"
	@# 指定リポジトリの main ブランチからのみ認証を許可する。既存のプロバイダーはこの定義で上書きする
	@if $(GCLOUD) iam workload-identity-pools providers describe $(WIF_PROVIDER) --location=global \
		--workload-identity-pool=$(WIF_POOL) >/dev/null 2>&1; then op=update-oidc; else op=create-oidc; fi; \
	set -x; $(GCLOUD) iam workload-identity-pools providers $$op $(WIF_PROVIDER) --location=global \
		--workload-identity-pool=$(WIF_POOL) \
		--display-name="GitHub $(GITHUB_REPO)" \
		--issuer-uri=https://token.actions.githubusercontent.com \
		--attribute-mapping=google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.repository_id=assertion.repository_id,attribute.ref=assertion.ref \
		--attribute-condition="assertion.repository_id=='$(GITHUB_REPO_ID)' && assertion.ref=='refs/heads/main'"
	@$(call RETRY,$(GCLOUD) iam service-accounts add-iam-policy-binding $(DEPLOY_SA) --role=roles/iam.workloadIdentityUser \
		--member=principalSet://iam.googleapis.com/projects/$(PROJECT_NUMBER)/locations/global/workloadIdentityPools/$(WIF_POOL)/attribute.repository_id/$(GITHUB_REPO_ID))
	@# GitHub 側：deploy ジョブが参照する Variables と production environment
	gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER -R $(GITHUB_REPO) --body "$(WIF_PROVIDER_NAME)"
	gh variable set GCP_DEPLOY_SA -R $(GITHUB_REPO) --body "$(DEPLOY_SA)"
	@# production environment は main ブランチからのみ使えるようにする
	echo '{"deployment_branch_policy":{"protected_branches":false,"custom_branch_policies":true}}' | \
		gh api -X PUT repos/$(GITHUB_REPO)/environments/production --input - --silent
	gh api repos/$(GITHUB_REPO)/environments/production/deployment-branch-policies -q '.branch_policies[].name' | grep -qx main || \
		gh api -X POST repos/$(GITHUB_REPO)/environments/production/deployment-branch-policies -f name=main -f type=branch --silent
	@echo "setup-github 完了（repository_id=$(GITHUB_REPO_ID)）"

secret: ## DATABASE_URL を Secret Manager に登録・更新（入力は画面に表示しない）
	@# 対話端末ならエコーなしで入力。パイプで渡すこともできる（例: printf '%s' "$$URL" | make secret）
	@if [ -t 0 ]; then read -rsp "DATABASE_URL: " value && echo; else value=$$(cat); fi && \
	if $(GCLOUD) secrets describe $(DB_SECRET) >/dev/null 2>&1; then \
		printf '%s' "$$value" | $(GCLOUD) secrets versions add $(DB_SECRET) --data-file=-; \
	else \
		printf '%s' "$$value" | $(GCLOUD) secrets create $(DB_SECRET) --replication-policy=automatic --data-file=-; \
	fi
	$(GCLOUD) secrets add-iam-policy-binding $(DB_SECRET) \
		--member=serviceAccount:$(RUNTIME_SA) --role=roles/secretmanager.secretAccessor >/dev/null

build: ## Cloud Build でイメージをビルドし Artifact Registry に push
	$(GCLOUD) builds submit --config=cloudbuild.yaml --substitutions=_IMAGE=$(IMAGE) \
		--service-account=projects/$(PROJECT_ID)/serviceAccounts/$(BUILD_SA) \
		--gcs-source-staging-dir=$(SOURCE_BUCKET)/source

deploy: build ## ビルドして Cloud Run にデプロイ
	$(GCLOUD) run deploy $(SERVICE) --image=$(IMAGE) --region=$(REGION) \
		--service-account=$(RUNTIME_SA) \
		--set-secrets=DATABASE_URL=$(DB_SECRET):latest \
		--allow-unauthenticated

url: ## デプロイ済みサービスの URL を表示
	@$(GCLOUD) run services describe $(SERVICE) --region=$(REGION) --format='value(status.url)'
