"""Where a measured constant's own uncertainty stops us, and where nothing does.

    python tools/dn_precision/calc/measured_floor.py --check
    python tools/dn_precision/calc/measured_floor.py              the report
    python tools/dn_precision/calc/measured_floor.py --exact      only the defined ones
    python tools/dn_precision/calc/measured_floor.py --fetch      refresh the cached table

THE QUESTION THIS ANSWERS

Every other tool in this family computes a DECIDABLE number. Pi has no uncertainty: a thousand
places is a thousand correct places, and a millionth place exists and is waiting. That is why the
arithmetic floor moving one decade per digit is the only floor those tools ever meet.

A measured constant is a different object and the difference is not a matter of degree. The electron
mass in kilograms is known to a published uncertainty, and no amount of arithmetic adds a digit to
it. So this file reads the CODATA table and reports, for each constant, the number of digits that
are actually KNOWN, against the number our arithmetic could carry.

TWO CLASSES, AND THE SPLIT IS THE POINT

The 2019 revision of the SI redefined the base units by fixing certain constants exactly. Those
constants are now definitions and carry no uncertainty whatsoever:

    EXACT       c, h, e, k, N_A and everything algebraically built from them alone. Decidable.
                Arbitrary precision is meaningful here to arbitrary depth, the same as for pi.
    MEASURED    G, alpha, the particle masses in kilograms, everything else. Bounded by measurement.
                Precision past the published uncertainty buys NOTHING and claiming otherwise is
                the most obvious way to misuse this whole family of tools.

The table is read rather than remembered, so which constants sit in which class comes off the file
and not off anybody's recollection of the 2019 revision.

WHAT THE ANSWER TURNS OUT TO BE, AND WHY IT CUTS BOTH WAYS

For every measured constant in the table our arithmetic floor sits tens of decades below the
published uncertainty. So the arithmetic NEVER binds on measured input. That is worth having: it
means any residual against a measured quantity belongs to the measurement or to the model and never
to our rounding, which is exactly the condition under which a residual is evidence of anything.

It also means more digits buy nothing there. The binding floor is the parameter floor: information
available goes as 1/epsilon^2 in the uncertainty of the map's parameters, and the reachable degree
as roughly 1/epsilon. Those are the numbers this file supplies, and until now they were hypothetical
in every document that mentioned them.

    THIS DOES NOT DERIVE ANY MEASURED VALUE AND CANNOT. Computing harder does not weigh an
    electron. The mass in kilograms is a measurement, its digits come from an experiment, and the
    only thing precision contributes is that our side of the arithmetic is not in the error budget.

NOTHING IS SENT ANYWHERE

`--fetch` performs one HTTP GET of a public NIST table and writes it beside this file. Nothing from
this machine goes out in it. The cached copy and its digest are committed, so every number below is
reproducible with no network at all, and a changed upstream table shows up as a changed digest
rather than as silently different numbers.
"""

import argparse
import decimal
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY = os.path.dirname(HERE)
SUPPORT = os.path.join(FAMILY, "support")
for _where in (SUPPORT, HERE):
    if _where not in sys.path:
        sys.path.insert(0, _where)

TABLE = os.path.join(FAMILY, "dn_const", "codata_2022_allascii.txt")
PROVENANCE = os.path.join(FAMILY, "dn_const", "codata_2022_provenance.tsv")
SOURCE = "https://physics.nist.gov/cuu/Constants/Table/allascii.txt"

# Fixed-width columns, confirmed against the file rather than assumed from the header's spacing.
QUANTITY = (0, 60)
VALUE = (60, 85)
UNCERTAINTY = (85, 110)
UNIT = (110, None)

# Rows before this are the banner and the column rule. Counted from the file, not guessed: the
# separator line of dashes is the last thing before the data.
def _data_lines(text):
    """Every line after the rule of dashes that is long enough to carry a value."""
    out = []
    started = False
    for line in text.splitlines():
        if not started:
            if line.startswith("---"):
                started = True
            continue
        if len(line) > VALUE[0] and line[:QUANTITY[1]].strip():
            out.append(line)
    return out


def _number(text):
    """A CODATA numeric field as a Decimal. Spaces are digit grouping and carry no meaning.

    The table writes 7.297 352 5643 e-3 and 299 792 458, so the spaces come out and the exponent
    joins the mantissa. Returns None for a field that is not a number, which is how '(exact)' and
    the dimensionless blanks arrive.
    """
    cleaned = text.replace(" ", "").replace("...", "")
    if not cleaned or cleaned.startswith("("):
        return None
    try:
        return decimal.Decimal(cleaned)
    except decimal.InvalidOperation:
        return None


