#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Chess: the backend that cannot be solved, and is here for exactly that reason.
#
#   Usage:  from representation.game import chess
#           game = chess.Chess()
#           state = chess.from_layout(chess.OPENING)
#
# Blackjack, checkers endgames and small deck poker all have a true answer this tree can compute. A
# chess position after four plies has more continuations than the other three games have positions,
# so here the outcome distribution has to be estimated. That is the point of including it. An
# estimator that is wrong on blackjack is caught immediately; an estimator that is wrong on chess is
# not caught by anything local. The only thing standing behind a chess number is whether the same
# estimator reproduced the solved games. This backend is where the measurement stops being checkable
# and starts having to be trusted, and the subject exists to make that boundary visible rather than
# to hide it.
#
# The rules are complete: castling with its four conditions, en passant, promotion to all four
# pieces, check, checkmate and stalemate. They are complete because an incomplete move generator
# produces a number that looks exactly like a correct one. A missing en passant does not raise, it
# quietly shifts a distribution, and nothing downstream can tell.
#
# Not modeled: the fifty move rule, threefold repetition and insufficient material. Each of those
# turns a long game into a draw, and this subject reports a game the budget did not finish as
# UNRESOLVED. Folding them in would move mass onto DRAW for positions the
# search never actually resolved, which is the one thing the enumerator is built not to do.

from representation.game import rules

EMPTY = 0
PAWN = 1
KNIGHT = 2
BISHOP = 3
ROOK = 4
QUEEN = 5
KING = 6

SIZE = 8
SQUARES = SIZE * SIZE

GLYPHS = {0: ".", 1: "P", 2: "N", 3: "B", 4: "R", 5: "Q", 6: "K"}

KNIGHT_STEPS = ((1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2))
KING_STEPS = ((1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1))
BISHOP_RAYS = ((1, 1), (1, -1), (-1, 1), (-1, -1))
ROOK_RAYS = ((1, 0), (-1, 0), (0, 1), (0, -1))

PROMOTIONS = (QUEEN, ROOK, BISHOP, KNIGHT)

# Castling rights, indexed into a four-tuple carried in the state.
ONE_SHORT = 0
ONE_LONG = 1
TWO_SHORT = 2
TWO_LONG = 3

# The opening array, rank 1 at the bottom for PLAYER_ONE. Written out rather than generated so it can
# be read and checked by eye.
OPENING = (
    "rnbqkbnr",
    "pppppppp",
    "........",
    "........",
    "........",
    "........",
    "PPPPPPPP",
    "RNBQKBNR",
)

LETTERS = {"p": PAWN, "n": KNIGHT, "b": BISHOP, "r": ROOK, "q": QUEEN, "k": KING}


def owner(piece):
    if piece > 0:
        return rules.PLAYER_ONE
    if piece < 0:
        return rules.PLAYER_TWO
    return None


def on_board(row, column):
    return 0 <= row < SIZE and 0 <= column < SIZE


def from_layout(rows, side=rules.PLAYER_ONE, rights=(True, True, True, True), passing=-1):
    """A position from eight text rows, rank 8 first. Uppercase is PLAYER_ONE, lowercase PLAYER_TWO.

    The rows read top down the way a board is drawn. A position written here looks like the
    position it is. Rights and the en passant square default to a full-rights opening; a fragment
    position should pass rights explicitly.
    """
    board = [EMPTY] * SQUARES
    for index, text in enumerate(rows):
        row = SIZE - 1 - index
        for column, glyph in enumerate(text):
            if glyph == ".":
                continue
            kind = LETTERS[glyph.lower()]
            board[row * SIZE + column] = kind if glyph.isupper() else -kind
    return (tuple(board), side, tuple(rights), passing)


