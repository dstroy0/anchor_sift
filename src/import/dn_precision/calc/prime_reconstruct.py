"""Rebuilds pi from the primes alone, and measures how fast it arrives.

    python tools/dn_precision/calc/prime_reconstruct.py
    python tools/dn_precision/calc/prime_reconstruct.py --check

THE CLAIM BEING TESTED

The primes determine pi, exactly, with nothing probabilistic in it. Euler's product for the zeta
function at two is

    zeta(2) = product over primes of 1/(1 - p^-2) = pi^2 / 6

so

    pi = sqrt(6 x product over primes of p^2/(p^2 - 1))

Every factor is a ratio of two integers, so the product over any finite set of primes is an exact
rational and the only inexact step in the whole computation is one square root at the end. Nothing
is estimated and no series is truncated mid-term.

WHAT SEPARATES DETERMINATION FROM COMPUTATION

The product determines pi and it is a poor way to compute it, and those are different claims worth
keeping apart. Truncating at prime bound N leaves the tail

    product over p > N of 1/(1 - p^-2)  =  1 + sum over p > N of p^-2 + ...

and the sum of reciprocal squares of the primes past N is about 1/(N ln N). So the relative error in
zeta(2) is about that, the error in pi is about half of it, and the digits recovered should go like

    digits  ~  log10(N ln N)

which means D digits wants primes out to roughly 10^D. This measures that slope instead of asserting
it. A confirmed slope settles the question in both directions at once: it is a reconstruction, and
it is not a method.

WHAT IS GRADED AGAINST WHAT

The reconstruction is compared against the project's own pi, from `dn_const/dn_constants.csv`, which
was itself agreed by Chudnovsky and Machin independently. Nothing here is compared against the
standard library, since a double would cap the comparison at sixteen digits and the point is to
watch a digit count climb past that.
"""

import argparse
import io
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY = os.path.dirname(HERE)
SUPPORT = os.path.join(FAMILY, "support")
if SUPPORT not in sys.path:
    sys.path.insert(0, SUPPORT)

import dn_load

# Prime bounds to sweep. The largest is where the exact rational product starts costing real time,
# and the sweep is wide enough that a slope is a slope rather than two points and a hope.
BOUNDS = (10, 100, 1000, 10000, 100000, 1000000)

# Places carried through the product and the root. Well past anything the sweep can recover, so the
# working precision is never what limits a row.
PLACES = 400


def primes_to(limit):
    """Every prime at or below `limit`, by a plain sieve."""
    if limit < 2:
        return []
    mark = bytearray([1]) * (limit + 1)
    mark[0] = 0
    mark[1] = 0
    for candidate in range(2, int(limit ** 0.5) + 1):
        if mark[candidate]:
            step = candidate
            start = candidate * candidate
            mark[start:limit + 1:step] = bytearray(len(range(start, limit + 1, step)))
    return [at for at in range(2, limit + 1) if mark[at]]


def euler_product(prime_list):
    """The exact rational product of p^2/(p^2 - 1), as (numerator, denominator).

    Exact because every factor is a ratio of integers. No rounding enters until the caller divides.
    """
    top = 1
    bottom = 1
    for prime in prime_list:
        square = prime * prime
        top *= square
        bottom *= square - 1
    return top, bottom


def pi_from(prime_list, places=PLACES):
    """Pi rebuilt from these primes, as an integer holding `places` decimal places.

    One square root, taken on an integer, at the end. `math.isqrt` is exact, so the returned value
    is the floor of the true root of the rational the primes describe.
    """
    top, bottom = euler_product(prime_list)
    # 6 * product, scaled so the root lands on `places` decimal places.
    inner = (6 * top * 10 ** (2 * places)) // bottom
    return math.isqrt(inner)


def agreed_digits(first, second, places):
    """How many decimal places two values at `places` places share, exactly.

    Counted by comparing the digit strings rather than by taking a logarithm of the difference,
    because the logarithm is off by one whenever the leading differing digits happen to be 9 and 0.
    """
    if first == second:
        return places
    one = str(first).rjust(places + 1, "0")
    two = str(second).rjust(places + 1, "0")
    shared = 0
    for left, right in zip(one, two):
        if left != right:
            break
        shared += 1
    # The first character is the units digit, so shared places past the point is one less.
    return max(0, shared - 1)


