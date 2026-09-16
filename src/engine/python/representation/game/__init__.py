#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Games as a subject: a position written as points carrying values.

Two kinds of object live here and they are not the same kind of evidence.

`board` holds a played game. A square is a point, the piece on it is its value, and the null is the
same pieces on the same squares in a drawn order. A board is the only corpus in this work where the
two things that make an object can be varied separately: the rules are fixed and public and the play
is a choice, and two players of different strength on one rule set differ in the second alone.

`combinatorial` holds an impartial game, where a position is an index and its value is the Grundy
number sitting on it. This is the subject that answers a question the workbook has had open since it
was written. Every reach claim in this work is quantified over a set nobody has enumerated, and
closing one needs a controlled series inside one domain with an outside answer attached to every
row. Subtraction games supply exactly that: the arithmetic to make a row is free, the number of rows
is unbounded, and the answer each row is scored against is a theorem and not a reading. Nim's is
Bouton's from 1901 and Wythoff's is Wythoff's from 1907.

Nothing downstream of this directory learns that a game exists.
"""
