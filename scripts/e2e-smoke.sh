#!/usr/bin/env bash
# =============================================================================
# e2e-smoke.sh — Agent API 全端點回歸驗證【維護者工具，非開發流程的一部分】
#
# 對已綁定的站點跑一遍完整開發生命週期，驗證每個端點與硬規則仍如契約所述。
# 用途：skill 改版、或平台 API 改版後，確認 references/ 沒有過時。
#
# ⚠⚠ 這會在**正式站點**建立真實 App、部署真實 Cloud Run 服務、消耗開發者點數。
#     測完的 App 會被設為 archived，但已送審者需管理員處理，Cloud Run 服務
#     需刪 App 才會一併拆除。**開發模組時不需要、也不應該跑這支。**
#
# 用法（在已 init 的專案目錄下，必須顯式帶 --confirm）：
#   bash scripts/e2e-smoke.sh --confirm --quick   # 跳過部署與 test-run（約 20 秒）
#   bash scripts/e2e-smoke.sh --confirm           # 完整（含兩次 Cloud Build，約 5 分鐘）
#   bash scripts/e2e-smoke.sh --confirm --keep    # 保留測試 App（預設測完 archive）
# =============================================================================
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SK="$HERE/agentoss.sh"
QUICK=0; KEEP=0; CONFIRM=0
for a in "$@"; do case "$a" in --quick) QUICK=1 ;; --keep) KEEP=1 ;; --confirm) CONFIRM=1 ;; esac; done

if [ "$CONFIRM" != "1" ]; then
  cat >&2 <<'WARN'
這是維護者用的回歸驗證工具，會在正式站點建立真實 App 與 Cloud Run 服務，
並消耗開發者點數。開發模組時不需要跑這支。

確定要跑，請加 --confirm：
  bash scripts/e2e-smoke.sh --confirm --quick
WARN
  exit 1
fi

PASS=0; FAIL=0; SKIP=0
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Windows 的 python3 可能是 Microsoft Store 假 stub——實跑驗證（同 agentoss.sh）
export PYTHONUTF8=1 PYTHONIOENCODING=utf-8
PY=""
for _p in python3 python; do
  if command -v "$_p" >/dev/null 2>&1 && "$_p" -c 'pass' >/dev/null 2>&1; then PY="$_p"; break; fi
done

ok()   { PASS=$((PASS+1)); echo "  ✅ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ❌ $1"; }
skip() { SKIP=$((SKIP+1)); echo "  ⏭  $1"; }
step() { echo; echo "── $1"; }

# call <method> <path> [bodyfile] → stdout=response body；狀態碼寫進 $TMP/status。
# 注意：call 多半在 $( ) 子 shell 裡跑，變數傳不回父層——狀態碼一律透過檔案傳遞，
# 由父層的 last_status() 讀取。
call() { bash "$SK" api "$@" 2>"$TMP/status"; }
last_status() { sed -n 's/^HTTP //p' "$TMP/status" | tail -n1; }

# expect <期望碼> <描述> ...args → 呼叫並比對狀態碼
expect() {
  local want="$1" desc="$2"; shift 2
  RESP="$(call "$@")"
  local got; got="$(last_status)"
  if [ "$got" = "$want" ]; then ok "$desc（HTTP $want）"
  else bad "$desc（期望 $want，實得 ${got:-無回應}）"; fi
}
# has <字串> <描述> — 在最近一次 RESP 裡找
has() {
  if printf '%s' "$RESP" | grep -q -- "$1"; then ok "$2"; else bad "$2（回應中找不到 $1）"; fi
}
jget() { printf '%s' "$RESP" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -n1; }

bash "$SK" site >/dev/null 2>&1 || { echo "尚未綁定站點：先跑 agentoss.sh init <site>"; exit 1; }
echo "=== Agent API 全端點回歸 ==="; bash "$SK" site

# ---------------------------------------------------------------------------
step "1. 列出 App"
expect 200 "GET /apps" GET /api/agent/apps

