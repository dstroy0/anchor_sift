#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRF-x-007
#
# Five precision theorems the engine's exact arithmetic rests on, each proven by cases where the answer
# is fixed by construction, with a positive control and a drawn null that names the fault the theorem
# excludes.
#
#   Usage:  python evidence/proofs/posits/proof_precision_theorems.py
#
# The theorems:
#   scale invariance      a value read at any scale above its own places gives the same number, and a
#                         scale below its places refuses in place of rounding.
#   no-alias convolution  a cyclic convolution of length M equals the linear one exactly when M is at
#                         least La + Lb - 1, and aliases when it is shorter.
#   CRT bijection         residues against pairwise coprime moduli name one integer below their product,
#                         and a value at or above the product aliases to it.
#   Fermat inverse        for a prime p and a not divisible by p, a times a^(p-2) is 1 modulo p, the
#                         modular inverse the transform and the CRT both use, and it fails on a composite.
#   exact accumulation    an exact integer sum is the same in any order, losing nothing; the same terms
#                         in floating point depend on the order.
#
# No bounding: every test is an exact integer or bit comparison, and each null is a constructed fault.

import io
import sys


class WillNotFit(ValueError):
    """A value carries more decimal places than the scale asked to hold it. Its own class by design."""


def scaled(numerator, places, digits):
    """`numerator` at `places` decimal places, re-read at `digits` places. Refuses a scale too small."""
    if places > digits:
        raise WillNotFit("%d places will not fit %d" % (places, digits))
    return numerator * (10 ** (digits - places))


