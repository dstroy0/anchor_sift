#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Write a first draft of what the page says, for a paper whose text is the font's encoding.
#
#   Usage:  python tools/dev_env/Salishan/draft_page_text.py <stem>
#
# Writes build/papers/<stem>.page.txt, line for line with the extraction so a page of one is a page
# of the other. Every rule it applies is in lyon_encoding.py, and the file it writes is a draft: it
# is not the paper until a person has read the rendered page beside it.
#
# closed_spaces is not applied here, although these papers do break words. Its rule is that a space
# after a stacked mark is inserted, and in these two the space lands in front of the mark instead:
# the extraction writes c ’kaPít@t for ck̓aʔítət. Running it after the map welds the wrong pairs,
# turning sti ’m uì into stim̓uɬ, because the mark now sits at the end of a token. Which of these
# spaces is a word boundary is what the page settles: iP ’kl is two words and i ’klíP is one.

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "corpus_script_extraction"))

from lyon_encoding import drafted  # noqa: E402

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")


def draft(stem):
    """One paper's extraction as a draft of the page, written beside it, and the line count."""
    source = os.path.join(PAPERS, "%s.txt" % stem)
    target = os.path.join(PAPERS, "%s.page.txt" % stem)
    with open(source, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    out = [drafted(one) for one in lines]
    with open(target, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(out))
    return target, len(lines)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    for stem in sys.argv[1:]:
        target, count = draft(stem)
        out.write("  %s  %d lines\n" % (os.path.basename(target), count))
    out.write("\n  a draft, not the paper. read the rendered page beside it before trusting a line.\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
