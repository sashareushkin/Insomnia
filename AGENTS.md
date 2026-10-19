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
- Use injected dependencies and temporary test journals. On the owner's working Mac, skip `UIStatusTests`, `UIStartupTests` and `KeychainStoreTests` as upstream documents; run the full suite on a disposable hosted CI runner. Report skips honestly.

## Completion
1. Run available, appropriate tests; inspect `git diff` and whitespace errors.
2. Make meaningful scoped commits, push the task branch to `origin`, and create a PR into `custom` with `gh ... -R sashareushkin/Insomnia`.
3. Update `docs/fork-changes.md` with date, feature, reason, subsystems and PR link.
4. Report changes, passed tests, skipped/remaining checks and blockers. Build/test failures mean the task is incomplete; fix them or report the blocker.
5. Never merge a PR without explicit owner permission. Never release or alter system settings as an implied completion step.
