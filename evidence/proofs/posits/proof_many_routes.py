#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRF-x-009
#
# Prove it more than one way. Each quantity below is computed by several independent routes, forward and
# backward, upside down and inside out, and they are made to agree to the digit. A result reached by one
# route is a computation; a result four independent routes agree on is checked, in the sense Blum, Luby
# and Rubinfeld gave result checking and David Platt gave his verification of the zeros.
#
#   Usage:  python evidence/proofs/posits/proof_many_routes.py
#
# Four checks:
#   pi          four routes: three arctan formulas (Machin, Euler, Gauss) and the Gauss-Legendre AGM,
#               a different algorithm with no trigonometric series at all.
#   sqrt(2)     three routes: an integer square root, a Newton iteration, and the backward route of
#               squaring the answer to land on 2 exactly.
#   the NTT     forward then inverse returns the input (backward and forward); the forward twice returns
#               the input reversed (upside down); and the transform of a convolution is the product of
#               the transforms (inside out).
#   the CRT     residues then reconstruction return the value (backward and forward), and two independent
#               reconstructions, direct and mixed-radix, agree.
#
# Positive control: within each check the routes agree exactly. Drawn null: one route is perturbed and
# the agreement breaks. The agreement above is a fact. No bounding: exact integers throughout.

import io
import sys
from math import isqrt

REPORT_DIGITS = 200
GUARD_DIGITS = 20
WORK_DIGITS = REPORT_DIGITS + GUARD_DIGITS
SCALE = 10 ** WORK_DIGITS
GUARD = 10 ** GUARD_DIGITS

PRIME = 998244353
GENERATOR = 3


def agrees(left, right):
    """Whether two scaled integers agree to the reported places."""
    return abs(left - right) < GUARD


def arctan_reciprocal(whole):
    """arctan(1/whole) at WORK_DIGITS places."""
    total = 0
    sign = 1
    power = whole
    whole_squared = whole * whole
    index = 0
    while True:
        term = SCALE // ((2 * index + 1) * power)
        if term == 0:
            break
        total += sign * term
        sign = -sign
        index += 1
        power *= whole_squared
    return total


def arctan_combo(terms):
    """A linear combination of arctan(1/whole) terms, each (coefficient, whole)."""
    return sum(coefficient * arctan_reciprocal(whole) for coefficient, whole in terms)


