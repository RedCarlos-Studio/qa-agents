# Task: on-demand QA agent runner on the Red Carlos Linux server

Part of: qa-agents (RedCarlos-Studio/qa-agents). Depends on PR #4 (v2 agents) being merged.
Relative size: medium. Mostly infrastructure and scripting; agent changes are small.

## 1. Goal

Run the QA agent team (qa-lead, qa-runner, qa-web, qa-api) headless on our own Linux server, on request, against a client's staging or UAT instance, with zero cost while idle. One command starts a run, the operator reads the checkpoint brief, replies `go`, and gets the reports.

Not in scope for this task: scheduled or event-triggered runs, mobile (qa-mobile stays local or manual), Slack or web UI (listed as a later stage, not required for acceptance).

## 2. Decisions already made

- Hosting: our Linux server, Docker, one disposable container per run. No cloud runner, no Anthropic cloud routines.
- Auth: subscription token from `claude setup-token` (`CLAUDE_CODE_OAUTH_TOKEN`) by default; API key (`ANTHROPIC_API_KEY`) as a switch for per-client cost attribution later. The script must support both via one variable.
- Agents live in the Docker image under `~/.claude/agents/`, not in client repos. Clients add nothing to their codebase.
- qa-web on the server uses Playwright MCP (inline `mcpServers`) instead of the Claude in Chrome extension. The local qa-web with Chrome stays for manual sessions from a developer machine.
- Models stay as in v2: qa-lead on Opus (`effort: medium`), specialists on Sonnet, qa-runner on Haiku.
- The checkpoint stays: a run is two phases (plan, then `go`) unless started with `no checkpoint`.

## 3. Stage 0: pre-flight

- [ ] PR #4 merged into `main`.
- [ ] Server: Docker and Docker Compose installed, outbound HTTPS to `api.anthropic.com`, network route to at least one client staging (VPN or IP allowlist confirmed with the client).
- [ ] Free resources on the server: 2 vCPU and 4 GB RAM per concurrent run (8 GB if two runs may overlap), 20 GB disk for images and caches. Confirm with `free -h`, `nproc`, `df -h`.
- [ ] `claude setup-token` run on John Michael's machine; token stored on the server in `/srv/qa/secrets/claude.env` with mode 0600. Note the expiry in the team calendar; the token is valid for one year and runs fail with 401 after that.
- [ ] A client repo chosen for the first run, with a read-only deploy key or token, and its `.env.test` content (stage URL, test accounts, test DB if any).

Gate: all boxes ticked, `docker run hello-world` works as the `qa` user.

## 4. Stage 1: repo layout and server variant of qa-web

Add to the qa-agents repo:

```
agents/                      (moved from .claude/agents/, source of truth for the image)
  qa-lead.md
  qa-runner.md
  qa-web.md                  (local, Chrome extension)
  qa-web-server.md           (new, Playwright MCP)
  qa-mobile.md
  qa-api.md
docker/
  Dockerfile
  entrypoint.sh
scripts/
  qa-run.sh
  qa-go.sh
docs/
  TASK-server-runner.md      (this file)
  SERVER.md                  (operator guide, written in Stage 5)
.claude/agents/              (symlinks or copies of agents/, so the repo itself still works locally)
```

`qa-web-server.md`:
- Same prompt as `qa-web.md` with the Chrome paragraph replaced by Playwright MCP instructions: navigate, snapshot (accessibility tree), click, fill, screenshot. Text snapshots first, screenshots only on failure.
- Frontmatter: `name: qa-web` (same name, so qa-lead dispatches it unchanged), `tools: Read, Grep, Glob, Bash, WebFetch, mcp__playwright`, and

```yaml
mcpServers:
  - playwright:
      type: stdio
      command: npx
      args: ["-y", "@playwright/mcp@latest", "--headless", "--browser", "chromium"]
```

