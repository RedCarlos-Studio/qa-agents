# QA agents: how to use

## Install

1. Copy `qa-web.md`, `qa-mobile.md`, `qa-api.md`, `qa-lead.md` into `.claude/agents/` in the project (create the folder if missing, then restart Claude Code once).
2. In each file, edit the `Setup` block: package manager, dev-server command, path to `openapi.yaml`, app id.
3. Create `.env.test` with the test base URL, test accounts and test DB. Agents use only this file.
4. Create `qa-reports/` and add it to `.gitignore` if you do not want reports in the repo.

## Requirements per agent

- qa-web: Playwright installed in the project; Claude in Chrome extension 1.0.36+; start the session with `claude --chrome` (or enable by default via `/chrome`); `/login` with a Pro/Max/Team/Enterprise account; not WSL.
- qa-mobile: Maestro installed; an Android emulator or iOS simulator booted before you start; local session only.
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

- qa-reports/<date>-web.md, -mobile.md, -api.md: per-layer reports (summary, bugs with severity and repro, coverage gaps).
- qa-reports/<date>-plan.md and -summary.md: only from qa-lead; summary has the GO / NO-GO verdict.
- qa-reports/screenshots/: screenshots and GIFs.
- New tests land in e2e/, .maestro/, tests/api/. Agents never edit app code.

## Good habits

- Give the agent scope, not a vague ask: feature name, acceptance criteria, which screens or endpoints.
- Run qa-api before the client agents when the API changed; clients depend on it.
- Review new tests before merging them into CI. The agent writes them from what it observed, not from the spec.
- If an agent reports "blocked", fix the environment (emulator, server, login) and ask it to continue; do not let it work around it.
- Reports are inputs for developers, not fixes. Hand bugs to the dev or to a separate fixing session.
