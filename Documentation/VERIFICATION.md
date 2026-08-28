# Verification record

## August 28, 2026 — scan reliability and reminder-cap pass (build 2)

Covers: flashlight control and camera-session recovery in the scanner, expiration
parsing for pharmacy wording (`DISCARD AFTER`, `USE BY`, named months, OCR
pipe-for-slash misreads), package-quantity vs. directions disambiguation,
matching photo OCR languages to the live scanner, comma-decimal locale
quantities, a 60-request notification cap that always prefers dose reminders and
the nearest refill alerts, refill sheet prefilled from refill history, and
same-day schedule overlap validation.

- Full unit tests: 120/120 on the iPhone 17 Pro simulator (Debug), including a
  new end-to-end test that renders a pharmacy-style label image and runs it
  through the real Vision OCR → sanitize → parse pipeline. That test caught
  Vision reading a printed slash as a pipe in `DISCARD AFTER 07/14/26`; the date
  patterns now accept `|` and `.` separators.
- UI and accessibility tests: 8/8 on the iPhone 17 simulator.
- Release static analysis on the application target: clean.
- Hands-on gates unchanged from the August 24 record below; the flashlight
  button and torch shutoff paths need a physical-device check (no torch exists
  in the simulator, so the button correctly stays hidden there).

---

Date: August 24, 2026

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
- The August 23 distribution artifact is superseded by the August 24 scanner changes and must not be uploaded
- Explicit store profile for `8G2SF9YU87.com.christoforakis.Meds`, with `get-task-allow = false`
- Exported IPA passes strict code-signature verification, archive integrity testing, privacy-manifest lint, and non-exempt-encryption inspection
- Installation and launch on a paired iPhone 16 Pro
- Unit coverage includes forecasting, supply accounting, scheduling, Latin-only stable multi-side scan evidence, ROI crop mapping, RxNorm-backed compound-fragment repair, noisy-label parsing, same-time reminder consolidation, notification-action logging, and tap routing
- 6 UI tests: onboarding, manual medication critical flow, Today and medication-editor accessibility audits, largest accessibility text in the editor, and accessible overdue-dose state
- Post-lifecycle-fix scanner-focused tests: 50/50 at `/private/tmp/Meds-Ahead-Scanner-Focused-20260824-0044.xcresult`
- Post-lifecycle-fix full unit tests: 76/76 at `/private/tmp/Meds-Ahead-Full-Unit-20260824-0045.xcresult`
- Post-lifecycle-fix UI tests: 6/6 at `/private/tmp/Meds-Ahead-UI-20260824-0046.xcresult`
- Post-lifecycle-fix Release build and app-target static analysis succeeded at `/private/tmp/Meds-Ahead-Release-Build-20260824-0047` and `/private/tmp/Meds-Ahead-Release-Analyze-20260824-0048`
- The exact signed Release device build at `/private/tmp/Meds-Ahead-Device-20260824-0049` installed on the paired iPhone 16 Pro; physical launch and live-continuation confirmation remain below because the phone locked before remote launch
- Final camera-handoff and grouped-reminder focused tests: 20/20 at `/private/tmp/Meds-Ahead-Scanner-Grouped-20260824-0053.xcresult`
- Final full unit tests: 79/79 at `/private/tmp/Meds-Ahead-Unit-20260824-0055.xcresult`
- Final UI tests: 6/6 at `/private/tmp/Meds-Ahead-UI-20260824-0061.xcresult`
- Final signed Release build succeeded at `/private/tmp/Meds-Ahead-Release-20260824-0062`; Release app-target static analysis also succeeded
- The exact final signed Release app from `/private/tmp/Meds-Ahead-Release-20260824-0062/Build/Products/Release-iphoneos/Meds.app` passed strict code-signature verification, installed on the paired iPhone 16 Pro, and launched successfully
- After removing automatic still capture and scanner recovery from the live session, the current scanner/parser/interpreter tests pass 43/43 at `/private/tmp/Meds-Ahead-Continuous-Scan-20260824-0065.xcresult`
- The current signed Release device build succeeded at `/private/tmp/Meds-Ahead-Continuous-Device-20260824-0066`, installed on the paired iPhone 16 Pro, and launched successfully
- Final post-form unit tests pass 79/79 at `/private/tmp/Meds-Ahead-Final-Unit-20260824-0067.xcresult`, including explicit greeting boundaries
- Final post-form UI and accessibility tests pass 6/6 at `/private/tmp/Meds-Ahead-Final-UI-20260824-0069.xcresult`
- Final signed Release build succeeded at `/private/tmp/Meds-Ahead-Final-Release-20260824-0070`; app-target Release analysis succeeded at `/private/tmp/Meds-Ahead-Final-App-Analyze-20260824-0072`
- The final Release build installed and launched on the paired iPhone 16 Pro
- The final IPA passes ZIP integrity, strict code-signature, privacy-manifest, export-compliance, and provisioning checks; it is signed by `Apple Distribution: NICHOLAS GEORGE CHRISTOFORAKIS (8G2SF9YU87)` with `get-task-allow = false`
- Review fields retain compact persistent names, including a visible `Refills remaining` label when its value is zero
- Optional tips use three consumable StoreKit products, remain hidden until Apple returns configured products, unlock no features, and finish verified transactions
- After restoring the intended three tip amounts, the definitive archive compiled at `build/MedsAhead-1.0-Submission-Final.xcarchive`, installed and launched on iPhone 16 Pro, and exported to `build/AppStore-Submission-Final/Meds.ipa`; the IPA again passed signature, profile, privacy, encryption, and ZIP-integrity checks
- The source and built privacy manifests pass `plutil` validation and declare the app-only UserDefaults reason `CA92.1` and elapsed-event system-boot-time reason `35F9.1`; no data collection or tracking is declared
- Equal-time dose schedules now produce one slot-level notification such as `8:00 PM meds are ready`; grouped alerts route into Meds Ahead for review and intentionally omit one-tap dose actions
- Physical-device critical-flow and automated accessibility-audit passes on iPhone 16 Pro
- Raw live label recognition and refill-alert delivery confirmed on iPhone 16 Pro
- Production replay of the later OTC and curved prescription photos returns Melatonin / 5 mg / 120 tablets and the complete amphetamine - dextroamphetamine generic name without invented directions
- Light and dark appearance on 6.1-inch, 6.3-inch, and 6.9-inch simulators
- Largest accessibility text size with adaptive Today and Supply layouts
- Reduce Motion, Reduce Transparency, and Increase Contrast simulator review
- 6.9-inch App Store screenshots: 1320 by 2868 JPEG, no alpha
- Privacy manifest, app icons, plist/JSON syntax, and whitespace validation
- Today, Supply, and medication-detail forecasts refresh their calendar-dependent state across midnight without relaunching

Xcode's metadata processor emits `Metadata extraction skipped. No AppIntents.framework dependency found.` This is a tool status message for an app with no App Intents dependency, not a compiler or application-code warning.

## Account or hands-on gates

- Upload the final distribution build and complete App Store Connect server-side validation.
- Create and submit the three optional consumable tip products with version 1.0, including their prices, availability, localization, and review screenshots.
- Complete pricing, availability, EU DSA status, accessibility declarations, and review-contact fields.
- Verify the `Taken` and `Skip` reminder actions from the locked iPhone and run a five-minute camera energy/thermal check.
- Complete a hands-on VoiceOver order/rotor pass.
