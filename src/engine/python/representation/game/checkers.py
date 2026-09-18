#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Checkers: perfect information, no chance, and endgames small enough to solve outright.
#
#   Usage:  from representation.game import checkers
#           game = checkers.Checkers()
#           state = checkers.endgame(((5, 2, checkers.MAN),), ((2, 5, checkers.KING),))
#
# This backend carries the weight of the survivorship result, because it is the only solved arm where
# the opponent actually chooses. Blackjack's dealer has exactly one legal move at every turn, so
# pruning its paths changes nothing and the pruned and unpruned readings come out identical -- which
# is a useful control, and is also why blackjack alone cannot show what pruning costs. Here the
# opponent has real choices, the three conditionings separate, and the gap between them is the size
# of the survivorship bias in a game whose true value is still computable.
#
# THE RULES IMPLEMENTED, STATED SO THEY ARE NOT GUESSED AT
#
# Eight by eight, play on dark squares. Men step diagonally forward one square and capture by jumping
# an adjacent enemy into the empty square beyond. Capturing is mandatory: where any capture exists,
# only captures are legal. A capture that can continue must continue. One move is a whole jump
# chain and not a single hop. A man reaching the far rank becomes a king and the move ends there,
# which is the standard rule and is the one place a chain stops early. Kings move and capture in all
# four diagonal directions. A player with no pieces, or with no legal move, has lost.
#
# There is no draw by repetition or by inaction here. A game that does not finish inside the declared
# budget returns UNRESOLVED, which is what the enumerator is for. Calling an unfinished game a draw
# would put mass on an outcome that was never reached.

from representation.game import rules

EMPTY = 0
MAN = 1
KING = 2

# Board squares are indexed row * 8 + column, row 0 at PLAYER_ONE's back rank. PLAYER_ONE advances
# toward row 7 and PLAYER_TWO toward row 0.
SIZE = 8
SQUARES = SIZE * SIZE

# A square holds one of these. Sign carries the owner so a single integer says both things.
PIECES = {
    (rules.PLAYER_ONE, MAN): 1,
    (rules.PLAYER_ONE, KING): 2,
    (rules.PLAYER_TWO, MAN): -1,
    (rules.PLAYER_TWO, KING): -2,
}

DIAGONALS = ((-1, -1), (-1, 1), (1, -1), (1, 1))


def owner(piece):
    """Which player holds a square's piece, or None where it is empty."""
    if piece > 0:
        return rules.PLAYER_ONE
    if piece < 0:
        return rules.PLAYER_TWO
    return None


def is_king(piece):
    return abs(piece) == KING


def forward_rows(player):
    """The row direction this player's men advance in."""
    return 1 if player == rules.PLAYER_ONE else -1


def on_board(row, column):
    return 0 <= row < SIZE and 0 <= column < SIZE


def dark(row, column):
    """Play happens on dark squares only."""
    return (row + column) % 2 == 1


