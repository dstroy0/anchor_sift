#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""A played board as points carrying values: one square is a point and the piece on it is its value.

The arithmetic downstream is the same arithmetic every other subject in this work uses, and it never
learns that a board exists. What sits here is the knowledge that makes a board a board: that squares
are laid out on a grid and flattening one costs its second dimension, that Reversi flips a bracketed
run and therefore cannot leave an isolated piece, and that a corner can never be flipped once taken.

The reason this subject is worth having is that a board separates two things every corpus in this
work holds welded together. A text carries its grammar and its author at once. A board carries the
rules, which are fixed and public, and the play, which is a choice. Two players of different strength
on the same rules give two corpora differing in the second alone, and both differ from a scatter of
the same pieces by the first. Nothing else here can vary one of those and hold the other.
"""

import random

# Side of the Reversi board. The game is defined on eight and nothing here generalizes it.
SIDE = 8

EMPTY, BLACK, WHITE = 0, 1, 2

# The eight directions a bracket can run in.
STEPS = ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1))

# Squares that can never be flipped once taken, which is the one piece of strategy in this file and
# is here because a player that knows it is the strong arm of the comparison.
CORNERS = ((0, 0), (0, SIDE - 1), (SIDE - 1, 0), (SIDE - 1, SIDE - 1))


def opening():
    """The four centre pieces Reversi starts from."""
    grid = bytearray(SIDE * SIDE)
    half = SIDE // 2
    grid[((half - 1) * SIDE) + (half - 1)] = WHITE
    grid[((half - 1) * SIDE) + half] = BLACK
    grid[(half * SIDE) + (half - 1)] = BLACK
    grid[(half * SIDE) + half] = WHITE
    return grid


def flips(grid, row, column, colour):
    """Squares a move would turn over, empty where the move is illegal."""
    if grid[(row * SIDE) + column] != EMPTY:
        return []
    other = WHITE if colour == BLACK else BLACK
    taken = []
    for down, across in STEPS:
        run = []
        step_row, step_column = row + down, column + across
        while (0 <= step_row < SIDE) and (0 <= step_column < SIDE):
            here = grid[(step_row * SIDE) + step_column]
            if here == other:
                run.append((step_row, step_column))
            elif here == colour:
                taken.extend(run)
                break
            else:
                break
            step_row += down
            step_column += across
    return taken


def legal(grid, colour):
    """Every move available to one colour, as (row, column, squares it turns over)."""
    out = []
    for row in range(SIDE):
        for column in range(SIDE):
            turned = flips(grid, row, column, colour)
            if turned:
                out.append((row, column, turned))
    return out


def apply_move(grid, row, column, colour, turned):
    """The board after a move, leaving the one handed in untouched."""
    out = bytearray(grid)
    out[(row * SIDE) + column] = colour
    for step_row, step_column in turned:
        out[(step_row * SIDE) + step_column] = colour
    return out


def pick_random(moves, rng):
    """Any legal move, drawn uniformly. This arm knows the rules and nothing else."""
    return moves[rng.randrange(len(moves))]


def pick_greedy(moves, rng):
    """The move turning over the most pieces. The textbook weak heuristic, and it is weak here too."""
    best = max(len(move[2]) for move in moves)
    tied = [move for move in moves if len(move[2]) == best]
    return tied[rng.randrange(len(tied))]


def pick_corner(moves, rng):
    """A corner where one is available, otherwise the move turning over the fewest pieces.

    Both halves are standard and both are knowledge the other two arms do not have: a corner cannot
    be flipped back, and turning over fewer pieces early leaves the opponent fewer legal replies.
    """
    for move in moves:
        if (move[0], move[1]) in CORNERS:
            return move
    fewest = min(len(move[2]) for move in moves)
    tied = [move for move in moves if len(move[2]) == fewest]
    return tied[rng.randrange(len(tied))]


ARMS = {"random": pick_random, "greedy": pick_greedy, "corner": pick_corner}


def play(black, white, seed=0):
    """One game to the end. Returns every position that occurred, and the final piece counts."""
    rng = random.Random(seed)
    grid = opening()
    colour = BLACK
    seen = [bytes(grid)]
    passes = 0
    while passes < 2:
        moves = legal(grid, colour)
        if not moves:
            passes += 1
        else:
            passes = 0
            chooser = black if colour == BLACK else white
            row, column, turned = chooser(moves, rng)
            grid = apply_move(grid, row, column, colour, turned)
            seen.append(bytes(grid))
        colour = WHITE if colour == BLACK else BLACK
    counts = (sum(1 for cell in grid if cell == BLACK), sum(1 for cell in grid if cell == WHITE))
    return seen, counts


def occupied_seats(grid):
    """The occupied squares of one board, read in row major order.

    Empty squares are dropped rather than given a symbol of their own. A board part way through a
    game is mostly empty, and a symbol for emptiness would put the game's clock into the histogram
    and be read as arrangement.
    """
    return bytearray(cell for cell in grid if cell != EMPTY)


def seats_row_major(grid):
    """Every square including the empty ones, row major. The flattening the width sweep reads."""
    return bytearray(grid)


def seats_column_major(grid):
    """The same board read down the columns instead of across the rows."""
    out = bytearray(SIDE * SIDE)
    index = 0
    for column in range(SIDE):
        for row in range(SIDE):
            out[index] = grid[(row * SIDE) + column]
            index += 1
    return out


def scattered(grid, seed=0):
    """The same pieces on the same squares in a uniformly drawn arrangement.

    This is the null for a board and it is the null permutation of this work, written for a grid.
    It keeps how many of each colour are on the board and which squares are occupied at all, and
    destroys only which colour sits where. Everything a rule imposed is in what it destroys.
    """
    cells = [index for index, cell in enumerate(grid) if cell != EMPTY]
    colours = [grid[index] for index in cells]
    random.Random(seed).shuffle(colours)
    out = bytearray(grid)
    for index, colour in zip(cells, colours):
        out[index] = colour
    return out
