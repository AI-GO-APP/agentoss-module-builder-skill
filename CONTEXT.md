# CONTEXT — 術語表

本檔是**術語消歧義表**，不是規格書。實作細節在 `references/` 底下。

---

## 四種憑證／token，別混用（混了必出錯）

| 名稱 | 長相 | 誰持有 | 用在哪 |
|---|---|---|---|
| **開發者 PAT**（developer API key / Agent key） | `dev_sk_...` | 開發者本人 | 呼叫 `/api/agent/apps/*` 管理自己所有的 App。從 `<站點>/developer/api-keys` 建立，**跨站點共用** |
| **App API key** | UUID | 單一 App | 該 App 的 Cloud Run 服務回呼 `/api/developer/callback/:runId` 時的 Bearer；create／rotate 當下只出現一次 |
| **mission_token** | 簽章字串 | 單次任務 | 任務 payload 內附，呼叫 `credit_api.*`（balance／charge／refund／files 上傳）的 Bearer |
| **callback token** | `callback_url` 的 `?token=` query | 單次任務 | 回呼認證的首選方式——**正式任務內含於網址**；Agent API test-runs 目前沒帶，改給 `callback_auth`（見 `references/platform-behaviors.md` §1） |

常見錯置：

- 拿 **App API key** 當 PAT 打 Agent API → 401。
- 拿 **PAT** 給 main.py 回呼 → 403。回呼只認 callback token 或 App API key。
- **mission_token** 只對該次任務的 credit API 有效，過了任務就失效。

## 站點綁定詞彙

| 詞 | 意義 |
|---|---|
| **site（站點）** | 一個對外市集／品牌（`99agent`、`irich`…）。App 建立後屬於固定站點，搬不了 |
| **baseUrl** | 該站點的 API 網域。**App 落點由呼叫哪個網域決定**——PAT 跨站共用擋不住放錯站，所以 skill 用 `.agentoss/config.json` 綁死 |
| **`.agentoss/config.json`** | 專案級站點綁定檔（site + baseUrl）。無此檔一律先跑 `agentoss.sh init` |
| **`.agentoss/credentials`** | PAT 存放檔（gitignored）；優先序：環境變數 `AGENTOSS_API_KEY` > 此檔 |

## App 生命週期詞彙

| 詞 | 意義 |
|---|---|
| **draft / pending / published / unlisted / archived** | App 狀態機。Agent API 可編輯非 published App 並送審（包含 published 原 ID → pending）；核准為 published／rejected／下架只能走管理員後台。重新送審非獨立候選版本，見 references/update-existing-app.md |
| **webhookUrl** | App 的正式 Cloud Run 服務網址。**唯讀**——只有正式部署的 deployer 會寫入 |
| **preview / production 部署** | 同一份 code 草稿的兩個部署目標；preview 是隔離的 `-preview` 服務，不動 webhookUrl |
| **test-run** | 開發者對自己 App 發的真實任務（`is_test`），不做上架／使用權檢查，扣**開發者自己**的點數 |
| **run（mission）** | 一次任務執行。`mission_id` = run id |
