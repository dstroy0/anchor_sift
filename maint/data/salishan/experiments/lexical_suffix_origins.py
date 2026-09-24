#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test Kinkade's account of where Salishan lexical suffixes come from against the oracle tables.
#
#   Usage:  python maint/data/salishan/experiments/lexical_suffix_origins.py [ORACLES] [PERMUTATIONS]
#
# Kinkade (1998, "Origins of Salishan Lexical Suffixes", ICSNL 33, pp. 266-295, read in full from
# the corpus copy) defines lexical suffixes as suffixes with the meaning of a noun and "no phonological
# similarity" to it, then argues that a set of nouns in every language, which he calls [C + LS] forms,
# are the source: a consonant, sometimes a vowel, then a string equal to the lexical suffix of the
# same meaning, as Upper Chehalis mus 'eye' beside =us. He found 6 to 14 per language by hand, and
# Mithun (1984, as Kinkade quotes her) held that no derivational relation between the suffixes and
# independent nouns is discernible. The two claims make opposite predictions about a large sample.
#
# What is counted. For each Salish language, a suffix is a cited affix row whose form begins with - or
# =, or a morpheme after = in a glossed segmentation that follows a root and carries a lowercase
# English gloss (the Interior papers write clitics with = too, and their glosses are labels such as
# 3SBJ, which the lowercase test drops). A noun is a form of one morpheme, after an s- nominalizer is
# set aside, glossed with an English word. Meanings are compared as lowercase words with quotes and
# articles removed, each suffix gloss split into its senses at commas and semicolons.
#
# The Kinkade relation holds for a same-meaning pair when the noun's segments end with the suffix's
# segments and the noun is one or two segments longer. Identity, the noun equal to the suffix, is
# counted apart. Segments are a base letter with its combining marks, glottalization written as an
# apostrophe folded to one mark, 7 read as ʔ, and stress accents removed.
#
# The null keeps every language's nouns and suffixes and shuffles which meaning each noun carries.
# Under Mithun's reading the count of Kinkade pairs among same-meaning pairs should sit inside the
# shuffled distribution; under Kinkade's it should sit above it.

import collections
import random
import re
import sys
import unicodedata

import corpus_rows

SALISH = ("CS", "NIS", "SIS", "NUX", "TS", "TI")
GLOTTAL = {"'", "’", "ʼ", "̓", "̕", "ˀ"}
STRESS = {"́", "̀"}
ATTACH = {"ʷ", "ː", "·"}


def segments(form):
    """A form as a tuple of segments: base letters with their marks, stress removed."""
    out = []
    for char in unicodedata.normalize("NFD", form.casefold()):
        if char in STRESS:
            continue
        if char in GLOTTAL:
            if out:
                out[-1] += "ʼ"
            continue
        if unicodedata.combining(char) or char in ATTACH:
            if out:
                out[-1] += char
            continue
        if char == "7":
            char = "ʔ"
        if char.isalpha() or char == "ʔ":
            out.append(char)
    return tuple(unicodedata.normalize("NFC", one) for one in out)


# Lexical suffixes carry generic nominal meanings (Kinkade 1998, section 2: 'back', 'foot', 'house',
# 'water'; his Table 1 and the Moses-Columbian list in his (1)). A gloss column also carries notes
# about provenance ("wordlist", "orthography"), and a = in an Interior paper's segmentation marks a
# clitic as often as a suffix. Both suffixes and nouns are therefore kept only when a sense is one of
# these meanings, folded to one word each. The list is fixed before any pair is counted.
NOMINAL = {
    "hand": "hand", "finger": "hand", "foot": "foot", "leg": "foot", "head": "head", "top": "head",
    "face": "face", "eye": "eye", "mouth": "mouth", "lips": "mouth", "lip": "mouth", "nose": "nose",
    "ear": "ear", "back": "back", "belly": "belly", "stomach": "belly", "throat": "throat", "neck": "neck",
    "tail": "tail", "rump": "tail", "bottom": "bottom", "base": "bottom", "buttocks": "bottom",
    "arm": "arm", "tooth": "tooth", "teeth": "tooth", "hair": "hair", "skin": "skin", "hide": "skin",
    "chest": "chest", "breast": "chest", "heart": "heart", "side": "side", "edge": "edge",
    "water": "water", "liquid": "water", "fire": "fire", "house": "house", "dwelling": "house",
    "road": "road", "trail": "road", "path": "road", "tree": "tree", "plant": "plant", "bush": "plant",
    "person": "person", "people": "people", "child": "child", "canoe": "canoe", "boat": "canoe",
    "land": "land", "ground": "land", "earth": "land", "rock": "rock", "stone": "rock", "day": "day",
    "container": "container", "rope": "rope", "blanket": "blanket", "clothes": "clothing",
    "clothing": "clothing", "garment": "clothing", "animal": "animal", "language": "language",
    "speech": "language", "food": "food", "fish": "fish", "wind": "wind", "rain": "rain", "snow": "snow",
    "egg": "egg", "horn": "horn", "antler": "horn", "wood": "wood", "stick": "wood", "log": "wood",
    "belongings": "belongings", "knee": "knee", "shoulder": "shoulder", "cheek": "cheek", "skull": "head",
}


def senses(gloss):
    """The nominal meanings a gloss offers, folded by NOMINAL: quoted meanings when it has quotes."""
    quoted = re.findall(r"[‘'\"“]([^’'\"”]+)[’'\"”]", gloss)
    text = " , ".join(quoted) if quoted else gloss
    text = re.sub(r"^page \d+,?\s*", "", text.casefold())
    found = []
    for part in re.split(r"[,;/()\[\]]| or ", text):
        part = re.sub(r"^\s*(the|a|an|his|her|its|one's)\s+", "", part.strip()).strip(" .:")
        if part in NOMINAL and NOMINAL[part] not in found:
            found.append(NOMINAL[part])
    return found