step "2. 建立 App"
cat > "$TMP/create.json" <<'EOF'
{"name":"e2e-smoke test app","description":"agentoss-module-builder-skill 回歸測試，可刪。","category":"general","uiMode":"form","version":"0.1.0"}
EOF
expect 201 "POST /apps" POST /api/agent/apps "$TMP/create.json"
APP="$(jget id)"
[ -n "$APP" ] && ok "取得 appId：$APP" || { bad "拿不到 appId，中止"; exit 1; }
has '"status": "draft"' "新 App 狀態為 draft"
has '"webhookUrl": ""' "新 App webhookUrl 為空（唯讀，待部署寫入）"

step "3. 讀回 App"
expect 200 "GET /apps/:id" GET "/api/agent/apps/$APP"

step "4. 更新 metadata 與定價"
cat > "$TMP/patch.json" <<'EOF'
{"version":"0.1.1","creditsBase":1,"billing":{"formCreditMode":"platform_fixed","creditBillingMode":"fixed"}}
EOF
expect 200 "PATCH /apps/:id" PATCH "/api/agent/apps/$APP" "$TMP/patch.json"
RESP="$(call GET "/api/agent/apps/$APP")"
has '"version": "0.1.1"' "version 已寫入"
has '"creditsBase": 1' "creditsBase 已寫入"
has '"formCreditMode": "platform_fixed"' "billing 已寫入"

step "5. 表單欄位（replace / merge）"
cat > "$TMP/f1.json" <<'EOF'
{"mode":"replace","fields":[
 {"name":"subject_text","label":"main text","fieldType":"textarea","required":true,"sortOrder":0},
 {"name":"style_choice","label":"style","fieldType":"select","options":[{"label":"A","value":"a"},{"label":"B","value":"b"}],"required":true,"sortOrder":1}]}
EOF
expect 200 "PUT /fields (replace)" PUT "/api/agent/apps/$APP/fields" "$TMP/f1.json"
has '"subject_text"' "replace 建立 subject_text"
printf '{"mode":"merge","fields":[{"name":"reference_url","label":"ref","fieldType":"text"}]}' > "$TMP/f2.json"
expect 200 "PUT /fields (merge)" PUT "/api/agent/apps/$APP/fields" "$TMP/f2.json"
has '"deleted": \[\]' "merge 未刪除既有欄位"

step "6. 程式碼（PUT / GET / partial update）"
if [ -n "$PY" ]; then
  "$PY" - "$HERE/../templates/main.py" "$TMP/code.json" <<'PY'
import json, sys
src = open(sys.argv[1], encoding='utf-8').read()
json.dump({"codeContent": src, "extraPackages": "requests"}, open(sys.argv[2], 'w', encoding='utf-8'))
PY
fi
if [ -f "$TMP/code.json" ]; then
  expect 200 "PUT /code" PUT "/api/agent/apps/$APP/code" "$TMP/code.json"
  printf '{"codeContent":"from fastapi import FastAPI\\napp = FastAPI()\\n"}' > "$TMP/code2.json"
  expect 200 "PUT /code（只帶 codeContent）" PUT "/api/agent/apps/$APP/code" "$TMP/code2.json"
  RESP="$(call GET "/api/agent/apps/$APP/code")"
  has '"extraPackages": "requests"' "partial update 保留 extraPackages"
  expect 200 "PUT /code（還原完整模板）" PUT "/api/agent/apps/$APP/code" "$TMP/code.json"
else
  skip "程式碼測試（本機無可用 python 產生 JSON）"
fi

step "7. Secrets（PUT / GET / DELETE，值 write-only）"
printf '{"envName":"SMOKE_TEST_SECRET","value":"e2e-only"}' > "$TMP/s1.json"
expect 200 "PUT /secrets" PUT "/api/agent/apps/$APP/secrets" "$TMP/s1.json"
RESP="$(call GET "/api/agent/apps/$APP/secrets")"
has 'SMOKE_TEST_SECRET' "GET /secrets 列出 env 名稱"
printf '%s' "$RESP" | grep -q 'e2e-only' && bad "★ 值外洩：GET /secrets 回傳了明文" || ok "值未回傳（write-only）"
expect 200 "DELETE /secrets" DELETE "/api/agent/apps/$APP/secrets?envName=SMOKE_TEST_SECRET"

