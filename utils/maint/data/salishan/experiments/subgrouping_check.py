#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# A known-answer run: does meaning-matched vocabulary from the oracles recover the accepted Salish
# subgrouping? Nothing new is claimed about the subgrouping. It is the check the other experiments in
# this directory have to pass before a comparison across languages built on these tables is trusted.
#
#   Usage:  python maint/data/salishan/experiments/subgrouping_check.py [ORACLES] [PERMUTATIONS]
#
# Forms are reduced to Dolgopolsky sound classes (labial P, dental T, sibilant and affricate S,
# velar and uvular K, lateral fricative and affricate L, liquid R, nasals M and N, glides W and J;
# vowels and laryngeals dropped), after the practical orthographies' digraphs are read as one sound
# and a nominalizing s- is set aside. Two forms of one meaning are counted as a match when their first
# two classes agree, the criterion Turchin, Peiros and Gell-Mann (2010) use. Their paper is cited from
# report and was not read for this file. The criterion is coarse by design: it survives the dozen
# orthographies in these tables, and chance matches are measured, not assumed away.
#
# For each pair of languages, the match rate over the meanings both attest is set against the rate
# when one language's meanings are shuffled. The excess, observed minus shuffled, is the signal.
#
# Fixed before the first run, the check passes when:
#   (a) each Interior language's highest-excess Salish partner is Interior,
#   (b) each Central Salish language's highest-excess Salish partner is Central Salish,
#   (c) the mean excess among Interior pairs and among Central pairs each exceeds the mean excess
#       between an Interior and a Central language,
#   (d) no language outside the family has an excess with a Salish language above the largest excess
#       its own shuffles produce for that pair.
# Criterion (d) as fixed depends on how many shuffles are run: Kwak'wala with ʔayʔaǰuθəm failed it at
# 200 and passed at 500. It is replaced, after that run and recorded as a change, by: no pair of an
# outside language and a Salish language has a shuffle p below 0.01 (0.05 divided across the pairs
# tested would be stricter still).

import collections
import random
import re
import sys
import unicodedata

import corpus_rows

DIGRAPHS = (("tl'", "ƛ"), ("tl’", "ƛ"), ("lh", "ɬ"), ("ch", "č"), ("sh", "š"), ("tth", "θ"), ("th", "θ"),
            ("hw", "x"), ("kw", "k"), ("qw", "q"), ("xw", "x"), ("gw", "g"), ("ts", "c"), ("tz", "c"))
CLASSES = {}
for letters, name in (("pbfφ", "P"), ("tdθð", "T"), ("szcčšžǰʃʒj", "S"), ("kgqxχɣ", "K"), ("ɬƛłλ", "L"),
                      ("rl", "R"), ("m", "M"), ("nŋ", "N"), ("w", "W"), ("y", "J")):
    for letter in letters:
        CLASSES[letter] = name


def classes(form):
    """The Dolgopolsky class string of a form, with a leading nominalizing s set aside."""
    text = unicodedata.normalize("NFC", form.casefold())
    text = re.sub(r"^s-", "", text)
    for digraph, one in DIGRAPHS:
        text = text.replace(digraph, one)
    text = "".join(char for char in unicodedata.normalize("NFD", text) if not unicodedata.combining(char))
    text = text.replace("ɫ", "ɬ")
    out = [CLASSES[char] for char in text if char in CLASSES]
    if len(out) > 2 and out[0] == "S" and re.match(r"^s[^aeiouəɛɩʌɔæáéíóú]", text):
        out = out[1:]
    return "".join(out)


def concept(gloss):
    """One English meaning: the quoted gloss when there is one, else a short plain gloss."""
    quoted = re.findall(r"[‘\"“]([^’\"”]+)[’\"”]", gloss)
    text = quoted[0] if quoted else gloss
    text = text.casefold().strip()
    text = re.split(r"[,;/(]| or ", text)[0].strip(" .:!?")
    text = re.sub(r"^(the|a|an|to|be)\s+", "", text)
    if re.fullmatch(r"[a-z]+(?: [a-z]+)?", text) and not re.match(r"^page\b", text):
        return text
    return None


# Glosses that describe a row's source or status and name no meaning.
NOT_MEANINGS = {"wordlist", "orthography", "engine language", "phonemic", "phonetic", "pairs", "columns",
                "current orthography", "underlying", "engine residue", "as said", "unbroken line", "appendix",
                "footnote", "candidate", "target consonant", "second step", "as printed"}
# Added after the first runs, which put Nuxalk nearest ʔayʔaǰuθəm on 'mother', 'father', 'child'
# and 'money'. Parent and child terms built on m, n, p, t match across unrelated languages the world
# over, and the post-contact meanings are loans that travel between neighbors. Lists built for
# finding cognates leave both out; this one did not, and now does.
NOT_EVIDENCE = {"mother", "father", "mom", "dad", "mama", "papa", "child", "baby", "grandmother",
                "grandfather", "money", "dollar", "doctor", "coffee", "tea", "sugar", "horse", "cow", "apple",
                "school", "store", "teacher", "church", "car", "book", "paper", "pig", "cat", "bread", "flour",
                "rice", "potato", "cattle", "table", "chair", "box", "bottle", "priest", "christmas", "sunday"}
NOT_MEANINGS |= NOT_EVIDENCE


