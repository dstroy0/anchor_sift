#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""One 128-bit encoding and the 128 that are one bit from it, written as raw instructions for nvdisasm --binary.

    sass_turn_bits.py <low> <high> <binary> [--without <address>,<address>,...]

`low` and `high` are the instruction's two 64-bit words in hex, low first, as a listing prints them. The encoding
itself goes first. The disassembler's line at address 0 is then the form given, and the line at address 16*(bit+1)
is that form with bit `bit` turned over.

`--without` names, in hex, the addresses of encodings the disassembler refused. Each is written as a NOP instead of
being dropped, and every other encoding then keeps the address that says which bit it is. Their bits read as NOP,
and by that the caller tells a refused encoding from a decoded one.
"""

import struct
import sys

# the part's NOP, as the cell's probe read it back (src/c/transpiler/cubin/machines/sm_86)
NOP_LOW = 0x0000000000007918
NOP_HIGH = 0x000FC00000000000


def main(arguments):
    if len(arguments) not in (3, 5) or (len(arguments) == 5 and arguments[3] != "--without"):
        print(__doc__)
        return 2
    low = int(arguments[0], 16)
    high = int(arguments[1], 16)
    refused = set()
    if len(arguments) == 5:
        refused = {int(one, 16) // 16 for one in arguments[4].split(",") if one}
    with open(arguments[2], "wb") as binary:
        for place in range(129):
            if place in refused:
                binary.write(struct.pack("<QQ", NOP_LOW, NOP_HIGH))
            elif place == 0:
                binary.write(struct.pack("<QQ", low, high))
            else:
                bit = place - 1
                turned_low = low ^ (1 << bit) if bit < 64 else low
                turned_high = high ^ (1 << (bit - 64)) if bit >= 64 else high
                binary.write(struct.pack("<QQ", turned_low, turned_high))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
