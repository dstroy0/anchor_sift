#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""What a cost reading resolves and what it cannot, measured instead of argued.

    python utils/maint/engine/measure_check.py [--trials N]

The noisy half of the query protocol. Six checks, each one isolating a claim chain slicing rests
on. Every number below is produced by the run and none is quoted from anywhere.

    1  slicing a chain by adjacent cuts, against the noise floor
    2  how far repetition carries check 1, steered: a level that orders no more pairs ends it
    3  permuted subsets against the prefix ladder at one measurement budget
    4  one ask per link against a known order of covering asks
    5  a known order against a drawn one, where a bad draw has nowhere to hide
    6  whether the costs add, what notices when they do not, and what repairs it

Everything here is about speed and nothing here reaches a correctness result.
`utils/maint/engine/order_check.py` holds the noiseless half as checks 7 through 12, and the separation
between the two files is the separation the two stages buy.

EVERY VALUE IS THREE INTEGERS: a quotient, a remainder and a divisor, the value q + r/d with
0 <= r < d. Integer adds and integer division move them, and every operation carries its remainder
forward. Nothing is rounded at any width. No floating point value is formed anywhere here. The
noise is a sum of fair coins, every solve is fraction-free integer elimination, and a spread is held
as its square. No root is taken. Each figure prints its quotient and its remainder over its
divisor, and every figure is written in full to build/engine/measure_check.tsv.

THE UNIT HERE IS THE FLOOR. Every cost is quoted in floors, and the noise's square is one floor
squared by construction. No absolute figure is written in. The plan's own ratio sets the rest:
one operation sits under the floor, and a chain of fifteen clears it.
"""

import math
import os
import random
import sys

# A chain long enough to clear the floor, as the plan measures it.
LINKS = 15

# Every cost is an integer count of this part of a floor.
UNIT = 6400

# One measurement's noise is this many fair coins, each worth COIN units. Their square sums to
# COIN * COIN * COINS, which is UNIT * UNIT: the noise's square is one floor squared.
COINS = 256
COIN = 400

# Per-link costs are drawn across this band, in units. Centred on the floor, because a single
# operation sitting under it is the case that makes slicing hard.
BAND = (UNIT // 2, (3 * UNIT) // 2)

# The contention a pair adds, in hundredths of a floor.
CONTENTION = (0, 1, 3, 8, 20)

# The levels check 2 descends through, as repeats of every cut.
LEVELS = (1, 10, 100, 400, 1600, 6400)

TRIALS = 400
SEED = 20260930

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
FIGURES = []


class Exact:
    """A value held as three integers: quotient, remainder and divisor, q + r/d with 0 <= r < d."""

    __slots__ = ("q", "r", "d")

    def __init__(self, numerator, divisor=1):
        if divisor < 0:
            numerator = -numerator
            divisor = -divisor
        self.q, remainder = divmod(numerator, divisor)
        self.keep(remainder, divisor)

    def keep(self, remainder, divisor):
        common = math.gcd(remainder, divisor)
        self.r = remainder // common
        self.d = divisor // common

    @classmethod
    def triple(cls, quotient, remainder, divisor):
        """The value quotient + remainder/divisor, the remainder's overflow carried into the quotient."""
        carried, remainder = divmod(remainder, divisor)
        value = cls.__new__(cls)
        value.q = quotient + carried
        value.keep(remainder, divisor)
        return value

    def whole(self):
        """The numerator over d."""
        return (self.q * self.d) + self.r

    def __add__(self, other):
        other = exact(other)
        return Exact.triple(self.q + other.q, (self.r * other.d) + (other.r * self.d), self.d * other.d)

    __radd__ = __add__

    def __neg__(self):
        return Exact.triple(-self.q, -self.r, self.d)

    def __sub__(self, other):
        return self + (-exact(other))

    def __rsub__(self, other):
        return exact(other) - self

    def __mul__(self, other):
        other = exact(other)
        crossed = (self.q * other.r * self.d) + (other.q * self.r * other.d) + (self.r * other.r)
        return Exact.triple(self.q * other.q, crossed, self.d * other.d)

    __rmul__ = __mul__

    def __truediv__(self, other):
        other = exact(other)
        return Exact(self.whole() * other.d, self.d * other.whole())

    def __rtruediv__(self, other):
        return exact(other) / self

    def __abs__(self):
        return -self if self.q < 0 else self

    def against(self, other):
        other = exact(other)
        lean = (self.whole() * other.d) - (other.whole() * self.d)
        return (lean > 0) - (lean < 0)

    def __lt__(self, other):
        return self.against(other) < 0

    def __gt__(self, other):
        return self.against(other) > 0

    def __le__(self, other):
        return self.against(other) <= 0

    def __ge__(self, other):
        return self.against(other) >= 0

    def __eq__(self, other):
        return self.against(other) == 0

    __hash__ = None


