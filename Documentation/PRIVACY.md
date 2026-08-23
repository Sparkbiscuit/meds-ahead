# Privacy design

Meds treats medication information as sensitive even when a particular privacy statute does not apply.

## V1 commitments

- Medication data stays in the app's protected local container.
- No account is required.
- No advertising or behavioral analytics are included.
- Label photos are processed on device and are not retained.
- Codes that resolve to URLs are displayed as evidence but never opened automatically.
- Notifications use the medication display name only when the user enables detailed notification previews.
- Medication records and their associated histories can be deleted by the user. Export is intentionally deferred until a safe, clearly labeled format is implemented.

## Data deletion

Deleting a medication removes its schedules, dose history, and inventory ledger from the local store. App deletion removes the remaining local data.
