#!/usr/bin/env bash
set -euo pipefail
umask 077

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  qa-run.sh <client> <repo-url> <branch> <base-branch> [stage-url] [extra prompt]
  qa-run.sh --feature "<what to check>" <client> <repo-url> <branch> <stage-url> [extra prompt]
  qa-run.sh --full <client> <repo-url> <branch> <stage-url> [extra prompt]
USAGE
  exit 64
}

QA_MODE=change
QA_FEATURE=
case "${1:-}" in
  --feature)
    (( $# >= 2 )) || usage
    QA_MODE=feature
    QA_FEATURE="$2"
    shift 2
    ;;
  --full)
    QA_MODE=full
    shift
    ;;
  -*) usage ;;
esac

if [[ "$QA_MODE" == change ]]; then
  (( $# >= 4 && $# <= 6 )) || usage
else
  (( $# >= 4 && $# <= 5 )) || usage
fi
source "$HERE/qa-common.sh"

if [[ "$QA_MODE" == change ]]; then
  CLIENT="$1" URL="$2" BRANCH="$3" BASE="$4"
  STAGE="${5:-}" EXTRA="${6:-}"
else
  CLIENT="$1" URL="$2" BRANCH="$3" BASE=
  STAGE="$4" EXTRA="${5:-}"
fi

[[ "$CLIENT" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$ ]] || qa_die 'Invalid client name'
[[ "$URL" != -* ]] || qa_die 'Invalid repository URL'

python3 - "$URL" <<'PY'
import sys, urllib.parse
u = urllib.parse.urlsplit(sys.argv[1])
if u.scheme in ('https', 'http') and (u.username or u.password):
    raise SystemExit('ERROR: use a deploy key or credential helper, not credentials in the URL')
PY

git check-ref-format "refs/heads/$BRANCH" >/dev/null
[[ "$BRANCH" != -* ]] || qa_die 'Invalid branch name'
if [[ "$QA_MODE" == change ]]; then
  git check-ref-format "refs/heads/$BASE" >/dev/null
  [[ "$BASE" != -* ]] || qa_die 'Invalid branch name'
fi

if [[ "$QA_MODE" == feature ]]; then
  [[ -n "${QA_FEATURE//[[:space:]]/}" ]] || qa_die 'Feature description is empty'
  (( ${#QA_FEATURE} <= 500 )) || qa_die 'Feature description is longer than 500 characters'
  [[ "$QA_FEATURE" != *$'\n'* && "$QA_FEATURE" != *$'\r'* ]] \
    || qa_die 'Feature description must be one line'
fi

if [[ "$QA_MODE" != change ]]; then
  python3 - "$STAGE" <<'PY'
import sys, urllib.parse
raw = sys.argv[1]
u = urllib.parse.urlsplit(raw)
if (u.scheme != 'https' or not u.hostname or u.username or u.password
        or any(c.isspace() for c in raw)):
    raise SystemExit('ERROR: stage-url must be an https:// URL without credentials or spaces')
PY
fi

QA_FULL_MAX_CASES="${QA_FULL_MAX_CASES:-60}"
QA_FULL_MAX_ROUNDS="${QA_FULL_MAX_ROUNDS:-8}"
if [[ "$QA_MODE" == full ]]; then
  [[ "$QA_FULL_MAX_CASES" =~ ^[1-9][0-9]{0,2}$ ]] || qa_die 'QA_FULL_MAX_CASES must be 1 to 999'
  [[ "$QA_FULL_MAX_ROUNDS" =~ ^[1-9][0-9]?$ ]] || qa_die 'QA_FULL_MAX_ROUNDS must be 1 to 99'
fi

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
[[ "$QA_MODE" == change ]] || SLUG="$QA_MODE-$SLUG"

mkdir -p "$QA_ROOT/runs/$CLIENT"
RUN_DIR="$(mktemp -d "$QA_ROOT/runs/$CLIENT/$(date -u +%Y%m%dT%H%M%SZ)-${SLUG:0:64}-XXXXXX")"
CONTAINER_NAME="qa-$(basename "$RUN_DIR" | tr '[:upper:]' '[:lower:]')"
mkdir -p "$RUN_DIR/claude-home" "$RUN_DIR/reports"
printf 'RUN_DIR=%s\n' "$RUN_DIR"

git clone --no-single-branch --branch "$BRANCH" -- "$URL" "$RUN_DIR/repo" >> "$RUN_DIR/run.log" 2>&1
if [[ "$QA_MODE" == change ]]; then
  git -C "$RUN_DIR/repo" fetch origin "+refs/heads/$BASE:refs/remotes/origin/$BASE" >> "$RUN_DIR/run.log" 2>&1
  if [[ "$BRANCH" != "$BASE" ]]; then
    git -C "$RUN_DIR/repo" branch --force "$BASE" "refs/remotes/origin/$BASE" >> "$RUN_DIR/run.log" 2>&1
  fi
fi

[[ ! -L "$RUN_DIR/repo/.env.test" ]] || qa_die 'Refusing a symlink at repo/.env.test'
install -m 600 "$ENV_TEST" "$RUN_DIR/repo/.env.test"
mkdir -p "$RUN_DIR/repo/qa-reports/$REPORT_DATE/evidence" "$RUN_DIR/repo/qa-reports/$REPORT_DATE/screenshots"

# Coverage ledger from earlier runs: the lead reads it and skips what is covered and unchanged.
LEDGER="$QA_ROOT/clients/$CLIENT/coverage-ledger.md"
HAVE_LEDGER=0
if [[ -e "$LEDGER" || -L "$LEDGER" ]]; then
  [[ -f "$LEDGER" && ! -L "$LEDGER" ]] || qa_die 'Client coverage-ledger.md is not a regular file'
  install -m 600 "$LEDGER" "$RUN_DIR/repo/qa-reports/coverage-ledger.md"
  HAVE_LEDGER=1
fi

STATE_VARS=(CLIENT QA_IMAGE QA_AUTH QA_NETWORK QA_CPUS QA_MEMORY QA_MEMORY_SWAP QA_SHM REPORT_DATE CONTAINER_NAME QA_MODE)
[[ "$QA_MODE" != feature ]] || STATE_VARS+=(QA_FEATURE)
[[ "$QA_MODE" != full ]] || STATE_VARS+=(QA_FULL_MAX_CASES QA_FULL_MAX_ROUNDS)
for variable in "${STATE_VARS[@]}"; do
  printf '%s=%q\n' "$variable" "${!variable}" >> "$RUN_DIR/state.env"
done

if (( EUID == 0 )); then
  chown qa:qa "$QA_ROOT/runner.lock" "$QA_ROOT/runs/$CLIENT"
  chown -hR qa:qa "$RUN_DIR"
elif [[ "$(id -un)" != qa ]]; then
  qa_die 'Run as qa or root'
fi

case "$QA_MODE" in
  change)
    PROMPT="QA branch $BRANCH against $BASE. Stage URL: ${STAGE:-read .env.test}. $EXTRA"
    ;;
  feature)
    PROMPT="Feature mode. Check: $QA_FEATURE. Target: current behavior on $STAGE. There is no diff; do not compare branches. $EXTRA"
    ;;
  full)
    PROMPT="Full mode. Run a full QA pass of the web portal on $STAGE: build the portal module map from code and from the live stage, propose modules and budgets at the checkpoint, then execute module by module. There is no diff. Budgets: max $QA_FULL_MAX_CASES cases, max $QA_FULL_MAX_ROUNDS rounds per specialist per module. $EXTRA"
    ;;
esac
if (( HAVE_LEDGER )); then
  PROMPT+=" Previous coverage ledger: qa-reports/coverage-ledger.md; skip what it shows as covered and unchanged."
else
  PROMPT+=" No coverage ledger yet for this client."
fi
PROMPT+=" Write the updated coverage ledger to qa-reports/$REPORT_DATE/coverage-ledger.md together with the verdict."
PROMPT+=" This is a Linux server run: web and API only; mobile is out of scope. Use /work/repo/.env.test for test credentials; never print secrets. Use qa-reports/$REPORT_DATE/ for all reports. The first line of summary.md must be exactly GO, NO-GO, or GO WITH KNOWN ISSUES."

if [[ "${QA_NO_CHECKPOINT:-0}" == 1 ]]; then
  PROMPT+=' no checkpoint'
fi

qa_container "$RUN_DIR/plan.json" "$PROMPT"
printf '\nReports: %s/reports\n' "$RUN_DIR"

if [[ "${QA_NO_CHECKPOINT:-0}" == 1 ]]; then
  qa_finish
else
  printf 'Continue: %q %q\n' "$HERE/qa-go.sh" "$RUN_DIR"
fi
