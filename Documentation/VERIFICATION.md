# Verification record

Date: August 23, 2026

Toolchain: Xcode 26.6, iOS 26.5 SDK

Release: 1.0 (build 1)

## Passed

- Debug iOS Simulator build
- Release iOS Simulator build
- Release generic iOS-device build
- Release static analysis on the application target
- Unsigned arm64 archive and shallow store validation
- Development signing with team `8G2SF9YU87`
- App Store distribution export signed by `Apple Distribution: NICHOLAS GEORGE CHRISTOFORAKIS (8G2SF9YU87)`
- Latest verified distribution artifact: `/private/tmp/Meds-AppStore-Export-CorrectnessFinal/Meds.ipa`
- SHA-256: `1a98e5f8c7b64147776cc3df5fa16067071153374bcb6f2beb01c7a9a2f6bf59`
- Explicit store profile for `8G2SF9YU87.com.christoforakis.Meds`, with `get-task-allow = false`
- Exported IPA passes strict code-signature verification, archive integrity testing, privacy-manifest lint, and non-exempt-encryption inspection
- Installation and launch on a paired iPhone 16 Pro
- 32 unit tests: forecasting, negative-ledger count correction, supply accounting, schedule-identity reconciliation, daylight-saving timing boundaries, confidence-aware sample-derived scan parsing and live-evidence merging, notification planning and request compaction, duplicate-safe reminder-action logging, and notification tap routing
- 4 UI tests: onboarding, manual medication critical flow, automated accessibility audit, and accessible overdue-dose state
- Physical-device critical-flow and automated accessibility-audit passes on iPhone 16 Pro
- Useful live label scanning and refill-alert delivery confirmed on iPhone 16 Pro
- Light and dark appearance on 6.1-inch, 6.3-inch, and 6.9-inch simulators
- Largest accessibility text size with adaptive Today and Supply layouts
- Reduce Motion, Reduce Transparency, and Increase Contrast simulator review
- 6.9-inch App Store screenshots: 1320 by 2868 JPEG, no alpha
- Privacy manifest, app icons, plist/JSON syntax, and whitespace validation
- Today and Supply refresh their calendar-dependent state across midnight without relaunching

Xcode's metadata processor emits `Metadata extraction skipped. No AppIntents.framework dependency found.` This is a tool status message for an app with no App Intents dependency, not a compiler or application-code warning.

## Account or hands-on gates

- Reserve the final name and create the App Store Connect app record.
- Enter the published support and privacy-policy URLs in App Store Connect.
- Upload the verified distribution build after the final app record exists and complete App Store Connect's server-side validation.
- Complete App Privacy, age rating, availability, regulated-medical-device, and review-contact fields.
- Verify the `Taken` and `Skip` reminder actions from the locked iPhone and run a five-minute camera energy/thermal check.
- Complete a hands-on VoiceOver order/rotor pass.
