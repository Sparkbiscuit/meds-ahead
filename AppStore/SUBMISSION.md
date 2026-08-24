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

Meds Ahead operates without an account or backend. Camera access is requested only when the user opens the scanner, and declining it is fully supported: the scanner then explains why it needs the camera, offers a direct link to Settings, and leaves photo import available. The simulator offers manual entry and photo import because live VisionKit scanning requires a supported physical device. No scanned photo is retained.

The app must not be used to make prescribing, dosing, or refill-eligibility decisions. All recognized label information is presented in an editable confirmation screen before it can be stored.

Suggested review path: complete onboarding, choose Add, select Enter Manually, add a name/current count/schedule, then open Supply. A supported physical iPhone is required to exercise the live text-and-barcode scanner; photo import remains available in the simulator.

Settings always shows the optional tip row, at Settings > Support Meds Ahead > Leave an Optional Tip. It presents three consumable amounts once StoreKit returns them, a spinner while it is loading, and an explicit unavailable state with a Try Again button if StoreKit returns nothing, so the purchase surface is never hidden. Tips are processed with StoreKit, are not recurring, and do not unlock content or functionality.

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
