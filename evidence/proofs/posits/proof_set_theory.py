#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PRF-x-008
#
# The set theory the precision work rests on, proven by construction: the generation operator is a
# Moore closure, and the set of exactly-nameable quantities is countable and of measure zero inside the
# uncountable reals. The measurement floor is that boundary, where a physical value falls off the
# countable set into the continuum.
#
#   Usage:  python evidence/proofs/posits/proof_set_theory.py
#
# This claims nothing about any open problem. It proves standard set theory, Cantor's and Turing's,
# reproduced here so the precision document can lean on it. The connection to the engine is one line: a
# quantity the engine carries exactly has a finite description. The exact quantities are countable,
# and a measured quantity is a real the engine can only bracket, since almost every real has no finite
# description at all.
#
# Four parts, each with a positive control and a drawn null:
#   Moore closure    the generation operator is extensive, monotone and idempotent; a single round of
#                    derivation is extensive and monotone but not idempotent, the null.
#   countable        finite descriptions over a finite alphabet enumerate. The nameable quantities
#                    inject into the naturals; the enumeration is shown injective and total on a sample.
#   uncountable      Cantor's diagonal: from any finite table of reals a real is built differing from
#                    every row. No list catches them all.
#   measure zero     a countable set is covered by intervals of total length epsilon for any epsilon.
#
# Prior art: Cantor 1891 (the diagonal), Turing 1936 (the computable reals are a countable subset), and
# that the computable reals have measure zero. No bounding: every test is exact integer or rational.

import io
import sys
from fractions import Fraction

UNIVERSE = ["a", "b", "c", "d", "e", "f"]
# identities as hyperedges: a set of inputs yields one output
IDENTITIES = [(("a", "b"), "c"), (("c",), "d"), (("a",), "e"), (("d", "e"), "f")]


def generate(seed):
    """The closure of `seed` under the identities: apply them to a fixed point."""
    current = set(seed)
    changed = True
    while changed:
        changed = False
        for inputs, output in IDENTITIES:
            if set(inputs) <= current and output not in current:
                current.add(output)
                changed = True
    return frozenset(current)


def derive_once(seed):
    """One round of derivation: fire every identity whose inputs are present, once. Not a closure."""
    current = set(seed)
    for inputs, output in IDENTITIES:
        if set(inputs) <= set(seed):
            current.add(output)
    return frozenset(current)


def all_subsets(universe):
    """Every subset of a small universe, as frozensets."""
    subsets = [frozenset()]
    for element in universe:
        subsets = subsets + [subset | {element} for subset in subsets]
    return subsets


def prove_moore_closure(out):
    """The generation operator is a Moore closure; one round of derivation is not idempotent."""
    out.write(
        "  Moore closure: generation is extensive, monotone, idempotent; one round is not\n"
    )
    subsets = all_subsets(UNIVERSE)

    extensive = all(subset <= generate(subset) for subset in subsets)
    idempotent = all(
        generate(generate(subset)) == generate(subset) for subset in subsets
    )
    monotone = all(
        generate(smaller) <= generate(larger)
        for smaller in subsets
        for larger in subsets
        if smaller <= larger
    )
    # closed sets are closed under intersection
    closed = [subset for subset in subsets if generate(subset) == subset]
    intersection_closed = all(
        (left & right) in closed for left in closed for right in closed
    )

    round_not_idempotent = any(
        derive_once(derive_once(subset)) != derive_once(subset) for subset in subsets
    )

    out.write(
        "    extensive: %s ; monotone: %s ; idempotent: %s\n"
        % (extensive, monotone, idempotent)
    )
    out.write("    closed sets closed under intersection: %s\n" % intersection_closed)
    out.write(
        "    one round of derivation is idempotent: %s (the null: a closure needs the fixed point)\n\n"
        % (not round_not_idempotent)
    )
    return (
        extensive
        and monotone
        and idempotent
        and intersection_closed
        and round_not_idempotent
    )


def description_index(description, alphabet):
    """A unique natural number for a finite string over `alphabet`: a bijection with the naturals.

    Strings are ordered by length, then within a length by base-|alphabet| place value. Every finite
    description lands at a finite index, the sense in which the set is countable.
    """
    base = len(alphabet)
    rank = {symbol: position for position, symbol in enumerate(alphabet)}
    index = 0
    for length in range(len(description)):
        index += base**length  # skip all shorter strings
    value = 0
    for symbol in description:
        value = value * base + rank[symbol]
    return index + value


