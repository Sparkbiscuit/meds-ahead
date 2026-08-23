# Meds V1 Product Definition

## North star

Always know what is due, what happened, and what will run out next.

## Release scope

Meds V1 is an iPhone-only, offline-first application with:

- Live camera recognition of printed text and machine-readable codes
- Still-photo import for accessibility, testing, and unsupported devices
- Mandatory review of every scanned medication before saving
- Manual medication entry
- Daily and selected-weekday schedules
- As-needed medication support
- Taken and skipped dose logging
- Reversible inventory adjustments and refill additions
- Forecasted depletion dates with explicit uncertainty
- Configurable low-supply lead times
- Local notifications
- Full edit, archive, and delete controls
- Dynamic Type, VoiceOver, Reduce Motion, Reduce Transparency, dark mode, and high-contrast support

## Safety boundary

Meds organizes information entered or confirmed by the user. It does not:

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

