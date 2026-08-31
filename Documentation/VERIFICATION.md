# Verification record

## August 30, 2026 (second pass) — responsiveness, tab routing, scanner pills

Four reports from using the previous build, each reproduced on the simulator
before acting.

- **App-wide sluggishness.** `MedicationListShareButton` declared four
  unfiltered `@Query` properties, and it lives in the Medications toolbar, so it
  is mounted for the whole session. Moving the share action out of Settings had
  quietly promoted four full-ledger observations — every dose and inventory event
  — from "only while a sheet is open" to "always". Only the active-medication
  check stays observed; the rest is fetched when the button is tapped.
  `RootView` was the larger lever and was already like this before today: it owns
  the `TabView`, so its four queries re-rendered every tab on every ledger write,
  while the values were only ever read at launch and on foregrounding. Every
  screen that mutates data replans notifications itself, so those became fetches
  too. Verified by hand: logging a dose still updates Today's counter and card.
  The PDF renderer was measured and exonerated — 25 medications render in 55 ms.

- **A detail view opened scrolled under the navigation bar and would not scroll
  back up.** Reported after using the scanner; the scanner turned out to be
  innocent. Bisected to opening and closing the Add sheet at all, then confirmed
  identical on the previous commit — pre-existing, not a regression. Cause: the
  Add tab committed `.add` as a selection and an `onChange` handler set it back,
  so the TabView switched to an empty tab and returned while a sheet was
  presenting, and the tab it bounced off came back with a stale scroll inset.
  Selection now routes through a binding that never commits `.add`. Confirmed
  fixed by the same reproduction.

- **Settings wore a person glyph**, which implies an account this app
  deliberately does not have. It is a gear now.

- **Scanner progress pills squashed instead of wrapping.** A fifth pill appeared
  with this pass's Refills indicator, and an `HStack` compresses every pill
  rather than wrapping. They now flow onto a second row at full size via a small
  `Layout`. Because the pills share the top band with the scan frame,
  `ScanFrameLayout` gained separate `topInset` (92) and `bottomInset` (64) in
  place of one symmetric `verticalInset`. Both the drawn outline and the
  recognition region use the same numbers, so the green frame still describes
  exactly where the scanner is reading.

Verified: 187 unit tests pass; scanner, Today, Supply, and the detail view
checked by hand on the iPhone 17 Pro simulator at default and accessibility text
sizes.

Known: at accessibility text sizes a wrapped second row of pills can still graze
the top of the scan frame. The band cannot grow without shrinking the region the
scanner actually reads, which is the worse trade.

## August 30, 2026 — pill-box session findings: doses, combination strengths, brand names

Seven defects found while entering a real week of a transplant patient's
medications from the bottles, each reproduced against source before acting.

Correctness:

- **No dose other than 1 could be entered.** A prednisone bottle dosed at 2.5
  tablets daily could not be recorded. `DoseSchedule.doseQuantity` was already a
  `Double` and the editor did contain a decimal field, but it rendered as bare
  right-aligned text beside the `Time` row's chrome, so it read as a label and was
  never found. It is now a filled, tappable field with a stepper — half-unit for
  tablets and capsules, whole-unit otherwise — with the label above the control so
  no unit name clips at either edge. Confirmed by hand: 2.5 tablets entered and
  saved, and the schedule row reads *2.5 tablets*.
- **A typed dose could be discarded by Save.** The field only wrote back on focus
  loss, and the Add toolbar button does not resign first responder, so typing 2.5
  and tapping Add saved the previous amount. The value is now tracked as it is
  typed. Confirmed by hand: typed and saved without dismissing the keyboard.
- **A combination strength lost its first ingredient.** A
  `SULFAMETHOXAZOLE/TRIMETHOPRIM 400-80 MG` label autofilled `80 mg`. The strength
  pattern now matches combination forms whole, and every captured strength is
  canonicalised, so the `50MG` and `5 mg` seen on two bottles the same evening now
  read alike.
- **`1,000 IU` matched as `000 IU`.** Grouped digits were not part of the number
  form, so a vitamin label offered a tenfold-wrong strength for confirmation.
