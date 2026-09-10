#!/usr/bin/env python3
# repotools-stamp: docs/docs_maint/quotes.py 8bbad6f8c384125a
# repo_tools - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Every quotation in src/, checked against the RFC text it says it came from.

docs/learn/RFC/README.md states the rule this enforces: "Read the section, do not recall it." A
comment that puts an RFC sentence in quotation marks is making a claim that can be settled, because
the sentence is sitting in docs/learn/RFC. Nothing else in the tree settles it - a quotation drifts
by a word and no compiler, no test and no reviewer reading the comment against the code will see it,
because the comment still says something true about the code. What it stops being true about is the
RFC.

    python tools/dev_env/quotes.py            the report
    python tools/dev_env/quotes.py --check    exit nonzero when any quotation's words differ
    python tools/dev_env/quotes.py --list     also print the ones that matched, and how

Three outcomes, and the difference between the first two is the whole design:

  verbatim   found in the RFC with only its typesetting undone - the [Page n] footer, the form feed
             and the running header removed, and words rejoined across the 72-column wrap.

  retyped    found once both sides are reduced to their words. This is what a faithful quotation
             still differs by, and none of it is an error: a nested quotation has to turn " into ',
             a reflowed list gains the commas the RFC wrote as line breaks, a sentence cut short
             gains a period, and RFC 9293 numbers requirements inline - "An application MUST
             (MUST-21) be able to" - which a quotation reasonably drops.

  differs    the words themselves are not the RFC's. Either the quotation is a paraphrase wearing
             quotation marks, or it is quoted accurately from a different RFC than the one named.

Getting the first two apart from the third is most of the work, and every normalisation here was
put in after a correct quotation was reported as an invention:

  - Page furniture goes line by line. Taking the line either side of the form feed as well ate the
    body text abutting a page break, and RFC 2236's report-suppression sentence - quoted correctly
    in igmp.h - came back as a miss.
  - A hyphen at the wrap is ambiguous and the text cannot settle it. RFC 8200 breaks
    "first-arriving" where the hyphen IS the wrap; RFC 9293 breaks "option-length" where it belongs
    to the word. Both readings are built and either may match. Reading every break as a wrap loses
    the second kind.
  - A run of // lines is one comment. code_mask marks the newline ending a // comment as code,
    because that is what it is, so reading the mask alone gives one block per line and truncates
    every quotation spanning two of them. That was hiding 591 quotations - two fifths of the total
    - and every one of the odd quote-mark counts that made blocks unreadable.
  - A block often cites a bare "sec 5.4.2" against the document the FILE is about rather than the
    last RFC it happened to name. dad.h quotes six RFC 4862 sections that way. The RFCs in the
    file's own @file comment are tried as well, or those six read as inventions.

  A comment block whose quote marks still do not pair after all that is skipped rather than guessed
  at, and the report says which. With an odd count every candidate after the stray mark is the gap
  BETWEEN two quotations, and each would be reported as an invented sentence.

WHAT THIS DOES NOT SETTLE. An RFC figure, state table or pseudo-code block is laid out in columns
with rules through it, and a phrase quoted out of one does not appear as running text: RFC 2236's
"send report, set flag, start timer" is three table cells. Those come back as differing and are not
wrong. Neither is a quoted phrase that was never the RFC's - the title of another work, a field
name, a label - which this cannot tell from a quotation. Read the differing list, do not act on its
count.

