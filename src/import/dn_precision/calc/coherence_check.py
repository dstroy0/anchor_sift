#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The identities between the constants, checked against each other rather than each against itself.
#
#   Usage:  python tools/dn_precision/calc/coherence_check.py [--digits N]
#
# WHY THIS EXISTS AND WHAT IT CATCHES THAT THE TWO-ROUTE GAP DOES NOT
#
# Douglas, 2026-09-12: "remember these are all const that just get mutated in coherence."
#
# Every row in dn_constants.csv is verified by two routes agreeing to a zero gap. That is a check on
# one row at a time, and it has a blind spot that is easy to state: TWO ROUTES SHARING AN INPUT FAIL
# TOGETHER. Both gamma routes take ln 2. If ln 2 were wrong, or a machine noise event flipped a bit
# in it, both routes would move the same way and the gap would stay zero. The row would be wrong and
# every check on it would pass.
#
# The table is not seventy six independent numbers. It is one coherent structure, and the relations
# between its entries are exact:
#
#     two_pi = 2 pi                 zeta_two = pi^2 / 6           root_6 = root_2 root_3
#     pi_squared = pi^2             golden_ratio^2 = phi + 1      ln_ten = ln_two + ln_five
#
# None of those has a tolerance. They are identities, so the residual is either zero at the table's
# width or the table is inconsistent with itself. Checking them costs nothing and it reaches the one
# failure the per-row gap cannot see.
#
# MACHINE NOISE IS THE OTHER THING THIS REACHES. There is no ECC on consumer memory, a flipped
# bit during a multi-second big-integer computation is not impossible. A flip in the discarded guard
# digits is harmless. A flip in a reported digit of a SHARED input would survive the two-route gap
# and would break these identities, because they cross-link rows that were computed at different
# times by different code paths.
#
# THE RESIDUAL IS ALLOWED TO BE ONE UNIT AND NOT ZERO, AND THAT IS NOT A TOLERANCE.
#
# Every value in the table is floor(true value * 10^digits). Two floored values combined
# arithmetically carry the floors of their operands, an identity between them is exact only up to
# the units those floors dropped. The bound is derived per identity from how many floored values it
# touches and how they are combined, and it is stated in the table below rather than chosen. A
# residual larger than its derived bound is a finding.

import argparse
import csv
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY = os.path.dirname(HERE)
CSV_PATH = os.path.join(FAMILY, "dn_const", "dn_constants.csv")


