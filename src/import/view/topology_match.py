#!/usr/bin/env python3
# PQC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Match a round's surface topology across two independent seeds, with rotation taken away, and read the delta.

    python tools/view/topology_match.py --check            the controls, each able to fail
    python tools/view/topology_match.py                    every round, seed A against seed B
    python tools/view/topology_match.py --word 3 --draws 300

  --samples   random blocks per seed. Default 4000.
  --degrees   highest harmonic degree carried. Default 12.
  --draws     pairs of fair rounds drawn for every null. Default 200.
  --word      flip only bits of this message word, 0 to 15. Default: any of the 512 bits.

THE QUESTION

build_bend_view.py showed that past about round 20 a round's shape does not point the same way when
it is measured twice. That leaves open whether the two measurements hold the same STRUCTURE at a
different orientation. Topology is where that would show: the peaks and pits of a surface, and how
they sit relative to one another, survive any rotation of the whole.

THREE READINGS, EACH AGAINST ITS OWN DRAWN NULL

    peak spacing    the angles between every pair of peaks in seed A against the same in seed B, as
                    a two-sample Kolmogorov-Smirnov distance. Pairwise angles do not change under
                    rotation, so no alignment is searched and no tolerance is set.

                    NOT CALIBRATED, AND ITS VERDICTS ARE NOT TO BE READ. Its null is drawn from fair
                    fields, which carry 15 to 25 peaks at degree 12, while a structured round carries
                    7 to 11. A Kolmogorov-Smirnov distance over fewer pair angles is noisier, so the
                    null is too narrow for exactly the rounds that matter. Measured 2026-09-16: any
                    bit reported "farther" at rounds 11 to 17, inside the window where the aligned
                    delta has the two seeds at 0.09 to 0.21. The fix is a null matched on peak count,
                    and until it lands the delta and the alignment carry the reading.
    alignment       the rotation that best carries A's peaks onto B's, scored by the symmetric mean
                    nearest-peak distance. Lower is closer. No matching radius is picked.
    delta           seed A rotated by that alignment, minus seed B, both scaled to unit size, as an
                    area-weighted norm. Zero is the same surface; unrelated surfaces sit near the
                    square root of two.

Every null is drawn: rounds of fair bits, exact binomial counts, pushed through the same placement
and kernel as the measurement, and run through the same three readings. A reading means something
only where it leaves that band.

THE GRID FOLLOWS FROM THE BAND LIMIT

Critical points are found on a latitude by longitude grid with four latitudes per degree carried and
two longitudes per latitude. A field limited to degree L varies on scales no finer than about pi / L,
so four samples a degree resolves it without a resolution being chosen by eye. Neighbors are the
eight surrounding samples, with longitude wrapping and the pole rows meeting across the pole.

WHAT IS HELD

Every number this writes is about SHA-256 and sits under the fail-closed partition as HELD.
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
import sphere_field  # noqa: E402

SEED_NULL = 31


def as_rows(flat, top):
    """Flat coefficients back into the per-degree rows sphere_field.synthesize reads."""
    rows = []
    for degree in range(top + 1):
        low = degree * degree
        rows.append(list(flat[low:low + 2 * degree + 1]))
    return rows


