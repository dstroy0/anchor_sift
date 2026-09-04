#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""How much of a target this library costs against the libc it would replace.

newlib is the comparison because it is the libc an embedded target actually ships, it is a static
archive with one object per entry so a single function can be weighed, and it is built by the same
compiler family. Both sides are compiled for the same core at the same optimisation level, so the
difference is the code and not the toolchain.

Only .text is counted. An archive member also carries relocations and symbol tables that never
reach flash, and the linker pulls whole members, so a member is the unit whether or not every entry
in it is called.

    python tools/dev_env/against_libc.py
    python tools/dev_env/against_libc.py --cpu cortex-m0 --level -Os
"""

import argparse
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "src"
TOOLCHAIN = pathlib.Path.home() / ".platformio" / "packages" / "toolchain-gccarmnoneeabi"

# What this library's modules stand in for.
#
# The two sides do not divide the work the same way, so the families are drawn where the code
# actually is rather than where the header names suggest. cellularum_laboro holds the bounded
# scans and the decimal parser in one translation unit, which on the newlib side is str* plus the
# whole strtod, dtoa and mprec apparatus. pow5 is header only, so its table lands in whoever
# includes it, which is cellularum_laboro.
#
# Every newlib member is named once across all the families. dtoa and mprec serve both parsing and
# printing there, and counting them twice would flatter this library by six kilobytes.
FAMILIES = (
    (
        "moving and comparing bytes",
        ["memoria_operor", "proximus_operor"],
        ["memcpy", "memmove", "memcmp", "memchr", "memset"],
    ),
    (
        "searching and parsing text",
        ["cellularum_laboro", "verbum_scrutor"],
        [
            "strlen",
            "strnlen",
            "strstr",
            "strchr",
            "strrchr",
            "strcmp",
            "strncmp",
            "strcpy",
            "strncpy",
            "strcasecmp",
            "strncasecmp",
            "strcat",
            "strncat",
            "strspn",
            "strcspn",
            "strpbrk",
            "strtok",
            "strdup",
            "strtod",
            "strtof",
            "strtol",
            "strtoul",
            "strtoll",
            "strtoull",
            "atoi",
            "atol",
            "atof",
            "dtoa",
            "mprec",
            "gdtoa",
        ],
    ),
    (
        "rendering numbers and text",
        ["verba_scribo", "numeros_scribo", "fractio"],
        [
            "vfprintf",
            "vfiprintf",
            "sprintf",
            "siprintf",
            "snprintf",
            "sniprintf",
            "vsprintf",
            "vsiprintf",
            "vsnprintf",
            "vsniprintf",
            "sccl",
            "fvwrite",
            "wsetup",
            "wbuf",
            "makebuf",
            "findfp",
            "fflush",
            "fwalk",
            "stdio",
            "ldtoa",
            "locale",
        ],
    ),
)


def run(cmd, cwd=None):
    """Run a tool and hand back its output, decoded loosely - a binutil may emit odd bytes."""
    return subprocess.run(cmd, capture_output=True, text=True, errors="replace", cwd=cwd)


def tool(name):
    """The named binutil, under whichever of its spellings this toolchain ships.

    Some drops have ar and some only have gcc-ar, which is the same program with a plugin already
    arranged. Either answers the questions here.
    """
    for stem in (name, "gcc-" + name):
        for ext in (".exe", ""):
            p = TOOLCHAIN / "bin" / ("arm-none-eabi-" + stem + ext)
            if p.is_file():
                return str(p)
    sys.exit("no arm-none-eabi-%s under %s" % (name, TOOLCHAIN / "bin"))


def archive_text(lib, wanted, ar, objdump, tmp):
    """.text of each named member of an archive, and which names were not there.

    Members are extracted into the working directory rather than read from a pipe: an object is
    binary and a text pipe will not carry it. newlib prefixes some members with lib_a-, which is a
    build artefact rather than part of the name, so it is taken off before matching.
    """
    by_stem = {}
    for m in run([ar, "t", str(lib)]).stdout.split():
        stem = pathlib.Path(m).stem
        if stem.startswith("lib_a-"):
            stem = stem[len("lib_a-") :]
        by_stem.setdefault(stem, m)

    got = {}
    missing = []
    for name in wanted:
        member = by_stem.get(name)
        if member is None:
            missing.append(name)
            continue
        run([ar, "x", str(lib), member], cwd=str(tmp))
        obj = tmp / member
        if not obj.is_file():
            missing.append(name)
            continue
        got[name] = section_text(obj, objdump)
    return got, missing


def section_text(obj, objdump):
    out = run([objdump, "-h", str(obj)]).stdout
    total = 0
    for line in out.splitlines():
        m = re.match(r"\s*\d+\s+(\S+)\s+([0-9a-f]+)\s", line)
        if m and (m.group(1) == ".text" or m.group(1).startswith(".text.")):
            total += int(m.group(2), 16)
    return total


def build_mmgr(modules, cc, objdump, cpu, level, tmp):
    """.text of this library's modules, built for the same core."""
    flags = [
        level,
        "-std=c11",
        "-DNDEBUG",
        "-I" + str(SRC),
        "-mcpu=" + cpu,
        "-mthumb",
        "-ffunction-sections",
        "-fdata-sections",
    ]
    got = {}
    for mod in modules:
        d = SRC / mod
        total = 0
        for c in sorted(d.glob("*.c")):
            obj = tmp / (mod + "_" + c.stem + ".o")
            r = run([cc] + flags + ["-c", str(c), "-o", str(obj)])
            if r.returncode != 0:
                sys.stderr.write(r.stderr[-1500:])
                sys.exit("could not build %s for %s" % (c.name, cpu))
            total += section_text(obj, objdump)
        got[mod] = total
    return got


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--cpu", default="cortex-m4")
    ap.add_argument("--level", default="-Os")
    ap.add_argument("--lib", default="armv7e-m")
    a = ap.parse_args()

    cc, ar, objdump = tool("gcc"), tool("ar"), tool("objdump")
    lib = TOOLCHAIN / "arm-none-eabi" / "lib" / a.lib / "libc.a"
    if not lib.is_file():
        sys.exit("no libc.a at " + str(lib))

    tmp = ROOT / "build" / "against_libc"
    tmp.mkdir(parents=True, exist_ok=True)

    print("  %s, %s, newlib from %s\n" % (a.cpu, a.level, lib.parent.name))

    grand_m = 0
    grand_n = 0
    for family, mods, members in FAMILIES:
        mine = build_mmgr(mods, cc, objdump, a.cpu, a.level, tmp)
        theirs, missing = archive_text(lib, members, ar, objdump, tmp)

        m = sum(mine.values())
        n = sum(theirs.values())
        grand_m += m
        grand_n += n

        print("  %s" % family)
        for k in sorted(mine, key=lambda x: -mine[x]):
            print("      mmgr    %-22s %7d" % (k, mine[k]))
        for k in sorted(theirs, key=lambda x: -theirs[x])[:10]:
            print("      newlib  %-22s %7d" % (k, theirs[k]))
        if len(theirs) > 10:
            print(
                "      newlib  %-22s %7d"
                % ("... %d more" % (len(theirs) - 10), sum(sorted(theirs.values(), reverse=True)[10:]))
            )
        if missing:
            print("      (this newlib has no %s)" % ", ".join(missing))
        if m and n:
            print("      -> mmgr %d, newlib %d, %.2fx\n" % (m, n, n / m))
        else:
            print("      -> mmgr %d, newlib %d\n" % (m, n))

    if grand_m:
        print(
            "  total    mmgr %d, newlib %d - %.2fx smaller, %d bytes of flash"
            % (grand_m, grand_n, grand_n / grand_m, grand_n - grand_m)
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
