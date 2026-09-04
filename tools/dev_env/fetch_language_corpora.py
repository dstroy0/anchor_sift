#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch public domain texts for the linguistic universals test in docs/research/anchor-sift.md.
#
# The claim under test is that every natural language carries the same regularities whatever its
# culture or century, so a sample of one modern English author says nothing about it. These are
# chosen to spread across language families and across four centuries, and to include two languages
# that are not Indo-European at all.
#
# Everything lands under build/corpora and nothing is written beside the source.
#
#   Usage:  python tools/dev_env/fetch_language_corpora.py
#
# Project Gutenberg wraps each text in an English license header and footer. Left in place they would
# put English words into every corpus and the non-English rows would be measuring this file's own
# boilerplate, so the marked region is cut out and only the body is kept.

import os
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "corpora")

# id, filename, what it is. Spread over families and centuries on purpose.
WANTED = [
    (1342, "english_1813_austen.txt", "English, Indo-European Germanic, 1813"),
    (10, "english_1611_kjv.txt", "English, Indo-European Germanic, 1611"),
    (2000, "spanish_1605_cervantes.txt", "Spanish, Indo-European Romance, 1605"),
    (17489, "french_1862_hugo.txt", "French, Indo-European Romance, 1862"),
    (2229, "german_1808_goethe.txt", "German, Indo-European Germanic, 1808"),
    (7000, "finnish_1849_kalevala.txt", "Finnish, Uralic, NOT Indo-European, 1849"),
    # Same decade and same language as the 1611 KJV, and composed in it. Section 4.14
    # measures the smallest vocabulary of any prose text in the KJV, which either belongs to 1611
    # English or to the translation. This is the control that separates them.
    (100, "english_1623_shakespeare.txt", "English, Indo-European Germanic, 1623"),
    # Not a Latin script, so the byte is the wrong symbol width for it. Section 4.13.05 measures it
    # after tools/dev_env/normalize_symbols.py re-carves it.
    (36248, "greek_iliad.txt", "Greek, Indo-European Hellenic, Greek script"),
    # Section 4.13.07 failed to find an epic register in the Greek Iliad, where an epithet declines
    # with its noun and no exact match survives. These two carry the register in a language that
    # barely inflects, and the second is the same story as the Greek one. Both are single works, so
    # neither carries the anthology structure that made the burst count meaningless.
    (26, "english_1667_milton_epic.txt", "English epic verse, single work, 1667"),
    (6130, "english_1720_pope_iliad_epic.txt", "English epic verse, single work, 1720"),
    # Section 4.13.08 cannot separate a drift rate from a change of genre. These three translate one
    # book, so the subject is held fixed instead of merely matched. The first two are two years apart
    # by rival translators, which measures what translator choice alone costs, and the third is 389
    # years after the second.
    (8300, "english_1609_douay_bible.txt", "English, same subject, 1609"),
    (8294, "english_2000_web_bible.txt", "English, same subject, circa 2000"),
    # Six kinds of writing with little in common beyond having been written by people. If a property
    # holds across these it does not belong to a genre, and if it fails on one of them the earlier
    # corpora were too alike to have shown it.
    # Logographic, so a character is a morpheme and the symbols at character width are meanings and not
    # letters. Every other corpus here uses an alphabet, where a symbol sits three levels below meaning.
    # In UTF-8 a Chinese character occupies three bytes, which also tests the divisor rule on a width the
    # earlier scripts do not reach.
    (24264, "chinese_1791_hongloumeng.txt", "Chinese, logographic, novel, 1791"),
    (23962, "chinese_1592_xiyouji.txt", "Chinese, logographic, novel, 1592"),
    (23950, "chinese_1522_sanguo.txt", "Chinese, logographic, novel, 1522"),
    (2009, "kind_science_darwin.txt", "English, scientific argument, 1859"),
    (10136, "kind_procedure_beeton.txt", "English, recipes and instructions, 1861"),
    (18, "kind_legal_federalist.txt", "English, political and legal argument, 1788"),
    (2591, "kind_folktale_grimm.txt", "English, folk narrative, 1812"),
    (6763, "kind_philosophy_aristotle.txt", "English, philosophical criticism, translated"),
    (3300, "kind_economics_smith.txt", "English, economic treatise, 1776"),
]

STARTS = ("*** START OF THE PROJECT GUTENBERG", "*** START OF THIS PROJECT GUTENBERG")
ENDS = ("*** END OF THE PROJECT GUTENBERG", "*** END OF THIS PROJECT GUTENBERG")


def strip_boilerplate(text):
    """Keep only the body between Gutenberg's own markers."""
    opened = -1
    for mark in STARTS:
        found = text.find(mark)
        if found >= 0:
            opened = text.find("\n", found)
            break
    closed = -1
    for mark in ENDS:
        found = text.find(mark)
        if found >= 0:
            closed = found
            break
    if (opened >= 0) and (closed > opened):
        return text[opened:closed]
    # Said out loud. A text whose markers moved would otherwise be measured with its license attached
    return None


def fetch(book_id):
    """Try the two layouts Gutenberg serves plain text under."""
    for url in ("https://www.gutenberg.org/cache/epub/%d/pg%d.txt" % (book_id, book_id),
                "https://www.gutenberg.org/files/%d/%d-0.txt" % (book_id, book_id)):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "MMgr-research/1.0"})
            with urllib.request.urlopen(request, timeout=60) as response:
                return response.read().decode("utf-8", "replace"), url
        except Exception:
            continue
    return None, None


def main():
    os.makedirs(OUT, exist_ok=True)
    taken = 0

    for book_id, name, what in WANTED:
        target = os.path.join(OUT, name)
        if os.path.isfile(target):
            print("  have   %-32s %s" % (name, what))
            taken += 1
            continue

        raw, url = fetch(book_id)
        if raw is None:
            print("  MISS   %-32s could not fetch %d" % (name, book_id))
            continue

        body = strip_boilerplate(raw)
        if body is None:
            print("  MISS   %-32s no boilerplate markers, not kept" % name)
            continue

        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write(body)
        print("  got    %-32s %-46s %d KB" % (name, what, len(body.encode("utf-8")) // 1024))
        taken += 1

    print("\n%d of %d corpora under build/corpora" % (taken, len(WANTED)))
    return 0 if taken > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
