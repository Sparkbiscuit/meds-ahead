# Verification record

## September 12, 2026 (night) — 1.1.1: the scanner, from the real-bottle pass

Built from `Documentation/handoff/1.1.1-SESSION-BRIEF.md`, first section, the
same night the brief was written. The two bottles that failed live on September
12 were not at hand, so the capture note could not be read on them; every
hypothesis the brief listed that code can close was closed instead, and the
rendered-label tests were pushed to a camera's worth of pixels.

### The frame (1a)

- The Name pill keeps its title in the exact-match state and changes only its
  symbol to `checkmark.seal.fill`, with the accessibility label "Name, exact
  match"; retitling it "Exact match" was what wrapped the row into the frame.
- The frame's top edge is measured from the pill row with `onGeometryChange`
  rather than assumed, so a row that wraps at a large text size pushes the frame
  down. The drawn outline's own frame, measured in the scan area's coordinate
  space alongside the scanner view's frame, is what becomes
  `regionOfInterest`; the two can no longer disagree. That also closed a quiet
  mismatch: the scanner view reaches up under the navigation bar while the
  outline does not, and the old constant inset was applied to the scanner's
  bounds, so the recognition region began about a hundred points above the
  drawn frame. In the simulator the frame now sits sixteen points under the
  pills at the default text size.

### NDC read reliability (1b)

What the code can settle without the bottles, and what was done about each of
the brief's hypotheses:

- **The capture never ran.** `captureCroppedPhoto` no longer throws when the
  crop cannot be mapped; the whole photo is read instead and the note says so.
- **Zoom is ignored.** Examined and found not to lose anything: if the photo
  carries the zoom the crop is right, and if it does not the crop still contains
  everything the preview showed, at the photo's native resolution. The note
  prints the zoom either way so the device can confirm which.
- **The merge cap cuts the capture.** The capture is now merged ahead of the
  live items, so the cap (raised from 80 to 120) cuts live extras and never the
  capture; a better live reading of a captured line keeps that line's place in
  the capture's order, so the adjacency that joins wrapped text and split codes
  survives the merge. Tested.
- **Small print.** Vision works a whole frame at a bounded resolution, which is
  the mechanism behind "the rendered tests read one percent of a 1,500-point
  canvas and the phone reads nothing": the canvas was small. The still pipeline
  now takes a second look when the first pass yields no code: lines that look
  like the code's (the caption, including "N0C", or hyphenated digits) are cut
  out of the full-resolution image with padding, scaled up to about forty pixels
  of text height, and read again with language correction off; if nothing even
  looked like the code, the frame is read in six overlapping full-resolution
  tiles. Only code-bearing lines come back, and they replace the first pass's
  misreading of the same print.
