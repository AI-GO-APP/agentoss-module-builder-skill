# 定價與計費模式

全部透過 `PATCH {BASE}/api/agent/apps/:appId` 設定。

## 頂層欄位

| 欄位 | 意義 |
|---|---|
| `creditsBase` | 每次執行的基本點數（fixed 模式 = 每次固定扣這麼多） |
| `estimatedMonthly` | 月租價（NT$）。>0 表示此 App 需要取得使用權（訂閱／買斷）才能執行 |
| `estimatedBuyout` | 買斷價（NT$） |

`estimatedMonthly` / `estimatedBuyout` 都為 0 = 免費 App（人人可跑，仍按點數計費）。
平台另有「每月免費次數」機制（`free_monthly_runs`，由主控台設定）。

## `billing` 物件

| 欄位 | 值 | 意義 |
|---|---|---|
| `formCreditMode` | `platform_fixed` / `developer_managed` | form 模式扣點方：platform_fixed = 平台在任務建立時直接扣 `creditsBase`（**建議，也是平台對新模組的預設要求**）；developer_managed = 模組自己透過 credit_api 扣 |
| `richUiCreditMode` | 同上 | rich_ui 模式的扣點方 |
| `creditBillingMode` | `fixed` / `media_duration` / `duration_value` / `quantity` / `char_to_audio` | 計量方式 |
| `creditRateUnit` | `second` / `minute` | 計量單位（media_duration / duration_value 用） |
| `creditRatePerSecond` | 整數 | 每單位點數費率 |
| `creditMeterField` | 欄位名 | 計量來源欄位（如 quantity 模式取哪個輸入欄位當數量） |

## 模式速查

- **固定計費（最常見）**：`creditBillingMode: "fixed"` + `formCreditMode: "platform_fixed"`
  ＋ `creditsBase: N` —— 每次執行平台扣 N 點，main.py 完全不用碰 credit API。
- **計量計費（metered）**：如 `media_duration`（按輸出媒體秒數）、`quantity`
  （按張數）——任務啟動先扣基本點，執行中由 main.py 用 `credit_api.charge_url`
  補扣；**少交付要用 `refund_url` 部分退點**（模組責任）。
- **使用者自帶金鑰**：欄位型別 `api_key` 且使用者選 `user_api_key` 模式時，
  該次任務平台**不扣點**（`credits_per_run` = 0）。

## 驗證

設定完 `GET /api/agent/apps/:appId` 讀回 `billing` 與 `creditsBase` 確認；
metered 模式務必用 test-run 實測一次扣點（測試扣的是開發者自己的點數，
`credit_api` 行為與正式任務完全相同）。
