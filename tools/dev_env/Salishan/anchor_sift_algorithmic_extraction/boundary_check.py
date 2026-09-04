#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Can the algorithm find a dialect border it was never told about?
#
#   Usage:  python tools/dev_env/Salishan/anchor_sift_algorithmic_extraction/boundary_check.py
#
# Lushootseed is not one dialect. The northern and southern varieties have known land and family
# borders, and Mellesmoen and Kye's stress paper labels every form it cites with which one it came
# from. The hand extraction copied that label into the who column, so the border is on disk as a
# fact from the paper.
#
# That makes it the one thing a test of this algorithm needs and almost never has: an answer that
# did not come from the algorithm. Scoring the sift against a split the sift proposed proves
# nothing and passes forever. Scoring it against a split a linguist published is a test.
#
# The measurement is blind. The labels are loaded, then set aside, then the forms are partitioned in
# two by the sift with no label in sight, and only then are the two compared. What is reported is
# how much of the published border the partition recovered.
#
# WHY THE WORD WEB IS IN HERE
#
# Section 3 of the method resolves at 6707 bytes. The northern forms are about a thousand bytes all
# together, three orders below that, so the byte pair distribution cannot be asked this question at
# all and says so. The web is what can: a shape edge is a shared leading or trailing run of four
# characters, and stress and vowel differences between the two varieties land in exactly those runs.
# Both are measured here and the gap between them is the point.

import collections
import io
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _category in os.scandir(HERE):
    if _category.is_dir():
        sys.path.insert(0, _category.path)

from anchor_sift import distance, squash  # noqa: E402
from salish_unsorted import is_language_token  # noqa: E402
from word_web import by_language, concepts, shapes, web  # noqa: E402

# The two labels the stress paper writes, as the extraction copied them into the who column.
BORDER = ("Lushootseed northern", "Lushootseed southern")


def shape_profile(forms):
    """A set of forms as a distribution over the runs its morphology shares.

    The web's shape edge asks whether two forms share a leading or trailing run. This asks the same
    thing of a whole variety at once, which is what a distance can then be taken between. The runs
    are counted, not the edges, because an edge count squares with the number of forms and a variety
    with more forms would win on size alone.
    """
    counts = collections.Counter()
    for one in forms:
        for run in shapes(one):
            counts[run] += 1
    total = sum(counts.values())
    if not total:
        return {}, 0
    return {key: value / total for key, value in counts.items()}, total


# The run widths the radix is looked for at. Two characters is a segment and a mark, four is about
# a morpheme in these languages, and the widths between are where a stress difference lands.
RADIX_WIDTHS = (2, 3, 4)

# How far a run has to sit from where the pooled counts put it before it is reported. Three standard
# deviations under the null leaves about one run in 370 by chance, and the count expected by chance
# is printed next to the count found so the two can be compared instead of trusted.
RADIX_DEVIATE = 3.0

# How many random borders the published one is scored against. Two hundred puts the resolution of
# the reported rate at half a percent, which is finer than the finding needs and cheap at this size.
PERMUTATIONS = 200


def runs(forms, width):
    """Every character run of one width across a set of forms, counted.

    A run, not a whole form. The whole form is what the distributions in this file could not
    resolve: there are a few hundred of them and each is seen once. A run of three characters is
    seen many times across many forms, and a count that repeats is a count that can be tested.
    """
    counts = collections.Counter()
    for one in forms:
        bare = one.strip()
        for at in range(len(bare) - width + 1):
            counts[bare[at:at + width]] += 1
    return counts


def radix(north, south, width):
    """The runs that sit either side of the border once the shared structure is flattened out.

    Both varieties are the same language, so most of what a distribution over their runs measures is
    what they have in common, and at this corpus size that shared mass swamps the difference. Raising
    the pooled counts to maximum entropy is what takes it out: every run is weighed against where the
    pooled total alone would have put it, so a run carrying no border information contributes
    nothing however common it is, and what is left in a cell is the part one variety has and the
    other does not.

    Each run is then its own test rather than a term in one big one. That is the whole reason this
    can be asked at a size the distributions cannot be: a run needs enough of itself, not enough of
    the language.

    Returns [(deviate, run, in north, in south), ...], largest first, and the number of runs that
    would clear the threshold by chance alone.
    """
    first = runs(north, width)
    second = runs(south, width)
    total_first = sum(first.values())
    total_second = sum(second.values())
    if not (total_first and total_second):
        return [], 0.0
    share = total_first / float(total_first + total_second)

    held = []
    for run in set(first) | set(second):
        seen_first = first.get(run, 0)
        seen_second = second.get(run, 0)
        pooled = seen_first + seen_second
        # A run seen once cannot separate anything and there are a great many of them, so letting
        # them in would spend the whole chance budget on runs that carry nothing.
        if pooled < 4:
            continue
        expected = pooled * share
        spread = math.sqrt(pooled * share * (1.0 - share))
        if spread <= 0.0:
            continue
        held.append(((seen_first - expected) / spread, run, seen_first, seen_second))
    held.sort(key=lambda one: -abs(one[0]))
    # Under one distribution a deviate clears three standard deviations about once in 370 tests.
    return held, len(held) / 370.0