def exact(value):
    return value if isinstance(value, Exact) else Exact(value)


def show(value, places=4):
    """The quotient, and the remainder over the divisor beside it.

    A divisor too long to print is carried on by long division for `places` more digits of the
    quotient, each one an integer division whose remainder carries to the next, and the remainder
    still standing is named by the length of its divisor.
    """
    if value.r == 0:
        return str(value.q)
    if value.q < 0:
        # q + r/d below zero reads as its magnitude with a sign: the quotient of -value is -q - 1
        return "-" + show(-value, places)
    digits = len(str(value.d))
    if digits <= 6:
        return "%d + %d/%d" % (value.q, value.r, value.d)
    remainder = value.r
    shown = ""
    for _ in range(places):
        digit, remainder = divmod(remainder * 10, value.d)
        shown += str(digit)
    if remainder == 0:
        return "%d.%s" % (value.q, shown)
    return "%d.%s + r/d, d of %d digits" % (value.q, shown, digits)


def figure(label, value):
    """Keeps `value` for the written record and returns it shown."""
    FIGURES.append((label, value))
    return show(value)


def write_figures():
    folder = os.path.join(ROOT, "build", "engine")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, "measure_check.tsv")
    with open(path, "w", encoding="utf-8", newline="\n") as out:
        out.write("figure\tquotient\tremainder\tdivisor\n")
        for label, value in FIGURES:
            out.write("%s\t%d\t%d\t%d\n" % (label, value.q, value.r, value.d))
    return os.path.relpath(path, ROOT).replace(os.sep, "/")


def noise(rng, measurements):
    """The noise of `measurements` measurements summed, in units: COINS fair coins each."""
    flips = COINS * measurements
    return COIN * ((2 * rng.getrandbits(flips).bit_count()) - flips)


def truth_of(rng, links=LINKS):
    """One chain's true per-link costs, in units."""
    return [rng.randint(BAND[0], BAND[1]) for _ in range(links)]


def kendall(truth, got):
    """Of the pairs the truth orders, how many the reading orders the same way, and how many there are."""
    agree = 0
    total = 0
    for first in range(len(truth)):
        for second in range(first + 1, len(truth)):
            apart = truth[first] - truth[second]
            if apart == 0:
                continue
            total += 1
            if apart * (got[first] - got[second]) > 0:
                agree += 1
    return agree, total


def first_most(values):
    return max(range(len(values)), key=lambda at: values[at])


def first_least(values):
    return min(range(len(values)), key=lambda at: values[at])


def ladder_read(truth, rng, repeats=1):
    """Per-link costs recovered from prefix cuts, the way the plan writes slicing today.

    Cut k measures the first k links `repeats` times over, summed. The per-link cost is the
    difference between neighboring cuts, and that difference carries the noise of both. Each
    reading comes back as a count of units over `repeats`.
    """
    seen = []
    cut = 0
    for at in range(LINKS + 1):
        seen.append((repeats * cut) + noise(rng, repeats))
        if at < LINKS:
            cut += truth[at]
    return [seen[at + 1] - seen[at] for at in range(LINKS)]


