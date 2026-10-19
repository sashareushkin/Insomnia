# Changes relative to upstream

Keep one entry per scoped change, including its PR. No application behavior has
been changed by the infrastructure bootstrap.

| Date | Feature | Reason | Subsystems | PR |
| --- | --- | --- | --- | --- |
| 2026-10-19 | Fork infrastructure bootstrap | Isolate development, CI and upstream integration from original publishing/system workflows | GitHub Actions, branch policy, agent instructions, documentation | Initial custom seed; no merge PR (bootstrap) |
| 2026-10-19 | Validate sync CI merge parents and document SSH transport | Reject stale synthetic merge refs; reuse existing SSH credentials for workflow edits | Fork CI, developer documentation | [PR #1](https://github.com/sashareushkin/Insomnia/pull/1) |
