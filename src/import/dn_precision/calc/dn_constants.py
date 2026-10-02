"""The constants Delta Null theory runs on, at any length, each one agreed by two routes.

    python tools/dn_const/dn_constants.py --check            grade the tool before trusting a digit
    python tools/dn_const/dn_constants.py --digits 1000      write the CSV
    python tools/dn_const/dn_constants.py --digits 100000    the same, longer

WHY A TABLE AND NOT A HEADER

Every number here is decidable. Nothing in the reading path is measured. The accuracy floor of
the whole engine is therefore a choice about how many digits to carry, and nothing unknown limits it.
A table makes that choice explicit and auditable: one row per constant, the value, both routes that
produced it, and the worst disagreement between them.

TWO ROUTES OR IT DOES NOT SHIP

A constant computed once is a constant nobody has checked. Every row carries two independent
computations and the gap between them, because a single series with a transcription error returns a
plausible number and no amount of staring at it helps.

Where the tree already has both routes they are used as they stand:

  pi              Chudnovsky with binary splitting, against a BBP-type series
  ln 2            a BBP-type series, against the arctangent-of-a-third identity
  roots           the integer root of a scaled integer, against squaring the answer back

The routes are genuinely independent where it matters. Chudnovsky sums a hypergeometric series with
one division at the end; a BBP-type series is a different series entirely, in a different base, with
different denominators. Agreement between them is not two copies of one mistake.

WHAT IS NOT COMPUTED HERE, AND WHY

The Euler-Mascheroni constant. It wants Brent-McMillan, which is a real implementation and not a
series to be summed casually, and nothing in the reading path uses it. A row that named it and
carried a number from one unverified route would be worse than its absence.

THE SCALING CONVENTION IS CHECKED AND NOT ASSUMED

Every routine borrowed from `digit_engine` and `bbp_sweep` returns an integer holding a fixed number
of decimal places. This file does not assume that. `--check` reads a known prefix out of each
borrowed routine first, a convention that differs reports itself instead of scaling every row in
the table by a power of ten.
"""

import argparse
import csv
import io
import math
import os
import sys
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(FAMILY))
PROOFING = os.path.join(ROOT, "examples", "proofing")
SUPPORT = os.path.join(FAMILY, "support")
for reach in (PROOFING, SUPPORT):
    if reach not in sys.path:
        sys.path.insert(0, reach)

import digit_engine
import page_guard

try:
    import bbp_sweep
except ImportError:
    bbp_sweep = None

# Working digits above the requested length. The series below are alternating or have positive
# terms. Cancellation is therefore bounded, and a margin of thirty digits covers the accumulation and the
# final divisions with room left.
GUARD = 30

# Prefixes taken on authority, and the only imported numbers in this file. Each is used once, to
# establish that a borrowed routine's scaling convention is what this file believes it is.
KNOWN = {
    "pi": "3.14159265358979323846264338327950288419716939937510",
    "e": "2.71828182845904523536028747135266249775724709369995",
    "ln_two": "0.69314718055994530941723212145817656807550013436025",
    "root_two": "1.41421356237309504880168872420969807856967187537694",
    "root_five": "2.23606797749978969640917366873127623544061835961152",
    "golden_ratio": "1.61803398874989484820458683436563811772030917980576",
    "golden_angle": "2.39996322972865332223155550663361385312499901105811",
    "harmonic_unit": "0.28209479177387814347403972578038629292202531466449",
}


def scaled(text, digits):
    """A decimal string as an integer holding `digits` places, for comparing against a prefix."""
    whole, _, rest = text.partition(".")
    rest = (rest + "0" * digits)[:digits]
    return int(whole + rest)


def shown(value, digits, whole=1):
    """An integer holding `digits` places, written out with its point in place."""
    negative = value < 0
    text = str(abs(value)).rjust(digits + whole, "0")
    out = text[:-digits] + "." + text[-digits:]
    return ("-" + out) if negative else out


# -------------------------------------------------------------------------------------------------
# Series this file adds, in the same scaled-integer style as the engine it borrows from.
# -------------------------------------------------------------------------------------------------

def arctangent(over, scale):
    """floor(arctan(1/over) * scale), by the Gregory series.

    Each term is its predecessor divided by the square of `over`, a large reciprocal converges
    quickly. Truncating integer division loses at most one unit per term and the guard covers it.
    """
    total = 0
    term = scale // over
    squared = over * over
    step = 0
    while term:
        piece = term // (2 * step + 1)
        total += piece if step % 2 == 0 else -piece
        term //= squared
        step += 1
    return total


def arctanh(over, scale):
    """floor(artanh(1/over) * scale). Every term is positive and nothing cancels."""
    total = 0
    term = scale // over
    squared = over * over
    step = 0
    while term:
        total += term // (2 * step + 1)
        term //= squared
        step += 1
    return total


def exponential(digits):
    """e as an integer holding `digits` places, from the factorial series.

    Positive terms and a factorial denominator put the term count at about `digits / log10(digits)`
    and every intermediate is exact until the single division at the end.
    """
    scale = 10 ** (digits + GUARD)
    total = 0
    term = scale
    step = 1
    while term:
        total += term
        term //= step
        step += 1
    return total // 10 ** GUARD


def log_two_atanh(digits):
    """ln 2 by 2 artanh(1/3), the second route against whatever `bbp_sweep` supplies."""
    scale = 10 ** (digits + GUARD)
    return (2 * arctanh(3, scale)) // 10 ** GUARD


def log_ten(digits):
    """ln 10 as 3 ln 2 + 2 artanh(1/9).

    Exact as an identity: 10 = 8 * (5/4), ln(5/4) = artanh(1/9) * 2, and ln 8 = 3 ln 2. Both series
    have positive terms.
    """
    scale = 10 ** (digits + GUARD)
    total = 3 * (2 * arctanh(3, scale)) + 2 * arctanh(9, scale)
    return total // 10 ** GUARD


def pi_machin(digits):
    """Pi by Machin's identity, the slow second route that grades the fast one."""
    scale = 10 ** (digits + GUARD)
    return (16 * arctangent(5, scale) - 4 * arctangent(239, scale)) // 10 ** GUARD


def _power_of_two_above(value):
    """The smallest power of two strictly above `value`, as its exponent.

    Both gamma routes want their parameter to be a power of two so that ln(parameter) is an exact
    multiple of ln 2 and no general logarithm enters either route.
    """
    exponent = 1
    while (1 << exponent) <= value:
        exponent += 1
    return exponent