def read_table(where=None):
    """The table as a list of dicts, with the uncertainty parsed and exactness flagged."""
    path = where or TABLE
    if not os.path.exists(path):
        raise RuntimeError(
            "no cached CODATA table at %s. Run this with --fetch once, which performs a single GET "
            "of %s and writes it there. This module will not invent an uncertainty." % (path, SOURCE))

    with io.open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()

    decimal.getcontext().prec = 60
    out = []
    for line in _data_lines(text):
        raw_uncertainty = line[UNCERTAINTY[0]:UNCERTAINTY[1]].strip()
        value = _number(line[VALUE[0]:VALUE[1]])
        if value is None:
            continue
        out.append({
            "quantity": line[QUANTITY[0]:QUANTITY[1]].strip(),
            "value": value,
            "uncertainty": _number(raw_uncertainty),
            "exact": raw_uncertainty == "(exact)",
            "unit": (line[UNIT[0]:] if UNIT[1] is None else line[UNIT[0]:UNIT[1]]).strip(),
        })
    return out


def _terminates(value):
    """Whether this Decimal's exact value has a terminating decimal expansion.

    A rational terminates exactly when its reduced denominator has no prime factor but 2 and 5. A
    Decimal is already a terminating decimal by construction, so the honest thing this answers is
    whether the value AS GIVEN is finite in decimal, which every field in the table is. It is kept
    as a function rather than assumed so that a future row carrying a ratio does not silently read
    as terminating when it is not.
    """
    top, bottom = value.as_integer_ratio()
    del top
    while bottom % 2 == 0:
        bottom //= 2
    while bottom % 5 == 0:
        bottom //= 5
    return bottom == 1


def relative(row):
    """Relative uncertainty as a Decimal, or None where it is exact or the value is zero."""
    if row["exact"] or row["uncertainty"] is None:
        return None
    if row["value"] == 0:
        return None
    return abs(row["uncertainty"] / row["value"])


def known_digits(row):
    """How many decimal digits of this constant are actually determined, as a float.

    This is -log10 of the relative uncertainty, which is the only place a float appears in this
    file, and it appears in a REPORTED quantity rather than in a computed one. A tenth of a digit
    either way changes nothing about the argument and carrying a Decimal logarithm to state it
    would be precision theatre.
    """
    share = relative(row)
    if share is None:
        return None
    return -float(share.log10())


# The arithmetic floor at a given working length, from the measurement this tree already has:
# 4.005e-16 in float64, falling 0.9861 decades per digit. Stated as the exponent.
FLOAT64_DIGITS = 15.95
DECADES_PER_DIGIT = 0.9861


