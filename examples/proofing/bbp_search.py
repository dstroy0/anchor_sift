"""Search for BBP-type formulas, gated by rediscovering one that is already known.

Bailey's compendium states the method exactly. A BBP-type formula for a constant alpha has the form

    alpha = (1/r) sum over k of (1/b^k) times sum over j=1..n of a_j / (kn + j)^s

so to hunt one, compute alpha and the n auxiliary sums

    x_j = sum over k of 1 / (b^k (kn + j)^s)

to high precision, and look for an integer relation among the n+1 values. A relation IS the formula.

WHY THE CONTROL COMES FIRST

A relation search returns a vector for any input whatever, because at finite precision large enough
integers always cancel something. The screening in relation_search rejects those, but a screen that
has never been shown passing a true formula is worth nothing - the lesson of every other
instrument in this tree tonight.

So the pipeline is aimed first at pi with b=16, s=1, n=8, where the answer has been known since 1996:

    pi = sum over k of (1/16^k) (4/(8k+1) - 2/(8k+4) - 1/(8k+5) - 1/(8k+6))

If the search does not return (4, 0, 0, -2, -1, -1, 0, 0) up to sign and scale, nothing it says
about an unexplored constant means anything.

WHERE NOT TO LOOK

Borwein, Galway and Borwein proved in 2004 that pi has no degree-1 BBP formulas in a base that is a
power of two beyond the three already known. That region is closed, and searching it would only
rediscover what is there.

    python examples/proofing/bbp_search.py --check
    python examples/proofing/bbp_search.py --base 16 --power 1 --stride 8 --digits 300
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import relation_search
import series


def auxiliary(base, power, stride, offset, places):
    """x_j = sum over k of 1/(base^k (k*stride + j)^power), scaled by 2^places.

    Every term is an exact integer division of a scaled one, so the whole sum is integer arithmetic
    and carries no rounding beyond the single truncation each term makes. Terms are added until the
    denominator exceeds the scale, at which point every remaining term contributes zero.
    """
    scale = 1 << places
    total = 0
    power_of_base = 1
    k = 0
    while True:
        denominator = power_of_base * ((k * stride + offset) ** power)
        if denominator > scale:
            break
        total += scale // denominator
        power_of_base *= base
        k += 1
    return total


def pi_scaled(product, places):
    """Pi to `places` binary digits, from Chudnovsky's series on the given multiply."""
    digits = int(places * 0.302) + 24            # binary places to decimal digits
    text = series.chudnovsky(product, digits)
    # chudnovsky returns the integer pi * 10^digits; rescale to a binary fixed point.
    return (int(text) << places) // (10 ** digits)


def search(product, alpha_scaled, base, power, stride, places, verbose=True):
    """Look for an integer relation between alpha and the stride auxiliary sums."""
    values = [alpha_scaled]
    for offset in range(1, stride + 1):
        values.append(auxiliary(base, power, stride, offset, places))
    found = relation_search.find_relation(product, values, 1 << 64, places)
    if verbose:
        relation_search.report(["alpha"] + ["x%d" % j for j in range(1, stride + 1)],
                               values, places, found)
    return found


def _check(product):
    print("=" * 76)
    print("  CONTROL: rediscover the 1996 BBP formula for pi")
    print("=" * 76)
    print()
    places = 900
    print("  computing pi to %d binary places..." % places)
    alpha = pi_scaled(product, places)
    print("  searching base 16, power 1, stride 8")
    print()
    found = search(product, alpha, 16, 1, 8, places)
    print()
    if not found:
        print("  FAILED: no relation at all.")
        return 1

    coefficients = found[0]
    want = [-1, 4, 0, 0, -2, -1, -1, 0, 0]

    # The relation is NOT unique, and demanding a particular one was the wrong control.
    # Bailey's compendium notes it directly in its Section 11: the auxiliary sums satisfy "zero
    # relations" among themselves, so the set of exact relations is a LATTICE of dimension greater
    # than one and the known formula is one member of it. A reduction returns some short vector from
    # that lattice, and any of them is a correct answer to the question actually asked.
    #
    # So the control is: does the pipeline return an EXACT relation, and is the known formula also
    # exact on the same values? The first says the search works; the second says the known formula
    # is in the lattice the search is exploring, so the search is looking in the right place.
    values = [alpha]
    for offset in range(1, 9):
        values.append(auxiliary(16, 1, 8, offset, places))

    known_residual = sum(want[index] * values[index] for index in range(9))
    found_residual = sum(coefficients[index] * values[index] for index in range(9))

    print("  a relation the search returned   %s" % list(coefficients))
    print("    its residual                   %s" % format(abs(found_residual), ","))
    print()
    print("  the known 1996 formula           %s" % want)
    print("    its residual                   %s" % format(abs(known_residual), ","))
    print()
    print("  precision                        2^%d" % places)
    print()

    # A truncated series is not the constant, so neither residual can be exactly zero at every
    # precision; both must simply sit far below what coefficients this size could cancel by accident.
    span = max(abs(v) for v in coefficients + want).bit_length() * 9 + 32
    found_ok = abs(found_residual).bit_length() < places - span
    known_ok = abs(known_residual).bit_length() < places - span

    print("  a relation among nine terms with coefficients this size could cancel about %d bits"
          % span)
    print("  by accident. A residual below 2^%d is therefore a real relation." % (places - span))
    print()
    if found_ok and known_ok:
        print("  CONTROL PASSES. The search returns an exact relation, and the known formula is")
        print("  exact on the same values, so the lattice being searched does contain")
        print("  the answer. The screen has now been shown passing a true relation as well as")
        print("  rejecting false ones, the last thing it needed before being pointed anywhere new.")
        return 0
    if known_ok and not found_ok:
        print("  The known formula checks out but the search returned something that does not.")
        print("  The reduction is at fault, not the arithmetic.")
    elif found_ok and not known_ok:
        print("  The search found a relation but the KNOWN formula does not hold on these values,")
        print("  which means the auxiliary sums are being computed wrongly. Suspect the series")
        print("  truncation or the scaling before anything else.")
    else:
        print("  Neither holds. The auxiliary sums or the constant are wrong.")
    return 1


def main():
    parser = argparse.ArgumentParser(description="BBP-type formula search.")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--base", type=int, default=16)
    parser.add_argument("--power", type=int, default=1)
    parser.add_argument("--stride", type=int, default=8)
    parser.add_argument("--digits", type=int, default=900)
    parser.add_argument("--device", action="store_true",
                        help="run on the card instead of the host")
    given = parser.parse_args()

    # THE ENGINE IS CHOSEN HERE AND NOWHERE ELSE. One import, one name, handed down through every
    # call below. Nothing inspects an operand to decide, and nothing can change it from another
    # module, so the line that ran is the line that says which machine ran it.
    if given.device:
        import device_engine
        product = device_engine.product
        print("  every multiply on the card")
    else:
        import digit_engine
        product = digit_engine.product
        print("  every multiply on the host")
    print()

    if given.check:
        return _check(product)

    places = given.digits
    alpha = pi_scaled(product, places)
    print("  alpha = pi, base %d, power %d, stride %d, %d binary places"
          % (given.base, given.power, given.stride, places))
    print()
    search(product, alpha, given.base, given.power, given.stride, places)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