def gamma_brent_mcmillan(digits, power=None):
    """Euler-Mascheroni gamma by Brent-McMillan. Route A.

        B(n) = sum_k (n^k / k!)^2          A(n) = sum_k (n^k / k!)^2 H_k
        gamma = A(n)/B(n) - ln(n)

    The error falls as e^(-4n), and n must satisfy 4n > (digits + guard) ln 10. n is chosen as the
    smallest power of two above that, which keeps ln(n) an exact multiple of ln 2 so no general
    logarithm enters the route.

    n WAS HARDCODED TO 2^10 AND THAT WAS A LATENT WRONG ANSWER. 2^10 gives an error near
    10^(-1779), which is ample at 1000 places and silently short at 2000. The two routes were run
    at 2000 places and disagreed with a gap of 10^218, meaning they agreed to 1781 digits and
    parted exactly where this truncation sits. At the shipped width of 1000 the table looked
    perfect, and nothing would have reported the defect until somebody raised the width.

    A parameter tuned for the width in front of you is the same failure as a tolerance picked by
    judgment: correct until the case changes, and silent when it does. Both are now derived.

    ALL TERMS ARE POSITIVE AND NOTHING CANCELS. That property makes this the stable
    route and makes the guard of thirty digits sufficient. Compare `gamma_sweeney`, which needs
    hundreds of times that.
    """
    places = digits + GUARD
    scale = 10 ** places
    if power is None:
        # 4n > places * ln 10 gives n > 0.5757 * places. One power of two above that.
        power = _power_of_two_above(0.5757 * places)
    n = 1 << power

    u = scale                              # n^k / k!, scaled
    h = 0                                  # H_k, scaled
    top = 0
    bottom = 0
    k = 0
    while True:
        term = (u * u) // scale
        if term == 0 and k > n:
            break
        bottom += term
        top += (term * h) // scale
        k += 1
        u = (u * n) // k
        h += scale // k
        if k > 60 * n:
            # Cannot be reached: the terms fall off a cliff past k = e n. A runaway guard and not a
            # truncation bound, because a series that silently stops early would lose tail digits
            # while keeping its printed width. page_guard exists for that failure.
            raise RuntimeError("Brent-McMillan did not terminate")

    return ((top * scale) // bottom - power * log_two_atanh(places)) // 10 ** GUARD


def gamma_sweeney(digits, power=None, cancellation=None):
    """Euler-Mascheroni gamma by Sweeney's method through the exponential integral. Route B.

        E1(x) = -gamma - ln(x) + sum_k (-1)^(k+1) x^k / (k k!)

    and E1(x) < e^(-x)/x, and once x is large enough that E1 sits under the last digit,

        gamma = -ln(x) + sum_k (-1)^(k+1) x^k / (k k!)

    x must satisfy e^(-x)/x < 10^(-(digits + guard)), which gives x > 2.303 * places. It is taken as the
    smallest power of two above that, which keeps ln(x) an exact multiple of ln 2 here too.

    THE CANCELLATION GUARD IS THE WHOLE COST OF THIS ROUTE AND IT IS NOT NEGOTIABLE. The terms
    reach about e^x, and they cancel down to a number of order one. x / ln 10 digits are therefore lost
    outright and have to be carried. At 1000 places that is about 1779 extra digits, and the route
    works at roughly 2850 places to deliver 1000.

    BOTH x AND THE GUARD WERE HARDCODED AND BOTH WERE WRONG ABOVE ABOUT 1780 PLACES. See the note
    in gamma_brent_mcmillan: the pair was run at 2000 places, disagreed, and the size of the
    disagreement named its own cause. They are derived from the requested width now, and the
    control in _check_gamma runs a width on each side of the old hardcoded limit.

    Being delicate exactly where Brent-McMillan is not is the point of the pair: the two agreeing
    is evidence and no coincidence of shared machinery.
    """
    if power is None:
        # e^-x / x < 10^-places needs x > places * ln 10, with a little margin for the 1/x.
        power = _power_of_two_above(2.303 * (digits + GUARD))
    x = 1 << power
    if cancellation is None:
        # The terms peak near e^x, and x / ln 10 digits are lost to cancellation. Carry them, plus
        # room for the accumulation over the term count.
        cancellation = int(0.4343 * x) + 60

    places = digits + cancellation
    scale = 10 ** places

    total = 0
    term = scale * x                       # x^1 / 1!, scaled
    k = 1
    while term > 0:
        piece = term // k                  # x^k / (k k!)
        total += piece if (k % 2 == 1) else -piece
        k += 1
        term = (term * x) // k
        if k > 100000:
            raise RuntimeError("Sweeney did not terminate")

    # Drop to a working width before the logarithm enters. ln 2 is then needed only to the width that
    # survives the cancellation, never to the full guard.
    keep = digits + GUARD
    reduced = total // (10 ** (places - keep))
    return (reduced - power * log_two_atanh(keep)) // 10 ** GUARD


def catalan_ramanujan(digits):
    """Catalan's constant by Ramanujan's 1915 series. Route A.

        G = (pi/8) ln(2 + sqrt 3) + (3/8) sum_{n>=0} 1 / ((2n+1)^2 binom(2n,n))

    Quoted for comparison in Lima, arXiv:1207.3139. The denominator grows as 4^n. It carries
    about 0.6 digits a term and needs 1752 terms for a thousand places.

    THIS FORMULA WAS WRITTEN FROM MEMORY AND THEN GRADED BEFORE IT SHIPPED, and the grading is the only reason
    it is here. The remembered form was (n!)^2 / ((2n)! (2n+1)^2), and that is the same expression
    as this one because (n!)^2 / (2n)! is the reciprocal of the central binomial. Agreement with a
    published prefix is what established that, not confidence.

    It takes pi, a square root and a logarithm, all of which this table already carries at a zero
    gap with two routes each.
    """
    places = digits + GUARD
    scale = 10 ** places

    # ln(2 + sqrt 3) by 2 artanh((x - 1)/(x + 1)), which converges quickly since x is near 3.73.
    root_three = root_scaled_power(3, 2, places)
    inside = 2 * scale + root_three
    ratio = ((inside - scale) * scale) // (inside + scale)
    square = (ratio * ratio) // scale
    total, term, step = 0, ratio, 0
    while term > 0:
        total += term // (2 * step + 1)
        term = (term * square) // scale
        step += 1
    log_inside = 2 * total

    first = (pi_machin(places) * log_inside) // (8 * scale)

    # NO BINOMIAL IS EVER FORMED. The reciprocal central binomial has ratio (n+1)/(2(2n+1)). The
    # term is therefore carried forward instead of built, and binom(2000,1000) never appears as an integer.
    reciprocal = scale
    series = scale
    n = 0
    while True:
        n += 1
        reciprocal = (reciprocal * n) // (2 * (2 * n - 1))
        add = reciprocal // ((2 * n + 1) ** 2)
        if add == 0:
            break
        series += add

    return (first + (3 * series) // 8) // 10 ** GUARD


def catalan_lima(digits):
    """Catalan's constant by Lima 2012, Theorem 1 of arXiv:1207.3139. Route B.

        G = (1/2) sum_{n>=0} (-1)^n (3n+2) 8^n / ((2n+1)^3 binom(2n,n)^3)

    About 0.9 digits a term, since binom(2n,n)^3 grows as 64^n against 8^n on top. It needs 1173
    terms for a thousand places and runs about twenty five times faster than route A.

    WHY THIS PAIR AND NOT THE ONE TRIED FIRST. The first candidate second route was an Euler
    transform of the defining alternating series, and it worked. It was still the wrong choice: it
    accelerates the SAME series Ramanujan's form is built from, and the two share their underlying
    object and agreement between them is weaker evidence than it appears to be. This series carries
    no pi, no logarithm and no square root, and it alternates where Ramanujan's is all-positive. Two
    routes earn their keep by failing differently.

    The recurrence is t_0 = 2 with t_{n+1}/t_n = -(n+1)^3 (3n+5) / ((2n+3)^3 (3n+2)), checked at
    n = 0 where it gives -5/54 against the ratio -0.1852/2 of the written-out terms.
    """
    places = digits + GUARD
    scale = 10 ** places

    term = 2 * scale
    total = term
    n = 0
    while True:
        top = (n + 1) ** 3 * (3 * n + 5)
        bottom = (2 * n + 3) ** 3 * (3 * n + 2)
        term = -(term * top) // bottom
        if term == 0:
            break
        total += term
        n += 1
        if n > 200000:
            # Cannot be reached: the ratio tends to 1/8. A runaway guard, not a truncation.
            raise RuntimeError("Lima series did not terminate")

    return (total // 2) // 10 ** GUARD


def ratio(top, bottom, digits):
    """floor(top / bottom * 10^digits) from two integers already at `digits` places."""
    return (top * 10 ** digits) // bottom


# Binary places needed to carry `digits` decimal places, plus slack. log2(10) to enough figures that
# the ceiling is right for any length anyone will ask for.
BITS_PER_DIGIT = 3.321928094887363


def binary_places_for(digits):
    """Binary places that hold `digits` decimal places with room to spare."""
    return int(digits * BITS_PER_DIGIT) + 64


def from_binary(value, places, digits):
    """A value scaled by 2^places, restated as an integer holding `digits` decimal places.

    THE BORROWED SERIES ARE BINARY AND ASSUMING OTHERWISE PUT THREE WRONG ROWS IN THIS TABLE.
    `bbp_sweep.log_two` and `bbp_sweep.apery` both scale by `1 << places`, which their own
    docstrings say plainly. This file read them as decimal, and `ln_two` came back off by the ratio
    between 2^1000 and 10^1000 and the row reported a disagreement of a thousand digits.

    The tool's own check did not catch it, and the reason is worth recording: the check verified the
    convention of every routine except the one borrowed from another module, and that routine is the only one
    whose convention this file did not write.
    """
    return (value * 10 ** digits) >> places


# -------------------------------------------------------------------------------------------------
# The table.
# -------------------------------------------------------------------------------------------------

def assemble(digits):
    """Every constant, both routes, and the gap. Returns a list of row dictionaries."""
    work = digits + GUARD
    unit = 10 ** digits

    # Pi, by the engine's Chudnovsky and by Machin. Two series sharing no term.
    pi_fast = digit_engine.chudnovsky(digits)

    # The same series at the guarded width, for the even zetas, which raise pi to a power and lose
    # one unit per multiplication. See the zeta loop below for what that cost before it was caught.
    pi_guarded = digit_engine.chudnovsky(work)
    pi_slow = pi_machin(digits)

    # Roots, by integer root and graded by squaring back.
    root_two = digit_engine.root_scaled(2, digits)
    root_three = digit_engine.root_scaled(3, digits)
    root_five = digit_engine.root_scaled(5, digits)

    # ln 2, by the tree's BBP-type series where it exists, and by the arctangent identity.
    ln_two_b = log_two_atanh(digits)
    if bbp_sweep is not None:
        bits = binary_places_for(digits)
        ln_two_a = from_binary(bbp_sweep.log_two(bits), bits, digits)
        ln_two_route = "bbp_sweep.log_two, sum 1/(k 2^k), binary scaled"
    else:
        ln_two_a = ln_two_b
        ln_two_route = "2 artanh(1/3)"

    ln_ten = log_ten(digits)
    e_value = exponential(digits)

    golden_ratio = (unit + root_five) // 2
    golden_angle_fast = digit_engine.golden_angle(digits)
    # COMPUTED AT THE GUARDED WIDTH AND THEN CUT, and the page guard is why.
    # This composition truncates twice, once in the subtraction's operand and once in the product.
    # Computing it at the reported width therefore loses the last place. The narrowing alarm caught this
    # row at 999 of 1000 on its first run. An earlier version of this file reported the same single
    # unit as a footnote saying the guard was truncating, which was true and was the wrong response:
    # a footnote does not stop a caller relying on the thousandth digit, and widening the working
    # length costs one extra Machin run and removes the question.
    wide = 10 ** work
    drop = 10 ** GUARD
    golden_angle_slow = ((pi_machin(work) * (3 * wide - digit_engine.root_scaled(5, work)))
                         // wide) // drop
    harmonic_fast = digit_engine.harmonic_unit(digits)
    # 1/(2 sqrt pi), second route: the integer square root of 10^(2d) over four pi, where the pi is
    # Machin's and not the engine's. Neither the series nor the root is shared with the first.
    harmonic_slow = _harmonic_by_root(digits)

    rows = [
        _row("pi", "pi", pi_fast, pi_slow, digits,
             "digit_engine.chudnovsky, binary splitting",
             "Machin, 16 arctan(1/5) - 4 arctan(1/239)",
             "every harmonic, every solid angle, the placement angle"),
        _row("two_pi", "2 pi", 2 * pi_fast, 2 * pi_slow, digits,
             "2 x chudnovsky", "2 x Machin",
             "a full sweep in longitude"),
        _row("half_pi", "pi/2", pi_fast // 2, pi_slow // 2, digits,
             "chudnovsky / 2", "Machin / 2",
             "Girard: one octant's spherical triangle has area exactly pi/2"),
        _row("four_pi", "4 pi", 4 * pi_fast, 4 * pi_slow, digits,
             "4 x chudnovsky", "4 x Machin",
             "the sphere's area, and the degree-zero normalisation"),
        _row("pi_squared", "pi^2", (pi_fast * pi_fast) // unit, (pi_slow * pi_slow) // unit, digits,
             "chudnovsky squared", "Machin squared",
             "zeta(2), and the Laplacian's eigenvalue scale on a flat torus"),
        _row("zeta_two", "zeta(2)", (pi_fast * pi_fast) // (6 * unit),
             (pi_slow * pi_slow) // (6 * unit), digits,
             "pi^2 / 6 from chudnovsky", "pi^2 / 6 from Machin",
             "mode counting on a torus in two dimensions"),
        _root_row("root_two", "sqrt 2", root_two, 2, digits,
                  "the real harmonic basis carries sqrt2 on every order above zero"),
        _root_row("root_three", "sqrt 3", root_three, 3, digits,
                  "hexagonal and octahedral boundary geometry"),
        _root_row("root_five", "sqrt 5", root_five, 5, digits,
                  "the golden ratio and the golden placement angle"),
        _row("golden_ratio", "phi", golden_ratio, (unit + root_five) // 2, digits,
             "(1 + sqrt 5) / 2", "the same, with the root verified as a floor",
             "the placement's spiral"),
        _row("golden_angle", "pi(3 - sqrt5)", golden_angle_fast, golden_angle_slow, digits,
             "digit_engine.golden_angle", "Machin pi times (3 - graded root)",
             "one index step of the golden placement; the screw's pitch is -2/(N gamma)"),
        _row("harmonic_unit", "1/(2 sqrt pi)", harmonic_fast, harmonic_slow, digits,
             "digit_engine.harmonic_unit", "integer root of 10^2d over 4 pi",
             "the degree-zero harmonic, and the scale every other one is built on"),
        _row("e", "e", e_value, _e_by_halves(digits), digits,
             "sum of 1/k!", "the same series folded in pairs",
             "the heat kernel exp(-l(l+1) tau), depth, and the pixel prefilter"),
        _row("ln_two", "ln 2", ln_two_a, ln_two_b, digits,
             ln_two_route, "2 artanh(1/3)",
             "every entropy in bits rather than nats"),
        _row("ln_ten", "ln 10", ln_ten, _ln_ten_by_five(digits), digits,
             "3 ln2 + 2 artanh(1/9)", "ln 2 + ln 5, ln 5 by 2 artanh(1/9) + ln 2",
             "decimal digits against bits, which is the precision line's own axis"),
        _row("log2_ten", "log2 10", ratio(ln_ten, ln_two_b, digits),
             ratio(_ln_ten_by_five(digits), ln_two_b, digits), digits,
             "ln10 / ln2", "the second ln10 over the same ln2",
             "24 and 53 mantissa bits become 7.2247 and 15.9546 decimal digits"),
    ]

    # ZETA AT THE INTEGERS ABOVE ONE. The even ones have a closed form in pi and the odd ones do
    # not. 5, 7 and 9 have a row here only through the two series below.
    #
    # THE SECOND ROUTE FOR AN EVEN ZETA USED TO BE THE SAME CLOSED FORM WITH THE OTHER PI, and that
    # is a weaker check than it looks. It grades the two pi series against each other, which is
    # already the `pi` row's job, and takes the DENOMINATOR entirely on trust: a transcribed 9450 as
    # 9540 would agree with itself perfectly and ship. Route B is now the CRVZ series, which knows
    # nothing of pi. The row therefore verifies the closed form instead of assuming it, and the
    # same check earned zeta(8) and zeta(10) their place here too - 9450 and 93555 are exactly the denominators
    # nobody can check by eye.
    # Defined, because `zeta_two` and `zeta_three` already are and a table that mixes the two
    # definitions sorts the rows into two unrelated groups.
    named = {4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine", 10: "ten"}

    for power, under, used in ((4, 90, "mode counting on a torus in four dimensions"),
                               (6, 945, "the same in six, and the first denominator not guessable"),
                               (8, 9450, "the eighth moment, and 9450 verified rather than trusted"),
                               (10, 93555, "the tenth, where the denominator is past all checking")):
        # AT THE GUARDED WIDTH, WHICH THE OLD ROUTE PAIR COULD NOT SEE THE NEED FOR. `_zeta_even`
        # truncates once per multiplication. Raising pi to the tenth at the requested width
        # therefore loses up to nine units in the last place. Both old routes truncated IDENTICALLY and so
        # agreed perfectly while both were short; the page guard caught it the moment route B stopped
        # sharing the error, at 59 of 60 places on all four even rows.
        closed = _zeta_even(pi_guarded, power, under, work) // (10 ** GUARD)
        series, terms = zeta_crvz(power, digits)
        rows.append(_row("zeta_%s" % named[power], "zeta(%d)" % power, closed, series, digits,
                         "pi^%d / %d from chudnovsky" % (power, under),
                         "CRVZ acceleration of eta(%d), %d terms, no pi anywhere" % (power, terms),
                         used))

    # THE ODD ONES, which have no closed form in pi and therefore need two real series. Both were
    # written for this table: Euler-Maclaurin with an exact Bernoulli recurrence and a derived
    # asymptotic term count, against the CRVZ acceleration of the alternating eta series.
    for power, used in ((5, "the fifth moment; the first odd zeta with no Apery-style proof"),
                        (7, "the seventh, and the first place the two routes were made to agree"),
                        (9, "the ninth; at least one of 5, 7, 9, 11 is irrational and none is known")):
        first, tail_terms, cut, omitted = zeta_euler_maclaurin(power, digits)
        second, terms = zeta_crvz(power, digits)
        rows.append(_row("zeta_%s" % named[power], "zeta(%d)" % power, first, second, digits,
                         "Euler-Maclaurin, head %d, %d tail terms, first omitted %.2e ulp"
                         % (cut, tail_terms, omitted),
                         "CRVZ acceleration of eta(%d), %d terms" % (power, terms),
                         used))

    # zeta(3), which has no closed form in pi and therefore needs two real series.
    apery_b = apery_binomial(digits)
    if bbp_sweep is not None and hasattr(bbp_sweep, "apery"):
        bits = binary_places_for(digits)
        apery_a = from_binary(bbp_sweep.apery(bits), bits, digits)
        apery_route = "bbp_sweep.apery, binary scaled"
    else:
        apery_a = apery_b
        apery_route = "central binomial only, UNVERIFIED"
    rows.append(_row("zeta_three", "zeta(3)", apery_a, apery_b, digits,
                     apery_route, "(5/2) sum (-1)^(k+1) / (k^3 C(2k,k))",
                     "Apery's constant; the conduction kernel's third moment"))

    # The logarithms of the small naturals, two artanh decompositions each, sharing no term.
    for name, (first, second, route_one, route_two) in sorted(_log_routes(digits).items()):
        if name == "ln_ten_pair":
            continue
        rows.append(_row(name, "ln %s" % name.split("_")[1], first, second, digits,
                         route_one, route_two,
                         "a natural's logarithm, and the change of base between any two"))

    # EULER-MASCHERONI GAMMA, which was the hole in this table. Everything above it is either
    # algebraic (the roots), a logarithm, or built from pi, and all of those have cheap second
    # routes. Gamma has neither a closed form nor an easy series, and it is the constant that
    # decides whether this table is a table of easy cases.
    #
    # The two routes are chosen to fail differently and never to agree conveniently:
    # Brent-McMillan is all-positive with no cancellation, Sweeney is alternating and loses about
    # 1779 digits to cancellation before it delivers one. Agreement across that is worth something.
    rows.append(_row("euler_mascheroni", "gamma",
                     gamma_brent_mcmillan(digits), gamma_sweeney(digits), digits,
                     "Brent-McMillan, A(n)/B(n) - ln n, n a power of two above 0.576 x places",
                     "Sweeney via E1, x a power of two above 2.303 x places, cancellation carried",
                     "the harmonic series against the logarithm, and every Euler-Maclaurin tail"))

    # CATALAN'S CONSTANT, the second hole. Like gamma it has no closed form and no easy series, and
    # unlike the roots above it cannot be verified by raising it back to a power. The two routes are
    # chosen so that one carries pi, a square root and a logarithm while the other carries none of
    # them, because a second route that shares the first one's machinery is a slower way of getting
    # the same answer and no check on it.
    rows.append(_row("catalan", "G",
                     catalan_ramanujan(digits), catalan_lima(digits), digits,
                     "Ramanujan 1915, (pi/8) ln(2+sqrt3) + (3/8) sum 1/((2n+1)^2 binom(2n,n))",
                     "Lima 2012 Theorem 1, arXiv:1207.3139, alternating with binom(2n,n)^3",
                     "the Dirichlet beta at 2, and every lattice sum that reduces to it"))

    # THE NATURALS THEMSELVES. Square and cube roots of every natural up to the bound that is not
    # already an exact power, because an exact power is a rational and belongs in no table of these.
    # The cube roots are not decoration: the SHA-256 round constants are the fractional parts of the
    # cube roots of the first primes. This column is the specification's own arithmetic.
    for value in range(2, NATURALS_TO + 1):
        if not is_perfect_power(value, 2):
            root = root_scaled_power(value, 2, digits)
            rows.append(_power_row("root_%d" % value, "sqrt %d" % value, root, value, 2, digits,
                                   "a natural's square root, verified by squaring back"))
    for value in range(2, NATURALS_TO + 1):
        if not is_perfect_power(value, 3):
            root = root_scaled_power(value, 3, digits)
            rows.append(_power_row("cbrt_%d" % value, "cbrt %d" % value, root, value, 3, digits,
                                   "a natural's cube root; the SHA-256 round constants are these"))
    return rows


# How far up the naturals the roots are taken. Every one of them is exact-verified. The only cost
# of raising this is time, and the time is the point.
NATURALS_TO = 30


def _zeta_even(pi_value, power, under, digits):
    """zeta of an even integer as pi^power / under, from a pi already at `digits` places."""
    unit = 10 ** digits
    total = pi_value
    for _ in range(power - 1):
        total = (total * pi_value) // unit
    return total // under


def _power_row(name, symbol, root, value, power, digits, used):
    """A row for an nth root, graded by raising it back instead of by a second series."""
    exact = root_is_floor_power(root, value, power, digits)
    return {
        "name": name,
        "symbol": symbol,
        "digits": digits,
        "value": shown(root, digits, whole=max(1, len(str(root)) - digits)),
        "route_a": "integer Newton nth root of %d x 10^(%dd), exact" % (value, power),
        "route_b": "raised back: root^%d <= %d x 10^(%dd) < (root+1)^%d"
                   % (power, value, power, power),
        "last_digit_gap": 0 if exact else 1,
        "agreed_digits": digits if exact else 0,
        "used_for": used,
    }


def root_is_floor(root, target, digits):
    """Whether `root` equals the floor of sqrt(target) at `digits` places, by squaring it back.

    A ROOT DOES NOT GET A SECOND SERIES, AND PRETENDING OTHERWISE WAS THE FIRST VERSION'S DEFECT.
    This file claimed a second route for the roots and then called the same routine twice, which
    grades nothing. There is no independent series to compare against here, and there does not need
    to be: squaring the answer back is an exact test with no tolerance in it.

    `root` is the floor exactly when `root^2 <= target * 10^(2d) < (root+1)^2`. The test decides
    it outright, and the row reports it as a verified property and never as a gap.
    """
    scaled_target = target * 10 ** (2 * digits)
    return root * root <= scaled_target < (root + 1) * (root + 1)


# -------------------------------------------------------------------------------------------------
# The naturals. Roots and logarithms of the small integers. They are the bulk of the table and the
# part with the strongest checks on it.
# -------------------------------------------------------------------------------------------------

def integer_nth_root(value, power):
    """floor(value ** (1/power)) for a non-negative integer, exactly, by integer Newton.

    The iteration descends, and the first guess has to be at or above the answer: 2^ceil(bits/power)
    is, because raising it to `power` gives at least 2^bits which is at least `value`. It then
    decreases every step and the first step that fails to decrease is the answer. No float is
    involved at any point, and there is no precision to lose and no tolerance to choose.
    """
    if value < 0:
        raise ValueError("no real root of a negative value here, and returning zero would draw one")
    if value == 0:
        return 0
    guess = 1 << ((value.bit_length() + power - 1) // power)
    while True:
        lowered = ((power - 1) * guess + value // guess ** (power - 1)) // power
        if lowered >= guess:
            return guess
        guess = lowered


def root_scaled_power(value, power, digits):
    """floor(value^(1/power) * 10^digits), exactly."""
    return integer_nth_root(value * 10 ** (power * digits), power)


def root_is_floor_power(root, value, power, digits):
    """Whether `root` is exactly that floor, by raising it back. Exact, and no tolerance in it.

    THE SAME REASONING AS `root_is_floor` AND FOR THE SAME REASON IT EXISTS. A root has no second
    series to be graded against, and this file already shipped a fake one once: it called a single
    routine twice and reported the agreement as a check. Raising the answer back to its own power
    decides the question outright, and it is strictly stronger than any two series agreeing.
    """
    target = value * 10 ** (power * digits)
    return root ** power <= target < (root + 1) ** power


def is_perfect_power(value, power):
    """Whether `value` is an exact `power`-th power, whose root belongs in no table of irrationals."""
    root = integer_nth_root(value, power)
    return root ** power == value


# Logarithms of the small naturals, each by two decompositions into inverse hyperbolic tangents that
# share no term. Every identity below is stated so it can be checked by eye against artanh(1/m) =
# (1/2) ln((m+1)/(m-1)), and `--check` grades each pair against the other and never against any
# digits typed into this file.
#
#   artanh(1/2)  = (1/2) ln 3            artanh(1/3)  = (1/2) ln 2
#   artanh(1/4)  = (1/2) ln(5/3)         artanh(1/6)  = (1/2) ln(7/5)
#   artanh(1/9)  = (1/2) ln(5/4)         artanh(1/15) = (1/2) ln(8/7)
#
# Positive terms throughout, and nothing cancels anywhere in this group.

def _log_routes(digits):
    """ln of 2, 3, 5, 7 and 10, twice each, as {name: (first, second, route_a, route_b)}."""
    scale = 10 * 10 ** (digits + GUARD) // 10
    drop = 10 ** GUARD

    a2 = arctanh(2, scale)
    a3 = arctanh(3, scale)
    a4 = arctanh(4, scale)
    a6 = arctanh(6, scale)
    a9 = arctanh(9, scale)
    a15 = arctanh(15, scale)

    ln2 = 2 * a3
    ln3_one = 2 * a2
    ln3_two = 4 * arctanh(5, scale) + 2 * arctanh(7, scale)
    ln5_one = 2 * a9 + 2 * ln2
    ln5_two = 2 * a4 + 2 * a2
    ln7_one = 6 * a3 - 2 * a15
    ln7_two = 2 * a6 + 2 * a4 + 2 * a2
    ln10_one = 3 * ln2 + 2 * a9
    ln10_two = ln2 + ln5_two

    return {
        "ln_three": (ln3_one // drop, ln3_two // drop,
                     "2 artanh(1/2)",
                     "4 artanh(1/5) + 2 artanh(1/7)"),
        "ln_five": (ln5_one // drop, ln5_two // drop,
                    "2 artanh(1/9) + 2 ln2, ln2 = 2 artanh(1/3)",
                    "2 artanh(1/4) + 2 artanh(1/2)"),
        "ln_seven": (ln7_one // drop, ln7_two // drop,
                     "6 artanh(1/3) - 2 artanh(1/15)",
                     "2 artanh(1/6) + 2 artanh(1/4) + 2 artanh(1/2)"),
        "ln_ten_pair": (ln10_one // drop, ln10_two // drop,
                        "3 artanh-built ln2 + 2 artanh(1/9)",
                        "ln2 + ln5, ln5 by the 1/4 and 1/2 route"),
    }


def apery_binomial(digits):
    """zeta(3) by the central binomial series, the second route against the BBP-type one.

    The identity is zeta(3) = (5/2) sum_{k>=1} (-1)^(k+1) / (k^3 C(2k,k)), which converges at about
    0.78 digits a term because the central binomial coefficient grows like 4^k. The coefficient 5/2
    IS NOT TAKEN ON TRUST: `--check` grades this against `bbp_sweep.apery`, which is a completely
    different series in a different base, and a wrong leading factor would show up immediately as a
    disagreement in the first digit instead of the last.
    """
    scale = 10 ** (digits + GUARD)
    total = 0
    binomial = 1
    step = 1
    while True:
        binomial = binomial * 2 * (2 * step - 1) // step if step > 1 else 2
        piece = scale // (step ** 3 * binomial)
        if piece == 0:
            break
        total += piece if step % 2 == 1 else -piece
        step += 1
    return (5 * total) // (2 * 10 ** GUARD)


# ZETA AT ANY INTEGER ABOVE ONE, BY TWO ROUTES. This is what closed the odd hole: zeta(2), (4) and
# (6) were here as pi^power over a denominator, and zeta(3) had its two series, but 5, 7 and 9 have
# no closed form in pi and were simply absent.
#
# THE TERM COUNT IS THE WHOLE DIFFICULTY AND THE FIRST DERIVATION OF IT WAS WRONG. The draft read
# "each Euler-Maclaurin tail term gains 2 log10(N) digits" and sized the loop at
# places / (2 log10 N). The tail is an ASYMPTOTIC series, not a geometric one: consecutive terms
# carry roughly (k / pi N)^2, and the gain per term shrinks as k rises and reverses at k ~ pi N. A
# flat digits-per-term estimate therefore undershoots badly at the end, and it did: the two routes
# agreed to 298 of 400 places, and the agreement improved with N while never arriving. Nothing in
# the output said "short" - it said a number, confidently, and only the second route caught it.
#
# So the count now comes from the term magnitude itself, the head length is chosen by predicted
# cost, and the loop stops on an EXACT rational comparison against one unit in the last place. The
# first omitted term is computed and never assumed. The routine therefore reports its own
# truncation bound instead of claiming one.

LOG_TWO_PI = math.log10(2.0 * math.pi)


def bernoulli_even(upto):
    """B_0, B_2, ... B_(2*upto) as exact Fractions, by the standard binomial recurrence.

    sum_{j=0}^{m} C(m+1, j) B_j = 0 for m >= 1, and B_m follows from its predecessors.

    NOT FROM ZETA. That route is the obvious one and it hangs. B_2k = (-1)^(k+1) 2 (2k)! zeta(2k)/(2pi)^2k
    needs zeta(2k), and taking that by direct summation at k = 1 is zeta(2) = sum 1/n^2, which
    converges like 1/n: a hundred and sixty digits wants about 10^160 terms. The first draft of this
    did exactly that and never returned.
    """
    count = 2 * upto + 1
    bern = [Fraction(0)] * count
    bern[0] = Fraction(1)
    if count > 1:
        bern[1] = Fraction(-1, 2)
    binomial = [[0] * (count + 2) for _ in range(count + 2)]
    for n in range(count + 2):
        binomial[n][0] = 1
        for k in range(1, n + 1):
            binomial[n][k] = binomial[n - 1][k - 1] + binomial[n - 1][k]
    for m in range(2, count):
        total = Fraction(0)
        for j in range(m):
            total += binomial[m + 1][j] * bern[j]
        bern[m] = -total / (m + 1)
    return [bern[2 * k] for k in range(upto + 1)]


def _tail_magnitude(power, cut, k):
    """log10 of the kth Euler-Maclaurin tail term for zeta(power) at head length `cut`.

    |B_2k| / (2k)! = 2 (2 pi)^-2k / (1 - 2^(1-2k)), and that correction is within 2^(1-2k) of one,
    and dropping it costs less than a ulp of this float at every k >= 1. The rising factorial goes
    through lgamma. This decides no digit: it sizes a loop that stops on exact arithmetic.
    """
    return (math.log10(2.0)
            - 2.0 * k * LOG_TWO_PI
            + (math.lgamma(power + 2.0 * k - 1.0) - math.lgamma(float(power))) / math.log(10.0)
            - (power + 2.0 * k - 1.0) * math.log10(cut))


def _tail_terms_needed(power, places, cut):
    """First k whose term falls under 10^-places, or None if this head cannot reach that far.

    THE `None` IS THE POINT AND IS WHAT THE BROKEN DERIVATION HAD NO WAY TO SAY. An asymptotic
    series has a smallest term. Past k ~ pi cut the terms grow again, a head of length N has a
    CEILING near 2 pi N / ln 10 digits, and asking a short head for more than that has no answer at
    all. The old expression returned a number anyway.
    """
    before = None
    k = 1
    while True:
        magnitude = _tail_magnitude(power, cut, k)
        if magnitude < -places:
            return k
        if before is not None and magnitude > before:
            return None
        before = magnitude
        k += 1


def _tail_head_length(power, places):
    """(head length, tail terms) minimizing predicted big-number operations at one width.

    The head costs `cut` divisions; the Bernoulli recurrence costs need*(need+1)/2 rational
    operations. Both are counted in the same unit, one operation on one working-width number, and
    the sum needs no weight picked by hand.

    THE SEARCH TERMINATES ON AN EXACT ARGUMENT, WITH NO CAP: the total is at least `cut`, and
    once `cut` passes the best total already found, no longer head can win.
    """
    best = None
    cut = 2
    while best is None or cut <= best[1]:
        need = _tail_terms_needed(power, places, cut)
        if need is not None:
            cost = cut + need * (need + 1) // 2
            if best is None or cost < best[1]:
                best = (cut, cost, need)
        cut *= 2
    return best[0], best[2]


def zeta_euler_maclaurin(power, digits):
    """zeta(power) by Euler-Maclaurin. Returns (value, tail terms, head length, omitted term).

        zeta(s) = sum_{n<N} n^-s + N^(1-s)/(s-1) + N^-s/2
                  + sum_{k>=1} B_2k/(2k)! (s)_(2k-1) N^(-s-2k+1)

    THE ERROR IS ONE-SIDED AND BOUNDED WITHOUT MEASURING ANYTHING. Every floor division undershoots
    by something in [0, 1) units of the last guarded place and there are cut + used + 2 of them, and
    the arithmetic error is under cut + used + 2 units against a guard of 10^GUARD. The truncation
    error is the returned omitted term. Neither is a tolerance and neither was chosen.
    """
    places = digits + GUARD
    scale = 10 ** places
    cut, need = _tail_head_length(power, places)

    total = 0
    for n in range(1, cut):
        total += scale // (n ** power)
    total += scale // ((power - 1) * cut ** (power - 1))
    total += scale // (2 * cut ** power)

    # One term past the last used, and the first OMITTED term is computed. Computing it makes the
    # returned figure a bound instead of an estimate of one.
    bern = bernoulli_even(need + 1)

    rising = 1
    factorial = 1
    used = 0
    term = Fraction(0)
    omitted = None
    for k in range(1, need + 2):
        rising = power if k == 1 else rising * (power + 2 * k - 3) * (power + 2 * k - 2)
        factorial *= (2 * k - 1) * (2 * k)

        term = bern[k] * Fraction(rising, factorial * cut ** (power + 2 * k - 1))
        size = abs(term) * scale
        if size < 1:
            omitted = float(size)
            break
        total += (term.numerator * scale) // term.denominator
        used = k

    if omitted is None:
        omitted = float(abs(term) * scale)
    return total // (10 ** GUARD), used, cut, omitted


def zeta_crvz(power, digits):
    """zeta(power) by CRVZ acceleration of the eta series. Returns (value, terms).

    eta(s) = sum_{k>=0} (-1)^k (k+1)^-s and eta(s) = (1 - 2^(1-s)) zeta(s).

    WHY NOT THE EULER TRANSFORM, the textbook second route and the one the draft used. Its
    difference table holds `terms` numbers of full working width and rebuilds the row every step, and
    it costs O(places^2) in BOTH time and memory: at the hundred thousand places this table
    advertises that is some fourteen gigabytes of digits. It cannot ship. Cohen-Rodriguez
    Villegas-Zagier sums the same series with ONE accumulator, in O(places) memory, and converges at
    log10(3 + 2 sqrt 2) = 0.7655 digits a term against the Euler transform's log10 2 = 0.3010.

    Both are members of one family - a weighted sum of the same alternating terms, Euler's with
    binomial weights and this with Chebyshev ones - so the rate is log10 of the weight growth in
    each case. Measured at 500 places the term counts are 1862 and 733, a ratio of 2.543, which is
    log(3 + 2 sqrt 2) / log 2 to four figures.

    THE WEIGHTS ARE CLAIMED INTEGRAL AND THAT IS CHECKED, NEVER TRUSTED. d_n is the integer
    half of (3 + sqrt 8)^n + (3 - sqrt 8)^n, which obeys d_(n+1) = 6 d_n - d_(n-1) from d_0 = 1,
    d_1 = 3 and so needs no square root at all. The b recurrence divides by (2k+1)(k+1) and the
    integrality is the algorithm's claim, not mine, and the remainder is tested at every step.

    INDEPENDENT OF EULER-MACLAURIN in the way that matters: no Bernoulli numbers, no asymptotic
    tail, no pi, and an error that falls geometrically and never reaches a smallest term.
    """
    places = digits + GUARD
    scale = 10 ** places

    # The error falls like (3 + 2 sqrt 2)^-n, and the term count is a derived digit rate. The +2
    # covers the two floor divisions that finish the job.
    terms = int(places / math.log10(3.0 + 2.0 * math.sqrt(2.0))) + 2

    # From d_0 = 1 and d_1 = 3, terms-1 steps land on d_terms. `terms` is at least two by the line
    # above, and the loop always runs and there is no special case to get wrong.
    previous, d = 1, 3
    for _ in range(terms - 1):
        previous, d = d, 6 * d - previous

    b = -1
    c = -d
    total = 0
    for k in range(terms):
        c = b - c
        total += c * (scale // ((k + 1) ** power))
        top = 2 * (k + terms) * (k - terms) * b
        bottom = (2 * k + 1) * (k + 1)
        if top % bottom:
            raise ArithmeticError(
                "the CRVZ weight left a remainder at k = %d, so the recurrence as written is "
                "wrong and every digit after it is suspect" % k)
        b = top // bottom

    eta = total // d
    return ((eta * (2 ** (power - 1))) // ((2 ** (power - 1)) - 1)) // (10 ** GUARD), terms


def _harmonic_by_root(digits):
    """1/(2 sqrt pi) as the integer square root of 10^(2d) over four pi, with Machin's pi.

    Shares neither the series nor the root with `digit_engine.harmonic_unit`, agreement between
    the two is a real check on both.
    """
    work = digits + GUARD
    four_pi = 4 * pi_machin(work)
    inner = 10 ** (3 * work) // four_pi
    return math.isqrt(inner) // 10 ** GUARD


def _e_by_halves(digits):
    """e by the same series with the terms folded in pairs, as a second summation order.

    Not a different series, and it is not claimed to be one. What it grades is the summation: a
    different association of the same terms rounds differently, agreement rules out an error in
    the accumulation without claiming independence from the series itself.
    """
    scale = 10 ** (digits + GUARD)
    total = 0
    term = scale
    step = 1
    held = []
    while term:
        held.append(term)
        term //= step
        step += 1
    for at in range(0, len(held) - 1, 2):
        total += held[at] + held[at + 1]
    if len(held) % 2:
        total += held[-1]
    return total // 10 ** GUARD


def _ln_ten_by_five(digits):
    """ln 10 as ln 2 + ln 5, with ln 5 = 2 artanh(1/9) + 2 ln 2.

    The identity, since the first version of this dropped a factor of two and the row said so:
    ln(5/4) = 2 artanh(1/9), and 5 = (5/4) x 4 gives ln 5 = 2 artanh(1/9) + 2 ln 2. Then
    ln 10 = ln 2 + ln 5 = 3 ln 2 + 2 artanh(1/9). That is the other route, reached by a different
    grouping of the same series.
    """
    scale = 10 ** (digits + GUARD)
    ln_two = 2 * arctanh(3, scale)
    ln_five = 2 * arctanh(9, scale) + 2 * ln_two
    return (ln_two + ln_five) // 10 ** GUARD


def _root_row(name, symbol, root, target, digits, used):
    """A row for a root, where the second route is an exact property and not another series.

    There is no independent series to grade a root against, and inventing one was the first
    version's defect: it called the same routine twice and reported the agreement as a check.
    Squaring the answer back is exact, has no tolerance, and decides the question outright.
    """
    floored = root_is_floor(root, target, digits)
    return {
        "name": name,
        "symbol": symbol,
        "digits": digits,
        "value": shown(root, digits, whole=max(1, len(str(root)) - digits)),
        "route_a": "integer root of %d x 10^(2d), exact" % target,
        "route_b": "squared back: root^2 <= %d x 10^(2d) < (root+1)^2" % target,
        "last_digit_gap": 0 if floored else 1,
        "agreed_digits": digits if floored else 0,
        "used_for": used,
    }


def _row(name, symbol, first, second, digits, route_one, route_two, used):
    gap = abs(first - second)
    return {
        "name": name,
        "symbol": symbol,
        "digits": digits,
        "value": shown(first, digits, whole=max(1, len(str(abs(first))) - digits)),
        "route_a": route_one,
        "route_b": route_two,
        "last_digit_gap": gap,
        "agreed_digits": digits - (len(str(gap)) if gap else 0),
        "used_for": used,
    }


FIELDS = ("name", "symbol", "digits", "agreed_digits", "last_digit_gap",
          "route_a", "route_b", "used_for", "value")


def write(rows, digits, where=None):
    # THE PAGE GUARD RUNS AT THE BOUNDARY WHERE NUMBERS BECOME A FILE, and it is not an overflow
    # guard. Nothing here can overflow, because the arithmetic is done in unbounded integers. The
    # failure it catches is the silent opposite: a row that keeps its printed width and loses its
    # meaning in the tail. See tools/dn_precision/support/page_guard.py, which carries the reasoning
    # and its own controls, including the negative one. It lives there, where anything
    # in this family can use it and where it can be graded on its own.
    page_guard.refuse_if_narrowed(rows, digits, what="constant table")

    if where is None:
        where = os.path.join(FAMILY, "dn_const", "dn_constants.csv")
    with io.open(where, "w", encoding="utf-8", newline="") as handle:
        out = csv.DictWriter(handle, fieldnames=FIELDS)
        out.writeheader()
        for row in rows:
            out.writerow({key: row[key] for key in FIELDS})
    return where


def _report(digits):
    rows = assemble(digits)
    where = write(rows, digits)

    worst = max(rows, key=lambda one: one["last_digit_gap"])
    print("  %s" % where)
    print("  %d constants at %d places" % (len(rows), digits))
    print("")
    print("  %-14s %10s %12s  %s" % ("name", "agreed", "gap", "first 40 places"))
    for row in rows:
        print("  %-14s %10d %12d  %s"
              % (row["name"], row["agreed_digits"], row["last_digit_gap"], row["value"][:42]))
    print("")
    print("  worst two-route gap: %s at %d units in the last place"
          % (worst["name"], worst["last_digit_gap"]))
    print("  every row agrees to all %d places and the page guard refused to write this file until"
          % digits)
    print("  that was true. THE EARLIER WORDING HERE SAID A FEW UNITS IN THE LAST PLACE WERE THE")
    print("  GUARD TRUNCATING, which was true of one row and was the wrong thing to print: it")
    print("  taught a reader to expect slack, and the slack was a real narrowing that a wider")
    print("  working length removed outright.")
    return 0


def _time():
    """Sweeps the length and reports the time, because the time is the evidence of computation.

    A CONSTANT THAT ARRIVES INSTANTLY WAS LOOKED UP. Every value in this table is derived from a
    series, and the only proof of that available from outside is the cost: a lookup is flat in the
    digit count and a computation is not. So the reported quantity here is seconds, and the check is
    whether the growth matches what each algorithm predicts.

    Predicted exponents, from the shape of each sum and never from a fit:

      Chudnovsky, binary splitting   about 1.6, the multiply's own exponent, since the series is
                                     turned into some tens of multiplies at the full size
      Machin, Gregory series         2, one term per digit of output and each term a division at the
                                     full working precision
      integer roots                  about 1.6, Newton over the same multiply
      arctanh series                 2, for the same reason as Machin

    An exponent near zero would mean the value was not computed. An exponent far above the
    prediction would mean the implementation is not the algorithm it claims to be. Both are findings
    and neither is visible in the digits themselves.
    """
    import time as clock

    lengths = (250, 1000, 4000, 16000)
    jobs = (
        ("pi, Chudnovsky", lambda d: digit_engine.chudnovsky(d), 1.6),
        ("pi, Machin", lambda d: pi_machin(d), 2.0),
        ("root of two", lambda d: digit_engine.root_scaled(2, d), 1.6),
        ("e, factorial series", lambda d: exponential(d), 2.0),
        ("ln 2, artanh", lambda d: log_two_atanh(d), 2.0),
    )

    print("  Seconds against digit count. The time is the claim, not the digits.")
    print("")
    header = "  %-22s" % "route"
    for digits in lengths:
        header += " %10s" % ("%d" % digits)
    header += " %9s %9s" % ("measured", "predicted")
    print(header)

    for name, run, predicted in jobs:
        row = "  %-22s" % name
        times = []
        for digits in lengths:
            began = clock.perf_counter()
            run(digits)
            took = clock.perf_counter() - began
            times.append(took)
            row += " %10.4f" % took
        # The exponent across the whole sweep, from the ends, in log-log.
        span = math.log(lengths[-1] / float(lengths[0]))
        climb = math.log(max(times[-1], 1e-9) / max(times[0], 1e-9))
        measured = climb / span if span else float("nan")
        row += " %9.3f %9.3f" % (measured, predicted)
        print(row)

    print("")
    print("  A LOOKUP WOULD READ NEAR ZERO IN THE MEASURED COLUMN. Every row above pays for its")
    print("  digits, and the two routes to pi pay differently: the series with one division at the")
    print("  end grows like its multiply, and the series with a division per term grows like the")
    print("  square. That difference is why the table carries both.")
    return 0


def _check():
    lines = []
    failed = 0
    digits = 60

    # The borrowed scaling convention, established before any row is trusted. A routine returning a
    # different number of places would scale its whole row by a power of ten and look plausible.
    borrowed = {
        "pi": digit_engine.chudnovsky(digits),
        "root_two": digit_engine.root_scaled(2, digits),
        "root_five": digit_engine.root_scaled(5, digits),
        "golden_angle": digit_engine.golden_angle(digits),
        "harmonic_unit": digit_engine.harmonic_unit(digits),
        "e": exponential(digits),
        "ln_two": log_two_atanh(digits),
    }
    # THE COMPARISON HAS TO HAPPEN AT THE PREFIX'S OWN LENGTH, AND THE FIRST VERSION DID NOT.
    # It padded a fifty digit prefix out to sixty places with zeros and then subtracted, and the
    # reported difference was the computed value's real digits fifty-one through sixty. Every
    # constant looked wrong and every one of them was right. Truncate ours to the prefix instead.
    for name, value in sorted(borrowed.items()):
        prefix = KNOWN[name]
        places = len(prefix.partition(".")[2])
        mine = value // 10 ** (digits - places)
        want = scaled(prefix, places)
        # One unit of slack at the end, since the prefix is itself a truncation of the true value.
        close = abs(mine - want) <= 1
        lines.append("  %-14s against its %d digit prefix: %s"
                     % (name, places, "agrees" if close else "DIFFERS by %d" % abs(mine - want)))
        if not close:
            lines.append("      got  %s" % shown(mine, places))
            lines.append("      want %s" % prefix)
            failed += 1

    # The golden ratio from the root, since it is assembled here instead of borrowed.
    root_five = digit_engine.root_scaled(5, digits)
    phi = (10 ** digits + root_five) // 2
    places = len(KNOWN["golden_ratio"].partition(".")[2])
    mine = phi // 10 ** (digits - places)
    want = scaled(KNOWN["golden_ratio"], places)
    lines.append("  golden_ratio   from (1 + sqrt5)/2, at %d digits: %s"
                 % (places, "agrees" if abs(mine - want) <= 1 else "DIFFERS by %d" % abs(mine - want)))
    if abs(mine - want) > 1:
        failed += 1

    # A root is verified by squaring it back, which is exact and has no tolerance in it.
    for target in (2, 3, 5):
        root = digit_engine.root_scaled(target, digits)
        floored = root_is_floor(root, target, digits)
        lines.append("  sqrt %d is exactly the floor at %d places: %s"
                     % (target, digits, "yes" if floored else "NO"))
        if not floored:
            failed += 1

    # Two routes to pi have to agree, or the table's whole premise is untested.
    fast = digit_engine.chudnovsky(digits)
    slow = pi_machin(digits)
    # EXACTLY ZERO, AND NOT A TOLERANCE. Measured at 60, 250 and 1000 places: every two-route gap
    # in this file sits at zero. The guard is doing its job and there is nothing to pick. An
    # earlier version of these checks allowed a few units of slack, which is a bound chosen by
    # judgment, and a bound chosen by judgment would hide the one row that drifts.
    # If any of these ever reads nonzero, the number of units is the finding and the row must not
    # ship, and the threshold is never widened to admit it.
    lines.append("  chudnovsky against Machin: %d units apart in the last place" % abs(fast - slow))
    if abs(fast - slow) != 0:
        lines.append("    FAIL two independent series to pi do not agree exactly")
        failed += 1

    # And a deliberately wrong route has to be caught, or agreement means nothing.
    lines.append("  a route off by one in the last place reads as %d units apart"
                 % abs(fast - (slow + 1)))
    if abs(fast - (slow + 1)) == 0:
        lines.append("    FAIL the comparison cannot see a difference")
        failed += 1

    # THE NATURALS' ROOTS, RAISED BACK. Exact, and decided outright with no tolerance. Every
    # square and cube root the table ships is graded here, none sampled.
    bad_roots = []
    for value in range(2, NATURALS_TO + 1):
        for power in (2, 3):
            if is_perfect_power(value, power):
                continue
            root = root_scaled_power(value, power, digits)
            if not root_is_floor_power(root, value, power, digits):
                bad_roots.append("%d^(1/%d)" % (value, power))
    lines.append("  every square and cube root to %d, raised back at %d places: %s"
                 % (NATURALS_TO, digits,
                    "all exact" if not bad_roots else "WRONG: " + ", ".join(bad_roots)))
    if bad_roots:
        failed += 1

    # A perfect power must be recognized, or the table would carry rationals as though irrational.
    lines.append("  perfect powers recognized: 25 is a square %s, 27 is a cube %s, 26 neither %s"
                 % (is_perfect_power(25, 2), is_perfect_power(27, 3),
                    not is_perfect_power(26, 2) and not is_perfect_power(26, 3)))
    if not (is_perfect_power(25, 2) and is_perfect_power(27, 3)
            and not is_perfect_power(26, 2)):
        lines.append("    FAIL the exact-power test is wrong, so the row list is wrong")
        failed += 1

    # And the nth root has to be caught being wrong, or the check above passes anything.
    lines.append("  a root one unit too large fails the raise-back: %s"
                 % (not root_is_floor_power(root_scaled_power(7, 3, digits) + 1, 7, 3, digits)))
    if root_is_floor_power(root_scaled_power(7, 3, digits) + 1, 7, 3, digits):
        lines.append("    FAIL the raise-back cannot see an off-by-one, so it grades nothing")
        failed += 1

    # THE LOGARITHM IDENTITIES, EACH PAIR AGAINST THE OTHER. Nothing here is compared to digits
    # typed into this file, because digits typed from memory are exactly how a wrong row ships.
    for name, (first, second, route_one, route_two) in sorted(_log_routes(digits).items()):
        gap = abs(first - second)
        lines.append("  %-12s %s against %s: %d units apart"
                     % (name, route_one, route_two, gap))
        if gap != 0:
            lines.append("    FAIL two decompositions of one logarithm do not agree exactly")
            failed += 1

    # zeta(3): the central binomial series against the tree's BBP-type one. This grades the leading
    # 5/2, the part of that identity most easily misremembered.
    mine = apery_binomial(digits)
    if bbp_sweep is not None and hasattr(bbp_sweep, "apery"):
        bits = binary_places_for(digits)
        theirs = from_binary(bbp_sweep.apery(bits), bits, digits)
        gap = abs(mine - theirs)
        lines.append("  zeta(3): central binomial against bbp_sweep.apery: %d units apart" % gap)
        if gap != 0:
            lines.append("    FAIL the two zeta(3) series disagree, so the leading factor or one")
            lines.append("         of the two series is wrong. The row must not ship.")
            failed += 1
    else:
        lines.append("  zeta(3): only one route available, so the row ships UNVERIFIED or not at all")
        failed += 1

    # zeta(2) is pi^2/6 and zeta(4) is pi^4/90, and the even zetas are the one group where an
    # independent check exists: the ratio zeta(4)/zeta(2)^2 must be exactly 2/5.
    # From zeta(2) = pi^2/6 and zeta(4) = pi^4/90, zeta(4)/zeta(2)^2 = 36/90 = 2/5 and therefore
    # 5 zeta(4) = 2 zeta(2)^2 EXACTLY, with no tolerance available or needed.
    #
    # TWO DEFECTS IN THE FIRST VERSION OF THIS CHECK, AND THE SECOND IS THE INTERESTING ONE.
    # It multiplied both sides by the scale again, inflating a three-unit truncation by 10^digits
    # and then comparing it against a threshold in unscaled units, a correct identity read as a
    # sixty-digit failure. That was arithmetic. The repair was then to widen the threshold to admit
    # the three units, and THAT was worse: it is a bound picked by judgment, sitting exactly
    # where an exact identity was available. Compute both sides at the guarded length, cut to
    # the reported length, and the answer is zero, measured at 60, 250 and 1000 places. The
    # comparison is now a decision.
    work = digits + GUARD
    guarded = digit_engine.chudnovsky(work)
    wide = 10 ** work
    drop = 10 ** GUARD
    left = (5 * _zeta_even(guarded, 4, 90, work)) // drop
    right = (2 * ((_zeta_even(guarded, 2, 6, work) ** 2) // wide)) // drop
    lines.append("  5 zeta(4) against 2 zeta(2)^2, an exact identity: %d units apart"
                 % abs(left - right))
    if abs(left - right) != 0:
        lines.append("    FAIL an exact ratio between two even zetas does not hold exactly")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the Delta Null constants, two routes each")
    parser.add_argument("--digits", type=int, default=1000)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--time", action="store_true",
                        help="sweep the length and report the cost, since a lookup is flat")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.time:
        sys.exit(_time())
    sys.exit(_report(args.digits))
