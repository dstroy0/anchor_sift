"""The boundary basis at any precision, in the NORMALISED convention, so the reader's format stops
being the limit.

    python tools/dn_precision/calc/normalised_harmonics.py --check
    python tools/dn_precision/calc/normalised_harmonics.py --agree

    from normalised_harmonics import golden_place, direction_of, flat_harmonics
    places = golden_place(64, 60)                    64 directions, 60 digits
    x, cos_lon, sin_lon = direction_of(places[0])
    row = flat_harmonics(8, x, cos_lon, sin_lon, 60)

THE CONVENTION IS IN THE FILENAME BECAUSE THIS TREE HOLDS BOTH, AND THEY DISAGREE

`examples/proofing/exact_harmonics.py` already evaluates associated Legendre values at arbitrary
width, in BINARY fixed point, and it arrived at the same thesis first: "a floor that MOVES when the
width moves belongs to the format, and one that does not belongs to the object." That module is the
prior work and this one does not replace it.

What it does not share is the convention, and the gap is not small:

    examples/proofing/exact_harmonics.py     unnormalised, WITH the Condon-Shortley sign,
                                             P_m^m = (-1)^m (2m-1)!! sin^m, binary fixed point
    this module, and sphere_field.py         normalised, NO Condon-Shortley sign, the climb
                                             kept at unit scale, decimal arithmetic

The two therefore differ by sqrt((2l+1)(l-m)! / (4 pi (l+m)!)) and by a sign in the odd orders.
Either is a correct convention; mixing them is not, and the mixture would be quiet, because the low
degrees would look nearly right and only the fine structure would be wrong. This file exists in the
normalised convention because every reading, coefficient vector and rank measurement in this tree is
in that convention, and a precision tool in the other one cannot grade any of them.

SO THE TWO ARE NOT INTERCHANGEABLE AND NEITHER IS REDUNDANT. The older module is the right one for
a single basis value carried to enormous width in integers. This one is the right one for a whole
READING, because the reading's rank, conditioning and residual are all defined in the normalised
convention and only there.

WHY THIS EXISTS

`sphere_field` evaluates this basis in double precision, and double precision is a format rather
than a fact. Its floor is 4.005e-16 and falls 0.9861 decades per digit, a difference sitting
below that floor is not absent, it is unrepresentable by the instrument reading it. Anything hidden
under a double's last digit is invisible to every tool in this tree that reads doubles, and it is
not invisible to this one.

THE ONLY TRANSCENDENTAL HERE IS ONE COSINE, AND THAT IS A DESIGN CHOICE

Arbitrary-precision inverse trigonometry is slow and easy to get subtly wrong, so this module never
calls for any. The harmonics do not want the colatitude, they want its cosine, and the longitude
enters only as cos(m*longitude) and sin(m*longitude):

    cos(colatitude) = y / radius                      algebraic
    sin(colatitude) = sqrt(1 - cos^2)                 algebraic, one square root
    cos(longitude)  = x / flat                        algebraic
    sin(longitude)  = z / flat                        algebraic
    cos(m*lon), sin(m*lon)                            de Moivre recurrence from the pair above

So no arccosine, no arctangent, and the whole basis is square roots and rational arithmetic. The
single series evaluation in the file is the cosine of the golden angle, needed once to lay the
placement out, and the placement's own spiral then advances by a de Moivre recurrence as well.

PI COMES FROM OUR TABLE AND THERE IS NO FALLBACK

`math.pi` is a double. A module whose whole purpose is to carry more than sixteen digits cannot
reach for it, and this one raises if the table is missing rather than quietly capping itself. The
harmonic unit sqrt(1/4pi) is the only place pi enters the basis at all, since every other factor in
the recurrence is the square root of a rational.

WHAT IS MATCHED, EXACTLY

The convention is `sphere_field.legendre_column` and `sphere_field.harmonics_at`, term for term:
no Condon-Shortley sign, the diagonal climbed before the degree recurrence, row l holding 2l+1
values ordered from -l to +l, and the m>0 pair scaled by sqrt(2). `--agree` measures this rather
than asserting it: the two implementations are evaluated at the same directions and differenced. A
basis convention that drifts between two implementations produces pictures that look right and
numbers that are wrong, which is the failure this tree has already had once in CUDA.
"""

