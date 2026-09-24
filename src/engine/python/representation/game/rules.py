#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The protocol every game backend satisfies, and the enumeration that reads it.
#
#   Usage:  from representation.game import rules
#           dist = rules.outcome_distribution(backend, state, rules.Budget(plies=6), rules.NULL)
#
# A backend is six calls. The enumeration below never learns which game it is reading, the
# only reason one measurement can cover blackjack and chess at all:
#
#   initial()          the opening position
#   to_move(state)     which player chooses here: PLAYER_ONE, PLAYER_TWO, or CHANCE
#   moves(state)       legal moves out of the position, as a list
#   weights(state)     for a CHANCE node, the weight of each move in moves(), as exact integers
#   apply(state, move) the position the move reaches
#   verdict(state)     WIN, LOSS, DRAW from PLAYER_ONE's side, or None where the game continues
#
# WHAT THIS DOES NOT DO, AND WHY THAT IS THE POINT
#
# A search that runs out of depth has to do something with the positions it never resolved. The
# usual answer is an evaluation function: score the unresolved position and fold that score into the
# result. That converts a bound on the search into a number that looks like an outcome, and from
# there nothing downstream can tell the two apart.
#
# This does not do that. Unresolved mass is carried as its own outcome, UNRESOLVED, and it is never
# redistributed over win, loss and draw. A distribution that reads 0.31 win / 0.12 loss / 0.00 draw
# / 0.57 unresolved is saying it does not know what happens in most of this branch, and it says so
# in the number and not in a caveat. The standing discipline in this tree is that bounding is
# not allowed -- no judgment-picked tolerances or parameters -- and a search depth is a bound. It is
# allowed here only because it is a declared input that is reported with the result and visible in
# the distribution it produced.
#
# This is the same failure crystallography records: a 0.25 angstrom grid applied on the way in
# silently became the answer, and every number downstream carried the grid instead of the deposit.
# An evaluation function is that grid.

import fractions
import random

# Outcomes, from PLAYER_ONE's side. PLAYER_TWO reads the same distribution mirrored.
WIN = "win"
LOSS = "loss"
DRAW = "draw"

# The fourth outcome, and the honest one. The search stopped here and the game had not ended.
UNRESOLVED = "unresolved"

OUTCOMES = (WIN, DRAW, LOSS, UNRESOLVED)
RESOLVED = (WIN, DRAW, LOSS)

PLAYER_ONE = 0
PLAYER_TWO = 1
CHANCE = 2

# What a resolved outcome is worth to PLAYER_ONE when a policy has to order two branches. A draw is
# half a win because that is the convention the games themselves score by, not because it was tuned.
# UNRESOLVED is worth nothing. A policy prefers a branch it can see the end of over one it
# cannot, the conservative direction.
SCORE = {
    WIN: fractions.Fraction(1),
    DRAW: fractions.Fraction(1, 2),
    LOSS: fractions.Fraction(0),
    UNRESOLVED: fractions.Fraction(0),
}

# How a player chooses among its legal moves.
#
#   UNIFORM   every legal move with equal probability. Reads nothing about the position.
#   BEST      the move maximizing PLAYER_ONE's expected score. Both players can be given this.
#   WORST     the move minimizing PLAYER_ONE's expected score.
UNIFORM = "uniform"
BEST = "best"
WORST = "worst"


class Budget(object):
    """The declared search bound, carried with the result so it is never lost from the number.

    `plies` is how many further moves the enumeration will make before it gives up and returns
    UNRESOLVED. `nodes` caps total positions visited, keeping an unexpectedly wide game from
    running unbounded; exhausting it also returns UNRESOLVED and not a guess.

    Both are inputs of the measurement and both are printed alongside it. A result computed at
    plies=4 and one computed at plies=8 are different measurements of the same position and this is
    what tells them apart.
    """

    def __init__(self, plies, nodes=400000):
        self.plies = plies
        self.nodes = nodes
        self.visited = 0

    def spend(self):
        """Charge one position. False once the node cap is gone."""
        self.visited += 1
        return self.visited <= self.nodes

    def describe(self):
        return "plies=%d nodes=%d visited=%d" % (self.plies, self.nodes, self.visited)


