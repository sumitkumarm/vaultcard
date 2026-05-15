# VaultCard Low-Fidelity Wireframes

These are text wireframes for the current MVP so the UX can be reviewed without opening the app.

## Onboarding

```text
+--------------------------------------------------+
|                                                  |
|                    [icon]                        |
|                                                  |
|   Track every gift card in one place             |
|   Short supporting explanation text              |
|                                                  |
|                [page dots]                       |
|                                                  |
|   [ Next / Get Started ]                         |
+--------------------------------------------------+
```

## Card List

```text
+--------------------------------------------------+
| VaultCard                         [sort] [gear]  |
|--------------------------------------------------|
| Your Cards                              Newest   |
|                                                  |
| +----------------------------------------------+ |
| | Nickname / **** 1111                         | |
| | VISA                                         | |
| | Balance / expiry / stale state              | |
| +----------------------------------------------+ |
|                                                  |
| +----------------------------------------------+ |
| | Another card                                | |
| +----------------------------------------------+ |
|                                                  |
|                             [ + Add Card ]       |
+--------------------------------------------------+
```

Empty state:

```text
+--------------------------------------------------+
| VaultCard                         [sort] [gear]  |
|--------------------------------------------------|
|                                                  |
|              No cards yet                        |
|   Add your first prepaid gift card to start      |
|                                                  |
|         [ Add Your First Card ]                  |
+--------------------------------------------------+
```

## Add Card Choice

```text
+--------------------------------------------------+
| Add Card                                         |
|--------------------------------------------------|
| Choose how to add your card                      |
| Scan the card to prefill fields or enter         |
| the details manually                             |
|                                                  |
| +----------------------------------------------+ |
| | [scan icon] Scan Card                        | |
| | Use on-device OCR to prefill card fields     | |
| +----------------------------------------------+ |
|                                                  |
| +----------------------------------------------+ |
| | [keyboard icon] Enter Manually               | |
| | Type card number, expiry, CVV, and PIN       | |
| +----------------------------------------------+ |
+--------------------------------------------------+
```

## Scan Card

```text
+--------------------------------------------------+
| Scan Card                                        |
|--------------------------------------------------|
| Scan with your camera                            |
| Capture the card, then review the prefilled form |
|                                                  |
| +----------------------------------------------+ |
| |                                              | |
| |              camera preview                  | |
| |         [capture guide overlay]             | |
| |                                              | |
| +----------------------------------------------+ |
|                                                  |
|      [ Capture Card ]                            |
|      [ Use text fallback ]                       |
|                                                  |
| Last scan                                        |
| Card: xxxx                                       |
| Expiry: xx/xx                                    |
| CVV: xxx                                         |
| Confidence: xx%                                  |
|                                                  |
| Fallback OCR text                                |
| [ multiline recognized text box              ]   |
| [ Use Text Result ]                              |
+--------------------------------------------------+
```

## Card Entry Form

```text
+--------------------------------------------------+
| Card Details                                     |
|--------------------------------------------------|
| Card Number                                      |
| [______________________________]                 |
|                                                  |
| Expiry                CVV                        |
| [__________]          [__________]               |
|                                                  |
| Card number field shows detected network badge   |
|                                                  |
| Nickname (optional)                              |
| [______________________________]                 |
|                                                  |
| [ Save Card ]                                    |
+--------------------------------------------------+
```

## Card Detail

```text
+--------------------------------------------------+
| Card Name                    [refresh] [menu]    |
|--------------------------------------------------|
| [optional stale / failure banner]                |
|                                                  |
| +----------------------------------------------+ |
| | VISA                                         | |
| | $Balance                                     | |
| | Expires MM/YY                                | |
| | Last updated ...                             | |
| | [ Refresh In GiftCardMall ]                  | |
| +----------------------------------------------+ |
|                                                  |
| +----------------------------------------------+ |
| | Sensitive Details                            | |
| | Card Number  **** **** **** 1111 [Reveal]    | |
| +----------------------------------------------+ |
|                                                  |
| +----------------------------------------------+ |
| | Transactions                                 | |
| | Merchant                          -$xx.xx     | |
| | Date                                         | |
| +----------------------------------------------+ |
+--------------------------------------------------+
```

## GiftCardMall Foreground Refresh

```text
+--------------------------------------------------+
| GiftCardMall Refresh                             |
|--------------------------------------------------|
| Card Name                                        |
| Status / instructions                            |
|                                                  |
| [ Secure Autofill ]   [ Reload Page ]            |
|--------------------------------------------------|
|                                                  |
|                embedded WebView                  |
|                                                  |
|        user clears challenge and submits         |
|                                                  |
+--------------------------------------------------+
```

## Settings

```text
+--------------------------------------------------+
| Settings                                         |
|--------------------------------------------------|
| App Lock                            [ on/off ]   |
| Require biometrics or passcode                   |
|                                                  |
| Analytics                           [ on/off ]   |
| Disabled by default in MVP                       |
|--------------------------------------------------|
| Expiry warnings                     [ on/off ]   |
| Low balance alerts                 [ on/off ]    |
| Balance updated                    [ on/off ]    |
| Refresh failed                     [ on/off ]    |
+--------------------------------------------------+
```

## Notes

- These are structural wireframes, not visual design comps.
- The current implementation uses Material components and a straightforward mobile layout.
- If the next step is a more polished design pass, these wireframes should become the baseline review artifact.
