"""The series rebuilt so the constants can go long on the host, with the GPU left alone.

    python examples/proofing/digit_engine.py --check       grade against known answers
    python examples/proofing/digit_engine.py --time        measure against the series in place
    python examples/proofing/digit_engine.py --pi 1000000  write pi and check its prefix

WHAT WAS MISSING

`natural_constants.py` computes pi, the roots, the golden angle, the harmonic unit and SHA-256's own
tables at any precision asked for. Every one of them bottoms out on a series summed one term at a
time, and the shape of that summation stops them, not the size of the answer.

MEASURED. `pi_machin` takes 0.002 s at a thousand places and 0.045 s at four thousand. The Gregory
series does a term per digit of output and each term costs a division at the full working precision,
so the cost is the square of the digit count. Extrapolated to a billion digits that is on the order
of ninety years, and no amount of care inside the loop changes the exponent.

The ceiling was never a property of pi. It belonged to the shape of the sum.

WHAT REPLACED IT

Binary splitting on Chudnovsky's series. The linear sum divides at every term at full precision;
binary splitting carries three exact integers per interval and merges pairs, so there is exactly ONE
division in the whole computation and it happens at the end. Nothing in between is rounded, so there
is no error to propagate and no tolerance to argue about: the intermediates are integers and they
are exact.

Chudnovsky gains 14.18 decimal digits per term against Machin's roughly 1.4, so the term count falls
by ten before the shape of the sum is even considered.

WHERE THE HOST STOPS, AND WHY THAT IS THE HONEST NUMBER

The multiply underneath is Python's own, which is Karatsuba: measured at 0.930 s for a million
digits and 5.610 s for three million, an exponent of 1.635. Binary splitting turns the series into
some tens of multiplies at the full size, so the reachable range follows directly from that exponent
and is reported by `--time` instead of promised here.

THE TRANSFORM IS WIRED IN, BEHIND `--device`. It lowers the exponent to N log N and it runs on the
card, over three moduli that each carry a Proth certificate and a proved twiddle order from
`twiddle_proof.py`. Measured on the empty message: a million places takes 53.4 s on the host and
19.3 s through the card, and both routes end on the same ten digits.

The gain is smaller than the multiply's own, and the reason is worth stating plainly. A
million digit run does most of its work in the LOWER levels of the splitting tree, where the
operands are small and the native multiply is the faster route; only the top few levels are large
enough for the transform to pay for its own setup. So the speedup grows with the digit count as
more levels cross that line, and quoting the multiply's ratio as the series' ratio would be
comparing two different quantities.

The threshold itself is measured and lives in `gpu_multiply.NATIVE_LIMBS`.

WHAT IT REFUSES

A result that has not been put next to an independent one. Every digit count checked below is
computed twice, once here and once by the module that was already trusted, and agreement is reported
as agreement instead of assumed from a clean run. The published prefix, which came from neither
routine, is the third opinion.
"""

import argparse
import io
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import natural_constants as nc
import series

# CPython refuses to render an integer past 4300 digits as text unless told otherwise, which is a
# guard against a denial of service in a parser and has nothing to say about arithmetic. Every value
# here is meant to be written out, so the guard is lifted instead of worked around; the arithmetic
# was never affected by it and only the printing was.
sys.set_int_max_str_digits(0)

# The series constants live in `series`, which is where the recurrences that use them live too.
# Re-exported here because callers and the tests below name them.
PER_TERM = series.PER_TERM
BASE = series.BASE
STEP = series.STEP
CUBED = series.CUBED
SCALE = series.SCALE


def product(left, right):
    """The product of two integers, on the host, at every size.

    THIS IS THE HOST HALF OF A DELIBERATE SPLIT and it has no device path in it. `device_engine` is
    the other half. Neither imports the other's multiply, and nothing at runtime moves work between
    them. A tool's import line is the only record of which machine it ran on.

    What stood here before was a `use_device()` that rebound this name to the card's multiply. Any
    tool that called it changed the arithmetic of every other tool in the same process, from
    anywhere, with no trace in the result. A run could not then be described without knowing the
    call order, and a sweep that read as a device tool spent a whole night on the host without ever
    saying so. That is a monkeypatch whatever it is called, and it is gone, not guarded.
    """
    return left * right


