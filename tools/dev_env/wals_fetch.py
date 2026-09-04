#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch the World Atlas of Language Structures so a claim about many languages can be checked against
# many languages, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/wals_fetch.py
#
# Everything measured here so far runs on nineteen treebanks and one Salish story, which is enough to say
# what those texts do and not enough to say anything about language. The claim now on the table is about
# language: that where the surroundings kill people, the pressure to teach is severe, and the grammar
# carries what reliable teaching needs.
#
# That is a claim about which languages have which features, and WALS is the record of exactly that. It
# codes some two hundred structural features across two and a half thousand languages, with a family, a
# genus and a position on the earth for each one, and it is published openly in the CLDF format as plain
# tables.
#
# Four tables are wanted. The languages with where they are spoken and what family they belong to. The
# parameters, which name the features. The codes, which say what each value of a feature means. And the
# values, which are the readings themselves.
#
# Nothing is concluded here. This fetches the tables and reports what arrived, because a test whose data
# has not been looked at is the mistake this work has already made twice with corpora.

import io
import os
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WALS = os.path.join(ROOT, "build", "wals")
AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic typology study)"}

BASE = "https://raw.githubusercontent.com/cldf-datasets/wals/master/cldf"
TABLES = ("languages.csv", "parameters.csv", "codes.csv", "values.csv")
PAUSE = 0.3


def fetch(url, target):
    """One table, kept on disk, skipped where it is already held."""
    if os.path.isfile(target) and (os.path.getsize(target) > 2000):
        return os.path.getsize(target), "already held"
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=600) as response:
        blob = response.read()
    with open(target, "wb") as handle:
        handle.write(blob)
    time.sleep(PAUSE)
    return len(blob), "fetched"


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(WALS, exist_ok=True)

    out.write("  %-18s %-12s %-14s %s\n" % ("table", "bytes", "how", "first line"))
    for name in TABLES:
        target = os.path.join(WALS, name)
        try:
            size, how = fetch("%s/%s" % (BASE, name), target)
        except urllib.error.HTTPError as refused:
            out.write("  %-18s %-12s not there (%s)\n" % (name, "0", refused.code))
            continue
        except Exception as trouble:
            out.write("  %-18s %-12s %s\n" % (name, "0", str(trouble)[:40]))
            continue
        with open(target, encoding="utf-8", errors="replace") as handle:
            header = handle.readline().rstrip("\n")
        out.write("  %-18s %-12d %-14s %s\n" % (name, size, how, header[:64]))
        out.flush()

    # The features this claim is about, found by name so a renumbering does not break it
    wanted = ("evidential", "aspect", "tense", "modality", "epistemic")
    parameters = os.path.join(WALS, "parameters.csv")
    if os.path.isfile(parameters):
        import csv

        out.write("\n  features naming what the claim is about\n")
        with open(parameters, encoding="utf-8", errors="replace", newline="") as handle:
            for row in csv.DictReader(handle):
                title = (row.get("Name") or "").lower()
                if any(word in title for word in wanted):
                    out.write("  %-8s %s\n" % (row.get("ID", ""), row.get("Name", "")))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
