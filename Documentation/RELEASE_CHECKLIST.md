# Release checklist

## Automated

- [x] Debug build passes for iOS Simulator
- [x] Release build passes for iOS Simulator and generic iOS device
- [x] Three hundred and fifty-four unit tests pass (1.1, build 6), including the store's move into the app group, the widget snapshots and timelines, the NDC second look, confusable and split-line readings, the identification outcomes, the Health dose reconciler, the RxNorm slice, the pharmacy card, refill-in-progress and expiration reminders, the trip check, the adherence month and the person-grouped list, on top of the 1.1 set:  multi-salt listings collapsing to the name people use, NDC rendering and barcode decoding, the bundled FDA snapshot's real products, the NDC corroboration gate and strength equivalence, a rendered label with its NDC printed at one percent of the frame, Apple Health name mapping, duplicate detection and imported dose history, the exact product code on the shared list, the rating-request policy, clipped-name rejection, sig-versus-product-line separation, combination and canonical strengths, wrapped-sig assembly across real capture shapes, brand/generic resolution, Latin-only stable multi-side evidence, ROI crop mapping, RxNorm-backed compound-fragment repair, low-confidence live-camera, noisy-label and printed-NDC parsing, scheduling, supply, grouped notifications, time-of-day greetings, Take Now dose reconciliation, as-needed rate windows, unit-denominated strengths, expiration plausibility, last-refill alerts, and medication-list pagination
- [x] Nine UI tests pass, including Today and medication-editor accessibility audits, largest accessibility text in the editor, and overdue-state coverage, with the Import from Apple Health card present
- [x] Static analysis passes for the Release app target
- [x] No source/compiler warnings; Xcode 26 emits only its no-AppIntents metadata-skip message for the app target
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
- [x] Upload and complete App Store Connect server-side build validation (1.0 builds 1 to 3)
- [x] Enter review notes and test instructions
- [x] Save Free pricing, tax category, and all-country availability in App Store Connect (required before the 1.0 submission, which was approved September 7, 2026)
- [x] Save the owner's non-trader EU DSA declaration in App Store Connect (same)
- [x] Save the authorized App Review contact details in App Store Connect (same)
- [ ] Publish verified accessibility declarations
- [x] Accept the Paid Apps Agreement and complete tax/banking setup (done for 1.0; the tips went on sale with it)
- [x] Create the three consumable tip products with the exact IDs in `AppStore/CONNECT_ANSWERS.md`, add them to the version 1.0 submission, and upload their review metadata/screenshots (created and approved with 1.0, confirmed September 13, 2026; nothing to add for 1.1, and the review notes' item 8 stands)

## 1.1 gates

Everything built under the 1.1.1 name ships in 1.1, build 6 (decided September 13, 2026, before the first archive). Verified in the simulator:

- [x] SwiftData migration for the batched 1.1 properties verified against stores the 1.0 build 3 and an intermediate 1.1 build created
- [x] Apple Health dose sync by hand in the simulator: a dose logged in Health arrives on the foreground sync and counts toward supply; an undo in Health removes it
- [x] The store's move into the app group container observed on the simulator: a store at the legacy location moved with its sidecars, its originals retired, and the medication, doses and inventory intact
- [x] Bundle the FDA NDC Directory snapshot with `Tools/build_ndc_directory.py` (September 11 files, 112,246 products) and the RxNorm table with `Tools/build_rxnorm_table.py` (September 8 release), and re-run the unit tests
- [x] Publish the updated privacy policy page (Apple Health and NDC sections, corrected backup sentence); live at https://sparkbiscuit.me/meds/privacy/ with a September 13 effective date

Still to do, on a physical iPhone and in App Store Connect:

- [x] Push the privacy policy's dose-sync and widget sentences (Sparkbiscuit.github.io `3330616`, pushed September 13)
- [x] Archive with automatic signing so HealthKit and the App Group `group.com.christoforakis.Meds` join the app's App ID and the App Group joins the extension's (`com.christoforakis.Meds.MedsWidgets`): the 15:46 archive on September 13 created the extension's App ID and both store profiles with the capabilities; that archive then failed upload validation on a missing `NSHealthUpdateUsageDescription` (ITMS-90683), fixed in the project, so the upload comes from a fresh archive
- [ ] Update from the App Store 1.0 on a physical iPhone: the store moves into the app group, and history is intact
- [ ] Real bottles on a physical iPhone: printed NDC on retail and hospital-pharmacy vials and a manufacturer barcode on a box, through live scanning and the Review capture; on the two bottles from September 12, read the capture note first
- [ ] Widgets on a physical iPhone: Next Dose (small, medium, Lock Screen rectangular, circular, inline) and Runs Out Next; the Taken button logs the dose once and Today shows it; names redact on the locked Lock Screen
- [ ] Apple Health import and dose sync on a fresh install of a physical iPhone on iOS 26, including a medication scanned from a bottle and matched to Health by RxNorm
- [ ] The torch, and `Taken` and `Skip` reminder actions on a locked iPhone
- [ ] VoiceOver pass on the Apple Health screens, the NDC field, the identification notes, the pharmacy card, the calendar and the trip check
- [ ] Enter What's New, the description naming the Apple Health integration, the keywords, and the 1.1 review notes from `AppStore/SUBMISSION.md`; make the notes' item 2 true first
- [ ] Confirm App Privacy stays `Data Not Collected` per `AppStore/CONNECT_ANSWERS.md`

## 1.1.1 gates

1.1.1 is version 1.1.1, build 7, on the local branch `fix/1.1.1-supply-accuracy` (unpushed). What it changes and why is in `VERIFICATION.md` under September 24–25, 2026, and the designs are in `ARCHITECTURE.md`. Verified in the simulator:

- [x] Unit tests 416/416 and UI tests 14/14 on the iPhone 17 Pro simulator, iOS 26.5
- [ ] Unit tests 413/416 and UI tests 14/14 on the iPhone 17 Pro simulator, iOS 27.0: three rendered-label OCR tests read blurred and 12-point NDC print differently there, filling nothing wrong; see `VERIFICATION.md`, September 24–25, "iOS 27"
- [x] Release build for the iOS Simulator and for a generic iOS device (unsigned); app and widget extension both 1.1.1 (7)
- [x] No `@Model` change since 1.1: `Shared/Models.swift` is untouched, so there is no migration to verify and the 1.1 record stands
- [x] A request dated three days back on the demo store: Supply shows "Act soon" above the "was expected" line, and Today says "A refill needs checking"
- [x] Today's refill card at the largest accessibility text size, from screenshots; the scanned label's count row at that size, by UI test

### Device script

About 75 minutes on the day, starting by 08:30, after fifteen minutes of setup two days ahead. It runs on the spare iPhone on iOS 26 with the Mac beside it. Every medication below is a made-up test entry; never run this on a phone that holds anyone's real medications. In Meds Ahead's Settings, dose reminders and refill reminders are on. Write down what each step shows, pass or fail, before moving on. The steps also close the 1.1 gates still open above; tick those as their steps pass.

**Two days before, in the evening before 22:00**

1. **The 1.0 → 1.1.1 update keeps history (10 min).** Delete Meds Ahead from the spare iPhone. In Organizer, distribute `build/MedsAhead-1.0-Submission-Final.xcarchive` for development (Debugging) and install that build through Devices and Simulators. Finish onboarding, add two medications by hand (one with two daily times), log two doses, add a refill and correct a count. Screenshot Supply and each medication's Recent Activity. Then run 1.1.1 from Xcode onto the same phone without deleting anything. Pass: every medication, dose, refill and correction is there with the same numbers, and the Runs Out Next widget shows them, which it can only do from the store after its move into the app group. Then archive both, so their doses stay out of the steps below.
2. **Set up the count-needed check (5 min).** Add "Count Test", 2 tablets on hand, one tablet at 22:00 every day, and log nothing for it from now on. Write down its run-out date. The next morning, if you can, glance at Supply: the same date, marked as an estimate because 1 dose since the last count wasn't logged, with the 2 called "on record".

**On the day**

3. **Set up (5 min, by 08:40).** Add "Refill Test", 8 tablets on hand, one at 21:00 daily, Low supply 7 days before, Refills left blank: it runs out in seven days, so its low-supply alert is planned for 09:00 today. Add "Dose Test" (one at 09:05) and "Skip Test" (one at 09:15), 20 tablets each, each the only medication at its time, so their reminders carry Taken and Skip.
4. **No dose from before a schedule existed (3 min, after 08:30).** Add "First Day Test", 30 tablets, one at 08:00 and one at 20:00. Pass: Today does not show its 08:00 dose as due or overdue, and neither does the Next Dose widget. Tomorrow morning, the missed-dose card does not ask about today's 08:00.
5. **1b: the typed number is the one recorded (5 min).** On First Day Test, Add Refill, replace the number with 45 with the keyboard up, and tap Add Refill without dismissing it. Pass: the count rises by exactly 45. Correct Count, type a new number with the keyboard up, and tap Save Count. Pass: the count is that number. Correct Count once more and type "1,000": Save Count stays disabled.
6. **Taken from a locked phone, and a delivered refill alert survives it (10 min).** Lock the phone by 08:55 and leave it locked. At 09:00 the Refill Test alert arrives; leave it in Notification Center. At 09:05 the Dose Test reminder arrives: touch and hold, Taken. Pass: the refill alert is still in Notification Center after the Taken. Unlock, open Meds Ahead, and go back to Notification Center: still there. Dose Test's Recent Activity shows one dose, "Logged from reminder", and its count went down by one.
7. **Skip from a locked phone (5 min).** Lock the phone again. At 09:15, Skip from the Skip Test reminder. Pass: Skip Test shows one skipped dose and its count is unchanged, and the Refill Test alert is still in Notification Center.
8. **A refill running late brings the warning back (5 min).** On Refill Test, Refill Requested…, set the expected date three days ago, and save. Pass: Supply's row reads "Act soon · around" a date in orange, with "Refill requested · was expected" and the date under it; Today says "A refill needs checking"; the Runs Out Next widget shows Refill Test's day count in the attention colour, not "Refill on its way"; the delivered alert is still in Notification Center. Then open Refill Requested… again and set the date two days ahead. Pass: Supply shows the refill in place of the warning, the widget says "Refill on its way", and after you leave and reopen the app the delivered alert has gone.
9. **1h: a widget Taken, then Today (8 min).** Add "Widget Test", 20 tablets, one at a time ten minutes from now, and put the small Next Dose widget on the Home Screen: it shows Widget Test with Taken. Open Meds Ahead on Today, where the dose is offered. Go to the Home Screen without closing the app, tap Taken on the widget, and come back. Write down whether Today still offers that dose. If it does, 1h's display half reproduces: tap Taken, and pass is an "Already Logged" alert with nothing recorded. Either way, pass: Widget Test's Recent Activity shows one dose, "Logged from widget", and its count went down by one.
10. **Count needed after days of not logging (5 min).** Count Test from step 2. Pass: Supply says "Count needed" and that 2 doses since the last count weren't logged, with no date and never "Out of supply", and the Runs Out Next widget says "Count needed" for it. Open Correct Count: the field is empty and Save Count is disabled. Type 2 and save. Pass: Recent Activity reads "Count confirmed", and "Count needed" is gone.
11. **Real bottles (10 min).** A retail pharmacy vial, a hospital-pharmacy vial, and a manufacturer barcode on a box, each through live scanning and the Review capture; use the torch on one. On the two bottles from September 12, read the capture note first. For each, write down the NDC outcome the review screen states. Pass: Current amount is blank; "Label says N when full" appears with the label's count; Use N fills the field and the button then reads "Using N"; Add with the field blank still asks for an amount.
12. **VoiceOver on the changed screens (10 min).** Supply rows (a count-needed row says "Count needed" once; an attention row reads the warning before the refill status), Today's refill card, the detail screen's forecast card, the Add Refill and Correct Count sheets (the empty field and its footer), the refill status sheets, the "Already Logged" alert, and the scanned review screen's label-count row (Use N reads "Use N as the current amount"). Then the 1.1 screens still unchecked: the Apple Health screens, the NDC field, the identification notes, the pharmacy card, the calendar and the trip check.
13. **Apple Health on a fresh install (12 min).** This deletes the test data, so it comes last. Delete Meds Ahead. In Health, add two medications, one matching a bottle from step 11 and one that matches none, and log a taken dose for each. Install 1.1.1 from Xcode and onboard. Import from Apple Health, share both in Health's picker, and import only the one that matches no bottle, with its doses toggle on. Pass: its earlier dose shows in Recent Activity and does not charge the count. Scan the matching bottle and save it with a count. Pass: after leaving and reopening the app its count is unchanged, because the dose Health logged before it was added never charges it. Log a dose in Health for each and return to Meds Ahead. Pass: each arrives once, "Logged in Apple Health", and charges its count once, the scanned one through its RxNorm match. Undo one in Health and return: it is gone.

### Release

- [ ] Every step above passes, or its failure is written down and decided
- [ ] Merge `fix/1.1.1-supply-accuracy` into `main` and push
- [ ] Archive build 7 from that commit with automatic signing, validate in Organizer, and upload
- [ ] In App Store Connect, create version 1.1.1 with build 7 and paste the 1.1.1 What's New from `AppStore/SUBMISSION.md`; the description, keywords and review notes stand, with item 2 true
- [ ] Confirm App Privacy stays `Data Not Collected`: 1.1.1 adds no collection, no network request and no new Health access
- [ ] Publish only the accessibility declarations a phone pass verified (`AppStore/CONNECT_ANSWERS.md`): VoiceOver after step 12; Sufficient Contrast only after an Accessibility Inspector pass on a phone, since the `.contrast` audit proved unreliable (`VERIFICATION.md`, September 21); Differentiate Without Color Alone after checking the calendar's glyphs with the setting on
