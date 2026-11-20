# Server QA runner

## Status

Docker image built; Chromium and Playwright MCP smoke tests passed.
The MCP test passed with 1 CPU, 1 GiB RAM and 256 MiB shared memory.
A real Claude plan/resume cycle and client isolation test are pending.
Three run modes are available: change, feature and full (see Start a run).

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
The shared rules file agents/qa-rules.md is copied to
/home/qa/.claude/qa-rules.md; every agent reads it first.

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

Login requirements (most portal pages are behind a login):

- Define one test account per role to be tested (for example customer,
  manager, admin). Document the variable names in the client's README
  or list them in a comment at the top of env.test, so the lead can
  name a role per case.
- Disable CAPTCHA on the stage, or allowlist the QA server's IP for it.
- 2FA/OTP needs a test bypass. SSO through a third-party identity
  provider cannot be automated; such logins are reported as blocked.
- qa-web signs in only on the stage origin and never writes credentials
  to evidence or screenshots.

Optional settings in env.test that the agents read:

- QA_IGNORE_ROBOTS=1 lets the full-mode crawl ignore robots.txt
  disallow rules on the stage. Default: robots.txt is respected.

If the stage is shared with other people, fill in a never-touch list
(buttons, endpoints, settings agents must not use) in the client's
README or tell the lead at the checkpoint. In full mode the lead asks
for it before any write case in money or data modules.

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

Three modes. All of them stop at the same operator checkpoint and
resume with the same qa-go.sh.

| Mode | What it checks | Needs |
| --- | --- | --- |
| change | a branch against a base branch (the diff) | branch, base |
| feature | one named piece of functionality as it works now | description, stage URL |
| full | the whole web portal, split into modules | stage URL |

Arguments:

    ./scripts/qa-run.sh <client> <repo-url> <branch> <base-branch> [stage-url] [extra-prompt]
    ./scripts/qa-run.sh --feature "<what to check>" <client> <repo-url> <branch> <stage-url> [extra-prompt]
    ./scripts/qa-run.sh --full <client> <repo-url> <branch> <stage-url> [extra-prompt]

Change mode example (initial low-memory experiment):

    QA_CPUS=1 QA_MEMORY=1g QA_SHM=256m \
      ./scripts/qa-run.sh example \
      git@github.com:ORG/REPO.git feature/example main \
      https://staging.example.com

Feature mode example:

    ./scripts/qa-run.sh --feature "checkout with a saved card" example \
      git@github.com:ORG/REPO.git main https://staging.example.com

Full mode example:

    ./scripts/qa-run.sh --full example \
      git@github.com:ORG/REPO.git main https://staging.example.com

Replace all example values before running.
The supplied stage URL must agree with env.test.

Feature and full mode:

- branch is the branch the stage is deployed from, usually main.
  It is cloned for reading code; no base branch is fetched.
- stage-url is required and must be an https:// URL without
  credentials.
- The feature description is one line, at most 500 characters.
  Quote it as a single argument.
- state.env records QA_MODE (and QA_FEATURE for feature mode) so the
  operator can see what a run directory was for.

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

## Full mode

The plan phase builds a module map of the portal from the code (routes,
navigation, role guards, feature flags) and from a read-only crawl of
the stage, then stops at the checkpoint. No module is researched or
tested before go.

The crawl is GET only, same origin, depth 3, at most 200 pages, no
form submission except sign-in, and respects robots.txt unless env.test
sets QA_IGNORE_ROBOTS=1.

The full-mode checkpoint shows a module table (module, risk, size,
layers, proposed case budget, included yes/no), the global budget and
the default selection: every module with money, auth or data risk plus
the main flows of the rest. Replies:

    ./scripts/qa-go.sh <run-dir>                          # go: default selection
    ./scripts/qa-go.sh <run-dir> "go all"                 # every module
    ./scripts/qa-go.sh <run-dir> "go modules auth,checkout"
    ./scripts/qa-go.sh <run-dir> "drop admin"             # default minus one module
    ./scripts/qa-go.sh <run-dir> "budget 40"              # change the case ceiling, then go

After go, modules run one at a time in risk order: research, review,
execution. A module ends when its backlog is empty, blocked or out of
budget. A shared blocker (stage down, login broken) stops the run and
comes back to the operator instead of being retried per module.

Budgets:

- per module: S 4 cases, M 8, L 12;
- global ceiling: QA_FULL_MAX_CASES (default 60) cases and
  QA_FULL_MAX_ROUNDS (default 8) rounds per specialist per module.
  Set them before qa-run, or override in the checkpoint reply;
- at the ceiling the lead stops dispatching, marks the rest
  "not run (budget)" and writes the verdict.

summary.md has the verdict on the first line, then a table per module
(passed, failed, blocked, not run, top issue), blockers and majors,
and a "not covered" list: modules not selected, pages found live but
not in the map, cases deferred by budget.

The board in full mode has a module table at the top and one section
per module. Task ids carry a module prefix, for example CHK-WEB-3.

## Interrupt and resume

Full runs are long. To interrupt a running phase:

    docker ps --filter name=qa-
    docker stop <container-name>

Resume with the same run directory:

    ./scripts/qa-go.sh <run-dir> "continue"

The board (reports/board.md, or repo/qa-reports/<date>/board.md) is
the state: the lead reads it and carries on from the first task that
is not passed, failed, blocked or dropped. The lock prevents two
phases running at once, not a second run starting while one is paused;
starting another run in between is allowed but uses the same memory
budget, so finish or clean up the paused run first on a small host.

Accounts added mid-run: if the run stops because it needs an account
(for example a test user whose password is set from an email), add it
to /srv/qa/clients/<client>/env.test and reply "continue". qa-go
copies the client env.test into the run's clone on every resume when
it has changed, and prints "env.test refreshed".

## Coverage ledger: what is already tested

Each client keeps one ledger of tested functionality across runs:

    /srv/qa/clients/<client>/coverage-ledger.md
    /srv/qa/clients/<client>/coverage-history/   (previous versions)

How it flows:

1. qa-run copies the client ledger into the clone as
   qa-reports/coverage-ledger.md and tells the lead about it.
   The first run of a client has none.
2. The lead reads it at intake. In full mode the checkpoint table gets
   a ledger column, and the default selection skips modules that are
   `covered` and whose code paths have no commits since the covered
   commit. `failed` modules get their failed cases again, `partial`
   modules only the cases that were not run, changed modules are
   retested.
3. With the verdict, the lead writes the complete updated ledger to
   qa-reports/<date>/coverage-ledger.md: one row per module (status,
   commit, run id, passed / failed / blocked / not run, open issues,
   what the next run should do) and one line per executed case.
4. After a recognized verdict (exit 0, 1 or 2), qa-go (or qa-run with
   QA_NO_CHECKPOINT=1) saves it as the client ledger and moves the
   previous one to coverage-history/. No verdict, no save: an
   interrupted run never overwrites the ledger.

Statuses: covered (all cases ran, no open blocker or major; the only
status that lets the next run skip), failed, partial, not covered.

Checkpoint replies that use it:

    go                       # default: skips covered, unchanged modules
    go all                   # everything, covered modules included
    go modules auth,orders   # exactly these, covered or not
    retest auth              # put one covered module back in

To start over for a client, move coverage-ledger.md into
coverage-history/ by hand. Do not edit rows to mark something covered:
a module counts as covered only with its executed case lines.

## Answer the checkpoint

This works the same in all three modes. qa-go prints the run's mode first.
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
