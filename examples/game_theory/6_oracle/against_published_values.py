#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-6-001
#
# The positive control: every number here was published by somebody else first.
#
#   Usage:  python examples/game_theory/6_oracle/against_published_values.py
#
# A game carries its own answer key, and that is the whole reason this subject is in the tree. The
# checks below are not self-consistency checks and they are not regression tests against a value this
# code produced earlier. Each one is a number that existed before this file did, computed by other
# people for other reasons, and the instrument either reproduces it or does not.
#
#   perft counts          the standard move generator oracle for chess, published for decades
#   Kiwipete perft        the position specifically constructed to catch castling, en passant and
#                         promotion bugs that the opening position does not exercise
#   checkers opening      seven legal moves, a fact about the rules
#   dealer bust rate      how often a blackjack dealer showing a ten busts
#   basic strategy        hit or stand on sixteen against a ten, a published decision
#   the hand ranking      that a flush beats a straight, which nothing here decided
#
# A negative control sits at the end. An instrument that passes every positive check and cannot fail
# is not being checked. The same machinery is pointed at a deliberately broken generator and has
# to reject it.

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation.game import blackjack, checkers, chess, poker, rules  # noqa: E402

# Published perft counts from the chess opening position.
PERFT_OPENING = {1: 20, 2: 400, 3: 8902, 4: 197281}

# Kiwipete, and its published counts. The position exists because the opening does not exercise
# castling, en passant or promotion. A generator can be wrong and still pass perft from the start.
KIWIPETE = (
    "r...k..r",
    "p.ppqpb.",
    "bn..pnp.",
    "...PN...",
    ".p..P...",
    "..N..Q.p",
    "PPPBBPPP",
    "R...K..R",
)
PERFT_KIWIPETE = {1: 48, 2: 2039}

# The published hand ranking, weakest to strongest. Nothing in this tree chose this order.
RANKING = (
    "high card",
    "pair",
    "two pair",
    "three of a kind",
    "straight",
    "flush",
    "full house",
    "four of a kind",
    "straight flush",
)

results = []


def check(label, got, expected, detail=""):
    passed = got == expected
    results.append(passed)
    print(
        "  %-46s %-12s %-12s %s%s"
        % (
            label,
            str(got),
            str(expected),
            "OK" if passed else "FAIL",
            "  " + detail if detail else "",
        )
    )
    return passed


def near(label, got, expected, window, detail=""):
    """For a published figure quoted at a different deck composition than the one measured here.

    The window is stated in the call and printed. It is a declared input of the check.
    """
    passed = abs(got - expected) <= window
    results.append(passed)
    print(
        "  %-46s %-12.4f %-12s %s%s"
        % (
            label,
            got,
            "%.4f +-%.3f" % (expected, window),
            "OK" if passed else "FAIL",
            "  " + detail if detail else "",
        )
    )
    return passed


def perft(game, state, depth):
    if depth == 0:
        return 1
    return sum(
        perft(game, game.apply(state, move), depth - 1) for move in game.moves(state)
    )


