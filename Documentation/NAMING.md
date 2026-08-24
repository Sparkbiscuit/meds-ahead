# Naming direction

Checked August 23, 2026 against the U.S. Apple catalog through Apple's Search API and against current health, medication, pharmacy, and software products on the public web.

These are preliminary product-name checks, not trademark clearance. A zero exact-title result is encouraging, but the only conclusive App Store availability test is successfully reserving the name in App Store Connect. A trademark attorney should review the final choice before a broader commercial launch.

## Final decision

The owner approved `Meds Ahead` on August 23, 2026. Apple accepted and saved the full store title `Meds Ahead: Supply Tracker` in App Store Connect on the existing draft record.

- Visible app name: `Meds Ahead`
- App Store name: `Meds Ahead: Supply Tracker`
- Subtitle: `Know what runs out next`
- Positioning line: `Know what you have, and how long it lasts.`
- Bundle identifier: `com.christoforakis.Meds`
- Apple ID: `6804540619`
- Reservation evidence: App Store Connect displayed the new title with a `Saved` state.

The public catalog screen returned no case-insensitive exact match for either `Meds Ahead` or `Meds Ahead: Supply Tracker` before reservation. App Store Connect acceptance is the definitive availability evidence for this release, but it is not trademark clearance.

## Reservation history

An earlier draft record was started under `Through: Medication Supply`. The cancellation screen did not prevent Apple from finishing creation in the background. After the owner rejected that direction, the same unsubmitted record was renamed to `Meds Ahead: Supply Tracker`; no app using the rejected name will be submitted or shipped. The draft record's immutable SKU still reflects the abandoned working name, but SKUs are internal and are not shown to customers.

## Screening evidence

- Apple catalog method: [iTunes Search API documentation](https://developer.apple.com/library/archive/documentation/AudioVideo/Conceptual/iTuneSearchAPI/Searching.html), U.S. software results, `limit=200`, case-insensitive exact-title comparison.
- Candidate queries: [Supply](https://itunes.apple.com/search?term=Supply&entity=software&country=us&limit=200), [Through](https://itunes.apple.com/search?term=Through&entity=software&country=us&limit=200), [Course](https://itunes.apple.com/search?term=Course&entity=software&country=us&limit=200), and [Maneo](https://itunes.apple.com/search?term=Maneo&entity=software&country=us&limit=200).
- Direct-collision examples: [Keel on the App Store](https://apps.apple.com/us/app/keel-your-focus-anchor/id6759875026), [Keel health and medication product](https://mykeelapp.com/), [Kept medication tracker](https://play.google.com/store/apps/details?id=com.kept.med), [Steady medication reminder](https://apps.apple.com/us/app/steady-medication-reminder/id6777527858), [Counted habit tracker](https://apps.apple.com/us/app/counted-habit-tracker/id6757755920), [Apace healthcare systems](https://apace.systems/solutions.html), [Vigil Med](https://vigilmed.health/), [Tended on the App Store](https://apps.apple.com/us/app/tended-symptom-tracker/id6760765910), [Span Healthcare](https://app.span-healthcare.com/), [Metrum Research Group](https://metrumrg.com/), and [Ballast medical-device record](https://uspto.report/TM/88206330).

## Ruled out after current screening

- `Keel`: an active App Store productivity app uses the exact title, and current health products use Keel for prescription scanning, medication reminders, and refill tracking.
- `Kept`: a current medication reminder and tracker offers offline medication records, barcode scanning, refill and stock alerts, and similar privacy positioning; another iPhone health-record product also uses the name.
- `Steady`: a current iPhone medication-reminder app uses the exact brand, and multiple current medication and caregiver products use the same direction.
- `Until`, `Pace`, `Enough`, and `Remain`: exact U.S. Apple software titles surfaced in the current catalog screen.
- `Counted`: a current App Store habit tracker uses the brand in its title, and additional current counting and time/pay apps use or are preparing the same brand.
- `Apace`: current healthcare software connects pharmacies, payers, and care providers and includes chronic-condition and medication-management functions.
- `Accounted`, `Lasts`, `Allot`, `Assured`, `Surety`, and `Afore`: active accounting, estate, insurance, pension, or healthcare brands create strong category or meaning conflicts.
- `Vigil`: a current consumer medication product is preparing a nearly feature-for-feature `Vigil Med` launch.
- `Tended`: a current App Store chronic-illness journal includes medication routines, reminders, adherence, and refills.
- `Span`: current health platforms and apps use the name.
- `Metrum`: current drug-development and healthcare-AI companies use the name.
- `Ballast`: active medical-device trademark and health/wellness uses.
- `In Hand`: current patient-app and telehealth company uses the phrase in health care.
- `Evenly`: current wellness and health-tracking app.
- `Refill`, `Morrow`, `Plenty`, `Daymark`, `Vela`, `Scripta`, `Plena`, `Continuo`, `Repleo`, `Replio`, `Praeva`, `Numera`, `Metron`, `Sigla`, `Replete`, `Sorted`, `Handled`, `Margin`, `Trove`, `Almanac`, `Twelve`, `Doseful`, `DoseMark`, `Doseway`, `DoseKeeper`, `MedShelf`, and `DoseLedger`: exact app titles, current health/medication products, or strong adjacent-category conflicts surfaced during screening.

## Reservation sequence after selection

1. Attempt the exact App Store name in App Store Connect.
2. If accepted, record the reservation date and SKU.
3. Run a final exact-name and confusingly-similar trademark screen.
4. Update `CFBundleDisplayName`, submission copy, screenshots, website paths or headings, and the release archive.
5. Re-run unit tests, UI tests, Release build, static analysis, archive validation, and signed IPA verification.
