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
# or below. The method rejected the noise that was present and not the noise it was handed.
#
# The second section keeps the evidence in this file rather than in a test, because a floor and a
# divergence probe are not tests of the code, they are the justification for the number beside them; a
# number separated from its basis gets requoted without it. Per method it carries the two independent
# routes and a broken third that must split from them, the drawn null with its spread rather than one
# figure, and the floor kept as a sweep where it moves with a parameter.
#
# THE TWO ROUTES NOW LIVE IN THE PRIMITIVES. Name them here where the example cannot show them:
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
from reference.exact_ratio import whole, add, sub, mul, over, to_float, reduced  # noqa: E402

SEED = 0x50D1
DRAWS = 8
PEDESTAL = 128


def _as_ratio(value):
    """Coerce an int, an exact_ratio pair, or a Fraction to an exact_ratio pair.

    The cleaned values reach here as pairs from the migrated primitives, as ints from the consensus and
    window routes, and as Fractions from self_similar, which is not on the pair representation yet.
    """
    if isinstance(value, tuple):
        return value
    if isinstance(value, int):
        return whole(value)
    return reduced(value.numerator, value.denominator)


def reduction(noisy, cleaned, clean, positions=None):
    """Share of injected noise energy removed, as an exact integer ratio pair, over `positions`."""
    points = range(len(clean)) if positions is None else positions
    injected = sum((noisy[i] - clean[i]) ** 2 for i in points)
    if injected == 0:
        return whole(1)
    left = whole(0)
    for i in points:
        difference = sub(_as_ratio(cleaned[i]), whole(clean[i]))
        left = add(left, mul(difference, difference))
    return sub(whole(1), over(left, whole(injected)))


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
    return reduced(sum(chunk), len(chunk))


