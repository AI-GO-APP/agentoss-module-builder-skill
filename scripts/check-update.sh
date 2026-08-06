#!/usr/bin/env bash
# =============================================================================
# check-update.sh — Skill 自我更新檢查
#
# 比對本地 VERSION 與 GitHub 遠端 VERSION，有新版時提示更新指令。
#
# 設計約束（改動前先讀）：
# - 零相依：只用 bash + curl（git 僅 --apply 用）。SessionStart hook 會在任何
#   專案下跑，不能假設其他工具存在。
# - 永不阻斷：離線、逾時（3 秒）、格式異常一律靜默 exit 0。
# - 節流：預設 24 小時內只檢查一次，狀態存 ~/.agentoss/update_check.json。
# - 絕不自動覆寫：--apply 只在 skill 目錄是 git repo 時 `pull --ff-only`；
#   其餘情況只印指令，由使用者決定。
#
# 用法：
#   bash check-update.sh            # 檢查（含節流），有新版才輸出
#   bash check-update.sh --force    # 忽略節流
#   bash check-update.sh --apply    # 有新版時嘗試就地更新（git 安裝才實際執行）
# =============================================================================
set -u

REPO="AI-GO-APP/agentoss-module-builder-skill"
RAW_BASE="https://raw.githubusercontent.com/$REPO/main"
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_FILE="$HOME/.agentoss/update_check.json"
FETCH_TIMEOUT=3
THROTTLE_SECONDS=86400
CHANGELOG_MAX_LINES=20

FORCE=0; APPLY=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --apply) APPLY=1; FORCE=1 ;;
  esac
done

# ---- 本地版本 ---------------------------------------------------------------
[ -f "$SKILL_DIR/VERSION" ] || exit 0
LOCAL="$(head -n1 "$SKILL_DIR/VERSION" | tr -d '[:space:]')"
[ -n "$LOCAL" ] || exit 0

# ---- 節流 -------------------------------------------------------------------
now="$(date +%s)"
if [ "$FORCE" != "1" ] && [ -f "$STATE_FILE" ]; then
  last="$(sed -n 's/.*"last_check"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$STATE_FILE" | head -n1)"
  if [ -n "$last" ] && [ $((now - last)) -lt "$THROTTLE_SECONDS" ]; then
    exit 0
  fi
fi

# ---- 遠端版本 ---------------------------------------------------------------
command -v curl >/dev/null 2>&1 || exit 0
REMOTE="$(curl -fsS -m "$FETCH_TIMEOUT" "$RAW_BASE/VERSION" 2>/dev/null | head -n1 | tr -d '[:space:]')"
[ -n "$REMOTE" ] || exit 0   # 離線/抓不到：不寫節流狀態，下次再試

mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null
printf '{\n  "last_check": %s,\n  "local": "%s",\n  "remote": "%s"\n}\n' \
  "$now" "$LOCAL" "$REMOTE" > "$STATE_FILE" 2>/dev/null || true

# ---- 版本比較（sort -V；不可用時退回字串不等判斷）---------------------------
is_newer() { # is_newer <remote> <local> → 0 表示遠端較新
  [ "$1" = "$2" ] && return 1
  if sort --help 2>/dev/null | grep -q -- '-V'; then
    [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -n1)" = "$1" ]
  else
    return 0
  fi
}
is_newer "$REMOTE" "$LOCAL" || exit 0

# ---- 有新版：輸出提示 -------------------------------------------------------
if [ -d "$SKILL_DIR/.git" ]; then METHOD=git; UPDATE_CMD="git -C \"$SKILL_DIR\" pull --ff-only"
else METHOD=copy; UPDATE_CMD="npx skills update"; fi

echo "[agentoss-module-builder] 有新版可用：本地 $LOCAL → 遠端 $REMOTE"

CHANGELOG="$(curl -fsS -m "$FETCH_TIMEOUT" "$RAW_BASE/CHANGELOG.md" 2>/dev/null \
  | awk -v ver="$REMOTE" 'BEGIN{p=0} /^## /{if(p)exit; if(index($0,ver))p=1} p{print}' \
  | head -n "$CHANGELOG_MAX_LINES")"
[ -n "$CHANGELOG" ] && printf '\n變更摘要：\n%s\n\n' "$CHANGELOG"

if [ "$APPLY" = "1" ] && [ "$METHOD" = "git" ]; then
  if out="$(git -C "$SKILL_DIR" pull --ff-only 2>&1)"; then
    echo "已更新：$out"
    echo "請重新讀取 SKILL.md 以套用新版指令。"
  else
    echo "更新未完成（本地可能有修改或分支已分岔）：$out"
  fi
else
  echo "更新指令：$UPDATE_CMD"
  echo "請先告知使用者版本落差並取得同意，不要逕自覆寫本地檔案。"
fi
exit 0
