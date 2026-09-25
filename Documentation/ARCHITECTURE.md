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

Medication identity keeps `brandName` as a stored field alongside the generic `name`. The empty default lets existing SwiftData records take the new field through a lightweight migration, and the reviewed value remains available to subtitles and exports without recomputation. `MedicationBrandIndex` uses a bundled curated table and exact, letters-only keys, with only a trailing salt or release-form suffix fallback. It resolves a generic or brand to its counterpart without a network lookup; fuzzy matching is deliberately excluded because a plausible but wrong brand on a clinician-facing list is worse than leaving the field blank. A release suffix set aside to find the generic brings back only a brand of that same release (1.1.1). The table's brand for tacrolimus is Prograf, the immediate-release product, and until then "Tacrolimus XL" was recorded as Prograf, "Metformin ER" as Glucophage and "Diltiazem CD" as Cardizem, though the extended-release products are dosed differently and are not interchangeable with them. Now those keep the release in the name and leave the brand blank; "Metoprolol succinate ER" still gets Toprol XL, because that salt is only ever extended-release (a short table lists such generics, checked against the FDA directory), and a reference brand followed by release letters, "Glucophage XR", is that release's own brand and kept as written.

A logged dose is matched to the slot it belongs to by schedule identifier and scheduled time, and every surface asks `ScheduleEngine` that one question rather than answering it locally. Take Now on a medication claims the same dose Today is offering, so one dose cannot be logged from both places and charged to the supply twice. Doses that were never logged remain answerable for two days on Today, because the forecast can only assume what became of an unlogged dose (see "Unlogged doses and the run-out date"), and a logged one needs no assumption.

A schedule has no slot earlier than the moment it was saved, less the due window. `ScheduleEngine.dueWindow`, thirty minutes either side of a dose's time, is the one constant behind Today's due and overdue states, the widget's change times, this first-day rule and the forecast's line between assumed and upcoming doses. In 1.1 a medication added at 15:00 showed that morning's 08:00 dose as overdue, Mark All charged it to the count just entered, and the next morning's missed-dose card asked whether it had been missed. New schedules are stamped with their save time and `ScheduleEngine.scheduledDate` declines any start-day slot before it, so Today, the widget, Mark All, Take Now, the reminders, the missed-dose card, the adherence calendar and the forecast agree that the dose never existed. A slot still inside its due window when the schedule is saved (08:00 saved at 08:10) is still offered; a first dose given later than that has no slot and is logged with Take Now. An edited time keeps its schedule's start date, because `ScheduleReconciler` reuses the record, so the days after the start day keep their slots. The demo store starts its schedules at the start of the day, so the UI tests do not depend on the hour they run. The rule has one trade-off: the start day is judged against the time the schedule has now, not the time it had when saved, which is not stored and would take an `@Model` change to keep. Moving a time later after the start day can bring back a start-day slot that was never offered; the next day's missed-dose card may ask about it once, and the forecast assumes it was taken, which only brings the run-out date earlier. Moving a time earlier can leave a start-day log without a slot.

An as-needed rate is measured over the history that exists — the days between the first logged dose in the window and now, capped at thirty — rather than a fixed thirty days. Three doses taken this week divided by thirty reported four times the runway that existed, and an over-long supply estimate is the failure that leaves someone without medication.

Each scheduled time retains its own dose quantity and weekday mask. Editing schedules reconciles those definitions with existing `DoseSchedule` records instead of replacing them. Stable schedule identifiers keep earlier `DoseEvent` history associated with the correct intended dose. Count corrections compare the entered physical count with the raw ledger balance, including any negative discrepancy, before the displayed balance is clamped to zero.

## Unlogged doses and the run-out date

1.1 forecast a scheduled medication from the ledger's balance and the doses still to come. A dose nobody logged was never subtracted, so every unlogged day moved the run-out date a day later, and the refill alert keyed to that date moved with it and never fired: a household that stopped logging for a week would be told its supply lasted a week longer than it did. That is the over-long estimate the as-needed rule exists to prevent.

The scheduled forecast therefore assumes that every scheduled dose since the anchor that nobody logged, and that is past its due window, was taken. The anchor is the last moment the ledger's number was known to be what was on hand: the latest opening count or correction, or a refill onto a ledger at or below zero, whichever is later, and failing both, the medication's creation. No dose could come out of an empty supply, so what is on hand after such a refill is the refill; a refill onto stock the ledger still showed confirms nothing about the doses before it and does not move the anchor. There is no look-back limit. The first version stopped at four hundred days, and dropping the oldest dose each day brought the slide back; a count years old still weighs every dose since.

