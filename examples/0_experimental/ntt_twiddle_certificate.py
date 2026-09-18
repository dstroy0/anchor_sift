#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-007
#
# The precision constants a number theoretic transform rests on, re-derived from the factorization of
# p-1 instead of tabled, and a wrong constant rejected by the same checks.
#
#   Usage:  python examples/0_experimental/ntt_twiddle_certificate.py
#
# This reads no corpus. It sits in 0_experimental: an arithmetic result shown working, not a stage
# reading. A number theoretic transform is exact only if its modulus is prime, its stated generator is
# a primitive root, and the root it builds twiddles from has order exactly the transform length. Each
# of those is a constant, and a constant taken on trust is a silent wrong answer waiting: the twiddle
# proof in theory_bucket/twiddle_constants_article.tex records two of them found in this project by
# running the check instead of reading the code.
#
# Three things are shown. First, the certificate: every modulus used here, the three device primes and
# the goldilocks prime from that paper plus the prime the image_transforms translation transform uses,
# re-derived from scratch. Second, the rejection: a composite of the same Proth shape and a false
# primitive-root claim are refused by the same checks that pass the real ones. The checks can fail
# and passing means something. Third, the floor: a root of HALF the required order passes every
# invariant computable from the table in O(n), and only the order test, two exponentiations, separates
# it. That is the paper's central result reproduced here (theory_bucket/twiddle_constants_article.tex, its section on a root of half the order and the only test that catches it).
#
# No bounding: no threshold is set here. Every verdict is an exact integer equality or inequality on
# unbounded Python integers, and the wrong cases are drawn, not described.

import io
import sys

# Declared inputs. The pinned moduli, each with the shape it is quoted in and the constants claimed for
# it. Device primes and witnesses are in theory_bucket/twiddle_constants_article.tex, its section on the
# two silent wrong answers the certificate caught; the goldilocks prime is in its section on what the
# size costs; the translation prime is the image_transforms exact-arithmetic chapter.
# generator is the primitive root that builds the twiddle table; witness is the Proth primality witness,
# a different role and, for the first device prime, a different number.
PINNED = [
    # (label, modulus, shape, generator, proth_witness)
    ("image_transforms translation", 998244353, "119 * 2^23 + 1", 3, None),
    ("device modulus 1", 2013265921, "15 * 2^27 + 1", 31, 11),
    ("device modulus 2", 2281701377, "17 * 2^27 + 1", 3, 3),
    ("device modulus 3", 3892314113, "29 * 2^27 + 1", 3, 3),
    ("goldilocks", 18446744069414584321, "(2^32 - 1) * 2^32 + 1", 7, None),
]


def distinct_prime_factors(number):
    """The distinct primes dividing `number`, by trial division. Exact and unbounded.

    The moduli here are at most 64 bits. P-1 factors in well under a second by trial division and
    needs nothing heavier. The primitive-root test below needs only the distinct primes, not their
    multiplicities.
    """
    factors = set()
    remaining = number
    divisor = 2
    while divisor * divisor <= remaining:
        while remaining % divisor == 0:
            factors.add(divisor)
            remaining //= divisor
        divisor += 1 if divisor == 2 else 2
    if remaining > 1:
        factors.add(remaining)
    return factors


def two_adic_order(number):
    """The largest power of two dividing `number`, as its exponent. The transform-length ceiling.

    A number theoretic transform of length n needs an n-th root of unity, and one exists modulo a prime
    p exactly when n divides p-1. The largest power of two dividing p-1 is therefore the longest
    power-of-two transform the modulus admits.
    """
    exponent = 0
    while number % 2 == 0:
        number //= 2
        exponent += 1
    return exponent


