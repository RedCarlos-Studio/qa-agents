# QA agents for Codex desktop and CLI

These four native Codex agents preserve the QA responsibilities of the original
[Claude agents](../.claude/agents/). Both sets can coexist. Nothing here installs
browser automation, Maestro, application dependencies or credentials for you.

| Agent | Work | Allowed output locations (instruction only) |
| --- | --- | --- |
| `qa-web` | Browser exploration, Playwright regressions | `e2e/`, `qa-reports/` |
| `qa-mobile` | Maestro on already booted Android/iOS devices | `.maestro/`, `qa-reports/` |
| `qa-api` | Contract, auth, validation, DB integrity, integration tests | `tests/api/`, `qa-reports/` |
| `qa-lead` | Plan, delegation specification, combined release verdict; no testing | `qa-reports/` |

## Install into the application repository

1. Clone this repository into a separate directory. In the **target application**,
   review existing `AGENTS.md`, `.codex/agents/` and `.codex/config.toml` first.
2. Copy the four `.codex/agents/qa-*.toml` files into the target's `.codex/agents/`.
   If a destination exists, compare and merge deliberately. Never replace the
   project's `AGENTS.md` or entire `.codex` directory/configuration. No new
   `AGENTS.md` is required.
3. Review the copied prompts and commit these non-secret agent definitions with
   the target project so teammates use the same version. Preserve `.claude/agents/`.
4. Ensure `.env.test` and `qa-reports/` are ignored in that target repository;
   merge missing ignore entries, preserving existing rules. This template repo
   already ignores both. Never commit test credentials or raw traces.

Optional non-overwriting copy on macOS/Linux, run from the target project after
setting `QA_AGENT_SOURCE` to this cloned template repository:

```sh
QA_AGENT_SOURCE=/absolute/path/to/qa-agents
mkdir -p .codex/agents
for role in qa-web qa-mobile qa-api qa-lead; do
  if [ -e ".codex/agents/$role.toml" ]; then
    echo "Review existing .codex/agents/$role.toml manually"
  else
    cp -n "$QA_AGENT_SOURCE/.codex/agents/$role.toml" ".codex/agents/$role.toml"
  fi
done
```

