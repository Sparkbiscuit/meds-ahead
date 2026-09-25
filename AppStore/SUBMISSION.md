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

Already tracking medications in Apple Health? On iOS 26 and later you can choose which ones to share, and Meds Ahead brings each one over for the same review. The doses you logged there in the last 30 days come along, so an as-needed medication has a usage rate from day one. It reads only what you choose and never writes to Health.

Key features:

- On-device medication label and barcode scanning
- Exact identification from the label's NDC, matched offline against the FDA directory, and printed on the shareable medication list
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

## 1.1.1 What's New (draft for Nick)

For version 1.1.1, build 7. A draft: read it against the build before pasting into App Store Connect > Version > What's New in This Version. It describes what the app does, not what it does for anyone's health. The description, keywords and review notes below stand for 1.1.1.

```
Fixes to the counts, dates and warnings:

- If a refill you marked as requested or ready runs two days late, or is due after your supply runs out, the low-supply warning comes back, and Meds Ahead asks whether the refill has arrived.
- Refill and expiration alerts stay in Notification Center while they are still true, instead of disappearing the next time the app opens.
- The run-out date no longer drifts later when doses go unlogged. Meds Ahead counts unlogged scheduled doses as taken, says so, and asks for a count when it can't tell what is left.
- A scanned label's count is offered with a Use button instead of filled in, because it is what the bottle held when full.
- Scanning takes a closer look at a hard-to-read NDC, and checks the label's brand and release, such as ER or XL, before filling in a product from the code.
- A medication added in the afternoon no longer shows that morning's dose as overdue.
- Add Refill and Correct Count record the number you typed.
- A dose already logged from the widget or a reminder is not logged again.
- Doses logged in Apple Health before you added a medication no longer count against its supply, and a logged dose stays logged after you change its time or travel.
- Clearer text on colored buttons in dark mode, missed days marked on the calendar, and correct plurals: 30 patches, 150 mL, 1 day.
```

## What's New in 1.1

Paste into App Store Connect > Version > What's New in This Version. Everything built under the 1.1.1 name ships in 1.1.

```
Exact identification. When a pharmacy label prints its NDC, or a package barcode carries one, Meds Ahead looks it up in a bundled copy of the FDA's National Drug Code Directory and fills in the exact product: name, brand, strength, and form. It does so only when the rest of the label agrees, and every field is still yours to confirm. When the small print is hard to read, it zooms in on the code line and reads it again, says whether a code was read, refused, or not in the directory, and lets you type the code off the bottle.

Apple Health. On iOS 26 and later, bring over medications you already track in Health. You choose which ones to share, Meds Ahead reads only those, and each goes through the same review. The doses you logged in the last 30 days come along, and doses you log in Health from then on are brought over whenever Meds Ahead opens and count toward the supply. Nothing is written back to Health.

Widgets. Put the next dose on your Home Screen or Lock Screen, with a Taken button when one medication is due, and see at a glance which medication runs out next.

Also new: the pharmacy, phone and Rx number read off the label with a Call button; mark a refill as requested or ready for pickup and the low-supply reminder pauses; a trip check in Supply; a person per medication for households with more than one; a reminder a week before a package expires; a month calendar of taken and skipped doses on every medication; and Meds Ahead may ask for a rating after you have logged a good number of doses, at most once per version.
```

## Review notes

Paste the block below into App Store Connect > App Review Information > Notes.
It answers the eight questions Apple sends new-app submissions, opens with what
1.1 changed, and says plainly that the Health integration is read-only, so a
reviewer never has to open a Guideline 2.1 or 5.1.3 request to learn either.

App Store Connect caps this field at 4,000 characters, and caps the Resolution
Center reply field at 4,000 separately. This block is 3945; re-count after any
edit. Paragraphs are deliberately unwrapped so pasting does not produce ragged
line breaks mid-sentence.

