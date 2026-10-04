#!/usr/bin/env bash
# r20 run-scenario v2 — PRODUCTION-TOPOLOGY bench (user ruling 2026-09-30:
# "我工作环境里是要用PCB-Orchestrator这个角色来执行的"). One rep = fresh arena
# (per-rep reseed is the L2 reset AND the pollution guard: smoke runs mutate the
# copied opencode.db/config and can drift G1), bwrap quarantine at the control
# literal, launcher-gated serve on a free port (netns impossible: lo EPERM),
# scenario driven as a REAL pcb-orchestrator session over REST, transcript +
# control-plane ledger harvested with literal->arena path mapping for the grader.
# Usage: run-scenario-r20.sh <unit-id> <scenario-file> <genome-repo> [arena-root]
set -uo pipefail
UNIT="$1"; SCENARIO="$2"; GENOME_REPO="$3"; ARENA="${4:-/tmp/r20-arena-$UNIT}"
GRAD=/home/lab/workspace/harness/Abathur/graders/pcb-agent
LIT=/home/lab/workspace/pcb-control
OUT="$GENOME_REPO/.omo/run-artifacts/$UNIT"; mkdir -p "$OUT"
BRIEF_FILE="$OUT/brief.md"; cp "$SCENARIO" "$BRIEF_FILE"

bash "$GRAD/seed-r20-arena.sh" "$ARENA" "$GENOME_REPO" > "$OUT/seed.log" 2>&1 || { echo "SEED_FAIL" > "$OUT/infra.fail"; exit 1; }

# candidate role files: seed copied $GENOME_REPO/agents/*.md over all three trees (v4 seam)

cat > "$OUT/inner.sh" <<'INNER'
set -x
L=/home/lab/workspace/pcb-control
OUTD=__OUT__
PORT=${PCB_PRODUCTION_SERVE_PORT}
cd $L/production-console
export HOME=$L/production-home
timeout ${PCB_REP_TIMEOUT:-1500} $L/tools/start_production_orchestrator_ui.sh --serve $PORT > $OUTD/serve.log 2>&1 &
SPID=$!
OK=0
for i in $(seq 1 150); do sleep 3
  curl -s --max-time 2 http://127.0.0.1:$PORT/session >/dev/null 2>&1 && { OK=1; break; }
  kill -0 $SPID 2>/dev/null || break
done
[ "$OK" = 1 ] || { echo "SERVE_UP=0" > $OUTD/infra.fail; kill $SPID 2>/dev/null; exit 1; }
$L/tools/start_production_orchestrator_ui.sh --probe $PORT 2>&1 | tail -1 > $OUTD/probe.txt
SID=$(curl -s --max-time 10 -X POST http://127.0.0.1:$PORT/session -H 'content-type: application/json' -d "{\"title\":\"bench-$UNIT\"}" | python3 -c "import json,sys;print(json.load(sys.stdin).get('id',''))")
# r21: named bench-approver arm (reactive H-gate stand-in, append-only audit log)
setsid nohup python3 /home/lab/workspace/harness/Abathur/graders/pcb-agent/bench-approver.py \
  http://127.0.0.1:$PORT "$SID" $OUTD/approve-log.jsonl ${PCB_REP_TIMEOUT:-2400} >/dev/null 2>&1 &
APPR=$!
python3 - "$OUTD" "$BRIEF_FILE" <<'PYMSG' > $OUTD/payload.json
import json, sys
outd, brief = sys.argv[1], sys.argv[2]
msg = open(brief).read()
json.dump({"agent": "pcb-orchestrator",
           "model": {"providerID": "local-qwen", "modelID": "qwen3.8-flash-next"},
           "parts": [{"type": "text", "text": msg}]}, open(outd + "/payload_body.json", "w"))
PYMSG
START=$(date +%s)
timeout ${PCB_REP_TIMEOUT:-2400} curl -s --max-time ${PCB_REP_TIMEOUT:-2400} -X POST "http://127.0.0.1:$PORT/session/$SID/message" -H 'content-type: application/json' -d @$OUTD/payload_body.json > $OUTD/turn1.json &
T1=$!
echo "$SID" > $OUTD/session-id
DONE=0
while kill -0 $SPID 2>/dev/null; do
  if find $L/production-console -maxdepth 3 -name 'RESULT.md' -newer $OUTD/seed.log 2>/dev/null | grep -qm1 .; then DONE=1; break; fi
  if kill -0 $T1 2>/dev/null && [ $(( $(date +%s) - START )) -gt $(( ${PCB_TURN_TIMEOUT:-1800} + 60 )) ]; then break; fi
  sleep 15
done
wait $T1 2>/dev/null
for i in 1 2 3; do curl -s --max-time 30 "http://127.0.0.1:$PORT/session/$SID/message" > $OUTD/transcript.json curl -s --max-time 60 "http://127.0.0.1:$PORT/session/$SID/message" > $OUTD/transcript.jsoncurl -s --max-time 60 "http://127.0.0.1:$PORT/session/$SID/message" > $OUTD/transcript.json [ -s $OUTD/transcript.json ] curl -s --max-time 60 "http://127.0.0.1:$PORT/session/$SID/message" > $OUTD/transcript.jsoncurl -s --max-time 60 "http://127.0.0.1:$PORT/session/$SID/message" > $OUTD/transcript.json break; sleep 5; done
kill $SPID $APPR 2>/dev/null
[ -s $OUTD/transcript.json ] || { echo "EMPTY_TRANSCRIPT" > $OUTD/infra.fail; exit 1; }
[ "$DONE" = 1 ] || { echo "MISSION_INCOMPLETE" > $OUTD/infra.fail; exit 1; }
INNER
sed -i "s#__OUT__#/tmp/r20-out-$UNIT#g" "$OUT/inner.sh"  # sandbox-writable; harvested after
mkdir -p /tmp/r20-out-$UNIT && rm -f /tmp/r20-out-$UNIT/*

# r20-bench.sh builds the full mount table (bin + every vendored node_modules
# literal-stack + free-port env). inner.sh reads $PCB_PRODUCTION_SERVE_PORT.
timeout $(( ${PCB_REP_TIMEOUT:-1500} + 900 )) bash "$GRAD/r20-bench.sh" "$ARENA" -- \
  "BRIEF_FILE=$BRIEF_FILE bash $OUT/inner.sh" > "$OUT/inner.log" 2>&1
RC=$?
cp -f /tmp/r20-out-$UNIT/* "$OUT/" 2>/dev/null || true
# node_modules literal-stack binds (arena lacks them by design)
# harvest: map the control literal back to the arena for the grader
python3 - "$OUT" "$ARENA" "$LIT" <<'PYH' 2>/dev/null || true
import json, os, re, sys
out, arena, lit = sys.argv[1:4]
t = os.path.join(out, "transcript.json")
if os.path.exists(t):
    s = open(t, errors="replace").read().replace(lit, arena)
    open(t, "w").write(s)
PYH
cp -f "$ARENA"/state/capabilities/*.json "$OUT/" 2>/dev/null || true
find "$ARENA/state" -name 'denied-*' -newer "$OUT/seed.log" 2>/dev/null | head -20 > "$OUT/ledger-rows.txt"
echo "r20-rep rc=$RC unit=$UNIT arena=$ARENA out=$OUT"
exit $RC