- **Confusables.** After the caption every one is repaired: O, D and Q to 0, I
  and l to 1, Z to 2, S to 5, G to 6, T to 7, B to 8. Spaces stand in for the
  hyphens after the caption when the segments fit a layout ("NDC 00093 1039
  01"); a phone number's segments do not, and spaces never count without the
  caption.
- **Split lines.** The gate reads the label's lines together in order, so "NDC
  00093-" on one line and "1039-01" on the next is one code; and the still
  pipeline judges "was a code read" on the joined text too, so a split code no
  longer triggers the second look for nothing.
- **Manual entry.** The review screen's Prescription & package section has an
  "NDC from the label" field. A typed code is looked up in the directory off the
  main actor, the listing is shown ("FDA directory: Tacrolimus 1 mg (Prograf),
  capsule."), and Use This Product fills name, brand, strength and form; the
  row then says what it filled and from which code. A malformed code, an
  unlisted one and ten bare digits that fit two products each get their own
  line.
- **Read but refused is said out loud.** The draft carries what became of the
  code — accepted, uncorroborated, contradicted, unlisted, ambiguous — and the
  review screen's summary states it in words, with the product the directory
  lists where there is one. A code that was read but filled nothing is prefilled
  into the NDC field so the person can check it digit by digit.

Measured on rendered labels through the real Vision pipeline, canvas 2,400 by
3,200 pixels at one pixel per point, the code line printed at 26, 22, 18, 16,
14, 12 and 10 pixels (0.8 percent of the frame down to 0.3): every size
resolved the exact product. All but one were read on the first pass; at 18
pixels the first pass did not recognise the line at all and the tiled fallback
found it. Two further tests exercise the second look directly — a 12-pixel
code line cut out around a deliberately loose box, scaled and read, with its
box mapped back to within a hundredth of the frame of where it was printed; and
the same line found by the tiled pass in the right-hand half of the frame — and
one puts the code split around its hyphen onto two lines.

### Text-heavy labels (1c)

- The product line is chosen once, and the strength and the name both come from
  it: the first line that is not a sig and reads as a name once its strength is
  set aside, else the first non-sig line carrying a strength. A line is a sig
  for this purpose when sig vocabulary appears anywhere in it — "every",
  "hours", "as needed", "with food", "then", a parenthesised dose — not only
  when it opens like one. The brief's hypothesis held: "(25 MG) BY MOUTH EVERY
  6 HOURS" had become the strength line and the product line below it was never
  consulted.
- A sig whose first line passes the gate alone is carried on through adjacent
  continuation lines, up to five in one capture, as long as each reads as sig
  text (sig vocabulary, a frequency, a second direction sentence, or a purpose
  such as "FOR PAIN") and the whole still passes the gate. A bare package count
  ("120 TABLETS"), a warning sticker and the product line never continue a sig;
  the first of those was caught by the rendered OTC label test on the way.
  `isTrustedDirections` accepts up to 300 characters, and "mfr" joined the
  dispensing words.
- Regression cases: the three-line wrapped sig with the restated dose
  (Hydroxyzine 25 mg, directions assembled whole, quantity and refills intact),
  a five-line sig, a trusted first line keeping its continuation, and the two
  lines that must not be swallowed.

### By hand in the simulator

A rendered label carrying only "NDC 0093-1039-01", an Rx number, a quantity and
a refill count, through Choose Photo: the scanner's pills showed quantity and
refills found and the name withheld; Review opened with "Code read, not in the
directory — 0093-1039-01 was read as an NDC but is not in the bundled FDA
directory", the product-code row showing the code as read, and the NDC field
prefilled with it and saying "Not in the bundled FDA directory. Check each digit
against the label." (That code is the sertraline row of the unit tests'
in-memory directory; it is not in the real snapshot, which is why this showed
the unlisted state rather than the uncorroborated one — an honest answer either
way.) Then, from Enter Manually, typing 0469-0617-73 into the NDC field showed
"FDA directory: Tacrolimus 1 mg (Prograf), capsule." with Use This Product;
tapping it filled Tacrolimus, Prograf, 1 mg and Capsule, set the product code
to 00469-0617-73, and the row read "Name, strength and form filled from the FDA
directory entry for 00469-0617-73".

### Results of the scanner batch

- Unit tests: 306/306 on the iPhone 17 Pro simulator (285 before, plus the
  confusable, spaced-hyphen and split-line readings, the outcome reporting, the
  frame inset, the merge position and cap order, the box mapping, the
  code-fragment shapes, the camera-sized and half-percent labels, the zoomed
  and tiled passes on their own, the wrapped code, and the four text-heavy
  labels).
- UI tests: 9/9 on the iPhone 17 simulator, with the NDC field present on the
  editor screens the accessibility audits cover.
- Committed as `13eb823`, the last commit without a model change; 1.1 can be
  archived from it.
- The two bottles from September 12 remain the acceptance test, on the phone.
  Read the capture note first; it now also says whether the second look ran
  and what it found.

## September 12, 2026 (late) — 1.1.1: Health dose sync, the RxNorm table, one migration

### The model change, batched

Every stored property 1.1.1 adds landed in one commit so existing stores take
them through one lightweight migration: `DoseEvent.healthSampleID`, and on
`Medication` the pharmacy name and phone, the Rx number, the person it is for,
the RxNorm code, and the refill-in-progress status with its date. All are
declared with inline defaults, as `brandName` and `countsTowardSupply` were.
Version bumped to 1.1.1, build 5.

### Health dose sync

- `HealthDoseReconciler` and its sixteen tests, over plain values: a stored
  sample is skipped; a status changed in Health is restated; a dose the 1.1
  import stored without a sample identifier is adopted by its time rather than
  duplicated, and two samples cannot adopt one; a Health dose logged against a
  reminder claims this app's nearest slot within two hours (Health's 8:00 is
  this app's 8:30) and is skipped when that slot is already logged here; a dose
  far from any slot is stored unscheduled at the nearest schedule's amount; a
  Health quantity outranks the slot's; an unscheduled Health dose within thirty
  minutes of a dose logged here is the same dose, and thirty-one minutes is not;
  a mirrored Health dose never blocks a second Health dose beside it; skipped
  in Health is skipped here; a sample Health took back is removed, and only
  mirrored events inside the window can be; records outside the window and
  another medication's events are invisible; and a name is never an identity.
- `ScheduleEngine.nearestScheduledDose` answers the slot question, tested.
- By hand on the iPhone 17 Pro simulator, on an on-disk store: Add > Import from
  Apple Health > Choose Medications in Health > Turn On All > Allow listed
  "Tacrolimus 1mg Oral capsule · 1 dose logged in 30 days"; the review screen
  saved it with a count of 30 (and asked for notification permission, as a first
  save does). In the Health app, Medications > As Needed Medications > + >
  Taken > Done logged a capsule at 10:46 PM. Bringing Meds Ahead back to the
  foreground ran the sync. The store, read directly: the medication carries
  RxNorm 198377 as both product identifier and `rxNormCode`; the 3:38 PM dose
  imported with the medication has `countsTowardSupply` 0 and now a sample
  identifier; the 10:46 PM dose arrived with `countsTowardSupply` 1 and its
  sample identifier; `healthDoseSync.lastCheck` reads the foreground moment.
  Then, in Health, opening the 10:46 PM entry and tapping Taken again un-logged
  it; bringing Meds Ahead forward again removed the mirrored copy, leaving only
  the imported 3:38 PM dose, and the last check advanced. Health's simulator
  quirks for the record: "As Needed Medications +" logs a dose dated now for any
  shared medication, and the per-object picker still needs "Turn On All" rather
  than its row toggle.
- **Migration verified empirically, from 1.0.** The shipped 1.0 build 3 commit
  (`1c9a5b2`) was built in a detached worktree, installed on the iPhone 17
  simulator, and launched with `-seed-demo-data -seed-missed-doses` and without
  the in-memory flag, so its store predates `countsTowardSupply` as well as
  every 1.1.1 column; one missed dose was logged as taken. The new build was
  installed over it, never uninstalled, and launched: three medications, four
  schedules, three inventory events and the dose event survived; the pharmacy,
  Rx number, person, RxNorm and refill-status columns read as empty strings,
  the refill-status date and the Health sample identifier as null, and
  `countsTowardSupply` as true. Nothing in the log mentioned a migration error.

### RxNorm

- `Tools/build_rxnorm_table.py` read the September 8, 2026 prescribable
  release (74.7 MB zip, SHA-256 `82cc1679…`, downloaded from NLM without a
  licence): RXNSAT's 441,035 NDC attributes cover 116,236 labeler-product keys,
  79,604 of them in the app's FDA snapshot; 8,083 of those map to a branded
  concept with a clinical drug behind it; 14,835 prescribable names. NLM's own
  NDC rows outvote labeler-submitted SPL rows where a package's concept is
  disputed (1,486 keys). `RxNormProducts.txt` is 1.5 MB and `RxNormNames.txt`
  0.8 MB, 0.6 MB together compressed.
- `RxNormTableTests` pin Prograf's product to 108513 with clinical drug 198377
  — the code Health showed for tacrolimus — Zoloft and a generic sertraline to
  the one clinical drug 312941, NLM's prescribable name for it ("sertraline
  HCl 50 MG Oral Tablet"), an accepted NDC carrying its concept into the draft
  and nothing when the table is absent, the Health duplicate check recognising
  Zoloft-in-Health as the generic bottle here, and the sync widening both sides.


Built in one session from the brief in `Documentation/handoff/NDC-SESSION-PROMPT.md`
and the September 11 plan. The FDA snapshot itself is the one piece that waits on a
download, and its results are recorded at the end of this entry once it lands.

### The investigation the brief asked for

1. **How often a US pharmacy label prints a readable NDC.** No federal rule requires
   it on a dispensed prescription — the FD&C Act exempts dispensed drugs from most
   labeling requirements and state boards list the required elements, which are the
   pharmacy, Rx number, patient, prescriber, drug and strength, directions and date.
   In practice the major retail chains and the hospital outpatient systems (Epic
   Willow among them) print the dispensed product's NDC because it identifies the
   exact manufacturer and package for their own records. The strongest evidence on
   hand is the bottles tested so far: every one, retail and hospital pharmacy
   alike, prints one. The barcode on a *patient* label is almost always the pharmacy's own
   Rx number in Code 128 or Code 39, which decodes to nothing useful. The NDC lives
   in a barcode only on manufacturer packaging — a GTIN in UPC-A, GS1-128 or the
   DSCSA DataMatrix — which a person does receive for inhalers, pens, tubes, blister
   cards, unit-of-use boxes and OTC products. So: printed digits are the common case
   for vials, barcodes the common case for boxes, and the app now reads both.
2. **What the FDA directory contains.** `ndctext.zip` (10.8 MB, product.txt and
   package.txt, tab-separated, refreshed daily; last modified September 11 at the
   time of writing) and `ndc_excluded.zip` (31.4 MB, listings that have left the
   directory, mostly because marketing ended). Product rows carry the product NDC,
   product type, proprietary name and suffix, nonproprietary name, dosage form,
   route, marketing dates and category, labeler, substance names, active strengths
   and units, pharmacologic classes and DEA schedule. It is US government work,
   public domain, no key and no terms; the FDA's own caveat is that inclusion is not
   approval, which the app never claims. Trimmed to human prescription and OTC
   listings and the four facts a label needs, it is one row per product.
3. **Normalisation.** Codes are assigned in three ten-digit layouts (4-4-2, 5-3-2,
   5-4-1); billing pads the short segment to a uniform 5-4-2 eleven digits. Labels
   print any of the four, hyphenated or bare. Hyphenated and eleven-digit renderings
   are unambiguous. Ten bare digits are not: all three layouts are offered and the
   directory settles it, with nothing accepted if more than one layout names a real
   product. OCR reads O for 0 and I or l for 1 often enough that those are repaired
   before lookup; the label's own text then has to vouch for the result.
4. **Barcodes.** A US drug GTIN is the ten-digit NDC wrapped in a `3` number-system
   digit and a check digit (`003` + NDC + check once padded to fourteen). Decoding
   costs forty lines and shares the lookup, so it is done in the same pass; the check
   digit means a decoded code needs no corroboration, only the absence of a
   contradiction. Pharmacy Rx-number barcodes decode to nothing, which is correct.
5. **A better offline option?** No. RxNorm's NDC attributes need the full UMLS
   release, openFDA's NDC endpoint is the same data behind a network call, DailyMed
   SPL is enormous, and the NSDE file drops the generic name and strength. Apple
   Health's medication API turned out to be a complementary exact source rather than
   a rival: it hands over RxNorm codings for whatever the person has already entered
   there, which is what the import stores.

### What was built

- `NationalDrugCode`, `NDCDirectory`, `NDCIdentification` and
  `Tools/build_ndc_directory.py`; the design is in `ARCHITECTURE.md` under
  "Exact identification". The gate is the point: a barcode is accepted on its own,
  printed digits must be corroborated by a word of the name or the same strength,
  and either is refused when the label names another confirmed drug, a different
  strength, a distinguishing salt (succinate against tartrate), a different vitamin
  number, or a different printed form. Strengths compare as amounts, so a mixed-salt
  stimulant printed as 20 mg agrees with four 5 mg components and `800-160 mg` agrees
  with `800 mg/160 mg`. The language model cannot override a resolved identity. A
  printed code now outranks the pharmacy barcode as the stored product code.
- Apple Health import on iOS 26 and later: `HealthMedicationImporter`,
  `HealthMedicationMapper`, `HealthImportView`, a third card in Add, the HealthKit
  entitlement and read-only purpose string. Per-object authorization, read only,
  every import through the ordinary review screen, saving returns to the Health list.
- The native rating request from Today, governed by `ReviewRequestPolicy`.
- Version 1.1, build 4. `MedicationSource` and `MedicationNameProvenance` gained
  cases; both are stored as strings and no `@Model` property changed, so there is
  no migration to verify this time.

### Results

- Unit tests: 268/268 on the iPhone 17 Pro simulator (220 before, plus 48 across
  `NationalDrugCodeTests`, `NDCIdentificationTests`, `HealthMedicationMapperTests`
  and `ReviewRequestPolicyTests`). The NDC tests run against an in-memory
  directory, so they prove the gate without the snapshot; the snapshot's own tests
  are listed below.
- UI tests: 9/9 on the iPhone 17 simulator, unchanged, with the third Add card
  present.
- Release static analysis on the app target: succeeded, nothing beyond Xcode's
  no-AppIntents metadata-skip message.
- Apple Health, by hand on the iPhone 17 Pro simulator: a Tacrolimus 1 mg capsule
  added in the simulator's Health app; Add > Import from Apple Health > Choose
  Medications in Health presents the system picker with the purpose string; after
  Allow, the list reads "Tacrolimus 1mg Oral capsule · Capsule · Scheduled in
  Health"; the review screen carries the From Apple Health note, name Tacrolimus,
  brand Prograf, strength 1 mg, form Capsule; saving returns to the list, where the
  row reads "Already in Meds Ahead as Tacrolimus" with a check. On a fresh install,
  Don't Allow on the picker lands on "No medications are shared with Meds Ahead
  yet. Choose Again shows Health's list." Nothing is written to Health at any point.
- Rating request, by hand: with first use backdated eleven days and eleven taken
  doses on record, logging a dose on Today produced the system "Enjoying Meds
  Ahead?" sheet 1.5 seconds later, and `reviewRequest.lastRequest` and
  `lastRequestedVersion = 1.1` were recorded so it is not asked again for this
  version. Two quirks cost time and are worth knowing: the app records first use
  on its very first launch, including `-ui-testing` launches, because the container
  outlives the in-memory store; and the simulator's preferences daemon caches the
  app's domain, so backdating has to go through `simctl spawn <udid> defaults
  write <container plist path> …` rather than editing the plist.

### Later the same day: the snapshot, small print, and three additions

- **The FDA snapshot is bundled.** `ndctext.zip` and `ndc_excluded.zip` were
  downloaded on Nick's approval (SHA-256 `4cd1b3fa…` and `736e55e0…`, both dated
  September 11). `Tools/build_ndc_directory.py` kept 112,246 of 116,155 product
  rows — human prescription and OTC; the 2,793 dropped are allergenics, vaccines,
  plasma derivatives and cellular therapies — 94,859 of them with a usable
  strength and 53,388 with a proprietary name that is not the generic restated.
  The delisted file contributes nothing: all 205,803 of its rows have the name,
  type and strength blanked, so the snapshot is the current directory alone and
  the tool says so. The resource is 7.5 MB in the bundle and 1.5 MB compressed.
  `NDCDirectoryBundleTests` pins Tecfidera, Prograf, Zoloft, a generic
  sertraline, a generic azathioprine, Bactrim DS, a prednisolone oral solution,
  Adderall XR and a labeler's messy mixed-salt listing to the values in the file,
  checks the vocabulary spellings they resolve to, and benchmarks a lookup.
- **Small print, measured.** Nick's worry was that a printed NDC is small. Vision
  processes stills and the captured frame at full resolution by default
  (`minimumTextHeight` of zero), and two rendered-label tests now push a Tecfidera
  label through the real OCR pipeline with the NDC line at 24 and at 16 points on
  a 1,500-point canvas — about one percent of the frame height. Both resolve to
  the exact product: brand Tecfidera, 240 mg, capsule, code 64406-0006-02, with
  the name and brand coming from the directory rather than the label. The
  printed-code reader also accepts a spaced caption ("N D C"), a code broken
  around its hyphens, and a hyphenated native layout printed without any caption,
  which is the first thing a curved bottle hides; bare digits without the caption
  stay refused because a phone number and a prescriber's NPI have that shape. The
  live camera path is VisionKit's and cannot be measured here; the captured frame
  on Review is its full-resolution second chance, the live guidance now says to
  hold the NDC line in frame once everything else is found, and the real-bottle
  pass on hardware remains the test that matters.
- **`-backdate-first-use` verified:** a launch with the flag wrote first use as
  August 13 at 19:50 UTC on September 12, thirty days back to the second.
- **The mixed-salt label now resolves exactly.** A clipped product line printed
  with NDC 47781-0174 used to be completed from the vocabulary to "Amphetamine -
  dextroamphetamine"; with the snapshot the code resolves and the exact listing
  wins. The test asserts that, and that the vocabulary completion remains the
  answer without a directory.
- **Dose history from Apple Health.** The last thirty days of doses Health
  recorded as taken come with each shared medication, offered as a toggle on the
  review screen and stored as dose events with `countsTowardSupply` false, so an
  as-needed medication has a usage rate from day one and the count the person
  just entered is not charged. That flag is the one `@Model` change in 1.1,
  declared with an inline default. **Migration verified empirically:** the
  previous commit (`05d8d09`) was built in a detached worktree, installed,
  launched against an on-disk store with demo data, and three doses were logged;
  the new build was installed over it without uninstalling, and the three
  medications, three dose events, three inventory events and four schedules
  survived with the new column defaulted to true — Furosemide read 25 on hand, as
  before. A first attempt at reading dose logs asked for the dose-event type with
  `requestAuthorization(toShare:read:)`; HealthKit refuses that with an
  uncatchable `NSInvalidArgumentException` ("Authorization to read the following
  types is disallowed"), which crashed the app in the simulator. Dose events are
  covered by the medication's per-object grant, and no second request is made.
  By hand: a dose logged in the simulator's Health app arrived as "1 dose logged
  in 30 days" on the list, as an on-by-default toggle on the review screen, and
  after saving as "Took 1 · Logged in Apple Health" in Recent Activity, with the
  supply at the 30 entered and the RxNorm code 198377 on the detail screen.
- **The exact product on the shared list.** The printable medication list now
  carries "NDC …" or "RxNorm …" on the prescription line when one is known; a
  pharmacy's own barcode payload stays off it.
- **`-backdate-first-use`.** A DEBUG-only launch argument that sets first use a
  month back, so the rating prompt can be driven in the simulator without the
  preferences-daemon detour above.
- Results: unit tests 283/283 (the 268 above plus the bundled-directory,
  small-print, imported-history, dose-ride-along, list-code and printed-code
  tests); UI tests 9/9; Release static analysis succeeded with no warnings after
  a key-path sort descriptor was replaced with an in-memory sort.

### Evening: names people use, and an icon that agrees with its words

- **Four salts, two words.** The FDA lists a mixed-salt stimulant under every
  salt of every ingredient, and the exact-identification path showed that whole
  listing as the name. `MedicationVocabulary.shortestName(forCombination:)`
  keys every multi-ingredient vocabulary entry by the sorted set of its base
  ingredients, salts and hydration set aside, and returns the shortest name for
  that set, so both Alvogen's generic listing and the Adderall XR listing read
  "Amphetamine - dextroamphetamine". Single ingredients keep their salt-aware
  paths, and succinate and tartrate are never set aside: "hydrochlorothiazide
  and metoprolol tartrate" stays as listed rather than collapsing to the
  salt-free entry, because the salt is the product. The curated brand table
  gains `amphetamine - dextroamphetamine|Adderall`, so a generic listing borrows
  the reference brand the way generic sertraline borrows Zoloft. The Health app
  shows the same long FDA name for a scanned Adderall bottle, so this is an
  improvement on Apple's own behaviour rather than a fix for a unique fault.
- **The tip jar's icon agrees with its words.** A failed tip showed a checkmark
  over "Tip Unavailable"; it now shows an orange X, and a purchase Apple is still
  processing shows a clock under "Tip Pending".
- **A capture note for the next bottle.** Nick's real-bottle pass found no NDC
  line in Scan evidence at all on two bottles, on a build of the day's final
  commit, so recognition never produced the line and the parser is not the first
  suspect. Debug builds now show, at the top of Scan evidence, what the Review
  capture did: the photo's pixel size, the crop, the zoom, the lines and codes it
  read, and the evidence counts either side of the merge cap. The hypotheses it
  decides between are in `Documentation/handoff/1.1.1-SESSION-BRIEF.md`.
- Results: unit tests 285/285; Release static analysis clean. One false alarm on
  the way: a test run failed to launch the host app with "Launchd job spawn
  failed" because the built bundle had lost its ad-hoc signature after an
  interrupted run; `xcodebuild clean` and a rebuild restored it.

### Still to do for 1.1

- Real bottles on a physical iPhone: retail and hospital-pharmacy vials,
  printed NDC and a manufacturer barcode, plus the torch check that only hardware
  can do.
- Apple Health on a fresh install of a physical iPhone on iOS 26, including a
  medication with logged doses; the review recording should include the picker.
- VoiceOver pass on the Apple Health screens and the NDC note.
- Publish the updated privacy policy page before submitting (three local commits
  in the website repository); it also corrects a stale sentence that said the
  database was excluded from backups, which stopped being true in August.
- Archive with automatic signing (HealthKit joins the App ID on the first archive),
  upload, paste the 1.1 review notes and What's New from `AppStore/SUBMISSION.md`.

Known and accepted: the review screen reached from the Health list shows both the
navigation back chevron and Cancel, as the scanned review already did in 1.0.

## August 31, 2026 (third pass) — a sig is not a product line

Scanning sertraline put `1 Week, Then Increas Every Evening If Tole Sertraline
HCl` in the name field. Reported as possibly-just-messy-OCR; it was not. The OCR
line carrying the strength was a clipped sig, and `medicationName` takes its name
from whichever line carries the strength without asking what kind of line it is.
`capturedStrength` already refuses to read a strength off a directions line; the
name search did not apply the same rule in the other direction.

Two changes:

- `medicationName` skips direction-like lines, both when locating the
  strength-bearing line and when scanning the lines beside it.
- `ScanParser.looksLikeMedicationName` gates the one remaining path that fills
  the name without the vocabulary confirming it. A reading must have the *shape*
  of a name: not direction-like, no digits, no comma, at most four tokens.

This was the residual risk recorded in the previous pass, and the shape rule is
the reason it did not become a blanket fail-closed. Requiring vocabulary
confirmation for every name would have been simpler, but it would throw away a
pharmacy's own wording — "Amphetamine salt combo" is a real label for a drug the
vocabulary lists under four salt names — and that wording is three short words,
while a clipped sig is a run of words with digits and commas in it. The two are
separable by shape, so the useful half of the path is kept and the dangerous half
is not.

Verified: 220 unit tests pass, up from 217, including the existing expectation
that the stimulant label still fills every field it prints. Release app-target
static analysis succeeds. The reported string now yields a blank name with a
correctly captured `50 mg` strength, and the same label read with the product
line intact still resolves to Sertraline / Zoloft.

Still open, and deliberately: a foreign-language dosing line, or an unusual
English one, printed on the strength line in four words or fewer with no digits
or commas would still stand as a name.

## August 31, 2026 (second pass) — the name field, fail-closed

A sertraline bottle autofilled as **Risedronate, brand Actonel**, and a hospital
label's **patient address** reached the name field. Both were reproduced before
anything was changed, and both turned out to be the same defect wearing two
faces: a name was accepted on evidence that never established it came from the
product line.

**How the wrong drug got in.** `SERTRALINE HCL` matched no vocabulary entry at
all — the bare ingredient is shorter than the reading, and the spelled-out salt
is too far by edit distance — so the genuine product line contributed nothing.
The candidate builder joins adjacent OCR lines into synthetic strings and a busy
label yields dozens; one of them resembled `risedronate` closely enough to score
through suffix completion, which was willing to invent up to five leading
characters. Being the label's *only* match, it was accepted — and accepted with
`.vocabulary` provenance, the app's highest confidence. `withBrandNames` then
added Actonel. Every step behaved as designed.

Four changes, each reproduced before and after:

- Suffix completion now has to be near-certain (missing ≤ 3, coverage ≥ 0.80),
  while prefix completion is unchanged. A reading clipped at the end keeps the
  part that distinguishes one drug from another; a reading clipped at the start
  asks us to invent it. `edronate` no longer completes to risedronate.
- `MedicationVocabulary.exactMatch` sets aside a salt that names the same
  medicine, so `SERTRALINE HCL` and `VALGANCICLOVIR HCL` resolve. It deliberately
  refuses to strip `succinate` or `tartrate`: those distinguish two metoprolol
  products with different brands.
- A vocabulary hit taken from anywhere on the label now has to corroborate the
  name the parser read off the strength line. `SERTRALIN 50 MG` beside `FOLIC`
  and `ACID` produced `Folic acid / Folvite` before this; it now yields
  `Sertraline / Zoloft`.
- A name read from a line *beside* the strength carries new provenance,
  `.adjacentToStrength`, and must be vocabulary-confirmed. Only a name printed on
  the strength line itself still stands unconfirmed, which is what the
  strength-anchored path was for. `PFIZER INC`, `JOHN SMITH`, `MEMBER ID: 1234`
  and `42 ELM` now leave the field blank; `AMPHETAMINE SALT COMBO 20 MG TAB`
  still resolves.

`ScanParser.isAddressOrPersonName` rejects street types, postal codes, hospital
and pharmacy words, and the `LAST, FIRST` shape, and `isPlausibleName` routes
through it on both the parser and candidate paths.

**A separate wrong name found while auditing.** Vocabulary keys dropped digits,
so `vitamin b12` and `vitamin b6` shared a key and a B12 bottle resolved as B6.
Keys keep digits now.

**Directions were assembling on no real scan at all.** The wrapped-sig join
tested adjacency by evidence *item*. The photo path emits one `ScanEvidence` per
recognised line — sharing a capture, numbered top to bottom — so no two lines
were ever adjacent; the live camera emits neither a capture nor a line number.
Adjacency now uses the capture and line number when present and reading order
when not, and refuses to join across two captures. The Bactrim label's
`TAKE 2 TABLETS BY MOUTH ON MONDAYS, / WEDNESDAYS, AND FRIDAYS` assembles again
on both paths.

The trust gate itself was also too strict and rejected ordinary sigs. It now
accepts sig abbreviations (`BID`, `TID`, `QID`, `PRN`, `Q4H`, `QHS`), common
administration phrases (`WITH FOOD`, `AT NIGHT`, `BEFORE MEALS`), a bounded
course length (`FOR 7 DAYS`), `SWISH`, an `ADULTS:`/`CHILDREN:` qualifier, and
compact openings (`1/2 TABLET`, `2.5 ML`, `1 TO 2 TABLETS`, `1 TAB PO BID`). All
three original garbage strings are still rejected, and so is a dangling
`TAKE 1 TABLET BY MOUTH TWICE`.

The review screen's explanation of scanned codes was removed. Nothing in the app
looks a code up, so it described a caveat about a feature that does not exist.

Verified: 217 unit tests pass, up from 199. Release app-target static analysis
succeeds. Both reported labels, the folic-acid case, the B12 case, the label
furniture cases and the Bactrim sig were each reproduced failing and then
confirmed fixed.

Residual risk accepted for now, recorded rather than silently carried: a
two-token junk line can still complete through `compoundEdgeScore` when one
token is exact and the other is within one character of a real prefix, and a
foreign-language or unusual English dosing line printed on the strength line can
still stand as a strength-anchored name.

## August 31, 2026 — clipped names, one row of pills, names that swap

- **A clipped label name reached the medication field.** Scanning metoprolol
  succinate produced a fragment from the middle of the name. Probing the parser
  showed it was systematic, not a one-off: the strength-anchored path exists so a
  pharmacy's own wording survives ("Amphetamine salt combo" is a real label for a
  drug the vocabulary lists under four salt names), and it applies no vocabulary
  check at all. A bottle's curve clips the ends off the product line, and
  `OPROLOL SUCCINATE ER`, `TOPROLOL SUCCINA` and `ROLOL SUCCIN` were all
  name-shaped enough to pass every other gate while naming no real drug.
  `MedicationVocabulary.isFragmentOfLongerName` now rejects a reading that is
  contained in a longer real name without being one; a pharmacy's own wording is
  not a substring of anything, so it still survives.
  `matchIgnoringTrailingNoise` recovers the opposite case, resolving
  `METOPROLOL SUCCINATE ER 50 MG TAB GG 263` by setting aside the release form
  and imprint code. The brand table is consulted before that trimming, because
  `Toprol XL` is a whole name rather than `Toprol` with a release form after it.
  All five degraded readings now leave the field blank; all six clean ones
  resolve.

- **Medication name and brand name now fill each other in.** Entering a brand in
  the name field left it in both fields, and entering a brand in the brand field
  filled nothing. Both are reconciled when a field loses focus — commit time, not
  per keystroke, since rewriting a name under the cursor is hostile. Confirmed by
  hand: typing `Prograf` into Medication name and moving on leaves name
  `Tacrolimus`, brand `Prograf`, with the brand row revealed. The live
  as-you-type fill now uses `brandName(forGeneric:)` rather than `resolve`, so
  the same word never sits in both fields at once.

- **Scanner progress is one row of four.** The Code pill is gone: a barcode is
  still captured and shown on the review screen, but nothing in the app looks a
  code up, so announcing it asked someone to keep turning a bottle for a fact
  that changes nothing. That brings Name, Strength, Quantity and Refills back to
  a single row at full size. All four are now permanently on screen — dimmed with
  a faint outline until found, then full strength with a green edge and a
  checkmark, so the change reads without relying on colour.

- **The banner agrees with the pills.** `Everything found` previously fired on
  name, strength and quantity while the Refills pill sat dark above it. The
  banner now waits for all four.

- **Controls.** `Clear Scan` is a capsule button rather than bare text. Both
  primary buttons hold one line, so their heights match; `Capture & Review` drops
  its arrow, which was pushing the label into truncation.

- The progress row moved down to clear the system scanner's own "Slow down"
  hint, which was reading through the pills.

Verified: 199 unit tests pass, up from 191. Release app-target static analysis
succeeds. Scanner, editor and the name swap checked by hand on the iPhone 17 Pro
simulator.

Still hands-on only: the "Slow down" clearance, which only appears with a live
camera and cannot be reproduced in the simulator.

Known: at accessibility text sizes four pills wrap to a second row that can graze
the top of the scan frame. Deepening the band further would shrink the region the
scanner actually reads.

## August 30, 2026 (third pass) — brand field earns its place, transplant coverage

The brand field no longer occupies a row until it has an answer. An empty
`Brand name` input sat in the medication form for every drug without a useful
brand — most of a household's list once supplements and old generics are
counted — and cost a skip on every entry. It is replaced by a compact
`Add brand name` button, and the field appears already filled the moment a
recognised name resolves. Once revealed it stays revealed; taking the row away
again mid-edit would be worse than an empty one. Confirmed by hand: the form
opens with the button, and typing `Mycophenolate sodium` reveals the field
carrying `Myfortic`.

Brand table expanded from 247 to 266 pairs, weighted toward lung-transplant
care, the audience this app is most likely to reach.
Added: `azathioprine|Imuran`, `mycophenolate
sodium|Myfortic`, `acyclovir|Zovirax`, `valganciclovir|Valcyte`,
`letermovir|Prevymis`, `maribavir|Livtencity`, `posaconazole|Noxafil`,
`isavuconazonium|Cresemba`, `methylprednisolone|Medrol`, `alendronate|Fosamax`,
`warfarin|Coumadin`, `linezolid|Zyvox`, `dornase alfa|Pulmozyme`,
`nintedanib|Ofev`, `pirfenidone|Esbriet`, and the CF modulators
`ivacaftor|Kalydeco`, `ivacaftor / lumacaftor|Orkambi`, `ivacaftor /
tezacaftor|Symdeko`, `elexacaftor / ivacaftor / tezacaftor|Trikafta` — cystic
fibrosis being one of the larger paths to a lung transplant.

Every added generic was checked against `Meds/Resources/MedicationNames.txt`
first: a pair whose generic is absent from that vocabulary can never be reached
by a scan.

Deliberately still blank, each pinned by a test so a later expansion cannot add
one back without someone deciding to: `prednisone` (Deltasone obsolete, Rayos is
a different delayed-release product), `aspirin` (no single brand),
`cyclosporine` (Neoral, Sandimmune and Gengraf are not interchangeable — the
most important omission in the table), `everolimus` (Zortress in transplant,
Afinitor in oncology), `nystatin`, `budesonide`, `tobramycin`, `albuterol`,
`ipratropium` (Atrovent names both an inhaler and a nasal spray), `lisinopril`,
`dapsone`, `pentamidine`, `ganciclovir`, `ursodiol`.

An independent review of the 18 proposed pairs argued for removing seven. Two
were accepted in substance — `ipratropium|Atrovent` was dropped on the same
route reasoning that dropped albuterol — and the review's own two proposals,
`letermovir|Prevymis` and `maribavir|Livtencity`, were adopted; both are
single-brand CMV drugs central to transplant care. The rest were kept: the
review disclaimed any ability to verify market status, and its objections to
`posaconazole|Noxafil` (Noxafil is the brand for every posaconazole
formulation) and `alendronate|Fosamax` did not hold up. Two are judgment calls
worth revisiting: `warfarin|Coumadin` keeps a brand discontinued in 2020 because
it remains the name patients and clinicians actually say for a high-risk drug,
and `methylprednisolone|Medrol` names the oral brand family while Solu-Medrol
and Depo-Medrol are injectable — defensible because this app tracks what a
person keeps at home.

`MedicationBrandIndex` now resolves a repeated brand deterministically by file
order rather than dictionary ordering. Myfortic legitimately answers to both
`mycophenolate sodium` and `mycophenolic acid`, so the table's uniqueness test
was relaxed from "no brand repeats" to "a repeated brand still resolves", which
is the invariant that actually matters.

Verified: 191 unit tests pass, up from 187. Coverage on the same 30-medication
reference list used to measure this before rose from 23/30 to 25/30; of the five
still blank, four are drugs with no brand worth printing.

## August 30, 2026 (second pass) — responsiveness, tab routing, scanner pills

Four reports from using the previous build, each reproduced on the simulator
before acting.

- **App-wide sluggishness.** `MedicationListShareButton` declared four
  unfiltered `@Query` properties, and it lives in the Medications toolbar, so it
  is mounted for the whole session. Moving the share action out of Settings had
  quietly promoted four full-ledger observations — every dose and inventory event
  — from "only while a sheet is open" to "always". Only the active-medication
  check stays observed; the rest is fetched when the button is tapped.
  `RootView` was the larger lever and was already like this before today: it owns
  the `TabView`, so its four queries re-rendered every tab on every ledger write,
  while the values were only ever read at launch and on foregrounding. Every
  screen that mutates data replans notifications itself, so those became fetches
  too. Verified by hand: logging a dose still updates Today's counter and card.
  The PDF renderer was measured and exonerated — 25 medications render in 55 ms.

- **A detail view opened scrolled under the navigation bar and would not scroll
  back up.** Reported after using the scanner; the scanner turned out to be
  innocent. Bisected to opening and closing the Add sheet at all, then confirmed
  identical on the previous commit — pre-existing, not a regression. Cause: the
  Add tab committed `.add` as a selection and an `onChange` handler set it back,
  so the TabView switched to an empty tab and returned while a sheet was
  presenting, and the tab it bounced off came back with a stale scroll inset.
  Selection now routes through a binding that never commits `.add`. Confirmed
  fixed by the same reproduction.

- **Settings wore a person glyph**, which implies an account this app
  deliberately does not have. It is a gear now.

- **Scanner progress pills squashed instead of wrapping.** A fifth pill appeared
  with this pass's Refills indicator, and an `HStack` compresses every pill
  rather than wrapping. They now flow onto a second row at full size via a small
  `Layout`. Because the pills share the top band with the scan frame,
  `ScanFrameLayout` gained separate `topInset` (92) and `bottomInset` (64) in
  place of one symmetric `verticalInset`. Both the drawn outline and the
  recognition region use the same numbers, so the green frame still describes
  exactly where the scanner is reading.

Verified: 187 unit tests pass; scanner, Today, Supply, and the detail view
checked by hand on the iPhone 17 Pro simulator at default and accessibility text
sizes.

Known: at accessibility text sizes a wrapped second row of pills can still graze
the top of the scan frame. The band cannot grow without shrinking the region the
scanner actually reads, which is the worse trade.

## August 30, 2026 — pill-box session findings: doses, combination strengths, brand names

Seven defects found while entering a week of medications from
real bottles, each reproduced against source before acting.

Correctness:

- **No dose other than 1 could be entered.** A bottle dosed at 2.5
  tablets daily could not be recorded. `DoseSchedule.doseQuantity` was already a
  `Double` and the editor did contain a decimal field, but it rendered as bare
  right-aligned text beside the `Time` row's chrome, so it read as a label and was
  never found. It is now a filled, tappable field with a stepper — half-unit for
  tablets and capsules, whole-unit otherwise — with the label above the control so
  no unit name clips at either edge. Confirmed by hand: 2.5 tablets entered and
  saved, and the schedule row reads *2.5 tablets*.
- **A typed dose could be discarded by Save.** The field only wrote back on focus
  loss, and the Add toolbar button does not resign first responder, so typing 2.5
  and tapping Add saved the previous amount. The value is now tracked as it is
  typed. Confirmed by hand: typed and saved without dismissing the keyboard.
- **A combination strength lost its first ingredient.** A
  `400-80 MG` combination label autofilled `80 mg`. The strength
  pattern now matches combination forms whole, and every captured strength is
  canonicalised, so the `50MG` and `5 mg` seen on two bottles the same evening now
  read alike.
- **`1,000 IU` matched as `000 IU`.** Grouped digits were not part of the number
  form, so a vitamin label offered a tenfold-wrong strength for confirmation.
- **Three real bottles produced unusable directions.** `is Filled: 8/13/2026 RPh:
  Mg by mouth 1 time each chew.`, `- capsule by mouth 2 tim agNe 8.5 mg total
  twice da`, and `like 2 tablets by mouth rednesdays, and fridays` were all
  accepted, because a bare ` by mouth` satisfied the old guard on its own. A
  candidate must now open with a direction verb or a dose phrase, carry a
  frequency, and be free of dispensing markers, dates, phone numbers, and OCR
  garbage. A sig wrapped across adjacent lines of one capture is assembled and
  re-tested. All three now yield a blank field.
- **A pharmacy imprint reached the name field.** A Zoloft bottle produced
  `Sertraline Hcl G1`. A trailing imprint token is dropped and the salt is cased,
  but only while two tokens still stand, so `Vitamin B12` is not truncated.
- **Guidance never updated.** The scanner said `Name matched — rotate for
  strength, quantity, and refill details` with every progress pill already lit,
  and its banner crossed the green frame. It now names only what is still missing,
  matches the pills' material and shape, and sits in the band below the frame.

Additions:

- A `brandName` field on `Medication`, filled from a curated 247-pair table.
  Scanning a generic supplies the brand; scanning a brand supplies the generic.
  Both appear on the editable review screen before anything is saved, and the
  brand prints on the shared list. Exact, letters-only matching with a trailing
  salt or release-form fallback — no fuzzy matching, because a plausible but wrong
  brand on a clinician's list is worse than a blank.
- Share Medication List moved from Settings onto the Medications screen toolbar.

Review findings, each fixed and covered by a regression test:

- Wrapped-sig assembly joined lines from different captures, so three unrelated
  readings could become `TAKE 1 TABLET Patient: Jane Doe TWICE DAILY` and print on
  the shared PDF. Lines now carry the evidence item they came from.
- Dispensing markers matched as substrings, rejecting `Apply lotion…` for `lot`
  and `Use on exposed skin…` for `exp`. They match whole words now, and `patient`
  and `doctor` were added.
- Renaming a medication kept the previous drug's brand. An autofilled brand is now
  replaced on rename; one typed by hand is left alone.
- The stepper's floor was its own step size, so a stored 0.5 mL dose would have
  been silently rounded up by the first tap.
- A refill count was treated as required scanner progress, which an OTC bottle
  never satisfies, leaving the banner nagging forever. It now has its own progress
  pill instead.

Verified:

- 187 unit tests pass on the iPhone 17 Pro simulator; the suite was 146 before
  this pass.
- Release app-target static analysis succeeds.
- **SwiftData migration confirmed empirically, not assumed.** A build of the
  previous commit was made in a detached worktree, installed, and used to create a
  medication, a schedule, and an opening inventory event in an on-disk store. The
  new build was then installed over it without uninstalling. The medication, its
  8:00 AM 1-tablet schedule, and the 42-unit ledger balance with its starting-count
  event all survived. `brandName` is declared with an inline default, matching how
  `refillRemindersEnabled` was added.
- End-to-end by hand on the simulator against rendered pharmacy labels: a Bactrim
  label yields name `Sulfamethoxazole / trimethoprim`, brand `Bactrim`, strength
  `400-80 mg`, and the assembled sig `TAKE 2 TABLETS BY MOUTH ON MONDAYS,
  WEDNESDAYS, AND FRIDAYS`; a tacrolimus label yields brand `Prograf` and clean
  directions.

Known and accepted: `isTrustedDirections` still admits a thin instruction such as
`Use daily`. It is shown for confirmation on an editable screen and is not worth
tightening at the cost of rejecting `TAKE AS DIRECTED`.

Still hands-on only: live-camera behaviour on a physical iPhone, including the
new banner placement over a real preview.

## August 28, 2026 (third pass) — audit fixes, unlogged-dose catch-up, delivery honesty

Findings from a full read of the app, each verified against source before acting.

Correctness:

- **Take Now could double-log a dose.** The medication detail screen wrote a
  `DoseEvent` with no `scheduleID` or `scheduledAt`, and Today matches a card to
  its log by both. So Take Now left the card reading *Due*, the natural next tap
  logged it again, and the supply was charged twice. Take Now now claims the same
  dose Today is offering, via one shared `ScheduleEngine.actionableDose`, and the
  UI-test overdue override moved into `ScheduleEngine.timingState` so the two
  screens cannot diverge under test either. Confirmed by hand on the simulator:
  Take Now on Furosemide leaves the 8:00 AM card reading *Taken · Logged*.
- **Take Now logged the wrong amount.** It used `schedules.first`, always the
  earliest of the day, so a 1-tablet morning and 2-tablet evening regimen
  recorded 1 at night. An unscheduled log now uses the schedule nearest that time
  of day, measured the short way around midnight.
- **As-needed forecasts always divided by thirty days** while only requiring
  three logged doses. A medication started ten days ago reported three times the
  runway it had, always in the optimistic direction. The rate is now measured
  over the history that exists, capped at thirty days, and the explanation says
  which window it used.
- `medicationQuantityText` trapped on any `Double` past `Int.max`; the count
  fields accept as many digits as a person can type, so a long entry crashed.
- Strength parsing gained `units` and `IU`, so insulin, heparin, and vitamin D
  labels no longer leave the field blank. Because a directions line quotes a
  dose in the same units ("Inject 10 units"), the strength is now read from
  non-direction lines first and only falls back to the whole label.
- Expirations more than six years out are rejected as an OCR slip on the year.
  Dates already past are kept: an expired package is real information.

Reminder delivery:

- **Nothing told anyone when reminders were off.** A refused or withdrawn
  authorization made scheduling a silent no-op, and `center.add` failures were
  discarded by `try?`. Both are now recorded by `NotificationHealth` on every
  pass and stated on Today with the action that fixes them.
- Plans are rebuilt when the app returns to the foreground. `task` runs once per
  view lifetime, so refill alerts — one-shot dates, unlike the repeating dose
  triggers — stopped being replaced for anyone who left the app closed.
- A prescription with no refills left warns on the longer of the person's lead
  time and a ten-day prescriber lead, and says a new prescription is what's
  needed. `refillsRemaining` had been scanned, decremented, and displayed, but
  never used.

Product:

- **New: unlogged doses stay answerable for two days on Today.** Today ended at
  midnight, so an evening dose nobody confirmed vanished with no screen left that
  could answer "did last night happen?" — and an unlogged dose reads as unspent,
  quietly stretching the forecast. Three compact rows, retroactively logged at
  their scheduled time, with a "Not Now" that sets them aside until tomorrow so
  someone tracking supply without logging is not nagged permanently.
- **The shared medication list is paginated onto US Letter pages.** It rendered
  as one page sized to its content — for a dozen-plus medications, a sheet about
  three feet tall that prints to nothing legible. Pages carry "Page n of m" and
  no medication is split across a break.
- The exported PDF is swept from the temporary directory at launch rather than
  left there indefinitely. Deleting it at share time would race an AirDrop still
  in flight.
- `-seed-missed-doses` backdates the demo schedules so the catch-up state can be
  driven by hand; the demo store is unchanged without it.

Copy and greeting:

- **The greeting said "Good evening" at three in the morning.** Evening was the
  fallback branch, so every hour before five fell into it. There are now four
  bands, with 22:00 to 04:59 reading "Good night" — a real hour to be awake and
  giving a dose.
- The story sheet and onboarding say more about whose care it was, sign off
  by name, and say "the app we needed". Em dashes
  are gone from the story, the onboarding, and the signature.
- The Share Medication List footer no longer promises "a one-page PDF", which
  stopped being true when the export was paginated.

Documentation:

- `README.md` said iOS 26.0; the project has targeted 18.0 since `8143b3e`.
- Test counts below supersede the 79/6 recorded in `RELEASE_CHECKLIST.md`.

Results:

- Unit tests: 146/146 (127 before, plus 19 covering every fix above), including
  the widened greeting-boundary cases.
- UI tests: 9/9, including the Today and editor accessibility audits, which now
  run against the added banner and catch-up card.
- Release static analysis on the app target: succeeded, no warnings beyond
  Xcode's no-AppIntents metadata-skip message.
- Hands-on simulator pass on iPhone 17: catch-up card logs and re-flows, Take Now
  reconciles with Today, notification banner renders and offers its action.

Still hands-on, unchanged from the passes below: App Store Connect upload and
server-side validation, tip IAP setup, locked-device reminder actions, the
VoiceOver order/rotor pass, the Focus-breakthrough check, and a physical-device
re-check of torch + live preview. **The banner's denied-permission and
partly-scheduled states have been driven in the simulator but not on a device.**

## August 28, 2026 (second pass) — torch fix, log-all-due, medication list PDF

- Fixed the hands-on finding that turning the flashlight on froze the live
  scanner: the torch is now driven on the AVCaptureDevice instance inside
  VisionKit's own session (found via its preview layer) instead of a second
  instance of the camera, whose configuration lock interrupted the session. A
  recovery nudge restarts scanning if the session still stops. **Needs a fresh
  physical-device check of torch + live preview together.**
- Scanner guidance is now state-aware: the photo-fallback screen no longer says
  to rotate a bottle in front of a camera that is off, and guides toward adding
  photos instead.
- New: "Mark all N due doses taken" on Today (confirmation-gated, each dose
  still logged individually at its scheduled time), and Settings → Your records
  → "Share Medication List", a one-page monochrome PDF of active medications,
  schedules, supply, refills, and expirations rendered on device.
- Unit tests: 127/127, adding medication-list document/PDF tests and a second
  rendered-label OCR test (OTC shape: package count wins over the dose printed
  in the directions; BEST BY named-month date).
- UI and accessibility tests: 9/9, adding the log-all-due flow.
- Release static analysis on the application target: clean.
- Simulator panel pass on iPhone 17 Pro: Today with the log-all shortcut
  (before/after states), the confirmation dialog copy, Settings share sheet
  producing a 19 KB PDF with correct live totals, the photo-fallback scanner
  states, and the full photo → OCR → review flow on a rendered Tacrolimus
  pharmacy label — every field (name via vocabulary, strength, form,
  directions, quantity 60, refills 2, DISCARD AFTER date, lot) prefilled
  correctly.

## August 28, 2026 — scan reliability and reminder-cap pass (build 2)

Covers: flashlight control and camera-session recovery in the scanner, expiration
parsing for pharmacy wording (`DISCARD AFTER`, `USE BY`, named months, OCR
pipe-for-slash misreads), package-quantity vs. directions disambiguation,
matching photo OCR languages to the live scanner, comma-decimal locale
quantities, a 60-request notification cap that always prefers dose reminders and
the nearest refill alerts, refill sheet prefilled from refill history, and
same-day schedule overlap validation.

- Full unit tests: 120/120 on the iPhone 17 Pro simulator (Debug), including a
  new end-to-end test that renders a pharmacy-style label image and runs it
  through the real Vision OCR → sanitize → parse pipeline. That test caught
  Vision reading a printed slash as a pipe in `DISCARD AFTER 07/14/26`; the date
  patterns now accept `|` and `.` separators.
- UI and accessibility tests: 8/8 on the iPhone 17 simulator.
- Release static analysis on the application target: clean.
- Hands-on gates unchanged from the August 24 record below; the flashlight
  button and torch shutoff paths need a physical-device check (no torch exists
  in the simulator, so the button correctly stays hidden there).

### Time Sensitive dose reminders (same day, later)

Dose reminders now carry `interruptionLevel = .timeSensitive` so they can break
through Focus modes; refill alerts stay `.active`. The entitlement lives in
`Meds/Meds.entitlements` and is wired through `CODE_SIGN_ENTITLEMENTS` in both
app configurations.

- `plutil -lint` passes on the entitlements file; full unit tests remain 120/120.
- Debug simulator build embeds the entitlement in the simulated entitlements
  (`Meds.app-Simulated.xcent`); `codesign -d --entitlements` on a simulator app
  reads the host slot and legitimately shows it empty.
- Release device build required `-allowProvisioningUpdates` once to regenerate
  the team provisioning profile with the Time Sensitive Notifications
  capability, then succeeded; the signed binary's entitlements contain
  `com.apple.developer.usernotifications.time-sensitive`.
- **The August 24 distribution artifacts are superseded**: the archive at
  `build/MedsAhead-1.0-Submission-Final.xcarchive` and the export in
  `build/AppStore-Submission-Final/` predate the entitlement and must not be
  uploaded. Re-archive and re-export; the App Store distribution profile will
  be regenerated with the capability during export. Re-run the strict
  signature, provisioning, privacy-manifest, and ZIP-integrity checks on the
  new IPA.
- New hands-on gate: with a Focus mode active on the paired iPhone, confirm a
  dose reminder breaks through and shows the system "Time Sensitive" chrome,
  and that Settings → Meds Ahead offers the per-app Time Sensitive toggle.

---

Date: August 24, 2026

Toolchain: Xcode 26.6, iOS 26.5 SDK

Release: 1.0 (build 1)

Reserved App Store name: `Meds Ahead: Supply Tracker` (Apple ID `6804540619`)

## Passed

- Debug iOS Simulator build
- Release iOS Simulator build
- Release generic iOS-device build
- Release static analysis on the application target
- Unsigned arm64 archive and shallow store validation
- Development signing with team `8G2SF9YU87`
- App Store distribution export signed by `Apple Distribution: NICHOLAS GEORGE CHRISTOFORAKIS (8G2SF9YU87)`
- The August 23 distribution artifact is superseded by the August 24 scanner changes and must not be uploaded
- Explicit store profile for `8G2SF9YU87.com.christoforakis.Meds`, with `get-task-allow = false`
- Exported IPA passes strict code-signature verification, archive integrity testing, privacy-manifest lint, and non-exempt-encryption inspection
- Installation and launch on a paired iPhone 16 Pro
- Unit coverage includes forecasting, supply accounting, scheduling, Latin-only stable multi-side scan evidence, ROI crop mapping, RxNorm-backed compound-fragment repair, noisy-label parsing, same-time reminder consolidation, notification-action logging, and tap routing
- 6 UI tests: onboarding, manual medication critical flow, Today and medication-editor accessibility audits, largest accessibility text in the editor, and accessible overdue-dose state
- Post-lifecycle-fix scanner-focused tests: 50/50 at `/private/tmp/Meds-Ahead-Scanner-Focused-20260824-0044.xcresult`
- Post-lifecycle-fix full unit tests: 76/76 at `/private/tmp/Meds-Ahead-Full-Unit-20260824-0045.xcresult`
- Post-lifecycle-fix UI tests: 6/6 at `/private/tmp/Meds-Ahead-UI-20260824-0046.xcresult`
- Post-lifecycle-fix Release build and app-target static analysis succeeded at `/private/tmp/Meds-Ahead-Release-Build-20260824-0047` and `/private/tmp/Meds-Ahead-Release-Analyze-20260824-0048`
- The exact signed Release device build at `/private/tmp/Meds-Ahead-Device-20260824-0049` installed on the paired iPhone 16 Pro; physical launch and live-continuation confirmation remain below because the phone locked before remote launch
- Final camera-handoff and grouped-reminder focused tests: 20/20 at `/private/tmp/Meds-Ahead-Scanner-Grouped-20260824-0053.xcresult`
- Final full unit tests: 79/79 at `/private/tmp/Meds-Ahead-Unit-20260824-0055.xcresult`
- Final UI tests: 6/6 at `/private/tmp/Meds-Ahead-UI-20260824-0061.xcresult`
- Final signed Release build succeeded at `/private/tmp/Meds-Ahead-Release-20260824-0062`; Release app-target static analysis also succeeded
- The exact final signed Release app from `/private/tmp/Meds-Ahead-Release-20260824-0062/Build/Products/Release-iphoneos/Meds.app` passed strict code-signature verification, installed on the paired iPhone 16 Pro, and launched successfully
- After removing automatic still capture and scanner recovery from the live session, the current scanner/parser/interpreter tests pass 43/43 at `/private/tmp/Meds-Ahead-Continuous-Scan-20260824-0065.xcresult`
- The current signed Release device build succeeded at `/private/tmp/Meds-Ahead-Continuous-Device-20260824-0066`, installed on the paired iPhone 16 Pro, and launched successfully
- Final post-form unit tests pass 79/79 at `/private/tmp/Meds-Ahead-Final-Unit-20260824-0067.xcresult`, including explicit greeting boundaries
- Final post-form UI and accessibility tests pass 6/6 at `/private/tmp/Meds-Ahead-Final-UI-20260824-0069.xcresult`
- Final signed Release build succeeded at `/private/tmp/Meds-Ahead-Final-Release-20260824-0070`; app-target Release analysis succeeded at `/private/tmp/Meds-Ahead-Final-App-Analyze-20260824-0072`
- The final Release build installed and launched on the paired iPhone 16 Pro
- The final IPA passes ZIP integrity, strict code-signature, privacy-manifest, export-compliance, and provisioning checks; it is signed by `Apple Distribution: NICHOLAS GEORGE CHRISTOFORAKIS (8G2SF9YU87)` with `get-task-allow = false`
- Review fields retain compact persistent names, including a visible `Refills remaining` label when its value is zero
- Optional tips use three consumable StoreKit products, remain hidden until Apple returns configured products, unlock no features, and finish verified transactions
- After restoring the intended three tip amounts, the definitive archive compiled at `build/MedsAhead-1.0-Submission-Final.xcarchive`, installed and launched on iPhone 16 Pro, and exported to `build/AppStore-Submission-Final/Meds.ipa`; the IPA again passed signature, profile, privacy, encryption, and ZIP-integrity checks
- The source and built privacy manifests pass `plutil` validation and declare the app-only UserDefaults reason `CA92.1` and elapsed-event system-boot-time reason `35F9.1`; no data collection or tracking is declared
- Equal-time dose schedules now produce one slot-level notification such as `8:00 PM meds are ready`; grouped alerts route into Meds Ahead for review and intentionally omit one-tap dose actions
- Physical-device critical-flow and automated accessibility-audit passes on iPhone 16 Pro
- Raw live label recognition and refill-alert delivery confirmed on iPhone 16 Pro
- Production replay of the later OTC and curved prescription photos returns Melatonin / 5 mg / 120 tablets and the complete amphetamine - dextroamphetamine generic name without invented directions
- Light and dark appearance on 6.1-inch, 6.3-inch, and 6.9-inch simulators
- Largest accessibility text size with adaptive Today and Supply layouts
- Reduce Motion, Reduce Transparency, and Increase Contrast simulator review
- 6.9-inch App Store screenshots: 1320 by 2868 JPEG, no alpha
- Privacy manifest, app icons, plist/JSON syntax, and whitespace validation
- Today, Supply, and medication-detail forecasts refresh their calendar-dependent state across midnight without relaunching

Xcode's metadata processor emits `Metadata extraction skipped. No AppIntents.framework dependency found.` This is a tool status message for an app with no App Intents dependency, not a compiler or application-code warning.

## Account or hands-on gates

- Upload the final distribution build and complete App Store Connect server-side validation.
- Create and submit the three optional consumable tip products with version 1.0, including their prices, availability, localization, and review screenshots.
- Complete pricing, availability, EU DSA status, accessibility declarations, and review-contact fields.
- Verify the `Taken` and `Skip` reminder actions from the locked iPhone and run a five-minute camera energy/thermal check.
- Complete a hands-on VoiceOver order/rotor pass.
