# QA agents: how to use

## Install

1. Copy `qa-web.md`, `qa-mobile.md`, `qa-api.md`, `qa-lead.md` into `.claude/agents/` in the project (create the folder if missing, then restart Claude Code once).
2. Copy `qa-rules.md` into `.claude/` in the project (next to `agents/`, not inside it). Every agent reads it first. Fill in its "This project" section: whether the test environment is your own or shared, the CI build command, the base branch, and what agents must never press or call.
3. In each agent file, edit the `Setup` block: package manager, dev-server command, path to `openapi.yaml`, app id.
4. Create `.env.test` with the test base URL, test accounts and test DB. Agents use only this file.
5. Create `qa-reports/` and add it to `.gitignore` if you do not want reports in the repo.

## Requirements per agent

- qa-web: Playwright installed in the project, with a `webkit` project in playwright.config and the WebKit browser installed (`pnpm exec playwright install webkit`); Claude in Chrome extension 1.0.36+; start the session with `claude --chrome` (or enable by default via `/chrome`); `/login` with a Pro/Max/Team/Enterprise account; not WSL.
- qa-mobile: Maestro installed; an Android emulator or iOS simulator installed (the agent boots one if none is running); local session only.
- qa-api: curl; Jest + Supertest or PHPUnit set up; test DB reachable.
- qa-lead: nothing extra, it only delegates.

## Run

Single layer, call the agent directly:

    use qa-api to test the new /orders endpoints against openapi.yaml
    use qa-web to test the checkout flow on localhost:3000
    use qa-mobile to test login and onboarding on the booted Android emulator

Several layers or a release:

    use qa-lead to QA branch feature/payments against main

Guaranteed routing: type `@` and pick the agent from the list, e.g. `@qa-lead`.

## Output

Every file in qa-reports/ starts with the run id `<YYYYMMDD-HHMM>-<short sha>`, so reruns never overwrite each other and every result names the commit it tested. Per-agent files add the layer (web, mobile, api), so parallel agents never overwrite each other either.

- qa-reports/<run>-web.md, -mobile.md, -api.md: per-layer reports (summary, bugs with severity and repro, regression sweep, coverage gaps, data left behind).
- qa-reports/<run>-plan.md and -summary.md: only from qa-lead; summary has the GO / NO-GO verdict.
- qa-reports/<run>-<layer>-state.json and -ledger.md: what an agent changed on a shared environment, and every money, stock or counter change it made.
- qa-reports/screenshots/<run>-<layer>-*: screenshots and GIFs.
- New tests land in e2e/, .maestro/, tests/api/. Agents never edit app code.

## Good habits

- Give the agent scope, not a vague ask: feature name, acceptance criteria, which screens or endpoints.
- Run qa-api before the client agents when the API changed; clients depend on it.
- Run QA in a separate session from the one that wrote the code, and give it the acceptance criteria, not the author's explanation of why it works. The author tests what they expect to work.
- Review new tests before merging them into CI. The agent writes them from what it observed, not from the spec.
- Agents fix local blockers themselves (start a server, boot an emulator, create data) and stop only for what needs a person. If one reports "blocked", fix that and ask it to continue. They never swap a real check for a weaker one and call it passed.
- A GO is for one commit. After any new commit, run again.
- Reports are inputs for developers, not fixes. Hand bugs to the dev or to a separate fixing session.
