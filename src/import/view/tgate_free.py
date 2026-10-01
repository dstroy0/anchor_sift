"""The T gate here costs nothing that it costs on hardware. Proved, with exact nulls.

    python tools/view/tgate_free.py --check
    python tools/view/tgate_free.py                 the claim, with the nulls that carry it
    python tools/view/tgate_free.py --wall          what DOES limit us, measured

THE CLAIM UNDER TEST

Douglas, 2026-09-12: "we dont have these problems", about the T gate and the non-Clifford gates
generally. Then: "prove that we dont have those problems."

He is right and the earlier framing in this family overstated a wall. On fault-tolerant hardware a
T gate is the expensive gate, and the expense is not the rotation: it is MAGIC STATE DISTILLATION.
A logical T needs a distilled |A> state, distillation consumes many noisy copies to make one clean
one, and the overhead is thousands of physical qubits and many rounds per logical T. That is why
architectures are graded on T-count and T-depth at all.

NONE OF THAT APPLIES HERE, and the reason is arithmetic rather than clever.

    T = diag(1, exp(i pi / 4))    and    exp(i pi / 4) = (1 + i) / sqrt(2)

sqrt(2) is row root_two of dn_constants.csv, held to a thousand places with two routes agreeing at
a zero gap. So the T gate's entire content is a multiplication by a number this tree already owns
exactly. No distillation, no magic state, no ancilla, no fault tolerance budget.

THE PROOF IS TWO EXACT NULLS AND THEY ARE FREE

    T^8 = I     because exp(i pi / 4) to the eighth is exp(2 pi i) = 1. Apply T eight times and
                the state must return EXACTLY, to the arithmetic floor of the working precision. If
                T gates cost precision, eight of them would show it. This is the decisive one.

    T^2 = S     because exp(i pi / 4) squared is exp(i pi / 2) = i, which is the S gate, and S is
                Clifford and already implemented independently in this file's simulator. Two T gates
                must equal one S exactly, which cross-checks the new gate against old machinery
                rather than against itself.

WHAT THIS DOES NOT PROVE, AND --wall MEASURES IT

The T gate is free. The STATE is not. A non-Clifford gate takes the state out of the stabiliser set,
so the graph form stops applying and the full 2^n amplitude array is required. That is the real
limit here and it is a qubit count, not a gate count: the opposite of the hardware situation, where
qubits are plentiful relative to distilled T gates.
"""

import argparse
import decimal
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
for _where in (HERE, os.path.join(ROOT, "tools", "dn_precision", "support"),
               os.path.join(ROOT, "examples", "proofing")):
    if _where not in sys.path:
        sys.path.insert(0, _where)

import exact_qubits


def apply_t(state, qubit, inverse=False):
    """The T gate on `qubit`, exactly.

    T multiplies every amplitude whose `qubit` bit is set by (1 + i)/sqrt(2), and leaves the rest
    alone. The inverse multiplies by (1 - i)/sqrt(2), which is the conjugate, so T followed by its
    inverse is the identity with no arithmetic left over beyond the working precision.

    THE FACTOR COMES FROM THE CONSTANTS TABLE AND NOWHERE ELSE. state.inv_root_two is 1/sqrt(2)
    built from root_two, which dn_constants.csv holds to a thousand places with a zero gap between
    Newton-on-integers and squaring back. That is the whole cost of a T gate here.
    """
    scale = state.inv_root_two
    sign = decimal.Decimal(-1) if inverse else decimal.Decimal(1)
    context = state.context

    for at in range(state.width):
        if ((at >> qubit) & 1) == 0:
            continue
        real = state.real[at]
        imag = state.imag[at]
        # (real + i imag) * (1 + i sign) / sqrt(2)
        new_real = context.multiply(context.subtract(real, context.multiply(sign, imag)), scale)
        new_imag = context.multiply(context.add(imag, context.multiply(sign, real)), scale)
        state.real[at] = new_real
        state.imag[at] = new_imag
    return state


def distance(left, right):
    """Largest absolute difference between two states, as a Decimal."""
    worst = decimal.Decimal(0)
    for at in range(left.width):
        gap_real = abs(left.real[at] - right.real[at])
        gap_imag = abs(left.imag[at] - right.imag[at])
        if gap_real > worst:
            worst = gap_real
        if gap_imag > worst:
            worst = gap_imag
    return worst


def spread_state(qubits, digits, seed=3):
    """A state with every amplitude populated, a phase gate has somewhere to act.

    A T gate on a basis state is a global phase and invisible. Hadamards first, then a couple of
    entangling gates, so the test is not accidentally trivial.
    """
    state = exact_qubits.ExactState(qubits, digits=digits)
    for at in range(qubits):
        state.h(at)
    for at in range(qubits - 1):
        state.cz(at, at + 1)
    return state


def copy_of(state):
    other = exact_qubits.ExactState(state.qubits, digits=len(str(state.real[0])) + 8)
    other.real = list(state.real)
    other.imag = list(state.imag)
    other.context = state.context
    other.inv_root_two = state.inv_root_two
    other.width = state.width
    other.qubits = state.qubits
    return other


