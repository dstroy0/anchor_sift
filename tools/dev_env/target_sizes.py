#!/usr/bin/env python3
"""Per-translation-unit .text at each optimization level, for the targets the library ships to.

The counterpart to sizes.py, and the one whose numbers decide anything. sizes.py reads its compiler
options out of build/compile_commands.json, which is the desktop build, so every figure it prints is
x86-64 code size. That is the wrong instruction set for a library whose targets are 32-bit Xtensa,
RISC-V and ARM, and they do not merely differ from the host by a constant: on all three -O1 is LARGER
than -O2, and on the host it is smaller. A level chosen off the host table is chosen off the wrong
measurement.

Each unit is compiled on its own, no LTO and no link, so a row is that unit alone:

    <target>-gcc -std=c11 -I src -O<level> -c <unit>.c -o <unit>.o && <target>-size <unit>.o

Usage:

    python tools/dev_env/target_sizes.py                 both targets
    python tools/dev_env/target_sizes.py --arch xtensa   one of them

The toolchains are the ones an ESP-IDF install already carries. --bin points at a different one.
"""

import argparse
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "src")

LEVELS = ("-O0", "-O1", "-Os", "-O2", "-O3")

# Where an ESP-IDF or PlatformIO install puts them. A different toolchain is named with --bin.
#
# arm carries -mcpu, because arm-none-eabi-gcc defaults to a core nothing in the target list is:
# Cortex-M4 with the Thumb-2 encoding is the shape this library is built for there, and the default
# ARM encoding would report a code size no target flashes.
TARGETS = {
    "xtensa": (r"C:\Espressif\tools\xtensa-esp-elf\esp-14.2.0_20260121\xtensa-esp-elf\bin", "xtensa-esp32s3-elf", []),
    "riscv": (r"C:\Espressif\tools\riscv32-esp-elf\esp-14.2.0_20260121\riscv32-esp-elf\bin", "riscv32-esp-elf", []),
    "arm": (
        os.path.join(os.path.expanduser("~"), ".platformio", "packages", "toolchain-gccarmnoneeabi", "bin"),
        "arm-none-eabi",
        ["-mcpu=cortex-m4", "-mthumb"],
    ),
}

# The five cost tables are alternatives, not additions - they all define the same symbol and a build
# links exactly one, so only the selected one is counted.
SKIP = re.compile(r"impensa_ancorae_acus_(english|inet|route|uri)\.c$")


def units():
    """Every .c under src/, minus the cost tables a build does not select."""
    out = []
    for base, _, names in os.walk(SRC):
        for n in sorted(names):
            if n.endswith(".c") and not SKIP.search(n):
                out.append(os.path.join(base, n))
    return sorted(out)


def text_size(gcc, size, unit, level, obj, extra):
    """.text for one unit at one level, or None when it does not compile."""
    r = subprocess.run(
        [gcc, "-c", level, "-std=c11", "-I", SRC] + extra + [unit, "-o", obj],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0:
        return None
    r = subprocess.run([size, obj], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    return int(r.stdout.strip().split("\n")[-1].split()[0])


def measure(arch, binpath):
    """One target's table: rows of (unit, [.text per level]), and the column totals."""
    base, prefix, extra = TARGETS[arch]
    base = binpath or base
    gcc = os.path.join(base, prefix + "-gcc.exe")
    size = os.path.join(base, prefix + "-size.exe")

    if not os.path.exists(gcc):
        print("target_sizes: no %s toolchain at %s" % (arch, base), file=sys.stderr)
        print("  point --bin at one, or install it through ESP-IDF.", file=sys.stderr)
        return None, None

    rows = []
    fd, obj = tempfile.mkstemp(suffix=".o")
    os.close(fd)
    try:
        for u in units():
            got = [text_size(gcc, size, u, lvl, obj, extra) for lvl in LEVELS]
            if any(g is None for g in got):
                print("target_sizes: %s failed to compile for %s" % (os.path.relpath(u, SRC), arch), file=sys.stderr)
                return None, None
            rows.append((os.path.relpath(u, SRC).replace("\\", "/"), got))
    finally:
        os.unlink(obj)

    rows.sort(key=lambda r: r[1][LEVELS.index("-O2")], reverse=True)
    totals = [sum(r[1][i] for r in rows) for i in range(len(LEVELS))]
    return rows, totals


def render(arch, rows, totals):
    wid = max(len(r[0]) for r in rows)
    print()
    print("  %s, .text in bytes" % arch)
    print()
    print("  %-*s %s" % (wid, "translation unit", " ".join("%7s" % l for l in LEVELS)))
    for name, got in rows:
        print("  %-*s %s" % (wid, name, " ".join("%7d" % g for g in got)))
    print("  %-*s %s" % (wid, "total", " ".join("%7d" % t for t in totals)))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--arch", choices=sorted(TARGETS), help="one target; both when not given")
    ap.add_argument("--bin", help="toolchain bin directory, when it is not where ESP-IDF puts it")
    a = ap.parse_args()

    picked = [a.arch] if a.arch else sorted(TARGETS)
    rc = 0
    for arch in picked:
        rows, totals = measure(arch, a.bin)
        if rows is None:
            rc = 1
            continue
        render(arch, rows, totals)
    return rc


if __name__ == "__main__":
    sys.exit(main())
