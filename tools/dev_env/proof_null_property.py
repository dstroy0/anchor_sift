#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Proof of the posit that a constructed null must delete the property being asked about, from the posits
# section of docs/research/anchor-sift-ledger.md.
#
#   Usage:  python tools/dev_env/proof_null_property.py
#
# The posit came from one domain. Protein structures gave 1.066 against a null that shuffled the values
# among fixed points and 2.512 against one that scattered the points and kept the values, on the same
# live arm. That is one case, and a rule inferred from the case that suggested it is a hypothesis.
#
# Proving it needs domains where the answer is known by construction instead of inferred, so four are
# built here. A sparse cloud carries two independent properties, where its points sit and what each
# holds, and either can be ordered or not:
#
#   lattice + pattern    both ordered
#   lattice + random     only the geometry
#   scatter + pattern    only the values
#   scatter + random     neither
#
# The prediction is exact. A null that permutes values among fixed points can only reveal order in the
# values, and a null that moves the points can only reveal order in the geometry. So the value null fires
# on the two rows with a pattern and the position null on the two rows with a lattice, and any hit off
# that diagonal refutes the posit.

import io
import random
import statistics

SIDE = 26
SPACING = 3
VALUES = 4
ANCHORS = 2
NEEDLE = 9
TOLERANCE = 1
TRIALS = 40


def build(ordered_positions, ordered_values, rng):
    """A sparse cloud of points carrying values, with each property ordered or not as asked."""
    places = {}
    if ordered_positions:
        spots = [(x * SPACING, y * SPACING, z * SPACING)
                 for x in range(SIDE) for y in range(SIDE) for z in range(SIDE)]
    else:
        span = SIDE * SPACING
        spots = []
        seen = set()
        while len(spots) < SIDE ** 3:
            spot = (rng.randrange(span), rng.randrange(span), rng.randrange(span))
            if spot not in seen:
                seen.add(spot)
                spots.append(spot)

    for spot in spots:
        if ordered_values:
            # Value determined by where the point is, which is order in the values and nothing else
            places[spot] = ((spot[0] + spot[1] + spot[2]) // SPACING) % VALUES
        else:
            places[spot] = rng.randrange(VALUES)
    return places


def value_null(places, rng):
    keys = list(places)
    values = [places[key] for key in keys]
    rng.shuffle(values)
    return dict(zip(keys, values))


def position_null(places, rng):
    keys = list(places)
    span = SIDE * SPACING
    out = {}
    for key in keys:
        for _ in range(64):
            spot = (rng.randrange(span), rng.randrange(span), rng.randrange(span))
            if spot not in out:
                out[spot] = places[key]
                break
    return out


def near(places, key, offset, value):
    base = (key[0] + offset[0], key[1] + offset[1], key[2] + offset[2])
    for dx in range(-TOLERANCE, TOLERANCE + 1):
        for dy in range(-TOLERANCE, TOLERANCE + 1):
            for dz in range(-TOLERANCE, TOLERANCE + 1):
                if places.get((base[0] + dx, base[1] + dy, base[2] + dz)) == value:
                    return True
    return False


def score(places, rng):
    keys = list(places)
    counts = {}
    for value in places.values():
        counts[value] = counts.get(value, 0) + 1
    total = float(len(keys))

    ratios = []
    for _ in range(TRIALS):
        seed = keys[rng.randrange(len(keys))]
        close = [key for key in keys
                 if 0 < max(abs(key[0] - seed[0]), abs(key[1] - seed[1]),
                            abs(key[2] - seed[2])) <= NEEDLE]
        if len(close) < ANCHORS:
            continue
        picked = rng.sample(close, ANCHORS)
        offsets = [(p[0] - seed[0], p[1] - seed[1], p[2] - seed[2]) for p in picked]
        wanted = [places[p] for p in picked]

        predicted = total
        for value in wanted:
            predicted *= counts[value] / total
        if predicted <= 0.0:
            continue

        survivors = 0
        for key in keys:
            for offset, value in zip(offsets, wanted):
                if not near(places, key, offset, value):
                    break
            else:
                survivors += 1
        ratios.append(max(survivors - 1, 0) / predicted)
    return statistics.median(ratios) if ratios else float("nan")


def main():
    out = io.TextIOWrapper(__import__("sys").stdout.buffer, encoding="utf-8", newline="")
    out.write("  %-22s %-9s %-11s %-11s %s\n"
              % ("domain", "live", "value null", "position null", "which null fires"))

    cases = (
        ("lattice + pattern", True, True),
        ("lattice + random", True, False),
        ("scatter + pattern", False, True),
        ("scatter + random", False, False),
    )

    for label, ordered_positions, ordered_values in cases:
        places = build(ordered_positions, ordered_values, random.Random(0xA11CE))
        live = score(places, random.Random(0xB0B))
        by_value = score(value_null(places, random.Random(0xC0DE)), random.Random(0xB0B))
        by_position = score(position_null(places, random.Random(0xC0DE)), random.Random(0xB0B))

        fires = []
        if by_value > 0 and live / by_value > 1.25:
            fires.append("value")
        if by_position > 0 and live / by_position > 1.25:
            fires.append("position")
        out.write("  %-22s %-9.3f %-11.3f %-11.3f %s\n"
                  % (label, live, by_value, by_position, ", ".join(fires) or "neither"))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
