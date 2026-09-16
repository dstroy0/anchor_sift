#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Widen build/cod toward a corpus that actually contains doping, and record which family each
# entry came from.
#
#   Usage:  python maint/data/fetch/fetch_cod_doped.py [target_total]
#
# WHY A SECOND NAME LIST
#
# The list in examples/crystallography/6_oracle/proof_positive_control.py was chosen for cells
# likely to be published with right angles, because that oracle could not read anything else. It is
# a list of simple, mostly stoichiometric compounds, and a stoichiometric compound is by definition
# the case with no doping in it. Measured on the 650 entries that list produced, 54 carried a mixed
# site, so the sample was thin in the one property a doping detector exists to find.
#
# The names below are solid solution formers: minerals whose published entries routinely put two
# elements on one crystallographic position. Olivine runs magnesium to iron, plagioclase runs sodium
# to calcium, the garnets and spinels and pyroxenes substitute across whole sites.
#
# WHY THE NAMES ARE GROUPED
#
# A mineral name is not the unit anybody reasons about. Forsterite and fayalite are the endpoints of
# one solid solution and asking whether forsterite dopes differently from fayalite is asking whether
# the magnesium end of olivine differs from the iron end, which is a question about one family and
# not two minerals. Grouping here means every entry carries the family it was fetched under, written
# to families.tsv beside the cache, so a reading can report by family without guessing from a name.
#
# The family is provenance and not chemistry. It records the search term that returned the entry,
# which is a fact about how the corpus was built. An entry the archive returned for "olivine" that
# is not an olivine is still recorded as fetched under olivine, because that is what happened. A
# reading that needs true mineral classification has to get it from the deposit and not from here.
#
# THE RIGHT ANGLE RESTRICTION IS DELIBERATELY NOT APPLIED
#
# Most of these are monoclinic or triclinic. The exact reading path does not need a right angle: it
# multiplies a fractional coordinate by an edge length and never consults a cell angle. See
# PROPOSALS/CRYSTAL_EXACT_PATH_RIGHT_ANGLE_GATE.md. The doping measure needs even less than that,
# reading only the atom site loop.
#
# WHAT THIS COSTS SOMEBODY ELSE
#
# The archive is a public service run by people. PAUSE below is the gap between requests that
# actually reach it and it is not negotiable. A cached entry waits for nothing, so a second run over
# the same names is free to them and nearly free here.
#
# At a target in the thousands this route stops being the polite one. COD publishes an rsync mirror
# for bulk copying and one rsync is cheaper for them than ten thousand requests. Use
# fetch_cod_bulk.py for those. This stays the right tool for a targeted few hundred.

import http.client
import io
import json
import os
import socket
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
FAMILIES_FILE = os.path.join(CACHE, "families.tsv")

AGENT = {"User-Agent": "anchor-sift-research/1.0 "
                       "(https://github.com/dstroy0/anchor_sift; dquigg123@gmail.com)"}
SEARCH = "https://www.crystallography.net/cod/result?format=json&text=%s&count=%d"
CIF = "https://www.crystallography.net/cod/%s.cif"

# Seconds between requests that actually reach the archive.
PAUSE = 2.0

# Attempts per request before an entry is given up on.
TRIES = 3

# Entries taken per name. The archive treats the count in the query as a hint and returned several
# hundred for "olivine", which on an early run filled a fifth of the corpus from one family before
# the sweep reached its second name. The cap below is what actually holds.
#
# Set against the target rather than for its own sake. At 60 the name list tops out well short of
# ten thousand, because most names return fewer than sixty and the overlap between related names is
# large.
#
# Raising it alone would undo what it was introduced for. Walking the families in order with a high
# cap lets olivine and feldspar reach the target before the sulfides are asked at all, which is the
# same one family corpus the cap was added to prevent, arriving by a different route. The names are
# therefore interleaved across families below, so the cap governs how deep a single name goes and
# the interleave governs how evenly the families are sampled. Neither setting is sufficient alone.
PER_NAME = 120

