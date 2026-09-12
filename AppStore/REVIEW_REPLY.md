# App Review reply — Guideline 2.1, Information Needed (1.0, build 3)

Apple's message is the standard new-app information request, not a report of a
broken feature. It asks for eight things; item 1, a screen recording from a
physical device, is the one that holds the review.

**The Reply field caps at 4,000 characters.** The text in Part 2 is 3,951, which
leaves room even if App Store Connect counts line breaks as two characters.
Re-count before pasting if you edit it.

Recorded on an iPhone 16 Pro running iOS 26.6 and uploaded on August 31, 2026.

---

## Part 1 — the screen recording (done; keep for the next submission)

Requirements Apple stated: physical device, latest OS, starts at app launch,
shows the typical flow through core features, and includes every permission
prompt and the in-app-purchase flow.

Record with Control Center > Screen Recording. **Delete the app first and
install a fresh copy**, or the camera and notification prompts will not fire and
the recording will be missing two of Apple's required items. Microphone off.

Shot list, in order:

1. Home screen, tap the Meds Ahead icon — the recording must begin at launch.
2. Onboarding, paged through to the end.
3. Today tab. Tap **Add**.
4. Tap **Scan a Label**. Let the camera permission prompt appear and **Allow**
   it — this is Apple's "prompts requesting access to sensitive data" item.
5. Scan a real prescription bottle. Hold it until fields populate.
6. The review screen: scroll it, and **edit one recognized field by hand** so it
   is visible that nothing is stored without human confirmation. Add a current
   count and a schedule. Save. Allow the notification prompt when it appears.
7. Back out to Today: tap a dose and mark it **Taken**, then show the log.
8. Supply tab: show the forecast and open one medication's explanation.
9. Medications tab: open the medication just created, show refill and inventory
   correction.
10. Settings (gear) > **Leave an Optional Tip** > the three tip amounts > tap one
    so the StoreKit purchase sheet appears. Cancel it. This is items 1 and 8.
11. Back out to Settings to show the tip row is a normal, always-present row.

Two to four minutes is right.

---

## Part 2 — reply text (3,951 characters; paste the block below)

```
The requested information follows; a screen recording is attached.

1. SCREEN RECORDING. Captured on an iPhone 16 Pro running iOS 26.6, beginning at app launch. It shows onboarding, the camera permission prompt, live scanning of a printed prescription label, the editable confirmation screen, saving a medication with a schedule, the notification permission prompt, logging a dose, the supply forecast, a refill and an inventory correction, and the optional tip purchase flow in Settings. There are no accounts, so no registration, login, or account deletion flow, and no user-generated content between users, so no reporting or blocking mechanism.

2. TESTED ON. iPhone 16 Pro, iOS 26.6: full hands-on pass including live scanning, the torch, locked-device notification actions, and a StoreKit sandbox tip purchase. iPhone 17 Pro and iPhone 17 simulators, iOS 26: automated unit and UI suites. iPhone only, portrait only, iOS 18.0 and later.

3. FUNCTIONS AND AUDIENCE. Meds Ahead answers which medication runs out next. A person adds a medication by scanning its pharmacy label or typing it in, confirms every recognized field on an editable review screen, and sets a schedule. The app tracks doses taken and skipped, refills, and inventory corrections, projects an explained run-out date for each medication, and sends dose and low-supply reminders. The audience is anyone managing several medications at once, and their caregivers. It is an organization and logging tool: it does not diagnose, give medical advice, recommend or modify a dose, state what a medication treats, check interactions, or determine refill eligibility.

4. SETUP. No login, demo account, or sample files are needed. Page through onboarding, tap Add, tap Scan a Label, and point the camera at any printed prescription label. Recognition runs on device and every field is editable before it is stored. Enter Manually reaches the same editor. Enter a count and a schedule and save. Today logs doses, Supply shows the forecast, and Medications > a medication records a refill or an inventory correction. Declining the camera prompt is supported: the scanner explains why, offers an Open Settings button, and keeps photo import available.

5. EXTERNAL SERVICES. None. No backend, accounts, network requests, analytics, advertising, or third-party SDKs. Core functionality is Apple frameworks running on device: VisionKit and Vision for text and barcode recognition; FoundationModels, Apple's on-device system model, used only to decide which recognized line is the name, strength, directions, quantity, or refill count and to repair an obvious OCR character error, never asked for and unable to contribute a medical fact of its own, with any name it proposes still checked against a bundled name list and deterministic parsing as the fallback; plus SwiftData, UserNotifications, StoreKit, PhotosUI, and AVFoundation. Scanned photos are processed in memory and not retained.

6. REGIONS. The app functions identically in all regions. English (U.S.) only, no region-gated features or data.

7. REGULATED INDUSTRY. Meds Ahead is not a regulated medical device and no authorization is required. Two bundled files contain medication NAMES only: roughly 12,900 names derived from RxNorm (U.S. National Library of Medicine, public domain), used solely so a misread label cannot invent a name, and roughly 270 hand-verified generic-to-brand name pairs. Neither carries indications, dosing, warnings, or interactions, and no licensed or protected third-party material is included.

8. IN-APP PURCHASE. Three optional, non-recurring consumable tips that unlock nothing; every feature is free. From any tab, tap the gear icon at top right, then Support Meds Ahead > Leave an Optional Tip, which presents Small Tip $1.99, Medium Tip $4.99, and Large Tip $9.99. The row is always visible, including an explicit Tips Are Unavailable state with a Try Again button if StoreKit returns nothing.
```
