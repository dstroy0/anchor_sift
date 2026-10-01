#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Does the deblurred funnel survive across two seeds, or is it magnified floor noise.

    python tools/view/funnel_coherence.py --check     the controls, each able to fail
    python tools/view/funnel_coherence.py             the coherence sweep over the deblur

THE QUESTION THE FUNNEL VIS CANNOT ANSWER

The inverse boundary amplifies the high degrees, and the field erupts into funnels. A funnel is the
elision only if it is REAL, a shape the object has, and not the deblur magnifying the noise every
high degree carries. A single seed cannot tell those apart: a beautiful funnel looks the same whether
it is structure or amplified randomness.

TWO SEEDS CAN. Build the field from two independent sets of samples. A real feature is in both, at the
same place, and survives the deblur coherently. Noise is different in each set, and amplifying it
drives the two apart. So the reading is the coherence between the two seeds' fields as the deblur is
turned up: coherence that HOLDS under the deblur is a real funnel; coherence that COLLAPSES as the
deblur rises is the deblur magnifying noise.

READ PER DEGREE, BECAUSE THAT IS WHERE THE ANSWER LIVES. The deblur weights degree l by a base to the
l, so it pours its gain into the highest degrees. If the high degrees are coherent across seeds, the
funnels are real. If only the low degrees are coherent and the high ones are noise, the deblur is
building funnels out of the incoherent part, and the elision dimension is not there.

THE NULL IS DRAWN. Two fair fields deblurred the same way give the coherence chance alone produces at
each deblur strength, and a real coherence has to beat that.

WHAT IS HELD

Every number here is about the nonce and sits under the fail-closed partition as HELD.
"""

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_bend_view  # noqa: E402
import build_sha_sphere_view  # noqa: E402


def deblur(field, slices, top, base):
    """Amplify degree l of a flat field by `base` to the l, the inverse boundary's own kernel."""
    out = list(field)
    climb = 1.0
    for degree in range(top + 1):
        low, high = slices[degree]
        for index in range(low, high):
            out[index] = field[index] * climb
        climb *= base
    return out


def per_degree_coherence(first, second, slices, top):
    """The correlation between two fields at each degree above zero: where each degree agrees."""
    out = []
    for degree in range(1, top + 1):
        low, high = slices[degree]
        out.append(build_bend_view.pearson(first[low:high], second[low:high]))
    return out


def coherence_angle(first, second, slices, top, base):
    """The angle between two seeds' fields after the deblur, above degree zero. Small is coherent."""
    a = deblur(first, slices, top, base)
    b = deblur(second, slices, top, base)
    return build_bend_view.angle_between(a[1:], b[1:])


def drawn_band(basis, slices, top, base, samples, draws, seed):
    """The deblurred coherence angle two fair fields give, over `draws` pairs: the null at this deblur."""
    generator = random.Random(seed)
    angles = []
    for _ in range(draws):
        first = build_bend_view.field_of(basis, build_bend_view.fair_departures(generator, samples))
        second = build_bend_view.field_of(basis, build_bend_view.fair_departures(generator, samples))
        found = coherence_angle(first, second, slices, top, base)
        if found is not None:
            angles.append(found)
    angles.sort()
    count = len(angles)
    return (angles[int(0.025 * (count - 1))], angles[int(0.5 * (count - 1))],
            angles[int(0.975 * (count - 1))])


def _check():
    failed = 0
    lines = []

    def say(text):
        lines.append(text)

    top = 12
    directions = build_sha_sphere_view.place("spiral")
    basis = build_bend_view.source_basis(top, directions)
    slices = build_bend_view.degree_slices(top)

    generator = random.Random(5)
    shared = build_bend_view.fair_departures(generator, 4000)
    # A planted coherent field: both seeds carry the SAME shape plus their own small noise, so their
    # coherence must survive the deblur. Independent seeds must not.
    noise_a = build_bend_view.fair_departures(generator, 4000)
    noise_b = build_bend_view.fair_departures(generator, 4000)
    coherent_a = build_bend_view.field_of(basis, [s + 0.15 * n for s, n in zip(shared, noise_a)])
    coherent_b = build_bend_view.field_of(basis, [s + 0.15 * n for s, n in zip(shared, noise_b)])
    independent_a = build_bend_view.field_of(basis, noise_a)
    independent_b = build_bend_view.field_of(basis, noise_b)

    band = drawn_band(basis, slices, top, 1.6, 4000, 200, 11)
    coherent = coherence_angle(coherent_a, coherent_b, slices, top, 1.6)
    independent = coherence_angle(independent_a, independent_b, slices, top, 1.6)
    say("  under a 1.6 deblur: shared-shape seeds angle %.2f, independent seeds %.2f, null %.2f to %.2f"
        % (coherent, independent, band[0], band[2]))
    if not (coherent < band[0]):
        say("    FAIL a planted shared shape did not stay coherent under the deblur")
        failed += 1
    if not (band[0] <= independent <= band[2]):
        say("    FAIL independent seeds did not sit in the deblurred null")
        failed += 1

    say("")
    say("%d check(s) failed" % failed)
    sys.stdout.write("\n".join(lines) + "\n")
    return failed


def main(argv):
    if "--help" in argv or "-h" in argv:
        sys.stdout.write(__doc__)
        return 0
    if "--check" in argv:
        return 1 if _check() else 0

    top = 12
    samples = 4000
    round_index = 6
    if "--round" in argv:
        round_index = int(argv[argv.index("--round") + 1]) - 1
    word = 3
    if "--word" in argv:
        word = int(argv[argv.index("--word") + 1])

    directions = build_sha_sphere_view.place("spiral")
    basis = build_bend_view.source_basis(top, directions)
    slices = build_bend_view.degree_slices(top)

    first_rows = build_bend_view.departures(build_bend_view.SEED_FIRST, samples, word)
    second_rows = build_bend_view.departures(build_bend_view.SEED_SECOND, samples, word)
    first = build_bend_view.field_of(basis, first_rows[round_index])
    second = build_bend_view.field_of(basis, second_rows[round_index])

    print("  seed A against seed B at round %d, word %d, %d samples, degrees to %d"
          % (round_index + 1, word, samples, top))
    print("  a funnel is real if its coherence HOLDS as the deblur rises; noise collapses to the null")
    print("")
    print("  %8s %14s %22s %10s" % ("deblur", "coherence deg", "null band", "verdict"))
    for base in (1.0, 1.2, 1.4, 1.6, 1.8, 2.0):
        live = coherence_angle(first, second, slices, top, base)
        band = drawn_band(basis, slices, top, base, samples, 200, 1000 + int(base * 10))
        verdict = "coherent" if (live is not None and live < band[0]) else "noise" if (live is not None and live > band[2]) else "in band"
        print("  %8.1f %14s %10s to %.1f %10s"
              % (base, "-" if live is None else "%.2f" % live, "%.1f" % band[0], band[2], verdict))

    print("")
    print("  per-degree coherence, seed A against seed B, at this round (1.0 agrees, 0 is noise):")
    degree_coherence = per_degree_coherence(first, second, slices, top)
    for degree in range(1, top + 1):
        value = degree_coherence[degree - 1]
        bar = "" if value is None else ("#" * max(0, int(value * 20)))
        print("    degree %2d  %6s  %s" % (degree, "-" if value is None else "%.3f" % value, bar))
    print("")
    print("  the deblur pours its gain into the highest degrees. If those degrees read near zero here,")
    print("  the funnels they build are magnified noise, and the elision dimension is not in this round.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
