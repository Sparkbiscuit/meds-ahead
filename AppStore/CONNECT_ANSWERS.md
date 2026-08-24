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

Rationale: Meds Ahead stores and organizes information entered or confirmed by the person using it. It does not supply diagnoses, treatment guidance, medication facts, dose recommendations, or wellness recommendations. Under Apple's current definitions, a medication organizer without app-provided medical guidance can accurately answer `None`; the expected global result is 4+. If a future release adds drug information, interaction checking, an AI medication assistant, or treatment guidance, this answer must be revisited.

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
- Distribution artifact: `build/AppStore-Submission-Final/Meds.ipa`, exported from `build/MedsAhead-1.0-Submission-Final.xcarchive` after the final scanner, compact-field-label, and three-tip passes. Do not upload any earlier export.

## Optional tip products

Meds Ahead uses Apple's permitted in-app-purchase tipping path. All three products are **Consumable**, non-recurring, and unlock nothing. Enter these case-sensitive product IDs exactly:

| Reference name | Product ID | Suggested U.S. price | Customer-facing name |
| --- | --- | ---: | --- |
| Small Tip | `com.christoforakis.Meds.tip.small` | $1.99 | Small Tip |
| Medium Tip | `com.christoforakis.Meds.tip.medium` | $4.99 | Medium Tip |
| Large Tip | `com.christoforakis.Meds.tip.large` | $9.99 | Large Tip |

For each product, add English (U.S.) localization, make it available in the same countries and regions as the app, set its price, and upload a review screenshot of Settings > Leave an Optional Tip. Suggested descriptions are respectively `A small thank-you for Meds Ahead.`, `A kind tip supporting continued development.`, and `A generous tip supporting continued development.`

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