def main():
    print("Every expected value below was published before this file existed.")
    print("")
    print("  %-46s %-12s %-12s %s" % ("check", "measured", "published", ""))
    print("  " + "-" * 74)

    game = chess.Chess()
    opening = game.initial()
    for depth in sorted(PERFT_OPENING):
        check(
            "chess perft(%d) from the opening" % depth,
            perft(game, opening, depth),
            PERFT_OPENING[depth],
        )

    kiwi = chess.from_layout(KIWIPETE)
    for depth in sorted(PERFT_KIWIPETE):
        check(
            "chess perft(%d) from Kiwipete" % depth,
            perft(game, kiwi, depth),
            PERFT_KIWIPETE[depth],
            "castling, en passant, promotion",
        )

    checkers_game = checkers.Checkers()
    check(
        "checkers legal moves from the opening",
        len(checkers_game.moves(checkers_game.initial())),
        7,
    )

    # Standing on sixteen wins only where the dealer busts. The win probability under STAND is the
    # dealer's bust rate for a ten upcard. The published figure is quoted for an infinite deck; this
    # is one deck with three cards already removed. The two differ by composition and the window
    # says by how much the check will allow.
    black = blackjack.Blackjack(decks=1)
    sixteen = blackjack.position(1, (10, 6), 10)
    stand = black.apply(sixteen, blackjack.STAND)
    stand_distribution = rules.outcome_distribution(
        black, stand, rules.Budget(plies=24, nodes=400000), rules.ADVERSARY
    )
    near(
        "blackjack dealer bust rate, ten showing",
        float(stand_distribution[rules.WIN]),
        0.2120,
        0.0100,
        "single deck, three cards removed",
    )
    check(
        "blackjack: standing on 16 can never draw",
        float(stand_distribution[rules.DRAW]),
        0.0,
        "a dealer standing on 17 or more cannot tie 16",
    )

    chosen, _ = rules.best_moves(
        black, sixteen, rules.Budget(plies=24, nodes=400000), rules.ADVERSARY
    )
    check(
        "blackjack basic strategy: 16 against a ten",
        [move for move, _ in chosen],
        [blackjack.HIT],
        "the published decision is hit",
    )

    ladder = [
        (
            poker.HIGH_CARD,
            [
                poker.card(12, 0),
                poker.card(10, 1),
                poker.card(8, 2),
                poker.card(6, 3),
                poker.card(3, 0),
            ],
        ),
        (
            poker.PAIR,
            [
                poker.card(12, 0),
                poker.card(12, 1),
                poker.card(8, 2),
                poker.card(6, 3),
                poker.card(3, 0),
            ],
        ),
        (
            poker.TWO_PAIR,
            [
                poker.card(12, 0),
                poker.card(12, 1),
                poker.card(8, 2),
                poker.card(8, 3),
                poker.card(3, 0),
            ],
        ),
        (
            poker.TRIPS,
            [
                poker.card(12, 0),
                poker.card(12, 1),
                poker.card(12, 2),
                poker.card(8, 3),
                poker.card(3, 0),
            ],
        ),
        (
            poker.STRAIGHT,
            [
                poker.card(4, 0),
                poker.card(5, 1),
                poker.card(6, 2),
                poker.card(7, 3),
                poker.card(8, 0),
            ],
        ),
        (
            poker.FLUSH,
            [
                poker.card(12, 0),
                poker.card(10, 0),
                poker.card(8, 0),
                poker.card(6, 0),
                poker.card(3, 0),
            ],
        ),
        (
            poker.FULL_HOUSE,
            [
                poker.card(12, 0),
                poker.card(12, 1),
                poker.card(12, 2),
                poker.card(8, 3),
                poker.card(8, 0),
            ],
        ),
        (
            poker.QUADS,
            [
                poker.card(12, 0),
                poker.card(12, 1),
                poker.card(12, 2),
                poker.card(12, 3),
                poker.card(8, 0),
            ],
        ),
        (
            poker.STRAIGHT_FLUSH,
            [
                poker.card(4, 0),
                poker.card(5, 0),
                poker.card(6, 0),
                poker.card(7, 0),
                poker.card(8, 0),
            ],
        ),
    ]
    ordered = all(
        poker.evaluate(ladder[index][1]) < poker.evaluate(ladder[index + 1][1])
        for index in range(len(ladder) - 1)
    )
    check(
        "poker: the published hand ranking, all nine in order",
        ordered,
        True,
        " < ".join(RANKING[:3]) + " ...",
    )

    wheel = [
        poker.card(12, 0),
        poker.card(0, 1),
        poker.card(1, 2),
        poker.card(2, 3),
        poker.card(3, 0),
    ]
    check(
        "poker: ace low straight is a straight",
        poker.evaluate(wheel)[0],
        poker.STRAIGHT,
    )

    print("")
    print("  negative control -- the same checks must REJECT a broken generator")
    print("  " + "-" * 74)
    broken = _LamePawns()
    got = perft(broken, broken.initial(), 1)
    rejected = got != PERFT_OPENING[1]
    results.append(rejected)
    print(
        "  %-46s %-12s %-12s %s"
        % (
            "chess perft(1) with double steps removed",
            got,
            "not 20",
            "OK" if rejected else "FAIL",
        )
    )

    print("")
    print(
        "  %d checks, %d passed, %d failed"
        % (len(results), sum(results), len(results) - sum(results))
    )
    return 0 if all(results) else 1


class _LamePawns(chess.Chess):
    """Chess with the pawn double step removed, which the perft count has to catch.

    A negative control is only worth running if it is a plausible bug.
    Dropping the double step changes no rule that any single move looks illegal under, and a
    generator missing it plays legal chess forever -- it just plays a different game, and only a node
    count notices.
    """

    def moves(self, state):
        return [
            move
            for move in chess.Chess.moves(self, state)
            if not _is_double_step(state, move)
        ]


def _is_double_step(state, move):
    board, _, _, _ = state
    origin, target, _ = move
    return abs(board[origin]) == chess.PAWN and abs(target // 8 - origin // 8) == 2


if __name__ == "__main__":
    sys.exit(main())
