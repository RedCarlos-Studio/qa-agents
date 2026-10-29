# Server QA runner

## Status

Docker image built; Chromium and Playwright MCP smoke tests passed.
The MCP test passed with 1 CPU, 1 GiB RAM and 256 MiB shared memory.
A real Claude plan/resume cycle and client isolation test are pending.
The implementation is based on qa-agents-v2; PR #4 must be merged
before final acceptance.

Commands below assume an authorized root shell on the host.
Claude and browser processes inside the container run as user qa.

## Requirements

- Docker, Git, Bash, Python 3, flock.
- Host user qa and private directories under /srv/qa.
- Access to the client repository using a read-only deploy key
  or a credential helper. Never put tokens in repository URLs.
- Outbound HTTPS for Claude authentication and API access.
- Network access to the client's staging or UAT environment.
- Client test accounts and permission to test that environment.

Recommended capacity per run: 2 vCPU, 4 GB RAM, 20 GB free disk.
Only one QA run can execute at a time on this installation.

This host has approximately 3.7 GiB total RAM. The initial experiment
uses a 1 GiB container limit. Only the browser smoke test has passed
at this limit; full workload capacity is not established.

## Build

From the repository root:

    ./scripts/qa-build.sh

The image tag uses the current Git commit:
redcarlos/qa-agents:<short-sha>.

Build again after committing changes, since the default tag changes.
Each run records the actual image ID; qa-go uses that same image.
Do not remove an image while a paused run still needs it.

Agent sources live in agents/. Local .claude/agents files are symlinks.
The image includes qa-lead, qa-runner, qa-api and the server variant
of qa-web. It excludes qa-mobile and the local Chrome variant.

## Authentication

Default: QA_AUTH=subscription.

The subscription owner generates a token with:

    claude setup-token

Store it in /srv/qa/secrets/claude.env:

    CLAUDE_CODE_OAUTH_TOKEN=<token>

For per-client API billing, use QA_AUTH=api and create:

    /srv/qa/clients/<client>/anthropic.env

with:

    ANTHROPIC_API_KEY=<key>

Authentication files must contain only the selected variable.
Use plain KEY=value syntax, without export or surrounding quotes.
Set owner qa:qa and mode 0600. Never commit or print these files.

Record the token's actual expiry and the person responsible for renewal.
Subscription runs share the owner's Claude plan limits with interactive
use. They do not provide per-client API billing.

## Add a client

Use a client name containing letters, digits, hyphens or underscores.

Example for a client named example:

    install -d -o qa -g qa -m 700 /srv/qa/clients/example

Create env.test in that directory using a secure editor.
It must contain the project's documented test environment variables:
staging URL, test accounts and any test database configuration.
Set owner qa:qa and mode 0600.

Never use production credentials or a production database.

The optional network file contains exactly one Docker network name:
bridge, host, or a preconfigured dedicated network.
It does not accept arbitrary Docker flags.
Default: bridge. Use host only when required for the host's VPN route.

The image includes Node/npm, Git and Chromium. It does not automatically
install client dependencies or provide every language runtime.
Confirm test setup for the chosen client. Missing dependencies,
runtimes or services must be reported as blocked, not as passing tests.

## Start a run

Arguments:

    ./scripts/qa-run.sh <client> <repo-url> <branch> <base-branch> [stage-url] [extra-prompt]

Example for the initial low-memory experiment:

    QA_CPUS=1 QA_MEMORY=1g QA_SHM=256m \
      ./scripts/qa-run.sh example \
      git@github.com:ORG/REPO.git feature/example main \
      https://staging.example.com

Replace all example values before running.
The supplied stage URL must agree with env.test.

Default resource limits are 2 CPU, 4g memory and 1g shared memory.
QA_MEMORY_SWAP defaults to QA_MEMORY, disabling container swap.
The shared-memory limit is not extra RAM outside the memory limit.
qa-go reuses the original resource limits.

The script clones the branch with full history, fetches the base branch,
copies env.test and starts qa-lead as the main Claude agent.

RUN_DIR is printed before cloning. At the checkpoint, the script prints
the plan and a qa-go command. No execute tasks should start before go.
Existing regression suites may run during planning.

To skip the operator checkpoint, set QA_NO_CHECKPOINT=1 before qa-run.
To select API billing, set QA_AUTH=api before qa-run.

## Answer the checkpoint

