#!/usr/bin/env bash
# =============================================================================
# agentoss.sh — Agent OSS Developer App API 呼叫器
#
# 站點綁定（避免 PAT 跨站共用導致 App 放錯站點）：
#   - 所有 API 呼叫強制走 .agentoss/config.json 的 baseUrl
#   - 沒綁定就拒絕執行（先跑 init）
#
# 憑證解析順序：$AGENTOSS_API_KEY > .agentoss/credentials
# 依賴：bash、curl；jq / python3 其一（美化輸出，缺了就吐原始 JSON）
# =============================================================================
set -euo pipefail

CONFIG_DIR=".agentoss"
CONFIG_FILE="$CONFIG_DIR/config.json"
CRED_FILE="$CONFIG_DIR/credentials"

# 內建站點 registry（新增站點：init <code> <baseUrl>）
site_base_url() {
  case "$1" in
    99agent) echo "https://all.99agent.app" ;;
    irich)   echo "https://www.irich.cc" ;;
    *)       echo "" ;;
  esac
}

die() { echo "錯誤：$*" >&2; exit 1; }

# Windows 的 python3 可能是 Microsoft Store 假 stub——必須實際跑一次驗證
PY=""
for _p in python3 python; do
  if command -v "$_p" >/dev/null 2>&1 && "$_p" -c 'pass' >/dev/null 2>&1; then PY="$_p"; break; fi
done

json_get() { # json_get <file> <key>  （頂層 string key）
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "$2" '.[$k] // empty' "$1"
  elif [ -n "$PY" ]; then
    "$PY" -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2],""))' "$1" "$2"
  else
    # 無 jq / python 時的最後手段（僅支援本腳本自己寫的扁平 config）
    sed -n 's/.*"'"$2"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1" | head -n1
  fi
}

pretty() {
  if command -v jq >/dev/null 2>&1; then jq .
  elif [ -n "$PY" ]; then "$PY" -m json.tool
  else cat; fi
}

require_config() {
  [ -f "$CONFIG_FILE" ] || die "尚未綁定站點。先執行：agentoss.sh init <site> [baseUrl]"
  SITE="$(json_get "$CONFIG_FILE" site)"
  BASE_URL="$(json_get "$CONFIG_FILE" baseUrl)"
  [ -n "$SITE" ] && [ -n "$BASE_URL" ] || die "$CONFIG_FILE 內容不完整，請重跑 init"
  case "$BASE_URL" in
    *agentoss.ai*)
      [ "${AGENTOSS_ALLOW_ANY_HOST:-}" = "1" ] || \
        die "agentoss.ai 是管理中台，不是模組開發目標站點（在那裡建立的 App 會誤落 99agent）。請 init 綁定正確站點。" ;;
  esac
}

require_key() {
  if [ -n "${AGENTOSS_API_KEY:-}" ]; then
    API_KEY="$AGENTOSS_API_KEY"
  elif [ -f "$CRED_FILE" ]; then
    API_KEY="$(head -n1 "$CRED_FILE" | tr -d '[:space:]')"
  else
    die "找不到 PAT。設定環境變數 AGENTOSS_API_KEY，或執行：agentoss.sh key（從 <baseUrl>/developer/api-keys 建立）"
  fi
  [ -n "$API_KEY" ] || die "PAT 是空的"
}

gen_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then uuidgen
  elif [ -r /proc/sys/kernel/random/uuid ]; then cat /proc/sys/kernel/random/uuid
  else date +%s%N; fi
}

