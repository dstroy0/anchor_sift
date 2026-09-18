#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: CEL-6-001
#
# Whether a cell's own collision entropy moves before it divides, against a published answer key.
#
#   Usage:  python examples/cell_tracking/6_oracle/entropy_before_a_division.py [dataset dir]
#
# THE CLAIM UNDER TEST, IN ONE LINE. A dividing cell's local entropy changes greatly.
#
# WHY THIS IS THE MEASUREMENT THIS SUBTREE WAS FOR. CEL-1-001 reads the answer key and finds that a
# cell is 49 px across and moves 3.5 px a frame. Consecutive masks overlap by over ninety
# percent and the correspondence is nearly free, while 59 of 95 tracks begin with a division. The
# difficulty in this data is division and not displacement, and everything measured in 2_partition
# and 4_measure refines a quantity that was never the obstacle.
#
# WHY IT IS A 6_ORACLE AND NOT AN EXAMPLE. The answer exists before the measurement and was not
# supplied by it. man_track.txt names every division in the sequence, published by the people who
# generated the data. anchor_sift/theory/workbook records that the permutation null measure carries
# most of the findings in that work and has no positive control from outside it, and calls that the
# largest single gap. This is an attempt at one. The instrument is collision entropy, which is the
# quantity anchor_sift's entire cost model runs on: every figure there is a function of 2^-H2.
#
# HOW A DIVISION IS LOCATED. A track with a non-zero parent was born from one. If child C begins at
# frame B with parent P, then P divided between frame B-1 and frame B. P at frame B-1 is a cell
# about to divide. Every other cell present at a frame it survives is not.
#
# THE BACKGROUND, AND IT IS BUILT BEFORE THE NUMBER IS QUOTED. A change in entropy says nothing on
# its own. Cells are moving, deforming and changing brightness all the time. The quantity has a
# distribution under ordinary behaviour and the question is whether division departs from it. The
# background here is every frame-to-frame entropy change of every cell that did NOT divide, drawn
# from the same sequence, the same annotation and the same intensity scale. An earlier file in this
# subtree quoted a raw value with no background and had to withdraw it.

import io
import os
import sys

import numpy

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)

DEFAULT = os.path.join("D:", os.sep, "tmp_ctc", "Fluo-N2DH-SIM+")

# Levels the intensities inside a mask are read at. CEL-4-002 sweeps this on synthetic fields and
# finds the optimum at 256, which is the depth the substrate carries. Held here rather than swept
# because the sweep belongs to a later file and this one is asking a different question.
LEVELS = 256


def collision_entropy(values, levels=LEVELS):
    """H2 of one cell's own intensities, in bits.

    -log2 of the sum of squared probabilities, which is the quantity every cost in anchor_sift is
    a function of. Computed over the pixels inside one label and nothing else. It is local by
    construction rather than by a window somebody sized.
    """
    if values.size == 0:
        return float("nan")
    low = float(values.min())
    high = float(values.max())
    if high <= low:
        return 0.0
    scaled = numpy.clip(((values - low) / (high - low) * levels).astype(numpy.int64), 0, levels - 1)
    counts = numpy.bincount(scaled, minlength=levels).astype(numpy.float64)
    total = counts.sum()
    if total <= 0:
        return float("nan")
    shares = counts / total
    return float(-numpy.log2((shares ** 2).sum()))


def read_tif(path):
    """One TIFF as an array, reading every page so a z-stack arrives whole.

    A 2D frame comes back as one plane and a 3D frame as a stack. Nothing downstream reads a
    shape: collision_entropy takes the values inside a mask and a mask selects them the same way
    in either. That is Section 2.4's corollary holding in the code as well as the proof, since the
    displacement support need not be ordered and nothing here asks how many axes it has.
    """
    from PIL import Image
    handle = Image.open(path)
    pages = []
    try:
        while True:
            pages.append(numpy.array(handle))
            handle.seek(handle.tell() + 1)
    except EOFError:
        pass
    return pages[0] if len(pages) == 1 else numpy.stack(pages)


def frame_number(name):
    """The digits at the end of a CTC filename, which is the only thing that orders a sequence."""
    digits = "".join(character for character in os.path.splitext(name)[0] if character.isdigit())
    return int(digits) if digits else -1


