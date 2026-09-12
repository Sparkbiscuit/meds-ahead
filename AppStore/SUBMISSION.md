# App Store submission draft

## Name

Meds Ahead: Supply Tracker

## Subtitle

Know what runs out next

## Promotional text

Scan a label, confirm your schedule, and see a calm, explainable forecast for every medication in your routine.

## Description

Meds Ahead is a private medication organizer designed around the question other reminder apps miss: what will run out next?

Scan printed labels and barcodes on device, review exactly what was recognized, and fill in only what is missing. Create flexible schedules, log taken or skipped doses, add refills, make inventory corrections, and see an understandable supply forecast for each medication.

Key features:

- On-device medication label and barcode scanning
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

medication,medicine,refill,pill,reminder,schedule,tracker,inventory,dose,health

## Review notes

Paste the block below into App Store Connect > App Review Information > Notes.
It answers the eight questions Apple sends new-app submissions, so a reviewer
never has to open a Guideline 2.1 information request to get them.

App Store Connect caps this field at 4,000 characters, and caps the Resolution
Center reply field at 4,000 separately. This block is 3943; re-count after any
edit. Paragraphs are deliberately unwrapped so pasting does not produce ragged
line breaks mid-sentence.

`AppStore/REVIEW_REPLY.md` holds the near-identical Resolution Center reply and
the screen-recording shot list; keep the two in step.

```
Answers to the eight questions App Review asks new-app submissions.

1. DEMONSTRATION. A screen recording from an iPhone 16 Pro on iOS 26.6, beginning at app launch, is available on request. It shows onboarding, the camera permission prompt, live scanning of a printed prescription label, the editable confirmation screen, saving a medication with a schedule, the notification permission prompt, logging a dose, the supply forecast, and the optional tip purchase flow in Settings. There are no accounts, so no registration, login, or account deletion flow, and no user-generated content between users, so no reporting or blocking mechanism.

2. TESTED ON. iPhone 16 Pro, iOS 26.6: full hands-on pass including live scanning, the torch, locked-device notification actions, and a StoreKit sandbox tip purchase. iPhone 17 Pro and iPhone 17 simulators, iOS 26: automated unit and UI suites. iPhone only, portrait only, iOS 18.0 and later.

3. FUNCTIONS AND AUDIENCE. Meds Ahead answers which medication runs out next. A person adds a medication by scanning its pharmacy label or typing it in, confirms every recognized field on an editable review screen, and sets a schedule. The app tracks doses taken and skipped, refills, and inventory corrections, projects an explained run-out date for each medication, and sends dose and low-supply reminders. The audience is anyone managing several medications at once, and their caregivers. It is an organization and logging tool: it does not diagnose, give medical advice, recommend or modify a dose, state what a medication treats, check interactions, or determine refill eligibility.

4. SETUP. No login, demo account, or sample files are needed. Page through onboarding, tap Add, tap Scan a Label, and point the camera at any printed prescription label. Recognition runs on device and every field is editable before it is stored. Enter Manually reaches the same editor. Enter a count and a schedule and save. Today logs doses, Supply shows the forecast, and Medications > a medication records a refill or an inventory correction. Declining the camera prompt is supported: the scanner explains why, offers an Open Settings button, and keeps photo import available.

5. EXTERNAL SERVICES. None. No backend, accounts, network requests, analytics, advertising, or third-party SDKs. Core functionality is Apple frameworks running on device: VisionKit and Vision for text and barcode recognition; FoundationModels, Apple's on-device system model, used only to decide which recognized line is the name, strength, directions, quantity, or refill count and to repair an obvious OCR character error, never asked for and unable to contribute a medical fact of its own, with any name it proposes still checked against a bundled name list and deterministic parsing as the fallback; plus SwiftData, UserNotifications, StoreKit, PhotosUI, and AVFoundation. Scanned photos are processed in memory and not retained.

6. REGIONS. The app functions identically in all regions. English (U.S.) only, no region-gated features or data.

7. REGULATED INDUSTRY. Meds Ahead is not a regulated medical device and no authorization is required. Two bundled files contain medication NAMES only: roughly 12,900 names derived from RxNorm (U.S. National Library of Medicine, public domain), used solely so a misread label cannot invent a name, and roughly 270 hand-verified generic-to-brand name pairs. Neither carries indications, dosing, warnings, or interactions, and no licensed or protected third-party material is included.

8. IN-APP PURCHASE. Three optional, non-recurring consumable tips that unlock nothing; every feature is free. From any tab, tap the gear icon at top right, then Support Meds Ahead > Leave an Optional Tip, which presents Small Tip $1.99, Medium Tip $4.99, and Large Tip $9.99. The row is always visible, including an explicit Tips Are Unavailable state with a Try Again button if StoreKit returns nothing.
```

## App Store Connect selections

- Primary category: Medical
- Secondary category: Health & Fitness
- Price: Free
- App Privacy: Data Not Collected
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