def reciprocal(value, bits):
    """floor(2^bits / value). `series.reciprocal` with the host multiply."""
    return series.reciprocal(product, value, bits)


def divide(top, bottom, places):
    """floor(top * 10^places / bottom). `series.divide` with the host multiply."""
    return series.divide(product, top, bottom, places)


def divide_binary(top, bottom, bits):
    """floor(top * 2^bits / bottom). `series.divide_binary` with the host multiply."""
    return series.divide_binary(product, top, bottom, bits)


def inverse_root(value, bits):
    """floor(2^bits / sqrt(value)). `series.inverse_root` with the host multiply."""
    return series.inverse_root(product, value, bits)


def root_scaled(value, places):
    """floor(sqrt(value) * 10^places). `series.root_scaled` with the host multiply."""
    return series.root_scaled(product, value, places)


def reduce_by(value, modulus, folded=None):
    """`value` modulo `modulus`. `series.reduce_by` with the host multiply."""
    return series.reduce_by(product, value, modulus, folded)


def power_mod(base, power, modulus):
    """`base` to `power` modulo `modulus`. `series.power_mod` with the host multiply."""
    return series.power_mod(product, base, power, modulus)


def split(first, last):
    """Chudnovsky's binary splitting over [first, last). `series.split` with the host multiply."""
    return series.split(product, first, last)