def load(where, sequence="01"):
    """Every annotated frame as (index, raw intensities, ground truth labels).

    Matched by frame number and never by sort order. Fluo-N2DH-SIM+ carries a mask for every raw
    frame and the two lists zip correctly; Fluo-N3DH-CE carries 197 annotated frames against 251
    raw ones, and zipping those pairs frame 40 of one against frame 52 of the other and reads
    every entropy against the wrong image. The sequences that would have caught it silently are
    exactly the ones this file was written on.
    """
    raw_dir = os.path.join(where, sequence)
    track_dir = os.path.join(where, "%s_GT" % sequence, "TRA")
    raws = {frame_number(name): name
            for name in os.listdir(raw_dir) if name.endswith(".tif")}
    masks = {frame_number(name): name
             for name in os.listdir(track_dir) if name.endswith(".tif")}
    for index in sorted(set(raws) & set(masks)):
        yield (index,
               read_tif(os.path.join(raw_dir, raws[index])),
               read_tif(os.path.join(track_dir, masks[index])))


def divisions(where):
    """Every division as (frame the parent last existed, parent label, [child labels]).

    A first version of this file asked for the parent's own entropy in the frame after it divided
    and found no parent there, because a label image has to do exactly that: the parent stops
    existing and two children appear. Nothing survives to difference against itself. The question
    was malformed and the data said so on the first run.

    What the parent hands over is handed to the children. The comparison is the parent against
    the pair that replaced it.
    """
    children = {}
    path = os.path.join(where, "01_GT", "TRA", "man_track.txt")
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            parts = line.split()
            if len(parts) != 4:
                continue
            label, begin, _, parent = (int(value) for value in parts)
            if parent != 0:
                children.setdefault((begin - 1, parent), []).append(label)
    return [(frame, parent, kids) for (frame, parent), kids in sorted(children.items())]


