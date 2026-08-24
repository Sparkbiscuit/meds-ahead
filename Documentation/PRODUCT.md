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
- Still-photo import for accessibility, testing, and unsupported devices
- Mandatory review of every scanned medication before saving
- Manual medication entry
- Multiple daily and selected-weekday schedules, each with its own dose amount and days
- As-needed medication support
- Taken and skipped dose logging
- Reversible inventory adjustments and refill additions
- Forecasted depletion dates with explicit uncertainty
- Configurable low-supply lead times
- Consolidated time-slot notifications for simultaneous medications, privacy-safe `Taken` and `Skip` actions for single-dose alerts, and refill-to-Supply routing
- Full edit, archive, and delete controls
- Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, dark mode, and high-contrast support
- Optional, non-recurring StoreKit tips that unlock no features

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
- HealthKit import and reconciliation
- Server-side medication identification
