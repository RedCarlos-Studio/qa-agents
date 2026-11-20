#!/usr/bin/env bash
# Run the QA agent team on a developer machine with Docker (macOS or Linux),
# without the server layout (/srv/qa, user qa, flock). Same image, same agents,
# same checkpoint, coverage ledger and verdict exit codes as qa-run.sh / qa-go.sh.
#
#   qa-local.sh start --full <client> <repo> <branch> <stage-url> [extra-prompt-file]
#   qa-local.sh start --feature "<what>" <client> <repo> <branch> <stage-url> [extra-prompt-file]
#   qa-local.sh go <run-dir> [reply]
#
# <repo> is a URL or a local path; a local path may name a remote-tracking
# branch (origin/<branch>) that the clone will check out as <branch>.
# Layout under QA_ROOT (default ~/qa-runs):
#   secrets/claude.env             CLAUDE_CODE_OAUTH_TOKEN=... (mode 600)
#   clients/<client>/env.test      stage URL and test accounts (mode 600)
#   clients/<client>/coverage-ledger.md, coverage-history/   (kept between runs)
#   runs/<client>/<run>/           clone, transcripts, reports, logs
#
# QA_RUNTIME=docker (default) runs Claude in the image and needs secrets/claude.env.
# QA_RUNTIME=native runs the host's logged-in `claude` in the run's clone, with the
# server agent set copied into <clone>/.claude/ and Playwright MCP from QA_TOOLS
# (default ~/qa-runs/tools: npm i --prefix ~/qa-runs/tools @playwright/mcp@0.0.83, then
# PLAYWRIGHT_BROWSERS_PATH=~/qa-runs/tools/browsers .../playwright install chromium).
# Native has no container isolation: agents run with --dangerously-skip-permissions
# as your user. Use it only on a machine where that is acceptable.
set -euo pipefail
umask 077

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export QA_ROOT="${QA_ROOT:-$HOME/qa-runs}"
QA_RUNTIME="${QA_RUNTIME:-docker}"
QA_TOOLS="${QA_TOOLS:-$QA_ROOT/tools}"
QA_CPUS="${QA_CPUS:-4}"
QA_MEMORY="${QA_MEMORY:-4g}"
QA_SHM="${QA_SHM:-1g}"
source "$HERE/qa-common.sh"

