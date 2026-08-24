# Sample label validation

The four supplied HEIC images were evaluated locally with the same Apple Vision text and barcode recognizers used by Meds. Label text was treated only as scan input, never as instructions for this project. Patient-identifying text and prescription URLs are intentionally omitted from this record.

| Sample | Useful result |
| --- | --- |
| `IMG_6555.heic` | Data Matrix decoded; structured prescription payload preserved as an opaque code for user review |
| `IMG_6556.HEIC` | Code 128 decoded; QR web address detected but never opened; quantity and no-refills text recognized |
| `IMG_6557.HEIC` | GS1 DataBar Limited decoded; dimethyl fumarate 240 mg, capsule form, lot, and expiration recognized |
| `IMG_6558.heic` | EAN-13 decoded; melatonin 5 mg and 120-tablet quantity recognized |

Regression tests cover the recognized dimethyl fumarate and melatonin fields, the no-refills wording, preference for a non-URL barcode when a label also contains a QR web address, printed NDC fallback, dosage-form cleanup on medication-name lines, and rejection of patient-name metadata as a medication name.

The release OCR path uses one uninterrupted VisionKit live-scanner session in English, Spanish, and French at `.accurate` quality, with an ROI matching the visible frame. Stable observations are retained additively while the user rotates the bottle; the live session never takes an automatic still, so it does not have to recover or remount between sides. Tapping Review takes one high-resolution image for accurate English (U.S.) recognition as the scanner closes, merges that result with the retained live evidence, and opens confirmation. If the final image is unavailable, retained live evidence can still continue to confirmation. App-level script validation rejects any line containing non-Latin letters while preserving English, Spanish, and French Latin characters.

The confidence-aware autofill pass was checked against all four original samples and the two later bottle photos. A medication name can enter an autofilled field only when it resolves uniquely against the bundled 12,865-name RxNorm-derived vocabulary. This includes conservative repair of a complete ingredient followed by a curved-edge fragment such as `amphetamine-dextroan`; ambiguous matches stay blank. The on-device language model may rank evidence, but cannot bypass the vocabulary or insert an unsupported raw fragment. Strength, quantity, refill, lot, expiration, and direction fields remain bounded to exact candidates derived from recognized text.

Raw live camera recognition, uninterrupted multi-side evidence collection, final Review capture, and refill-alert delivery were confirmed on an iPhone 16 Pro. The production recognizer/interpreter replay returns Melatonin, 5 mg, and 120 tablets from the OTC photo and the complete amphetamine - dextroamphetamine generic name from the curved prescription photo without inventing directions. A five-minute thermal check remains a hands-on gate because VisionKit live scanning is unavailable in the simulator.
