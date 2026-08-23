# Sample label validation

The four supplied HEIC images were evaluated locally with the same Apple Vision text and barcode recognizers used by Meds. Label text was treated only as scan input, never as instructions for this project. Patient-identifying text and prescription URLs are intentionally omitted from this record.

| Sample | Useful result |
| --- | --- |
| `IMG_6555.heic` | Data Matrix decoded; structured prescription payload preserved as an opaque code for user review |
| `IMG_6556.HEIC` | Code 128 decoded; QR web address detected but never opened; quantity and no-refills text recognized |
| `IMG_6557.HEIC` | GS1 DataBar Limited decoded; dimethyl fumarate 240 mg, capsule form, lot, and expiration recognized |
| `IMG_6558.heic` | EAN-13 decoded; melatonin 5 mg and 120-tablet quantity recognized |

Regression tests cover the recognized dimethyl fumarate and melatonin fields, the no-refills wording, and preference for a non-URL barcode when a label also contains a QR web address.

The confidence-aware autofill pass was checked against all four samples. Of 39 text observations, 37 were above the strong-confidence threshold; the remaining two remained eligible when they contained explicit medication-field context. This preserves useful label content while preventing unstable low-confidence fragments from silently becoming a medication name.

Useful live camera recognition and refill-alert delivery were subsequently confirmed on an iPhone 16 Pro. A five-minute thermal check remains outstanding because VisionKit live scanning is unavailable in the simulator.
