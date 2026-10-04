#!/usr/bin/env bash
# seed-sandbox.sh — PCB bench per-unit arena seeding (evolution harness, NOT board work).
# Creates a fresh isolated arena and copies the STARTER tool kit + inputs only.
# The team's own improvements must land in tools-v2/ inside the arena; the seeded
# tools/ stay pristine so the grader can diff what the team actually changed.
set -euo pipefail
ARENA="${1:?usage: seed-sandbox.sh <arena-dir> <seed-src-dir>}"
SEED="${2:?seed source dir (graders/pcb-agent/seed)}"
rm -rf "$ARENA"; mkdir -p "$ARENA/tools" "$ARENA/fab-out"
cp "$SEED"/tools/*.py "$SEED"/tools/*.sh "$ARENA/tools/"
cp "$SEED"/spec.json "$SEED"/esp32s3-r12-BRIEF.txt "$ARENA/"
chmod +w "$ARENA/tools/"* 2>/dev/null || true
echo "SEEDED arena=$ARENA tools=$(ls "$ARENA/tools" | wc -l) inputs=$(ls "$ARENA"/*.json "$ARENA"/*.txt | wc -l)"
