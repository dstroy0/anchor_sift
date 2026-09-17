#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The first move, read as a per-player winning-path entropy, and why the exact answer is a
# tablebase, not a search.
#
#   Usage:  python examples/game_theory/6_oracle/first_move_advantage.py
#
# THE QUESTION. Does the side that moves first have an advantage? The move-sequence tree is the
# wrong place to look: it is unbounded, and a bounded search folds a horizon into the number. This
# subject refuses exactly that, so the question is put as a magnitude instead.
#
# THE WINDICATOR. Each player carries one number, its winning-path mass: the probability that play
# from this position reaches THAT player's win, an exact Fraction in [0, 1]. It closes to 1 as a win
# becomes forced and rests at 0 when no winning path survives. A winning path bottoms out where the
# opponent has no legal move (checkmate is verdict()==WIN/LOSS with no reply). The two windicators
# are separate state, one per player, from PLAYER_ONE's and PLAYER_TWO's own side.
#
# WHY THE MAGNITUDE ALONE CANNOT ANSWER IT. The sum of the two windicators is invariant under
# swapping the players; the first-move advantage is ODD under that swap -- give the move to the other
# side and the advantage flips sign. A quantity that is odd under a symmetry is invisible to any
# quantity that is even under it. So the advantage lives in the SIGNED difference V(side to move)
# minus V(if the other side moved), never in the magnitude. This is the same fact a reflection-
# invariant magnitude has about chirality: it is exact for what the symmetry preserves and blind to
# what the symmetry flips.
#
# WHY THE TREE IS FINITE WITHOUT A HORIZON. Real tournament rules end a non-progressing line by the
# game's OWN rule, not by a depth cap the analyst chose: threefold repetition (the rule for a draw of
# exactly this cyclic type), the fifty-move rule, and insufficient material. A line that engine
# chess.py leaves UNRESOLVED forever coalesces to an exact DRAW under these. That is not bounding: the
# rule belongs to chess, it is reported, and it is the same for every position.
#
# WHAT IS EXACT HERE AND WHAT IS NOT. The windicator on a fully resolved position is an exact
# rational. The bare-kings draw is exact by insufficient material. The repetition draw is exact. What
# is NOT delivered here is the exact windicator of a full king-and-pawn or king-and-rook ending: that
# is a retrograde solve over the coalesced position graph -- a tablebase -- because forward search
# explodes and a plain negamax memo is unsound once repetition makes a value depend on the path that
# reached it. That solve is named as the open work in theory/workbook, not folded into a number here.

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

import fractions  # noqa: E402

from representation.game import chess, rules  # noqa: E402

GAME = chess.Chess()
NO_RIGHTS = (False, False, False, False)
HALF = fractions.Fraction(1, 2)


# ---- tournament draw rules: the field's own finiteness, not an analyst's horizon ----

def is_pawn_or_capture(state, move):
    board = state[0]
    origin, target, _ = move
    return abs(board[origin]) == chess.PAWN or board[target] != chess.EMPTY


def insufficient_material(state):
    """A draw by rule when no mate is possible: bare kings, or a lone king plus one minor."""
    minors = 0
    for piece in state[0]:
        kind = abs(piece)
        if kind in (chess.PAWN, chess.ROOK, chess.QUEEN):
            return False
        if kind in (chess.KNIGHT, chess.BISHOP):
            minors += 1
    return minors <= 1


def tournament_verdict(state, halfmove, history):
    """WIN/LOSS/DRAW/None, extending engine chess.py with the tournament draw rules.

    `history` maps a state to how many times it has already occurred on this line; the third
    occurrence is threefold repetition. `halfmove` is plies since the last pawn move or capture.
    """
    verdict = GAME.verdict(state)
    if verdict is not None:
        return verdict
    if insufficient_material(state):
        return rules.DRAW
    if halfmove >= 100:
        return rules.DRAW  # fifty-move rule, counted in plies
    if history.get(state, 0) >= 2:
        return rules.DRAW  # threefold repetition
    return None


# ---- the windicator: per-player winning-path mass, an exact Fraction closing to 1 ----

def windicator(state, target, depth, halfmove, history, weight):
    """Exact winning-path mass for `target` from `state`, to `depth` plies, under uniform play.

    Uniform because the windicator reads what the position makes available, not what a chooser would
    do with it. A winning path is a line ending in `target`; its weight is the product of 1/branching
    along it. The tournament draw rules terminate cyclic and non-progressing lines exactly.
    """
    verdict = tournament_verdict(state, halfmove, history)
    if verdict is not None:
        return weight if verdict == target else fractions.Fraction(0)
    if depth <= 0:
        return fractions.Fraction(0)  # a horizon reached is not a win; mass here is not counted
    moves = GAME.moves(state)
    share = weight / len(moves)
    history[state] = history.get(state, 0) + 1
    total = fractions.Fraction(0)
    for move in moves:
        child = GAME.apply(state, move)
        nxt = 0 if is_pawn_or_capture(state, move) else halfmove + 1
        total += windicator(child, target, depth - 1, nxt, history, share)
    if history[state] == 1:
        del history[state]
    else:
        history[state] -= 1
    return total


def sampled_windicator(state, target, depth, trials, seed):
    """The windicator by a second route: uniform-random rollouts under the same tournament rules.

    This is the sampled arm. It answers the same question as `windicator` and converges to it; the
    gap is sampling error and shrinks with the trial count. The seed is an input of the measurement
    and is reported with the result, so the number is reproducible.
    """
    import random
    generator = random.Random(seed)
    wins = 0
    for _ in range(trials):
        current = state
        halfmove = 0
        history = {}
        # Check the verdict at every ply 0..depth, matching the enumerator, which reads the horizon
        # node too. A win landing on the last move must be counted, not dropped.
        for step in range(depth + 1):
            verdict = tournament_verdict(current, halfmove, history)
            if verdict is not None:
                if verdict == target:
                    wins += 1
                break
            if step == depth:
                break  # horizon reached with no verdict: not a win, as the enumerator counts it
            move = generator.choice(GAME.moves(current))
            history[current] = history.get(current, 0) + 1
            halfmove = 0 if is_pawn_or_capture(current, move) else halfmove + 1
            current = GAME.apply(current, move)
    return fractions.Fraction(wins, trials)