Use the exact run directory printed by qa-run:

    ./scripts/qa-go.sh /srv/qa/runs/example/<run-directory>

Default reply: go. A custom reply is the optional second argument:

    ./scripts/qa-go.sh /srv/qa/runs/example/<run-directory> "go without WEB"

A fresh container resumes the recorded session. Transcripts persist
under claude-home, mounted at /home/qa/.claude/projects.

Exit codes:

- 0: checkpoint returned successfully, or final verdict GO.
- 1: final verdict NO-GO.
- 2: final verdict GO WITH KNOWN ISSUES.
- 64: invalid command arguments.
- 70: runner/Claude/result-processing error.
- Other nonzero codes can come from preflight, Git or filesystem errors.

A technical failure is not a release verdict.
An unfinished reply without summary.md is not a completed QA run.

## Files and monitoring

Each run has its own directory under /srv/qa/runs/<client>/:

- repo/: disposable client clone and private .env.test.
- claude-home/: persistent Claude project transcripts.
- reports/: copied report contents, including board.md and summary.md.
- reports/evidence/ and reports/screenshots/: supporting evidence.
- state.env: runner settings and pinned image ID; contains no auth token.
- session: Claude session ID.
- plan.json and reply-*.json: Claude responses.
- run.log: clone output, Claude stderr and final JSON responses.

Reports are copied from repo/qa-reports/<run-date>/.
The recorded date stays the same if qa-go runs on another day.
Screenshots are expected only for failures, so that folder can be empty.

The final brief appears when the phase finishes. Monitor resources
from another terminal with docker stats and free -h.

## Cleanup

Preview cleanup; keep the newest three run directories per client:

    ./scripts/qa-clean.sh

Choose a different retention count:

    ./scripts/qa-clean.sh --keep 5

Delete only the listed old clones and transcripts:

    ./scripts/qa-clean.sh --keep 5 --apply

QA_KEEP_RUNS sets the default retention count.
Reports, metadata and logs remain.
Runs without a recognized final summary are skipped.
Cleanup refuses to run while a QA phase holds the shared lock.

A cleaned run cannot be resumed. Do not manually remove a paused
run's repo or claude-home directories.

## Troubleshooting

401/authentication failure:
Check token expiry, revocation, account access and selected QA_AUTH.
Replace the token securely; never paste it into logs or a ticket.
Only one authentication variable is allowed in the selected file.

Chromium crash:
Check available RAM, the container limit and shared-memory capacity.
The standard QA_SHM is 1g; the initial experiment uses 256m.
Changing limits requires a new run with the current scripts.

Exit 137:
This indicates SIGKILL, not necessarily an out-of-memory event.
Check Docker state and host kernel logs to establish the cause.

Interrupted phase:
Use docker ps to check whether its named qa-* container is still running.
Stop that specific container if necessary before resuming.
Do not start a second phase while the first container is active.

Missing test dependencies or unreachable staging:
Treat the affected suite as blocked. Correct client setup and start
a new run, or resume only after confirming that continuation is valid.

## Isolation and limitations

Each QA container mounts only that run's clone and Claude project state.
No host Docker socket or other client's directories are mounted.
The selected auth variables are supplied through Docker's env-file.

Private files stay out of Git. However, Claude is a remote model:
if an agent reads a secret into its context, it can leave the server.
This setup does not guarantee the stricter requirement that test
credentials never enter model context. Use restricted test accounts.

The server uses Playwright MCP, not the Chrome extension.
Mobile testing is excluded. iOS is unavailable on Linux; Android
emulators require additional infrastructure and resources.

No QA daemon, scheduler or frontend is installed. Containers are
removed after their process exits; images and run files consume disk.
Idle QA uses no model requests, but server and disk costs remain.

Before acceptance, complete a real plan/go cycle, verify MCP tools,
compare the verdict with manual QA, test two-client isolation and
have a second operator follow this guide.

## Chromium sandbox mode

The server agent passes --no-sandbox to Playwright MCP because Chromium's
sandbox could not initialize under the current container configuration.
This disables Chromium's internal sandbox; Docker isolation remains,
but it is not an equivalent replacement for browser sandboxing.
Use only trusted staging/UAT targets. No host sandbox settings were changed.

## MCP smoke test

From the repository root, run:

    python3 scripts/qa-mcp-smoke.py

No Claude token or external network is required. This checks MCP
tool discovery, browser navigation and accessibility snapshots.
It does not verify integration with the Claude agent.
