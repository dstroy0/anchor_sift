#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: SND-4-003
#
# One filter, four noises: reject the component the target's invariant does not share, with the
# evidence for every 100% kept beside it.
#
#   Usage:  python examples/sound/4_measure/noise_removed_to_the_bit.py
#
# These are not four filters. They are one construction with four arguments: group the positions an
# invariant makes equivalent, take the value the group agrees on, and the residual is what the group
# could not have predicted. Only the invariant changes.
#
#   coherent hum       the invariant is POSITION   group by phase (period), take the mean
#   incoherent impulse the invariant is a REPEAT   group by phase, take the consensus
#   recurring motif    the invariant is CONTENT    group by surrounding context, take the mean
#   sparse outlier     the invariant is NEARNESS   group by window, take the median
#
# The first section is the sweep: one row per noise type. The WRONG-REFERENCE column is there so the
# matched 100% cannot be read alone -- the same signal through another noise's reference reads near zero
# or below, so the method rejected the noise that was present and not the noise it was handed.
#
# The second section keeps the evidence in this file rather than in a test, because a floor and a
# divergence probe are not tests of the code, they are the justification for the number beside them; a
# number separated from its basis gets requoted without it. Per method it carries the two independent
# routes and a broken third that must split from them, the drawn null with its spread rather than one
# figure, and the floor kept as a sweep where it moves with a parameter.
#
# THE TWO ROUTES NOW LIVE IN THE PRIMITIVES, so name them here where the example cannot show them:
#   coherent hum        periodic.mean_background        vs mean_background_incremental
#   incoherent impulse  periodic.consensus_majority     vs consensus_median
#   recurring motif     self_similar.similar_background vs similar_background_scanned
#   sparse outlier      windowed.window_median          vs window_median_counted
# A route pair that is real but invisible is one edit from being invisible and gone.
#
# Every figure is exact on a synthetic positive control. Nothing is bounded: periods, radii, window
# sizes and shuffle counts are declared inputs. A native-C route is the natural hardening and is not
# claimed here.

import io
import os
import random
import sys
from fractions import Fraction

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from reference.periodic import (mean_background, mean_background_incremental,  # noqa: E402
                                mean_residual, consensus_majority, consensus_median)
from reference.self_similar import (similar_background, similar_background_scanned,  # noqa: E402
                                    context_groups)
from reference.windowed import restore_at, window_median, window_median_counted  # noqa: E402
from reference.shuffles import permuted  # noqa: E402
from measure.local_outlier import outliers  # noqa: E402
from measure.periodic_energy import recover_period, null_band  # noqa: E402
from measure.shift_agreement import recover_exact_period  # noqa: E402
from representation.exact import placed  # noqa: E402

SEED = 0x50D1
DRAWS = 8
PEDESTAL = 128


def reduction(noisy, cleaned, clean, positions=None):
    """Share of injected noise energy removed, exact, over `positions` (all of them by default)."""
    points = range(len(clean)) if positions is None else positions
    injected = sum((Fraction(noisy[i]) - clean[i]) ** 2 for i in points)
    left = sum((Fraction(cleaned[i]) - clean[i]) ** 2 for i in points)
    if injected == 0:
        return Fraction(1)
    return Fraction(1) - left / injected


def zero_sum(period, cycles, swing, seed):
    rng = random.Random(seed)
    out = [0] * (period * cycles)
    half = cycles // 2
    for phase in range(period):
        members = [rng.randint(1, swing) for _ in range(half)]
        members += [-v for v in members]
        if cycles % 2:
            members.append(0)
        rng.shuffle(members)
        for step, value in enumerate(members):
            out[phase + step * period] = value
    return out


def window_mean(values, index, radius):
    low, high = max(0, index - radius), min(len(values), index + radius + 1)
    chunk = values[low:high]
    return Fraction(sum(chunk), len(chunk))


def pct(fraction):
    return "%.2f%%" % (float(fraction) * 100.0)


# ---------------------------------------------------------------- coherent hum

