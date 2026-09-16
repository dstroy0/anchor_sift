#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-2-001
#
# What a position partitions into, and where enumeration stops being possible.
#
#   Usage:  python examples/game_theory/2_partition/what_the_branching_costs.py [plies]
#
# A move partitions the futures reachable from a position into disjoint blocks: play this move and
# you are in this block, and the blocks do not overlap. That is the partition this stage measures,
# and the quantity that matters is how fast the blocks subdivide, because that is what decides
# whether the outcome distribution under a move can be computed or only estimated.
#
# This stage is also where the budget stops being an implementation detail. Every later number in
# this subject carries a declared ply count, and the reason is measured here: the node count is
# exponential in the ply count with a base the game sets, so a bound is not a convenience, it is the
# difference between a number and no number at all. Reporting the bound beside every result is the
# only thing that keeps two readings of the same position comparable.

import os
import sys
import time

ROOT = os.path.dirname(os.path.abspath(__file__))
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation.game import blackjack, checkers, chess, poker, rules  # noqa: E402

DEFAULT_PLIES = 4


def count_nodes(game, state, plies):
    """Positions reachable in exactly `plies` moves. The same walk a perft is, over any backend."""
    if plies == 0:
        return 1
    legal = game.moves(state)
    if not legal:
        return 1
    return sum(count_nodes(game, game.apply(state, move), plies - 1) for move in legal)


def sweep(title, game, state, plies):
    print("")
    print("%s" % title)
    print("  %-6s %-14s %-12s %s" % ("plies", "positions", "seconds", "growth"))
    previous = None
    for depth in range(1, plies + 1):
        started = time.time()
        total = count_nodes(game, state, depth)
        elapsed = time.time() - started
        growth = "" if previous is None else "%.1fx" % (float(total) / previous)
        print("  %-6d %-14d %-12.3f %s" % (depth, total, elapsed, growth))
        previous = total
        if elapsed > 20.0:
            print("  stopped: one more ply would not finish in a readable time")
            break


def main():
    plies = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PLIES

    print("How fast a position subdivides. The base is the game's, not the search's.")

    game = chess.Chess()
    sweep("CHESS from the opening", game, game.initial(), plies)

    game = checkers.Checkers()
    sweep("CHECKERS from the opening", game, game.initial(), plies)

    game = checkers.Checkers()
    ending = checkers.endgame(
        ((5, 2, checkers.KING), (2, 3, checkers.MAN)),
        ((6, 5, checkers.MAN), (4, 7, checkers.MAN)),
    )
    sweep("CHECKERS from a four piece ending", game, ending, plies + 2)

    game = blackjack.Blackjack(decks=1)
    sweep("BLACKJACK from sixteen against a ten", game, blackjack.position(1, (10, 6), 10), plies + 2)

    card = poker.card
    game = poker.Poker(ranks=6, suits=2, hand=3)
    sweep(
        "POKER on a twelve card deck, both hands dealt",
        game,
        game.deal((card(5, 0), card(5, 1), card(0, 0)), (card(4, 0), card(3, 1), card(2, 0))),
        plies + 2,
    )

    print("")
    print("=" * 78)
    print("What this decides")
    print("=" * 78)
    print(
        "The three small games bottom out: the walk reaches terminal positions and stops, so the\n"
        "outcome distribution under a move is a sum over a finite set and can be computed exactly.\n"
        "Chess does not bottom out at any depth this will run, so its distribution has to be\n"
        "estimated, and the estimate has nothing local to check it against.\n"
        "\n"
        "That asymmetry is the subject. Stage six checks the estimator where the answer is known.\n"
        "Nothing checks it on chess, which is why the chess numbers carry their budget in the same\n"
        "line as the result rather than in a footnote."
    )


if __name__ == "__main__":
    main()
