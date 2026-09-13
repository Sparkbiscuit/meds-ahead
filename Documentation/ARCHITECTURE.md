# Architecture

## Platform

- SwiftUI application targeting iOS 18.0+
- SwiftData local persistence
- VisionKit live scanning
- Vision text and barcode recognition for still images
- UserNotifications for local reminders and duplicate-safe dose logging actions
- StoreKit for optional, non-recurring consumable tips and the native rating request
- FoundationModels on iOS 26+ where Apple Intelligence is eligible, weak-linked and entirely optional
- A bundled snapshot of the FDA National Drug Code Directory for exact identification, with no lookup service behind it
- HealthKit on iOS 26+ for a read-only, per-medication import of what a person already tracks in Apple Health

## Deployment floor

The floor is iOS 18.0. FoundationModels was the only thing holding it at 26.0, and it is refinement, not capability: `interpret` selects among candidates the deterministic parser already produced, and returns that parser's result unchanged whenever the model is missing. That fallback is not new — it already covered every device without Apple Intelligence, which is most of them, since the model needs iPhone 15 Pro or newer. Below iOS 26 the same path simply runs for one more reason. The framework is weak-linked, so an iOS 18 device loads the app normally.

## Data model

The app uses an append-oriented ledger:

- `Medication`: user-confirmed identity and display metadata
- `DoseSchedule`: recurring intended doses
- `DoseEvent`: taken or skipped observations
- `InventoryEvent`: opening counts, refills, corrections, losses, and discards

Current supply is derived from inventory events minus taken dose events. This preserves an audit trail and allows corrections without silently rewriting history.

A dose event carries `countsTowardSupply`. It is true for everything the app logs itself. History imported from Apple Health is stored with it false: those doses were taken before Meds Ahead was keeping the count the person just entered, so they feed the as-needed rate and appear in history but never charge the supply. It was added with an inline default and taken through the same lightweight migration `brandName` was.

Medication identity keeps `brandName` as a stored field alongside the generic `name`. The empty default lets existing SwiftData records take the new field through a lightweight migration, and the reviewed value remains available to subtitles and exports without recomputation. `MedicationBrandIndex` uses a bundled curated table and exact, letters-only keys, with only a trailing salt or release-form suffix fallback. It resolves a generic or brand to its counterpart without a network lookup; fuzzy matching is deliberately excluded because a plausible but wrong brand on a clinician-facing list is worse than leaving the field blank.

A logged dose is matched to the slot it belongs to by schedule identifier and scheduled time, and every surface asks `ScheduleEngine` that one question rather than answering it locally. Take Now on a medication claims the same dose Today is offering, so one dose cannot be logged from both places and charged to the supply twice. Doses that were never logged remain answerable for two days on Today, because an unlogged dose reads as an unspent one and quietly stretches the forecast.

An as-needed rate is measured over the history that exists — the days between the first logged dose in the window and now, capped at thirty — rather than a fixed thirty days. Three doses taken this week divided by thirty reported four times the runway that existed, and an over-long supply estimate is the failure that leaves someone without medication.

Each scheduled time retains its own dose quantity and weekday mask. Editing schedules reconciles those definitions with existing `DoseSchedule` records instead of replacing them. Stable schedule identifiers keep earlier `DoseEvent` history associated with the correct intended dose. Count corrections compare the entered physical count with the raw ledger balance, including any negative discrepancy, before the displayed balance is clamped to zero.

## Privacy

The application has no account, advertising SDK, analytics SDK, cloud container, or medication lookup service. OCR and barcode recognition happen on device. Photo bytes are released after recognition and are not saved into the model store.

The optional tip jar loads only Apple's configured StoreKit products. Its row in Settings is always present and reports its own state — loading, available, or unavailable with a retry — rather than disappearing, so the purchase surface can always be found. Tips unlock no functionality. Verified tip transactions are finished at purchase time or on the next app launch; no developer payment server or medication data is involved.

