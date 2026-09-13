# AGENTS.md

Meds Ahead — iPhone medication supply manager. SwiftUI, SwiftData, iOS 18.0
floor, Xcode 26.6. On-device scanning (VisionKit/Vision), local notifications,
StoreKit tips, optional weak-linked FoundationModels. No account, no analytics,
no cloud, no network lookups.

## Map

- `Meds/Sources` — app code
- `Meds/Resources` — assets, privacy manifest, name vocabulary, FDA NDC Directory snapshot
- `Tools/build_ndc_directory.py` — rebuilds that snapshot from the FDA's files
- `MedsTests` / `MedsUITests` — tests
- `Documentation/ARCHITECTURE.md` — why the data model and scanner work as they do
- `AppStore` — submission copy

## Rules

Violating any of these is a defect, regardless of what the task asked for.

- **Never change an `@Model` as a side effect.** SwiftData migrations can destroy
  a person's on-device history. Stop and flag it instead.
- **The ledger is append-only.** Supply derives from inventory events minus taken
  dose events that count toward supply; history imported from Apple Health with
  a medication is stored with `countsTowardSupply` false and feeds only the
  as-needed rate, while a dose Health logs after the medication exists here is
  brought over by `HealthDoseSync` with it true and carries its
  `healthSampleID`. Correct a wrong number with a new event; never rewrite
  history. The one mirror exception: a Health sample the person undoes or
  changes in Health is removed or restated here, because the copy was never
  the person's entry in this app.
- **`ScheduleEngine` owns dose-slot identity.** Views ask it which slot a dose
  belongs to. Never answer that locally.
- **As-needed rates measure over the history that exists, capped at 30 days** —
  never a fixed 30-day divisor. An over-long estimate leaves someone without
  medication.
- **Scan preview stays off the main actor**, debounced and cancellable. The
  camera preview must never wait on parsing.
- **Medication names are gated twice**: vocabulary-confirmed, or
  `strengthAnchored`. A merely name-shaped line is dropped on purpose.
- **Notification planning is global** and consolidates same-time slots across
  medications. Never schedule per-medication requests.
- **An NDC never fills a field on its own word.** A code read by OCR must be
  corroborated by the label; a code from any source is refused when the label
  contradicts it; a refused code stays visible as the product code and fills
  nothing. The gate is `NDCIdentification`. A code the person types into the
  review screen's NDC field fills the identity only when they tap Use This
  Product on the listing shown to them: their reading of the bottle is the
  corroboration. The directory is bundled — never look a code up online.
- **Apple Health is read-only and per object.** Never request share
  authorization, never write to HealthKit, and keep HealthKit types inside
  `HealthMedicationImport.swift`.

## Conventions

- SwiftUI first; do not add UIKit to a file that lacks it.
- Colours, spacing, animation come from `AppTheme` / `Components`. Grep for an
  existing token before adding a value. Never invent a colour.
- Smallest change that solves the stated problem. No unrequested refactors,
  renames, or reformatting.
- New behaviour needs a test in `MedsTests`.
- Comments explain why a non-obvious decision was made, not what the line does.

## Build and test

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Meds.xcodeproj -scheme Meds \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```

Report pass/fail counts, then per failure the test name, file, line, and
assertion. Never paste a raw xcodebuild log. A build failure means tests never
ran — say so rather than reporting it as a test failure.
