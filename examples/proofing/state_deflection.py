"""Deflection read off the compression state, round by round, against a control of the same weight.

    python examples/proofing/state_deflection.py --check    the instrument on known answers
    python examples/proofing/state_deflection.py --sweep    deflection per round against the null

WHAT IS BEING ASKED

Whether the boundary reading sees structure in SHA-256's compression state, and at which round it
stops seeing it. The reading is taken on the state and not on the digest, because the digest is the
feed-forward of sixty four rounds and reading it answers a question about the wrong object.

THE OBJECTS LINE UP WITHOUT ANYBODY ARRANGING THEM. The reading is taken on a lit set over an eight
by thirty two ring placement, which is 256 points, and the compression state is eight words of
thirty two bits, which is 256 bits. So bit i of the state lights point i, and no mapping had to be
invented to make the instrument fit the object.

WHAT THE STATE IS, AND WHY EARLY ROUNDS CANNOT LOOK RANDOM

The round computes two words and shifts the rest:

    a' = T1 + T2      e' = d + T1
    b' = a            f' = e
    c' = b            g' = f
    d' = c            h' = g

So six of the eight words at round r are words from round r-1 in a new position. The state is a
shift register with two live inputs. Six eighths of the object is therefore last round's object
moved over, and a reading that sees the object as a placement is going to see that, because it is
there. This is the standard description of the compression function and not a finding; what is
measured below is how many rounds it takes before the reading stops being able to tell.

WHAT THE CONTROL IS

For each state, sets of the same weight drawn at random. Weight alone fixes the degree zero term
exactly, so comparing against a control of equal weight removes the one degree that carries no
information and leaves the comparison to the rest.

WHAT WOULD COUNT AS A FINDING, AND WHAT WOULD NOT

A large departure at one degree in one state is noise: eight degrees times many states will produce
large values by chance. A finding is the SAME degree departing in the SAME direction across many
independent messages. So the sweep reports the median across messages and not the best case, and it
reports how many messages agreed on the sign, which is the statistic a lucky draw cannot fake.
"""

import argparse
import math
import os
import random
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
VIEW = os.path.join(ROOT, "examples", "00_blob_viz_tools")
for where in (HERE, VIEW):
    if where not in sys.path:
        sys.path.insert(0, where)

import boundary_read
import natural_constants as nc

RINGS, WIDTH = 8, 32
TOTAL = RINGS * WIDTH
TOP = 8

MASK = 0xFFFFFFFF
ROUND_CONSTANT = nc.round_constants()
START = nc.starting_words()


def turn_right(value, by):
    return ((value >> by) | (value << (32 - by))) & MASK


def schedule_of(block):
    """The sixty four schedule words of one 512 bit block, given as sixteen words."""
    out = list(block)
    for at in range(16, 64):
        low = out[at - 15]
        high = out[at - 2]
        s0 = turn_right(low, 7) ^ turn_right(low, 18) ^ (low >> 3)
        s1 = turn_right(high, 17) ^ turn_right(high, 19) ^ (high >> 10)
        out.append((out[at - 16] + s0 + out[at - 7] + s1) & MASK)
    return out


def states_of(block, start=None):
    """The compression state after each round, as a list of sixty five eight word tuples.

    Entry zero is the state before any round runs, so entry r is the state after r rounds and the
    indexing needs no apology.
    """
    words = schedule_of(block)
    state = list(start if start is not None else START)
    out = [tuple(state)]
    for at in range(64):
        a, b, c, d, e, f, g, h = state
        s1 = turn_right(e, 6) ^ turn_right(e, 11) ^ turn_right(e, 25)
        choose = (e & f) ^ (~e & g)
        t1 = (h + s1 + choose + ROUND_CONSTANT[at] + words[at]) & MASK
        s0 = turn_right(a, 2) ^ turn_right(a, 13) ^ turn_right(a, 22)
        most = (a & b) ^ (a & c) ^ (b & c)
        t2 = (s0 + most) & MASK
        state = [(t1 + t2) & MASK, a, b, c, (d + t1) & MASK, e, f, g]
        out.append(tuple(state))
    return out


