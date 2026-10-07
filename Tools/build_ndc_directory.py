#!/usr/bin/env python3
"""Build Meds/Resources/NDCDirectory.txt from the FDA National Drug Code Directory.

The FDA publishes the directory daily, public domain, at
https://www.fda.gov/drugs/drug-approvals-and-databases/national-drug-code-directory
as ndctext.zip (product.txt, package.txt) and ndc_excluded.zip (products that
have left the directory). The excluded file is accepted but, as of September
2026, contributes nothing: the FDA blanks the name, type and strength of every
delisted listing, so only product.txt matters in practice. This tool trims
the product listings to the facts a pharmacy label needs — generic name, brand
name, strength, dosage form, release — keyed by the nine digits (labeler +
product) that a printed or barcoded NDC reduces to, and writes one sorted,
tab-separated row per product. The app binary-searches that file; see
NDCDirectory.swift.

The release column is "er" (extended), "dr" (delayed) or empty. Immediate- and
extended-release products of one drug share a generic name, strength and form
(Prograf and Astagraf XL are both tacrolimus 1 mg capsules), so without it a
code misread by one digit names the other medicine and nothing contradicts it.

Usage:
  Tools/build_ndc_directory.py --products product.txt \
      [--excluded products_excluded.txt] [--excluded-within-years 6] \
      --snapshot 2026-09-25 --output Meds/Resources/NDCDirectory.txt

  Tools/build_ndc_directory.py --self-test
"""

import argparse
import csv
import datetime as dt
import os
import re
import sys
import tempfile
from collections import Counter

INCLUDED_PRODUCT_TYPES = {"HUMAN PRESCRIPTION DRUG", "HUMAN OTC DRUG"}

# Tokens that make a proprietary name nothing more than the generic restated.
NOISE_TOKENS = {
    "tablet", "tablets", "capsule", "capsules", "caplet", "caplets", "softgel", "softgels",
    "oral", "solution", "suspension", "syrup", "injection", "injectable", "usp", "nf",
    "for", "and", "with", "of", "the", "extended", "delayed", "immediate", "release",
    "controlled", "er", "xl", "xr", "sr", "dr", "cr", "la", "odt", "ec", "ir",
    "hcl", "hydrochloride", "hbr", "hydrobromide", "sodium", "potassium", "calcium",
    "magnesium", "chewable", "film", "coated", "ophthalmic", "otic", "nasal", "topical",
    "cream", "ointment", "gel", "lotion", "drops", "spray", "kit", "pack", "patch",
    "transdermal", "system", "powder", "granules", "concentrate", "elixir", "lozenge",
    "suppository", "enema", "inhalation", "aerosol", "metered", "dose", "unit", "vial",
    "prefilled", "syringe", "pen", "cartridge", "strength", "regular", "maximum", "extra",
    "childrens", "children", "adult", "adults", "infant", "infants", "junior",
    "cii", "ciii", "civ", "cv", "cll", "rx", "only", "mg", "mcg", "ml",
}

FORM_RULES = [
    ("capsule", ["CAPSULE"]),
    ("tablet", ["TABLET", "LOZENGE", "TROCHE", "WAFER", "PELLET", "PASTILLE", "GUM"]),
    ("patch", ["PATCH", "SYSTEM"]),
    ("injection", ["INJECT", "IMPLANT"]),
    ("inhaler", ["AEROSOL", "INHALANT", "POWDER, METERED", "INHALATION"]),
    ("drops", ["DROPS"]),
    ("topical", ["CREAM", "OINTMENT", "GEL", "LOTION", "FOAM", "PASTE", "SHAMPOO", "SOAP",
                 "LINIMENT", "SALVE", "STICK", "SWAB", "CLOTH", "SPONGE", "OIL", "WAX"]),
    ("liquid", ["SOLUTION", "SUSPENSION", "SYRUP", "ELIXIR", "LIQUID", "EMULSION",
                "CONCENTRATE", "TINCTURE", "RINSE", "MOUTHWASH", "IRRIGANT", "ENEMA", "SPRAY"]),
]

NUMERATOR_UNITS = {
    "mg": "mg", "ug": "mcg", "mcg": "mcg", "g": "g", "kg": "kg", "ml": "mL", "l": "L",
    "[iu]": "IU", "[usp'u]": "units", "meq": "mEq", "mmol": "mmol", "%": "%",
    "[au]": "AU", "[bau]": "BAU", "[pfu]": "PFU",
}

