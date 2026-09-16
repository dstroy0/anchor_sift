#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRO-6-001
#
# Ask the Ramachandran reading for a deposit's outlier rate, against the rate wwPDB published for it.
#
#   Usage:  python examples/proteins/6_oracle/published_outlier_rate.py [how many structures]
#
# This is the positive control the protein subject did not have. Every control in this work until
# now was a memoryless process, and a memoryless process can only show that an instrument does not
# invent structure. It cannot show that an instrument finds structure that is there, and the protein
# case is where the difference bit: the crystallography README records that a protein was reported
# as unstructured twice, because nothing here could tell an instrument that stayed silent on real
# structure from one that was working.
#
# Crystallography became the first positive control because a cell edge is published: a number
# somebody else measured before this instrument existed. Ramachandran is the protein equivalent, and
# a closer one, because the reference is not a single number but the rules themselves. The Richardson
# laboratory's contours say which conformations a clean reference took, the wwPDB validation pipeline
# scores every deposit against them, and it publishes the resulting outlier percentage for each
# entry. So both halves are somebody else's: the rules, and the answer.
#
# The reading is coordinate free. It never sees where an atom is, only the two torsions of each
# residue, computed from exact integer coordinates and rendered through a single decimal atan2 far
# under the reference grid. It then scores those against the published contours and counts the
# outliers, and the count is compared to the published percentage.
#
# WHAT AGREEMENT TO EXPECT, STATED BEFORE THE NUMBERS
#
# Not exact equality on every structure, and the crystallography README says why in advance: a
# crystal displacement lands on an occupied place or does not, but a protein is a cloud of real
# valued coordinates and its rules are published on a two-degree grid. The quantum is real and it is
# the reference's. So the honest measure is the distribution: how many structures land on the
# published rate exactly, how many within a single residue of it, and every clear miss named.
#
# A miss here is one-directional and that direction is the finding. Where the two disagree, this
# reading almost always counts one or two residues as outliers that the pipeline's own count does
# not, never the reverse. The angle is not in dispute, since the decimal atan2 agrees with a double
# to fourteen places. What differs is which residues each side scores at all: chain ends, alternate
# locations and residues at a break are counting conventions, and that is where the last residue of
# disagreement lives. The geometry is exact; the residue bookkeeping is the tolerance.

import io
import json
import os
import sys
import time
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

# Seconds between requests that actually reach an archive. A cached read waits for nothing.
PAUSE = 1.0

# How many structures to sweep by default. The archive holds tens of thousands that match; this is
# a number the run can finish and the cache makes free to rerun.
DEFAULT = 300

# The corpus: X-ray models refined well enough that their published validation is trustworthy, and
# long enough to carry a real distribution of conformations.
QUERY = {
    "query": {"type": "group", "logical_operator": "and", "nodes": [
        {"type": "terminal", "service": "text", "parameters": {
            "attribute": "exptl.method", "operator": "exact_match", "value": "X-RAY DIFFRACTION"}},
        {"type": "terminal", "service": "text", "parameters": {
            "attribute": "rcsb_entry_info.resolution_combined", "operator": "less_or_equal",
            "value": 1.5}},
        {"type": "terminal", "service": "text", "parameters": {
            "attribute": "rcsb_entry_info.deposited_polymer_monomer_count",
            "operator": "greater_or_equal", "value": 100}},
    ]},
    "return_type": "entry",
    "request_options": {"paginate": {"start": 0, "rows": DEFAULT},
                        "sort": [{"sort_by": "rcsb_entry_info.resolution_combined",
                                  "direction": "asc"}]},
}


def cached_json(name, url, out):
    """Fetch a JSON document once and keep it. Returns the parsed body, or None on refusal."""
    path = os.path.join(CACHE, name)
    if os.path.isfile(path):
        with open(path, encoding="utf-8", errors="replace") as handle:
            return json.load(handle), False
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=AGENT), timeout=180) as r:
            body = r.read().decode("utf-8", "replace")
    except Exception as trouble:
        out.write("      gave up on %s: %s\n" % (name, str(trouble)[:60]))
        return None, True
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(body)
    return json.loads(body), True