- **Three real bottles produced unusable directions.** `is Filled: 8/13/2026 RPh:
  Mg by mouth 1 time each chew.`, `- capsule by mouth 2 tim agNe 8.5 mg total
  twice da`, and `like 2 tablets by mouth rednesdays, and fridays` were all
  accepted, because a bare ` by mouth` satisfied the old guard on its own. A
  candidate must now open with a direction verb or a dose phrase, carry a
  frequency, and be free of dispensing markers, dates, phone numbers, and OCR
  garbage. A sig wrapped across adjacent lines of one capture is assembled and
  re-tested. All three now yield a blank field.
- **A pharmacy imprint reached the name field.** A Zoloft bottle produced
  `Sertraline Hcl G1`. A trailing imprint token is dropped and the salt is cased,
  but only while two tokens still stand, so `Vitamin B12` is not truncated.
- **Guidance never updated.** The scanner said `Name matched — rotate for
  strength, quantity, and refill details` with every progress pill already lit,
  and its banner crossed the green frame. It now names only what is still missing,
  matches the pills' material and shape, and sits in the band below the frame.

Additions:

- A `brandName` field on `Medication`, filled from a curated 247-pair table.
  Scanning a generic supplies the brand; scanning a brand supplies the generic.
  Both appear on the editable review screen before anything is saved, and the
  brand prints on the shared list. Exact, letters-only matching with a trailing
  salt or release-form fallback — no fuzzy matching, because a plausible but wrong
  brand on a clinician's list is worse than a blank.
- Share Medication List moved from Settings onto the Medications screen toolbar.

Review findings, each fixed and covered by a regression test:

- Wrapped-sig assembly joined lines from different captures, so three unrelated
  readings could become `TAKE 1 TABLET Patient: Jane Doe TWICE DAILY` and print on
  the shared PDF. Lines now carry the evidence item they came from.
- Dispensing markers matched as substrings, rejecting `Apply lotion…` for `lot`
  and `Use on exposed skin…` for `exp`. They match whole words now, and `patient`
  and `doctor` were added.
- Renaming a medication kept the previous drug's brand. An autofilled brand is now
  replaced on rename; one typed by hand is left alone.
- The stepper's floor was its own step size, so a stored 0.5 mL dose would have
  been silently rounded up by the first tap.
- A refill count was treated as required scanner progress, which an OTC bottle
  never satisfies, leaving the banner nagging forever. It now has its own progress
  pill instead.

Verified:

- 187 unit tests pass on the iPhone 17 Pro simulator; the suite was 146 before
  this pass.
- Release app-target static analysis succeeds.
- **SwiftData migration confirmed empirically, not assumed.** A build of the
  previous commit was made in a detached worktree, installed, and used to create a
  medication, a schedule, and an opening inventory event in an on-disk store. The
  new build was then installed over it without uninstalling. The medication, its
  8:00 AM 1-tablet schedule, and the 42-unit ledger balance with its starting-count
  event all survived. `brandName` is declared with an inline default, matching how
  `refillRemindersEnabled` was added.
- End-to-end by hand on the simulator against rendered pharmacy labels: a Bactrim
  label yields name `Sulfamethoxazole / trimethoprim`, brand `Bactrim`, strength
  `400-80 mg`, and the assembled sig `TAKE 2 TABLETS BY MOUTH ON MONDAYS,
  WEDNESDAYS, AND FRIDAYS`; a tacrolimus label yields brand `Prograf` and clean
  directions.

Known and accepted: `isTrustedDirections` still admits a thin instruction such as
`Use daily`. It is shown for confirmation on an editable screen and is not worth
tightening at the cost of rejecting `TAKE AS DIRECTED`.

Still hands-on only: live-camera behaviour on a physical iPhone, including the
new banner placement over a real preview.

## August 28, 2026 (third pass) — audit fixes, unlogged-dose catch-up, delivery honesty

Findings from a full read of the app, each verified against source before acting.

Correctness:

- **Take Now could double-log a dose.** The medication detail screen wrote a
  `DoseEvent` with no `scheduleID` or `scheduledAt`, and Today matches a card to
  its log by both. So Take Now left the card reading *Due*, the natural next tap
  logged it again, and the supply was charged twice. Take Now now claims the same
  dose Today is offering, via one shared `ScheduleEngine.actionableDose`, and the
  UI-test overdue override moved into `ScheduleEngine.timingState` so the two
  screens cannot diverge under test either. Confirmed by hand on the simulator:
  Take Now on Furosemide leaves the 8:00 AM card reading *Taken · Logged*.
- **Take Now logged the wrong amount.** It used `schedules.first`, always the
  earliest of the day, so a 1-tablet morning and 2-tablet evening regimen
  recorded 1 at night. An unscheduled log now uses the schedule nearest that time
  of day, measured the short way around midnight.
- **As-needed forecasts always divided by thirty days** while only requiring
  three logged doses. A medication started ten days ago reported three times the
  runway it had, always in the optimistic direction. The rate is now measured
  over the history that exists, capped at thirty days, and the explanation says
  which window it used.
- `medicationQuantityText` trapped on any `Double` past `Int.max`; the count
  fields accept as many digits as a person can type, so a long entry crashed.
- Strength parsing gained `units` and `IU`, so insulin, heparin, and vitamin D
  labels no longer leave the field blank. Because a directions line quotes a
  dose in the same units ("Inject 10 units"), the strength is now read from
  non-direction lines first and only falls back to the whole label.
- Expirations more than six years out are rejected as an OCR slip on the year.
  Dates already past are kept: an expired package is real information.

Reminder delivery:

- **Nothing told anyone when reminders were off.** A refused or withdrawn
  authorization made scheduling a silent no-op, and `center.add` failures were
  discarded by `try?`. Both are now recorded by `NotificationHealth` on every
  pass and stated on Today with the action that fixes them.
- Plans are rebuilt when the app returns to the foreground. `task` runs once per
  view lifetime, so refill alerts — one-shot dates, unlike the repeating dose
  triggers — stopped being replaced for anyone who left the app closed.
- A prescription with no refills left warns on the longer of the person's lead
  time and a ten-day prescriber lead, and says a new prescription is what's
  needed. `refillsRemaining` had been scanned, decremented, and displayed, but
  never used.

Product:

- **New: unlogged doses stay answerable for two days on Today.** Today ended at
  midnight, so an evening dose nobody confirmed vanished with no screen left that
  could answer "did last night happen?" — and an unlogged dose reads as unspent,
  quietly stretching the forecast. Three compact rows, retroactively logged at
  their scheduled time, with a "Not Now" that sets them aside until tomorrow so
  someone tracking supply without logging is not nagged permanently.
- **The shared medication list is paginated onto US Letter pages.** It rendered
  as one page sized to its content — for a dozen-plus medications, a sheet about
  three feet tall that prints to nothing legible. Pages carry "Page n of m" and
  no medication is split across a break.
- The exported PDF is swept from the temporary directory at launch rather than
  left there indefinitely. Deleting it at share time would race an AirDrop still
  in flight.
- `-seed-missed-doses` backdates the demo schedules so the catch-up state can be
  driven by hand; the demo store is unchanged without it.

Copy and greeting:

- **The greeting said "Good evening" at three in the morning.** Evening was the
  fallback branch, so every hour before five fell into it. There are now four
  bands, with 22:00 to 04:59 reading "Good night" — a real hour to be awake and
  giving a dose in this house.
- The story sheet and onboarding name Lukas's age and that it is lung transplant
  care, sign off as Nick Christoforakis, and say "the app we needed". Em dashes
  are gone from the story, the onboarding, and the signature.
- The Share Medication List footer no longer promises "a one-page PDF", which
  stopped being true when the export was paginated.

Documentation:

- `README.md` said iOS 26.0; the project has targeted 18.0 since `8143b3e`.
- Test counts below supersede the 79/6 recorded in `RELEASE_CHECKLIST.md`.