DENOMINATOR_UNITS = {"1": "", "ml": "mL", "l": "L", "g": "g", "mg": "mg", "h": "h", "d": "d",
                     "kg": "kg", "cm2": "cm²", "[usp'u]": "units", "[iu]": "IU"}

# Release letters as a brand carries them: "Oxtellar XR", "Ambien CR", "Aspirin EC".
# The app reads the same letters off a label (ReleaseForm.swift).
RELEASE_LETTERS = {"er": "er", "xl": "er", "xr": "er", "sr": "er", "cr": "er", "la": "er", "cd": "er",
                   "xt": "er", "dr": "dr", "ec": "dr"}
EXTENDED_PHRASE = re.compile(r"(?i)\b(?:extended|sustained|controlled)[\s-]*release")
DELAYED_PHRASE = re.compile(r"(?i)\b(?:delayed[\s-]*release|enteric[\s-]*coated)")


def read_rows(path):
    """Rows of a tab-separated FDA file as dicts with upper-cased keys."""
    for encoding in ("utf-8-sig", "cp1252"):
        try:
            with open(path, encoding=encoding, newline="") as handle:
                reader = csv.reader(handle, delimiter="\t", quoting=csv.QUOTE_NONE)
                header = [column.strip().upper() for column in next(reader)]
                rows = []
                for values in reader:
                    if not values:
                        continue
                    rows.append({column: (values[index].strip() if index < len(values) else "")
                                 for index, column in enumerate(header)})
                return rows
        except UnicodeDecodeError:
            continue
    raise SystemExit(f"could not decode {path} as UTF-8 or Windows-1252")


def product_key(product_ndc):
    """'0093-1039' -> '000931039'. None when the code is not a labeler-product pair."""
    parts = product_ndc.strip().split("-")
    if len(parts) != 2:
        return None
    labeler, product = parts
    if not (labeler.isdigit() and product.isdigit()):
        return None
    if not (4 <= len(labeler) <= 5 and 3 <= len(product) <= 4):
        return None
    return labeler.zfill(5) + product.zfill(4)


def collapse(text):
    return re.sub(r"\s+", " ", text.replace("\t", " ").replace("\n", " ")).strip()


def letters(text):
    return re.sub(r"[^a-z0-9]", "", text.lower())


def tokens(text):
    return [token for token in re.split(r"[^a-z0-9]+", text.lower()) if token]


def smart_title(text):
    """'TOPROL XL' -> 'Toprol XL', 'Zoloft' unchanged. Only all-caps names are re-cased."""
    if text != text.upper():
        return text
    words = []
    for word in text.split(" "):
        if len(word) <= 2 and word.isalpha():
            words.append(word)
        else:
            words.append(word[:1].upper() + word[1:].lower())
    return " ".join(words)


GENERIC_TRAILER = re.compile(
    r"(?i)[\s,;(-]*\b(?:tablets?|capsules?|caplets?|softgels?|injection|injectable|solution|suspension|"
    r"syrup|elixir|cream|ointment|gel|lotion|drops|spray|inhaler|inhalant|aerosol|powder|granules?|"
    r"kit|patch(?:es)?|suppositor(?:y|ies)|film|lozenges?|for oral use|oral|chewable|extended[- ]release|"
    r"delayed[- ]release|usp|nf|rx only|c-?(?:ii|iii|iv|v|ll)|\d+(?:\.\d+)?\s*(?:mg|mcg|g|ml|%|units?|iu))\b.*$"
)


def generic_name(row):
    name = collapse(row.get("NONPROPRIETARYNAME", ""))
    if not name:
        name = collapse(row.get("SUBSTANCENAME", "")).replace("; ", ", ")
    # Cut a labeler's trailing form, strength or schedule off the name, but never
    # the whole name: "Tablets" alone would otherwise become nothing.
    trimmed = GENERIC_TRAILER.sub("", name).strip(" ,.;(-")
    if trimmed and any(character.isalpha() for character in trimmed):
        name = trimmed
    return name.lower().strip(" ,.;")


