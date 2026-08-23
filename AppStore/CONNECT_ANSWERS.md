# App Store Connect answer sheet

Prepared for release 1.0 (build 1) on August 23, 2026. Values marked **Owner input** cannot be completed accurately without the account holder.

## New app record

- Platform: iOS
- Name: **Owner input — final name pending**
- Primary language: English (U.S.)
- Bundle ID: `com.christoforakis.Meds`
- SKU: `meds-ios-1`
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
- Copyright: **Owner input — legal name and year**

## App Privacy

- Data collection: `No, we do not collect data from this app`
- Tracking: No
- Advertising identifier: Not used
- Privacy choices URL: Leave blank; Meds has no account, server-held data, or tracking choices

Medication records, label text, barcodes, schedules, dose logs, and inventory events remain on the iPhone. Photos are processed on device and are not retained by the app. Apple defines collection as transmitting data off-device in a way that remains accessible to the developer or partners; Meds performs no such transmission.

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

Rationale: Meds stores and organizes information entered or confirmed by the person using it. It does not supply diagnoses, treatment guidance, medication facts, dose recommendations, or wellness recommendations. Under Apple's current definitions, a medication organizer without app-provided medical guidance can accurately answer `None`; the expected global result is 4+. If a future release adds drug information, interaction checking, an AI medication assistant, or treatment guidance, this answer must be revisited.

## Regulated medical device declaration

- Is this app a regulated medical device? No
- Rationale: Meds is an organization, reminder, logging, and inventory-forecast tool. It does not diagnose, prevent, monitor, predict, prognose, treat, or alleviate disease, and it does not recommend or modify treatment.

## Export compliance

- Uses non-exempt encryption: No
- Supporting plist value: `ITSAppUsesNonExemptEncryption = NO`
- Documentation upload: Not expected

Meds relies only on encryption supplied by Apple operating-system services and contains no proprietary cryptographic implementation.

## Version information

- Version: 1.0
- Build: 1
- Price: Free
- Promotional text: `Scan a label, confirm your schedule, and see a calm, explainable forecast for every medication in your routine.`
- Description and keywords: Use `AppStore/SUBMISSION.md`
- Screenshots: Upload the three files in `AppStore/Screenshots/6.9-inch/` in numeric order
- Export options: `AppStore/ExportOptions-AppStore.plist`
- Verified local distribution artifact: `/private/tmp/Meds-AppStore-Export-OCRFinal/Meds.ipa` (temporary local path; rebuild after final naming)

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
- Contact first name, last name, phone, and email: **Owner input**
- Review attachment: None required
- Review notes: Use the review notes in `AppStore/SUBMISSION.md`

Suggested review route: complete onboarding, choose Add, select Enter Manually, create a medication with a current count and schedule, then open Supply. On a supported physical iPhone, Add > Scan Label exercises on-device text and barcode recognition. Every recognized field is editable before save.

## Availability and compliance decisions

- Initial countries or regions: **Owner input**
- EU Digital Services Act trader status: **Owner input**
- App Review release: Recommended `Manually release this version`
- Pre-order: No
- App Clips, Game Center, in-app purchases, subscriptions: None

## Current official references

- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Age rating categories and values](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)
- [App information fields](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [Export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance)
