#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Move the modules from the names they arrived under onto this library's Latin category names.

Driven entirely by tools/dev_env/names.tsv. Nothing about the naming lives in this file, so a change
of mind is an edit to the table rather than to the code.

    rename_modules.py symbols   mmgr_<infix>_<tail>, and the verbs inside the tail
    rename_modules.py headers   guards and include paths
    rename_modules.py files     git mv of the directories and filenames
    rename_modules.py all       all three, in that order

Dry run by default; --go writes.

WHY IT CHECKS BEFORE IT WRITES. Several old names map onto one new one by design - bw and br both
become byteio - so the map is many-to-one, and a many-to-one map can merge two distinct identifiers
into a single name. That is a miscompile no rename tool reports afterwards: the build still
succeeds, it just calls the wrong function. Every mode below computes its whole map first, refuses
on a collision, and only then writes.

The verb pass runs on the TAIL only, never on the whole symbol, so a module whose stem happens to
contain a verb is not rewritten by accident. Verbs are applied longest-first, or scratch_alloc is
eaten by alloc and leaves scratch_capio behind.
"""

import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LIB = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(LIB, "src")
TABLE = os.path.join(HERE, "names.tsv")


def load_table():
    modules, infixes, verbs, types, namespaces = [], {}, [], {}, []
    for line in io.open(TABLE, encoding="utf-8"):
        line = line.rstrip("\n")
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        kind = parts[0]
        if kind == "MODULE":
            modules.append({"old": parts[1], "latin": parts[2], "stem": parts[3], "pascal": parts[4]})
        elif kind == "INFIX":
            infixes[parts[1]] = parts[2]
        elif kind == "VERB":
            verbs.append((parts[1], parts[2]))
        elif kind == "TYPE":
            types[parts[1]] = parts[2]
        elif kind == "NS":
            namespaces.append({"otype": parts[1], "oinst": parts[2], "ntype": parts[3], "ninst": parts[4]})
    # Longest first: scratch_alloc must be tried before alloc, or alloc matches inside it.
    verbs.sort(key=lambda kv: -len(kv[0]))
    return modules, infixes, verbs, types, namespaces


def sources(root):
    for dirpath, _d, names in os.walk(root):
        for fn in sorted(names):
            if fn.endswith((".c", ".h")):
                yield os.path.join(dirpath, fn)


def apply_verbs(tail, verbs):
    for old, new in verbs:
        if tail == old:
            return new
        if tail.startswith(old + "_"):
            return new + tail[len(old) :]
        if tail.endswith("_" + old):
            return tail[: -len(old)] + new
    return tail


def mode_symbols(go):
    modules, infixes, verbs, _t, _n = load_table()
    SYM = re.compile(r"\bmmgr_([a-z0-9]+)_([a-z0-9_]+)\b")

    # Whole-tree map first, so a collision is found before a single file is touched.
    mapping = {}
    for p in sources(SRC):
        text = io.open(p, encoding="utf-8", errors="replace").read()
        for m in SYM.finditer(text):
            infix, tail = m.group(1), m.group(2)
            if infix not in infixes:
                continue
            mapping[m.group(0)] = "mmgr_%s_%s" % (infixes[infix], apply_verbs(tail, verbs))

    buckets = {}
    for old, new in mapping.items():
        buckets.setdefault(new, []).append(old)
    collisions = {k: sorted(v) for k, v in buckets.items() if len(v) > 1}
    if collisions:
        print("REFUSING: %d collisions - these would become the same identifier:\n" % len(collisions))
        for k in sorted(collisions):
            print("  %-34s <-  %s" % (k, ", ".join(collisions[k])))
        return 1
    print("%d symbols -> %d distinct names, no collisions" % (len(mapping), len(buckets)))

    # Longest first so mmgr_span_from is rewritten before mmgr_span would match its prefix.
    keys = sorted(mapping, key=len, reverse=True)
    rx = re.compile(r"\b(" + "|".join(re.escape(k) for k in keys) + r")\b")
    files = hits = 0
    for p in sources(SRC):
        text = io.open(p, encoding="utf-8", errors="replace").read()
        out, n = rx.subn(lambda m: mapping[m.group(1)], text)
        if n:
            files += 1
            hits += n
            if go:
                io.open(p, "w", encoding="utf-8", newline="\n").write(out)
    print("%d files, %d occurrences" % (files, hits))
    return 0


def mode_headers(go):
    modules, _i, _v, _t, _n = load_table()
    pairs = []
    for m in modules:
        old, latin = m["old"], m["latin"]
        pairs.append(('"%s/%s.h"' % (old, old), '"%s/%s.h"' % (latin, latin)))
        pairs.append(("MMGR_%s_H" % old.upper(), "MMGR_%s_H" % latin.upper()))
    # ring arrived as a bare header rather than a directory.
    pairs.append(('"ring.h"', '"confinium_exclusivum_infinitas/confinium_exclusivum_infinitas.h"'))
    pairs.append(("MMGR_RING_H", "MMGR_CONFINIUM_EXCLUSIVUM_INFINITAS_H"))

    files = hits = 0
    for p in sources(SRC):
        text = io.open(p, encoding="utf-8", errors="replace").read()
        before = text
        n = 0
        for old, new in pairs:
            c = text.count(old)
            if c:
                text = text.replace(old, new)
                n += c
        if text != before:
            files += 1
            hits += n
            if go:
                io.open(p, "w", encoding="utf-8", newline="\n").write(text)
    print("%d files, %d guard/include occurrences" % (files, hits))
    return 0


def mode_types(go):
    """Data typedefs, the Ns type, and the Ns instance.

    The instance is the delicate one. It is a bare lowercase word - mem, span, raw, bytes - and each
    of those is also something else in this tree: `mem` is the struct member holding pool storage,
    `span` and `raw` are function-pointer member names inside the very structs being renamed, and
    `secure` appears inside an MMGR_ASSERT message. Rewriting the bare identifier corrupts all four,
    so only two forms are touched:

        const <OldNs> <oldinstance>     the declaration
        <oldinstance>.                  member access, which is the only way an instance is read

    A member-access match is additionally required NOT to be preceded by `->` or `.`, so
    `ctx->store->mem` is left alone while `mem.cpy(...)` is rewritten.
    """
    _m, _i, _v, types, namespaces = load_table()

    files = hits = 0
    for p in sources(SRC):
        text = io.open(p, encoding="utf-8", errors="replace").read()
        before = text

        for old, new in sorted(types.items(), key=lambda kv: -len(kv[0])):
            text = re.sub(r"\b%s\b" % re.escape(old), new, text)

        for ns in namespaces:
            text = re.sub(r"\b%s\b" % re.escape(ns["otype"]), ns["ntype"], text)
            if ns["oinst"] == ns["ninst"]:
                continue
            # the declaration
            text = re.sub(
                r"(const\s+%s\s+)%s\b" % (re.escape(ns["ntype"]), re.escape(ns["oinst"])),
                r"\g<1>%s" % ns["ninst"],
                text,
            )
            # member access, but not when it is itself reached through . or ->
            text = re.sub(r"(?<![.\w>])%s\." % re.escape(ns["oinst"]), "%s." % ns["ninst"], text)

        if text != before:
            files += 1
            hits += 1
            if go:
                io.open(p, "w", encoding="utf-8", newline="\n").write(text)
    print("%d files rewritten" % files)
    return 0


def mode_files(go):
    modules, _i, _v, _t, _n = load_table()
    moves = []
    for m in modules:
        old, latin = m["old"], m["latin"]
        d = os.path.join(SRC, old)
        if old == "ring":
            bare = os.path.join(SRC, "ring.h")
            if os.path.exists(bare):
                moves.append((bare, os.path.join(SRC, latin, latin + ".h")))
            continue
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            src = os.path.join(d, fn)
            if fn == old + ".c" or fn == old + ".h":
                dst = os.path.join(SRC, latin, latin + fn[len(old) :])
            else:
                dst = os.path.join(SRC, latin, fn)
            # bitio, dma and endian are already their own category name, so every file in them maps
            # to itself. git mv refuses that ("cannot move directory into itself") rather than
            # treating it as a no-op, so the no-ops are dropped here instead.
            if os.path.abspath(src) != os.path.abspath(dst):
                moves.append((src, dst))

    for src, dst in moves:
        rel_s = os.path.relpath(src, LIB).replace("\\", "/")
        rel_d = os.path.relpath(dst, LIB).replace("\\", "/")
        print("  %-46s -> %s" % (rel_s, rel_d))
        if go:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            r = subprocess.run(["git", "mv", rel_s, rel_d], cwd=LIB, capture_output=True, text=True)
            if r.returncode != 0:
                print("     git mv failed: %s" % r.stderr.strip())
                return 1
    print("%d moves" % len(moves))
    if go:
        for m in modules:
            d = os.path.join(SRC, m["old"])
            if os.path.isdir(d) and not os.listdir(d):
                os.rmdir(d)
    return 0


def main():
    args = sys.argv[1:]
    go = "--go" in args
    modes = [a for a in args if not a.startswith("-")]
    mode = modes[0] if modes else ""
    if mode not in ("symbols", "headers", "types", "files", "all"):
        print(__doc__)
        return 2
    rc = 0
    for m in (["symbols", "headers", "types", "files"] if mode == "all" else [mode]):
        print("--- %s ---" % m)
        rc = {"symbols": mode_symbols, "headers": mode_headers, "types": mode_types, "files": mode_files}[m](go)
        if rc:
            return rc
    if not go:
        print("\nDRY RUN - pass --go to write")
    return rc


if __name__ == "__main__":
    sys.exit(main())
