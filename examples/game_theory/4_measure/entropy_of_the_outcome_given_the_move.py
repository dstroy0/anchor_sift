#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-4-001
#
# H(Y|X): how much of the result is still open once a move is chosen.
#
#   Usage:  python examples/game_theory/4_measure/entropy_of_the_outcome_given_the_move.py
#
# X is the move played out of a position. Y is the outcome the game finally reaches, one of win, draw
# and loss. H(Y|X) is what remains undecided after the move, averaged over the moves available.
#
# The instrument returns no answer key here. Nothing in this stage compares against a published
# value; it reports what the measure says and what it cost. Stage six does the checking. This is the
# same division the rest of the tree keeps: a measure that also validates itself is two instruments
# in one file and neither can be trusted.
#
# THREE NUMBERS, NOT ONE, AND WHY THE THIRD IS THE USEFUL ONE
#
#   H(Y)     the marginal. How open the result is before the move is chosen.
#   H(Y|X)   the conditional. How open it is after.
#   I(X;Y)   the difference. How many bits the choice of move is worth.
#
# The third is what the objective is reaching for when it asks for the best next move. A position
# where one move wins and the rest lose has a large I(X;Y) -- the choice decides the game. A position
# where every move leads to the same distribution has none, and in that position there is no best
# move to find, which is a fact about the position.
#
# UNRESOLVED IS NOT FOLDED IN. Where the budget runs out the mass lands on UNRESOLVED and the entropy
# is reported twice: over the resolved outcomes renormalized, and over all four categories. The first
# is the position's uncertainty; the second includes the search's own ignorance. Neither is the right
# one on its own and both are printed with the unresolved mass beside them.

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure import outcome_entropy  # noqa: E402
from representation.game import blackjack, checkers, chess, poker, rules  # noqa: E402

MATE_IN_ONE = (
    "......k.",
    ".....ppp",
    "........",
    "........",
    "........",
    "........",
    ".....PPP",
    "....R.K.",
)

QUIET_OPENING = chess.OPENING


def measure(title, game, state, plies, namer=str, conditioning=rules.ADVERSARY, top=8):
    print("")
    print("=" * 78)
    print("%s   [%s]" % (title, conditioning.name))
    print("  %s" % conditioning.statement)
    print("=" * 78)

    budget = rules.Budget(plies=plies, nodes=4000000)
    chosen, table = rules.best_moves(game, state, budget, conditioning)
    if not table:
        print("  no legal moves")
        return

    print("  budget      : %s" % budget.describe())
    print("  moves       : %d" % len(table))

    # Both category sets, because on a shallow budget they answer different questions and the
    # resolved-only reading can collapse to zero for a reason that is about the budget. A move whose branch resolved nothing contributes no term to the
    # resolved-only entropy. A position where one move mates and nineteen run out of depth has
    # every informative term dropped and reports a gain of zero. Over all four categories the same
    # position reports what it should, because "the search did not finish" is itself one of the
    # things knowing the move tells you.
    for label, over in (
        ("resolved only", rules.RESOLVED),
        ("all four", rules.OUTCOMES),
    ):
        gain, marginal_bits, conditional_bits = outcome_entropy.information_gain(
            table, over=over
        )
        _, covered = outcome_entropy.conditional_entropy(table, over=over)
        print(
            "  %-14s H(Y)=%s  H(Y|X)=%s  I(X;Y)=%s   over %s of the move set"
            % (
                label,
                "  n/a " if marginal_bits is None else "%.4f" % marginal_bits,
                "  n/a " if conditional_bits is None else "%.4f" % conditional_bits,
                "  n/a " if gain is None else "%.4f" % gain,
                covered,
            )
        )

    print("  best move(s): %s" % ", ".join(namer(move) for move, _ in chosen))

    print("")
    print("  per move, worst first by how much is left open:")
    rows = []
    for move, distribution in table:
        record = outcome_entropy.reading(distribution)
        rows.append((record["resolved_bits"] or 0.0, move, record))
    rows.sort(reverse=True)
    for _, move, record in rows[:top]:
        print("    " + outcome_entropy.format_reading(record, namer(move)))
    if len(rows) > top:
        print("    ... %d more" % (len(rows) - top))


def main():
    game = chess.Chess()
    measure(
        "CHESS -- a back rank mate in one",
        game,
        chess.from_layout(MATE_IN_ONE, rights=(False, False, False, False)),
        2,
        chess.move_name,
    )
    measure(
        "CHESS -- the opening, where four plies resolves nothing",
        game,
        chess.from_layout(QUIET_OPENING),
        4,
        chess.move_name,
    )

    game = checkers.Checkers()
    measure(
        "CHECKERS -- a four piece ending",
        game,
        checkers.endgame(
            ((5, 2, checkers.KING), (2, 3, checkers.MAN)),
            ((6, 5, checkers.MAN), (4, 7, checkers.MAN)),
        ),
        9,
        str,
    )

    game = blackjack.Blackjack(decks=1)
    measure(
        "BLACKJACK -- sixteen against a dealer ten",
        game,
        blackjack.position(1, (10, 6), 10),
        24,
        str,
    )

    card = poker.card
    game = poker.Poker(ranks=6, suits=2, hand=3)
    measure(
        "POKER -- a pair of sevens on a twelve card deck",
        game,
        game.deal(
            (card(5, 0), card(5, 1), card(0, 0)), (card(4, 0), card(3, 1), card(2, 0))
        ),
        10,
        lambda move: poker.show(move) if move else "(keep all)",
    )

    print("")
    print("=" * 78)
    print("Reading these")
    print("=" * 78)
    print(
        "The mate in one is the case that shows why two category sets are printed and not one.\n"
        "Read over the resolved outcomes alone it reports I(X;Y) = 0, which is false as a statement\n"
        "about the position and true as a statement about the reading: nineteen of the twenty moves\n"
        "resolved nothing at two plies. Every term that carried information was dropped and only\n"
        "the mate was left, and a single certain outcome has no entropy to lose. Read over all four\n"
        "categories the same position reports a positive gain, because knowing the move tells you\n"
        "whether the game ends here, and that is a real thing to know.\n"
        "\n"
        "The chess opening at four plies is the honest failure. Almost every branch is unresolved,\n"
        "both readings are computed over a sliver of the mass, and the number means very little. It\n"
        "is printed anyway, with its unresolved mass and its covered share beside it, because hiding\n"
        "a weak reading is worse than showing one."
    )


if __name__ == "__main__":
    main()