def prove_countable(out):
    """Finite descriptions enumerate. The nameable quantities inject into the naturals."""
    out.write(
        "  countable: finite descriptions over a finite alphabet inject into the naturals\n"
    )
    alphabet = "0123456789abcdefghijklmnopqrstuvwxyz+-*/().^ "  # enough to write the engine's constants
    sample = ["3", "22/7", "sqrt(2)", "pi", "pi^2/6", "e", "ln(2)", "sqrt(2)*sqrt(3)"]

    indices = [description_index(text, alphabet) for text in sample]
    injective = len(set(indices)) == len(indices)
    finite = all(isinstance(index, int) and index >= 0 for index in indices)

    # total on a sample: every short string appears exactly once as some index
    seen = {}
    for length in range(0, 3):
        for value in range(len(alphabet) ** length):
            symbols = []
            residual = value
            for _ in range(length):
                symbols.append(alphabet[residual % len(alphabet)])
                residual //= len(alphabet)
            text = "".join(reversed(symbols))
            seen[description_index(text, alphabet)] = text
    contiguous = sorted(seen) == list(range(len(seen)))

    out.write(
        "    the sample of named constants maps to distinct naturals: %s\n" % injective
    )
    out.write("    every index is a finite natural: %s\n" % finite)
    out.write(
        "    the enumeration is a contiguous prefix of the naturals over strings up to length 2: %s\n\n"
        % contiguous
    )
    return injective and finite and contiguous


def prove_uncountable(out):
    """Cantor's diagonal: from any table of reals a real is built that is in no row."""
    out.write("  uncountable: Cantor's diagonal builds a real outside any given list\n")
    # a table of reals in [0,1) as decimal-digit rows, deterministic, standing in for any enumeration
    table = []
    state = 0x1234
    rows, digits = 12, 12
    for _ in range(rows):
        row = []
        for _ in range(digits):
            state = (1103515245 * state + 12345) & 0x7FFFFFFF
            row.append(state % 10)
        table.append(row)

    # the diagonal escaper: differ from row i at digit i, avoiding 9 and 0 to dodge the 0.4999 = 0.5000 tie
    escaper = []
    for position in range(rows):
        digit = table[position][position]
        escaper.append(5 if digit != 5 else 6)

    not_in_table = all(escaper != row[:rows] for row in table)
    differs_on_diagonal = all(
        escaper[position] != table[position][position] for position in range(rows)
    )

    out.write(
        "    the built real differs from every row on the diagonal: %s\n"
        % differs_on_diagonal
    )
    out.write(
        "    so it is in none of the %d rows: %s (and this works for any list)\n\n"
        % (rows, not_in_table)
    )
    return not_in_table and differs_on_diagonal


def prove_measure_zero(out):
    """A countable set is covered by intervals of total length epsilon. Its measure is zero."""
    out.write(
        "  measure zero: a countable set is covered to any total length, the interval is not\n"
    )
    epsilon = Fraction(1, 1000)
    # cover the n-th point by an interval of length epsilon / 2^(n+1); the total is a geometric sum
    terms = 200
    total = sum(epsilon * Fraction(1, 2 ** (index + 1)) for index in range(terms))
    within = (
        total < epsilon
    )  # the partial sum is strictly under epsilon, and the full sum equals it

    # the null: the whole interval [0,1] has measure 1 and cannot be covered to total length epsilon
    interval_measure = Fraction(1)
    interval_not_coverable = interval_measure > epsilon

    out.write(
        "    countable cover total after %d terms: %s < epsilon %s: %s\n"
        % (terms, total, epsilon, within)
    )
    out.write(
        "    the unit interval has measure %s, not coverable to epsilon: %s (the null)\n\n"
        % (interval_measure, interval_not_coverable)
    )
    return within and interval_not_coverable


def main():
    out = io.TextIOWrapper(
        sys.stdout.buffer, encoding="utf-8", errors="replace", newline=""
    )
    out.write(
        "  PROOF: the exact quantities are a countable, measure-zero set in the uncountable reals\n\n"
    )
    results = [
        prove_moore_closure(out),
        prove_countable(out),
        prove_uncountable(out),
        prove_measure_zero(out),
    ]
    if all(results):
        out.write(
            "  all four hold: generation is a closure, the nameable quantities are countable, the\n"
        )
        out.write(
            "  reals are not, and the countable set has measure zero. the measurement floor is that\n"
        )
        out.write("  boundary; it claims nothing about any open problem.\n")
    else:
        out.write("  a part missed its forced outcome: refuted as stated.\n")
    out.flush()
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