class Grid(object):
    """The sampling grid, its unit vectors and area weights, sized from the band limit."""

    def __init__(self, top):
        self.top = top
        self.latitudes = 4 * top
        self.longitudes = 2 * self.latitudes
        self.vectors = []
        self.weights = []
        for row in range(self.latitudes):
            colatitude = math.pi * (row + 0.5) / self.latitudes
            for column in range(self.longitudes):
                longitude = 2.0 * math.pi * column / self.longitudes
                self.vectors.append((math.sin(colatitude) * math.cos(longitude),
                                     math.sin(colatitude) * math.sin(longitude),
                                     math.cos(colatitude)))
                self.weights.append(math.sin(colatitude))

    def values(self, flat):
        """The shape on the grid, degree zero removed, scaled to unit area-weighted norm."""
        shape = list(flat)
        shape[0] = 0.0
        grid = sphere_field.synthesize(as_rows(shape, self.top), self.top,
                                       self.latitudes, self.longitudes)
        out = [value for line in grid for value in line]
        norm = math.sqrt(sum(weight * value * value for weight, value in zip(self.weights, out)))
        if norm == 0.0:
            return out
        return [value / norm for value in out]

    def neighbors(self, row, column):
        """The eight samples around one, longitude wrapping and the pole rows meeting across the pole."""
        out = []
        half = self.longitudes // 2
        for row_step in (-1, 0, 1):
            for column_step in (-1, 0, 1):
                if row_step == 0 and column_step == 0:
                    continue
                next_row = row + row_step
                next_column = column + column_step
                if next_row < 0:
                    next_row = 0
                    next_column += half
                elif next_row >= self.latitudes:
                    next_row = self.latitudes - 1
                    next_column += half
                out.append(next_row * self.longitudes + next_column % self.longitudes)
        return out

    def critical(self, values):
        """Indices of strict local maxima and strict local minima."""
        peaks, pits = [], []
        for row in range(self.latitudes):
            for column in range(self.longitudes):
                here = row * self.longitudes + column
                around = [values[index] for index in self.neighbors(row, column)]
                if values[here] > max(around):
                    peaks.append(here)
                elif values[here] < min(around):
                    pits.append(here)
        return peaks, pits

    def sample(self, values, vector):
        """The grid's values at an arbitrary direction, bilinear in colatitude and longitude."""
        colatitude = math.acos(max(-1.0, min(1.0, vector[2])))
        longitude = math.atan2(vector[1], vector[0]) % (2.0 * math.pi)
        row_position = colatitude * self.latitudes / math.pi - 0.5
        column_position = longitude * self.longitudes / (2.0 * math.pi)
        row_low = int(math.floor(row_position))
        row_fraction = row_position - row_low
        row_low = max(0, min(self.latitudes - 1, row_low))
        row_high = max(0, min(self.latitudes - 1, row_low + 1))
        column_low = int(math.floor(column_position))
        column_fraction = column_position - column_low
        column_low %= self.longitudes
        column_high = (column_low + 1) % self.longitudes

        def at(row, column):
            return values[row * self.longitudes + column]

        upper = at(row_low, column_low) * (1 - column_fraction) + at(row_low, column_high) * column_fraction
        lower = at(row_high, column_low) * (1 - column_fraction) + at(row_high, column_high) * column_fraction
        return upper * (1 - row_fraction) + lower * row_fraction


def dot(first, second):
    return first[0] * second[0] + first[1] * second[1] + first[2] * second[2]


def cross(first, second):
    return (first[1] * second[2] - first[2] * second[1],
            first[2] * second[0] - first[0] * second[2],
            first[0] * second[1] - first[1] * second[0])


def normalized(vector):
    length = math.sqrt(dot(vector, vector))
    if length == 0.0:
        return None
    return (vector[0] / length, vector[1] / length, vector[2] / length)


def frame(first, second):
    """An orthonormal frame whose first axis is `first` and whose plane holds `second`, as columns."""
    axis_one = normalized(first)
    axis_three = normalized(cross(first, second))
    if axis_one is None or axis_three is None:
        return None
    axis_two = cross(axis_three, axis_one)
    return (axis_one, axis_two, axis_three)


def rotation_between(source_pair, target_pair):
    """The rotation carrying the source frame onto the target frame, as three rows."""
    source = frame(*source_pair)
    target = frame(*target_pair)
    if source is None or target is None:
        return None
    rows = []
    for row in range(3):
        rows.append(tuple(sum(target[axis][row] * source[axis][column] for axis in range(3))
                          for column in range(3)))
    return tuple(rows)


def apply(rotation, vector):
    return (dot(rotation[0], vector), dot(rotation[1], vector), dot(rotation[2], vector))


def transpose(rotation):
    return tuple(tuple(rotation[column][row] for column in range(3)) for row in range(3))


def pairwise_angles(vectors):
    out = []
    for first in range(len(vectors)):
        for second in range(first + 1, len(vectors)):
            out.append(math.acos(max(-1.0, min(1.0, dot(vectors[first], vectors[second])))))
    out.sort()
    return out


def kolmogorov_distance(first, second):
    """Largest gap between the two empirical distributions, or None when either is empty."""
    if not first or not second:
        return None
    first_at = second_at = 0
    largest = 0.0
    # EVERY COPY OF A VALUE ADVANCES TOGETHER, in both lists, before the gap is read. The first version
    # stepped one list by one element at a time, so two identical lists read a gap of one third after
    # the first step, before the other list had caught up to the same value. The control on identical
    # sets reported 0.3 where the distance is exactly zero.
    while first_at < len(first) or second_at < len(second):
        heads = []
        if first_at < len(first):
            heads.append(first[first_at])
        if second_at < len(second):
            heads.append(second[second_at])
        value = min(heads)
        while first_at < len(first) and first[first_at] == value:
            first_at += 1
        while second_at < len(second) and second[second_at] == value:
            second_at += 1
        largest = max(largest, abs(first_at / float(len(first)) - second_at / float(len(second))))
    return largest


