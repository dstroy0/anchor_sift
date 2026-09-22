"""Do pools disagree about the hour, or does the statistic disagree with itself?

An earlier version of this test compared each pool's peak-minus-trough against two Poisson floors
and reported that eight pools cleared it and their troughs spanned twenty hours. Both halves of that
were artifacts.

Peak minus trough is a maximum minus a minimum over twenty-four bins, and that spans three and a
half to four and a half standard deviations for pure noise, by construction. A bar set at two, or
even at four, is at or below what chance produces, so every pool clears it. And eight trough hours
drawn uniformly from twenty-four span about nineteen hours on average, so a twenty hour spread is
the expected result of no signal at all, not evidence against it.

The correct question is asked here in two stages, each against a null built at that pool's own
sample size:

  is the pool non-uniform     chi-square on its own 24 hourly counts, against a multinomial null
                              drawn at that pool's n. Only pools that clear this have a phase.
  do the phases differ        for the pools that clear, whether their trough hours are further
                              apart than the same number of uniform draws would be

The second stage is only meaningful on pools that pass the first, which is the step the earlier
version skipped.
"""

import argparse
import io
import json
import math
import os
import random

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT = os.path.join(HERE, "blocks_labelled.json")


def chi_square(counts):
    expect = sum(counts) / float(len(counts))
    if expect <= 0:
        return 0.0
    return sum((c - expect) ** 2 / expect for c in counts)


def multinomial_null(total, bins, draws, rng):
    out = []
    for _ in range(draws):
        counts = [0] * bins
        for _ in range(total):
            counts[rng.randrange(bins)] += 1
        out.append(chi_square(counts))
    return sorted(out)


def main():
    parser = argparse.ArgumentParser(description="Per-pool daily phase, properly nulled.")
    parser.add_argument("--corpus", default=DEFAULT)
    parser.add_argument("--min-blocks", type=int, default=60)
    given = parser.parse_args()

    with io.open(given.corpus, encoding="utf-8") as handle:
        blocks = json.load(handle)
    named = [b for b in blocks if b.get("pool")]
    rng = random.Random(0x7A5E)

    groups = {}
    for block in named:
        groups.setdefault(block["pool"], []).append(int(block["timestamp"]))
    usable = {k: v for k, v in groups.items() if len(v) >= given.min_blocks}

    print("  %d blocks, %d pools, %d with at least %d blocks"
          % (len(named), len(groups), len(usable), given.min_blocks))
    print()
    print("=" * 78)
    print("  STAGE 1  -  is each pool's own hourly spread beyond its own null?")
    print("=" * 78)
    print()
    print("    pool                     n    chi-square   null 95th   p        trough")

    passed = []
    for name in sorted(usable, key=lambda k: -len(usable[k])):
        stamps = usable[name]
        hours = [0] * 24
        for stamp in stamps:
            hours[(stamp // 3600) % 24] += 1
        observed = chi_square(hours)
        null = multinomial_null(len(stamps), 24, 600, rng)
        beat = sum(1 for v in null if v >= observed)
        p = beat / float(len(null))
        trough = min(range(24), key=lambda h: hours[h])
        flag = ""
        if p <= 0.05:
            passed.append((name, trough, p))
            flag = "   <- clears"
        print("    %-22s %5d   %9.2f   %9.2f   %.3f    %02d:00%s"
              % (name[:22], len(stamps), observed, null[int(0.95 * len(null))], p, trough, flag))

    print()
    print("    %d of %d pools clear their own null." % (len(passed), len(usable)))
    print("    At p = 0.05 over %d pools, chance alone produces about %.1f."
          % (len(usable), 0.05 * len(usable)))

    print()
    print("=" * 78)
    print("  STAGE 2  -  do the phases of those pools differ beyond chance?")
    print("=" * 78)
    print()
    if len(passed) < 3:
        print("    Fewer than three pools carry a phase at all, so there is nothing to compare.")
        print("    The geography claim is not supported and is not refuted; this corpus cannot")
        print("    address it. A deeper labelled corpus is what the question needs.")
        return 0

    troughs = [t for _, t, _ in passed]
    print("    pools carrying a phase: %s" % ", ".join(n for n, _, _ in passed))
    print("    their trough hours:     %s" % sorted(troughs))

    # Circular spread: hours wrap, so a plain max-minus-min is the wrong measure. The resultant
    # length of unit vectors at each hour is the right one - near 1 is agreement, near 0 is spread.
    def resultant(hours_list):
        x = sum(math.cos(h / 24.0 * 2 * math.pi) for h in hours_list)
        y = sum(math.sin(h / 24.0 * 2 * math.pi) for h in hours_list)
        return math.sqrt(x * x + y * y) / len(hours_list)

    observed = resultant(troughs)
    draws = []
    for _ in range(4000):
        draws.append(resultant([rng.randrange(24) for _ in troughs]))
    draws.sort()
    below = sum(1 for v in draws if v <= observed)
    print()
    print("    circular concentration of those troughs: %.4f" % observed)
    print("    uniform draws of the same count:         %.4f (5th pct %.4f, 95th %.4f)"
          % (sum(draws) / len(draws), draws[int(0.05 * len(draws))], draws[int(0.95 * len(draws))]))
    print("    draws at or below observed: %d of 4000  ->  p = %.4f" % (below, below / 4000.0))
    print()
    if below <= 200:
        print("    -> the troughs are MORE spread than chance. Pools genuinely disagree about the")
        print("       hour, which is regional and which a global cause cannot produce.")
    elif below >= 3800:
        print("    -> the troughs are MORE clustered than chance. Pools agree about the hour, so")
        print("       the cycle is global and longitude explains nothing extra.")
    else:
        print("    -> the troughs sit where uniform draws sit. This corpus cannot distinguish a")
        print("       regional cycle from a global one, or from no cycle at all.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
