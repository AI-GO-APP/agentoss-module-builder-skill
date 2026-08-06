---
name: agentoss-module-builder
description: >-
  開發、測試、部署與送審 Agent OSS 平台站點（99agent、iRich…）的 Developer App（平台模組）。
  以開發者 PAT（dev_sk_ Agent key）呼叫 Agent API，涵蓋：建立 App、表單欄位、Rich UI、
  main.py 程式碼與 Cloud Run 部署、環境變數 secrets、定價設定、測試任務、送審上架。
  當使用者要開發／修改／測試／上架平台模組（DeveloperApp）時使用。
---

# Agent OSS Module Builder

協助模組開發者在自己的 IDE（Claude Code / Codex）裡，透過平台 Agent API 完成
Developer App 的完整開發流程：建立 → 設定欄位或 Rich UI → 定價 → 寫 main.py →
secrets → 部署 Cloud Run → 測試任務 → 送審。

## 0. 站點綁定（最重要的規則）

**PAT（開發者 Agent key）與開發者權限是跨站點共用的**：同一把 `dev_sk_` key 在
99agent 與 iRich 都能通過驗證。**App 落在哪個站點，由「你呼叫哪個網域」決定**——
呼叫錯網域，App 就會出現在錯的站點市集，而且事後搬不了。

因此本 skill 強制「先綁站點、再動 API」：

1. 專案根目錄必須有 `.agentoss/config.json`（由 `scripts/agentoss.sh init` 建立）：

   ```json
   { "site": "99agent", "baseUrl": "https://all.99agent.app" }
   ```

2. **每一次 API 呼叫都必須使用 config 裡的 `baseUrl`**。沒有 config → 先問使用者
   要開發哪個站點，跑 `init`，再繼續。
3. **絕不静默切換站點**。使用者明確要求換站點時，才重跑 `init` 覆寫 config，
   並提醒：既有 App 留在原站點，不會跟著搬。
4. 已知站點對照表（`init` 內建）：

   | site code | baseUrl | 備註 |
   |---|---|---|
   | `99agent` | `https://all.99agent.app` | 99agent 主站 |
   | `irich` | `https://www.irich.cc` | iRich（財經站；App 會落在 finance 站點範疇） |

   其他／未來站點：使用者提供該站正式網域，`init <code> <baseUrl>` 綁定。
5. **禁止把 `agentoss.ai`（管理中台）當開發目標**——在那裡建立的 App 會誤落
   99agent 站點。`agentoss.sh` 會直接擋下這個 host。

## 1. 憑證（PAT / Agent key）

- 開發者在目標站點登入後，到 `<baseUrl>/developer/api-keys` 建立
  **開發者層級 API Key**（`dev_sk_` 開頭，scope `agent:apps:write`）。
- Key 的提供方式（擇一，優先序由上而下）：
  1. 環境變數 `AGENTOSS_API_KEY`（web IDE 環境建議在專案的 secrets 設定裡配置）
  2. `.agentoss/credentials` 檔（單行，`init` 會自動把它 gitignore）
- **絕不**把 key 寫進程式碼、config.json、commit 或任何會進版控的檔案。
- 這是「開發者 key」；每個 App 另有一把「App API key」（Cloud Run 服務回呼
  callback 用），兩者不要混用。

## 2. 快速開始

```bash
# 1) 綁定站點（第一次、或使用者明說要換站點時）
bash scripts/agentoss.sh init 99agent

# 2) 驗證 key 與連線（列出自己名下的 App）
bash scripts/agentoss.sh api GET /api/agent/apps

# 3) 建立草稿 App
echo '{"name":"我的模組","description":"...","category":"general","uiMode":"form"}' > /tmp/app.json
bash scripts/agentoss.sh api POST /api/agent/apps /tmp/app.json
```

`agentoss.sh api <METHOD> <path> [bodyfile]` 是萬用呼叫器：自動帶
`Authorization` / `Content-Type` / `Idempotency-Key`，並強制走綁定站點的 baseUrl。
完整端點契約見 [references/api-reference.md](references/api-reference.md)。

## 3. 開發生命週期（標準流程）

按順序執行；每一步完成後**用 GET 讀回驗證**，不要只看寫入回應就宣告完成。

