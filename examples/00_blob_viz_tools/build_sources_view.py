#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: VIZ-x-011
#
"""Turns build/bench/sources.csv into a viewer that switches between sources.

Every null in this work is a number. This puts the fields themselves side by side - SHA-256, a
matrix that is pseudorandom by construction, and two ablations - through identical projection code.
"does this look like noise" can be answered by looking as well as by a statistic.

    python examples/00_blob_viz_tools/build_sources_view.py
"""

import csv
import os
import sys
import out_path
import generate_template

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SOURCE = os.path.join(ROOT, "build", "bench", "sources.csv")
TEMPLATE = os.path.join(HERE, "sources_view_template.html")
TARGET = out_path.resolve("sources_view.html")

ROUNDS = 48
SHAPES = {"residue": 32, "inbit": 512, "outbit": 256}


def read():
    """One dense array per (source, projection), indexed [axis][round]. Partial rounds dropped."""
    packed = {}
    with open(SOURCE, newline="") as handle:
        for row in csv.DictReader(handle):
            try:
                at = int(row["round"]) - 1
                if not (0 <= at < ROUNDS):
                    continue
                kind = row["kind"]
                if kind not in SHAPES:
                    continue
                plane = packed.setdefault(row["source"], {}).setdefault(
                    kind, [[0.0] * ROUNDS for _ in range(SHAPES[kind])])
                plane[int(row["a"])][at] = float(row["value"])
            except (TypeError, ValueError, IndexError):
                continue
    return packed


def trimmed(rows, places):
    return [[round(value, places) for value in row] for row in rows]


def main():
    if not os.path.exists(SOURCE):
        sys.stderr.write("no build/bench/sources.csv - run bench_sac in build/bench with 18 45 64 sources\n")
        return 1

    packed = read()
    if not packed:
        sys.stderr.write("sources.csv held nothing usable\n")
        return 1

    payload = {"rounds": ROUNDS, "sources": {}}
    for name, planes in packed.items():
        payload["sources"][name] = {
            kind: trimmed(rows, 2 if kind == "residue" else 1)
            for kind, rows in planes.items()
        }
    payload["order"] = [n for n in ["sha256", "psrand", "no_addition", "no_sigma1"]
                        if n in payload["sources"]]

    try:
        page = generate_template.assemble(TEMPLATE, payload)
    except generate_template.Refused as why:
        sys.stderr.write("%s: %s\n" % (os.path.basename(TEMPLATE), why))
        return 1

    with open(TARGET, "w", encoding="utf-8") as handle:
        handle.write(page)

    print("wrote %s (%.1f KB) with %d sources"
          % (TARGET, os.path.getsize(TARGET) / 1024.0, len(payload["order"])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