cmd_init() {
  local site="${1:-}" base="${2:-}"
  [ -n "$site" ] || die "用法：agentoss.sh init <site> [baseUrl]（內建站點：99agent、irich）"
  if [ -z "$base" ]; then
    base="$(site_base_url "$site")"
    [ -n "$base" ] || die "未知站點 '$site'，請提供 baseUrl：agentoss.sh init $site https://<站點網域>"
  fi
  case "$base" in
    https://*) : ;;
    *) die "baseUrl 必須是 https:// 開頭的完整網址" ;;
  esac
  case "$base" in
    *agentoss.ai*) die "agentoss.ai 是管理中台，不能綁定為開發目標站點" ;;
  esac

  if [ -f "$CONFIG_FILE" ]; then
    local old_site; old_site="$(json_get "$CONFIG_FILE" site)"
    if [ -n "$old_site" ] && [ "$old_site" != "$site" ]; then
      echo "⚠ 站點切換：$old_site → $site。既有 App 留在原站點，不會跟著搬。" >&2
    fi
  fi

  mkdir -p "$CONFIG_DIR"
  printf '{\n  "site": "%s",\n  "baseUrl": "%s"\n}\n' "$site" "$base" > "$CONFIG_FILE"
  # credentials 永不進版控
  grep -qx 'credentials' "$CONFIG_DIR/.gitignore" 2>/dev/null || echo 'credentials' >> "$CONFIG_DIR/.gitignore"
  echo "已綁定站點：$site → $base"

  # 有 key 就順手驗證連線
  if [ -n "${AGENTOSS_API_KEY:-}" ] || [ -f "$CRED_FILE" ]; then
    echo "驗證 PAT..." >&2
    cmd_api GET /api/agent/apps >/dev/null && echo "PAT 驗證成功。" || echo "⚠ PAT 驗證失敗，請確認 key 是否有效。" >&2
  fi
}

cmd_site() {
  require_config
  echo "site:    $SITE"
  echo "baseUrl: $BASE_URL"
}

cmd_key() {
  mkdir -p "$CONFIG_DIR"
  grep -qx 'credentials' "$CONFIG_DIR/.gitignore" 2>/dev/null || echo 'credentials' >> "$CONFIG_DIR/.gitignore"
  echo "貼上 dev_sk_ 開頭的 PAT（輸入不會顯示）：" >&2
  local key; IFS= read -rs key
  [ -n "$key" ] || die "沒有輸入"
  printf '%s\n' "$key" > "$CRED_FILE"
  chmod 600 "$CRED_FILE" 2>/dev/null || true
  echo "已存入 $CRED_FILE（已 gitignore）"
}

