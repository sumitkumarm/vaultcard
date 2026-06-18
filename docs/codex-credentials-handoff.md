# Codex Credential Handoff

Use this file when another Codex thread needs Appetize/GitHub Actions context.

Local Codex credentials are stored in:

```text
C:\Users\sumit\OneDrive\Documents\Gift Card Vault\.env.local
```

That file is intentionally ignored by git. Load it locally before using Appetize APIs.

GitHub Actions credentials/config are stored in:

```text
Repo Settings > Secrets and variables > Actions
```

Configured values:

```text
Secret:
APPETIZE_API_TOKEN

Variables:
APPETIZE_ANDROID_PUBLIC_KEY
APPETIZE_IOS_PUBLIC_KEY
```

Current Appetize public keys:

```text
Android: pxg2rht5zcqqjk6ek3o7yaevqm
iOS: menqwwjiw7wmvef57eeohiwrg4
```

For native iOS build/testing work:

1. Build via GitHub Actions or another macOS CI runner.
2. Upload/update the iOS simulator build in Appetize using `APPETIZE_API_TOKEN`.
3. Test the resulting Appetize app using `APPETIZE_IOS_PUBLIC_KEY`.
4. Do not ask the user to paste tokens into chat; read `.env.local` locally or use GitHub Actions secrets in CI.