- Only one of `qa-web.md` / `qa-web-server.md` is copied into the image (the server one). Locally only `qa-web.md` is used. Document this in README.
- Inline MCP servers in `~/.claude/agents/` load without the folder-trust prompt, which is why agents go to the user level in the image and not into the cloned project.

Gate: `claude --agent qa-web -p "mode: research ..."` works locally against a test URL with the Playwright variant swapped in; `qa-lead` still dispatches it by name.

## 5. Stage 2: Docker image

`docker/Dockerfile`:
- Base: the official Playwright image for the pinned Playwright version (includes Node and Chromium with system deps). Pin the tag; do not use `latest`.
- Install Claude Code globally with npm. Pin the version.
- Pre-install `@playwright/mcp` globally so the inline server does not download on every run.
- Copy `agents/` (server set) to `/home/qa/.claude/agents/`.
- Non-root user `qa`, working directory `/work`.
- `entrypoint.sh`: reads `/run/secrets` or env, validates that exactly one auth variable is set, `cd /work/repo`, executes the `claude -p` command passed by the script.
- Image tag: `redcarlos/qa-agents:<git sha>`; build script in `scripts/` or a Makefile target.

Resource limits for the container (set in the run script): `--cpus 2 --memory 4g`, `--shm-size 1g` for Chromium.

Gate: `docker run --rm -e CLAUDE_CODE_OAUTH_TOKEN=... redcarlos/qa-agents:<sha> claude -p "say ok"` prints ok. `claude agents` inside the container lists qa-lead, qa-runner, qa-web, qa-api.

## 6. Stage 3: run scripts

`scripts/qa-run.sh <client> <repo-url> <branch> <base-branch> [stage-url] [extra prompt]`
`scripts/qa-run.sh <client> <repo-url> <branch> --feature "<what to check>" <stage-url>` (feature mode: no base branch, the prompt becomes "use qa-lead to check <what> on <stage-url>"; the lead maps the feature itself):