class Chess(object):
    """The chess backend. States are (board, side, castling rights, en passant square)."""

    name = "chess"

    def initial(self):
        return from_layout(OPENING)

    def to_move(self, state):
        return state[1]

    def weights(self, state):
        raise NotImplementedError("chess has no chance nodes")

    def moves(self, state):
        """Legal moves: pseudo-legal generation filtered by whether the mover's king survives it."""
        board, side, _, _ = state
        legal = []
        for move in _pseudo_legal(state):
            reached = self.apply(state, move)
            if not _in_check(reached[0], side):
                legal.append(move)
        return legal

    def apply(self, state, move):
        board, side, rights, passing = state
        origin, target, promotion = move
        squares = list(board)
        piece = squares[origin]
        kind = abs(piece)

        squares[origin] = EMPTY

        # En passant capture removes a pawn that is not on the target square.
        if kind == PAWN and target == passing and squares[target] == EMPTY:
            captured_row = target // SIZE + (-1 if side == rules.PLAYER_ONE else 1)
            squares[captured_row * SIZE + target % SIZE] = EMPTY

        # Castling moves the rook as part of the king's move.
        if kind == KING and abs(target % SIZE - origin % SIZE) == 2:
            row = origin // SIZE
            if target % SIZE > origin % SIZE:
                squares[row * SIZE + 5] = squares[row * SIZE + 7]
                squares[row * SIZE + 7] = EMPTY
            else:
                squares[row * SIZE + 3] = squares[row * SIZE + 0]
                squares[row * SIZE + 0] = EMPTY

        if promotion:
            piece = promotion if side == rules.PLAYER_ONE else -promotion

        squares[target] = piece

        new_passing = -1
        if kind == PAWN and abs(target // SIZE - origin // SIZE) == 2:
            new_passing = (origin + target) // 2

        return (
            tuple(squares),
            rules.PLAYER_TWO if side == rules.PLAYER_ONE else rules.PLAYER_ONE,
            _update_rights(rights, origin, target),
            new_passing,
        )

    def verdict(self, state):
        """Checkmate and stalemate, read from PLAYER_ONE's side.

        A side with no legal move has either been mated or stalemated, and which one it is depends
        only on whether its king is attacked. Nothing else ends a game here; a position the budget
        does not resolve comes back UNRESOLVED from the enumerator instead.
        """
        side = state[1]
        if self.moves(state):
            return None
        if _in_check(state[0], side):
            return rules.LOSS if side == rules.PLAYER_ONE else rules.WIN
        return rules.DRAW

    def describe(self, state):
        board, side, rights, passing = state
        lines = []
        for row in range(SIZE - 1, -1, -1):
            text = ""
            for column in range(SIZE):
                piece = board[row * SIZE + column]
                glyph = GLYPHS[abs(piece)]
                text += glyph if piece > 0 else glyph.lower() if piece < 0 else "."
            lines.append(text)
        lines.append(
            "to move: %s  rights: %s  ep: %d"
            % ("one" if side == rules.PLAYER_ONE else "two", "".join(
                letter for letter, held in zip("KQkq", rights) if held
            ) or "-", passing)
        )
        return "\n".join(lines)


def _update_rights(rights, origin, target):
    """Castling rights after a move, lost by the king or rook moving or by the rook being taken."""
    held = list(rights)
    for square in (origin, target):
        if square == 4:
            held[ONE_SHORT] = held[ONE_LONG] = False
        elif square == 60:
            held[TWO_SHORT] = held[TWO_LONG] = False
        elif square == 7:
            held[ONE_SHORT] = False
        elif square == 0:
            held[ONE_LONG] = False
        elif square == 63:
            held[TWO_SHORT] = False
        elif square == 56:
            held[TWO_LONG] = False
    return tuple(held)


def _pseudo_legal(state):
    """Every move the pieces can make, before asking whether the mover's own king survives it."""
    board, side, rights, passing = state
    found = []
    forward = 1 if side == rules.PLAYER_ONE else -1
    start_row = 1 if side == rules.PLAYER_ONE else 6
    last_row = 7 if side == rules.PLAYER_ONE else 0

    for square in range(SQUARES):
        piece = board[square]
        if owner(piece) != side:
            continue
        row, column = divmod(square, SIZE)
        kind = abs(piece)

        if kind == PAWN:
            step = row + forward
            if on_board(step, column) and board[step * SIZE + column] == EMPTY:
                _add_pawn(found, square, step * SIZE + column, step == last_row)
                jump = row + 2 * forward
                if row == start_row and board[jump * SIZE + column] == EMPTY:
                    found.append((square, jump * SIZE + column, 0))
            for side_step in (-1, 1):
                new_column = column + side_step
                if not on_board(step, new_column):
                    continue
                target = step * SIZE + new_column
                if owner(board[target]) == _other(side):
                    _add_pawn(found, square, target, step == last_row)
                elif target == passing:
                    found.append((square, target, 0))

        elif kind == KNIGHT:
            for drow, dcolumn in KNIGHT_STEPS:
                _add_step(found, board, side, square, row + drow, column + dcolumn)

        elif kind == KING:
            for drow, dcolumn in KING_STEPS:
                _add_step(found, board, side, square, row + drow, column + dcolumn)
            _add_castles(found, board, side, rights, square)

        else:
            rays = []
            if kind in (BISHOP, QUEEN):
                rays.extend(BISHOP_RAYS)
            if kind in (ROOK, QUEEN):
                rays.extend(ROOK_RAYS)
            for drow, dcolumn in rays:
                distance = 1
                while True:
                    new_row, new_column = row + drow * distance, column + dcolumn * distance
                    if not on_board(new_row, new_column):
                        break
                    target = new_row * SIZE + new_column
                    holder = owner(board[target])
                    if holder == side:
                        break
                    found.append((square, target, 0))
                    if holder is not None:
                        break
                    distance += 1

    return found


def _other(side):
    return rules.PLAYER_TWO if side == rules.PLAYER_ONE else rules.PLAYER_ONE


def _add_pawn(found, origin, target, promoting):
    """A pawn move, expanded into four moves where it reaches the last rank.

    All four promotions are generated and not just the queen. Underpromotion is rarely the best move
    and is occasionally the only one, and a generator that omits it is wrong in a way that never
    raises.
    """
    if promoting:
        for kind in PROMOTIONS:
            found.append((origin, target, kind))
    else:
        found.append((origin, target, 0))


def _add_step(found, board, side, origin, row, column):
    if not on_board(row, column):
        return
    target = row * SIZE + column
    if owner(board[target]) != side:
        found.append((origin, target, 0))


def _add_castles(found, board, side, rights, square):
    """Castling, with all four conditions checked.

    The rights tuple covers the king and rook never having moved. The rest is checked here: the
    squares between are empty, the king is not currently in check, and it does not pass through an
    attacked square on the way. Landing in check is caught by the legality filter like any other
    move.
    """
    row = 0 if side == rules.PLAYER_ONE else 7
    if square != row * SIZE + 4:
        return
    short, long_side = (ONE_SHORT, ONE_LONG) if side == rules.PLAYER_ONE else (TWO_SHORT, TWO_LONG)
    if _in_check(board, side):
        return

    if rights[short] and all(board[row * SIZE + column] == EMPTY for column in (5, 6)):
        if not _attacked(board, row * SIZE + 5, _other(side)):
            found.append((square, row * SIZE + 6, 0))
    if rights[long_side] and all(board[row * SIZE + column] == EMPTY for column in (1, 2, 3)):
        if not _attacked(board, row * SIZE + 3, _other(side)):
            found.append((square, row * SIZE + 2, 0))


def _in_check(board, side):
    """Whether this side's king stands on a square the other side attacks."""
    king = KING if side == rules.PLAYER_ONE else -KING
    for square in range(SQUARES):
        if board[square] == king:
            return _attacked(board, square, _other(side))

    # A board with no king is not a chess position. Report not in check. A
    # fragment position used in an example does not have to invent a king it does not need.
    return False


def _attacked(board, square, by_side):
    """Whether `by_side` attacks this square. Written as a reverse scan from the square itself."""
    row, column = divmod(square, SIZE)
    forward = 1 if by_side == rules.PLAYER_ONE else -1

    # A pawn attacks diagonally forward. From the square's view it sits diagonally backward.
    for side_step in (-1, 1):
        new_row, new_column = row - forward, column + side_step
        if on_board(new_row, new_column):
            piece = board[new_row * SIZE + new_column]
            if owner(piece) == by_side and abs(piece) == PAWN:
                return True

    for drow, dcolumn in KNIGHT_STEPS:
        new_row, new_column = row + drow, column + dcolumn
        if on_board(new_row, new_column):
            piece = board[new_row * SIZE + new_column]
            if owner(piece) == by_side and abs(piece) == KNIGHT:
                return True

    for drow, dcolumn in KING_STEPS:
        new_row, new_column = row + drow, column + dcolumn
        if on_board(new_row, new_column):
            piece = board[new_row * SIZE + new_column]
            if owner(piece) == by_side and abs(piece) == KING:
                return True

    for rays, sliders in ((BISHOP_RAYS, (BISHOP, QUEEN)), (ROOK_RAYS, (ROOK, QUEEN))):
        for drow, dcolumn in rays:
            distance = 1
            while True:
                new_row, new_column = row + drow * distance, column + dcolumn * distance
                if not on_board(new_row, new_column):
                    break
                piece = board[new_row * SIZE + new_column]
                if piece != EMPTY:
                    if owner(piece) == by_side and abs(piece) in sliders:
                        return True
                    break
                distance += 1

    return False


def square_name(square):
    """Algebraic name of a square. A printed move is one a reader can find on a board."""
    return "abcdefgh"[square % SIZE] + str(square // SIZE + 1)


def move_name(move):
    origin, target, promotion = move
    text = square_name(origin) + square_name(target)
    if promotion:
        text += GLYPHS[promotion].lower()
    return text
