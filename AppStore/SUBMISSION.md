# App Store submission draft

## Name

Meds Ahead: Supply Tracker

## Subtitle

Know what runs out next

## Promotional text

Scan a label, confirm your schedule, and see a calm, explainable forecast for every medication in your routine.

## Description

Meds Ahead is a private medication organizer designed around the question other reminder apps miss: what will run out next?

Scan printed labels and barcodes on device, review exactly what was recognized, and fill in only what is missing. When a label prints its NDC, or a package barcode carries one, Meds Ahead looks it up in a bundled copy of the FDA's National Drug Code Directory and fills in the exact product: name, brand, strength, and form. It does so only when the rest of the label agrees, and every field is still yours to confirm. Create flexible schedules, log taken or skipped doses, add refills, make inventory corrections, and see an understandable supply forecast for each medication.

Already tracking medications in Apple Health? On iOS 26 and later you can choose which ones to share, and Meds Ahead brings each one over for the same review. It reads only the medications you choose and never writes to Health.

Key features:

- On-device medication label and barcode scanning
- Exact identification from the label's NDC, matched offline against the FDA directory
- Import from Apple Health on iOS 26 and later, read-only and one medication at a time
- Human-confirmed medication records
- Daily and selected-day schedules
- As-needed medication support
- Consolidated dose reminders that avoid same-time notification spam, with privacy-safe Taken and Skip actions when an alert represents one medication
- Taken and skipped dose history
- Dose and low-supply refill reminders
- Refill and inventory adjustments
- Explainable low-supply forecasts
- Private local storage with no account or advertising
- Dynamic Type, VoiceOver, dark mode, and reduced-motion support
- An optional, non-recurring tip jar; every app feature remains free

Meds Ahead is free. Every feature is included, there is nothing to unlock, and there is no subscription. An optional tip in Settings supports development and unlocks nothing.

I built Meds Ahead because my mother was managing more than a dozen medications and refills for my brother through his transplant care, and every app we tried was built around reminders rather than the question she actually needed answered: what runs out next?

Meds Ahead is an organization tool. It does not provide medical advice, recommend dose changes, or determine prescription refill eligibility. Always follow your prescription label and clinician's instructions.

## Keywords

medication,medicine,refill,pill,reminder,schedule,tracker,inventory,dose,health,caregiver,ndc

## What's New in 1.1

Paste into App Store Connect > Version > What's New in This Version.

```
Exact identification. When a pharmacy label prints its NDC, or a package barcode carries one, Meds Ahead now looks it up in a bundled copy of the FDA's National Drug Code Directory and fills in the exact product: name, brand, strength, and form. It only does so when the rest of the label agrees, the printed name remains the fallback, and every field is still yours to confirm.

Apple Health import. On iOS 26 and later, bring over medications you already track in Health. You choose which ones to share, Meds Ahead reads only those, and each one goes through the same review before it is saved. Nothing is written back to Health.

Also new: Meds Ahead may ask for a rating after you have logged a good number of doses, at most once per version.
```

## Review notes

Paste the block below into App Store Connect > App Review Information > Notes.
It answers the eight questions Apple sends new-app submissions, opens with what
1.1 changed, and says plainly that the Health integration is read-only, so a
reviewer never has to open a Guideline 2.1 or 5.1.3 request to learn either.

App Store Connect caps this field at 4,000 characters, and caps the Resolution
Center reply field at 4,000 separately. This block is 3927; re-count after any
edit. Paragraphs are deliberately unwrapped so pasting does not produce ragged
line breaks mid-sentence.

Before pasting, make item 2 true: it describes the hands-on pass on the iPhone
16 Pro that the 1.1 release checklist requires, and it must not be submitted
ahead of that pass.

`AppStore/REVIEW_REPLY.md` holds the 1.0 Resolution Center reply and the
screen-recording shot list; add the Health picker to the shot list if a
recording is requested again.