def lit_of(state):
    """The lit set of a state: point i is lit when bit i of the eight words is set."""
    out = []
    for slot, word in enumerate(state):
        for bit in range(32):
            if word & (1 << (31 - bit)):
                out.append(slot * 32 + bit)
    return out


def deflection_of(angles, live):
    """Power per degree for one lit set."""
    return boundary_read.deflection(boundary_read.complex_coefficients(angles, live, TOP), TOP)


def control_spread(angles, weight, draws, seed):
    """Mean and deviation of the deflection of random sets of a fixed weight, per degree."""
    state = random.Random(seed)
    rows = []
    for _ in range(draws):
        rows.append(deflection_of(angles, state.sample(range(TOTAL), weight)))
    out = []
    for degree in range(TOP + 1):
        column = [row[degree] for row in rows]
        out.append((statistics.fmean(column),
                    statistics.pstdev(column) if len(column) > 1 else 0.0))
    return out


def departures(angles, state, draws, seed):
    """How far each degree of one state sits from a same weight control, in control deviations."""
    live = lit_of(state)
    got = deflection_of(angles, live)
    spread = control_spread(angles, len(live), draws, seed)
    out = []
    for degree in range(TOP + 1):
        middle, wide = spread[degree]
        out.append(0.0 if wide == 0.0 else (got[degree] - middle) / wide)
    return out


def _blocks(count, seed):
    """Message blocks with nothing chosen about them."""
    state = random.Random(seed)
    return [[state.getrandbits(32) for _ in range(16)] for _ in range(count)]


