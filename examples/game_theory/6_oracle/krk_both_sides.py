#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: GAM-6-004
#
# The exact predictor plays BOTH sides of K+R vs K to a real, played-out win and loss.
#
#   Usage:  python examples/game_theory/6_oracle/krk_both_sides.py
#           (about half a minute: it solves the whole K+R vs K class, folded by symmetry.)
#
# WHAT THIS SHOWS. The tablebase of the previous example gives a value per position. This one lets
# that exact predictor MOVE. It solves K+R vs K for win/draw/loss and distance to mate, then plays a
# game out with the predictor choosing for BOTH sides: the winning side takes the move with the
# smallest distance to mate, the losing side the largest, so the win is forced and the defense is the
# longest legal one. The moveset printed is a real game -- legal moves to a terminal position -- and
# its length must equal the distance to mate the solve reported. That equality is the check: the
# static value and the played-out game are two routes to the same number.
#
# K+R vs K is the class where this closes cleanly: it is a forced win for the rook's side, there is no
# pawn and so no promotion, and the whole game stays in the class until mate. The move-sequence source
# here is the game itself, not an outside record: the repository holds no game corpus, so the real
# movesets are the ones the exact predictor plays, from a real starting position, not pulled from a
# database of human games. Comparing the predictor against human play would need such a corpus.
#
# HOW IT STAYS EXACT AND INTEGER ONLY. Value is win, draw or loss as the integers 2, 1, 0; distance to
# mate is an integer count of plies; the eight board symmetries fold the position graph to its classes
# without a pawn to break them. No fractions, no math library, no outside library: retrograde over the
# coalesced graph, and the tournament rules give a draw where neither side can force progress.

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


def _symmetry(square, which):
    """One of the eight square maps of the board's dihedral symmetry group."""
    row, col = square // 8, square % 8
    if which == 0:
        row, col = row, col
    elif which == 1:
        row, col = col, 7 - row
    elif which == 2:
        row, col = 7 - row, 7 - col
    elif which == 3:
        row, col = 7 - col, row
    elif which == 4:
        row, col = row, 7 - col
    elif which == 5:
        row, col = 7 - row, col
    elif which == 6:
        row, col = col, row
    else:
        row, col = 7 - col, 7 - row
    return row * 8 + col


def squares_of(board):
    white_king = white_rook = black_king = None
    for square, piece in enumerate(board):
        if piece == chess.KING:
            white_king = square
        elif piece == -chess.KING:
            black_king = square
        elif piece == chess.ROOK:
            white_rook = square
    return white_king, white_rook, black_king


def is_bare_kings(board):
    for piece in board:
        if abs(piece) not in (0, chess.KING):
            return False
    return True


def canonical(state):
    """The key of a position's symmetry class; the side to move is preserved by every symmetry."""
    board, side, _, _ = state
    white_king, white_rook, black_king = squares_of(board)
    best = None
    for which in range(8):
        candidate = (_symmetry(white_king, which), _symmetry(white_rook, which),
                     _symmetry(black_king, which))
        if best is None or candidate < best:
            best = candidate
    return best + (side,)


def make_board(white_king, white_rook, black_king):
    board = [chess.EMPTY] * 64
    board[white_king] = chess.KING
    board[white_rook] = chess.ROOK
    board[black_king] = -chess.KING
    return tuple(board)


def enumerate_reps():
    """One legal position per symmetry class: the square triple that is its own canonical form."""
    reps = []
    for white_king in range(64):
        for white_rook in range(64):
            if white_rook == white_king:
                continue
            for black_king in range(64):
                if black_king in (white_king, white_rook) or adjacent(white_king, black_king):
                    continue
                best = None
                for which in range(8):
                    candidate = (_symmetry(white_king, which), _symmetry(white_rook, which),
                                 _symmetry(black_king, which))
                    if best is None or candidate < best:
                        best = candidate
                if best != (white_king, white_rook, black_king):
                    continue
                board = make_board(white_king, white_rook, black_king)
                for side in (rules.PLAYER_ONE, rules.PLAYER_TWO):
                    other = rules.PLAYER_TWO if side == rules.PLAYER_ONE else rules.PLAYER_ONE
                    if chess._in_check(board, other):
                        continue  # the side not to move is in check: illegal
                    reps.append((board, side, NO_RIGHTS, -1))
    return reps


