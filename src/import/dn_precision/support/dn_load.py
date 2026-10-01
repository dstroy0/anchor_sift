"""Hands out the project's own constants, so nothing reaches for the standard library's.

    from dn_load import at, decimal_of, double
    at("golden_angle", 200)      an integer holding 200 decimal places
    decimal_of("pi", 80)         a Decimal at 80 places, context set to match
    double("golden_angle")       the correctly rounded double of OUR value

    python tools/dn_precision/support/dn_load.py --check
    python tools/dn_precision/support/dn_load.py --against-stdlib

WHY THIS EXISTS, AND WHERE IT ACTUALLY BUYS SOMETHING

The rule is that this project uses its own constants. The rule is right, and the reason is narrower
than it first looks, so it is worth stating precisely instead of asserting a blanket win.

**Above double precision it is not a preference, it is required.** `math.pi` is a double. Any
computation carrying more than about sixteen digits and reaching for it has silently capped itself
at sixteen, and the run will look fine. `precision_floor.py` already computes pi itself for exactly
this reason, and everything in `calc/` does the same.

**At double precision a single named constant gains nothing.** `math.pi` is the correctly rounded
double of pi. Loading our thousand-digit pi and rounding it to a double returns the identical bits,
and claiming an improvement there would be false.

**At double precision exactly ONE of the fourteen library forms differs, and it is one ulp.**
Measured by `--against-stdlib`, not estimated. Thirteen give identical bits, including every root,
every multiple of pi, and the golden ratio. The one that differs is the placement's own step:

    GOLDEN = math.pi * (3.0 - math.sqrt(5.0))        4.441e-16 away, 1.0 ulp

It rounds three times, at sqrt(5), at the subtraction and at the product, and lands on the
neighbouring representable number. `double("golden_angle")` rounds once and lands on the right one.

**An earlier version of this paragraph said two bits and that was an overclaim.** It is one unit in
the last place. The honest case for the rule is therefore: required above sixteen digits, free and
bit-identical for thirteen of fourteen constants at sixteen, and worth one ulp on the golden angle,
which happens to be the constant every source in the placement is positioned by.

Composition is what costs, and most compositions in this table turn out not to. That is a
measurement and it could have gone the other way, so it is printed rather than asserted.

WHERE THE NUMBERS COME FROM

`calc/dn_constants.py` writes `dn_const/dn_constants.csv`, every row agreed by two independent
routes. This reads that file and nothing else. If the CSV is absent this raises and says so, because
falling back to `math` would defeat the only thing the module is for.
"""

import argparse
import csv
import io
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY = os.path.dirname(HERE)
TABLE = os.path.join(FAMILY, "dn_const", "dn_constants.csv")

_HELD = None