`ScheduleEngine.unloggedDoses` returns the unlogged doses between the anchor and thirty minutes ago, where a dose turns overdue, and owns the slot question. A log naming a schedule accounts for the dose `loggedEvent` says it does, taken or skipped. A log outside every slot (Take Now with nothing due, or a Health dose no slot was near) accounts for the nearest unlogged dose on its own day within `ScheduleEngine.nearbySlotTolerance`, two hours, and for one dose at most: within reach it is that dose taken early or late, but hours from any slot it is as likely an extra one, so the slot stays assumed and the error is toward an earlier date. The pairing is made over the whole day, so asking about a range in pieces gives the same answer as asking once. The forecast hands over only the outside-slot logs that were taken, count toward supply and were made since the anchor, since history imported with a medication never came out of the count. The doses still to come start at the same boundary and leave out logged ones, so every dose since the anchor is counted exactly once, a dose logged a little early is not charged twice, and the run-out date, and the refill alert keyed to it, hold still while a dose sits in its due window. `DoseLogIndex` files a medication's logs by schedule and day, so a dose with a log on its own day is never timed, and the future is laid out a stretch at a time, thirty-one days and then doubling, until the supply runs out. A test holds `unloggedDoses` to the answer `loggedEvent` gives dose by dose, across a daylight-saving day and logs shifted by hours.

Nothing is written. `currentSupply`, `correctionDelta`, `AdherenceSummary` and the as-needed rate read only what was recorded. `SupplyForecast.assumedDoses` says how many doses were assumed: the forecast is then an estimate that says so and whether they are counted since the last count or the last refill, and every surface calls the ledger's number "on record" rather than "on hand", because the run-out date beside it has already taken those doses out. When the assumptions would use up everything on record, `needsCount` is set. The forecast then carries today as its date and zero days, but what is left is unknown, not zero, so it must read "Count needed", never "Out of supply": Supply, Today, the detail card, the runs-out widget, the printed list and Trip Check say so, and the notification planner writes no refill alert from that date.

Only a count ends an assumption. Correct Count always records an event: a count that matches the ledger is a zero correction, shown in Recent Activity as "Count confirmed", and it is a new anchor. While the forecast assumes any dose, the count sheet opens empty and Save Count stays disabled until a number is typed, because a prefilled number saved with one tap would record a count nobody made, clear every assumed dose, and move the run-out date later. Restoring an archived medication opens the count sheet at once, since the engine cannot see what happened while it was archived; cancelling leaves "Count needed" showing until someone counts, which is the honest answer. An edit that changes a kept schedule's amount or weekdays, or drops a schedule, while doses are being assumed opens the count sheet too once the editor closes (`ScheduleReconciler.asksForCount`): the reconciler rewrites those records in place, so the forecast would otherwise weigh the unlogged past at the new schedule, and a taper from four tablets to two over ten unlogged days moved the run-out date from 4 days to 19 when 9 was right. A changed or added time leaves the past's amounts alone, and a logged dose keeps its own, so neither asks. Ending the old schedule and starting a new one would keep the past exact, but every surface would have to learn to skip ended schedules.

## Privacy

The application has no account, advertising SDK, analytics SDK, cloud container, or medication lookup service. OCR and barcode recognition happen on device. Photo bytes are released after recognition and are not saved into the model store.

The optional tip jar loads only Apple's configured StoreKit products. Its row in Settings is always present and reports its own state — loading, available, or unavailable with a retry — rather than disappearing, so the purchase surface can always be found. Tips unlock no functionality. Verified tip transactions are finished at purchase time or on the next app launch; no developer payment server or medication data is involved.

The SwiftData store uses iOS data protection and remains available after the first device unlock so a person can log a reminder action while the iPhone is locked. It is deliberately left eligible for the user's own encrypted device and iCloud backups: a hand-built medication history cannot be recreated, and excluding it would silently destroy that history on a restore without protecting it from anyone. Reminder actions carry only internal medication and schedule identifiers; notification text remains generic unless the person explicitly enables medication names.

