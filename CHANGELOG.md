# Changelog

本檔是 `scripts/check-update.sh` 更新提示的變更摘要來源：
每個版本一節，節標題格式 `## <version> - <date>`，新版在上。

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