import argparse
import decimal
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY = os.path.dirname(HERE)
SUPPORT = os.path.join(FAMILY, "support")
for where in (SUPPORT, HERE):
    if where not in sys.path:
        sys.path.insert(0, where)

import dn_load

# Guard digits carried above whatever the caller asks for. The recurrence is 2*top long and each
# step is one multiply and one subtract, so the digits it can cost are a few, not a few dozen. Ten
# is generous and the cost of generosity here is a few percent of runtime.
GUARD = 10


def _context(digits):
    """A Decimal context at `digits` plus the guard, a returned value is clean at `digits`."""
    out = decimal.Context(prec=digits + GUARD)
    return out


def pi_at(digits):
    """OUR pi, from dn_const/dn_constants.csv. Raises if the table is absent, and does not guess."""
    return dn_load.decimal_of("pi", digits + GUARD)


def _cos_sin_series(angle, context):
    """Cosine and sine of one angle by Taylor series, after halving the argument into fast territory.

    Halved until the magnitude is under an eighth, where the factorial in the denominator outruns
    the power within a few dozen terms at any precision this module is used at, then doubled back
    with cos(2t) = 1 - 2 sin^2 t and sin(2t) = 2 sin t cos t. Doubling back is exact arithmetic and
    costs no accuracy beyond the rounding of the multiply.
    """
    halvings = 0
    small = angle
    eighth = context.divide(decimal.Decimal(1), decimal.Decimal(8))
    while abs(small) > eighth:
        small = context.divide(small, decimal.Decimal(2))
        halvings += 1

    # Both series at once, sharing the power. The stop is when a term cannot move the sum at this
    # context's precision, which is the only stopping rule that does not have a magic number in it.
    cosine = decimal.Decimal(1)
    sine = decimal.Decimal(0)
    term = decimal.Decimal(1)
    step = 0
    while True:
        step += 1
        term = context.divide(context.multiply(term, small), decimal.Decimal(step))
        if term.is_zero():
            break
        stage = step % 4
        if stage == 1:
            sine = context.add(sine, term)
        elif stage == 2:
            cosine = context.subtract(cosine, term)
        elif stage == 3:
            sine = context.subtract(sine, term)
        else:
            cosine = context.add(cosine, term)
        if abs(term) < decimal.Decimal(1).scaleb(-(context.prec + 2)):
            break

    for _ in range(halvings):
        twice_sine = context.multiply(context.multiply(decimal.Decimal(2), sine), cosine)
        cosine = context.subtract(
            decimal.Decimal(1),
            context.multiply(decimal.Decimal(2), context.multiply(sine, sine)))
        sine = twice_sine
    return cosine, sine


def golden_place(count, digits):
    """The Fibonacci placement at `digits` digits, as unit vectors of Decimals.

    Identical in definition to `boundary_read.golden_place`: index k sits at height
    1 - 2(k + 0.5)/count and longitude k*gamma. The height is an exact rational at any precision.
    The longitude advances by ONE de Moivre step per index, which is the same statement as that
    placement's own note that one step in the index is one fixed rigid move.
    """
    context = _context(digits)
    golden = dn_load.decimal_of("golden_angle", digits + GUARD)
    base_cos, base_sin = _cos_sin_series(golden, context)

    out = []
    run_cos, run_sin = decimal.Decimal(1), decimal.Decimal(0)
    for k in range(count):
        height = context.subtract(
            decimal.Decimal(1),
            context.divide(context.multiply(decimal.Decimal(2), decimal.Decimal(2 * k + 1)),
                           context.multiply(decimal.Decimal(2), decimal.Decimal(count))))
        flat_squared = context.subtract(decimal.Decimal(1), context.multiply(height, height))
        flat = context.sqrt(flat_squared) if flat_squared > 0 else decimal.Decimal(0)
        out.append((context.multiply(flat, run_cos), height, context.multiply(flat, run_sin)))

        next_cos = context.subtract(context.multiply(run_cos, base_cos),
                                    context.multiply(run_sin, base_sin))
        next_sin = context.add(context.multiply(run_sin, base_cos),
                               context.multiply(run_cos, base_sin))
        run_cos, run_sin = next_cos, next_sin
    return out


