# GiftCardMall Direct HTTP Spike

Observed on April 4, 2026 in the local development environment.

## Result

Direct HTTP access to the GiftCardMall balance site is currently blocked by a JavaScript-based anti-bot gate before the balance form can be used.

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

## Next Architecture Step

If live GiftCardMall support remains required, the next viable path is a browser-mediated flow or a user-assisted session handoff, not a raw background HTTP POST.
