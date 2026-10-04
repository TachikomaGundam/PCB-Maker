#!/usr/bin/env bash
# Mutator wrapper for the historian live run (task 14). Invoked by the run-loop
# as `bash mutate.sh <brief-file> <worktree> <model>` with cwd = the throwaway
# launch worktree (reflect.ts contract). The REAL candidate source is a headless
# `opencode run` child: it reads the reflection brief and proposes exactly one
# mutation — a new RUN CARD under abathur-notes/ (never a sealed path;
# kernel.immutableGlobs is enforced independently by the driver's PathPolicy).
# Run cards are the delivery seam (S4): run-scenario.sh appends them VERBATIM to
# every scenario brief under a `## Run card` heading, so a candidate tree's
# mutation genuinely steers the benched agent and score deltas are attributable.
# The wrapper deterministically packages the model's run card as a unified CREATE
# diff (creation diffs have no context to drift) and appends a genome.jsonc
# create-diff carrying the resolved spec bytes (plan 184: every sealed tree
# must contain genome.jsonc so bundle export self-describes; plan 181 requires
# it for the lineage). On unparseable model output the wrapper degrades to a
# packaging-only candidate — honest, logged, never a fabricated mutation.
set -uo pipefail
brief_file="${1:?usage: mutate.sh <brief-file> <worktree> <model>}"
worktree="${2:?usage: mutate.sh <brief-file> <worktree> <model>}"
model="${3:?usage: mutate.sh <brief-file> <worktree> <model>}"
# the published engine does not export ABATHUR_GENOME_CANONICAL; derive from the
# launch worktree's own genome.jsonc (written by the engine each round). Env wins
# when present; missing-both still fail-closes on the [ -f "$canonical" ] guard.
canonical="${ABATHUR_GENOME_CANONICAL:-$worktree/genome.jsonc}"
[ -f "$brief_file" ] || { echo "mutate: missing brief $brief_file" >&2; exit 1; }
cp -f "$brief_file" "${ABATHUR_MUTATOR_RAW:-/tmp/abathur-mutate-raw.jsonl}.brief" 2>/dev/null || true
[ -f "$canonical" ] || { echo "mutate: missing canonical spec $canonical" >&2; exit 1; }
bin="${ABATHUR_OPENCODE_BIN:-opencode}"

ptfile="$(mktemp /tmp/abathur-mutate-prompt.XXXXXX)"
cat > "$ptfile" <<'PROMPT_EOF'
You are the genome mutator of the Abathur evolution harness, PCB-agent lane. Read the reflection brief below (evidence from the incumbent bench of the pcb-agent genome: the PCB team run log, FINDINGS.md, and the grader OUTCOME/EYES metrics). Propose exactly ONE improvement: create a NEW RUN CARD under abathur-notes/ (slug .md). The run card is appended VERBATIM to the team task brief at bench time — write direct, actionable engineering guidance the PCB orchestrator team can follow. TARGET THE EYES GAP: if the grader shows traps the team hit but never NAMED (trap_coverage low while outcome partial), the card must teach the DISCOVERY PROCEDURE (how to notice this class of defect yourself), not the pasted answer — an answer scores once and dies; a discovery method evolves the team. Prefer converting one observed failure into a check the team can run itself. Output ONLY a single JSON object, no prose, shape:
{"rationale": "<one sentence, <=400 chars>", "path": "abathur-notes/<slug>.md", "content": "<full markdown file contents>"}
Do not modify any other path. Scenarios/, README.md and genome.jsonc are immutable; board tooling lives in the arena, not the genome tree.

BRIEF:
PROMPT_EOF
cat "$brief_file" >> "$ptfile"
prompt="$(cat "$ptfile")"
rm -f "$ptfile"

raw="${ABATHUR_MUTATOR_RAW:-/tmp/abathur-mutate-raw.jsonl}"
"$bin" run --model "$model" --format json -- "$prompt" >"$raw" 2>/dev/null
rc=$?
echo "mutate: opencode rc=$rc raw=$raw" >&2