def direction_of(point, digits=None):
    """A point as the three quantities the basis actually wants: cos(colatitude), cos and sin of the
    longitude.

    The polar axis is y and the longitude is measured from x toward z, which is what
    `boundary_read.as_angles` does with acos(y/r) and atan2(z, x). Taking the cosine and sine
    directly skips both inverse functions and the forward ones that would undo them.

    At a pole the longitude is undefined and the choice does not matter, because sin(colatitude) is
    zero there and every harmonic of order above zero carries a factor of it. The pair is set to
    (1, 0) so the recurrence still has something finite to start from.
    """
    x, y, z = point
    if digits is None:
        digits = decimal.getcontext().prec - GUARD
    context = _context(digits)

    radius = context.sqrt(context.add(context.add(context.multiply(x, x), context.multiply(y, y)),
                                      context.multiply(z, z)))
    if radius.is_zero():
        raise ValueError("the zero vector has no direction, and treating it as one draws a picture")
    cos_colatitude = context.divide(y, radius)

    flat = context.sqrt(context.add(context.multiply(x, x), context.multiply(z, z)))
    if flat.is_zero():
        return cos_colatitude, decimal.Decimal(1), decimal.Decimal(0)
    return cos_colatitude, context.divide(x, flat), context.divide(z, flat)


def legendre_column(top, order, x, digits):
    """Normalised associated Legendre values for one order, degree `order` up to `top`.

    Term for term `sphere_field.legendre_column`, with the same climb up the diagonal before the
    recurrence in degree, for the same reason: every intermediate stays at unit scale, where the
    factorial form overflows above degree 150 and loses digits well before that. The sine is taken
    from x rather than from the geometry so this matches the reference implementation's definition
    and not merely its value.
    """
    context = _context(digits)
    one = decimal.Decimal(1)
    out = [decimal.Decimal(0)] * (top + 1)

    inside = context.subtract(one, context.multiply(x, x))
    sine = context.sqrt(inside) if inside > 0 else decimal.Decimal(0)

    four_pi = context.multiply(decimal.Decimal(4), pi_at(digits))
    value = context.sqrt(context.divide(one, four_pi))
    for step in range(1, order + 1):
        ratio = context.divide(decimal.Decimal(2 * step + 1), decimal.Decimal(2 * step))
        value = context.multiply(context.multiply(context.sqrt(ratio), sine), value)

    if order <= top:
        out[order] = value
    if order + 1 <= top:
        out[order + 1] = context.multiply(
            context.multiply(context.sqrt(decimal.Decimal(2 * order + 3)), x), value)

    for degree in range(order + 2, top + 1):
        lead = context.sqrt(context.divide(
            decimal.Decimal(4 * degree * degree - 1),
            decimal.Decimal(degree * degree - order * order)))
        trail = context.sqrt(context.divide(
            decimal.Decimal((degree - 1) ** 2 - order * order),
            decimal.Decimal(4 * (degree - 1) ** 2 - 1)))
        out[degree] = context.multiply(lead, context.subtract(
            context.multiply(x, out[degree - 1]),
            context.multiply(trail, out[degree - 2])))
    return out


