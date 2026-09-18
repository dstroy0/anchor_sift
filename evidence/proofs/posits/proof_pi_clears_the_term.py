#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRF-x-013
#
# Proof of the posit that the exact boundary is read without touching it: pi clears the term-tower and is
# never held, from the posits section of theory/workbook (exact_inspection_and_the_cloud_clock).
#
#   Usage:  python evidence/proofs/posits/proof_pi_clears_the_term.py
#
# The posit. Draw the term as a vertical bar, a tower. Pi does not stand on the tower; it clears it. An
# alternating series encloses pi between two exact rationals that agree to more places as the term grows.
# That enclosure is the boundary, exact at every floor, and pi is strictly inside every finite bracket,
# so no finite computation ever holds pi. This is the exact boundary read without touching exactly. The
# term is the number of terms, the height the enclosure is pushed to; pi clears every finite height.
#
# The wave inverts. Each term flips the running sum from one side of pi to the other. The sum scrapes
# the boundary once per term, n scrapes for n terms. That is the same event as the transform inverting at
# its boundary, and this proof pairs with examples/0_experimental/ntt_double_transform_inverts.py the way
# proof_group_law pairs with exact_congruent_number: the demonstration shows the inversion working, this
# proof shows the boundary scraped exactly n times without the continuum being touched.
#
# Exact integers throughout. A rational is an integer pair and rationals compare by cross-multiply. No
# float enters the arithmetic. A float appears once, at the end, only to print the enclosing decimals.
# The two routes are the two fences: the sums that fall to pi from above and the sums that rise to it from
# below. A fence crossing, or a bracket of zero width, refutes the posit.


def add(left, right):
    """The exact sum of two integer-pair rationals."""
    return (left[0] * right[1] + right[0] * left[1], left[1] * right[1])


def compare(left, right):
    """-1, 0 or 1 as left is below, equal to, or above right, by cross-multiply. Denominators positive."""
    here = left[0] * right[1]
    there = right[0] * left[1]
    return (here > there) - (here < there)


def nilakantha_partials(terms):
    """Partial sums of the Nilakantha series for pi, as exact integer pairs. Consecutive sums bracket pi.

    pi = 3 + 4/(2.3.4) - 4/(4.5.6) + 4/(6.7.8) - ... . Each term flips the sum across pi. Odd-indexed
    sums fall to pi from above and even-indexed sums rise to it from below.
    """
    total = (3, 1)
    sums = [total]
    for step in range(1, terms + 1):
        base = 2 * step
        term = (4, base * (base + 1) * (base + 2))
        if step % 2 == 0:
            term = (-term[0], term[1])
        total = add(total, term)
        sums.append(total)
    return sums


def decimals(pair, places):
    """The rational floored and ceiled to `places` decimals, an exact integer bound for display only."""
    scale = 10 ** places
    low = (pair[0] * scale) // pair[1]
    high = -((-pair[0] * scale) // pair[1])
    return low / scale, high / scale


def main():
    import io
    import sys
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    terms = 40
    sums = nilakantha_partials(terms)

    # the wave inversion: every step flips the sum to the other side of the limit
    flips = 0
    for step in range(2, len(sums)):
        before = compare(sums[step - 1], sums[step - 2])
        after = compare(sums[step], sums[step - 1])
        if before != 0 and after != 0 and before != after:
            flips += 1

    upper_fence = [sums[i] for i in range(1, len(sums), 2)]   # odd index, falling from above
    lower_fence = [sums[i] for i in range(2, len(sums), 2)]   # even index, rising from below

    upper_monotone = all(compare(upper_fence[i], upper_fence[i - 1]) < 0 for i in range(1, len(upper_fence)))
    lower_monotone = all(compare(lower_fence[i], lower_fence[i - 1]) > 0 for i in range(1, len(lower_fence)))
    low = lower_fence[-1]
    high = upper_fence[-1]
    fences_hold = compare(low, high) < 0                      # the two routes never cross
    positive_width = compare(low, high) != 0                  # the bracket never collapses onto pi

    out.write("  posit: pi clears the term-tower and is never held; the exact boundary is the enclosure\n")
    out.write("  Nilakantha series, %d terms; a rational is an integer pair, compared by cross-multiply\n\n"
              % terms)
    out.write("  the wave inverts once per term: %d flips over %d terms (the n scrapes)\n"
              % (flips, terms))
    out.write("  upper fence falls to pi from above, monotone: %s\n" % upper_monotone)
    out.write("  lower fence rises to pi from below, monotone: %s\n" % lower_monotone)
    out.write("  the two fences never cross: %s ; the bracket has width, pi untouched: %s\n\n"
              % (fences_hold, positive_width))

    low_dec, _ = decimals(low, 12)
    _, high_dec = decimals(high, 12)
    out.write("  exact rational enclosure at %d terms, floored and ceiled to 12 places for display:\n" % terms)
    out.write("    lower fence: %.12f\n" % low_dec)
    out.write("    upper fence: %.12f\n" % high_dec)
    out.write("    pi is strictly between these two exact rationals and equal to neither\n\n")

    # push the term: a larger tower gives a tighter enclosure, and pi still clears it
    wide = nilakantha_partials(8)
    narrow = nilakantha_partials(80)
    wide_bracket = (wide[8], wide[7])
    narrow_bracket = (narrow[80], narrow[79])
    tighter = compare(add(narrow_bracket[1], (-narrow_bracket[0][0], narrow_bracket[0][1])),
                      add(wide_bracket[1], (-wide_bracket[0][0], wide_bracket[0][1]))) < 0

    out.write("  push the term from 8 to 80: the enclosure tightens and pi still clears it: %s\n\n" % tighter)

    ok = (flips == terms - 1) and upper_monotone and lower_monotone and fences_hold \
        and positive_width and tighter
    out.write("  the boundary is exact at every floor and pi is never held; the wave inverts once per\n")
    out.write("  term. a fence crossing or a zero-width bracket refutes the posit: %s\n"
              % ("holds" if ok else "refuted"))
    out.flush()
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
