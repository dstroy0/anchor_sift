"""Magic is conserved by every free operation. The finality conserves, measured with exact nulls.

    python examples/00_blob_viz_tools/magic_conserves.py --check
    python examples/00_blob_viz_tools/magic_conserves.py             the conservation, and what breaks it
    python examples/00_blob_viz_tools/magic_conserves.py --distill    what a 5-to-1 protocol can and cannot do

THE CLAIM

On the QuEra logical magic state distillation result: "the finality conserves."

That is the resource theory of magic stated in three words and it is correct. Distillation does not
manufacture fidelity. It CONCENTRATES it: five noisy magic states become one cleaner state, and the
total quantity of magic does not rise. For that reason the protocol needs five inputs for one output
and not one for one.

WHY THAT MAKES CLIFFORD OPERATIONS FREE IN A STRICT SENSE

A magic monotone is any quantity that cannot increase under the free operations of the theory, and
the free operations are Clifford gates, Pauli measurement and classical post-processing. For a
single qubit the monotone is easy to write down exactly, and that leaves this testable here
and not in the abstract:

    F(psi) = max over the six stabilizer states of |<s|psi>|^2

The six are the Pauli eigenstates, the octahedron vertices recorded in bloch_reach.py. The
single-qubit Clifford group has 24 elements and PERMUTES those six. The maximum over them is
taken over the same set before and after. F is therefore EXACTLY invariant under Clifford, not
approximately, and that is the null this file is built on.

THE THREE THINGS THAT MUST HOLD, AND THE ONE THAT MUST NOT

    EXACT NULL      every Clifford gate leaves F unchanged to the arithmetic floor. Conservation.
    POSITIVE        the T gate changes F. If it did not, T would be free and Clifford plus T could
                    not be universal, a null here would refute the whole picture.
    EXACT VALUE     the magic state |A> = T|+> sits at F = cos^2(pi/8) = (2 + sqrt 2)/4, which is
                    a closed form to grade the measurement against and not a number to trust.
    MUST NOT        no sequence of free operations may raise F above its starting value. That is
                    the conservation law and it is checked by search and not by assertion.

WHAT THIS DOES NOT CLAIM ABOUT THE QuEra RESULT

Their achievement is that distillation worked on real atoms with real correlated noise and real
transport error. Nothing here reproduces that. This measures the protocol's resource accounting
under an exact noise model, the clean reference curve their noisy data sits against, and
it is a different statement from theirs.
"""

import argparse
import cmath
import math
import os
import sys

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import bloch_reach

ROOT_TWO = math.sqrt(2.0)
HALF_ROOT = 1.0 / ROOT_TWO


def stabilizer_fidelity(alpha, beta):
    """F(psi), the largest squared overlap with any of the six stabilizer states.

    Computed as a maximum over the six amplitude pairs and not from the Bloch vector. The
    quantity graded is the overlap itself and not a geometric restatement of it.
    """
    best = 0.0
    for _name, pair, _vector in bloch_reach.stabilizer_points():
        overlap = abs(pair[0].conjugate() * alpha + pair[1].conjugate() * beta) ** 2
        if overlap > best:
            best = overlap
    return best


def magic_of(alpha, beta):
    """How far from free this state is. Zero for every stabilizer state, positive otherwise."""
    return 1.0 - stabilizer_fidelity(alpha, beta)


# The free gates, which are the single-qubit Clifford generators. Everything in the 24 element group
# is a word in these. Invariance under these is invariance under all of it.
def gate_h(alpha, beta):
    return ((alpha + beta) * HALF_ROOT, (alpha - beta) * HALF_ROOT)


def gate_s(alpha, beta):
    return (alpha, beta * 1j)


def gate_x(alpha, beta):
    return (beta, alpha)


def gate_z(alpha, beta):
    return (alpha, -beta)


def gate_t(alpha, beta):
    """The one gate that is not free. pi/4 phase, exact from (1 + i)/sqrt(2)."""
    return (alpha, beta * cmath.exp(1j * math.pi / 4.0))


FREE_GATES = (("H", gate_h), ("S", gate_s), ("X", gate_x), ("Z", gate_z))


