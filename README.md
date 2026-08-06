# agentoss-module-builder-skill

給 **Agent OSS 平台站點（99agent、iRich…）模組開發者**的 AI 開發 skill：
讓 Claude Code / Codex 在你的 IDE（含 web IDE）裡，透過平台 Agent API 完成
Developer App 的完整開發流程——建立 App、表單欄位、Rich UI、定價、
main.py 撰寫與 Cloud Run 部署、secrets、測試任務、送審上架。

> 這裡的「開發者」指**平台模組（DeveloperApp）開發者**，
> 不是站點本身或 Agent OSS 平台的開發者。

## 安裝

**Claude Code**（skill 目錄）：

```bash
git clone https://github.com/AI-GO-APP/agentoss-module-builder-skill.git \
  ~/.claude/skills/agentoss-module-builder
```

或放在專案內：`<你的專案>/.claude/skills/agentoss-module-builder/`。

**Codex / 其他 agent**：clone 到模組專案裡任一目錄，
讓 agent 讀 [`AGENTS.md`](AGENTS.md)（會指向 [`SKILL.md`](SKILL.md)）。

## 前置需求

1. 在**目標站點**註冊並開通開發者身分。
2. 到 `<站點網址>/developer/api-keys` 建立開發者 API Key（PAT，`dev_sk_` 開頭）。
3. 把 key 放進環境變數 `AGENTOSS_API_KEY`（web IDE 建議用專案 secrets 設定），
   或執行 `bash scripts/agentoss.sh key` 存到本機（自動 gitignore）。

> ⚠️ **憑證要放你的 App 專案，不要放 skill 安裝目錄**。
> 用 `npx skills` 之類的工具更新 skill 時，可能會刪掉整個 skill 資料夾再重建——
> 放在裡面的 `.agentoss/credentials` 會直接消失，而且因為被 gitignore 忽略、
> 不在任何 commit 裡，救不回來。執行 `agentoss.sh` 前先確認 CWD 是你的專案目錄。
>
> `.agentoss/config.json` 只有站點綁定（無機密），**建議跟著專案進版控**——
> 團隊成員 clone 下來就綁在同一個站點，不會有人不小心把 App 建到別站。

## 核心概念：站點綁定

PAT 與開發者權限**跨站點共用**，但 App 落點由「呼叫哪個網域」決定。
skill 會把你選定的站點寫進 `.agentoss/config.json`，之後所有 API 呼叫
強制走該站點網域，避免 App 放錯站點市集。

```bash
bash scripts/agentoss.sh init 99agent   # 或 irich，或 init <code> <baseUrl>
bash scripts/agentoss.sh api GET /api/agent/apps
```

## 保持更新

Skill 內含版本標記（`VERSION`）與更新檢查腳本（`scripts/check-update.sh`），
比對本地與 GitHub 上的 `VERSION`，有新版才提示。腳本零相依（只用 bash + curl），
離線或逾時一律靜默略過，預設 24 小時內只檢查一次
（狀態存 `~/.agentoss/update_check.json`）。

**任何 agent 都適用（預設）**：`SKILL.md` 的第 -1 節會在每次 skill 觸發時執行檢查，
有新版時由 AI 告知並詢問是否更新。缺點是 `SKILL.md` 已載入 context，更新後需重新讀取
才會在當回合生效。

**Claude Code / Codex（推薦加裝）**：改用 SessionStart hook，在 skill 載入**之前**完成檢查，
沒有上述時序問題。範本在 `resources/hooks/`，把 `<SKILL_DIR>` 換成本機 skill 路徑後合併進設定：

| Agent | 設定檔 | 範本 |
|---|---|---|
| Claude Code | `~/.claude/settings.json` 或 `<專案>/.claude/settings.json` | `resources/hooks/claude-code.settings.example.json` |
| Codex CLI | `~/.codex/config.toml` 或 `<repo>/.codex/config.toml` | `resources/hooks/codex.config.example.toml` |

手動檢查與更新：

```bash
bash scripts/check-update.sh --force
```

`--apply` 只在 skill 目錄是 git repo 時才會實際 `pull --ff-only`（遇到分岔直接失敗，
不會覆寫你的本地修改）。

> 維護者注意：改動 skill 內容後要同步 bump `VERSION` 並在 `CHANGELOG.md` 補一節，
> 否則使用者端不會收到更新提示。

## 內容

| 路徑 | 說明 |
|---|---|
| `SKILL.md` | skill 主體：自我更新、站點綁定、Review 現況、開發生命週期、硬規則 |
| `CONTEXT.md` | 術語表——四種憑證／token、站點綁定、生命週期詞彙 |
| `VERSION` / `CHANGELOG.md` | 版本標記與變更紀錄（更新檢查的比對基準） |
| `references/` | Agent API 端點契約、任務／callback、Rich UI、計費、實測行為補遺、錯誤速查 |
| `templates/` | `main.py` 與 Rich UI HTML 起手模板 |
| `resources/hooks/` | SessionStart 更新檢查 hook 範本 |
| `scripts/agentoss.sh` | API 呼叫器（站點綁定、auth、部署／任務 poll） |
| `scripts/check-update.sh` | 自我更新檢查（零相依） |
| `scripts/e2e-smoke.sh` | 全端點回歸驗證 |

## 回歸驗證

skill 迭代或平台 API 改版後，對已綁定站點重跑全端點驗證：

```bash
bash scripts/e2e-smoke.sh --quick
```

不帶 `--quick` 會連 Cloud Run 部署與 test-run 一起驗（約 5 分鐘）。
⚠️ 會在目標站點建立真實 App 與 Cloud Run 服務並消耗開發者點數，
不要對正式站點大量重跑。

## 安全

- PAT 只放環境變數或 `.agentoss/credentials`（自動 gitignore），絕不進版控。
- skill 產出的 main.py 一律以環境變數讀金鑰（平台 Secrets API 設定）。
- Agent API 無法把 App 直接上架（`published`）——公開上架一律走平台管理員審核。
