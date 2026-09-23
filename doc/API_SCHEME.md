# 営業日報システム API仕様書

作成日：2026-09-23
関連資料：営業日報システム 要件定義書／画面定義書

---

## 1. 概要

| 項目 | 仕様 |
| --- | --- |
| 方式 | REST / JSON |
| ベースURL | `https://{host}/api/v1` |
| 文字コード | UTF-8 |
| 認証 | Bearerトークン（ログインAPIで発行。`Authorization: Bearer {token}`） |
| トークン有効期限 | 最終アクセスから60分（画面定義書のセッションタイムアウトと同じ） |
| 日付形式 | `YYYY-MM-DD`（例：`2026-09-23`） |
| 時刻形式 | `HH:MM`（例：`10:00`） |
| 日時形式 | ISO 8601、JST（例：`2026-09-23T18:05:00+09:00`） |
| 命名規則 | JSONのキーはsnake_case（テーブル定義に合わせる） |

---

## 2. API一覧

| No | メソッド | パス | 概要 | 営業 | 上長 | 管理者 | 対応画面 |
| --- | --- | --- | --- | :-: | :-: | :-: | --- |
| A-01 | POST | /auth/login | ログイン | ○ | ○ | ○ | SCR-01 |
| A-02 | POST | /auth/logout | ログアウト | ○ | ○ | ○ | 共通 |
| A-03 | GET | /auth/me | ログインユーザー情報取得 | ○ | ○ | ○ | 共通 |
| D-01 | GET | /dashboard | ホーム表示用データ取得 | ○ | ○ | ○ | SCR-02 |
| R-01 | GET | /reports | 日報一覧・検索 | ○ | ○ | ○ | SCR-03 |
| R-02 | POST | /reports | 日報作成（訪問記録含む） | ○ | - | - | SCR-04 |
| R-03 | GET | /reports/{report_id} | 日報詳細取得 | ○ | ○ | ○ | SCR-04, SCR-05 |
| R-04 | PUT | /reports/{report_id} | 日報更新（訪問記録含む） | ○ | - | - | SCR-04 |
| R-05 | POST | /reports/{report_id}/submit | 日報提出 | ○ | - | - | SCR-04 |
| R-06 | POST | /reports/{report_id}/review | 確認済にする | - | ○ | - | SCR-05 |
| R-07 | POST | /reports/{report_id}/return | 差し戻し | - | ○ | - | SCR-05 |
| C-01 | GET | /reports/{report_id}/comments | コメント一覧取得 | ○ | ○ | ○ | SCR-05 |
| C-02 | POST | /reports/{report_id}/comments | コメント投稿・返信 | △ | ○ | - | SCR-05 |
| M-01 | GET | /customers | 顧客一覧・検索 | ○ | ○ | ○ | SCR-04-M, SCR-06 |
| M-02 | GET | /customers/recent | 最近訪問した顧客 | ○ | - | - | SCR-04-M |
| M-03 | GET | /customers/{customer_id} | 顧客詳細取得 | ○ | ○ | ○ | SCR-07 |
| M-04 | POST | /customers | 顧客登録 | - | - | ○ | SCR-07 |
| M-05 | PUT | /customers/{customer_id} | 顧客更新・無効化 | - | - | ○ | SCR-07 |
| S-01 | GET | /staff | 営業一覧・検索 | △ | ○ | ○ | SCR-03, SCR-08 |
| S-02 | GET | /staff/{staff_id} | 営業詳細取得 | - | - | ○ | SCR-09 |
| S-03 | POST | /staff | 営業登録 | - | - | ○ | SCR-09 |
| S-04 | PUT | /staff/{staff_id} | 営業更新・無効化 | - | - | ○ | SCR-09 |

凡例：○＝利用可、△＝制限付き（S-01は自分のみ返却、C-02は自分の日報への返信のみ）、-＝403

**設計方針**
- 訪問記録（visit_record）は日報の明細として、日報の作成・更新APIで一括送信する（行ごとのAPIは設けない）。SCR-04の「保存」1回で全行を確定させるため。
- マスタは物理削除APIを設けず、`is_active=false` への更新で無効化する。
- ステータス変更は専用エンドポイント（submit / review / return）で行い、PUTでは変更させない。

