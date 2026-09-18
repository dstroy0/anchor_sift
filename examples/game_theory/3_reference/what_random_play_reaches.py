#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-3-001
#
# The background: what a position returns when nobody is trying.
#
#   Usage:  python examples/game_theory/3_reference/what_random_play_reaches.py [trials]
#
# Every result in stages four and five is a departure from this one. A move that wins 60% of the time
# is saying nothing until it is known what a move chosen at random wins, because a winning position
# wins under random play too. The null here is both sides moving uniformly over their legal moves,
# which reads nothing about the position at all.
#
# This stage also carries the two-arm check, which is the reason the null is computed twice. The
# enumerated arm sums over every continuation exactly, in Fractions. The sampled arm plays games out
# with a seeded generator and counts. They answer the same question by different routes, and where
# both can run they have to agree. Where they disagree, the disagreement is the finding and it is
# printed rather than tuned away.
#
# The sampled arm converges to the enumerated one and does not equal it. That gap is sampling error
# and it shrinks as the trial count grows, which is what the sweep below shows. A gap that does not
# shrink is a different animal and would mean one of the two routes is wrong.

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure import outcome_entropy  # noqa: E402
from representation.game import blackjack, checkers, poker, rules  # noqa: E402

DEFAULT_TRIALS = 20000
SEED = 20260916


def compare(title, game, state, plies, trials, seed=SEED):
    """Both arms on one position, then the distance between them."""
    print("")
    print("=" * 78)
    print(title)
    print("=" * 78)

    budget = rules.Budget(plies=plies, nodes=4000000)
    exact = rules.outcome_distribution(game, state, budget, rules.NULL)
    print("  enumerated  : %s" % budget.describe())
    print("  " + outcome_entropy.format_reading(outcome_entropy.reading(exact), "exact"))

    print("")
    print("  sampled, seed %d, both arms under the same null:" % seed)
    for count in (trials // 20, trials // 4, trials):
        sampled = rules.sampled_distribution(
            game, state, rules.Budget(plies=plies), rules.NULL, trials=count, seed=seed
        )
        gap = max(
            abs(float(sampled[outcome]) - float(exact[outcome])) for outcome in rules.RESOLVED
        )
        print(
            "    %-8d %s  worst gap %.5f"
            % (count, outcome_entropy.format_reading(outcome_entropy.reading(sampled), ""), gap)
        )


def main():
    trials = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_TRIALS

    print("The null is both sides uniform over their legal moves. It reads nothing about the")
    print("position. It is the floor every later number is measured against.")

    game = blackjack.Blackjack(decks=1)
    compare(
        "BLACKJACK -- sixteen against a dealer ten",
        game,
        blackjack.position(1, (10, 6), 10),
        24,
        trials,
    )

    game = checkers.Checkers()
    compare(
        "CHECKERS -- a four piece ending",
        game,
        checkers.endgame(
            ((5, 2, checkers.KING), (2, 3, checkers.MAN)),
            ((6, 5, checkers.MAN), (4, 7, checkers.MAN)),
        ),
        9,
        trials,
    )

    card = poker.card
    game = poker.Poker(ranks=6, suits=2, hand=3)
    compare(
        "POKER -- a pair of sevens on a twelve card deck",
        game,
        game.deal((card(5, 0), card(5, 1), card(0, 0)), (card(4, 0), card(3, 1), card(2, 0))),
        10,
        trials,
    )

    print("")
    print("=" * 78)
    print("What the background is for")
    print("=" * 78)
    print(
        "Two arms agreeing is a positive control for the estimator, not a result about the games.\n"
        "It is here because stage four reports a number for chess, where no enumerated arm exists\n"
        "and nothing else can catch the estimator being wrong. An estimator that cannot reproduce\n"
        "blackjack has nothing to say about chess, and this is where that is checked."
    )


if __name__ == "__main__":
    main()
