# Post-1.1 brief

> Status, September 24–25, 2026: 1.1.1 is version 1.1.1, build 7, still on
> the local branch `fix/1.1.1-supply-accuracy` (unpushed), and covers all of
> section 1. 1a, 1c–1g, 1i and 1j are fixed with tests (September 21). 1b:
> Add Refill and Correct Count now read the number from the text as typed, a
> defensive fix, since the simulator never reproduced the bug; the phone
> repro still says whether it ever failed. 1h: the write half is guarded
> (Today and Take Now ask the store first, and a stale tap writes nothing and
> says "Already Logged"); whether Today shows the widget's log is still the
> device check. Sections 4 and 6 are done, except that
> `LogNextDoseIntent.perform` still has no test of its own (its new slot
> check is tested through `ScheduleEngine.hasSlot`). Beyond this brief, a
> supply-accuracy review on September 24 added one attention rule with a
> bounded refill pause and a refill check, delivered alerts kept while still
> true, a run-out date that assumes unlogged doses were taken and asks for a
> count when it cannot tell, the first-day rule, scanned label counts offered
> rather than filled, and written-out plurals; see `VERIFICATION.md` and
> `ARCHITECTURE.md`. Left: the device script under "1.1.1 gates" in
> `RELEASE_CHECKLIST.md` (it also closes section 2's open 1.1 gates), the
> accessibility declaration (section 2), the archive and submission, a
> decision on three OCR tests that read blurred NDC print differently on the
> iOS 27 simulator (nothing wrong is filled; see `VERIFICATION.md`), and
> sections 3, 5 and 7.
>
> Status, September 21, 2026: 1a, 1c, 1d, 1e, 1f, 1g, 1i and 1j are fixed
> with tests on the local branch `fix/1.1.1-supply-accuracy` (unpushed); see
> `VERIFICATION.md`. 1b's UI test passes in the simulator, so it still needs
> the device repro before any fix; 1h still needs its device check. Section 4's
> contrast fixes are in too, measured from screenshots because the `.contrast`
> audit proved unreliable (see `VERIFICATION.md`). The NDC reading was
> measured under blur and the still pipeline's second look now runs on
> misread codes too, with the label choosing between readings. Sections 2,
> 3, 5 and 6 are untouched.
>
> Status, September 16, 2026: 1.1 is live (released September 14) and being
> shared with caregivers. Everything below was found in a read-only review of
> the code on September 16, 2026; nothing below is fixed yet.

Read `AGENTS.md` first. Line numbers are as of the 1.1 build 6 commit. Where an
entry says "needs a device check", the code path is real but whether it fails
depends on runtime behaviour nobody has watched yet; do the check before the
fix. Verify by running things, append to `VERIFICATION.md`, commit and push.

## 1. Supply-accuracy bugs in the live 1.1

Candidates for a 1.1.1 bug-fix release before the Pediatric Rare Disease Summit
on October 9. In priority order. The rules in `AGENTS.md` that constrain the
fixes:

- **The ledger is append-only.** Fixes change what the sync inserts or what the
  sheets record; never rewrite a stored event. The only deletions allowed are
  the Health mirror exception (a sample undone or changed in Health).
- **`ScheduleEngine` owns dose-slot identity.** 1c is fixed there, and the two
  local copies of the rule are removed in favour of it.
- **No `@Model` change as a side effect.** None of these fixes needs one:
  `Medication.createdAt` already exists (`Shared/Models.swift:136`). If a fix
  seems to need a stored property (a tombstone for deleted Health doses, say),
  stop, park it, and batch it into one deliberate `@Model` change with its
  migration verified once, as 1.1 did.
- **HealthKit types stay inside `HealthMedicationImport.swift`.** Anything
  injected for tests hands back app-side values.

### 1a. Health doses from before a medication existed charge its count

High. Effort S.

`Meds/Sources/HealthDoseReconciler.swift:92` only checks the 30-day window
(`record.date >= windowStart`); nothing compares a dose with when the
medication was added. `apply` (`Meds/Sources/HealthMedicationImport.swift:377-390`)
inserts every new sample with `countsTowardSupply: true`, although its own
comment says only doses logged after the medication existed count, and the
review screen's footer (`Meds/Sources/MedicationEditorView.swift:622`) promises
imported doses "do not count against the amount you enter now".

With the import toggle on (the default, `MedicationEditorView.swift:59`) the
history is stored as non-counting and the sync skips it, which is what the
simulator check saw. The failure is on the other two paths: a person imports
from Health and turns the toggle off, or scans a bottle that links to a Health
medication through NDC → RxNorm. The next launch or foreground inserts up to 30
days of Health doses as supply-charging. A 60-count bottle taken twice a day
reads 0 on hand, "No confirmed supply remains", with false low-supply alerts,
on a new user's first day.

- **Fix.** Pass `medication.createdAt` into `HealthDoseReconciler.plan` and
  skip any record dated before it. Filter inside the loop, not before
  `reported` is built (`HealthDoseReconciler.swift:154`): pre-filtering
  `records` would make the stored import history look undone in Health and
  delete it.
- **Test.** `HealthDoseReconcilerTests`: "a Health dose logged before the
  medication was added never charges the count", once with no stored history
  (toggle off, scanned bottle) and once with stored non-counting history, which
  must be neither re-inserted nor deleted.

### 1b. Add Refill and Correct Current Count likely save the old number

High, needs a 1-minute device repro first. Effort S.

`SupplyChangeSheet` (`Meds/Sources/MedicationDetailView.swift:677`) binds
`TextField(value:format:)` with `.decimalPad`, which has no Return key, and the
confirmation button (`:692-698`) passes the bound `quantity` to `onSave`
without committing the field. The August 30 device notes in `VERIFICATION.md` record exactly this
pattern failing for the dose field: the value wrote back only on focus loss,
and the toolbar button does not resign first responder. The editor was fixed;
this sheet was not.

Add Refill is prefilled with the suggested quantity, so typing 90 and tapping
Add Refill records the prefilled number. For Save Count the stale value equals
the current supply, so the guard at `MedicationDetailView.swift:144` returns,
nothing is saved, and the sheet closes as if it worked. Count corrections are
the app's main way to fix a wrong number.

- **Repro.** On a phone: open a medication, Add Refill, type a different
  number with the keyboard still up, tap Add Refill. Then Correct Current
  Count, type a new count, tap Save Count. If either records the old value, it
  reproduces.
- **Fix.** Reuse the editor's approach from `ScheduleDoseQuantityField`
  (`MedicationEditorView.swift:946-1035`): a text-backed field parsed with
  `Double.medicationQuantity(from:)` on each change and committed before
  `onSave`. The sheet accepts 0 for a count (`isValid`, `:652-654`), where the
  editor's field requires more than 0, so keep that difference.
- **Test.** A `MedsUITests` case with `-seed-demo-data`: type a new amount in
  each sheet, tap the toolbar button without dismissing the keyboard, and
  assert the on-hand count changed by that amount.

### 1c. Editing a dose time, or a time-zone change, makes logged doses look unlogged

High. Effort M.

`ScheduleEngine.loggedStatus` (`Shared/ScheduleEngine.swift:100-108`) matches a
log by `scheduleID` and a `scheduledAt` within 60 seconds of the slot.
`ScheduleReconciler` (`Meds/Sources/ScheduleReconciler.swift:55-61`) changes
`minutesAfterMidnight` in place on the reused schedule, so its comment at
`:33-35` ("a simple edit does not make a logged dose look pending again") is
not true. Slot dates come from `Calendar.autoupdatingCurrent` while
`scheduledAt` is an absolute date, so crossing time zones does the same.

Change 8:00 to 9:00 after today's 8:00 dose is logged: Today shows 9:00 as due,
the missed-doses card (`TodayView.swift:65-82`) lists the last two days' 9:00
slots as not logged, and Today's `record` (`:456`), Take Now
(`MedicationDetailView.swift:481`) and the widget (`WidgetSnapshots.swift:59`,
`LogDoseIntent.swift:51`) all accept a second Taken. Each one double-charges
supply, and an already-given dose shown as overdue after travel invites a
second dose. `NotificationActions.swift:100-104` and
`AdherenceSummary.swift:55-58` keep their own copies of the 60-second rule,
which `AGENTS.md` forbids.

- **Fix.** A `DoseSchedule` yields at most one dose per day, so match on
  `scheduleID` plus `calendar.isDate(scheduledAt, inSameDayAs: dose.date)` in
  `loggedStatus`. Make `NotificationDoseRecorder` and `AdherenceSummary` call
  it. `HealthDoseReconciler` already does (`:124`); its 16 tests must still
  pass.
- **Test.** `ScheduleReconcilerTests` has four tests and none covers this.
  Add "a logged dose stays logged after its time is edited" and "a logged dose
  stays logged after a time-zone change", including a change that moves the
  logged time across midnight.

### 1d. A failed Health query, or deleting a mirrored dose, turns history into charged doses

Medium. Effort S.

`Meds/Sources/HealthMedicationImport.swift:343-348` turns a thrown dose query
into `[]` (`try? ... ?? []`), and `HealthDoseReconciler.swift:153-159` then
deletes every mirrored event in the window as undone in Health. Separately,
`deleteDoseActivity` (`MedicationDetailView.swift:531-539`) deletes any dose
row, Health-mirrored or not. Either way the next good sync re-inserts those
samples with `countsTowardSupply: true`, including import history that was
stored as non-counting. The count drops silently, and a person's own deletion
is undone on the next foreground. The query failure is rare (the sync runs
while the phone is unlocked); the delete path is ordinary use.

- **Fix.** `guard let records = try? await ... else { continue }`, so a failed
  query changes nothing. 1a stops re-inserted pre-count history from charging.
  For a deleted mirrored dose after `createdAt`, either replace Delete on
  Health-mirrored rows with "Undo it in Health" copy, or keep a small
  ignored-sample list in `UserDefaults`. Not an `@Model` tombstone (parked).
- **Test.** `HealthDoseReconcilerTests` covers the reinsert rule once 1a lands;
  the failed-query case needs the injection in section 6.

### 1e. Brand and generic in Health, one medication here: doses flip on every foreground

Medium. Effort M.

`HealthDoseSync.run` (`Meds/Sources/HealthMedicationImport.swift:334-357`)
loops over every shared Health medication, archived ones included
(`HealthImportView.swift:133` shows them). The only guard is
`matches.count == 1`, one Health medication to one medication here; nothing
stops two Health medications matching the same one, and `expanded()` widens
brand to clinical drug on purpose. Each pass plans with only its own Health
medication's records but with all of that medication's stored events, so the
deletion loop (`HealthDoseReconciler.swift:153-159`) removes the other entry's
mirrored doses. `doseEvents` is snapshotted once (`:332`), so nothing
re-inserts them in the same run.

A brand entry archived after a switch to the generic is common. Every
foreground then alternates: one sync deletes the mirrored doses, the next
re-inserts them as supply-charging. The on-hand count and the as-needed
forecast swing between launches, and refill alerts can fire falsely.

- **Fix.** Group the shared Health medications by the medication they match
  here and plan once per medication with the union of their records. Keep the
  existing refusal when one Health medication matches two here.
- **Test.** Two Health concepts mapped to one medication: a second sync
  changes nothing. As a reconciler test over plain values if the grouping is
  pulled out as a function; otherwise with the section 6 injection.

### 1f. The 1.0 store move is not atomic

Medium, low likelihood. Effort S.

`StoreLocation.migrate` (`Shared/StoreLocation.swift:61-71`) copies the main
file first, straight to its final name, then the `-wal` and `-shm` sidecars.
Line 47 returns `.alreadyShared` whenever the main file exists, and only the
main file's size is checked (`:72-73`). If the process dies between the main
copy and the `-wal` copy (a background launch from a reminder right after an
auto-update, say), the next launch opens the shared store without its WAL and
loses un-checkpointed 1.0 history, or opens a partial file and shows "Medication
Data Unavailable" for good. The intact legacy store is never retried. Every 1.0
user goes through this once, and the loss cannot be undone.

- **Fix.** Copy all three files to temporary names in the group directory,
  check the main file's and the WAL's sizes, rename the sidecars into place,
  and rename the main file last, so its existence still means a finished
  move. That keeps the widget's rule intact: it only opens a store that
  exists.
- **Test.** `StoreLocationTests` has no interrupted-copy case. Pre-create a
  partial temporary copy with no main file and expect a clean `.moved`.

### 1g. Two Health syncs can run at once and insert a sample twice

Medium, uncertain: needs a device check. Effort S.

`RootView.swift:87` (`.task`) and `:98` (`onChange(of: scenePhase)` to
active) both call `HealthDoseSync.run`, and so does Check Now
(`SettingsView.swift:195`). `run()` snapshots `doseEvents` (`:332`), awaits a
HealthKit query per medication, then inserts with no re-check and no
single-flight guard; `healthSampleID` is not unique. If two runs overlap, each
new Health dose is stored twice and double-charges supply.

- **Check that settles it.** With a Health-linked medication, log a new dose
  in Health, cold-launch the app, and look for a duplicate row in Recent
  Activity. Then return to the foreground and tap Check Now at once. The open
  question is whether `scenePhase` reaches active after `.task` starts on a
  cold launch.
- **Fix.** Cheap enough to do either way: make `run` single-flight (a static
  in-flight task later callers await), and in `apply` skip any sample ID
  already in the store before inserting.
- **Test.** "Two overlapping runs insert once", with the section 6 injection.

### 1h. A widget Taken tap may not reach Today, which then offers the dose again

Medium, uncertain: needs a device check. Effort S if it reproduces.

`LogNextDoseIntent` runs in the widget extension only and saves from its own
container (`MedsWidgets/LogDoseIntent.swift:41-61`). Today gates `record()` on
its `@Query` arrays (`TodayView.swift:24-27`, `:456`), and `RootView` refetches
on foreground only for notification planning (`RootView.swift:116-128`). If
SwiftData does not merge the extension's write into the running app's
`@Query`, Today still shows the dose as due, and Taken inserts a second event.
The September 12 simulator check (`VERIFICATION.md:290-295`) looked at the
store row, not Today. This is the open gate at `RELEASE_CHECKLIST.md:85`.

- **Check that settles it.** Open Today, background the app, tap Taken on the
  widget, return to the app. If Today still offers Taken for that dose, it
  reproduces. Two minutes.
- **Fix, only if it reproduces.** Have Today re-read from the store when the
  scene becomes active, and have `record()` re-check with a fresh fetch before
  inserting.
- **Test.** The cross-process write is the device check; the fresh-fetch guard
  gets a unit test if it is pulled out as a function over a `ModelContext`.

### 1i. Dose reminders past the 60-request cap are dropped silently

Low. Effort M.

`NotificationPlanner.swift:61-64` promises a heavy regimen drops "the
farthest-out refill alert — never a dose", but line 226 applies
`prefix(maximumScheduledRequests)` to doses plus refill alerts, and dose
requests alone can pass 60. `NotificationService.swift:111-115` reports the
count after truncation, so `NotificationHealth` never sees the drop and the
Today banner says everything is fine. It takes about nine dose times whose
membership differs across all seven weekdays, which is unusual.

- **Fix.** Count dose requests before truncating and report the overflow
  through `NotificationHealth` as `partlyScheduled`. Planning stays global;
  the optional collapse into daily grouped requests is parked.
- **Test.** A `NotificationPlannerTests` case with more than 60 dose requests
  that expects the overflow reported. The existing cap test (`:271`) stops at
  58.

### 1j. A huge as-needed count can crash the app on every launch

Low. Effort S.

`Shared/ForecastEngine.swift:220-221` does `Int(rawDays.rounded(.down))` with
no clamp, and `Int(_:)` traps (`Shared/Quantity.swift:4-8` says so). Supply has
no upper bound anywhere. An as-needed count of about 18 digits (typed, pasted
or OCR-merged) with at least three logged doses traps in the forecast, which
runs at launch, so the app and the Runs Out widget crash every time and the
only way out is deleting the app and its history. Unlikely input,
unrecoverable result.

- **Fix.** When `rawDays` passes the three-year horizon the scheduled path
  already uses (`:155`), return the existing "extends beyond the forecast
  window" result. Optionally cap the editor, the supply sheet and the scanned
  quantity at a sane bound.
- **Test.** `ForecastEngineTests`: an as-needed medication with a supply of
  1e20 forecasts without trapping.

## 2. Physical-iPhone gates still open

1.1 is on real users' phones with its device gates unticked.

- **`RELEASE_CHECKLIST.md`, "1.1 gates", lines 83-90.** The 1.0 → 1.1 update
  (`:83`), real bottles (`:84`), widgets including "the Taken button logs the
  dose once and Today shows it" (`:85`), Health import and dose sync on a
  fresh install including a bottle matched by RxNorm (`:86`), the torch and
  locked-phone reminder actions (`:87`), the VoiceOver pass (`:88`). These are
  the paths behind 1a, 1e, 1f and 1h. About 45 minutes: install 1.0 on a spare
  device, add data, update, confirm history; run 1h's widget check; scan a
  bottle that is also in Health with history; use Taken and Skip on a locked
  phone. Tick or file each result. `:89` (What's New, description, review
  notes) and `:90` (App Privacy) are probably done since 1.1 is live; confirm
  in App Store Connect and tick them. Also still open: `:26` (hands-on
  VoiceOver), `:45-46` (locked-phone actions, scan energy check).
- **The App Store accessibility declaration.** The live listing still says the
  developer has not indicated which accessibility features the app supports,
  and `RELEASE_CHECKLIST.md:65` is unticked. `AppStore/SUBMISSION.md:37`
  already claims VoiceOver support, and `AppStore/CONNECT_ANSWERS.md:148-149`
  plans to declare Sufficient Contrast and Differentiate Without Color Alone,
  which fail today (section 4). Order: fix section 4, do the VoiceOver pass on
  the 1.1 screens, then publish only what was verified, before the October 12
  featuring nomination. Effort S.

## 3. 1.2 Spanish: where things actually stand

Nothing exists yet. `knownRegions` is `en, Base`
(`Meds.xcodeproj/project.pbxproj:285-288`); there is no `.xcstrings`,
`.strings` or `.lproj` in the repo and no Spanish draft anywhere under
Documents; the only explicit localization API in the code is
`MedsWidgets/LogDoseIntent.swift:14`. So the planned step, a native medical
reader reviewing AI-drafted strings, has nothing to review. The featuring
nomination is due October 12 for a release around November 1. A workable
schedule: reviewer file out by about October 5, nominate October 12, reviewed
strings imported by about October 22, submit about October 26.

The order of work:

1. **Catalog and region** (high, M). Add `Localizable.xcstrings` to `Meds/`
   and a separate one to `MedsWidgets/`: `Shared/` compiles into both targets
   and the extension resolves `Bundle.main` to itself. Add Spanish as a single
   `es` localization in neutral Latin-American medical wording, so es-US,
   es-MX and es-419 phones all fall back to it.
2. **Move String-typed UI to `LocalizedStringKey` / `LocalizedStringResource`**
   (high, L). About 410 English literals sit in `String`-typed code that
   Xcode's extraction skips (a heuristic count; about 221 more are already in
   auto-localized contexts). `EmptyStateCard` (`Meds/Sources/Components.swift:43-68`)
   renders `Text(title)` from a `String`, which is never localized; the same
   holds for `OnboardingPage` (`OnboardingView.swift:98-104`), the "Taken"
   action (`NotificationActions.swift:13`), the forecast explanations
   (`Shared/ForecastEngine.swift:131-240`), `RefillStatusText`
   (`Shared/RefillStatusText.swift:20-23`), form and inventory display names
   (`Shared/Models.swift:17-83`), the notification titles and bodies
   (`NotificationPlanner.swift:174-288`), the widget status lines
   (`MedsWidgets/RunsOutWidget.swift:108-111`) and the shared PDF list.
   Biggest files: `MedicationEditorView`, `ScannerView`, `SettingsView`,
   `MedicationDetailView`, `TodayView`, `MedicationListExport`. Change the
   shared components' parameters, wrap `String`-returning helpers in
   `String(localized:)`, leave `rawValue`s and stored identifiers alone. Go
   file by file; a file is done when its strings appear in the catalog after
   a build.
   - **Leave the stored dose notes alone** (low, S).
     `DoseEvent.appleHealthNote` (`Shared/Models.swift:339`) is compared as a
     match key (`HealthDoseReconciler.swift:89`, `:106`), and "Logged from
     reminder" (`NotificationActions.swift:115`) and "Logged from widget"
     (`LogDoseIntent.swift:59`) are stored too. Keep all three as fixed English
     sentinels, add a test asserting the exact string, and translate known
     sentinels only where the activity row renders them
     (`MedicationDetailView.swift:454-455`). No `@Model` change.