| 步驟 | 端點 | 說明 |
|---|---|---|
| 1. 建立 App | `POST /api/agent/apps` | 拿到 `appId`，狀態 `draft`。把 appId 記進 `.agentoss/config.json` 的 `apps` 清單 |
| 2a. 表單欄位（form 模式） | `PUT /api/agent/apps/:appId/fields` | `replace` / `merge` 兩種模式；欄位型別 text / textarea / file / select / api_key |
| 2b. Rich UI（rich_ui 模式） | `PUT /api/agent/apps/:appId/rich-ui` | 上傳完整 HTML（≤2MB）；平台自動注入 runtime。見 [references/rich-ui.md](references/rich-ui.md) |
| 3. 定價 | `PATCH /api/agent/apps/:appId` | `creditsBase`、`billing.*`、`estimatedMonthly` / `estimatedBuyout`。見 [references/billing.md](references/billing.md) |
| 4. 寫程式 | `PUT /api/agent/apps/:appId/code` | 單檔 Python FastAPI `main.py` + `extraPackages`。契約見 [references/mission-and-callback.md](references/mission-and-callback.md)，起手式用 [templates/main.py](templates/main.py) |
| 5. Secrets | `PUT /api/agent/apps/:appId/secrets` | API 金鑰一律走 env（write-only），絕不寫死在 main.py |
| 6. 預覽部署 | `POST /api/agent/apps/:appId/deployments/preview` | 部署到隔離 `-preview` 服務，不動正式環境 |
| 7. 等部署完成 | `bash scripts/agentoss.sh wait-deploy <appId> <deploymentId>` | async（202）；poll 到 `deployed` / `failed`。失敗看回傳的 `buildLogTail` |
| 8. 測試任務 | `POST /api/agent/apps/:appId/test-runs`（`"target":"preview"`） | 發真實任務打 preview 服務；`wait-run` poll 結果 |
| 9. 正式部署 | `POST /api/agent/apps/:appId/deployments` | 成功後平台把 Cloud Run serviceUrl 寫入 `webhookUrl`（唯一寫入途徑） |
| 10. 正式測試 | `POST .../test-runs`（`"target":"production"`） | 至少一次 completed run 才能過送審門檻 |
| 11. 封面圖 | `POST /api/agent/apps/:appId/cover`（multipart） | `cover_sm/md/lg` JPG ≤5MB，缺的變體平台自動補 |
| 12. 送審 | `POST /api/agent/apps/:appId/submit-review` | 硬門檻不足時回 409 + `details.missing[]`，逐項補齊再送 |

改「已上架（published）」的 App：不能直接編輯，先
`POST /api/agent/apps/:appId/versions` clone 出新草稿再走上表流程。

## 4. 硬規則（違反 = 平台直接拒絕）

- **不能自行上架**：`status` 不接受 `published` / `rejected`；送審走
  `submit-review`，公開上架只有管理員後台審核一條路。
- **`webhookUrl` 唯讀**：由正式部署自動寫入 Cloud Run serviceUrl，任何寫入
  嘗試回 400。要改後端 = 改 code 重新部署。
- **published App 禁止直接改**：code / 正式部署 / metadata 都回 409，先 clone version。
- **secrets write-only**：任何 API 都不回明文；改完要重新部署才生效。
- **App API key 明文只在 create / rotate 當下出現一次**，要即刻交給使用者保存。
- 金鑰一律 env 讀取（`os.environ`），寫死在 main.py 的程式碼不要產出。

## 5. 驗證要求（回報完成前必做）

- 每個寫入操作後用對應 GET 讀回，確認欄位真的變了。
- 部署必須 poll 到 `deployed`；`failed` 就讀 `buildLogTail` 修到過。
- 「開發完成」的定義：**至少一次 test-run 跑到 `completed` 且 output 內容正確**。
  只有 tsc / 語法通過不算完成。
- 送審前把 submit-review 的門檻自查一遍（name / description / category / version /
  fields 或 richUi / production deployment / completed run）。

## 6. Reference 索引

| 檔案 | 內容 |
|---|---|
| [references/api-reference.md](references/api-reference.md) | 全部 Agent API 端點、request/response、錯誤碼 |
| [references/mission-and-callback.md](references/mission-and-callback.md) | main.py 收到的任務 payload、回應方式、callback 格式、credit API、檔案上傳、取消 |
| [references/rich-ui.md](references/rich-ui.md) | Rich UI 開發：runtime（`$99agent`）、requestMission、沙箱限制 |
| [references/billing.md](references/billing.md) | 定價與計費模式完整說明 |
| [templates/main.py](templates/main.py) | main.py 起手模板（FastAPI + callback + 取消處理） |
| [templates/rich-ui.html](templates/rich-ui.html) | Rich UI 起手模板 |