def solve():
    started = time.time()
    reps = enumerate_reps()
    value = {}
    distance = {}
    descriptors = {}
    for state in reps:
        key = canonical(state)
        moves = GAME.moves(state)
        if not moves:
            value[key] = LOSS if chess._in_check(state[0], state[1]) else DRAW  # mate or stalemate
            distance[key] = 0
            descriptors[key] = None
        else:
            value[key] = None
            distance[key] = None
            kids = []
            for move in moves:
                child = GAME.apply(state, move)
                kids.append(("draw", None) if is_bare_kings(child[0]) else ("ref", canonical(child)))
            descriptors[key] = kids
    print("  K+R vs K symmetry classes: %d, built in %.0fs" % (len(reps), time.time() - started))

    changed = True
    passes = 0
    while changed:
        changed = False
        passes += 1
        for key, kids in descriptors.items():
            if kids is None:
                continue
            loss_child_distances = []
            win_child_distances = []
            unknown = has_draw = False
            for kind, payload in kids:
                if kind == "draw":
                    has_draw = True
                    continue
                child_value = value[payload]
                if child_value is None:
                    unknown = True
                elif child_value == LOSS:
                    loss_child_distances.append(distance[payload])
                elif child_value == WIN:
                    win_child_distances.append(distance[payload])
                else:
                    has_draw = True
            if loss_child_distances:
                new_value, new_distance = WIN, 1 + min(loss_child_distances)
            elif not unknown and not has_draw:
                new_value, new_distance = LOSS, 1 + max(win_child_distances)
            else:
                continue  # a draw is available or children are unknown: leave it for a later pass
            if value[key] != new_value or distance[key] != new_distance:
                value[key], distance[key] = new_value, new_distance
                changed = True
    for key in value:
        if value[key] is None:
            value[key] = DRAW
            distance[key] = 0
    print("  solved to fixed point in %d passes, %.0fs total" % (passes, time.time() - started))
    return value, distance


def child_value_distance(child, value, distance):
    if is_bare_kings(child[0]):
        return DRAW, 0
    key = canonical(child)
    return value[key], distance[key]


def choose(state, value, distance):
    """The predictor's move for the side to move: win soonest, else hold a draw, else lose latest."""
    best_move = best_reply = best_distance = None
    for move in GAME.moves(state):
        child = GAME.apply(state, move)
        child_value, child_distance = child_value_distance(child, value, distance)
        reply = FLIP[child_value]  # the value of this move to the side to move
        take = best_reply is None or reply > best_reply
        if not take and reply == best_reply:
            take = (reply == WIN and child_distance < best_distance) or \
                   (reply == LOSS and child_distance > best_distance)
        if take:
            best_move, best_reply, best_distance = move, reply, child_distance
    return best_move


def play_out(layout, side, value, distance, cap=200):
    state = chess.from_layout(layout, side=side, rights=NO_RIGHTS)
    start = canonical(state)
    moves = []
    for _ in range(cap):
        if GAME.verdict(state) is not None or is_bare_kings(state[0]):
            break
        move = choose(state, value, distance)
        moves.append(chess.move_name(move))
        state = GAME.apply(state, move)
    return value[start], distance[start], moves, GAME.verdict(state)


# Rook's side and bare-king's side to move in the same shape: a real win moveset and its loss.
SHAPE = ("....k...", "........", "........", "........",
         "........", "........", "........", "R...K...")
SEEDS = (
    ("rook side to move", rules.PLAYER_ONE),
    ("bare-king side to move", rules.PLAYER_TWO),
)


def main():
    print("=" * 78)
    print("THE EXACT PREDICTOR PLAYS BOTH SIDES OF K+R vs K TO A REAL RESULT")
    print("=" * 78)
    value, distance = solve()
    all_pass = True
    for title, side in SEEDS:
        start_value, start_distance, moves, verdict = play_out(SHAPE, side, value, distance)
        played = len(moves)
        decisive = start_value in (WIN, LOSS)
        ok = played == start_distance and verdict is not None if decisive else verdict == rules.DRAW
        all_pass = all_pass and ok
        print("")
        print("  %s: exact value = %s, distance to mate = %d plies"
              % (title, NAME[start_value], start_distance))
        print("    played out %d plies, terminal verdict = %s, played length equals the solve: %s"
              % (played, verdict, "PASS" if ok else "FAIL"))
        print("    moveset: %s" % " ".join(moves))
    print("")
    print("  check: %s"
          % ("both played-out games reach the solved result in the solved distance"
             if all_pass else "MISMATCH -- see FAIL"))
    print("  The moveset is the game the exact predictor plays as both sides, and it mates in exactly")
    print("  the distance the static solve reported -- the value and the played game agreeing is the")
    print("  two-route check. A win for the rook's side is a loss for the bare king: one decisive game.")


if __name__ == "__main__":
    main()