def magic_state():
    """|A> = T|+>, the state a distillation factory is built to produce."""
    return gate_t(HALF_ROOT + 0j, HALF_ROOT + 0j)


def _report():
    print("")
    print("  MAGIC IS 1 - F, where F is the largest squared overlap with any of the six")
    print("  stabilizer states. Zero magic means the state is free.")
    print("")

    cases = [
        ("|0>", (1 + 0j, 0 + 0j)),
        ("|+>", (HALF_ROOT + 0j, HALF_ROOT + 0j)),
        ("|A> = T|+>", magic_state()),
        ("T|0>", gate_t(1 + 0j, 0 + 0j)),
        ("T T|+>", gate_t(*magic_state())),
        ("H T|+>", gate_h(*magic_state())),
    ]

    print("  %-14s %14s %14s %s" % ("state", "F", "magic", "note"))
    for name, pair in cases:
        fidelity = stabilizer_fidelity(*pair)
        print("  %-14s %14.10f %14.10f %s"
              % (name, fidelity, 1.0 - fidelity,
                 "free, a stabilizer state" if (1.0 - fidelity) < 1e-12 else ""))

    exact = (2.0 + ROOT_TWO) / 4.0
    got = stabilizer_fidelity(*magic_state())
    print("")
    print("  |A> sits at F = cos^2(pi/8) = (2 + sqrt 2)/4")
    print("    closed form %.12f, measured %.12f, difference %.3e"
          % (exact, got, abs(exact - got)))
    print("")

    print("  THE CONSERVATION. Every free gate applied to |A>, and the magic it leaves behind.")
    print("")
    print("  %-8s %16s %16s %14s" % ("gate", "magic before", "magic after", "moved"))
    start = magic_state()
    before = magic_of(*start)
    for name, gate in FREE_GATES:
        after = magic_of(*gate(*start))
        print("  %-8s %16.12f %16.12f %14.3e" % (name, before, after, abs(after - before)))

    print("")
    print("  T, which is NOT free, for contrast:")
    after = magic_of(*gate_t(*start))
    print("  %-8s %16.12f %16.12f %14.3e" % ("T", before, after, abs(after - before)))
    print("")
    print("  READ THE NUMBERS, NOT THIS SENTENCE. Free gates move the magic by the arithmetic")
    print("  floor and T moves it by a real amount. Calling Clifford free means that,")
    print("  and it is the same shape as the twist leaving entanglement at exactly zero.")
    return 0


def _distill():
    """What a 5-to-1 protocol can do, in the resource accounting and not on hardware."""
    print("")
    print("  A 5-to-1 protocol takes five noisy magic states and returns one cleaner state.")
    print("  The resource accounting says what that can and cannot be.")
    print("")

    ideal = magic_of(*magic_state())
    print("  magic of a perfect |A>: %.12f" % ideal)
    print("")
    print("  %10s %18s %18s %16s %14s"
          % ("input err", "magic in, one", "magic in, five", "magic out max", "concentrated"))

    for error in (0.20, 0.10, 0.05, 0.02, 0.01):
        # A depolarized magic state: the Bloch vector shrinks toward the center by (1 - error).
        # Its stabilizer fidelity rises toward 1/2 + something. Its magic falls.
        alpha, beta = magic_state()
        # Mixing toward the maximally mixed state cannot be written as a pure amplitude pair.
        # The fidelity is computed from the Bloch vector directly: F = (1 + r . s)/2 maximized over
        # the six axis directions s, with r the shrunken Bloch vector.
        vector = bloch_reach.bloch_of(alpha, beta) * (1.0 - error)
        best = 0.0
        for _name, _pair, axis in bloch_reach.stabilizer_points():
            overlap = 0.5 * (1.0 + float(vector.dot(axis)))
            if overlap > best:
                best = overlap
        magic_in = 1.0 - best
        print("  %10.3f %18.12f %18.12f %16.12f %14s"
              % (error, magic_in, 5.0 * magic_in, 5.0 * magic_in,
                 "%.2fx" % (5.0 * magic_in / magic_in) if magic_in > 0 else "-"))

    print("")
    print("  THE BOUND IS THE POINT AND IT IS NOT A MEASUREMENT OF THEIR EXPERIMENT. Five inputs")
    print("  carry five times one input's magic, and the output cannot carry more than that sum.")
    print("  So the protocol trades QUANTITY for QUALITY: one state gets better by five getting")
    print("  spent. Nothing is created, as 'the finality conserves' says.")
    print("")
    print("  That is also why the ratio is five to one and not one to one, and why stacking")
    print("  three layers costs 5^3 = 125 raw states for one twice-distilled output. The QuEra")
    print("  result is that this survives real noise on real atoms. This is only the ledger.")
    return 0


