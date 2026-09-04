#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Extract the voiceless Bella Coola words Hank Nater lists in ICSNL 59.
#
#   Usage:  python tools/dev_env/Salishan/corpus_script_extraction/extract_nater_voiceless.py
#
# Nater's argument is that Bella Coola has words with no vowel in them, so his data is 127 numbered
# entries that are each a run of two to four consonants with a gloss. That layout is the easiest in
# the set to read and the hardest to tell from English by character, because an entry like kp 'each,
# all, every' carries no mark of the orthography at all. What identifies an entry here is its
# position: a number in parentheses at the head of a column.
#
# WHAT IS NOT BELLA COOLA
#
# Six of the numbered entries, (128) to (133), are Heiltsuk. Tables 6 and 7 put Oowekyala, Kwak̓wala,
# Haisla, Sechelt, Lillooet, Upper Chehalis and Tsimshianic forms in a column beside the Bella Coola
# ones, and Heiltsuk, Oowekyala, Kwak̓wala and Haisla are North Wakashan, which is a different family
# entirely. A reader that took the whole page would build a Nuxalk corpus holding Wakashan words.
#
# So the entry number decides: 1 to 127 is Bella Coola, 128 to 133 is Heiltsuk, and the etymology
# tables are read for their Bella Coola column alone. Everything else goes to the unclassified file
# for a person to sort, which is where a form belongs when a tool cannot say whose it is.
#
# THE CLUSTER CHARTS ARE NOT WORDS
#
# Tables 2 to 5 are every two-member voiceless cluster the language allows, about two hundred cells.
# They are Bella Coola phonotactics and they are not words anybody said, so they stay out of the pure
# stream. The hand extraction records them under the kind "cluster" for the same reason.

import io
import os
import re
import sys

from inserted_space import closed_spaces
from salish_marking import DERIVED, SPOKEN, UNCLASSIFIED, rendered, switches, tagged_spans
from salish_unsorted import UNKNOWN_KIND, covered_tokens, unreached, write_unsorted

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")
CORPORA = os.path.join(ROOT, "build", "corpora")

SOURCE = os.path.join(PAPERS, "ICSNL59_Nater_2_final.txt")

# <spoken by>_<original paper>_<who wrote it down>_Salish_<language>_<year>_<mixed>
TARGET = os.path.join(
    CORPORA,
    "unstated_VoicelessWordsInBellaCoolaFactVsFiction_Nater_Salish_nuxalk_2024_mixed.txt")

# Kept in step with NATER in hand_extraction/papers.py. The apostrophe is deliberately absent: it is
# Nater's ejective mark, and putting it in the set also makes every English gloss a word of the
# language, because a gloss ends in a closing quote. papers.py has the count behind that decision.
MARKS = "ʔʕɬłƛəχ7̓̔̕ʷ˽" + "̩̌"

PAGE = re.compile(r"^===== page \d+ =====$")

# One entry of the numbered lists: the number, the form, and the gloss in single quotes. The columns
# are read by finding every one of these on a line, because the paper sets two entries per line.
#
# The right single quote cannot be used to delimit anything here. It is Nater's ejective mark, so cq’
# and c’p carry one inside the form, and a pattern that stopped at it read 73 of the 133 entries as
# ending before their own last letter and then failed to match them at all. The left single quote
# never occurs inside a form, so the form is everything up to that, and the gloss ends at the right
# quote that is followed by the next entry number or by the end of the line. Without that lookahead
# the gloss of (54) stops inside ‘pass one’s hand through sth.’
# The form also may not run across the next entry number. (108) is xp = px and carries no gloss at
# all, so a form that could span one swallowed (109) and its gloss along with it.
ENTRY = re.compile(r"\((\d{1,3})([abc])?\)\s*((?:(?!\(\d)[^‘])*?)\s*‘(.*?)’(?=\s*(?:\(\d|$))")

# A row of the two etymology tables: a list number, the Bella Coola form with its gloss, and then the
# comparandum with its own. Only the first form is Bella Coola. The same quote problem applies.
COMPARED = re.compile(r"^(\d{1,3})\s+([^‘]*?)\s*‘(.*?)’\s+(\S.*)$")

# Where the numbered entries stop being Bella Coola. (128) to (133) are Heiltsuk, cited from
# Kortlandt 1975 to show that the clustering is an areal trait.
BELLA_COOLA_LAST = 127

# What the paper marks a transitive verb with, which is not part of the form.
ASIDE = re.compile(r"\((?:tr\.|itr\.|tr\./itr\.|DIM)\)")


