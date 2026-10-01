"""仅供协议测试使用的本地 JSONL 服务，不调用网络或真实账号。"""
import json
import sys
import time

mode = sys.argv[1]
reset = int(time.time()) + 18000
requested = False


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
        result = {"account": {"type": "chatgpt", "email": "probe@example.invalid", "planType": "plus"}}
    elif method == "account/rateLimits/read":
        bucket = {
            "limitId": "codex", "planType": "plus",
            "primary": {"usedPercent": 10.5 if requested else 10, "windowDurationMins": 300, "resetsAt": reset},
            "secondary": {"usedPercent": 30, "windowDurationMins": 10080, "resetsAt": reset + 500000}
        }
        result = {"rateLimits": bucket, "rateLimitsByLimitId": {"codex": bucket}, "ordinaryUsageAllowed": mode != "quota-denied"}
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