python3 - "$raw" "$canonical" "$rc" "$worktree" <<'PY'
import json, os, re, sys

raw, canonical_path, rc, worktree = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]

def create_diff(path, text):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    body = "".join("+" + ln + "\n" for ln in lines)
    return f"--- /dev/null\n+++ b/{path}\n@@ -0,0 +1,{len(lines)} @@\n{body}"

def last_text_events(path):
    texts = []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue
                part = ev.get("part") or {}
                if ev.get("type") == "text" and isinstance(part.get("text"), str):
                    texts.append(part["text"])
    except FileNotFoundError:
        pass
    return texts

proposal = None
for text in reversed(last_text_events(raw)):
    candidate = text.strip()
    fence = re.search(r"```(?:json)?\s*(\{.*\})\s*```", candidate, re.S)
    if fence:
        candidate = fence.group(1)
    end = candidate.rfind("}")
    if end < 0:
        continue
    # prose preambles can contain set-notation braces like {症状/Symptoms, ...} —
    # the first '{' is not necessarily JSON; try every open brace from the LAST
    # backwards so the outermost-to-last-close object wins when one parses.
    opens = [i for i, ch in enumerate(candidate) if ch == "{" and i < end]
    doc = None
    for start in reversed(opens):
        try:
            parsed = json.loads(candidate[start : end + 1])
        except ValueError:
            continue
        if isinstance(parsed, dict):
            doc = parsed
            break
    if doc is not None:
        proposal = doc
        break

spec_text = open(canonical_path, encoding="utf-8").read()
if not spec_text.endswith("\n"):
    spec_text += "\n"
# genome.jsonc in the base tree was written by this wrapper's own prior round,
# so a replace-all modify hunk always anchors deterministically at line 1.
# A CREATE here would break apply the moment the file lands in the base (udiff
# refuses create-over-existing and discards the WHOLE candidate).
gen_path = os.path.join(worktree, "genome.jsonc")
try:
    with open(gen_path, encoding="utf-8") as fh:
        base_text = fh.read()
except FileNotFoundError:
    packaging = create_diff("genome.jsonc", spec_text)
except OSError as err:
    sys.stderr.write("mutate: genome.jsonc unreadable: %s\n" % err)
    sys.exit(3)
else:
    if base_text == spec_text:
        packaging = None
    else:
        base_body = base_text.split("\n")
        if base_body and base_body[-1] == "":
            base_body.pop()
        old_h = "".join("-" + ln + "\n" for ln in base_body)
        new_h = "".join("+" + ln + "\n" for ln in spec_text.split("\n")[:-1])
        packaging = (
            "--- a/genome.jsonc\n+++ b/genome.jsonc\n"
            "@@ -1,%d +1,%d @@\n%s%s" % (len(base_body), len(spec_text.split("\n")) - 1, old_h, new_h)
        )

if isinstance(proposal, dict):
    path = proposal.get("path")
    content = proposal.get("content")
    rationale = proposal.get("rationale")
    if (
        isinstance(path, str)
        and re.fullmatch(r"abathur-notes/[a-z0-9][a-z0-9._-]{0,63}\.md", path)
        and isinstance(content, str)
        and 0 < len(content) < 200000
        and isinstance(rationale, str)
        and 0 < len(rationale) <= 4000
        and "\x00" not in content
    ):
        content = content.replace("\r", "")
        if not content.endswith("\n"):
            content += "\n"
        diffs = [create_diff(path, content)] + ([packaging] if packaging else [])
        candidate = {"id": "mutate-live", "rationale": rationale, "diffs": diffs}
        print(json.dumps({"candidates": [candidate]}))
        sys.exit(0)

if packaging:
    print(json.dumps({
        "candidates": [{
            "id": "mutate-package-only",
            "rationale": "packaging-only candidate: model output unparseable or path rejected (opencode rc=%d); lineage genome.jsonc added, no skill mutation proposed" % rc,
            "diffs": [packaging],
        }]
    }))
else:
    print(json.dumps({"candidates": []}))
PY
