# Agent API 端點參考

> 所有路徑都相對於 `.agentoss/config.json` 的 `baseUrl`（下稱 `{BASE}`）。
> 本文件描述 `/api/agent/*`（開發者 PAT 驗證的 Agent API），與瀏覽器用的
> `/api/developer/*` 是同一套資料、不同驗證方式。

## 共通 Headers

```txt
Authorization: Bearer dev_sk_<developer-api-key>
Content-Type: application/json
Idempotency-Key: <mutating 請求帶穩定 key，重試不會重複建立>
```

## 回應信封

成功：`{ "ok": true, "requestId": "req_...", "data": { ... } }`
失敗：`{ "ok": false, "requestId": "req_...", "error": { "code", "message", "details" } }`

| code | HTTP | 意義 |
|---|---:|---|
| `unauthorized` | 401 | token 缺少或無效 |
| `forbidden_scope` | 403 | key 缺 scope，或嘗試被禁止的操作（如自行上架） |
| `not_found` | 404 | App / run 不存在，或不屬於這把 key 的擁有者 |
| `validation_failed` | 400 | body 不合法（含嘗試寫唯讀欄位 `webhookUrl`） |
| `conflict` | 409 | 直接編輯 published App、重複 key、狀態不符、送審門檻不足 |
| `external_webhook_failed` | 502 | 下游服務（如 Rich UI 上傳）失敗 |

---

## App 生命週期

### 列出自己的 App

```txt
GET {BASE}/api/agent/apps
```

回傳這把 key 擁有者名下的 App（含各站點；owner-scoped，不做站點過濾——
這正是要靠站點綁定避免放錯站的原因）。

### 建立 App

```txt
POST {BASE}/api/agent/apps
```

```json
{
  "name": "AI 發票憑證分類器",
  "description": "上傳憑證後回傳分類與缺漏提醒。",
  "category": "accounting",
  "uiMode": "form",
  "version": "0.1.0"
}
```

- 狀態從 `draft` 開始；`webhookUrl` 為空，正式部署後由平台寫入。
- 回傳含 `webhook.callbackUrlTemplate`（`{BASE}/api/developer/callback/{runId}`）。
- `uiMode`：`form`（平台表單）或 `rich_ui`（自訂 HTML）。

### 讀取 App

```txt
GET {BASE}/api/agent/apps/:appId
```

回傳 metadata、`webhookUrl`（部署狀態）、fields、richUi、billing、links
（`editUrl` 開發者主控台 / `previewUrl` 前台預覽）。

### 更新 App metadata

```txt
PATCH {BASE}/api/agent/apps/:appId
```

可帶：`name`、`description`、`tutorial`、`category`、`version`、`uiMode`、
`creditsBase`、`estimatedMonthly`、`estimatedBuyout`、`billing.*`（見 billing.md）、
`status`。

限制：

- `status` 只接受 `draft` / `archived`。`published` / `rejected` 回 403；
  `pending` 系列請走 submit-review。已上架／已下架的 App 不能自行改回 draft。
- `webhookUrl` 唯讀，帶了直接 400。
- published App 禁止直接編輯（409）→ 先 Clone Version。

### Clone Version（改 published App 的唯一途徑）

```txt
POST {BASE}/api/agent/apps/:appId/versions
```

```json
{ "version": "0.2.0", "copyFields": true, "copyRichUi": true, "notes": "..." }
```

複製成新的 `draft`；新草稿 `webhookUrl` 一律為空（部署後拿到自己的服務網址）。

---

## 表單欄位（form 模式）

```txt
PUT {BASE}/api/agent/apps/:appId/fields
```

```json
{
  "mode": "replace",
  "fields": [
    {
      "name": "receipt_files",
      "label": "上傳憑證",
      "description": "支援 jpg、png、pdf",
      "fieldType": "file",
      "accept": ".jpg,.jpeg,.png,.pdf",
      "required": true,
      "maxFiles": 10,
      "sortOrder": 0
    },
    { "name": "company_tax_id", "label": "公司統編", "fieldType": "text", "sortOrder": 1 }
  ]
}
```

- `mode`：`replace`（預設，整組替換）或 `merge`（依 `name` upsert，未提及的保留；
  merge 沒帶 `sortOrder` 時更新沿用原排序、新增排最後）。
- `name` 必須符合 `^[a-z][a-z0-9_]{1,63}$`，同組不得重複。
- `fieldType`：`text` / `textarea` / `file` / `select` / `api_key`。
  - `file`：可設 `accept`（副檔名或 MIME 逗號清單）、`maxFiles`、`maxDurationSeconds`。
  - `select`：必須有 `options`，每項 `{ "label", "value" }`（或純字串）。
    可加 `previewUrl` 提供試聽／預覽（必須匿名可讀：公開 bucket 或
    `visibility=public` 的 `/api/media/<guid>`；私有 bucket 直連會 403）。
  - `api_key`：執行時使用者可選「自帶金鑰」或「用平台點數」。
- 回應 `diff`：`created` / `updated` / `deleted`（merge 模式 deleted 恆為空）。

---

## Rich UI

```txt
PUT {BASE}/api/agent/apps/:appId/rich-ui
```

```json
{ "html": "<!doctype html>...", "sourceName": "workbench.html" }
```