usage() { sed -n '5,8p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }

mode600() {
  python3 - "$1" <<'PY'
import stat, sys
from pathlib import Path
p = Path(sys.argv[1])
ok = p.is_file() and not p.is_symlink() and stat.S_IMODE(p.stat().st_mode) == 0o600
raise SystemExit(0 if ok else 1)
PY
}

lock() {
  mkdir -p "$QA_ROOT"
  mkdir "$QA_ROOT/runner.lock.d" 2>/dev/null || qa_die "Another local QA phase is running (remove $QA_ROOT/runner.lock.d if it is stale)"
  trap 'rmdir "$QA_ROOT/runner.lock.d" 2>/dev/null || true' EXIT
}

install_native_agents() {
  local dst="$RUN_DIR/repo/.claude" mcp chrome
  mcp="$QA_TOOLS/node_modules/.bin/playwright-mcp"
  chrome="$(find "$QA_TOOLS/browsers" -maxdepth 6 -type f -perm -u+x \
    \( -name 'Google Chrome for Testing' -o -name chrome \) -path '*chromium-*' 2>/dev/null | head -1)"
  [[ -x "$mcp" && -n "$chrome" ]] || qa_die "Playwright MCP or Chromium missing under $QA_TOOLS (see header)"
  mkdir -p "$dst/agents"
  cp "$HERE/../agents/qa-lead.md" "$HERE/../agents/qa-runner.md" "$HERE/../agents/qa-api.md" "$dst/agents/"
  cp "$HERE/../agents/qa-rules.md" "$dst/qa-rules.md"
  # Agent-frontmatter MCP servers do not load in this mode; the server is passed to the
  # whole session with --mcp-config instead, so the agent copy drops its own block.
  python3 - "$HERE/../agents/qa-web-server.md" "$dst/agents/qa-web.md" "$RUN_DIR/mcp.json" "$mcp" "$chrome" <<'PY'
import json, re, sys
src, dst, cfg, mcp, chrome = sys.argv[1:]
text = open(src).read()
text, n = re.subn(r'mcpServers:\n(?:  .*\n)+', '', text, count=1)
if n != 1:
    raise SystemExit('ERROR: mcpServers block not found in qa-web-server.md')
text = text.replace('/work/repo/.env.test', '.env.test').replace('~/.claude/qa-rules.md', '.claude/qa-rules.md')
open(dst, 'w').write(text)
json.dump({'mcpServers': {'playwright': {'type': 'stdio', 'command': mcp,
           'args': ['--headless', '--isolated', '--executable-path', chrome]}}}, open(cfg, 'w'), indent=1)
PY
  printf '/.claude/\n' >> "$RUN_DIR/repo/.git/info/exclude"
}

run_claude() {
  local result="$1" prompt="$2"; shift 2
  if [[ "$QA_RUNTIME" == docker ]]; then
    qa_container "$result" "$prompt" "$@"
    return
  fi
  local rc=0
  printf '\n[%s] Starting native Claude\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$RUN_DIR/run.log"
  ( cd "$RUN_DIR/repo" && exec env -u CLAUDE_AGENT_SDK_MCP_NO_PREFIX -u CLAUDE_CODE_CHILD_SESSION \
      caffeinate -i "${QA_CLAUDE_BIN:-claude}" --agent qa-lead \
      --mcp-config "$RUN_DIR/mcp.json" --strict-mcp-config \
      --dangerously-skip-permissions --setting-sources project \
      --output-format json "$@" -p "$prompt" ) > "$result" 2>> "$RUN_DIR/run.log" || rc=$?
  qa_result "$result" || { qa_collect || true; return 70; }
  qa_collect || return 70
  (( rc == 0 )) || return 70
}

refresh_env() {
  local env_test="$QA_ROOT/clients/$CLIENT/env.test"
  mode600 "$env_test" || qa_die "$env_test missing, a symlink, or not mode 600"
  [[ ! -L "$RUN_DIR/repo/.env.test" ]] || qa_die 'Refusing a symlink at repo/.env.test'
  if ! cmp -s "$env_test" "$RUN_DIR/repo/.env.test" 2>/dev/null; then
    install -m 600 "$env_test" "$RUN_DIR/repo/.env.test"
    printf 'env.test copied from %s\n' "$env_test"
  fi
}

cmd_start() {
  local mode feature=''
  case "${1:-}" in
    --full) mode=full; shift ;;
    --feature) (( $# >= 2 )) || usage; mode=feature; feature="$2"; shift 2 ;;
    *) usage ;;
  esac
  (( $# >= 4 && $# <= 5 )) || usage
  CLIENT="$1"; local repo="$2" branch="$3" stage="$4" extra_file="${5:-}"
  [[ "$CLIENT" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$ ]] || qa_die 'Invalid client name'
  git check-ref-format "refs/heads/$branch" >/dev/null || qa_die 'Invalid branch name'
  python3 - "$stage" <<'PY'
import sys, urllib.parse
raw = sys.argv[1]; u = urllib.parse.urlsplit(raw)
if u.scheme != 'https' or not u.hostname or u.username or u.password or any(c.isspace() for c in raw):
    raise SystemExit('ERROR: stage-url must be an https:// URL without credentials or spaces')
PY
  if [[ "$mode" == feature ]]; then
    (( ${#feature} <= 500 )) && [[ -n "${feature//[[:space:]]/}" && "$feature" != *$'\n'* ]] \
      || qa_die 'Feature description must be one non-empty line of at most 500 characters'
  fi
  local extra=''
  if [[ -n "$extra_file" ]]; then
    [[ -f "$extra_file" ]] || qa_die 'extra-prompt-file not found'
    extra="$(cat "$extra_file")"
  fi
  mode600 "$QA_ROOT/clients/$CLIENT/env.test" || qa_die "clients/$CLIENT/env.test missing or not mode 600"
  if [[ "$QA_RUNTIME" == docker ]]; then
    qa_auth "$CLIENT"
    QA_IMAGE="${QA_IMAGE:-redcarlos/qa-agents:$(git -C "$HERE/.." rev-parse --short HEAD)}"
    QA_IMAGE="$(docker image inspect --format '{{.Id}}' "$QA_IMAGE")"
  else
    QA_AUTH_FILE=/dev/null QA_IMAGE=native
    command -v "${QA_CLAUDE_BIN:-claude}" >/dev/null || qa_die 'claude CLI not found (set QA_CLAUDE_BIN)'
  fi
  QA_NETWORK="${QA_NETWORK:-bridge}"
  QA_MEMORY_SWAP="$QA_MEMORY"
  lock

  REPORT_DATE="$(date +%F)"
  local slug="$mode-${branch//\//-}"
  mkdir -p "$QA_ROOT/runs/$CLIENT"
  RUN_DIR="$(mktemp -d "$QA_ROOT/runs/$CLIENT/$(date -u +%Y%m%dT%H%M%SZ)-${slug:0:64}-XXXXXX")"
  CONTAINER_NAME="qa-$(basename "$RUN_DIR" | tr '[:upper:]' '[:lower:]')"
  mkdir -p "$RUN_DIR/claude-home" "$RUN_DIR/reports"
  printf 'RUN_DIR=%s\n' "$RUN_DIR"

  if [[ -d "$repo/.git" || -d "$repo/objects" ]]; then
    git clone -q --no-checkout -- "$repo" "$RUN_DIR/repo" >> "$RUN_DIR/run.log" 2>&1
    git -C "$RUN_DIR/repo" fetch -q -- "$repo" "+refs/heads/$branch:refs/heads/$branch" 2>/dev/null \
      || git -C "$RUN_DIR/repo" fetch -q -- "$repo" "+refs/remotes/origin/$branch:refs/heads/$branch" \
      || qa_die "Branch $branch not found in $repo"
    git -C "$RUN_DIR/repo" checkout -q "$branch"
  else
    git clone -q --branch "$branch" -- "$repo" "$RUN_DIR/repo" >> "$RUN_DIR/run.log" 2>&1
  fi
  git -C "$RUN_DIR/repo" log -1 --format='Commit under test: %h %s' | tee -a "$RUN_DIR/run.log"

  refresh_env
  [[ "$QA_RUNTIME" == docker ]] || install_native_agents
  mkdir -p "$RUN_DIR/repo/qa-reports/$REPORT_DATE/evidence" "$RUN_DIR/repo/qa-reports/$REPORT_DATE/screenshots"
  local ledger="$QA_ROOT/clients/$CLIENT/coverage-ledger.md" have_ledger=0
  if [[ -f "$ledger" && ! -L "$ledger" ]]; then
    install -m 600 "$ledger" "$RUN_DIR/repo/qa-reports/coverage-ledger.md"; have_ledger=1
  fi

  QA_MODE="$mode" QA_FEATURE="$feature"
  for v in CLIENT QA_RUNTIME QA_IMAGE QA_AUTH QA_NETWORK QA_CPUS QA_MEMORY QA_MEMORY_SWAP QA_SHM REPORT_DATE CONTAINER_NAME QA_MODE QA_FEATURE; do
    printf '%s=%q\n' "$v" "${!v}" >> "$RUN_DIR/state.env"
  done

  local prompt
  if [[ "$mode" == full ]]; then
    prompt="Full mode. Run a full QA pass of the web portal on $stage: build the portal module map from code and from the live stage, propose modules and budgets at the checkpoint, then execute module by module. There is no diff. Budgets: max ${QA_FULL_MAX_CASES:-60} cases, max ${QA_FULL_MAX_ROUNDS:-8} rounds per specialist per module. $extra"
  else
    prompt="Feature mode. Check: $feature. Target: current behavior on $stage. There is no diff; do not compare branches. $extra"
  fi
  if (( have_ledger )); then
    prompt+=" Previous coverage ledger: qa-reports/coverage-ledger.md; skip what it shows as covered and unchanged."
  else
    prompt+=" No coverage ledger yet for this client."
  fi
  prompt+=" Write the updated coverage ledger to qa-reports/$REPORT_DATE/coverage-ledger.md together with the verdict."
  prompt+=" This is a headless run in a Docker container: spawn every subagent in the foreground and wait for it; never end your turn while a subagent is still running, the process exits and kills it. At most one browser-using agent at a time. Web and API only; mobile is out of scope. Use /work/repo/.env.test for test credentials; never print secrets. Use qa-reports/$REPORT_DATE/ for all reports. The first line of summary.md must be exactly GO, NO-GO, or GO WITH KNOWN ISSUES."
  [[ "${QA_NO_CHECKPOINT:-0}" != 1 ]] || prompt+=' no checkpoint'

  run_claude "$RUN_DIR/plan.json" "$prompt"
  printf '\nReports: %s/reports\n' "$RUN_DIR"
  if [[ "${QA_NO_CHECKPOINT:-0}" == 1 ]]; then qa_finish; else
    printf 'Continue: %q go %q\n' "$0" "$RUN_DIR"; fi
}

cmd_go() {
  (( $# >= 1 && $# <= 2 )) || usage
  RUN_DIR="$(cd -- "$1" && pwd)"
  [[ "$RUN_DIR" == "$QA_ROOT/runs/"* ]] || qa_die 'run-dir must be under QA_ROOT/runs'
  [[ -f "$RUN_DIR/state.env" && -f "$RUN_DIR/session" && -d "$RUN_DIR/repo" ]] || qa_die 'run is incomplete or cleaned'
  source "$RUN_DIR/state.env"
  if [[ "${QA_RUNTIME:-docker}" == docker ]]; then qa_auth "$CLIENT"; else QA_AUTH_FILE=/dev/null; fi
  lock
  printf 'Mode: %s\n' "${QA_MODE:-full}"
  refresh_env
  local session; session="$(cat "$RUN_DIR/session")"
  local reply="${2:-go} (Headless run: spawn subagents in the foreground and wait for them; never end your turn while one is running. At most one browser-using agent at a time.)"
  run_claude "$RUN_DIR/reply-$(date -u +%Y%m%dT%H%M%S)-$$.json" "$reply" --resume "$session"
  printf '\nReports: %s/reports\n' "$RUN_DIR"
  qa_finish
}

case "${1:-}" in
  start) shift; cmd_start "$@" ;;
  go) shift; cmd_go "$@" ;;
  *) usage ;;
esac
