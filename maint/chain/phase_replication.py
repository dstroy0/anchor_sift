"""Does the daily cycle's PHASE replicate, or is it this corpus' noise wearing a clock?

WHY THIS EXISTS

`docs/version-rolling-signature.md` reports a daily cycle in block counts: 27.5 per cent peak to
trough, chi-square 36.62 on 23 degrees of freedom, p = 0.036 against a drawn multinomial null. That
part is measured, drawn rather than derived, and stated as marginal, which is correct.

The PHASE is a different claim and it carried no test at all. The document reads the trough at 18:00
to 23:00 UTC as United States afternoon peak pricing, and then builds a geography argument on it. The
amplitude's p-value says nothing about the phase: a chi-square is invariant to relabelling the bins,
so it fires identically whatever hour the trough lands in.

That matters more than usual here because the nearest retracted claim in this tree is exactly this
shape. Twenty per-pool trough hours were read as geography and turned out to sit where uniform draws
sit, p = 0.662. An amplitude with a null and a phase without one is how that happened.

THE TEST

A real daily cycle is a property of the population, so it must be there in any large enough piece of
it. A phase that is noise is a property of this particular draw and will not survive being cut.

    1. Split the corpus into halves, by time and then by parity of height.
    2. Read the trough hour and the peak hour of each half independently.
    3. Measure the circular distance between the halves' troughs.
    4. Draw the null: shuffle the hour labels within each half and repeat, many times, to get the
       distribution of that distance when there is no common phase.

Splitting by PARITY as well as by time is the arm that matters. A split by time confounds phase with
migration - if the hashrate genuinely moved between the first and second half, the troughs should
differ, and a disagreement would be evidence FOR the geography reading rather than against it. A
parity split interleaves the halves, so both see the same epochs, the same difficulty, the same
population, and any disagreement is noise with nothing else it can be.

WHAT EACH OUTCOME MEANS

    parity halves agree, time halves agree      a real phase, and a stable one
    parity halves agree, time halves differ     a real phase that MOVED, which is the interesting
                                                case and the one the geography claim wants
    parity halves differ                        no phase to speak of. The trough hour is this
                                                corpus' noise and the geography paragraph has to go

    python tools/chain/phase_replication.py
"""

import argparse
import collections
import datetime
import io
import json
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
HOURS = 24


def load(path):
    with io.open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def hour_of(block):
    """The UTC hour a block's own timestamp claims.

    The block's timestamp and not the median-time, because the question is about when the block was
    produced. The timestamp is miner-supplied and loose by up to two hours, which widens the bins
    rather than shifting them and so cannot manufacture a phase.
    """
    stamp = datetime.datetime.fromtimestamp(block["timestamp"], datetime.timezone.utc)
    return stamp.hour


def counts_of(blocks):
    out = [0] * HOURS
    for block in blocks:
        out[hour_of(block)] += 1
    return out


def trough_and_peak(counts):
    """The hour of the lowest and highest count, smoothed over three hours.

    SMOOTHED, because the statistic being replicated has to be the one the claim is about. The
    document reads a BAND - "low across 18:00 to 23:00" - not a single hour, and a bare argmin over
    24 noisy bins moves around far more than the band does. A three-hour window is the narrowest
    thing that reads a band rather than a bin.
    """
    smoothed = [(counts[(h - 1) % HOURS] + counts[h] + counts[(h + 1) % HOURS]) / 3.0
                for h in range(HOURS)]
    low = min(range(HOURS), key=lambda h: smoothed[h])
    high = max(range(HOURS), key=lambda h: smoothed[h])
    return low, high


def circular_distance(left, right):
    """Hours between two clock positions, the short way round. Zero to twelve."""
    gap = abs(left - right) % HOURS
    return min(gap, HOURS - gap)


def draw_null(first, second, trials, rng):
    """How far apart two troughs land when neither half has a phase.

    The counts are redrawn multinomially at each half's own total over uniform hours, which is the
    same null the amplitude was tested against. What comes back is the distribution of the
    trough-to-trough distance under no common cycle, and it is emphatically NOT uniform on 0..12 -
    the smoothing correlates neighbouring bins - so it has to be drawn rather than reasoned about.
    """
    totals = (sum(first), sum(second))
    spread = []
    for _ in range(trials):
        pair = []
        for total in totals:
            drawn = [0] * HOURS
            for _ in range(total):
                drawn[rng.randrange(HOURS)] += 1
            pair.append(trough_and_peak(drawn)[0])
        spread.append(circular_distance(pair[0], pair[1]))
    spread.sort()
    return spread


