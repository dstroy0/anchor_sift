import os
import random
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HEADER = os.path.join(ROOT, "engine", "transform_constants.h")

PRIMES = 10
TWO_POWER = 20
ROOT_ORDER = 1024
LIMBS = 9
LIMB_BITS = 32
RESIDUAL_BITS = 285

def power(base, exponent, modulus):
    return pow(base, exponent, modulus)

def miller_rabin(candidate):
    for small in (2, 7, 61):
        if candidate == small:
            return True
        if candidate % small == 0:
            return False
    odd, twos = candidate - 1, 0
    while odd % 2 == 0:
        odd //= 2
        twos += 1
    for base in (2, 7, 61):
        witness = power(base, odd, candidate)
        if witness in (1, candidate - 1):
            continue
        for _ in range(twos - 1):
            witness = witness * witness % candidate
            if witness == candidate - 1:
                break
        else:
            return False
    return True

def trial_division(candidate):
    if candidate % 2 == 0:
        return candidate == 2
    divisor = 3
    while divisor * divisor <= candidate:
        if candidate % divisor == 0:
            return False
        divisor += 2
    return True

def prime_factors(number):
    factors, divisor = [], 2
    while divisor * divisor <= number:
        if number % divisor == 0:
            factors.append(divisor)
            while number % divisor == 0:
                number //= divisor
        divisor += 1
    if number > 1:
        factors.append(number)
    return factors

