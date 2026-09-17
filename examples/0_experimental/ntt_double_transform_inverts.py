#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-013
#
# The number theoretic transform applied twice turns the sequence around: NTT(NTT(x))[m] = n x[(-m) mod
# n], a reflection about the origin, exact in the integers modulo a prime. It is a wave inversion, and
# it is where the transform's boundary shows itself.
#
#   Usage:  python examples/0_experimental/ntt_double_transform_inverts.py
#
# This reads no corpus, so it sits in 0_experimental: an arithmetic result shown working, not a stage
# reading. The transform is a sum over roots of unity, which are waves on the circle: X[k] = sum_j x[j]
# w^{jk} with w an n-th root of unity. Apply it a second time and every term collects into a delta,
# because sum_k w^{k(j+m)} is n when j+m is 0 modulo n and 0 otherwise, so the second transform returns
# n times the original read backward from index 0. The forward transform is its own inverse up to that
# reversal and the scale n, and that is the exact reason the inverse transform runs the same butterfly
# with the reciprocal root.
#
# The boundary is real and it is here. The transform length n must divide p - 1, and for this prime,
# p = 998244353 = 119 * 2^23 + 1, the longest power-of-two length is 2^23. Past it there is no root of
# the needed order on this prime; a larger 2-adic prime (2^27 on the device primes, 2^32 on goldilocks,
# 2^48 in the twiddle paper) moves the boundary, and it is a choice of format, never absent. The
# transform is cyclic within that length: index n folds back to 0, the turn-around, and a
# convolution longer than n wraps into itself unless it is padded, the aliasing the translation example
# guards against.
#
# Prior art. The transform being its own inverse up to a reversal is the discrete Fourier transform's
# order-four structure: the DFT is an operator of order 4 with eigenvalues in {+1, -1, +i, -i}, and its
# square is the reflection or parity operator P with (P x)[m] = x[-m], the wave inversion shown here.
# See McClellan and Parks, "Eigenvalue and eigenvector decomposition of the discrete Fourier
# transform", IEEE Trans. Audio Electroacoust. 1972, and arXiv:0808.3214. The number theoretic transform
# is the discrete Fourier transform over a finite field, with the length condition n divides p-1 that
# fixes the boundary named above: Pollard, "The fast Fourier transform in a finite field", Math. Comp.
# 1971, and the survey arXiv:2211.13546. This example reproduces those results in exact integers and
# does not rest on them; the citation records that the property is known, not that it is assumed here.
#
# Positive control: NTT(NTT(x)) equals n times the reversed x, to the digit. Two routes: the double
# transform against a direct reversal, shown able to disagree. Drawn null: the claim without the
# reversal, NTT(NTT(x)) = n x, is refused on a sequence that is not a palindrome. No bounding: the
# length, the prime and the root are declared, and every value is an exact residue.

import io
import sys

PRIME = 998244353          # 119 * 2^23 + 1, primitive root 3
GENERATOR = 3
LENGTH = 8                 # a small power-of-two length dividing p - 1


def ntt_forward(values, prime, root_of_length):
    """The forward number theoretic transform, X[k] = sum_j x[j] root^{jk}, in place on a copy."""
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

    span = 2
    while span <= count:
        step_root = pow(root_of_length, count // span, prime)
        for block in range(0, count, span):
            wave = 1
            for offset in range(span // 2):
                low = sequence[block + offset]
                high = sequence[block + offset + span // 2] * wave % prime
                sequence[block + offset] = (low + high) % prime
                sequence[block + offset + span // 2] = (low - high) % prime
                wave = wave * step_root % prime
        span <<= 1
    return sequence


def reverse_about_origin(values, prime):
    """x read backward from index 0: entry m becomes x[(-m) mod n]. Index 0 stays, the rest turn around."""
    count = len(values)
    return [values[(count - index) % count] % prime for index in range(count)]


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  the transform applied twice turns the sequence around: a wave inversion, exact mod p\n\n")

    root_of_length = pow(GENERATOR, (PRIME - 1) // LENGTH, PRIME)  # a primitive LENGTH-th root of unity
    original = [3, 1, 4, 1, 5, 9, 2, 6]  # not a palindrome, so the reversal is visible

    once = ntt_forward(original, PRIME, root_of_length)
    twice = ntt_forward(once, PRIME, root_of_length)

    turned = [(LENGTH * value) % PRIME for value in reverse_about_origin(original, PRIME)]
    inverts = twice == turned

    # the null: the same claim without the reversal, which a non-palindrome refuses
    without_reversal = [(LENGTH * value) % PRIME for value in original]
    no_reversal_holds = twice == without_reversal

    out.write("  prime %d, length %d, root of unity %d\n" % (PRIME, LENGTH, root_of_length))
    out.write("  x            = %s\n" % original)
    out.write("  NTT(NTT(x))  = %s\n" % twice)
    out.write("  n * reverse  = %s\n" % turned)
    out.write("  NTT(NTT(x)) == n * reverse(x): %s (the wave inversion, exact)\n" % inverts)
    out.write("  NTT(NTT(x)) == n * x (no reversal): %s (refused, x is not a palindrome)\n\n"
              % no_reversal_holds)

    out.write("  boundary: the length divides p - 1, capped at 2^23 for this prime, moved by a larger\n")
    out.write("  2-adic prime or by CRT, and the transform is cyclic within it: index n folds to 0.\n")
    out.flush()

    return 0 if (inverts and not no_reversal_holds) else 1


if __name__ == "__main__":
    raise SystemExit(main())
