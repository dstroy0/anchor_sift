#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""A game as a subject: a position, the moves out of it, and the outcomes they reach.

The arithmetic inside is counting. What makes it a subject is the knowledge around it: that a knight
leaves a square no other piece can leave it by, that a checkers man promotes on the far rank and
then moves backward, that a dealt card is gone from the deck, and that a hand of poker is decided by
a ranking nobody here invented.

That last property is why this subject is here. A game carries its own answer key. A terminal
position is win, loss or draw by the rules of the game and not by anything measured. The outcome
distribution under a move is a quantity with a right value. For a game small enough to enumerate,
that right value can be computed outright  and an estimator that disagrees
with it is wrong in a way no amount of sampling can argue with.

Four backends live here and they are deliberately different in kind:

    blackjack   chance dominated, one player against a fixed dealer rule, small enough to solve
    checkers    perfect information, no chance, endgames small enough to solve
    poker       chance and hidden information, decided by an external hand ranking
    chess       perfect information, no chance, and far too large to solve

The first three give a solved arm. Chess does not, and that is the point of including it: it is the
only one of the four where the number has to be estimated. It is the only one where the estimator
can be wrong without the disagreement showing up locally.

Every backend exposes the same six calls and nothing else. The measurement code never learns
which game it is reading. See `rules.py` for the protocol those calls satisfy.
"""
