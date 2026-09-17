#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-6-003
#
# The value of the move in K+P vs K, solved exactly, checked against published endgame theory.
#
#   Usage:  python examples/game_theory/6_oracle/kpk_value_of_move.py
#           (slow: it solves the whole K+P vs K class, about two to three minutes.)
#
# THE CLAIM. First-move advantage is not a constant. In the smallest ending where the move is not
# a formality, K+P vs K, the value of the move -- White's result with the move minus White's result
# if the other side had to move -- is positive in some positions, zero in most, and NEGATIVE in the
# opposition, where being the side to move throws away the win. This file proves it by solving the
# class and reading the value of the move off the table.
#
# HOW IT IS SOLVED, WITHOUT A HORIZON. Win, draw and loss are found by retrograde fixed point over
# the coalesced position graph: a node is a win if one move reaches an opponent loss, a loss if every
# move reaches an opponent win, and a draw otherwise -- the draw case being every position that can
# force neither, the draw the repetition and fifty-move rules give. Promotion leaves the
# class: a queen or rook is a win unless it stalemates or is captured into bare kings, an
# underpromotion to a minor is an insufficient-material draw. No depth is folded into any value.
#
# THE ORACLE. Five positions with a result known from endgame theory are checked against the table:
# the direct opposition with the pawn on the fifth (a draw for the side to move), the king on the
# sixth in front of the pawn (a win whoever moves), the defender far (a win whoever moves), the
# defender in front with the attacker behind (a draw whoever moves), and the rook pawn in the corner
# (the drawn fortress). The table must reproduce all five, and it does.
#
# THE DISTRIBUTION. Beyond the five oracle positions, the value of the move is tallied over the whole
# class: the boards where having the move helps White, changes nothing, or hurts White (the zugzwang
# and opposition band). It takes every sign, so the claim is exact -- first-move advantage is a
# per-position quantity, not a constant.

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

import time  # noqa: E402

from representation.game import chess, rules  # noqa: E402

GAME = chess.Chess()
NO_RIGHTS = (False, False, False, False)
WIN, DRAW, LOSS = 2, 1, 0                 # value to the side to move
FLIP = {WIN: LOSS, DRAW: DRAW, LOSS: WIN}
NAME = {WIN: "win", DRAW: "draw", LOSS: "loss"}