```
Answers to the questions App Review asks, updated for 1.1.

NEW IN 1.1. (a) Exact identification: an NDC printed on a label or carried in a package barcode is matched against a bundled, public-domain snapshot of the FDA National Drug Code Directory (product name, brand, strength, dosage form only) and prefills those fields, but only when the rest of the label agrees; every field stays editable. (b) Apple Health import, iOS 26 and later: Add > Import from Apple Health opens Health's own per-medication picker; the app reads only what the person ticks, never writes to Health, and each goes through the same editable review.

1. DEMONSTRATION. A screen recording from a physical iPhone, from launch, is available on request: onboarding, the camera prompt, live label scanning, the review screen, the Health picker and import, saving a medication with a schedule, the notification prompt, logging a dose, the forecast, and the tip purchase. No accounts, so no registration, login, or account deletion; no content between users, so no reporting or blocking.

2. TESTED ON. iPhone 16 Pro, iOS 26: hands-on pass including live scanning, the torch, the Health import, locked-device notification actions, and a StoreKit sandbox tip. iPhone 17 Pro and iPhone 17 simulators: automated unit and UI suites. iPhone only, portrait only, iOS 18.0 and later; the Health import needs iOS 26.

3. FUNCTIONS AND AUDIENCE. Meds Ahead answers which medication runs out next. A person adds a medication by scanning its label, importing it from Health, or typing it in, confirms every field, and sets a schedule. The app tracks doses, refills, and corrections, projects an explained run-out date, and sends dose and low-supply reminders. The audience is anyone managing several medications, and their caregivers. It is an organization and logging tool: no diagnosis, medical advice, dose recommendations, indications, interaction checks, or refill-eligibility decisions.

4. SETUP. No login, demo account, or sample files. Page through onboarding, tap Add, then Scan a Label at any prescription label; every field is editable before it is stored. Enter Manually reaches the same editor; Import from Apple Health lists what the person shares. Enter a count and a schedule and save. Today logs doses, Supply shows the forecast, Medications records refills and corrections. Declining the camera prompt is supported: the scanner explains why, offers Open Settings, and keeps photo import available.

5. EXTERNAL SERVICES. None: no backend, accounts, network requests, analytics, advertising, or third-party SDKs. Apple frameworks on device: VisionKit and Vision for recognition; FoundationModels, Apple's on-device model, used only to choose which recognized line is which field and to repair an obvious OCR error, unable to contribute a medical fact of its own; HealthKit, read only, per-object authorization; plus SwiftData, UserNotifications, StoreKit, PhotosUI, and AVFoundation. Photos are not retained. Health data is never transmitted.

6. REGIONS. Identical in all regions. English (U.S.) only, nothing region-gated.

7. REGULATED INDUSTRY. Not a regulated medical device; no authorization required. Three bundled files hold product names and packaging facts only: about 12,900 medication names derived from RxNorm (NLM, public domain); about 270 hand-verified generic-to-brand pairs; and an FDA National Drug Code Directory snapshot (public domain) trimmed to name, brand, strength, and dosage form, keyed by NDC. None carries indications, dosing, warnings, or interactions; no licensed material is included.

8. IN-APP PURCHASE. Three optional, non-recurring consumable tips that unlock nothing; every feature is free. Gear icon > Support Meds Ahead > Leave an Optional Tip: Small Tip $1.99, Medium Tip $4.99, Large Tip $9.99. The row is always visible, with a Tips Are Unavailable state and a Try Again button if StoreKit returns nothing.
```

## App Store Connect selections

- Primary category: Medical
- Secondary category: Health & Fitness
- Price: Free
- App Privacy: Data Not Collected (Health data is read on device and never transmitted; see `CONNECT_ANSWERS.md`)
- HealthKit: read-only medication import on iOS 26+; the description and the privacy policy both name it, as Apple requires
- Advertising identifier: Not used
- Tracking: No
- Regulated medical device: No; Meds Ahead is an organization and logging tool
- Export compliance: Uses only encryption provided by the operating system
- Content rights: No third-party streamed or hosted content
- In-App Purchases: Three optional consumable tip amounts; no subscription and no paid functionality

## Required account-owned values

- Copyright holder text
- Support URL: https://sparkbiscuit.me/meds/support/
- Public privacy-policy URL: https://sparkbiscuit.me/meds/privacy/
- Distribution bundle identifier and signing team
- App Review contact details