def form_of(text):
    """One entry's form, with the paper's own parenthesized notes taken off.

    (tr.) and (tr./itr.) sit between the form and its gloss and are English, not Bella Coola. Left
    in, every transitive entry arrives as two tokens and the second of them is the word tr.
    """
    return " ".join(ASIDE.sub(" ", text).split()).strip(" ,=")


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    if not os.path.isfile(SOURCE):
        out.write("  no %s\n" % SOURCE)
        out.flush()
        return 1

    with open(SOURCE, encoding="utf-8", errors="replace") as handle:
        lines = [closed_spaces(one.rstrip("\n")) for one in handle]

    rows = []
    where = "front matter"
    seen = set()

    for line in lines:
        trimmed = " ".join(line.split())
        if PAGE.match(trimmed) or not trimmed:
            continue

        found = ENTRY.findall(trimmed)
        if found:
            for number, letter, text, gloss in found:
                count = int(number)
                form = form_of(text)
                if not form:
                    continue
                who = "Nuxalk" if (count <= BELLA_COOLA_LAST) else "Heiltsuk"
                spot = "(%s%s)" % (number, letter)
                rows.append((spot, who, "cited form", form, gloss))
                seen.add(count)
            continue

        # A row of Table 6 or Table 7. The list number opens it, the Bella Coola form follows, and
        # whatever comes after the first gloss belongs to another language and is not read here.
        found = COMPARED.match(trimmed)
        if found and (int(found.group(1)) <= BELLA_COOLA_LAST):
            form = form_of(found.group(2))
            if form:
                rows.append(("compared %s" % found.group(1), "Nuxalk", "cited form",
                             form, found.group(3)))
            rest = found.group(4).strip()
            if rest:
                rows.append(("compared %s" % found.group(1), "", UNCLASSIFIED, rest, ""))
            continue

        rows.append((where, "", UNCLASSIFIED, trimmed, ""))

    # Every line no branch above reached, so the record holds every token the paper printed.
    missed = unreached(lines, covered_tokens(one[3] for one in rows), marks=MARKS)
    for page, spot, reason, missing, text in missed:
        rows.append(("not reached page %d" % page, "", UNCLASSIFIED, text, ""))

    with open(TARGET, "w", encoding="utf-8", newline="") as handle:
        handle.write("# Voiceless Words in Bella Coola: Fact vs. Fiction.\n")
        handle.write("# Hank Nater, Independent Linguist. Papers for the International Conference\n")
        handle.write("# on Salish and Neighbouring Languages 59, Vancouver, BC: UBCWPL, 2024.\n")
        handle.write("#\n")
        handle.write("# 127 numbered entries of Bella Coola (Nuxalk), then six of Heiltsuk. The who\n")
        handle.write("# column says which, because Heiltsuk, Oowekyala, Kwak̓wala and Haisla are\n")
        handle.write("# North Wakashan and not Salish at all.\n")
        handle.write("#\n")
        handle.write("# The cluster charts of Tables 2 to 5 are phonotactics and not words, so they\n")
        handle.write("# are not read here. The hand extraction records them.\n")
        handle.write("line\twho\tkind\tswitches\tcontent\n")
        for at, (spot, who, kind, text, gloss) in enumerate(rows, 1):
            layer = SPOKEN if (kind == "cited form") else DERIVED
            if kind == UNCLASSIFIED:
                content = "N.%s.%s:{%s}" % (layer, kind, text)
                crossings = 0
            else:
                content = rendered(text, layer, kind, MARKS)
                crossings = switches(text, MARKS)
            handle.write("line#${%d}\t%s\t%s\t%d\t%s\n"
                         % (at, who or spot, kind, crossings, content))

    # The Bella Coola words alone, one per line. Heiltsuk is held out by the who column, which is the
    # whole reason the column is there.
    pure = TARGET[:-4] + ".pure.txt"
    kept = 0
    already = set()
    with open(pure, "w", encoding="utf-8", newline="") as handle:
        for spot, who, kind, text, gloss in rows:
            if (kind != "cited form") or (who != "Nuxalk"):
                continue
            for span, run in tagged_spans(text, MARKS):
                if (span != "T") or not run.strip():
                    continue
                key = " ".join(run.split())
                if key in already:
                    continue
                already.add(key)
                handle.write("%s\n" % key)
                kept += 1

    stuck = TARGET[:-4] + ".unclassifiable.tsv"
    flagged = [(0, spot, UNKNOWN_KIND, "", text) for spot, who, kind, text, gloss in rows
               if (kind == UNCLASSIFIED) and not spot.startswith("not reached")]
    flagged.extend(missed)
    stuck_count = write_unsorted(stuck, "Voiceless Words in Bella Coola", flagged)

    out.write("  %d lines written to\n  %s\n" % (len(rows), os.path.basename(TARGET)))
    out.write("  %d Bella Coola words written to\n  %s\n" % (kept, os.path.basename(pure)))
    out.write("  %d lines the tool could not sort written to\n  %s\n"
              % (stuck_count, os.path.basename(stuck)))

    numbered = sorted(seen)
    if numbered:
        gaps = [one for one in range(1, max(numbered) + 1) if one not in seen]
        out.write("\n  entries 1..%d, missing %s\n"
                  % (max(numbered), ", ".join(str(one) for one in gaps) if gaps else "none"))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
