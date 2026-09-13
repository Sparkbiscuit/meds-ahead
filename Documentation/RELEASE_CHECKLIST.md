# Release checklist

## Automated

- [x] Debug build passes for iOS Simulator
- [x] Release build passes for iOS Simulator and generic iOS device
- [x] Three hundred and forty unit tests pass (1.1.1), including the NDC second look, confusable and split-line readings, the identification outcomes, the Health dose reconciler, the RxNorm slice, the pharmacy card, refill-in-progress and expiration reminders, the trip check, the adherence month and the person-grouped list, on top of the 1.1 set:  multi-salt listings collapsing to the name people use, NDC rendering and barcode decoding, the bundled FDA snapshot's real products, the NDC corroboration gate and strength equivalence, a rendered label with its NDC printed at one percent of the frame, Apple Health name mapping, duplicate detection and imported dose history, the exact product code on the shared list, the rating-request policy, clipped-name rejection, sig-versus-product-line separation, combination and canonical strengths, wrapped-sig assembly across real capture shapes, brand/generic resolution, Latin-only stable multi-side evidence, ROI crop mapping, RxNorm-backed compound-fragment repair, low-confidence live-camera, noisy-label and printed-NDC parsing, scheduling, supply, grouped notifications, time-of-day greetings, Take Now dose reconciliation, as-needed rate windows, unit-denominated strengths, expiration plausibility, last-refill alerts, and medication-list pagination
- [x] Nine UI tests pass, including Today and medication-editor accessibility audits, largest accessibility text in the editor, and overdue-state coverage, with the Import from Apple Health card present
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
- [x] Apple Health import (1.1): system picker with the purpose string, shared list, review screen, save returning to the list, already-on-file marking, and the cancelled-picker state
- [x] Rating request (1.1): appears after a logged dose once the policy is met and is recorded so it is not asked again for the version
- [x] Exact identification (1.1): rendered Tecfidera label with its NDC at 24 and 16 points through the real OCR pipeline resolves the exact product against the bundled snapshot
- [x] Dose history import (1.1): a dose logged in the simulator's Health app arrives on the list, as a toggle on the review screen, and in Recent Activity without charging the supply
- [x] SwiftData migration for `DoseEvent.countsTowardSupply` verified against a store the previous build created

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
- [ ] Exact identification (1.1) against the household's real bottles: printed NDC on orange retail and blue BCH vials, and a manufacturer barcode on a box
- [ ] Apple Health import (1.1) on a fresh install of a physical iPhone on iOS 26
- [ ] VoiceOver pass on the Apple Health screens and the NDC note on the review screen

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

## 1.1.1 gates

- [x] SwiftData migration for the batched 1.1.1 properties verified against stores the 1.0 build 3 and the 1.1 build created
- [x] Apple Health dose sync by hand in the simulator: a dose logged in Health arrives on the foreground sync and counts toward supply; an undo in Health removes it
- [ ] Real bottles on a physical iPhone: the two bottles from September 12 through live scanning and the Review capture, reading the capture note first
- [ ] Apple Health dose sync on a physical iPhone on iOS 26, including a medication scanned from a bottle and matched to Health by RxNorm
- [ ] VoiceOver pass on the NDC field, the identification notes, the pharmacy card, the calendar and the trip check
- [ ] Enter the 1.1.1 What's New from `AppStore/SUBMISSION.md`

## 1.1 submission gates

- [x] Bundle the FDA NDC Directory snapshot with `Tools/build_ndc_directory.py` (September 11 files, 112,246 products) and re-run the unit tests
- [ ] Publish the updated privacy policy page (Apple Health and NDC sections, corrected backup sentence) before submitting
- [ ] Archive with automatic signing; HealthKit joins the `com.christoforakis.Meds` App ID on the first archive, or is enabled by hand in Certificates, Identifiers & Profiles
- [ ] Enter What's New, the description naming the Apple Health integration, the keywords, and the 1.1 review notes from `AppStore/SUBMISSION.md`
- [ ] Confirm App Privacy stays `Data Not Collected` per `AppStore/CONNECT_ANSWERS.md`
