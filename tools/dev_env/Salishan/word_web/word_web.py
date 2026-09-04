#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The word web: every form the hand extractions hold, joined to the forms it is related to.
#
#   Usage:  python tools/dev_env/Salishan/word_web/word_web.py
#           from word_web import web, concept_profile
#
# The anchor sift squashes text to a distribution over byte pairs and asks how far two of those
# distributions are apart. That works and it needs no per-language term, but it is the page as
# bytes: it cannot see that cítxʷ and citxw are the same word written twice, and it cannot see that
# a Nuxalk word and a Lushootseed word mean the same thing.
#
# The web is what carries that. It has three kinds of edge and each is measured off the extraction
# rather than listed by hand:
#
#   concept    two forms whose glosses share a content word. This is the edge that crosses
#              orthographies and dialects, because a concept is the one thing both papers wrote in
#              English. It is what makes an anchor a concept expressed as a distribution instead of
#              a bag of characters.
#   shape      two forms of one language sharing a leading or trailing run of at least SHAPE_RUN
#              characters. Salish morphology is heavily affixed and reduplicating, so a shared run
#              is usually a shared root or a shared affix. It is a measurement, not a parse.
#   context    two forms written in the same section of the same paper by the same speaker. Words
#              that turn up together in one telling are related by that telling.
#
# The web is per language and is written to build/corpora/<language>.web.tsv. Nothing here decides
# what a language is: the who column of the extraction says, and where it says northern or southern
# that is what it says, because the paper said so.

import collections
import glob
import io
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
for _category in os.scandir(HERE):
    if _category.is_dir():
        sys.path.insert(0, _category.path)

from papers import EVERY  # noqa: E402
from salish_unsorted import is_language_token  # noqa: E402

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
TABLES = os.path.join(ROOT, "docs", "research", "Salishan", "pure_corpus")
CORPORA = os.path.join(ROOT, "build", "corpora")

# How long a shared leading or trailing run has to be before it counts as a shape edge. Two
# characters joins every word with a schwa in it, which is a web with one node. Four is long enough
# that a shared run is a morpheme and short enough to catch the short roots.
SHAPE_RUN = 4

# English function words carry no concept, so a gloss sharing one of these with another gloss is not
# two forms meaning the same thing. This is the whole of the list and it is English, not Salish:
# nothing here is a claim about any of the languages being extracted.
EMPTY = frozenset((
    "a", "an", "the", "of", "to", "in", "on", "at", "by", "for", "with", "from", "and", "or",
    "but", "is", "are", "was", "were", "be", "been", "being", "it", "its", "he", "she", "they",
    "them", "his", "her", "their", "this", "that", "these", "those", "there", "here", "as", "so",
    "not", "no", "then", "than", "when", "who", "whom", "which", "what", "you", "your", "i", "me",
    "my", "we", "us", "our", "him", "one", "s", "t",
))


def tables():
    """Every hand extraction on disk, as (stem, marks, rows).

    papers.py is the one table saying which extraction goes with which paper and what that paper
    writes its language with. Reading it here keeps the web on the same list the checks grade
    against, so a paper cannot be in the web and outside the checks.
    """
    held = []
    for name, stem, record, repair, marks in EVERY:
        path = os.path.join(TABLES, name)
        if not os.path.isfile(path):
            continue
        rows = []
        with open(path, encoding="utf-8") as handle:
            for at, line in enumerate(handle):
                if at == 0:
                    continue
                if not line.strip():
                    continue
                # A row whose gloss is empty is written with no trailing tab, so it arrives as four
                # fields. That is most of them: 1401 of Lyon's 1417. Requiring five dropped every
                # one and left the web reading sixteen rows of that paper.
                parts = line.rstrip("\n").split("\t")
                if len(parts) == 4:
                    parts.append("")
                if len(parts) == 5:
                    rows.append(parts)
        held.append((stem, marks, rows))
    return held


def concepts(gloss):
    """The content words of a gloss, which is what two forms have to share to be one concept."""
    held = set()
    for one in gloss.lower().replace("/", " ").replace(",", " ").replace(";", " ").split():
        word = "".join(letter for letter in one if letter.isalpha())
        if word and (word not in EMPTY) and (len(word) > 2):
            held.add(word)
    return held


