# Instructions for every AI agent

## Development
- Our version is `custom`. Never develop, commit, or resolve conflicts on `main`: it is an exact upstream mirror, updated only by fast-forward.
- Before each task inspect status, remotes and branch; fetch `origin`, then update local `custom` with `git merge --ff-only origin/custom`. Preserve all existing work; stop on divergence.
- Create one independent `feature/<name>` or `fix/<name>` branch from current `origin/custom`. Infrastructure tasks may use `chore/<name>`.
- Keep independent changes in separate PRs targeting `custom`. Follow existing architecture and style; prefer minimal changes without unnecessary refactoring. Add suitable tests for every behavior change.
- Do not change Mac system settings without explicit owner permission. Do not install or launch Insomnia just to validate a source change.
- Read `docs/fork-workflow.md` before working. Its fork instructions supersede upstream contribution/release procedures. Never run upstream merge-gate or publishing workflows for this fork.

## Upstream
- Preserve upstream compatibility and functionality; do not rewrite existing mechanisms without necessity or remove features for simplicity.
- Integrate upstream changes only through a reviewed PR. Analyze both implementations in conflicts; never automatically choose ours/theirs.
- Preserve custom changes unless they conflict with security fixes or necessary upstream changes. Ask the owner when a conflict requires a product decision.
- Never force-push, hard-reset, or push to upstream. Do not merge an upstream PR automatically.

## Safety
Insomnia controls sleep, power settings, process suspension and restoration.
- Preserve the recovery journal and recovery backstop. Never disable or simplify either to pass tests, or bypass safety checks.
- A session must not finish without its prescribed system-state restoration. Any session lifecycle change requires separate review.
- Real tests involving lid closure, power changes or stopping processes require explicit owner permission.
- Use injected dependencies and temporary test journals. On the owner's working Mac, run `scripts/verify-local.sh safe`; it skips `UIStatusTests`, `UIStartupTests` and `KeychainStoreTests`, checks that this pattern excludes exactly those suites, and reports every test skip or failure.
- Run the full test suite only with `INSOMNIA_ISOLATED_MACOS26=1 scripts/verify-local.sh full-isolated` on a disposable macOS 26 VM or dedicated test Mac. Never set this acknowledgment on the owner's daily-use Mac.
- Keep verification reports, logs, build products and the temporary `.app` outside the checkout. Report the candidate SHA, `origin/custom` base SHA, tested merge-tree SHA, commands, skips and failures. A local report is not a GitHub status check.

## Completion
1. Run `scripts/verify-local.sh safe` on the exact candidate, inspect its report and `git diff`/whitespace errors.
2. Make meaningful scoped commits, push the task branch to `origin`, and create a PR into `custom` with `gh ... -R sashareushkin/Insomnia`.
3. Update `docs/fork-changes.md` with date, feature, reason, subsystems and PR link.
4. Report changes, passed tests, skipped/remaining checks and blockers. Build/test failures mean the task is incomplete; fix them or report the blocker.
5. Never merge a PR without explicit owner permission. Never release or alter system settings as an implied completion step.

## Local verification gate

- Pull requests must include the local verification summary from `.github/pull_request_template.md` and link the generated report.
- Upstream integration candidates must be checked as the merge of `origin/main` into the latest `origin/custom`, using `scripts/verify-local.sh safe --candidate origin/main --base origin/custom`.
- Do not post synthetic GitHub statuses or claim GitHub Actions passed based on a local report.
- The `custom` branch's previous required `Swift build and test` check must be reviewed and replaced with the documented manual verification gate before merging this infrastructure change. Keep pull-request, conversation-resolution, no-force-push and no-deletion protections.