def _check():
    failed = 0
    print("")

    floor = 1e-14

    # THE EXACT NULL. Every free gate must leave the magic unchanged, from every starting state.
    # Clifford permutes the six stabilizer states. The maximum over them is over the same set.
    worst = 0.0
    generator = numpy.random.default_rng(5)
    starts = [magic_state(), (1 + 0j, 0 + 0j), (HALF_ROOT + 0j, HALF_ROOT + 0j)]
    for _ in range(40):
        angle = generator.random() * math.pi
        phase = generator.random() * 2.0 * math.pi
        starts.append((math.cos(angle / 2.0) + 0j,
                       cmath.exp(1j * phase) * math.sin(angle / 2.0)))
    for start in starts:
        before = magic_of(*start)
        for _name, gate in FREE_GATES:
            after = magic_of(*gate(*start))
            worst = max(worst, abs(after - before))
    print("  every free gate conserves magic, worst movement %.3e over %d states"
          % (worst, len(starts)))
    if worst > floor:
        print("    FAIL a Clifford gate changed the magic. It is not free")
        failed += 1

    # AND NO WORD IN THE FREE GATES MAY RAISE IT. Conservation is an inequality. It is checked
    # by search over sequences and not by one application.
    start = magic_state()
    before = magic_of(*start)
    highest = before
    frontier = [start]
    for _depth in range(6):
        nxt = []
        for state in frontier:
            for _name, gate in FREE_GATES:
                moved = gate(*state)
                highest = max(highest, magic_of(*moved))
                nxt.append(moved)
        frontier = nxt[:200]
    print("  no free sequence to depth 6 raised it: start %.12f, highest %.12f" % (before, highest))
    if highest > before + floor:
        print("    FAIL a free sequence manufactured magic, which breaks conservation")
        failed += 1

    # THE POSITIVE CONTROL. T must move it, or the null above is satisfied by a dead measure.
    moved = abs(magic_of(*gate_t(1 + 0j, 0 + 0j)) - magic_of(1 + 0j, 0 + 0j))
    moved_plus = abs(magic_of(*gate_t(HALF_ROOT + 0j, HALF_ROOT + 0j))
                     - magic_of(HALF_ROOT + 0j, HALF_ROOT + 0j))
    print("  T moves the magic: on |0> by %.3e, on |+> by %.3e" % (moved, moved_plus))
    if moved_plus <= floor:
        print("    FAIL T did not change the magic. It would be free and nothing is universal")
        failed += 1

    # THE CLOSED FORM. |A> must sit at cos^2(pi/8) exactly, which grades the measure against
    # arithmetic and not against itself.
    exact = (2.0 + ROOT_TWO) / 4.0
    got = stabilizer_fidelity(*magic_state())
    print("  |A> fidelity measured %.14f against (2 + sqrt2)/4 = %.14f, gap %.3e"
          % (got, exact, abs(got - exact)))
    if abs(got - exact) > 1e-13:
        print("    FAIL the magic state is not where the closed form puts it")
        failed += 1

    # AND EVERY STABILIZER STATE MUST HAVE EXACTLY ZERO MAGIC, or the measure has an offset.
    worst = 0.0
    for _name, pair, _vector in bloch_reach.stabilizer_points():
        worst = max(worst, magic_of(*pair))
    print("  all six stabilizer states carry zero magic, worst %.3e" % worst)
    if worst > floor:
        print("    FAIL a free state carries magic. The measure has an offset")
        failed += 1

    print("")
    print("  %d check(s) failed" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="magic is conserved by every free operation")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--distill", action="store_true")
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0
    if args.distill:
        return _distill()
    return _report()


if __name__ == "__main__":
    sys.exit(main())