---

## 3. 共通仕様

### 3.1 リクエストヘッダー

| ヘッダー | 必須 | 値 |
| --- | :-: | --- |
| Authorization | ○（A-01以外） | `Bearer {token}` |
| Content-Type | ○（ボディあり） | `application/json` |

### 3.2 ページング（一覧系API共通）

| パラメータ | 型 | 初期値 | 備考 |
| --- | --- | --- | --- |
| page | int | 1 | 1始まり |
| per_page | int | 20 | 最大100 |

レスポンスには以下の `pagination` を含む。

```json
"pagination": { "page": 1, "per_page": 20, "total": 57, "total_pages": 3 }
```

### 3.3 HTTPステータス

| コード | 意味 | 主なケース |
| --- | --- | --- |
| 200 | OK | 取得・更新成功 |
| 201 | Created | 登録成功 |
| 204 | No Content | ログアウト成功 |
| 400 | Bad Request | JSON形式不正、パラメータ型不正 |
| 401 | Unauthorized | 未認証、トークン期限切れ |
| 403 | Forbidden | ロール・閲覧範囲外へのアクセス |
| 404 | Not Found | 対象が存在しない |
| 409 | Conflict | 同一日の日報重複、ステータス遷移不可、同時更新 |
| 422 | Unprocessable Entity | 入力チェックエラー |
| 500 | Internal Server Error | サーバーエラー |

閲覧範囲外の日報には、存在を推測させないため403ではなく404を返す。

### 3.4 エラーレスポンス

```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "入力内容に誤りがあります",
    "details": [
      { "field": "visits[1].visit_end", "message": "終了時刻は開始時刻以降にしてください" }
    ]
  }
}
```

| code | HTTP | 説明 |
| --- | --- | --- |
| UNAUTHORIZED | 401 | 未認証・トークン無効 |
| INVALID_CREDENTIALS | 401 | メールアドレスまたはパスワード誤り |
| FORBIDDEN | 403 | 権限なし |
| NOT_FOUND | 404 | 対象なし（閲覧範囲外を含む） |
| VALIDATION_ERROR | 422 | 入力チェックエラー（detailsに項目別） |
| REPORT_ALREADY_EXISTS | 409 | 同一営業・同一日の日報が既に存在 |
| INVALID_STATUS_TRANSITION | 409 | 現在のステータスでは実行不可 |
| CONFLICT_UPDATED | 409 | 他で更新済み（updated_at不一致） |
| DUPLICATE_EMAIL | 409 | メールアドレス重複 |

### 3.5 楽観的排他制御

更新系（R-04、M-05、S-04）はリクエストに取得時の `updated_at` を含める。サーバー側の値と一致しない場合は `409 CONFLICT_UPDATED` を返す。

---

## 4. API詳細

### 4.1 認証

#### A-01 POST /auth/login

**リクエスト**

```json
{ "email": "yamada@example.com", "password": "********" }
```

| 項目 | 型 | 必須 | 制約 |
| --- | --- | :-: | --- |
| email | string | ○ | メール形式、254文字以内 |
| password | string | ○ | 8〜64文字 |

**レスポンス 200**

```json
{
  "token": "eyJhbGciOi...",
  "expires_at": "2026-09-23T19:05:00+09:00",
  "user": {
    "staff_id": 12,
    "name": "山田 太郎",
    "role": "SALES",
    "manager_id": 3
  }
}
```

**エラー**：401 `INVALID_CREDENTIALS`（無効化された社員も同じエラーを返す）

#### A-02 POST /auth/logout

トークンを無効化する。レスポンス 204。

#### A-03 GET /auth/me

**レスポンス 200**

```json
{
  "staff_id": 12,
  "name": "山田 太郎",
  "email": "yamada@example.com",
  "department": "第一営業部",
  "position": "主任",
  "role": "SALES",
  "manager": { "staff_id": 3, "name": "佐藤 次郎" }
}
```

---

### 4.2 ホーム

#### D-01 GET /dashboard