def brand_name(row, generic):
    name = collapse(row.get("PROPRIETARYNAME", ""))
    suffix = collapse(row.get("PROPRIETARYNAMESUFFIX", ""))
    if suffix and letters(suffix) not in letters(name):
        name = f"{name} {suffix}"
    name = smart_title(name).strip(" ,.;")
    if not name:
        return ""
    brand_key, generic_key = letters(name), letters(generic)
    if brand_key == generic_key:
        return ""
    generic_tokens = set(tokens(generic))
    informative = [token for token in tokens(name) if token not in NOISE_TOKENS]
    if informative and all(token in generic_tokens for token in informative):
        return ""
    if not informative:
        return ""
    return name


def format_number(text):
    try:
        value = float(text)
    except ValueError:
        return None
    if value <= 0:
        return None
    if value == int(value) and value < 1e9:
        return str(int(value))
    formatted = f"{value:.4f}".rstrip("0").rstrip(".")
    return formatted if formatted else None


def parse_unit(unit):
    """'mg/1' -> ('mg', ''), 'mg/5mL' -> ('mg', '5 mL'), '[iU]/mL' -> ('IU', 'mL')."""
    if "/" not in unit:
        numerator, denominator = unit, "1"
    else:
        numerator, denominator = unit.split("/", 1)
    numerator = NUMERATOR_UNITS.get(numerator.strip().lower())
    if numerator is None:
        return None
    denominator = denominator.strip()
    if denominator in ("", "1"):
        return (numerator, "")
    match = re.fullmatch(r"(\d*\.?\d+)?\s*([A-Za-z\[\]'%][A-Za-z\[\]'0-9%]*)", denominator)
    if not match:
        return None
    amount, denominator_unit = match.group(1), match.group(2)
    if denominator_unit not in DENOMINATOR_UNITS and denominator_unit.lower() not in DENOMINATOR_UNITS:
        return None
    mapped = DENOMINATOR_UNITS.get(denominator_unit, DENOMINATOR_UNITS.get(denominator_unit.lower(), ""))
    if not mapped:
        return (numerator, "")
    if amount and format_number(amount) not in (None, "1"):
        return (numerator, f"{format_number(amount)} {mapped}")
    return (numerator, mapped)


def strength(row):
    numerators = [part.strip() for part in row.get("ACTIVE_NUMERATOR_STRENGTH", "").split(";")]
    units = [part.strip() for part in row.get("ACTIVE_INGRED_UNIT", "").split(";")]
    if not numerators or numerators == [""] or len(numerators) != len(units):
        return ""
    components = []
    for numerator, unit in zip(numerators, units):
        value = format_number(numerator)
        parsed = parse_unit(unit)
        if value is None or parsed is None:
            return ""
        components.append((value, parsed[0], parsed[1]))
    if len(components) > 4:
        return ""
    unit_set = {unit for _, unit, _ in components}
    denominator_set = {denominator for _, _, denominator in components}
    if len(unit_set) == 1 and len(denominator_set) == 1:
        unit, denominator = components[0][1], components[0][2]
        joined = "-".join(value for value, _, _ in components)
        return f"{joined} {unit}" + (f"/{denominator}" if denominator else "")
    if len(components) == 1:
        value, unit, denominator = components[0]
        return f"{value} {unit}" + (f"/{denominator}" if denominator else "")
    if len(components) <= 3 and denominator_set == {""}:
        return "/".join(f"{value} {unit}" for value, unit, _ in components)
    return ""


def form(row):
    dosage_form = row.get("DOSAGEFORMNAME", "").upper()
    for app_form, markers in FORM_RULES:
        if any(marker in dosage_form for marker in markers):
            return app_form
    return "other"