The SwiftData store uses iOS data protection and remains available after the first device unlock so a person can log a reminder action while the iPhone is locked. It is deliberately left eligible for the user's own encrypted device and iCloud backups: a hand-built medication history cannot be recreated, and excluding it would silently destroy that history on a restore without protecting it from anyone. Reminder actions carry only internal medication and schedule identifiers; notification text remains generic unless the person explicitly enables medication names.

A prescription with no refills left needs a prescriber before a pharmacy can act, so it warns on the longer of the person's own lead time and a ten-day prescriber lead, and says which call to make. Refill reminders are only scheduled for a lead moment still in the future. Plans are rebuilt on launch, on returning to the foreground, and after every change, so an already-passed lead day would otherwise produce an immediate alert on top of the low-supply state the person is already looking at, and would fire again on every launch once dismissed. A supply that has already run out is surfaced in Today and Supply rather than pushed.

Notification planning is global across the medication set. Doses that occur at the same local time on the same weekday are consolidated into one slot-level request such as `8:00 PM meds are ready`; an identical seven-day slot collapses to one repeating daily request. A grouped notification opens Meds Ahead for review and does not expose one-tap Taken or Skip actions, because one action cannot safely represent several medications. A single-dose slot retains the privacy-aware quick actions. This reduces notification spam and keeps common polypharmacy routines comfortably below iOS's pending-notification ceiling while retaining exact weekday behavior.

Delivery can fail silently in two ways iOS reports quietly: a refused or withdrawn authorization, and an individual request the system declines to hold. Both outcomes are recorded by `NotificationHealth` on every scheduling pass and stated on Today, because an app that exists to remember a dose must not fail without saying so.

## Scanner frame

The green frame is a promise about where the scanner is reading, so the drawn
outline and `DataScannerViewController.regionOfInterest` are one rectangle: the
screen measures the outline's own frame and the scanner view's frame in one
coordinate space and hands the difference to the scanner, which reaches up under
the navigation bar while the outline does not. The frame's top edge is measured
from the pill row above it rather than assumed, because the row wraps onto a
second line at large text sizes and a frame sized for one row had the second
row lying across it. The exact-match state changes the Name pill's symbol and
nothing else; retitling it widened the row into that same second line.

## Scanner responsiveness

The live scanner's overlay reports which fields have been recognised so far. Deriving that runs the whole parse pipeline, including a match against the bundled name vocabulary, which costs far too much to sit in a SwiftUI body that re-evaluates on every recognised frame. `ScanPreview` is computed off the main actor, debounced, and cancelled when superseded, and the view only reads the stored result. The camera preview must never wait on parsing.

## Label parsing

The parser is deliberately biased toward a blank directions field. Three real prescription bottles produced unusable directions under the old acceptance rule, which was willing to promote text that looked instruction-like but was actually pharmacy or OCR residue. A candidate now has to open with a direction verb or dose phrase, contain a frequency, and contain none of the dispensing markers, dates, phone numbers, or OCR garbage the label commonly contributes. A wrapped sig may still be assembled from up to three adjacent OCR lines, but the combined text must pass the same gate. The blank is intentional: a person can confirm or enter a missing direction, while a false instruction can change how they take a medication.

The product line is chosen once and the strength and the name both come from it:
the first line that is not a sig and reads as a name once its strength is set
aside, else the first line that is not a sig and carries a strength at all. "Not
a sig" is judged on sig vocabulary anywhere in the line, not only on how it
opens, because a wrapped sig opens mid-sentence after the wrap — "(25 MG) BY
MOUTH EVERY 6 HOURS" — and restates the dose in parentheses; that line used to
be taken for the product line, the name search ran on it, found nothing, and
the real product line below was never consulted. A sig that passes the gate on
its own first line is carried on through the adjacent lines that continue it,
up to five in one capture, as long as every continuation reads as sig text and
the whole still passes the same gate; a package count, a warning sticker and
the product line never continue a sig.