def primitive_root(prime):
    factors = prime_factors(prime - 1)
    for candidate in range(2, prime):
        if all(power(candidate, (prime - 1) // factor, prime) != 1 for factor in factors):
            return candidate
    raise SystemExit("no primitive root for %d" % prime)

def fail(message):
    sys.stderr.write("  emit refused: %s\n" % message)
    raise SystemExit(1)

def main():
    primes = []
    for multiple in range((1 << (30 - TWO_POWER)) - 1, (1 << (29 - TWO_POWER)) - 1, -1):
        candidate = (multiple << TWO_POWER) + 1
        if candidate <= (1 << 29):
            continue
        first, second = miller_rabin(candidate), trial_division(candidate)
        if first != second:
            fail("the two primality routes disagree on %d" % candidate)
        if first:
            primes.append(candidate)
        if len(primes) == PRIMES:
            break
    if len(primes) != PRIMES:
        fail("fewer than %d primes found" % PRIMES)
    modulus = 1
    for prime in primes:
        modulus *= prime
    if modulus <= (1 << (RESIDUAL_BITS + 1)):
        fail("the primes' product does not pass twice the residual's magnitude")

    barretts, psis, generators = [], [], []
    for prime in primes:
        barretts.append((1 << 62) // prime)
        generator = primitive_root(prime)
        psi = power(generator, (prime - 1) // ROOT_ORDER, prime)
        if power(psi, ROOT_ORDER, prime) != 1 or power(psi, ROOT_ORDER // 2, prime) != prime - 1:
            fail("psi is not a primitive %d-th root modulo %d" % (ROOT_ORDER, prime))
        generators.append(generator)
        psis.append(psi)

    coefficients, inverses = [], []
    for index, prime in enumerate(primes):
        row, before = [], 1
        for digit in range(PRIMES):
            row.append(before % prime if digit < index else 0)
            if digit < index:
                before = before * primes[digit] % prime
        coefficients.append(row)
        inverses.append(power(before, prime - 2, prime) if index > 0 else 1)
    half = (modulus - 1) // 2
    half_digits, rest = [], half
    for prime in primes:
        half_digits.append(rest % prime)
        rest //= prime
    modulus_limbs = [(modulus >> (LIMB_BITS * limb)) & 0xFFFFFFFF for limb in range(LIMBS)]

    generator = random.Random(20260917)
    samples = [0, 1, -1, (1 << RESIDUAL_BITS) - 1, -((1 << RESIDUAL_BITS) - 1)]
    samples += [generator.getrandbits(RESIDUAL_BITS) - (1 << (RESIDUAL_BITS - 1)) for _ in range(2000)]
    width = 1 << (LIMB_BITS * LIMBS)
    for value in samples:
        residues = [value % prime for prime in primes]
        digits = [residues[0]]
        for index in range(1, PRIMES):
            prime = primes[index]
            partial = sum(digits[digit] * coefficients[index][digit] for digit in range(index)) % prime
            if index == 1:
                partial = digits[0] % prime
            else:
                partial = (digits[0] + sum(digits[digit] * coefficients[index][digit] for digit in range(1, index))) % prime
            digits.append((residues[index] - partial) * inverses[index] % prime)
        negative = False
        for index in range(PRIMES - 1, -1, -1):
            if digits[index] != half_digits[index]:
                negative = digits[index] > half_digits[index]
                break
        folded = 0
        for index in range(PRIMES - 1, -1, -1):
            folded = folded * primes[index] + digits[index]
        mixed = (folded - (modulus if negative else 0)) % width
        direct = sum(residues[index] * (modulus // primes[index]) * power(modulus // primes[index] % primes[index], primes[index] - 2, primes[index])
                     for index in range(PRIMES)) % modulus
        if direct > half:
            direct -= modulus
        if mixed != value % width or direct != value:
            fail("the two join routes disagree on %d" % value)

    lines = []
    lines.append("/* cell_tracking - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>")
    lines.append(" * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational")
    lines.append(" *")
    lines.append(" * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a")
    lines.append(" * negotiated commercial licensing contract or an educator's license issued to you personally.")
    lines.append(" */")
    lines.append("/**")
    lines.append(" * @file transform_constants.h")
    lines.append(" * @brief The transform's seed constants, GENERATED by maint/emit_transform_constants.py; do not edit.")
    lines.append(" * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>")
    lines.append(" * @date 2026-09-17")
    lines.append(" *")
    lines.append(" * Primes proved twice (Miller-Rabin and trial division), psi checked of order %d, and the join constants" % ROOT_ORDER)
    lines.append(" * checked against the direct Chinese remainder sum on %d signed values. The device expands these seeds" % len(samples))
    lines.append(" * into its tables with warp kernels.")
    lines.append(" */")
    lines.append("#ifndef TRANSFORM_CONSTANTS_H")
    lines.append("#define TRANSFORM_CONSTANTS_H")
    lines.append("")
    lines.append("/** @brief Primes, and the order of the root of unity psi each carries. */")
    lines.append("#define TRANSFORM_PRIMES %du" % PRIMES)
    lines.append("#define TRANSFORM_ROOT_ORDER %du" % ROOT_ORDER)
    lines.append("")

    def row(name, values, brief):
        lines.append("/** @brief %s */" % brief)
        lines.append("#define %s \\" % name)
        chunks = [", ".join("%du" % value for value in values[start:start + 5]) for start in range(0, len(values), 5)]
        for index, chunk in enumerate(chunks):
            lines.append("    %s%s \\" % (chunk, "," if index + 1 < len(chunks) else ""))
        lines.append("")

    row("TRANSFORM_PRIME_VALUES", primes, "The primes, c 2^20 + 1 between 2^29 and 2^30, from the top.")
    row("TRANSFORM_BARRETT_LOW", [value & 0xFFFFFFFF for value in barretts], "floor(2^62 / prime), its low 32 bits.")
    row("TRANSFORM_BARRETT_HIGH", [value >> 32 for value in barretts], "floor(2^62 / prime), its high 32 bits.")
    row("TRANSFORM_PSI_VALUES", psis, "psi, a primitive %d-th root of unity per prime." % ROOT_ORDER)
    row("TRANSFORM_COEFFICIENT_VALUES", [value for row_values in coefficients for value in row_values],
        "Per prime i and digit j below i, the product of the primes before j modulo prime i; zero elsewhere.")
    row("TRANSFORM_INVERSE_VALUES", inverses, "Per prime i, the product of the primes before i, inverted modulo prime i.")
    row("TRANSFORM_HALF_VALUES", half_digits, "The mixed radix digits of (modulus - 1) / 2.")
    row("TRANSFORM_MODULUS_VALUES", modulus_limbs, "The modulus modulo 2^288, nine limbs, least significant first.")
    lines.append("#endif /* TRANSFORM_CONSTANTS_H */")
    text = "\n".join(lines) + "\n"
    with open(HEADER, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    print("  wrote %s: %d primes, generators %s" % (HEADER, PRIMES, generators))

if __name__ == "__main__":
    main()