def chamfer(rotated, target):
    """Symmetric mean angle from each point to its nearest partner in the other set."""
    def one_way(points, others):
        total = 0.0
        for point in points:
            nearest = max(dot(point, other) for other in others)
            total += math.acos(max(-1.0, min(1.0, nearest)))
        return total / len(points)
    return 0.5 * (one_way(rotated, target) + one_way(target, rotated))


def best_alignment(source, target):
    """The rotation carrying `source` peaks onto `target` peaks most closely, and its score.

    Candidates are built from pairs, because two directions fix a rotation. Each source peak is paired
    with its own nearest peak, and that pair is matched to the target pair whose separation is closest
    to it, in both orders. That keeps the search to a few candidates per peak instead of every pair of
    pairs, and no tolerance enters: the score is compared, never thresholded.
    """
    if len(source) < 2 or len(target) < 2:
        return None, None
    target_pairs = []
    for first in range(len(target)):
        for second in range(len(target)):
            if first != second:
                separation = math.acos(max(-1.0, min(1.0, dot(target[first], target[second]))))
                target_pairs.append((separation, first, second))

    best_score, best_rotation = None, None
    for first in range(len(source)):
        nearest = max((dot(source[first], source[other]), other)
                      for other in range(len(source)) if other != first)[1]
        separation = math.acos(max(-1.0, min(1.0, dot(source[first], source[nearest]))))
        match = min(target_pairs, key=lambda pair: abs(pair[0] - separation))
        rotation = rotation_between((source[first], source[nearest]),
                                    (target[match[1]], target[match[2]]))
        if rotation is None:
            continue
        score = chamfer([apply(rotation, point) for point in source], target)
        if best_score is None or score < best_score:
            best_score, best_rotation = score, rotation
    return best_rotation, best_score


def readings(grid, first_flat, second_flat):
    """The three readings for one pair of rounds."""
    first_values = grid.values(first_flat)
    second_values = grid.values(second_flat)
    first_peaks, first_pits = grid.critical(first_values)
    second_peaks, second_pits = grid.critical(second_values)
    first_vectors = [grid.vectors[index] for index in first_peaks]
    second_vectors = [grid.vectors[index] for index in second_peaks]

    spacing = kolmogorov_distance(pairwise_angles(first_vectors), pairwise_angles(second_vectors))
    rotation, alignment = best_alignment(first_vectors, second_vectors)

    delta = None
    if rotation is not None:
        # Seed A carried onto seed B: B's value at x is compared with A's value at R^-1 x.
        inverse = transpose(rotation)
        total = 0.0
        for weight, vector, value in zip(grid.weights, grid.vectors, second_values):
            difference = grid.sample(first_values, apply(inverse, vector)) - value
            total += weight * difference * difference
        delta = math.sqrt(total)
    return {
        "peaks": (len(first_peaks), len(second_peaks)),
        "pits": (len(first_pits), len(second_pits)),
        "spacing": spacing,
        "alignment": alignment,
        "delta": delta,
    }


def drawn_band(values):
    kept = sorted(value for value in values if value is not None)
    count = len(kept)
    if count == 0:
        return None
    return (kept[int(0.025 * (count - 1))], kept[int(0.5 * (count - 1))], kept[int(0.975 * (count - 1))])


def verdict(value, band, closer_is_lower):
    """Where a reading sits against its band. `closer` means the two seeds agree beyond chance."""
    if value is None or band is None:
        return "-"
    if closer_is_lower:
        return "closer" if value < band[0] else ("farther" if value > band[2] else "in")
    return "closer" if value > band[2] else ("farther" if value < band[0] else "in")


def fair_readings(grid, basis, samples, draws, seed):
    generator = random.Random(seed)
    out = {"spacing": [], "alignment": [], "delta": []}
    for _ in range(draws):
        first = build_bend_view.field_of(basis, build_bend_view.fair_departures(generator, samples))
        second = build_bend_view.field_of(basis, build_bend_view.fair_departures(generator, samples))
        found = readings(grid, first, second)
        for key in out:
            out[key].append(found[key])
    return {key: drawn_band(values) for key, values in out.items()}


