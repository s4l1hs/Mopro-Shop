---
name: QA Bug Report
about: Bug found during manual QA testing (L1 checklist pass)
title: "[QA] "
labels: bug, qa
assignees: ''
---

## Build Info

| Field | Value |
|-------|-------|
| **Build SHA** | <!-- git rev-parse --short HEAD --> |
| **APK version** | <!-- e.g. 0.3.0+42 from pubspec.yaml --> |
| **iOS version** | <!-- e.g. 0.3.0+42 or N/A --> |
| **QA pass date** | <!-- YYYY-MM-DD --> |
| **Tester** | <!-- your GitHub username --> |

## Device

| Field | Value |
|-------|-------|
| **Device / Emulator** | <!-- e.g. Pixel 6 emulator Android 14 / iPhone 15 simulator iOS 17 / Samsung Galaxy S22 physical --> |
| **Flutter channel** | <!-- flutter --version output --> |
| **Backend environment** | <!-- staging / local --> |

## QA Flow

<!-- Which of the 10 flows from docs/ops/flutter-qa-l1.md triggered this bug? -->

- [ ] 1. Cold Start + Theme
- [ ] 2. Auth — OTP Login
- [ ] 3. Home Screen
- [ ] 4. Catalog List
- [ ] 5. Product Detail (PDP)
- [ ] 6. Search
- [ ] 7. Cart
- [ ] 8. Checkout (3 steps)
- [ ] 9. Order Confirmation + Detail
- [ ] 10. Account Area

## Reproduction Steps

<!-- Numbered list — assume the reader starts with the app freshly installed -->

1.
2.
3.

## Expected Behaviour

<!-- What the spec / checklist says should happen -->

## Actual Behaviour

<!-- What actually happened — be precise: error message text, wrong value, crash, freeze, etc. -->

## Evidence

<!-- Screenshot or screen recording required for UI bugs. Attach here or paste Imgur/Drive link. -->

## Severity

- [ ] **Blocker** — prevents the flow from completing; release cannot ship
- [ ] **Major** — incorrect behaviour but workaround exists
- [ ] **Minor** — cosmetic / UX issue; does not affect functionality

## Checklist Assertion

<!-- Copy the exact assertion line from docs/ops/flutter-qa-l1.md that failed -->

> `- [ ] …`

## Additional Context

<!-- Proxy log snippet, stack trace, or any other detail that helps diagnose -->
