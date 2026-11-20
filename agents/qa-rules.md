# QA rules

Shared by qa-web, qa-mobile, qa-api and qa-lead. Every agent reads this file before it starts and follows it.
Fill in "This project" at the bottom once per project.

## 1. Know what you are testing

- Every run has a run id: `<YYYYMMDD-HHMM>-<short sha>`. The sha is the commit under test: `git rev-parse --short HEAD` for a local run (first confirm HEAD is the branch you were asked to test; if it is not, never check out over the person's work: test from a separate `git worktree`, or stop and say so), or the deployed build's commit for a deployed environment. If `git status --porcelain` shows changes outside qa-reports/ and the test folders, add `-dirty`: uncommitted code is not in the sha. qa-lead sets the run id and passes it on; an agent called directly sets its own.
- Every file you write under qa-reports/ starts with the run id and your layer (web, mobile or api): `<run>-web.md`, `<run>-web-state.json`, `screenshots/<run>-web-login.png`. Parallel agents share the run id; the layer keeps their files apart. qa-lead writes `<run>-plan.md` and `<run>-summary.md`.
- For a deployed environment, also record the build or deploy id.
- Prove the running app contains the change before you trust any result. Pick a marker from the diff (a new label, route, response field or log line) and find it in what is actually running. A stale build, a dev server that did not reload, or an environment running another branch makes every pass meaningless.
- A result is valid for one commit. Write "passed on <sha>", never just "passed". Any later commit needs a new run.
- Check whether the base has moved: `git fetch origin <base>`, then `git log HEAD..origin/<base>`. Without the fetch the list can be falsely empty. If the base has moved, what will ship after the merge is untested. Base commits that touch files the branch changed, or modules its new files import, are where a clean merge silently breaks. Test those paths on a local merge in a separate `git worktree` and name both shas, or list them in the report as untested.

## 2. Start clean, check for real

- Every run starts from a clean session: a new browser context or cleared cookies and storage, a fresh sign-in, a fresh app launch. Never reuse a result from an earlier run.
- Wait for real content before you judge a page: rows, numbers, text. A spinner or a skeleton is not a pass, and neither is an empty table, unless empty is the expected result and the request behind it succeeded.
- Capture the evidence at the moment of the check: screenshot, response body, DB row. The report quotes what was there, not what should have been.
- HTTP 200 is not success. GraphQL and many other APIs return errors inside a 200 body, and a list that says "No data" may hide a failed request. Read the body.

## 3. Test the build that ships

- Explore on a dev server if you like. The final pass runs on a production build, built the way CI builds it (a release variant on mobile).
- The build must finish and exit. A build that prints "compiled successfully" and then hangs is a failure. Time it.
- If CI builds without a database, cache or queue, build once with them unreachable: point their host and port settings at a closed port, or build in a container with no network. Never stop a service you did not start.
- When CI has run, read the job log, not only the green check.

## 4. Scope: the change, and what it can break

- Passing the acceptance criteria is half the job. The other half is a regression sweep sized to what the change can reach:
  - a change local to one screen or endpoint: that screen or endpoint and its neighbours;
  - a shared component, helper, middleware or query: every place that uses it (find them with grep);
  - anything global (router, layout, auth, providers, API client, theme, migrations): every page or endpoint, including nested sub-pages. Click into each area's sub-navigation. A sweep of top-level pages misses whole subtrees.
- Work in order of what a defect would cost: money, lost data, data visible to the wrong user, sign-in and permissions first; cosmetics last.
- While an area keeps producing bugs, stay in it. If time runs out, stop where you are and list what you did not reach.

## 5. When there is no spec

Mark every case as one of:

- Expected: the agreed or obvious result. Pass or fail.
- [Record]: nobody has agreed what should happen. Write down exactly what happens; no pass or fail.
- [Probe]: the code suggests this place could break (an unchecked branch, a race, a missing permission check). Try hard to break it.

Acceptance criteria derived from the diff describe what the code does, so a pass against them only proves the code does what it was written to do. Say which criteria were derived.

## 6. Test data

- On your own test environment, create whatever data each branch of the feature needs: none, one, many, edge values, a second user, a second account. "No data to test with" is setup to do, not a coverage gap to report.
- On a shared environment:
  - prefix everything you create with `qa-<layer>-<run>-`, and touch only records with your prefix and settings whose original value you saved first;
  - before the first write, save what you will change (ids, counts, setting values) to `qa-reports/<run>-<layer>-state.json`;
  - at the end, restore it, sign in fresh and check that the restore worked;
  - list every setting you changed and whether you put it back.
- Never press or call anything on the "never touch" list below.
- If the app handles money, stock or counters, keep a ledger in `qa-reports/<run>-<layer>-ledger.md`: one row for every change you make. Check every report, total, dashboard and export against it. Checking one DB row proves one row; the ledger proves the totals.

## 7. Parallel runs

- Agents running at the same time must not share writable state. Each uses its own data prefix and, where possible, its own ports, database copy and job queue. A shared queue will run your jobs with another checkout's code.
- A prefix keeps records apart, not totals. Agents that keep a ledger need an account no other agent writes to during the run, or must run one after the other.
- Stop only the processes you started, by PID or port. Never kill by name pattern.

## 8. Blocked

- Before you report "blocked", spend two minutes trying: start the server, boot an installed emulator, create the missing data, sign in with the `.env.test` credentials (in a fresh Playwright context, a fresh app install, or an API call; never in the person's own browser), look for an installed tool.
- Fix blockers that are local and reversible yourself. Fixing a blocker never means editing files outside the folders your agent file allows.
- Some checks need a person: a CAPTCHA, a code sent to an inbox you cannot read, missing credentials, a real device, anything on production or involving real money. Mark each such check not run, give the reason, and carry on with the rest. Stop the whole run only when nothing else can proceed.
- Never swap a real check for a weaker one (reading the code instead of running it, a unit check instead of the flow) and report it as passed. Report it as not run, with the reason.

## 9. Test the test

- Every check ends in an explicit pass or fail. A helper that treats "returned something" as a pass will pass failures.
- Give each detector a control that must trigger it. Before you rely on "no error shown", show it one error.
- A test written for a bug must fail on the buggy build. If it passes there, it does not test the bug.
- A suspiciously round result (0 errors, 0 rows, 100%) means a broken check until you prove otherwise.

## 10. Performance claims

Only when the change claims to make something faster or lighter:

- measure the base commit first, then the change, on the same machine and data;
- at least three runs each; report the median and the spread;
- name the metric (load time, first paint, request count, query time). A fix often moves one and not another;
- a difference smaller than the run-to-run spread is not a result.

## 11. Severity

All agents use one scale, so they rank the same way. The lead re-ranks only for impact across layers.

| Severity | Meaning | Examples |
| --- | --- | --- |
| blocker | Money, stock or data is wrong or lost; data is visible to the wrong user; a core flow cannot be completed | a wrong total charged or saved; a payment recorded twice; another account's record visible; cannot sign in or pay |
| major | A main function fails with no reasonable workaround; a permission is not enforced; a report shows wrong figures while the stored data is right | a role sees what it should not; an import rejects valid rows; an export differs from the screen |
| minor | Works with a workaround; misleading; cosmetic | a filter silently returns nothing; a raw technical error message; a typo |

Wrong stored data is a blocker; a wrong display of correct data is major.

Put blockers at the top of your report and in your final reply, so the lead sees them without opening the file.

## This project (fill in)

Replace the examples.

- Test environment: own (agents may reset it freely, but never while another agent is running on it) or shared (prefix, snapshot and restore, section 6). Example: shared.
- CI build command, for section 3. Example: `pnpm build`.
- Base branch. Example: `main`.
- Never touch (buttons, endpoints, settings). Example: billing and plan changes, "delete all" actions, connect/disconnect/sync of external integrations, real payments, messages to real people.