def load(path=CSV_PATH):
    """The table as {name: (scaled integer, digits)}.

    The stored value is a decimal string with a point. It is read back to the same scaled integer
    the calculator produced, so nothing here reformats or rounds it.
    """
    out = {}
    with io.open(path, encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            digits = int(row["digits"])
            whole, _, rest = row["value"].partition(".")
            rest = (rest + "0" * digits)[:digits]
            out[row["name"]] = (int(whole + rest), digits)
    return out


def identities(table, scale, digits):
    """Every identity worth checking, as (name, left, right, bound, why the bound is that).

    `left` and `right` are scaled integers at `digits` places. The bound is the largest residual the
    dropped floors can produce, derived rather than picked.
    """
    def get(name):
        return table[name][0] if name in table else None

    out = []

    pi = get("pi")
    if pi is not None:
        # 2 pi: one floored value multiplied by an exact integer, so the floor is scaled by 2.
        if get("two_pi") is not None:
            out.append(("two_pi = 2 pi", get("two_pi"), 2 * pi, 2,
                        "one floor times an exact 2"))
        if get("half_pi") is not None:
            out.append(("2 half_pi = pi", 2 * get("half_pi"), pi, 2,
                        "one floor times an exact 2"))
        if get("four_pi") is not None:
            out.append(("four_pi = 4 pi", get("four_pi"), 4 * pi, 4,
                        "one floor times an exact 4"))
        if get("pi_squared") is not None:
            # A product of two floored values divided back by the scale drops at most pi + pi + 1
            # units, about 7 at this magnitude.
            out.append(("pi_squared = pi * pi", get("pi_squared"), (pi * pi) // scale, 8,
                        "two floors multiplied, each contributing its operand's magnitude"))
        if get("zeta_two") is not None:
            out.append(("6 zeta_two = pi^2", 6 * get("zeta_two"), (pi * pi) // scale, 16,
                        "a floor times 6 against a product of two floors"))

    # Roots: the defining identity is squaring back, which is what _power_row already does. What it
    # does NOT check is that DIFFERENT roots are consistent with each other.
    for left, right, product in (("root_2", "root_3", "root_6"),
                                 ("root_2", "root_5", "root_10"),
                                 ("root_2", "root_7", "root_14"),
                                 ("root_3", "root_5", "root_15"),
                                 ("root_2", "root_11", "root_22"),
                                 ("root_3", "root_7", "root_21")):
        if get(left) is not None and get(right) is not None and get(product) is not None:
            out.append(("%s = %s * %s" % (product, left, right),
                        get(product), (get(left) * get(right)) // scale, 8,
                        "two floors multiplied"))

    # Cube roots against each other.
    for left, right, product in (("cbrt_2", "cbrt_3", "cbrt_6"),
                                 ("cbrt_2", "cbrt_5", "cbrt_10"),
                                 ("cbrt_3", "cbrt_5", "cbrt_15"),
                                 ("cbrt_2", "cbrt_7", "cbrt_14")):
        if get(left) is not None and get(right) is not None and get(product) is not None:
            out.append(("%s = %s * %s" % (product, left, right),
                        get(product), (get(left) * get(right)) // scale, 8,
                        "two floors multiplied"))

    # The golden ratio is the one row that carries an identity nothing else in the table shares.
    phi = get("golden_ratio")
    if phi is not None:
        out.append(("phi^2 = phi + 1", (phi * phi) // scale, phi + scale, 8,
                    "a product of two floors against a floor plus an exact 1"))

    # Logarithms add, which crosses three independently computed rows.
    if get("ln_ten") is not None and get("ln_two") is not None and get("ln_five") is not None:
        out.append(("ln_ten = ln_two + ln_five", get("ln_ten"),
                    get("ln_two") + get("ln_five"), 3,
                    "three floors summed"))
    if get("ln_ten") is not None and get("log2_ten") is not None and get("ln_two") is not None:
        out.append(("log2_ten * ln_two = ln_ten", (get("log2_ten") * get("ln_two")) // scale,
                    get("ln_ten"), 8, "two floors multiplied against one"))
    if get("ln_two") is not None and get("ln_three") is not None:
        # ln 2 + ln 3 has no row, so this checks against ln 6 only if it exists.
        pass

    # root_two against root_2, which are two separate rows for the same number by two different
    # routes. If those ever disagree the table is holding one quantity twice, inconsistently.
    if get("root_two") is not None and get("root_2") is not None:
        out.append(("root_two = root_2, same number two rows",
                    get("root_two"), get("root_2"), 1, "two floors of one quantity"))
    if get("root_five") is not None and get("root_5") is not None:
        out.append(("root_five = root_5, same number two rows",
                    get("root_five"), get("root_5"), 1, "two floors of one quantity"))
    if get("root_three") is not None and get("root_3") is not None:
        out.append(("root_three = root_3, same number two rows",
                    get("root_three"), get("root_3"), 1, "two floors of one quantity"))

    return out


def main():
    parser = argparse.ArgumentParser(description="the identities between the constants")
    parser.add_argument("--table", default=CSV_PATH)
    args = parser.parse_args()

    if not os.path.exists(args.table):
        sys.stdout.write("  no table at %s\n" % args.table)
        return 1

    table = load(args.table)
    widths = {digits for _value, digits in table.values()}
    if len(widths) != 1:
        sys.stdout.write("  the table holds mixed widths %s, which this check cannot compare\n"
                         % sorted(widths))
        return 1
    digits = widths.pop()
    scale = 10 ** digits

    checks = identities(table, scale, digits)
    sys.stdout.write("\n")
    sys.stdout.write("  %d constants at %d places. %d identities between them.\n"
                     % (len(table), digits, len(checks)))
    sys.stdout.write("  A residual is the units of the last place by which an identity misses.\n")
    sys.stdout.write("  The bound is derived from how many floored values the identity touches.\n\n")
    sys.stdout.write("  %-44s %12s %8s %s\n" % ("identity", "residual", "bound", "verdict"))

    failed = 0
    worst = (0, "")
    for name, left, right, bound, _why in checks:
        residual = abs(left - right)
        ok = residual <= bound
        if not ok:
            failed += 1
        if residual > worst[0]:
            worst = (residual, name)
        sys.stdout.write("  %-44s %12d %8d %s\n"
                         % (name, residual, bound, "ok" if ok else "FAILS"))

    sys.stdout.write("\n")
    sys.stdout.write("  worst residual: %d units, on %s\n" % (worst[0], worst[1]))
    sys.stdout.write("\n")
    if failed:
        sys.stdout.write("  %d identity(s) FAILED. The table is inconsistent with itself, which no\n"
                         % failed)
        sys.stdout.write("  per-row two-route gap can detect: two routes sharing a wrong input agree.\n")
    else:
        sys.stdout.write("  Every identity holds inside its derived bound. The table is coherent as\n")
        sys.stdout.write("  one structure and not merely correct row by row, and a flipped bit in a\n")
        sys.stdout.write("  shared input would have broken one of these rather than passing quietly.\n")
    return failed


if __name__ == "__main__":
    sys.exit(main())