class Conditioning(object):
    """Which quantity is being measured, named, a reader cannot mistake one for another.

    This exists because the objective asks for survivorship pruning -- prune the opponent's paths
    and maximize our own -- and pruning changes what the distribution means. It stops being
    P(outcome | our move) and becomes P(outcome | our move, the opponent plays into our line). Those
    are different quantities. Reporting the second under the name of the first is the most likely
    way for this work to be quietly wrong. The name travels with the number.
    """

    def __init__(self, name, hero_policy, foe_policy, statement):
        self.name = name
        self.hero_policy = hero_policy
        self.foe_policy = foe_policy
        self.statement = statement

    def __repr__(self):
        return "<Conditioning %s>" % self.name


# The three conditionings this work reports. They bracket the truth: whatever the opponent actually
# does, the hero's real prospects sit between ADVERSARY and SURVIVOR, and NULL is the reading a
# player who knows nothing would get.
NULL = Conditioning(
    "null",
    UNIFORM,
    UNIFORM,
    "P(outcome | move), both sides moving uniformly at random",
)
SURVIVOR = Conditioning(
    "survivor",
    BEST,
    BEST,
    "P(outcome | move, both sides play into our line) -- survivorship pruned, an upper bound",
)
ADVERSARY = Conditioning(
    "adversary",
    BEST,
    WORST,
    "P(outcome | move, opponent plays its best reply) -- minimax, a lower bound",
)

CONDITIONINGS = (NULL, SURVIVOR, ADVERSARY)


def empty_distribution():
    """A distribution with no mass yet, over all four outcomes."""
    return dict((outcome, fractions.Fraction(0)) for outcome in OUTCOMES)


def certain(outcome):
    """All the mass on one outcome."""
    distribution = empty_distribution()
    distribution[outcome] = fractions.Fraction(1)
    return distribution


def blend(parts):
    """Mix distributions by exact rational weight.

    `parts` is a list of (weight, distribution). Weights need not sum to one; they are normalized
    here, exactly, because they are Fractions and not floats.
    """
    total = sum(weight for weight, _ in parts)
    if total == 0:
        return certain(UNRESOLVED)
    mixed = empty_distribution()
    for weight, distribution in parts:
        share = fractions.Fraction(weight, 1) / total
        for outcome in OUTCOMES:
            mixed[outcome] += share * distribution[outcome]
    return mixed


def expected_score(distribution):
    """PLAYER_ONE's expected score under a distribution, as an exact Fraction."""
    return sum(SCORE[outcome] * distribution[outcome] for outcome in OUTCOMES)


def outcome_distribution(backend, state, budget, conditioning, memo=None):
    """The exact distribution over WIN, DRAW, LOSS and UNRESOLVED from this position.

    Exact in the arithmetic sense: every number returned is a Fraction. A distribution computed
    two ways can be compared with `==` and not with a tolerance. Exact is not the same as complete --
    where the budget runs out the mass lands on UNRESOLVED, the honest statement of what a
    bounded search knows.
    """
    if memo is None:
        memo = {}

    return _walk(backend, state, budget.plies, budget, conditioning, memo)


def _walk(backend, state, plies_left, budget, conditioning, memo):
    verdict = backend.verdict(state)
    if verdict is not None:
        return certain(verdict)

    if plies_left <= 0 or not budget.spend():
        return certain(UNRESOLVED)

    key = (state, plies_left)
    if key in memo:
        return memo[key]

    legal = backend.moves(state)
    if not legal:
        # A backend that returns no moves from a non-terminal position is telling us its rules are
        # incomplete. Fail closed instead of calling it a draw.
        return certain(UNRESOLVED)

    mover = backend.to_move(state)
    children = [
        _walk(
            backend,
            backend.apply(state, move),
            plies_left - 1,
            budget,
            conditioning,
            memo,
        )
        for move in legal
    ]

    if mover == CHANCE:
        result = blend(list(zip(backend.weights(state), children)))
    else:
        policy = (
            conditioning.hero_policy if mover == PLAYER_ONE else conditioning.foe_policy
        )
        result = _choose(children, policy)

    memo[key] = result
    return result


