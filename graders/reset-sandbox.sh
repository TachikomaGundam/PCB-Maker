#!/usr/bin/env bash
# Reset hook (pcb-agent): honest no-op. Freshness is guaranteed at run time —
# run-scenario.sh re-seeds the arena (rm -rf + copy pristine starter kit) at the
# top of EVERY rep, so back-to-back generations are state-equal without a
# separate wipe. Kept as an explicit file so the contract is visible, not empty.
set -euo pipefail
echo "RESET-NOOP (per-rep reseed happens in run-scenario.sh)"
