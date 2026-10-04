#!/usr/bin/env bash
# run-scenario.sh (pcb-agent) — spawn the PCB TEAM headless on the scenario brief.
# The seat writes ZERO board artifacts here: this script only (1) seeds an isolated
# arena, (2) launches the internal-control orchestrator profile (isolated HOME/DB per
# L-isolation) with the brief, (3) records the transcript. All engineering is done by
# the team's own agents. Transcript = the evidence the grader reads.
#
# Contract mirrors historian: argv = <unitId> <scenario-file> [repoRoot]; last stdout
# line = {"tokensEst":N,"turns":M} for parseRunMeta; ABATHUR_TRANSCRIPT honored.
set -euo pipefail
unit_id="${1:?usage: run-scenario.sh <unitId> <scenario-file> [repoRoot]}"
scenario_file="${2:?scenario file}"
repo_root="${3:-$(dirname "$(dirname "$scenario_file")")}"
HERE="$(cd "$(dirname "$0")" && pwd)"
CONTROL=/home/lab/workspace/pcb-control
ARENA_ROOT="${PCB_BENCH_ARENA:-/tmp/opencode/pcb-bench}"
ARENA="$ARENA_ROOT/$unit_id"
TRANSCRIPT="${ABATHUR_TRANSCRIPT:-$ARENA_ROOT/$unit_id.transcript.jsonl}"
mkdir -p "$ARENA_ROOT"

bash "$HERE/seed-sandbox.sh" "$ARENA" "$HERE/seed"

# Brief = the scenario file (whole thing; it is the task card, no solutions inside).
BRIEF="$(cat "$scenario_file")"
# run cards (S4 seam, historian precedent): candidate mutations ride to the team verbatim.
rc=""
if [ -d "$repo_root/abathur-notes" ]; then
  for n in "$repo_root"/abathur-notes/*.md; do [ -e "$n" ] || continue
    rc="$rc
## Run card
$(cat "$n")"; done
fi

cd "$ARENA"
# per-unit isolated HOME/DB (never the human main DB; L-isolation law), seeded
# from the PROVISIONED internal home's provider config (local-qwen baseURL etc).
UHOME="$ARENA_ROOT/$unit_id.home"; rm -rf "$UHOME"; mkdir -p "$UHOME/.config" "$UHOME/.local/share/opencode"
cp -r /home/lab/workspace/pcb-control/internal-home/.config/opencode "$UHOME/.config/" 2>/dev/null || true
rm -rf "$UHOME/.config/opencode/node_modules" "$UHOME/.local/share/opencode/opencode.db" 2>/dev/null || true
DB="$UHOME/.local/share/opencode/opencode.db"

# THE TEAM IS THE SUBJECT: mount the PCB role tree into the arena cwd so
# `--agent pcb-orchestrator` resolves. Role provenance is the genome seam:
# if the candidate tree carries agents/*.md (a mutation to the team itself),
# those files WIN over the canonical internal-control copies.
mkdir -p "$ARENA/.opencode/agents"
cp /home/lab/workspace/pcb-control/internal-control/.opencode/agents/*.md "$ARENA/.opencode/agents/"
if [ -d "$repo_root/agents" ] && ls "$repo_root"/agents/*.md >/dev/null 2>&1; then
  cp -f "$repo_root"/agents/*.md "$ARENA/.opencode/agents/"
  echo "role-provenance: candidate-tree agents override canonical" >&2
fi

RUNENV=(env -i PATH="$PATH" LANG=C.UTF-8 TERM=xterm-256color HOME="$UHOME"
  XDG_DATA_HOME="$UHOME/.local/share" XDG_CACHE_HOME="$UHOME/.cache" XDG_STATE_HOME="$UHOME/.local/state"
  OPENCODE_DB="$DB" KICAD_SHARE_DIR=/home/lab/.local/AppDir/share/kicad)

# FAIL-CLOSED SELF-PROOF GATE: the named agent must actually resolve BEFORE we
# spend a rep. "agent not found. Falling back to default" voids the rep — that
# is precisely the channel-dead noise theater the lane forbids.
"${RUNENV[@]}" opencode agent list >"$ARENA/.agent-list.txt" 2>&1
grep -q "pcb-orchestrator" "$ARENA/.agent-list.txt" || {
  echo "RUNNER_GATE_FAIL: pcb-orchestrator not in resolved agent inventory" >&2
  tail -5 "$ARENA/.agent-list.txt" >&2
  exit 1
}

timeout "${PCB_RUN_TIMEOUT:-2400}" "${RUNENV[@]}" \
  opencode run --agent pcb-orchestrator --format json \
  --dir "$ARENA" -- "$BRIEF$rc" > "$TRANSCRIPT" 2>"$ARENA/.run-stderr" || true

if [ ! -s "$TRANSCRIPT" ]; then
  echo "RUNNER_INFRA_FAIL: empty transcript (see $ARENA/.run-stderr)" >&2
  exit 1
fi
# mechanical role attribution proof: the bench session in the isolated DB MUST
# be owned by pcb-orchestrator (transcript lines carry no agent field; the DB
# session table does). No proof = void rep, never a scored fallback run.
ROLE_OK="$(sqlite3 "$DB" "SELECT COUNT(*) FROM session WHERE agent='pcb-orchestrator';" 2>/dev/null || echo 0)"
[ "${ROLE_OK:-0}" -ge 1 ] || { echo "RUNNER_INFRA_FAIL: no pcb-orchestrator session in $DB (fallback-agent run would be noise theater)" >&2; exit 1; }

turns=$(grep -c '"type":"text"' "$TRANSCRIPT" 2>/dev/null || true); turns="${turns:-0}"
tokens=$(python3 - "$TRANSCRIPT" <<'EOF' 2>/dev/null | tail -1 || true
import json,sys
n=0
for l in open(sys.argv[1]):
    try: d=json.loads(l)
    except Exception: continue
    p=d.get("part",{})
    if p.get("type")=="text": n+=len(p.get("text",""))
print(n//4)
EOF
); tokens="${tokens:-0}"
echo "arena=$ARENA" > "$ARENA_ROOT/$unit_id.arena"
python3 -c "import json,re;t=int(re.sub(r'[^0-9]','',str('$tokens')) or 0);u=int(re.sub(r'[^0-9]','',str('$turns')) or 0);print(json.dumps({'tokensEst':t,'turns':u}))"
