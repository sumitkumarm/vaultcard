# VaultCard UX Flow

This document describes the implemented Android-first MVP user journey and the intended behavior of each major screen.

## Primary User Journey

1. User opens VaultCard for the first time.
2. User completes onboarding.
3. User lands on the card list.
4. User adds a card by either:
   - scanning the card with on-device OCR, or
   - entering details manually
5. User reviews the saved card in card detail.
6. User reveals sensitive fields only after biometric authentication.
7. User refreshes card data either:
   - through the built-in direct refresh path, or
   - through the foreground GiftCardMall browser session flow
8. User adjusts app lock, analytics, and notification preferences in settings.

## Route Map

- `/onboarding`
- `/`
- `/add`
- `/add/form`
- `/scan`
- `/card/:id`
- `/card/:id/giftcardmall`
- `/settings`

## Screen Details

### Onboarding

File: [onboarding_screen.dart](C:/Users/sumit/OneDrive/Documents/New%20project/lib/src/presentation/screens/onboarding_screen.dart)

Purpose:
- explain the value proposition
- establish privacy and security expectations
- move the user into the main app

Key states:
- page 1: organize gift cards locally
- page 2: refresh balances and transactions
- page 3: sensitive details protected with biometrics

Primary action:
- `Next`
- final page changes to `Get Started`

Exit:
- marks onboarding complete
- routes to card list

### Card List

File: [card_list_screen.dart](C:/Users/sumit/OneDrive/Documents/New%20project/lib/src/presentation/screens/card_list_screen.dart)

Purpose:
- show all saved cards
- highlight empty state for first-time users
- provide sort and navigation to add/settings

Key states:
- loading placeholder
- empty state with primary add-card CTA
- populated list with sort menu

Actions:
- pull to refresh all cards
- open settings
- sort cards
- open card detail
- floating `Add Card`

### Add Card Choice

File: [add_card_screen.dart](C:/Users/sumit/OneDrive/Documents/New%20project/lib/src/presentation/screens/add_card_screen.dart)

Purpose:
- let the user choose between scan and manual entry

Actions:
- `Scan Card`
- `Enter Manually`

### Card Entry Form

File: [card_entry_form_screen.dart](C:/Users/sumit/OneDrive/Documents/New%20project/lib/src/presentation/screens/card_entry_form_screen.dart)

Purpose:
- capture card number, expiry, CVV, and optional nickname

Behavior:
- validates fields before save
- infers and displays card network from the entered number
- auto-formats expiry as `MM/YY`
- accepts prefill from scan flow

Primary action:
- `Save Card`

Exit:
- creates the card
- routes to card detail

### Scan Card

File: [scan_card_screen.dart](C:/Users/sumit/OneDrive/Documents/New%20project/lib/src/presentation/screens/scan_card_screen.dart)

Purpose:
- use device camera plus on-device OCR to prefill card fields

Behavior:
- initializes camera on load
- shows capture frame guidance
- processes captured image locally
- falls back to manual OCR text paste/edit path

Primary actions:
- `Capture Card`
- `Use text fallback`
- `Use Text Result`

Exit:
- routes to card entry form with extracted values

### Card Detail

File: [card_detail_screen.dart](C:/Users/sumit/OneDrive/Documents/New%20project/lib/src/presentation/screens/card_detail_screen.dart)

Purpose:
- show current balance, expiry, last updated time, sensitive details, and transactions

Sections:
- stale/failure banner when refreshes fail
- balance summary card
- sensitive details card
- transactions card

Actions:
- app bar refresh
- open GiftCardMall foreground refresh
- reveal card number
- delete card

Security behavior:
- reveals require biometric authentication
- revealed values auto-hide after timeout

### GiftCardMall Foreground Refresh

File: [gift_card_mall_refresh_screen.dart](C:/Users/sumit/OneDrive/Documents/New%20project/lib/src/presentation/screens/gift_card_mall_refresh_screen.dart)

Purpose:
- support GiftCardMall refresh through a foreground browser session when direct HTTP is blocked

Behavior:
- loads GiftCardMall in a WebView
- user can clear the anti-bot challenge in-page
- secure autofill requires biometric auth
- JS bridge listens for balance summary and transaction API calls
- syncs successful result back into VaultCard

Primary actions:
- `Secure Autofill`
- `Reload Page`

Important UX rule:
- the user still submits inside GiftCardMall
- VaultCard observes and syncs the active browser session

### Settings

File: [settings_screen.dart](C:/Users/sumit/OneDrive/Documents/New%20project/lib/src/presentation/screens/settings_screen.dart)

Purpose:
- control security and notification preferences

Settings:
- app lock
- analytics toggle
- expiry warnings
- low balance alerts
- balance updated
- refresh failed

## UX Principles In The Current MVP

- privacy-first: card credentials are treated as sensitive and only revealed on demand
- local-first: saved card vaulting works without a hosted backend
- fallback-friendly: scan and refresh flows include degraded paths when automation fails
- Android-first practicality: flows are designed to be verifiable on Android before iOS is finalized
