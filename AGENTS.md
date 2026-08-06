# Agent 進入點

任何 AI agent（Codex、Gemini CLI、Cursor…）要協助開發 Agent OSS 平台模組
（DeveloperApp）時：

**直接讀 [`SKILL.md`](SKILL.md)，並嚴格遵守其中的「站點綁定」與「硬規則」。**

最重要的三件事：

1. **先綁站點再動 API**：沒有 `.agentoss/config.json` 就先問使用者要開發哪個
   站點，跑 `bash scripts/agentoss.sh init <site>`。PAT 跨站共用，呼叫錯網域
   App 會落在錯的站點。
2. **PAT 不進版控**：只用環境變數 `AGENTOSS_API_KEY` 或 gitignored 的
   `.agentoss/credentials`。
3. **驗證才算完成**：寫入後 GET 讀回、部署 poll 到 `deployed`、
   test-run 跑到 `completed` 才能回報完成。

API 契約在 `references/`，模板在 `templates/`。