def _report():
    truth = dn_load.at("pi", PLACES)

    print("  Pi rebuilt from the primes, by Euler's product for zeta(2).")
    print("  Graded against the project's own pi, agreed by Chudnovsky and Machin.")
    print("")
    print("  %10s %9s %9s %12s %10s  %s"
          % ("prime<=", "primes", "digits", "predicted", "ratio", "first 24 places"))

    rows = []
    for bound in BOUNDS:
        prime_list = primes_to(bound)
        rebuilt = pi_from(prime_list)
        shared = agreed_digits(rebuilt, truth, PLACES)
        predicted = math.log10(bound * math.log(bound)) if bound > 2 else 0.0
        ratio = shared / predicted if predicted > 0 else float("nan")
        text = dn_load.text_of("pi", 24)
        mine = str(rebuilt).rjust(PLACES + 1, "0")
        shown = mine[0] + "." + mine[1:24]
        rows.append((bound, len(prime_list), shared, predicted, ratio))
        print("  %10d %9d %9d %12.3f %10.3f  %s"
              % (bound, len(prime_list), shared, predicted, ratio, shown))

    print("")
    print("  the reference:                                              %s" % dn_load.text_of("pi", 24))
    print("")

    # The slope, taken across the sweep rather than from its ends, since two points and a hope is
    # what this tool exists to replace.
    good = [one for one in rows if one[2] > 0]
    if len(good) >= 2:
        first = good[0]
        last = good[-1]
        span = math.log10(last[0]) - math.log10(first[0])
        climb = last[2] - first[2]
        print("  digits recovered per decade of prime bound: %.3f" % (climb / span if span else 0.0))
        print("  predicted 1.000, since the tail past N is about 1/(N ln N)")
        print("")

        # RECONCILING THE TWO NUMBERS ABOVE, WHICH THIS TOOL USED TO PRINT SIDE BY SIDE AND LEAVE.
        # A measured 1.25 against a predicted 1.00 reads like a disagreement and is not one. The
        # per-row ratio is RISING toward 1, so the asymptotic estimate is an upper bound that the
        # finite-N values approach from below, and a ratio still climbing necessarily makes the
        # measured slope steeper than the asymptotic one over the same range. The convergence is
        # the thing to check, and `--check` now does, rather than a reader having to notice.
        ratios = [one[4] for one in rows if one[2] > 0]
        if len(ratios) >= 2:
            print("  measured over predicted, row by row: %s"
                  % " ".join("%.3f" % one for one in ratios))
            print("  rising toward 1, so the prediction is an asymptote approached from below and")
            print("  the steeper measured slope is that approach rather than a disagreement.")
    print("")
    print("  SO IT RECONSTRUCTS AND IT IS NOT A METHOD. About one digit per decade of primes means")
    print("  D digits wants primes out to 10^D, and the largest bound above recovers single figures.")
    print("  Chudnovsky gains 14.18 digits per TERM. The product settles that pi is determined by")
    print("  the primes; it settles just as firmly that nobody should compute it this way.")
    return 0


def _check():
    lines = []
    failed = 0

    # The sieve, against a known count. pi(100) = 25 and pi(1000) = 168.
    for limit, want in ((100, 25), (1000, 168), (10000, 1229)):
        got = len(primes_to(limit))
        lines.append("  primes up to %5d: %d" % (limit, got))
        if got != want:
            lines.append("    FAIL the sieve says %d and the count is %d" % (got, want))
            failed += 1

    # The product has to be exact. Over the first two primes it is (4/3)(9/8) = 3/2 exactly.
    top, bottom = euler_product([2, 3])
    lines.append("  the product over 2 and 3 is %d/%d" % (top, bottom))
    if top * 2 != bottom * 3:
        lines.append("    FAIL that is not three halves")
        failed += 1

    # The digit comparison must not be fooled by a 9 against a 0, which is the case a logarithm of
    # the difference gets wrong.
    places = 6
    lines.append("  0.199999 against 0.200000 shares %d places"
                 % agreed_digits(199999, 200000, places))
    if agreed_digits(199999, 200000, places) != 0:
        lines.append("    FAIL a leading nine against a zero was counted as agreement")
        failed += 1
    lines.append("  0.123456 against 0.123999 shares %d places"
                 % agreed_digits(123456, 123999, places))
    if agreed_digits(123456, 123999, places) != 3:
        lines.append("    FAIL the shared prefix was miscounted")
        failed += 1

    # And the reconstruction has to actually approach pi, or the sweep is measuring nothing. Two
    # bounds, and the larger must share strictly more places than the smaller.
    truth = dn_load.at("pi", PLACES)
    near = agreed_digits(pi_from(primes_to(100)), truth, PLACES)
    far = agreed_digits(pi_from(primes_to(10000)), truth, PLACES)
    lines.append("  primes to 100 share %d places, primes to 10000 share %d" % (near, far))
    if not far > near:
        lines.append("    FAIL more primes did not get closer to pi")
        failed += 1

    # THE PREDICTION IS AN ASYMPTOTE AND THAT HAS TO BE TESTED, NOT NARRATED. The report prints a
    # measured slope of 1.25 beside a predicted 1.00, which reads like a disagreement. It is not:
    # the per-row ratio of recovered digits to predicted digits RISES toward 1, so the estimate is
    # approached from below and a still-rising ratio makes the measured slope steeper over the same
    # range. The claim is therefore that the ratio is monotone and stays under 1, and both halves
    # are graded here. If the ratio ever exceeded 1 the tail estimate would be wrong rather than
    # conservative, and if it stopped rising the reconstruction would not be converging at the
    # predicted rate at all.
    ratios = []
    for bound in BOUNDS:
        predicted = math.log10(bound * math.log(bound)) if bound > 2 else 0.0
        shared = agreed_digits(pi_from(primes_to(bound)), truth, PLACES)
        if predicted > 0 and shared > 0:
            ratios.append((bound, shared / predicted))
    lines.append("  recovered over predicted: %s"
                 % " ".join("%d:%.3f" % (bound, one) for bound, one in ratios))
    if any(one > 1.0 for _bound, one in ratios):
        lines.append("    FAIL a bound recovered MORE digits than the tail estimate allows, so the")
        lines.append("         estimate is wrong rather than conservative")
        failed += 1
    slipped = [(bound, one) for at, (bound, one) in enumerate(ratios)
               if at and one < ratios[at - 1][1]]
    lines.append("  the ratio rises at every bound: %s" % (not slipped))
    if slipped:
        lines.append("    FAIL the ratio fell at %s, so it is not approaching the asymptote and the"
                     % ", ".join(str(bound) for bound, _one in slipped))
        lines.append("         steeper measured slope is a disagreement after all")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="pi from the primes, and how fast it arrives")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    sys.exit((1 if _check() else 0) if args.check else _report())
