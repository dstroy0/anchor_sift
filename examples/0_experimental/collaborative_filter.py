#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-002
#
# Collaborative filtering: fill a hole in a table from the rows that agree with its row.
#
#   Usage:  python examples/0_experimental/collaborative_filter.py
#
# This reads no corpus. It sits in 0_experimental: an algorithm shown working, a recommender-systems
# filter beside the signal ones. It is the group-mean estimate the denoisers use, over a table with
# holes: to fill a missing entry, find the rows that agree with its row wherever both have values, and
# average what those neighbors put in the missing column.
#
# It is application logic, not an engine primitive, and it lives here. A
# group-mean is the signal estimate a reading is measured INTO. A denoiser OUTPUTS it; nothing outputs
# a null. Same mathematical form, opposite role. The estimate is application and only the null is a
# reference-stage object.
#
# TWO ROUTES THAT CAN GENUINELY DISAGREE: the field's own two methods. User-based filtering averages
# down the missing column over the ROWS that agree; item-based averages across the row over the COLUMNS
# that agree. They read the table along different axes and
# share no traversal. On a table that is a row effect plus a column effect they return the same value
# to the last digit; on a table with no such structure they disagree, and the disagreement is the
# finding. Nothing is bounded: agreement is exact equality on the overlap. There is
# no similarity cutoff; a row whose effect is unique has no neighbors and its holes are left unfilled.

import io
import os
import sys
from fractions import Fraction

MISSING = None


def agrees_on_overlap(left, right):
    shared = 0
    for a, b in zip(left, right):
        if (a is not MISSING) and (b is not MISSING):
            shared += 1
            if a != b:
                return shared, False
    return shared, True


def row_neighbours(matrix, target):
    here = matrix[target]
    found = []
    for other in range(len(matrix)):
        if other == target:
            continue
        shared, agreed = agrees_on_overlap(here, matrix[other])
        if agreed and shared:
            found.append(other)
    return found


def predict_user(matrix, row, column):
    values = [
        matrix[other][column]
        for other in row_neighbours(matrix, row)
        if matrix[other][column] is not MISSING
    ]
    return Fraction(sum(values), len(values)) if values else None


def transpose(matrix):
    return [[matrix[r][c] for r in range(len(matrix))] for c in range(len(matrix[0]))]


def predict_item(matrix, row, column):
    return predict_user(transpose(matrix), column, row)


def additive_table(users, items, hold_out):
    """value[r][c] = u[r] + v[c], with effects shared across several rows and columns so neighbors
    exist, and a held-out set of entries set MISSING. Returns the holed table and the clean values.
    """
    u = [((r % users) + 1) * 10 for r in range(users * 2)]  # two rows per user effect
    v = [((c % items) + 1) * 3 for c in range(items * 2)]  # two columns per item effect
    clean = [[u[r] + v[c] for c in range(len(v))] for r in range(len(u))]
    holed = [list(row) for row in clean]
    step = 0
    held = []
    for r in range(len(u)):
        for c in range(len(v)):
            step += 1
            if step % hold_out == 0:
                holed[r][c] = MISSING
                held.append((r, c))
    return holed, clean, held


def main():
    out = io.TextIOWrapper(
        sys.stdout.buffer, encoding="utf-8", errors="replace", newline=""
    )
    out.write("  collaborative filtering: the group-mean over a table with holes\n")
    out.write(
        "  declared inputs: user effects=4 item effects=4, every 5th entry held out\n\n"
    )

    holed, clean, held = additive_table(4, 4, hold_out=5)
    user_ok = item_ok = agree = declined = 0
    for r, c in held:
        pu = predict_user(holed, r, c)
        pi = predict_item(holed, r, c)
        if pu is None or pi is None:
            declined += 1
            continue
        user_ok += pu == clean[r][c]
        item_ok += pi == clean[r][c]
        agree += pu == pi
    filled = len(held) - declined
    out.write(
        "  positive control (row effect + column effect), %d held-out entries:\n"
        % len(held)
    )
    out.write("    user-based recovered exactly:  %d / %d\n" % (user_ok, filled))
    out.write("    item-based recovered exactly:  %d / %d\n" % (item_ok, filled))
    out.write("    the two routes agreed:         %d / %d\n" % (agree, filled))
    out.write("    declined (no neighbor):       %d\n" % declined)

    # the routes must be able to disagree, or their agreeing is empty. A broken user-route that
    # averages the WHOLE column instead of the neighbourhood splits from the honest one.
    def broken_user(matrix, row, column):
        seen = [
            matrix[r][column]
            for r in range(len(matrix))
            if r != row and matrix[r][column] is not MISSING
        ]
        return Fraction(sum(seen), len(seen)) if seen else None

    r0, c0 = held[0]
    splits = broken_user(holed, r0, c0) != predict_user(holed, r0, c0)
    out.write(
        "\n  divergence probe: a broken route (whole-column mean) splits from the honest one: %s\n"
        % splits
    )

    # null: a table with no row+column structure -- no exact neighbor exists. Both routes DECLINE
    rng_state = 0x51F7
    noise = [[0] * 8 for _ in range(8)]
    for r in range(8):
        for c in range(8):
            rng_state = (1103515245 * rng_state + 12345) & 0x7FFFFFFF
            noise[r][c] = rng_state % 100
    holed_noise = [list(row) for row in noise]
    holed_noise[0][0] = MISSING
    pu = predict_user(holed_noise, 0, 0)
    pi = predict_item(holed_noise, 0, 0)
    out.write(
        "  null: a table with no row+column structure -> user says %s, item says %s\n"
        % (pu, pi)
    )
    out.write("  neither finds an exact neighbor. Both decline.\n")
    out.write(
        "\n  on the structured table both routes land on the same rational and it is the clean\n"
    )
    out.write(
        "  value; they are different computations, rows against columns, that coincide only\n"
    )
    out.write(
        "  because the structure is real. the floor is a row whose effect is unique: no neighbor,\n"
    )
    out.write("  so the hole is left.\n")
    out.flush()
    return (
        0
        if (
            user_ok == filled
            and item_ok == filled
            and agree == filled
            and filled > 0
            and splits
            and pu is None
            and pi is None
        )
        else 1
    )


if __name__ == "__main__":
    raise SystemExit(main())
