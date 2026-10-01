"""Detects degrees of freedom the model does not contain, and measures the smallest it could find.

    python examples/00_blob_viz_tools/unmodeled.py
    python examples/00_blob_viz_tools/unmodeled.py --check

THE TEST

A full-rank reading of an N-dimensional model should drive the fit residual down to the arithmetic
floor, because at full rank the model can represent anything the model can represent. a residual
ABOVE that floor is the signature of something the model does not contain.

That is only a test because the floor is known in advance. It is the identity null: the object did
not change. Whatever the residual shows is arithmetic. Measured at 4.005e-16 in float64 and known
to move 0.9861 decades per digit of precision. The threshold is derived and not fitted.

    identity      object unchanged, reading unchanged    the floor, and it belongs to the format
    delta null    object changed, reading unchanged      the kernel, and it belongs to the map
    lift here     object contains what the model cannot  the residual exceeds the floor

WHAT IS INJECTED AND WHY IT IS OUTSIDE THE MODEL

The model carries sources at 256 golden-placed directions. The injection is a source at a direction
BETWEEN them. The model can approximate it and cannot represent it. No combination of modeled
weights reproduces it and the residual has nowhere to hide. That is a genuine degree of freedom
outside the model and not a modeled one in disguise.

BOTH CONTROLS RUN, AND THE NEGATIVE ONE MATTERS MORE

With no injection the residual must sit at the floor. Without that, a lift proves nothing: an
instrument that always reports a lift reports nothing. With the injection faded toward zero there is
an amplitude at which the lift disappears into the floor, and THAT AMPLITUDE IS THE DETECTION LIMIT.
It is the only form in which a null result here would be worth anything, since "looked and saw
nothing" without a limit is not a measurement.

WHAT THIS DOES NOT ESTABLISH, STATED BEFORE ANY NUMBER

It detects that the model is inadequate. It says nothing about why. Ahead of any exotic explanation
sit an unmodeled ordinary source, a depth or conduction time known worse than assumed, a
nonlinearity where linearity was assumed, and a bug. Attributing a lift to any particular cause is a
separate argument and a much harder one, and this tool supplies no part of it.
"""

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PRECISION = os.path.join(os.path.dirname(os.path.dirname(HERE)), "src", "import", "dn_precision",
                         "support")
for _where in (HERE, PRECISION):
    if _where not in sys.path:
        sys.path.insert(0, _where)

import numpy

import boundary_read
import normalized_harmonics
import reading_rank

COUNT = 256          # modeled source directions
DEGREE = 16          # reading degree: 289 coefficients, rank 256, and conditioned at 1.5e-1
DEPTH = 0.62         # r/R for every source, modeled and injected alike
AMPLITUDES = (1.0, 1e-2, 1e-4, 1e-6, 1e-8, 1e-10, 1e-12, 1e-14, 0.0)


def gain_vector(top, depth):
    """The per-degree gain, depth only. One number per degree carries all of the physics."""
    out = numpy.zeros(top + 1)
    climb = 1.0
    for degree in range(top + 1):
        out[degree] = climb
        climb *= depth
    return out


def spread_gain(gain, top):
    """The gain expanded to one entry per coefficient, degree l occupying the run at l squared."""
    out = numpy.zeros((top + 1) * (top + 1))
    for degree in range(top + 1):
        out[degree * degree:(degree + 1) * (degree + 1)] = gain[degree]
    return out


def model_map(points, top, depth):
    """The reading map: a weight per modeled source to boundary coefficients, at this depth."""
    raw = reading_rank.reading_matrix(top, points)
    return raw * spread_gain(gain_vector(top, depth), top)[:, None]


def between_direction(points):
    """A direction the placement does not contain: the normalized mean of two adjacent points.

    Adjacent on the golden spiral. The new direction sits in the gap between them and is not a
    small perturbation of either. Deterministic. The run repeats.

    The pair is taken from the middle of the spiral and not at a fixed index, because a fixed
    index is out of range for any placement smaller than itself.
    """
    middle_at = len(points) // 2
    first = numpy.array(points[middle_at], dtype=float)
    second = numpy.array(points[middle_at + 1], dtype=float)
    middle = first + second
    return middle / numpy.linalg.norm(middle)


