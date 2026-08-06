# 任務契約：main.py 收到什麼、怎麼回

模組後端是**單一檔案 Python FastAPI `main.py`**，由平台建置並部署到 Cloud Run。
起手模板：[templates/main.py](../templates/main.py)。

## 1. 平台如何呼叫你（POST /）

平台對服務**根路徑 `POST /`** 送一包 JSON：

```json
{
  "mission_id": "<runId>",
  "app_id": "<appId>",
  "callback_url": "https://<site>/api/developer/callback/<runId>?token=...",
  "credits_per_run": 20,
  "credits_base": 20,
  "billing": { "...": "計費資訊，一般模組可忽略" },
  "mission_token": "<signed token，呼叫 credit_api 用>",
  "credit_api": {
    "balance_url":  ".../api/developer/missions/<runId>/credits",
    "charge_url":   ".../api/developer/missions/<runId>/credits/charge",
    "refund_url":   ".../api/developer/missions/<runId>/credits/refund",
    "files_url":    ".../api/developer/missions/<runId>/files"
  },

  "receipt_files": ["https://...png"],
  "company_tax_id": "12345678"
}
```

重點：

- **使用者輸入欄位直接攤平在 body 最上層**（key = 欄位 `name`）。
  - `file` 欄位一律是 **URL 字串陣列**（即使 maxFiles=1）。
  - `select` 欄位送的是 option 的 `value`。
  - `api_key` 欄位會多一個 `<name>_mode` key：`user_api_key`（使用者自帶，
    `<name>` 是明文金鑰，直接用）或 `platform_credits`（`<name>` 為空字串，
    改用你在 secrets 設定的平台金鑰）。
- `callback_url` **內含 token**，回呼時直接 POST 那個網址，
  **不需要也不要再加任何 Authorization header**。
- 平台 POST timeout 30 秒、回非 2xx 會直接判任務失敗並退點——所以：

**收到後立刻回 `{"accepted": true}`（HTTP 200），用 BackgroundTasks 背景處理。**

## 2. 取消訊號（同一個 POST / 端點）

使用者取消任務時，平台對同一端點送（best-effort，10 秒 timeout）：

```json
{ "mission_id": "<runId>", "app_id": "<appId>", "action": "cancel", "status": "cancel", "mission_token": "..." }
```

main.py 要先檢查 `body.get("action") == "cancel"`，是的話停掉對應任務。
任務一旦 `cancelled`，**之後所有 callback 都會被忽略**（回 200 no-op），
遲到的 done/failed 不會被採用。

## 3. Callback（回報進度與結果）

對收到的 `callback_url` POST JSON：

### 進度（可多次）

```json
{ "mission_id": "<runId>", "app_id": "<appId>", "status": 33, "message": "處理中..." }
```

`status`：`1–99`（或 `"processing"`）= 進度；`100` 或 `"done"` = 完成；
`"failed"` / `"fail"` = 失敗；`"cancel"` / `"cancelled"` = 模組主動中止（平台退點）。

### 完成（檔案類輸出）

```json
{
  "mission_id": "<runId>",
  "app_id": "<appId>",
  "status": 100,
  "result": {
    "files": [ { "type": "image", "label": "圖片1", "url": "https://<AI服務原始網址>" } ]
  }
}
```

- `type`：`image` 或 `video`。
- `url` 給外部服務的原始網址即可，**平台自動轉存**到自己的儲存空間。

### 完成（結構化輸出）

```json
{ "status": "done", "progress": 100, "output": { "summary": "已完成分析", "items": [] } }
```

### 失敗

```json
{ "status": "failed", "message": "外部服務逾時", "retryable": true }
```

**任何失敗都要 callback failed，不要讓任務卡住。**
注意：任務 `failed` 平台**不會**自動退點，退點要模組自己呼叫 `refund_url`（見下）。

## 4. Credit API（metered 計費 / 退點 / 檔案上傳）

以 `Authorization: Bearer <mission_token>` 呼叫 `credit_api` 內的網址：

- `balance_url`（GET）：查使用者剩餘點數。
- `charge_url`（POST）：執行中加扣點（developer_managed / metered 模式用）。
- `refund_url`（POST）：退點。
  ```json
  { "amount": 3, "idempotency_key": "mission:<runId>:partial-refund", "reason": "partial_delivery_refund" }
  ```
  - `amount` 省略 = 全額退；帶數字 = 部分退（如 quantity 計費少交付）。
  - 上限 = 該任務實際扣款，永遠不會退超過；未扣點任務是 no-op。
  - **務必帶固定 `idempotency_key`**，重試不重複退。
  - 平台只在 cancel 路徑自動退點；`failed` 與部分交付的退點是模組責任。
- `files_url`（POST multipart）：模組產出「本機檔案」（無外部 URL）時上傳：
  ```txt
  欄位：file（必填，≤20MB）、filename（選填）
  → { "ok": true, "url": "/api/media/<guid>" }
  ```
  回傳的 `/api/media/<guid>` 直接放進 callback 的 `files[].url`。
  只在任務 pending 期間可上傳；有外部 URL 就不需要這支（平台會自動轉存）。

## 5. 必守規則（build / 部署層）

- 單檔 `main.py`，FastAPI + uvicorn，監聽環境變數 `PORT`（預設 8080）。
- 預設可用套件：`fastapi`、`uvicorn`、`requests`、`pydantic`、`httpx`；
  其他套件寫進 `extraPackages`（一行一個）。
- **金鑰一律 `os.environ` 讀取**，用 Secrets API 設定；絕不寫死。
- 加 `GET /health` 回 `{"ok": true}`。
