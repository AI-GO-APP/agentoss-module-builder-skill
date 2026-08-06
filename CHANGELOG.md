# Changelog

本檔是 `scripts/check-update.sh` 更新提示的變更摘要來源：
每個版本一節，節標題格式 `## <version> - <date>`，新版在上。

## 0.3.0 - 2026-08-06

- **`agentoss.sh doctor`**：探測綁定站點實際支援哪些 Agent API 端點（唯讀無副作用）。
  各站點是獨立部署，**API 覆蓋度不保證相同**——正式環境實測 `www.irich.cc` 缺
  `/code`、`/secrets`、`/deployments`、`/deployments/preview`、`/cover`，
  在該站無法透過 Agent API 寫 main.py 或部署 Cloud Run。
- SKILL.md 快速開始改為「init → doctor」；站點綁定規則新增第 6 條
- `references/platform-behaviors.md` §0：兩站端點覆蓋度對照表與辨識方式
  （這類 404 回 HTML，非 API 的 JSON 錯誤信封）

## 0.2.1 - 2026-08-06

- `e2e-smoke.sh`：修正狀態碼捕捉——`LAST_STATUS` 設在 command substitution 的子 shell
  裡傳不回父層，導致每個端點都誤報「無回應」。改用檔案傳遞。
  修正後對 UAT 實跑 **47 通過 / 0 失敗**（含兩次 Cloud Build 與 preview／production test-run）
- `check-update.sh`：新增 `AGENTOSS_UPDATE_RAW_BASE` 覆寫（fork／鏡像可指向自己的
  raw base；也讓更新邏輯本身可被測試）
- `agentoss.sh`：新增 `baseurl` 子指令（組 curl 網址用）
- README：補「憑證不要放 skill 安裝目錄」警告，並說明 `.agentoss/config.json`
  應跟著專案進版控（站點綁定共享可避免團隊成員把 App 建到別站）

## 0.2.0 - 2026-08-06

- **自我更新機制**：`VERSION` + 本檔 + `scripts/check-update.sh`（零相依 bash+curl，
  24h 節流、離線靜默、`--apply` 僅 git 安裝 `pull --ff-only`）；
  SessionStart hook 範本（`resources/hooks/`）；SKILL.md 新增「自我更新檢查」段
- **`CONTEXT.md` 術語表**：四種易混憑證（開發者 PAT／App API key／mission_token／
  callback token）與站點綁定詞彙
- **`references/platform-behaviors.md`**：UAT 全端點實測行為補遺
  （is_test 煙霧語意、callback_auth、部署 409 併發防護、callback-simulations 回捲雷…）
- **`references/troubleshooting.md`**：錯誤速查表＋「設定問題 vs 程式問題」分流
- **SKILL.md 新增「Review 現況」強制步驟**：對既有 App 開發前先盤點再動手
- **`scripts/e2e-smoke.sh`**：全端點回歸驗證腳本（skill 迭代後可對 UAT 重跑）

## 0.1.1 - 2026-08-06

- `agentoss.sh`：強制 `PYTHONUTF8`（Windows python 以 cp950 讀 stdin 導致中文 JSON 顯示亂碼）
- `agentoss.sh init`：支援 `AGENTOSS_ALLOW_ANY_HOST=1` 綁定 agentoss.ai 系網域（平台方 UAT 測試用）
- `templates/main.py` + references：callback 防禦性支援 `callback_auth`
  （Agent API test-runs 的 callback_url 未帶 `?token=`）

## 0.1.0 - 2026-08-06

- 初版：SKILL.md（站點綁定＋開發生命週期＋硬規則）、Agent API 全端點 reference、
  mission/callback 契約、Rich UI、計費說明、`main.py` 與 Rich UI 模板、
  `agentoss.sh` CLI（init／api／wait-deploy／wait-run）