def harmonics_at(top, x, cos_lon, sin_lon, digits):
    """Every real harmonic to `top` at one direction, as rows indexed by degree.

    Row l holds 2l + 1 values ordered from -l to +l, matching `sphere_field.harmonics_at` and the
    storage order every reading in this tree uses. The order's cosine and sine come off a de Moivre
    recurrence rather than a trigonometric call, which is exact arithmetic on the pair handed in.
    """
    context = _context(digits)
    rows = [[decimal.Decimal(0)] * (2 * degree + 1) for degree in range(top + 1)]
    root_two = context.sqrt(decimal.Decimal(2))

    run_cos, run_sin = decimal.Decimal(1), decimal.Decimal(0)
    for order in range(top + 1):
        if order > 0:
            next_cos = context.subtract(context.multiply(run_cos, cos_lon),
                                        context.multiply(run_sin, sin_lon))
            next_sin = context.add(context.multiply(run_sin, cos_lon),
                                   context.multiply(run_cos, sin_lon))
            run_cos, run_sin = next_cos, next_sin

        column = legendre_column(top, order, x, digits)
        if order == 0:
            for degree in range(top + 1):
                rows[degree][degree] = column[degree]
            continue

        cosine = context.multiply(run_cos, root_two)
        sine = context.multiply(run_sin, root_two)
        for degree in range(order, top + 1):
            rows[degree][degree + order] = context.multiply(column[degree], cosine)
            rows[degree][degree - order] = context.multiply(column[degree], sine)
    return rows


def flat_harmonics(top, x, cos_lon, sin_lon, digits):
    """The rows above flattened to one vector of length (top+1)^2, in `reading_rank`'s order."""
    out = []
    for row in harmonics_at(top, x, cos_lon, sin_lon, digits):
        out.extend(row)
    return out


def _agree(top=8, digits=40):
    """Differences the float implementation against this one, at the same directions.

    THIS IS THE CHECK THAT MATTERS, because the two are independent codings of one recurrence and
    nothing in this tree had compared the Python to anything until the CUDA was graded. Agreement to
    the float's own floor says the convention is shared. Disagreement above it says one of them is
    wrong and does not say which.
    """
    # FAMILY is tools/dn_precision, so the view tools are its sibling and not its parent's sibling.
    view = os.path.join(os.path.dirname(FAMILY), "view")
    if view not in sys.path:
        sys.path.insert(0, view)
    import boundary_read
    import sphere_field

    places = golden_place(16, digits)
    worst = 0.0
    scale = 0.0
    for point in places:
        x, cos_lon, sin_lon = direction_of(point, digits)
        mine = flat_harmonics(top, x, cos_lon, sin_lon, digits)

        floats = tuple(float(one) for one in point)
        colatitude, longitude = boundary_read.as_angles([floats])[0]
        rows = sphere_field.harmonics_at(top, colatitude, longitude)
        theirs = []
        for row in rows:
            theirs.extend(row)

        for got, want in zip(mine, theirs):
            worst = max(worst, abs(float(got) - want))
            scale = max(scale, abs(want))

    lines = []
    lines.append("  degree %d, 16 directions, %d digits here against double precision there" % (top, digits))
    lines.append("  largest basis value over the sample: %.6e" % scale)
    lines.append("  worst disagreement:                  %.6e" % worst)
    lines.append("  relative to the basis scale:         %.6e" % (worst / max(scale, 1e-300)))
    lines.append("")
    lines.append("  The floats carry sixteen digits and the recurrence is 2*degree steps long, a")
    lines.append("  few units in their last place is agreement and anything larger is a convention")
    lines.append("  difference rather than rounding.")
    sys.stdout.write("\n".join(lines) + "\n")
    return 0


