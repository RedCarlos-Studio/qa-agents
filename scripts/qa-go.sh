#!/usr/bin/env bash
set -euo pipefail
umask 077

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if (( $# < 1 || $# > 2 )); then
  echo 'Usage: qa-go.sh <run-dir> [reply]'
  exit 64
fi

QA_ROOT="${QA_ROOT:-/srv/qa}"
RUN_DIR="$(realpath -- "$1")"
[[ "$RUN_DIR" == "$QA_ROOT/runs/"* ]] || {
  echo 'ERROR: run-dir must be under QA_ROOT/runs' >&2
  exit 70
}
[[ -f "$RUN_DIR/state.env" && -f "$RUN_DIR/session" && -d "$RUN_DIR/repo" ]] || {
  echo 'ERROR: run is incomplete or cleaned' >&2
  exit 70
}

AUTH_OVERRIDE="${QA_AUTH:-}"
source "$RUN_DIR/state.env"
[[ -z "$AUTH_OVERRIDE" ]] || QA_AUTH="$AUTH_OVERRIDE"
source "$HERE/qa-common.sh"
qa_auth "$CLIENT"

exec 9> "$QA_ROOT/runner.lock"
if (( EUID == 0 )); then chown qa:qa "$QA_ROOT/runner.lock"; fi
flock -n 9 || qa_die 'Another QA run is active on this server'

SESSION="$(cat "$RUN_DIR/session")"
python3 - "$SESSION" <<'PY'
import sys, uuid
uuid.UUID(sys.argv[1])
PY

RESULT="$RUN_DIR/reply-$(date -u +%Y%m%dT%H%M%S)-$$.json"
qa_container "$RESULT" "${2:-go}" --resume "$SESSION"
printf '\nReports: %s/reports\n' "$RUN_DIR"
qa_verdict
