#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Render a paper's pages as images, so a person reads the page and not the extraction.
#
#   Usage:  python tools/dev_env/Salishan/pdf2png.py <stem> <first> <last> [scale]
#
# The text under build/papers is what pypdf could recover, and on these papers that is not what the
# page says. Lyon's Okanagan comes out as ˇx@cm@ncut where the page prints x̌əcməncut: the caron
# arrives before its letter, the schwa as @, the glottal stop as P. Words break mid-token, and the
# five-line interlinear arrives one token per line with the surface run into its own parse.
#
# A hand extraction taken off that text records the extractor. The page is the source, so the page
# is what gets read, and the images go under build/pages.

import os
import sys

import pypdfium2

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
PAGES = os.path.join(ROOT, "build", "pages")


def rendered(stem, first, last, scale):
    """Every page of one paper between first and last, written as a PNG, newest path last."""
    source = os.path.join(PAPERS, "%s.pdf" % stem)
    into = os.path.join(PAGES, stem)
    if not os.path.isdir(into):
        os.makedirs(into)
    document = pypdfium2.PdfDocument(source)
    held = []
    for number in range(first, min(last, len(document)) + 1):
        name = os.path.join(into, "page_%03d.png" % number)
        document[number - 1].render(scale=scale).to_pil().save(name)
        held.append(name)
    return held


def main():
    stem = sys.argv[1]
    first = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    last = int(sys.argv[3]) if len(sys.argv) > 3 else first
    # 3 puts a 12pt body around 50px tall, which is where a stacked diacritic stops guessing.
    scale = float(sys.argv[4]) if len(sys.argv) > 4 else 3.0
    for name in rendered(stem, first, last, scale):
        print(name)


if __name__ == "__main__":
    raise SystemExit(main())
