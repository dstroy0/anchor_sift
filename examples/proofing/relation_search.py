"""Integer relation detection at whatever precision the engine will carry.

Given real numbers x0 through xn, an integer relation is a vector of integers a0 through an, not all
zero, with

    a0 x0 + a1 x1 + ... + an xn = 0

Finding one turns a set of numbers into a closed form. This is how the BBP formula for pi was found:
Bailey, Borwein and Plouffe computed candidate terms to high precision and searched for a relation
among them, and the relation WAS the formula. Nothing about the method is specific to pi.

WHY PRECISION IS THE WHOLE GAME

A relation whose coefficients run to D digits cannot be seen at less than about D times n digits of
input, because below that the lattice cannot tell a true relation from an accidental one. That makes
this a precision-bound search and not a time-bound one. Precision is the single axis where an engine
with no floor under it buys something that more cores do not.

It also makes the failure mode sharp and worth stating: at insufficient precision the search returns
relations that are ARTIFACTS, small integer combinations that happen to cancel in the digits
available and diverge past them. So every candidate here is re-evaluated at the full input precision
and reported with the size of its residual, and a relation whose residual is not far below the
precision it was found at is rejected instead of reported.

THE METHOD

An integer-preserving LLL on the lattice whose rows are

    ( 1 0 ... 0   round(M x0) )
    ( 0 1 ... 0   round(M x1) )
    ( ...                     )
    ( 0 0 ... 1   round(M xn) )

for a large multiplier M. A short vector in that lattice has a small last coordinate, which is
exactly a small value of the combination, and its first n coordinates are the coefficients. The
reduction is done in integers throughout - no float appears anywhere in the search, which matters
the search has to work below the depth where a float has anything left.

    python examples/proofing/relation_search.py --check
    python examples/proofing/relation_search.py --demo
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# THE MULTIPLY IS AN ARGUMENT, NOT A GLOBAL. The lattice entries are the constants at full width, so
# every inner product multiplies numbers of whatever precision the search is running at. The whole
# search reduces to that single operation, and it is the operation the engines exist for.
#
# What stood here was a `use_engine()` that rebound a module-level PRODUCT. It meant a caller could
# change the arithmetic of every other caller in the process, and - worse - it routed through a
# dispatch that hands operands below 1,024 limbs back to the host, leaving a search at 900 bits to run
# entirely on the CPU while reporting that the device was engaged. Passing the multiply in makes the
# machine visible at the call site and impossible to change from anywhere else.
#
#     import digit_engine     then pass digit_engine.product     host, at every size
#     import device_engine    then pass device_engine.product    card, at every size
#
# Nothing here is a float and nothing is approximate. The entries are exact scaled integers, the
# products are exact, and the reduction's decisions are integer comparisons throughout.


def inner(product, left, right):
    total = 0
    for index in range(len(left)):
        total += product(left[index], right[index])
    return total


def gram_schmidt_integer(product, basis):
    """Integer Gram-Schmidt quantities: d[i] are the leading Gram determinants, lam[i][j] the
    scaled coefficients. Everything stays an integer.

    De Weger's formulation, in which every division below is exact by construction - the numerator
    is a determinant identity that the previous d divides - so no rational is ever formed and no
    rounding enters the reduction.
    """
    count = len(basis)
    lam = [[0] * count for _ in range(count)]
    d = [0] * (count + 1)
    d[0] = 1
    for index in range(count):
        for other in range(index + 1):
            # THIS USED TO COMPUTE `total` TWICE. A first version accumulated one recurrence, then
            # overwrote it with the second before the first was ever read - dead work whose only
            # effect was to make the loop look like it was doing something it was not. The second
            # form is the correct one and is now the only one.
            total = inner(product, basis[index], basis[other])
            for step in range(other):
                total = (product(total, d[step + 1])
                         - product(lam[index][step], lam[other][step])) // d[step]
            if other < index:
                lam[index][other] = total
            else:
                d[index + 1] = total
    return lam, d


def reduce_lattice(product, basis):
    """Integer LLL with the standard three-quarters condition. Returns the reduced basis.

    Written against de Weger's integer formulation so no rational or float is ever formed. The
    exchange condition is cross-multiplied instead of divided, for the same reason.
    """
    basis = [list(row) for row in basis]
    count = len(basis)
    lam, d = gram_schmidt_integer(product, basis)

    def reduce_pair(index, other):
        if d[other + 1] == 0:
            return
        twice = 2 * lam[index][other]
        if twice > d[other + 1] or twice < -d[other + 1]:
            near = (twice + d[other + 1]) // (2 * d[other + 1])
            for slot in range(len(basis[index])):
                basis[index][slot] -= product(near, basis[other][slot])
            for step in range(other):
                lam[index][step] -= near * lam[other][step]
            lam[index][other] -= near * d[other + 1]

    index = 1
    guard = 0
    while index < count and guard < 200000:
        guard += 1
        reduce_pair(index, index - 1)
        left = (product(d[index + 1], d[index - 1])
                + product(lam[index][index - 1], lam[index][index - 1]))
        right = (3 * product(d[index], d[index])) // 4
        if left < right:
            basis[index], basis[index - 1] = basis[index - 1], basis[index]
            lam, d = gram_schmidt_integer(product, basis)
            index = max(index - 1, 1)
        else:
            for other in range(index - 2, -1, -1):
                reduce_pair(index, other)
            index += 1
    return basis


def find_relation(product, scaled, multiplier, places):
    """Search for an integer relation among values already scaled to `places` binary digits.

    `scaled[k]` is round(x_k * 2^places) as an exact integer. The multiplier weights the last
    column, forcing a short vector to have a small combination instead of small coefficients.
    """
    count = len(scaled)
    basis = []
    for index in range(count):
        row = [0] * count + [multiplier * scaled[index]]
        row[index] = 1
        basis.append(row)
    reduced = reduce_lattice(product, basis)

    best = None
    for row in reduced:
        coefficients = row[:count]
        if not any(coefficients):
            continue
        residual = 0
        for index in range(count):
            residual += product(coefficients[index], scaled[index])
        size = max(abs(v) for v in coefficients)
        if best is None or abs(residual) < abs(best[1]):
            best = (coefficients, residual, size)
    return best


def report(names, scaled, places, found):
    """State the candidate and whether its residual is small enough to be believed."""
    if found is None:
        print("    no candidate")
        return False
    coefficients, residual, size = found
    print("    coefficients      %s" % ", ".join(str(v) for v in coefficients))
    print("    largest           %s" % format(size, ","))
    print("    residual          %s" % format(abs(residual), ","))
    print("    input precision   2^%d" % places)
    # A relation is believable only when its residual sits far below the precision it was found at.
    # An artifact cancels to roughly the precision and no further.
    margin = places - (abs(residual).bit_length() if residual else 0)
    print("    residual is 2^-%d of the scale, a margin of %d bits"
          % (places - (abs(residual).bit_length() if residual else places), margin))
    coefficient_bits = size.bit_length()
    print("    coefficient size  %d bits" % coefficient_bits)
    print()
    if residual == 0:
        print("    EXACT. The combination vanishes at full precision.")
        return True
    if margin > coefficient_bits * len(scaled) + 32:
        print("    Believable: the residual sits far below what coefficients this size could")
        print("    cancel by accident at this precision.")
        return True
    print("    REJECTED as an artifact. The residual is not far enough below the precision to")
    print("    distinguish a relation from an accidental cancellation among integers this large.")
    return False


def _check(product, label):
    """The gate, run against one named engine. Both directions, because one is not a test.

    A search that finds the planted relation but also "finds" one among unrelated numbers is a
    generator of vectors, not a detector of relations, and only the second arm can tell those apart.
    """
    print("=" * 74)
    print("  GATE on the %s: a planted relation must come back exactly" % label)
    print("=" * 74)
    places = 400
    scale = 1 << places
    # 3a - 5b + 2c = 0 by construction, with a and b arbitrary large integers.
    a = 987654321987654321 * (scale // 10 ** 19)
    b = 123456789123456789 * (scale // 10 ** 19)
    c = (5 * b - 3 * a) // 2
    print()
    print("  planted: 3a - 5b + 2c = 0")
    found = find_relation(product, [a, b, c], 1 << 64, places)
    ok = report(["a", "b", "c"], [a, b, c], places, found)
    if found:
        print()
        print("  recovered up to sign and a common factor: %s" % (found[0],))
    print()

    print("=" * 74)
    print("  NULL on the %s: unrelated numbers must NOT produce a believable relation" % label)
    print("=" * 74)
    import random
    rng = random.Random(0x5EE)
    unrelated = [rng.getrandbits(places) for _ in range(3)]
    print()
    null = find_relation(product, unrelated, 1 << 64, places)
    bad = report(["u", "v", "w"], unrelated, places, null)
    print()
    return ok, bad, (found[0] if found else None)


def main():
    parser = argparse.ArgumentParser(description="Integer relation detection.")
    parser.add_argument("--check", action="store_true", help="run the gate on the host")
    parser.add_argument("--both", action="store_true",
                        help="run the gate on host and card and require identical answers")
    given = parser.parse_args()

    if given.both:
        import device_engine
        import digit_engine
        import gpu_multiply
        host_ok, host_bad, host_found = _check(digit_engine.product, "host")
        card_ok, card_bad, card_found = _check(device_engine.product, "card")
        print("=" * 74)
        print("  RESULT")
        print("=" * 74)
        print()
        print("    host  recovered the planted relation:  %s" % ("yes" if host_ok else "NO"))
        print("    card  recovered the planted relation:  %s" % ("yes" if card_ok else "NO"))
        print("    host  rejected the unrelated numbers:  %s" % ("yes" if not host_bad else "NO"))
        print("    card  rejected the unrelated numbers:  %s" % ("yes" if not card_bad else "NO"))
        # THE DECIDING LINE. Two engines that agree on a verdict but disagree on the vector are
        # not the same search, and a difference here is a device fault that the verdicts hid.
        agree = host_found == card_found
        print("    the two returned the SAME vector:      %s" % ("yes" if agree else "NO"))
        print()
        print("    %s" % ("host and card are running the same search"
                          if agree else "REFUSING: the engines disagree and one of them is wrong"))
        gpu_multiply.shut_down()
        good = host_ok and card_ok and not host_bad and not card_bad and agree
        return 0 if good else 1

    if given.check:
        import digit_engine
        ok, bad, _ = _check(digit_engine.product, "host")
        print("=" * 74)
        print("  RESULT")
        print("=" * 74)
        print()
        print("    planted relation recovered:     %s" % ("yes" if ok else "NO"))
        print("    unrelated numbers rejected:     %s" % ("yes" if not bad else "NO, FALSE POSITIVE"))
        return 0 if (ok and not bad) else 1

    print(__doc__)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