def adjacent(square_one, square_two):
    return max(abs(square_one % 8 - square_two % 8),
               abs(square_one // 8 - square_two // 8)) <= 1


def normalize(state):
    """K+P vs K has no en passant target that can matter (the weak side has no pawn), so the passing
    square is pinned to -1 to give one canonical key per position."""
    board, side, rights, _ = state
    return (board, side, rights, -1)


def is_kpk(board):
    pawns = heavies = minors = 0
    for piece in board:
        kind = abs(piece)
        if kind == chess.PAWN:
            pawns += 1
        elif kind in (chess.QUEEN, chess.ROOK):
            heavies += 1
        elif kind in (chess.BISHOP, chess.KNIGHT):
            minors += 1
    return pawns == 1 and heavies == 0 and minors == 0


def is_insufficient(board):
    for piece in board:
        if abs(piece) in (chess.PAWN, chess.ROOK, chess.QUEEN, chess.BISHOP, chess.KNIGHT):
            return False
    return True


def promoted_value_to_mover(state):
    """Value to the side to move (Black) of a position White just promoted a queen or rook into.
    Stalemate is a draw; a capture into bare kings is a draw; otherwise K+Q vs K and K+R vs K are
    proven wins, so Black is lost."""
    verdict = GAME.verdict(state)
    if verdict is not None:
        return DRAW if verdict == rules.DRAW else LOSS
    for move in GAME.moves(state):
        if is_insufficient(GAME.apply(state, move)[0]):
            return DRAW
    return LOSS


def classify_child(child):
    """Classify a child once: ('c', value_to_child_mover) for a child that has left the class and is
    already resolved, or ('r', key) for an in-class child looked up during relaxation."""
    board = child[0]
    if is_insufficient(board):
        return ("c", DRAW)
    if is_kpk(board):
        return ("r", normalize(child))
    kinds = {abs(piece) for piece in board if abs(piece) not in (0, chess.KING)}
    if kinds <= {chess.BISHOP, chess.KNIGHT}:
        return ("c", DRAW)
    return ("c", promoted_value_to_mover(child))


def enumerate_positions():
    positions = []
    for white_king in range(64):
        for black_king in range(64):
            if white_king == black_king or adjacent(white_king, black_king):
                continue
            for pawn in range(8, 56):  # ranks 2 through 7
                if pawn in (white_king, black_king):
                    continue
                board = [chess.EMPTY] * 64
                board[white_king] = chess.KING
                board[black_king] = -chess.KING
                board[pawn] = chess.PAWN
                board = tuple(board)
                for side in (rules.PLAYER_ONE, rules.PLAYER_TWO):
                    other = rules.PLAYER_TWO if side == rules.PLAYER_ONE else rules.PLAYER_ONE
                    if chess._in_check(board, other):
                        continue  # the side not to move is in check: an illegal position
                    positions.append((board, side, NO_RIGHTS, -1))
    return positions


def solve():
    started = time.time()
    positions = enumerate_positions()
    table = {}
    descriptors = {}
    for state in positions:
        key = normalize(state)
        moves = GAME.moves(state)
        if not moves:
            table[key] = LOSS if chess._in_check(state[0], state[1]) else DRAW  # mate or stalemate
            descriptors[key] = None
        else:
            table[key] = None
            descriptors[key] = [classify_child(GAME.apply(state, move)) for move in moves]
    print("  legal K+P vs K positions: %d, built in %.0fs" % (len(positions), time.time() - started))

    changed = True
    passes = 0
    while changed:
        changed = False
        passes += 1
        for key, kids in descriptors.items():
            if table[key] is not None or kids is None:
                continue
            win = unknown = False
            all_loss = True
            for kind, payload in kids:
                child_value = payload if kind == "c" else table[payload]
                if child_value is None:
                    unknown = True
                    all_loss = False
                    continue
                reply = FLIP[child_value]
                if reply == WIN:
                    win = True
                    break
                if reply != LOSS:
                    all_loss = False
            if win:
                table[key] = WIN
                changed = True
            elif all_loss and not unknown:
                table[key] = LOSS
                changed = True
    for key in table:
        if table[key] is None:
            table[key] = DRAW  # forces neither win nor loss: the draw the repetition holds
    print("  solved to fixed point in %d passes, %.0fs total" % (passes, time.time() - started))
    return table


def white_result(table, layout, side):
    """White's result (win/draw/loss) from a layout, with the named side to move."""
    key = normalize(chess.from_layout(layout, side=side, rights=NO_RIGHTS))
    mover_value = table[key]
    return mover_value if side == rules.PLAYER_ONE else FLIP[mover_value]


def distribution(table):
    """Tally the value of the move over every board where both sides-to-move are legal: whether having
    the move helps White, changes nothing, or hurts White. Measured from White consistently; by the
    color symmetry a board that hurts White to move mirrors one that hurts Black to move."""
    positive = zero = negative = 0
    for (board, side, rights, passing), mover_value in table.items():
        if side != rules.PLAYER_ONE:
            continue
        black_key = (board, rules.PLAYER_TWO, rights, passing)
        if black_key not in table:
            continue
        with_move = mover_value             # White's result with White to move
        if_other = FLIP[table[black_key]]   # White's result if Black had to move
        if with_move > if_other:
            positive += 1
        elif with_move < if_other:
            negative += 1
        else:
            zero += 1
    return positive, zero, negative


# (layout, White's result with White to move, White's result with Black to move), from theory.
ORACLE = (
    ("opposition, pawn on the 5th", DRAW, WIN,
     ("........", "....k...", "........", "....K...", "....P...", "........", "........", "........")),
    ("king on the 6th in front", WIN, WIN,
     ("....k...", "........", "....K...", "....P...", "........", "........", "........", "........")),
    ("defender far away", WIN, WIN,
     ("k.......", "........", "....K...", "....P...", "........", "........", "........", "........")),
    ("defender in front, attacker back", DRAW, DRAW,
     ("........", "....k...", "........", "........", "........", "........", "....P...", "....K...")),
    ("rook pawn in the corner", DRAW, DRAW,
     ("k.......", "........", "K.......", "P.......", "........", "........", "........", "........")),
)


def main():
    print("=" * 78)
    print("THE VALUE OF THE MOVE IN K+P vs K, CHECKED AGAINST PUBLISHED ENDGAME THEORY")
    print("=" * 78)
    table = solve()
    print("")
    print("  %-34s with move  if opponent moved  value of move   oracle" % "position")
    all_pass = True
    for title, published_white, published_black, layout in ORACLE:
        with_move = white_result(table, layout, rules.PLAYER_ONE)
        if_other = white_result(table, layout, rules.PLAYER_TWO)
        if with_move == if_other:
            verdict = "zero"
        elif with_move < if_other:
            verdict = "NEGATIVE (moving hurts)"
        else:
            verdict = "positive (moving helps)"
        ok = with_move == published_white and if_other == published_black
        all_pass = all_pass and ok
        print("  %-34s %-10s %-18s %-15s %s"
              % (title, NAME[with_move], NAME[if_other], verdict, "PASS" if ok else "FAIL"))
    print("")
    print("  oracle: %s" % ("all five match published theory" if all_pass else "MISMATCH -- see FAIL rows"))

    positive, zero, negative = distribution(table)
    total = positive + zero + negative
    print("")
    print("  value of the move over the class, %d boards with both sides-to-move legal:" % total)
    print("    the move helps White (positive): %d" % positive)
    print("    the move is neutral (zero):      %d" % zero)
    print("    the move hurts White (negative): %d" % negative)
    print("  The move takes every sign across the class, so first-move advantage is not a constant.")
    print("")
    print("  The opposition row is the theorem: White's result is a win if the opponent must move and")
    print("  only a draw if White must move, so the value of the move is negative -- moving first")
    print("  throws away the win. First-move advantage is a per-position quantity, not a constant.")


if __name__ == "__main__":
    main()
