# AGENTS.md

Meds Ahead — iPhone medication supply manager. SwiftUI, SwiftData, iOS 18.0
floor, Xcode 26.6. On-device scanning (VisionKit/Vision), local notifications,
StoreKit tips, optional weak-linked FoundationModels. No account, no analytics,
no cloud, no network lookups.

## Map

- `Meds/Sources` — app code
- `Meds/Resources` — assets, privacy manifest, name vocabulary
- `MedsTests` / `MedsUITests` — tests
- `Documentation/ARCHITECTURE.md` — why the data model and scanner work as they do
- `AppStore` — submission copy

## Rules

Violating any of these is a defect, regardless of what the task asked for.

- **Never change an `@Model` as a side effect.** SwiftData migrations can destroy
  a person's on-device history. Stop and flag it instead.
- **The ledger is append-only.** Supply derives from inventory events minus taken
  dose events. Correct a wrong number with a new event; never rewrite history.
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

## Conventions

- SwiftUI first; do not add UIKit to a file that lacks it.
- Colours, spacing, animation come from `AppTheme` / `Components`. Grep for an
  existing token before adding a value. Never invent a colour.
- Smallest change that solves the stated problem. No unrequested refactors,
  renames, or reformatting.
- New behaviour needs a test in `MedsTests`.
- Comments explain why a non-obvious decision was made, not what the line does.

## Parallel execution

Workers run concurrently in one checkout, each leased a disjoint file set.

- Edit only your assigned paths. Never tidy, revert, or reformat outside them.
- Peers' work is invisible to you and lands unpredictably. Do not wait for it or
  depend on it; your brief contains everything you need.
- Workers do not run `xcodebuild`. The coordinator builds and tests.
- No network, credential, deployment, or external-account actions.

## Build and test (coordinator only)

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Meds.xcodeproj -scheme Meds \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```

Report pass/fail counts, then per failure the test name, file, line, and
assertion. Never paste a raw xcodebuild log. A build failure means tests never
ran — say so rather than reporting it as a test failure.
