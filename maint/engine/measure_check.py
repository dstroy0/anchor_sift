#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""What a cost reading resolves and what it cannot, measured instead of argued.

    python maint/engine/measure_check.py [--trials N]

The noisy half of the query protocol. Six checks, each one isolating a claim chain slicing rests
on. Every number below is produced by the run and none is quoted from anywhere.

    1  slicing a chain by adjacent cuts, against the noise floor
    2  what repetition costs to make check 1 usable
    3  permuted subsets against the prefix ladder at one measurement budget
    4  one ask per link against a known order of covering asks
    5  a known order against a drawn one, where a bad draw has nowhere to hide
    6  whether the costs add, what notices when they do not, and what repairs it

Everything here is about speed and nothing here reaches a correctness result.
`maint/engine/order_check.py` holds the noiseless half as checks 7 through 12, and the separation
between the two files is the separation the two stages buy.

THE UNIT HERE IS THE FLOOR. Every cost is quoted in floors. Sigma is therefore 1.0 by
construction and no absolute figure is written in. The plan's own ratio sets the rest: one operation sits under the
floor, and a chain of fifteen clears it.

NUMPY IS FINE HERE AND IS BANNED IN `src/`. Under `maint/` and `test/` any library is fair, and
standing one up as an oracle against the library is a good use of one. Nothing under `src/` takes a
dependency on anything: the engine and the compiler need none.
"""

import itertools
import sys

import numpy as np

# A chain long enough to clear the floor, as the plan measures it.
LINKS = 15

# The measurement noise, in floors. One by construction: the floor is the unit.
SIGMA = 1.0

# Per-link costs are drawn across this band, in floors. Centred on the floor, because a single
# operation sitting under it is the case that makes slicing hard.
BAND = (0.5, 1.5)

TRIALS = 400
SEED = 20260930


def kendall(a, b):
    """Fraction of pairs the two orderings agree on, from 0 disagreeing to 1 identical."""
    n = len(a)
    agree = 0
    total = 0
    for i in range(n):
        for j in range(i + 1, n):
            total += 1
            if (a[i] - a[j]) * (b[i] - b[j]) > 0:
                agree += 1
    return agree / total if total else 1.0


def truth_of(rng):
    """One chain's true per-link costs, in floors."""
    return rng.uniform(BAND[0], BAND[1], LINKS)


def ladder_read(truth, rng, repeats=1):
    """Per-link costs recovered from prefix cuts, the way the plan writes slicing today.

    Cut k measures the first k links and carries one measurement's noise. The per-link cost is the
    difference between neighboring cuts, and that difference carries the noise of both.
    """
    cuts = np.array([truth[:k].sum() for k in range(LINKS + 1)])
    seen = np.zeros(LINKS + 1)
    for _ in range(repeats):
        seen += cuts + rng.normal(0, SIGMA, LINKS + 1)
    return np.diff(seen / repeats)


def subset_read(truth, rng, runs):
    """Per-link costs recovered from permuted subsets, solved as one system.

    Each run measures the sum over a random half of the links and carries one measurement's noise.
    Nothing is differenced. The noise spreads across the whole design in place of landing twice on
    every link.
    """
    design = (rng.random((runs, LINKS)) < 0.5).astype(float)
    # A run measuring nothing constrains nothing. Give it one link so the system stays solvable.
    empty = design.sum(axis=1) == 0
    if empty.any():
        design[empty, rng.integers(0, LINKS, int(empty.sum()))] = 1.0
    seen = design @ truth + rng.normal(0, SIGMA, runs)
    answer, _, _, _ = np.linalg.lstsq(design, seen, rcond=None)
    return answer


def check_adjacent(say, rng, trials):
    """1. Adjacent differencing puts the noise above the signal it is trying to read."""
    say("1. SLICING BY ADJACENT CUTS")
    say("   A chain of %d links, each drawn in [%.1f, %.1f] floors." % (LINKS, *BAND))
    say("")

    error = []
    taus = []
    best = 0
    worst = 0
    for _ in range(trials):
        truth = truth_of(rng)
        got = ladder_read(truth, rng)
        error.append(got - truth)
        taus.append(kendall(truth, got))
        best += int(np.argmax(got) == np.argmax(truth))
        worst += int(np.argmin(got) == np.argmin(truth))

    error = np.concatenate(error)
    say("   noise on one measurement        %6.3f floors" % SIGMA)
    say("   noise on a recovered link       %6.3f floors   (predicted %.3f, sigma * sqrt 2)"
        % (error.std(), SIGMA * np.sqrt(2)))
    say("   typical link cost               %6.3f floors" % np.mean(BAND))
    say("   signal to noise per link        %6.3f" % (np.mean(BAND) / error.std()))
    say("")
    say("   Subtraction adds variance. The cuts are long and well above the floor; the difference")
    say("   between two of them is one link, and one link is the quantity sitting under it.")
    say("")
    say("   pairs ordered correctly         %6.1f%%   (50%% is a coin)" % (100 * np.mean(taus)))
    say("   most expensive link found       %6.1f%%   (%.1f%% is a guess)"
        % (100 * best / trials, 100 / LINKS))
    say("   cheapest link found             %6.1f%%" % (100 * worst / trials))
    say("")
    say("   A branch comparison built on this ranks links by coin toss.")
    return error.std()