def report_split(name, first, second, trials, rng):
    first_counts = counts_of(first)
    second_counts = counts_of(second)
    first_low, first_high = trough_and_peak(first_counts)
    second_low, second_high = trough_and_peak(second_counts)
    apart = circular_distance(first_low, second_low)

    spread = draw_null(first_counts, second_counts, trials, rng)
    # How often chance alone puts two troughs THIS close or closer. Small means the halves agree
    # more than they should by accident, which is what a real phase looks like.
    beaten = sum(1 for value in spread if value <= apart)
    p = beaten / float(len(spread))
    middle = sum(spread) / float(len(spread))

    print("  %s" % name)
    print("    half one   %5d blocks, trough %02d:00 UTC, peak %02d:00"
          % (len(first), first_low, first_high))
    print("    half two   %5d blocks, trough %02d:00 UTC, peak %02d:00"
          % (len(second), second_low, second_high))
    print("    troughs %d hours apart; chance alone averages %.1f and is this close p = %.3f"
          % (apart, middle, p))
    print()
    return apart, p


def main():
    parser = argparse.ArgumentParser(description="Does the daily cycle's phase replicate?")
    parser.add_argument("--corpus", default=os.path.join(HERE, "blocks_deep.json"))
    parser.add_argument("--trials", type=int, default=4000)
    given = parser.parse_args()

    blocks = load(given.corpus)
    blocks = [b for b in blocks if "timestamp" in b]
    blocks.sort(key=lambda b: b["height"])
    rng = random.Random(0xDA11)

    print("=" * 78)
    print("  DOES THE DAILY CYCLE'S PHASE REPLICATE?")
    print("=" * 78)
    print()
    print("  %d blocks, heights %d to %d"
          % (len(blocks), blocks[0]["height"], blocks[-1]["height"]))
    print()

    whole = counts_of(blocks)
    low, high = trough_and_peak(whole)
    swing = (max(whole) - min(whole)) / (sum(whole) / float(HOURS)) * 100.0
    print("  WHOLE CORPUS: trough %02d:00 UTC, peak %02d:00, swing %.1f per cent"
          % (low, high, swing))
    print("  This is the reading the document interprets as geography.")
    print()
    print("-" * 78)
    print()

    # THE PARITY SPLIT IS THE ONE THAT DECIDES IT. Both halves span the same epochs and the same
    # population, so nothing but noise can separate their troughs.
    evens = [b for b in blocks if b["height"] % 2 == 0]
    odds = [b for b in blocks if b["height"] % 2 == 1]
    parity_apart, parity_p = report_split(
        "INTERLEAVED SPLIT (even against odd heights) - same epochs, same population",
        evens, odds, given.trials, rng)

    middle = len(blocks) // 2
    time_apart, time_p = report_split(
        "TIME SPLIT (first half against second) - confounds phase with migration",
        blocks[:middle], blocks[middle:], given.trials, rng)

    print("=" * 78)
    print("  WHAT THIS SETTLES")
    print("=" * 78)
    print()
    if parity_p > 0.25:
        print("    The interleaved halves put the trough %d hours apart, which is what chance does"
              % parity_apart)
        print("    (p = %.3f). Two halves of the SAME population, over the SAME epochs, do not" % parity_p)
        print("    agree on where the trough is.")
        print()
        print("    So the trough hour is not a stable property of this corpus, and the geography")
        print("    reading built on it is not supported. The AMPLITUDE result stands - it was drawn")
        print("    against a proper null and correctly called marginal - but a chi-square is")
        print("    invariant to relabelling the bins, so it never spoke to the phase at all.")
        print()
        print("    This is the same shape as the retracted per-pool phase claim, caught earlier.")
    else:
        print("    The interleaved halves agree on the trough to within %d hours, which chance"
              % parity_apart)
        print("    manages only p = %.3f of the time. The phase replicates within the corpus." % parity_p)
        print()
        if time_p > 0.25:
            print("    The time-split halves do NOT agree (p = %.3f). Since the interleaved split" % time_p)
            print("    rules out noise, a real phase that MOVED between the halves is the reading")
            print("    that survives - which is what the migration claim predicts, and it is now")
            print("    evidence for it rather than an interpretation laid over it.")
        else:
            span_days = (blocks[-1]["timestamp"] - blocks[0]["timestamp"]) / 86400.0
            print("    The time-split halves agree too (p = %.3f), so the phase is stable across"
                  % time_p)
            print("    the corpus. That supports a real, steady daily cycle.")
            print()
            print("    It says NOTHING about migration either way, and the reason is the window:")
            print("    this corpus spans %.0f days, and each half is %.0f. Mining geography moves"
                  % (span_days, span_days / 2.0))
            print("    over years. Two halves three weeks apart agreeing is what a stable phase")
            print("    looks like AND what an unmeasurably slow migration looks like, and nothing")
            print("    here separates them. The migration claim needs a corpus of years; treating")
            print("    this agreement as evidence against it would be reading absence of power as")
            print("    absence of effect.")
    print()
    print("    Either way the phase now has a test, which is the thing it was missing.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
