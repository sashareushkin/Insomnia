# Development workflow for this fork

This fork is https://github.com/sashareushkin/Insomnia; original: https://github.com/krishhgg/Insomnia.
`AGENTS.md` and this document describe our process. Upstream CONTRIBUTING.md,
release docs, scripts and badges describe the original author's infrastructure,
not configured fork services. Do not run those publishing or merge-gate procedures.

## Branches and starting a task

- `main`: exact mirror of upstream/main; never develop here, only fast-forward.
- `custom`: default branch for our modified version and future releases.
- `feature/*`: one feature from current custom, PR to custom.
- `fix/*`: one bug fix from current custom, PR to custom.
- `chore/*`: scoped maintenance from current custom, PR to custom.

Inspect `git status --short --branch` before switching; preserve uncommitted work.
For a clean checkout:

```sh
git fetch origin
git fetch upstream --tags
git switch custom
git merge --ff-only origin/custom
git switch -c feature/example origin/custom
```

Use `origin` for the owner's fork and `upstream` for the original. Upstream's
local push URL is DISABLED; remote.pushDefault=origin, push.default=simple and
pull.ff=only are local safeguards. New clones must configure those too:

```sh
git remote add upstream https://github.com/krishhgg/Insomnia.git
git remote set-url --push upstream DISABLED
git config remote.pushDefault origin
git config push.default simple
git config pull.ff only
gh repo set-default sashareushkin/Insomnia
```

The current gh OAuth token lacks the workflow scope. Existing SSH access was
verified and can push workflow edits without expanding token permissions:

```sh
git -c url.ssh://git@github.com/.insteadOf=https://github.com/ push -u origin feature/example
```

This per-command transport override preserves the configured HTTPS remote URLs.
Use it for branches editing workflows if an ordinary HTTPS push is rejected.
Do not print credentials or change global Git configuration.

Always pass `-R sashareushkin/Insomnia` to gh PR/workflow commands: gh can
otherwise select the parent repository of a fork.

## Local verification and Pull Requests

```sh
scripts/verify-local.sh safe
git push -u origin feature/example
gh pr create -R sashareushkin/Insomnia --base custom
```

`scripts/verify-local.sh safe` fetches `origin`, merges the selected candidate
into the latest `origin/custom` in a temporary worktree, and runs the approved
local checks there. It leaves the developer's checkout and `main` untouched.
The default candidate is `HEAD`; for an upstream integration PR, use
`scripts/verify-local.sh safe --candidate origin/main --base origin/custom`.
The source checkout must be clean so the report names the exact committed
candidate. A merge conflict fails before any build or tests run.

The safe mode records macOS, Xcode, Swift, architecture, checkout branch, dirty
state, candidate SHA, base SHA and merged tree SHA. It runs the upstream-sync
and verifier Python unit tests, localization validation when present, shell
syntax checks, plist checks, `swift build`, the lid-simulation release gate,
and `swift test --skip 'UIStatusTests|UIStartupTests|KeychainStoreTests'`.
Before running that test command it inspects `swift test list`, confirms the
skip expression matches exactly those three suites, and checks the executed
test total against the discovered inventory. Missing tmux or other runtime
skips are listed in the report; they do not silently become passes.

The safe mode also uses `scripts/build-app.sh --output <report-dir>/package`
to build an ad-hoc signed temporary `.app`. It checks the bundle identity,
version/build metadata, plist, icon, backstop and any localized resources,
then verifies the signature. It never installs or launches that bundle and
does not change system settings. Reports, logs and build products are kept in
the printed directory under the system temporary directory by default; an
explicit `--report-dir` must also be outside the checkout. The report contains
human-readable Markdown and machine-readable JSON. A local report does not
post or forge a GitHub status.

The full suite is guarded for a disposable macOS 26 VM or dedicated test Mac:

```sh
INSOMNIA_ISOLATED_MACOS26=1 scripts/verify-local.sh full-isolated
```

Only set that acknowledgment after confirming the host is isolated. The mode
requires macOS 26 and runs the same build/package checks with the full
`swift test` suite. Do not run it on the owner's daily-use Mac. The recovery
journal, backstop, injected dependencies and test fixtures remain enabled in
both modes.

