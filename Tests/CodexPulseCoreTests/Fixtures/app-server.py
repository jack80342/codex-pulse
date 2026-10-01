"""仅供协议测试使用的本地 JSONL 服务，不调用网络或真实账号。"""
import json
import os
import sys
import time
from pathlib import Path

mode = sys.argv[1]
reset = int(time.time()) + 18000
requested = False
home = Path(os.environ["CODEX_HOME"])
login_modes = {"login-success", "login-failed", "login-timeout", "login-invalid-url", "login-wrong-event"}
logged_in = mode not in login_modes and mode != "account-unlogged"
marker = home / "fixture-login"
logged_in = logged_in or marker.exists()


def send(message):
    payload = json.dumps(message) + "\n"
    if mode == "fragmented":
        split = len(payload) // 2
        sys.stdout.write(payload[:split])
        sys.stdout.flush()
        time.sleep(0.01)
        sys.stdout.write(payload[split:])
    else:
        sys.stdout.write(payload)
    sys.stdout.flush()


for line in sys.stdin:
    request = json.loads(line)
    method = request.get("method")
    if "id" not in request or not method:
        continue
    identifier = request["id"]
    with (home / "fixture-methods").open("a") as history:
        history.write(method + "\n")
    if mode == "malformed":
        print("not-json", flush=True)
        continue
    if mode == "eof":
        break
    if mode == "timeout":
        continue
    if mode == "rpc-error":
        send({"id": identifier, "error": {"code": 401, "message": "private-token-must-not-be-logged"}})
        continue
    if mode == "stderr":
        sys.stderr.write("x" * 262144)
        sys.stderr.flush()
    if method == "account/read":
        result = {"account": {"type": "chatgpt", "email": "probe@example.invalid", "planType": "plus"} if logged_in else None}
    elif method == "account/login/start":
        result = {"type": "chatgpt", "loginId": "login-test", "authUrl": "https://auth.openai.com/test"}
        if mode == "login-invalid-url":
            result["authUrl"] = "https://untrusted.example.invalid/private-token"
        if mode not in {"login-timeout", "login-invalid-url"}:
            if mode == "login-wrong-event":
                send({"method": "account/login/completed", "params": {"loginId": "different-login", "success": False}})
            logged_in = mode != "login-failed"
            if logged_in:
                marker.write_text("fixture-auth-only")
            send({"method": "account/login/completed", "params": {"loginId": "login-test", "success": logged_in}})
    elif method == "account/rateLimits/read":
        if mode == "account-quota-error":
            send({"id": identifier, "error": {"code": 401, "message": "private-token-must-not-be-logged"}})
            continue
        bucket = {
            "limitId": "codex", "planType": "plus",
            "primary": {"usedPercent": 10.5 if requested else 10, "windowDurationMins": 300, "resetsAt": reset},
            "secondary": {"usedPercent": 30, "windowDurationMins": 10080, "resetsAt": reset + 500000}
        }
        result = {"rateLimits": bucket, "rateLimitsByLimitId": {"codex": bucket}, "ordinaryUsageAllowed": mode != "quota-denied"}
        result["accountId"] = "fixture-" + home.name
    elif method == "model/list":
        result = {"data": [{"model": "test-model", "isDefault": True, "supportedReasoningEfforts": [{"reasoningEffort": "low"}]}], "nextCursor": None}
    elif method == "thread/start":
        assert request["params"]["sandbox"] == "read-only"
        assert request["params"]["ephemeral"] is True
        result = {"thread": {"id": "thread-test"}}
    elif method == "turn/start":
        requested = True
        assert request["params"]["serviceTierForTurn"] == "default"
        if mode == "tool-request":
            send({"id": "server-approval", "method": "item/commandExecution/requestApproval", "params": {}})
        if mode == "tool-item":
            send({"method": "item/started", "params": {"threadId": "thread-test", "turnId": "turn-test", "item": {"type": "commandExecution"}}})
        send({"method": "turn/completed", "params": {"threadId": "another-thread", "turn": {"id": "turn-test", "status": "failed"}}})
        send({"method": "item/completed", "params": {"threadId": "thread-test", "turnId": "turn-test", "item": {"type": "agentMessage", "text": "OK"}}})
        send({"method": "turn/completed", "params": {"threadId": "thread-test", "turn": {"id": "turn-test", "status": "failed" if mode == "failed-turn" else "completed"}}})
        result = {"turn": {"id": "turn-test", "status": "inProgress"}}
    else:
        result = {"echo": method}
    send({"id": identifier, "result": result})
