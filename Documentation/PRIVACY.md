# Privacy design

Meds Ahead treats medication information as sensitive even when a particular privacy statute does not apply.

## V1 commitments

- Medication data stays in the app's protected local container, readable only after the device is first unlocked.
- The local store stays eligible for the user's own encrypted device and iCloud backups. A medication history entered by hand cannot be recreated, so excluding it would cost the user their records on a restore while protecting them from no one.
- No account is required.
- No advertising or behavioral analytics are included.
- Label photos are processed on device and are not retained.
- Codes that resolve to URLs are displayed as evidence but never opened automatically.
- Notifications use the medication display name only when the user enables detailed notification previews.
- `Taken` and `Skip` reminder actions carry only internal record identifiers and do not add medication details to a private notification.
- Medication records and their associated histories can be deleted by the user. Export is intentionally deferred until a safe, clearly labeled format is implemented.

## Camera

Camera access is resolved before the scanner is usable. A refusal is a supported state, not a failure: the scanner explains what the camera is for, links to Settings, and leaves photo import and manual entry available.

## Data deletion

Deleting a medication removes its schedules, dose history, and inventory ledger from the local store. App deletion removes the remaining local data.
