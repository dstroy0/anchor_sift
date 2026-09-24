#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRO-x-001
# Catalog: PRO-CORPUS
#
# Draw a corpus of deposited proteins from the open archive and cache the coordinate files. The
# vector-walk stages have a fixed, repeatable set to read.
#
#   Usage:  python examples/proteins/build_corpus.py [how many]
#
# The draw is the same one the oracle uses: every X-ray protein entry in the Protein Data Bank,
# shuffled by a held seed. A smaller number is a prefix of that shuffle and a larger one extends it.
# A corpus of 10000 contains the oracle's 1000 and every number between. The oracle already cached
# the id list under build/rama; this reads it and never re-asks the search.
#
# The target is a count to reach, not a slice off the top. An id with no PDB-format coordinate file
# is skipped and the next drawn, until the target many are cached. The archive is open and keyless,
# the same RCSB mirror the oracle reads, and the courtesy pause is the oracle's: half a second
# between requests that reach the network, nothing between cache hits.

import io
import os
import random
import sys
import time
import urllib.error

ROOT = os.path.dirname(os.path.abspath(__file__))
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))
sys.path.insert(0, os.path.join(ROOT, "examples", "proteins"))

from representation.structure.protein import fetch  # noqa: E402

CORPORA = os.path.join(ROOT, "build", "corpora")
CACHE = os.path.join(ROOT, "build", "rama")
IDS = os.path.join(CACHE, "all_xray_protein_ids.json")

# The oracle's seed. This corpus is the same draw extended, not a different one.
SEED = 0x51F7
PAUSE = 0.5
TRIES = 3
TARGET = 10000


def pool():
    """The held-seed shuffle of every matching entry id, read from the oracle's cached list."""
    import json

    with open(IDS, encoding="utf-8", errors="replace") as handle:
        found = json.load(handle)
    ids = (
        [row["identifier"] for row in found.get("result_set", [])]
        if isinstance(found, dict)
        else list(found)
    )
    random.Random(SEED).shuffle(ids)
    return ids


def main():
    out = io.TextIOWrapper(
        sys.stdout.buffer, encoding="utf-8", errors="replace", newline=""
    )
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isfile(IDS):
        out.write(
            "no id list at %s. Run the oracle once to cache it, or set it in place.\n"
            % IDS
        )
        out.flush()
        return 1

    target = int(sys.argv[1]) if len(sys.argv) > 1 else TARGET
    ids = pool()
    out.write(
        "drawing until %d coordinate files are cached, from %d shuffled ids\n"
        % (target, len(ids))
    )
    out.flush()

    have = fetched = failed = drawn = 0
    for code in ids:
        if have >= target:
            break
        drawn += 1
        path = os.path.join(CORPORA, "pdb_%s.txt" % code)
        if os.path.isfile(path):
            have += 1
            continue
        got = False
        for attempt in range(TRIES):
            try:
                fetch(code, CORPORA)
                got = True
                break
            except urllib.error.HTTPError:
                # No PDB-format file for this entry: an answer, not a dropped line. Do not retry.
                break
            except Exception:
                time.sleep(PAUSE * (attempt + 2))
        time.sleep(PAUSE)
        if got:
            have += 1
            fetched += 1
        else:
            failed += 1
        if (drawn % 100) == 0:
            out.write(
                "  drawn %d  cached %d  fetched this run %d  no file %d\n"
                % (drawn, have, fetched, failed)
            )
            out.flush()

    out.write(
        "\ndone: %d coordinate files cached (drew %d ids, fetched %d this run, %d had no file)\n"
        % (have, drawn, fetched, failed)
    )
    out.flush()
    return 0 if have >= target else 1


if __name__ == "__main__":
    raise SystemExit(main())