3. **Plural variations** (medium, M). Appending "s" already prints "30 patchs
   on hand" and "150 mLs" in the live English 1.1, on Supply, Today, the
   detail screen, reminders, widgets and the printed list: `SupplyView.swift:196`,
   `MedicationEditorView.swift:253`, `:985`, `MedicationDetailView.swift:349`,
   `:680`, `TodayView.swift:625`, `Shared/WidgetSnapshots.swift:72`,
   `MedicationListExport.swift:81`, `:94`, `NotificationPlanner.swift:325`,
   plus the count phrases in `AdherenceCalendarView.swift:39`,
   `SettingsView.swift:204`, `HealthImportView.swift:131`,
   `MedicationListExport.swift:104`, `:143` and `Components.swift:147`. Fix it
   once, here: one shared helper (e.g. `MedicationForm.quantityText(_:)`)
   backed by `String(localized:)` with plural variations in the catalog, or
   automatic grammar agreement (`^[\(n) \(unit)](inflect: true)`). Make each
   glued sentence one key: `ScannerView.swift:244-246` (use
   `.formatted(.list(type: .and))`), `NotificationPlanner.swift:261`,
   `SupplyView.swift:124`, `MedicationDetailView.swift:454-455`. Test in
   `MedicationQuantityTextTests`: patch, mL, 0.5 tablet.
