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

## 核心概念：站點綁定

PAT 與開發者權限**跨站點共用**，但 App 落點由「呼叫哪個網域」決定。
skill 會把你選定的站點寫進 `.agentoss/config.json`，之後所有 API 呼叫
強制走該站點網域，避免 App 放錯站點市集。

```bash
bash scripts/agentoss.sh init 99agent   # 或 irich，或 init <code> <baseUrl>
bash scripts/agentoss.sh api GET /api/agent/apps
```

## 內容

| 路徑 | 說明 |
|---|---|
| `SKILL.md` | skill 主體：站點綁定規則、開發生命週期、硬規則 |
| `references/` | Agent API 完整端點契約、任務／callback 契約、Rich UI、計費 |
| `templates/` | `main.py` 與 Rich UI HTML 起手模板 |
| `scripts/agentoss.sh` | API 呼叫器（站點綁定、auth、部署／任務 poll） |

## 安全

- PAT 只放環境變數或 `.agentoss/credentials`（自動 gitignore），絕不進版控。
- skill 產出的 main.py 一律以環境變數讀金鑰（平台 Secrets API 設定）。
- Agent API 無法把 App 直接上架（`published`）——公開上架一律走平台管理員審核。