def _report(samples, top, draws, word):
    directions = build_sha_sphere_view.place("spiral")
    basis = build_bend_view.source_basis(top, directions)
    first_rows = build_bend_view.departures(build_bend_view.SEED_FIRST, samples, word)
    second_rows = build_bend_view.departures(build_bend_view.SEED_SECOND, samples, word)
    entries = [build_bend_view.entry_round(first_rows), build_bend_view.entry_round(second_rows)]
    if None in entries:
        print("  no round shows a flip in one of the seeds, so nothing was measured")
        return 2
    entry = max(entries)
    grid = Grid(top)
    bands = fair_readings(grid, basis, samples, draws, SEED_NULL)

    print("  flipped bit in %s" % ("any of the 512 input bits" if word is None
                                   else "message word %d only" % word))
    print("  %d samples per seed, degrees to %d, grid %d by %d, %d fair pairs per null"
          % (samples, top, grid.latitudes, grid.longitudes, draws))
    for key, label in (("spacing", "peak spacing KS"), ("alignment", "alignment rad"), ("delta", "delta")):
        band = bands[key]
        print("  null %-16s %.4f to %.4f, median %.4f" % (label, band[0], band[2], band[1]))
    print("")
    print("  %5s %11s %9s %10s %9s %11s %9s %8s %9s"
          % ("round", "peaks A/B", "spacing", "verdict", "align", "verdict", "delta", "verdict", "pits A/B"))

    closer = {"spacing": [], "alignment": [], "delta": []}
    for index in range(entry, build_bend_view.ROUNDS):
        found = readings(grid, [value for value in _field(basis, first_rows[index])],
                         [value for value in _field(basis, second_rows[index])])
        spacing_verdict = verdict(found["spacing"], bands["spacing"], True)
        alignment_verdict = verdict(found["alignment"], bands["alignment"], True)
        delta_verdict = verdict(found["delta"], bands["delta"], True)
        for key, said in (("spacing", spacing_verdict), ("alignment", alignment_verdict), ("delta", delta_verdict)):
            closer[key].append((index, said))

        def shown(value):
            return "-" if value is None else "%.4f" % value

        print("  %5d %11s %9s %10s %9s %11s %9s %8s %9s"
              % (index + 1, "%d/%d" % found["peaks"], shown(found["spacing"]), spacing_verdict,
                 shown(found["alignment"]), alignment_verdict, shown(found["delta"]), delta_verdict,
                 "%d/%d" % found["pits"]))

    print("")
    for key, label in (("spacing", "peak spacing"), ("alignment", "alignment"), ("delta", "delta")):
        verdicts = closer[key]
        run_end = None
        for index, said in verdicts:
            if said != "closer":
                break
            run_end = index
        start = entry if run_end is None else run_end + 1
        tail = [said for index, said in verdicts if index >= start]
        count_closer = sum(1 for said in tail if said == "closer")
        count_farther = sum(1 for said in tail if said == "farther")
        print("  %-13s seeds agree beyond chance through %-9s after that %d closer / %d farther of %d, chance %.1f each"
              % (label, "none" if run_end is None else "round %d" % (run_end + 1),
                 count_closer, count_farther, len(tail), 0.025 * len(tail)))
    return 0


def _field(basis, row):
    return build_bend_view.field_of(basis, row)