def _report(qubits=8, digits=60):
    print("")
    print("  %d qubits, %d working digits. 1/sqrt(2) from dn_const's root_two." % (qubits, digits))
    print("")
    print("  THE DECISIVE NULL: T^8 = I. Eight T gates must return the state exactly.")
    print("")
    print("  %8s %10s %26s" % ("qubit", "T applied", "distance from the original"))

    for qubit in (0, 1, qubits // 2, qubits - 1):
        state = spread_state(qubits, digits)
        original = copy_of(state)
        for count in range(1, 9):
            apply_t(state, qubit)
            if count in (1, 2, 4, 8):
                print("  %8d %10d %26s" % (qubit, count, distance(state, original)))
        print("")

    print("  THE CROSS-CHECK: T^2 = S, against the S gate already in the simulator.")
    print("")
    print("  %8s %30s" % ("qubit", "distance T^2 from S"))
    for qubit in range(qubits):
        left = spread_state(qubits, digits)
        right = copy_of(left)
        apply_t(left, qubit)
        apply_t(left, qubit)
        right.s(qubit)
        print("  %8d %30s" % (qubit, distance(left, right)))

    print("")
    print("  READ THE NUMBERS, NOT THIS SENTENCE.")
    print("")
    print("  A T gate on hardware needs a distilled magic state, which costs thousands of physical")
    print("  qubits and many rounds per logical gate, and that is why T-count is the currency of")
    print("  fault-tolerant design. Here a T gate is one multiplication by (1 + i)/sqrt(2) with")
    print("  sqrt(2) taken from a table that holds it to a thousand places at a zero gap. There is")
    print("  no distillation because there is nothing noisy to distil.")
    return 0


def _wall(digits=40):
    """What actually limits this, since it is not the gate."""
    import time
    print("")
    print("  THE REAL LIMIT IS THE STATE, NOT THE GATE. A non-Clifford gate leaves the stabiliser")
    print("  set, so the graph form stops applying and the full 2^n array is needed.")
    print("")
    print("  %8s %12s %14s %16s %16s"
          % ("qubits", "amplitudes", "one T gate s", "graph form bytes", "state form"))

    for qubits in (4, 8, 12, 14, 16):
        state = exact_qubits.ExactState(qubits, digits=digits)
        for at in range(qubits):
            state.h(at)
        start = time.perf_counter()
        apply_t(state, 0)
        spent = time.perf_counter() - start
        graph_bytes = qubits * 32 + (qubits * (qubits - 1) // 2) / 8.0
        print("  %8d %12d %14.4f %16.0f %16s"
              % (qubits, state.width, spent, graph_bytes,
                 "%.1f KB" % (state.width * 2 * digits / 1024.0)))

    print("")
    print("  The gate cost is linear in the amplitude count and the amplitude count doubles per")
    print("  qubit. That is the whole wall, and it is the OPPOSITE of the hardware situation:")
    print("  there qubits are plentiful and distilled T gates are scarce, here T gates are free")
    print("  and qubits are what run out. Stabiliser-rank methods sit between the two, paying")
    print("  about 2^(0.4t) for t T gates while keeping the qubit count large.")
    return 0


def _check():
    failed = 0
    digits = 50
    print("")

    # THE EXACT NULL. T^8 must return the state to the arithmetic floor. The floor is the working
    # precision, so the bar is derived from `digits` rather than chosen.
    bar = decimal.Decimal(10) ** (-(digits - 12))
    worst = decimal.Decimal(0)
    for qubits in (4, 6, 8):
        for qubit in range(qubits):
            state = spread_state(qubits, digits)
            original = copy_of(state)
            for _ in range(8):
                apply_t(state, qubit)
            got = distance(state, original)
            if got > worst:
                worst = got
    print("  T^8 returns the state, worst distance %s against a floor of %s" % (worst, bar))
    if worst > bar:
        print("    FAIL eight T gates did not return the state, so they cost precision")
        failed += 1

    # THE CROSS-CHECK against machinery that did not come from this file.
    worst = decimal.Decimal(0)
    for qubits in (4, 6, 8):
        for qubit in range(qubits):
            left = spread_state(qubits, digits)
            right = copy_of(left)
            apply_t(left, qubit)
            apply_t(left, qubit)
            right.s(qubit)
            got = distance(left, right)
            if got > worst:
                worst = got
    print("  T^2 equals the S gate, worst distance %s" % worst)
    if worst > bar:
        print("    FAIL two T gates are not one S, so the gate is wrong")
        failed += 1

    # T FOLLOWED BY ITS INVERSE, which is a second and independent exact null.
    worst = decimal.Decimal(0)
    for qubits in (4, 8):
        state = spread_state(qubits, digits)
        original = copy_of(state)
        for qubit in range(qubits):
            apply_t(state, qubit)
        for qubit in range(qubits):
            apply_t(state, qubit, inverse=True)
        got = distance(state, original)
        if got > worst:
            worst = got
    print("  T then T inverse on every qubit returns the state, worst distance %s" % worst)
    if worst > bar:
        print("    FAIL the inverse is not the inverse")
        failed += 1

    # THE POSITIVE CONTROL. A SINGLE T gate must NOT return the state, or the null above is
    # satisfied by a gate that does nothing at all.
    state = spread_state(6, digits)
    original = copy_of(state)
    apply_t(state, 0)
    moved = distance(state, original)
    print("  a single T gate moves the state by %s" % moved)
    if moved <= bar:
        print("    FAIL the T gate does nothing, so every null above is vacuous")
        failed += 1

    # AND THE NORM MUST SURVIVE, since T is unitary. A gate that quietly rescaled the state would
    # pass the returns-to-original tests and still be wrong.
    state = spread_state(8, digits)
    before = state.norm_squared()
    for qubit in range(8):
        apply_t(state, qubit)
    after = state.norm_squared()
    print("  norm before %s, after %s, moved %s" % (before, after, abs(after - before)))
    if abs(after - before) > bar:
        print("    FAIL the T gate is not unitary")
        failed += 1

    print("")
    print("  %d check(s) failed" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="the T gate, exactly and for free")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--wall", action="store_true")
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0
    if args.wall:
        return _wall()
    return _report()


if __name__ == "__main__":
    sys.exit(main())