Strength is canonicalised as it is captured so casing and spacing variants such as `50MG` and `50 mg` become one display value. Combination strengths are matched before single-strength forms and retained as one value — `400-80 mg`, `5/325 mg`, or `800 mg/160 mg` — because keeping only a trailing component misstates the product; the old Bactrim path reduced its strength to `80 mg`.

## Autofill posture

Every scanned field is shown for confirmation before anything is stored, which sets
where the app should guess and where it should stay silent. A field the parser read
off the label is pre-filled even when the language model is unsure among several
candidates: the person can correct a wrong strength at a glance, but an empty field
costs them retyping what the label plainly says, and the audience is people already
carrying a lot.

The medication name is the exception, and it is gated twice. A name confirmed by the
bundled vocabulary is used. Otherwise only a `strengthAnchored` reading survives —
one found on the line that also carries the strength, which is where a drug name
actually sits. A merely name-shaped line is dropped, because "Open 9 to 6" or a
patient's own name in the medication field is worse than a blank one. `ScanParser`
reports this as `MedicationNameProvenance` so the distinction is explicit rather
than re-derived.

## Exact identification

A label's National Drug Code names the product exactly — labeler, drug, strength,
package — where the printed name is a reading to be gated. `ScanParser` has read
`NDC 0093-1039-01` off labels since 1.0 and stored it unused; 1.1 resolves it.
`NationalDrugCode` reduces every rendering a label uses (the three native 4-4-2,
5-3-2 and 5-4-1 layouts, the padded 5-4-2 layout, and bare digits of either) to
the eleven-digit form, and decodes the GTIN inside a manufacturer barcode, which
is the ten-digit code wrapped in a `3` and a check digit. A hyphenated code
printed without its NDC caption is read as well, in the native layouts only:
bare digits without the caption are not, because a phone number and a
prescriber's NPI have the same shape. Small print is the ordinary case for this
line, so the still-image and captured-frame passes let Vision work at full
resolution (`minimumTextHeight` of zero), and the rendered-label tests read a
code printed at one percent of the frame height. `NDCDirectory` is a
snapshot of the FDA National Drug Code Directory — public domain, refreshed daily
by the FDA, trimmed by `Tools/build_ndc_directory.py` to generic name, brand name,
strength and dosage form for human prescription and OTC listings — sorted by
nine-digit product key and binary-searched in place, so a hundred thousand
products cost one buffer rather than a dictionary. No network is involved at any
point. The FDA's delisted-products file was examined and contributes nothing:
it blanks the name, type and strength of every delisted listing, so the snapshot
is the current directory alone, and a bottle from a product delisted since the
snapshot falls back to the printed name like any other.

The line is also the hardest to read. Vision works a whole frame at a bounded
resolution, so on a twelve-megapixel capture a two-millimetre line of print
reaches the recognizer a few pixels tall whatever `minimumTextHeight` says. The
still pipeline therefore takes a second look when its first pass yields no code:
every line that looks like it might be the code's — the caption, which small
print turns into "N0C", or digits with hyphens — is cut out of the
full-resolution image with room around it, scaled up to a height Vision reads
comfortably, and read again with language correction off, because correction is
built for words and a code is not a word; when nothing even looked like the code
the frame is read in overlapping full-resolution tiles instead. Only code-bearing
lines come back from the second look, and they take the place of the first
pass's misreading of the same print. After the caption every digit confusable is
repaired — O, D and Q for 0, I and l for 1, Z for 2, S for 5, G for 6, T for 7,
B for 8 — and the hyphens of a small code, which come through as spaces at least
as often as its digits come through as letters, are accepted as spaces when the
segments fit a layout, after the caption only. A code broken across two
recognized lines is read by looking at the label's lines together in order
rather than one at a time. The Review capture is merged ahead of the live items
rather than behind them, so the evidence cap cuts live extras and never the
capture, and a better live reading of a captured line keeps that line's place
in the capture's order so the adjacency wrapped text depends on survives.

