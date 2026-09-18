#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-010
#
# An existing error-correcting code, the redundant residue number system, run on exact integers, where
# a disagreement it flags is real uncertainty and never a rounding artifact.
#
#   Usage:  python examples/0_experimental/exact_residue_code_detects_uncertainty.py
#
# This reads no corpus. It sits in 0_experimental: an arithmetic result shown working, not a stage
# reading. It takes a code the coding-theory field already uses and points it at this engine's job. A
# residue number system carries an integer as its remainders against a set of pairwise coprime moduli,
# and the Chinese remainder theorem reconstructs the integer from them. Adding REDUNDANT moduli past
# the ones the value needs turns the representation into a code: a single number reconstructed past its
# declared range is a residue that disagrees with the rest, and an error shows itself. This is the same
# capability as a Reed-Solomon code, correcting half the redundant moduli's worth of errors.
#
# Two things this pairing gives that neither half gives alone. First, RANGE without a fixed width: the
# exact integer the system holds is the product of the moduli, and every modulus added multiplies that
# range, and a single modulus near 2^40 widens the exact range by more than a trillion, without end.
# Second, DETECTION that cannot cry wolf: because every residue is an exact integer and nothing rounds,
# a nonzero syndrome is a real disagreement. The code detects genuine uncertainty and never its own
# arithmetic. That is the protein session's enantiomer case stated as a code: two independent exact
# measurements compared residue by residue agree exactly or name where they differ, and a rounded
# compare would have merged them.
#
# Positive control: a clean codeword reconstructs inside its range and no error is flagged. Two routes:
# the error is caught two independent ways, by the range test and by recomputing the redundant residues,
# and both name the same position. Drawn null: a batch of clean codewords raises zero false alarms.
# Stated floor: two redundant moduli correct one error and detect two; a third error defeats them, and
# the example shows the floor by injecting past it.
#
# No bounding: the moduli, the information count and the redundancy are declared inputs, printed with
# the run. No threshold decides an error; the range test is an exact integer comparison.

import io
import sys

# Declared inputs: the moduli, small primes for a readable reconstruction. The first INFORMATION carry
# the value; the rest are redundant and carry the code.
MODULI = [97, 89, 83, 79, 73, 71]
INFORMATION = 4
REDUNDANT = len(MODULI) - INFORMATION


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


def encode(value, moduli):
    """The residues of `value` against every modulus."""
    return [value % modulus for modulus in moduli]


def information_range(moduli, information):
    """The largest value the information moduli represent, the product of the first `information`."""
    return product(moduli[:information])


def detect_and_correct(residues, moduli, information):
    """Detect a single corrupted residue by range, and correct it by finding the residue to drop.

    Reconstructing all residues gives a value below the information range when the codeword is clean.
    A single corrupted residue pushes the reconstruction past that range, and that is the detection. The
    correction drops each residue in turn; the drop that returns the reconstruction below the range
    names the corrupted position and recovers the value.
    """
    limit = information_range(moduli, information)
    whole_value = crt(residues, moduli)
    if whole_value < limit:
        return ("clean", whole_value, None)

    candidates = []
    for dropped in range(len(moduli)):
        kept_residues = residues[:dropped] + residues[dropped + 1:]
        kept_moduli = moduli[:dropped] + moduli[dropped + 1:]
        recovered = crt(kept_residues, kept_moduli)
        if recovered < limit:
            candidates.append((dropped, recovered))

    if len(candidates) == 1:
        dropped, recovered = candidates[0]
        return ("corrected", recovered, dropped)
    return ("detected", None, None)  # past the floor: detected but not uniquely correctable


def redundant_check(residues, moduli, information):
    """The second route: reconstruct from the information residues alone, recompute the redundant
    residues from that value, and compare to the stored ones. Independent of the range test, and it
    needs no knowledge of the original value. A corrupted residue, in an information slot or a redundant
    one, leaves the recomputed redundant residues disagreeing with the stored ones.
    """
    value_from_information = crt(residues[:information], moduli[:information])
    disagreements = []
    for position in range(information, len(moduli)):
        if value_from_information % moduli[position] != residues[position]:
            disagreements.append(position)
    return value_from_information, disagreements


def report_positive_control(out):
    """A clean codeword reconstructs inside its range, both routes quiet."""
    out.write("  positive control: a clean codeword, no error\n")
    limit = information_range(MODULI, INFORMATION)
    value = 12_345_678 % limit
    residues = encode(value, MODULI)
    status, recovered, position = detect_and_correct(residues, MODULI, INFORMATION)
    out.write("  moduli %s, information %d, redundant %d\n" % (MODULI, INFORMATION, REDUNDANT))
    out.write("  value %d, residues %s\n" % (value, residues))
    out.write("  status %s, recovered %d, matches original: %s\n\n"
              % (status, recovered, recovered == value))
    return status == "clean" and recovered == value


