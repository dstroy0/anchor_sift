#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRO-6-001
#
# Ask the Ramachandran reading for a deposit's outlier rate, against the rate wwPDB published for it,
# over a thousand proteins drawn at random from the open archive.
#
#   Usage:  python examples/proteins/6_oracle/published_outlier_rate.py [how many proteins]
#
# This is the positive control the protein subject did not have. Every control in this work until
# now was a memoryless process, and a memoryless process can only show that an instrument does not
# invent structure. It cannot show that an instrument finds structure that is present, and the
# protein case is where that bit: the crystallography README records that a protein was reported as
# unstructured twice, because nothing here could tell an instrument that stayed silent on real
# structure from one that was working.
#
# Crystallography became the first positive control because a cell edge is published in an open
# database: the Crystallography Open Database gives the edge for every entry, a number somebody else
# measured before this instrument existed. Proteins have the same kind of open archive and a closer
# reference. The worldwide Protein Data Bank is open and keyless, the same way the COD is: the RCSB
# mirror serves every deposited coordinate file and every deposit's validation report to anyone, no
# account and no key. The Richardson laboratory's Ramachandran contours are the rules the wwPDB
# validation pipeline scores against, and it publishes the resulting outlier percentage per entry.
# So both halves of the check are somebody else's: the rules, and the answer.
#
# WHY A RANDOM SAMPLE AND NOT THE BEST STRUCTURES
#
# The corpus is drawn at random from every X-ray protein entry in the archive, with a held seed so
# the draw repeats. Sorting by resolution and taking the top of the list was the wrong control: the
# best-resolved structures nearly all have an outlier rate of zero. An instrument that only ever
# answered zero would have scored full marks against them and taught nothing. A random protein spans
# the whole quality range, from sub-angstrom to the low-resolution end, and carries a real spread of
# published rates from zero to several percent. Reproducing that spread is the test; reproducing a
# column of zeros is not.
#
# The archive is open and the reading takes only what it needs. It never sees where an atom sits,
# only the two backbone torsions of each residue, computed from exact integer coordinates and
# rendered through a single decimal atan2 far under the reference grid. It scores those against the
# published contours, counts the outliers, and compares the count to the published percentage.
#
# WHAT AGREEMENT TO EXPECT, STATED BEFORE THE NUMBERS
#
# Not exact equality on every structure, and the crystallography README says why in advance: a
# crystal displacement lands on an occupied place or it does not, but a protein is a cloud of real
# valued coordinates and its rules are published on a two-degree grid. The quantum is real and it is
# the reference's. So the honest measure is the distribution: how many of the thousand land on the
# published rate exactly, how many within a single residue of it, and every clear miss carried
# forward with the direction it went and the resolution it came from, because a random sample is the
# first corpus here that can say whether disagreement tracks resolution.

import io
import json
import os
import random
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))
sys.path.insert(0, os.path.join(ROOT, "examples", "proteins"))

from representation.structure.protein import fetch, phi_psi  # noqa: E402
import ramachandran_rules as rules  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")
CACHE = os.path.join(ROOT, "build", "rama")

AGENT = {"User-Agent": "anchor-sift-research/1.0 "
                       "(https://github.com/dstroy0/anchor_sift; dquigg123@gmail.com)"}
SEARCH = "https://search.rcsb.org/rcsbsearch/v2/query?json=%s"
ENTRY = "https://data.rcsb.org/rest/v1/core/entry/%s"

# Seconds between requests that actually reach the archive. A cached read waits for nothing. RCSB is
# a large service and asks for courtesy, not silence; half a second is well inside what it invites.
PAUSE = 0.5

# Attempts before a reached request is given up on, with a growing wait between. A dropped connection
# under a sweep this size is not a missing structure, and counting it as one would shrink the
# denominator quietly.
TRIES = 3

# Proteins to grade. The archive holds two hundred thousand that match. This is a target to reach,
# not a slice off the top: the sweep draws from the shuffled pool until this many have graded.
TARGET = 1000

# Held. The random draw repeats. The corpus belongs to the seed and not to the run.
SEED = 0x51F7

# Every X-ray protein entry, spanning the whole resolution range on purpose. The monomer floor drops
# fragments and peptides that carry too little backbone to place a distribution.
QUERY = {
    "query": {"type": "group", "logical_operator": "and", "nodes": [
        {"type": "terminal", "service": "text", "parameters": {
            "attribute": "exptl.method", "operator": "exact_match", "value": "X-RAY DIFFRACTION"}},
        {"type": "terminal", "service": "text", "parameters": {
            "attribute": "rcsb_entry_info.polymer_entity_count_protein",
            "operator": "greater_or_equal", "value": 1}},
        {"type": "terminal", "service": "text", "parameters": {
            "attribute": "rcsb_entry_info.deposited_polymer_monomer_count",
            "operator": "greater_or_equal", "value": 30}},
    ]},
    "return_type": "entry",
    "request_options": {"return_all_hits": True, "results_content_type": ["experimental"]},
}