step "8. 負面測試（硬規則）"
printf '{"webhookUrl":"https://evil.example.com"}' > "$TMP/n1.json"
expect 400 "PATCH webhookUrl 被拒（唯讀）" PATCH "/api/agent/apps/$APP" "$TMP/n1.json"
has 'read-only' "錯誤訊息說明 webhookUrl 唯讀"
printf '{"status":"published"}' > "$TMP/n2.json"
expect 403 "PATCH status=published 被拒" PATCH "/api/agent/apps/$APP" "$TMP/n2.json"
printf '{"mode":"replace","fields":[{"name":"Bad-Name","label":"x","fieldType":"text"}]}' > "$TMP/n3.json"
expect 400 "非法欄位名被拒" PUT "/api/agent/apps/$APP/fields" "$TMP/n3.json"
expect 200 "還原合法欄位" PUT "/api/agent/apps/$APP/fields" "$TMP/f1.json"

step "9. Rich UI（在 clone 上測，不動主 App 的 form 模式）"
printf '{"version":"0.2.0","copyFields":true,"copyRichUi":false}' > "$TMP/clone.json"
expect 201 "POST /versions（clone）" POST "/api/agent/apps/$APP/versions" "$TMP/clone.json"
CLONE="$(jget id)"
has '"webhookUrl": ""' "clone 的 webhookUrl 為空"
if [ -n "$CLONE" ] && [ -n "$PY" ]; then
  "$PY" - "$HERE/../templates/rich-ui.html" "$TMP/ui.json" <<'PY'
import json, sys
json.dump({"html": open(sys.argv[1], encoding='utf-8').read(), "sourceName": "e2e.html"},
          open(sys.argv[2], 'w', encoding='utf-8'))
PY
  expect 200 "PUT /rich-ui" PUT "/api/agent/apps/$CLONE/rich-ui" "$TMP/ui.json"
  has '"uiMode": "rich_ui"' "uiMode 切換為 rich_ui"
  URL="$(jget richUiHtmlUrl)"
  if [ -n "$URL" ] && curl -fsS -m 15 "$URL" | grep -q '99agentRichUiAutoResize'; then
    ok "hosted HTML 已注入平台 runtime"
  else bad "hosted HTML 未見 runtime 注入標記"; fi
else skip "Rich UI 測試"; fi

step "10. 封面圖（multipart，只給 lg 應自動補齊）"
if [ -n "$PY" ]; then
  "$PY" - "$TMP/cover.jpg" <<'PY'
import base64, sys
# 64x48 純色 JPEG
open(sys.argv[1], 'wb').write(base64.b64decode(
 "/9j/4AAQSkZJRgABAQEAeAB4AAD/2wBDAAMCAgMCAgMDAwMEAwMEBQgFBQQEBQoHBwYIDAoMDAsKCwsNDhIQDQ4RDgsLEBYQERMUFRUVDA8XGBYUGBIUFRT/2wBDAQMEBAUEBQkFBQkUDQsNFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBQUFBT/wAARCAAwAEADASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDEooor9dPyQKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigAooooAKKKKACiiigD/9k="))
PY
  BASE="$(bash "$SK" baseurl)"
  if bash "$SK" curl -X POST "$BASE/api/agent/apps/$APP/cover" \
       -F "cover_lg=@$TMP/cover.jpg" 2>/dev/null | grep -q '"coverImageSmUrl"'; then
    ok "POST /cover：只給 lg，sm/md 自動補齊"
  else bad "POST /cover 失敗"; fi
else skip "封面圖測試"; fi

