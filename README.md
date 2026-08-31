# Meds Ahead

Meds Ahead is an iPhone-first medication supply manager. It combines on-device label and barcode scanning with human-confirmed schedules, dose logging, inventory adjustments, and explainable refill forecasts.

## Product promise

Meds Ahead helps a person answer three questions without guesswork:

1. What is due today?
2. What did I actually take?
3. Which medication will run out next?

Medication records remain on the device. Scanned photos are processed locally and are not retained by default. Meds Ahead does not diagnose, recommend dose changes, or determine whether a prescription is legally eligible for refill.

## Requirements

- Xcode 26.6 or later
- iOS 18.0 or later
- An iPhone for live camera scanning; the simulator supports photo import and manual entry

## Build and test

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Meds.xcodeproj -scheme Meds \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```

## Repository map

- `Meds/Sources`: application code
- `Meds/Resources`: assets and privacy manifest
- `MedsTests`: forecasting and scan parsing tests
- `MedsUITests`: launch and critical-flow UI tests
- `Documentation`: product, architecture, privacy, and release decisions
- `AppStore`: submission copy and review notes
