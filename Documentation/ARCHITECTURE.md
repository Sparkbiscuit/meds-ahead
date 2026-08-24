# Architecture

## Platform

- SwiftUI application targeting iOS 26.0+
- SwiftData local persistence
- VisionKit live scanning
- Vision text and barcode recognition for still images
- UserNotifications for local reminders and duplicate-safe dose logging actions
- StoreKit for optional, non-recurring consumable tips

## Data model

The app uses an append-oriented ledger:

- `Medication`: user-confirmed identity and display metadata
- `DoseSchedule`: recurring intended doses
- `DoseEvent`: taken or skipped observations
- `InventoryEvent`: opening counts, refills, corrections, losses, and discards

Current supply is derived from inventory events minus taken dose events. This preserves an audit trail and allows corrections without silently rewriting history.

Each scheduled time retains its own dose quantity and weekday mask. Editing schedules reconciles those definitions with existing `DoseSchedule` records instead of replacing them. Stable schedule identifiers keep earlier `DoseEvent` history associated with the correct intended dose. Count corrections compare the entered physical count with the raw ledger balance, including any negative discrepancy, before the displayed balance is clamped to zero.

## Privacy

The application has no account, advertising SDK, analytics SDK, cloud container, or medication lookup service. OCR and barcode recognition happen on device. Photo bytes are released after recognition and are not saved into the model store.

The optional tip jar loads only Apple's configured StoreKit products. Its row in Settings is always present and reports its own state — loading, available, or unavailable with a retry — rather than disappearing, so the purchase surface can always be found. Tips unlock no functionality. Verified tip transactions are finished at purchase time or on the next app launch; no developer payment server or medication data is involved.

The SwiftData store uses iOS data protection and remains available after the first device unlock so a person can log a reminder action while the iPhone is locked. It is deliberately left eligible for the user's own encrypted device and iCloud backups: a hand-built medication history cannot be recreated, and excluding it would silently destroy that history on a restore without protecting it from anyone. Reminder actions carry only internal medication and schedule identifiers; notification text remains generic unless the person explicitly enables medication names.

Refill reminders are only scheduled for a lead moment still in the future. Plans are rebuilt on launch and after every change, so an already-passed lead day would otherwise produce an immediate alert on top of the low-supply state the person is already looking at, and would fire again on every launch once dismissed. A supply that has already run out is surfaced in Today and Supply rather than pushed.

Notification planning is global across the medication set. Doses that occur at the same local time on the same weekday are consolidated into one slot-level request such as `8:00 PM meds are ready`; an identical seven-day slot collapses to one repeating daily request. A grouped notification opens Meds Ahead for review and does not expose one-tap Taken or Skip actions, because one action cannot safely represent several medications. A single-dose slot retains the privacy-aware quick actions. This reduces notification spam and keeps common polypharmacy routines comfortably below iOS's pending-notification ceiling while retaining exact weekday behavior.

## Scanner responsiveness

The live scanner's overlay reports which fields have been recognised so far. Deriving that runs the whole parse pipeline, including a match against the bundled name vocabulary, which costs far too much to sit in a SwiftUI body that re-evaluates on every recognised frame. `ScanPreview` is computed off the main actor, debounced, and cancelled when superseded, and the view only reads the stored result. The camera preview must never wait on parsing.

## Source confidence

Scan results retain field-level evidence. Barcode payloads are stored only when the user saves the reviewed medication. Pharmacy URLs and opaque prescription identifiers are never opened automatically.