def load(where=None):
    """The table, as {name: (digits, integer_at_that_scale)}. Read once and kept."""
    global _HELD
    if _HELD is not None and where is None:
        return _HELD

    path = where or TABLE
    if not os.path.exists(path):
        raise RuntimeError(
            "no constant table at %s. Run tools/dn_precision/calc/dn_constants.py --digits N "
            "first. This module will not fall back to the standard library, because avoiding that "
            "is the only thing it is for." % path)

    out = {}
    with io.open(path, encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            digits = int(row["digits"])
            text = row["value"]
            negative = text.startswith("-")
            whole, _, rest = text.lstrip("-").partition(".")
            rest = (rest + "0" * digits)[:digits]
            value = int(whole + rest)
            out[row["name"]] = (digits, -value if negative else value)

    if where is None:
        _HELD = out
    return out


def available():
    """Every name the table carries."""
    return sorted(load().keys())


def at(name, digits):
    """`name` as an integer holding `digits` decimal places.

    Refuses to lengthen. A request past what the table holds would be answered with trailing zeros,
    which reads as precision the table does not have, so it raises instead.
    """
    table = load()
    if name not in table:
        raise KeyError("%s is not in the table. Have: %s" % (name, ", ".join(available())))
    held, value = table[name]
    if digits > held:
        raise ValueError(
            "%s is held to %d places and %d were asked for. Regenerate the table longer rather "
            "than padding, since padding invents digits." % (name, held, digits))
    return value // 10 ** (held - digits)


def decimal_of(name, digits):
    """`name` as a Decimal at `digits` places, with the context widened to hold it."""
    import decimal
    if decimal.getcontext().prec < digits + 2:
        decimal.getcontext().prec = digits + 2
    return decimal.Decimal(at(name, digits)).scaleb(-digits)


# Enough places that the rounding to a double is decided by the digits and never by the table's end.
DOUBLE_PLACES = 40


def text_of(name, places=DOUBLE_PLACES):
    """`name` as a decimal string at `places` places."""
    held, value = load()[name]
    places = min(places, held)
    shortened = value // 10 ** (held - places)
    negative = shortened < 0
    digits = str(abs(shortened)).rjust(places + 1, "0")
    out = digits[:-places] + "." + digits[-places:]
    return ("-" + out) if negative else out


def double(name):
    """The correctly rounded double of our own value for `name`.

    THE CONVERSION GOES THROUGH THE DECIMAL STRING, AND THE FIRST VERSION DID NOT.
    It computed `float(at(name, 40)) / float(10 ** 40)`, which rounds three times: the numerator to
    a double, `10 ** 40` to a double, and then the quotient. `float(10 ** 40)` is not exactly ten to
    the fortieth, so the result was not the correctly rounded double of our value and could land on
    a neighbouring representable number.

    It was caught by this module disagreeing with `natural_constants.py`, which had measured the
    composed golden angle at 4.441e-16 from the true value while `--against-stdlib` reported
    identical bits. Two measurements of one quantity, both ours, and they could not both be right.

    `float()` on a decimal string is correctly rounded by the language, so one rounding and no
    arithmetic.
    """
    return float(text_of(name))


def _against_stdlib():
    """Prints where our constants differ from the standard library's, and by how much."""
    pairs = [
        ("pi", math.pi, "math.pi"),
        ("e", math.e, "math.e"),
        ("root_two", math.sqrt(2.0), "math.sqrt(2)"),
        ("root_three", math.sqrt(3.0), "math.sqrt(3)"),
        ("root_five", math.sqrt(5.0), "math.sqrt(5)"),
        ("ln_two", math.log(2.0), "math.log(2)"),
        ("ln_ten", math.log(10.0), "math.log(10)"),
        ("two_pi", 2.0 * math.pi, "2 * math.pi"),
        ("four_pi", 4.0 * math.pi, "4 * math.pi"),
        ("half_pi", math.pi / 2.0, "math.pi / 2"),
        ("golden_ratio", (1.0 + math.sqrt(5.0)) / 2.0, "(1 + math.sqrt(5)) / 2"),
        ("golden_angle", math.pi * (3.0 - math.sqrt(5.0)), "math.pi * (3 - math.sqrt(5))"),
        ("harmonic_unit", math.sqrt(1.0 / (4.0 * math.pi)), "sqrt(1 / (4 * math.pi))"),
        ("log2_ten", math.log2(10.0), "math.log2(10)"),
    ]

    have = load()
    lines = []
    lines.append("  ours against the standard library, both as doubles")
    lines.append("")
    lines.append("  %-14s %-30s %12s  %s" % ("name", "library form", "gap", "verdict"))

    composed = 0
    identical = 0
    for name, theirs, how in pairs:
        if name not in have:
            lines.append("  %-14s %-30s %12s  not in the table" % (name, how, "-"))
            continue
        mine = double(name)
        gap = abs(mine - theirs)
        if gap == 0.0:
            verdict = "identical bits"
            identical += 1
        else:
            # One unit in the last place at this magnitude, for scale.
            step = math.ulp(mine) if hasattr(math, "ulp") else 2.0 ** -52 * max(abs(mine), 1.0)
            verdict = "%.1f ulp, composed" % (gap / step)
            composed += 1
        lines.append("  %-14s %-30s %12.3e  %s" % (name, how, gap, verdict))

    lines.append("")
    lines.append("  %d identical, %d different" % (identical, composed))
    lines.append("  A named constant the library rounds correctly gives identical bits, and claiming")
    lines.append("  a gain there would be false. The differences are the composed ones, where the")
    lines.append("  library form rounds two or three times and ours rounds once.")
    sys.stdout.write("\n".join(lines) + "\n")
    return 0


def _check():
    lines = []
    failed = 0

    try:
        table = load()
    except RuntimeError as why:
        sys.stdout.write("  %s\n\n1 check(s) failed\n" % why)
        return 1

    lines.append("  table holds %d constants: %s" % (len(table), ", ".join(available())))

    # A named constant the library rounds correctly must come back bit identical, or our table is
    # wrong rather than merely different.
    for name, theirs in (("pi", math.pi), ("e", math.e), ("root_two", math.sqrt(2.0))):
        if name not in table:
            continue
        mine = double(name)
        same = mine == theirs
        lines.append("  %-10s as a double against the library: %s"
                     % (name, "identical" if same else "DIFFERS by %.3e" % abs(mine - theirs)))
        if not same:
            lines.append("    FAIL a correctly rounded library constant should match ours exactly")
            failed += 1

    # Shortening must divide and never pad. A silent pad would hand out digits the table lacks.
    if "pi" in table:
        held, _ = table["pi"]
        short = at("pi", 10)
        lines.append("  pi shortened to 10 places: %d" % short)
        if short != 31415926535:
            lines.append("    FAIL shortening did not truncate correctly")
            failed += 1
        try:
            at("pi", held + 1)
            lines.append("    FAIL a request past the table's length was answered")
            failed += 1
        except ValueError:
            lines.append("  a request past the table's length raises instead of padding")

    # An absent name must raise, not return zero. A zero constant draws a picture.
    try:
        at("not_a_constant", 10)
        lines.append("    FAIL an unknown name was answered")
        failed += 1
    except KeyError:
        lines.append("  an unknown name raises instead of returning zero")

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the project's own constants, at any length")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--against-stdlib", action="store_true")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.against_stdlib:
        sys.exit(_against_stdlib())
    sys.stdout.write(__doc__)
    sys.exit(2)
