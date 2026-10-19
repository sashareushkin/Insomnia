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

## Verification and Pull Requests

```sh
swift build
# Owner's working Mac: avoid upstream's UI/keychain suites.
swift test --skip 'UIStatusTests|UIStartupTests|KeychainStoreTests'
python3 -m unittest discover -s .github/scripts -p 'test_upstream_sync.py' -v
git diff --check
git push -u origin feature/example
gh pr create -R sashareushkin/Insomnia --base custom
```

`Fork CI` uses hosted `macos-26`, reports the actual Xcode/Swift versions,
executes swift build and the full swift test suite in disposable fixtures.
It does not install the app or invoke privileged power commands. Missing tmux
may skip upstream integration tests; report the count. Local test isolation is
provided by InsomniaTestHome and existing injected dependencies.
Only the owner merges after review and required `Swift build and test` passes;
no external approval requirement is imposed on this single-owner repository.
The initial custom infrastructure seed is a one-time bootstrap before protection;
all subsequent work uses PRs. No automatic merge or release is configured.

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
conflicts; an unmergeable PR stays open. A separate explicit fork-ci dispatch
checks refs/pull/N/merge. A separate privileged job (never executing PR code)
posts its result on the captured PR head, only if both head and base still match.
This avoids depending on PR events created by GITHUB_TOKEN.
The token needs contents:write, pull-requests:write and actions:write for dispatch;
CI code runs with contents:read, and its separate reporting job has statuses:write.

Both protected branches disallow force-push and deletion, including for admins.
Main does not require linear history: upstream merge commits must be preserved
by a fast-forward update. The workflow enforces ancestry and force=false.

The required check is not strict/up-to-date: updating a main-to-custom PR's
head with custom would contaminate the mirror. Before merging upstream, rerun
Fork CI against current custom using the dispatch input `pr` and verify the
reported base SHA. If custom moves during CI the status reporter fails closed.
For conflicts create `fix/integrate-upstream` from custom, merge origin/main
there, inspect both implementations and open a replacement PR into custom.
Never use GitHub's Update branch button on mirror main. Close the original
sync PR after the replacement is merged; if it stays open, sync reuses it.

Both workflows must remain active on default custom. Original workflows are retained unchanged for upstream compatibility and static
workflow tests, and disabled at repository level; main retains original files. Inspect Actions state after upstream workflow changes.
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
