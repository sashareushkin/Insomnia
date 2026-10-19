# Changes relative to upstream

Keep one entry per scoped change, including its PR. No application behavior has
been changed by the infrastructure bootstrap.

| Date | Feature | Reason | Subsystems | PR |
| --- | --- | --- | --- | --- |
| 2026-10-19 | Fork infrastructure bootstrap | Isolate development, CI and upstream integration from original publishing/system workflows | GitHub Actions, branch policy, agent instructions, documentation | Initial custom seed; no merge PR (bootstrap) |
| 2026-10-19 | Validate sync CI and API errors; document SSH transport | Reject stale synthetic merge refs, preserve actionable API failures, and document workflow permission limits | Fork CI, upstream sync, developer documentation | [PR #1](https://github.com/sashareushkin/Insomnia/pull/1) |
| 2026-10-19 | Menu bar session end controls (draft; real status-bar acceptance pending) | Consume the complete × press sequence and offer safe termination from the active-session context menu | Status item AppKit/SwiftUI bridge, menu, regression tests; existing recovery lifecycle unchanged | [PR #3](https://github.com/sashareushkin/Insomnia/pull/3) |