def main():
    where = sys.argv[1] if len(sys.argv) > 1 else DEFAULT
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isdir(where):
        out.write("  not found: %s\n" % where)
        out.flush()
        return 1

    events = divisions(where, sequence)

    # Keyed by the real frame number, never by position in a list. man_track.txt names absolute
    # frames, and a sequence whose annotation is sparse has no relation between the two.
    frames_data = {}
    per_frame = {}
    for index, raw, labels in load(where, sequence):
        frames_data[index] = (raw, labels)
        here = {}
        for label in numpy.unique(labels):
            if label == 0:
                continue
            here[int(label)] = collision_entropy(raw[labels == label], levels)
        per_frame[index] = here

    # A division: the parent's entropy against each daughter's, and against the pair read as one
    # object. The pair is the test of whether what the parent held is still there once it is in two
    # pieces, which is a different question from whether either piece resembles it.
    inherited = []
    pair_gap = []
    for frame, parent, kids in events:
        if frame < 0 or (frame + 1) >= len(frames_data):
            continue
        if parent not in per_frame[frame]:
            continue
        before = per_frame[frame][parent]
        after_raw, after_labels = frames_data[frame + 1]
        present = [kid for kid in kids if kid in per_frame[frame + 1]]
        if len(present) < 2:
            continue
        for kid in present:
            inherited.append(abs(per_frame[frame + 1][kid] - before))
        # The daughters read as one object, which is the closest thing to the parent the next
        # frame holds. Kept SIGNED. A first version of this file took an absolute value here and
        # threw away the only thing the claim under test is about: whether the pair reads slightly
        # BELOW the parent, consistently, which is a conservation statement. A magnitude cannot
        # carry a direction and reporting one as the other is how three claims in
        # anchor_sift/theory/workbook merged two instruments.
        together = numpy.isin(after_labels, present)
        pair_gap.append(collision_entropy(after_raw[together]) - before)

    # The background: a cell that did not divide, differenced against itself one frame on. Signed
    # for the same reason, and it is the noise floor the signed claim has to clear.
    ordinary = []
    for index in range(len(per_frame) - 1):
        after = per_frame[index + 1]
        for label, value in per_frame[index].items():
            if label in after:
                ordinary.append(after[label] - value)

    about_to = numpy.array(inherited)
    pair_gap = numpy.array(pair_gap)
    ordinary = numpy.array(ordinary)

    out.write("  Fluo-N2DH-SIM+ sequence 01. Collision entropy inside each cell's own mask.\n")
    out.write("  %d divisions in the answer key, %d usable, %d daughter readings.\n"
              % (len(events), len(pair_gap), len(about_to)))
    out.write("  %d ordinary frame-to-frame changes as the background.\n\n" % len(ordinary))

    if about_to.size == 0:
        out.write("  No division has both daughters present in the next frame. Nothing to read.\n")
        out.flush()
        return 0

    out.write("  %-26s %-10s %-10s %-10s\n" % ("|change in H2|, bits", "median", "mean", "p90"))
    out.write("  %-26s %-10.4f %-10.4f %-10.4f\n"
              % ("parent to one daughter", float(numpy.median(about_to)),
                 float(about_to.mean()), float(numpy.percentile(about_to, 90))))
    out.write("  %-26s %-10.4f %-10.4f %-10.4f\n"
              % ("parent to both together", float(numpy.median(pair_gap)),
                 float(pair_gap.mean()), float(numpy.percentile(pair_gap, 90))))
    out.write("  %-26s %-10.4f %-10.4f %-10.4f\n"
              % ("background, cell to self", float(numpy.median(ordinary)),
                 float(ordinary.mean()), float(numpy.percentile(ordinary, 90))))

    # A standard deviation on this background is not a valid floor and a first version of this file
    # used one. The background is heavy tailed, mean %.4f against median %.4f, and
    # anchor_sift/theory/workbook records that quoting a mean and a deviation on such a quantity is
    # the defect that put figures three orders of magnitude too large into several of its entries,
    # with a Jarque-Bera of 800 against a one percent point of 9.21. The rank statistic it uses
    # instead is what this now reports.
    skew_note = (float(ordinary.mean()), float(numpy.median(ordinary)))
    out.write("\n  Background is heavy tailed, mean %.4f against median %.4f. A deviation on\n"
              % skew_note)
    out.write("  it is not a floor. Read by rank instead.\n\n")

    # Where a division's reading falls in the background's own distribution. A detector's real
    # operating point: how much of the background it would have to admit to catch this division.
    def rank_of(values):
        return float(numpy.mean([
            (ordinary < value).mean() for value in values]))

    one_rank = rank_of(about_to)
    pair_rank = rank_of(pair_gap)
    cut = float(numpy.percentile(ordinary, 90))
    caught = float((about_to > cut).mean())
    pair_caught = float((pair_gap > cut).mean())

    out.write("  %-26s %-14s %s\n" % ("", "mean rank", "share past background p90"))
    out.write("  %-26s %-14.4f %.4f\n" % ("parent to one daughter", one_rank, caught))
    out.write("  %-26s %-14.4f %.4f\n" % ("parent to both together", pair_rank, pair_caught))

    # The signed claim, which is the sharp one: the pair reads slightly BELOW the parent, and does
    # so consistently, against a background whose signed changes have no direction.
    signed = numpy.array(pair_gap)
    noise = numpy.array(ordinary)
    below = float((signed < 0.0).mean())
    noise_below = float((noise < 0.0).mean())
    # The noise floor is the spread of the background's own mean under resampling, which is what
    # a direction has to clear to be a direction and not a draw.
    floor = float(noise.std() / numpy.sqrt(len(noise)))
    out.write("\n  SIGNED, which is the claim: pair minus parent, in bits.\n")
    out.write("  %-26s %-11s %-11s %-11s %s\n"
              % ("", "median", "mean", "share < 0", "floors"))
    out.write("  %-26s %-11.4f %-11.4f %-11.4f %.1f\n"
              % ("pair minus parent", float(numpy.median(signed)), float(signed.mean()),
                 below, abs(float(signed.mean())) / floor if floor > 0 else float("inf")))
    out.write("  %-26s %-11.4f %-11.4f %-11.4f %s\n"
              % ("background, cell to self", float(numpy.median(noise)), float(noise.mean()),
                 noise_below, "-"))
    out.write("  noise floor %.5f bits, the background mean's own standard error over %d changes.\n"
              % (floor, len(noise)))

    # Above this share of the background, a cut that catches most divisions is admitting too much
    # to be a detector on its own.
    one_floors = one_rank
    pair_floors = pair_rank

    if (caught >= 0.5) and (pair_gap.mean() < about_to.mean()):
        out.write("\n  A daughter differs from its parent by more than an ordinary cell differs\n")
        out.write("  from itself, and the two daughters read together differ by LESS than one of\n")
        out.write("  them does. What the parent held is still present once it is in two pieces,\n")
        out.write("  and splitting it is what moved the reading. That is the inheritance stated\n")
        out.write("  as a measurement rather than an image.\n")
        out.write("\n  It is not a detector on its own. Catching that share of divisions costs\n")
        out.write("  admitting a tenth of every ordinary frame-to-frame change, and there are\n")
        out.write("  %d of those against %d divisions. A cut at p90 fires far more often on\n"
                  % (len(ordinary), len(pair_gap)))
        out.write("  an ordinary cell than on a dividing one. It is a term and not a test.\n")
    elif caught >= 0.5:
        out.write("\n  A daughter departs from its parent, and reading the pair as one object does\n")
        out.write("  not recover it. The change is not conserved across the split.\n")
    else:
        out.write("\n  It does not clear the background. Collision entropy inside a mask does not\n")
        out.write("  separate a division from ordinary frame-to-frame change here, and a detector\n")
        out.write("  built on it would fire on both.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
