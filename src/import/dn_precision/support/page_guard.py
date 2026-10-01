"""Alarms when a computation returns fewer verified places than were asked for.

    python tools/dn_precision/support/page_guard.py --check

    from page_guard import agreed_places, require, survey
    agreed_places(route_one, route_two, 1000)    how many of 1000 places two routes agree to
    require("pi", route_one, route_two, 1000)    raises unless all 1000 agree
    survey(rows, 1000)                           the rows that narrowed, as (name, places)

THIS IS NOT AN OVERFLOW GUARD AND THE DISTINCTION IS THE WHOLE REASON IT EXISTS

Nothing in this family can overflow. The arithmetic is done in Python integers, which are unbounded,
and that is precisely why it is done in them. The failure worth a guard is the opposite one:

    overflow    the value gets too large, and something raises or wraps        LOUD
    narrowing   the value keeps its width and loses its meaning in the tail    SILENT

A request for a thousand places that comes back agreeing to nine hundred still prints a thousand
digits. The leading nine hundred are right. Nothing about the output looks wrong, no exception is
raised, and a caller has no way to tell which nine hundred to trust. There is no signal at all
unless someone counts.

AND IT COMPOUNDS, WHICH IS WHAT MAKES IT WORTH STOPPING RATHER THAN NOTING

A narrowed constant is then used to compute the next one. Each composition truncates again, so the
loss grows down a chain nobody is watching, and the place it finally shows up is nowhere near the
place it started. That is why this raises instead of warning. A warning that is printed and
survived teaches a reader to expect slack, and the slack is real lost digits.

    THE FIRST ROW THIS CAUGHT WAS ALREADY SHIPPING AS A FOOTNOTE. `dn_constants.py` reported
    golden_angle at 999 of 1000 places and printed a line saying a few units in the last place were
    the guard truncating. That was true and it was the wrong response: the row was a real narrowing
    and one extra Machin run at the guarded width removed it outright. The footnote had been there
    for as long as the table had.

WHAT IT MEASURES IS AGREEMENT AND NOT CORRECTNESS

Two routes agreeing to N places means N places are VERIFIED, not that they are right. Two
transcriptions of one wrong formula agree perfectly. So this is the second of two gates and never
the only one: the routes have to be independent for the count to mean anything, and judging
independence is a reading of the mathematics that no tool performs.

NO TOLERANCE IS ACCEPTED ANYWHERE IN THIS FILE

There is no slack parameter and there is not going to be one. A threshold picked by judgment sits in
front of every row and admits exactly the one that drifted, which is the failure the guard is for.
Either the places agree or the count of agreeing places is the finding.
"""

import argparse
import sys


def agreed_places(first, second, digits):
    """How many of `digits` decimal places two scaled integers agree to.

    Both arguments hold `digits` places. The gap is an integer at that same scale, so the number of
    places that agree is `digits` less the number of digits in the gap, and an exact match agrees to
    all of them. Counting the gap's digits rather than dividing avoids introducing a float into a
    routine whose entire purpose is to protect precision.
    """
    gap = abs(first - second)
    if gap == 0:
        return digits
    lost = len(str(gap))
    return max(0, digits - lost)


def require(name, first, second, digits):
    """Returns `first` when both routes agree to all `digits` places, and raises otherwise.

    Raising rather than returning a shortened value is deliberate. A caller that asked for a
    thousand places has already decided it needs them, and handing back nine hundred in a container
    shaped for a thousand is the silent case this module exists to prevent.
    """
    got = agreed_places(first, second, digits)
    if got < digits:
        raise NarrowingAlarm(
            "%s agrees to %d of the %d places requested, so %d places would be carried unverified. "
            "Widen the working length and recompute. Do not narrow the request: the request is what "
            "the caller will rely on." % (name, got, digits, digits - got))
    return first


class NarrowingAlarm(RuntimeError):
    """Raised when fewer places are verified than were asked for. Named a caller can catch this
    and nothing else, since catching RuntimeError broadly would swallow it."""


def survey(rows, digits, places_key="agreed_digits", name_key="name"):
    """Every row carrying fewer verified places than `digits`, as (name, places) pairs.

    Takes the rows a table is about to be written from, so the check happens at the boundary where
    numbers become a file that other tools will read as authoritative.
    """
    return [(row[name_key], row[places_key]) for row in rows
            if row[places_key] < digits]