def per_move_paths(state, target, depth):
    """For the side to move, count how many of `target`'s winning paths survive under each move.

    A move is truthy if it keeps at least one winning path in its subtree and falsy if it prunes them
    all -- "the moves decide how many branches-to-win are pruned".
    """
    rows = []
    for move in GAME.moves(state):
        child = GAME.apply(state, move)
        history = {state: 1}
        nxt = 0 if is_pawn_or_capture(state, move) else 1
        mass = windicator(child, target, depth - 1, nxt, history, fractions.Fraction(1))
        rows.append((mass, move))
    return rows


# ---- demonstrations, all exact and all fast ----

MATE_IN_ONE = ("......k.", ".....ppp", "........", "........",
               "........", "........", ".....PPP", "....R.K.")
KRK = ("....k...", "........", "....K...", "........",
       "........", "........", "........", "R.......")
BARE_KINGS = ("....k...", "........", "........", "........",
              "........", "........", "........", "....K...")
# A knight shuffle that returns to its own start: the engine calls it ongoing forever; the
# repetition rule calls the third occurrence a draw.
REPEAT_START = ("......k.", "........", "........", "........",
                "........", "........", "........", "N....K..")
REPEAT_CYCLE = ("a1b3", "g8f8", "b3a1", "f8g8")  # White knight out and back, Black king out and back


def show_windicators(title, layout, depth, trials=0, seed=0):
    state = chess.from_layout(layout, rights=NO_RIGHTS)
    p1 = windicator(state, rules.WIN, depth, 0, {}, fractions.Fraction(1))
    p2 = windicator(state, rules.LOSS, depth, 0, {}, fractions.Fraction(1))
    print("")
    print("%s   (depth=%d plies)" % (title, depth))
    print("  windicator W(P1) = %-12s W(P2) = %-12s   signed W(P1)-W(P2) = %s"
          % (str(p1), str(p2), str(p1 - p2)))
    if trials:
        sampled = sampled_windicator(state, rules.WIN, depth, trials, seed)
        print("  two routes on W(P1): enumerated = %.6f, sampled = %.6f  (trials=%d seed=%d)"
              % (float(p1), float(sampled), trials, seed))
    rows = per_move_paths(state, rules.WIN, depth)
    truthy = [move for mass, move in rows if mass > 0]
    print("  P1 moves that keep a branch-to-win (truthy): %d of %d; the rest prune every one (falsy)"
          % (len(truthy), len(rows)))
    forced = [chess.move_name(move) for mass, move in rows if mass == 1]
    if forced:
        print("  moves that force the win outright (mass = 1): %s" % ", ".join(forced))


def show_repetition():
    print("")
    print("Threefold repetition: the field's own rule makes a cyclic line finite")
    state = chess.from_layout(REPEAT_START, rights=NO_RIGHTS)
    history = {state: 1}
    seq = REPEAT_CYCLE + REPEAT_CYCLE  # walk the four-ply cycle twice
    for text in seq:
        origin = "abcdefgh".index(text[0]) + (int(text[1]) - 1) * chess.SIZE
        target = "abcdefgh".index(text[2]) + (int(text[3]) - 1) * chess.SIZE
        move = next(m for m in GAME.moves(state) if m[0] == origin and m[1] == target)
        state = GAME.apply(state, move)
        history[state] = history.get(state, 0) + 1
    verdict = tournament_verdict(state, 8, history)
    print("  start position seen %d times after two cycles" % history[chess.from_layout(REPEAT_START, rights=NO_RIGHTS)])
    print("  engine verdict on the line: %s" % GAME.verdict(state))
    print("  tournament verdict on the line: %s" % verdict)


def show_bare_kings():
    print("")
    print("Bare kings: exact draw by insufficient material -- a game with NO first-move advantage")
    state = chess.from_layout(BARE_KINGS, rights=NO_RIGHTS)
    verdict = tournament_verdict(state, 0, {})
    print("  tournament verdict = %s, so both windicators are 0 and the signed difference is 0"
          % verdict)


def main():
    print("=" * 78)
    print("THE FIRST MOVE AS A WINNING-PATH WINDICATOR")
    print("=" * 78)
    show_bare_kings()
    show_repetition()
    show_windicators("MATE IN ONE -- the mover forces a win, the other side has no winning path",
                     MATE_IN_ONE, 3, trials=40000, seed=0x5E7)
    show_windicators("K+R vs K -- most moves prune every branch-to-win",
                     KRK, 4)
    print("")
    print("=" * 78)
    print("The theorem, and the open work")
    print("=" * 78)
    print(
        "The value of the move is V(side to move) - V(if the other side moved). It is POSITIVE where\n"
        "a tempo helps and NEGATIVE in zugzwang, where being forced to move loses -- so first-move\n"
        "advantage is a property measured per position, not a constant. The windicator is the\n"
        "instrument. Proving the sign for a whole ending is an exact retrograde solve over the\n"
        "coalesced position graph -- a repetition-aware tablebase -- which is named in the workbook as\n"
        "the open work and is not folded into a number here. Bare kings above is the tractable control\n"
        "where the answer is exact and the advantage is zero."
    )


if __name__ == "__main__":
    main()