ロールに応じて返す項目が変わる。該当しないブロックは `null`。

**レスポンス 200（上長の例）**

```json
{
  "today": {
    "report_date": "2026-09-23",
    "report_id": 1045,
    "status": "DRAFT"
  },
  "my_drafts": [
    { "report_id": 1040, "report_date": "2026-09-21", "status": "DRAFT" }
  ],
  "recent_comments": [
    {
      "comment_id": 88,
      "report_id": 1038,
      "report_date": "2026-09-20",
      "commenter_name": "佐藤 次郎",
      "target_type": "PROBLEM",
      "is_reply": false,
      "body_excerpt": "10%までなら可。明日話そう"
    }
  ],
  "recent_replies": [
    {
      "comment_id": 95,
      "parent_comment_id": 90,
      "report_id": 1044,
      "report_date": "2026-09-22",
      "commenter_name": "鈴木 花子",
      "target_type": "PROBLEM",
      "body_excerpt": "承知しました。明日10時に伺います"
    }
  ],
  "unreviewed_reports": [
    {
      "report_id": 1044,
      "report_date": "2026-09-22",
      "staff": { "staff_id": 15, "name": "鈴木 花子" },
      "visit_count": 3,
      "submitted_at": "2026-09-22T18:05:00+09:00"
    }
  ],
  "not_submitted_today": [
    { "staff_id": 16, "name": "田中 一郎", "status": "NOT_CREATED" }
  ]
}
```

| 項目 | 対象ロール | 備考 |
| --- | --- | --- |
| today | 営業・上長 | 当日の自分の日報。未作成なら `report_id: null, status: "NOT_CREATED"` |
| my_drafts | 営業・上長 | 自分の下書き（当日除く） |
| recent_comments | 営業・上長 | 自分の日報へのコメント・返信の最新5件（自分の投稿は除く）。本文は先頭30文字。`is_reply` は返信かどうか |
| recent_replies | 上長 | 自分が投稿したコメントへの返信の最新5件（自分の投稿は除く）。本文は先頭30文字 |
| unreviewed_reports | 上長 | 直属部下の提出済（SUBMITTED）日報 |
| not_submitted_today | 上長 | 当日未提出の直属部下 |

---

### 4.3 日報

#### ステータス定義

| 値 | 表示名 | 遷移元 → 遷移先 | 実行API |
| --- | --- | --- | --- |
| DRAFT | 下書き | （作成時） | R-02 |
| SUBMITTED | 提出済 | DRAFT → SUBMITTED | R-05 |
| REVIEWED | 確認済 | SUBMITTED → REVIEWED | R-06 |
| DRAFT | 下書き（差し戻し） | SUBMITTED → DRAFT | R-07 |

> 差し戻しを独立ステータス（RETURNED）にするかは未決。採用する場合、R-07の遷移先と `status` の値域を変更する。

#### R-01 GET /reports

**クエリパラメータ**

| パラメータ | 型 | 必須 | 備考 |
| --- | --- | :-: | --- |
| date_from | date | - | 報告日の開始 |
| date_to | date | - | 報告日の終了。date_from ≦ date_to |
| staff_id | int | - | 営業ロールは指定しても自分に固定 |
| customer_name | string | - | 訪問記録の顧客名で部分一致 |
| status | string | - | カンマ区切りで複数可（例：`SUBMITTED,REVIEWED`） |
| sort | string | - | `report_date_desc`（初期）/ `report_date_asc` |
| page, per_page | int | - | 3.2参照 |

**閲覧範囲**：営業＝自分、上長＝自分＋直属部下、管理者＝全件。上長・管理者に他人の下書きを返すかは未決（初期案では返さない）。

**レスポンス 200**

```json
{
  "items": [
    {
      "report_id": 1044,
      "report_date": "2026-09-22",
      "staff": { "staff_id": 15, "name": "鈴木 花子" },
      "visit_count": 3,
      "visit_customers": ["A社", "B社"],
      "status": "SUBMITTED",
      "comment_count": 1,
      "submitted_at": "2026-09-22T18:05:00+09:00"
    }
  ],
  "pagination": { "page": 1, "per_page": 20, "total": 57, "total_pages": 3 }
}
```

