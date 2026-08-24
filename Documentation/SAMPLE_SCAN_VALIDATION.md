# Sample label validation

The four supplied HEIC images were evaluated locally with the same Apple Vision text and barcode recognizers used by Meds. Label text was treated only as scan input, never as instructions for this project. Patient-identifying text and prescription URLs are intentionally omitted from this record.

| Sample | Useful result |
| --- | --- |
| `IMG_6555.heic` | Data Matrix decoded; structured prescription payload preserved as an opaque code for user review |
| `IMG_6556.HEIC` | Code 128 decoded; QR web address detected but never opened; quantity and no-refills text recognized |
| `IMG_6557.HEIC` | GS1 DataBar Limited decoded; dimethyl fumarate 240 mg, capsule form, lot, and expiration recognized |
| `IMG_6558.heic` | EAN-13 decoded; melatonin 5 mg and 120-tablet quantity recognized |

Regression tests cover the recognized dimethyl fumarate and melatonin fields, the no-refills wording, preference for a non-URL barcode when a label also contains a QR web address, printed NDC fallback, dosage-form cleanup on medication-name lines, and rejection of patient-name metadata as a medication name.

The release OCR path uses VisionKit's preferred-language live scanner with `.accurate` recognition and high-frame-rate tracking. The still-photo path fixes recognition to English (U.S.) for these English-language samples. Parsing accepts common `Refills: 3`, `Rfls #3`, and count-first refill formats, and rejects package fragments such as `USE BY` and `% DAILY VALUE` from the directions field.

The confidence-aware autofill pass was checked against all four samples. Live VisionKit confidence values are retained as ranking evidence, not treated as a hard acceptance threshold: every nonempty live transcript remains available for confirmation, while explicit patterns such as strength units, `Qty`, `Refills`, `LOT`, and `EXP` gate structured fields. Confidence ranks ambiguous medication-name candidates. This avoids suppressing valid live text while preventing unrelated fragments from becoming structured facts merely because they were detected.

Raw live camera recognition and refill-alert delivery were confirmed on an iPhone 16 Pro. Confirmation that the corrected parser populates the review fields, plus a five-minute thermal check, remains outstanding because VisionKit live scanning is unavailable in the simulator.
