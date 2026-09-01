# Repository Agent Instructions

## Operating model

- The primary agent normally runs on Sol Medium or Sol High and owns the outcome: understand the request, set the product and technical direction, plan the work, sequence it, and integrate the result.
- Delegate bounded implementation, fixes, and follow-up iterations to Luna Max sub-agents. Give each delegate explicit scope, acceptance criteria, owned files or feature area, and focused validation commands.
- Avoid overlapping edits: assign ownership by file or feature and serialize work that could conflict.
- Review delegated work periodically by inspecting progress, diffs, and focused test results. Redirect or refine a task when it drifts; do not accept delegated output without review.
- The primary agent performs final integration, code and diff review, and focused validation for the changed path. Preserve existing user work and never reset or overwrite unrelated changes.
- Always create or switch to a dedicated local working branch before changing the repository. Do not implement changes directly on `main`.
- Keep working branches local. Never push a non-`main` branch or create a remote branch unless the user explicitly requests it.
- Commit successful work on the local working branch with a clear message. Exclude secrets, credentials, local caches, generated build output, temporary artifacts, and unrelated user changes.
- Release only after focused validation succeeds and the completed working branch has been integrated into local `main`. Push only `main`; `origin/main` is the canonical reference for the latest released code. If work is not ready to release, leave it committed on the local branch without pushing.
- Before releasing, reconcile local `main` with `origin/main` without overwriting unrelated work, merge the validated working branch into `main`, and push `main` without force. If integration or pushing fails, report it clearly and leave the work recoverable.
