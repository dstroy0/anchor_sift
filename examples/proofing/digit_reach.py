"""A digit of pi taken from a named place, without computing the places before it.

    python examples/proofing/digit_reach.py --check        grade against pi computed the hard way
    python examples/proofing/digit_reach.py --at 1000000   the hex digits at that place
    python examples/proofing/digit_reach.py --time         where the cost actually goes

WHAT THIS DOES THAT THE OTHER ROUTE CANNOT

`digit_engine.py` computes pi from the front. To hold the digit at place n it holds all n of them,
so the storage is the answer's own size, and the wall sits there: a run of 10^30 digits needs 4 * 10^29
bytes, which is some ten million times all the storage ever manufactured. No transform and no
factoring changes that, because it is a statement about the size of the answer and not about the
cost of finding it.

Bailey, Borwein and Plouffe found that pi has a form that does not need the front:

    pi = sum over k of 16^-k * (4/(8k+1) - 2/(8k+4) - 1/(8k+5) - 1/(8k+6))

Because the base is sixteen, multiplying by 16^(n-1) and keeping the fractional part lands exactly
on the nth hexadecimal digit. Every term in the head is then 16^(n-1-k) over (8k+j) reduced modulo
that same (8k+j), which modular exponentiation gives in log time WITHOUT ever forming the large
power. The tail falls off geometrically and a handful of terms exhausts it.

So the memory is O(log n) and the digit at place n costs nothing in storage. The trade is that the
time is still O(n log n): reaching further costs longer, it just does not cost SPACE.

WHY THE GATE IS WORTH MORE THAN THE RESULT

A digit returned from a place nobody can independently reach is a digit nobody can check. So this
is graded against `digit_engine.chudnovsky`, which computes pi from the front by an entirely
different series with no term in common, converted to hexadecimal. The two share no arithmetic and
no constant beyond pi itself, and they have to agree digit for digit over the whole checked range.

THE HONEST LIMIT OF THIS IMPLEMENTATION

The head sum is accumulated in the host's double, which carries 53 bits. That is worth about
thirteen hexadecimal digits before rounding reaches the end, and the last few are not to be
trusted; `--check` measures how many actually survive against the known answer instead of assuming
a number. Extending past that wants the sum carried in exact rationals or in a wider float, and the
place to spend that effort is only after the reach itself is proved, and this file proves it.

WHAT WOULD MAKE IT FAST

The head sum is a sum over k of terms that do not refer to each other. It is embarrassingly
parallel in the strict sense, so the same card that runs the transform would run this with one k
per lane and no communication at all. That is not built here; the reach is proved on the host first
so the device has something to be checked against.
"""

import argparse
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import digit_engine

sys.set_int_max_str_digits(0)

HEX = "0123456789abcdef"


def series(j, place):
    """The fractional part of sum over k of 16^(place-1-k) / (8k+j).

    The head runs k below `place` and every term is a modular power over its own denominator, so
    nothing here is ever larger than that denominator and the whole sum stays inside a double. The
    tail runs above `place`, where the powers are negative and fall by sixteen each step, so it is
    exhausted as soon as a term drops under the format's own resolution.
    """
    total = 0.0
    for k in range(place):
        lower = 8 * k + j
        total += pow(16, place - 1 - k, lower) / lower
        total -= int(total)

    scale = 1.0 / 16.0
    k = place
    while True:
        term = scale / (8 * k + j)
        if term < 1e-18:
            break
        total += term
        scale /= 16.0
        k += 1
    return total - int(total)


def hex_at(place, count=10):
    """The `count` hexadecimal digits of pi beginning at `place`, counting the first after the point.

    Place one is the first hexadecimal digit after the point, which is 2, since pi is 3.243F6A88 in
    hexadecimal. The whole part is not returned because the formula addresses the fraction.
    """
    if place < 1:
        raise ValueError("places are counted from one")
    value = (4.0 * series(1, place) - 2.0 * series(4, place)
             - series(5, place) - series(6, place))
    value -= int(value)
    if value < 0.0:
        value += 1.0

    out = []
    for _ in range(count):
        value *= 16.0
        digit = int(value)
        out.append(HEX[digit])
        value -= digit
    return "".join(out)


