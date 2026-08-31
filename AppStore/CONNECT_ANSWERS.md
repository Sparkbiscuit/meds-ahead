# App Store Connect answer sheet

Prepared for release 1.0 (build 1) on August 24, 2026. Owner-supplied release, availability, compliance, and review-contact decisions are recorded below.

## New app record

- Platform: iOS
- Name: `Meds Ahead: Supply Tracker`
- Primary language: English (U.S.)
- Bundle ID: `com.christoforakis.Meds`
- SKU: `through-ios-1` (immutable internal identifier created before the final public name; not customer-visible)
- User access: Full Access

## App information

- Subtitle: `Know what runs out next`
- Primary category: Medical
- Secondary category: Health & Fitness
- Content rights: No, the app does not contain, show, or access third-party hosted content
- License agreement: Apple's standard EULA
- Privacy policy URL: https://sparkbiscuit.me/meds/privacy/
- Support URL: https://sparkbiscuit.me/meds/support/
- Marketing URL: https://sparkbiscuit.me/meds/
- Copyright: `2026 Nicholas Christoforakis` (saved in App Store Connect)

## App Privacy

- Data collection: `No, we do not collect data from this app`
- Tracking: No
- Advertising identifier: Not used
- Privacy choices URL: Leave blank; Meds Ahead has no account, server-held data, or tracking choices

Medication records, label text, barcodes, schedules, dose logs, and inventory events remain on the iPhone. Photos are processed on device and are not retained by the app. Apple defines collection as transmitting data off-device in a way that remains accessible to the developer or partners; Meds Ahead performs no such transmission.

The local database is included in the user's own encrypted device and iCloud backups. That is not collection: the backup is made by iOS under the user's Apple Account, and neither Meds Ahead nor its developer can read it. `Data Not Collected` remains the correct answer.

## Age rating

Recommended questionnaire answers:

- Parental controls: No
- Age assurance: No
- Unrestricted web access: No
- User-generated content: No
- Messaging and chat: No
- Advertising: No
- Medical or Treatment Information: None
- Health or Wellness Topics: None
- All mature themes, sexuality, violence, and chance-based activities: None / No
- Made for Kids: No
- Override to higher age rating: Not Applicable
- Age suitability URL: Leave blank

Rationale: Meds Ahead stores and organizes information entered or confirmed by the person using it. It does not diagnose, offer treatment guidance, recommend or modify a dose, state what a medication is for or does, check interactions, or make wellness recommendations. Every field it derives from a label is shown in an editable review screen and is stored only after the person confirms it. On that basis `None` is accurate for both questions, and the expected global result is 4+.

Disclose accurately if App Review asks what the app knows about medications. Version 1.0 ships three things that are easy to mischaracterise, and none supplies medical information:

- A bundled list of roughly 12,900 medication *names* derived from RxNorm (`Meds/Resources/MedicationNames.txt`). It is used only to decide whether scanned text spells a real medication name, so a misread label cannot invent one. It carries no indications, dosing, warnings, or interactions — names only.
- A bundled table of roughly 270 generic-to-brand name pairs
  (`Meds/Resources/MedicationBrandNames.txt`). It supplies the other name a
  medication is sold under — `tacrolimus` and `Prograf` — so a shared medication
  list carries both, which is how a pharmacy counter and a specialist's intake
  form each ask for it. It is a name equivalence and nothing more: no
  indications, dosing, warnings, or interactions. Pairs are exact-match only,
  hand-verified, and deliberately omit any medication whose brands are not
  interchangeable — cyclosporine is absent because Neoral, Sandimmune and Gengraf
  are different products, and prednisone is absent because no brand for it is
  still in use. The field is shown for confirmation and is editable like every
  other scanned field.
- Apple's on-device `FoundationModels` system language model, used strictly to pick which recognised OCR line is the name, strength, directions, quantity, or refill count, and to repair an obvious OCR error in a name that the bundled vocabulary then has to confirm. It is never asked for, and cannot contribute, a medication fact of its own. If the model is unavailable the app falls back to deterministic parsing.

Risk note: this is a Medical-category app whose subject matter is prescriptions, and the questionnaire is applied by Apple, not self-certified. Apple may still set Medical or Treatment Information to `Infrequent/Mild` and land the rating at 12+. That outcome is acceptable and is not worth arguing; do not overstate the app's capabilities to avoid it, and do not understate the two items above to secure 4+.

Revisit this section if a release ever adds indications, dosing guidance, interaction checking, or a medication assistant that answers questions.

## Regulated medical device declaration

- Is this app a regulated medical device? No
- Rationale: Meds Ahead is an organization, reminder, logging, and inventory-forecast tool. It does not diagnose, prevent, monitor, predict, prognose, treat, or alleviate disease, and it does not recommend or modify treatment.

