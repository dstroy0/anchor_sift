#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch text with every word's lemma and grammar written beside it, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/fetch_treebanks.py
#
# Polish humour turns on using a word correctly in order to use it incorrectly, and the structural reason
# is that Polish forms are shared across grammatical slots. Seven cases over three genders collapse into
# far fewer distinct forms than the paradigm allows, so one written word is often correct under two or
# three different parses at once. English cannot do this from its morphology, having almost none left, and
# has to find two unrelated words that happen to sound alike.
#
# That is countable if the grammar of each word is written down, and these treebanks write it down: every
# token carries its surface form, the lemma it belongs to, and the case, number, gender and person it
# stands in. So the count of distinct readings sharing one surface form is the syncretism, measured and
# not estimated.
#
# It also bears on why walking through a text makes the possibilities grow instead of shrink. If the
# average form carries more than one analysis, then reading a second word multiplies the readings instead
# of settling the first, and the space over a sentence grows as the product. A language averaging below
# one cannot explode and a language above one cannot help it.
#
# Languages are chosen to span that: Polish and Czech for heavy case syncretism, Finnish and Hungarian for
# many cases with little syncretism, English and Vietnamese for almost no inflection at all.

import io
import os
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")
AGENT = {"User-Agent": "MMgr-research/1.0 (linguistic invariance study)"}

BASE = "https://raw.githubusercontent.com/UniversalDependencies"
PAUSE = 0.5

WANTED = (
    # Germanic. German capitalizes every noun and the rest capitalize only names, so the family
    # holds both orthographies. Icelandic is the one that separates the two from inflection, being
    # Germanic and four-case and still capitalizing nothing but names.
    ("german", "UD_German-GSD", "de_gsd-ud-train.conllu", "Germanic, every noun capitalized"),
    ("english", "UD_English-EWT", "en_ewt-ud-train.conllu", "Germanic, names only, no cases"),
    ("dutch", "UD_Dutch-Alpino", "nl_alpino-ud-train.conllu", "Germanic, names only, no cases"),
    ("danish", "UD_Danish-DDT", "da_ddt-ud-train.conllu", "Germanic, names only, no cases"),
    ("swedish", "UD_Swedish-Talbanken", "sv_talbanken-ud-train.conllu",
     "Germanic, names only, no cases"),
    ("icelandic", "UD_Icelandic-Modern", "is_modern-ud-train.conllu",
     "Germanic, names only, four cases"),
    # Slavic, to find out whether Polish's payoff is a property of the family or of Polish
    ("polish", "UD_Polish-PDB", "pl_pdb-ud-train.conllu", "Slavic, names only, seven cases"),
    ("czech", "UD_Czech-PDT", "cs_pdt-ud-train.conllu", "Slavic, names only, seven cases"),
    ("russian", "UD_Russian-SynTagRus", "ru_syntagrus-ud-train.conllu",
     "Slavic, names only, six cases"),
    ("croatian", "UD_Croatian-SET", "hr_set-ud-train.conllu", "Slavic, names only, seven cases"),
    ("slovak", "UD_Slovak-SNK", "sk_snk-ud-train.conllu", "Slavic, names only, six cases"),
    ("ukrainian", "UD_Ukrainian-IU", "uk_iu-ud-train.conllu", "Slavic, names only, seven cases"),
    # Agglutinative, which sat at the floor of the first run
    ("finnish", "UD_Finnish-TDT", "fi_tdt-ud-train.conllu", "Uralic, fifteen cases"),
    ("hungarian", "UD_Hungarian-Szeged", "hu_szeged-ud-train.conllu", "Uralic, agglutinative"),
    ("estonian", "UD_Estonian-EDT", "et_edt-ud-train.conllu", "Uralic, fourteen cases"),
    ("turkish", "UD_Turkish-BOUN", "tr_boun-ud-train.conllu", "Turkic, agglutinative"),
    # Heavy case outside Germanic and Slavic, and two Romance for the low-inflection end
    ("latvian", "UD_Latvian-LVTB", "lv_lvtb-ud-train.conllu", "Baltic, seven cases"),
    ("romanian", "UD_Romanian-RRT", "ro_rrt-ud-train.conllu", "Romance, some case left"),
    ("spanish", "UD_Spanish-AnCora", "es_ancora-ud-train.conllu", "Romance, no case"),
    ("vietnamese", "UD_Vietnamese-VTB", "vi_vtb-ud-train.conllu", "Austroasiatic, isolating"),
)


def fetch(url):
    """The bytes at one URL."""
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=300) as response:
        return response.read()


def fetch_train(repository, filename):
    """The training file, or the lettered parts a large treebank splits it into, joined in order.

    Czech and Russian are held as cs_pdt-ud-train-a.conllu through -c and similar, and asking for
    the plain name gives a 404 that reads as a missing treebank when the treebank is there.
    """
    base = "%s/%s/master/" % (BASE, repository)
    try:
        blob = fetch(base + filename)
        time.sleep(PAUSE)
        return blob.decode("utf-8", errors="replace"), "whole"
    except urllib.error.HTTPError as refused:
        if refused.code != 404:
            return None, "refused (%s)" % refused.code

    stem = filename[:-len(".conllu")]
    pieces = []
    for letter in "abcdefghij":
        try:
            blob = fetch("%s%s-%s.conllu" % (base, stem, letter))
            time.sleep(PAUSE)
        except urllib.error.HTTPError:
            break
        pieces.append(blob.decode("utf-8", errors="replace"))
    if not pieces:
        return None, "not there (404)"
    return "\n".join(pieces), "in %d parts" % len(pieces)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(CORPORA, exist_ok=True)
    out.write("  %-12s %-34s %-10s %s\n" % ("language", "what its grammar does", "tokens", "note"))

    landed = 0
    for language, repository, filename, note in WANTED:
        target = os.path.join(CORPORA, "ud_%s.conllu" % language)
        if os.path.isfile(target) and (os.path.getsize(target) > 200000):
            with open(target, encoding="utf-8", errors="replace") as handle:
                tokens = sum(1 for line in handle if line and line[0].isdigit())
            out.write("  %-12s %-34s %-10d already held\n" % (language, note, tokens))
            landed += 1
            continue

        try:
            text, how = fetch_train(repository, filename)
        except Exception as trouble:
            out.write("  %-12s %-34s %-10s %s\n" % (language, note, "0", str(trouble)[:30]))
            continue
        if text is None:
            out.write("  %-12s %-34s %-10s %s\n" % (language, note, "0", how))
            continue
        tokens = sum(1 for line in text.splitlines() if line and line[0].isdigit())
        if tokens < 5000:
            out.write("  %-12s %-34s %-10d too few tokens\n" % (language, note, tokens))
            continue
        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write(text)
        out.write("  %-12s %-34s %-10d\n" % (language, note, tokens))
        landed += 1
        out.flush()

    out.write("\n  %d treebanks landed\n" % landed)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