Before pasting, make item 2 true: it describes the hands-on pass on the iPhone
16 Pro that the 1.1 gates in the release checklist require (live scanning, the
torch, the Health import and dose sync, the widgets, locked-device reminder
actions, a sandbox tip), and it must not be submitted ahead of that pass.

`AppStore/REVIEW_REPLY.md` holds the 1.0 Resolution Center reply and the
screen-recording shot list; add the Health picker to the shot list if a
recording is requested again.

```
Answers to the questions App Review asks, updated for 1.1.

NEW IN 1.1: exact identification from a label's NDC or package barcode against a bundled, public-domain FDA National Drug Code Directory snapshot (name, brand, strength, form only), used only when the rest of the label agrees, always editable, with the code typeable off the bottle; a read-only Apple Health import on iOS 26 and later through Health's own per-medication picker, plus later Health doses for such a medication; Home and Lock Screen widgets (next dose with a Taken button; what runs out next); a pharmacy card with a Call button, refill-in-progress status, a trip check, a person per medication, expiration reminders, and a dose calendar. Nothing is written to Health.

1. DEMONSTRATION. A screen recording from a physical iPhone, from launch, is available on request: onboarding, both permission prompts, scanning, review, the Health picker, saving, logging a dose, the forecast, a widget, the tip purchase. No accounts, so no registration, login, or deletion; no content between users, so no reporting or blocking.

2. TESTED ON. iPhone 16 Pro, iOS 26: hands-on pass including live scanning, the torch, the Health import and dose sync, the widgets, locked-device notification actions, and a StoreKit sandbox tip. Simulators: automated unit and UI suites. iPhone only, portrait only, iOS 18.0 and later; the Health features need iOS 26.

3. FUNCTIONS AND AUDIENCE. Meds Ahead answers which medication runs out next. A person adds a medication by scanning, importing from Health, or typing, confirms every field, and sets a schedule. The app tracks doses, refills, and corrections, projects an explained run-out date, and sends dose and supply reminders. For people managing several medications, and caregivers. An organization and logging tool: no diagnosis, medical advice, dose recommendations, indications, interaction checks, or refill-eligibility decisions.

4. SETUP. No login, demo account, or sample files. Page through onboarding, tap Add, then Scan a Label at any prescription label; every field is editable before saving. Enter Manually reaches the same editor; Import from Apple Health lists what the person shares. Enter a count and a schedule and save. Today logs doses, Supply shows the forecast, Medications records refills and corrections. Declining the camera prompt is supported: the scanner explains why, offers Open Settings, and keeps photo import available.

5. EXTERNAL SERVICES. None: no backend, accounts, network requests, analytics, advertising, or third-party SDKs. Apple frameworks only: VisionKit and Vision for recognition; FoundationModels, Apple's on-device model, only to choose among lines the app already read, never a source of a medical fact; HealthKit, read only, per-object authorization for medications and their dose logs; WidgetKit and App Intents, the widgets reading the local database through an App Group; SwiftData, UserNotifications, StoreKit, PhotosUI, AVFoundation. Photos are not retained; Health data is never transmitted.

6. REGIONS. Identical in all regions. English (U.S.) only, nothing region-gated.

7. REGULATED INDUSTRY. Not a regulated medical device; no authorization required. Four bundled files hold names and packaging facts only: about 12,900 medication names derived from RxNorm (NLM, public domain); about 270 hand-verified generic-to-brand pairs; an FDA NDC Directory snapshot (public domain): name, brand, strength, dosage form; and an RxNorm concept-code table (NLM, public domain) for those NDCs. None carries indications, dosing, warnings, or interactions; no licensed material is included.

8. IN-APP PURCHASE. Three optional, non-recurring consumable tips that unlock nothing; every feature is free. Gear icon > Support Meds Ahead > Leave an Optional Tip: Small Tip $1.99, Medium Tip $4.99, Large Tip $9.99. The row is always visible, with an explicit unavailable state and a Try Again button.
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
