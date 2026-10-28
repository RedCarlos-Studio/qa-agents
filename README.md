# QA agents: how to use

Five Claude Code subagents that work as a small QA team: a lead on Opus that plans, reviews and dispatches, three specialists on Sonnet that research and execute one task at a time, and a Haiku runner that executes the existing suites first so the specialists spend their rounds on new behavior.

## Install

1. Copy `.claude/agents/` into the project (restart Claude Code once if the folder did not exist).
2. In each specialist file, edit the `Setup` block: package manager, dev-server command, path to `openapi.yaml`, app id.
3. Create `.env.test` with the test base URL, test accounts and test DB. Agents use only this file.
4. Create `qa-reports/` and add it to `.gitignore` if you do not want reports in the repo.

## Requirements per agent

- qa-web: Playwright in the project; Claude in Chrome extension 1.0.36+; session started with `claude --chrome` (or Chrome enabled by default via `/chrome`); `/login` with a Pro/Max/Team/Enterprise account; not WSL.
- qa-mobile: Maestro installed; an Android emulator or iOS simulator booted before you start; local session only.
- qa-api: curl; Jest + Supertest or PHPUnit set up; test DB reachable.
- qa-runner: whatever the existing suites need (Playwright, Maestro, Jest or PHPUnit). Runs on Haiku.
- qa-lead: nothing extra. Runs on Opus, so expect it to cost more per run than the specialists.

## How a run works

1. Intake: the lead reads the diff and spec, creates `qa-reports/<date>/board.md`.
2. Research and regression, in parallel: the lead asks each involved specialist what should be tested (they return proposed cases with priority, preconditions and dependencies, nothing executed yet) and has qa-runner execute the existing suites.
3. Review: failing existing tests become P1 cases at the top of the backlog; proposed cases already covered by a passing test are dropped. The lead merges duplicates, orders by dependency (API before clients), drops cases that are already blocked, caps the scope, writes the backlog to the board.
4. Checkpoint: the lead stops and gives you a one-screen brief: scope, environment status, backlog size by layer and priority, estimate (rounds, wall time, cost), biggest risks, and anything only you can unblock. Nothing runs until you reply. Reply `go`, `go without MOB`, or change the scope. To skip the pause, start the run with "no checkpoint".
5. Execution: the lead sends each specialist one validated task, reads the result, updates the board, reacts (block dependents of a failure, stop on repeated blockers, triage observations), then sends the next task. Specialists keep their context between tasks.
6. Verdict: `qa-reports/<date>/summary.md` with GO / NO-GO and the full coverage picture, plus a short brief in chat.

The board is the single source of truth. If a run is interrupted, read the board to see what was done and what is left.

## Run

Several layers or a release (two steps: the lead returns a plan brief, you approve, it executes):

    use qa-lead to QA branch feature/payments against main
    ... lead returns the checkpoint brief ...
    go

Same, without the pause:

    use qa-lead to QA branch feature/payments against main, no checkpoint

Single layer, call the specialist directly (it will research, then execute its own top case):

    use qa-api to test the new /orders endpoints against openapi.yaml
    use qa-web to test the checkout flow on localhost:3000

Quick regression only, no planning:

    use qa-runner to run all existing suites

Guaranteed routing: type `@` and pick the agent, e.g. `@qa-lead`.

## Output

- `qa-reports/<date>/board.md`: scope, backlog with owners and statuses, decision log.
- `qa-reports/<date>/summary.md`: verdict, bugs by severity, coverage, open questions, process notes.
- `qa-reports/<date>/screenshots/`: screenshots and GIFs.
- New tests land in `e2e/`, `.maestro/`, `tests/api/`. Agents never edit app code.

## Cost and speed

Already on by default:

- Prompt cache held for 1 hour on all five agents (`experimental.cacheTtl: 1h`). The only values are `5m` and `1h`, and the hour restarts on every hit, so as long as rounds come more often than once an hour the cache lives for the whole run. Ignored while a subscription runs on usage credits.
- Specialists keep project memory (`memory: project`, stored in `.claude/agent-memory/<name>/`): environment facts, where the spec and tests live, recurring failure spots. Costs a few thousand tokens per spawn to load and a turn or two at the end of a run to update; saves most of the research phase from the second run on the same project. For a one-off project, remove the line.
- qa-runner on Haiku runs the existing suites in parallel with research. Failures become P1 cases before any specialist spends a round.
- Conditional chains: the lead can send up to three validated, independent cases in one message ("WEB-2; if passed, WEB-3; stop at first failure"). Fewer round trips, same control.
- Specialists read only their slice of the diff; the lead passes a digest.
- Evidence goes to `qa-reports/<date>/evidence/<task-id>.md`; specialists return a block under 25 lines. The Opus lead reads summaries, not logs.
- qa-web works through text tools; screenshots only on failure at half scale, GIF only for blockers.
- If a case already has a Playwright, Maestro or API test, the specialist runs the test instead of exploring by hand.
- Lead on `effort: medium`: judgment for review and verdict, no long thinking on mechanical rounds.

Optional switches, each a one-line change:

- Lead on Sonnet for everyday PRs: set `model: sonnet` in `qa-lead.md` and ask for Opus explicitly on release runs ("use qa-lead with opus for the release branch").
- Lower the round limit in `qa-lead.md` (default 6 per specialist) or cap cases per layer at 8 with P3 deferred by default.
- Drop `memory: project` from a specialist for a one-off project.

## Good habits

- Give the lead scope and acceptance criteria. The better the intake, the fewer rounds.
- When the lead stops with a blocker (no emulator, env down, login wall), fix the environment and say "continue"; it resumes from the board.
- Review new tests before merging them into CI. Specialists write them from what they observed, not from the spec.
- Reports are inputs for developers, not fixes. Hand bugs to the dev or to a separate fixing session.
- If a run drifts (too many rounds, low-value cases), lower the round limit in `qa-lead.md` or tighten the scope.