def cached_json(name, url, out, timeout=180):
    """Fetch a JSON document once and keep it, retrying a reached request that drops.

    Returns (parsed body or None, whether the network was reached). A cache hit reaches nothing.
    """
    path = os.path.join(CACHE, name)
    if os.path.isfile(path):
        with open(path, encoding="utf-8", errors="replace") as handle:
            return json.load(handle), False
    body = None
    for attempt in range(TRIES):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=AGENT),
                                        timeout=timeout) as response:
                body = response.read().decode("utf-8", "replace")
            break
        except urllib.error.HTTPError as trouble:
            # A 404 is an answer, not a dropped line: this entry has no such document. Do not retry.
            out.write("      %s: %s\n" % (name, trouble))
            return None, True
        except Exception as trouble:
            if attempt == (TRIES - 1):
                out.write("      gave up on %s: %s\n" % (name, str(trouble)[:60]))
                return None, True
            time.sleep(PAUSE * (attempt + 2))
    if body is None:
        return None, True
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(body)
    return json.loads(body), True


def pool(out):
    """Every matching entry id, fetched once and shuffled by the held seed.

    The whole id list is small next to the coordinate files it points at. It is fetched once and
    cached, and the shuffle is deterministic. Drawing from the front of this list is a uniform random
    sample of the archive that repeats exactly on a rerun.
    """
    url = SEARCH % urllib.parse.quote(json.dumps(QUERY))
    found, reached = cached_json("all_xray_protein_ids.json", url, out, timeout=600)
    if reached:
        time.sleep(PAUSE)
    if not found:
        return []
    ids = ([row["identifier"] for row in found.get("result_set", [])]
           if isinstance(found, dict) else list(found))
    random.Random(SEED).shuffle(ids)
    return ids


def published(code, out):
    """The wwPDB-published Ramachandran outlier percentage and resolution for one entry, or None."""
    body, reached = cached_json("entry_%s.json" % code, ENTRY % code, out)
    if reached:
        time.sleep(PAUSE)
    if not body:
        return None, None
    geometry = body.get("pdbx_vrpt_summary_geometry")
    if isinstance(geometry, list):
        geometry = geometry[0] if geometry else {}
    resolution = body.get("rcsb_entry_info", {}).get("resolution_combined")
    resolution = resolution[0] if isinstance(resolution, list) and resolution else resolution
    return (geometry or {}).get("percent_ramachandran_outliers"), resolution


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    os.makedirs(CACHE, exist_ok=True)

    target = int(sys.argv[1]) if len(sys.argv) > 1 else TARGET
    contours = rules.load_contours(CACHE)

    out.write("  Predicted: the recovered outlier rate lands on the published one, exactly or\n")
    out.write("  within a single residue, on nearly every protein, from the torsions alone.\n")
    out.write("  The corpus is %d proteins drawn at random from every X-ray entry in the PDB.\n\n"
              % target)
    out.write("  %-6s %-8s %-8s %-9s %-6s %-6s %s\n"
              % ("code", "recov %", "pub %", "delta", "res", "n", "agreement"))

    ids = pool(out)
    if not ids:
        out.write("\n  no corpus. The search could not be reached and no id list is cached.\n")
        out.flush()
        return 1

    exact = 0
    within = 0
    graded = 0
    misses = []
    bands = {}  # resolution band -> [graded, agreed within one residue]
    for code in ids:
        if graded >= target:
            break
        pub, resolution = published(code, out)
        if pub is None:
            continue
        try:
            text = fetch(code, CORPORA)
        except Exception:
            # No PDB-format file, or the download dropped: draw the next id instead of stopping.
            continue
        read = rules.score(contours, phi_psi(text))
        total = len(read)
        if total == 0:
            continue
        outliers = sum(1 for residue in read if residue["outlier"])
        recovered = 100.0 * outliers / total
        delta = recovered - pub
        graded += 1

        one_residue = 100.0 / total + 0.01
        agreed = abs(delta) <= one_residue
        if abs(delta) < 0.05:
            exact += 1
            note = "exact"
        elif agreed:
            within += 1
            note = "within one residue"
        else:
            note = "MISS"
            misses.append((code, recovered, pub, delta, outliers, total, resolution))

        band = "unknown" if resolution is None else "%.1f" % (round(float(resolution) * 2) / 2)
        tally = bands.setdefault(band, [0, 0])
        tally[0] += 1
        tally[1] += 1 if agreed else 0

        res_text = "?" if resolution is None else "%.2f" % float(resolution)
        out.write("  %-6s %7.2f %7.2f %+8.2f %-6s %-6d %s\n"
                  % (code, recovered, pub, delta, res_text, total, note))
        out.flush()

    if graded == 0:
        out.write("\n  nothing graded. The archive may be unreachable and the cache is empty.\n")
        out.flush()
        return 1

    out.write("\n  %d proteins graded\n" % graded)
    out.write("  %d on the published rate exactly (%.1f percent)\n"
              % (exact, 100.0 * exact / graded))
    out.write("  %d more within a single residue (%.1f percent cumulative)\n"
              % (within, 100.0 * (exact + within) / graded))
    out.write("  %d clear misses (%.1f percent)\n"
              % (len(misses), 100.0 * len(misses) / graded))

    if misses:
        over = sum(1 for row in misses if row[3] > 0)
        out.write("\n  %d of %d misses count MORE outliers than wwPDB, not fewer\n"
                  % (over, len(misses)))

    # Whether agreement tracks resolution, which a random sample is the first corpus here to show.
    out.write("\n  agreement within one residue, by resolution band\n")
    for band in sorted(bands, key=lambda one: (one == "unknown", one)):
        seen, ok = bands[band]
        out.write("    %-8s %4d of %4d  (%.1f percent)\n"
                  % (band + (" A" if band != "unknown" else ""), ok, seen, 100.0 * ok / seen))

    out.write("\n  The angle is exact; the residual is which residues each side scores, which is a\n")
    out.write("  counting convention and not the geometry.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
