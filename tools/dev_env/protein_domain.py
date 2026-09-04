#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Run the anchor cascade on a protein structure in three dimensions, for Section 4.2 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/protein_domain.py
#
# Section 4.2 holds the invariant over thirteen geometries and dimensions one to eight, and it was
# measured on generated point sets. A protein is that case occurring in nature: an irregular cloud of
# points in three dimensions, each carrying a value.
#
# Projecting it to a sequence would measure the projection. The construction does not need one. A pattern
# here is a set of displacements in three dimensions together with the value expected at each, and an
# alignment survives when every displacement lands on a point holding the value asked for. That is
# Proposition 1 with no order, no raster and no alphabet assumption, which is the form the propositions
# were stated in.
#
# The null is built by deletion, as everywhere else here, and which property it deletes is the whole of
# the question. Shuffling the values among fixed points deletes composition and keeps geometry, and a
# protein is ordered geometrically, so that null cancels the structure. Scattering the points and keeping
# the values deletes geometry instead, and that is the one that shows it.

import os
import random
import statistics
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BASE = "https://files.rcsb.org/download/%s.pdb"
AGENT = {"User-Agent": "MMgr-research/1.0 (https://github.com/dstroy0/MMgr; dquigg123@gmail.com)"}

WANTED = ("1AON",)

VOXEL = 2.0
ANCHORS = int(os.environ.get("PROT_ANCHORS", "3"))
NEEDLE = 12
TOLERANCE = int(os.environ.get("PROT_TOL", "1"))
TRIALS = 60
NULL_MODE = os.environ.get("PROT_NULL", "values")


def alpha_carbons(text):
    """Voxel coordinate and residue name for every alpha carbon in the file."""
    out = []
    for line in text.splitlines():
        if (not line.startswith("ATOM")) or line[12:16].strip() != "CA":
            continue
        try:
            x = float(line[30:38])
            y = float(line[38:46])
            z = float(line[46:54])
        except ValueError:
            continue
        out.append(((int(x / VOXEL), int(y / VOXEL), int(z / VOXEL)), line[17:20].strip()))
    return out


def near_match(places, key, offset, value):
    """Whether a point holding `value` sits within TOLERANCE voxels of the displaced position.

    Exact equality is the wrong test on a continuous domain. Coordinates are real numbers, so two
    occurrences of one structural motif never land on identical voxel offsets and only the seed ever
    matches. Proposition 1 survives the change: a point lying within a distance of every displacement is
    still a necessary condition, and dropping some of those conditions still leaves a necessary one.
    """
    base = (key[0] + offset[0], key[1] + offset[1], key[2] + offset[2])
    for dx in range(-TOLERANCE, TOLERANCE + 1):
        for dy in range(-TOLERANCE, TOLERANCE + 1):
            for dz in range(-TOLERANCE, TOLERANCE + 1):
                if places.get((base[0] + dx, base[1] + dy, base[2] + dz)) == value:
                    return True
    return False


def cascade(cloud, rng, shuffled):
    """Survivors of a three dimensional anchor cascade, against the product of the anchor rates."""
    places = dict(cloud)
    if shuffled and NULL_MODE == "values":
        # Deletes which residue sits where and leaves every coordinate alone. That is the wrong property
        # to remove here: the rules a protein obeys, backbone angles and secondary structure and bond
        # lengths, constrain where the points are. This null keeps all of it, so it appears in both arms
        # and cancels
        keys = list(places)
        values = [places[key] for key in keys]
        rng.shuffle(values)
        places = dict(zip(keys, values))
    elif shuffled:
        # Deletes the geometry and keeps the composition, by scattering the same values over the same
        # bounding box. What the fold constrains is then present in one arm and absent from the other
        keys = list(places)
        lows = [min(key[axis] for key in keys) for axis in range(3)]
        highs = [max(key[axis] for key in keys) for axis in range(3)]
        scattered = {}
        for key in keys:
            for _ in range(64):
                spot = tuple(rng.randint(lows[axis], highs[axis]) for axis in range(3))
                if spot not in scattered:
                    scattered[spot] = places[key]
                    break
        places = scattered

    keys = list(places)
    counts = {}
    for value in places.values():
        counts[value] = counts.get(value, 0) + 1
    total = float(len(keys))

    ratios = []
    for _ in range(TRIALS):
        seed = keys[rng.randrange(len(keys))]
        # A needle is a set of displacements from one point, taken from points actually nearby, so the
        # pattern is a shape the domain contains and not an arbitrary offset into empty space
        near = [key for key in keys
                if 0 < max(abs(key[0] - seed[0]), abs(key[1] - seed[1]), abs(key[2] - seed[2])) <= NEEDLE]
        if len(near) < ANCHORS:
            continue
        picked = rng.sample(near, ANCHORS)
        offsets = [(point[0] - seed[0], point[1] - seed[1], point[2] - seed[2]) for point in picked]
        wanted = [places[point] for point in picked]

        predicted = total
        for value in wanted:
            predicted *= counts[value] / total
        if predicted <= 0.0:
            continue

        survivors = 0
        for key in keys:
            for offset, value in zip(offsets, wanted):
                if not near_match(places, key, offset, value):
                    break
            else:
                survivors += 1
        # The seed itself always survives, so only what is beyond it is evidence
        ratios.append(max(survivors - 1, 0) / predicted)

    return ratios


def main():
    print("  %-10s %-9s %-11s %-11s %s"
          % ("entry", "points", "live median", "null median", "live / null"))

    for index, entry in enumerate(WANTED):
        if index:
            time.sleep(1.5)
        try:
            request = urllib.request.Request(BASE % entry, headers=AGENT)
            with urllib.request.urlopen(request, timeout=240) as response:
                text = response.read().decode("utf-8", "replace")
        except Exception as trouble:
            print("  %-10s could not fetch: %s" % (entry, str(trouble)[:50]))
            continue

        cloud = alpha_carbons(text)
        if len(cloud) < 800:
            print("  %-10s %-9d too few points" % (entry, len(cloud)))
            continue

        live = cascade(cloud, random.Random(0xC0FFEE), False)
        null = cascade(cloud, random.Random(0xC0FFEE), True)
        if (not live) or (not null):
            print("  %-10s %-9d no usable needles" % (entry, len(cloud)))
            continue

        live_mid = statistics.median(live)
        null_mid = statistics.median(null)
        share = (live_mid / null_mid) if null_mid > 0 else float("inf")
        print("  %-10s %-9d %-11.3f %-11.3f %.3f"
              % (entry, len(cloud), live_mid, null_mid, share))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
