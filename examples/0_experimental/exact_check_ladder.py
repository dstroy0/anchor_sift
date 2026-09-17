#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-011
#
# A ladder of error-detecting and error-correcting checks, each catching a fault the one below it
# misses, every check on exact integers or exact bits, where a detection is real and never a rounding.
#
#   Usage:  python examples/0_experimental/exact_check_ladder.py
#
# This reads no corpus, so it sits in 0_experimental: arithmetic results shown working, not a stage
# reading. It takes four checks the coding-theory and arithmetic fields already use and runs them one
# above the other. Each has a floor, a fault it cannot see, and the next check up the ladder sees that
# fault. The point of the ladder is the same as the point of the whole engine: a necessary condition
# loses nothing, and where it is blind, a second condition is added, never a tolerance.
#
#   casting out nines   n mod 9, from the digit sum. Catches a changed digit. Floor: a transposition of
#                       two digits leaves the digit sum, so it is missed.
#   mod eleven          the ISBN-10 weighted sum mod 11. Catches the transposition nines misses, and
#                       every single-digit error. Floor: it detects, it does not locate or correct.
#   cyclic redundancy   a polynomial remainder over GF(2). Catches a burst of bit errors up to the
#                       generator's degree, which a digit check reads as one changed digit at best.
#   Hamming (7,4)       three parity bits over four data bits. Catches AND corrects a single bit error,
#                       naming its position. Floor: two bit errors defeat it, the reason the residue
#                       code beside this file adds redundancy for more.
#
# Positive control: clean data passes every check. Drawn null: each check is shown the exact fault it
# catches and the exact fault it misses. No bounding: every check is an integer or bit comparison, and
# the faults are constructed, not sampled for a threshold.

import io
import sys


def cast_out_nines(digits):
    """n mod 9 from a digit list, the value the check stores. Equal to the number modulo nine."""
    return sum(digits) % 9


def mod_eleven_ok(digits):
    """The ISBN-10 weighted check: sum of (position weight) times digit is 0 modulo 11.

    Weights run high to low, ten down to one, over ten digits. This detects every single-digit error
    and every transposition of two digits, because each weight is distinct modulo 11.
    """
    weighted = sum((10 - index) * digit for index, digit in enumerate(digits))
    return weighted % 11 == 0


def crc_remainder(bits, generator):
    """The remainder of the bit polynomial divided by `generator` over GF(2), the cyclic redundancy check.

    Both operands are bit lists, high order first. Division is repeated exclusive-or, the field's own
    subtraction. A burst of errors shorter than the generator changes the remainder.
    """
    work = list(bits) + [0] * (len(generator) - 1)
    for position in range(len(bits)):
        if work[position] == 1:
            for offset in range(len(generator)):
                work[position + offset] ^= generator[offset]
    return work[len(bits):]


HAMMING_PARITY = {1: (1, 3, 5, 7), 2: (2, 3, 6, 7), 4: (4, 5, 6, 7)}


def hamming_encode(data):
    """Four data bits to a seven-bit Hamming word, parity at positions 1, 2, 4 (one-indexed)."""
    word = [0] * 8  # index 0 unused, positions 1..7
    for slot, position in zip(data, (3, 5, 6, 7)):
        word[position] = slot
    for parity, covered in HAMMING_PARITY.items():
        word[parity] = 0
        for position in covered:
            word[parity] ^= word[position]
    return word[1:]


def hamming_syndrome(word):
    """The one-indexed position of a single bit error, or 0 when the word is clean."""
    indexed = [0] + list(word)  # shift to one-indexed
    syndrome = 0
    for parity, covered in HAMMING_PARITY.items():
        check = 0
        for position in covered:
            check ^= indexed[position]
        if check != 0:
            syndrome += parity
    return syndrome