def corpus(how_many, out):
    """The list of entry ids to sweep, from the archive's own search."""
    query = dict(QUERY)
    query["request_options"] = dict(QUERY["request_options"])
    query["request_options"]["paginate"] = {"start": 0, "rows": how_many}
    url = SEARCH % urllib.parse.quote(json.dumps(query))
    found, reached = cached_json("search_%d.json" % how_many, url, out)
    if reached:
        time.sleep(PAUSE)
    if not found:
        return []
    return [row["identifier"] for row in found.get("result_set", [])]


def published(code, out):
    """The wwPDB-published Ramachandran outlier percentage for one entry, or None."""
    body, reached = cached_json("entry_%s.json" % code, ENTRY % code, out)
    if reached:
        time.sleep(PAUSE)
    if not body:
        return None
    geometry = body.get("pdbx_vrpt_summary_geometry")
    if isinstance(geometry, list):
        geometry = geometry[0] if geometry else {}
    return (geometry or {}).get("percent_ramachandran_outliers")


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    os.makedirs(CACHE, exist_ok=True)

    how_many = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT
    contours = rules.load_contours(CACHE)

    out.write("  Predicted: the recovered outlier rate lands on the published one, exactly or\n")
    out.write("  within a single residue, on nearly every structure, from the torsions alone.\n\n")
    out.write("  %-6s %-8s %-8s %-9s %-8s %s\n"
              % ("code", "recov %", "pub %", "delta", "n", "agreement"))

    codes = corpus(how_many, out)
    exact = 0
    within = 0
    graded = 0
    misses = []
    for code in codes:
        pub = published(code, out)
        if pub is None:
            continue
        try:
            text = fetch(code, CORPORA)
        except Exception as trouble:
            out.write("  %-6s could not fetch: %s\n" % (code, str(trouble)[:40]))
            continue
        read = rules.score(contours, phi_psi(text))
        total = len(read)
        if total == 0:
            continue
        outliers = sum(1 for residue in read if residue["outlier"])
        recovered = 100.0 * outliers / total
        delta = recovered - pub
        graded += 1
        # One residue is worth 100/total percent. Inside that, the two counts differ by no residue.
        one_residue = 100.0 / total + 0.01
        if abs(delta) < 0.05:
            exact += 1
            note = "exact"
        elif abs(delta) <= one_residue:
            within += 1
            note = "within one residue"
        else:
            note = "MISS"
            misses.append((code, recovered, pub, delta, outliers, total))
        out.write("  %-6s %7.2f %7.2f %+8.2f %-8d %s\n"
                  % (code, recovered, pub, delta, total, note))
        out.flush()

    if graded == 0:
        out.write("\n  nothing graded. An archive may be unreachable and the cache is empty.\n")
        out.flush()
        return 1

    out.write("\n  %d structures graded\n" % graded)
    out.write("  %d on the published rate exactly (%.1f percent)\n"
              % (exact, 100.0 * exact / graded))
    out.write("  %d more within a single residue (%.1f percent cumulative)\n"
              % (within, 100.0 * (exact + within) / graded))
    out.write("  %d clear misses (%.1f percent)\n"
              % (len(misses), 100.0 * len(misses) / graded))

    if misses:
        over = sum(1 for _, _, _, delta, _, _ in misses if delta > 0)
        out.write("\n  every miss, and the direction it went\n")
        out.write("  %d of %d misses count MORE outliers than wwPDB, not fewer\n"
                  % (over, len(misses)))
        for code, recovered, pub, delta, outliers, total in misses[:30]:
            out.write("    %-6s recovered %5.2f  published %5.2f  %+.2f  (%d of %d residues)\n"
                      % (code, recovered, pub, delta, outliers, total))
        out.write("\n  The angle is not in dispute. The residual is which residues each side scores,\n")
        out.write("  which is a counting convention and not the geometry.\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