# Solid solution formers, grouped by the family a mineralogist would put them in. The family is the
# unit a reading reports by; the names are how the archive is asked.
FAMILIES = (
    ("olivine", ("olivine", "forsterite", "fayalite", "tephroite", "monticellite",
                 "liebenbergite", "kirschsteinite")),
    ("feldspar", ("plagioclase", "albite", "anorthite", "oligoclase", "andesine", "labradorite",
                  "bytownite", "orthoclase", "microcline", "sanidine", "anorthoclase", "celsian")),
    ("feldspathoid", ("nepheline", "leucite", "sodalite", "cancrinite", "scapolite", "analcime")),
    ("garnet", ("garnet", "almandine", "pyrope", "grossular", "andradite", "spessartine",
                "uvarovite", "majorite", "schorlomite")),
    ("pyroxene", ("pyroxene", "diopside", "augite", "enstatite", "ferrosilite", "hedenbergite",
                  "jadeite", "aegirine", "spodumene", "omphacite", "wollastonite")),
    ("amphibole", ("amphibole", "hornblende", "tremolite", "actinolite", "glaucophane",
                   "riebeckite", "cummingtonite", "grunerite", "pargasite", "edenite")),
    ("mica", ("biotite", "phlogopite", "muscovite", "annite", "lepidolite", "paragonite",
              "zinnwaldite")),
    ("chlorite", ("chlorite", "clinochlore", "chamosite", "penninite")),
    ("tourmaline", ("tourmaline", "schorl", "elbaite", "dravite", "uvite", "liddicoatite")),
    ("apatite", ("apatite", "fluorapatite", "chlorapatite", "hydroxylapatite", "pyromorphite",
                 "mimetite", "vanadinite")),
    ("spinel", ("spinel", "magnetite", "chromite", "franklinite", "gahnite", "hercynite",
                "magnesioferrite", "ulvospinel", "trevorite")),
    ("perovskite", ("perovskite", "tausonite", "loparite", "latrappite", "lueshite")),
    ("oxide", ("ilmenite", "hematite", "corundum", "rutile", "anatase", "brookite", "cassiterite",
               "pyrolusite", "columbite", "tantalite", "wolframite", "pseudobrookite")),
    ("tungstate", ("scheelite", "powellite", "stolzite", "raspite")),
    ("sulfate", ("barite", "celestine", "anglesite", "anhydrite", "gypsum", "alunite", "jarosite")),
    ("epidote", ("epidote", "clinozoisite", "allanite", "zoisite", "piemontite", "vesuvianite")),
    ("cyclosilicate", ("cordierite", "beryl", "osumilite", "milarite", "sekaninaite")),
    ("nesosilicate", ("staurolite", "chloritoid", "zircon", "titanite", "monazite", "xenotime",
                      "topaz", "andalusite", "kyanite", "sillimanite", "datolite")),
    ("serpentine", ("serpentine", "antigorite", "lizardite", "chrysotile", "greenalite")),
    ("melilite", ("melilite", "gehlenite", "akermanite", "hardystonite")),
    ("sulfide", ("chalcopyrite", "bornite", "tetrahedrite", "tennantite", "arsenopyrite",
                 "pentlandite", "pyrrhotite", "marcasite", "cobaltite", "skutterudite",
                 "sphalerite", "galena", "stannite", "enargite")),
    ("carbonate", ("dolomite", "ankerite", "magnesite", "rhodochrosite", "smithsonite", "calcite",
                   "siderite", "aragonite", "witherite", "strontianite", "kutnohorite")),
    ("hydroxide", ("goethite", "lepidocrocite", "manganite", "psilomelane", "romanechite",
                   "brucite", "gibbsite", "diaspore", "boehmite")),
    ("phosphate", ("triphylite", "lithiophilite", "graftonite", "sarcopside", "wagnerite",
                   "amblygonite", "montebrasite", "childrenite", "eosphorite")),
    ("halide", ("fluorite", "halite", "sylvite", "carnallite", "cryolite", "villiaumite",
                "chlorargyrite", "atacamite")),
    ("clay", ("montmorillonite", "illite", "kaolinite", "vermiculite", "saponite", "nontronite",
              "beidellite")),
    ("zeolite", ("zeolite", "natrolite", "heulandite", "clinoptilolite", "chabazite", "stilbite",
                 "mordenite", "phillipsite", "laumontite")),
    ("borate", ("tourmaline group", "boracite", "ludwigite", "vonsenite", "kotoite")),
)


