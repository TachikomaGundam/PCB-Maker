#!/usr/bin/env bash
# r20 production-topology bench sandbox: runs a command INSIDE bwrap where the
# arena is bind-mounted AT the control literal, with host-vendored dirs re-bound
# over the arena's excluded gaps (bind-mounts stack: later wins).
# Usage: r20-bench.sh <arena> -- <inner command...>
set -euo pipefail
ARENA="${1:?arena}"; shift; [ "${1:-}" = "--" ] && shift
SRC=/home/lab/workspace/pcb-control
LIT=$SRC   # the literal path the control plane believes itself to be
# v8 netns ABANDONED: lo cannot be raised in this unprivileged userns (EPERM).
# Isolation strategy instead: arena bind at the literal (fs) + PCB_PRODUCTION_SERVE_PORT
# exported to a FREE host port (net coexistence; data dirs are the arena's, so the
# bench serve cannot touch the real lane state; verified by G5 record tuple).
PORT=$(python3 -c "import socket;s=socket.socket();s.bind((\"127.0.0.1\",0));print(s.getsockname()[1]);s.close()")
ARGS=(--ro-bind / / --dev-bind /dev /dev --proc /proc --bind /tmp /tmp
      --bind "$ARENA" "$LIT" --unshare-pid --setenv PCB_PRODUCTION_SERVE_PORT "$PORT")
# vendored opencode binary (excluded from arena tar; must appear AT the literal)
ARGS+=(--ro-bind "$SRC/profiles/production/bin" "$LIT/profiles/production/bin")
# every vendored node_modules under the control tree (typescript for the loader,
# production-home caches carrying OMO/ACP/HR packages) — ro at their literals
while IFS= read -r -d '' d; do
  rel="${d#$SRC}"
  [ -d "$ARENA$rel" ] && continue   # arena copy exists: leave it (candidate-owned)
  mkdir -p "$ARENA$(dirname "$rel")" 2>/dev/null || true
  ARGS+=(--ro-bind "$d" "$LIT$rel")
done < <(find "$SRC" -maxdepth 6 -name node_modules -type d -print0)
exec bwrap "${ARGS[@]}" -- /bin/bash -c "$*"