`visit_customers` は先頭2件の顧客名。`comment_count` は返信を含むコメントの件数。

#### R-02 POST /reports

ログインユーザーの日報を下書きとして作成する。

**リクエスト**

```json
{
  "report_date": "2026-09-23",
  "problem": "B社の値引き要求にどこまで応じるべきか相談したい。",
  "plan": "C社へ見積提出。",
  "visits": [
    {
      "customer_id": 101,
      "visit_start": "10:00",
      "visit_end": "11:00",
      "visit_content": "提案書の説明。先方は前向き。"
    },
    {
      "customer_id": 205,
      "visit_start": "14:00",
      "visit_end": "15:00",
      "visit_content": "定例会。"
    }
  ]
}
```

| 項目 | 型 | 必須 | 制約 |
| --- | --- | :-: | --- |
| report_date | date | ○ | 未来日不可 |
| problem | string | - | 2,000文字以内 |
| plan | string | - | 2,000文字以内 |
| visits | array | - | 0〜20件。配列の順番を sort_order とする |
| visits[].customer_id | int | ○ | 有効な顧客であること |
| visits[].visit_start | time | - | |
| visits[].visit_end | time | - | visit_start ≦ visit_end |
| visits[].visit_content | string | ○ | 1〜2,000文字 |

**レスポンス 201**：R-03と同じ形式。`Location: /api/v1/reports/{report_id}`

**エラー**：409 `REPORT_ALREADY_EXISTS`（details に既存の `report_id` を含め、画面側でその日報を開けるようにする）

#### R-03 GET /reports/{report_id}

**レスポンス 200**

```json
{
  "report_id": 1045,
  "report_date": "2026-09-23",
  "staff": { "staff_id": 12, "name": "山田 太郎" },
  "status": "DRAFT",
  "problem": "B社の値引き要求にどこまで応じるべきか相談したい。",
  "plan": "C社へ見積提出。",
  "submitted_at": null,
  "visits": [
    {
      "visit_id": 5001,
      "customer": { "customer_id": 101, "customer_name": "A社" },
      "visit_start": "10:00",
      "visit_end": "11:00",
      "visit_content": "提案書の説明。先方は前向き。",
      "sort_order": 1
    }
  ],
  "comments": [
    {
      "comment_id": 88,
      "parent_comment_id": null,
      "commenter": { "staff_id": 3, "name": "佐藤 次郎" },
      "target_type": "PROBLEM",
      "body": "10%までなら可。明日話そう",
      "created_at": "2026-09-22T19:10:00+09:00",
      "replies": [
        {
          "comment_id": 89,
          "parent_comment_id": 88,
          "commenter": { "staff_id": 12, "name": "山田 太郎" },
          "target_type": "PROBLEM",
          "body": "ありがとうございます。10%で提示します",
          "created_at": "2026-09-22T19:30:00+09:00"
        }
      ]
    }
  ],
  "permissions": {
    "can_edit": true,
    "can_submit": true,
    "can_comment": false,
    "can_reply": true,
    "can_review": false,
    "can_return": false
  },
  "created_at": "2026-09-23T17:40:00+09:00",
  "updated_at": "2026-09-23T17:55:00+09:00"
}
```

`permissions` はログインユーザーとステータスから算出し、画面のボタン表示制御に使う。`comments` の形式は C-01 と同じ。

| 項目 | true になる条件 |
| --- | --- |
| can_comment | 直属の上長、かつ `SUBMITTED` / `REVIEWED`（トップレベルのコメントを投稿できる） |
| can_reply | 日報の本人（ステータス問わず）、または直属の上長かつ `SUBMITTED` / `REVIEWED`（返信できる） |

#### R-04 PUT /reports/{report_id}

日報本体と訪問記録を丸ごと置き換える。

**実行条件**：本人かつ `status = DRAFT`。それ以外は 409 `INVALID_STATUS_TRANSITION`（他人の日報は404）。

**リクエスト**

