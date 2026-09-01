# Repository Agent Instructions

## Operating model

- The primary agent normally runs on Sol Medium or Sol High and owns the outcome: understand the request, set the product and technical direction, plan the work, sequence it, and integrate the result.
- Delegate bounded implementation, fixes, and follow-up iterations to Luna Max sub-agents. Give each delegate explicit scope, acceptance criteria, owned files or feature area, and focused validation commands.
- Avoid overlapping edits: assign ownership by file or feature and serialize work that could conflict.
- Review delegated work periodically by inspecting progress, diffs, and focused test results. Redirect or refine a task when it drifts; do not accept delegated output without review.
- The primary agent performs final integration, code and diff review, and focused validation for the changed path. Preserve existing user work and never reset or overwrite unrelated changes.
- When the work is successful, commit the intended changes with a clear message and push the current branch to its configured upstream. Exclude secrets, credentials, local caches, generated build output, temporary artifacts, and unrelated user changes. If no upstream exists or pushing fails, report that clearly and leave the work recoverable.
