#!/usr/bin/env bash
set -euo pipefail
umask 077

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if (( $# < 4 || $# > 6 )); then
  echo 'Usage: qa-run.sh <client> <repo-url> <branch> <base-branch> [stage-url] [extra prompt]'
  exit 64
fi
source "$HERE/qa-common.sh"

CLIENT="$1" URL="$2" BRANCH="$3" BASE="$4"
[[ "$CLIENT" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$ ]] || qa_die 'Invalid client name'
[[ "$URL" != -* ]] || qa_die 'Invalid repository URL'

python3 - "$URL" <<'PY'
import sys, urllib.parse
u = urllib.parse.urlsplit(sys.argv[1])
if u.scheme in ('https', 'http') and (u.username or u.password):
    raise SystemExit('ERROR: use a deploy key or credential helper, not credentials in the URL')
PY

git check-ref-format "refs/heads/$BRANCH" >/dev/null
git check-ref-format "refs/heads/$BASE" >/dev/null
[[ "$BRANCH" != -* && "$BASE" != -* ]] || qa_die 'Invalid branch name'
qa_auth "$CLIENT"

ENV_TEST="$QA_ROOT/clients/$CLIENT/env.test"
[[ -f "$ENV_TEST" && ! -L "$ENV_TEST" ]] || qa_die 'Client env.test missing or is a symlink'
[[ "$(stat -c %a "$ENV_TEST")" == 600 ]] || qa_die 'Client env.test must have mode 0600'

QA_NETWORK=bridge
if [[ -f "$QA_ROOT/clients/$CLIENT/network" ]]; then
  QA_NETWORK="$(cat "$QA_ROOT/clients/$CLIENT/network")"
fi
[[ "$QA_NETWORK" =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ ]] || qa_die 'Invalid Docker network name'

QA_IMAGE="${QA_IMAGE:-redcarlos/qa-agents:$(git -C "$HERE/.." rev-parse --short HEAD)}"
QA_IMAGE="$(docker image inspect --format '{{.Id}}' "$QA_IMAGE")"

exec 9> "$QA_ROOT/runner.lock"
if (( EUID == 0 )); then chown qa:qa "$QA_ROOT/runner.lock"; fi
flock -n 9 || qa_die 'Another QA run is active on this server'

REPORT_DATE="$(TZ=Europe/Kyiv date +%F)"
SLUG="${BRANCH//\//-}"
SLUG="$(printf '%s' "$SLUG" | tr -c 'a-zA-Z0-9._-' '-')"

mkdir -p "$QA_ROOT/runs/$CLIENT"
RUN_DIR="$(mktemp -d "$QA_ROOT/runs/$CLIENT/$(date -u +%Y%m%dT%H%M%SZ)-${SLUG:0:64}-XXXXXX")"
CONTAINER_NAME="qa-$(basename "$RUN_DIR" | tr '[:upper:]' '[:lower:]')"
mkdir -p "$RUN_DIR/claude-home" "$RUN_DIR/reports"
printf 'RUN_DIR=%s\n' "$RUN_DIR"

git clone --no-single-branch --branch "$BRANCH" -- "$URL" "$RUN_DIR/repo" >> "$RUN_DIR/run.log" 2>&1
git -C "$RUN_DIR/repo" fetch origin "+refs/heads/$BASE:refs/remotes/origin/$BASE" >> "$RUN_DIR/run.log" 2>&1
if [[ "$BRANCH" != "$BASE" ]]; then
  git -C "$RUN_DIR/repo" branch --force "$BASE" "refs/remotes/origin/$BASE" >> "$RUN_DIR/run.log" 2>&1
fi

[[ ! -L "$RUN_DIR/repo/.env.test" ]] || qa_die 'Refusing a symlink at repo/.env.test'
install -m 600 "$ENV_TEST" "$RUN_DIR/repo/.env.test"
mkdir -p "$RUN_DIR/repo/qa-reports/$REPORT_DATE/evidence" "$RUN_DIR/repo/qa-reports/$REPORT_DATE/screenshots"

for variable in CLIENT QA_IMAGE QA_AUTH QA_NETWORK QA_CPUS QA_MEMORY QA_MEMORY_SWAP QA_SHM REPORT_DATE CONTAINER_NAME; do
  printf '%s=%q\n' "$variable" "${!variable}" >> "$RUN_DIR/state.env"
done

if (( EUID == 0 )); then
  chown qa:qa "$QA_ROOT/runner.lock" "$QA_ROOT/runs/$CLIENT"
  chown -hR qa:qa "$RUN_DIR"
elif [[ "$(id -un)" != qa ]]; then
  qa_die 'Run as qa or root'
fi

PROMPT="QA branch $BRANCH against $BASE. Stage URL: ${5:-read .env.test}. ${6:-}"
PROMPT+=" This is a Linux server run: web and API only; mobile is out of scope. Use /work/repo/.env.test for test credentials; never print secrets. Use qa-reports/$REPORT_DATE/ for all reports. The first line of summary.md must be exactly GO, NO-GO, or GO WITH KNOWN ISSUES."

if [[ "${QA_NO_CHECKPOINT:-0}" == 1 ]]; then
  PROMPT+=' no checkpoint'
fi

qa_container "$RUN_DIR/plan.json" "$PROMPT"
printf '\nReports: %s/reports\n' "$RUN_DIR"

if [[ "${QA_NO_CHECKPOINT:-0}" == 1 ]]; then
  qa_verdict
else
  printf 'Continue: %q %q\n' "$HERE/qa-go.sh" "$RUN_DIR"
fi
