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
- Installation and launch on a paired iPhone 16 Pro
- 17 unit tests: forecasting, supply accounting, scheduling, sample-derived scan parsing, and notification planning
- 3 UI tests: onboarding, manual medication critical flow, and automated accessibility audit
- Physical-device critical-flow and automated accessibility-audit passes on iPhone 16 Pro
- Light and dark appearance on 6.1-inch and 6.9-inch simulators
- Largest accessibility text size with adaptive Today and Supply layouts
- Reduce Motion, Reduce Transparency, and Increase Contrast simulator review
- 6.9-inch App Store screenshots: 1320 by 2868 JPEG, no alpha
- Privacy manifest, app icons, plist/JSON syntax, and whitespace validation

Xcode's metadata processor emits `Metadata extraction skipped. No AppIntents.framework dependency found.` This is a tool status message for an app with no App Intents dependency, not a compiler or application-code warning.

## Account or hands-on gates

- Reserve the final name and create the App Store Connect app record.
- Enter the published support and privacy-policy URLs in App Store Connect.
- Confirm the App Store Distribution certificate/profile, then create and validate the signed distribution archive.
- Complete App Privacy, age rating, availability, regulated-medical-device, and review-contact fields.
- Use the installed build with the four physical labels to verify live camera focus/glare behavior.
- Verify reminder delivery on a locked iPhone and run a five-minute camera energy/thermal check.
- Complete a hands-on VoiceOver order/rotor pass.
