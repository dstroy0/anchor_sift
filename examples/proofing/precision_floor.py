"""Is a measured noise floor a property of the reading, or of the number format it was read in.

    python examples/proofing/precision_floor.py
    python examples/proofing/precision_floor.py --check

THE QUESTION

`null_harness.py` measures a floor for deflection under rotation and reports 4.005e-16. Every
threshold set against that floor inherits whatever the number is a property of, and the number sits
one bit above the epsilon of a double. So the floor might be a fact about the reading, or a fact
about float64, and those two answers lead to different work.

THE LAW SAYS THE RESIDUAL IS ZERO

Power per degree, `P_l = sum over m of |a_lm|^2`, is invariant under every rotation, because the
degree-l subspace carries a unitary irreducible representation of the rotation group. On a ring
placement turned by whole steps the statement is stronger still: each point moves along its own
ring, so the rotated configuration is the same set of directions relabelled, every coefficient pair
`(a_lm^cos, a_lm^sin)` turns rigidly by `m alpha`, and the sum of their squares is unchanged.

So the exact residual is zero, identically, with no measurement needed. Anything a program reports
above zero is arithmetic. That makes the floor measurable in the one way that settles what it
belongs to: compute the same null at rising precision and watch what the residual does.

WHAT THE TWO ANSWERS LOOK LIKE

  falls one decade per digit    the floor is the number format, and 4e-16 is float64's own noise
  flattens at some value        something in the reading does not commute with the rotation

This is the house method applied to the house instrument. A law supplies the prediction, the
program supplies the measurement, and the gap between them is the thing being reported. No
statistical model enters, because none is needed when the predicted value is exact.

WHY THE CONSTANTS ARE NOT IMPORTED

Pi is computed here to whatever precision the run asks for, by `natural_constants.pi_machin`, and
every root is `Decimal.sqrt` at the same precision. Nothing is read from a library at the precision
that library happens to carry, since a reference no better than the thing it grades cannot grade it.
"""

import argparse
import decimal
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import natural_constants

# The placement and ceiling `null_harness.py` runs its nulls at. A floor measured here is
# comparable with the floor it publishes.
RINGS, WIDTH = 8, 32
TOP = 8

# Rotations to try, in whole ring steps. Each is an exact relabelling of the placement.
STEPS = (1, 5, 13, 31)

# Working digits above the requested precision. The Taylor sums below are alternating, so their
# cancellation is bounded by the largest term, and a dozen digits covers it.
#
# THE GUARD IS PART OF THE ARITHMETIC AND HAS TO BE REPORTED AS SUCH. A rounding residual is set by
# the precision the arithmetic actually ran at, so asking for 20 digits and computing at 32 gives a
# residual near 1e-32 and not near 1e-20. Plotting those residuals against the requested figure put
# a 3.82 decade per digit segment in an otherwise straight line and read as a real effect at the
# boundary between the float arms and this ladder. It was this constant. Use `working_digits` for
# any axis, any fit and any comparison against a format's own width.
GUARD = 12


def working_digits(requested):
    """The precision the arithmetic runs at, and a rounding residual is a function of that."""
    return requested + GUARD