def meaning(gloss):
    """A noun's single meaning, or None when its gloss is not one short English word or phrase."""
    offered = senses(gloss)
    return offered[0] if offered else None


def collect(everything):
    suffixes = collections.defaultdict(dict)
    nouns = collections.defaultdict(dict)
    for row in everything:
        if row.branch not in SALISH:
            continue
        form = row.form.strip()
        if row.kind == "cited affix" and re.match(r"^[-=]", form) and not form.endswith(("-", "=")):
            key = segments(form)
            if len(key) >= 2 and senses(row.gloss):
                suffixes[row.language].setdefault(key, set()).update(senses(row.gloss))
        elif row.kind in ("cited form", "root", "transcription", "phonemic") and " " not in form:
            bare = re.sub(r"^s-", "", form)
            if re.search(r"[-=~√*<>]", bare):
                continue
            wanted = meaning(row.gloss)
            if wanted:
                nouns[row.language].setdefault(segments(bare), wanted)
    for segmentation, gloss in corpus_rows.glossed_pairs(everything):
        if segmentation.branch not in SALISH:
            continue
        words, glosses = segmentation.form.split(), gloss.form.split()
        if len(words) != len(glosses):
            continue
        for word, sense in zip(words, glosses):
            parts, labels = re.split(r"([-=])", word), re.split(r"([-=])", sense)
            if len(parts) != len(labels):
                continue
            content = [index for index in range(0, len(parts), 2) if re.fullmatch(r"[a-z.]+", labels[index])]
            if len(parts) == 1 or (len(parts) == 3 and parts[1] == "-" and labels[0].casefold() in ("nom", "nmlz")):
                offered = senses(labels[-1].replace(".", " "))
                if offered:
                    nouns[segmentation.language].setdefault(segments(parts[-1]), offered[0])
            for index in range(2, len(parts), 2):
                if parts[index - 1] == "=" and index in content and any(one < index for one in content):
                    key, offered = segments(parts[index]), senses(labels[index].replace(".", " "))
                    if len(key) >= 2 and offered:
                        suffixes[segmentation.language].setdefault(key, set()).update(offered)
    return suffixes, nouns


def kinkade(noun, suffix):
    return len(noun) - len(suffix) in (1, 2) and noun[-len(suffix):] == suffix


def tail(noun, suffix):
    """The looser relation: the noun is longer than the suffix and ends with it."""
    return len(noun) > len(suffix) and noun[-len(suffix):] == suffix


def count(suffixes, nouns, meaning_of, found=None):
    """Same-meaning pairs, and among them the Kinkade, tail and identical ones."""
    relation, ends, identical, pairs = 0, 0, 0, 0
    for suffix, offered in suffixes.items():
        for noun in nouns:
            if meaning_of[noun] in offered:
                pairs += 1
                if noun == suffix:
                    identical += 1
                    continue
                if kinkade(noun, suffix):
                    relation += 1
                if tail(noun, suffix):
                    ends += 1
                    if found is not None:
                        found.append(("".join(noun), "".join(suffix), meaning_of[noun],
                                      "Kinkade" if kinkade(noun, suffix) else "tail"))
    return relation, ends, identical, pairs


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    given = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].isdigit() else None
    permutations = int(sys.argv[-1]) if sys.argv[-1].isdigit() else 2000
    suffixes, nouns = collect(corpus_rows.rows(given))
    generator = random.Random(1998)
    observed = [0, 0]
    null_totals = [[0] * permutations, [0] * permutations]
    pooled_pairs, found = 0, []
    print("%-18s %4s %5s %5s %7s %9s %5s %9s %5s %9s" % ("language", "LS", "nouns", "pairs", "Kinkade", "null mean",
                                                          "tail", "null mean", "ident", "p (tail)"))
    for language in sorted(suffixes, key=lambda one: -len(suffixes[one])):
        own_nouns = nouns.get(language, {})
        if len(suffixes[language]) < 3 or len(own_nouns) < 10:
            continue
        relation, ends, identical, pairs = count(suffixes[language], own_nouns, own_nouns, found)
        pooled_pairs += pairs
        keys, labels = list(own_nouns), list(own_nouns.values())
        shuffled_counts = [[], []]
        for trial in range(permutations):
            generator.shuffle(labels)
            null = count(suffixes[language], own_nouns, dict(zip(keys, labels)))
            for which in (0, 1):
                shuffled_counts[which].append(null[which])
                null_totals[which][trial] += null[which]
        observed[0] += relation
        observed[1] += ends
        above = sum(1 for one in shuffled_counts[1] if one >= ends)
        print("%-18s %4d %5d %5d %7d %9.2f %5d %9.2f %5d %9.4f" % (
            language, len(suffixes[language]), len(own_nouns), pairs, relation,
            sum(shuffled_counts[0]) / permutations, ends, sum(shuffled_counts[1]) / permutations, identical,
            (above + 1) / (permutations + 1)))
    for which, name in ((0, "Kinkade (noun one or two segments longer)"), (1, "tail (noun longer, ends in it)")):
        above = sum(1 for one in null_totals[which] if one >= observed[which])
        print("pooled %s: observed %d, null mean %.2f, null max %d, p %.4f over %d shuffles, %d same-meaning pairs"
              % (name, observed[which], sum(null_totals[which]) / permutations, max(null_totals[which]),
                 (above + 1) / (permutations + 1), permutations, pooled_pairs))
    for noun, suffix, sense, relation in found:
        print("   %-8s %s ~ =%s '%s'" % (relation, noun, suffix, sense))


if __name__ == "__main__":
    main()
