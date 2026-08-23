# Architecture

## Platform

- SwiftUI application targeting iOS 26.0+
- SwiftData local persistence
- VisionKit live scanning
- Vision text and barcode recognition for still images
- UserNotifications for local reminders and duplicate-safe dose logging actions

## Data model

The app uses an append-oriented ledger:

- `Medication`: user-confirmed identity and display metadata
- `DoseSchedule`: recurring intended doses
- `DoseEvent`: taken or skipped observations
- `InventoryEvent`: opening counts, refills, corrections, losses, and discards

Current supply is derived from inventory events minus taken dose events. This preserves an audit trail and allows corrections without silently rewriting history.

Editing a schedule reconciles definitions with existing `DoseSchedule` records instead of replacing them. Stable schedule identifiers keep earlier `DoseEvent` history associated with the correct intended dose. Count corrections compare the entered physical count with the raw ledger balance, including any negative discrepancy, before the displayed balance is clamped to zero.

## Privacy

The application has no account, advertising SDK, analytics SDK, cloud container, or medication lookup service. OCR and barcode recognition happen on device. Photo bytes are released after recognition and are not saved into the model store.

The SwiftData store uses iOS data protection and remains available after the first device unlock so a person can log a reminder action while the iPhone is locked. Reminder actions carry only internal medication and schedule identifiers; notification text remains generic unless the person explicitly enables medication names.

An every-day dose uses one repeating daily notification request. Selected-weekday schedules use one weekly request per selected day. This keeps common polypharmacy routines comfortably below iOS's pending-notification ceiling while retaining exact weekday behavior.

## Source confidence

Scan results retain field-level evidence. Barcode payloads are stored only when the user saves the reviewed medication. Pharmacy URLs and opaque prescription identifiers are never opened automatically.