4. **InfoPlist strings** (S). The camera and Health purpose strings exist only
   as `INFOPLIST_KEY_` build settings (`project.pbxproj:513-515`, `:550-552`),
   so the permission prompts will be English on Spanish phones. Add
   `InfoPlist.xcstrings` to the app target.
5. **AI draft, then native medical reader review.** Build to extract keys,
   Product > Export Localizations, draft the Spanish, hand the `.xcloc` to the
   reviewer, import the reviewed file.

Alongside, for the listing and the quality bar:

- **Store copy and tips** (medium, S). `SettingsView.swift:295` prefers the
  hard-coded English `TipStore.displayNames` (`TipStore.swift:10-14`) over
  `product.displayName`, so Spanish tip names from App Store Connect would
  never show; use `product.displayName` and add Spanish names for the three
  tips. Add a Spanish (Mexico) localization in App Store Connect (the US
  storefront shows it to Spanish-language users and indexes its keywords) and
  draft its name and subtitle (30 characters each), keywords (100), promo
  text, description and What's New in `AppStore/` as a reviewer file. Update
  review note 6 (`AppStore/SUBMISSION.md:100`, "English (U.S.) only") and the
  IAP localization line (`AppStore/CONNECT_ANSWERS.md:125`). The label parser's
  refill and quantity patterns are English-only (`ScanParser.swift:158-163`),
  so the copy says "Spanish interface", never Spanish-label reading. Spanish
  screenshots need Spanish sample data; `DemoData` is English-only.
