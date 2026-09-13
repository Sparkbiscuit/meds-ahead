# Meds Ahead V1 Product Definition

## Origin

Meds Ahead was built for one household first: a mother managing more than a dozen
medications and their refills for her son through transplant care. That is the user
to picture. She is not short of reminders, she is short of certainty and time, and
she is often reading a label at the end of a long day.

Two consequences run through every decision here. Friction is the enemy, so a field
the app can reasonably pre-fill for review should never arrive blank and make her
retype what the label plainly says. And confidence must be earned, so where the app
genuinely does not know something it says so rather than inventing precision.

## North star

Always know what is due, what happened, and what will run out next.

## Release scope

Meds Ahead V1 is an iPhone-only, offline-first application with:

- Live camera recognition of printed text and machine-readable codes
- Exact identification from the NDC printed on a label or carried in a manufacturer barcode, resolved against a bundled FDA directory only when the label itself agrees; the printed name remains the fallback (1.1)
- Still-photo import for accessibility, testing, and unsupported devices
- Import of medications a person already tracks in Apple Health, on iOS 26 and later: read-only, chosen one by one in Health's own picker, each reviewed before it is saved, with the last thirty days of taken doses offered alongside so an as-needed medication has a usage rate from day one (1.1)
- Mandatory review of every scanned medication before saving
- Manual medication entry
- An optional Brand name field: scanning either a recognised generic or brand puts the generic and brand together on the editable review screen; entering a recognised name manually can fill the brand, which appears in medication subtitles and the printable list
- Multiple daily and selected-weekday schedules, each with its own dose amount and days
- Dose amounts that accept half and fractional values, including 2.5 tablets; tablet and capsule steppers use half-unit increments
- As-needed medication support
- Taken and skipped dose logging, including two days of catch-up for doses never logged
- Reversible inventory adjustments and refill additions
- Forecasted depletion dates with explicit uncertainty
- Configurable low-supply lead times
- Consolidated time-slot notifications for simultaneous medications, privacy-safe `Taken` and `Skip` actions for single-dose alerts, and refill-to-Supply routing
- A stated reminder-delivery state on Today when notifications are refused, never asked for, or partly rejected by iOS
- Earlier, differently worded low-supply warnings when a prescription has no refills left
- A paginated, printable medication list for appointments and pharmacy visits, available from the Share Medication List button in the Medications screen toolbar rather than Settings, carrying each medication's NDC or RxNorm code when one is known (1.1)
- Full edit, archive, and delete controls
- Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, dark mode, and high-contrast support
- Optional, non-recurring StoreKit tips that unlock no features
- A native rating request after a dose is logged, at most once per version and never within a season of the last (1.1)
- A second look for the NDC on a captured frame, an NDC field on the review screen that fills the identity from the FDA directory once the person chooses the listing, and a review screen that says whether a code was read, refused, or unlisted (1.1.1)
- Ongoing Apple Health dose sync for medications with an exact identity: doses logged in Health arrive on launch and on returning to the foreground, count toward supply, never double a dose logged here, and follow an undo in Health; still read-only (1.1.1)
- A bundled RxNorm slice that links a scanned bottle's NDC to its RxNorm concept and clinical drug, printed on the shared list (1.1.1)
- The pharmacy card: pharmacy, phone and Rx number read off the label, a Call button, and the pharmacy named in a detailed low-supply reminder (1.1.1)
- A refill marked requested or ready for pickup, which pauses the low-supply reminder and tells Today what to pick up (1.1.1)
- Trip check in Supply: pick the day you are back and see what runs out first (1.1.1)
- A person per medication, grouping Today, Supply and the shared list when a household names more than one (1.1.1)
- A package-expiration reminder a week ahead, under the refill-reminders toggle (1.1.1)
- A month calendar of taken, skipped and unlogged days on every medication, and a thirty-day count on the shared list (1.1.1)
- Home and Lock Screen widgets: the next dose with a Taken button when one medication is due, and which medication runs out next (1.1.1)

## Safety boundary

Meds Ahead organizes information entered or confirmed by the user. It does not:

- Recommend, prescribe, or change a dose
- Diagnose a condition
- Claim that a pharmacy can fill a prescription on a particular date
- Replace a prescription label, pharmacist, or clinician
- Infer a patient-specific regimen solely from a product barcode

## Forecast semantics

For scheduled medications, the forecast subtracts confirmed future scheduled doses from current on-hand supply. For as-needed medications, it uses recent logged consumption only when enough history exists and labels the result as an estimate. Missing or contradictory data produces an unknown forecast rather than false precision.

## Deferred beyond V1

- Caregiver or household accounts
- Cloud synchronization
- Pharmacy ordering
- Clinical interaction or contraindication checking
- Writing dose history to Apple Health
- Server-side medication identification
