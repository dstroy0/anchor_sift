#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""What each translation unit costs, at whichever optimisation levels are asked for.

The options are read out of the build rather than written down here. cmake already emits every
compile command it issues into build/compile_commands.json, so that is the one place the flags
live: a list copied into this file would agree with CMakeLists.txt until somebody changed one of
them, and then it would quietly be measuring something else. The optimisation level and link time
optimisation are the only things taken out - the level because it is what varies, and LTO because
an object built with it holds intermediate form rather than instructions and its size says nothing
about what would land on a target.

Sections are read rather than file lengths, because an object also carries relocations, symbol
tables and debug records that never reach flash.

  text    instructions
  rodata  constants: tables, string literals, the const namespaces
  data    writable with an initial value
  bss     writable, zero at start

    python tools/dev_env/sizes.py                       -O2 against -O3
    python tools/dev_env/sizes.py -O0 -O1 -Os -O2 -O3   the whole sweep
    python tools/dev_env/sizes.py -Os                   one level, per unit
"""

import argparse
import json
import pathlib
import re
import shlex
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "src"

# Dropped from whatever the build uses: the level is the variable, LTO hides the instructions, and
# the output and input names are supplied per call.
DROP_EXACT = {"-c", "-o"}
DROP_PREFIX = ("-O", "-flto", "-fno-fat-lto-objects", "-MD", "-MT", "-MF")

WANTED = (
    ("text", (".text",)),
    ("rodata", (".rdata", ".rodata")),
    ("data", (".data",)),
    ("bss", (".bss",)),
)


def flags_from_build():
    """The options the build actually issues for a src translation unit."""
    for tree in ("build", "build-oracle"):
        cc = ROOT / tree / "compile_commands.json"
        if not cc.is_file():
            continue
        for entry in json.loads(cc.read_text(encoding="utf-8")):
            path = entry["file"].replace("\\", "/")
            if "/src/" not in path:
                continue
            parts = shlex.split(entry["command"].replace("\\", "/"))
            out = []
            skip = False
            for i, tok in enumerate(parts[1:]):
                if skip:
                    skip = False
                    continue
                if tok in DROP_EXACT:
                    skip = tok == "-o"
                    continue
                if tok.startswith(DROP_PREFIX):
                    continue
                if not tok.startswith("-"):
                    continue  # a source or object name
                out.append(tok)
            return out, parts[0]
    sys.exit("no compile_commands.json - configure a build tree first")


def sections(obj, objdump):
    """Section sizes of one object, by name."""
    out = subprocess.run([objdump, "-h", str(obj)], capture_output=True, text=True)
    got = {name: 0 for name, _ in WANTED}

    for line in out.stdout.splitlines():
        m = re.match(r"\s*\d+\s+(\S+)\s+([0-9a-f]+)\s", line)
        if not m:
            continue
        sect, size = m.group(1), int(m.group(2), 16)
        for name, prefixes in WANTED:
            if any(sect == p or sect.startswith(p + "$") or sect.startswith(p + ".") for p in prefixes):
                got[name] += size
    return got


def build(level, cc, flags, objdump, tmp):
    """Compile every src unit at one level and read its sections."""
    rows = {}
    for c in sorted(SRC.rglob("*.c")):
        obj = tmp / (c.stem + level.replace("-", "_") + ".o")
        r = subprocess.run([cc, level] + flags + ["-c", str(c), "-o", str(obj)], capture_output=True, text=True)
        if r.returncode != 0:
            sys.stderr.write(r.stderr[-2000:])
            sys.exit("could not compile %s at %s" % (c.name, level))
        rows[c.relative_to(SRC).as_posix()] = sections(obj, objdump)
    return rows


def main():
    # -O2 and -Os read as options to argparse, so the levels are taken out of the arguments first.
    # It is a small thing to write and it means the command reads the way the compiler's does.
    levels = [t for t in sys.argv[1:] if re.fullmatch(r"-O[0-3sgz]?", t)]
    rest = [t for t in sys.argv[1:] if t not in levels]

    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--objdump", default="objdump")
    ap.add_argument("--section", default="text", choices=[n for n, _ in WANTED])
    a = ap.parse_args(rest)
    a.levels = levels or ["-O2", "-O3"]

    flags, cc = flags_from_build()
    print("  options taken from the build: %s\n" % " ".join(flags))

    tmp = ROOT / "build" / "sizes"
    tmp.mkdir(parents=True, exist_ok=True)
    got = {lv: build(lv, cc, flags, a.objdump, tmp) for lv in a.levels}
    files = [f for f in sorted(next(iter(got.values()))) if any(got[lv][f]["text"] for lv in a.levels)]

    if len(a.levels) == 1:
        lv = a.levels[0]
        print("  %-34s %8s %8s %8s %8s" % ("translation unit", "text", "rodata", "data", "bss"))
        for f in files:
            s = got[lv][f]
            print("  %-34s %8d %8d %8d %8d" % (f, s["text"], s["rodata"], s["data"], s["bss"]))
        tot = {k: sum(got[lv][f][k] for f in files) for k, _ in WANTED}
        print("  %-34s %8d %8d %8d %8d" % ("total", tot["text"], tot["rodata"], tot["data"], tot["bss"]))
        return 0

    sect = a.section
    print("  %s, in bytes\n" % sect)
    head = "  %-34s" % "translation unit"
    for lv in a.levels:
        head += " %9s" % lv
    print(head)

    for f in files:
        row = "  %-34s" % f
        for lv in a.levels:
            row += " %9d" % got[lv][f][sect]
        print(row)

    row = "  %-34s" % "total"
    totals = []
    for lv in a.levels:
        t = sum(got[lv][f][sect] for f in files)
        totals.append(t)
        row += " %9d" % t
    print(row)

    base = totals[0]
    row = "  %-34s" % ("against %s" % a.levels[0])
    for t in totals:
        row += " %8.0f%%" % (100.0 * (t - base) / base)
    print(row)
    return 0


if __name__ == "__main__":
    sys.exit(main())
