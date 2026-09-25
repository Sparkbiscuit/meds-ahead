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

**Folded into 1.2 on September 25, 2026.** 1.1.1 is not released on its own: its fixes ship in 1.2, build 8. Run the device script below on the 1.2 build, together with the 1.2 gates; its Release steps are superseded by 1.2's.

1.1.1 was version 1.1.1, build 7, on the branch `fix/1.1.1-supply-accuracy`. What it changes and why is in `VERIFICATION.md` under September 24–25, 2026, and, for the iOS 27 scanner and the release form, September 25; the designs are in `ARCHITECTURE.md`. Verified in the simulator:

- [x] Unit tests 472/472 and UI tests 16/16 on the iPhone 17 Pro simulator, iOS 26.5
- [x] Unit tests 472/472 and UI tests 16/16 on the iPhone 17 Pro simulator, iOS 27.0; the three rendered-label OCR tests that failed there at `a564dd6` pass (`VERIFICATION.md`, September 25)
- [x] Release build for the iOS Simulator and for a generic iOS device (unsigned), with no warnings; app and widget extension both 1.1.1 (7)
- [x] FDA NDC Directory snapshot regenerated with its release column (the FDA's September 24 product file: 112,571 products, 5,142 extended- and 1,856 delayed-release), and `Tools/build_ndc_directory.py --self-test` passes
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

### Scanning: the release form, and iOS 27

About 35 minutes, on any day after step 13, with 1.1.1 run from Xcode (a Debug build, so the review screen shows the capture note). Steps 14 and 15 run on the iOS 26 phone; step 16 needs an iPhone on iOS 27. Scan the bottles and cancel each review; save nothing scanned from them. What each step checks, and why, is in `VERIFICATION.md` under September 25, 2026, and `ARCHITECTURE.md` under "Exact identification".

14. **An immediate-release bottle one digit from its extended-release twin (10 min).** A Prograf or generic tacrolimus capsule bottle that prints its NDC. Scan it three times through live scanning and the Review capture, once holding the phone a little unsteady. For each, write down the code in the NDC field, the note the review screen shows, and the name and brand. Pass: never Astagraf XL and never "Tacrolimus ER". If a Prograf bottle's code reads 0469-0677, a 1 read as a 7, the note is "Code read, not used yet" or "Code read, but the label disagrees" and nothing is filled from it, and Prograf is not the brand unless the label prints PROGRAF. Then type the bottle's own code into the NDC field: the listing shown is the immediate-release product, and Use This Product fills it.
15. **An extended-release bottle (5 min).** A tablet or capsule bottle whose label prints ER, XL or XR and its NDC. Pass: when the note is "Identified by its NDC", the name or brand carries the release ("Tacrolimus ER", "Toprol XL"), and no scan fills an immediate-release product. If the code is not used, write down which note appeared and where the label prints the release: on the drug's line, the line under it, or only in a brand.
16. **iOS 27: small print, a shaken line, and the search of guesses (20 min).** On the iOS 27 iPhone, repeat step 11's retail and hospital-pharmacy vials and steps 14 and 15, then capture each code line once while moving the phone. For each, write down the note, the code, and the capture note's last part, which says "the label vouched for N alternate readings" when the search of Vision's lower-ranked guesses ran; time from tapping Review to the review screen, once with a manufacturer barcode in frame and once without. Pass: nothing wrong is filled on any capture; a label that says only TACROLIMUS is never filled as Prograf or Astagraf XL; a bottle whose code the review calls "Code read, not in the directory" still has its name from the label, and no guessed code fills anything; and a capture with a barcode the label agrees with does not run the search. The simulator takes about 5 seconds for the search; write down how long the phone takes.

### Release

Superseded by 1.2's release steps; kept as the record of what 1.1.1 would have needed.

- [ ] Every step above passes, or its failure is written down and decided
- [ ] Merge `fix/1.1.1-supply-accuracy` into `main` and push
- [ ] Archive build 7 from that commit with automatic signing, validate in Organizer, and upload
- [ ] In App Store Connect, create version 1.1.1 with build 7 and paste the 1.1.1 What's New from `AppStore/SUBMISSION.md`; the description, keywords and review notes stand, with item 2 true
- [ ] Confirm App Privacy stays `Data Not Collected`: 1.1.1 adds no collection, no network request and no new Health access
- [ ] Publish only the accessibility declarations a phone pass verified (`AppStore/CONNECT_ANSWERS.md`): VoiceOver after step 12; Sufficient Contrast only after an Accessibility Inspector pass on a phone, since the `.contrast` audit proved unreliable (`VERIFICATION.md`, September 21); Differentiate Without Color Alone after checking the calendar's glyphs with the setting on

## 1.2 gates

1.2, "First Days Home", is version 1.2, build 8, on the branch `feature/first-days-home` (pull request #2), which carries all of 1.1.1 and ships it. What it changes and why is in `VERIFICATION.md` under September 25, 2026 (1.2); the designs are in `ARCHITECTURE.md` under "Dated reminders, follow-ups and the weekly count check", "Courses", "Why this date?", "The quick count", "Scanning a dozen bottles" and "The same bottle twice". Verified in the simulator:

- [x] Unit tests 643/643 and UI tests 29/29 on the iPhone 17 Pro simulator, iOS 26.5
- [x] Unit tests 643/643 and UI tests 29/29 on the iPhone 17 Pro simulator, iOS 27.0
- [x] Release build for the iOS Simulator and for a generic iOS device (unsigned), with no warnings; app and widget extension both 1.2 (8); no DEBUG launch argument, seed or hook is in either Release binary
- [x] No `@Model` change since 1.1: `Shared/Models.swift` is untouched, so there is no migration to verify
- [x] Today's new cards, the course's words on Supply, the detail screen and Why This Date, and the planned-through notice, in light and dark and at Accessibility XXXL, from screenshots and UI tests

### Device script

About three hours across three days, on the spare iPhone on iOS 26, plus twenty minutes on an iPhone on iOS 27, after five minutes of setup a week ahead. Every medication below is a made-up test entry, and the bottles in steps 6 and 7 are any labelled bottles that can sit on a test phone: vitamins, over-the-counter bottles, empty vials. Never run this on a phone that holds anyone's real medications. Run 1.2 from Xcode over the build already on the phone, without deleting it. Write down what each step shows, pass or fail, before moving on.

**A week before, any time (5 min)**

1. **Set up the count check.** Archive every medication left from earlier scripts. Add "Count Check Test", 40 tablets on hand, one at 22:30 every day, with Dose reminders off and Refill reminders on, and do not count it again. In Settings, Weekly Count Check is on (the default) and Remind Again If Not Logged is off. Its question is due at 10:00 seven days later, which is day 1 below.

**Day 1**

2. **A course ending tomorrow, on Supply and the widget (10 min, by 09:00).** Add "Course Test", 12 tablets, one at 09:30 and one at 21:00, Course ends on, Last day tomorrow. Pass: the schedule footer says "Reminders stop after the last day."; Supply's row reads "Enough to finish the course on" tomorrow; the detail screen's forecast says the same with the tablets left after its last dose. Put Runs Out Next (medium) and Next Dose (small) on the Home Screen. Pass: Runs Out Next shows Course Test with a tick after any medication with a date.
3. **Taken on a dated reminder from a locked phone (5 min).** Lock the phone by 09:25. At 09:30 Course Test's reminder arrives: touch and hold, Taken. Pass: its Recent Activity shows one dose, "Logged from reminder", at 09:30 today, and the count is 11.
4. **The weekly count check and the quick count (10 min).** Leave the phone locked at 10:00. Pass: a reminder titled "Quick count" arrives at 10:00. Tap it. Pass: Today shows the missed-doses card with Count Check Test's 22:30 doses, and below it "Quick count: Count Check Test" with "Log or skip its missed doses above first, so they don't come off the new count." Turn on VoiceOver: the card reads its question and that line, then its two buttons. Turn it off, skip those doses on the missed-doses card, then Count Now. Pass: the count sheet names Count Check Test and its field is empty, since doses are assumed. Type 35 and save. Pass: the quick count card is gone and does not come back when you leave Today and return.
5. **Follow-ups (2 hours, mostly waiting, 10:10 to 12:40).** In Settings, turn on Remind Again If Not Logged. Add "Follow-up Test" (one at 10:30), "Logged Test" (one at 11:15) and "Widget Follow-up Test" (one at 12:00), 20 tablets each, each alone at its time.
   - At 10:30 leave the reminder. Pass: at 11:00 a second one arrives, "10:30 AM dose not logged yet", saying to check before giving it in case someone already did. Taken on it from the Lock Screen. Pass: Follow-up Test shows one dose, "Logged from reminder".
   - At 11:15, Taken on Logged Test from Today. Pass: nothing arrives at 11:45.
   - From 11:50 do not open Meds Ahead. At 12:00, when the Next Dose widget shows Widget Follow-up Test with Taken, tap Taken on the widget. Pass: nothing arrives at 12:30; opened afterwards, Recent Activity shows one dose, "Logged from widget".
6. **Twelve bottles in one session (25 min).** Add > Scan a Label, and scan twelve bottles one after another. For the first, enter what is on hand and one tablet at 22:15 every day; for the rest, turn on Taken as needed so they add no reminders. Enter an amount and tap Add on each. Pass: after each Add a new, empty scanner opens with nothing of the last bottle in it; the bar under the camera names the bottles saved, newest first, and from the sixth on the newest leads and the oldest names are the ones cut short. Tap Done after the twelfth. Pass: Medications lists all twelve. Write down how long the twelve took.
7. **The same bottle twice (10 min).** A second bottle of one product from step 6: the same drug and strength, another fill or another box. Add > Scan a Label and scan it. Pass: the review shows "Already in Meds Ahead:" with that medication and "Add this bottle to" it. Tap it, enter the bottle's amount, and add it. Pass: Medications still lists the medication once; its Recent Activity shows a refill of exactly that amount; the scanner's bar says "Added to" it. If the label shows a later expiry or more refills left than the first bottle's, the sheet says the earlier expiry and the lower number stay. If you have them, an extended-release bottle of a drug tracked in its immediate-release form gets no banner, and a generic bottle of a tracked brand shows the brand in parentheses.
8. **Why This Date against a counted bottle (10 min).** The first bottle from step 6. Count what is in it, and Correct Count with that number. Take one tablet out into a dish and tap Take Now. Open Why this date? from its detail screen, then from a touch and hold on its Supply row. Pass: it starts from the count you made and its time, shows 1 taken, and the number on record is your count less one; count the bottle again and it agrees. The date it ends on is the date Supply shows. Put the tablet back and record nothing for it.
9. **The evening dose and its follow-up (5 min).** At 21:00 Course Test's reminder arrives; leave it. Pass: at 21:30 its follow-up arrives. Taken on it.

**Day 2, the course's last day**

10. **Skip on a dated reminder (5 min).** Lock the phone before 09:30. At 09:30, Skip from Course Test's reminder. Pass: one skipped dose, the count unchanged. At 21:00, Taken on its reminder. Pass: that evening Supply still reads "Enough to finish the course on" today.

**Day 3**

11. **Reminders stop after the last day (10 min).** Do not open Meds Ahead before 10:05. Pass: no Course Test reminder at 09:30 and no follow-up at 10:00. Then open it. Pass: Today shows "Course Test's course finished on" yesterday, with Not Now and Archive; Supply's row says "Course finished" and the day; Runs Out Next no longer lists it. Turn on VoiceOver: the card reads its title and line together, then "Keep Course Test for now" and "Archive Course Test". Turn it off and tap Archive. Pass: it leaves Today and Supply, is under archived in Medications, and its Recent Activity has no new entry.
12. **VoiceOver on the new screens (15 min).** The course controls in the editor (Course ends, Last day, the footer); Settings' Remind Again If Not Logged and Weekly Count Check with their footers; Today's missed-doses card; Why This Date, where each line reads as one sentence with the signs said as words; the scanner's bar and Done; the "Already in Meds Ahead" banner and the Add this bottle sheet.
13. **iOS 27 (20 min).** On an iPhone running iOS 27, run 1.2 from Xcode. Add a course ending tomorrow and repeat step 3; turn on follow-ups and repeat the first part of step 5; scan three bottles in one session as in step 6; repeat step 7 with one of them; and put both widgets on the Home Screen. Pass: the same results as on iOS 26. If the 1.1.1 scanning steps 14 to 16 have not run on this phone, run them now.

### Release

- [ ] Every step above passes, or its failure is written down and decided
- [ ] The 1.1.1 device script above has also passed on this build, since 1.2 ships its fixes
- [ ] Merge `feature/first-days-home` into `main` (pull request #2) and push
- [ ] Archive build 8 from that commit with automatic signing, validate in Organizer, and upload
- [ ] In App Store Connect, create version 1.2 with build 8; paste the 1.2 What's New (new features and the 1.1.1 fixes), the promotional text, the description and the review notes from `AppStore/SUBMISSION.md`, with item 2 true of the passes above
- [ ] Confirm App Privacy stays `Data Not Collected`: 1.2 adds no collection, no network request and no new Health access; the new settings and cards remember their state in the app's own `UserDefaults`, which the privacy manifest already declares
- [ ] Publish only the accessibility declarations a phone pass verified, as for 1.1.1, with step 12 added to VoiceOver's
