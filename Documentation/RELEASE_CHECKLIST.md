# Release checklist

## Automated

- [x] Debug build passes for iOS Simulator
- [x] Release build passes for iOS Simulator and generic iOS device
- [x] Seventy-nine unit tests pass, including Latin-only stable multi-side evidence, ROI crop mapping, RxNorm-backed compound-fragment repair, low-confidence live-camera, noisy-label and printed-NDC parsing, scheduling, supply, grouped notifications, and time-of-day greetings
- [x] Six UI tests pass, including Today and medication-editor accessibility audits, largest accessibility text in the editor, and overdue-state coverage
- [x] Static analysis passes for the Release app target
- [x] No source/compiler warnings; Xcode 26 emits only its no-AppIntents metadata-skip message
- [x] Privacy manifest is present in the built app, declares required-reason access for app-only UserDefaults and elapsed-event system uptime, and declares no collection or tracking
- [x] Regular, dark, and tinted app icon variants validate
- [x] `git diff --check`, trailing-whitespace, plist, and JSON checks pass
- [x] Unsigned arm64 Release archive succeeds and passes Xcode's shallow store validation
- [x] Development-signed build succeeds, installs, launches, and remains running on an iPhone 16 Pro

## Simulator review

- [x] iPhone 17e light and dark mode
- [x] iPhone 17 Pro light and dark mode
- [x] iPhone 17 Pro Max light and dark mode
- [x] Largest accessibility text size; Today and Supply switch to stacked layouts
- [x] Reduce Motion
- [x] Reduce Transparency and Increase Contrast
- [x] Automated labels, hit regions, traits, clipping, and element-detection audit
- [ ] Hands-on VoiceOver navigation order and rotor review
- [x] Empty, populated, low-supply, and unknown-forecast states
- [x] Explicit overdue-dose state review

## Physical-device gates

- [x] Development-signed app installs and launches on iPhone 16 Pro
- [x] Isolated manual-entry → save → supply critical-flow UI test passes on iPhone 16 Pro
- [x] Automated Today-screen accessibility audit passes on iPhone 16 Pro
- [x] Live camera label scan on iPhone 16 Pro returns raw VisionKit text
- [x] Corrected uninterrupted live scan populates the mandatory confirmation fields on iPhone 16 Pro
- [x] The four original still images return useful local Vision text/barcode results
- [x] Refill-alert delivery confirmed on iPhone 16 Pro
- [x] Equal-time dose schedules consolidate into one slot-level reminder; grouped reminders omit unsafe one-tap multi-dose actions
- [ ] `Taken` and `Skip` notification actions on a locked iPhone
- [ ] Energy and thermal behavior during a five-minute scan session

## App Store Connect gates

- [x] Reserve `Meds Ahead: Supply Tracker` as the final store name
- [x] Select local development team and confirm development signing
- [x] Confirm App Store Distribution signing and store provisioning profile
- [x] Create the App Store Connect record for `com.christoforakis.Meds` (Apple ID `6804540619`)
- [x] Publish support and privacy-policy URLs
- [x] Enter support and privacy-policy URLs in App Store Connect
- [x] Complete age rating, regulated-medical-device, and App Privacy answers
- [x] Prepare three accepted-size, no-alpha 6.9-inch screenshots
- [x] Upload screenshots
- [x] Export the final App Store-distribution-signed IPA and verify its signature, profile, privacy manifest, and ZIP integrity
- [ ] Upload and complete App Store Connect server-side build validation
- [x] Enter review notes and test instructions
- [ ] Save Free pricing, tax category, and all-country availability in App Store Connect
- [ ] Save the owner's non-trader EU DSA declaration in App Store Connect
- [ ] Save the authorized App Review contact details in App Store Connect
- [ ] Publish verified accessibility declarations
- [ ] Accept the Paid Apps Agreement and complete tax/banking setup
- [ ] Create the three consumable tip products with the exact IDs in `AppStore/CONNECT_ANSWERS.md`, add them to the version 1.0 submission, and upload their review metadata/screenshots