def ladder_squares(truth, got, repeats):
    """The ladder's squared error over a chain, in floors squared."""
    return Exact(sum((seen - (repeats * cost)) ** 2 for seen, cost in zip(got, truth)), repeats * repeats * UNIT * UNIT)


def solve(matrix, rhs):
    """Fraction-free integer elimination. Each unknown is held[i] / divisor; a divisor of 0 is a singular system."""
    size = len(matrix)
    rows = [list(matrix[at]) + [rhs[at]] for at in range(size)]
    previous = 1
    for step in range(size):
        pivot_at = next((at for at in range(step, size) if rows[at][step] != 0), None)
        if pivot_at is None:
            return 0, None
        if pivot_at != step:
            rows[step], rows[pivot_at] = rows[pivot_at], rows[step]
        pivot = rows[step][step]
        for at in range(step + 1, size):
            factor = rows[at][step]
            rows[at] = [((pivot * rows[at][col]) - (factor * rows[step][col])) // previous for col in range(size + 1)]
        previous = pivot
    divisor = rows[size - 1][size - 1]
    held = [0] * size
    for at in range(size - 1, -1, -1):
        rest = (divisor * rows[at][size]) - sum(rows[at][col] * held[col] for col in range(at + 1, size))
        quotient, remainder = divmod(rest, rows[at][at])
        if remainder != 0:
            raise ArithmeticError("elimination left a remainder at row %d" % at)
        held[at] = quotient
    return divisor, held


def columns_of(masks, links):
    """For each link, the runs that cover it, as a bit set over the runs."""
    columns = [0] * links
    for run, mask in enumerate(masks):
        for link in range(links):
            if (mask >> link) & 1:
                columns[link] |= 1 << run
    return columns


def normal_system(masks, seen, links, square=False):
    """The normal equations of a covering design, and with `square` a column for the count covered, squared."""
    columns = columns_of(masks, links)
    matrix = [[(columns[row] & columns[col]).bit_count() for col in range(links)] for row in range(links)]
    rhs = [sum(seen[run] for run in range(len(masks)) if (columns[link] >> run) & 1) for link in range(links)]
    if square:
        counted = [mask.bit_count() ** 2 for mask in masks]
        for link in range(links):
            matrix[link].append(sum(counted[run] for run in range(len(masks)) if (columns[link] >> run) & 1))
        matrix.append([matrix[link][links] for link in range(links)] + [sum(value * value for value in counted)])
        rhs.append(sum(value * read for value, read in zip(counted, seen)))
    return matrix, rhs


def covered_sum(mask, costs):
    return sum(costs[link] for link in range(len(costs)) if (mask >> link) & 1)


def subset_squares(truth, rng, runs):
    """Per-link costs recovered from permuted subsets, solved as one system, and the squared error in floors squared.

    Each run measures the sum over a random half of the links and carries one measurement's noise.
    Nothing is differenced. The noise spreads across the whole design in place of landing twice on
    every link.
    """
    masks = []
    for _ in range(runs):
        mask = rng.getrandbits(LINKS)
        # A run measuring nothing constrains nothing. Give it one link so the system stays solvable.
        masks.append(mask if mask != 0 else 1 << rng.randrange(LINKS))
    seen = [covered_sum(mask, truth) + noise(rng, 1) for mask in masks]
    matrix, rhs = normal_system(masks, seen, LINKS)
    divisor, held = solve(matrix, rhs)
    squares = sum((value - (divisor * cost)) ** 2 for value, cost in zip(held, truth))
    return Exact(squares, divisor * divisor * UNIT * UNIT)


def percent(part, whole):
    return Exact(100 * part, whole)


def check_adjacent(say, rng, trials):
    """1. Adjacent differencing puts the noise above the signal it is trying to read."""
    say("1. SLICING BY ADJACENT CUTS")
    say("   A chain of %d links, each drawn in [1/2, 3/2] floors." % LINKS)
    say("")

    squares = Exact(0)
    agree = 0
    pairs = 0
    best = 0
    worst = 0
    for _ in range(trials):
        truth = truth_of(rng)
        got = ladder_read(truth, rng)
        squares = squares + ladder_squares(truth, got, 1)
        held, total = kendall(truth, got)
        agree += held
        pairs += total
        best += int(first_most(got) == first_most(truth))
        worst += int(first_least(got) == first_least(truth))

    error = squares / (trials * LINKS)
    say("   noise on one measurement, squared         1 floor squared")
    say("   noise on a recovered link, squared        %s   (predicted 2, the noise's square twice)"
        % figure("1 recovered link noise squared", error))
    say("   typical link cost                         1 floor")
    say("   signal squared over noise squared         %s" % figure("1 signal squared over noise squared", 1 / error))
    say("")
    say("   Subtraction adds variance. The cuts are long and well above the floor; the difference")
    say("   between two of them is one link, and one link is the quantity sitting under it.")
    say("")
    say("   pairs ordered correctly         %s%%   (50%% is a coin)" % figure("1 pairs ordered percent", percent(agree, pairs)))
    say("   most expensive link found       %s%%   (%s%% is a guess)"
        % (figure("1 most expensive found percent", percent(best, trials)), show(percent(1, LINKS))))
    say("   cheapest link found             %s%%" % figure("1 cheapest found percent", percent(worst, trials)))
    say("")
    say("   A branch comparison built on this ranks links by coin toss.")
    return error, percent(agree, pairs)


def check_repetition(say, rng, trials):
    """2. Repetition fixes check 1, and the descent through repeat counts says how far it carries.

    The steering the engine does, put to repetition. One population of chains is held, and each
    level reads every chain again at more repeats. The pairs a level orders wrongly are the ones
    still standing, and a level counts only when it leaves strictly fewer standing than the level
    above it. The first level that does not prune ends the descent, and every level below it is
    destroyed with it.
    """
    say("2. HOW FAR REPETITION CARRIES")
    say("")
    population = [truth_of(rng) for _ in range(max(40, trials // 8))]
    say("   %d chains held, read again at every level." % len(population))
    say("")
    say("   repeats    noise/link squared    pairs ordered    most expensive found    misordered")
    standing = None
    kept = None
    kept_ordered = None
    for repeats in LEVELS:
        squares = Exact(0)
        agree = 0
        pairs = 0
        best = 0
        for truth in population:
            got = ladder_read(truth, rng, repeats)
            squares = squares + ladder_squares(truth, got, repeats)
            held, total = kendall(truth, got)
            agree += held
            pairs += total
            best += int(first_most(got) == first_most(truth))
        error = squares / (len(population) * LINKS)
        misordered = pairs - agree
        say("   %7d    %18s    %12s%%    %19s%%    %10d"
            % (repeats, figure("2 noise squared at %d" % repeats, error),
               figure("2 pairs ordered percent at %d" % repeats, percent(agree, pairs)),
               figure("2 most expensive found percent at %d" % repeats, percent(best, len(population))), misordered))
        if (standing is not None) and (misordered >= standing):
            say("")
            say("   %d repeats left %d pairs misordered against %d at %d: the level prunes nothing, and"
                % (repeats, misordered, standing, kept))
            say("   the descent ends there.")
            break
        standing = misordered
        kept = repeats
        kept_ordered = percent(agree, pairs)
    else:
        say("")
        say("   Every level pruned, down to the deepest one tried.")
    say("")
    say("   %d repeats of every cut is the last level that ordered more pairs, at %s%%." % (kept, show(kept_ordered)))
    say("   The noise's square falls as one over the count, and the gap between two neighboring")
    say("   links falls as one over the link count. Both have to be paid.")
    return kept, kept_ordered


def check_subsets(say, rng, trials):
    """3. The same measurement budget, spent on permuted subsets instead of a prefix ladder."""
    say("3. PERMUTED SUBSETS AGAINST THE PREFIX LADDER")
    say("")
    say("   One budget is one count of measurements. The ladder spends it on %d cuts repeated;" % (LINKS + 1))
    say("   the subset design spends it on that many separate runs. Errors are squared, in floors squared.")
    say("")
    say("   budget    ladder noise squared    subset noise squared    subset is better by, squared")
    gains = Exact(0)
    levels = (4, 16, 64, 256)
    for repeats in levels:
        budget = repeats * (LINKS + 1)
        count = max(30, trials // 10)
        ladder = Exact(0)
        subset = Exact(0)
        for _ in range(count):
            truth = truth_of(rng)
            ladder = ladder + ladder_squares(truth, ladder_read(truth, rng, repeats), repeats)
            subset = subset + subset_squares(truth, rng, budget)
        one = ladder / (count * LINKS)
        two = subset / (count * LINKS)
        gain = one / two
        gains = gains + gain
        say("   %6d    %20s    %20s    %28s" % (budget, figure("3 ladder noise squared at %d" % budget, one),
                                                figure("3 subset noise squared at %d" % budget, two),
                                                figure("3 squared gain at %d" % budget, gain)))
    mean = gains / len(levels)
    say("")
    say("   The ladder inverts a triangle of ones, and every row of that inverse has two")
    say("   non-zero entries, which fixes its squared error at twice the noise's square")
    say("   whatever the budget. A subset design has no such floor: its error falls with the")
    say("   whole budget because every run constrains many links at once.")
    say("")
    say("   Predicted squared gain is (link count + 1) over two, %d here. Measured %s."
        % ((LINKS + 1) // 2, figure("3 squared gain over the budgets", mean)))
    say("")
    say("   The permutation this needs is already in the emission.")
    return mean


def known_order(links):
    """The known order of asks for a chain of `links`, where links + 1 is a power of two.

    Ask r covers link c where (r + 1) & (c + 1) has an odd count of ones: a Hadamard matrix one
    larger with its first row and column dropped, which leaves every ask covering half the links
    and every two asks overlapping on a quarter. Nothing is drawn. The order is fixed, reproducible
    from the link count alone, and carries no record beyond that count. Each ask is a bit set over
    the links.
    """
    return [sum(1 << link for link in range(links) if (((ask + 1) & (link + 1)).bit_count() & 1)) for ask in range(links)]


def known_solve(order, seen, links):
    """Every link's cost times (links + 1), exactly: 4 times what the asks covering it read, less twice them all."""
    every = sum(seen)
    return [(4 * sum(seen[ask] for ask in range(links) if (order[ask] >> link) & 1)) - (2 * every) for link in range(links)]


def check_carrier_gain(say, rng, trials):
    """4. Asking in a known order against asking one link at a time, at one budget."""
    say("4. ONE ASK PER LINK AGAINST A KNOWN ORDER OF ASKS")
    say("")
    say("   Both spend one ask per link. One asks about a single link each time. The other asks")
    say("   about half the links each time, in an order chosen so the answers come apart.")
    say("   Errors are squared, in floors squared, and so is the gain.")
    say("")
    say("   links    one at a time    known order    squared gain    predicted")
    gains = []
    for links in (3, 7, 15, 31, 63, 127, 255):
        order = known_order(links)
        reps = max(8, trials // (2 * links))
        lone = 0
        rode = 0
        for _ in range(reps):
            truth = truth_of(rng, links)
            lone += sum(noise(rng, 1) ** 2 for _ in range(links))
            seen = [covered_sum(mask, truth) + noise(rng, 1) for mask in order]
            held = known_solve(order, seen, links)
            rode += sum((value - ((links + 1) * cost)) ** 2 for value, cost in zip(held, truth))
        one = Exact(lone, reps * links * UNIT * UNIT)
        two = Exact(rode, reps * links * (links + 1) * (links + 1) * UNIT * UNIT)
        gain = one / two
        gains.append((links, gain))
        say("   %5d    %13s    %11s    %12s    %9s" % (links, figure("4 one at a time squared at %d" % links, one),
                                                  figure("4 known order squared at %d" % links, two),
                                                  figure("4 squared gain at %d" % links, gain),
                                                  show(Exact(links + 1, 4))))
    say("")
    say("   The known order carries the cost of several links in every answer, and the orders are")
    say("   chosen to come apart cleanly. One ask therefore informs every link at once, and the")
    say("   squared gain is (links + 1) over four and it grows with the chain.")
    say("")
    say("   At %d links the squared gain is %s and at %d links it is %s. A short chain is"
        % (gains[0][0], show(gains[0][1]), gains[-1][0], show(gains[-1][1])))
    say("   not worth a known order and a long one is worth a great deal.")
    say("")
    say("   Nothing here beats the bound on what one ask can carry. The known order reaches that")
    say("   bound and one ask per link does not, and the whole gain is that difference.")
    return gains


def quantile(ordered, numerator, denominator):
    """The value at numerator/denominator of the way through `ordered`, between its two neighbors exactly."""
    at, part = divmod(numerator * (len(ordered) - 1), denominator)
    if part == 0:
        return ordered[at]
    return ordered[at] + ((ordered[at + 1] - ordered[at]) * Exact(part, denominator))


def check_known_against_drawn(say, rng, trials):
    """5. A known order against a drawn one, at the budget where a bad draw has nowhere to hide."""
    say("5. A KNOWN ORDER AGAINST A DRAWN ONE")
    say("")
    say("   %d links and %d asks: exactly enough, with nothing spare. A drawn order is a drawn" % (LINKS, LINKS))
    say("   order and some draws do not come apart at all.")
    say("")
    order = known_order(LINKS)
    held_worst = []
    drawn_worst = []
    lost = 0
    for _ in range(trials):
        truth = truth_of(rng)
        seen = [covered_sum(mask, truth) + noise(rng, 1) for mask in order]
        held = known_solve(order, seen, LINKS)
        held_worst.append(Exact(max(abs(value - ((LINKS + 1) * cost)) for value, cost in zip(held, truth)),
                                (LINKS + 1) * UNIT))
        pick = [rng.getrandbits(LINKS) for _ in range(LINKS)]
        noisy = [covered_sum(mask, truth) + noise(rng, 1) for mask in pick]
        matrix = [[(mask >> link) & 1 for link in range(LINKS)] for mask in pick]
        divisor, got = solve(matrix, noisy)
        if divisor == 0:
            lost += 1
            continue
        drawn_worst.append(Exact(max(abs(value - (divisor * cost)) for value, cost in zip(got, truth)),
                                 abs(divisor) * UNIT))

    held_worst.sort()
    drawn_worst.sort()
    rows = (("median", 1, 2), ("95th percentile", 95, 100), ("worst", 1, 1))
    say("   worst link error, in floors")
    ratios = []
    for name, numerator, denominator in rows:
        known = quantile(held_worst, numerator, denominator)
        drawn = quantile(drawn_worst, numerator, denominator)
        ratio = drawn / known
        ratios.append(ratio)
        say("   %-16s known %s" % (name, figure("5 known %s" % name, known)))
        say("   %-16s drawn %s" % ("", figure("5 drawn %s" % name, drawn)))
        say("   %-16s drawn over known %s" % ("", figure("5 drawn over known %s" % name, ratio)))
    say("")
    say("   orders that came apart at all    %d of %d known, %d of %d drawn" % (trials, trials, trials - lost, trials))
    say("")
    say("   The known order wins on every row and wins by more the further out the row is.")
    say("   %d of %d draws came apart not at all and cost the whole pass." % (lost, trials))
    say("")
    say("   An engine answering every time is held to its worst case. A drawn order has no worst")
    say("   case to be held to, and a known one is the same every pass by construction.")
    return ratios, lost


def half_and_half(links, runs, rng):
    """Asks each covering about half the links."""
    masks = []
    for _ in range(runs):
        mask = rng.getrandbits(links)
        masks.append(mask if mask != 0 else 1)
    return masks


def size_swept(links, runs, rng):
    """Asks sweeping the count of links covered, from two up to nearly all of them."""
    return [sum(1 << link for link in rng.sample(range(links), 2 + (at % (links - 2)))) for at in range(runs)]


def contended(hundredths, builder, runs, rng, with_term):
    """One pass where the links contend, solved with and without a term for the contention.

    Contention over a set grows as the square of how many links the set covers. The links
    themselves grow as the count. A solve carrying a squared-count column can tell the two apart
    and a solve without one cannot. A pair contends by a draw of 0 to 16 sixteenths of
    `hundredths` hundredths of a floor, which is 4 * hundredths * draw units.
    """
    truth = truth_of(rng)
    cross = [[0] * LINKS for _ in range(LINKS)]
    for first in range(LINKS):
        for second in range(first + 1, LINKS):
            cross[first][second] = 4 * hundredths * rng.randint(0, 16)
    masks = builder(LINKS, runs, rng)
    seen = []
    for mask in masks:
        inside = [link for link in range(LINKS) if (mask >> link) & 1]
        extra = sum(cross[first][second] for at, first in enumerate(inside) for second in inside[at + 1:])
        seen.append(covered_sum(mask, truth) + extra + noise(rng, 1))
    matrix, rhs = normal_system(masks, seen, LINKS, square=with_term)
    divisor, held = solve(matrix, rhs)
    damage = Exact(sum(abs(held[link] - (divisor * truth[link])) for link in range(LINKS)), LINKS * abs(divisor) * UNIT)
    if not with_term:
        left = sum(((divisor * read) - covered_sum(mask, held)) ** 2 for mask, read in zip(masks, seen))
        return damage, None, Exact(left, divisor * divisor * (runs - LINKS) * UNIT * UNIT)
    return damage, Exact(held[LINKS], divisor * UNIT), None


def check_additive(say, rng, trials):
    """6. Whether link costs add, what notices when they do not, and what repairs it."""
    say("6. WHETHER THE COSTS ADD")
    say("")
    say("   Solving for links from covering asks takes the cost of a set to be the sum of its")
    say("   parts. Where parts contend for something, it is not, and the solve returns a")
    say("   confident wrong answer with nothing in it saying so.")
    say("")
    runs = 4 * LINKS
    count = max(40, trials // 6)
    say("   %d links, %d asks, a floor of 1, over two orders of asking." % (LINKS, runs))
    say("   Contention is the cost added per contending pair, in hundredths of a floor.")
    say("")
    swept = []
    for name, builder in (("asks covering half the links", half_and_half),
                          ("asks sweeping the count covered", size_swept)):
        say("   %s:" % name)
        say("     contention   damage   leftover squared   term read   fires   damage left")
        spread = None
        base = None
        base_after = None
        for hundredths in CONTENTION:
            plain = [contended(hundredths, builder, runs, rng, False) for _ in range(count)]
            fixed = [contended(hundredths, builder, runs, rng, True) for _ in range(count)]
            hurt = sum((one for one, _, _ in plain), Exact(0)) / count
            left = sum((three for _, _, three in plain), Exact(0)) / count
            terms = [two for _, two, _ in fixed]
            term = sum(terms, Exact(0)) / count
            after = sum((one for one, _, _ in fixed), Exact(0)) / count
            if spread is None:
                # the term's spread at no contention, held as its square: the mean square less the square of the mean
                spread = (sum((value * value for value in terms), Exact(0)) / count) - (term * term)
                base = hurt
                base_after = after
            # the term fires where it is positive and its square clears four times the spread's square
            fires = sum(1 for value in terms if (value > 0) and ((value * value) > (4 * spread)))
            shown = (figure("6 %s damage at %d" % (name, hundredths), hurt / base),
                     figure("6 %s leftover squared at %d" % (name, hundredths), left),
                     figure("6 %s term at %d" % (name, hundredths), term),
                     figure("6 %s fires percent at %d" % (name, hundredths), percent(fires, count)),
                     figure("6 %s damage left at %d" % (name, hundredths), after / base_after))
            say("     %10d   %s" % (hundredths, "   ".join(shown)))
            if builder is size_swept:
                swept.append((hundredths, hurt / base, percent(fires, count), after / base_after))
        say("")
    say("   Three readings, left to right. DAMAGE is how far the per-link answers have gone")
    say("   wrong, against no contention. LEFTOVER is what the fit could not account for, squared.")
    say("   FIRES is how often the term clears twice its own spread at no contention, the test")
    say("   this check puts, compared in squares.")
    say("")
    say("   The leftover barely moves while the damage arrives, because contention lands inside")
    say("   the additive answer: it comes back as plausible per-link numbers and leaves nothing")
    say("   over to read. The term fires where the leftover is still flat, because it is asked")
    say("   about what tells them apart. Contention grows as the square of how")
    say("   many links an ask covers and the links grow as the count, and an order of asks that")
    say("   never varies that count gives the difference nowhere to appear.")
    say("")
    say("   The last column is the same solve carrying the term. Reading for contention and")
    say("   taking it out are one operation, and it costs one more unknown and not one more ask.")
    return swept


def main():
    sys.set_int_max_str_digits(0)
    trials = TRIALS
    if "--trials" in sys.argv:
        trials = int(sys.argv[sys.argv.index("--trials") + 1])
    out = sys.stdout
    out.reconfigure(encoding="utf-8", errors="replace")

    def say(line=""):
        out.write("  " + line + "\n" if line else "\n")

    rng = random.Random(SEED)
    say("=" * 76)
    say("WHAT A COST READING RESOLVES")
    say("=" * 76)
    say("%d trials, seed %d, every cost in floors, every figure exact." % (trials, SEED))
    say()

    noise_squared, ordered = check_adjacent(say, rng, trials)
    say()
    kept, kept_ordered = check_repetition(say, rng, trials)
    say()
    gain = check_subsets(say, rng, trials)
    say()
    rode = check_carrier_gain(say, rng, trials)
    say()
    ratios, lost = check_known_against_drawn(say, rng, trials)
    say()
    swept = check_additive(say, rng, trials)
    say()

    say("=" * 76)
    say("WHAT THIS RUN SAYS")
    say("=" * 76)
    say("1  a link recovered by adjacent cuts carries %s floors squared of noise against a"
        % show(noise_squared))
    say("   signal of 1, and orders %s%% of pairs. Written as it stands, slicing does not measure a link."
        % show(ordered))
    say("2  repetition prunes misordered pairs down to %d repeats of every cut, which order %s%%."
        % (kept, show(kept_ordered)))
    say("3  one budget spent on covering asks beats the ladder by %s, squared, and the order it"
        % show(gain))
    say("   wants is one the emission already does.")
    say("4  a known order of asks beats one ask per link by %s, squared, at %d links. The squared"
        % (show(rode[-1][1]), rode[-1][0]))
    say("   gain is (links + 1) over four: one at three links, growing with the chain.")
    say("5  the known order wins by %s at the median worst-link error, %s at the 95th and %s"
        % tuple(show(ratio) for ratio in ratios))
    say("   at the worst, and %d drawn orders came apart not at all. An engine answering every" % lost)
    say("   time is held to its worst case.")
    say("6  where links contend the costs do not add. Over the asks sweeping the count covered:")
    for hundredths, damage, fires, after in swept:
        say("   at %d hundredths a pair the answers are %s as far off, the term fires on %s%%, and"
            % (hundredths, show(damage), show(fires)))
        say("   carried in the solve it leaves them %s as far off." % show(after))
    say()
    say("every figure in full: %s" % write_figures())
    say()
    say("Nothing above reaches a correctness result, and nothing above can. The noiseless half")
    say("is utils/maint/engine/order_check.py.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
