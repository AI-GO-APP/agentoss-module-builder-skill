# Rich UI 開發指南

`uiMode: "rich_ui"` 的 App 不用平台表單，改由開發者提供**完整 HTML 頁面**，
在前台以 sandbox iframe 呈現。起手模板：[templates/rich-ui.html](../templates/rich-ui.html)。

## 上傳

```txt
PUT {BASE}/api/agent/apps/:appId/rich-ui
{ "html": "<!doctype html>...", "sourceName": "workbench.html" }
```

- HTML ≤ 2MB（含內嵌 CSS/JS；外部資產自行掛 CDN 或平台公開儲存）。
- 平台會**自動注入 runtime script**（也會先剝掉舊版），不要自己複製 runtime 程式碼。
- 上傳後 `uiMode` 自動變 `rich_ui`，回傳 hosted `richUiHtmlUrl` 與 `previewUrl`。

## Runtime（平台注入的 `window.$99agent`）

| API | 說明 |
|---|---|
| `$99agent.requestMission(options?)` | 回傳 `Promise<mission>`。向平台要求建立任務（平台處理 entitlement／扣點），resolve 拿到任務 payload。`options.timeoutMs` 預設 15000 |
| `$99agent.getMission()` | 取得最近一次任務 payload（沒有則 `null`） |
| `$99agent.postHeight()` | 手動觸發 iframe 高度回報（平常 runtime 自動偵測） |
| `window` 事件 `99agent:mission` | 任務 payload 抵達時 dispatch，`event.detail` = mission |

任務 payload 內容與 main.py 收到的一致（`mission_id`、`callback_url`、
`mission_token`、`credit_api`、`billing`…，見 mission-and-callback.md）。

## 標準流程

1. 使用者在你的 UI 填好參數，按執行。
2. `const mission = await $99agent.requestMission()` —— 失敗（點數不足／未取得
   使用權）promise 會 reject，把錯誤顯示給使用者。
3. 把 mission 內容 + 你 UI 收集的參數，POST 到**你自己的 Cloud Run 後端**
   （正式部署後的 serviceUrl；開發期可先打 preview 服務網址）。
4. 你的 main.py 背景處理、對 `callback_url` 回報進度／結果（同 form 模式）。
5. UI 端可輪詢你自己的後端、或讓使用者從平台任務紀錄看結果。

## 注意事項

- **計費**：rich_ui 預設 `richUiCreditMode: "developer_managed"` ——
  requestMission 建立任務後，扣點細節由你的後端透過 `credit_api` 控制
  （`platform_fixed` 則由平台按 `creditsBase` 固定扣）。見 billing.md。
- **沙箱**：頁面跑在 iframe sandbox 裡，不能碰平台 cookie／DOM；
  與平台唯一的溝通管道就是上述 runtime。
- 高度自適應由 runtime 自動處理，避免頁面用 `position: fixed` 佈局。
- **iRich 站點注意**：iRich（finance）站點的既有 Rich UI runtime 物件名是
  `window.$nSchool`（歷史 wire protocol）。為 iRich 開發時先確認該站現行
  runtime 名稱，兩個名稱都掛上防呆判斷最保險：
  `const rt = window.$99agent || window.$nSchool`。