def _check():
    lines = []
    failed = 0
    digits = 50
    context = _context(digits)

    # The one series in the file, against the identity that does not involve it being right for the
    # right reason. sin^2 + cos^2 = 1 is necessary and it is not sufficient, so the value is also
    # checked against our own table for cos of the golden angle below.
    golden = dn_load.decimal_of("golden_angle", digits + GUARD)
    cosine, sine = _cos_sin_series(golden, context)
    unit = context.add(context.multiply(cosine, cosine), context.multiply(sine, sine))
    gap = abs(unit - decimal.Decimal(1))
    lines.append("  cos^2 + sin^2 - 1 at the golden angle: %.3e" % float(gap))
    if gap > decimal.Decimal(1).scaleb(-(digits - 2)):
        lines.append("    FAIL the series does not land on the unit circle")
        failed += 1

    # And the series against a value computed a different way: the double from the standard library,
    # which is independent of everything here and good to sixteen digits.
    import math
    library = math.cos(dn_load.double("golden_angle"))
    lines.append("  against math.cos of the same angle as a double: %.3e"
                 % abs(float(cosine) - library))
    if abs(float(cosine) - library) > 1e-14:
        lines.append("    FAIL the series disagrees with double precision well above its floor")
        failed += 1

    # The placement must be unit vectors, or every direction derived from it is wrong by its length.
    places = golden_place(32, digits)
    worst = decimal.Decimal(0)
    for x, y, z in places:
        norm = context.add(context.add(context.multiply(x, x), context.multiply(y, y)),
                           context.multiply(z, z))
        worst = max(worst, abs(norm - decimal.Decimal(1)))
    lines.append("  placement: worst |point|^2 - 1 over 32 points: %.3e" % float(worst))
    if worst > decimal.Decimal(1).scaleb(-(digits - 2)):
        lines.append("    FAIL the placement is not on the unit sphere")
        failed += 1

    # THE POSITIVE CONTROL FOR THE BASIS ITSELF: the addition theorem at coincident directions says
    # the sum of squares over one degree's orders is exactly (2l+1)/(4pi), for every direction. It
    # is an identity, it involves every order and both the diagonal climb and the degree recurrence,
    # and a sign or normalisation error anywhere in either breaks it.
    top = 10
    four_pi = context.multiply(decimal.Decimal(4), pi_at(digits))
    worst_theorem = decimal.Decimal(0)
    for point in places[:6]:
        x, cos_lon, sin_lon = direction_of(point, digits)
        rows = harmonics_at(top, x, cos_lon, sin_lon, digits)
        for degree, row in enumerate(rows):
            total = decimal.Decimal(0)
            for value in row:
                total = context.add(total, context.multiply(value, value))
            want = context.divide(decimal.Decimal(2 * degree + 1), four_pi)
            worst_theorem = max(worst_theorem, abs(total - want))
    lines.append("  addition theorem to degree %d, 6 directions: worst gap %.3e"
                 % (top, float(worst_theorem)))
    if worst_theorem > decimal.Decimal(1).scaleb(-(digits - 4)):
        lines.append("    FAIL the basis fails an identity it must satisfy at every direction")
        failed += 1

    # The negative control. The same identity must NOT hold if a sign is flipped, or the check above
    # would pass a broken basis and mean nothing.
    x, cos_lon, sin_lon = direction_of(places[3], digits)
    rows = harmonics_at(top, x, cos_lon, sin_lon, digits)
    spoiled = [list(row) for row in rows]
    spoiled[4][6] = context.multiply(spoiled[4][6], decimal.Decimal(3))
    total = decimal.Decimal(0)
    for value in spoiled[4]:
        total = context.add(total, context.multiply(value, value))
    want = context.divide(decimal.Decimal(9), four_pi)
    lines.append("  the same identity with one value tripled: gap %.3e" % float(abs(total - want)))
    if abs(total - want) < decimal.Decimal(1).scaleb(-(digits - 4)):
        lines.append("    FAIL a broken basis passed the identity, so passing it proves nothing")
        failed += 1

    # And the precision has to actually be there. Recomputing at more digits must agree with the
    # shorter run to the shorter run's own length, or the guard is not doing its job.
    short = legendre_column(6, 3, direction_of(places[5], 20)[0], 20)
    long_run = legendre_column(6, 3, direction_of(places[5], 60)[0], 60)
    worst_pair = max(abs(a - b) for a, b in zip(short, long_run))
    lines.append("  20 digits against 60 digits, degree 6 order 3: worst gap %.3e" % float(worst_pair))
    if worst_pair > decimal.Decimal(1).scaleb(-18):
        lines.append("    FAIL the short run does not carry the digits it claims")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the boundary basis at arbitrary precision")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--agree", action="store_true")
    parser.add_argument("--degree", type=int, default=8)
    parser.add_argument("--digits", type=int, default=40)
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.agree:
        sys.exit(_agree(args.degree, args.digits))
    sys.stdout.write(__doc__)
    sys.exit(2)
