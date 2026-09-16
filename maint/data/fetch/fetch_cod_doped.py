#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Widen build/cod toward a corpus that actually contains doping.
#
#   Usage:  python maint/data/fetch/fetch_cod_doped.py [target_total]
#
# WHY A SECOND NAME LIST
#
# The list in examples/crystallography/6_oracle/proof_positive_control.py was chosen for cells
# likely to be published with right angles, because that oracle could not read anything else. It is
# a list of simple, mostly stoichiometric compounds, and a stoichiometric compound is by definition
# the case with no doping in it. Measured on the 650 entries that list produced, 54 carry a mixed
# site and 176 carry a site under full occupancy, so the sample is thin in the one property a
# doping detector exists to find.
#
# The names below are solid solution formers: minerals whose published entries routinely put two
# elements on one crystallographic position. Olivine runs magnesium to iron, plagioclase runs sodium
# to calcium, the garnets and spinels and pyroxenes substitute across whole sites. These are where a
# deposited mixed site is normal rather than exceptional.
#
# The right angle restriction is deliberately not applied here. Most of these are monoclinic or
# triclinic, and the exact reading path does not need a right angle: it multiplies a fractional
# coordinate by an edge length and never consults a cell angle. See
# PROPOSALS/CRYSTAL_EXACT_PATH_RIGHT_ANGLE_GATE.md.
#
# WHAT THIS COSTS SOMEBODY ELSE
#
# The archive is a public service run by people. PAUSE below is the gap between requests that
# actually reach it and it is not negotiable. A cached entry waits for nothing, so a second run over
# the same names is free to them and nearly free here.

import io
import json
import os
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)

CACHE = os.path.join(ROOT, "build", "cod")

AGENT = {"User-Agent": "anchor-sift-research/1.0 "
                       "(https://github.com/dstroy0/anchor_sift; dquigg123@gmail.com)"}
SEARCH = "https://www.crystallography.net/cod/result?format=json&text=%s&count=%d"
CIF = "https://www.crystallography.net/cod/%s.cif"

# Seconds between requests that actually reach the archive.
PAUSE = 2.0

# Attempts per request before an entry is given up on.
TRIES = 3

# Entries asked for per name. Taken higher than the oracle's because a name here returns a family
# rather than a single compound.
PER_NAME = 40

# Minerals whose published entries routinely put two elements on one position. Names, not formulas,
# because the archive's text search is what accepts them.
WANTED = (
    "olivine", "forsterite", "fayalite", "tephroite", "monticellite",
    "plagioclase", "albite", "anorthite", "oligoclase", "andesine", "labradorite",
    "orthoclase", "microcline", "sanidine", "nepheline", "leucite",
    "garnet", "almandine", "pyrope", "grossular", "andradite", "spessartine", "uvarovite",
    "pyroxene", "diopside", "augite", "enstatite", "ferrosilite", "hedenbergite", "jadeite",
    "amphibole", "hornblende", "tremolite", "actinolite", "glaucophane", "riebeckite",
    "biotite", "phlogopite", "muscovite", "annite", "chlorite", "clinochlore",
    "tourmaline", "schorl", "elbaite", "dravite",
    "apatite", "fluorapatite", "chlorapatite", "hydroxylapatite",
    "perovskite", "ilmenite", "columbite", "tantalite", "wolframite",
    "scheelite", "powellite", "barite", "celestine", "anglesite",
    "epidote", "clinozoisite", "allanite", "vesuvianite", "cordierite",
    "staurolite", "chloritoid", "serpentine", "antigorite", "lizardite",
    "melilite", "gehlenite", "akermanite", "sodalite", "cancrinite", "scapolite",
    "beryl", "cordierite", "osumilite", "zircon", "titanite", "monazite", "xenotime",
    "chalcopyrite", "bornite", "tetrahedrite", "tennantite", "arsenopyrite",
    "pentlandite", "pyrrhotite", "marcasite", "cobaltite", "skutterudite",
    "dolomite", "ankerite", "magnesite", "rhodochrosite", "smithsonite",
    "goethite", "lepidocrocite", "manganite", "psilomelane", "romanechite",
)


def fetched(url, out):
    """One request that reaches the archive, with retries. Returns text, or None where refused."""
    for attempt in range(TRIES):
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=180) as response:
                return response.read().decode("utf-8", errors="replace")
        except (urllib.error.URLError, OSError, ValueError) as reason:
            # The archive closes a connection now and then under a sweep this size. A dropped
            # request is not an absent entry, so it is retried before being given up on.
            if attempt == (TRIES - 1):
                out.write("      gave up on %s: %s\n" % (url.rsplit("/", 1)[-1], reason))
                out.flush()
                return None
            time.sleep(PAUSE * (attempt + 2))
    return None


def held():
    """Entry numbers already cached, so a rerun costs the archive nothing for them."""
    if not os.path.isdir(CACHE):
        return set()
    return {name[:-4] for name in os.listdir(CACHE) if name.endswith(".cif")}


def main():
    target = int(sys.argv[1]) if len(sys.argv) > 1 else 1200
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    if not os.path.isdir(CACHE):
        os.makedirs(CACHE)

    have = held()
    out.write("\n  cached now %d, target %d\n\n" % (len(have), target))
    out.flush()

    added = 0
    started = time.time()
    for name in WANTED:
        if len(have) >= target:
            break
        out.write("  %-18s " % name)
        out.flush()
        body = fetched(SEARCH % (urllib.request.quote(name), PER_NAME), out)
        time.sleep(PAUSE)
        if body is None:
            out.write("search refused\n")
            out.flush()
            continue
        try:
            found = json.loads(body)
        except ValueError:
            out.write("search returned nothing readable\n")
            out.flush()
            continue

        numbers = []
        for row in (found if isinstance(found, list) else []):
            number = str(row.get("file", "")).strip()
            if number and (number not in have):
                numbers.append(number)

        # Capped here and not by the count in the query. The archive treats that count as a hint
        # and returned several hundred entries for "olivine", which on the first run filled a fifth
        # of the corpus from one mineral family before the sweep reached its second name. A corpus
        # that is mostly one solid solution would make this detector look more general than it is.
        numbers = numbers[:PER_NAME]

        took = 0
        for number in numbers:
            if len(have) >= target:
                break
            text = fetched(CIF % number, out)
            time.sleep(PAUSE)
            if not text or "_atom_site" not in text:
                continue
            with io.open(os.path.join(CACHE, number + ".cif"), "w",
                         encoding="utf-8", errors="replace") as handle:
                handle.write(text)
            have.add(number)
            added += 1
            took += 1
        out.write("%d new (%d offered)\n" % (took, len(numbers)))
        out.flush()

    out.write("\n  added %d, cache now %d, %.0fs\n\n"
              % (added, len(held()), time.time() - started))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