A prescription with no refills left needs a prescriber before a pharmacy can act, so it warns on the longer of the person's own lead time and a ten-day prescriber lead, and says which call to make. Refill reminders are only scheduled for a lead moment still in the future. Plans are rebuilt on launch, on returning to the foreground, and after every change, so an already-passed lead day would otherwise produce an immediate alert on top of the low-supply state the person is already looking at, and would fire again on every launch once dismissed. A supply that has already run out is surfaced in Today and Supply rather than pushed.

Notification planning is global across the medication set. Doses that occur at the same local time on the same weekday are consolidated into one slot-level request such as `8:00 PM meds are ready`; an identical seven-day slot collapses to one repeating daily request. A grouped notification opens Meds Ahead for review and does not expose one-tap Taken or Skip actions, because one action cannot safely represent several medications. A single-dose slot retains the privacy-aware quick actions. This reduces notification spam and keeps common polypharmacy routines comfortably below iOS's pending-notification ceiling while retaining exact weekday behavior. A course or a schedule starting within the week is planned one day at a time instead, and a moment it shares with a repeating schedule rings twice; see Dated reminders below.

Delivery can fail silently in two ways iOS reports quietly: a refused or withdrawn authorization, and an individual request the system declines to hold. Both outcomes are recorded by `NotificationHealth` on every scheduling pass and stated on Today, because an app that exists to remember a dose must not fail without saying so.

## Supply attention

`SupplyAttention` is the one rule for whether a medication's supply needs someone to act. It is decided once, over plain values, and Supply, Today, the detail screen's forecast card, the runs-out widget and the notification planner all read it. In 1.1 they did not agree: the screens and the alert counted different lead times, and a refill marked requested or ready silenced every one of them for good, even with nothing on hand. The lead is now the person's own everywhere, or the ten-day prescriber lead when no refills are left. A supply is low inside the lead, with nothing on hand, or when a count is needed.

A refill in progress pauses the warning only while it can still answer for the supply: fewer than two whole days have passed since its expected or pickup date (`refillGraceDays`), more than two days of supply remain (`refillPauseMinimumDays`), something is on hand, no count is needed, and its date falls before the run-out day. A pharmacy a day behind is ordinary; one two days behind may not be coming, and the warning is then the only prompt. With two days left, a refill that does not arrive is a missed dose however recently it was asked for. A refill due on the run-out day or after it can leave doses with nothing to take even if it arrives as promised (on the run-out day itself, any dose after the one that empties the bottle), so it is a gap to close rather than a refill on its way. A refill with no date, or a supply with no forecast, does not end the pause: an unknown runway is not a short one. The pause ends at the start of the second day after the refill's date, the stricter of the two readings of "two days late". When it no longer holds, Supply puts the attention line first ("Act soon · around" a date, "No confirmed supply remains", or "Count needed") and the refill's status under it, "Refill requested · was expected" a date once that date has passed; Today says "A refill needs checking"; and the widget shows the day count in the attention colour instead of "Refill on its way", and "Out of supply" at zero whatever the refill's status. A changed refill status starts its date from today, because the stored date belonged to the previous status, and keeping it started a pause that had already ended the moment the person marked the refill ready.

