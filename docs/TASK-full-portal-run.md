# Task: consolidate PRs #3, #4, #5 and add full-portal QA runs

Repository: RedCarlos-Studio/qa-agents
Relative size: medium to large. Mostly prompt and Bash work; one integration pass on the server.
Executor: Claude Code, working in a local clone with push access to RedCarlos-Studio/qa-agents and read access to the fork RuslanPostnikovRC/qa-agents.

Operator decision (Stage 0, open question 1): the consolidation is pushed into `server-runner` (PR #5) instead of a new `qa-full-run` PR. Read `qa-full-run` below as `server-runner`; #3 and #4 are closed with a link to #5 after it merges.

## 1. Goal

One branch, one PR, that contains everything from the three open PRs plus the missing pieces, so an operator can run on the QA server:

1. **Change run** (exists): QA a branch against a base.
2. **Feature run** (agents exist, scripts missing): "check <feature> on <stage-url>", no diff.
3. **Full run** (new): QA the whole web portal on <stage-url>, split into modules, each module planned and executed by the existing team, one consolidated verdict at the end.

All three modes go through the same operator checkpoint and the same `qa-go.sh` resume.

Out of scope: mobile on the server, scheduling, Slack or web UI, buying or resizing server resources.

## 2. Inputs: the three open PRs

| PR | Branch | Author | What it brings | Status |
|---|---|---|---|---|
| #4 | `qa-agents-v2` | ostfrost | v2 team: Opus qa-lead orchestrator, Sonnet specialists with research/execute modes, Haiku qa-runner, operator checkpoint, board, cost settings (`cacheTtl: 1h`, `memory: project`, `effort: medium`), **feature mode in qa-lead**, `docs/TASK-server-runner.md` | open, base for #5 |
| #3 | `RuslanPostnikovRC/qa-agents:qa-rules-from-practice` | RuslanPostnikovRC | `.claude/qa-rules.md` with 16 practices (regression sweep sized to reach, test the shipping build, results tied to a commit, clean session per run, test-data rules and ledger, severity scale, blocked-vs-not-run rules, test-the-test, WebKit/Firefox, isolation of parallel runs, HTTP 200 is not success, merge drift, performance method); run-id report names; Chrome login resolution (Playwright signs in with `.env.test`); sign-out/sign-in check in qa-web | open, written against v1 `main` |
| #5 | `server-runner` | Yarik-Gut | Docker image (Playwright base, pinned Claude Code and `@playwright/mcp`), `agents/` as source with symlinks from `.claude/agents/`, `qa-web-server.md` on Playwright MCP, `scripts/qa-run.sh`, `qa-go.sh`, `qa-common.sh`, `qa-build.sh`, `qa-clean.sh`, `qa-mcp-smoke.py`, `docs/SERVER.md` | open, based on #4; change mode only |

Known gaps found in review (this task closes them):

- G1. `qa-run.sh` has no `--feature`, although `docs/TASK-server-runner.md` requires it.
- G2. There is no full-portal mode anywhere.
- G3. `agents/qa-web-server.md` still says "If a login page or CAPTCHA appears, stop and report blocked". Most portal pages are behind login, so a full run would be almost entirely blocked. #3 fixed this only for the local Chrome variant.
- G4. qa-lead limits are sized for a PR (5 to 12 cases per layer, "10 strong cases over 30 weak", 6 rounds per specialist). A full run needs per-module budgets and a global ceiling.
- G5. #3 is written against v1 agents (single-pass lead, no research/execute modes, `tools:` without Write/Edit). Its rules must be merged into the v2 structure, not applied as-is.
- G6. #3 notes that `tools: mcp__claude-in-chrome` is not the documented form; the documented form is `mcp__claude-in-chrome__*`.

## 3. Ground rules for the executor

- Do not rewrite agents from scratch. Merge and extend. Keep v2 structure (phases, modes, board, checkpoint) as the backbone; add #3 rules into it; keep #5 infrastructure as is unless a change below says otherwise.
- `agents/` is the single source of truth (from #5). `.claude/agents/` stays symlinks. Make every agent edit in `agents/`.
- Keep the server image contents rule from #5: image ships qa-lead, qa-runner, qa-api, qa-web-server (as `qa-web`); excludes qa-mobile and local qa-web.
- No secrets in the repo, logs or prompts. Do not print or copy token files. Do not change server security settings.
- Preserve authorship: merge #3 and #4 with their original commits (merge or rebase that keeps authors), then add your own commits on top.
- No time-based terms in docs (weeks, days, deadlines). Use stages.
- Every commit message ends with the attribution lines required by the session.

## 4. Stage 0: pre-flight

- [ ] Clone `RedCarlos-Studio/qa-agents`, add remote `ruslan` for `RuslanPostnikovRC/qa-agents`, fetch all three branches.
- [ ] Read in full: the three PR descriptions, every changed file in each PR, `docs/TASK-server-runner.md`, `docs/SERVER.md`, `.claude/qa-rules.md` from #3.
- [ ] Write a short conflict map in the PR description draft: for each agent file, what #3 changes, what #4 changes, what #5 changes.
- [ ] Confirm with the operator before pushing anything to `main` or force-pushing an existing PR branch. Default plan: create a new branch `qa-full-run` and open a new PR; leave #3, #4, #5 open until the new PR is merged, then close them with a link.

Gate: conflict map exists, operator has confirmed the branch plan.

## 5. Stage 1: consolidate the three PRs

Order: start from `server-runner` (#5, already contains #4), then bring in #3.

1. `git checkout -b qa-full-run origin/server-runner`.
2. Verify #4 is fully contained: `git log origin/qa-agents-v2 --not HEAD` must be empty. If not, merge `origin/qa-agents-v2` first.
3. Merge `ruslan/qa-rules-from-practice`. Resolve conflicts by intent, not by side:
   - `.claude/qa-rules.md`: take #3 as is, move it to `agents/qa-rules.md`, symlink from `.claude/qa-rules.md`, and copy it into the image next to the agents (`/home/qa/.claude/qa-rules.md`). Update the Dockerfile copy step accordingly.
   - Agent files: v2 text wins for structure (phases, modes, report blocks, checkpoint, chains). Insert #3 rules as references to `qa-rules.md` sections at the matching place:
     - qa-lead: rules §4 (regression sweep sized to reach, order by cost of defect, list what was not reached) into Phase 2 review; rules §1 (results tied to a commit, marker from the diff proves the build) into Phase 0 and Phase 4; rules §5 (Expected / [Record] / [Probe] when there is no spec) into feature mode step 3; rules §11 severity scale into Phase 4; rules §7 isolation into Phase 3.
     - qa-web (local) and qa-web-server: rules §2 (clean session, wait for content, HTTP 200 is not success), §9 (test the test), WebKit and Firefox in addition to Chromium where the environment has them, sign-out / sign-in-as-another-user check.
     - qa-api: ledger check (rules §6), errors inside 200 bodies (rules §2).
     - qa-mobile: fresh install, emulator boot rule from #3 rules §8, kept consistent with v2 "no booted device means blocked" by preferring #3's wording (boot an already installed emulator if available, otherwise blocked).
     - qa-runner: tie results to the commit SHA; no other change.
   - Report naming: adopt #3 run id `<YYYYMMDD-HHMM>-<sha>` in report and evidence names, but keep v2 folder layout `qa-reports/<date>/board.md`, `summary.md`, `evidence/`, `screenshots/`. Update `scripts/qa-common.sh` collection only if paths change; `summary.md` stays the verdict file that `qa_verdict` reads.
   - `tools:` frontmatter: keep v2 values (lead has Write, Edit, Agent, SendMessage). Add `Write` and `Edit` to specialists and qa-runner so "edit only X/" rules are enforceable by intent; keep the path restriction in the prompt. Change local qa-web to `mcp__claude-in-chrome__*` (G6).
   - README: merge both; keep v2 sections, add #3 "run QA in a separate session from the one that wrote the code".
4. Run a frontmatter check: every agent file in `agents/` parses as YAML frontmatter, names are unique, every `qa-rules §N` reference points to an existing heading.

Gate: branch builds the image (`./scripts/qa-build.sh`), `python3 scripts/qa-mcp-smoke.py` passes, frontmatter check passes.

## 6. Stage 2: server qa-web login (G3)

In `agents/qa-web-server.md` replace the login rule with:

- Login pages are expected. Sign in with the test accounts from `/work/repo/.env.test`. Use the account whose role the case needs; if `.env.test` defines several roles, the lead names the role per case.
- Never type credentials into anything but the target stage origin. Never print, log or put credentials in evidence; redact them in snapshots and screenshots (use `browser_snapshot` text, which does not include typed password values, and do not screenshot filled password fields).
- Blocked only when: CAPTCHA, 2FA/OTP without a test bypass, SSO to a third-party identity provider, or the account is missing or rejected. Report which one and what unblocks it.
- One login per role per specialist session; reuse the authenticated browser context across cases of the same role, but start a fresh context for any case marked "clean session" by rules §2 and for sign-out checks.

Add to `docs/SERVER.md` → Add a client: `env.test` must define one account per role to be tested, with variable names documented in the client's README or listed in a comment at the top of `env.test`; CAPTCHA must be disabled on the stage or allowlisted for the server IP.

Gate: on a test stage with a login form, a feature run of "sign in and open the profile page" passes without operator help.

## 7. Stage 3: `--feature` in the scripts (G1)

`scripts/qa-run.sh` gets a mode switch while staying backward compatible:

```
qa-run.sh <client> <repo-url> <branch> <base-branch> [stage-url] [extra-prompt]          # change mode (unchanged)
qa-run.sh --feature "<what to check>" <client> <repo-url> <branch> <stage-url> [extra-prompt]
qa-run.sh --full <client> <repo-url> <branch> <stage-url> [extra-prompt]
```

- Parse the first argument; `--feature` and `--full` are the only options. Keep all existing validation (client name, URL without credentials, `git check-ref-format`, auth file checks, lock, network file).
- Feature and full modes clone `<branch>` (default branch of the stage, usually `main`) with no base fetch. `stage-url` is required in both and must be an `https://` URL; reject anything else.
- Store `QA_MODE=change|feature|full` and, for feature, `QA_FEATURE` (shell-quoted with `%q`) in `state.env`. `qa-go.sh` does not need them for resuming but they must be visible to the operator.
- Prompts:
  - change: unchanged.
  - feature: `Feature mode. Check: <what>. Target: current behavior on <stage-url>. There is no diff; do not compare branches.` plus the existing server suffix (web and API only, `.env.test`, report path, first line of `summary.md`).
  - full: see Stage 4.
- The `<what to check>` string is operator input: pass it as a separate argument, never through `eval`; limit to 500 characters and reject newlines.
- Update usage text, `docs/SERVER.md` → Start a run, and README → Run.

Gate: `qa-run.sh --feature "checkout with a saved card" ...` reaches the checkpoint, the brief says `mode: feature`, lists entry points; `qa-go.sh` completes and returns a verdict exit code.

## 8. Stage 4: full-portal mode (G2, G4)

### 8.1 Behavior

Full mode is feature mode applied to every module of the portal, with one plan, one checkpoint and one verdict.

**Phase 0F, portal map (qa-lead, no specialists yet):**
1. Build a module map from the code: route definitions (Next.js `app/` and `pages/`, React Router config, Laravel `routes/web.php` and `routes/api.php`, Nest controllers, WordPress templates and REST routes), navigation components, sitemap, role/permission guards, feature flags.
2. Cross-check with the live stage: qa-runner (or qa-web in research mode) fetches the sitemap and crawls navigation from the home page and from the dashboard of each role, depth-limited, same-origin only, no form submission. Record pages found live but not in code, and routes in code not reachable live.
3. Group into modules (for example auth and account, catalog and search, cart and checkout, orders and history, admin, content pages, settings). For each module: entry points per layer, roles, existing tests, risk (money, data loss, auth, legal, high traffic), and a size mark S/M/L.

**Phase 1F, research per module:** reuse Phase 1 per module, but research only the modules the operator keeps after the checkpoint (see below). To save cost, research of S modules may be batched into one specialist call.

**Checkpoint (full mode variant):** one screen per the existing format plus:
- module table: module, risk, size, layers, proposed case budget, included yes/no;
- global budget: total cases, total rounds per specialist, estimated wall time range, estimated cost note;
- the default selection: all modules with risk money/auth/data plus P1 flows of the rest; everything else marked "not in this run";
- operator replies: `go`, `go modules auth,checkout`, `go all`, `drop admin`, or a new budget (`budget 60`).

The plan phase stops at this checkpoint. Research of individual modules happens after `go`, module by module, unless `QA_NO_CHECKPOINT=1`.

**Phase 3F, execution:** process modules in risk order. Inside a module use the existing Phase 2 and 3 loop (backlog, dependency order, chains, blockers). Move to the next module when its backlog is empty, blocked, or its budget is spent. Shared blockers (stage down, login broken) stop the run and go to the operator; they do not get retried per module.

**Phase 4F, verdict:** one `summary.md` with the first line exactly `GO`, `NO-GO` or `GO WITH KNOWN ISSUES`, then a per-module table (cases passed/failed/blocked/not run, top issue), blockers and majors across modules, and an explicit "not covered" list: modules not selected, pages found live but not mapped, cases deferred by budget.

### 8.2 Budgets (replace PR-sized limits in full mode only)

Add a "Full mode budgets" section to qa-lead with defaults the operator can override in the reply or via env:

- per module: S 4 cases, M 8, L 12;
- global ceiling: 60 cases and 8 rounds per specialist per module (`QA_FULL_MAX_CASES`, `QA_FULL_MAX_ROUNDS`, passed into the prompt by `qa-run.sh`);
- when the ceiling is reached: stop dispatching, write remaining cases as "not run (budget)", go to the verdict.

Change and feature mode keep the existing limits.

### 8.3 Board structure in full mode

`board.md` gets a top-level module table and one section per module with its own task table and log. Task ids get a module prefix: `CHK-WEB-3`, `AUTH-API-1`. Keep the run id from #3 in the header.

### 8.4 Prompt from `qa-run.sh --full`

`Full mode. Run a full QA pass of the web portal on <stage-url>: build the portal module map from code and from the live stage, propose modules and budgets at the checkpoint, then execute module by module. There is no diff. Budgets: max <N> cases, max <R> rounds per specialist per module.` plus the server suffix.

### 8.5 Resource and safety notes for full mode

- One run at a time stays (existing lock). Full runs are long: document in `docs/SERVER.md` that the operator may interrupt with `docker stop <name>` and resume with `qa-go.sh <run-dir> "continue"`; the board is the state.
- Crawling in Phase 0F is read-only: GET only, same origin, depth limit 3, max 200 pages, respects `robots.txt` disallow for the stage unless `env.test` sets `QA_IGNORE_ROBOTS=1`.
- No destructive actions on shared stages without test-data rules from #3 (rules §6: prefix, snapshot, restore, never-touch list). If the stage has no never-touch list, the lead asks for one at the checkpoint before any write case in modules with risk money or data.

Gate: a full run on one real client stage reaches the checkpoint with a module table that the operator recognizes as complete (no major module missing), and after `go modules <two modules>` finishes with a verdict and the "not covered" list.

## 9. Stage 5: docs and README

- `docs/SERVER.md`: three run modes with examples, full-mode checkpoint replies, budgets and env overrides, interrupt and resume, login requirements for `env.test`, CAPTCHA allowlist note.
- README: modes table (change / feature / full), local vs server qa-web, link to `agents/qa-rules.md`, link to SERVER.md.
- `docs/TASK-server-runner.md`: tick the items now delivered; add a line that full mode is specified in `docs/TASK-full-portal-run.md` (this file, committed under `docs/`).

Gate: a teammate who has not seen this conversation starts a feature run and a full run using only SERVER.md.

## 10. Stage 6: validation on the server

Run on the QA host, against a real client stage with test accounts, in this order. Record each result in the PR description.

1. Smoke: `qa-build.sh`, `qa-mcp-smoke.py`, `claude -p "reply with ok"` inside the image with the configured auth.
2. Change run on a small branch with the checkpoint, then `qa-go.sh`.
3. Feature run on one login-protected feature.
4. Full run: checkpoint only, review the module table with the operator.
5. Full run continued with two modules selected.
6. Two-client isolation: run client A then client B; confirm neither sees the other's env, reports or memory.
7. Compare the full-run verdict for the two modules with manual QA on the same build; list misses both ways; adjust prompts only where a miss is systematic.

Note from the current host state: about 3.7 GiB RAM and limited free disk. Keep `QA_MEMORY` and `QA_SHM` within the values already validated in #5 unless the operator has added capacity. Do not delete data or resize anything to make room; report it instead.

## 11. Acceptance

- One PR from `qa-full-run` to `main` containing #4, #3 (with original authorship) and #5, plus the changes in this task. #3, #4, #5 closed with a link after merge.
- `qa-run.sh` supports change, `--feature` and `--full`; `qa-go.sh` resumes all three; exit codes unchanged.
- Server qa-web signs in with `.env.test` accounts and blocks only on CAPTCHA, 2FA, external SSO or bad accounts.
- Full mode produces a module map, a checkpoint with module selection and budgets, module-by-module execution, one verdict with a per-module table and a "not covered" list.
- qa-rules from #3 are referenced from every agent at the right places; local qa-web uses `mcp__claude-in-chrome__*`.
- Validation steps 1 to 6 passed and recorded; step 7 recorded with findings.
- No secrets in the repo, logs, prompts or PR text.

## 12. Open questions for the operator (ask before Stage 1 push)

1. New branch and PR (`qa-full-run`), or push the consolidation into `server-runner` (#5)?
2. Who approves the final PR, given the required-review rule on `main`?
3. Which client stage is the validation target, and which roles have test accounts?
4. Default full-mode budgets: keep 60 cases / 8 rounds, or different?
5. Keep WebKit and Firefox from #3 on the server image (adds image size and memory), or Chromium only on the server and all engines locally?