- **Spanish test coverage** (low, S). Nothing launches with a Spanish locale.
  Add UI test variants with `-AppleLanguages (es) -AppleLocale es_US` running
  `.textClipped` on Today, Supply, the editor and onboarding; run once with the
  double-length pseudolanguage; add a unit test that fails when a catalog key
  has no `es` value or is stale. Watch the fixed 82 pt label column in the
  printed list (`MedicationListExport.swift:368`), the single-line widget
  headers (`NextDoseWidget.swift:106`, `RunsOutWidget.swift:119`) and the
  scanner buttons' `minimumScaleFactor` (`ScannerView.swift:281`, `:301`).
- **Spanish privacy and support pages.** sparkbiscuit.me/meds/es/ returns 404
  and both pages are English-only. Tracked in that site's notes.

## 4. Accessibility

White text on several fills fails contrast, and the dose calendar relies on
colour alone. Medium. Effort S.

- The missed-day fill is `Color.orange.opacity(0.85)`
  (`Meds/Sources/AdherenceCalendarView.swift:127`) with white text (`:134`):
  about 2.0:1 in light mode and 2.7-3.1:1 in dark. Caption text needs 4.5:1.
- White on the dark-mode accent (rgb 123, 203, 235) is 1.81:1: the calendar's
  complete days, and the selected weekday letters
  (`MedicationEditorView.swift:936-937`). The ten `.borderedProminent` buttons
  probably do the same in dark mode; not yet checked.