def _check():
    lines = []
    failed = 0

    lines.append("  THE COMPRESSION AGREES WITH THE STANDARD")
    # The digest of the empty string, padded by hand, against the published value.
    block = [0x80000000] + [0] * 14 + [0]
    final = states_of(block)[64]
    digest = "".join("%08x" % ((START[at] + final[at]) & MASK) for at in range(8))
    wanted = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    agree = digest == wanted
    lines.append("    empty string digest  %s" % ("agrees" if agree else "DIFFERS"))
    if not agree:
        failed += 1
        lines.append("      got    %s" % digest)
        lines.append("      wanted %s" % wanted)
    lines.append("")

    lines.append("  THE SHIFT IS THERE, which is the claim the sweep rests on")
    states = states_of(_blocks(1, 5)[0])
    shifted = 0
    for at in range(1, 64):
        before, after = states[at], states[at + 1]
        # b',c',d' are a,b,c and f',g',h' are e,f,g. Six of eight words, every round.
        if (after[1], after[2], after[3]) == (before[0], before[1], before[2]) and \
           (after[5], after[6], after[7]) == (before[4], before[5], before[6]):
            shifted += 1
    lines.append("    %d of 63 rounds carry six of eight words unchanged in position" % shifted)
    if shifted != 63:
        failed += 1
    lines.append("")

    lines.append("  THE INSTRUMENT ON A KNOWN ANSWER")
    points = boundary_read.ring_place(RINGS, WIDTH)
    angles = boundary_read.as_angles(points)
    # A LIT SET WITH NO SYMMETRY ANYBODY CHOSE. Every second index was the first try, and it is
    # sixteen fold symmetric, so every non zonal degree sits at about 1e-30 and the reading has
    # almost nothing in it to move.
    live = [k for k in range(TOTAL) if (k * 7 + k // 5) % 3]
    one = deflection_of(angles, live)
    # ALONG EACH POINT'S OWN RING, which is what a turn about the ring axis is. Adding the ring
    # width to the index instead moves every point to the NEXT RING, which is a different set and
    # not a rotation of this one.
    turned = [(at // WIDTH) * WIDTH + (at % WIDTH + 7) % WIDTH for at in live]
    two = deflection_of(angles, turned)

    # AGAINST THE SCALE OF THE READING AND NOT AGAINST EACH DEGREE'S OWN VALUE. Dividing each gap
    # by its own degree lets the emptiest degree set the answer, which reported a sound instrument
    # as broken at 9.2e-01 while the harness that owns this null reads 2.5e-14 on it.
    scale = max(abs(value) for value in one) or 1.0
    moved = max(abs(one[d] - two[d]) for d in range(TOP + 1)) / scale
    lines.append("    deflection under a whole ring turn moved by %.3e" % moved)
    if moved > 1e-9:
        failed += 1
        lines.append("    THAT IS NOT A NULL and the reading cannot be trusted")
    lines.append("")

    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


def _sweep(messages, draws):
    points = boundary_read.ring_place(RINGS, WIDTH)
    angles = boundary_read.as_angles(points)
    blocks = _blocks(messages, 0x51F7)

    sys.stdout.write("  DEFLECTION OF THE COMPRESSION STATE, in control deviations\n\n")
    sys.stdout.write("  %6s %10s %10s %8s %s\n"
                     % ("round", "worst |z|", "at degree", "agreed", "reading"))
    sys.stdout.flush()

    for step in (1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64):
        rows = []
        for block in blocks:
            rows.append(departures(angles, states_of(block)[step], draws, 0xA13D + step))

        best_degree, best_median, best_agreed = 0, 0.0, 0
        for degree in range(1, TOP + 1):
            column = [row[degree] for row in rows]
            middle = statistics.median(column)
            agreed = max(sum(1 for one in column if one > 0), sum(1 for one in column if one < 0))
            if abs(middle) > abs(best_median):
                best_degree, best_median, best_agreed = degree, middle, agreed

        # A median past two deviations that most messages agree on is the thing worth a second look.
        loud = abs(best_median) > 2.0 and best_agreed >= 0.8 * len(blocks)
        sys.stdout.write("  %6d %10.2f %10d %7d/%d %s\n"
                         % (step, best_median, best_degree, best_agreed, len(blocks),
                            "STRUCTURE" if loud else "indistinguishable"))
        sys.stdout.flush()

    sys.stdout.write("\n  A round reading indistinguishable is one where this instrument cannot\n")
    sys.stdout.write("  separate the state from a random set of the same weight. That is a\n")
    sys.stdout.write("  statement about the instrument and not a claim about SHA-256.\n")
    return 0


def concentration(power):
    """How few degrees carry the power, as a participation ratio over degrees one and up.

    The sum of the spectrum squared against the square of its sum. One means every degree carries
    the same power, which is the flattest a spectrum gets; the count of degrees means one degree
    carries everything. Degree zero is left out because it is fixed by the weight alone and would
    report the same number for every set of the same size.

    Reported divided by the degree count, so the answer runs from near zero for a concentrated
    spectrum to one for a flat one and does not change meaning when the degree changes.
    """
    rest = [value for value in power[1:] if value > 0.0]
    if not rest:
        return 1.0
    total = sum(rest)
    squares = sum(value * value for value in rest)
    return (total * total / squares) / len(rest) if squares > 0.0 else 1.0


def zonal_dipole(angles, live):
    """The degree one, order zero coefficient: the lit set's displacement along the polar axis.

    This is the quantity a cone sitting at one pole rather than the other IS. Taken as the signed
    coefficient and not its magnitude, because the sign is the whole question.
    """
    table = boundary_read.complex_coefficients(angles, live, TOP)
    real, _ = table.get((1, 0), (0.0, 0.0))
    return real


def sign_runs(values):
    """How many runs of constant sign a sequence has, and what independence would predict.

    A run is a maximal stretch of one sign. Independent signs give
    `2 n1 n2 / (n1 + n2) + 1` runs on average with a known variance, so the count is a test of
    autocorrelation that assumes nothing about the distribution of the values themselves. Fewer runs
    than predicted means the sequence drifts; more means it alternates.
    """
    signs = [1 if one > 0 else -1 for one in values if one != 0.0]
    if len(signs) < 2:
        return 0, 0.0, 0.0, 0.0
    runs = 1
    for at in range(1, len(signs)):
        if signs[at] != signs[at - 1]:
            runs += 1
    ups = sum(1 for one in signs if one > 0)
    downs = len(signs) - ups
    if ups == 0 or downs == 0:
        return runs, float(runs), 0.0, 0.0
    total = ups + downs
    middle = 2.0 * ups * downs / total + 1.0
    spread = (2.0 * ups * downs * (2.0 * ups * downs - total)) / (total * total * (total - 1.0))
    spread = math.sqrt(spread) if spread > 0.0 else 0.0
    score = 0.0 if spread == 0.0 else (runs - middle) / spread
    return runs, middle, spread, score


def _runs(messages, draws):
    """The autocorrelation of the dipole across rounds, against states that carry nothing over.

    The real sequence cannot jump, because six of eight words at round r are round r-1's words in a
    new position. So a drifting dipole is exactly what the shift register predicts, and reporting
    that drift as a finding without this control would be reporting the compression function's
    published structure as a discovery.

    The control replaces the round sequence with INDEPENDENT states of the same weights. Everything
    else is identical: same placement, same reading, same test. If the real sequence shows fewer
    runs and the control does not, the carryover accounts for it.
    """
    points = boundary_read.ring_place(RINGS, WIDTH)
    angles = boundary_read.as_angles(points)
    block = [0x80000000] + [0] * 15
    states = states_of(block)
    control = random.Random(0x5EED)

    real = [zonal_dipole(angles, lit_of(states[r])) for r in range(1, 65)]
    weights = [len(lit_of(states[r])) for r in range(1, 65)]

    sys.stdout.write("  DIPOLE AUTOCORRELATION ACROSS ROUNDS\n\n")
    sys.stdout.write("  %-34s %6s %9s %8s\n" % ("sequence", "runs", "expected", "z"))
    sys.stdout.flush()

    runs, middle, _, score = sign_runs(real)
    sys.stdout.write("  %-34s %6d %9.1f %8.2f\n"
                     % ("the real rounds, with carryover", runs, middle, score))
    sys.stdout.flush()

    # The control, repeated, so one lucky draw cannot stand for the whole answer.
    scores = []
    for _ in range(draws):
        made = []
        for weight in weights:
            made.append(zonal_dipole(angles, control.sample(range(TOTAL), weight)))
        scores.append(sign_runs(made)[3])
    middle_control = statistics.fmean(scores)
    spread_control = statistics.pstdev(scores) if len(scores) > 1 else 0.0
    sys.stdout.write("  %-34s %6s %9s %8.2f\n"
                     % ("independent states, %d draws" % draws, "-", "-", middle_control))
    sys.stdout.write("      control spread %.2f, so the real z sits %.1f control deviations out\n"
                     % (spread_control,
                        0.0 if spread_control == 0.0 else (score - middle_control) / spread_control))
    sys.stdout.write("\n")

    if score < -2.0 and abs(middle_control) < 1.0:
        sys.stdout.write("  The real sequence drifts and the control does not, so the carryover\n")
        sys.stdout.write("  accounts for it. That is the shift register, seen in the reading.\n")
    else:
        sys.stdout.write("  The two do not separate, so this reading does not show the carryover.\n")
    return 0


def _shape(messages, draws):
    """The two degrees that ARE the shape described: the dipole and the quadrupole.

    A cone sitting at one pole rather than the other is degree one, since that is what a dipole is:
    the whole set displaced along an axis. An elongation, a lemon, is degree two. Every statistic
    that averages over degrees washes both of them out, which is what the concentration reading
    did, so these two are taken on their own and against their own controls.
    """
    points = boundary_read.ring_place(RINGS, WIDTH)
    angles = boundary_read.as_angles(points)
    block = [0x80000000] + [0] * 15
    states = states_of(block)
    control = random.Random(0xC0FFEE)

    sys.stdout.write("  THE DIPOLE AND THE QUADRUPOLE, which are the cone and the lemon\n\n")
    sys.stdout.write("  %6s %7s %10s %8s %10s %8s\n"
                     % ("round", "weight", "P1", "z(P1)", "P2", "z(P2)"))
    sys.stdout.flush()

    loud = 0
    for step in list(range(1, 65, 4)) + [64]:
        live = lit_of(states[step])
        power = deflection_of(angles, live)

        ones, twos = [], []
        for _ in range(draws):
            pick = control.sample(range(TOTAL), len(live))
            shuffled = deflection_of(angles, pick)
            ones.append(shuffled[1])
            twos.append(shuffled[2])

        row = []
        for degree, column in ((1, ones), (2, twos)):
            middle = statistics.fmean(column)
            wide = statistics.pstdev(column) if len(column) > 1 else 0.0
            row.append((power[degree], 0.0 if wide == 0.0 else (power[degree] - middle) / wide))
        if max(abs(row[0][1]), abs(row[1][1])) > 3.0:
            loud += 1

        sys.stdout.write("  %6d %7d %10.4f %8.2f %10.4f %8.2f\n"
                         % (step, len(live), row[0][0], row[0][1], row[1][0], row[1][1]))
        sys.stdout.flush()

    sys.stdout.write("\n  %d round(s) past three deviations on either degree.\n" % loud)
    return 0


def _coherence(messages, draws):
    points = boundary_read.ring_place(RINGS, WIDTH)
    angles = boundary_read.as_angles(points)

    # The padded empty message, so the states match the page and the published digest exactly.
    block = [0x80000000] + [0] * 15
    states = states_of(block)

    control = random.Random(0xC0FFEE)
    sys.stdout.write("  COHERENCE OF THE SHAPE, round by round\n\n")
    sys.stdout.write("  %6s %7s %12s %12s %9s\n"
                     % ("round", "weight", "concentration", "control", "z"))
    sys.stdout.flush()

    for step in (1, 2, 4, 8, 12, 16, 24, 32, 40, 48, 56, 64):
        live = lit_of(states[step])
        got = concentration(deflection_of(angles, live))

        shuffled = []
        for _ in range(draws):
            pick = control.sample(range(TOTAL), len(live))
            shuffled.append(concentration(deflection_of(angles, pick)))
        middle = statistics.fmean(shuffled)
        wide = statistics.pstdev(shuffled) if len(shuffled) > 1 else 0.0
        score = 0.0 if wide == 0.0 else (got - middle) / wide

        sys.stdout.write("  %6d %7d %12.5f %12.5f %9.2f\n"
                         % (step, len(live), got, middle, score))
        sys.stdout.flush()

    sys.stdout.write("\n  Concentration near one is a flat spectrum. The control is sets of the\n")
    sys.stdout.write("  same weight with no structure, so z is how far the state sits from a\n")
    sys.stdout.write("  shuffle of itself and not from an assumption about what random means.\n")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="deflection on the compression state")
    parser.add_argument("--coherence", action="store_true", help="shape concentration per round")
    parser.add_argument("--shape", action="store_true", help="the dipole and quadrupole per round")
    parser.add_argument("--runs", action="store_true", help="dipole autocorrelation against a control")
    parser.add_argument("--check", action="store_true", help="grade the instrument")
    parser.add_argument("--sweep", action="store_true", help="deflection per round against a null")
    parser.add_argument("--messages", type=int, default=24, help="how many messages")
    parser.add_argument("--draws", type=int, default=64, help="control sets per reading")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.sweep:
        sys.exit(_sweep(args.messages, args.draws))
    if args.coherence:
        sys.exit(_coherence(args.messages, args.draws))
    if args.shape:
        sys.exit(_shape(args.messages, args.draws))
    if args.runs:
        sys.exit(_runs(args.messages, args.draws))
    parser.print_help()
