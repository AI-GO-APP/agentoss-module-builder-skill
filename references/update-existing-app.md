# 更新已上架 App：保留 App ID

適用：使用者要求修提示詞、修模組或更新既有 App，且已授權更新／發布。這是 DeveloperApp 作業，不授權修改或部署主系統。

## 先區分三件事

- App 的 `version`：可修改的版本標籤，不是版本樹。
- deployment：同一 App 的後端程式快照與 Cloud Run 部署紀錄。
- `POST /versions`：複製出另一個 App ID，不會自動替換舊 App、承接會員權益或建立父子版本連結。只有需要獨立 App 才使用。

## 同一 App 的操作順序

所有 Agent API 呼叫沿用 `.agentoss/config.json` 的站點與開發者 PAT，不切站、不換 App ID。

1. GET App、`/code`、`/fields`、`/secrets` 名稱、`/deployments` 與必要的執行紀錄。私下保存原設定、版本、code/packages、計費與正式部署 ID；不要輸出秘密或客戶素材。
2. 備妥修改內容與管理員核准管道後，POST `/api/agent/apps/:appId/submit-review`，通常送 `{}`。GET 同一 ID，確認 `pending`。這個端點會改整個 App 的狀態，可能暫時影響市集可見性與一般使用者執行；不是舊版持續上架的候選版本功能。
3. PATCH 同一 App 的版本（例如 `1.0.1`），PUT `/code` 更新程式。保留額外套件及非本次範圍設定；GET 讀回比對。
4. POST `/deployments/preview`，poll 至 `deployed`，驗證實際模組輸出。`is_test` 煙霧結果或 HTTP 200 僅代表連線成功，不能當影片／音檔生成驗收。
5. POST `/deployments`，poll 至 `deployed`，核對新部署 ID、程式快照與正式服務。正式部署成功就會改變 live backend，不是等待上架核准才切流量。
6. 由具權限管理員透過後台核准。對應端點是 `POST /api/admin/developer-apps/:appId/review`、`{"action":"approve"}`，需要既有合法管理員 session；developer PAT 不具這項權限。使用者已明確授權發布時，不要重複索取一般確認，但也不可假造 session 或直接改 DB 上架。
7. GET 確認同一 App ID、預期 version、`published`、最新 production 部署為 `deployed`；比較計費、欄位、權益分類及其他非預期設定。分別回報「部署發布完成」與「實際生成驗收」的結果，不混用。

## 已知限制與失敗處理

- 2026-10-30 於 99agent 實際完成同 ID 重新送審／部署／核准；仍要以各站回應與讀回確認，不能假設各站 API 都一致。
- submit-review 會接受歷史 production deployment / completed run；這不是新版本測試證據。`notes` 目前被忽略；`exampleRunId` 會改公開範例，沒要更換時不要帶。
- 部署紀錄曾固定標記 `1.0.0`。舊紀錄請以部署 ID、程式快照／hash 與實際服務核實；不要為了讓標籤相同去改歷史 DB。版本快照修正尚待平台 PR 合併與各站部署，不要假設已生效。
- 這是單一可變 App，不是原子發布／完整版本回滾系統。失敗先讀回目前狀態，保留舊部署；若需回復，還原備份的 code/version，已改正式 backend 則重新部署原快照，再由管理員核准。若缺管理員權限，精確交付審核網址與當前狀態，不宣稱已發布。
- 不以 clone、直接 SQL 改 status/webhook、擷取瀏覽器憑證或擴大權限來繞過失敗。