`NDCIdentification` is the gate between a resolved code and the review screen.
It runs after the ordinary label reading, not instead of it, because that reading
is what a code is checked against. A code from a barcode is accepted on its own: a
check digit guarantees it is the code that was printed. A code read by OCR must be
corroborated by the label — a word of the product's name, or the same strength —
because one misread digit is a different product and the directory would state it
with confidence. A code from either source is refused when the label plainly
contradicts it: a confirmed name of another drug, a strength that disagrees, a salt
that makes a different product (metoprolol succinate is not metoprolol tartrate),
a vitamin number that differs, or a printed form that differs. Ten bare digits
that fit two listed products, or two codes naming two products, resolve to
nothing. A refused or uncorroborated code is still kept as the product code, as
read, so the person can see it; it just fills nothing. An accepted one fills name,
brand, strength and form, carries `MedicationNameProvenance.ndc`, outranks the
pharmacy's own barcode as the stored product code, and is not overridden by the
language model, which may still choose among directions, quantity and refill
readings. The review screen says which happened: the draft carries an
`NDCIdentificationOutcome` — accepted, uncorroborated, contradicted, unlisted,
or ambiguous — because "no code was read" and "a code was read and refused"
used to look the same, an empty screen, and only the second is worth a second
look at the digits. A code that was read but filled nothing is offered back in
the review screen's own NDC field, digit by digit, for the person to check
against the bottle.

That field is the last resort exactness should have had from the start: the
smallest print on a label is the line worth an exact match, and a person can
read it when the camera cannot. A code typed there is looked up in the same
directory and the listing is shown — "Tacrolimus 1 mg (Prograf), capsule" — with
a button that fills name, brand, strength and form from it. The corroboration
rule holds: the code fills nothing on its own word, and the person's reading it
off the bottle and choosing the product it names is the word that fills it.

Strengths are compared as amounts, not strings, because the directory and the
label write one fact several ways: `800-160 mg` against `800 mg/160 mg`,
`100 units/mL` against `100 IU/mL`, and a mixed-salt stimulant printed as its
20 mg total against four 5 mg components. Only a one- or two-component listing can
contradict a label; a partial reading of a multi-ingredient product proves nothing
either way. Names come out as the vocabulary spells them, with the bare ingredient
preferred over a salt form, so a medication reads the same whichever path
identified it. A combination listed under every salt of every ingredient — a
mixed-salt stimulant is the everyday case — reads as the vocabulary's shortest
name for that same set of ingredients, "Amphetamine - dextroamphetamine" rather
than four salts, with succinate and tartrate never set aside because the salt
is the product.

## Apple Health import

On iOS 26 and later, `HealthMedicationImporter` reads the medications a person
chooses to share from Apple Health. Authorization is per object: Health presents
its own picker, only the medications ticked there are ever returned, and the app
asks for read access alone — nothing is written back, and Health can withdraw the
choice at any time. Each shared medication is copied into a plain
`HealthMedicationSummary` at the boundary so no other file imports HealthKit, and
`HealthMedicationMapper` turns it into a draft: strength, form and route wording
are set aside from Health's display text, the curated brand table and then the
vocabulary supply the spelling, a name neither knows is kept exactly as the person
typed it, and Health's RxNorm coding is stored as the product identifier. Health
knows whether a medication has a schedule but not its times, and nothing about
supply, so every import goes through the same review screen as a scanned label,
where the person enters what is on hand and the schedule Meds Ahead should keep
count of. Saving returns to the Health list rather than closing the flow, so a
regimen of a dozen medications is a dozen reviews, not a dozen trips through Add,
and a medication already on file is marked as such in the list.

Dose logs come with the medication. The per-object grant that shares a
medication is the grant for the doses logged against it — HealthKit refuses a
type-level read request for the dose-event type with an exception — so the last
thirty days of doses Health recorded as taken for each shared medication come
along, offered as a toggle on the review screen and stored as dose events that
do not count toward supply. That gives an
as-needed medication a usage rate on the day it is imported instead of after its
third logged dose. Skipped, snoozed and untouched reminders are Health's
business and are not imported.

