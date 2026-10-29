#!/usr/bin/env bash
set -euo pipefail

QA_ROOT="${QA_ROOT:-/srv/qa}"
QA_AUTH="${QA_AUTH:-subscription}"
QA_CPUS="${QA_CPUS:-2}"
QA_MEMORY="${QA_MEMORY:-4g}"
QA_MEMORY_SWAP="${QA_MEMORY_SWAP:-$QA_MEMORY}"
QA_SHM="${QA_SHM:-1g}"

qa_die() { printf 'ERROR: %s\n' "$*" >&2; exit 70; }

qa_auth() {
  local client="$1"
  case "$QA_AUTH" in
    subscription) QA_AUTH_FILE="$QA_ROOT/secrets/claude.env" ;;
    api) QA_AUTH_FILE="$QA_ROOT/clients/$client/anthropic.env" ;;
    *) qa_die 'QA_AUTH must be subscription or api' ;;
  esac
  python3 - "$QA_AUTH_FILE" "$QA_AUTH" <<'PY'
import stat, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.is_file() or p.is_symlink():
    raise SystemExit('ERROR: authentication file missing or is a symlink: ' + str(p))
if stat.S_IMODE(p.stat().st_mode) != 0o600:
    raise SystemExit('ERROR: authentication file must have mode 0600')
values = {}
for line in p.read_text().splitlines():
    line = line.strip()
    if not line or line.startswith('#'): continue
    key, sep, value = line.partition('=')
    if not sep or key in values:
        raise SystemExit('ERROR: invalid or duplicate entry in authentication file')
    values[key] = value
expected = 'CLAUDE_CODE_OAUTH_TOKEN' if sys.argv[2] == 'subscription' else 'ANTHROPIC_API_KEY'
if set(values) != {expected} or not values.get(expected, '').strip():
    raise SystemExit('ERROR: authentication file must contain only the selected nonempty auth variable')
PY
}

qa_container() {
  local result="$1" prompt="$2"
  shift 2
  local rc=0
  printf '\n[%s] Starting Claude\n' "$(date -Is)" >> "$RUN_DIR/run.log"
  docker run --rm --init \
    --name "$CONTAINER_NAME" \
    --cpus "$QA_CPUS" --memory "$QA_MEMORY" \
    --memory-swap "$QA_MEMORY_SWAP" --shm-size "$QA_SHM" \
    --network "$QA_NETWORK" \
    --env-file "$QA_AUTH_FILE" \
    --mount "type=bind,src=$RUN_DIR/repo,dst=/work/repo" \
    --mount "type=bind,src=$RUN_DIR/claude-home,dst=/home/qa/.claude/projects" \
    "$QA_IMAGE" claude --agent qa-lead \
    --dangerously-skip-permissions --setting-sources user \
    --output-format json "$@" -p "$prompt" \
    > "$result" 2>> "$RUN_DIR/run.log" || rc=$?
  qa_result "$result" || { qa_collect || true; return 70; }
  qa_collect || return 70
  (( rc == 0 )) || return 70
}

qa_collect() {
  python3 - "$RUN_DIR" "$REPORT_DATE" <<'PY'
import shutil, sys
from pathlib import Path
run = Path(sys.argv[1])
source = run / 'repo' / 'qa-reports' / sys.argv[2]
if source.is_dir() and not source.is_symlink():
    shutil.copytree(source, run / 'reports', dirs_exist_ok=True, symlinks=True)
PY
}

qa_result() {
  python3 - "$1" "$RUN_DIR" "$QA_AUTH_FILE" <<'PY'
import json, sys, uuid
from pathlib import Path
result, run, auth = map(Path, sys.argv[1:])
secrets = [line.partition('=')[2] for line in auth.read_text().splitlines()
           if line and not line.startswith('#') and '=' in line]
def redact(text):
    for secret in secrets:
        if secret: text = text.replace(secret, '[REDACTED]')
    return text
log = run / 'run.log'
if log.exists():
    log.write_text(redact(log.read_text(errors='replace')))
raw = redact(result.read_text(errors='replace'))
result.write_text(raw)
with log.open('a') as f:
    f.write(raw + '\n')
try:
    data = json.loads(raw)
except ValueError:
    raise SystemExit('ERROR: no valid Claude JSON; inspect run.log')
if not isinstance(data, dict):
    raise SystemExit('ERROR: unexpected Claude JSON; inspect run.log')
session = data.get('session_id')
if session:
    uuid.UUID(session)
    (run / 'session').write_text(session + '\n')
print(str(data.get('result', '')))
if data.get('is_error') or not session:
    raise SystemExit('ERROR: Claude run failed; inspect run.log')
PY
}

qa_verdict() {
  python3 - "$RUN_DIR/reports/summary.md" <<'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.is_file() or p.is_symlink():
    print('ERROR: summary.md missing or is a symlink', file=sys.stderr)
    raise SystemExit(70)
try:
    first = next(iter(p.read_text().splitlines()), '').replace('**', '').strip().lstrip('# ').strip()
except (OSError, UnicodeError):
    print('ERROR: summary.md cannot be read', file=sys.stderr)
    raise SystemExit(70)
match = re.match(r'(?:Release verdict:\s*|Verdict:\s*)?(GO WITH KNOWN ISSUES|NO-GO|GO)(?=$|[\s:.,;—–-])', first, re.I)
if not match:
    print('ERROR: first line of summary.md has no recognized verdict', file=sys.stderr)
    raise SystemExit(70)
raise SystemExit({'GO': 0, 'NO-GO': 1, 'GO WITH KNOWN ISSUES': 2}[match[1].upper()])
PY
}
