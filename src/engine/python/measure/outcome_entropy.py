#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Conditional entropy of a game's outcome given the move that was played.
#
#   Usage:  from measure.outcome_entropy import conditional_entropy, reading
#
# H(Y|X) where X is the move out of a position and Y is the outcome the game finally reaches. It
# answers how much is still undecided after a move is chosen. A move into a position whose result is
# forced carries zero bits; a move into a position that could still go any of three ways carries up
# to log2(3).
#
# WHERE THE FLOAT ENTERS, WHICH IS THE ONE LOSSY STEP IN THE WHOLE SUBJECT
#
# Everything upstream is exact. The outcome distributions arrive as fractions.Fraction, built from
# exact integer weights over deck counts and uniform move priors. Two distributions computed by
# different routes can be compared with `==` and not with a tolerance. The logarithm is where that
# ends. log2 of a rational is irrational except at powers of two. The entropy is a float and
# carries a float's sixteen digits and no more.
#
# That boundary is drawn on purpose and it is drawn as late as possible. Every probability reported
# beside an entropy here is the exact rational, not a rounded copy of it. A reader who distrusts
# the entropy can recompute it. The quantity that gets compared between conditionings is the
# distribution; the entropy is a summary of it.
#
# WHAT UNRESOLVED DOES TO THIS
#
# A bounded search returns mass on UNRESOLVED, and that mass is not an outcome of the game. Folding
# it into the entropy would report the search's ignorance as the position's uncertainty, and the two
# are different things: one shrinks when the budget grows, the other does not. So two readings are
# returned side by side.
#
#   resolved_bits   entropy over win, draw and loss alone, renormalized over the mass that finished.
#                   This is the position's uncertainty, conditional on the game having ended inside
#                   the budget.
#   total_bits      entropy over all four categories with UNRESOLVED treated as a fourth. This is
#                   the reading including the search's own ignorance.
#
# Neither is the right one. Reporting only resolved_bits hides how little was resolved; reporting
# only total_bits lets a bigger budget look like a more certain position. Both are printed with the
# unresolved mass beside them, and a reader who wants one number can pick, knowing which they picked.

import fractions
import math

from representation.game import rules


def shannon(distribution, over=rules.OUTCOMES):
    """Entropy in bits over the named categories, renormalized to the mass they hold.

    Returns (bits, mass) where `mass` is the exact Fraction share of the distribution those
    categories cover. A mass of zero returns (None, 0) rather than nought bits, because no
    distribution at all is not the same as a certain one.
    """
    mass = sum(distribution[outcome] for outcome in over)
    if mass == 0:
        return None, fractions.Fraction(0)

    bits = 0.0
    for outcome in over:
        share = distribution[outcome] / mass
        if share > 0:
            bits -= float(share) * math.log2(float(share))
    return bits, mass


def reading(distribution):
    """Both entropies and the unresolved mass, as one record for a position or a move.

    This is the shape every example prints. Keeping it one function means the two readings are never
    accidentally computed over different category sets.
    """
    resolved_bits, resolved_mass = shannon(distribution, rules.RESOLVED)
    total_bits, _ = shannon(distribution, rules.OUTCOMES)
    return {
        "resolved_bits": resolved_bits,
        "total_bits": total_bits,
        "resolved_mass": resolved_mass,
        "unresolved_mass": distribution[rules.UNRESOLVED],
        "distribution": distribution,
    }


def move_prior(table, prior=None):
    """The probability of each move, as exact Fractions summing to one.

    Uniform over the legal moves unless a prior is supplied. Uniform is the honest default here: it
    reads nothing about the position. H(Y|X) computed against it measures what the move set makes
    available. A prior that already prefers the
    good moves lowers the entropy and reports that preference as a property of the position.
    """
    if not table:
        return []
    if prior is not None:
        total = sum(prior)
        return [fractions.Fraction(weight, 1) / total for weight in prior]
    return [fractions.Fraction(1, len(table))] * len(table)


def conditional_entropy(table, prior=None, over=rules.RESOLVED):
    """H(Y|X) in bits, X the move and Y the outcome.

    `table` is a list of (move, distribution) as `rules.best_moves` returns. The default category set
    is the resolved outcomes. This is the uncertainty about how the game ends given the move,
    conditional on it ending inside the budget. Pass rules.OUTCOMES to include the search's own
    ignorance as a fourth category.

    Moves whose branch resolved nothing contribute no term. They are counted in `covered`, returned
    beside the entropy. A reading taken over a third of the move set cannot be mistaken for one
    taken over all of it.
    """
    weights = move_prior(table, prior)
    bits = 0.0
    covered = fractions.Fraction(0)

    for (_, distribution), weight in zip(table, weights):
        moved_bits, mass = shannon(distribution, over)
        if moved_bits is None:
            continue
        bits += float(weight) * moved_bits
        covered += weight

    if covered == 0:
        return None, covered
    return bits, covered


def marginal(table, prior=None):
    """The outcome distribution with the move averaged out, which is P(Y) for this position."""
    weights = move_prior(table, prior)
    mixed = rules.empty_distribution()
    for (_, distribution), weight in zip(table, weights):
        for outcome in rules.OUTCOMES:
            mixed[outcome] += weight * distribution[outcome]
    return mixed


def information_gain(table, prior=None, over=rules.RESOLVED):
    """I(X;Y) = H(Y) - H(Y|X): how many bits the choice of move tells you about the outcome.

    Zero means the move does not matter to how the game ends -- every move leads to the same outcome
    distribution. A large value means the position is decided by this choice. It is the quantity the
    objective is reaching for when it asks which move is best: a position where one move wins and the
    rest lose has high gain, and a position where nothing can be saved has none.

    Returned as (gain, marginal_bits, conditional_bits) so a reader sees both terms rather than a
    difference they cannot check.
    """
    marginal_bits, _ = shannon(marginal(table, prior), over)
    conditional_bits, _ = conditional_entropy(table, prior, over)
    if marginal_bits is None or conditional_bits is None:
        return None, marginal_bits, conditional_bits
    return marginal_bits - conditional_bits, marginal_bits, conditional_bits


def format_reading(record, label=""):
    """One line per reading, in the column layout every stage of this subject prints."""
    resolved = record["resolved_bits"]
    total = record["total_bits"]
    distribution = record["distribution"]
    return "%-22s win=%.6f draw=%.6f loss=%.6f unres=%.6f  H_res=%s  H_all=%s" % (
        label,
        float(distribution[rules.WIN]),
        float(distribution[rules.DRAW]),
        float(distribution[rules.LOSS]),
        float(record["unresolved_mass"]),
        "  n/a " if resolved is None else "%.4f" % resolved,
        "  n/a " if total is None else "%.4f" % total,
    )