The [current custom-agent format](https://learn.chatgpt.com/docs/agent-configuration/subagents#custom-agents)
requires `name`, `description` and `developer_instructions` in each standalone
TOML file. Models are deliberately omitted to inherit the session selection.
Do not add legacy experimental `multi_agent` flags or `[agents.role]`/`config_file`
registrations for these files. Optional parent configuration, manually merged
into an existing `[agents]` table only once:

```toml
[agents]
enabled = true # already the default
max_concurrent_threads_per_session = 4
```

No config file is shipped, so installation cannot overwrite team preferences.
The prompts' output restrictions are not filesystem isolation. Subagents inherit
parent permissions; `sandbox_mode`, `approval_policy`, `model_provider` and
`mcp_servers` cannot be overridden by these agent files. Set actual permissions
in the parent session. Project configuration requires project trust; review it
before trusting. See [config basics](https://learn.chatgpt.com/docs/config-file/config-basic).

## Desktop app — recommended

1. Open the [desktop app](https://learn.chatgpt.com/docs/app), select **Codex**
   from the dropdown, and open the **target application folder**.
2. Select **Work in → This computer**. Local uses the checkout; Worktree isolates
   Git changes. Start a new chat after installing agents, and review permissions
   under the composer. See [environment modes](https://learn.chatgpt.com/docs/environments/modes).
3. For Worktree, ensure the copied agents and test dependencies are present in
   that checkout. Ignored `.env.test` and running services are not Git content:
   configure the test runtime locally and confirm the server uses the tested
   revision. Do not assume an existing server is running the worktree's code.
4. Run the discovery prompt below, then a scoped QA prompt. Inspect worker activity
   and reports before accepting test changes. A missing role or tool is a setup
   issue to resolve, not permission to invent a successful run.

Cloud is a separate environment: local browser sign-ins, VPN, services and
simulators do not automatically transfer. Prefer local execution for mobile and
local-only test services. Cloud API/web QA needs separately provisioned tools,
network access, test data and runtime credentials.

## CLI

Install/update using the [official CLI installation instructions](https://learn.chatgpt.com/docs/cli),
then sign in through the supported interactive flow. No token belongs in these files.

```sh
cd /absolute/path/to/target-application
codex --version
codex
```

Use the same plain-language requests as in the app. `/status` shows session
configuration, `/permissions` controls permissions, `/mcp` diagnoses connected
MCP tools and `/subagents` inspects workers. `/agents` is not a custom-agent
installer. See [CLI commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli).
Restart into a fresh session after installing/changing agent definitions. If a
role is unavailable, check version, project path/trust, TOML diagnostics and
conflicting personal agents before running QA.

## Tooling and environment prerequisites

| Layer | Prepare before asking for live QA |
| --- | --- |
| All | Acceptance criteria, target revision, non-production URL/app id, isolated fixtures, locally configured test accounts, existing test instructions and allowed network/process access |
| Web | Project package manager/runtime, installed Playwright + browser binaries, existing scripts, reachable app/test server; optional configured browser tool for exploration |
| Mobile | Maestro, installed test app, booted device; Android SDK/adb for Android, macOS + Xcode simulator tools for iOS; explicit device ownership |
| API | curl or httpie, OpenAPI/route definitions, existing Jest + Supertest or PHPUnit harness, isolated test DB and authorized DB inspection |
| Lead | Diff/base revision and worker reports; no separate testing tool |

Use the project's documented dependency setup. Agents must report missing setup;
they may not edit manifests/configs or application code to make tests pass.
For example, `pnpm exec playwright test` is appropriate only for a project that
already uses pnpm and Playwright. Maestro flows use the installed CLI's device
selection and existing project conventions. k6 requires an explicit load-test
request with target, duration, rates and stop conditions.

An available browser tool may support exploration; Playwright browser APIs can
also explore. Neither Claude in Chrome nor any browser MCP is automatically
available to Codex. Verify DOM, console, network, screenshot and recording
capabilities individually. Record unsupported checks as gaps.
[MCP configuration](https://learn.chatgpt.com/docs/extend/mcp) belongs in the parent
config and is shared by app/CLI. Use only a real approved server configuration;
keep authentication local and outside committed team configuration.

`.env.test` remains a local test-runtime convention, not a file to paste into
chat. Use the project's safe loader; do not blindly shell-source it, dump it or
search for other credentials. Reports must redact secrets/PII before persistence,
including cookies, response bodies, screenshots, browser traces and device logs.

## Example requests

Discovery (no live QA, no test execution or secret access):

> Confirm that qa-web, qa-mobile, qa-api and qa-lead are registered custom agents.
> Report missing roles and available testing tools without reading credentials,
> spawning workers, running tests or editing files. Distinguish actual registered
> roles from merely finding TOML files on disk.

Single layer:

> Spawn qa-web to test checkout on our local test URL at port 3000. Verify guest
> checkout and required-field validation at 1440px and 390px. Use existing test
> accounts through the configured runtime. Write this run's report and evidence,
> reproduce bugs twice and add targeted Playwright tests. Do not fix app code.

> Spawn qa-api to test /orders against openapi.yaml in the configured test env.
> Cover role isolation, validation and DB consistency with disposable records.
> Use the existing integration harness; no load testing or app-code fixes.

> Spawn qa-mobile to test login and onboarding on the already booted Android
> device. Identify it first; mark iOS coverage unavailable if no iOS device is
> booted. Write small Maestro flows and report two-attempt bug evidence.

Multi-layer release (root coordinates, no nested delegation dependency):

> QA this branch against main. First ask qa-lead for a plan only, with a unique
> run id and worker scopes. In this root conversation, spawn the necessary
> qa-api, qa-web and qa-mobile workers according to that plan. API contract or
> migration changes must finish API QA before dependent client testing. Run
> independent scopes in parallel only with separate fixtures/accounts/devices
> and output paths. Wait for all required reports, then ask qa-lead to synthesize
> those reports into GO / NO-GO / GO WITH KNOWN ISSUES. Do not edit app code.

The lead can be used in two phases (plan, then synthesis). Passing the plan and
report paths explicitly works even when nested spawning is unavailable. If
spawning itself is unavailable, stop at the plan and report execution blocked.

## Reports and review

A run owns `qa-reports/<UTC-timestamp>-<unique-suffix>/` with `plan.md`, `web.md`,
`mobile.md`, `api.md`, `summary.md` as applicable and per-layer evidence folders.
Keep each worker's files and test edits disjoint. Same-day runs must not collide.

Every report records revision/environment, executed commands/results, confirmed
bugs with two reproductions, unconfirmed observations and coverage gaps.
**FAILED** means observed incorrect behavior; **BLOCKED** means a prerequisite
prevented testing; **SKIPPED** means intentionally outside scope; **NOT RUN** means
no execution evidence. Missing platforms, recordings or DB checks are not passes.
The lead deduplicates cross-layer causes and flags contradictory evidence.
Required coverage gaps or unresolved critical uncertainty imply NO-GO.

Review generated tests before CI integration. These prompts recommend a QA
verdict; they do not authorize deployment, change sandbox policies or guarantee
complete coverage. Fixes belong in a separate development task.

## Validate this template

With Python 3.11+:

```sh
python3 scripts/validate_codex_agents.py
git diff --check
```

The validator checks TOML syntax, required fields/types, names and the intentionally
minimal schema used here. It is not the Codex runtime schema/compiler. Separately
run the discovery prompt in an installed current Codex client; actual loading
must be observed. Live application QA is a third check requiring a target app,
tools and test environment. Do not infer either loading or live QA from parsing.

## Optional import from Claude

Codex also offers [import](https://learn.chatgpt.com/docs/import): desktop Settings
→ Import (or General → Import other agent setup), and CLI `/import`. Originals
remain intact. Review imported permissions, tools and MCP authentication. Avoid
duplicate named agents if these native files are already installed. For teams,
prefer reviewing and committing this native TOML set so installation is repeatable.

Documentation checked 2026-10-15; UI labels and availability can vary by release.