- The four day states differ only by fill; there is no
  `accessibilityDifferentiateWithoutColor` handling anywhere. Each cell does
  carry its own VoiceOver label (`:141-150`), so the hidden legend is fine.
- The Today audit (`MedsUITests/MedsUITests.swift:69-75`) leaves out
  `.contrast`.

**Fix.** In dark mode use dark text on accent fills, or add a darker dark-mode
or Increase Contrast variant to `AccentColor.colorset`, in both
`Meds/Resources/Assets.xcassets` and `MedsWidgets/Assets.xcassets`, not a new
colour in a view. Give missed cells dark text or a darker fill plus a small
glyph or outline. Add `.contrast` to a dark-mode run of the Today and editor
audits, and check the prominent buttons in Accessibility Inspector. This comes
before the accessibility declaration in section 2.

## 5. Summit

October 9. Low. Effort S.

- **Release builds have no demo data.** Seeding is `#if DEBUG` only
  (`Meds/Sources/RootView.swift:79-86`, `DemoData.swift:1`). Decide on a demo
  phone that holds only non-real sample medications: a Debug build with
  `-seed-demo-data` on a spare phone, or the App Store build with `DemoData`'s
  sample medications entered by hand. Never a phone that holds anyone's real
  medications.
- **Record the QR target.** Nothing says where the printed cards point. Make a
  separate App Store Connect campaign link (e.g. `ct=prds-summit-2026`) and
  encode it in the QR; the form
  `https://apps.apple.com/app/apple-store/id6804540619?ct=...&mt=8` resolves.
  That keeps summit installs apart from the community campaign's numbers.
  Scan-test a printed card before ordering, and record the URL in Nick OS.

