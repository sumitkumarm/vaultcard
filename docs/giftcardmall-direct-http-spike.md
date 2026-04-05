# GiftCardMall Direct HTTP Spike

Observed on April 4, 2026 in the local development environment.

## Result

Direct HTTP access to the GiftCardMall balance site is currently blocked by a JavaScript-based anti-bot gate before the balance form can be used.

Updated on April 4, 2026 with browser-inspector evidence from a human-cleared session: once the anti-bot challenge is passed in a real browser, the site does expose JSON API endpoints for balance summary and transaction retrieval.

## Evidence

- `https://www.giftcardmall.com/mygift` redirects to `https://mygift.giftcardmall.com`
- direct requests return a `405 Method Not Allowed`
- response headers include `x-datadome: protected`
- response body includes `Please enable JS and disable any ad blocker`
- response body references `captcha-delivery.com`

## Implementation Impact

- VaultCard cannot rely on the old direct form POST assumption for live balance refreshes.
- The app now detects this protection explicitly and reports a `botProtection` refresh failure.
- Refresh attempts are cooled down for 24 hours after this failure mode to avoid repeated background churn.
- The blocker is not the absence of JSON APIs. The blocker is acquiring and maintaining the browser-cleared session state that those APIs require.

## Next Architecture Step

If live GiftCardMall support remains required, the next viable path is a browser-mediated flow or a user-assisted session handoff, not a raw background HTTP POST.

## Browser-Captured API Shape

Sanitized summary from a real browser session after the challenge was cleared:

- Balance summary endpoint: `POST /api/card/getCardBalanceSummary`
- Summary payload fields:
  - `cardNumber`
  - `expirationMonth`
  - `expirationYear`
  - `securityCode`
  - `rmsSessionId`
- Summary response fields include:
  - `success`
  - `result.cardLastfour`
  - `result.balances.openingBalance`
  - `result.balances.closingBalance`
  - `result.balances.pendingBalance`
  - `access_token`
- Transactions endpoint: `POST /api/card/getCardTransactions`
- Transactions payload fields include:
  - `pageIndex`
  - `itemPerPage`
  - `startDate`
  - `endDate`
  - `preferredLanguage`
  - `rmsSessionId`
- Transactions request also carries a token header returned by the balance-summary response.

## Current Understanding

- There is no traditional user sign-in, but the APIs are still protected behind anti-bot session controls.
- The browser session appears to require values such as:
  - `datadome` cookie
  - `x-datadome-clientid` header
  - session cookies such as `TAsessionID`
  - `rmsSessionId`
  - follow-on transaction token from the summary response
- Because those values are established in a real browser session, a headless raw client cannot currently reproduce the flow reliably.

## Recommended Product Path

- Support GiftCardMall as a foreground-only browser-mediated refresh flow first.
- Use the embedded browser or WebView to let the user clear the anti-bot challenge and submit the card form.
- After the browser session is established, either:
  - parse the JSON calls from within the browser-mediated flow, or
  - extract the balance data from the rendered page if that is simpler and more stable.
- Do not promise background refresh for GiftCardMall in MVP unless a durable user-approved session handoff has been proven.

## Security Note

- Do not store raw copied curl commands, full card numbers, CVVs, cookies, or bearer-like tokens in the repository.
- Any future fixtures or docs should stay sanitized.
