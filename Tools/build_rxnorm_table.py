#!/usr/bin/env python3
"""Build the bundled RxNorm tables from NLM's "current prescribable content" release.

Source: https://download.nlm.nih.gov/rxnorm/RxNorm_full_prescribe_current.zip —
the subset of RxNorm limited to prescribable drugs, which NLM distributes without
a UMLS licence. Unzip it and point this tool at the rrf/ directory.

Two tab-separated files come out, each sorted by a fixed-width numeric key so
the app can binary-search the file's own bytes the way it does the FDA snapshot:

  RxNormProducts.txt  labeler-product key (9 digits) → RXCUI → clinical-drug RXCUI
      One row per FDA product in the app's own NDC Directory snapshot that RxNorm
      lists an NDC for. The RXCUI is the concept RxNorm attaches to the package
      (a clinical drug for a generic, a branded drug for a brand); the third
      column is the clinical drug a branded RXCUI is a tradename of, or empty.
  RxNormNames.txt     RXCUI (8 digits, zero-padded) → prescribable name
      The PSN for every concept the products file mentions, or the concept's own
      name when NLM has not assigned a PSN.

RxNorm is courtesy of the U.S. National Library of Medicine, National Institutes
of Health, Department of Health and Human Services; NLM is not responsible for
the product and does not endorse or recommend this or any other product.
"""

from __future__ import annotations

import argparse
import collections
import sys
from pathlib import Path

NATIVE_LAYOUTS = {(4, 4, 2), (5, 3, 2), (5, 4, 1), (5, 4, 2)}
CONCEPT_TYPES = {"SCD", "SBD", "GPCK", "BPCK"}


def ndc11(value: str) -> str | None:
    value = value.strip()
    if "-" in value:
        segments = value.split("-")
        if len(segments) != 3 or tuple(len(s) for s in segments) not in NATIVE_LAYOUTS:
            return None
        if not all(s.isdigit() for s in segments):
            return None
        return segments[0].zfill(5) + segments[1].zfill(4) + segments[2].zfill(2)
    if len(value) == 11 and value.isdigit():
        return value
    return None


def load_fda_keys(directory: Path) -> set[str]:
    keys = set()
    with directory.open(encoding="utf-8") as handle:
        for line in handle:
            if line.startswith("#"):
                continue
            keys.add(line.split("\t", 1)[0])
    return keys


def load_concepts(conso: Path) -> tuple[dict[str, str], dict[str, str]]:
    """RXCUI → name for prescribable concepts, and RXCUI → PSN where one exists."""
    names: dict[str, str] = {}
    psn: dict[str, str] = {}
    with conso.open(encoding="utf-8") as handle:
        for line in handle:
            parts = line.split("|")
            if parts[11] != "RXNORM":
                continue
            rxcui, tty, name = parts[0], parts[12], parts[14]
            if tty in CONCEPT_TYPES and rxcui not in names:
                names[rxcui] = name
            elif tty == "PSN" and rxcui not in psn:
                psn[rxcui] = name
    return names, psn


def load_tradenames(rel: Path, concepts: dict[str, str]) -> dict[str, str]:
    """Branded RXCUI → the clinical drug it is a tradename of."""
    generic_of: dict[str, str] = {}
    with rel.open(encoding="utf-8") as handle:
        for line in handle:
            parts = line.split("|")
            if parts[7] != "tradename_of" or parts[10] != "RXNORM":
                continue
            # RELA describes column 5's relationship to column 1: column 5 is
            # a tradename of column 1.
            generic, brand = parts[0], parts[4]
            if brand in concepts and generic in concepts:
                generic_of.setdefault(brand, generic)
    return generic_of


def load_products(sat: Path, concepts: dict[str, str], fda_keys: set[str]) -> dict[str, str]:
    """Labeler-product key → the RXCUI RxNorm attaches to its packages."""
    votes: dict[str, collections.Counter] = collections.defaultdict(collections.Counter)
    with sat.open(encoding="utf-8") as handle:
        for line in handle:
            parts = line.split("|")
            if parts[8] != "NDC":
                continue
            code = ndc11(parts[10])
            if code is None:
                continue
            key = code[:9]
            if key not in fda_keys or parts[0] not in concepts:
                continue
            # NLM's own NDC attributes outrank the labeler-submitted SPL ones
            # when the two disagree about a package.
            weight = 3 if parts[9] == "RXNORM" else 1
            votes[key][parts[0]] += weight
    return {key: counter.most_common(1)[0][0] for key, counter in votes.items()}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--rrf", required=True, type=Path, help="the rrf/ directory of the unzipped release")
    parser.add_argument("--ndc-directory", required=True, type=Path, help="the app's NDCDirectory.txt")
    parser.add_argument("--release", required=True, help="the release date, YYYY-MM-DD, from the Readme")
    parser.add_argument("--out", required=True, type=Path, help="Meds/Resources")
    args = parser.parse_args()

    fda_keys = load_fda_keys(args.ndc_directory)
    concepts, psn = load_concepts(args.rrf / "RXNCONSO.RRF")
    generic_of = load_tradenames(args.rrf / "RXNREL.RRF", concepts)
    products = load_products(args.rrf / "RXNSAT.RRF", concepts, fda_keys)

    attribution = ("Courtesy of the U.S. National Library of Medicine (NLM), National Institutes of Health, "
                   "Department of Health and Human Services; NLM is not responsible for the product and does "
                   "not endorse or recommend this or any other product.")
    mentioned: set[str] = set()
    with (args.out / "RxNormProducts.txt").open("w", encoding="utf-8") as handle:
        handle.write(f"# RxNorm current prescribable content {args.release}: {len(products)} FDA products "
                     f"keyed by labeler-product digits, their RXCUI, and the clinical drug a brand is a tradename of. "
                     f"{attribution}\n")
        for key in sorted(products):
            rxcui = products[key]
            generic = generic_of.get(rxcui, "")
            mentioned.add(rxcui)
            if generic:
                mentioned.add(generic)
            handle.write(f"{key}\t{rxcui}\t{generic}\n")

    with (args.out / "RxNormNames.txt").open("w", encoding="utf-8") as handle:
        handle.write(f"# RxNorm current prescribable content {args.release}: prescribable names for {len(mentioned)} "
                     f"concepts. {attribution}\n")
        for rxcui in sorted(mentioned, key=int):
            name = psn.get(rxcui) or concepts[rxcui]
            handle.write(f"{rxcui.zfill(8)}\t{name}\n")

    branded = sum(1 for rxcui in products.values() if rxcui in generic_of)
    print(f"{len(products)} of {len(fda_keys)} FDA products mapped; {branded} to a branded concept with a clinical drug; "
          f"{len(mentioned)} names written", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