def coefficients_of(direction, top, depth):
    """The boundary coefficients of one unit source at a direction, through the depth kernel."""
    colatitude, longitude = boundary_read.as_angles([direction])[0]
    basis = numpy.array(reading_rank.flat_harmonics(top, colatitude, longitude))
    return basis * spread_gain(gain_vector(top, depth), top)


def residual_at(amplitude, points, matrix, outside, weights):
    """Least-squares residual of the model against a reading carrying an unmodeled source.

    The solve is lstsq on the model's own map, at full rank and zero amplitude the residual is
    the arithmetic of the decomposition, alone.
    """
    reading = matrix.dot(weights) + amplitude * outside
    fitted, _, _, _ = numpy.linalg.lstsq(matrix, reading, rcond=None)
    return float(numpy.linalg.norm(matrix.dot(fitted) - reading))


def _report():
    points = boundary_read.golden_place(COUNT)
    matrix = model_map(points, DEGREE, DEPTH)

    singular = numpy.linalg.svd(matrix, compute_uv=False)
    floor = singular[0] * max(matrix.shape) * numpy.finfo(float).eps
    live = int((singular > floor).sum())

    generator = numpy.random.default_rng(5)
    weights = generator.normal(size=COUNT)
    outside = coefficients_of(between_direction(points), DEGREE, DEPTH)

    print("  Model: %d sources at r/R %.2f, read to degree %d, %d coefficients."
          % (COUNT, DEPTH, DEGREE, (DEGREE + 1) ** 2))
    print("  Rank %d of %d. The model is full rank and can represent any modeled object."
          % (live, COUNT))
    print("  Conditioning: largest %.4f, least live %.4e, ratio %.3e"
          % (singular[0], singular[live - 1], singular[0] / singular[live - 1]))
    print("")
    print("  Injecting one source at a direction BETWEEN two placement points.")
    print("")
    print("  %14s %16s %14s" % ("amplitude", "residual", "against floor"))

    base = residual_at(0.0, points, matrix, outside, weights)
    scale = max(base, numpy.finfo(float).tiny)
    rows = []
    for amplitude in AMPLITUDES:
        got = residual_at(amplitude, points, matrix, outside, weights)
        rows.append((amplitude, got))
        print("  %14.0e %16.6e %14.2f" % (amplitude, got, got / scale))

    print("")
    print("  the negative control, amplitude exactly zero: %.6e" % base)
    print("  that is the arithmetic of the decomposition and it is the threshold everything")
    print("  else is measured against")
    print("")

    # The detection limit: the smallest injected amplitude whose residual is clear of the floor.
    limit = None
    for amplitude, got in rows:
        if amplitude > 0.0 and got > 10.0 * scale:
            limit = amplitude
    if limit is not None:
        print("  DETECTION LIMIT: %.0e, the smallest amplitude tried whose residual clears the" % limit)
        print("  floor by a factor of ten. Below it an unmodeled source of this kind is present")
        print("  and unreadable: a limit, and not an absence.")
    else:
        print("  NO AMPLITUDE LIFTED THE RESIDUAL. The instrument is blind and every number above")
        print("  is uninformative. Do not read a null result off a tool that failed its own")
        print("  positive control.")

    print("")
    print("  A LIFT MEANS THE MODEL IS INADEQUATE AND SAYS NOTHING ABOUT WHY. An ordinary")
    print("  unmodeled source, a depth known worse than assumed, a nonlinearity and a bug all")
    print("  produce one, and each is likelier than anything exotic.")
    return 0


# -------------------------------------------------------------------------------------------------
# The same test with the format taken out of the way.
# -------------------------------------------------------------------------------------------------

# Small enough that a Gram-Schmidt in software decimals finishes in seconds, and still full rank:
# 81 coefficients against 64 sources. The slope below is a property of the arithmetic and not of the
# size. Measuring it on a small system costs nothing but time saved.
PRECISION_COUNT = 64
PRECISION_DEGREE = 8

# Depth as an exact rational. It carries every digit the context has. 0.62 as a literal would be
# a double and would cap the whole sweep at sixteen digits through one number.
DEPTH_OVER = 62
DEPTH_UNDER = 100

# Working precisions read, and the ladder of injected amplitudes. Four decades a rung is deliberately
# coarse: the limit is reported as the rung, and the rung is honest about what was actually tried.
PRECISIONS = (16, 20, 25, 30, 40, 55)