## 6. Test gaps

Low. Effort M.

`HealthDoseSync.run` and `apply`, the code that inserts and deletes
supply-changing doses, have no tests: `MedsTests` references `HealthDoseSync`
only through `expanded` (`RxNormTableTests.swift:129-131`). `run()` builds
`HKHealthStore()` inline (`HealthMedicationImport.swift:324`), so its error
handling, creation-date handling, repeated runs and overlap cannot be tested.
1a, 1d, 1e and 1g all live there. `LogNextDoseIntent.perform` has no tests
either.

**Fix, as part of the section 1 fixes rather than on its own.** Inject a
shared-medications provider and a dose-records provider into `run()` that hand
back app-side values (codes, archived flag, `HealthDoseRecord`), so the tests
never touch HealthKit types. Then, with an in-memory `ModelContainer`: a
failed query leaves the ledger untouched; records from before `createdAt`
don't charge supply; two overlapping runs insert once; two Health medications
mapped to one medication are stable across syncs; a re-run after a person
deletes a mirrored dose does what 1d decides. The other gaps (slot identity
after an edit, an interrupted store move, more than 60 dose reminders, a huge
as-needed supply) are the tests listed under 1c, 1f, 1i and 1j.

## 7. Later / parked

- HealthKit background delivery for the dose sync; the foreground sync is
  enough for now.
- A persistent tombstone for Health doses deleted here; needs an `@Model`
  change, so batch it with a deliberate schema change.
- Consolidate weekday-varying reminder times into daily grouped requests, as a
  design change beyond 1i.
- Read directions, refills and quantity from Spanish-language pharmacy labels.
- Print the shared medication list in English from a Spanish-language phone,
  for US pharmacies and clinicians.
- Spanish support and privacy pages at sparkbiscuit.me/meds/es/ to go with the
  es-MX listing (tracked in that site's notes).

Before the session: read AGENTS.md; build and test with the command in AGENTS.md; append results to VERIFICATION.md.
