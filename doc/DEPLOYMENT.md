# デプロイ手順（Cloud Run / GitHub Actions）

関連資料：`Makefile`、`.github/workflows/ci.yml`、`Dockerfile`、`cloudbuild.yaml`

---

## 1. 全体の流れ

| きっかけ | 実行されるもの |
| --- | --- |
| PR の作成・更新 | ci ジョブ（lint / typecheck / format / test / build） |
| main への push（PR のマージ） | ci ジョブ → deploy ジョブ（`make deploy`：Cloud Build でイメージ作成 → Cloud Run へデプロイ） |

deploy ジョブは Workload Identity Federation（WIF）で GCP に認証する。サービスアカウントの鍵ファイルは使わない。

---

## 2. 初回セットアップ（実施済み）

GCP プロジェクト `eigyo-509504` に対して、以下を一度だけ実行する。どれも何度実行してもよい。

| 手順 | コマンド | 内容 |
| --- | --- | --- |
| 1 | `make setup` | API の有効化、Artifact Registry、ソース用バケット、サービスアカウント（`eigyo-run` / `eigyo-build` / `eigyo-deploy`）と権限 |
| 2 | `make setup-github` | WIF のプールとプロバイダー、`eigyo-deploy` への `workloadIdentityUser` 付与、GitHub の Variables と `production` environment の設定 |
| 3 | `make secret` | `DATABASE_URL` を Secret Manager（`database-url`）に登録し、`eigyo-run` に読み取り権限を付与 |

`make secret` は対話入力（画面に表示しない）のほか、パイプでも渡せる。

```sh
printf '%s' "$DATABASE_URL" | make secret
```

> 本番 DB（#28）ができるまでは、`database-url` にダミーの接続文字列を登録している。アプリはまだ DB に接続しないため、デプロイには影響しない。

---

## 3. 認証の信頼条件

`make setup-github` で作成する WIF プロバイダーは、次の条件を**両方**満たす GitHub Actions のトークンだけを受け付ける。

| 条件 | 値 | 理由 |
| --- | --- | --- |
| `assertion.repository_id` | `1383586105`（kuny518/eigyo） | リポジトリ名ではなく不変の ID で判定し、同名リポジトリの再作成による乗っ取りを防ぐ |
| `assertion.ref` | `refs/heads/main` | main ブランチ上のワークフローからのみデプロイできるようにする |

GitHub 側の設定：

| 項目 | 値 |
| --- | --- |
| Variables `GCP_WORKLOAD_IDENTITY_PROVIDER` | `projects/173821429814/locations/global/workloadIdentityPools/github/providers/github` |
| Variables `GCP_DEPLOY_SA` | `eigyo-deploy@eigyo-509504.iam.gserviceaccount.com` |
| Environment `production` | デプロイできるブランチを `main` のみに制限 |

---

## 4. main ブランチの保護について（制約）

このリポジトリは GitHub Free の private リポジトリのため、**ブランチ保護とルールセットが使えない**（API は 403 を返す）。そのため「main への直接 push の禁止」「PR のマージ前に CI 成功を必須にする」は GitHub 側で強制できない。

代わりに次の対策を入れている。

| 対策 | 内容 | 限界 |
| --- | --- | --- |
| pre-push フック | `.husky/pre-push` で main への push を拒否する | ローカルのフックなので `--no-verify` で回避できる |
| WIF の条件 | main 以外のブランチからはデプロイできない | main への直接 push 自体は防げない |
| production environment | main 以外のブランチからは deploy ジョブを実行できない | 同上 |

GitHub 側で強制するには、GitHub Pro 以上にアップグレードするか、リポジトリを public にする必要がある。

---

## 5. 手動デプロイ・確認

```sh
make deploy   # ローカルの gcloud 認証でビルド・デプロイ（未コミットの変更があるとタグに -dirty が付く）
make url      # サービスの URL
curl "$(make -s url)/api/health"
```
