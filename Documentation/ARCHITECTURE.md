# Architecture

## Platform

- SwiftUI application targeting iOS 18.0+
- SwiftData local persistence
- VisionKit live scanning
- Vision text and barcode recognition for still images
- UserNotifications for local reminders and duplicate-safe dose logging actions
- StoreKit for optional, non-recurring consumable tips
- FoundationModels on iOS 26+ where Apple Intelligence is eligible, weak-linked and entirely optional

## Deployment floor

The floor is iOS 18.0. FoundationModels was the only thing holding it at 26.0, and it is refinement, not capability: `interpret` selects among candidates the deterministic parser already produced, and returns that parser's result unchanged whenever the model is missing. That fallback is not new — it already covered every device without Apple Intelligence, which is most of them, since the model needs iPhone 15 Pro or newer. Below iOS 26 the same path simply runs for one more reason. The framework is weak-linked, so an iOS 18 device loads the app normally.

## Data model

The app uses an append-oriented ledger:

- `Medication`: user-confirmed identity and display metadata
- `DoseSchedule`: recurring intended doses
- `DoseEvent`: taken or skipped observations
- `InventoryEvent`: opening counts, refills, corrections, losses, and discards

Current supply is derived from inventory events minus taken dose events. This preserves an audit trail and allows corrections without silently rewriting history.

Medication identity keeps `brandName` as a stored field alongside the generic `name`. The empty default lets existing SwiftData records take the new field through a lightweight migration, and the reviewed value remains available to subtitles and exports without recomputation. `MedicationBrandIndex` uses a bundled curated table and exact, letters-only keys, with only a trailing salt or release-form suffix fallback. It resolves a generic or brand to its counterpart without a network lookup; fuzzy matching is deliberately excluded because a plausible but wrong brand on a clinician-facing list is worse than leaving the field blank.

A logged dose is matched to the slot it belongs to by schedule identifier and scheduled time, and every surface asks `ScheduleEngine` that one question rather than answering it locally. Take Now on a medication claims the same dose Today is offering, so one dose cannot be logged from both places and charged to the supply twice. Doses that were never logged remain answerable for two days on Today, because an unlogged dose reads as an unspent one and quietly stretches the forecast.

An as-needed rate is measured over the history that exists — the days between the first logged dose in the window and now, capped at thirty — rather than a fixed thirty days. Three doses taken this week divided by thirty reported four times the runway that existed, and an over-long supply estimate is the failure that leaves someone without medication.

Each scheduled time retains its own dose quantity and weekday mask. Editing schedules reconciles those definitions with existing `DoseSchedule` records instead of replacing them. Stable schedule identifiers keep earlier `DoseEvent` history associated with the correct intended dose. Count corrections compare the entered physical count with the raw ledger balance, including any negative discrepancy, before the displayed balance is clamped to zero.

## Privacy

The application has no account, advertising SDK, analytics SDK, cloud container, or medication lookup service. OCR and barcode recognition happen on device. Photo bytes are released after recognition and are not saved into the model store.

The optional tip jar loads only Apple's configured StoreKit products. Its row in Settings is always present and reports its own state — loading, available, or unavailable with a retry — rather than disappearing, so the purchase surface can always be found. Tips unlock no functionality. Verified tip transactions are finished at purchase time or on the next app launch; no developer payment server or medication data is involved.

The SwiftData store uses iOS data protection and remains available after the first device unlock so a person can log a reminder action while the iPhone is locked. It is deliberately left eligible for the user's own encrypted device and iCloud backups: a hand-built medication history cannot be recreated, and excluding it would silently destroy that history on a restore without protecting it from anyone. Reminder actions carry only internal medication and schedule identifiers; notification text remains generic unless the person explicitly enables medication names.

A prescription with no refills left needs a prescriber before a pharmacy can act, so it warns on the longer of the person's own lead time and a ten-day prescriber lead, and says which call to make. Refill reminders are only scheduled for a lead moment still in the future. Plans are rebuilt on launch, on returning to the foreground, and after every change, so an already-passed lead day would otherwise produce an immediate alert on top of the low-supply state the person is already looking at, and would fire again on every launch once dismissed. A supply that has already run out is surfaced in Today and Supply rather than pushed.

Notification planning is global across the medication set. Doses that occur at the same local time on the same weekday are consolidated into one slot-level request such as `8:00 PM meds are ready`; an identical seven-day slot collapses to one repeating daily request. A grouped notification opens Meds Ahead for review and does not expose one-tap Taken or Skip actions, because one action cannot safely represent several medications. A single-dose slot retains the privacy-aware quick actions. This reduces notification spam and keeps common polypharmacy routines comfortably below iOS's pending-notification ceiling while retaining exact weekday behavior.

Delivery can fail silently in two ways iOS reports quietly: a refused or withdrawn authorization, and an individual request the system declines to hold. Both outcomes are recorded by `NotificationHealth` on every scheduling pass and stated on Today, because an app that exists to remember a dose must not fail without saying so.

## Scanner responsiveness

The live scanner's overlay reports which fields have been recognised so far. Deriving that runs the whole parse pipeline, including a match against the bundled name vocabulary, which costs far too much to sit in a SwiftUI body that re-evaluates on every recognised frame. `ScanPreview` is computed off the main actor, debounced, and cancelled when superseded, and the view only reads the stored result. The camera preview must never wait on parsing.

## Label parsing

The parser is deliberately biased toward a blank directions field. Three real prescription bottles produced unusable directions under the old acceptance rule, which was willing to promote text that looked instruction-like but was actually pharmacy or OCR residue. A candidate now has to open with a direction verb or dose phrase, contain a frequency, and contain none of the dispensing markers, dates, phone numbers, or OCR garbage the label commonly contributes. A wrapped sig may still be assembled from up to three adjacent OCR lines, but the combined text must pass the same gate. The blank is intentional: a person can confirm or enter a missing direction, while a false instruction can change how they take a medication.

Strength is canonicalised as it is captured so casing and spacing variants such as `50MG` and `50 mg` become one display value. Combination strengths are matched before single-strength forms and retained as one value — `400-80 mg`, `5/325 mg`, or `800 mg/160 mg` — because keeping only a trailing component misstates the product; the old Bactrim path reduced its strength to `80 mg`.

## Autofill posture

Every scanned field is shown for confirmation before anything is stored, which sets
where the app should guess and where it should stay silent. A field the parser read
off the label is pre-filled even when the language model is unsure among several
candidates: the person can correct a wrong strength at a glance, but an empty field
costs them retyping what the label plainly says, and the audience is people already
carrying a lot.

The medication name is the exception, and it is gated twice. A name confirmed by the
bundled vocabulary is used. Otherwise only a `strengthAnchored` reading survives —
one found on the line that also carries the strength, which is where a drug name
actually sits. A merely name-shaped line is dropped, because "Open 9 to 6" or a
patient's own name in the medication field is worse than a blank one. `ScanParser`
reports this as `MedicationNameProvenance` so the distinction is explicit rather
than re-derived.

## Source confidence

Scan results retain field-level evidence. Barcode payloads are stored only when the user saves the reviewed medication. Pharmacy URLs and opaque prescription identifiers are never opened automatically.