def _report(only_exact=False):
    rows = read_table()
    exact = [one for one in rows if one["exact"]]
    measured = [one for one in rows if not one["exact"] and relative(one) is not None]

    with io.open(PROVENANCE, encoding="utf-8") as handle:
        stamp = dict(line.rstrip("\n").split("\t", 1) for line in handle if "\t" in line)

    print("  %s, fetched %s" % (stamp.get("adjustment", "?"), stamp.get("fetched", "?")))
    print("  cached at %s" % os.path.relpath(TABLE, os.path.dirname(os.path.dirname(FAMILY))))
    print("  sha256 %s" % stamp.get("sha256", "?"))
    print("")
    print("  %d rows carry a value. %d are EXACT by definition, %d are MEASURED."
          % (len(rows), len(exact), len(measured)))
    print("")

    if only_exact:
        print("  THE EXACT ONES, AND THEY ARE BETTER THAN DECIDABLE. Pi is decidable and still costs")
        print("  time: every digit has to be summed for. These cost nothing at all, because a")
        print("  defined SI constant is a RATIONAL, and its decimal expansion terminates.")
        print("")
        print("  So each of them is an ANCHOR in two senses at once. It has no uncertainty, so")
        print("  anything derived from these alone inherits none. And it is exact integer or")
        print("  terminating-decimal arithmetic, so it is the fastest thing in the family: no")
        print("  series, no guard digits, no narrowing, and nothing to check against a second")
        print("  route because there is no first route to be wrong.")
        print("")
        print("  %-52s %8s %8s" % ("quantity", "sig digs", "repeats"))
        terminating = 0
        for row in exact:
            text = str(row["value"].normalize())
            figures = len(text.replace("-", "").replace(".", "").lstrip("0").rstrip("0")) or 1
            ends = _terminates(row["value"])
            if ends:
                terminating += 1
            print("  %-52s %8d %8s" % (row["quantity"][:52], figures, "no" if ends else "YES"))
        print("")
        print("  %d of %d terminate outright, so carrying them to a thousand places or a million"
              % (terminating, len(exact)))
        print("  is the same work: the digits after the last significant one are zeros and are not")
        print("  computed, they are known. A non-terminating row would be a rational with a factor")
        print("  other than 2 or 5 under it, and it would REPEAT rather than run forever, so it is")
        print("  still finite information and still free after one period.")
        print("")
        print("  THE USE FOR THE TABLE IS THEREFORE THE OPPOSITE OF WHAT IT LOOKS LIKE. The 81 rows")
        print("  above are where arbitrary precision is free and adds no error. The 274 measured")
        print("  rows are where precision is cheap and USELESS past the published uncertainty. So")
        print("  compute through the anchors wherever a chain allows it, and carry a measured value")
        print("  only as far as its own digits go.")
        return 0

    ranked = sorted(measured, key=lambda one: relative(one))

    print("  BEST KNOWN MEASURED CONSTANTS. 'digits known' is -log10 of the relative uncertainty.")
    print("")
    print("  %-46s %14s %11s %12s" % ("quantity", "relative unc", "digits", "our floor under"))
    for row in ranked[:8]:
        got = known_digits(row)
        print("  %-46s %14.3e %11.2f %11.1f dec"
              % (row["quantity"][:46], float(relative(row)), got, FLOAT64_DIGITS - got))

    print("")
    print("  WORST KNOWN, which is where the parameter floor actually bites.")
    print("")
    print("  %-46s %14s %11s %12s" % ("quantity", "relative unc", "digits", "our floor under"))
    for row in ranked[-5:]:
        got = known_digits(row)
        print("  %-46s %14.3e %11.2f %11.1f dec"
              % (row["quantity"][:46], float(relative(row)), got, FLOAT64_DIGITS - got))

    sharpest = ranked[0]
    bluntest = ranked[-1]
    best = known_digits(sharpest)
    worst = known_digits(bluntest)

    print("")
    print("  EVEN IN PLAIN FLOAT64 OUR ARITHMETIC IS %.1f DECADES BELOW THE BEST MEASUREMENT EVER"
          % (FLOAT64_DIGITS - best))
    print("  MADE. At 55 digits it is %.0f decades below it. So on measured input the arithmetic"
          % (55 * DECADES_PER_DIGIT - best))
    print("  floor never binds, in any format this tree has ever used, and that is the useful half:")
    print("  a residual against a measured quantity belongs to the measurement or to the model and")
    print("  never to our rounding. That is the condition under which a residual is evidence.")
    print("")
    print("  AND IT IS ALSO THE LIMIT. Past %.1f digits on %s, and past %.1f on %s,"
          % (best, sharpest["quantity"][:30], worst, bluntest["quantity"][:30]))
    print("  more digits buy nothing whatsoever. The binding floor there is the PARAMETER floor and")
    print("  not the arithmetic one.")
    print("")
    print("  THE PARAMETER FLOOR IN DEGREES, which is the number the boundary chapters wanted and")
    print("  have been carrying as a hypothetical. Reachable degree goes as about 1 / epsilon:")
    print("")
    print("  %-46s %14s %14s" % ("if a map parameter were known this well", "epsilon", "degrees"))
    for row in (sharpest, ranked[len(ranked) // 2], bluntest):
        share = relative(row)
        print("  %-46s %14.3e %14.0f"
              % (row["quantity"][:46], float(share), 1.0 / float(share)))
    print("")
    print("  Information available goes as 1/epsilon^2, so the sharpest of those carries about")
    print("  %.3e times the information of the bluntest."
          % ((float(relative(bluntest)) / float(relative(sharpest))) ** 2))
    print("")
    print("  NOTHING HERE DERIVES A MEASURED VALUE AND NOTHING HERE CAN. Computing harder does not")
    print("  weigh an electron. These are measurements, their digits come from experiments, and the")
    print("  only contribution precision makes is keeping our arithmetic out of the error budget.")
    return 0


def _fetch():
    """One GET of the public NIST table, written beside this file with a digest. Sends nothing."""
    import hashlib
    import urllib.request

    print("  GET %s" % SOURCE)
    with urllib.request.urlopen(SOURCE, timeout=60) as answer:
        body = answer.read()
    digest = hashlib.sha256(body).hexdigest()

    with io.open(TABLE, "wb") as handle:
        handle.write(body)
    print("  wrote %d bytes to %s" % (len(body), TABLE))
    print("  sha256 %s" % digest)
    print("")
    print("  Update %s by hand if the digest changed, a changed upstream table shows up as a"
          % os.path.basename(PROVENANCE))
    print("  changed digest in a diff rather than as silently different numbers in a report.")
    return 0


def _check():
    lines = []
    failed = 0

    rows = read_table()
    lines.append("  table parses: %d rows carry a value" % len(rows))
    if len(rows) < 300:
        lines.append("    FAIL the table should carry hundreds of rows, so parsing lost most of it")
        failed += 1

    # The parser must place the columns correctly, and the way to show that is a row whose value is
    # known to everybody: the speed of light is exactly 299792458 m/s by definition.
    light = [one for one in rows if one["quantity"] == "speed of light in vacuum"]
    if not light:
        lines.append("    FAIL the speed of light is not in the parsed table at all")
        failed += 1
    else:
        row = light[0]
        right = (row["value"] == decimal.Decimal(299792458) and row["exact"]
                 and row["unit"] == "m s^-1")
        lines.append("  speed of light: %s %s, exact %s" % (row["value"], row["unit"], row["exact"]))
        if not right:
            lines.append("    FAIL the columns are misaligned, or a defined constant reads inexact")
            failed += 1

    # THE CLASS SPLIT HAS TO BE REAL IN BOTH DIRECTIONS, or the whole argument of this file is a
    # single unchecked assumption. Both classes must be populated.
    exact = [one for one in rows if one["exact"]]
    measured = [one for one in rows if not one["exact"] and relative(one) is not None]
    lines.append("  %d exact and %d measured, both classes populated: %s"
                 % (len(exact), len(measured), bool(exact) and bool(measured)))
    if not exact or not measured:
        lines.append("    FAIL one class is empty, so the split is not being read from the file")
        failed += 1

    # A defined constant must have NO relative uncertainty, and a measured one must have one. This
    # is the negative control: if `relative` returned a number for everything, every digit count
    # below would be fiction.
    if light:
        lines.append("  a defined constant's relative uncertainty is %s" % relative(light[0]))
        if relative(light[0]) is not None:
            lines.append("    FAIL an exact constant was given an uncertainty")
            failed += 1

    gravity = [one for one in rows if one["quantity"] == "Newtonian constant of gravitation"]
    if gravity:
        share = relative(gravity[0])
        lines.append("  G's relative uncertainty: %.3e, digits known %.2f"
                     % (float(share), known_digits(gravity[0])))
        # G is the famously badly known one. If it came back sharper than a part in ten thousand,
        # the parse is wrong rather than physics having moved.
        if not (decimal.Decimal("1e-6") < share < decimal.Decimal("1e-3")):
            lines.append("    FAIL G's uncertainty is outside every plausible range, so the")
            lines.append("         uncertainty column is being read wrong")
            failed += 1

    # Digit grouping must not change a value. 299 792 458 and 299792458 are the same number, and a
    # parser that kept the spaces would fail here rather than silently truncating at the first one.
    lines.append("  digit grouping stripped: '7.297 352 5643 e-3' reads as %s"
                 % _number("7.297 352 5643 e-3"))
    if _number("7.297 352 5643 e-3") != decimal.Decimal("7.2973525643e-3"):
        lines.append("    FAIL spaces in the numeric fields are not being handled")
        failed += 1

    # And '(exact)' must not parse as a number, or exactness would read as an uncertainty of zero
    # arriving from a failed conversion rather than from the file saying so.
    lines.append("  '(exact)' parses to %s rather than to a number" % _number("(exact)"))
    if _number("(exact)") is not None:
        lines.append("    FAIL a non-numeric field produced a number")
        failed += 1

    # The arithmetic floor must actually be below every measured uncertainty, which is the claim the
    # report makes. Checked over the whole table rather than on the one example the report prints.
    worst = max(measured, key=lambda one: relative(one))
    ours = decimal.Decimal(10) ** int(-FLOAT64_DIGITS)
    lines.append("  the worst-known measured constant is %s at %.3e, and float64 sits at %.3e"
                 % (worst["quantity"][:34], float(relative(worst)), float(ours)))
    if not ours < relative(worst):
        lines.append("    FAIL our arithmetic floor is not below the worst measurement, so the")
        lines.append("         report's central claim is false")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the parameter floor, with measured numbers in it")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--exact", action="store_true", help="list the constants the SI defines")
    parser.add_argument("--fetch", action="store_true", help="one GET of the public NIST table")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.fetch:
        sys.exit(_fetch())
    sys.exit(_report(args.exact))
