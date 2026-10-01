"""Emits the device's constants header FROM the constants table, so nothing is typed by hand.

    python tools/dn_precision/emit_device_constants.py

WHY THIS EXISTS

`qengine.cu` carried pi as hexadecimal limbs somebody typed in. That is a second copy of a number
this tree already holds to a thousand places, agreed by two independent routes with a last-digit gap
of zero, and a typed copy is one transposition away from being wrong in a way no test would name:
every answer would simply be slightly off, consistently, and the engine would still look like it
worked.

So the header is GENERATED. `dn_constants.csv` is the source, the conversion is exact rational
arithmetic on the decimal text, and the emitted file says which row it came from and how many places
that row was agreed to.

THE CONVERSION IS EXACT AND IT IS NOT A ROUNDING

A decimal string is an exact rational. Multiplying the fractional part by two to the sixty-four and
taking the whole part is exactly the next limb, and what is left is exactly the remainder. Nothing
is rounded until the last limb, which is truncated rather than rounded to nearest so the value never
exceeds the true constant.
"""

import io
import os
import sys

from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TABLE = os.path.join(HERE, "dn_const", "dn_constants.csv")
HEADER = os.path.join(ROOT, "src", "device", "quantum", "qconstants.cuh")

LIMB_BITS = 64
FRACTION_LIMBS = 8          # 512 fractional bits, more than any declared register width uses

WANTED = ("pi", "root_two", "root_three", "root_five", "golden_ratio", "e", "ln_two")


def table_rows(path):
    """The constants table, as {name: (value text, agreed digits)}. Its own CSV, read plainly."""
    rows = {}
    body = io.open(path, encoding="utf-8").read().splitlines()
    header = body[0].split(",")
    name_at = header.index("name")
    agreed_at = header.index("agreed_digits")
    value_at = header.index("value")
    for line in body[1:]:
        # The value is the last field and carries no comma; the middle fields may be quoted, so the
        # split is done from both ends rather than by a CSV parser this tree does not need.
        pieces = line.split(",")
        if len(pieces) <= max(name_at, agreed_at, value_at):
            continue
        name = pieces[name_at].strip()
        value = pieces[-1].strip()
        agreed = pieces[agreed_at].strip()
        if name and value:
            rows[name] = (value, agreed)
    return rows


def limbs_of(decimal_text, limbs=FRACTION_LIMBS):
    """(whole part, fractional limbs most significant first) from exact decimal text.

    Fraction over the text, so the decimal is the rational it actually is. Each limb is the whole
    part of the remainder times two to the sixty-four, which is exact.
    """
    value = Fraction(decimal_text)
    whole = int(value)
    rest = value - whole
    out = []
    for _ in range(limbs):
        rest *= (1 << LIMB_BITS)
        limb = int(rest)
        rest -= limb
        out.append(limb)
    return whole, out


def main():
    if not os.path.exists(TABLE):
        sys.stderr.write("the constants table is not at %s\n" % TABLE)
        return 1
    rows = table_rows(TABLE)

    lines = []
    lines.append("/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>")
    lines.append(" * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR "
                 "LicenseRef-Educational")
    lines.append(" *")
    lines.append(" * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, "
                 "which is either a")
    lines.append(" * negotiated commercial licensing contract or an educator's license issued to "
                 "you personally.")
    lines.append(" */")
    lines.append("/**")
    lines.append(" * @file qconstants.cuh")
    lines.append(" * @brief GENERATED from dn_const/dn_constants.csv. Do not edit; regenerate.")
    lines.append(" * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>")
    lines.append(" *")
    lines.append(" * Emitted by tools/dn_precision/emit_device_constants.py. Every value below came")
    lines.append(" * from the constants table, which holds each to a thousand places agreed by two")
    lines.append(" * independent routes. Nothing here was typed by hand, which is the point: a")
    lines.append(" * transposed hex digit in a constant makes every answer slightly and")
    lines.append(" * consistently wrong, and no test in this tree would name it.")
    lines.append(" *")
    lines.append(" * @note %d fractional limbs of %d bits, which is %d fractional bits, more than"
                 % (FRACTION_LIMBS, LIMB_BITS, FRACTION_LIMBS * LIMB_BITS))
    lines.append(" *       any declared register width uses. A register takes the leading limbs.")
    lines.append(" */")
    lines.append("")
    lines.append("#ifndef QCONSTANTS_CUH")
    lines.append("#define QCONSTANTS_CUH")
    lines.append("")
    lines.append("#include <cstdint>")
    lines.append("")
    lines.append("/** @brief Fractional limbs each constant below carries. */")
    lines.append("#define CONSTANT_FRACTION_LIMBS %du" % FRACTION_LIMBS)
    lines.append("")

    emitted = 0
    for name in WANTED:
        if name not in rows:
            continue
        value, agreed = rows[name]
        whole, fraction = limbs_of(value)
        upper = name.upper()
        lines.append("/** @brief %s, whole part. From dn_constants.csv, agreed to %s places. */"
                     % (name, agreed))
        lines.append("#define CONSTANT_%s_WHOLE %dULL" % (upper, whole))
        lines.append("/** @brief %s, fractional limbs, most significant first. */" % name)
        lines.append("__constant__ uint64_t DEVICE_%s_FRACTION[CONSTANT_FRACTION_LIMBS] = {"
                     % upper)
        for at in range(0, FRACTION_LIMBS, 3):
            piece = ", ".join("0x%016XULL" % one for one in fraction[at:at + 3])
            lines.append("    %s%s" % (piece, "," if (at + 3) < FRACTION_LIMBS else ""))
        lines.append("};")
        lines.append("static const uint64_t HOST_%s_FRACTION[CONSTANT_FRACTION_LIMBS] = {" % upper)
        for at in range(0, FRACTION_LIMBS, 3):
            piece = ", ".join("0x%016XULL" % one for one in fraction[at:at + 3])
            lines.append("    %s%s" % (piece, "," if (at + 3) < FRACTION_LIMBS else ""))
        lines.append("};")
        lines.append("")
        emitted += 1

    lines.append("#endif /* QCONSTANTS_CUH */")
    io.open(HEADER, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")

    print("")
    print("  emitted %d constants from %s" % (emitted, os.path.relpath(TABLE, ROOT)))
    print("  into    %s" % os.path.relpath(HEADER, ROOT))
    for name in WANTED:
        if name in rows:
            value, agreed = rows[name]
            whole, fraction = limbs_of(value)
            print("    %-14s agreed to %-6s places   %d.%016X%016X..."
                  % (name, agreed, whole, fraction[0], fraction[1]))
    print("")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