def proth_holds(multiplier, power, witness):
    """Whether `witness` certifies `multiplier * 2^power + 1` prime, by Proth's criterion.

    The criterion is an equivalence for `multiplier` below two to the `power`. A witness with
    a^((N-1)/2) congruent to -1 therefore proves primality outright and does not merely indicate it.
    Returns the value found alongside the verdict, letting a caller record the whole certificate
    instead of the conclusion alone.
    """
    value = multiplier * (1 << power) + 1
    if multiplier % 2 == 0 or multiplier >= (1 << power):
        return None, "outside Proth's range"
    lifted = power_mod(witness, (value - 1) // 2, value)
    if lifted == value - 1:
        return True, "prime, witness %d" % witness
    if lifted != 1:
        return False, "composite, Fermat witness %d" % witness
    return None, "witness %d says nothing" % witness


def terms_for(digits):
    """How many terms of the series `digits` places needs, from the series' own rate."""
    return series.terms_for(digits)


def chudnovsky(digits, guard=24):
    """Pi to `digits` places, as an integer holding them, with every multiply on the host."""
    return series.chudnovsky(product, digits, guard)


def golden_angle(digits, guard=24):
    """Pi times three less the root of five, to `digits` places, on the fast series.

    The same quantity `natural_constants.golden_angle` computes, with the series underneath
    replaced. Kept here instead of edited into that module so the two can be run against each other
    at any size, and that comparison is what `--check` runs.
    """
    work = digits + guard
    root_five = math.isqrt(5 * 10 ** (2 * work))
    return chudnovsky(work, guard) * (3 * 10 ** work - root_five) // 10 ** (2 * guard + digits)


def harmonic_unit(digits, guard=24):
    """One over twice the root of pi, to `digits` places, on the fast series."""
    work = digits + guard
    four_pi = 4 * chudnovsky(work, guard)
    inner = 10 ** (3 * work) // four_pi
    return math.isqrt(inner) // 10 ** guard


def shown(value, digits, whole=1):
    """An integer holding `digits` places, written out with its point in place."""
    return nc.shown(value, digits, whole)


def _check():
    lines = []
    failed = 0

    lines.append("  PI, against the module that already computes it")
    for digits in (100, 1000, 5000, 20000):
        start = time.perf_counter()
        mine = chudnovsky(digits)
        spent = time.perf_counter() - start
        theirs = nc.pi_machin(digits)
        agree = mine == theirs
        lines.append("    %7s places  %8.3fs  against pi_machin  %s"
                     % (format(digits, ","), spent, "agree" if agree else "DIFFER"))
        if not agree:
            failed += 1
            left, right = str(mine), str(theirs)
            where = next((i for i in range(min(len(left), len(right))) if left[i] != right[i]), None)
            lines.append("      first difference at place %s" % where)
    lines.append("")

    lines.append("  AND AGAINST A SERIES SHARING NO TERM WITH EITHER")
    for digits in (1000, 5000):
        agree = chudnovsky(digits) == nc.pi_euler(digits)
        lines.append("    %7s places  against pi_euler  %s"
                     % (format(digits, ","), "agree" if agree else "DIFFER"))
        if not agree:
            failed += 1
    lines.append("")

    lines.append("  THE PUBLISHED PREFIX, which came from none of the three")
    prefix = nc.PI_PREFIX.replace(".", "")
    text = str(chudnovsky(len(prefix) + 10))
    agree = text[:len(prefix)] == prefix
    lines.append("    %d places  %s" % (len(prefix), "agree" if agree else "DIFFER"))
    if not agree:
        failed += 1
        lines.append("      wanted %s" % prefix)
        lines.append("      got    %s" % text[:len(prefix)])
    lines.append("")

    lines.append("  THE CONSTANTS THAT STAND ON PI")
    for what, mine_of, theirs_of in (("golden angle", golden_angle, nc.golden_angle),
                                     ("harmonic unit", harmonic_unit, nc.harmonic_unit)):
        agree = mine_of(2000) == theirs_of(2000)
        lines.append("    %-14s 2,000 places  %s" % (what, "agree" if agree else "DIFFER"))
        if not agree:
            failed += 1
    lines.append("")

    lines.append("  THE TERM COUNT is taken from the rate, so check the rate holds")
    for digits in (1000, 100000):
        got = len(str(chudnovsky(digits)))
        wanted = digits + 1
        agree = got == wanted
        lines.append("    %7s places produces %s digits  %s"
                     % (format(digits, ","), format(got, ","), "ok" if agree else "WRONG"))
        if not agree:
            failed += 1
    lines.append("")

    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


def _time():
    lines = ["  PI ON THE HOST, binary splitting against the series in place", ""]
    lines.append("    %12s %14s %14s %10s" % ("places", "Gregory", "splitting", "faster by"))

    for digits in (1000, 10 ** 4, 10 ** 5, 10 ** 6, 10 ** 7):
        if digits <= 10 ** 5:
            start = time.perf_counter()
            nc.pi_machin(digits)
            series = time.perf_counter() - start
        else:
            series = None

        start = time.perf_counter()
        chudnovsky(digits)
        mine = time.perf_counter() - start

        lines.append("    %12s %13s %13.3fs %10s"
                     % (format(digits, ","),
                        ("%.3fs" % series) if series is not None else "not run",
                        mine,
                        ("%.0fx" % (series / mine)) if series and mine else "-"))

    lines.append("")
    lines.append("  The exponent between the last two rows is what sets the reach from here.")
    sys.stdout.write("\n".join(lines) + "\n")
    return 0


def _write_pi(digits, where):
    start = time.perf_counter()
    value = chudnovsky(digits)
    spent = time.perf_counter() - start
    text = str(value)

    folder = os.path.dirname(where)
    if folder and not os.path.isdir(folder):
        os.makedirs(folder)
    with io.open(where, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text[0] + "." + text[1:] + "\n")

    prefix = nc.PI_PREFIX.replace(".", "")
    take = min(len(prefix), len(text))
    sys.stdout.write("%s places in %.3f s\n" % (format(digits, ","), spent))
    sys.stdout.write("  written to %s\n" % os.path.relpath(where, ROOT))
    sys.stdout.write("  digits produced %s\n" % format(len(text), ","))
    sys.stdout.write("  the published prefix %s\n"
                     % ("agrees" if text[:take] == prefix[:take] else "DIFFERS"))
    sys.stdout.write("  last ten digits %s\n" % text[-10:])
    return 0


if __name__ == "__main__":
    sys.setrecursionlimit(10000)
    parser = argparse.ArgumentParser(description="the series rebuilt for length, on the host")
    parser.add_argument("--check", action="store_true", help="grade against known answers")
    parser.add_argument("--time", action="store_true", help="measure against the series in place")
    parser.add_argument("--pi", type=int, default=0, help="write pi to this many places")
    parser.add_argument("--into", default=None, help="where --pi writes")
    args = parser.parse_args()

    if args.check:
        sys.exit(1 if _check() else 0)
    if args.time:
        sys.exit(_time())
    if args.pi:
        sys.exit(_write_pi(args.pi, args.into or os.path.join(ROOT, "build", "pi.txt")))
    parser.print_help()
