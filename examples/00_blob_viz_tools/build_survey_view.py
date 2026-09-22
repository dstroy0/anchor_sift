"""Draws the device survey: the output bit map, the power-of-two histogram, and what the fix bought.

The survey hashes a nonce range on the device and accumulates two things the miner never reads: how
often each of the 256 output bit positions was set, and how many digests carried at least k leading
zeros. Both are tests of the construction rather than of any particular block, and both were sitting
in the tree unread.

EXACT ARITHMETIC, NO FLOATS

Every count is an integer and every comparison here stays one. For a position set c times out of N
the deviation from a fair coin is

    2c - N

which is exact, and testing it against k standard errors is

    (2c - N)^2  against  k^2 * N

with no division and no square root anywhere. Floats appear only when a number is formatted for
display, and never in a decision. This matters because the deviations are parts in a hundred
thousand and the question of whether the format can carry them should not have to be asked.

WHAT THE THIRD PANEL SHOWS

A grid-stride loop in this kernel rounded its trip count up in thirty-two bits, so a survey of the
full nonce range wrapped to zero iterations and returned every counter empty while the host credited
the whole count. The run looked, from outside, exactly like one that completed. The panel puts the
two runs side by side because a silent zero is the failure mode worth being able to recognise.

    python tools/view/build_survey_view.py
    python tools/view/build_survey_view.py --dump path/to/survey_dump.json
"""

import argparse
import io
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "survey_view_template.html")
WORD_NAME = ("a", "b", "c", "d", "e", "f", "g", "h")


def sigma_bucket(deviation, samples):
    """How many whole standard errors the deviation reaches, by integer comparison only.

    (2c - N)^2 against k^2 * N, walked upward. No division, no square root, no float.
    """
    squared = deviation * deviation
    reach = 0
    while reach < 8 and squared >= (reach + 1) * (reach + 1) * samples:
        reach += 1
    return reach


def main():
    parser = argparse.ArgumentParser(description="Build the survey view.")
    parser.add_argument("--dump", default=os.path.join(
        os.path.expanduser("~"), ".claude", "jobs", "52b29cc3", "tmp", "survey_dump.json"))
    parser.add_argument("--out", default=os.path.join(HERE, "survey_view.html"))
    given = parser.parse_args()

    # Prefer the combed arms where they exist. Pooling them deepens the estimate, and the
    # agreement between them is a separate reading that depth cannot produce: a bias in the
    # construction pushes every arm the same way, a bias in one header pushes one arm, and noise
    # pushes each independently.
    import glob

    arm_paths = sorted(glob.glob(os.path.join(os.path.dirname(given.dump), "survey_arm_*.json")))
    arms = []
    for path in arm_paths:
        with io.open(path, encoding="utf-8") as handle:
            arms.append(json.load(handle))

    if len(arms) >= 3:
        samples = sum(int(a["nonces"]) for a in arms)
        counts = [sum(int(a["bits"][i]) for a in arms) for i in range(256)]
        zeros = [sum(int(a["zeros"][k]) for a in arms) for k in range(33)]
    else:
        with io.open(given.dump, encoding="utf-8") as handle:
            dump = json.load(handle)
        samples = int(dump["nonces"])
        counts = [int(v) for v in dump["bits"]]
        zeros = [int(v) for v in dump["zeros"]]

    # Deviation and its reach in whole standard errors, both exact.
    positions = []
    worst_reach = 0
    worst_at = 0
    total_squared = 0
    for index, count in enumerate(counts):
        deviation = 2 * count - samples
        reach = sigma_bucket(deviation, samples)
        total_squared += deviation * deviation
        if reach > worst_reach or (reach == worst_reach and abs(deviation) > abs(
                2 * counts[worst_at] - samples)):
            worst_reach, worst_at = reach, index
        positions.append({
            "at": index,
            "word": index // 32,
            "bit": index % 32,
            "deviation": deviation,
            "reach": reach,
            "high": deviation > 0,
        })

    # The sum of squared z, as an exact rational scaled by 10^6 so the page never divides.
    # z is (2c - N) over the square root of N, so z squared is (2c - N) squared over N and there is
    # no factor of four. An earlier version carried one and read 976.03 where the truth is 244.01,
    # which the float arm caught by disagreeing with it.
    sum_z_millionths = (total_squared * 1000000) // samples

    # The histogram against its exact expectation. Bin k expects samples / 2^k, and the comparison
    # is done by cross-multiplying rather than dividing.
    histogram = []
    for k, observed in enumerate(zeros):
        expected_numerator = samples
        denominator = 1 << k
        expected_times = expected_numerator // denominator
        if expected_times < 8:
            break
        deviation = observed * denominator - samples
        histogram.append({
            "k": k,
            "observed": observed,
            "expected": expected_times,
            "ratio_millionths": (observed * 1000000 * denominator) // samples,
        })

    # What each anchor width costs to resolve. Events at width k arrive at rate / 2^k, and settling
    # a deficit of one part in `parts` needs about 9 * parts^2 events.
    RATE = 2400000000
    sensitivity = []
    for k in (16, 20, 24, 28, 32):
        per_second = RATE >> k
        needed = 9 * 29 * 29          # a 3.45% deficit, which is 1 part in 29
        seconds = (needed // per_second) if per_second else None
        sensitivity.append({
            "width": k,
            "per_second": per_second,
            "seconds": seconds if seconds is not None else -1,
        })

    payload = {
        "samples": samples,
        "positions": positions,
        "worstAt": worst_at,
        "worstReach": worst_reach,
        "sumZMillionths": sum_z_millionths,
        "histogram": histogram,
        "sensitivity": sensitivity,
        "words": list(WORD_NAME),
    }

    with io.open(TEMPLATE, encoding="utf-8") as handle:
        page = handle.read()
    if "/*DATA*/" not in page:
        raise SystemExit("template has no /*DATA*/ placeholder: %s" % TEMPLATE)
    page = page.replace("/*DATA*/", json.dumps(payload, separators=(",", ":")))

    with io.open(given.out, "w", encoding="utf-8") as handle:
        handle.write(page)

    print("wrote %s" % given.out)
    print("  %s nonces surveyed" % format(samples, ","))
    print("  loudest position %d, reaching %d whole standard errors" % (worst_at, worst_reach))
    print("  sum of squared z: %d.%06d over 256 positions, expectation 256"
          % (sum_z_millionths // 1000000, sum_z_millionths % 1000000))
    print("  histogram bins with at least 8 expected: %d" % len(histogram))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