## Export compliance

- Uses non-exempt encryption: No
- Supporting plist value: `ITSAppUsesNonExemptEncryption = NO`
- Documentation upload: Not expected

Meds Ahead relies only on encryption supplied by Apple operating-system services and contains no proprietary cryptographic implementation.

## Version information

- Version: 1.0
- Build: 1
- Price: Free
- Promotional text: `Scan a label, confirm your schedule, and see a calm, explainable forecast for every medication in your routine.`
- Description and keywords: Use `AppStore/SUBMISSION.md`
- Screenshots: Upload the three files in `AppStore/Screenshots/6.9-inch/` in numeric order
- Export options: `AppStore/ExportOptions-AppStore.plist`
- Distribution artifact: **re-archive before uploading.** Every existing export under `build/` predates the scanner-performance, refill-notification, backup, camera-permission, and tip-surface changes, and none of them should be uploaded. Archive fresh from the current commit and export with `AppStore/ExportOptions-AppStore.plist`.

## Optional tip products

Meds Ahead uses Apple's permitted in-app-purchase tipping path. All three products are **Consumable**, non-recurring, and unlock nothing. Enter these case-sensitive product IDs exactly:

| Reference name | Product ID | Suggested U.S. price | Customer-facing name |
| --- | --- | ---: | --- |
| Small Tip | `com.christoforakis.Meds.tip.small` | $1.99 | Small Tip |
| Medium Tip | `com.christoforakis.Meds.tip.medium` | $4.99 | Medium Tip |
| Large Tip | `com.christoforakis.Meds.tip.large` | $9.99 | Large Tip |

For each product, add English (U.S.) localization, make it available in the same countries and regions as the app, set its price, and upload a review screenshot of Settings > Leave an Optional Tip.

The tip row in Settings is always present, in all three states: a disabled row with a spinner while StoreKit answers, the working button once products load, and an explicit `Tips Are Unavailable` row with a `Try Again` button if StoreKit returns nothing. It is never hidden. This is deliberate: the most common rejection for a first consumable is Guideline 2.1, "we were unable to locate the in-app purchases," which happens when a sandbox hiccup makes the entry point disappear for the reviewer. Suggested descriptions are respectively `A small thank-you for Meds Ahead.`, `A kind tip supporting continued development.`, and `A generous tip supporting continued development.`

The Account Holder must accept the current Paid Apps Agreement and complete Apple's tax and banking setup. Product metadata can take up to one hour to appear in the sandbox. Add all three products to the version 1.0 review submission; Apple requires the first consumable purchase to be submitted with a new app version.

## Accessibility declarations

Declare only the features verified in the submitted build:

- VoiceOver: Supported, pending final hands-on rotor/order pass
- Larger Text: Supported
- Sufficient Contrast: Supported
- Differentiate Without Color Alone: Supported
- Reduced Motion: Supported
- Dark Interface: Supported

Do not declare captions, audio descriptions, voice control, or switch control without a dedicated hands-on pass.

## App Review information

- Sign-in required: No
- Demo account: Not applicable
- Contact first name: `Nicholas`
- Contact last name: `Christoforakis`
- Contact phone: on file with the account holder; not recorded in this repository
- Contact email: `nick@christoforakis.com`
- Authorization: The owner explicitly authorized use of these details for App Review on August 23, 2026
- Review attachment: None required
- Review notes: Use the review notes in `AppStore/SUBMISSION.md`
- Camera: denying the camera prompt is a supported path. The scanner shows an explanatory screen with an `Open Settings` button and photo import stays available, so the reviewer is never left on a blank camera view.

Suggested review route: complete onboarding, choose Add, select Enter Manually, create a medication with a current count and schedule, then open Supply. On a supported physical iPhone, Add > Scan Label exercises on-device text and barcode recognition. Every recognized field is editable before save.

If the tip products are included, add: `Settings contains three optional, non-recurring StoreKit tip amounts. They do not unlock features; Meds Ahead remains fully functional for free.`

## Availability and compliance decisions

- Price: Free
- Initial countries or regions: All countries and regions available in App Store Connect
- EU Digital Services Act trader status: Non-trader, per the owner's direction; do not publish trader contact details in the EU
- App Review release: Recommended `Manually release this version`
- Pre-order: No
- App Clips, Game Center, subscriptions: None
- In-app purchases: Three optional consumable tip amounts, submitted with version 1.0

## Current official references

- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Age rating categories and values](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)
- [App information fields](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [Export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
- [Create consumable In-App Purchases](https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-consumable-or-non-consumable-in-app-purchases/)
- [Submit an In-App Purchase](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/)
