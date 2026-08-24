# Verification record

Date: August 23, 2026

Toolchain: Xcode 26.6, iOS 26.5 SDK

Release: 1.0 (build 1)

Reserved App Store name: `Meds Ahead: Supply Tracker` (Apple ID `6804540619`)

## Passed

- Debug iOS Simulator build
- Release iOS Simulator build
- Release generic iOS-device build
- Release static analysis on the application target
- Unsigned arm64 archive and shallow store validation
- Development signing with team `8G2SF9YU87`
- App Store distribution export signed by `Apple Distribution: NICHOLAS GEORGE CHRISTOFORAKIS (8G2SF9YU87)`
- Latest verified distribution artifact: `/private/tmp/MedsAhead-OCRFix-AppStore-Export-20260823/Meds.ipa`
- SHA-256: `e7a049a2e3f2456cfbdb4be7162f65922e1320e0c7ddcda994729dce5064b228`
- Explicit store profile for `8G2SF9YU87.com.christoforakis.Meds`, with `get-task-allow = false`
- Exported IPA passes strict code-signature verification, archive integrity testing, privacy-manifest lint, and non-exempt-encryption inspection
- Installation and launch on a paired iPhone 16 Pro
- 40 unit tests: forecasting, negative-ledger count correction, supply accounting, independent per-time schedules, schedule-identity reconciliation, daylight-saving timing boundaries, sample-derived and noisy-label scan parsing, low-confidence live-camera field extraction, direction-fragment rejection, common refill-label formats, printed-NDC fallback, notification planning and request compaction, duplicate-safe reminder-action logging, and notification tap routing
- 6 UI tests: onboarding, manual medication critical flow, Today and medication-editor accessibility audits, largest accessibility text in the editor, and accessible overdue-dose state
- Physical-device critical-flow and automated accessibility-audit passes on iPhone 16 Pro
- Raw live label recognition and refill-alert delivery confirmed on iPhone 16 Pro
- Light and dark appearance on 6.1-inch, 6.3-inch, and 6.9-inch simulators
- Largest accessibility text size with adaptive Today and Supply layouts
- Reduce Motion, Reduce Transparency, and Increase Contrast simulator review
- 6.9-inch App Store screenshots: 1320 by 2868 JPEG, no alpha
- Privacy manifest, app icons, plist/JSON syntax, and whitespace validation
- Today, Supply, and medication-detail forecasts refresh their calendar-dependent state across midnight without relaunching

Xcode's metadata processor emits `Metadata extraction skipped. No AppIntents.framework dependency found.` This is a tool status message for an app with no App Intents dependency, not a compiler or application-code warning.

## Account or hands-on gates

- Confirm the corrected live scan populates the mandatory review fields on iPhone 16 Pro.
- Upload the verified distribution build and complete App Store Connect's server-side validation.
- Complete pricing, availability, EU DSA status, accessibility declarations, and review-contact fields.
- Verify the `Taken` and `Skip` reminder actions from the locked iPhone and run a five-minute camera energy/thermal check.
- Complete a hands-on VoiceOver order/rotor pass.