def release(row, app_form):
    """'er', 'dr', or '' when nothing in the listing claims a modified release.

    The dosage form is the FDA's own word and settles it. Where it is silent
    the names can still say so: some labelers file an extended-release tablet
    as TABLET and put "Extended-Release" in the name, a brand carries its
    release letters, "Oxtellar XR", and a repackager can put them in the
    generic name, "Metformin ER 500 mg". The letters only count after a name's
    first word and only on an oral tablet or capsule, because "Dr. Sheffield"
    and "La Roche-Posay" lead with the same letters on creams and sunscreens.
    """
    dosage_form = row.get("DOSAGEFORMNAME", "").upper()
    if "EXTENDED RELEASE" in dosage_form:
        return "er"
    if "DELAYED RELEASE" in dosage_form:
        return "dr"
    names = " ".join(collapse(row.get(column, "")) for column in
                     ("PROPRIETARYNAME", "PROPRIETARYNAMESUFFIX", "NONPROPRIETARYNAME"))
    extended, delayed = bool(EXTENDED_PHRASE.search(names)), bool(DELAYED_PHRASE.search(names))
    if extended != delayed:
        return "er" if extended else "dr"
    if extended or "ORAL" not in row.get("ROUTENAME", "").upper() or app_form not in ("tablet", "capsule"):
        return ""
    brand = f'{collapse(row.get("PROPRIETARYNAME", ""))} {collapse(row.get("PROPRIETARYNAMESUFFIX", ""))}'
    generic = collapse(row.get("NONPROPRIETARYNAME", ""))
    found = {RELEASE_LETTERS[token] for name in (brand, generic) for token in tokens(name)[1:] if token in RELEASE_LETTERS}
    return found.pop() if len(found) == 1 else ""


def marketing_date(text):
    text = text.strip()
    if len(text) != 8 or not text.isdigit():
        return None
    try:
        return dt.date(int(text[:4]), int(text[4:6]), int(text[6:8]))
    except ValueError:
        return None


def build_entries(rows, stats, label):
    entries = {}
    for row in rows:
        product_type = row.get("PRODUCTTYPENAME", "").upper()
        stats[f"{label} rows"] += 1
        if product_type not in INCLUDED_PRODUCT_TYPES:
            stats[f"{label} skipped type {product_type or 'blank'}"] += 1
            continue
        key = product_key(row.get("PRODUCTNDC", ""))
        if key is None:
            stats[f"{label} skipped bad code"] += 1
            continue
        generic = generic_name(row)
        if not generic:
            stats[f"{label} skipped no name"] += 1
            continue
        app_form = form(row)
        entry = {
            "key": key,
            "generic": generic,
            "brand": brand_name(row, generic),
            "strength": strength(row),
            "form": app_form,
            "release": release(row, app_form),
            "start": marketing_date(row.get("STARTMARKETINGDATE", "")) or dt.date.min,
            "end": marketing_date(row.get("ENDMARKETINGDATE", "")),
        }
        if not entry["strength"]:
            stats[f"{label} without usable strength"] += 1
        previous = entries.get(key)
        if previous is None or (entry["start"], bool(entry["brand"])) > (previous["start"], bool(previous["brand"])):
            entries[key] = entry
    return entries