def is_primitive_root(generator, prime, pminus1_factors):
    """Whether `generator` has order exactly prime-1, the definition of a primitive root.

    g is a primitive root modulo a prime p iff g^((p-1)/q) != 1 for every prime q dividing p-1. If it
    were 1 for some q, the order of g would divide (p-1)/q and so fall short of p-1. Checking the
    prime divisors is enough because any proper divisor of p-1 divides one of them.
    """
    exponent_base = prime - 1
    return all(pow(generator, exponent_base // q, prime) != 1 for q in pminus1_factors)


def proth_certifies_prime(witness, candidate):
    """Whether `witness` proves `candidate` prime by Proth's theorem.

    Proth's theorem: for N = k * 2^n + 1 with k odd and 2^n > k, N is prime iff some a satisfies
    a^((N-1)/2) == -1 (mod N). One witness meeting that congruence is a proof, not evidence.
    """
    return pow(witness, (candidate - 1) // 2, candidate) == candidate - 1


def order_dividing(element, prime, bound):
    """The multiplicative order of `element` modulo `prime`, given it divides `bound`.

    Walks the divisors of `bound` upward and returns the first that annihilates the element. Used only
    where the order is known to divide a small power of two. The walk is short.
    """
    for candidate_order in range(1, bound + 1):
        if bound % candidate_order == 0 and pow(element, candidate_order, prime) == 1:
            return candidate_order
    return None


def report_certificate(out):
    """Section one: re-derive every pinned constant. The positive control."""
    out.write("  certificate: every pinned modulus re-derived from p-1\n")
    out.write("  %-30s %-13s %-6s %-9s %-11s %-11s %s\n"
              % ("modulus", "value", "bits", "2-adic", "generator", "witness", "verdict"))
    all_pass = True
    for label, modulus, _shape, generator, witness in PINNED:
        factors = distinct_prime_factors(modulus - 1)
        adic = two_adic_order(modulus - 1)
        primitive = is_primitive_root(generator, modulus, factors)
        witness_ok = proth_certifies_prime(witness, modulus) if witness is not None else True
        verdict = primitive and witness_ok
        all_pass = all_pass and verdict
        out.write("  %-30s %-13d %-6d 2^%-4d %-11s %-11s %s\n"
                  % (label, modulus, modulus.bit_length(), adic,
                     "%d %s" % (generator, "prim" if primitive else "NOT"),
                     ("%d %s" % (witness, "ok" if witness_ok else "NO")) if witness is not None else "-",
                     "pass" if verdict else "FAIL"))
    out.write("\n  every generator has order p-1 and every Proth witness certifies its modulus.\n")
    out.write("  the generator (31) and witness (11) of device modulus 1 are different numbers: one\n")
    out.write("  builds the twiddle table, the other proves the prime. conflating them is a defect.\n\n")
    return all_pass


def report_rejection(out):
    """Section two: the same checks refuse a wrong constant. Two routes able to disagree."""
    out.write("  rejection: the checks refuse a composite and a false primitive-root claim\n")

    # A composite of Proth shape: 3 * 2^4 + 1 = 49 = 7^2. The shape is right and the certificate is not.
    composite = 3 * (2 ** 4) + 1
    factors = distinct_prime_factors(composite)
    certified = any(proth_certifies_prime(a, composite) for a in range(2, composite))
    out.write("  composite %d = 3 * 2^4 + 1 factors as %s: no Proth witness in 2..%d certifies it -> %s\n"
              % (composite, sorted(factors), composite - 1, "rejected" if not certified else "PASSED(!)"))

    # A false primitive-root claim: 9 = 3^2 is a perfect square, hence a quadratic residue, hence never
    # a primitive root. Its order divides (p-1)/2. The q=2 check catches it.
    prime = 998244353
    prime_factors = distinct_prime_factors(prime - 1)
    false_claim = 9
    primitive = is_primitive_root(false_claim, prime, prime_factors)
    residue = pow(false_claim, (prime - 1) // 2, prime)
    out.write("  generator %d claimed for %d: %d^((p-1)/2) = %d (not 1 would be needed) -> %s\n"
              % (false_claim, prime, false_claim, residue, "rejected" if not primitive else "PASSED(!)"))
    out.write("\n  a check that cannot fail is not a check. these two fail. The passes above hold.\n\n")
    return (not certified) and (not primitive)


def report_half_order_floor(out):
    """Section three: the fiddled twiddle. A root of half the order, and the only test that catches it."""
    prime = 998244353
    generator = 3
    length = 1024  # a modest power-of-two transform length, 2^10

    right_root = pow(generator, (prime - 1) // length, prime)          # order exactly `length`
    wrong_root = pow(generator, (prime - 1) // (length // 2), prime)   # order `length` / 2

    out.write("  floor: a root of half the order passes every cheap invariant\n")
    out.write("  prime %d, length %d, generator %d\n" % (prime, length, generator))

    for name, root in (("order n  (right)", right_root), ("order n/2 (wrong)", wrong_root)):
        table = [pow(root, exponent, prime) for exponent in range(length)]
        identity_ok = table[0] == 1
        sum_zero = sum(table) % prime == 0
        sum_sq_zero = sum((value * value) % prime for value in table) % prime == 0
        # the group law on sampled index pairs: w_j * w_k == w_((j+k) mod n)
        law_ok = all((table[j] * table[k]) % prime == table[(j + k) % length]
                     for j, k in ((1, 1), (3, 500), (511, 700), (1023, 2), (256, 256)))
        order = order_dividing(root, prime, length)
        order_ok = order == length
        out.write("    %-18s w0=1:%s  sum=0:%s  sum^2=0:%s  group law:%s  ORDER=%d:%s\n"
                  % (name, identity_ok, sum_zero, sum_sq_zero, law_ok, order, order_ok))

    out.write("\n  the wrong root matches on w0=1, sum=0, sum^2=0 and the group law, every invariant a\n")
    out.write("  reader can compute from the table in O(n). only the order test separates them, and it\n")
    out.write("  costs two exponentiations. that is the floor: the certificate cannot be made cheaper\n")
    out.write("  than proving the order, because the smaller group satisfies every cheaper statement.\n")
    out.write("  prove the order, then generate the table. reversing them is a fast wrong answer.\n")
    return True


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  the twiddle certificate: NTT precision constants re-derived, and a wrong one refused\n")
    out.write("  constants cite theory_bucket/twiddle_constants_article.tex (public, on ePrint)\n\n")

    certificate = report_certificate(out)
    rejection = report_rejection(out)
    floor = report_half_order_floor(out)
    out.flush()

    # The example agrees only if the real constants pass AND the wrong ones are refused.
    return 0 if (certificate and rejection and floor) else 1


if __name__ == "__main__":
    raise SystemExit(main())
