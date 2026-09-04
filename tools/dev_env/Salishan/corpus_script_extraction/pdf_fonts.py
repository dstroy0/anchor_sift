#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find out which fonts a PDF uses and whether each one carries a map back to Unicode.
#
#   Usage:  python tools/dev_env/pdf_fonts.py <name> [name ...]
#
# salish_purity.py reports which extracted papers lost their phonemes, and the answer for everything
# published before about 2014 is all of them. Lushootseed with no glottal stop, no schwa and no lateral
# fricative is not Lushootseed, and the whole pre-2010 literature in this archive reads that way.
#
# The glyphs are still in those files. What is missing is the map from the font's own character codes back
# to Unicode, which is the ToUnicode entry a PDF may or may not carry. Where it is absent the extractor
# gets a code and has nothing to turn it into, so it emits whatever the code happens to mean in a default
# encoding and the marked consonants come out as blanks.
#
# This reports, for each font in a file, whether that map is present. A font with a map that still
# extracts badly is a different problem from a font with no map at all, and the second one is recoverable
# by supplying the table the font was designed against.

import io
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PAPERS = os.path.join(ROOT, "build", "papers")


def fonts_of(path):
    """Every font the pages of a PDF refer to, with what the file says about each one."""
    import pypdf

    reader = pypdf.PdfReader(path)
    held = {}
    for page in reader.pages:
        try:
            resources = page.get("/Resources")
            if resources is None:
                continue
            fonts = resources.get_object().get("/Font")
            if fonts is None:
                continue
            for key, reference in fonts.get_object().items():
                font = reference.get_object()
                name = str(font.get("/BaseFont", "unnamed"))
                kind = str(font.get("/Subtype", ""))
                encoding = font.get("/Encoding")
                if hasattr(encoding, "get_object"):
                    encoding = encoding.get_object()
                    encoding = str(encoding.get("/BaseEncoding", "custom differences"))
                else:
                    encoding = str(encoding) if encoding else "none"
                mapped = "/ToUnicode" in font
                held.setdefault((name, kind, encoding, mapped), 0)
                held[(name, kind, encoding, mapped)] += 1
        except Exception:
            continue
    return held


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if len(sys.argv) < 2:
        out.write("  usage: pdf_fonts.py <name> [name ...]\n")
        out.flush()
        return 1

    for stem in sys.argv[1:]:
        path = os.path.join(PAPERS, "%s.pdf" % stem)
        if not os.path.isfile(path):
            out.write("  no %s\n" % path)
            continue
        out.write("\n  %s\n" % stem)
        try:
            held = fonts_of(path)
        except Exception as trouble:
            out.write("    could not read it, %s\n" % str(trouble)[:60])
            continue
        if not held:
            out.write("    no fonts found on any page\n")
            continue
        out.write("    %-40s %-14s %-22s %s\n"
                  % ("font", "kind", "encoding", "has a unicode map"))
        for key in sorted(held, key=lambda one: -held[one]):
            name, kind, encoding, mapped = key
            out.write("    %-40s %-14s %-22s %s\n"
                      % (name[:40], kind[:14], encoding[:22], "yes" if mapped else "NO"))

    out.write("\n  a font with no unicode map is recoverable by supplying the table it was\n")
    out.write("  designed against. A font with a map that still extracts badly is not the\n")
    out.write("  same problem and needs a different fix\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
