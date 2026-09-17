#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch the molecular formulae of the first several thousand PubChem compounds, one wide set.
#
#   Usage:  python maint/data/fetch/fetch_pubchem_formulae.py [--refresh]
#
# The molecules legality sift reads these. A real compound's formula has a legal valence structure, and
# a wide set of them is the positive control: the sift should pass nearly all of them. The set is a
# range of compound identifiers, not a curated pick, and it is not chosen to make the sift look good.
#
# PubChem is a public service run by people. The identifiers are asked in chunks with a pause between,
# and the whole set caches, and a second run does not ask again. A chunk that fails is skipped and named,
# and the run refuses if it gathered almost nothing, which tells a stale endpoint apart from a real set.
#
# Source: the PubChem compound database, PUG REST, MolecularFormula property.

import io
import os
import sys
import time
import urllib.error
import urllib.request

# Walk up to the repository instead of counting directories to it, and stop at the filesystem root.
# A directory that is its own parent would otherwise loop the walk forever.
ROOT = os.path.dirname(os.path.abspath(__file__))
while ROOT != os.path.dirname(ROOT) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
if not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    raise SystemExit("could not find src/engine above %s" % os.path.abspath(__file__))

CACHE = os.path.join(ROOT, "build", "pubchem")
FORMULAE = os.path.join(CACHE, "formulae.csv")

ENDPOINT = "https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/cid/%s/property/MolecularFormula/CSV"

# The identifiers are asked in chunks of this many, up to this top, until the wanted count is gathered.
CHUNK = 150
TOP_CID = 12000
WANTED = 10000

# Seconds between requests. PubChem allows five a second; this stays well under.
PAUSE = 0.2

# Below this the response cannot be a wide set, and a short gather refuses instead of caching.
LEAST_ROWS = 5000


def gather(out):
    """Ask PubChem for formulae in chunks and return the CID,formula rows, or raise on a short gather."""
    rows = []
    for start in range(1, TOP_CID + 1, CHUNK):
        identifiers = ",".join(str(cid) for cid in range(start, min(start + CHUNK, TOP_CID + 1)))
        address = ENDPOINT % identifiers
        request = urllib.request.Request(address, headers={"User-Agent": "anchor_sift/molecules"})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                text = response.read().decode("utf-8", errors="replace")
        except urllib.error.URLError as failure:
            out.write("  chunk at cid %d skipped: %s\n" % (start, failure))
            continue
        for line in text.splitlines():
            # A data row starts with a digit; the header and any error text do not.
            if line[:1].isdigit():
                rows.append(line.strip())
        if len(rows) >= WANTED:
            break
        time.sleep(PAUSE)
    if len(rows) < LEAST_ROWS:
        raise ValueError("gathered %d rows, below the %d a wide set takes" % (len(rows), LEAST_ROWS))
    return rows


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if os.path.isfile(FORMULAE) and "--refresh" not in argv:
        out.write("\n  already cached: %s\n  pass --refresh to fetch again.\n\n"
                  % FORMULAE.replace(os.sep, "/"))
        out.flush()
        return 0
    out.write("\n  fetching PubChem formulae in chunks of %d, up to cid %d, wanting %d\n"
              % (CHUNK, TOP_CID, WANTED))
    try:
        rows = gather(out)
    except (urllib.error.URLError, ValueError) as failure:
        out.write("  fetch failed: %s\n\n" % failure)
        out.flush()
        return 1
    if not os.path.isdir(CACHE):
        os.makedirs(CACHE)
    with io.open(FORMULAE, "w", encoding="utf-8", newline="") as handle:
        handle.write("CID,MolecularFormula\n")
        handle.write("\n".join(rows))
        handle.write("\n")
    out.write("  wrote %d formulae to %s\n\n" % (len(rows), FORMULAE.replace(os.sep, "/")))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
