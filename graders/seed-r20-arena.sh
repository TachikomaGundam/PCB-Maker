#!/usr/bin/env bash
# r20 production-topology bench arena: FULL launcher + plugin + gates running
# against a candidate tree. Method: copy the control tree minus bulk, then
# rewrite ONLY the launcher's CONTROL_ROOT literal to the arena (sed-verified
# single-line patch; every gate expression stays byte-identical, they just
# evaluate on the candidate tree — this is the honest quarantine).
# Usage: seed-r20-arena.sh <arena-root> <candidate-worktree-or-empty>
set -euo pipefail
ARENA="${1:?arena root}"; CAND="${2:-}"
SRC=/home/lab/workspace/pcb-control
rm -rf "$ARENA"; mkdir -p "$ARENA"
# bulk exclusions: reports/evidence are outputs, checkpoints/dispatches are state,
# node_modules + hermetic bin get symlinked (110MB, content-identical).
tar -C "$SRC" \
  --exclude='./reports' --exclude='./evidence-links' --exclude='./state' \
  --exclude='./dispatches' --exclude='./fixtures' --exclude='./node_modules' \
  --exclude='*/node_modules' --exclude='./profiles/production/bin' \
  --exclude='./.git' -cf - . | tar -C "$ARENA" -xf -
mkdir -p "$ARENA/state/capabilities" "$ARENA/reports/recovery" "$ARENA/fixtures" "$ARENA/dispatches"
# bin + node_modules: NO copies, NO links — r20-bench.sh stacks host ro-binds at
# their literals inside the sandbox. Remove any stale self-looping links from
# earlier seed versions so the mount points and the find-scan stay honest.
rm -f "$ARENA/profiles/production/bin"
find "$ARENA" -maxdepth 6 -type l -name node_modules -delete
find "$ARENA" -maxdepth 6 -xtype l -delete   # dangling links only
# bwrap model: ARENA is bind-mounted AT $SRC inside the sandbox; every literal
# path (launcher CONTROL_ROOT, plugin profileOf, overlay plugin dirs) holds with
# zero edits. production-home is copied wholesale (config-home input; per v3
# lesson a degraded copy fails G1 — so copy everything and re-link vendored
# node_modules below); writes still land only under $SRC (bind-mounted arena)
# and /tmp.
# overlay keeps ABSOLUTE src paths: inside bwrap those literals ARE the arena (bind-mounted). No rewrite.
# candidate overlay: genome delivery = role files (+ plugin if a candidate ships one)
if [ -n "$CAND" ]; then
  [ -d "$CAND/agents" ] && for t in internal-control production-console user-console; do
    mkdir -p "$ARENA/$t/.opencode/agents"; cp -f "$CAND"/agents/*.md "$ARENA/$t/.opencode/agents/" 2>/dev/null || true; done
  [ -f "$CAND/plugins/pcb-control-plane.ts" ] && cp -f "$CAND/plugins/pcb-control-plane.ts" "$ARENA/profiles/production/plugins/pcb-control-plane.ts"
  [ -f "$CAND/launch-pins.json" ] && cp -f "$CAND/launch-pins.json" "$ARENA/profiles/production/launch-pins.json"
fi
# the single-line root rewrite is GONE (bwrap keeps literals; see header note)
# after plugin swap, re-pin plugin_sha256 + drop integrity-window notes that bind arena to src
python3 - "$ARENA" <<'PY'
import sys, os, json, hashlib
arena = sys.argv[1]
pins_path = os.path.join(arena, "profiles/production/launch-pins.json")
plg = os.path.join(arena, "profiles/production/plugins/pcb-control-plane.ts")
d = json.load(open(pins_path))
d["plugin_sha256"] = hashlib.sha256(open(plg,"rb").read()).hexdigest()
json.dump(d, open(pins_path,"w"), indent=2); open(pins_path,"a").write("\n")
PY
L="$ARENA/tools/start_production_orchestrator_ui.sh"
grep -c 'CONTROL_ROOT="/home/lab/workspace/pcb-control"' "$L" | grep -qx 1 || { echo "SEED_FAIL: CONTROL_ROOT literal changed shape"; exit 1; }
bash -n "$L"
echo "ARENA_SEEDED $ARENA plugin=$(sha256sum "$ARENA/profiles/production/plugins/pcb-control-plane.ts" | cut -c1-12)"
# mission inputs (r26 F-001/F-002): seed declares them — copy the named fixture pair into the orchestrator cwd
# mission inputs (r26 findings F-001/F-002): the scenario text names these; seed must place them
SEEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/seed"
cp -f "$SEEDIR/spec.json" "$ARENA/production-console/spec.json"
cp -f "$SEEDIR/esp32s3-r12-BRIEF.txt" "$ARENA/production-console/BRIEF.txt"
test -s "$ARENA/production-console/spec.json" && test -s "$ARENA/production-console/BRIEF.txt" || { echo SEED_FAIL: mission inputs missing; exit 1; }
