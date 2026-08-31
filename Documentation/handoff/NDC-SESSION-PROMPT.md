# Session prompt — NDC-based medication identification

Paste everything below the line into a fresh Claude Code (Opus 5) session opened
in `/Users/nichris/Documents/Meds app`. The Luna fleet is configured in that
repo already (`.mcp.json`, `.claude/agents/orchestrator.md`, `AGENTS.md`).

---

Good morning. Meds Ahead is an offline iPhone medication supply manager I built
for my mother, who manages a lung-transplant regimen for my brother. It is at
1.0-candidate and I shipped last night's build as-is. Today I want to explore and
then implement a change to how the app identifies a medication from a bottle.

You are the orchestrator for the ten GPT-5.6 Luna workers configured in this
repo. Read `AGENTS.md` first; it has the rules, the map, and the build/test
commands. `Documentation/VERIFICATION.md` is a dated record — its three newest
entries are last night's work and are the background for this task.

## Why this task exists

Identification is currently OCR plus fuzzy matching against a bundled
RxNorm-derived name list. Over one evening of scanning real bottles it produced,
in order: a sertraline bottle read as **Risedronate / Actonel**, a patient
address accepted as a medication name, a vitamin B12 bottle read as **B6**, and a
clipped dosing instruction read as a name. Each was reproduced, root-caused and
fixed, and each fix is regression-tested — but they were four instances of one
structural problem. The app is inferring identity from text that is
ambiguous, clipped, and sometimes not about the medication at all.

Every bottle in this house — retail orange vials and Boston Children's blue
ones — prints an **NDC**. That is an exact product identifier: manufacturer,
drug, strength, package. It turns identification from inference into lookup.

## What already exists

- `ScanParser.ndcPattern` already reads `NDC 12345-678-90` off labels.
- Barcode payloads are already captured with their symbology.
- Both land in `Medication.productIdentifier` / `productIdentifierType`, are
  shown read-only on the review and detail screens, and are **used for nothing
  else**.
- Note a wrinkle worth deciding about early: in `ScanParser.parse`,
  `preferredBarcode` takes precedence over the NDC text, so when any barcode is
  in frame the NDC we read is discarded. One field is currently doing two jobs.

## The idea to evaluate, then build

Bundle a trimmed FDA **NDC Directory** (free, downloadable, no API key) as an
app resource, and resolve a scanned NDC to generic name, brand name, strength
and dosage form. Offline, no network at runtime, consistent with the app's
no-account/no-cloud posture. When an NDC is present it becomes the fast path and
the existing OCR heuristics become the fallback.

**Do not treat this as settled.** Investigate first and tell me if it is wrong
or if something better exists. Questions I actually want answered, with evidence:

1. How often does a US pharmacy label print a readable NDC in the text, versus
   only in a barcode, versus neither? Retail and hospital outpatient both.
2. What is really in the FDA NDC Directory, what are its fields, how big is it
   trimmed to marketed human drugs and the four fields above, and how often does
   it change? What is the licensing/attribution position?
3. NDCs appear as 10-digit and 11-digit forms with hyphens in three different
   segment layouts. What normalisation is needed so a label's rendering matches a
   directory row? Where does that ambiguity bite?
4. Pharmacy-label barcodes: how often do they encode the NDC or a GTIN that
   converts to one, versus an internal Rx number? Is decoding GTIN-to-NDC worth
   doing in the same pass, given it shares the lookup table?
5. Is there a better offline option I have not considered?

## The gating step — ask me before acting

Fetching the FDA data means going outside the repository, and the Luna workers
are forbidden network access. Work out exactly what file you need and where from,
then **stop and ask me** — I will download it or approve you doing so. Do not
attempt it unilaterally, and do not add any runtime network call to the app under
any circumstances; offline is a promise this app makes.

## Constraints

- `AGENTS.md` binds. In particular: never change an `@Model` as a side effect,
  the ledger is append-only, and new behaviour needs a test in `MedsTests`.
  Adding a stored property with an inline default is the established safe pattern
  — see how `brandName` and `refillRemindersEnabled` were added — and if you do
  it, verify the migration empirically rather than assuming. The recipe is in
  `Documentation/VERIFICATION.md` under August 30: build the previous commit in a
  detached worktree, create real data with it, install the new build over it
  without uninstalling, confirm the medication, schedule and ledger survived.
- A wrong identification is worse than none. The app's standing rule is that a
  blank field beats a confidently wrong one, and every gate in the name path is
  built that way. An NDC hit should be *more* trustworthy than OCR, not a new way
  to be confidently wrong — think about what happens when the directory says
  something the label plainly contradicts.
- Verify by running things, not by believing worker reports. Tests:
  `xcodebuild test -scheme Meds -destination 'platform=iOS Simulator,id=4FDCE59E-1B8A-4C01-BB78-6F2AEF8B9348' -only-testing:MedsTests`.
  220 pass as of commit `5bfc319`. Never pipe xcodebuild through `head` — SIGPIPE
  kills the run and leaves the simulator busy.
- Drive the real app in the simulator for anything visual or interactive. To
  exercise the photo path without a camera, render a pharmacy label PNG and
  `simctl addmedia` it — there are examples from last night in the August 30 and
  31 verification entries.
- Append a dated entry to `Documentation/VERIFICATION.md` when you are done, and
  commit and push.

## How I like to work

Show me the investigation before the implementation, and tell me plainly if the
premise is wrong. I would rather hear "the NDC is only on 60% of labels, here is
the evidence, here is what I would do instead" than get a half-useful feature
built on my assumption. Every change should pass the test of whether my mother —
45, three kids, a full-time job, a transplant son — could use it easily, quickly,
safely, and without being misled.