The morning the pause ends is announced. A refill check (`PlannedNotificationKind.refillCheck`, identifier `meds.<id>.refillcheck.<yyyyMMdd>` in the plan's calendar) asks "Is the refill in hand?" at 9:00 on the earlier of two days after the refill's date and two days before the run-out day (`SupplyAttention.refillCheckMoment`); the detailed version names the medication, the run-out date, and the pharmacy and Rx number. It is planned whenever a refill is in progress and that moment is still ahead, including for a medication with plenty left whose refill is running late, because a late refill nobody updated means the record is stale. It is sorted with the refill and expiration alerts, behind every dose reminder, under the sixty-request cap. The ordinary low-supply alert is skipped only when the pause will still hold at its own moment, or when a refill check falls on the same morning and says it instead. A count needed plans neither, since its date is where the assumptions ran out.

A replan used to remove every delivered alert it had not planned. A refill or expiration alert is planned only until its moment, so once delivered it was never in the plan again, and the next launch, or the next Taken on the Lock Screen, took the only low-supply warning out of Notification Center. `NotificationPlanOutcome.retains` now says which delivered alerts still say something true, and `NotificationService.deliveredIdentifiersToRemove` leaves them: an expiration alert by its exact identifier while the same expiration date is on file; a refill alert by medication while `SupplyAttention` says the supply needs attention now; a refill check by medication while the refill is in progress, until it is added or cleared. Each needs the medication active and refill reminders on, and dose reminders are never kept. Refill alerts are kept by medication rather than by identifier because the run-out day in the identifier moves, with a skipped dose and every day once nothing is left, while the warning already given is just as true. The price is that a kept alert can quote a run-out date a day or so off today's forecast; Supply shows the current one. A delivered refill alert is still removed when the medication is archived, refill reminders are turned off, a refill lifts the supply out of the lead, or a refill in progress pauses the warning. Pending requests are still replaced by the plan outright, since one the plan no longer asks for must not fire. The refill and expiration identifiers keep 1.1's date code, the digits of the month, day and year, so alerts delivered before the update keep their identity across it.

## Dated reminders, follow-ups and the weekly count check

A schedule running today and through the whole planning week is planned as repeating requests, as above. One that starts or ends within the week, a course or a medication starting later, is planned as one-shot requests for today and the six days after (`NotificationPlanner.datedHorizonDays`), one per day and time across every such schedule. A repeating request cannot skip days, so a course cannot join one, and planning the ongoing medication one day at a time too would let its reminders go quiet whenever the app is not opened for a week. Where a steady schedule and a dated one share a day and time, that moment therefore rings twice: the repeating request and the dated one (`DatedReminderPlanningTests.testASharedTimeRingsForBothOnTheCoursesDays`). Two reminders are the price of never going quiet, and this is the one exception to consolidating same-time slots. A dated slot already logged, early inside its due window or from the widget, is left out. A course ending a week or more away is still planned as repeating, and rings past its end if nothing replans in its last week; a Taken or Skip on that reminder finds no dose to log and replans, which withdraws it. When the horizon or the cap leaves dated reminders wanted after a day, `NotificationPlanOutcome.plannedThrough` names it, and Today says so from three days before, while reminders can be delivered at all.

Follow-ups, "Remind Again If Not Logged" in Settings and off until chosen, repeat an unlogged dose's question 30 minutes after its time, for the coming day only, consolidated by moment. They are worded for a household with two people giving doses: this phone knows only what was logged on it. Under the sixty-request cap they come last, after the dose requests and after the refill, expiration, refill-check and count-check alerts, because a follow-up repeats a question already asked, while a refill alert crowded out until its moment passes is never announced again.

The weekly count check (`CountCheckPolicy`) asks about one medication at 10:00 on a day its last count is a whole number of weeks old, at most once a week across all of them: a count needed first, then the soonest to run out. It is planned before it falls due, because plans are made only when the app is used, and a course over by the question's moment is not asked about. Its reminder is worded as Today's quick count card words the same medication, "Count needed" when only a count can say what is left, since no low-supply alert can be planned until then.

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
than re-derived. On the strength's own line a trailing "DR" is the
delayed-release form and is set aside before the address and person tests,
which read it as "Drive" and used to leave every delayed-release label ("X DR
240 MG CAPSULE") with a blank name (1.1.1); a street or a prescriber line with
DR is still refused.

A label's count is the other exception: it is offered, never filled. The number a
label prints, a pharmacy's QTY or CONTENTS or a stock bottle's "120 TABLETS", is
what the bottle held when full, not what is on hand, and in 1.1 a scanned draft
put it straight into Current amount. A bottle two weeks into a twice-daily fill
then read 28 doses high, the direction that runs someone out. `ScanParser` still
reads the count into `MedicationDraft.currentSupply`, but the scanned review
screen starts Current amount blank and offers the count beneath it: "Label says N
when full", a sentence saying that is the count before any were taken, and a Use N
button, so the person's tap is what confirms it for an unopened bottle. The
wording avoids "dispensed" because a stock bottle's count was never dispensed. N
is the label's count rounded to the two places a quantity shows, so the note, the
button's "Using N" state and the saved amount agree, and a count that shows as 0
at two places is not offered. Manual and Apple Health drafts are unchanged. The
rule lives in `MedicationDraft.labelDispensedQuantity`, `labelDispensedNote` and
`initialCurrentAmountText`.

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
strength, dosage form and release for human prescription and OTC listings — sorted by
nine-digit product key and binary-searched in place, so a hundred thousand
products cost one buffer rather than a dictionary. No network is involved at any
point. The FDA's delisted-products file was examined and contributes nothing:
it blanks the name, type and strength of every delisted listing, so the snapshot
is the current directory alone, and a bottle from a product delisted since the
snapshot falls back to the printed name like any other.

The line is also the hardest to read. Vision works a whole frame at a bounded
resolution, so on a twelve-megapixel capture a two-millimetre line of print
reaches the recognizer a few pixels tall whatever `minimumTextHeight` says. The
still pipeline therefore takes a second look whether or not its first pass read
a code, because a blurred line is misread more often than it is missed:
every line that looks like it might be the code's — the caption, which small
print turns into "N0C", or digits with hyphens — is cut out of the
full-resolution image with room around it, scaled up to a height Vision reads
comfortably, and read again with language correction off, because correction is
built for words and a code is not a word; when nothing read so far names a
listed product the frame is also searched in overlapping full-resolution tiles.
Only code-bearing lines come back from the second look, and they take the place
of the first pass's misreading of the same print. After the caption every digit
confusable is repaired — O, D and Q for 0, I and l for 1, Z for 2, S for 5, G for 6, T for 7,
B for 8 — and the hyphens of a small code, which come through as spaces at least
as often as its digits come through as letters, are accepted as spaces when the
segments fit a layout, after the caption only. A code broken across two
recognized lines is read by looking at the label's lines together in order
rather than one at a time. The Review capture is merged ahead of the live items
rather than behind them, so the evidence cap cuts live extras and never the
capture, and a better live reading of a captured line keeps that line's place
in the capture's order so the adjacency wrapped text depends on survives.

iOS 27 changed what the second look has to do (1.1.1). Vision offers the same
text-recognition revision 3 on iOS 26 and 27, so there is no revision to pin,
but the model under it reads small print differently: over some 140 crops,
scales and filters of a shaken Tecfidera line, iOS 27 never put the right code
first and listed it among its top ten guesses in about one look in seven, where
iOS 26.5 read it first in about one in three. The still pipeline now runs four
passes, in order:

1. The first pass over the whole frame, with language correction on.
2. The zoomed second look at each code-shaped line, with correction off.
3. When nothing read so far names a listed product, tiles, which now only find
   the code line: the zoom reads each line a tile finds. A tile hands Vision
   small print at its own few pixels, and iOS 27 read a 12-point "-02" as
   "-07" there where the zoom read it right, so the zoom's reading leads. The
   zoom misreads a shaken line too, so the tile's reading goes forward beside
   it whenever it carries a code the zoom did not read.
4. A search of Vision's lower-ranked guesses, only when nothing read, in print
   or in a barcode, is a listed code the label accepts, the label shows a
   confirmed name and a strength, and a code-shaped line exists. It reads at
   most two such lines at seven text heights, 40 to 150 pixels, because where a
   shaken line reads right is close to chance, a matter of how its blurred
   edges land on the pixel grid; it leaves language correction on, the only
   mode that ranks guesses, and looks at the top ten of each. It costs a few
   seconds in the simulator when it runs, off the main actor like the rest of
   the still pipeline, and a code the label accepts, a barcode included, spares
   it.

Wherever two passes read different codes, both go forward and the
identification gate asks the label. The evidence merge judges two lines to be
one line read twice by their letters, and two readings of one code line differ
only in their digits, so it used to keep whichever Vision scored higher and
choose a product by OCR confidence; it now never merges two text readings that
carry different codes, in the capture, in a photo merged into a scan, or in the
live tracker's retained lines.

A guess below the top reading is a guess among guesses, and the likeliest
wrong one is a neighbour from the same labeler, which numbers its line in
sequence: the same drug at another strength, or at the same strength in another
release. On the shaken Tecfidera 240 mg line the 120 mg code turned up among
the guesses more often than the right one, and Prograf and Astagraf XL are one
digit apart at every strength. So a guess must clear a stricter bar than a top
reading, `NDCIdentification.labelNamesExactly`, before it joins the evidence:
the label's confirmed name and an equivalent printed strength are the
product's; a form the label prints is the product's form; a brand it prints is
the product's whole brand, release letters included, so WELLBUTRIN XL is not
Wellbutrin SR and WELLBUTRIN alone names neither; nothing on the label
contradicts the product, release included; and none of the labeler's other
products fits the label as well. A label that says only "TACROLIMUS 1 MG
CAPSULE" fits both Prograf and Astagraf XL and takes a guess at neither; one
that prints PROGRAF can take only the Prograf code, and one that prints
ASTAGRAF XL only the Astagraf XL code. An admitted guess enters the evidence as
"NDC" and its code alone and displaces no line, so a quantity or a date beside
the code keeps the passes' reading rather than the guess's, and it then faces
the ordinary gate beside every other reading, where two surviving products
still fill nothing. Rivals are looked for only under the guess's own labeler: a
directory-wide rule would refuse every drug that has generics, the Tecfidera
guess iOS 27 needs among them, so a guess misread onto another labeler that
lists the same name, strength and form is caught only by a printed brand.

`NDCIdentification` is the gate between a resolved code and the review screen.
It runs after the ordinary label reading, not instead of it, because that reading
is what a code is checked against. A code from a barcode is accepted on its own: a
check digit guarantees it is the code that was printed. A code read by OCR must be
corroborated by the label — a word of the product's name, or the same strength —
because one misread digit is a different product and the directory would state it
with confidence. A code from either source is refused when the label plainly
contradicts it: a confirmed name of another drug, a strength that disagrees, a salt
that makes a different product (metoprolol succinate is not metoprolol tartrate),
a vitamin number that differs, a printed form that differs, a release that
differs, or a brand of another product of the drug (below). Ten bare digits
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

The directory is keyed by labeler and product, and the label vouches for the
drug, strength and form, so nothing checks the two package digits. When printed
readings of the accepted product disagree there ("-02" from the zoom, "-07"
from a tile on iOS 27), the first one read used to be stored and printed on the
shared list, a package no pharmacy dispensed. Such a code is now kept as the
FDA's two-segment product NDC, "64406-0006" (1.1.1;
`NDCIdentification.Match.recordedCode`): it names the drug exactly and claims
no package it does not know. A barcode's check digit settles the package,
readings that agree keep the full code, and the review screen's note says why
the code is shorter than the bottle's, so nobody "corrects" it; typing the code
from the bottle and choosing Use This Product still records the full one. A
stored NDC can therefore be either form, and anything that parses one must
accept both. RxNorm is looked up by product and does not care.

Release is part of a product's identity (1.1.1). Prograf (0469-0617) and
Astagraf XL (0469-0677) are both tacrolimus 1 mg capsules from labeler 0469,
one digit apart, and small print swaps 1 and 7. Prograf is immediate-release
and taken twice a day, Astagraf XL extended-release and taken once, and they
are not interchangeable. Name, strength and form cannot tell them apart, so a
misread code on a Prograf bottle, even one that printed PROGRAF, was accepted as
Astagraf XL. Only release and brand tell them apart, so an immediate- against
an extended-release disagreement is a contradiction like a salt's, and a
brand is checked both ways.

The directory's sixth column is the listing's release: "er", "dr", or empty
when the listing claims neither. `Tools/build_ndc_directory.py` takes it from
the FDA's dosage form ("CAPSULE, EXTENDED RELEASE"); where that is silent, from
a release phrase in the proprietary name, its suffix or the nonproprietary name
("potassium chloride extended-release", "Enteric coated"); and, for oral
tablets and capsules only, from release letters after the first word of the
brand or of the generic name (XL, XR, ER, SR, CR, LA, CD and XT for extended,
DR and EC for delayed). The letters count only there because "Dr. Sheffield"
and "La Roche-Posay" lead with them on creams and sunscreens; the generic name
counts because a repackager lists extended-release metformin as a plain TABLET
named "Metformin ER 500 mg".
`NDCDirectory` reads the column into `NDCProduct.release` and still loads
five-column rows. Release is compared only for tablets, capsules and oral
liquids (`NDCProduct.comparableRelease`): a patch is extended-release by
nature, and a label for a patch or an injection seldom says so.

`ReleaseForm` reads the label's release only on the lines that name the drug,
because read across the whole label a prescriber's "DR JONES" is delayed
release and a Louisiana address is long-acting. Extended-release letters also count on the
next line when it is the rest of the description, as a narrow label wraps
"TACROLIMUS" / "XL 1 MG CAPSULE"; DR, EC and LA stay on the drug's own line,
since a prescriber, a manufacturer and a state are what usually follow it. A
dosing interval is never release evidence: "every 12 hours" is how Prograf is
taken. A product's "24 HR" only suggests extended release, since Nexium 24HR
is not, so it can back a code up and never refuses one. From there:

- A label that states a release the product is not refuses the code, and a
  reference brand it prints states the release for it: PROGRAF is
  immediate-release, TOPROL XL extended. The one asymmetry is that a DR label
  does not refuse a listing that claims no release, because the FDA files some
  delayed-release products, Tecfidera among them, as plain capsules; extended
  release is the one that changes how often a dose is taken.
- A printed code for an extended- or delayed-release product fills nothing
  until the label backs the release up: its letters or phrase, the product's
  "24 HR", the product's own brand when that brand is more than the drug's
  name and strength ("Aspirin 81 mg" is not), or a drug name the table knows
  in only that release, as metoprolol succinate is only ever extended-release.
  A barcode needs no backing, as it needs no corroboration, but a label that
  contradicts it still refuses it.
- The other brands a label can print are the table's reference brand and the
  brands of the code's labeler's other products of the drug
  (`NDCDirectory.products(withLabeler:genericName:)`), where a one-digit
  misread lands first. One of those printed refuses a branded code whose own
  brand is not on the label, PROGRAF with an Astagraf XL code or ASTAGRAF XL
  with a Prograf one, and its release counts as the label's, so ASTAGRAF XL on
  a line of its own refuses the labeler's generic immediate-release code too. A
  variant of the product's own brand (Bactrim DS, Adderall XR) and a store's
  brand that prints "compare to Advil" are left to the strength and release
  checks.
- The brand the table lends a label's name, Prograf for "TACROLIMUS", is held
  back whenever a code read on the label names the drug in another release or
  the label prints another brand of it (`NDCIdentification.doubts`), whatever
  the code's verdict and in the language model's pass as well. Generic
  extended-release tacrolimus is named "Tacrolimus ER" with no brand, and the
  review screen's listing says the release when the brand does not. A brand
  the label prints is never held back.

Extended releases share one value, so a printed brand tells a labeler's
branded variants apart but generic letters do not: "BUPROPION SR" against a
bupropion XL code, or diltiazem CD against LA, is not refused on release.

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

That mark, "Already in Meds Ahead", matches names only within one release
(1.1.1), since Prograf and Astagraf XL share the name tacrolimus and an
Astagraf XL entry used to read as the Prograf bottle already here. A release
the entry states stays in its name for any drug, "Nifedipine ER", where it used
to be set aside with the form words. An entry whose text states none takes the
release the FDA directory gives every product the bundled RxNorm table lists
under its code, so "Tacrolimus 1 mg" coded as Astagraf XL reads as "Tacrolimus ER" with no
brand; finding a code's products reads the whole table, so the importer does it
once, off the main actor, as the entry is read
(`HealthMedicationSummary.codedRelease`). A name that states no release is
read as the table's reference product. When both sides carry codes that name
different clinical drugs, a matching name never joins them. RxNorm's names
lead with a duration, "24 HR tacrolimus", which is not taken as part of the
name.

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
is skipped, and a status Health changed is restated. A dose an earlier build's
import stored before samples carried identifiers is recognised by its time and
adopted rather than stored again. A Health dose logged against a reminder is mapped to
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
for to its concept and to the clinical drug a branded concept is a tradename of, in a
megabyte and a half. (The tool can also write NLM's prescribable names for
those concepts, but nothing in the app reads them, so that file is not
bundled.) An accepted NDC, whether read or typed, carries its RxNorm
concept into `Medication.rxNormCode`, which is what lets the dose sync recognise
a scanned bottle in Health, and both sides of that match are widened to the
clinical drug so a generic bottle scanned here and the brand chosen in Health
read as one medication. The Health import's duplicate check uses the same
widening. It never joins two releases: RxNorm gives each its own clinical drug
(Prograf 1 mg, 108513, widens to 198377; Astagraf XL 1 mg, 1431982, to
1431980), which a test pins against the shipped files for both the duplicate
check and the dose sync. The shared list prints the code beside the NDC, since a clinic's
system speaks RxNorm where a pharmacy's speaks NDC.

## The pharmacy card, refills under way, trips, people, expirations, and days

Six small things a caregiver does around the count, each built on facts the
model already had or gained in 1.1's one migration.

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
  with a date. The forecast is unchanged, because the count is the count.
  In 1.1 the low-supply reminder stopped for as long as the status stood;
  since 1.1.1 the refill quiets the warning only while `SupplyAttention` says
  it can still answer for the supply, and a refill check asks on the morning
  it stops (see "Supply attention"). Today lists what to pick up and when,
  and adding the refill clears it. Never inferred: the person sets it.
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
slot already logged alone, from Today, from a reminder, or from Health. Since
1.1.1 it also asks `ScheduleEngine.hasSlot` whether the schedule still has a
dose at exactly the moment the widget drew, as the reminder actions do, and
writes nothing when a time was edited, a schedule ended, or a first day began
after that time since the widget last drew. The app replans notifications the
next time it comes forward, as it does after a reminder action.

The same question has to run the other way. The widget saves from its own
process, and nothing guarantees that a running app's `@Query` arrays have
merged that write when the person next taps Taken on Today or Take Now on a
medication; the arrays alone would call the dose unlogged and spend the supply
a second time. So every path in the app that writes a scheduled dose asks the
store first, as the reminder actions and the widget already did:
`DoseLogGuard.isLogged` for Today's Taken and Skip, the missed-dose card and
Mark All, and `DoseLogGuard.actionableDose` for Take Now, which claims the next
due dose the store has unlogged. The widget logs the earliest due dose, so a
Take Now tap then belongs to the next one, as it would had the screen caught
up, and not to nothing. The fetch is narrowed only by medication; slot
identity is still `ScheduleEngine.loggedEvent` and `actionableDose`. A tap that
finds its dose already logged writes nothing and says so in an "Already
Logged" alert, and a failed fetch shows the existing couldn't-log alert and
writes nothing. `DoseLogGuardTests` proves it with two containers on one store
file. The guard does not refresh the screen. Whether Today shows the widget's
log when the app comes back depends on SwiftData merging another process's
write into a running app's queries, which nobody has yet watched on a phone;
it is a device check in `RELEASE_CHECKLIST.md`. Until it is settled, Today may
show a dose as due that the store already has, and a tap on it writes nothing.

A widget runs in its own process and can only reach a store in an app group
container, so the store now lives in `group.com.christoforakis.Meds`.
`StoreLocation.migrate` moves a store 1.0 kept in Application Support
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

## Words and numbers kept exact

The notes a dose carries when it was logged away from Today are stored data,
not display copy. `DoseEventNote.reminder` ("Logged from reminder") and
`DoseEventNote.widget` ("Logged from widget") live in `Shared`, so the app and
the widget write the same words, and `DoseEvent.appleHealthNote` ("Logged in
Apple Health") lives with the model. `HealthDoseReconciler` tells a dose logged
here from Health's copy of one by its note, and every event already saved keeps
the words it was saved with, so rewording one would mean migrating stored
history. `DoseEventNoteTests` pins all three.

The words after a number are written out once. Every surface used to add "s"
to the form's unit, which printed "30 patchs on hand", "150 mLs" and "1 days of
supply remaining". `Shared/QuantityText.swift`, compiled into the app and the
widgets, holds `MedicationForm.quantityText(_:)` and `unitText(for:)`, with each
form's plural written out rather than derived ("patch" takes "es"; mL is a
symbol and never takes one), and `Int.dayCountText` and `Int.counted(_:plural:)`
for whole-number counts. The singular follows the number as printed, not as
stored: 1.004 prints as "1" and reads "1 tablet", decided by the same two-place
rounding `medicationQuantityText` uses, in a fixed locale so a region's digits
cannot change the answer. Notification plans carry the medication's form rather
than a unit name, so a reminder can choose the plural.

Add Refill and Correct Count read the number from the text as typed. They were
`TextField(value:format:)` fields on a keypad with no Return key, a pattern
that on a phone committed the editor's dose field only when focus left (August
30), and the sheet's button never took focus. The simulator never reproduced
that for the sheets, so the change is defensive and the phone repro stays
open. The sheets keep the text and parse it on every change through
`SupplyChangeQuantity` and `Double.medicationQuantity(from:)`: a count may be
0 and a refill may not, and empty, unparseable or negative text, or text with
two decimal separators, leaves the button disabled. The sheets, the editor's
Current amount and the scanned label's Use button write their numbers without
grouping, and text containing the region's grouping separator disables the
button rather than being guessed at, because a region that groups with "."
read "1.497" as 1.497, and en_US read "1,000" as 1. Untouched prefilled text
stands for the exact number it was made from, so the two-place rounding is
never recorded as a difference.

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
