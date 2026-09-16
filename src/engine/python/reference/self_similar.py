#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The background self-similarity allows: a value estimated from the other places that sit in its
# context.
#
#   Usage:  from reference.self_similar import similar_background, similar_residual, context_groups
#
# This is the non-local means idea, reached through the one construction the tree already uses. A
# periodic background groups the positions congruent modulo a period and averages each group; the
# group key is a POSITION. This groups the positions that carry the same surrounding CONTEXT and
# averages each group; the group key is a piece of CONTENT. Everything else is identical, and that is
# the point: non-local means and a comb filter are one operation over two different groupings, so
# nothing is ported between them.
#
# The invariant it rejects against is repetition of context. A motif that occurs many times, at
# positions with no period between them, gives many places that share one context. If the noise on the
# center of that motif sums to zero across its occurrences, the mean over the group is the clean center
# and the residual is the noise. A periodic filter cannot read this, because the occurrences have no
# period; this reads it, because it never asked for one.
#
# WHY EXACT CONTEXT, AND WHAT THAT COSTS
#
# Classic non-local means matches contexts that are merely SIMILAR, and how similar is a bandwidth h
# chosen by the author, which is a bound this tree does not allow. So the match here is exact: two
# centers share a group only when their contexts are equal as integers. That keeps the rule free of a
# tolerance, and it moves the whole cost into the floor. A context that never recurs exactly is a group
# of one and is left untouched, and a context corrupted by noise is a different context and does not
# match, so the noise must sit on the CENTER and not on the context it is read against. Where the
# context is clean and recurs, the rejection is exact; where it does not, nothing is claimed. That is
# the honest shape of the trade, stated rather than tuned away.
#
# The context excludes the center, so a value is never used to estimate itself. Positions without a
# full context on both sides are edges and are left as they are, a declared choice reported by the
# caller rather than a padding invented here.
#
# Two routes build the group mean and share no code: one keys a dictionary by the context and averages
# each bucket; the other, for each center, scans every center and averages those whose context equals
# it. They reach the same rational by different work, so their agreeing is a check and not a
# restatement. A native-C route is the natural hardening and is not claimed here.

from fractions import Fraction


def context_of(values, index, radius):
    """The `radius` values on each side of `index`, excluding the value at `index` itself.

    The content a center is read against. Returns None where a full context does not fit on both
    sides, which marks `index` as an edge the caller leaves untouched.
    """
    if (index < radius) or (index + radius >= len(values)):
        return None
    left = tuple(values[index - radius:index])
    right = tuple(values[index + 1:index + 1 + radius])
    return left + right


def context_groups(values, radius):
    """Interior centers grouped by identical context, as a map from context to the list of centers.

    An edge, whose context does not fit, is left out entirely. This is the grouping the background
    averages over, the content-keyed counterpart of the phase classes a period gives.
    """
    groups = {}
    for index in range(len(values)):
        context = context_of(values, index, radius)
        if context is not None:
            groups.setdefault(context, []).append(index)
    return groups


def similar_background(values, radius):
    """Each center replaced by the mean of the centers that share its context, exact. Route one.

    A center whose context recurs carries the mean of every center seen in that context, which under
    the one constraint that a value depends only on its context is the maximum entropy estimate of it.
    An edge, or a center whose context never recurs, keeps its own value, because a group of one has no
    other evidence and inventing some would be a background that is not drawn from the data.
    """
    groups = context_groups(values, radius)
    means = {}
    for context, members in groups.items():
        total = sum(values[index] for index in members)
        means[context] = Fraction(total, len(members))
    out = []
    for index in range(len(values)):
        context = context_of(values, index, radius)
        out.append(means[context] if (context is not None) else Fraction(values[index]))
    return out


def similar_background_scanned(values, radius):
    """The same group means, found by scanning for equal contexts instead of keying them. Route two.

    For each interior center it walks every interior center and averages those whose context equals its
    own. It shares no dictionary, no bucket and no traversal with the keyed route, so the two landing on
    the same rationals is evidence the code is right and not one identity typed twice. It costs a square
    in the length and is here to check the fast route, not to replace it.
    """
    length = len(values)
    contexts = [context_of(values, index, radius) for index in range(length)]
    out = []
    for index in range(length):
        here = contexts[index]
        if here is None:
            out.append(Fraction(values[index]))
            continue
        total = 0
        count = 0
        for other in range(length):
            if contexts[other] == here:
                total += values[other]
                count += 1
        out.append(Fraction(total, count))
    return out


def similar_residual(values, radius, background=None):
    """What each center holds above the estimate its context gives, exact.

    The reject step for noise on a repeating motif: the context-mean is the identified signal and the
    residual is the noise the context could not have predicted. Where a context recurs and its centers'
    noise sums to zero, the residual is the noise exactly and the center is recovered to the bit.
    """
    if background is None:
        background = similar_background(values, radius)
    return [Fraction(value) - back for value, back in zip(values, background)]
