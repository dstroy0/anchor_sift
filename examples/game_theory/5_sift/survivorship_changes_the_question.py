#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-5-001
#
# What pruning the opponent's branches does to the number it produces.
#
#   Usage:  python examples/game_theory/5_sift/survivorship_changes_the_question.py
#
# The objective this subject was built for asks for survivorship bias: prune the opponent's paths and
# maximize our own. Doing that is easy. The finding is what it costs, and the cost is not that the
# number gets bigger. The cost is that it stops being the number it is named after.
#
#   P(outcome | our move)                                     what H(Y|X) means
#   P(outcome | our move, the opponent plays into our line)    what pruning returns
#
# Those are different quantities about different things, and the second is not an estimate of the
# first. Reporting the second under the first's name is the way this work would be quietly wrong,
# all three conditionings are computed on the same position at the same budget and printed together,
# each carrying the sentence that says which quantity it is.
#
# THE CONTROL IS BLACKJACK AND IT IS WHY THE OTHER NUMBERS MEAN ANYTHING
#
# Blackjack's dealer has exactly one legal move at every turn. It never chooses. There is nothing
# to prune, and the pruned and unpruned readings must come out identical. They do. That identity is
# what proves the gap seen in checkers and poker is the pruning and not an artifact of the
# estimator -- without it, three different numbers from three conditionings could just be three
# different bugs.

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure import outcome_entropy  # noqa: E402
from representation.game import blackjack, checkers, chess, poker, rules  # noqa: E402

FORCED_MATE = (
    "......k.",
    ".....ppp",
    "........",
    "........",
    "........",
    "........",
    ".....PPP",
    "....R.K.",
)


def spread(title, game, state, plies, namer=str, note=""):
    print("")
    print("=" * 78)
    print(title)
    if note:
        print("  %s" % note)
    print("=" * 78)

    readings = {}
    for conditioning in rules.CONDITIONINGS:
        budget = rules.Budget(plies=plies, nodes=4000000)
        distribution = rules.outcome_distribution(game, state, budget, conditioning)
        chosen, table = rules.best_moves(
            game, state, rules.Budget(plies=plies, nodes=4000000), conditioning
        )
        readings[conditioning.name] = distribution
        print("")
        print("  %s -- %s" % (conditioning.name.upper(), conditioning.statement))
        print(
            "  "
            + outcome_entropy.format_reading(outcome_entropy.reading(distribution), "")
        )
        print("    budget     : %s" % budget.describe())
        print("    best move(s): %s" % ", ".join(namer(move) for move, _ in chosen))

    survivor_win = float(readings["survivor"][rules.WIN])
    adversary_win = float(readings["adversary"][rules.WIN])
    print("")
    print(
        "  survivorship gap: win %.6f pruned against %.6f unpruned, a difference of %.6f"
        % (survivor_win, adversary_win, survivor_win - adversary_win)
    )
    if survivor_win == adversary_win:
        print("  the gap is zero: the opponent had no choice to prune")


def main():
    print(
        "Three conditionings, one position, one budget. The spread between them is the bias."
    )

    game = blackjack.Blackjack(decks=1)
    spread(
        "BLACKJACK -- the control, where pruning can do nothing",
        game,
        blackjack.position(1, (10, 6), 10),
        24,
        str,
        "the dealer has exactly one legal move at every turn. There is nothing to prune",
    )

    game = checkers.Checkers()
    spread(
        "CHECKERS -- a four piece ending, where the opponent really chooses",
        game,
        checkers.endgame(
            ((5, 2, checkers.KING), (2, 3, checkers.MAN)),
            ((6, 5, checkers.MAN), (4, 7, checkers.MAN)),
        ),
        9,
        str,
    )

    card = poker.card
    game = poker.Poker(ranks=6, suits=2, hand=3)
    spread(
        "POKER -- a pair of sevens, where pruning also changes the recommendation",
        game,
        game.deal(
            (card(5, 0), card(5, 1), card(0, 0)), (card(4, 0), card(3, 1), card(2, 0))
        ),
        10,
        lambda move: poker.show(move) if move else "(keep all)",
    )

    game = chess.Chess()
    spread(
        "CHESS -- a back rank mate in one, where pruning cannot flatter the result",
        game,
        chess.from_layout(FORCED_MATE, rights=(False, False, False, False)),
        2,
        chess.move_name,
        "a forced mate survives any opponent. The pruned and unpruned readings must agree here",
    )

    print("")
    print("=" * 78)
    print("What this stage found")
    print("=" * 78)
    print(
        "Pruning does not make the estimate optimistic by a correctable amount. On the checkers\n"
        "ending it turns a position the opponent wins into one we win with certainty, at the same\n"
        "budget, from the same code. In poker it changes which move is recommended, which is worse\n"
        "than changing a probability: a number that is wrong can be caveated, a recommendation that\n"
        "is wrong gets acted on.\n"
        "\n"
        "The forced mate is the case where all three agree, and it agrees for a reason worth stating:\n"
        "a mate survives any opponent. Pruning removes nothing that mattered. That is a property\n"
        "of that position and not a reassurance about pruning in general."
    )


if __name__ == "__main__":
    main()
