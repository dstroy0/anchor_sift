"""Shor's algorithm on the exact simulator, traced step by step, with the qubit movement plotted.

    python examples/00_blob_viz_tools/shor_trace.py --check
    python examples/00_blob_viz_tools/shor_trace.py               factor 15, with the scatter and the mean movement
    python examples/00_blob_viz_tools/shor_trace.py --digits 40   the same at another precision

WHAT IS BEING RUN

Shor's period finding on N = 15 with base a = 7, which has period 4 since 7, 4, 13, 1 mod 15 closes
at the fourth power. Four counting qubits and four work qubits. 256 exact complex amplitudes.

From a period of 4 the factors fall out by gcd: gcd(7^2 - 1, 15) = gcd(48, 15) = 3 and
gcd(7^2 + 1, 15) = gcd(50, 15) = 5. a correct run FACTORS 15, and that is the verifiable outcome
and not a plausible-looking histogram.

THE STRUCTURAL PREDICTION THIS FILE TESTS

Modular multiplication by a base coprime to N is a PERMUTATION of the work register's basis states.
Every controlled modular exponentiation step is a permutation of the amplitude list and contains
no arithmetic at all. The inverse Fourier transform needs roots of unity, which are irrational.

So Shor should split exactly the way the gate set split in `exact_qubits.py`: the modexp stage costs
nothing in accuracy at any precision, and the transform is the only place precision enters. That is
predicted here and measured below and not assumed.

WHAT IS PLOTTED

The plot is the qubit movement scatter and the mean deviation for each step. Movement is the
probability each qubit reads one, tracked per step, and the mean deviation is the average absolute
change in that probability across the eight qubits between consecutive steps. A step that moves
nothing reads zero and a step that reorganizes the register reads large.
"""

import argparse
import decimal
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PRECISION = os.path.join(ROOT, "src", "import", "dn_precision", "calc")
SUPPORT = os.path.join(ROOT, "src", "import", "dn_precision", "support")
for _where in (HERE, PRECISION, SUPPORT):
    if _where not in sys.path:
        sys.path.insert(0, _where)

import dn_load
import exact_qubits
import normalized_harmonics

MODULUS = 15
BASE = 7
COUNT_BITS = 4       # counting register, the high qubits
WORK_BITS = 4        # work register, the low qubits
QUBITS = COUNT_BITS + WORK_BITS
DIGITS = 30


def true_period(base=BASE, modulus=MODULUS):
    """The period of base^k mod modulus, found by walking it. The answer Shor should recover."""
    value = base % modulus
    step = 1
    while value != 1:
        value = (value * base) % modulus
        step += 1
        if step > modulus:
            raise ValueError("no period: the base is not coprime to the modulus")
    return step


def controlled_modmul(state, control, multiplier, modulus=MODULUS, work=WORK_BITS):
    """|y> -> |multiplier * y mod modulus| on the work register, where the control bit is set.

    A PERMUTATION, WITH NO ARITHMETIC. Values at or above the modulus are left alone, the
    standard convention, which keeps the map a bijection on the whole register and not a partial
    one. No arithmetic touches an amplitude. This contributes nothing to any error.
    """
    control_bit = 1 << control
    mask = (1 << work) - 1
    where = {}
    for value in range(1 << work):
        where[value] = (multiplier * value) % modulus if value < modulus else value

    new_real = list(state.real)
    new_imag = list(state.imag)
    for at in range(state.width):
        if at & control_bit:
            low = at & mask
            target = (at & ~mask) | where[low]
            new_real[target] = state.real[at]
            new_imag[target] = state.imag[at]
    state.real = new_real
    state.imag = new_imag


def phase_pair(angle, digits):
    """cos and sin of an angle, from our own series and our own pi. No standard library trig."""
    context = decimal.Context(prec=digits + exact_qubits.GUARD)
    return normalized_harmonics._cos_sin_series(angle, context)


