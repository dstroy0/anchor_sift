# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Emits the CRC-64/XZ key, after checking it: crc_key.h holds the byte table and CRC_KEY_ADVANCE, whose operators
come from crc_key_advance_low.h (across 2^0 to 2^23 zero bytes) and crc_key_advance_high.h (2^24 to 2^47)."""
import os
import random

POLYNOMIAL = 0xC96C5795D7870F42
MASK = (1 << 64) - 1
CHECK = 0x995DC9BBDF1939FA
POWERS = 48
HERE = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))), "src", "c", "includes", "codecs", "crc")
SPDX = "// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational"

table = []
for byte in range(256):
    crc = byte
    for _ in range(8):
        crc = ((crc >> 1) ^ POLYNOMIAL) if (crc & 1) else (crc >> 1)
    table.append(crc)


def step(crc, byte):
    return table[(crc ^ byte) & 0xFF] ^ (crc >> 8)


def carry(crc, data):
    for byte in data:
        crc = step(crc, byte)
    return crc


def apply(columns, value):
    out = 0
    for column in range(64):
        if (value >> column) & 1:
            out ^= columns[column]
    return out


advance = [[step(1 << column, 0) for column in range(64)]]
for power in range(1, POWERS):
    before = advance[-1]
    advance.append([apply(before, before[column]) for column in range(64)])


def across(value, count):
    power = 0
    while count:
        if count & 1:
            value = apply(advance[power], value)
        count >>= 1
        power += 1
    return value


assert carry(MASK, b"123456789") ^ MASK == CHECK
for count in (1, 2, 3, 5, 127, 128, 129, 1000, 4096, 65537):
    assert across(0x0123456789ABCDEF, count) == carry(0x0123456789ABCDEF, bytes(count))
chance = random.Random(20260921)
for _ in range(64):
    left = bytes(chance.randrange(256) for _ in range(chance.randrange(1, 300)))
    right = bytes(chance.randrange(256) for _ in range(chance.randrange(1, 300)))
    assert carry(0, left + right) == across(carry(0, left), len(right)) ^ carry(0, right)
message = bytes(chance.randrange(256) for _ in range(1000))
assert carry(MASK, message) ^ MASK == (carry(0, message) ^ across(MASK, len(message))) ^ MASK


def rows(values, per_line, indent):
    lines = []
    for at in range(0, len(values), per_line):
        lines.append(indent + ", ".join("0x%016XULL" % value for value in values[at:at + per_line]))
    return (",\n").join(lines)


def emit(name, lines):
    with open(os.path.join(HERE, name), "w", encoding="utf-8", newline="\n") as target:
        target.write("\n".join(lines) + "\n")


def operators(first, last):
    blocks = []
    for power in range(first, last):
        blocks.append("        { \\\n" + rows(advance[power], 4, "            ").replace(",\n", ", \\\n") + " \\\n        }")
    return (", \\\n").join(blocks)


HALF = POWERS // 2
for part, first, last in (("low", 0, HALF), ("high", HALF, POWERS)):
    guard = "CRC_KEY_ADVANCE_%s" % part.upper()
    emit("crc_key_advance_%s.h" % part, [
        SPDX,
        "#ifndef %s_H" % guard,
        "#define %s_H" % guard,
        "",
        "#define %s \\" % guard,
        operators(first, last),
        "",
        "#endif",
    ])

emit("crc_key.h", [
    SPDX,
    "#ifndef CRC_KEY_H",
    "#define CRC_KEY_H",
    "",
    "#include \"crc_key_advance_low.h\"",
    "#include \"crc_key_advance_high.h\"",
    "",
    "#define CRC_KEY_POWERS %du" % POWERS,
    "",
    "#define CRC_KEY_TABLE \\",
    "    { \\",
    rows(table, 4, "        ").replace(",\n", ", \\\n") + " \\",
    "    }",
    "",
    "#define CRC_KEY_ADVANCE \\",
    "    { \\",
    "        CRC_KEY_ADVANCE_LOW, \\",
    "        CRC_KEY_ADVANCE_HIGH \\",
    "    }",
    "",
    "#endif",
])
print("crc_key.h, crc_key_advance_low.h, crc_key_advance_high.h written: %d table entries, %d advance operators, "
      "every check held" % (len(table), POWERS))