Results:

- Unit tests: 146/146 (127 before, plus 19 covering every fix above), including
  the widened greeting-boundary cases.
- UI tests: 9/9, including the Today and editor accessibility audits, which now
  run against the added banner and catch-up card.
- Release static analysis on the app target: succeeded, no warnings beyond
  Xcode's no-AppIntents metadata-skip message.
- Hands-on simulator pass on iPhone 17: catch-up card logs and re-flows, Take Now
  reconciles with Today, notification banner renders and offers its action.

Still hands-on, unchanged from the passes below: App Store Connect upload and
server-side validation, tip IAP setup, locked-device reminder actions, the
VoiceOver order/rotor pass, the Focus-breakthrough check, and a physical-device
re-check of torch + live preview. **The banner's denied-permission and
partly-scheduled states have been driven in the simulator but not on a device.**

## August 28, 2026 (second pass) — torch fix, log-all-due, medication list PDF

- Fixed the hands-on finding that turning the flashlight on froze the live
  scanner: the torch is now driven on the AVCaptureDevice instance inside
  VisionKit's own session (found via its preview layer) instead of a second
  instance of the camera, whose configuration lock interrupted the session. A
  recovery nudge restarts scanning if the session still stops. **Needs a fresh
  physical-device check of torch + live preview together.**
- Scanner guidance is now state-aware: the photo-fallback screen no longer says
  to rotate a bottle in front of a camera that is off, and guides toward adding
  photos instead.
- New: "Mark all N due doses taken" on Today (confirmation-gated, each dose
  still logged individually at its scheduled time), and Settings → Your records
  → "Share Medication List", a one-page monochrome PDF of active medications,
  schedules, supply, refills, and expirations rendered on device.
- Unit tests: 127/127, adding medication-list document/PDF tests and a second
  rendered-label OCR test (OTC shape: package count wins over the dose printed
  in the directions; BEST BY named-month date).
- UI and accessibility tests: 9/9, adding the log-all-due flow.
- Release static analysis on the application target: clean.
- Simulator panel pass on iPhone 17 Pro: Today with the log-all shortcut
  (before/after states), the confirmation dialog copy, Settings share sheet
  producing a 19 KB PDF with correct live totals, the photo-fallback scanner
  states, and the full photo → OCR → review flow on a rendered Tacrolimus
  pharmacy label — every field (name via vocabulary, strength, form,
  directions, quantity 60, refills 2, DISCARD AFTER date, lot) prefilled
  correctly.

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

### Time Sensitive dose reminders (same day, later)

Dose reminders now carry `interruptionLevel = .timeSensitive` so they can break
through Focus modes; refill alerts stay `.active`. The entitlement lives in
`Meds/Meds.entitlements` and is wired through `CODE_SIGN_ENTITLEMENTS` in both
app configurations.

- `plutil -lint` passes on the entitlements file; full unit tests remain 120/120.
- Debug simulator build embeds the entitlement in the simulated entitlements
  (`Meds.app-Simulated.xcent`); `codesign -d --entitlements` on a simulator app
  reads the host slot and legitimately shows it empty.
- Release device build required `-allowProvisioningUpdates` once to regenerate
  the team provisioning profile with the Time Sensitive Notifications
  capability, then succeeded; the signed binary's entitlements contain
  `com.apple.developer.usernotifications.time-sensitive`.
- **The August 24 distribution artifacts are superseded**: the archive at
  `build/MedsAhead-1.0-Submission-Final.xcarchive` and the export in
  `build/AppStore-Submission-Final/` predate the entitlement and must not be
  uploaded. Re-archive and re-export; the App Store distribution profile will
  be regenerated with the capability during export. Re-run the strict
  signature, provisioning, privacy-manifest, and ZIP-integrity checks on the
  new IPA.
- New hands-on gate: with a Focus mode active on the paired iPhone, confirm a
  dose reminder breaks through and shows the system "Time Sensitive" chrome,
  and that Settings → Meds Ahead offers the per-app Time Sensitive toggle.

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
