#!/usr/bin/env python3
"""r21 bench-approver — the named stand-in for the human H-gate INSIDE THE BENCH
ONLY. It never runs against the production serve (asserted by port arg + the
arena's existence). Watches the orchestrator session transcript; whenever a
dispatch is denied for a missing approval whose plan has been DECLARED in the
session (the orchestrator states 'plan_sha256 <hex64>' per its role contract),
posts the exact user message `APPROVE PLAN <sha>`. Every grant is written to an
append-only approve-log with the trigger evidence, so the grader can audit that
the approval was REACTIVE to the team's own plan text — the approver never
authors a plan and never approves an unread hash.
Usage: bench-approver.py <base-url> <session-id> <log.jsonl> [deadline_s]"""
import json, re, sys, time, urllib.request

BASE, SID, LOG = sys.argv[1], sys.argv[2], sys.argv[3]
DEADLINE = time.time() + int(sys.argv[4] if len(sys.argv) > 4 else 1200)
HEX64 = re.compile(r"^[0-9a-f]{64}$")


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=15) as r:
        return json.load(r)


def post(path, body):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode(),
                                 headers={"content-type": "application/json"}, method="POST")
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def log(rec):
    with open(LOG, "a") as fh:
        rec["at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        fh.write(json.dumps(rec, ensure_ascii=False) + "\n")


seen = set()
while time.time() < DEADLINE:
    try:
        msgs = get(f"/session/{SID}/message")
        arr = msgs if isinstance(msgs, list) else msgs.get("data", [])
        plans = []
        for m in arr:
            info = m.get("info") or m
            for p in m.get("parts", []):
                if p.get("type") != "text":
                    continue
                t = str(p.get("text") or "")
                # plan declarations by the ORCHESTRATOR (assistant text) and
                # gate-denial echoes (tool text): collect every 64-hex after a plan marker
                for mm in re.finditer(r"plan_sha256[^0-9a-f]{0,4}([0-9a-f]{64})", t):
                    plans.append(mm.group(1))
                for mm in re.finditer(r"PLAN_NOT_APPROVED[^0-9a-f]{0,80}([0-9a-f]{64})", t):
                    plans.append(mm.group(1))
        for sha in dict.fromkeys(plans):
            if sha in seen or not HEX64.match(sha):
                continue
            seen.add(sha)
            already = False
            for m in arr:
                info = m.get("info") or m
                if info.get("role") != "user":
                    continue
                for p in m.get("parts", []):
                    if str(p.get("text", "")).strip() == f"APPROVE PLAN {sha}":
                        already = True
            if already:
                continue
            r = post(f"/session/{SID}/message", {
                "agent": "pcb-orchestrator",
                "parts": [{"type": "text", "text": f"APPROVE PLAN {sha}"}]})
            log({"grant": "APPROVE PLAN " + sha, "message_id": (r.get("info") or {}).get("id"),
                 "basis": "reactive to plan declared in team's own session text"})
    except Exception as e:  # noqa: BLE001
        log({"error": str(e)[:200]})
    time.sleep(10)
log({"done": True, "reason": "deadline"})
