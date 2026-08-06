# 實測行為補遺（platform behaviors）

> 本檔收「與直覺或文件字面不符的**實測平台行為**」。每條都寫：實測結果、
> 為什麼容易誤判、正確作法。API 規格本身見 `api-reference.md`。
> （驗證基準：2026-08-06 UAT 全端點實測）

## 0. 各站點的 API 覆蓋度不同（★ 動工前先 `doctor`）

站點是**各自獨立的部署**，Agent API 的端點覆蓋度不保證一致。
綁定站點後第一件事：

```bash
bash scripts/agentoss.sh doctor
```

2026-08-06 正式環境實測：

| 端點 | all.99agent.app | www.irich.cc |
|---|:---:|:---:|
| 列表／讀取／改 metadata、fields、rich-ui | ✅ | ✅ |
| test-runs、callback-simulations、runs | ✅ | ✅ |
| versions、submit-review、apikey/rotate | ✅ | ✅ |
| **code（main.py）** | ✅ | ❌ 404 |
| **secrets** | ✅ | ❌ 404 |
| **deployments／deployments/preview** | ✅ | ❌ 404 |
| **cover** | ✅ | ❌ 404 |

**影響**：在 irich 站**無法透過 Agent API 完成完整開發流程**——寫不了 `main.py`、
設不了 secrets、部署不了 Cloud Run。該站的模組後端由平台方以其他方式供裝
（實測既有 finance 模組的 `webhookUrl` 是 `finance-<appId>-prod` 命名的 Cloud Run
服務，非自助部署產物）。

**辨識方式**：這類 404 回的是 **HTML**（Next.js 找不到路由），
不是 API 的 JSON 錯誤信封（`{"ok":false,...}`）。看到 `content-type: text/html`
就是「本站沒有這個端點」，不是你的參數錯。

**規劃工作時**：若使用者要在覆蓋度不完整的站點開發模組，**先講清楚哪些步驟做不到**，
不要做到第 4 步才撞 404。

## 1. Agent API test-runs 的 callback 認證與正式任務不同（★ 最重要）

- **正式任務**（前台表單執行）：`callback_url` 內含 `?token=`，模組直接 POST 即可。
- **Agent API test-runs**：`callback_url` **沒帶 token**，改在 payload 給
  `callback_auth: { "header": "Authorization", "value": "Bearer <app-api-key>" }`。
- 誤判方式：按官方模組契約（「不要加任何 Authorization header」）寫的模組，
  在 test-run 下回呼一律 **401**，而且模組端若沒 log 回應碼就完全無感。
- **正確作法**：模組防禦性支援兩種——body 有 `callback_auth` 就帶上該 header，
  沒有就直接 POST（`templates/main.py` 已內建）。

## 2. test-run 出現「is_test 煙霧測試」summary = 你的 callback 沒進來

- 模組在等待時間內沒有以 callback 收斂 run 時，平台會把 run 直接標成
  `completed`，output 寫入 `「is_test 煙霧測試（<target>）HTTP <code>｜依約定未進生成流程、未扣點」`。
- 誤判方式：看到 `status: completed` 就以為端到端成功。**這個 summary 是
  平台合成的煙霧結果，不是你模組的 output**。
- 正確作法：驗證 test-run 時必須檢查 `output` 內容是**你模組產的資料**；
  出現煙霧字樣 → 回頭查 callback（多半是 §1 的 401，或模組沒回報）。

## 3. callback-simulations 會無條件套用 payload（可能把 run 倒回 processing）

- 對已 `completed` 的 run 模擬 `status: processing, progress: 55` → run 真的
  **倒回 processing**，並停在那裡。
- 正確作法：模擬完 processing 後補一發 `status: 100` 讓 run 重新收斂，
  不要把測試 run 留在 processing 狀態。

## 4. 部署併發與時長

- 同一 environment 同時只允許一個進行中的部署：409 `conflict`，
  `details.activeDeployment` 附進行中那筆。**preview 與 production 可並行**。
- 實測 build+deploy 一輪約 **70–90 秒**（Cloud Build）。`wait-deploy` 以 10 秒
  間隔 poll 即可，不必更密。
- `DELETE /deployments/:id` 只認 legacy `pending_review` 部署；對已 `deployed`
  的紀錄回 409 `deployment is past review and cannot be withdrawn`——這是預期
  行為，不是 bug。

## 5. Cloud Run 服務直連是 403，不是壞掉

- 部署出的服務 IAM 只綁平台 SA 的 `run.invoker`（OIDC）。瀏覽器或 curl 直打
  serviceUrl 回 403 是**預期**——只有平台能呼叫你的服務。
- 要測服務就走 `POST /test-runs`（回應的 `target.authenticated: true` 表示
  平台有帶 OIDC token）。

## 6. secrets 改動不會即時生效

- `PUT /secrets` 只寫加密儲存；**下一次部署**才注入成 Cloud Run env var。
- 驗證注入是否成功：模組把 `bool(os.environ.get("KEY"))` 放進 output 回報
  （不要回傳值本身）。

## 7. cover 上傳只給 lg 會自動補 sm/md

- `POST /cover` 至少一個變體即可；缺的以最大變體補齊。重 POST 即覆蓋。

## 8. 站點落點與 siteCode

- App 落在哪個站點由**呼叫的網域**決定；`POST /api/agent/apps` 不接受 body
  傳 siteCode。平台正在補「依 request host 自動 stamp + 回應帶 `siteCode`」，
  部署後建立回應可直接驗證落點；在那之前，落點只能靠站點綁定紀律保證。

## 9. Windows 客戶端雷（skill 腳本已處理，自寫工具注意）

- Git Bash 的 `python3` 可能是 Microsoft Store 假 stub（exit 49）——用前先
  實跑 `python3 -c 'pass'` 驗證。
- Windows python 預設以系統 ANSI codepage（cp950）讀 stdin：中文 JSON 經
  `python -m json.tool` 顯示成 `\udcxx` 亂碼，**資料本身沒壞**。
  設 `PYTHONUTF8=1` 即解。
- Bash tool／heredoc 寫含中文的 JSON 檔可能編碼不穩——用編輯器／Write 工具
  產檔，並以 hexdump 驗 UTF-8（`e5 85 a8` = 「全」）。