def fetched(url, out):
    """One request that reaches the archive, with retries. Returns text, or None where refused."""
    for attempt in range(TRIES):
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=180) as response:
                return response.read().decode("utf-8", errors="replace")
        except (urllib.error.URLError, http.client.HTTPException, socket.timeout,
                OSError) as reason:
            # The archive closes a connection now and then under a sweep this size. A dropped
            # request is not an absent entry, so it is retried before being given up on.
            #
            # http.client.HTTPException is in that list because leaving it out killed a run at 1836
            # entries. A truncated response raises IncompleteRead, which descends from
            # HTTPException and not from URLError or OSError, so it walked straight through a
            # handler that looked complete. The failure mode is worth naming: every ordinary network
            # error was retried and the one that ends a four hour sweep was the one not caught.
            #
            # ValueError was in this list and has been taken out. It was here to catch a decode
            # failure, and it also catches a programming error: a bad format string or a bad int()
            # inside this block would be retried three times and then reported as the archive
            # refusing. That is the same fault as catching bare Exception, one notch smaller, and
            # the sibling client in examples/crystallography/6_oracle/proof_positive_control.py:109
            # has the full sized version of it. A network retry should not be able to swallow a bug
            # in the code doing the retrying.
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


def recorded():
    """Entry numbers already carrying a family, so a rerun does not write a second row for one."""
    if not os.path.isfile(FAMILIES_FILE):
        return set()
    seen = set()
    with io.open(FAMILIES_FILE, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if parts and parts[0] and not parts[0].startswith("#"):
                seen.add(parts[0])
    return seen


def main():
    target = int(sys.argv[1]) if len(sys.argv) > 1 else 1200
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    if not os.path.isdir(CACHE):
        os.makedirs(CACHE)

    have = held()
    already = recorded()
    fresh = not os.path.isfile(FAMILIES_FILE)
    out.write("\n  cached now %d, target %d\n\n" % (len(have), target))
    out.flush()

    # Appended rather than rewritten. The family of an entry already fetched is a fact about a run
    # that already happened, and a later run overwriting it would erase provenance to no purpose.
    families = io.open(FAMILIES_FILE, "a", encoding="utf-8")
    if fresh:
        families.write("# entry\tfamily\tsearch name\n")
        families.flush()

    # Interleaved, not walked family by family. Taking the first name of every family before the
    # second name of any of them means a target reached early is still spread across the whole list.
    # Walked in order, a target of ten thousand would be met inside the first few families and the
    # corpus would carry no sulfides, carbonates or zeolites at all.
    rounds = []
    deepest = max(len(names) for _, names in FAMILIES)
    for step in range(deepest):
        for family, names in FAMILIES:
            if step < len(names):
                rounds.append((family, names[step]))

    added = 0
    backfilled = 0
    started = time.time()
    for family, name in rounds:
        if len(have) >= target:
            break
        out.write("  %-14s %-18s " % (family, name))
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

        # An entry this search returns that is already cached but carries no family gets one
        # written now. The corpus was built before families were recorded, so without this the
        # first twelve hundred entries would stay unlabelled forever. It costs no extra request:
        # the search response is already in hand and only the CIF fetch is skipped.
        numbers = []
        for row in (found if isinstance(found, list) else []):
            number = str(row.get("file", "")).strip()
            if not number:
                continue
            if number in have:
                if number not in already:
                    families.write("%s\t%s\t%s\n" % (number, family, name))
                    already.add(number)
                    backfilled += 1
                continue
            numbers.append(number)
        numbers = numbers[:PER_NAME]

        took = 0
        for number in numbers:
            if len(have) >= target:
                break
            text = fetched(CIF % number, out)
            time.sleep(PAUSE)
            if not text or "_atom_site" not in text:
                continue
            try:
                with io.open(os.path.join(CACHE, number + ".cif"), "w",
                             encoding="utf-8", errors="replace") as handle:
                    handle.write(text)
            except OSError as reason:
                # One entry that will not write does not end the sweep. The alternative is losing
                # every request made after it to a full disk or a locked file.
                out.write("      could not write %s: %s\n" % (number, reason))
                out.flush()
                continue
            have.add(number)
            if number not in already:
                families.write("%s\t%s\t%s\n" % (number, family, name))
                already.add(number)
            added += 1
            took += 1
        families.flush()
        out.write("%d new (%d offered)\n" % (took, len(numbers)))
        out.flush()

    families.close()
    out.write("\n  added %d, family backfilled onto %d already cached, cache now %d, %.0fs\n\n"
              % (added, backfilled, len(held()), time.time() - started))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