def _check():
    lines = []
    failed = 0

    def say(text):
        lines.append(text)

    top = 8
    grid = Grid(top)
    spacing = math.pi / grid.latitudes
    say("  grid %d by %d, row spacing %.4f rad" % (grid.latitudes, grid.longitudes, spacing))

    # POSITIVE CONTROL: one strong source must print one peak, and the peak must sit on the source.
    source_direction = (0.9, 2.1)
    single = sphere_field.coefficients([(1.0, 0.92, source_direction[0], source_direction[1])], top, 0.0)
    flat = [value for row in single for value in row]
    values = grid.values(flat)
    peaks, pits = grid.critical(values)
    tallest = max(peaks, key=lambda index: values[index]) if peaks else None
    want = (math.sin(source_direction[0]) * math.cos(source_direction[1]),
            math.sin(source_direction[0]) * math.sin(source_direction[1]),
            math.cos(source_direction[0]))
    miss = math.acos(max(-1.0, min(1.0, dot(grid.vectors[tallest], want)))) if tallest is not None else None
    say("  one source: %d peaks, tallest %.4f rad from the source" % (len(peaks), miss if miss is not None else -1))
    if miss is None or miss > 2.0 * spacing:
        say("    FAIL the tallest peak is not on the source, within two grid rows")
        failed += 1

    # A ROTATION MUST BE RECOVERED. Sources at known directions, the same sources rotated by a known
    # rotation, and the alignment has to find it. The error allowed is the grid's own row spacing
    # twice over, because peak positions are only known to the grid.
    generator = random.Random(5)
    sources = []
    for _ in range(18):
        colatitude = math.acos(generator.uniform(-1.0, 1.0))
        longitude = generator.uniform(0.0, 2.0 * math.pi)
        sources.append((generator.uniform(0.3, 1.0), 0.85, colatitude, longitude))
    axis = normalized((0.3, -0.5, 0.8))
    turn = 1.1
    cosine, sine = math.cos(turn), math.sin(turn)
    ux, uy, uz = axis
    true_rotation = (
        (cosine + ux * ux * (1 - cosine), ux * uy * (1 - cosine) - uz * sine, ux * uz * (1 - cosine) + uy * sine),
        (uy * ux * (1 - cosine) + uz * sine, cosine + uy * uy * (1 - cosine), uy * uz * (1 - cosine) - ux * sine),
        (uz * ux * (1 - cosine) - uy * sine, uz * uy * (1 - cosine) + ux * sine, cosine + uz * uz * (1 - cosine)),
    )
    turned = []
    for strength, depth, colatitude, longitude in sources:
        vector = (math.sin(colatitude) * math.cos(longitude), math.sin(colatitude) * math.sin(longitude),
                  math.cos(colatitude))
        moved = apply(true_rotation, vector)
        turned.append((strength, depth, math.acos(max(-1.0, min(1.0, moved[2]))),
                       math.atan2(moved[1], moved[0])))
    first_flat = [value for row in sphere_field.coefficients(sources, top, 0.0) for value in row]
    second_flat = [value for row in sphere_field.coefficients(turned, top, 0.0) for value in row]
    found = readings(grid, first_flat, second_flat)
    say("  a planted rotation: peaks %d/%d, spacing KS %.4f, alignment %.4f rad, delta %.4f"
        % (found["peaks"][0], found["peaks"][1], found["spacing"], found["alignment"], found["delta"]))
    if found["alignment"] is None or found["alignment"] > 2.0 * spacing:
        say("    FAIL the alignment did not recover a known rotation to within two grid rows")
        failed += 1

    # THE SAME PIPELINE ON UNRELATED SURFACES has to read far apart, or it reads everything as a match.
    other = []
    for _ in range(18):
        other.append((generator.uniform(0.3, 1.0), 0.85, math.acos(generator.uniform(-1.0, 1.0)),
                      generator.uniform(0.0, 2.0 * math.pi)))
    unrelated_flat = [value for row in sphere_field.coefficients(other, top, 0.0) for value in row]
    unrelated = readings(grid, first_flat, unrelated_flat)
    say("  unrelated surfaces: alignment %.4f rad, delta %.4f" % (unrelated["alignment"], unrelated["delta"]))
    if unrelated["delta"] is None or found["delta"] is None or unrelated["delta"] <= found["delta"]:
        say("    FAIL unrelated surfaces read at least as close as a rotated copy")
        failed += 1

    # Identical sets are zero apart by Kolmogorov-Smirnov, exactly.
    same = kolmogorov_distance([0.1, 0.4, 0.9], [0.1, 0.4, 0.9])
    say("  identical sets: KS distance %.1f" % same)
    if same != 0.0:
        failed += 1

    # The rotation builder must carry its source pair onto its target pair.
    pair_rotation = rotation_between(((1.0, 0.0, 0.0), (0.0, 1.0, 0.0)), ((0.0, 0.0, 1.0), (1.0, 0.0, 0.0)))
    landed = apply(pair_rotation, (1.0, 0.0, 0.0))
    say("  a two-vector rotation lands its first vector at %s" % (tuple(round(value, 12) for value in landed),))
    if max(abs(one - two) for one, two in zip(landed, (0.0, 0.0, 1.0))) > 8.0 * sys.float_info.epsilon:
        failed += 1

    sys.stdout.write("\n".join(lines) + "\n\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


def main(argv):
    if "--help" in argv or "-h" in argv:
        sys.stdout.write(__doc__)
        return 0
    if "--check" in argv:
        return 1 if _check() else 0
    samples = build_bend_view.option(argv, "--samples", 4000, int)
    top = build_bend_view.option(argv, "--degrees", 12, int)
    draws = build_bend_view.option(argv, "--draws", 200, int)
    word = build_bend_view.option(argv, "--word", None, int)
    if samples <= 0 or top <= 0 or draws <= 0:
        sys.stderr.write("samples, degrees and draws must all be positive\n")
        return 2
    if word is not None and not 0 <= word < 16:
        sys.stderr.write("--word names one of the sixteen message words, 0 to 15\n")
        return 2
    return _report(samples, top, draws, word)


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