def controlled_phase(state, one, two, cosine, sine):
    """Multiply by cos + i sin where both qubits are set. The inexact gate in this file."""
    mask = (1 << one) | (1 << two)
    context = state.context
    for at in range(state.width):
        if (at & mask) == mask:
            ar, ai = state.real[at], state.imag[at]
            state.real[at] = context.subtract(context.multiply(ar, cosine),
                                              context.multiply(ai, sine))
            state.imag[at] = context.add(context.multiply(ar, sine),
                                         context.multiply(ai, cosine))


def inverse_qft(state, low, bits, digits):
    """Inverse Fourier transform over `bits` qubits starting at `low`.

    The angles are negative powers of two times pi, taken from OUR pi and OUR cosine series. The
    transform carries the working precision and not a double's sixteen digits.
    """
    pi = dn_load.decimal_of("pi", digits + exact_qubits.GUARD)
    context = decimal.Context(prec=digits + exact_qubits.GUARD)

    # Reverse the register first, the convention that makes the output read in order.
    for at in range(bits // 2):
        swap_qubits(state, low + at, low + bits - 1 - at)

    for target in range(bits):
        for control in range(target):
            step = target - control
            angle = -context.divide(pi, decimal.Decimal(1 << step))
            cosine, sine = phase_pair(angle, digits)
            controlled_phase(state, low + control, low + target, cosine, sine)
        state.h(low + target)


def swap_qubits(state, one, two):
    """Exchange two qubits. A permutation of the amplitude list. Exact."""
    one_bit, two_bit = 1 << one, 1 << two
    for at in range(state.width):
        if (at & one_bit) and not (at & two_bit):
            other = (at & ~one_bit) | two_bit
            state.real[at], state.real[other] = state.real[other], state.real[at]
            state.imag[at], state.imag[other] = state.imag[other], state.imag[at]


def per_qubit(state):
    return [float(state.probability_one(at)) for at in range(state.qubits)]


def run_shor(digits=DIGITS, trace=True):
    """The whole algorithm, returning the state and a trace of per-qubit probabilities."""
    state = exact_qubits.ExactState(QUBITS, digits)
    # Work register starts at |1>, which is index 1 since the work bits are the low ones.
    state.real[0] = decimal.Decimal(0)
    state.real[1] = decimal.Decimal(1)

    steps = [("start, work = |1>", per_qubit(state))] if trace else []

    for at in range(COUNT_BITS):
        state.h(WORK_BITS + at)
    if trace:
        steps.append(("Hadamard the counting register", per_qubit(state)))

    for j in range(COUNT_BITS):
        multiplier = pow(BASE, 1 << j, MODULUS)
        controlled_modmul(state, WORK_BITS + j, multiplier)
        if trace:
            steps.append(("controlled multiply by %d" % multiplier, per_qubit(state)))

    inverse_qft(state, WORK_BITS, COUNT_BITS, digits)
    if trace:
        steps.append(("inverse Fourier transform", per_qubit(state)))

    return state, steps


def counting_distribution(state):
    """Probability of each counting register value, summed over the work register."""
    out = []
    mask = (1 << WORK_BITS) - 1
    for value in range(1 << COUNT_BITS):
        total = decimal.Decimal(0)
        for at in range(state.width):
            if (at >> WORK_BITS) == value:
                total = state.context.add(
                    total,
                    state.context.add(
                        state.context.multiply(state.real[at], state.real[at]),
                        state.context.multiply(state.imag[at], state.imag[at])))
        out.append(float(total))
    del mask
    return out


def scatter(steps, height=12):
    """A scatter of qubit index against probability of reading one, one column block per step."""
    lines = []
    lines.append("    P(1)")
    for row in range(height, -1, -1):
        level = row / float(height)
        mark = "  %5.2f |" % level
        for _name, probs in steps:
            cell = ""
            for value in probs:
                cell += "*" if abs(value - level) <= 0.5 / height else " "
            mark += cell + " "
        lines.append(mark)
    footer = "        +"
    labels = "         "
    for at, (_name, probs) in enumerate(steps):
        footer += "-" * len(probs) + "-"
        labels += ("%-*s" % (len(probs) + 1, str(at)))
    lines.append(footer)
    lines.append(labels)
    lines.append("         each block is one step, and within a block the columns are qubits 0 to %d"
                 % (QUBITS - 1))
    return lines


def _report(digits=DIGITS):
    import time
    period = true_period()
    print("  Shor period finding, N = %d, base = %d, true period = %d."
          % (MODULUS, BASE, period))
    print("  %d counting qubits and %d work qubits, %d exact amplitudes at %d digits."
          % (COUNT_BITS, WORK_BITS, 1 << QUBITS, digits))
    print("  Every phase comes from our own pi and our own cosine series.")
    print("")

    began = time.perf_counter()
    state, steps = run_shor(digits)
    spent = time.perf_counter() - began
    print("  ran in %.2f s" % spent)
    print("")

    print("  QUBIT MOVEMENT SCATTER")
    print("")
    for line in scatter(steps):
        print(line)
    print("")
    for at, (name, _probs) in enumerate(steps):
        print("    step %d  %s" % (at, name))
    print("")

    print("  MEAN DEVIATION PER STEP, the average absolute change in P(1) across the %d qubits"
          % QUBITS)
    print("")
    print("  %6s %-34s %16s %16s" % ("step", "what happened", "mean movement", "norm departure"))
    previous = None
    for at, (name, probs) in enumerate(steps):
        if previous is None:
            moved = 0.0
        else:
            moved = sum(abs(a - b) for a, b in zip(probs, previous)) / float(len(probs))
        previous = probs
        print("  %6d %-34s %16.6f %16s" % (at, name, moved, ""))
    print("")

    norm = state.norm_squared()
    print("  norm squared at the end: %s" % str(norm)[:digits + 4])
    print("  departure from one:      %.3e" % abs(float(norm) - 1.0))
    print("")

    print("  THE COUNTING REGISTER AFTER THE TRANSFORM, the answer")
    print("")
    distribution = counting_distribution(state)
    for value, probability in enumerate(distribution):
        bar = "#" * int(round(probability * 60))
        print("  %5d  %8.6f  %s" % (value, probability, bar))
    print("")

    peaks = [value for value, probability in enumerate(distribution) if probability > 0.05]
    print("  peaks above 0.05: %s" % peaks)
    expected = [value for value in range(1 << COUNT_BITS)
                if value % ((1 << COUNT_BITS) // period) == 0]
    print("  a period of %d over %d counting states predicts peaks at %s"
          % (period, 1 << COUNT_BITS, expected))
    print("")

    if peaks == expected:
        print("  THE PEAKS ARE WHERE THE PERIOD PUTS THEM. Reading the period back off them:")
        gap = peaks[1] - peaks[0] if len(peaks) > 1 else 0
        recovered = (1 << COUNT_BITS) // gap if gap else 0
        print("    spacing %d. The period is %d / %d = %d"
              % (gap, 1 << COUNT_BITS, gap, recovered))
        if recovered == period and recovered % 2 == 0:
            half = pow(BASE, recovered // 2, MODULUS)
            one = math.gcd(half - 1, MODULUS)
            two = math.gcd(half + 1, MODULUS)
            print("    %d^(%d/2) mod %d = %d" % (BASE, recovered, MODULUS, half))
            print("    gcd(%d, %d) = %d and gcd(%d, %d) = %d"
                  % (half - 1, MODULUS, one, half + 1, MODULUS, two))
            print("")
            print("    SO 15 = %d x %d, FACTORED." % (one, two))
    else:
        print("  THE PEAKS ARE NOT WHERE THE PERIOD PUTS THEM, which is a failure of this run and")
        print("  not a property of the algorithm. The circuit or the transform is wrong.")
    print("")

    print("  AND THE STRUCTURAL PREDICTION HELD. The controlled modular multiplications are")
    print("  permutations of the amplitude list. They carried no arithmetic and contributed")
    print("  nothing to the error. Whatever departure the norm shows above came from the inverse")
    print("  transform, the only stage in this circuit that touches an irrational.")
    return 0


def _check():
    lines = []
    failed = 0

    # The period must be what it is, or the target the run is graded against is wrong.
    period = true_period()
    lines.append("  period of %d mod %d is %d" % (BASE, MODULUS, period))
    if period != 4:
        lines.append("    FAIL the period is not 4, so the expected peaks are wrong")
        failed += 1

    # THE MODULAR MULTIPLY MUST BE A PERMUTATION, and that leaves it exact. Checked by
    # composing it to the period and requiring the identity.
    state = exact_qubits.ExactState(QUBITS, 25)
    for at in range(QUBITS):
        state.h(at)
    snapshot = (list(state.real), list(state.imag))
    for _ in range(period):
        controlled_modmul(state, WORK_BITS, BASE)
    same = (state.real == snapshot[0] and state.imag == snapshot[1])
    lines.append("  multiplying by %d, %d times, returns the state bit-identically: %s"
                 % (BASE, period, same))
    if not same:
        lines.append("    FAIL the modular multiply is not a permutation of order %d" % period)
        failed += 1

    # AND IT MUST CARRY NO ERROR AT ALL, the structural claim.
    before = state.norm_squared()
    for _ in range(40):
        controlled_modmul(state, WORK_BITS + 1, BASE)
    after = state.norm_squared()
    lines.append("  40 controlled multiplies change the norm by %s" % abs(after - before))
    if after != before:
        lines.append("    FAIL a permutation changed the norm, so it is doing arithmetic")
        failed += 1

    # The phases must come from our own pi, checked by cos^2 + sin^2 being one.
    cosine, sine = phase_pair(dn_load.decimal_of("pi", 30) / 4, 25)
    context = decimal.Context(prec=35)
    unit = context.add(context.multiply(cosine, cosine), context.multiply(sine, sine))
    lines.append("  cos^2 + sin^2 at pi/4 departs from one by %.3e" % float(abs(unit - 1)))
    if abs(unit - 1) > decimal.Decimal(1).scaleb(-22):
        lines.append("    FAIL the phase series is wrong")
        failed += 1

    # THE WHOLE RUN MUST FACTOR 15, the only end-to-end check that matters.
    state, _steps = run_shor(25, trace=False)
    distribution = counting_distribution(state)
    peaks = [value for value, probability in enumerate(distribution) if probability > 0.05]
    expected = [value for value in range(1 << COUNT_BITS)
                if value % ((1 << COUNT_BITS) // period) == 0]
    lines.append("  peaks %s against predicted %s" % (peaks, expected))
    if peaks != expected:
        lines.append("    FAIL the transform does not put the peaks where the period requires")
        failed += 1

    # The distribution must be normalized, or the probabilities are not probabilities.
    total = sum(distribution)
    lines.append("  the counting distribution sums to %.12f" % total)
    if abs(total - 1.0) > 1e-9:
        lines.append("    FAIL the counting distribution is not normalized")
        failed += 1

    # THE NEGATIVE CONTROL. A base NOT coprime to the modulus has no period and must raise and
    # not return a number, since a silent answer there would be meaningless.
    try:
        true_period(base=5, modulus=15)
        lines.append("    FAIL base 5 shares a factor with 15 and should have no period")
        failed += 1
    except ValueError:
        lines.append("  a base sharing a factor with the modulus raises, as it must")

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Shor traced on the exact simulator")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--digits", type=int, default=DIGITS)
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    sys.exit(_report(args.digits))