## Apple Health dose sync

Once a medication exists here, the doses a person logs for it in Health keep
arriving. `HealthDoseSync` runs on launch and on returning to the foreground,
just ahead of notification replanning, so the forecast that depends on the
doses is replanned with them. Only a medication with an exact identity Health
shares takes part — an RxNorm code, either Health's own coding on an imported
medication or the bundled RxNorm table's answer for a scanned NDC — and nothing
is ever matched by name, because a wrong match here changes a supply count.
The medications come from the per-object grant the import already holds, so
no picker and no new permission appears, and the dose events come under that
same grant; the dose-event type is never requested on its own, which HealthKit
refuses with an exception. The check covers the same thirty days the as-needed
forecast measures over, on every pass, so an undo in Health is caught for as
long as the dose still matters.

`HealthDoseReconciler` decides, over plain values, what the ledger should do:
never twice, never double. A sample already stored (`DoseEvent.healthSampleID`)
is skipped, and a status Health changed is restated. A dose the 1.1 import
stored before samples carried identifiers is recognised by its time and adopted
rather than stored again. A Health dose logged against a reminder is mapped to
this app's slot through `ScheduleEngine` — the nearest scheduled dose that day
within two hours, because Health keeps its own times — and skipped when the
person already logged that slot here; any Health dose within thirty minutes of
a dose logged here is the same dose. Skipped in Health becomes skipped here. A
sample Health no longer reports inside the window was undone there, and its
copy is removed: the one place the ledger is not append-only, because the copy
was never the person's entry in this app. A dose brought over this way counts
toward supply — it was taken from the count this app is keeping — unlike the
pre-count history that arrives with an import. Settings carries the last check
and a Check Now, and nothing is ever written to Health.

## RxNorm

`RxNormTable` bundles a slice of NLM's "current prescribable content", the
subset of RxNorm distributed without a UMLS licence, produced by
`Tools/build_rxnorm_table.py` and read the way the FDA snapshot is read: sorted
by a fixed-width numeric key and binary-searched in the file's own bytes. One
file maps each FDA product in the app's own directory that RxNorm lists an NDC
for to its concept and to the clinical drug a branded concept is a tradename of;
the other holds the prescribable names of the concepts mentioned. It is a
couple of megabytes. An accepted NDC, whether read or typed, carries its RxNorm
concept into `Medication.rxNormCode`, which is what lets the dose sync recognise
a scanned bottle in Health, and both sides of that match are widened to the
clinical drug so a generic bottle scanned here and the brand chosen in Health
read as one medication. The Health import's duplicate check uses the same
widening. The shared list prints the code beside the NDC, since a clinic's
system speaks RxNorm where a pharmacy's speaks NDC.

## The pharmacy card, refills under way, trips, people, expirations, and days

Six small things a caregiver does around the count, each built on facts the
model already had or gained in 1.1.1's one migration.

- **The pharmacy card.** The label prints the pharmacy, its phone and the Rx
  number, and `ScanParser` reads all three: the pharmacy is the first short
  line naming one (a chain, or a word like "pharmacy"), its phone is the first
  number on or beside that line — never a fax, never a ten-digit NPI — and the
  Rx number follows its own caption, fill suffix included. The detail screen
  shows the Rx number large enough to read aloud and a Call button that dials
  the pharmacy, and a detailed low-supply reminder says which pharmacy to call
  with which number. A renewal reminder does not, because the call it asks
  for is to the prescriber.
- **A refill under way.** `RefillStatus` — requested, or ready for pickup —
  with a date. The forecast is unchanged, because the count is the count, but
  the low-supply reminder stops while the status stands, Supply shows the
  status instead of "Act soon", Today lists what to pick up and when, and
  adding the refill clears it. Never inferred: the person sets it.