1. Creates `/srv/qa/runs/<client>/<timestamp>-<branch>/` (RUN_DIR) with `repo/`, `claude-home/`, `reports/`.
2. Clones the repo at `<branch>` with full history for `<base-branch>` (the lead needs `git diff <base>...HEAD`). Shallow clone is fine if `--depth` covers both refs; otherwise a plain clone.
3. Copies `/srv/qa/clients/<client>/env.test` to `repo/.env.test`.
4. Starts the container with:
   - `-v RUN_DIR/repo:/work/repo`
   - `-v RUN_DIR/claude-home:/home/qa/.claude/projects` (session transcripts must survive between phase 1 and phase 2)
   - `--env-file /srv/qa/secrets/claude.env` (or the client's API key file when `QA_AUTH=api`)
   - `--cpus 2 --memory 4g --shm-size 1g --network <as required>`
   - permission prompts disabled (`--dangerously-skip-permissions`); acceptable because the container is disposable and holds only the clone and the test env.
5. Runs phase 1: `claude -p --output-format json "use qa-lead to QA branch <branch> against <base-branch> on <stage-url>. <extra prompt>"`, or in feature mode `"use qa-lead to check <what> on <stage-url>. <extra prompt>"`.
6. Parses `session_id` from the JSON, writes it to `RUN_DIR/session`, prints the checkpoint brief (the lead's final text) to stdout, copies `repo/qa-reports/` to `RUN_DIR/reports/`.
7. Exits 0 with the brief; the container is removed, the volumes stay.

`scripts/qa-go.sh <run-dir> [reply]`:

1. Reads `session`, starts a fresh container with the same mounts.
2. Runs `claude -p --resume <session_id> --output-format json "<reply, default: go>"`.
3. Copies `qa-reports/` to `RUN_DIR/reports/`, prints the final brief, exits with 0 for GO, 1 for NO-GO, 2 for GO WITH KNOWN ISSUES (parse the first line of `summary.md`).

Both scripts:
- `QA_AUTH=subscription|api` selects which env file is passed. Refuse to start if both tokens are present.
- `QA_NO_CHECKPOINT=1` appends "no checkpoint" to the prompt; `qa-run.sh` then runs to the verdict in one phase.
- Log everything to `RUN_DIR/run.log`. Never print token values.
- `scripts/qa-clean.sh` removes run directories older than a configurable count of runs per client (keep reports, drop `repo/` and `claude-home/`).

Gate: a full plan-then-go cycle completes on a toy repo (any small Next.js or Nest project with a couple of tests) against a local stage, and `reports/` contains `board.md` and `summary.md`.

## 7. Stage 4: client secrets and isolation

- `/srv/qa/clients/<client>/env.test`, mode 0600, owner `qa`. One file per client. No secrets in the image or the repo.
- Optional per-client API key: `/srv/qa/clients/<client>/anthropic.env`; used only when `QA_AUTH=api`.
- Container network: default bridge is fine when staging is public; for VPN-only staging, run the container with the host's VPN route (`--network host` or a dedicated Docker network attached to the VPN namespace). Decide per client and record it in `/srv/qa/clients/<client>/network` as a one-line option the script reads.
- Each run sees only its own clone and its own client's env file. Verify by listing mounts and env inside the container.

Gate: two different clients can be run back to back without either seeing the other's env or reports.

## 8. Stage 5: first real run and operator guide

- [ ] Run against the chosen client's staging on a real feature branch, with the checkpoint.
- [ ] Compare the lead's verdict with a manual QA pass on the same branch. Record misses in both directions on the board's log; adjust agent prompts where the gap is systematic (not per case).
- [ ] Write `docs/SERVER.md`: how to start a run, how to answer the checkpoint, where reports land, how to switch auth, how to add a client, what to do on 401 (token expired) and on a Chromium crash (shm size).
- [ ] Add a line to README linking SERVER.md.

Gate: a second person on the team starts and finishes a run using only SERVER.md.

## 9. Stage 6 (later, not required for acceptance): request front-end

Options, pick one when the manual flow has been used a few times:
- Slack slash command that calls `qa-run.sh` and posts the brief to a thread; a reply in the thread calls `qa-go.sh`.
- Minimal web form behind our VPN with a client dropdown, branch field and a "go" button.

Both are thin wrappers over the scripts; the scripts stay the interface.

## 10. Acceptance for the whole task

- A run costs nothing when nothing is running (no services, no cloud instances; only disk under `/srv/qa`).
- `qa-run.sh` then `qa-go.sh` produces `board.md`, `summary.md`, `evidence/` and `screenshots/` for a real client branch against staging, and the same for a feature-mode run ("check <feature> on staging") on a branch with no pending changes.
- qa-web works through Playwright MCP in the container; qa-api and qa-runner work unchanged.
- Auth switch between subscription token and API key is a single variable.
- Client env files are isolated and never leave the server.
- SERVER.md is enough for a teammate to run it.

## 11. Known constraints to state in SERVER.md

- Subscription token: all runs count against John Michael's plan limits and share them with his interactive use. No per-client cost split in this mode; use `QA_AUTH=api` with a per-client key for that.
- No Chrome extension on the server; exploratory testing there is Playwright MCP only.
- No iOS on Linux; Android would need KVM and an extra 4 vCPU / 4 GB per emulator. Out of scope here.
- Claude Code itself is light (Node process, about 0.5 GB); the budget goes to Chromium and the project's own dev server and tests.

## 12. Open questions for the operator

1. Which client and branch is the first real run? Need repo access and staging reachability confirmed.
2. Does any target staging sit behind a VPN? Determines the network option in Stage 4.
3. Keep reports only on the server, or also push them to a `qa-reports` branch in the client repo / post a summary to Slack?
4. Who besides John Michael will start runs? If more than one person, decide now between a shared subscription token and per-person tokens on a Team plan.