def shapes(form):
    """The leading and trailing runs of a form, which is where a shared morpheme shows up."""
    held = set()
    bare = form.strip()
    if len(bare) > SHAPE_RUN:
        held.add("<%s" % bare[:SHAPE_RUN])
        held.add("%s>" % bare[-SHAPE_RUN:])
    return held


def web(rows, marks, language):
    """One language's web: its forms, and the three kinds of edge joining them.

    Returns (forms, edges). forms is the distinct language forms, edges is a Counter keyed by the
    joined pair and the kind of edge, which is the thing a distribution gets taken over.

    A row's form is kept only where it is language under this paper's alphabet. The kind column is
    not consulted: a title and a transcription are told apart by whether the marks are in them,
    which is the same test the checks use, so the web cannot drift from what the checks call
    language.
    """
    forms = []
    by_concept = collections.defaultdict(set)
    by_shape = collections.defaultdict(set)
    by_context = collections.defaultdict(set)
    for where, who, kind, form, gloss in rows:
        pieces = [one for one in form.split() if is_language_token(one, marks)]
        if not pieces:
            continue
        whole = " ".join(pieces)
        forms.append(whole)
        for one in concepts(gloss):
            by_concept[one].add(whole)
        for one in shapes(whole):
            by_shape[one].add(whole)
        by_context[(where, who)].add(whole)

    edges = collections.Counter()
    for kind, table in (("concept", by_concept), ("shape", by_shape), ("context", by_context)):
        for key, members in table.items():
            held = sorted(members)
            # A group of n forms is n*(n-1)/2 edges, and one section of a story can hold a hundred
            # forms. The context groups are capped so a single long section does not outweigh every
            # concept edge in the language.
            if (kind == "context") and (len(held) > 24):
                continue
            for first in range(len(held)):
                for second in range(first + 1, len(held)):
                    edges[(held[first], held[second], kind)] += 1
    return sorted(set(forms)), edges


def concept_profile(edges):
    """The web as a distribution, which is what the sift can be handed in place of byte pairs.

    Keyed on the concept and shape edges only. The context edges are a fact about one paper's
    sections and do not transfer to a page nobody has read, so they are in the web for reading and
    out of the profile for matching.
    """
    counts = collections.Counter()
    for (first, second, kind), seen in edges.items():
        if kind in ("concept", "shape"):
            counts[(first, second, kind)] += seen
    total = sum(counts.values())
    if not total:
        return {}, 0
    return {key: value / total for key, value in counts.items()}, total


def by_language():
    """Every extraction's rows regrouped under the language its who column names.

    A paper whose who column says northern and southern is two languages here, because that is what
    the paper says its forms are. The dialect border is not being discovered at this step and is not
    being guessed at: it is being read off the extraction, so anything measured against it later is
    measured against a label that came from the paper.
    """
    held = collections.defaultdict(list)
    marks = {}
    for stem, sheet, rows in tables():
        for where, who, kind, form, gloss in rows:
            name = who.strip().lower()
            if name in ("northern", "southern"):
                name = "Lushootseed %s" % name
            else:
                name = stem
            held[name].append((where, who, kind, form, gloss))
            marks[name] = sheet
    return held, marks


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isdir(CORPORA):
        os.makedirs(CORPORA)

    grouped, marks = by_language()
    out.write("  %-34s %-8s %-9s %-9s %-9s %s\n"
              % ("group", "rows", "forms", "concept", "shape", "context"))
    total_forms = 0
    total_edges = 0
    for name in sorted(grouped):
        rows = grouped[name]
        forms, edges = web(rows, marks[name], name)
        if not forms:
            continue
        counted = collections.Counter(kind for (_, _, kind) in edges.elements())
        out.write("  %-34s %-8d %-9d %-9d %-9d %d\n"
                  % (name[:34], len(rows), len(forms), counted["concept"], counted["shape"],
                     counted["context"]))
        total_forms += len(forms)
        total_edges += sum(counted.values())

        path = os.path.join(CORPORA, "%s.web.tsv" % name.replace(" ", "_").replace("/", "_"))
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write("first\tsecond\tkind\tseen\n")
            for (first, second, kind), seen in sorted(edges.items()):
                handle.write("%s\t%s\t%s\t%d\n" % (first, second, kind, seen))

    out.write("\n  %d forms, %d edges, written to %s\n"
              % (total_forms, total_edges, os.path.relpath(CORPORA, ROOT)))
    out.write("  a concept edge is the one that crosses an orthography, because the gloss is the\n")
    out.write("  only part of a form two papers wrote the same way\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
