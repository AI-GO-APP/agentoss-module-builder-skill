# 錯誤速查

> 出錯時**先查本表對症狀**，不要自行推測修法。多數症狀有明確成因，
> 猜測通常會改錯地方——尤其是「設定問題」被當成「程式問題」一直改 code。

## 設定問題 vs 程式問題（★ 先分流）

以下症狀**改程式碼一輩子都不會好**，要去改設定：

| 症狀 | 真正原因 | 動作 |
|---|---|---|
| 模組讀不到 `os.environ["X"]` | secret 沒設，或設了但**還沒重新部署** | `PUT /secrets` 後**必須重新部署**才注入 |
| test-run 回 `no deployed preview service` | 還沒 preview 部署 | 先 `POST /deployments/preview` |
| test-run 回 `no production deployment` | 還沒正式部署（`webhookUrl` 空） | 先 `POST /deployments` |
| submit-review 409 `missing: [productionDeployment]` | 只做過 preview | 正式部署一次 |
| API 一律 401 | PAT 無效／已撤銷，或拿錯 token（見 `CONTEXT.md`） | 到 `<站點>/developer/api-keys` 重新建立 |
| 建好的 App 出現在錯的站點 | 呼叫了錯的 baseUrl | **無法搬站**，只能在正確站點重建。動 API 前先 `agentoss.sh site` 確認 |

## HTTP 狀態碼語義

| 碼 | 意義 | 常見情境 |
|---|---:|---|
| **400** `validation_failed` | 輸入不合法 | 寫 `webhookUrl`（唯讀）、欄位 `name` 不符 `^[a-z][a-z0-9_]{1,63}$`、`select` 缺 options、`envName` 不符 `^[A-Z][A-Z0-9_]*$`、code 未儲存就部署 |
| **401** `unauthorized` | token 缺或無效 | PAT 錯／已撤銷 |
| **403** `forbidden_scope` | 明令禁止的操作 | 自行改 `status: published`／`rejected`；把已上架 App 改回 draft |
| **404** `not_found` | App 不存在**或不屬於這把 key** | 跨帳號存取會偽裝成 404（刻意設計，不洩漏存在性） |
| **409** `conflict` | 狀態衝突 | 編輯 published App（先 clone version）；同 env 併發部署；撤回已部署紀錄；送審門檻不足 |
| **413** | Rich UI HTML 超過 2MB | 拆資產／壓縮 |
| **502** `external_webhook_failed` | 下游失敗 | Rich UI 上傳到 GCS 失敗；test-run 打不到模組端點 |

## 部署失敗

1. `GET /deployments/:id` 讀 **`buildLogTail`**（build log 尾段 4000 字，錯誤都在最後）。
2. 常見成因：`extraPackages` 套件名錯／版本不存在、`main.py` 語法錯、
   import 了沒宣告的套件。
3. `errorMessage` 有值時優先看它。
4. 完整 log 走開發者主控台部署頁（`links.editUrl`）。

## 任務跑不出結果

| 症狀 | 檢查順序 |
|---|---|
| test-run `completed` 但 output 是「is_test 煙霧測試…」 | 你的 callback 沒進來 → 見 `platform-behaviors.md` §1／§2（多半是 callback 認證 401） |
| run 卡在 `pending` | 模組沒回 callback；或模組沒有**先回 200 再背景處理**（平台 POST 只等 30 秒） |
| run 直接 `failed`、訊息說端點無回應 | 模組回了非 2xx，或服務啟動失敗（看 Cloud Run log） |
| 點數不足 | test-run 扣的是**開發者自己**的點數，先儲值 |

## Rich UI

| 症狀 | 成因 |
|---|---|
| `$99agent` is undefined | 在平台預覽頁以外的環境開啟（runtime 只在 iframe 內注入）；iRich 站點物件名是 `$nSchool` |
| `requestMission()` reject | 使用者點數不足／未取得使用權——把錯誤訊息顯示給使用者，不要吞掉 |
| iframe 高度不對 | 頁面用了 `position: fixed` 佈局；runtime 的自動量測會失準 |
| select 試聽 404/403 | `previewUrl` 指向私有 bucket——必須匿名可讀（公開 bucket 或 `visibility=public` 的 `/api/media/<guid>`） |

## 客戶端環境

Windows／編碼相關問題見 `platform-behaviors.md` §9。
