"""Builds the longitude view: the daily cycle read as a map of where the hashrate sits.

A daily cycle in UTC is already a statement about geography. Every miner follows its own local
clock, so a hashrate spread evenly around the planet cancels to nothing in UTC and produces no
daily signal at all. A signal exists only where the distribution is lopsided, and the hour its
trough falls on is a longitude-weighted average of where the machines actually are.

That makes the right picture a polar one. Twenty-four hours of UTC close a circle, and so do three
hundred and sixty degrees of longitude, so the daily count plotted on a dial IS the planet seen
down its own axis with the hashrate drawn as radius. Nothing is being analogised: the two axes are
the same axis.

WHAT THE VIEW MAKES YOU SAY OUT LOUD

Turning an hour into a longitude needs one assumption - which local hour the dip belongs to - and
that assumption changes the answer. Electricity peaks in the local afternoon, so a curtailment dip
should sit near local 16:00, but a maintenance window would not, and a cheap-power surge would sit
opposite. The view therefore puts that hour on a control instead of burying it in the arithmetic:
move it and the inferred longitude rotates, which is the honest way to show that the geography is
downstream of a mechanism nobody has proved yet.

WHAT IT IS NOT

The evidence is marginal. Twenty-four bins over six thousand nine hundred and eighty blocks give a
chi-square of 36.62 against a multinomial null whose ninety-fifth percentile is 35.10. That is
p = 0.036 and it is drawn on the page, so it cannot be read as more than it is.

    python tools/view/build_earth_view.py
    python tools/view/build_earth_view.py --corpus tools/chain/blocks_deep.json
"""

import argparse
import io
import json
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TEMPLATE = os.path.join(HERE, "earth_view_template.html")
DEFAULT = os.path.join(ROOT, "tools", "chain", "blocks_deep.json")

# Longitudes where mining is known to concentrate, for reference marks only. These are drawn as
# labels on the dial and are never fitted to anything.
REGIONS = [
    ("US, ERCOT", -99.0),
    ("US, Appalachia", -81.0),
    ("Iceland", -19.0),
    ("Russia, Irkutsk", 104.0),
    ("Kazakhstan", 67.0),
    ("China, Sichuan", 103.0),
    ("Paraguay", -57.0),
]


def chi_square(counts):
    expect = sum(counts) / len(counts)
    return sum((c - expect) ** 2 / expect for c in counts)


def multinomial_null(total, bins, draws, rng):
    """Chi-square the way chance produces it, at the same count and the same bins."""
    out = []
    for _ in range(draws):
        counts = [0] * bins
        for _ in range(total):
            counts[rng.randrange(bins)] += 1
        out.append(chi_square(counts))
    return sorted(out)


def main():
    parser = argparse.ArgumentParser(description="Build the longitude view.")
    parser.add_argument("--corpus", default=DEFAULT)
    parser.add_argument("--out", default=os.path.join(HERE, "earth_view.html"))
    given = parser.parse_args()

    with io.open(given.corpus, encoding="utf-8") as handle:
        blocks = json.load(handle)
    stamps = sorted(int(b["timestamp"]) for b in blocks)
    total = len(stamps)

    hours = [0] * 24
    for stamp in stamps:
        hours[(stamp // 3600) % 24] += 1

    days = [0] * 7
    for stamp in stamps:
        days[((stamp // 86400) + 4) % 7] += 1

    rng = random.Random(0xEA27)
    null = multinomial_null(total, 24, 1500, rng)
    observed = chi_square(hours)
    beat = sum(1 for v in null if v >= observed)

    # The interval per hour as well, since the count and the interval are the same statement read
    # two ways and disagreeing would mean the reading is wrong.
    by_hour = [[] for _ in range(24)]
    for index in range(len(stamps) - 1):
        gap = stamps[index + 1] - stamps[index]
        if gap > 0:
            by_hour[(stamps[index] // 3600) % 24].append(gap)
    intervals = [round(sum(v) / len(v), 2) if len(v) > 20 else None for v in by_hour]

    payload = {
        "total": total,
        "days": (max(stamps) - min(stamps)) / 86400.0,
        "hours": hours,
        "weekdays": days,
        "intervals": intervals,
        "chi": round(observed, 2),
        "nullMean": round(sum(null) / len(null), 2),
        "null95": round(null[int(0.95 * len(null))], 2),
        "p": round(beat / float(len(null)), 4),
        "regions": [{"name": name, "lon": lon} for name, lon in REGIONS],
    }

    with io.open(TEMPLATE, encoding="utf-8") as handle:
        page = handle.read()
    if "/*DATA*/" not in page:
        raise SystemExit("template has no /*DATA*/ placeholder: %s" % TEMPLATE)
    page = page.replace("/*DATA*/", json.dumps(payload, separators=(",", ":")))

    with io.open(given.out, "w", encoding="utf-8") as handle:
        handle.write(page)

    print("wrote %s" % given.out)
    print("  %d blocks over %.1f days" % (total, payload["days"]))
    print("  chi-square %.2f, null 95th %.2f, p = %.4f"
          % (payload["chi"], payload["null95"], payload["p"]))
    swing = 100.0 * (max(hours) - min(hours)) / (total / 24.0)
    print("  peak-to-trough swing %.1f%%" % swing)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
