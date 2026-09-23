"""Puts the combed survey on the golden spiral: 256 output bits, 256 places, one arm each.

The survey counts how often each of SHA-256's 256 output positions is set. A table of 256 numbers
hides the one thing worth seeing, which is whether anything clusters, so the positions are placed
on the sphere by `boundary_read.golden_place` - index k at height 1 - 2(k + 0.5)/256, longitude
k gamma - and drawn there. That placement has no seam and no pole pile, so a cluster on the surface
is a cluster in the data rather than an artifact of where the points were put.

WHAT EACH ARM ADDS

An arm is one survey under one header. Arms cost nothing to keep: the counters are 256 numbers and
33 bins whatever the depth, and the device buffers are allocated once, so memory is flat in the arm
count. What they buy is not flat, and it does not all scale alike:

    pooled depth   as the square root of the arm count, which is what more of anything buys
    agreement      as two to the arm count, because each further arm halves the chance that a run
                   of agreeing signs is coincidence

So the size of a point is its pooled deviation, which answers HOW LARGE, and the colour is how many
arms agreed on its sign, which answers WHETHER IT IS ANYTHING. Those are different questions and
the drawing keeps them apart.

Every comparison is integer: a position set c times out of N deviates by exactly 2c - N, pooling is
addition, and reach in standard errors is (sum of deviations) squared against k squared times the
summed N. Division appears only when a number is formatted.

    python examples/00_blob_viz_tools/build_spiral_view.py
"""

import argparse
import glob
import io
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "spiral_view_template.html")
DEFAULT_DIR = os.path.join(os.path.expanduser("~"), ".claude", "jobs", "52b29cc3", "tmp")

sys.path.insert(0, HERE)
import boundary_read

WORD_NAME = ("a", "b", "c", "d", "e", "f", "g", "h")


def reach_of(deviation, samples):
    """Whole standard errors, by integer comparison only. No division, no root."""
    squared = deviation * deviation
    reach = 0
    while reach < 12 and squared >= (reach + 1) * (reach + 1) * samples:
        reach += 1
    return reach


def main():
    parser = argparse.ArgumentParser(description="Build the combed spiral view.")
    parser.add_argument("--dir", default=DEFAULT_DIR)
    parser.add_argument("--out", default=os.path.join(HERE, "spiral_view.html"))
    given = parser.parse_args()

    paths = sorted(glob.glob(os.path.join(given.dir, "survey_arm_*.json")),
                   key=lambda p: int(os.path.basename(p).split("_")[2].split(".")[0]))
    arms = []
    for path in paths:
        with io.open(path, encoding="utf-8") as handle:
            arms.append(json.load(handle))
    if len(arms) < 3:
        raise SystemExit("need at least three arms, found %d in %s" % (len(arms), given.dir))

    width = len(arms)
    total = sum(int(a["nonces"]) for a in arms)
    places = boundary_read.golden_place(256)

    points = []
    for position in range(256):
        deviations = [2 * int(a["bits"][position]) - int(a["nonces"]) for a in arms]
        pooled = sum(deviations)
        positives = sum(1 for d in deviations if d > 0)
        agree = max(positives, width - positives)
        x, y, z = places[position]
        points.append({
            "at": position,
            "word": position // 32,
            "bit": position % 32,
            "xyz": [round(x, 5), round(y, 5), round(z, 5)],
            "deviation": pooled,
            "reach": reach_of(pooled, total),
            "agree": agree,
            "high": pooled > 0,
        })

    # How many positions agreed at each level, against the exact binomial. Under the null a
    # position's sign is a fair coin in every arm, so the count agreeing is binomial and the
    # expectation is computable rather than simulated.
    def binomial(n, k):
        return math.comb(n, k)

    spread = {}
    for point in points:
        spread[point["agree"]] = spread.get(point["agree"], 0) + 1
    expected = {}
    for agree in range(width // 2, width + 1):
        if agree * 2 == width:
            ways = binomial(width, agree)
        else:
            ways = 2 * binomial(width, agree)
        expected[agree] = 256.0 * ways / float(1 << width)

    payload = {
        "arms": width,
        "perArm": min(int(a["nonces"]) for a in arms),
        "total": total,
        "points": points,
        "words": list(WORD_NAME),
        "agreement": [{"agree": a, "seen": spread.get(a, 0), "expected": round(expected[a], 3)}
                      for a in sorted(expected, reverse=True)],
        "unanimousByChance": 256.0 * 2.0 / float(1 << width),
    }

    with io.open(TEMPLATE, encoding="utf-8") as handle:
        page = handle.read()
    if "/*DATA*/" not in page:
        raise SystemExit("template has no /*DATA*/ placeholder: %s" % TEMPLATE)
    page = page.replace("/*DATA*/", json.dumps(payload, separators=(",", ":")))
    with io.open(given.out, "w", encoding="utf-8") as handle:
        handle.write(page)

    loudest = max(points, key=lambda p: abs(p["deviation"]))
    print("wrote %s" % given.out)
    print("  %d arms, %s nonces each, %s pooled"
          % (width, format(payload["perArm"], ","), format(total, ",")))
    print("  loudest position %d, reaching %d sd, %d of %d arms agreeing"
          % (loudest["at"], loudest["reach"], loudest["agree"], width))
    print("  unanimous positions: %d seen, %.3g expected by chance"
          % (spread.get(width, 0), payload["unanimousByChance"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