def _choose(children, policy):
    """Apply a policy to the distributions reachable from one node."""
    if policy == UNIFORM:
        return blend([(1, child) for child in children])

    scores = [expected_score(child) for child in children]
    target = max(scores) if policy == BEST else min(scores)

    # Every move achieving the target is kept and mixed uniformly. Keeping the whole tied set rather
    # than the first one found matters: the objective asks for the best next move to be one or a set
    # of one, and a set of size three is a real answer about the position, not an artifact of the
    # order the move generator happened to emit.
    tied = [child for child, score in zip(children, scores) if score == target]
    return blend([(1, child) for child in tied])


def best_moves(backend, state, budget, conditioning):
    """The move or moves that achieve the best outcome distribution, with each move's distribution.

    Returns (chosen, table) where `table` is a list of (move, distribution) over every legal move and
    `chosen` is the sublist that ties for the best expected score. A single-element `chosen` is a
    forced best move; a longer one means the position genuinely does not distinguish them at this
    budget, which is a finding about the position and not a failure to decide.
    """
    memo = {}
    table = []
    for move in backend.moves(state):
        reached = _walk(
            backend,
            backend.apply(state, move),
            budget.plies - 1,
            budget,
            conditioning,
            memo,
        )
        table.append((move, reached))

    if not table:
        return [], []

    scores = [expected_score(distribution) for _, distribution in table]
    target = max(scores)
    chosen = [entry for entry, score in zip(table, scores) if score == target]
    return chosen, table


def rollout(backend, state, budget, conditioning, generator):
    """Play one game to its end under the conditioning, returning its outcome.

    This is the sampled arm. It answers the same question as `outcome_distribution` and it is here so
    the two can be compared where both can run. Where they disagree, the disagreement is the finding.
    """
    for _ in range(budget.plies):
        verdict = backend.verdict(state)
        if verdict is not None:
            return verdict

        legal = backend.moves(state)
        if not legal:
            return UNRESOLVED

        mover = backend.to_move(state)
        if mover == CHANCE:
            state = backend.apply(
                state, _weighted_pick(legal, backend.weights(state), generator)
            )
            continue

        policy = (
            conditioning.hero_policy if mover == PLAYER_ONE else conditioning.foe_policy
        )
        if policy == UNIFORM:
            state = backend.apply(state, generator.choice(legal))
            continue

        # A sampled arm under BEST or WORST still has to look one ply ahead to know what best means.
        # It is a shallow look on purpose: this arm exists to be a different route to the same
        # number, and giving it the enumerator's depth would make it the same route twice.
        state = backend.apply(
            state, _shallow_pick(backend, state, legal, policy, generator)
        )

    return UNRESOLVED


def _weighted_pick(moves, weights, generator):
    """One move drawn in proportion to exact integer weights."""
    total = sum(weights)
    cut = generator.randrange(total)
    running = 0
    for move, weight in zip(moves, weights):
        running += weight
        if cut < running:
            return move
    return moves[-1]


def _shallow_pick(backend, state, legal, policy, generator):
    """The move a one-ply look prefers, ties broken by the generator and not by move order."""
    scored = []
    for move in legal:
        reached = backend.apply(state, move)
        verdict = backend.verdict(reached)
        scored.append((SCORE[verdict] if verdict is not None else SCORE[DRAW], move))

    target = (
        max(score for score, _ in scored)
        if policy == BEST
        else min(score for score, _ in scored)
    )
    return generator.choice([move for score, move in scored if score == target])


def sampled_distribution(backend, state, budget, conditioning, trials, seed):
    """The distribution estimated by `trials` rollouts, as exact rationals over the trial count.

    The seed is an input of the measurement like the budget is, and it is reported with the result.
    A sampled number nobody can reproduce is not a measurement.
    """
    generator = random.Random(seed)
    counts = dict((outcome, 0) for outcome in OUTCOMES)
    for _ in range(trials):
        counts[rollout(backend, state, budget, conditioning, generator)] += 1

    return dict(
        (outcome, fractions.Fraction(counts[outcome], trials)) for outcome in OUTCOMES
    )
