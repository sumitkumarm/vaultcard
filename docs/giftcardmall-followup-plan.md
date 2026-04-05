# GiftCardMall Follow-Up Plan

This note captures the current recommendation so the topic can be resumed later without rediscovering the constraints.

## What We Know

- A raw HTTP client is blocked before reaching the live GiftCardMall balance flow.
- A human-cleared browser session can reach JSON APIs for balance summary and transactions.
- Those APIs appear to depend on browser-established anti-bot and session values, not just card data.

## Questions To Resolve Next

- Can an in-app WebView reliably clear the anti-bot challenge on Android and iOS?
- Can VaultCard safely read the needed session state inside that WebView context without persisting sensitive cookies beyond the active session?
- Is transaction retrieval stable enough to support a structured parser, or should MVP only surface current balance?
- Is GiftCardMall support acceptable as foreground-only for MVP?

## Recommended Next Experiment

1. Add a separate WebView proof of concept behind a feature flag.
2. Open `https://mygift.giftcardmall.com` in the WebView.
3. Let the user manually clear the challenge and submit card details.
4. Inspect whether the WebView flow exposes stable success signals:
   - known API calls
   - known page routes
   - stable JSON payloads
5. If stable, design a foreground-only GiftCardMall refresh path.
6. If not stable, remove GiftCardMall live refresh from MVP scope.

## MVP Position If We Stop Here

- Keep manual card vaulting, OCR, secure storage, notifications, and local tracking.
- Mark GiftCardMall live refresh as unsupported due to anti-bot protection.
- Preserve the current failure handling and documentation.