- **Trip check.** `TripCheck` is pure arithmetic over the forecasts Supply
  already has: a supply that runs out on or before the return day needs a
  refill before leaving, one with no forecast cannot be vouched for, the rest
  are fine.
- **Who it's for.** A person's name on the medication. When the household
  names more than one, Today, Supply and the shared list group under the
  names, with the unassigned last; one name or none, and nothing changes.
- **Expiration reminders.** A package expiration on file earns one reminder,
  a week ahead at nine, planned with the refill alerts under the same toggle
  and the same cap, and never re-announced once its moment has passed.
- **Doses by day.** `AdherenceSummary` reads a month of one medication's
  doses onto its days: a slot's dose by slot identity, a dose logged outside
  any slot by the day it was logged, and each day's state from the two — taken,
  partly, skipped, nothing logged, or not yet — so the calendar on the detail
  screen answers "which days" without inventing a miss for a day that has not
  come or a schedule that had not started. The shared list carries the same
  fact as a sentence: how many doses were logged in the last thirty days,
  with the day the medication was added when that is less than a month ago.

## Widgets, and where the store lives

Two widgets, for the Home Screen and the Lock Screen: Next Dose and Runs Out
Next. They live in the `MedsWidgets` extension, which compiles the `Shared`
folder — the model, `ScheduleEngine`, `ForecastEngine`, the theme and the
store location — alongside the app, so the widget's answers come from the same
code as the app's. `NextDoseSnapshot` and `RunsOutSnapshot` decide what to show
over plain values: the earliest unlogged dose time of the day and everything
due at it, overdue or not; and the medications in the order their supply runs
out, with the unforecastable last. A timeline entry is planned for every moment
the answer changes on its own — each unlogged dose time still ahead, the edges
of its due window, and midnight — and the app reloads the widgets whenever the
ledger changes, from the one place every change passes through, the
notification replan. Names are marked privacy-sensitive, so a locked Lock
Screen redacts them the way it redacts a notification preview.

The Taken button on the next-dose widget is `LogNextDoseIntent`. It appears
only when exactly one medication is due at that time, for the reason a grouped
reminder offers no Taken action: one tap cannot safely stand for several doses.
The intent matches the dose to its slot through `ScheduleEngine` and leaves a
slot already logged alone, from Today, from a reminder, or from Health; the app
replans notifications the next time it comes forward, as it does after a
reminder action.

A widget runs in its own process and can only reach a store in an app group
container, so the store now lives in `group.com.christoforakis.Meds`.
`StoreLocation.migrate` moves a store 1.0 or 1.1 kept in Application Support
there once, on the first launch after the update, before any connection is
opened: all three SQLite files together, because a committed transaction can
sit in the write-ahead log until the next checkpoint; the copy is checked
against the original's size before the original is set aside, and the original
is renamed beside its old name rather than deleted, so a launch that somehow
found the copy unusable could be recovered by hand. A copy that fails or cannot
be trusted leaves nothing behind at the shared location and the app keeps using
the legacy store, with the widgets saying to open the app. The widget itself
never creates the store — opening a SwiftData container where none exists would
create one, and an empty store at the shared location would tell the app the
move had already happened — so it opens only a store that exists.

## Rating request

The native review request is made from Today, only after a dose has just been
logged, and only when `ReviewRequestPolicy` agrees: three days since first use,
ten taken doses on record, never twice for one version, never within 120 days of
the last ask. The clock starts on the first launch past onboarding, so a 1.0 user
is treated like a new one for a few days rather than asked on update day. A
request that fails the policy is never made, rather than made and rate-limited by
iOS, and UI tests never see one.

## Source confidence

Scan results retain field-level evidence. Barcode payloads are stored only when the user saves the reviewed medication. Pharmacy URLs and opaque prescription identifiers are never opened automatically. The stored product code is, in order of preference, a resolved NDC, the NDC as printed, or the barcode payload; a medication imported from Apple Health stores its RxNorm code instead.