def shared_concepts(grouped, marks):
    """The forms of each variety that name a concept the other variety also names.

    The radix above separates two sets of forms, and two sets of forms can differ because the
    varieties differ or because different words were cited. Those are not the same finding and the
    first is worthless if it is really the second.

    Holding the concept fixed is what tells them apart. A concept here is a content word of the
    gloss, which is the word web's concept edge, and a run difference measured over forms that name
    the same concept in both varieties is a difference in how the variety says it. Returns the two
    filtered form lists and how many concepts they stand on.
    """
    by_side = {}
    for name in BORDER:
        held = collections.defaultdict(set)
        for where, who, kind, form, gloss in grouped.get(name, ()):
            pieces = [one for one in form.split() if is_language_token(one, marks[name])]
            if not pieces:
                continue
            for concept in concepts(gloss):
                held[concept].add(" ".join(pieces))
        by_side[name] = held

    both = set(by_side[BORDER[0]]) & set(by_side[BORDER[1]])
    first, second = [], []
    for concept in sorted(both):
        first.extend(sorted(by_side[BORDER[0]][concept]))
        second.extend(sorted(by_side[BORDER[1]][concept]))
    return first, second, len(both)


def halves(items):
    """A group split in two by alternating, which samples it rather than cutting it in place.

    self_distance cuts a corpus at its midpoint, and a corpus written in paper order puts one paper
    on each side of that cut. Alternating puts a mixture on both sides, so what comes back is the
    estimator's resolution and not the distance between whatever the midpoint separated.
    """
    return items[0::2], items[1::2]


def resolution(forms, profile):
    """How far apart two samples of one variety land, which is the floor any reading has to clear."""
    first, second = halves(sorted(forms))
    if (len(first) < 2) or (len(second) < 2):
        return 1.0
    return distance(profile(first)[0], profile(second)[0])


def bisect(forms, profile):
    """Split a set of forms in two, using nothing but the distances between them.

    Each form is its own tiny distribution, which is far too small to read on its own. What carries
    the split is the seed pair: the two forms furthest apart, taken as the two poles, with every
    other form joined to whichever pole it is nearer. That is the whole method. There is no label
    in it, no count of how many groups to expect, and no per-language term.
    """
    held = sorted(forms)
    if len(held) < 4:
        return set(held), set()
    profiles = {one: profile([one])[0] for one in held}
    # The two poles: the furthest apart pair. Every other form joins the nearer of the two.
    first, second, widest = held[0], held[1], -1.0
    for at in range(len(held)):
        for to in range(at + 1, len(held)):
            apart = distance(profiles[held[at]], profiles[held[to]])
            if apart > widest:
                first, second, widest = held[at], held[to], apart
    left, right = set(), set()
    for one in held:
        near = distance(profiles[one], profiles[first])
        far = distance(profiles[one], profiles[second])
        (left if near <= far else right).add(one)
    return left, right