```json
{
  "problem": "…",
  "plan": "…",
  "updated_at": "2026-09-23T17:55:00+09:00",
  "visits": [
    { "visit_id": 5001, "customer_id": 101, "visit_start": "10:00", "visit_end": "11:00", "visit_content": "…" },
    { "customer_id": 330, "visit_start": "16:00", "visit_end": "16:30", "visit_content": "…" }
  ]
}
```

- `visit_id` ありの行は更新、なしの行は追加、リクエストに含まれない既存行は削除。
- `report_date` は変更不可（変更したい場合は作り直し）。
- 項目制約はR-02と同じ。

**レスポンス 200**：R-03と同じ形式

#### R-05 POST /reports/{report_id}/submit

**実行条件**：本人かつ `status = DRAFT`

**提出時チェック（422）**

| 項目 | ルール |
| --- | --- |
| visits | 1件以上（訪問なしの日の扱いは未決） |
| problem | 必須（「特になし」可） |
| plan | 必須 |

**処理**：`status = SUBMITTED`、`submitted_at` を記録、上長へ通知。

**レスポンス 200**：R-03と同じ形式

#### R-06 POST /reports/{report_id}/review

**実行条件**：対象日報の営業の直属上長、かつ `status = SUBMITTED`

**処理**：`status = REVIEWED`

**レスポンス 200**：R-03と同じ形式

#### R-07 POST /reports/{report_id}/return

**実行条件**：R-06と同じ

**リクエスト**

```json
{ "target_type": "PROBLEM", "body": "訪問内容をもう少し具体的に書いてください。" }
```

| 項目 | 型 | 必須 | 制約 |
| --- | --- | :-: | --- |
| target_type | string | ○ | `PROBLEM` / `PLAN` |
| body | string | ○ | 1〜1,000文字（差し戻し理由） |

**処理**：差し戻し理由をコメントとして登録し、`status = DRAFT`、`submitted_at` をクリア、営業へ通知。1トランザクションで実行する。

**レスポンス 200**：R-03と同じ形式

---

### 4.4 コメント

#### C-01 GET /reports/{report_id}/comments

**クエリパラメータ**

| パラメータ | 型 | 必須 | 備考 |
| --- | --- | :-: | --- |
| target_type | string | - | `PROBLEM` / `PLAN`。省略時は両方 |

**レスポンス 200**

```json
{
  "items": [
    {
      "comment_id": 88,
      "parent_comment_id": null,
      "commenter": { "staff_id": 3, "name": "佐藤 次郎" },
      "target_type": "PROBLEM",
      "body": "10%までなら可。明日話そう",
      "created_at": "2026-09-22T19:10:00+09:00",
      "replies": [
        {
          "comment_id": 89,
          "parent_comment_id": 88,
          "commenter": { "staff_id": 12, "name": "山田 太郎" },
          "target_type": "PROBLEM",
          "body": "ありがとうございます。10%で提示します",
          "created_at": "2026-09-22T19:30:00+09:00"
        }
      ]
    }
  ]
}
```

- `items` はトップレベルのコメント（`parent_comment_id` が null）を作成日時の昇順で返す
- 返信は親コメントの `replies` に作成日時の昇順で入れる。返信の要素は `replies` を持たない
- `target_type` で絞り込んだ場合、返信も同じ条件で絞り込まれる（返信は親と同じ target_type のため）

#### C-02 POST /reports/{report_id}/comments

コメント（トップレベル）の投稿と、コメントへの返信を行う。返信は1階層までで、返信への返信はできない。

**実行条件**

| 種類 | 投稿できる人 | ステータス |
| --- | --- | --- |
| コメント（`parent_comment_id` なし） | 対象日報の営業の直属上長 | `SUBMITTED` / `REVIEWED` |
| 返信（`parent_comment_id` あり） | 日報の本人 | 問わない（差し戻し理由への返信のため） |
| 返信（`parent_comment_id` あり） | 対象日報の営業の直属上長 | `SUBMITTED` / `REVIEWED` |

- 営業がトップレベルのコメントを投稿しようとした場合と、管理者が投稿・返信しようとした場合は 403 `FORBIDDEN`
- 閲覧範囲外の日報は 404 `NOT_FOUND`
- ステータスが条件を満たさない場合は 409 `INVALID_STATUS_TRANSITION`