Not a pass/fail gate by default, for the same reason harness.py deps and unwired.py are not: a
paraphrase in quotation marks is a real defect but it is a documentation defect, and failing a
build on one would put pressure on the wrong thing. --check is there for when you want it held.
"""
import argparse
import collections
import io
import os
import re
import sys

ROOT = os.getcwd()
sys.path.insert(0, os.path.join(ROOT, "tools", "dev_env"))
from codemask import code_mask

RFC_DIR = os.path.join(ROOT, "docs", "learn", "RFC")

RFC_REF = re.compile(r"\bRFC\s*(\d{1,4})\b")
FOOTER = re.compile(r"\[Page \d+\]\s*$")
HEADER = re.compile(r"^RFC \d+\s")
WRAP = re.compile(r"(?<=\w)-[ \t]*\n[ \t]*(?=\w)")
MARKER = re.compile(r"\(\s*(?:MUST|SHOULD|SHLD|MAY|REQ|RFC)[- ]?\d+\s*\)", re.I)

# A quotation is prose. These are the shapes that are not: a path, an identifier, a snippet.
NOT_PROSE = re.compile(r"[/\\]|->|::|^#|^%|_[a-z]|^\{|^<")
LEADS_WITH_PUNCT = re.compile(r"^[,;:.)\]]")

_corpus = {}


def norm(s):
    """Whitespace, and the punctuation an encoding changes. Nothing that alters a word."""
    for a, b in (("’", "'"), ("‘", "'"), ("“", '"'), ("”", '"'),
                 ("–", "-"), ("—", "-")):
        s = s.replace(a, b)
    return re.sub(r"\s+", " ", s).strip()


def words(s):
    """The words alone, which is what a faithful quotation preserves."""
    s = MARKER.sub(" ", norm(s)).lower()
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9]+", " ", s)).strip()


def corpus(num):
    """((wrap-joined, wrap-kept), words) for an RFC, or None when it is not vendored."""
    if num in _corpus:
        return _corpus[num]
    path = os.path.join(RFC_DIR, "rfc{}.txt".format(num))
    if not os.path.exists(path):
        _corpus[num] = None
        return None
    raw = io.open(path, encoding="utf-8", errors="replace").read()
    body = "\n".join(
        line for line in raw.split("\n")
        if "\f" not in line and not FOOTER.search(line) and not HEADER.match(line)
    )
    kept = norm(WRAP.sub("-", body))
    _corpus[num] = ((norm(WRAP.sub("", body)), kept), words(kept))
    return _corpus[num]


def unwrap(block):
    """A comment block as prose: leaders off, wrapping gone."""
    out = []
    for line in block.splitlines():
        line = re.sub(r"^(///|//|/\*+|\*+/|\*)", "", line.strip()).strip()
        out.append(re.sub(r"\*/$", "", line).strip())
    return norm(" ".join(out))


def comment_blocks(text):
    """Every comment in the file, as (line number, raw text).

    A run of // lines is ONE comment and has to be returned as one. code_mask marks the newline
    that ends a // comment as code, because that is what it is, so scanning the mask alone yields
    one block per line and cuts every quotation that spans two of them - which is most of the long
    ones. Adjacent // blocks are merged back together here.
    """
    mask = code_mask(text)
    raw, i, n = [], 0, len(text)
    while i < n:
        if mask[i] or text[i] in " \t\r\n":
            i += 1
            continue
        j = i
        while j < n and not mask[j]:
            j += 1
        chunk = text[i:j]
        if chunk.lstrip().startswith(("//", "/*")):
            start = text.count("\n", 0, i) + 1
            raw.append([start, start + chunk.count("\n"), chunk])
        i = j

    out = []
    for start, end, chunk in raw:
        if (out and chunk.lstrip().startswith("//") and out[-1][2].lstrip().startswith("//")
                and start == out[-1][1] + 1):
            out[-1][1] = end
            out[-1][2] += "\n" + chunk
        else:
            out.append([start, end, chunk])
    return [(start, chunk) for start, _, chunk in out]


def fragments(quote):
    """A quotation split at its elisions; each side has to be found on its own."""
    parts = re.split(r"\s*\.\.\.\s*|\s*\[\.\.\.\]\s*", quote)
    return [norm(p) for p in parts if len(norm(p)) >= 12]


def quote_line(block, block_start, quote):
    """The line the quotation actually starts on, not the line its comment block starts on.

    Reporting the block is no use for checking a claim: a file-level @brief can run eighty lines
    and the reader has to hunt for which sentence was meant. The quotation is matched back into the
    raw block through the comment leaders and the wrap, and the line it lands on is returned.
    """
    tokens = [re.escape(t) for t in quote.split()[:5] if t]
    if not tokens:
        return block_start
    between = r"(?:[ \t]*(?:\n[ \t]*(?://+|\*+)?)?[ \t]*)"
    hit = re.search(between.join(tokens), block)
    return block_start + block.count("\n", 0, hit.start()) if hit else block_start


def verdict(frags, num):
    """'verbatim', 'retyped', 'differs', or None when the RFC is not vendored."""
    body = corpus(num)
    if body is None:
        return None
    forms, bag = body
    if any(all(f in form for f in frags) for form in forms):
        return "verbatim"
    if all(words(f) in bag for f in frags):
        return "retyped"
    return "differs"


def sources():
    """Every .c and .h under src/, in a stable order."""
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, "src")):
        dirnames[:] = sorted(dirnames)
        for name in sorted(filenames):
            if name.endswith((".c", ".h")):
                path = os.path.join(dirpath, name)
                yield os.path.relpath(path, ROOT).replace("\\", "/"), path


def file_context(blocks):
    """The RFCs the file's own head comment names.

    A block often cites a bare "sec 5.4.2" and means the document the FILE is about - dad.h quotes
    six RFC 4862 sections that way and never names 4862 again after its @file line. Taking only the
    RFCs named in the same block reads those against whatever was mentioned last, which was RFC 4291,
    and reports six correct quotations as inventions. The head comment is the missing context.
    """
    for lineno, block in blocks:
        if "@file" in block or "@brief" in block:
            return RFC_REF.findall(unwrap(block))
    return []


def scan():
    """Every quotation, with what became of it."""
    found, unpaired, skipped, unvendored = [], [], 0, 0
    for rel, path in sources():
        text = io.open(path, encoding="utf-8").read()
        blocks = comment_blocks(text)
        context = file_context(blocks)
        for lineno, block in blocks:
            prose = unwrap(block)
            refs = RFC_REF.findall(prose)
            if not refs:
                continue
            marks = [i for i, ch in enumerate(prose) if ch == '"']
            if len(marks) % 2:
                if len(marks) >= 3:
                    unpaired.append((rel, lineno))
                continue
            for a, b in zip(marks[0::2], marks[1::2]):
                quote = prose[a + 1 : b].strip()
                if (len(quote) < 12 or " " not in quote
                        or NOT_PROSE.search(quote) or LEADS_WITH_PUNCT.match(quote)):
                    skipped += 1
                    continue
                frags = fragments(quote)
                if not frags:
                    skipped += 1
                    continue
                order, seen = [], set()
                for num in RFC_REF.findall(prose[:a])[::-1] + refs + context:
                    if num not in seen:
                        seen.add(num)
                        order.append(num)
                results = [(num, verdict(frags, num)) for num in order]
                if all(v is None for _, v in results):
                    unvendored += 1
                    continue
                for rank in ("verbatim", "retyped"):
                    hit = next((num for num, v in results if v == rank), None)
                    if hit:
                        found.append((rel, quote_line(block, lineno, quote), hit, quote, rank))
                        break
                else:
                    found.append((rel, quote_line(block, lineno, quote), order[0], quote, "differs"))
    return found, unpaired, skipped, unvendored


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="exit nonzero when any quotation differs")
    ap.add_argument("--list", action="store_true", help="print the matches too, not just the misses")
    args = ap.parse_args()

    found, unpaired, skipped, unvendored = scan()
    tally = collections.Counter(rank for _, _, _, _, rank in found)

    print("quotations checked against a vendored RFC : {}".format(len(found)))
    print("  verbatim                               : {}".format(tally["verbatim"]))
    print("  retyped, same words                    : {}".format(tally["retyped"]))
    print("  WORDS DIFFER                           : {}".format(tally["differs"]))
    print("not prose, skipped                       : {}".format(skipped))
    print("RFC not vendored                         : {}".format(unvendored))
    print("blocks skipped, quote marks do not pair  : {}".format(len(unpaired)))

    if args.list:
        print("\n--- matched ---")
        for rel, lineno, num, quote, rank in found:
            if rank != "differs":
                print("{:<9} {}:{}  RFC {}\n    {}".format(rank, rel, lineno, num, quote[:150]))

    differs = [f for f in found if f[4] == "differs"]
    if differs:
        print("\n" + "=" * 94)
        print("WORDS DIFFER - a paraphrase in quotation marks, or the wrong RFC named")
        print("=" * 94)
        for rel, lineno, num, quote, _ in differs:
            print("{}:{}  says RFC {}".format(rel, lineno, num))
            print("    {}".format(quote[:230]))

    if unpaired:
        print("\n" + "=" * 94)
        print("NOT CHECKED - the quote marks in these blocks do not pair, so read them by hand")
        print("=" * 94)
        for rel, lineno in unpaired:
            print("  {}:{}".format(rel, lineno))

    return 1 if (args.check and differs) else 0


if __name__ == "__main__":
    sys.exit(main())