def vocabulary(everything):
    """Meaning to class strings, per language, from single-morpheme forms and glossed roots."""
    words = collections.defaultdict(lambda: collections.defaultdict(set))
    for row in everything:
        if row.language is None or row.placed != "who":
            continue
        if row.kind in ("cited form", "root", "transcription", "phonemic") and " " not in row.form.strip():
            if re.search(r"[=~√*<>…]", row.form) or row.form.count("-") > 1:
                continue
            meaning = concept(row.gloss)
            shape = classes(row.form.split("-")[-1])
            if meaning and meaning not in NOT_MEANINGS and len(shape) >= 2:
                words[row.language][meaning].add((shape, row.stem))
    for segmentation, gloss in corpus_rows.glossed_pairs(everything):
        if segmentation.language is None or segmentation.placed != "who":
            continue
        forms, glosses = segmentation.form.split(), gloss.form.split()
        if len(forms) != len(glosses):
            continue
        for form, sense in zip(forms, glosses):
            parts, labels = re.split(r"[-=]", form), re.split(r"[-=]", sense)
            if len(parts) != len(labels):
                continue
            for part, label in zip(parts, labels):
                if re.fullmatch(r"[a-z]+(?:\.[a-z]+)?", label):
                    shape = classes(part)
                    meaning = label.replace(".", " ")
                    if len(shape) >= 2 and meaning not in NOT_MEANINGS:
                        words[segmentation.language][meaning].add((shape, segmentation.stem))
    return words


# A comparative paper cites two languages' forms side by side because they resemble each other. A
# match between two forms read off one paper measures that paper's selection. A match counts only
# when the two forms come from different papers, unless the run is given "same" to show the size of
# that selection.
ACROSS_PAPERS = "same" not in sys.argv[1:]


def match(first, second):
    return any(one[0][:2] == two[0][:2] and (one[1] != two[1] or not ACROSS_PAPERS)
               for one in first for two in second)


def excess(left, right, generator, permutations):
    shared = sorted(set(left) & set(right))
    if len(shared) < 15:
        return None
    observed = sum(1 for meaning in shared if match(left[meaning], right[meaning])) / len(shared)
    others = [right[meaning] for meaning in shared]
    rates = []
    for _ in range(permutations):
        generator.shuffle(others)
        rates.append(sum(1 for meaning, shape in zip(shared, others) if match(left[meaning], shape)) / len(shared))
    above = sum(1 for rate in rates if rate >= observed)
    return observed - sum(rates) / len(rates), observed, len(shared), (above + 1) / (len(rates) + 1)


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    given = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].isdigit() else None
    permutations = int(sys.argv[-1]) if sys.argv[-1].isdigit() else 200
    words = vocabulary(corpus_rows.rows(given))
    languages = [one for one in words if len(words[one]) >= 40 and corpus_rows.BRANCHES.get(one) != "PROTO"]
    languages.sort(key=lambda one: (corpus_rows.BRANCHES.get(one), one))
    generator = random.Random(61)
    table = {}
    for index, left in enumerate(languages):
        for right in languages[index + 1:]:
            result = excess(words[left], words[right], generator, permutations)
            if result:
                table[(left, right)] = table[(right, left)] = result
    print("languages with 40 or more meanings:")
    for one in languages:
        print("   %-5s %-18s %5d meanings" % (corpus_rows.BRANCHES[one], one, len(words[one])))
    print("\nexcess match rate (observed minus shuffled), shared meanings in brackets")
    salish = ("CS", "NIS", "SIS", "NUX", "TS", "TI")
    for left in languages:
        partners = sorted(((table[(left, right)][0], right) for right in languages
                           if (left, right) in table), reverse=True)
        print("%-5s %-18s %s" % (corpus_rows.BRANCHES[left], left, "  ".join(
            "%s %+.3f[%d]" % (right[:10], value, table[(left, right)][2]) for value, right in partners[:5])))
    interior = ("NIS", "SIS")

    def branch(one):
        return corpus_rows.BRANCHES[one]

    verdicts = []
    for group, name in ((interior, "a"), (("CS",), "b")):
        for left in languages:
            if branch(left) not in group:
                continue
            partners = [(table[(left, right)][0], right) for right in languages
                        if (left, right) in table and branch(right) in salish]
            if partners:
                best = max(partners)[1]
                verdicts.append((name, left, best, branch(best) in group))
    for name, left, best, ok in verdicts:
        print("(%s) %-18s best Salish partner %-18s %s" % (name, left, best, "pass" if ok else "FAIL"))

    def mean_between(first, second):
        values = [table[(left, right)][0] for left in languages for right in languages
                  if left < right and (left, right) in table and
                  ((branch(left) in first and branch(right) in second) or (branch(left) in second and branch(right) in first))]
        return sum(values) / len(values) if values else float("nan"), len(values)

    within_interior = mean_between(interior, interior)
    within_central = mean_between(("CS",), ("CS",))
    across = mean_between(interior, ("CS",))
    print("(c) mean excess: Interior pairs %+.3f (%d), Central pairs %+.3f (%d), Interior-Central %+.3f (%d): %s"
          % (within_interior[0], within_interior[1], within_central[0], within_central[1], across[0], across[1],
             "pass" if within_interior[0] > across[0] and within_central[0] > across[0] else "FAIL"))
    failures = []
    for left in languages:
        if branch(left) != "OUT":
            continue
        for right in languages:
            if (left, right) in table and branch(right) in salish:
                value, _, shared, chance = table[(left, right)]
                if chance < 0.01:
                    failures.append("%s-%s %+.3f p %.4f [%d]" % (left, right, value, chance, shared))
    print("(d) outside-Salish pairs with shuffle p below 0.01: %s" % ("; ".join(failures) if failures else "none, pass"))
    for left in languages:
        if branch(left) == "NUX":
            for group, name in ((interior, "Interior"), (("CS",), "Central"), (("TS",), "Tsamosan")):
                values = [table[(left, right)][0] for right in languages if (left, right) in table and branch(right) in group]
                if values:
                    print("Nuxalk mean excess with %-9s %+.3f over %d languages" % (name, sum(values) / len(values), len(values)))


if __name__ == "__main__":
    main()