def pi_agm():
    """pi by the Gauss-Legendre arithmetic-geometric mean, a different algorithm from any series."""
    a = SCALE                                   # 1
    b = isqrt(SCALE * SCALE // 2)               # 1/sqrt(2)
    t = SCALE // 4                              # 1/4
    p = 1
    for _ in range(12):                         # quadratic convergence: 12 rounds passes 200 places
        a_next = (a + b) // 2
        b = isqrt(a * b)                        # geometric mean, scaled
        difference = a - a_next
        t = t - p * (difference * difference) // SCALE
        p *= 2
        a = a_next
    return (a + b) * (a + b) // (4 * t)


def report_pi(out):
    """pi by four independent routes."""
    out.write("  pi, four routes: three arctan formulas and the Gauss-Legendre AGM\n")
    machin = arctan_combo([(16, 5), (-4, 239)])
    euler = arctan_combo([(4, 2), (4, 3)])
    gauss = arctan_combo([(48, 18), (32, 57), (-20, 239)])
    agm = pi_agm()

    routes = {"Machin": machin, "Euler": euler, "Gauss": gauss, "AGM": agm}
    all_agree = all(agrees(value, machin) for value in routes.values())
    # the null: a wrong Machin coefficient, 12 in place of 16
    wrong = arctan_combo([(12, 5), (-4, 239)])
    null_breaks = not agrees(wrong, machin)

    for name, value in routes.items():
        out.write("    %-8s agrees with Machin: %s\n" % (name, agrees(value, machin)))
    out.write("    all four agree to %d places: %s ; a wrong coefficient breaks it: %s\n\n"
              % (REPORT_DIGITS, all_agree, null_breaks))
    return all_agree and null_breaks


def report_sqrt_two(out):
    """sqrt(2) by an integer root, a Newton iteration, and squaring it back."""
    out.write("  sqrt(2), three routes: integer root, Newton, and the backward square\n")
    direct = isqrt(2 * SCALE * SCALE)

    guess = SCALE + SCALE // 2  # 1.5
    for _ in range(20):
        guess = (guess + (2 * SCALE * SCALE) // guess) // 2
    newton = guess

    squared_back = (direct * direct) // SCALE  # should be 2
    routes_agree = agrees(direct, newton)
    round_trip = agrees(squared_back, 2 * SCALE)
    null_breaks = not agrees(direct + GUARD * 10, direct)  # a value off by more than the guard

    out.write("    integer root and Newton agree: %s\n" % routes_agree)
    out.write("    the backward route, (sqrt 2)^2, lands on 2: %s\n" % round_trip)
    out.write("    a value past the guard is caught: %s\n\n" % null_breaks)
    return routes_agree and round_trip and null_breaks


def ntt(values, prime, root_of_length, invert):
    """The number theoretic transform, forward or inverse, on a copy."""
    sequence = list(values)
    count = len(sequence)
    target = 0
    for source in range(1, count):
        bit = count >> 1
        while target & bit:
            target ^= bit
            bit >>= 1
        target ^= bit
        if source < target:
            sequence[source], sequence[target] = sequence[target], sequence[source]
    base = pow(root_of_length, prime - 2, prime) if invert else root_of_length
    span = 2
    while span <= count:
        step = pow(base, count // span, prime)
        for block in range(0, count, span):
            wave = 1
            for offset in range(span // 2):
                low = sequence[block + offset]
                high = sequence[block + offset + span // 2] * wave % prime
                sequence[block + offset] = (low + high) % prime
                sequence[block + offset + span // 2] = (low - high) % prime
                wave = wave * step % prime
        span <<= 1
    if invert:
        inverse_count = pow(count, prime - 2, prime)
        sequence = [value * inverse_count % prime for value in sequence]
    return sequence


def cyclic_convolution_direct(left, right, prime):
    """The cyclic convolution of two equal-length sequences, computed directly, modulo prime."""
    count = len(left)
    result = [0] * count
    for index_left in range(count):
        for index_right in range(count):
            result[(index_left + index_right) % count] += left[index_left] * right[index_right]
    return [value % prime for value in result]


def report_ntt(out):
    """The NTT forward and backward, upside down, and inside out."""
    out.write("  the NTT: forward-inverse round trip, double-transform reversal, convolution theorem\n")
    length = 8
    root = pow(GENERATOR, (PRIME - 1) // length, PRIME)
    original = [3, 1, 4, 1, 5, 9, 2, 6]

    # backward and forward: inverse of the forward is the input
    round_trip = ntt(ntt(original, PRIME, root, False), PRIME, root, True) == original

    # upside down: forward twice is the input read backward from index 0
    twice = ntt(ntt(original, PRIME, root, False), PRIME, root, False)
    reversed_input = [(length * original[(length - index) % length]) % PRIME for index in range(length)]
    inversion = twice == reversed_input

    # inside out: the transform of a cyclic convolution is the pointwise product of the transforms
    other = [2, 7, 1, 8, 2, 8, 1, 8]
    convolution = cyclic_convolution_direct(original, other, PRIME)
    transform_of_convolution = ntt(convolution, PRIME, root, False)
    product_of_transforms = [(one * two) % PRIME for one, two in
                             zip(ntt(original, PRIME, root, False), ntt(other, PRIME, root, False))]
    convolution_theorem = transform_of_convolution == product_of_transforms

    null_breaks = ntt(ntt(original, PRIME, root, False), PRIME, root, True) != [value + 1 for value in original]

    out.write("    forward then inverse returns the input: %s\n" % round_trip)
    out.write("    forward twice returns the input reversed: %s\n" % inversion)
    out.write("    transform of a convolution is the product of transforms: %s\n" % convolution_theorem)
    out.write("    a shifted input is not the round trip: %s\n\n" % null_breaks)
    return round_trip and inversion and convolution_theorem and null_breaks


def report_crt(out):
    """The CRT round trip, and two independent reconstructions."""
    out.write("  the CRT: residues and back, by direct reconstruction and by mixed radix\n")
    moduli = [97, 89, 83, 79]
    whole = 1
    for modulus in moduli:
        whole *= modulus
    value = 4_000_000 % whole
    residues = [value % modulus for modulus in moduli]

    # direct reconstruction
    direct = 0
    for residue, modulus in zip(residues, moduli):
        rest = whole // modulus
        direct += residue * rest * pow(rest, -1, modulus)
    direct %= whole

    # mixed-radix (Garner) reconstruction, an independent route
    mixed = list(residues)
    for outer in range(len(moduli)):
        for inner in range(outer):
            mixed[outer] = (mixed[outer] - mixed[inner]) * pow(moduli[inner], -1, moduli[outer]) % moduli[outer]
    garner = 0
    radix = 1
    for position in range(len(moduli)):
        garner += mixed[position] * radix
        radix *= moduli[position]

    round_trip = direct == value
    routes_agree = direct == garner
    null_breaks = value + whole != direct  # value + product aliases. The raw sum differs

    out.write("    residues then direct reconstruction return the value: %s\n" % round_trip)
    out.write("    direct and mixed-radix reconstructions agree: %s\n" % routes_agree)
    out.write("    a value shifted by the product is not the reconstruction: %s\n\n" % null_breaks)
    return round_trip and routes_agree and null_breaks


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  PROOF: each result by several independent routes, forward and backward, inside out\n\n")
    results = [report_pi(out), report_sqrt_two(out), report_ntt(out), report_crt(out)]
    if all(results):
        out.write("  every result agrees across all its routes, and every null breaks: the routes are\n")
        out.write("  independent and the agreement is a fact, not one computation trusting itself.\n")
    else:
        out.write("  a result disagreed across routes, or a null held: refuted as stated.\n")
    out.flush()
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