Every PR must include the exact-SHA summary from
`.github/pull_request_template.md` and link its report. The owner reviews the
result before manually merging; no automatic merge or release is configured.
The initial custom infrastructure seed is a one-time bootstrap before
protection; all subsequent work uses PRs.

### Required-check migration

The repository previously required the GitHub status context `Swift build and
test`. Deleting its workflow does not remove that branch-protection rule. The
owner must review `Settings → Branches → custom` and remove that hosted check
before the workflow-removal PR can merge. Keep the PR and conversation
resolution protections, and keep force-push and deletion disabled. The manual
gate is the reviewed exact-SHA local report plus the owner's explicit merge
authorization; do not post a fabricated status to satisfy the old rule.

## Synchronization

`Upstream sync` runs daily at 05:23 UTC (08:23 Moscow), or manually:

```sh
gh workflow run upstream-sync.yml -R sashareushkin/Insomnia --ref custom
```

The trusted custom script reads upstream/main, verifies ancestry, and calls
GitHub's update-ref API with force=false. Divergence fails without overwriting
history. Identical refs and already-integrated commits produce no changes.
After main advances, at most one open main-to-custom PR is created or reused.
Commit subjects and the complete comparison describe changes. GitHub computes
conflicts; an unmergeable PR stays open. The sync workflow only updates the
mirror and creates or reuses the integration PR. It does not dispatch hosted
build/test jobs. Before integration, locally verify the exact merge candidate
with `scripts/verify-local.sh safe --candidate origin/main --base origin/custom`,
then post its report in the PR. The token needs `contents:write` and
`pull-requests:write`; no Actions or status-write permission is required.

Both protected branches disallow force-push and deletion, including for admins.
Main does not require linear history: upstream merge commits must be preserved
by a fast-forward update. The workflow enforces ancestry and force=false.

The former required check was not strict/up-to-date: updating a main-to-custom
PR's head with custom would contaminate the mirror. Verify against the latest
base with the local temporary-worktree command above immediately before review.
If custom advances after the report, rerun verification against its new SHA.
For conflicts create `fix/integrate-upstream` from custom, merge origin/main
there, inspect both implementations and open a replacement PR into custom.
Never use GitHub's Update branch button on mirror main. Close the original
sync PR after the replacement is merged; if it stays open, sync reuses it.

GitHub may require an additional Workflows write permission when upstream changes
workflow files ([Git reference API permissions](https://docs.github.com/en/rest/git/refs#update-a-reference)).
GITHUB_TOKEN has no configurable Workflows permission. If GitHub rejects such an
update, sync stops without overwriting main and prints the API error. The owner
can use the already verified SSH transport for a manual fast-forward of main
from upstream, then rerun sync to create/reuse the integration PR. Do not add a
personal secret, expand permissions, or force the update implicitly. This case
cannot be accepted live until an upstream update is available.

`Upstream sync` remains active on default `custom`. Original upstream
workflows are retained unchanged for upstream compatibility and static tests,
and disabled at repository level; `main` retains the original files. Inspect
Actions state after upstream workflow changes.
Repository Actions is enabled, workflow default token permission is read, and
Actions may create PRs. GitHub can disable scheduled workflows after inactivity;
check for disabled_inactivity and re-enable upstream-sync.yml if needed.
Failures appear in Actions and GitHub's normal workflow notifications.

Local main is refreshed separately (automation updates GitHub, not this Mac):

```sh
git fetch origin
git fetch upstream --tags
git switch main
git merge --ff-only origin/main
git rev-parse main upstream/main
git switch custom
git merge --ff-only origin/custom
```

## Rollback

Use a new fix branch from current custom and `git revert <commit>` (for a merge,
`git revert -m 1 <merge>` after checking its parents), run tests and open a PR.
Never reset shared history, force-push, or revert our changes on main. If sync
fails on divergence, stop it and investigate; do not repair by force.

## Future releases (not implemented)

Stable and Nightly channels must build from our custom history, with automatic
package builds, authenticated update metadata/artifacts, in-app updates and a
safe recovery-agent upgrade protocol. Design signing, rollback and recovery
journal compatibility before implementation. Preserve MIT and original author
attribution. No release or updater is created by this infrastructure setup.