def write_directory(entries, output, snapshot, description):
    with open(output, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(f"# FDA NDC Directory snapshot {snapshot}: {description}\n")
        for key in sorted(entries):
            entry = entries[key]
            fields = [key, entry["generic"], entry["brand"], entry["strength"], entry["form"], entry["release"]]
            handle.write("\t".join(field.replace("\t", " ").replace("\n", " ") for field in fields) + "\n")


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--products", help="product.txt from ndctext.zip")
    parser.add_argument("--excluded", help="the products file from ndc_excluded.zip")
    parser.add_argument("--excluded-within-years", type=int, default=6,
                        help="keep excluded products whose marketing ended within this many years of the snapshot")
    parser.add_argument("--snapshot", help="date the FDA files were downloaded, YYYY-MM-DD")
    parser.add_argument("--output", default="Meds/Resources/NDCDirectory.txt")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        return self_test()
    if not args.products or not args.snapshot:
        parser.error("--products and --snapshot are required")

    snapshot = dt.date.fromisoformat(args.snapshot)
    stats = Counter()
    entries = build_entries(read_rows(args.products), stats, "product")
    main_count = len(entries)

    excluded_count = 0
    if args.excluded:
        horizon = snapshot.replace(year=snapshot.year - args.excluded_within_years)
        for key, entry in build_entries(read_rows(args.excluded), stats, "excluded").items():
            if key in entries:
                stats["excluded already present"] += 1
                continue
            if entry["end"] is not None and entry["end"] < horizon:
                stats["excluded too old"] += 1
                continue
            entries[key] = entry
            excluded_count += 1

    description = (f"{len(entries)} human prescription and OTC products "
                   f"({main_count} listed, {excluded_count} delisted within {args.excluded_within_years} years). "
                   "Public domain: https://www.fda.gov/drugs/drug-approvals-and-databases/national-drug-code-directory")
    write_directory(entries, args.output, args.snapshot, description)

    print(f"wrote {args.output}: {len(entries)} products")
    for key in sorted(stats):
        print(f"  {stats[key]:>8}  {key}")
    forms = Counter(entry["form"] for entry in entries.values())
    print("  forms:", ", ".join(f"{name} {count}" for name, count in forms.most_common()))
    branded = sum(1 for entry in entries.values() if entry["brand"])
    print(f"  with a brand: {branded}; with a strength: {sum(1 for e in entries.values() if e['strength'])}")
    releases = Counter(entry["release"] or "immediate" for entry in entries.values())
    print("  release:", ", ".join(f"{name} {count}" for name, count in releases.most_common()))
    return 0


def self_test():
    assert product_key("0093-1039") == "000931039"
    assert product_key("64406-006") == "644060006"
    assert product_key("64406-0006") == "644060006"
    assert product_key("123-45") is None
    assert product_key("0093-1039-01") is None

    assert strength({"ACTIVE_NUMERATOR_STRENGTH": "50", "ACTIVE_INGRED_UNIT": "mg/1"}) == "50 mg"
    assert strength({"ACTIVE_NUMERATOR_STRENGTH": "800; 160", "ACTIVE_INGRED_UNIT": "mg/1; mg/1"}) == "800-160 mg"
    assert strength({"ACTIVE_NUMERATOR_STRENGTH": "15", "ACTIVE_INGRED_UNIT": "mg/5mL"}) == "15 mg/5 mL"
    assert strength({"ACTIVE_NUMERATOR_STRENGTH": "5", "ACTIVE_INGRED_UNIT": "mg/mL"}) == "5 mg/mL"
    assert strength({"ACTIVE_NUMERATOR_STRENGTH": "100", "ACTIVE_INGRED_UNIT": "[iU]/mL"}) == "100 IU/mL"
    assert strength({"ACTIVE_NUMERATOR_STRENGTH": "500", "ACTIVE_INGRED_UNIT": "ug/1"}) == "500 mcg"
    assert strength({"ACTIVE_NUMERATOR_STRENGTH": ".5", "ACTIVE_INGRED_UNIT": "mg/1"}) == "0.5 mg"
    assert strength({"ACTIVE_NUMERATOR_STRENGTH": "5; 5; 5; 5", "ACTIVE_INGRED_UNIT": "mg/1; mg/1; mg/1; mg/1"}) == "5-5-5-5 mg"
    assert strength({"ACTIVE_NUMERATOR_STRENGTH": "0.5; 50", "ACTIVE_INGRED_UNIT": "mg/1; ug/1"}) == "0.5 mg/50 mcg"
    assert strength({"ACTIVE_NUMERATOR_STRENGTH": "1", "ACTIVE_INGRED_UNIT": "g/100mL"}) == "1 g/100 mL"
    assert strength({"ACTIVE_NUMERATOR_STRENGTH": "2.5", "ACTIVE_INGRED_UNIT": "mg/.5mL"}) == "2.5 mg/0.5 mL"
    assert strength({"ACTIVE_NUMERATOR_STRENGTH": "100", "ACTIVE_INGRED_UNIT": "[iU]/1"}) == "100 IU"
    assert strength({"ACTIVE_NUMERATOR_STRENGTH": "30", "ACTIVE_INGRED_UNIT": "[hp_X]/1"}) == ""
    assert strength({"ACTIVE_NUMERATOR_STRENGTH": "", "ACTIVE_INGRED_UNIT": ""}) == ""
    assert strength({"ACTIVE_NUMERATOR_STRENGTH": "10", "ACTIVE_INGRED_UNIT": "mg/1; mg/1"}) == ""

    assert brand_name({"PROPRIETARYNAME": "Zoloft"}, "sertraline hydrochloride") == "Zoloft"
    assert brand_name({"PROPRIETARYNAME": "SERTRALINE HYDROCHLORIDE"}, "sertraline hydrochloride") == ""
    assert brand_name({"PROPRIETARYNAME": "Sertraline"}, "sertraline hydrochloride") == ""
    assert brand_name({"PROPRIETARYNAME": "Ibuprofen Tablets, USP"}, "ibuprofen") == ""
    assert brand_name({"PROPRIETARYNAME": "CVS Health Ibuprofen"}, "ibuprofen") == "CVS Health Ibuprofen"
    assert brand_name({"PROPRIETARYNAME": "TOPROL", "PROPRIETARYNAMESUFFIX": "XL"}, "metoprolol succinate") == "Toprol XL"
    assert brand_name({"PROPRIETARYNAME": "TECFIDERA"}, "dimethyl fumarate") == "Tecfidera"
    assert brand_name({"PROPRIETARYNAME": "Metoprolol Succinate Extended-Release"}, "metoprolol succinate") == ""
    assert brand_name({"PROPRIETARYNAME": "Dextroamphetamine Saccharate, Amphetamine Aspartate, Dextroamphetamine Sulfate, Amphetamine Sulfate Tablets,CII"},
                      "dextroamphetamine saccharate, amphetamine aspartate, dextroamphetamine sulfate, amphetamine sulfate") == ""
    assert generic_name({"NONPROPRIETARYNAME": "Dextroamphetamine Saccharate, Amphetamine Aspartate, Dextroamphetamine Sulfate, Amphetamine Sulfate Tablets, 5 mg,Cll"}) == "dextroamphetamine saccharate, amphetamine aspartate, dextroamphetamine sulfate, amphetamine sulfate"
    assert generic_name({"NONPROPRIETARYNAME": "Sertraline Hydrochloride"}) == "sertraline hydrochloride"
    assert generic_name({"NONPROPRIETARYNAME": "Tablets"}) == "tablets"
    assert generic_name({"NONPROPRIETARYNAME": "sulfamethoxazole and Trimethoprim"}) == "sulfamethoxazole and trimethoprim"

    assert form({"DOSAGEFORMNAME": "TABLET, FILM COATED"}) == "tablet"
    assert form({"DOSAGEFORMNAME": "CAPSULE, DELAYED RELEASE"}) == "capsule"
    assert form({"DOSAGEFORMNAME": "INJECTION, SOLUTION"}) == "injection"
    assert form({"DOSAGEFORMNAME": "SOLUTION/ DROPS"}) == "drops"
    assert form({"DOSAGEFORMNAME": "SOLUTION"}) == "liquid"
    assert form({"DOSAGEFORMNAME": "AEROSOL, METERED"}) == "inhaler"
    assert form({"DOSAGEFORMNAME": "PATCH, EXTENDED RELEASE"}) == "patch"
    assert form({"DOSAGEFORMNAME": "CREAM"}) == "topical"
    assert form({"DOSAGEFORMNAME": "KIT"}) == "other"
    assert form({"DOSAGEFORMNAME": "SPRAY, METERED"}) == "liquid"

    def released(**row):
        return release(row, form(row))
    assert released(DOSAGEFORMNAME="CAPSULE, COATED, EXTENDED RELEASE", PROPRIETARYNAME="ASTAGRAF XL") == "er"
    assert released(DOSAGEFORMNAME="CAPSULE, GELATIN COATED", PROPRIETARYNAME="Prograf", ROUTENAME="ORAL") == ""
    assert released(DOSAGEFORMNAME="TABLET, EXTENDED RELEASE", PROPRIETARYNAME="Envarsus", PROPRIETARYNAMESUFFIX="XR") == "er"
    assert released(DOSAGEFORMNAME="CAPSULE, DELAYED RELEASE", PROPRIETARYNAME="TECFIDERA") == "dr"
    assert released(DOSAGEFORMNAME="TABLET, ORALLY DISINTEGRATING, DELAYED RELEASE", PROPRIETARYNAME="Prevacid") == "dr"
    assert released(DOSAGEFORMNAME="PATCH, EXTENDED RELEASE", PROPRIETARYNAME="Exelon") == "er"
    # The dosage form is silent; the names are not.
    assert released(DOSAGEFORMNAME="TABLET", ROUTENAME="ORAL", PROPRIETARYNAME="Potassium Chloride",
                    NONPROPRIETARYNAME="potassium chloride extended-release") == "er"
    assert released(DOSAGEFORMNAME="TABLET, COATED", ROUTENAME="ORAL", PROPRIETARYNAME="Aspirin 81mg Enteric coated") == "dr"
    assert released(DOSAGEFORMNAME="TABLET", ROUTENAME="ORAL", PROPRIETARYNAME="OXTELLAR", PROPRIETARYNAMESUFFIX="XR") == "er"
    assert released(DOSAGEFORMNAME="TABLET, COATED", ROUTENAME="ORAL", PROPRIETARYNAME="Ambien CR") == "er"
    assert released(DOSAGEFORMNAME="TABLET", ROUTENAME="ORAL", PROPRIETARYNAME="ASPIRIN 325 MG EC") == "dr"
    assert released(DOSAGEFORMNAME="TABLET", ROUTENAME="ORAL", PROPRIETARYNAME="Immediate Release Mucus Relief") == ""
    # A repackager's listing of 50090-6515: the release is only in the generic name.
    assert released(DOSAGEFORMNAME="TABLET", ROUTENAME="ORAL", PROPRIETARYNAME="Metformin",
                    NONPROPRIETARYNAME="Metformin ER 500 mg") == "er"
    assert released(DOSAGEFORMNAME="TABLET", ROUTENAME="ORAL", PROPRIETARYNAME="Metformin",
                    NONPROPRIETARYNAME="Metformin Hydrochloride") == ""
    assert released(DOSAGEFORMNAME="TABLET", ROUTENAME="ORAL", PROPRIETARYNAME="Pain Relief",
                    NONPROPRIETARYNAME="Aspirin EC 81 mg") == "dr"
    assert released(DOSAGEFORMNAME="TABLET", ROUTENAME="ORAL", PROPRIETARYNAME="Dr Simi Pain Relief",
                    NONPROPRIETARYNAME="Acetaminophen") == ""
    # Letters that lead a name, or sit on something that is not an oral tablet or capsule, are not a release.
    assert released(DOSAGEFORMNAME="TABLET, COATED", ROUTENAME="ORAL", PROPRIETARYNAME="Dr Simi Pain Relief") == ""
    assert released(DOSAGEFORMNAME="CREAM", ROUTENAME="TOPICAL", PROPRIETARYNAME="Dr. Sheffield Anti Itch Cream") == ""
    assert released(DOSAGEFORMNAME="LOTION", ROUTENAME="TOPICAL", PROPRIETARYNAME="La Roche Posay Anthelios XL") == ""
    assert released(DOSAGEFORMNAME="INJECTION, SUSPENSION", ROUTENAME="INTRAMUSCULAR", PROPRIETARYNAME="BICILLIN CR") == ""
    assert released(DOSAGEFORMNAME="TABLET", ROUTENAME="ORAL", PROPRIETARYNAME="Metoprolol Tartrate") == ""

    rows = [
        {"PRODUCTNDC": "0093-1039", "PRODUCTTYPENAME": "HUMAN PRESCRIPTION DRUG", "PROPRIETARYNAME": "Sertraline",
         "NONPROPRIETARYNAME": "Sertraline Hydrochloride", "DOSAGEFORMNAME": "TABLET, FILM COATED",
         "ACTIVE_NUMERATOR_STRENGTH": "50", "ACTIVE_INGRED_UNIT": "mg/1", "STARTMARKETINGDATE": "20100101"},
        {"PRODUCTNDC": "0093-1039", "PRODUCTTYPENAME": "HUMAN PRESCRIPTION DRUG", "PROPRIETARYNAME": "Sertraline",
         "NONPROPRIETARYNAME": "Sertraline Hydrochloride", "DOSAGEFORMNAME": "TABLET",
         "ACTIVE_NUMERATOR_STRENGTH": "50", "ACTIVE_INGRED_UNIT": "mg/1", "STARTMARKETINGDATE": "20090101"},
        {"PRODUCTNDC": "1234-567", "PRODUCTTYPENAME": "BULK INGREDIENT", "NONPROPRIETARYNAME": "x"},
    ]
    stats = Counter()
    entries = build_entries(rows, stats, "product")
    assert list(entries) == ["000931039"], entries
    assert entries["000931039"]["start"] == dt.date(2010, 1, 1)
    assert entries["000931039"]["release"] == ""
    assert stats["product skipped type BULK INGREDIENT"] == 1
    print("self-test passed")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