class Checkers(object):
    """The checkers backend. States are (board, side to move) and boards are 64-tuples."""

    name = "checkers"

    def initial(self):
        board = [EMPTY] * SQUARES
        for row in range(0, 3):
            for column in range(SIZE):
                if dark(row, column):
                    board[row * SIZE + column] = PIECES[(rules.PLAYER_ONE, MAN)]
        for row in range(SIZE - 3, SIZE):
            for column in range(SIZE):
                if dark(row, column):
                    board[row * SIZE + column] = PIECES[(rules.PLAYER_TWO, MAN)]
        return (tuple(board), rules.PLAYER_ONE)

    def to_move(self, state):
        return state[1]

    def weights(self, state):
        """Never called. Checkers has no chance nodes, and saying so is cheaper than a comment."""
        raise NotImplementedError("checkers has no chance nodes")

    def moves(self, state):
        board, side = state
        captures = []
        steps = []

        for square in range(SQUARES):
            piece = board[square]
            if owner(piece) != side:
                continue
            found = _capture_chains(board, square, piece, side)
            if found:
                captures.extend(found)
            elif not captures:
                steps.extend(_simple_steps(board, square, piece, side))

        # Mandatory capture. Where a capture exists the quiet moves are not legal. They are
        # discarded.
        return captures if captures else steps

    def apply(self, state, move):
        board, side = state
        squares = list(board)
        path = move

        piece = squares[path[0]]
        squares[path[0]] = EMPTY

        for index in range(len(path) - 1):
            origin = path[index]
            target = path[index + 1]
            if abs(target - origin) > SIZE + 1:
                jumped = (origin + target) // 2
                squares[jumped] = EMPTY

        landing = path[-1]
        row = landing // SIZE
        if not is_king(piece) and row == (SIZE - 1 if side == rules.PLAYER_ONE else 0):
            piece = PIECES[(side, KING)]
        squares[landing] = piece

        return (tuple(squares), rules.PLAYER_TWO if side == rules.PLAYER_ONE else rules.PLAYER_ONE)

    def verdict(self, state):
        board, side = state

        one = any(owner(piece) == rules.PLAYER_ONE for piece in board)
        two = any(owner(piece) == rules.PLAYER_TWO for piece in board)
        if not one:
            return rules.LOSS
        if not two:
            return rules.WIN

        if not self.moves(state):
            # The side to move is stuck, which loses. Stated from PLAYER_ONE's side as always.
            return rules.LOSS if side == rules.PLAYER_ONE else rules.WIN
        return None

    def describe(self, state):
        board, side = state
        glyphs = {0: ".", 1: "o", 2: "O", -1: "x", -2: "X"}
        lines = []
        for row in range(SIZE - 1, -1, -1):
            lines.append(
                "".join(glyphs[board[row * SIZE + column]] for column in range(SIZE))
            )
        lines.append("to move: %s" % ("one" if side == rules.PLAYER_ONE else "two"))
        return "\n".join(lines)


def _simple_steps(board, square, piece, side):
    """Quiet moves for one piece, as one-hop paths."""
    row, column = divmod(square, SIZE)
    paths = []
    for drow, dcolumn in DIAGONALS:
        if not is_king(piece) and drow != forward_rows(side):
            continue
        new_row, new_column = row + drow, column + dcolumn
        if not on_board(new_row, new_column):
            continue
        target = new_row * SIZE + new_column
        if board[target] == EMPTY:
            paths.append((square, target))
    return paths


def _capture_chains(board, square, piece, side):
    """Every complete jump chain available to one piece.

    A chain ends where no further jump exists, or where a man has just crowned. Returning whole
    chains means one move is one turn. The search never sees a half-finished capture.
    """
    chains = []
    _extend(board, square, piece, side, (square,), chains)
    return chains


def _extend(board, square, piece, side, path, chains):
    row, column = divmod(square, SIZE)
    grew = False

    for drow, dcolumn in DIAGONALS:
        if not is_king(piece) and drow != forward_rows(side):
            continue
        over_row, over_column = row + drow, column + dcolumn
        land_row, land_column = row + 2 * drow, column + 2 * dcolumn
        if not on_board(land_row, land_column):
            continue

        over = over_row * SIZE + over_column
        landing = land_row * SIZE + land_column
        if board[landing] != EMPTY:
            continue
        captured = board[over]
        if owner(captured) is None or owner(captured) == side:
            continue

        grew = True
        stepped = list(board)
        stepped[square] = EMPTY
        stepped[over] = EMPTY
        stepped[landing] = piece

        crowned = not is_king(piece) and land_row == (SIZE - 1 if side == rules.PLAYER_ONE else 0)
        if crowned:
            # Crowning ends the turn. A man that has just become a king does not carry on jumping in
            # the same move under standard rules.
            chains.append(tuple(path) + (landing,))
            continue

        _extend(tuple(stepped), landing, piece, side, tuple(path) + (landing,), chains)

    if not grew and len(path) > 1:
        chains.append(tuple(path))


def endgame(one_pieces, two_pieces):
    """A position built from named pieces. An example can measure a solvable ending.

    Each entry is (row, column, MAN or KING). Rows count from PLAYER_ONE's back rank. The position is
    returned with PLAYER_ONE to move.
    """
    board = [EMPTY] * SQUARES
    for row, column, kind in one_pieces:
        board[row * SIZE + column] = PIECES[(rules.PLAYER_ONE, kind)]
    for row, column, kind in two_pieces:
        board[row * SIZE + column] = PIECES[(rules.PLAYER_TWO, kind)]
    return (tuple(board), rules.PLAYER_ONE)