step "11. API key 旋轉"
expect 200 "POST /apikey/rotate" POST "/api/agent/apps/$APP/apikey/rotate"

step "12. callback 模擬（不需部署）"
expect 200 "GET /runs" GET "/api/agent/apps/$APP/runs?limit=5"

# ---------------------------------------------------------------------------
if [ "$QUICK" = "1" ]; then
  step "13-16. 部署與 test-run"; skip "--quick 模式跳過（Cloud Build 約需 70-90 秒/次）"
else
  step "13. 預覽部署"
  expect 202 "POST /deployments/preview" POST "/api/agent/apps/$APP/deployments/preview"
  DEP="$(jget id)"
  expect 409 "同 env 併發部署被拒" POST "/api/agent/apps/$APP/deployments/preview"
  if [ -n "$DEP" ] && bash "$SK" wait-deploy "$APP" "$DEP" 600 >"$TMP/dep.log" 2>&1; then
    ok "preview 部署完成（deployed）"
  else bad "preview 部署失敗（見 $TMP/dep.log 的 buildLogTail）"; fi

  step "14. test-run（preview）"
  cat > "$TMP/run.json" <<'EOF'
{"input":{"subject_text":"e2e smoke","style_choice":"a","reference_url":"https://example.com"},"target":"preview","waitForCallbackSeconds":45}
EOF
  expect 201 "POST /test-runs (preview)" POST "/api/agent/apps/$APP/test-runs" "$TMP/run.json"
  has '"status": "completed"' "run 收斂為 completed"
  if printf '%s' "$RESP" | grep -q 'is_test 煙霧測試'; then
    bad "★ output 是平台煙霧結果，模組 callback 未進來（見 platform-behaviors.md §1/§2）"
  else ok "output 來自模組本身（callback 成功）"; fi

  step "15. 正式部署"
  expect 202 "POST /deployments" POST "/api/agent/apps/$APP/deployments"
  DEP2="$(jget id)"
  if [ -n "$DEP2" ] && bash "$SK" wait-deploy "$APP" "$DEP2" 600 >"$TMP/dep2.log" 2>&1; then
    ok "production 部署完成"
    RESP="$(call GET "/api/agent/apps/$APP")"
    printf '%s' "$RESP" | grep -q '"webhookUrl": "https' && ok "deployer 已寫入 webhookUrl" || bad "webhookUrl 仍為空"
  else bad "production 部署失敗（見 $TMP/dep2.log）"; fi

  step "16. test-run（production）+ 送審"
  sed 's/"preview"/"production"/' "$TMP/run.json" > "$TMP/run2.json"
  expect 201 "POST /test-runs (production)" POST "/api/agent/apps/$APP/test-runs" "$TMP/run2.json"
  RUN="$(jget id)"
  printf '{"notes":"e2e smoke test","exampleRunId":"%s"}' "$RUN" > "$TMP/rev.json"
  expect 200 "POST /submit-review" POST "/api/agent/apps/$APP/submit-review" "$TMP/rev.json"
  has '"status": "pending"' "送審後狀態為 pending"
fi

# ---------------------------------------------------------------------------
step "清理"
if [ "$KEEP" = "1" ]; then
  echo "  --keep：保留 App $APP${CLONE:+ 與 clone $CLONE}"
else
  printf '{"status":"archived"}' > "$TMP/arch.json"
  [ -n "${CLONE:-}" ] && call PATCH "/api/agent/apps/$CLONE" "$TMP/arch.json" >/dev/null
  # 已送審（pending）的 App 無法自行 archive，屬預期
  call PATCH "/api/agent/apps/$APP" "$TMP/arch.json" >/dev/null
  echo "  已嘗試 archive 測試 App（送審中的 App 需由管理員處理）"
  echo "  App: $APP${CLONE:+  Clone: $CLONE}"
fi

echo; echo "=== 結果：$PASS 通過 / $FAIL 失敗 / $SKIP 略過 ==="
[ "$FAIL" -eq 0 ]