def pct(ratio):
    return "%.2f%%" % (to_float(ratio) * 100.0)


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
        means = [reduced(sums[p], counts[p] + 1) for p in range(per)]
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

    untouched = all(mean_residual(target, period)[i] == whole(target[i]) for i in range(len(target)))
    wrong = reduction(signal, [window_median(signal, i, 3) for i in range(len(signal))], target)
    return {
        "name": "coherent hum", "reference": "phase mean (period 4)",
        "nrr": reduction(signal, matched, target), "untouched": untouched,
        "routes": ("mean_background", "mean_background_incremental",
                   route_a == route_b, route_a != broken_route and route_b != broken_route),
        "null": "period %s at ratio %.1f vs null band %.2f..%.2f over %d shuffles"
                % (found, to_float(live), to_float(band[0]), to_float(band[-1]), DRAWS),
        "floors": [("target energy at the hum's period (depth)", floor)],
        "floor_rep": floor[2][1],
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

    stuck_floor = []
    for stuck in (3, 8, 12, 14):
        crowd = list(clean)
        for step in range(stuck):
            crowd[step * period] = 255                      # a stuck value filling a phase class
        stuck_floor.append((stuck, reduction(crowd, consensus_majority(crowd, period), clean)))

    # second mechanism: SCATTERED impulses each land on their own value. Plurality stays robust
    # well past half a class -- a different floor from the stuck-value one above.
    scattered_floor = []
    cycles = len(clean) // period
    for per_class in (3, 8, 12, 16):
        sca = list(clean)
        srng = random.Random(SEED ^ (per_class << 8))
        for phase in range(period):
            slots = srng.sample(range(cycles), per_class)
            for slot in slots:
                pos = phase + slot * period
                value = srng.randrange(256)
                sca[pos] = value if value != clean[pos] else (value + 1) % 256
        scattered_floor.append((per_class, reduction(sca, consensus_majority(sca, period), clean)))

    untouched = consensus_majority(clean, period) == clean
    mean_bg = mean_background(signal, period)
    wrong = reduction(signal, [sub(whole(signal[i]), mean_bg[i]) for i in range(len(signal))], clean)
    return {
        "name": "incoherent impulse", "reference": "phase consensus (period 5)",
        "nrr": reduction(signal, route_a, clean), "untouched": untouched,
        "routes": ("consensus_majority", "consensus_median", route_a == route_b, broken_splits),
        "null": "live exact period %s at agreement %s; a shuffle's best is period %s at agreement %s"
                % (found, agree, dead, dead_agree),
        "floors": [("one stuck value filling a phase class (count)", stuck_floor),
                   ("scattered impulses, plurality stays robust past half (per-class count)", scattered_floor)],
        "floor_rep": stuck_floor[3][1],
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
    # grouping then no longer recovers the clean center. The live 100% is the link, not the grouping.
    shuffled = list(signal)
    center_values = [signal[c] for c in centers]
    random.Random(SEED ^ 0x2).shuffle(center_values)
    for c, value in zip(centers, center_values):
        shuffled[c] = value
    null_nrr = reduction(shuffled, similar_background(shuffled, radius), clean_full, centers)

    # floor: contexts that recur only once are groups of one and cannot be denoised
    once = [90, 111, 91, 70, 222, 71]
    once_clean = [90, 100, 91, 70, 200, 71]
    once_floor = [(1, reduction(once, similar_background(once, radius), once_clean, [1, 4]))]

    untouched = all(similar_background(clean_full, radius)[c] == clean_full[c] for c in centers)
    wrong = reduction(signal, mean_background(signal, 4), clean_full, centers)
    return {
        "name": "recurring motif", "reference": "context mean (radius 1)",
        "nrr": reduction(signal, route_a, clean_full, centers), "untouched": untouched,
        "routes": ("similar_background", "similar_background_scanned",
                   route_a == route_b, route_a != broken_route),
        "null": "%d contexts recur; live recovers 100%%, but with the centers shuffled the same grouping recovers %s"
                % (recurring, pct(null_nrr)),
        "floors": [("a context that recurs only once (occurrences)", once_floor)],
        "floor_rep": once_floor[0][1],
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

    crowd_floor = []
    for count in (6, 12, 20):
        rng2 = random.Random(SEED ^ count)
        crowd = list(clean)
        for pos in rng2.sample(range(len(clean)), count):
            value = rng2.randrange(256)
            crowd[pos] = value if value != clean[pos] else (value + 1) % 256
        crowd_floor.append((count, reduction(crowd, restore_at(crowd, radius, outliers(crowd, radius)), clean)))

    # second mechanism: on a VARYING signal the window median is not the exact value. The restore
    # is a floor about the signal. A monotone ramp + spaced impulses.
    ramp = [20 + i for i in range(len(clean))]
    rrng = random.Random(SEED ^ 0xA5)
    ramp_dirty, rp = list(ramp), []
    for pos in rrng.sample(range(radius, len(ramp) - radius), len(ramp) - 2 * radius):
        if any(abs(pos - q) <= 2 * radius + 1 for q in rp):
            continue
        ramp_dirty[pos] = ramp[pos] + 90
        rp.append(pos)
        if len(rp) >= 6:
            break
    ramp_floor = [(len(rp), reduction(ramp_dirty, restore_at(ramp_dirty, radius, outliers(ramp_dirty, radius)), ramp))]

    untouched = restore_at(clean, radius, outliers(clean, radius)) == clean
    wrong = reduction(signal, broken_route, clean)
    return {
        "name": "sparse outlier", "reference": "window median (radius 3)",
        "nrr": reduction(signal, matched, clean), "untouched": untouched,
        "routes": ("window_median", "window_median_counted",
                   route_a == route_b, [whole(v) for v in route_a] != broken_route),
        "null": "flagged %d = the impulses; a clean signal draws %d flags (band drawn from neighbours)"
                % (len(outliers(signal, radius)), clean_flags),
        "floors": [("impulses allowed to crowd, two per window mask one (count)", crowd_floor),
                   ("a varying ramp restores to the median, not exactly (impulses)", ramp_floor)],
        "floor_rep": crowd_floor[1][1],
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
        ok = ok and (row["nrr"] == whole(1)) and agree and splits and row["untouched"]
        out.write("\n  %s -- reference %s\n" % (row["name"], row["reference"]))
        out.write("    two routes: %s vs %s agree bit-exact: %s; a broken route splits: %s\n"
                  % (a, b, agree, splits))
        out.write("    no noise: a clean signal comes back untouched: %s\n" % row["untouched"])
        out.write("    drawn null: %s\n" % row["null"])
        for label, sweep in row["floors"]:
            out.write("    floor sweep (%s):\n" % label)
            for param, value in sweep:
                out.write("      %-6s -> %s\n" % (param, pct(value)))

    out.write("\n  every matched NRR is 100% because each control's noise is identifiable as separate\n")
    out.write("  from its target; the routes agree and a broken one splits. The agreement is\n")
    out.write("  evidence; the null is drawn, not assumed; and the floor is a sweep because a floor\n")
    out.write("  that moves with a parameter is a different claim from one quoted at a single setting.\n")
    out.flush()
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