def lit_set(total):
    """The same lit set the harness uses: about half weight and no structure anybody chose."""
    return [k for k in range(total) if (k * 7 + k // 5) % 3]


def turned(live, steps):
    """The lit set moved along its rings by whole steps, which is an exact rotation of it."""
    return [(at // WIDTH) * WIDTH + (at % WIDTH + steps) % WIDTH for at in live]


# -------------------------------------------------------------------------------------------------
# Arbitrary precision trigonometry. Decimal ships sqrt and no transcendentals, so these are built.
# -------------------------------------------------------------------------------------------------

def pi_at(digits):
    """Pi as a Decimal carrying `digits` places, from the integer Machin computation."""
    raw = natural_constants.pi_machin(digits)
    return decimal.Decimal(raw).scaleb(-digits)


def cosine_of(angle, pi):
    """Cosine by Taylor series, after folding the argument to the nearest multiple of two pi.

    Folding first keeps the series argument under pi in magnitude, so the terms fall quickly and the
    alternating cancellation stays bounded by the first term.
    """
    two_pi = 2 * pi
    angle = angle - two_pi * (angle / two_pi).to_integral_value(rounding=decimal.ROUND_HALF_EVEN)
    total = decimal.Decimal(1)
    term = decimal.Decimal(1)
    square = angle * angle
    step = 1
    while True:
        term = -term * square / ((2 * step - 1) * (2 * step))
        if term == 0:
            return total
        total += term
        step += 1


def sine_of(angle, pi):
    """Sine, by the same series."""
    two_pi = 2 * pi
    angle = angle - two_pi * (angle / two_pi).to_integral_value(rounding=decimal.ROUND_HALF_EVEN)
    total = angle
    term = angle
    square = angle * angle
    step = 1
    while True:
        term = -term * square / ((2 * step) * (2 * step + 1))
        if term == 0:
            return total
        total += term
        step += 1


# -------------------------------------------------------------------------------------------------
# The reading, written once and run at any precision the caller sets.
# -------------------------------------------------------------------------------------------------

def legendre_column(top, order, x, one, four_pi):
    """Normalised associated Legendre values for one order, every degree, in the caller's arithmetic.

    The same climb-the-diagonal recurrence `sphere_field.legendre_column` uses, with every square
    root taken at the working precision instead of in a double.
    """
    kind = type(x)
    out = [kind(0)] * (top + 1)
    sine = (one - x * x)
    sine = sine.sqrt() if hasattr(sine, "sqrt") else math.sqrt(sine)
    value = (one / four_pi).sqrt() if hasattr(one, "sqrt") else math.sqrt(1.0 / four_pi)
    for s in range(1, order + 1):
        ratio = kind(2 * s + 1) / kind(2 * s)
        value *= (ratio.sqrt() if hasattr(ratio, "sqrt") else math.sqrt(ratio)) * sine
    if order <= top:
        out[order] = value
    if order + 1 <= top:
        root = kind(2 * order + 3)
        out[order + 1] = (root.sqrt() if hasattr(root, "sqrt") else math.sqrt(root)) * x * value
    for d in range(order + 2, top + 1):
        lead = kind(4 * d * d - 1) / kind(d * d - order * order)
        trail = kind((d - 1) * (d - 1) - order * order) / kind(4 * (d - 1) * (d - 1) - 1)
        lead = lead.sqrt() if hasattr(lead, "sqrt") else math.sqrt(lead)
        trail = trail.sqrt() if hasattr(trail, "sqrt") else math.sqrt(trail)
        out[d] = lead * (x * out[d - 1] - trail * out[d - 2])
    return out


def power_per_degree(live, top, columns, cosines, sines, kind, root_two):
    """`P_l` of the lit set, summed over orders, in the caller's arithmetic.

    The basis is real, so each order above zero carries a cosine part and a sine part. Under a
    rotation those two turn into each other rigidly and the sum of their squares does not move,
    and that rigidity is the invariance under test.
    """
    width = (top + 1) * (top + 1)
    total = [kind(0)] * width
    for at in live:
        ring, step = at // WIDTH, at % WIDTH
        column = columns[ring]
        for order in range(top + 1):
            here = column[order]
            if order == 0:
                for d in range(top + 1):
                    total[d * d + d] += here[d]
                continue
            gain_cos = cosines[step][order] * root_two
            gain_sin = sines[step][order] * root_two
            for d in range(order, top + 1):
                total[d * d + d + order] += here[d] * gain_cos
                total[d * d + d - order] += here[d] * gain_sin
    out = []
    for d in range(top + 1):
        got = kind(0)
        for slot in range(d * d, (d + 1) * (d + 1)):
            got += total[slot] * total[slot]
        out.append(got)
    return out


def residual_at(digits):
    """The worst relative change in `P_l` under the rotations, computed at `digits` places.

    `digits` of None means float64, so the same code path supplies the comparison the harness runs
    in. One implementation and two arithmetics, which removes any question of the two differing
    somewhere other than in their precision.
    """
    if digits is None:
        kind = float
        pi = math.pi
        one, four_pi, root_two = 1.0, 4.0 * math.pi, math.sqrt(2.0)
        cos_of, sin_of = (lambda a, _p: math.cos(a)), (lambda a, _p: math.sin(a))
    else:
        decimal.getcontext().prec = digits + GUARD
        kind = decimal.Decimal
        pi = pi_at(digits + GUARD)
        one, four_pi, root_two = kind(1), 4 * pi, kind(2).sqrt()
        cos_of, sin_of = cosine_of, sine_of

    # One Legendre column set per ring, since every point on a ring shares its colatitude. This is
    # the whole reason the run finishes at fifty digits.
    columns = []
    for ring in range(RINGS):
        colatitude = pi * kind(2 * ring + 1) / kind(2 * RINGS)
        x = cos_of(colatitude, pi)
        columns.append([legendre_column(TOP, order, x, one, four_pi) for order in range(TOP + 1)])

    cosines, sines = [], []
    for step in range(WIDTH):
        longitude = 2 * pi * kind(step) / kind(WIDTH)
        cosines.append([cos_of(longitude * order, pi) for order in range(TOP + 1)])
        sines.append([sin_of(longitude * order, pi) for order in range(TOP + 1)])

    live = lit_set(RINGS * WIDTH)
    base = power_per_degree(live, TOP, columns, cosines, sines, kind, root_two)

    worst = kind(0)
    for steps in STEPS:
        moved = power_per_degree(turned(live, steps), TOP, columns, cosines, sines, kind, root_two)
        for before, after in zip(base, moved):
            scale = abs(before) if abs(before) > 0 else one
            gap = abs(after - before) / scale
            if gap > worst:
                worst = gap
    return worst


def _report():
    lines = []
    lines.append("  deflection under rotation, the same null at rising precision")
    lines.append("")
    lines.append("    arithmetic          working digits   worst relative change in P_l")
    lines.append("    float64             %-14.4f   %s" % (53.0 / math.log2(10.0),
                                                           format(residual_at(None), ".3e")))
    previous = None
    for digits in (20, 30, 40, 50):
        got = residual_at(digits)
        slope = ""
        if previous is not None:
            fell = (previous / got).log10() / decimal.Decimal(10)
            slope = "   %.2f decades per digit" % float(fell)
        lines.append("    decimal, %2d asked   %-14d   %.3e%s"
                     % (digits, working_digits(digits), float(got), slope))
        previous = got
    lines.append("")
    lines.append("    the working column is the one to read and the asked column is not: the guard")
    lines.append("    digits are arithmetic too, so a run asked for 20 rounds at 32")
    lines.append("")
    lines.append("    the law puts this residual at exactly zero, so every value above is")
    lines.append("    arithmetic. A slope near one decade per digit says the floor belongs to the")
    lines.append("    number format and to nothing in the reading.")
    lines.append("")
    lines.append("  what this settles about the published floor")
    lines.append("    null_harness reports 4.005e-16 for this null and the viewer runs in float64,")
    lines.append("    so that number is the right threshold to hand a float64 caller. It is not a")
    lines.append("    property of the boundary reading, and it must not be quoted as one: the")
    lines.append("    reading's own residual is zero and its floor is whatever precision is bought.")
    sys.stdout.write("\n".join(lines) + "\n")
    return 0


def _check():
    lines = []
    failed = 0

    # The float64 path must land in the same range as the published harness, and the band
    # is wide because this is not the harness's code.
    #
    # WHY THESE TWO NUMBERS DIFFER, since a reader will ask. The harness reads deflection off
    # complex coefficients and this reads it off the real basis; the lit points are summed in a
    # different order; and the two carry different depth gains. P_l is the same quantity in either
    # basis, so the readings agree on the answer and disagree on the rounding. That rounding is the only
    # thing being measured. Measured: 2.122e-14 here against 4.005e-16 there, a factor of about 53.
    #
    # So the finding does not rest on this value. It rests on the slope: whatever the constant in
    # front, a residual that falls one decade per digit is arithmetic. The band below admits two
    # orders either side of the harness for that reason, and a residual outside it would mean this
    # tool is reading something other than a rounding error.
    got = float(residual_at(None))
    lines.append("  float64 residual: %.3e, against the harness's 4.005e-16 in its own basis" % got)
    if not 1e-18 < got < 1e-12:
        lines.append("    FAIL this is too far from the harness to be the same null rounding off")
        failed += 1

    # Rising precision must lower the residual. If it does not, the attribution in the report is
    # wrong and the floor is something else.
    coarse = residual_at(20)
    finer = residual_at(40)
    lines.append("  20 digits %.3e against 40 digits %.3e" % (float(coarse), float(finer)))
    if not finer < coarse:
        lines.append("    FAIL more precision did not lower the residual, so it is not the format")
        failed += 1

    # The trigonometry has to be right before anything built on it is read. Checked against the
    # identity, at the working precision, and never against the double in the math module.
    decimal.getcontext().prec = 60
    pi = pi_at(60)
    for angle in (decimal.Decimal("0.3"), pi / 3, pi, 2 * pi - decimal.Decimal("0.1")):
        unit = cosine_of(angle, pi) ** 2 + sine_of(angle, pi) ** 2
        gap = abs(unit - 1)
        if gap > decimal.Decimal(10) ** -45:
            lines.append("    FAIL sine squared plus cosine squared is %s off at %s" % (gap, angle))
            failed += 1
    lines.append("  the series satisfy the Pythagorean identity at 60 places")

    # And the folding has to be right, or a large argument reads as a small one. Cosine of an angle
    # and of that angle plus a full turn must agree.
    apart = abs(cosine_of(decimal.Decimal("0.7"), pi) - cosine_of(decimal.Decimal("0.7") + 2 * pi, pi))
    lines.append("  a whole turn added to the argument moves the cosine by %s" % apart)
    if apart > decimal.Decimal(10) ** -45:
        lines.append("    FAIL the argument folding is wrong")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="what a measured noise floor belongs to")
    parser.add_argument("--check", action="store_true", help="run the checks and exit")
    args = parser.parse_args()
    sys.exit((1 if _check() else 0) if args.check else _report())