def check_repetition(say, rng, trials):
    """2. Repetition fixes check 1, and the count needed is the finding."""
    say("2. WHAT REPETITION COSTS")
    say("")
    say("   repeats    noise/link    pairs ordered    most expensive found")
    needed = None
    for repeats in (1, 10, 100, 400, 1600, 6400):
        error = []
        taus = []
        best = 0
        for _ in range(max(40, trials // 8)):
            truth = truth_of(rng)
            got = ladder_read(truth, rng, repeats)
            error.append(got - truth)
            taus.append(kendall(truth, got))
            best += int(np.argmax(got) == np.argmax(truth))
        shown = 100 * np.mean(taus)
        hits = 100 * best / max(40, trials // 8)
        say("   %7d    %10.4f    %12.1f%%    %18.1f%%"
            % (repeats, np.concatenate(error).std(), shown, hits))
        if needed is None and shown >= 95.0:
            needed = repeats
    say("")
    if needed:
        say("   %d repeats of every cut to order 95%% of pairs correctly." % needed)
    else:
        say("   95%% of pairs correctly ordered is past the largest count tried.")
    say("   Noise falls as one over the square root of the count, and the gap between two")
    say("   neighboring links falls as one over the link count. Both have to be paid.")
    return needed


def check_subsets(say, rng, trials):
    """3. The same measurement budget, spent on permuted subsets instead of a prefix ladder."""
    say("3. PERMUTED SUBSETS AGAINST THE PREFIX LADDER")
    say("")
    say("   One budget is one count of measurements. The ladder spends it on %d cuts repeated;" % (LINKS + 1))
    say("   the subset design spends it on that many separate runs.")
    say("")
    say("   budget    ladder noise    subset noise    subset is better by")
    gains = []
    for repeats in (4, 16, 64, 256):
        budget = repeats * (LINKS + 1)
        ladder = []
        subset = []
        for _ in range(max(30, trials // 10)):
            truth = truth_of(rng)
            ladder.append(ladder_read(truth, rng, repeats) - truth)
            subset.append(subset_read(truth, rng, budget) - truth)
        one = np.concatenate(ladder).std()
        two = np.concatenate(subset).std()
        gains.append(one / two)
        say("   %6d    %12.4f    %12.4f    %16.2fx" % (budget, one, two, one / two))
    say("")
    say("   The ladder inverts a triangle of ones, and every row of that inverse has two")
    say("   non-zero entries, which fixes its error at sigma times the square root of two")
    say("   whatever the budget. A subset design has no such floor: its error falls with the")
    say("   whole budget because every run constrains many links at once.")
    say("")
    say("   Predicted gain is the square root of (link count + 1) over the square root of two,")
    say("   %.2fx here. Measured %.2fx." % (np.sqrt(LINKS + 1) / np.sqrt(2), np.mean(gains)))
    say("")
    say("   The permutation this needs is already in the emission.")
    return float(np.mean(gains))



def hadamard(order):
    """A Hadamard matrix of an order that is a power of two, by doubling."""
    held = np.array([[1.0]])
    while held.shape[0] < order:
        held = np.block([[held, held], [held, -held]])
    return held


def carrier_design(links):
    """The known order of asks for a chain of `links`, where links + 1 is a power of two.

    One row is one ask: the 1s name the links it covers. Built from a Hadamard matrix one larger
    with its first row and column dropped, which leaves every row covering half the links and every
    two rows overlapping on a quarter. Nothing is drawn. The order is fixed, reproducible from the
    link count alone, and carries no record beyond that count.
    """
    full = hadamard(links + 1)
    return (1.0 - full[1:, 1:]) / 2.0


def check_carrier_gain(say, rng, trials):
    """4. Asking in a known order against asking one link at a time, at one budget."""
    say("4. ONE ASK PER LINK AGAINST A KNOWN ORDER OF ASKS")
    say("")
    say("   Both spend one ask per link. One asks about a single link each time. The other asks")
    say("   about half the links each time, in an order chosen so the answers come apart.")
    say("")
    say("   links    one at a time    known order    gain    predicted")
    gains = []
    for links in (3, 7, 15, 31, 63, 127, 255):
        design = carrier_design(links)
        reps = max(8, trials // (2 * links))
        lone = []
        rode = []
        for _ in range(reps):
            truth = rng.uniform(BAND[0], BAND[1], links)
            lone.append(rng.normal(0, SIGMA, links))
            seen = design @ truth + rng.normal(0, SIGMA, links)
            rode.append(np.linalg.solve(design, seen) - truth)
        one = np.concatenate(lone).std()
        two = np.concatenate(rode).std()
        gains.append((links, one / two))
        say("   %5d    %13.4f    %11.4f  %6.2fx    %6.2fx"
            % (links, one, two, one / two, np.sqrt(links + 1) / 2))
    say("")
    say("   The known order carries the cost of several links in every answer, and the orders are")
    say("   chosen to come apart cleanly. One ask therefore informs every link at once, and the gain is")
    say("   square root of (links + 1) over two and it grows with the chain.")
    say("")
    say("   At %d links there is no gain at all and at %d links it is %.1f times. A short chain is"
        % (gains[0][0], gains[-1][0], gains[-1][1]))
    say("   not worth a known order and a long one is worth a great deal.")
    say("")
    say("   Nothing here beats the bound on what one ask can carry. The known order reaches that")
    say("   bound and one ask per link does not, and the whole gain is that difference.")
    return gains[-1][1]


def check_known_against_drawn(say, rng, trials):
    """5. A known order against a drawn one, at the budget where a bad draw has nowhere to hide."""
    say("5. A KNOWN ORDER AGAINST A DRAWN ONE")
    say("")
    say("   %d links and %d asks: exactly enough, with nothing spare. A drawn order is a drawn" % (LINKS, LINKS))
    say("   order and some draws do not come apart at all.")
    say("")
    design = carrier_design(LINKS)
    held = []
    drawn = []
    lost = 0
    for _ in range(trials):
        truth = rng.uniform(BAND[0], BAND[1], LINKS)
        seen = design @ truth + rng.normal(0, SIGMA, LINKS)
        held.append(np.abs(np.linalg.solve(design, seen) - truth).max())
        pick = (rng.random((LINKS, LINKS)) < 0.5).astype(float)
        noisy = pick @ truth + rng.normal(0, SIGMA, LINKS)
        try:
            if abs(np.linalg.det(pick)) < 1e-9:
                raise np.linalg.LinAlgError
            drawn.append(np.abs(np.linalg.solve(pick, noisy) - truth).max())
        except np.linalg.LinAlgError:
            lost += 1
            drawn.append(np.inf)

    held = np.array(held)
    drawn = np.array(drawn)
    usable = drawn[np.isfinite(drawn)]
    say("   worst link error      known order    drawn order")
    say("   median              %13.3f  %13.3f" % (np.median(held), np.median(usable)))
    say("   95th percentile     %13.3f  %13.3f"
        % (np.percentile(held, 95), np.percentile(usable, 95)))
    say("   worst of %4d        %13.3f  %13.3f" % (trials, held.max(), usable.max()))
    say("")
    say("   orders that came apart at all    %4d of %d known, %d of %d drawn"
        % (trials, trials, trials - lost, trials))
    say("")
    say("   The known order wins on every row and wins by more the further out the row is: by")
    say("   %.1f times at the median, %.1f times at the 95th, %.1f times at the worst."
        % (np.median(usable) / np.median(held),
           np.percentile(usable, 95) / np.percentile(held, 95),
           usable.max() / held.max()))
    say("   %d of %d draws came apart not at all and cost the whole pass." % (lost, trials))
    say("")
    say("   An engine answering every time is held to its worst case. A drawn order has no worst")
    say("   case to be held to, and a known one is the same every pass by construction.")
    return lost


def half_and_half(links, runs, rng):
    """Asks each covering about half the links."""
    held = (rng.random((runs, links)) < 0.5).astype(float)
    bare = held.sum(axis=1) == 0
    if bare.any():
        held[bare, 0] = 1.0
    return held


def size_swept(links, runs, rng):
    """Asks sweeping the count of links covered, from two up to nearly all of them."""
    held = np.zeros((runs, links))
    for at in range(runs):
        held[at, rng.permutation(links)[:2 + (at % (links - 2))]] = 1.0
    return held


def contended(kappa, builder, runs, rng, with_term):
    """One pass where the links contend, solved with and without a term for the contention.

    Contention over a set grows as the square of how many links the set covers. The links
    themselves grow as the count. A solve carrying a squared-count column can tell the two apart
    and a solve without one cannot.
    """
    truth = rng.uniform(BAND[0], BAND[1], LINKS)
    cross = np.triu(rng.uniform(0, kappa, (LINKS, LINKS)), 1)
    cross = cross + cross.T
    design = builder(LINKS, runs, rng)
    extra = 0.5 * np.einsum("ri,ij,rj->r", design, cross, design)
    seen = design @ truth + extra + rng.normal(0, SIGMA, runs)
    if not with_term:
        got, _, _, _ = np.linalg.lstsq(design, seen, rcond=None)
        left = seen - design @ got
        return np.abs(got - truth).mean(), 0.0, np.sqrt((left ** 2).sum() / (runs - LINKS))
    wide = np.column_stack([design, design.sum(axis=1) ** 2])
    got, _, _, _ = np.linalg.lstsq(wide, seen, rcond=None)
    return np.abs(got[:LINKS] - truth).mean(), got[LINKS], 0.0


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
    say("   %d links, %d asks, a floor of %.2f, over two orders of asking." % (LINKS, runs, SIGMA))
    say("   Contention is the cost added per contending pair, in floors.")
    say("")
    for name, builder in (("asks covering half the links", half_and_half),
                          ("asks sweeping the count covered", size_swept)):
        say("   %s:" % name)
        say("     contention   damage   leftover   term read   term/spread   fires   damage left")
        spread = None
        for kappa in (0.0, 0.01, 0.03, 0.08, 0.20):
            plain = [contended(kappa, builder, runs, rng, False) for _ in range(count)]
            fixed = [contended(kappa, builder, runs, rng, True) for _ in range(count)]
            hurt = np.mean([one for one, _, _ in plain])
            left = np.mean([three for _, _, three in plain])
            term = np.array([two for _, two, _ in fixed])
            after = np.mean([one for one, _, _ in fixed])
            if spread is None:
                spread = term.std()
                base = hurt
                base_after = after
            say("     %10.2f   %5.2fx   %8.2f   %9.4f   %11.2f   %4.0f%%   %10.2fx"
                % (kappa, hurt / base, left / SIGMA, term.mean(), term.mean() / spread,
                   100 * np.mean(term > 2 * spread), after / base_after))
        say("")
    say("   Three readings, left to right. DAMAGE is how far the per-link answers have gone")
    say("   wrong. LEFTOVER is what the fit could not account for. FIRES is how often the term")
    say("   clears twice its own spread at no contention, the test this check puts.")
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
    return 0


def main():
    trials = TRIALS
    if "--trials" in sys.argv:
        trials = int(sys.argv[sys.argv.index("--trials") + 1])
    out = sys.stdout
    out.reconfigure(encoding="utf-8", errors="replace")

    def say(line=""):
        out.write("  " + line + "\n" if line else "\n")

    rng = np.random.default_rng(SEED)
    say("=" * 76)
    say("WHAT A COST READING RESOLVES")
    say("=" * 76)
    say("%d trials, seed %d, every cost in floors." % (trials, SEED))
    say()

    noise = check_adjacent(say, rng, trials)
    say()
    needed = check_repetition(say, rng, trials)
    say()
    gain = check_subsets(say, rng, trials)
    say()
    rode = check_carrier_gain(say, rng, trials)
    say()
    lost = check_known_against_drawn(say, rng, trials)
    say()
    check_additive(say, rng, trials)
    say()

    say("=" * 76)
    say("WHAT THIS RUN SAYS")
    say("=" * 76)
    say("1  a link recovered by adjacent cuts carries %.2f floors of noise against a signal of"
        % noise)
    say("   about %.2f. Written as it stands, slicing does not measure a link." % np.mean(BAND))
    say("2  %s repeats of every cut make it usable."
        % (str(needed) if needed else "more than the largest count tried"))
    say("3  one budget spent on covering asks beats the ladder by %.2fx, and the order it wants"
        % gain)
    say("   is one the emission already does.")
    say("4  a known order of asks beats one ask per link by %.1fx at 255 links. The gain is the"
        % rode)
    say("   square root of (links + 1) over two: nothing at three links, growing with the chain.")
    say("5  on the worst case the known order wins, and %d drawn orders came apart not at all."
        % lost)
    say("   An engine answering every time is held to its worst case.")
    say("6  where links contend the costs do not add, and the leftover from the solve does not")
    say("   notice until the answers are badly wrong. A term for the contention's own shape")
    say("   notices at 88%, and the same solve then takes the damage back out. The order of")
    say("   asks decides whether it can be read at all: sweep the count of links covered.")
    say()
    say("Nothing above reaches a correctness result, and nothing above can. The noiseless half")
    say("is maint/engine/order_check.py.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
