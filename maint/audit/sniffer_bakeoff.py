"""Which scan finds which structure: the harmonic expansion against three rivals, on planted data.

The claim under test is that spherical harmonics are the best sniffer for deciding where to point an
expensive measurement. That is testable rather than arguable: plant structures whose nature is known,
run every scan on each, and see which finds what.

Four structures, chosen so they are NOT all of one kind:

    cap         a region of the sphere over-lit. Spatial, and the harmonic's home ground.
    word        one 32-bit state word biased. Aligned to SHA's own structure, not to the sphere's.
    stride      every seventh bit index lit. Periodic in index, which the placement scatters.
    parity      bits chosen so a fixed parity is forced. Purely algebraic - no bit is individually
                biased, no region is over-lit, and nothing about it is spatial at all.

Four scans:

    harmonic    per-degree power, against a popcount-matched null
    shares      the 256 individual bit shares, loudest against its own max-of-256 bar
    walsh       the loudest parity correlation over a mask set, which is a linear functional in
                bit space rather than on the sphere
    runs        adjacent-index agreement, which sees clumping in index order

A scan that finds everything would be the answer. The expected result is that each finds its own
kind, which would mean "best sniffer" is not a property a single transform can have.
"""

import argparse
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "examples", "00_blob_viz_tools"))

import boundary_read

POINTS = 256
TOP = 8


def plant(kind, weight, rng):
    """A lit set of `weight` bits carrying one known kind of structure."""
    if kind == "none":
        return sorted(rng.sample(range(POINTS), weight))
    if kind == "cap":
        # Over-light a polar region: spatial, and invisible to anything index-based.
        places = boundary_read.golden_place(POINTS)
        ordered = sorted(range(POINTS), key=lambda i: places[i][1])
        head = ordered[: POINTS // 3]
        rest = [i for i in range(POINTS) if i not in set(head)]
        take = min(len(head), int(weight * 0.62))
        return sorted(rng.sample(head, take) + rng.sample(rest, weight - take))
    if kind == "word":
        # Bias one 32-bit word: aligned to SHA's structure, not the sphere's.
        band = list(range(64, 96))
        rest = [i for i in range(POINTS) if i not in set(band)]
        take = min(len(band), int(weight * 0.34))
        return sorted(rng.sample(band, take) + rng.sample(rest, weight - take))
    if kind == "stride":
        # Every seventh index: periodic in index, scattered by the placement.
        band = [i for i in range(POINTS) if i % 7 == 0]
        rest = [i for i in range(POINTS) if i % 7 != 0]
        take = min(len(band), int(weight * 0.42))
        return sorted(rng.sample(band, take) + rng.sample(rest, weight - take))
    if kind == "parity":
        # Force a parity over a fixed mask. No bit is individually biased and no region is
        # over-lit; the structure is purely algebraic.
        chosen = rng.sample(range(POINTS), weight)
        mask = [3, 47, 91, 150, 203]
        inside = sum(1 for i in chosen if i in mask)
        if inside % 2 == 1:
            for candidate in mask:
                if candidate in chosen:
                    chosen.remove(candidate)
                    spare = [i for i in range(POINTS) if i not in chosen and i not in mask]
                    chosen.append(rng.choice(spare))
                    break
        return sorted(chosen)
    raise ValueError(kind)


def scan_harmonic(sets, weight, rng, places, draws=160):
    """Per-degree power against a popcount-matched null. Returns the loudest z."""
    angles = boundary_read.as_angles(places)

    def power(live):
        table = boundary_read.complex_coefficients(angles, live, TOP)
        out = [0.0] * (TOP + 1)
        for (degree, order), (re, im) in table.items():
            out[degree] += (1.0 if order == 0 else 2.0) * ((re * re) + (im * im))
        return out

    real = [power(one) for one in sets]
    mean_real = [sum(row[d] for row in real) / len(real) for d in range(TOP + 1)]
    null = []
    for _ in range(draws):
        null.append(power(rng.sample(range(POINTS), weight)))
    loudest = 0.0
    for degree in range(1, TOP + 1):
        column = [row[degree] for row in null]
        middle = sum(column) / len(column)
        spread = math.sqrt(sum((v - middle) ** 2 for v in column) / len(column)) or 1.0
        z = (mean_real[degree] - middle) / (spread / math.sqrt(len(sets)))
        loudest = max(loudest, abs(z))
    return loudest


def scan_shares(sets):
    """The 256 individual bit shares, loudest against its own bar."""
    trials = len(sets)
    counts = [0] * POINTS
    for one in sets:
        for index in one:
            counts[index] += 1
    share = len(sets[0]) / float(POINTS)
    se = math.sqrt(share * (1 - share) / trials) or 1.0
    return max(abs((c / float(trials)) - share) for c in counts) / se


def scan_walsh(sets, rng, masks=400):
    """Loudest parity correlation over random sparse masks: a linear functional in bit space."""
    trials = len(sets)
    loudest = 0.0
    for _ in range(masks):
        mask = rng.sample(range(POINTS), rng.randint(2, 5))
        agree = 0
        for one in sets:
            lit = set(one)
            if sum(1 for i in mask if i in lit) % 2 == 0:
                agree += 1
        z = abs((2 * agree) - trials) / math.sqrt(trials)
        loudest = max(loudest, z)
    return loudest


def scan_runs(sets):
    """Adjacent-index agreement: clumping in index order."""
    trials = len(sets)
    total = 0
    for one in sets:
        lit = set(one)
        total += sum(1 for i in range(POINTS - 1) if (i in lit) == ((i + 1) in lit))
    share = len(sets[0]) / float(POINTS)
    expect = trials * (POINTS - 1) * ((share * share) + ((1 - share) ** 2))
    spread = math.sqrt(trials * (POINTS - 1) * 0.25) or 1.0
    return abs(total - expect) / spread


def main():
    parser = argparse.ArgumentParser(description="Which scan finds which structure.")
    parser.add_argument("--trials", type=int, default=400)
    parser.add_argument("--weight", type=int, default=110)
    given = parser.parse_args()

    rng = random.Random(0x5217)
    places = boundary_read.golden_place(POINTS)

    print("  %d sets of %d lit bits per structure, 256 positions, degree %d"
          % (given.trials, given.weight, TOP))
    print("  every cell is the loudest reading that scan produced, in standard errors")
    print()
    print("    structure   harmonic    shares     walsh      runs")
    for kind in ("none", "cap", "word", "stride", "parity"):
        sets = [plant(kind, given.weight, rng) for _ in range(given.trials)]
        row = (scan_harmonic(sets, given.weight, rng, places),
               scan_shares(sets),
               scan_walsh(sets, rng),
               scan_runs(sets))
        print("    %-10s %9.2f %9.2f %9.2f %9.2f" % (kind, row[0], row[1], row[2], row[3]))

    print()
    print("=" * 76)
    print("  READING")
    print("=" * 76)
    print()
    print("    The 'none' row is the floor every column has to clear, since each scan reports its")
    print("    own loudest over many cells and that is large by construction.")
    print()
    print("    A scan that led every row would settle the question. One that leads only its own")
    print("    kind means 'best sniffer' is not a property a single transform has, and the right")
    print("    move is to run more than one rather than to pick.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