> 差し戻すと日報は DRAFT に戻るため、営業が差し戻し理由に返信しても、上長が返信できるのは再提出後になる。#2 で RETURNED を採用する場合は、上長の返信条件に RETURNED を加える。

**リクエスト**

```json
{ "target_type": "PLAN", "body": "C社は部長同行で行こう。" }
```

```json
{ "parent_comment_id": 88, "body": "ありがとうございます。10%で提示します" }
```

| 項目 | 型 | 必須 | 制約 |
| --- | --- | :-: | --- |
| parent_comment_id | int | - | 返信先のコメントID。同じ日報のトップレベルのコメントであること |
| target_type | string | コメント時○ | `PROBLEM` / `PLAN`。返信時は省略可（返信先の値を使う）。指定した場合は返信先と一致すること |
| body | string | ○ | 1〜1,000文字 |

**入力チェック（422）**
- `parent_comment_id` が存在しない、別の日報のコメント、または返信（`parent_comment_id` が null でない）を指している
- 返信で `target_type` が返信先と異なる

**処理**：コメントを登録し、通知する。

| 種類 | 通知先 |
| --- | --- |
| コメント | 日報の本人 |
| 返信 | 日報の本人と、返信先のコメントの投稿者（投稿した本人は除く） |

**レスポンス 201**：登録したコメント1件（C-01の items の要素と同じ形式。返信の場合は `replies` を持たない）

---

### 4.5 顧客マスタ

#### M-01 GET /customers

**クエリパラメータ**

| パラメータ | 型 | 必須 | 備考 |
| --- | --- | :-: | --- |
| keyword | string | - | 顧客名の部分一致 |
| industry | string | - | |
| assigned_staff_id | int | - | 顧客選択モーダルの「担当顧客のみ」で使用 |
| include_inactive | boolean | - | 初期値 false。true は管理者のみ有効 |
| page, per_page | int | - | 3.2参照 |

**レスポンス 200**

```json
{
  "items": [
    {
      "customer_id": 101,
      "customer_name": "A社",
      "industry": "小売",
      "address": "東京都千代田区…",
      "phone": "03-1234-5678",
      "assigned_staff": { "staff_id": 12, "name": "山田 太郎" },
      "is_active": true
    }
  ],
  "pagination": { "page": 1, "per_page": 20, "total": 134, "total_pages": 7 }
}
```

#### M-02 GET /customers/recent

ログインユーザーの訪問記録から、最近訪問した有効な顧客を重複なしで最大10件返す（最終訪問日の降順）。

```json
{
  "items": [
    { "customer_id": 205, "customer_name": "B社", "last_visited_on": "2026-09-22" }
  ]
}
```

#### M-03 GET /customers/{customer_id}

M-01の要素に `created_at`、`updated_at` を加えた形式。

#### M-04 POST /customers

**リクエスト**

```json
{
  "customer_name": "D社",
  "industry": "金融",
  "address": "東京都中央区…",
  "phone": "03-9876-5432",
  "assigned_staff_id": 12
}
```

| 項目 | 型 | 必須 | 制約 |
| --- | --- | :-: | --- |
| customer_name | string | ○ | 1〜100文字 |
| industry | string | - | 業種の選択肢は未決 |
| address | string | - | 200文字以内 |
| phone | string | - | 半角数字とハイフン、20文字以内 |
| assigned_staff_id | int | - | 有効な営業であること |

**レスポンス 201**：M-03と同じ形式。同名の有効顧客が存在する場合は、登録したうえでレスポンスに `warnings: ["同名の顧客が既に登録されています"]` を含める。

#### M-05 PUT /customers/{customer_id}

M-04の項目に `is_active`（boolean、必須）と `updated_at`（必須）を加える。無効化しても過去の訪問記録は保持し、R-03では顧客名を表示し続ける。

**レスポンス 200**：M-03と同じ形式

---

### 4.6 営業マスタ

#### S-01 GET /staff

**クエリパラメータ**