def refuse_if_narrowed(rows, digits, what="table"):
    """Raises NarrowingAlarm naming every short row, or returns the count checked."""
    short = survey(rows, digits)
    if short:
        raise NarrowingAlarm(
            "NARROWING ALARM: %d of %d rows in this %s agree to fewer than the %d places "
            "requested. Raise the working length and recompute rather than shipping them. "
            "Narrowed: %s"
            % (len(short), len(rows), what, digits,
               ", ".join("%s at %d" % (name, got) for name, got in short)))
    return len(rows)


def _check():
    lines = []
    failed = 0
    digits = 40

    # An exact match agrees to every place. This is the case that must not alarm, and it is the one
    # that decides whether the guard is usable at all: a guard that fires on correct input gets
    # switched off, and then it is protecting nothing.
    same = 12345678901234567890123456789012345678
    got = agreed_places(same, same, digits)
    lines.append("  two identical routes agree to %d of %d places" % (got, digits))
    if got != digits:
        lines.append("    FAIL an exact match must agree to every place")
        failed += 1

    # THE POSITIVE CONTROL. A route short by one unit in the last place has lost one place, and the
    # guard has to see it. Without this the guard could return `digits` unconditionally and every
    # check above would still pass.
    got = agreed_places(same, same + 1, digits)
    lines.append("  a route off by one unit in the last place: %d of %d places" % (got, digits))
    if got != digits - 1:
        lines.append("    FAIL one unit of disagreement should cost exactly one place")
        failed += 1

    # And the loss has to scale with the size of the gap, or the count is not measuring the gap.
    for lost in (1, 5, 17):
        got = agreed_places(same, same + 10 ** (lost - 1), digits)
        ok = got == digits - lost
        lines.append("  a gap of 10^%d costs %d places, expected %d: %s"
                     % (lost - 1, digits - got, lost, "yes" if ok else "NO"))
        if not ok:
            failed += 1

    # `require` must pass the agreeing case through unchanged, since a guard that alters the value
    # it guards is a second source of error rather than a check on the first.
    passed = require("agreeing", same, same, digits)
    lines.append("  require returns the value unchanged when it agrees: %s" % (passed == same))
    if passed != same:
        lines.append("    FAIL the guard modified the value it was guarding")
        failed += 1

    # And it must raise on the narrowed case, by the named type and not a bare RuntimeError.
    try:
        require("narrowed", same, same + 1, digits)
        lines.append("    FAIL a narrowed value was returned instead of raising")
        failed += 1
    except NarrowingAlarm as why:
        lines.append("  require raises NarrowingAlarm on a narrowed value, saying: %s"
                     % str(why).split(",")[0])

    # The row survey, on rows shaped the way the constants table shapes them.
    rows = [{"name": "clean_one", "agreed_digits": digits},
            {"name": "clean_two", "agreed_digits": digits},
            {"name": "short_one", "agreed_digits": digits - 1}]
    short = survey(rows, digits)
    lines.append("  survey over 3 rows, one of them short: found %s" % (short,))
    if short != [("short_one", digits - 1)]:
        lines.append("    FAIL the survey did not name exactly the short row")
        failed += 1

    # The negative control for the survey: all-clean rows must produce no alarm at all.
    try:
        checked = refuse_if_narrowed(rows[:2], digits)
        lines.append("  a clean set of %d rows raises nothing" % checked)
    except NarrowingAlarm:
        lines.append("    FAIL a clean set of rows alarmed, so the guard is unusable")
        failed += 1

    try:
        refuse_if_narrowed(rows, digits)
        lines.append("    FAIL a set containing a short row did not alarm")
        failed += 1
    except NarrowingAlarm:
        lines.append("  a set containing a short row alarms and names it")

    # A zero-length request is a degenerate case and must not be answered with a false pass, since
    # "agrees to all zero places" reads as agreement in a log.
    lines.append("  at a request of 0 places, two differing routes agree to %d"
                 % agreed_places(1, 2, 0))
    if agreed_places(1, 2, 0) != 0:
        lines.append("    FAIL a zero-width request should report zero agreeing places")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the narrowing alarm, with no tolerance in it")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    sys.stdout.write(__doc__)
    sys.exit(2)