cmd_api() { # api <METHOD> <path> [bodyfile|-]
  require_config; require_key
  local method="${1:-}" path="${2:-}" bodyfile="${3:-}"
  [ -n "$method" ] && [ -n "$path" ] || die "用法：agentoss.sh api <METHOD> </api/agent/...> [body.json|-]"
  case "$path" in /*) : ;; *) die "path 必須以 / 開頭" ;; esac

  local args=(-sS -X "$method" "$BASE_URL$path" \
    -H "Authorization: Bearer $API_KEY" \
    -H "X-99Agent-Schema-Version: 2026-05-21" \
    -w $'\n__HTTP_STATUS__:%{http_code}')
  case "$method" in
    POST|PUT|PATCH|DELETE) args+=(-H "Idempotency-Key: $(gen_uuid)") ;;
  esac
  if [ -n "$bodyfile" ]; then
    args+=(-H "Content-Type: application/json")
    if [ "$bodyfile" = "-" ]; then args+=(--data-binary @-)
    else [ -f "$bodyfile" ] || die "找不到 body 檔：$bodyfile"; args+=(--data-binary "@$bodyfile"); fi
  fi

  local raw status body
  raw="$(curl "${args[@]}")"
  status="${raw##*__HTTP_STATUS__:}"
  body="${raw%$'\n'__HTTP_STATUS__:*}"
  printf '%s\n' "$body" | pretty
  echo "HTTP $status" >&2
  [ "$status" -lt 400 ]
}

cmd_curl() { # 逃生口：帶好 auth 的裸 curl（multipart 上傳等用）
  require_config; require_key
  curl -sS -H "Authorization: Bearer $API_KEY" "$@"
}

extract_field() { # extract_field <json> <jq-path> <python-expr>
  local json="$1"
  if command -v jq >/dev/null 2>&1; then printf '%s' "$json" | jq -r "$2 // empty"
  elif [ -n "$PY" ]; then printf '%s' "$json" | "$PY" -c "import json,sys
try:
    d = json.load(sys.stdin)
    v = $3
    print('' if v is None else v)
except Exception:
    print('')"
  else echo ""; fi
}

cmd_wait_deploy() { # wait-deploy <appId> <deploymentId> [timeoutSec]
  require_config; require_key
  local app_id="${1:-}" dep_id="${2:-}" timeout="${3:-600}" waited=0 interval=10
  [ -n "$app_id" ] && [ -n "$dep_id" ] || die "用法：agentoss.sh wait-deploy <appId> <deploymentId> [timeoutSec]"
  while :; do
    local body status
    body="$(curl -sS "$BASE_URL/api/agent/apps/$app_id/deployments/$dep_id" \
      -H "Authorization: Bearer $API_KEY")"
    status="$(extract_field "$body" '.data.deployment.status' "d['data']['deployment']['status']")"
    echo "[$waited s] status=$status" >&2
    case "$status" in
      deployed) printf '%s\n' "$body" | pretty; return 0 ;;
      failed)   printf '%s\n' "$body" | pretty; echo "部署失敗——看上面 buildLogTail / errorMessage" >&2; return 1 ;;
      "")       printf '%s\n' "$body" | pretty; die "讀不到部署狀態（回應如上）" ;;
    esac
    [ "$waited" -ge "$timeout" ] && { echo "等待逾時（${timeout}s），最後狀態=$status" >&2; return 1; }
    sleep "$interval"; waited=$((waited + interval))
  done
}

cmd_wait_run() { # wait-run <appId> <runId> [timeoutSec]
  require_config; require_key
  local app_id="${1:-}" run_id="${2:-}" timeout="${3:-600}" waited=0 interval=5
  [ -n "$app_id" ] && [ -n "$run_id" ] || die "用法：agentoss.sh wait-run <appId> <runId> [timeoutSec]"
  while :; do
    local body status
    body="$(curl -sS "$BASE_URL/api/agent/apps/$app_id/runs?limit=50" \
      -H "Authorization: Bearer $API_KEY")"
    if command -v jq >/dev/null 2>&1; then
      status="$(printf '%s' "$body" | jq -r --arg id "$run_id" '(.data.runs // [])[] | select(.id==$id) | .status')"
    else
      status="$(printf '%s' "$body" | "$PY" -c "import json,sys
d = json.load(sys.stdin)
runs = (d.get('data') or {}).get('runs') or []
m = [r for r in runs if r.get('id') == '$run_id']
print(m[0]['status'] if m else '')" 2>/dev/null || echo '')"
    fi
    echo "[$waited s] status=${status:-not-found}" >&2
    case "$status" in
      completed|failed|timeout|cancelled)
        if command -v jq >/dev/null 2>&1; then
          printf '%s' "$body" | jq --arg id "$run_id" '(.data.runs // [])[] | select(.id==$id)'
        else printf '%s\n' "$body" | pretty; fi
        [ "$status" = "completed" ]; return $? ;;
    esac
    [ "$waited" -ge "$timeout" ] && { echo "等待逾時（${timeout}s），最後狀態=${status:-unknown}" >&2; return 1; }
    sleep "$interval"; waited=$((waited + interval))
  done
}

usage() {
  cat <<'EOF'
用法：agentoss.sh <command> ...

  init <site> [baseUrl]              綁定開發站點（內建：99agent、irich；其他站點需給 baseUrl）
  site                               顯示目前綁定
  key                                從 stdin 存入 PAT 到 .agentoss/credentials（gitignored）
  api <METHOD> <path> [body.json|-]  呼叫 Agent API（自動帶 auth / idempotency / baseUrl）
  curl <curl args...>                帶好 Authorization 的裸 curl（multipart 上傳等）
  wait-deploy <appId> <deploymentId> [timeoutSec]   poll 部署直到 deployed/failed
  wait-run <appId> <runId> [timeoutSec]             poll 任務直到終態

範例：
  agentoss.sh init 99agent
  agentoss.sh api GET /api/agent/apps
  echo '{"name":"我的模組","uiMode":"form"}' | agentoss.sh api POST /api/agent/apps -
EOF
}

case "${1:-}" in
  init)        shift; cmd_init "$@" ;;
  site)        shift; cmd_site "$@" ;;
  key)         shift; cmd_key "$@" ;;
  api)         shift; cmd_api "$@" ;;
  curl)        shift; cmd_curl "$@" ;;
  wait-deploy) shift; cmd_wait_deploy "$@" ;;
  wait-run)    shift; cmd_wait_run "$@" ;;
  ""|help|-h|--help) usage ;;
  *) die "未知指令 '${1}'（agentoss.sh help）" ;;
esac
