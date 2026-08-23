# Release checklist

## Automated

- [x] Debug build passes for iOS Simulator
- [x] Release build passes for iOS Simulator and generic iOS device
- [x] Seventeen unit tests pass
- [x] Three UI tests pass, including an automated accessibility audit
- [x] Static analysis passes for the Release app target
- [x] No source/compiler warnings; Xcode 26 emits only its no-AppIntents metadata-skip message
- [x] Privacy manifest is present in the archived app
- [x] Regular, dark, and tinted app icon variants validate
- [x] `git diff --check`, trailing-whitespace, plist, and JSON checks pass
- [x] Unsigned arm64 Release archive succeeds and passes Xcode's shallow store validation
- [x] Development-signed build succeeds, installs, launches, and remains running on an iPhone 16 Pro

## Simulator review

- [x] iPhone 17e light and dark mode
- [ ] iPhone 17 Pro light and dark mode
- [x] iPhone 17 Pro Max light and dark mode
- [x] Largest accessibility text size; Today and Supply switch to stacked layouts
- [x] Reduce Motion
- [x] Reduce Transparency and Increase Contrast
- [x] Automated labels, hit regions, traits, clipping, and element-detection audit
- [ ] Hands-on VoiceOver navigation order and rotor review
- [x] Empty, populated, low-supply, and unknown-forecast states
- [ ] Explicit overdue-dose state review

## Physical-device gates

- [x] Development-signed app installs and launches on iPhone 16 Pro
- [x] Isolated manual-entry → save → supply critical-flow UI test passes on iPhone 16 Pro
- [x] Automated Today-screen accessibility audit passes on iPhone 16 Pro
- [ ] Live camera scan on a supported iPhone
- [x] The four original still images return useful local Vision text/barcode results
- [ ] Notification delivery and actions on a locked iPhone
- [ ] Energy and thermal behavior during a five-minute scan session

## App Store Connect gates

- [ ] Reserve the final store name
- [x] Select local development team and confirm development signing
- [ ] Confirm App Store Distribution certificate/profile
- [ ] Create the App Store Connect record and bundle identifier
- [x] Publish support and privacy-policy URLs
- [ ] Enter support and privacy-policy URLs in App Store Connect
- [ ] Complete age rating and App Privacy answers
- [x] Prepare three accepted-size, no-alpha 6.9-inch screenshots
- [ ] Upload screenshots
- [ ] Archive and validate the App Store-distribution-signed build
- [ ] Submit review notes and test instructions