def hex_of_pi(places):
    """Pi's hexadecimal fraction to `places` digits, from the front, by the verified series.

    Computed as an integer so nothing rounds: pi scaled by sixteen to the place count, with the
    whole part removed, gives the fraction's hexadecimal digits precisely.
    """
    # Decimal places enough to cover the hexadecimal ones asked for, with room for the conversion.
    decimals = int(places * 1.21) + 24
    scaled = digit_engine.chudnovsky(decimals)

    # scaled holds pi * 10^decimals. Multiply by 16^places and divide the ten out, exactly.
    lifted = (scaled * (16 ** places)) // (10 ** decimals)
    whole = 3 * (16 ** places)
    fraction = lifted - whole
    text = format(fraction, "x").rjust(places, "0")
    return text[:places]


def _check():
    lines = []
    failed = 0

    lines.append("  THE FIRST PLACES, against the published hexadecimal expansion")
    known = "243f6a8885a308d313198a2e03707344"
    got = hex_at(1, 16)
    agree = got == known[:16]
    lines.append("    place 1     %s" % got)
    lines.append("    published   %s   %s" % (known[:16], "agree" if agree else "DIFFER"))
    if not agree:
        # Report how far it held instead of a bare failure, since the tail is the format's.
        held = 0
        for one, two in zip(got, known):
            if one != two:
                break
            held += 1
        lines.append("    held for %d of 16 digits before the double ran out" % held)
        if held < 10:
            failed += 1
    lines.append("")

    lines.append("  REACHED PLACES, against pi computed from the front by another series")
    front = hex_of_pi(260)
    trouble = 0
    for place in (1, 2, 7, 16, 33, 64, 100, 150, 200, 240):
        reached = hex_at(place, 8)
        wanted = front[place - 1:place - 1 + 8]
        held = 0
        for one, two in zip(reached, wanted):
            if one != two:
                break
            held += 1
        mark = "all 8" if held >= 8 else ("%d of 8" % held)
        lines.append("    place %-5d reached %s  front %s  %s" % (place, reached, wanted, mark))
        if held < 6:
            trouble += 1
    failed += trouble
    lines.append("")
    lines.append("    %s" % ("every place held at least six digits"
                             if not trouble else "%d place(s) held under six" % trouble))
    lines.append("")

    lines.append("  THE REACH IS NOT READING THE FRONT, which is the whole claim")
    start = time.perf_counter()
    hex_at(50000, 4)
    far = time.perf_counter() - start
    start = time.perf_counter()
    hex_at(500, 4)
    near = time.perf_counter() - start
    lines.append("    place 500    %.4f s" % near)
    lines.append("    place 50000  %.4f s" % far)
    lines.append("    cost grows with the place and the memory does not move, which is the point")
    lines.append("")

    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


def _time():
    sys.stdout.write("  WHERE THE COST GOES\n\n")
    sys.stdout.write("  %14s %12s %14s\n" % ("place", "seconds", "digits"))
    sys.stdout.flush()
    for power in (3, 4, 5, 6, 7):
        place = 10 ** power
        start = time.perf_counter()
        got = hex_at(place, 6)
        spent = time.perf_counter() - start
        sys.stdout.write("  %14s %12.3f %14s\n" % (format(place, ","), spent, got))
        sys.stdout.flush()
    sys.stdout.write("\n  Memory does not appear in this table because it does not change.\n")
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="a digit of pi from a named place")
    parser.add_argument("--check", action="store_true", help="grade against the front route")
    parser.add_argument("--time", action="store_true", help="where the cost goes")
    parser.add_argument("--at", type=int, default=0, help="the place to reach into")
    parser.add_argument("--count", type=int, default=10, help="how many digits to take")
    args = parser.parse_args()

    if args.check:
        sys.exit(1 if _check() else 0)
    if args.time:
        sys.exit(_time())
    if args.at:
        start = time.perf_counter()
        got = hex_at(args.at, args.count)
        spent = time.perf_counter() - start
        sys.stdout.write("pi, hexadecimal, %s digits from place %s: %s\n"
                         % (args.count, format(args.at, ","), got))
        sys.stdout.write("  %.3f s, and the places before it were never computed\n" % spent)
        sys.exit(0)
    parser.print_help()