| パラメータ | 型 | 必須 | 備考 |
| --- | --- | :-: | --- |
| keyword | string | - | 氏名の部分一致 |
| department | string | - | |
| role | string | - | `SALES` / `MANAGER` / `ADMIN` |
| manager_id | int | - | 上長の部下一覧（日報検索の営業プルダウン用） |
| include_inactive | boolean | - | 初期値 false。true は管理者のみ有効 |

**返却範囲**：営業＝自分のみ、上長＝自分＋直属部下、管理者＝全件。

**レスポンス 200**

```json
{
  "items": [
    {
      "staff_id": 12,
      "name": "山田 太郎",
      "email": "yamada@example.com",
      "department": "第一営業部",
      "position": "主任",
      "manager": { "staff_id": 3, "name": "佐藤 次郎" },
      "role": "SALES",
      "is_active": true
    }
  ],
  "pagination": { "page": 1, "per_page": 20, "total": 42, "total_pages": 3 }
}
```

#### S-02 GET /staff/{staff_id}

S-01の要素に `created_at`、`updated_at` を加えた形式。パスワードは返さない。

#### S-03 POST /staff

**リクエスト**

```json
{
  "name": "鈴木 花子",
  "email": "suzuki@example.com",
  "department": "第一営業部",
  "position": "担当",
  "manager_id": 3,
  "role": "SALES",
  "initial_password": "********"
}
```

| 項目 | 型 | 必須 | 制約 |
| --- | --- | :-: | --- |
| name | string | ○ | 1〜50文字 |
| email | string | ○ | メール形式、254文字以内、重複不可 |
| department | string | ○ | 1〜50文字 |
| position | string | - | 50文字以内 |
| manager_id | int | - | 有効な社員であること |
| role | string | ○ | `SALES` / `MANAGER` / `ADMIN` |
| initial_password | string | ○ | 8〜64文字。ハッシュ化して保存 |

**エラー**：409 `DUPLICATE_EMAIL`

**レスポンス 201**：S-02と同じ形式

#### S-04 PUT /staff/{staff_id}

S-03の項目（`initial_password` を除く）に `is_active`（必須）と `updated_at`（必須）を加える。

**追加チェック（422）**
- `manager_id` に自分自身は指定不可
- 上長関係の循環（AがBの上長、BがAの上長など）は不可

**処理**：無効化した社員のトークンは即時失効させる。直属部下がいる社員を無効化した場合は、登録したうえで `warnings` に部下の件数を返す。

**レスポンス 200**：S-02と同じ形式

---

## 5. 権限チェックまとめ

| 対象 | 営業 | 上長 | 管理者 |
| --- | --- | --- | --- |
| 日報の閲覧 | 自分 | 自分＋直属部下 | 全件 |
| 日報の作成・編集・提出 | 自分（DRAFTのみ） | 自分（DRAFTのみ） | 不可 |
| コメント投稿 | 不可 | 直属部下の提出済・確認済日報 | 不可 |
| コメントへの返信 | 自分の日報 | 自分の日報、直属部下の提出済・確認済日報 | 不可 |
| 確認・差し戻し | 不可 | 直属部下の提出済日報 | 不可 |
| 顧客マスタ | 閲覧 | 閲覧 | 登録・更新 |
| 営業マスタ | 自分のみ閲覧 | 自分＋部下を閲覧 | 登録・更新 |

上長も営業活動を行う前提で、自分の日報を作成できるものとした。管理者による日報の代理編集は設けない。

---

## 6. 未決事項（API関連）

- [ ] 差し戻しを独立ステータス（RETURNED）にするか → R-07とステータス値域に影響
- [x] ~~営業のコメント返信を許可するか~~ → 本人と直属上長が返信可、1階層まで（#1）。C-01、C-02、R-03、D-01 に反映済み
- [ ] 上長・管理者に他人の下書きを返すか → R-01、R-03の閲覧範囲
- [ ] 訪問0件での提出を許可するか → R-05の提出時チェック
- [ ] 管理者に日報の閲覧だけでなくコメント権限を与えるか
- [ ] 通知手段（メール／チャット）と、通知を同期・非同期どちらで行うか
- [ ] 業種の選択肢をマスタ化するか（その場合 `GET /industries` を追加）