def report_nines(out):
    """Casting out nines catches a changed digit and misses a transposition."""
    out.write("  casting out nines: catches a changed digit, misses a transposition\n")
    digits = [4, 1, 5, 9, 2, 6, 5, 3, 5, 8]
    check = cast_out_nines(digits)

    changed = list(digits)
    changed[2] = (changed[2] + 3) % 10
    caught_change = cast_out_nines(changed) != check

    swapped = list(digits)
    swapped[0], swapped[1] = swapped[1], swapped[0]
    caught_swap = cast_out_nines(swapped) != check

    out.write("  changed digit detected: %s ; transposition detected: %s (the floor)\n\n"
              % (caught_change, caught_swap))
    return caught_change and not caught_swap


def report_mod_eleven(out):
    """Mod eleven catches the transposition nines misses."""
    out.write("  mod eleven: catches the transposition, and every single-digit error\n")
    # a digit string whose weighted sum is already 0 modulo 11
    digits = [0, 3, 0, 6, 4, 0, 6, 1, 5, 2]
    base_ok = mod_eleven_ok(digits)

    swapped = list(digits)
    swapped[0], swapped[1] = swapped[1], swapped[0]
    caught_swap = base_ok and not mod_eleven_ok(swapped)

    changed = list(digits)
    changed[4] = (changed[4] + 1) % 10
    caught_change = base_ok and not mod_eleven_ok(changed)

    out.write("  clean word valid: %s ; transposition detected: %s ; single-digit detected: %s\n\n"
              % (base_ok, caught_swap, caught_change))
    return base_ok and caught_swap and caught_change


def report_crc(out):
    """A cyclic redundancy check catches a burst of bit errors."""
    out.write("  cyclic redundancy check: catches a burst of bit errors\n")
    generator = [1, 0, 1, 1]  # x^3 + x + 1, degree three
    data = [1, 1, 0, 1, 0, 0, 1, 1, 1, 0]
    check = crc_remainder(data, generator)

    burst = list(data)
    for position in (4, 5, 6):  # a three-bit burst
        burst[position] ^= 1
    caught = crc_remainder(burst, generator) != check

    out.write("  generator x^3+x+1, remainder %s ; three-bit burst detected: %s\n\n" % (check, caught))
    return caught


def report_hamming(out):
    """Hamming (7,4) corrects a single bit error, and is defeated by two. The stated floor."""
    out.write("  Hamming (7,4): corrects a single bit error, defeated by two\n")
    data = [1, 0, 1, 1]
    word = hamming_encode(data)
    clean_syndrome = hamming_syndrome(word)

    one_error = list(word)
    one_error[4] ^= 1  # flip position 5 (one-indexed)
    located = hamming_syndrome(one_error)
    corrected = list(one_error)
    if located != 0:
        corrected[located - 1] ^= 1
    single_fixed = corrected == word

    two_errors = list(word)
    two_errors[4] ^= 1
    two_errors[6] ^= 1
    double_syndrome = hamming_syndrome(two_errors)
    # two errors give a nonzero syndrome that points at the wrong single position: detected, mis-located
    mis_locates = double_syndrome != 0 and (double_syndrome != 5)

    out.write("  clean syndrome %d ; single error located at %d and corrected: %s\n"
              % (clean_syndrome, located, single_fixed))
    out.write("  two errors give syndrome %d, a wrong single position: the floor, and the reason a\n"
              % double_syndrome)
    out.write("  residue code adds more redundancy (see exact_residue_code_detects_uncertainty.py)\n\n")
    return clean_syndrome == 0 and single_fixed and mis_locates


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  a ladder of exact checks, each catching what the one below it misses\n\n")
    nines = report_nines(out)
    eleven = report_mod_eleven(out)
    crc = report_crc(out)
    hamming = report_hamming(out)
    out.write("  each check is exact, so every detection above is a real fault and never an artifact of\n")
    out.write("  rounding. each floor is caught by the check above it, and more checks catch more.\n")
    out.flush()
    return 0 if (nines and eleven and crc and hamming) else 1


if __name__ == "__main__":
    raise SystemExit(main())