def recovered(found, known):
    """How much of the published border a blind partition recovered.

    The partition's two groups arrive unnamed, so both ways of matching them to the two labels are
    scored and the better one is reported. Chance is the rate a coin flip would reach on these group
    sizes, and it is printed beside the result because a two way split of a lopsided set scores well
    by doing nothing.
    """
    left, right = found
    north, south = known
    straight = len(left & north) + len(right & south)
    swapped = len(left & south) + len(right & north)
    total = len(north) + len(south)
    if not total:
        return 0.0, 0.0
    largest = max(len(north), len(south)) / float(total)
    return max(straight, swapped) / float(total), largest


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    grouped, marks = by_language()

    sides = {}
    for name in BORDER:
        rows = grouped.get(name)
        if not rows:
            out.write("  %s is not in the extraction\n" % name)
            out.flush()
            return 1
        forms, edges = web(rows, marks[name], name)
        sides[name] = forms

    north, south = sides[BORDER[0]], sides[BORDER[1]]
    out.write("  the published border, as the stress paper labelled it\n")
    out.write("    %-22s %d forms, %d bytes\n"
              % ("northern", len(north), len(" ".join(north).encode("utf-8"))))
    out.write("    %-22s %d forms, %d bytes\n"
              % ("southern", len(south), len(" ".join(south).encode("utf-8"))))

    out.write("\n  can the two be told apart at all\n")
    out.write("    %-16s %-10s %-10s %-10s %s\n"
              % ("measure", "apart", "north D", "south D", "reading"))
    for label, profile in (("byte pairs", lambda held: squash(held)),
                           ("word web shape", shape_profile)):
        apart = distance(profile(north)[0], profile(south)[0])
        first = resolution(north, profile)
        second = resolution(south, profile)
        floor = max(first, second)
        out.write("    %-16s %-10.4f %-10.4f %-10.4f %s\n"
                  % (label, apart, first, second,
                     "separated" if apart > (2.0 * floor) else "below resolution"))

    out.write("\n  how much more of the language the border needs before it can be asked\n")
    out.write("    %-16s %-10s %-10s %s\n" % ("measure", "needs", "have", "still wanted"))
    for label, profile in (("byte pairs", lambda held: squash(held)),
                           ("word web shape", shape_profile)):
        apart = distance(profile(north)[0], profile(south)[0])
        floor = max(resolution(north, profile), resolution(south, profile))
        # A resolution measured at n falls as 1/sqrt(n), so the growth that brings the floor under
        # half the distance is the square of the ratio between them. Under a distance the two
        # varieties do not have, no amount of growth reaches it and the answer is not a number.
        if apart <= 0.0:
            out.write("    %-16s %s\n" % (label, "no distance to resolve"))
            continue
        growth = (2.0 * floor / apart) ** 2.0
        standing = len(" ".join(north + south).encode("utf-8"))
        out.write("    %-16s %-10.1fx %-10d %d bytes\n"
                  % (label, growth, standing, max(0, int(standing * (growth - 1.0)))))

    out.write("\n  the blind partition, scored against the published border\n")
    out.write("    %-16s %-12s %-12s %s\n" % ("measure", "recovered", "chance", "verdict"))
    for label, profile in (("byte pairs", lambda held: squash(held)),
                           ("word web shape", shape_profile)):
        found = bisect(north + south, profile)
        share, chance = recovered(found, (set(north), set(south)))
        out.write("    %-16s %-12.3f %-12.3f %s\n"
                  % (label, share, chance, "beats chance" if share > chance else "no better"))

    out.write("\n  the radix: single runs that sit either side of the border, pooled counts\n")
    out.write("  flattened to maximum entropy first so what both varieties share drops out\n")
    out.write("    %-8s %-9s %-9s %-9s %s\n"
              % ("width", "runs", "found", "by chance", "verdict"))
    carried = []
    for width in RADIX_WIDTHS:
        held, chance = radix(north, south, width)
        found = [one for one in held if abs(one[0]) >= RADIX_DEVIATE]
        out.write("    %-8d %-9d %-9d %-9.2f %s\n"
                  % (width, len(held), len(found), chance,
                     "carries the border" if len(found) > (2.0 * chance) else "no better"))
        carried.extend((abs(one[0]), width, one) for one in found)

    if carried:
        carried.sort(reverse=True)
        out.write("\n    %-8s %-10s %-10s %-9s %s\n"
                  % ("width", "run", "deviate", "northern", "southern"))
        for _, width, (deviate, run, seen_first, seen_second) in carried[:16]:
            out.write("    %-8d %-10s %-10.2f %-9d %d\n"
                      % (width, run, deviate, seen_first, seen_second))
        out.write("\n    a run with a positive deviate is northern, a negative one southern\n")

    held_north, held_south, standing = shared_concepts(grouped, marks)
    out.write("\n  the same question with the concept held fixed, over the %d concepts both\n"
              % standing)
    out.write("  varieties name, so a run difference is the variety and not a different word\n")
    out.write("    %-8s %-9s %-9s %-9s %-9s %s\n"
              % ("width", "north", "south", "runs", "found", "by chance"))
    controlled = []
    for width in RADIX_WIDTHS:
        held, chance = radix(held_north, held_south, width)
        found = [one for one in held if abs(one[0]) >= RADIX_DEVIATE]
        out.write("    %-8d %-9d %-9d %-9d %-9d %.2f\n"
                  % (width, len(held_north), len(held_south), len(held), len(found), chance))
        controlled.extend((abs(one[0]), width, one) for one in found)

    if controlled:
        controlled.sort(reverse=True)
        out.write("\n    %-8s %-10s %-10s %-9s %s\n"
                  % ("width", "run", "deviate", "northern", "southern"))
        for _, width, (deviate, run, seen_first, seen_second) in controlled[:12]:
            out.write("    %-8d %-10s %-10.2f %-9d %d\n"
                      % (width, run, deviate, seen_first, seen_second))
    else:
        out.write("\n    nothing clears the threshold once the concept is held fixed, so what the\n")
        out.write("    uncontrolled radix above found is which words were cited and not how a\n")
        out.write("    variety says them\n")

    out.write("\n  the inverse, as arithmetic only\n")
    out.write("  Swapping the two sides negates the numerator and leaves the spread alone, so an\n")
    out.write("  exact negation is what this estimator does on any two sets whatever, including\n")
    out.write("  two halves of noise. It is worth running because a nonzero gap would mean a\n")
    out.write("  defect, and it is worth saying plainly that passing it is evidence of nothing\n")
    out.write("  about Lushootseed. The border being symmetric is a fact about the border. This\n")
    out.write("  is a fact about the algebra, and the permutation below is the one that can fail.\n")
    out.write("    %-8s %-12s %-12s %-10s %s\n"
              % ("width", "found there", "found back", "largest gap", "verdict"))
    for width in RADIX_WIDTHS:
        forward, _ = radix(held_north, held_south, width)
        backward, _ = radix(held_south, held_north, width)
        ahead = {one[1]: one[0] for one in forward}
        behind = {one[1]: one[0] for one in backward}
        if set(ahead) != set(behind):
            out.write("    %-8d %-12s %s\n" % (width, "run sets differ", "FAILED"))
            continue
        # The two readings have to negate each other exactly, so the largest disagreement across
        # every run is the number that decides it. Anything but zero is an asymmetry in the method.
        gap = max([abs(ahead[run] + behind[run]) for run in ahead] or [0.0])
        out.write("    %-8d %-12d %-12d %-10.2e %s\n"
                  % (width,
                     len([one for one in forward if abs(one[0]) >= RADIX_DEVIATE]),
                     len([one for one in backward if abs(one[0]) >= RADIX_DEVIATE]),
                     gap, "holds" if gap < 1e-9 else "MOVED"))

    out.write("\n  and the border should not move when half the evidence is taken away either\n")
    out.write("    %-8s %-14s %-14s %s\n" % ("width", "top run, all", "top run, half", "verdict"))
    for width in RADIX_WIDTHS:
        whole, _ = radix(held_north, held_south, width)
        part, _ = radix(halves(held_north)[0], halves(held_south)[0], width)
        if not (whole and part):
            continue
        out.write("    %-8d %-14s %-14s %s\n"
                  % (width, whole[0][1], part[0][1],
                     "holds" if whole[0][1] == part[0][1] else "moved"))

    out.write("\n  the permutation: the one test here that is allowed to fail\n")
    out.write("  The border is put back on the same forms at random, %d times, and the radix is\n"
              % PERMUTATIONS)
    out.write("  run again on each. If what was found on the published labels is the language, a\n")
    out.write("  random border finds less. If it finds as much, then the count was a property of\n")
    out.write("  having two piles of words and the published labels never mattered.\n")
    out.write("    %-8s %-10s %-12s %-12s %s\n"
              % ("width", "published", "random mean", "random best", "beaten in"))
    pooled = held_north + held_south
    for width in RADIX_WIDTHS:
        found, _ = radix(held_north, held_south, width)
        real = len([one for one in found if abs(one[0]) >= RADIX_DEVIATE])
        counts = []
        for seed in range(PERMUTATIONS):
            shuffled = list(pooled)
            random.Random(seed).shuffle(shuffled)
            drawn, _ = radix(shuffled[:len(held_north)], shuffled[len(held_north):], width)
            counts.append(len([one for one in drawn if abs(one[0]) >= RADIX_DEVIATE]))
        beaten = sum(1 for one in counts if one >= real)
        out.write("    %-8d %-10d %-12.2f %-12d %d of %d\n"
                  % (width, real, sum(counts) / float(len(counts)), max(counts), beaten,
                     PERMUTATIONS))

    out.write("\n  the labels were read from the who column and never shown to the partition\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