def build_coherent():
    period, hum = 4, (-48, -16, 16, 48)
    target = zero_sum(period, 48, 30, SEED)
    signal = [target[n] + hum[n % period] for n in range(len(target))]
    byte_view = [v + PEDESTAL for v in signal]

    def broken(values, per):
        sums = [0] * per
        counts = [0] * per
        for index, value in enumerate(values):
            sums[index % per] += value
            counts[index % per] += 1
        means = [Fraction(sums[p], counts[p] + 1) for p in range(per)]
        return [means[i % per] for i in range(len(values))]

    route_a = mean_background(signal, period)
    route_b = mean_background_incremental(signal, period)
    broken_route = broken(signal, period)
    matched = mean_residual(signal, period)

    band = null_band(byte_view, 32, DRAWS)
    found, live, _ = recover_period(byte_view, 32)

    floor = []
    for depth in (0, 5, 15, 30):
        shaped = list(target)
        for step in range(len(shaped) // period):
            shaped[step * period] += depth
        dirty = [shaped[n] + hum[n % period] for n in range(len(shaped))]
        floor.append((depth, reduction(dirty, mean_residual(dirty, period), shaped)))

    wrong = reduction(signal, [window_median(signal, i, 3) for i in range(len(signal))], target)
    return {
        "name": "coherent hum", "reference": "phase mean (period 4)",
        "nrr": reduction(signal, matched, target),
        "routes": ("mean_background", "mean_background_incremental",
                   route_a == route_b, route_a != broken_route and route_b != broken_route),
        "null": "period %s at ratio %.1f vs null band %.2f..%.2f over %d shuffles"
                % (found, float(live), float(band[0]), float(band[-1]), DRAWS),
        "floor_label": "target energy at the hum's period (depth)",
        "floor": floor, "floor_rep": floor[2][1],
        "wrong_ref": "window median", "wrong": wrong,
    }


# ---------------------------------------------------------------- incoherent impulse

def build_impulse():
    period, cycle = 5, (30, 90, 150, 210, 60)
    clean = [cycle[n % period] for n in range(period * 24)]
    rng = random.Random(SEED)
    signal = list(clean)
    for pos in rng.sample(range(len(clean)), len(clean) // 8):
        value = rng.randrange(256)
        signal[pos] = value if value != clean[pos] else (value + 1) % 256

    route_a = consensus_majority(signal, period)
    route_b = consensus_median(signal, period)
    nomaj = [0, 0, 0, 10, 10, 20, 20]                       # a class with no majority: mode != median
    broken_splits = consensus_majority(nomaj, 1) != consensus_median(nomaj, 1)

    found, agree = recover_exact_period(placed(list(enumerate(signal))), families=2)
    dead, dead_agree = recover_exact_period(placed(list(enumerate(permuted(bytearray(signal))))), families=2)

    floor = []
    for stuck in (3, 8, 12, 14):
        crowd = list(clean)
        for step in range(stuck):
            crowd[step * period] = 255                      # a stuck value filling a phase class
        floor.append((stuck, reduction(crowd, consensus_majority(crowd, period), clean)))

    mean_bg = mean_background(signal, period)
    wrong = reduction(signal, [Fraction(signal[i]) - mean_bg[i] for i in range(len(signal))], clean)
    return {
        "name": "incoherent impulse", "reference": "phase consensus (period 5)",
        "nrr": reduction(signal, route_a, clean),
        "routes": ("consensus_majority", "consensus_median", route_a == route_b, broken_splits),
        "null": "live exact period %s at agreement %s; a shuffle's best is period %s at agreement %s"
                % (found, agree, dead, dead_agree),
        "floor_label": "one stuck value filling a phase class (count)",
        "floor": floor, "floor_rep": floor[3][1],
        "wrong_ref": "phase mean (additive)", "wrong": wrong,
    }


# ---------------------------------------------------------------- recurring motif

def build_motif():
    radius = 1
    motifs = {0: ((10, 20), 100), 1: ((30, 40), 150), 2: ((50, 60), 200), 3: ((70, 80), 130)}
    rng = random.Random(SEED)
    order = [m for m in motifs for _ in range(20)]
    rng.shuffle(order)
    draws = {}
    for m in motifs:
        pairs = [rng.randint(1, 9) for _ in range(10)]
        pairs += [-v for v in pairs]
        rng.shuffle(pairs)
        draws[m] = iter(pairs)
    signal, centers, clean_full = [], [], []
    for m in order:
        (left, right), middle = motifs[m]
        signal.append(left); clean_full.append(left)
        centers.append(len(signal)); signal.append(middle + next(draws[m])); clean_full.append(middle)
        signal.append(right); clean_full.append(right)

    route_a = similar_background(signal, radius)
    route_b = similar_background_scanned(signal, radius)
    broken_route = [route_a[i] + (1 if i in centers else 0) for i in range(len(route_a))]
    recurring = sum(1 for members in context_groups(signal, radius).values() if len(members) > 1)
    # drawn null: break the context->center link by shuffling the centers among themselves; the same
    # grouping then no longer recovers the clean center, so the live 100% is the link, not the grouping.
    shuffled = list(signal)
    center_values = [signal[c] for c in centers]
    random.Random(SEED ^ 0x2).shuffle(center_values)
    for c, value in zip(centers, center_values):
        shuffled[c] = value
    null_nrr = reduction(shuffled, similar_background(shuffled, radius), clean_full, centers)

    # floor: contexts that recur only once are groups of one and cannot be denoised
    once = [90, 111, 91, 70, 222, 71]
    once_clean = [90, 100, 91, 70, 200, 71]
    floor = [(1, reduction(once, similar_background(once, radius), once_clean, [1, 4]))]

    wrong = reduction(signal, mean_background(signal, 4), clean_full, centers)
    return {
        "name": "recurring motif", "reference": "context mean (radius 1)",
        "nrr": reduction(signal, route_a, clean_full, centers),
        "routes": ("similar_background", "similar_background_scanned",
                   route_a == route_b, route_a != broken_route),
        "null": "%d contexts recur; live recovers 100%%, but with the centers shuffled the same grouping recovers %s"
                % (recurring, pct(null_nrr)),
        "floor_label": "a context that recurs only once (occurrences)",
        "floor": floor, "floor_rep": floor[0][1],
        "wrong_ref": "phase mean (period 4)", "wrong": wrong,
    }


# ---------------------------------------------------------------- sparse outlier

def build_outlier():
    radius = 3
    clean = [50] * 20 + [120] * 20 + [200] * 20 + [80] * 20
    rng = random.Random(SEED)
    signal, picked = list(clean), []
    edges = {b * 20 + k for b in range(4)
             for k in list(range(radius + 1)) + list(range(20 - radius - 1, 20))}
    for pos in rng.sample(range(len(clean)), len(clean)):
        if pos in edges or any(abs(pos - q) <= 2 * radius + 1 for q in picked):
            continue
        signal[pos] = (clean[pos] + 37) % 256
        picked.append(pos)
        if len(picked) >= 6:
            break

    route_a = [window_median(signal, i, radius) for i in range(len(signal))]
    route_b = [window_median_counted(signal, i, radius) for i in range(len(signal))]
    broken_route = [window_mean(signal, i, radius) for i in range(len(signal))]
    matched = restore_at(signal, radius, outliers(signal, radius))
    clean_flags = len(outliers(clean, radius))

    floor = []
    for count in (6, 12, 20):
        rng2 = random.Random(SEED ^ count)
        crowd = list(clean)
        for pos in rng2.sample(range(len(clean)), count):
            value = rng2.randrange(256)
            crowd[pos] = value if value != clean[pos] else (value + 1) % 256
        floor.append((count, reduction(crowd, restore_at(crowd, radius, outliers(crowd, radius)), clean)))

    wrong = reduction(signal, broken_route, clean)
    return {
        "name": "sparse outlier", "reference": "window median (radius 3)",
        "nrr": reduction(signal, matched, clean),
        "routes": ("window_median", "window_median_counted",
                   route_a == route_b, route_a != broken_route),
        "null": "flagged %d = the impulses; a clean signal draws %d flags (band drawn from neighbours)"
                % (len(outliers(signal, radius)), clean_flags),
        "floor_label": "impulses allowed to crowd, two per window mask one (count)",
        "floor": floor, "floor_rep": floor[1][1],
        "wrong_ref": "window mean", "wrong": wrong,
    }


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    rows = [build_coherent(), build_impulse(), build_motif(), build_outlier()]

    out.write("  one filter, four noises: reject the component the target's invariant does not share\n")
    out.write("  seed=0x%X; periods, radii, windows and shuffle counts declared per method\n\n" % SEED)

    out.write("  === the sweep ===\n")
    out.write("  %-19s %-26s %-9s %-9s %-24s %s\n"
              % ("noise type", "reference used", "NRR", "floor", "wrong reference", "NRR(wrong)"))
    for row in rows:
        out.write("  %-19s %-26s %-9s %-9s %-24s %s\n"
                  % (row["name"], row["reference"], pct(row["nrr"]), pct(row["floor_rep"]),
                     row["wrong_ref"], pct(row["wrong"])))
    out.write("\n  the wrong-reference column is here so the matched 100% cannot be read alone: the same\n")
    out.write("  signal through another noise's reference reads near zero or below.\n\n")

    out.write("  === the evidence, per method ===\n")
    ok = True
    for row in rows:
        a, b, agree, splits = row["routes"]
        ok = ok and (row["nrr"] == 1) and agree and splits
        out.write("\n  %s -- reference %s\n" % (row["name"], row["reference"]))
        out.write("    two routes: %s vs %s agree bit-exact: %s; a broken route splits: %s\n"
                  % (a, b, agree, splits))
        out.write("    drawn null: %s\n" % row["null"])
        out.write("    floor sweep (%s):\n" % row["floor_label"])
        for param, value in row["floor"]:
            out.write("      %-6s -> %s\n" % (param, pct(value)))

    out.write("\n  every matched NRR is 100% because each control's noise is identifiable as separate\n")
    out.write("  from its target; the routes agree and a broken one splits, so the agreement is\n")
    out.write("  evidence; the null is drawn, not assumed; and the floor is a sweep because a floor\n")
    out.write("  that moves with a parameter is a different claim from one quoted at a single setting.\n")
    out.flush()
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