- HTML ≤ 2MB；平台會剝掉舊 runtime、注入現行 runtime、存原始碼、掛上 hosted URL，
  並把 `uiMode` 設為 `rich_ui`。
- 開發細節（`window.$99agent` runtime、任務流程）見 rich-ui.md。

---

## 程式碼（main.py）

```txt
GET {BASE}/api/agent/apps/:appId/code
PUT {BASE}/api/agent/apps/:appId/code
```

```json
{ "codeContent": "from fastapi import FastAPI\n...", "extraPackages": "requests\npillow==10.0.0" }
```

- 存的是**草稿**，不會自動部署；要生效需呼叫 deployments。
- **Partial update**：沒帶的欄位保留原值；要清空明確傳 `""`；兩個都沒帶回 400。
- `extraPackages` 一行一個 pip 套件（禁 shell 特殊字元）；`codeContent` ≤ 1MB。
- published App 拒絕編輯（409）→ 先 Clone Version。

---

## 部署（Cloud Run）

```txt
POST   {BASE}/api/agent/apps/:appId/deployments            正式部署
POST   {BASE}/api/agent/apps/:appId/deployments/preview    預覽部署（隔離 -preview 服務）
GET    {BASE}/api/agent/apps/:appId/deployments?limit=20   列出部署
GET    {BASE}/api/agent/apps/:appId/deployments/:deploymentId   單筆狀態（poll 用）
```

- async：回 `202` + `status:"deploying"`；用 GET poll 到 `deployed` / `failed`
  （通常數分鐘；`scripts/agentoss.sh wait-deploy` 已包好）。
- 正式部署成功 → 平台把 Cloud Run `serviceUrl` 寫入 `webhookUrl`。
- 預覽部署不動正式 `webhookUrl`，任何狀態都允許；正式部署對 published App 回 409。
- 同一 environment 同時只允許一個進行中的部署（409 附 `details.activeDeployment`）。
- 還沒存過 code 回 400（先 PUT `/code`）。
- 回傳含 `buildLogTail`（build log 尾段 4000 字）——build 失敗先看這裡。

---

## Secrets（部署環境變數）

```txt
GET    {BASE}/api/agent/apps/:appId/secrets                 列出 env 名稱（永不回值）
PUT    {BASE}/api/agent/apps/:appId/secrets                 { "envName": "OPENAI_API_KEY", "value": "..." }
DELETE {BASE}/api/agent/apps/:appId/secrets?envName=FOO
```

- 值 write-only、加密儲存，下次部署注入為 Cloud Run env var。
- `envName` 必須 `^[A-Z][A-Z0-9_]*$`。**改完要重新部署才生效。**

---

## 測試

### 發測試任務（打已部署服務）

```txt
POST {BASE}/api/agent/apps/:appId/test-runs
```

```json
{
  "input": { "receipt_files": ["https://.../invoice-1.png"] },
  "target": "preview",
  "waitForCallbackSeconds": 60
}
```

- `target`：`production`（預設，打正式 `webhookUrl`）或 `preview`（打最近一次
  成功的 `-preview` 服務）。
- payload 與正式任務完全相同（`mission_token` / `credit_api` / `billing`），
  metered billing 也能完整測；測試扣的是**開發者自己的點數**。
- 最多等 60 秒；更長任務用 List Runs poll（`wait-run` 已包好）。

### 模擬 callback（不需要已部署的服務）

```txt
POST {BASE}/api/agent/apps/:appId/callback-simulations
```

```json
{ "runId": "run-id", "payload": { "status": "processing", "progress": 33, "output": {} } }
```

語意與真實 callback 相同——在 main.py 還沒寫之前就能先驗 output 形狀。

### List Runs

```txt
GET {BASE}/api/agent/apps/:appId/runs?limit=20
```

回傳近期 runs：status / progress / duration / input・output 預覽 / callback 次數。

---

## 其他

### 封面圖

```txt
POST {BASE}/api/agent/apps/:appId/cover      （multipart/form-data）
```

欄位 `cover_sm` / `cover_md` / `cover_lg`（JPG，各 ≤5MB）。至少一個；缺的變體
平台以最大者自動補齊。重新 POST 即覆蓋。用 curl：

```bash
bash scripts/agentoss.sh curl -X POST "{BASE}/api/agent/apps/$APP_ID/cover" \
  -F cover_lg=@cover.jpg
```

### 旋轉 App API Key

```txt
POST {BASE}/api/agent/apps/:appId/apikey/rotate
```

新 key 只回傳這一次，之後拿不到明文。

### 送審

```txt
POST {BASE}/api/agent/apps/:appId/submit-review
```

```json
{ "notes": "Test run <run-id> completed.", "exampleRunId": "run-id" }
```

硬門檻（缺項回 409 + `details.missing[]`）：

- App 是 `draft`，且 name / description / category / version 齊全
- form App 有 fields；rich_ui App 有 HTML
- 有 `production` 環境、`deployed` 狀態的部署（`productionDeployment`）
- 至少一次 completed run，或帶 `exampleRunId` / `overrideReason`

送審後狀態 `pending`，等管理員審核。**API 無法直接把 App 變 published。**

### Console 限定（Agent API 刻意不開放）

- 協作者管理（帳號授權屬人為決策）
- App API key 明文讀取（只在 create / rotate 當下出現一次）