def prove_scale_invariance(out):
    """A value read above its places is the same number; read below its places it refuses."""
    out.write("  scale invariance: a scale above the value's places changes nothing, below it refuses\n")
    numerator, places = 47605, 4  # the value 4.7605

    at_places = scaled(numerator, places, places)
    at_higher = scaled(numerator, places, places + 40)
    at_highest = scaled(numerator, places, places + 400)
    same = (at_higher // (10 ** 40)) == at_places and (at_highest // (10 ** 400)) == at_places

    refused = False
    try:
        scaled(numerator, places, places - 1)
    except WillNotFit:
        refused = True

    out.write("    read at %d, %d, %d places is the same value: %s\n"
              % (places, places + 40, places + 400, same))
    out.write("    read at %d places (below its own): refused: %s\n\n" % (places - 1, refused))
    return same and refused


def linear_convolution(left, right):
    """The exact linear convolution, length len(left) + len(right) - 1."""
    result = [0] * (len(left) + len(right) - 1)
    for index_left, value_left in enumerate(left):
        for index_right, value_right in enumerate(right):
            result[index_left + index_right] += value_left * value_right
    return result


def cyclic_convolution(left, right, length):
    """The exact cyclic convolution of a given length, index sums taken modulo `length`."""
    result = [0] * length
    for index_left, value_left in enumerate(left):
        for index_right, value_right in enumerate(right):
            result[(index_left + index_right) % length] += value_left * value_right
    return result


def prove_no_alias_convolution(out):
    """Cyclic equals linear at length La + Lb - 1, and aliases one shorter."""
    out.write("  no-alias convolution: cyclic equals linear at length La + Lb - 1, aliases below it\n")
    left = [3, 1, 4, 1]
    right = [5, 9, 2]
    linear = linear_convolution(left, right)
    exact_length = len(left) + len(right) - 1

    no_alias = cyclic_convolution(left, right, exact_length) == linear
    aliased = cyclic_convolution(left, right, exact_length - 1) != linear[:exact_length - 1]

    out.write("    length %d: cyclic == linear: %s\n" % (exact_length, no_alias))
    out.write("    length %d: cyclic aliases (differs from linear): %s\n\n" % (exact_length - 1, aliased))
    return no_alias and aliased


def product(values):
    """The product of a list of integers."""
    total = 1
    for value in values:
        total *= value
    return total


def crt(residues, moduli):
    """The unique integer in [0, product(moduli)) with the given residues, by the Chinese remainder theorem."""
    whole = product(moduli)
    total = 0
    for residue, modulus in zip(residues, moduli):
        rest = whole // modulus
        total += residue * rest * pow(rest, -1, modulus)
    return total % whole


def prove_crt_bijection(out):
    """Residues name one integer below the product, and a value at or above the product aliases to it."""
    out.write("  CRT bijection: residues name one integer below the product, a larger value aliases\n")
    moduli = [7, 11, 13]
    whole = product(moduli)

    round_trips = all(crt([value % modulus for modulus in moduli], moduli) == value
                      for value in range(whole))
    # injective on [0, whole): distinct values below the product never share a residue tuple
    tuples = {tuple(value % modulus for modulus in moduli) for value in range(whole)}
    injective = len(tuples) == whole

    value = 100
    aliases = crt([(value + whole) % modulus for modulus in moduli], moduli) == value

    out.write("    every value in [0, %d) round-trips through its residues: %s\n" % (whole, round_trips))
    out.write("    the map is injective on that range: %s\n" % injective)
    out.write("    a value at product + %d aliases back to %d: %s (the boundary)\n\n" % (value, value, aliases))
    return round_trips and injective and aliases


def prove_fermat_inverse(out):
    """a^(p-2) is a's inverse modulo a prime p, and the identity fails on a composite."""
    out.write("  Fermat inverse: a^(p-2) inverts a modulo a prime, and fails on a composite\n")
    prime = 998244353
    holds = all((base * pow(base, prime - 2, prime)) % prime == 1 for base in range(1, 200))

    # A non-Carmichael composite. A Carmichael number, 561 the smallest, satisfies a^(n-1) == 1 for
    # every coprime a and so would satisfy this identity and fool the test; the honest null avoids one.
    composite = 15
    fails_somewhere = any((base * pow(base, composite - 2, composite)) % composite != 1
                          for base in range(2, composite) if gcd(base, composite) == 1)

    out.write("    prime %d: a * a^(p-2) == 1 for a in 1..199: %s\n" % (prime, holds))
    out.write("    composite %d: the identity fails for some unit a: %s\n\n" % (composite, fails_somewhere))
    return holds and fails_somewhere


def gcd(first, second):
    """The greatest common divisor, by Euclid."""
    while second:
        first, second = second, first % second
    return first


def prove_exact_accumulation(out):
    """An exact integer sum is order-invariant; the same terms in floating point are not."""
    out.write("  exact accumulation: an exact sum is order-free, a floating sum is not\n")
    terms = [1, 10 ** 16, -(10 ** 16)]

    forward = terms[0] + terms[1] + terms[2]
    backward = terms[2] + terms[1] + terms[0]
    reordered = terms[1] + terms[2] + terms[0]
    exact_order_free = forward == backward == reordered == 1

    floats = [1.0, 1e16, -1e16]
    float_one = (floats[0] + floats[1]) + floats[2]
    float_two = (floats[1] + floats[2]) + floats[0]
    float_order_dependent = float_one != float_two

    out.write("    exact sum is 1 in every order: %s\n" % exact_order_free)
    out.write("    floating sum depends on order: %s (%.1f vs %.1f)\n\n"
              % (float_order_dependent, float_one, float_two))
    return exact_order_free and float_order_dependent


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  PROOF: five precision theorems, each with a positive control and a drawn null\n\n")
    results = [
        prove_scale_invariance(out),
        prove_no_alias_convolution(out),
        prove_crt_bijection(out),
        prove_fermat_inverse(out),
        prove_exact_accumulation(out),
    ]
    if all(results):
        out.write("  all five land on their forced outcome: the theorems hold as stated.\n")
    else:
        out.write("  a theorem missed its forced outcome: it is refuted as stated.\n")
    out.flush()
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
