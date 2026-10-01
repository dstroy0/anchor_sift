# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Emits qasm_pi.h: pi from representation.constants.naturals.pi, to the places the qasm fixed point needs.

    python utils/maint/engine/emit_qasm_pi.py            write the header
    python utils/maint/engine/emit_qasm_pi.py --check    exit 1 where the header on disk is not what this writes

The guard width is read from QASM_GUARD_BITS in qasm_internal.h and never written here. The places are the least p
with 10^p past 2^(G + 1), found in integers: pi cut to p places is then within half a unit of pi * 2^G, and
qasm_fixed_constants takes it the rest of the way. naturals.pi reaches its digits by two routes that have to agree.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
QASM = os.path.join(ROOT, "src", "engine", "quantum", "qasm")
INTERNAL = os.path.join(QASM, "qasm_internal.h")
HEADER = os.path.join(QASM, "qasm_pi.h")
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation.constants.naturals import pi  # noqa: E402

SPDX = "// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational"
# characters of the digit string on one line of the header
WIDTH = 100


def guard_bits():
    found = re.search(r"#define QASM_GUARD_BITS (\d+)u", open(INTERNAL, encoding="utf-8").read())
    if found is None:
        sys.exit("QASM_GUARD_BITS is not defined in " + INTERNAL)
    return int(found.group(1))


def places_for(bits):
    """The least p with 10^p past 2^(bits + 1), every step an integer comparison."""
    reach = 1 << (bits + 1)
    places = 0
    power = 1
    while power <= reach:
        power *= 10
        places += 1
    return places


def header_text():
    bits = guard_bits()
    places = places_for(bits)
    digits = str(pi(places)).rjust(places + 1, "0")
    text = digits[0] + "." + digits[1:]
    pieces = [text[at:at + WIDTH] for at in range(0, len(text), WIDTH)]
    lines = [
        SPDX,
        "// qasm_pi.h: pi to QASM_PI_PLACES places, for the fixed point at QASM_PI_BITS guard bits",
        "//",
        "// Written by utils/maint/engine/emit_qasm_pi.py from representation.constants.naturals.pi. Do not edit it: emit",
        "// it again. 10^QASM_PI_PLACES is past 2^(QASM_PI_BITS + 1): the digits are within half a unit of pi at that",
        "// width, and qasm_exact.c refuses to build where QASM_GUARD_BITS has grown past QASM_PI_BITS.",
        "#ifndef QASM_PI_H",
        "#define QASM_PI_H",
        "",
        "#define QASM_PI_BITS %du" % bits,
        "#define QASM_PI_PLACES %du" % places,
        "#define QASM_PI_TEXT \\",
    ]
    for index, piece in enumerate(pieces):
        tail = " \\" if index + 1 < len(pieces) else ""
        lines.append('    "%s"%s' % (piece, tail))
    lines += ["", "#endif", ""]
    return "\n".join(lines)


def main():
    text = header_text()
    if "--check" in sys.argv:
        held = open(HEADER, encoding="utf-8").read() if os.path.exists(HEADER) else ""
        if held != text:
            print("  qasm_pi.h is not what emit_qasm_pi.py writes: emit it again")
            return 1
        print("  qasm_pi.h holds pi as emit_qasm_pi.py writes it")
        return 0
    with open(HEADER, "w", encoding="utf-8", newline="\n") as out:
        out.write(text)
    print("  wrote " + os.path.relpath(HEADER, ROOT).replace(os.sep, "/"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
