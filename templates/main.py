# =============================================================================
# Agent OSS Developer App — main.py 起手模板
#
# 平台契約（詳見 references/mission-and-callback.md）：
#   1. 平台 POST / 送任務 JSON（30 秒 timeout）→ 立刻回 {"accepted": True}
#   2. 背景處理，期間可對 callback_url 回報進度（status 1–99）
#   3. 完成 → status 100 + result.files（或 output）；失敗 → status "failed"
#   4. 取消訊號也打 POST /（body 帶 action="cancel"）
#   5. 金鑰一律環境變數（平台 Secrets API 設定），絕不寫死
#
# 預設可用套件：fastapi / uvicorn / requests / pydantic / httpx
# 其他套件請加進 App 的 extraPackages（一行一個）。
# =============================================================================
import os
import threading

import requests
from fastapi import BackgroundTasks, FastAPI, Request

app = FastAPI()

# 進行中任務的取消旗標：mission_id -> threading.Event
_cancel_flags: dict[str, threading.Event] = {}


def post_callback(callback_url: str, payload: dict, headers: dict | None = None) -> None:
    """對 callback_url 回報。

    正式任務的 callback_url 已內含 ?token=，不需要額外 header；但 Agent API
    test-runs 的 callback_url 沒帶 token，改以 payload 的 callback_auth 提供
    認證 header——有給就帶上（防禦性支援，兩種路徑都相容）。
    """
    try:
        resp = requests.post(callback_url, json=payload, headers=headers or {}, timeout=30)
        if resp.status_code >= 400:
            print(f"[callback] HTTP {resp.status_code}: {resp.text[:200]}", flush=True)
    except Exception as exc:  # callback 失敗不要讓程式炸掉
        print(f"[callback] failed: {exc}", flush=True)


def callback_headers(body: dict) -> dict:
    auth = body.get("callback_auth") or {}
    if isinstance(auth, dict) and auth.get("header") and auth.get("value"):
        return {str(auth["header"]): str(auth["value"])}
    return {}


def process_mission(body: dict) -> None:
    mission_id = body.get("mission_id", "")
    app_id = body.get("app_id", "")
    callback_url = body.get("callback_url", "")
    cb_headers = callback_headers(body)
    cancel = _cancel_flags.setdefault(mission_id, threading.Event())

    def report(status, message="", result=None, output=None):
        payload = {"mission_id": mission_id, "app_id": app_id, "status": status}
        if message:
            payload["message"] = message
        if result is not None:
            payload["result"] = result
        if output is not None:
            payload["output"] = output
        post_callback(callback_url, payload, cb_headers)

    try:
        # ---- 讀取輸入欄位（key = 欄位 name，直接在 body 最上層）----------------
        # file 欄位一律是 URL 陣列；select 送 option value；api_key 欄位見下。
        # example_files: list[str] = body.get("receipt_files") or []
        # example_text: str = body.get("company_tax_id") or ""

        # ---- api_key 欄位（如有）---------------------------------------------
        # mode = body.get("openai_key_mode")  # "user_api_key" | "platform_credits"
        # api_key = body.get("openai_key") if mode == "user_api_key" \
        #     else os.environ["OPENAI_API_KEY"]   # 平台 Secrets 設定，部署後生效

        report(10, "開始處理")

        # ---- 在這裡實作你的邏輯 ----------------------------------------------
        # 長流程請分段檢查取消旗標：
        # if cancel.is_set():
        #     report("cancel", "使用者已取消")
        #     return
        #
        # 呼叫外部 AI 服務、輪詢結果……期間可多次 report(30, "..."), report(60, "...")

        # ---- 完成：檔案類輸出（平台會自動轉存外部 URL）------------------------
        # report(100, "完成", result={
        #     "files": [{"type": "image", "label": "圖片1", "url": "https://..."}],
        # })
        # ---- 或：結構化輸出 ---------------------------------------------------
        report(100, "完成", output={"summary": "已完成", "items": []})

        # ---- 本機檔案（無外部 URL）：先上傳 files_url 再放進 files[].url -------
        # credit_api = body.get("credit_api") or {}
        # token = body.get("mission_token", "")
        # with open(local_path, "rb") as fh:
        #     up = requests.post(
        #         credit_api["files_url"],
        #         headers={"Authorization": f"Bearer {token}"},
        #         files={"file": fh}, data={"filename": "result.png"}, timeout=60,
        #     ).json()
        # report(100, "完成", result={"files": [{"type": "image", "label": "結果", "url": up["url"]}]})

    except Exception as exc:
        # 任何失敗都要回報，不要讓任務卡住。failed 不會自動退點；
        # 需要退點時呼叫 credit_api.refund_url（帶固定 idempotency_key）。
        report("failed", f"處理失敗：{exc}")
    finally:
        _cancel_flags.pop(mission_id, None)


@app.post("/")
async def handle_mission(request: Request, background: BackgroundTasks):
    body = await request.json()

    # 取消訊號：與任務同一個端點，body 帶 action="cancel"
    if body.get("action") == "cancel":
        flag = _cancel_flags.get(body.get("mission_id", ""))
        if flag:
            flag.set()
        return {"accepted": True, "cancelled": True}

    # 立刻回應，背景處理（平台 POST 只等 30 秒）
    background.add_task(process_mission, body)
    return {"accepted": True}


@app.get("/health")
async def health():
    return {"ok": True}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8080")))
