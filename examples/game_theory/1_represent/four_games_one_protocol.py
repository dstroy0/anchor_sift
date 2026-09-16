#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-1-001
#
# Four games carrying their own answer key, behind one protocol that knows none of them apart.
#
#   Usage:  python examples/game_theory/1_represent/four_games_one_protocol.py
#
# What a game keeps and what it throws away. A position here is a tuple: a board, whose turn it is,
# and whatever else the rules need to say what happens next. Nothing is remembered about how the
# position was reached, because nothing in the rules depends on it -- except the things that do, and
# those are in the state explicitly. Castling rights are in the chess state for that reason, and so
# is the en passant square. A state that needs history is a state that was not written down properly.
#
# The four differ in the two properties that decide whether the outcome distribution can be computed
# or only estimated: whether chance deals, and whether the opponent chooses. Blackjack has chance and
# no opponent choice. Checkers has opponent choice and no chance. Poker has both. Chess has only
# opponent choice and is far too large regardless. Those four corners are why these four games.

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke every
# path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation.game import blackjack, checkers, chess, poker, rules  # noqa: E402

MOVER_NAMES = {rules.PLAYER_ONE: "player one", rules.PLAYER_TWO: "player two", rules.CHANCE: "chance"}


def show(title, game, state, note):
    print("")
    print("=" * 78)
    print("%s -- %s" % (title, note))
    print("=" * 78)
    print(game.describe(state))
    mover = game.to_move(state)
    legal = game.moves(state)
    print("")
    print("  to move      : %s" % MOVER_NAMES[mover])
    print("  legal moves  : %d" % len(legal))
    print("  state is     : %d fields, hashable, no history" % len(state))
    verdict = game.verdict(state)
    print("  verdict      : %s" % ("still running" if verdict is None else verdict))
    if mover == rules.CHANCE:
        weights = game.weights(state)
        print("  chance weights: %d entries summing to %d" % (len(weights), sum(weights)))


def main():
    print("Four games, one protocol. Every backend answers the same six calls and nothing else:")
    print("  initial, to_move, moves, weights, apply, verdict")

    game = chess.Chess()
    show(
        "CHESS",
        game,
        game.initial(),
        "opponent chooses, no chance, and no hope of enumeration",
    )

    game = checkers.Checkers()
    show(
        "CHECKERS",
        game,
        game.initial(),
        "opponent chooses, no chance, endgames small enough to solve",
    )

    game = blackjack.Blackjack(decks=1)
    show(
        "BLACKJACK",
        game,
        blackjack.position(1, (10, 6), 10),
        "chance deals, the dealer never chooses",
    )

    game = poker.Poker(ranks=6, suits=2, hand=3)
    card = poker.card
    show(
        "POKER",
        game,
        game.deal((card(5, 0), card(5, 1), card(0, 0)), (card(4, 0), card(3, 1), card(2, 0))),
        "chance deals and the opponent chooses without seeing our hand",
    )

    print("")
    print("=" * 78)
    print("What the representation cost")
    print("=" * 78)
    print(
        "Nothing was rounded to build any of these. A card is an integer, a square is an index, and\n"
        "a deck is a count per rank. There is no scale, no tolerance and no grid anywhere in this\n"
        "stage, which is why the later stages can compare two readings with == instead of a\n"
        "tolerance. The subject was chosen partly for that: a game is a domain where the exact\n"
        "representation is the obvious one, so nothing is lost on the way in and any loss further\n"
        "down belongs to the measurement rather than to the reader."
    )


if __name__ == "__main__":
    main()