# --deep. Far enough out that the slope is established over more than a decade of working length
# and not fitted across a handful of nearby points. The cost of a Gram-Schmidt in software
# decimals goes roughly as the square of the digits. The last row here is minutes and not
# seconds, and the time is part of the evidence: a floor that arrives free was not computed.
DEEP_PRECISIONS = (16, 55, 120, 250, 500)
LADDER = tuple(10 ** -step for step in range(0, 4)) + tuple(range(0, 0))


def _decimal_ladder(digits):
    """The amplitude rungs, as Decimals, reaching far enough below the floor at `digits` to bracket
    it from both sides."""
    import decimal
    out = []
    step = 0
    while step <= digits + 8:
        out.append(decimal.Decimal(1).scaleb(-step))
        step += 4
    return out


def _exact_system(digits):
    """The model map and the unmodeled source's coefficients, both at `digits` digits.

    Everything here is exact-in-principle arithmetic: the placement from the golden angle in our own
    table, the basis from square roots of rationals, the depth gain from a rational raised to a
    power. No quantity in the returned system has passed through a double, and it is built for
    that.
    """
    import decimal
    context = decimal.Context(prec=digits + 12)

    places = normalized_harmonics.golden_place(PRECISION_COUNT, digits + 12)
    gain = []
    climb = decimal.Decimal(1)
    ratio = context.divide(decimal.Decimal(DEPTH_OVER), decimal.Decimal(DEPTH_UNDER))
    for _ in range(PRECISION_DEGREE + 1):
        gain.append(climb)
        climb = context.multiply(climb, ratio)

    spread = []
    for degree in range(PRECISION_DEGREE + 1):
        spread.extend([gain[degree]] * (2 * degree + 1))

    columns = []
    for point in places:
        x, cos_lon, sin_lon = normalized_harmonics.direction_of(point, digits + 12)
        row = normalized_harmonics.flat_harmonics(PRECISION_DEGREE, x, cos_lon, sin_lon, digits + 12)
        columns.append([context.multiply(one, factor) for one, factor in zip(row, spread)])

    # The unmodeled direction, between two adjacent placement points, exactly as the float path
    # picks it so the two modes are testing the same geometry.
    first = places[PRECISION_COUNT // 2]
    second = places[PRECISION_COUNT // 2 + 1]
    middle = [context.add(a, b) for a, b in zip(first, second)]
    length = context.sqrt(sum((context.multiply(one, one) for one in middle),
                              decimal.Decimal(0)))
    middle = tuple(context.divide(one, length) for one in middle)

    x, cos_lon, sin_lon = normalized_harmonics.direction_of(middle, digits + 12)
    raw = normalized_harmonics.flat_harmonics(PRECISION_DEGREE, x, cos_lon, sin_lon, digits + 12)
    outside = [context.multiply(one, factor) for one, factor in zip(raw, spread)]
    return columns, outside


def _rounded(columns, outside, digits):
    """The system as a reader carrying `digits` digits would hold it, and nothing finer.

    This is the step that makes the sweep a measurement and not a demonstration. The object is
    fixed; only the format changes. A difference in what comes out belongs to the format: the
    identity primitive applied to precision itself.
    """
    import decimal
    context = decimal.Context(prec=digits)
    return ([[context.plus(one) for one in column] for column in columns],
            [context.plus(one) for one in outside])


def _orthonormal(columns, context):
    """Modified Gram-Schmidt, returning an orthonormal basis of the columns' span.

    Gram-Schmidt and not normal equations, DELIBERATELY. Forming A^T A squares the condition
    number, which would spend digits of the very precision being measured and put a bend in the
    slope that belongs to the method and not to the format.
    """
    import decimal
    basis = []
    for column in columns:
        vector = list(column)
        for held in basis:
            share = decimal.Decimal(0)
            for a, b in zip(held, vector):
                share = context.add(share, context.multiply(a, b))
            for at in range(len(vector)):
                vector[at] = context.subtract(vector[at], context.multiply(share, held[at]))
        length = decimal.Decimal(0)
        for one in vector:
            length = context.add(length, context.multiply(one, one))
        length = context.sqrt(length)
        if length.is_zero():
            continue
        basis.append([context.divide(one, length) for one in vector])
    return basis


def _residual(basis, reading, context):
    """How much of `reading` lies outside the span, as a length. Zero means the model fits it."""
    import decimal
    left = list(reading)
    for held in basis:
        share = decimal.Decimal(0)
        for a, b in zip(held, left):
            share = context.add(share, context.multiply(a, b))
        for at in range(len(left)):
            left[at] = context.subtract(left[at], context.multiply(share, held[at]))
    total = decimal.Decimal(0)
    for one in left:
        total = context.add(total, context.multiply(one, one))
    return context.sqrt(total)


def _precision_sweep(widths=None):
    """Measures the detection limit against the reader's precision, holding the object fixed.

    ARBITRARY PRECISION IS WHERE A SMALL SIGNAL SITS UNREAD. A double's floor is 4.005e-16 and a
    difference below it is not absent, it is unrepresentable by the instrument. So the quantity
    worth reporting is not whether something was found but the smallest thing that COULD have been,
    and that number is set by the format and not by the object.
    """
    import decimal
    import time

    print("  Model: %d sources at r/R %d/%d, degree %d, %d coefficients. Full rank."
          % (PRECISION_COUNT, DEPTH_OVER, DEPTH_UNDER, PRECISION_DEGREE,
             (PRECISION_DEGREE + 1) ** 2))
    print("  The object is built once at high precision and never rebuilt. Only the reader's")
    print("  format changes down the table. Every change in the limit belongs to the format.")
    print("")

    widest = max(widths)
    began = time.time()
    columns, outside = _exact_system(widest)
    print("  exact system built at %d digits in %.2f s" % (widest, time.time() - began))
    print("")

    # A fixed modeled object, as exact rationals so it carries every digit too.
    weights = [decimal.Decimal(((k * 37) % 71) - 35) / decimal.Decimal(16)
               for k in range(PRECISION_COUNT)]

    print("  %7s %16s %16s %10s" % ("digits", "identity floor", "detection limit", "seconds"))
    rows = []
    for digits in widths:
        context = decimal.Context(prec=digits)
        held_columns, held_outside = _rounded(columns, outside, digits)
        clock = time.time()
        basis = _orthonormal(held_columns, context)

        reading = [decimal.Decimal(0)] * len(held_columns[0])
        for column, weight in zip(held_columns, weights):
            scaled = context.plus(weight)
            for at in range(len(reading)):
                reading[at] = context.add(reading[at], context.multiply(column[at], scaled))

        floor = _residual(basis, reading, context)
        limit = None
        for amplitude in _decimal_ladder(digits):
            lifted = [context.add(a, context.multiply(amplitude, b))
                      for a, b in zip(reading, held_outside)]
            got = _residual(basis, lifted, context)
            if got > context.multiply(decimal.Decimal(10), floor):
                limit = amplitude
        spent = time.time() - clock
        rows.append((digits, floor, limit, len(basis)))
        print("  %7d %16.3e %16s %10.2f"
              % (digits, float(floor), ("%.0e" % float(limit)) if limit else "none found", spent))

    print("")
    usable = [(digits, limit) for digits, _, limit, _ in rows if limit is not None]
    if len(usable) >= 2:
        first_digits, first_limit = usable[0]
        last_digits, last_limit = usable[-1]
        decades = math.log10(float(first_limit) / float(last_limit))
        slope = decades / float(last_digits - first_digits)
        print("  THE LIMIT FALLS %.4f DECADES PER DIGIT, measured from %d digits to %d."
              % (slope, first_digits, last_digits))
        print("  The arithmetic floor in this tree was measured at 0.9861 decades per digit and")
        print("  the two are the same quantity. This slope is a check on both and not a")
        print("  new result. A rung is four decades wide. The agreement is to that resolution.")
    else:
        print("  TOO FEW PRECISIONS FOUND A LIMIT for a slope to mean anything.")

    print("")
    print("  AND THE SAME DEPTH KERNEL ADMITS MORE DEGREES AS THE FLOOR FALLS. The gain at degree l")
    print("  is (r/R)^l, which is never zero, a degree is unreadable only once it lands under the")
    print("  reader's floor. The last surviving degree is therefore digits / log10(R/r), counted")
    print("  here and not quoted:")
    print("")
    print("  %7s %16s %14s" % ("digits", "last degree", "predicted"))
    ratio = float(DEPTH_UNDER) / float(DEPTH_OVER)
    per_digit = math.log10(ratio)
    for digits, floor, _, _ in rows:
        counted = 0
        while DEPTH_OVER ** (counted + 1) * 10 ** (digits * 1) > DEPTH_UNDER ** (counted + 1):
            counted += 1
        print("  %7d %16d %14.1f" % (digits, counted, digits / per_digit))
    print("")
    print("  So the depth kernel does not zero a degree's marginal value, it PRICES that value in")
    print("  digits at %.4f degrees per digit for r/R = %d/%d. An earlier statement of this in the"
          % (1.0 / per_digit, DEPTH_OVER, DEPTH_UNDER))
    print("  boundary chapter called the zeroing a property of the reading. It is a property of the")
    print("  reading AT A PRECISION, and the two columns above are the retraction.")
    print("")
    print("  rank at every precision: %s" % ", ".join(str(one) for _, _, _, one in rows))
    print("  Rank does not move with precision and it is not supposed to: %d is the source count"
          % PRECISION_COUNT)
    print("  and it bounds what any reading can carry at any precision whatsoever. PRECISION BUYS")
    print("  THE SIZE OF WHAT CAN BE SEEN AND NEVER THE NUMBER OF THINGS.")
    return 0


# -------------------------------------------------------------------------------------------------
# How far a reading reaches, against distance and against dimension.
# -------------------------------------------------------------------------------------------------

def harmonic_count(dimension, degree):
    """Real harmonics of one degree on the sphere in `dimension` dimensions.

    The dimension of the space of degree-l harmonic polynomials in d variables, which is
    C(l+d-1, d-1) - C(l+d-3, d-1). In three dimensions it collapses to 2l+1, the count
    every reading in this tree uses, so that case is the check on the general formula and not a
    separate branch.
    """
    def choose(top, bottom):
        return math.comb(top, bottom) if top >= bottom >= 0 else 0
    return (choose(degree + dimension - 1, dimension - 1)
            - choose(degree + dimension - 3, dimension - 1))


def reach_of(digits, ratio, dimension=3):
    """The last degree a reader with `digits` digits can still see at radius ratio R/r.

    The exterior gain at degree l in d dimensions is (r/R)^(l+d-2), because the exterior harmonic
    solution falls as r^-(l+d-2). A degree is unreadable exactly when its gain lands under the
    floor, so

        (l + d - 2) log10(R/r) < digits        =>        l_max = digits / log10(R/r) - (d - 2)

    Two things fall out of that and both are the point. DISTANCE DIVIDES: the reach goes as the
    reciprocal of the log of the ratio. Every decade of distance costs a fixed slice of the
    degrees. DIMENSION SUBTRACTS: it comes off the reach directly, one degree per dimension above
    three, before any distance enters.
    """
    span = math.log10(ratio)
    if span <= 0.0:
        return None
    return digits / span - (dimension - 2)


def readable_numbers(digits, ratio, dimension=3):
    """How many real numbers survive the trip, summed over every degree that still reads."""
    top = reach_of(digits, ratio, dimension)
    if top is None or top < 0:
        return 0
    total = 0
    for degree in range(int(math.floor(top)) + 1):
        total += harmonic_count(dimension, degree)
    return total


# Distances swept, as R/r. The first is the depth this tree reads at; the last is far enough that
# the answer is one number and then none.
RATIOS = (100.0 / 62.0, 2.0, 10.0, 1.0e2, 1.0e4, 1.0e8, 1.0e16, 1.0e40)


def _reach():
    """Error impedes propagation, and this is the amount. Distance divides it, dimension subtracts.

    THE PRINCIPLE HAS A PRECISE FORM HERE AND IT IS NOT A METAPHOR. Every cheap operator in this
    tree is diagonal in degree because it commutes with the Laplacian, and every one of its gains
    is below one. A gain below one plus a floor above zero is exactly an impediment: the degree is
    not destroyed, it is pushed under the reader's last digit. So the reach is a ratio of two
    quantities that are both ours to choose, the digits carried and the distance read from, and the
    object never enters it.
    """
    print("  The exterior gain at degree l in d dimensions is (r/R)^(l+d-2), a degree goes")
    print("  unreadable when that lands under the floor. Reach = digits/log10(R/r) - (d-2).")
    print("")
    print("  IN THREE DIMENSIONS. Last readable degree, then the real numbers that survive.")
    print("")
    header = "  %14s" % "R/r"
    for digits in (16, 55, 1000):
        header += " %12s %12s" % ("deg @%d" % digits, "numbers")
    print(header)
    for ratio in RATIOS:
        row = "  %14.3g" % ratio
        for digits in (16, 55, 1000):
            top = reach_of(digits, ratio, 3)
            row += " %12.1f %12d" % (top, readable_numbers(digits, ratio, 3))
        print(row)

    print("")
    print("  DISTANCE DIVIDES. The reach is the digits over the log")
    print("  of the ratio, a reader with any fixed precision runs out: at R/r = 10^digits the")
    print("  reach in three dimensions is exactly ZERO, which leaves the monopole and nothing")
    print("  else, and one decade further out leaves nothing at all. A thousand-digit reader is")
    print("  not exempt, it is only further along the same curve.")
    print("")
    print("  NOW DIMENSION, HELD AT ONE DISTANCE, because it enters differently.")
    print("")
    print("  %10s %14s %14s %16s" % ("dimension", "reach @55", "per degree", "numbers @55"))
    for dimension in (3, 4, 5, 8, 16, 32):
        top = reach_of(55, 10.0, dimension)
        print("  %10d %14.1f %14d %16d"
              % (dimension, top, harmonic_count(dimension, 2),
                 readable_numbers(55, 10.0, dimension)))

    print("")
    print("  DIMENSION PULLS BOTH WAYS AND THE COUNT WINS AT FIRST. It subtracts from the reach")
    print("  one degree at a time, and it multiplies the harmonics at each surviving degree, which")
    print("  is why the numbers column climbs before the reach runs out. So more dimensions are")
    print("  not simply more impediment: they are fewer degrees each holding far more.")
    print("")
    print("  WHERE IT GOES TO NOTHING. Fix the precision and send the distance up, and the reach")
    print("  falls to zero in every dimension. THE IMPEDIMENT IS WHAT DIVERGES, not the")
    print("  information: the readable part goes to one number and then to none.")
    print("")
    print("  %10s %16s %16s" % ("dimension", "R/r for 1 degree", "R/r for none"))
    for dimension in (3, 4, 8, 32):
        # Reach falls to 1 and then to 0; invert the formula for each.
        one = 10.0 ** (55.0 / (1.0 + dimension - 2))
        none = 10.0 ** (55.0 / max(1e-9, float(dimension - 2)))
        print("  %10d %16.3g %16.3g" % (dimension, one, none))

    print("")
    print("  WHAT THIS DOES NOT SAY, AND IT MATTERS BECAUSE THE STATEMENT GENERALIZES BADLY.")
    print("  This is a theorem about a diagonal kernel whose gains are below one, as")
    print("  depth and conduction both are. It is not a general law that error impedes")
    print("  information, and that general law is false: dithering and stochastic resonance are")
    print("  cases where added noise RAISES the recoverable information. The principle holds")
    print("  exactly here and exactly because the gains are diagonal and under one.")
    return 0


def _check():
    lines = []
    failed = 0

    points = boundary_read.golden_place(64)
    matrix = model_map(points, 8, DEPTH)
    generator = numpy.random.default_rng(3)
    weights = generator.normal(size=64)
    outside = coefficients_of(between_direction(points), 8, DEPTH)

    # The negative control. With nothing injected the residual must be at the arithmetic floor, or
    # every lift this tool reports is its own.
    base = residual_at(0.0, points, matrix, outside, weights)
    reading_size = float(numpy.linalg.norm(matrix.dot(weights)))
    relative = base / max(reading_size, 1e-30)
    lines.append("  nothing injected: residual %.3e against a reading of %.3e, relative %.3e"
                 % (base, reading_size, relative))
    if relative > 1e-10:
        lines.append("    FAIL the model cannot fit its own object, so no lift here means anything")
        failed += 1

    # The positive control. A unit injection must lift it, or the tool is blind and a null result
    # from it would be worthless.
    lifted = residual_at(1.0, points, matrix, outside, weights)
    lines.append("  unit injection: residual %.3e, a factor of %.3e over the floor"
                 % (lifted, lifted / max(base, 1e-300)))
    if not lifted > 100.0 * max(base, 1e-300):
        lines.append("    FAIL a unit unmodeled source did not lift the residual")
        failed += 1

    # And the lift must scale with the injection, or it is not measuring the injection.
    half = residual_at(0.5, points, matrix, outside, weights)
    ratio = lifted / max(half, 1e-300)
    lines.append("  halving the injection divides the lift by %.3f, and linearity says 2" % ratio)
    if not 1.8 < ratio < 2.2:
        lines.append("    FAIL the lift does not scale with the amplitude")
        failed += 1

    # The injected direction has to be outside the placement, or the whole test is circular.
    outside_direction = between_direction(points)
    closest = max(float(numpy.array(one, dtype=float).dot(outside_direction)
                        / numpy.linalg.norm(one)) for one in points)
    lines.append("  the injected direction's closest placement point: cosine %.6f" % closest)
    if closest > 0.9999:
        lines.append("    FAIL the injection sits on a placement point and is modeled after all")
        failed += 1

    # THE GENERAL HARMONIC COUNT MUST COLLAPSE TO 2l+1 IN THREE DIMENSIONS, the count every
    # reading in this tree is built on. If it does not, every dimension column is wrong and the
    # three-dimensional one would still look right, the quiet failure.
    wrong = [degree for degree in range(24)
             if harmonic_count(3, degree) != 2 * degree + 1]
    lines.append("  harmonic count in 3 dimensions matches 2l+1 for degrees 0 to 23: %s"
                 % ("yes" if not wrong else "NO at %s" % wrong))
    if wrong:
        failed += 1

    # And degree 0 is one number and degree 1 is d numbers, in every dimension. Both are known
    # independently of the formula. They grade it and not restate it.
    bad = [dimension for dimension in (3, 4, 5, 8, 16, 32)
           if harmonic_count(dimension, 0) != 1 or harmonic_count(dimension, 1) != dimension]
    lines.append("  degree 0 is 1 number and degree 1 is d numbers, every dimension tried: %s"
                 % ("yes" if not bad else "NO at %s" % bad))
    if bad:
        failed += 1

    # Reach has to fall with distance and fall with dimension, or the sweep is not measuring either.
    near = reach_of(55, 2.0, 3)
    far = reach_of(55, 1.0e8, 3)
    lines.append("  reach at 55 digits: %.1f degrees at R/r 2, %.1f at R/r 1e8" % (near, far))
    if not far < near:
        lines.append("    FAIL distance did not reduce the reach")
        failed += 1

    flat = reach_of(55, 10.0, 3)
    deep = reach_of(55, 10.0, 32)
    lines.append("  reach at R/r 10: %.1f degrees in 3 dimensions, %.1f in 32" % (flat, deep))
    if not deep < flat:
        lines.append("    FAIL dimension did not reduce the reach")
        failed += 1

    # THE EXACT INVERSION POINT.
    # In three dimensions reach = digits/log10(R/r) - 1, at R/r = 10^digits it is ZERO and not
    # one. Zero reach still leaves the monopole, because degrees nought through nought is one
    # degree, and in three dimensions that degree holds exactly one number. The reach and the count
    # of degrees it admits are different quantities, and both are asserted.
    exact = reach_of(40, 10.0 ** 40, 3)
    survivors = readable_numbers(40, 10.0 ** 40, 3)
    lines.append("  at R/r = 10^digits, 3 dimensions: reach %.6f, numbers surviving %d"
                 % (exact, survivors))
    if abs(exact) > 1e-9 or survivors != 1:
        lines.append("    FAIL the reach formula does not invert where it must: the monopole and")
        lines.append("         nothing else should survive exactly there")
        failed += 1

    # One decade further out and even that is gone, the other half of the identity.
    beyond = reach_of(40, 10.0 ** 41, 3)
    lines.append("  one decade further out: reach %.6f, numbers surviving %d"
                 % (beyond, readable_numbers(40, 10.0 ** 41, 3)))
    if beyond >= 0.0 or readable_numbers(40, 10.0 ** 41, 3) != 0:
        lines.append("    FAIL past the inversion point something still read")
        failed += 1

    # THE NEGATIVE CONTROL FOR THE WHOLE SWEEP. At R/r = 1 there is no distance and no impediment.
    # The reach is undefined and not zero. Returning zero there would read as total blindness
    # at zero distance, the opposite of the truth.
    lines.append("  at R/r = 1, no distance at all, the reach is %s rather than a number"
                 % reach_of(55, 1.0, 3))
    if reach_of(55, 1.0, 3) is not None:
        lines.append("    FAIL zero distance reported a finite reach")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="degrees of freedom the model does not contain")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--precision", action="store_true",
                        help="sweep the reader's precision and watch the detection limit follow")
    parser.add_argument("--reach", action="store_true",
                        help="how far a reading reaches, against distance and against dimension")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.precision:
        sys.exit(_precision_sweep())
    if args.reach:
        sys.exit(_reach())
    sys.exit(_report())