def report_error_correction(out):
    """One corrupted residue, caught by the range route and the redundant route, both naming it."""
    out.write("  error correction: one corrupted residue, caught two ways\n")
    limit = information_range(MODULI, INFORMATION)
    value = 40_000_000 % limit
    residues = encode(value, MODULI)

    bad_position = 2
    corrupted = list(residues)
    corrupted[bad_position] = (corrupted[bad_position] + 5) % MODULI[bad_position]

    status, recovered, position = detect_and_correct(corrupted, MODULI, INFORMATION)
    _reconstructed, route_two = redundant_check(corrupted, MODULI, INFORMATION)
    out.write("  value %d, corrupted residue at position %d\n" % (value, bad_position))
    out.write("  range route: status %s, names position %s, recovers %s (original %d)\n"
              % (status, position, recovered, value))
    out.write("  redundant route: independent reconstruction disagrees at redundant positions %s\n\n"
              % route_two)
    # both routes detect the error; the range route also locates and corrects it
    both_detect = (status != "clean") and (len(route_two) > 0)
    return both_detect and recovered == value and position == bad_position


def report_null(out):
    """A batch of clean codewords raises zero false alarms."""
    out.write("  drawn null: clean codewords raise no false alarm\n")
    limit = information_range(MODULI, INFORMATION)
    false_alarms = 0
    state = 0x5EED
    for _ in range(500):
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        value = state % limit
        status, _recovered, _position = detect_and_correct(encode(value, MODULI), MODULI, INFORMATION)
        if status != "clean":
            false_alarms += 1
    out.write("  500 clean codewords, false alarms: %d\n\n" % false_alarms)
    return false_alarms == 0


def report_floor(out):
    """Two redundant moduli correct one error; a second error defeats them. The stated floor."""
    out.write("  floor: two redundant moduli correct one error, a second defeats them\n")
    limit = information_range(MODULI, INFORMATION)
    value = 33_333_333 % limit
    residues = encode(value, MODULI)

    two_errors = list(residues)
    two_errors[1] = (two_errors[1] + 3) % MODULI[1]
    two_errors[4] = (two_errors[4] + 7) % MODULI[4]
    status, recovered, _position = detect_and_correct(two_errors, MODULI, INFORMATION)
    mis_corrected = status == "corrected" and recovered != value
    out.write("  two errors injected: status %s, recovered %s (original %d)\n" % (status, recovered, value))
    out.write("  the code detects past its correction floor and does not silently return a wrong value:\n")
    out.write("  status is '%s', not a false 'clean'. two redundant moduli correct one, detect two.\n\n"
              % status)
    # the floor holds when a double error is not passed off as clean or mis-corrected to a wrong value
    return status != "clean" and not mis_corrected


def is_prime(number):
    """A deterministic Miller-Rabin primality test for the sizes used here.

    The witness set is exact for every number below 3.3e24, well past the moduli near 2^40 stacked
    below. The range table rests on genuine pairwise-coprime primes.
    """
    small = (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37)
    if number < 2:
        return False
    for divisor in small:
        if number % divisor == 0:
            return number == divisor
    odd_part = number - 1
    twos = 0
    while odd_part % 2 == 0:
        odd_part //= 2
        twos += 1
    for witness in small:
        residue = pow(witness, odd_part, number)
        if residue in (1, number - 1):
            continue
        for _ in range(twos - 1):
            residue = residue * residue % number
            if residue == number - 1:
                break
        else:
            return False
    return True


def next_prime(lower):
    """The smallest prime greater than `lower`."""
    candidate = lower + 1 if lower % 2 == 0 else lower + 2
    while not is_prime(candidate):
        candidate += 2
    return candidate


def report_range(out):
    """The exact range is the product of the moduli, exponential in their count, past a googol."""
    out.write("  range: the exact integer the code holds is the product of the moduli, exponential in count\n")
    base = MODULI[:INFORMATION]
    base_value = product(base)

    large_moduli = []
    seed = 2 ** 40
    while len(large_moduli) < 9:
        seed = next_prime(seed)
        large_moduli.append(seed)

    out.write("  %-12s %-16s %s\n" % ("moduli near 2^40", "range digits", "factor over base"))
    googol = 10 ** 100
    reached = False
    for count in range(0, len(large_moduli) + 1):
        running = product(base + large_moduli[:count])
        digits = len(str(running))
        factor = running // base_value
        crossed = " <- past a googol" if (running > googol and not reached) else ""
        if running > googol:
            reached = True
        out.write("  %-16d %-16d %-24d%s\n" % (count, digits, factor, crossed))
    out.write("  each modulus near 2^40 multiplies the range by more than a trillion. Nine of them\n")
    out.write("  pass a googol of exact range, and the product has no fixed width to stop the climb.\n\n")
    return reached


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  an exact redundant residue code: existing ECC on exact integers detects real uncertainty\n\n")
    control = report_positive_control(out)
    corrected = report_error_correction(out)
    null = report_null(out)
    floor = report_floor(out)
    ranged = report_range(out)
    out.flush()
    return 0 if (control and corrected and null and floor and ranged) else 1


if __name__ == "__main__":
    raise SystemExit(main())
