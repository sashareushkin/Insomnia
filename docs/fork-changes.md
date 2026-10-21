# Changes relative to upstream

Keep one entry per scoped change, including its PR. No application behavior has
been changed by the infrastructure bootstrap.

| Date | Feature | Reason | Subsystems | PR |
| --- | --- | --- | --- | --- |
| 2026-10-19 | Fork infrastructure bootstrap | Isolate development, CI and upstream integration from original publishing/system workflows | GitHub Actions, branch policy, agent instructions, documentation | Initial custom seed; no merge PR (bootstrap) |
| 2026-10-19 | Validate sync CI and API errors; document SSH transport | Reject stale synthetic merge refs, preserve actionable API failures, and document workflow permission limits | Fork CI, upstream sync, developer documentation | [PR #1](https://github.com/sashareushkin/Insomnia/pull/1) |
| 2026-10-19 | Menu bar session end controls and visible clamshell countdown | Intercept the complete × sequence before status-bar window tracking, offer safe termination from the active-session menu, and keep the visible countdown live on an external display with the lid closed | Status item AppKit event monitor/SwiftUI bridge, menu, presentation clock, regression tests; existing recovery lifecycle unchanged | [PR #3](https://github.com/sashareushkin/Insomnia/pull/3) |
| 2026-10-20 | Local verification gate | Replace hosted fork CI dispatch with reproducible, merge-candidate local evidence and explicitly guarded isolated full verification | Verification scripts/reports, upstream sync, GitHub workflow, branch policy docs and PR template | [PR #9](https://github.com/sashareushkin/Insomnia/pull/9) |
| 2026-10-20 | Stabilize recovery script fixture deadlines | Prevent host scheduling delays from turning the one-second fake-command timeout into false recovery failures while preserving timeout assertions | RecoveryScriptTests ScriptFixture, escaped-journal uninstall and app-record recovery cases | [PR #10](https://github.com/sashareushkin/Insomnia/pull/10) |
| 2026-10-20 | Russian and English localization | Resolve the app language from macOS preferences and allow an immediate transient language switch without changing configuration or recovery state | SwiftPM localization resources, settings and status UI, alerts and notifications, app bundle packaging, localization CI and tests | [PR #5](https://github.com/sashareushkin/Insomnia/pull/5) |
