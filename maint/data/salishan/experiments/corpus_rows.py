#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The rows of the hand-extracted Salishan oracles, read once for the experiments beside this file.
#
#   Usage:  python maint/data/salishan/experiments/corpus_rows.py [ORACLES]
#
# Run on its own it prints how many form rows each language holds and which "who" values it could
# not place. The experiments import it.
#
# The oracles are closed (salishan_corpus/README.md). This file reads them where they sit, at
# build/oracles when that exists and at the private checkout beside this repository otherwise, and
# nothing it returns is written back into this tree. The experiments print counts and rates.
#
# An oracle row is where, who, kind, form, gloss. For a form row, who names the language, but the
# papers spell one language several ways (nɬeʔkepmxcín, Nɬeʔkepmxcín, Nłeʔkepmxcín), a few give an
# older name (Bella Coola for Nuxalk, Thompson), and some give a speaker or a historical source in
# place of a language. SPELLINGS folds the spellings to one name and BRANCHES gives its branch in the
# classification the survey literature uses (Thompson's overview, Kinkade's 1998 abbreviations):
# Nuxalk alone, Central Salish, Tsamosan, Tillamook, Interior Salish split north and south. A who
# that is not a language takes the language the paper states in its ops header, and is counted as
# placed through the paper. An experiment can then leave those rows out.

import collections
import glob
import os
import re
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
PRIVATE = os.path.normpath(os.path.join(ROOT, "..", "..", "private", "salishan_corpus"))


def oracle_dir(given=None):
    """The oracle tables: an explicit path, build/oracles, or the private checkout beside this tree."""
    for candidate in (given, os.path.join(ROOT, "build", "oracles"), os.path.join(PRIVATE, "oracles")):
        if candidate and os.path.isdir(candidate):
            return candidate
    raise SystemExit("no oracle tables found; pass their directory")


FORM_KINDS = ("segmentation", "transcription", "cited form", "cited affix", "phonemic", "phonetic", "root",
              "running speech", "practical orthography", "underlying")

# Branch codes: NUX Nuxalk, CS Central Salish, TS Tsamosan, TI Tillamook, NIS and SIS Northern and
# Southern Interior Salish, PROTO a reconstruction, OUT a language outside the family.
BRANCHES = {
    "Nuxalk": "NUX",
    "ʔayʔaǰuθəm": "CS", "Pentlatch": "CS", "Sechelt": "CS", "Squamish": "CS", "Halkomelem": "CS",
    "Nooksack": "CS", "Northern Straits": "CS", "Klallam": "CS", "Lushootseed": "CS", "Twana": "CS",
    "Upper Chehalis": "TS", "Lower Chehalis": "TS", "Quinault": "TS", "Cowlitz": "TS",
    "Tillamook": "TI",
    "St’át’imcets": "NIS", "Nɬeʔkepmxcín": "NIS", "Secwepemctsín": "NIS",
    "Nsyilxcən": "SIS", "Columbian": "SIS", "Montana Salish": "SIS", "Coeur d’Alene": "SIS",
    "Proto-Salish": "PROTO", "Proto-Central Salish": "PROTO", "Proto-Interior Salish": "PROTO",
    "Haisla": "OUT", "Heiltsuk": "OUT", "Oowekyala": "OUT", "Kwak’wala": "OUT", "Nuuchahnulth": "OUT",
    "Gitksan": "OUT", "Haida": "OUT", "Ktunaxa": "OUT", "Chinuk Wawa": "OUT", "English": "OUT",
    "Proto-Athabascan": "PROTO",
}

# Spellings seen in the who column, folded (casefold, straight apostrophes, ł to ɬ) to one name.
SPELLINGS = {
    "nuxalk": "Nuxalk", "bella coola": "Nuxalk",
    "ʔayʔaǰuθəm": "ʔayʔaǰuθəm", "ʔayʔajuθəm": "ʔayʔaǰuθəm", "mainland comox": "ʔayʔaǰuθəm",
    "comox": "ʔayʔaǰuθəm", "mainland comox (ayajuthem)": "ʔayʔaǰuθəm", "sliammon": "ʔayʔaǰuθəm", "ayajuthem": "ʔayʔaǰuθəm",
    "pentl'ach": "Pentlatch", "pentlatch": "Pentlatch",
    "sechelt": "Sechelt", "shashishalhem": "Sechelt", "she shashishalhem": "Sechelt",
    "squamish": "Squamish", "sḵwx̱wú7mesh": "Squamish", "skwxwú7mesh": "Squamish",
    "halkomelem": "Halkomelem", "hul'q'umi'num'": "Halkomelem", "hən̓q̓əmin̓əm̓": "Halkomelem",
    "musqueam": "Halkomelem", "chilliwack": "Halkomelem", "halq'eméylem": "Halkomelem",
    "upriver halq'eméylem": "Halkomelem", "cowichan": "Halkomelem", "downriver halkomelem": "Halkomelem",
    "nooksack": "Nooksack",
    "northern straits salish": "Northern Straits", "northern straits": "Northern Straits",
    "senćoŧen": "Northern Straits", "saanich": "Northern Straits", "lummi": "Northern Straits",
    "klallam": "Klallam",
    "lushootseed": "Lushootseed", "snohomish": "Lushootseed", "skagit": "Lushootseed",
    "twana": "Twana",
    "upper chehalis": "Upper Chehalis", "lower chehalis": "Lower Chehalis", "quinault": "Quinault",
    "cowlitz": "Cowlitz", "tillamook": "Tillamook",
    "st'át'imcets": "St’át’imcets", "st'at'imcets": "St’át’imcets", "lillooet": "St’át’imcets",
    "nɬeʔkepmxcín": "Nɬeʔkepmxcín", "thompson": "Nɬeʔkepmxcín", "nɬeʔkepmxcin": "Nɬeʔkepmxcín",
    "secwepemctsín": "Secwepemctsín", "secwepemctsin": "Secwepemctsín", "shuswap": "Secwepemctsín",
    "nsyilxcn": "Nsyilxcən", "nsyilxcən": "Nsyilxcən", "okanagan": "Nsyilxcən", "colville-okanagan": "Nsyilxcən",
    "columbian": "Columbian", "moses-columbian": "Columbian",
    "montana salish": "Montana Salish", "spokane": "Montana Salish", "kalispel": "Montana Salish",
    "coeur d'alene": "Coeur d’Alene",
    "ps": "Proto-Salish", "proto-salish": "Proto-Salish", "pcs": "Proto-Central Salish",
    "proto-central salish": "Proto-Central Salish", "pis": "Proto-Interior Salish",
    "haisla": "Haisla", "heiltsuk": "Heiltsuk", "oowekyala": "Oowekyala", "'wuikala": "Oowekyala",
    "kwak'wala": "Kwak’wala", "kwak̕wala": "Kwak’wala", "nuuchahnulth": "Nuuchahnulth",
    "nuu-chah-nulth": "Nuuchahnulth", "gitksan": "Gitksan", "x̱aad kíl": "Haida", "haida": "Haida",
    "ktunaxa": "Ktunaxa", "chinook jargon": "Chinuk Wawa", "chinuk wawa": "Chinuk Wawa",
    "english": "English", "proto-athabascan": "Proto-Athabascan",
    "nxaʔamxcín": "Columbian", "upriver halkomelem": "Halkomelem", "halq̓eméylem": "Halkomelem",
    "upper st'át'imcets": "St’át’imcets", "samish": "Northern Straits", "straits": "Northern Straits",
    "suquamish": "Lushootseed", "kwak̓wala": "Kwak’wala", "kwakiutl": "Kwak’wala", "nootka": "Nuuchahnulth",
    "comox-sliammon": "ʔayʔaǰuθəm", "ʔayʔaǰusəm": "ʔayʔaǰuθəm",
    "proto-northern interior salish": "Proto-Interior Salish",
    "songish": "Northern Straits", "northern straits (songish)": "Northern Straits",
    "northern straits (saanich)": "Northern Straits", "island halkomelem": "Halkomelem",
    "moses-columbia": "Columbian", "columbia": "Columbian", "thompson (river)": "Nɬeʔkepmxcín",
    "nxa'amxcin": "Columbian", "spokane-kalispel-montana salish": "Montana Salish", "k'omoks": "ʔayʔaǰuθəm",
    "st̓át̓imcets": "St’át’imcets", "nsyílxcən": "Nsyilxcən", "st'át'imcets (lillooet)": "St’át’imcets",
    # Robertson (ICSNL 61) compares Nicola Athabaskan with Nɬeʔkepmxcín; the Nicola forms are Dene.
    "nicola": "Nicola Athabaskan", "carrier": "Dakelh", "dakelh": "Dakelh", "clackamas kiksht": "Kiksht",
}
BRANCHES.update({"Nicola Athabaskan": "OUT", "Dakelh": "OUT", "Kiksht": "OUT"})


def fold(name):
    text = unicodedata.normalize("NFC", name).casefold().strip()
    text = text.replace("’", "'").replace("ʼ", "'").replace("̕", "'").replace("ł", "ɬ")
    return unicodedata.normalize("NFC", text)


FOLDED = {fold(key): value for key, value in SPELLINGS.items()}


def language_of(who):
    """The folded language name for a who value, or None when it names no language."""
    return FOLDED.get(fold(who))


def paper_language(stem, extract):
    """The language an ops header states for a paper, folded, or None."""
    path = os.path.join(extract, "ops", stem + ".ops")
    if not os.path.isfile(path):
        return None
    for line in open(path, encoding="utf-8").read().split("\n")[:5]:
        if line.startswith("meta lang "):
            return language_of(line[len("meta lang "):])
    return None


# The 25 papers extracted before ops files existed carry their language in paper_config.PAPERS,
# kept by hand beside the reader that is checked against them.
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "corpus_script_extraction"))
from paper_config import PAPERS  # noqa: E402

CONFIGURED = {paper.stem: language_of(paper.language) for paper in PAPERS if language_of(paper.language)}

Row = collections.namedtuple("Row", "stem where who kind form gloss language branch placed")


def rows(given=None):
    """Every oracle row, with its language folded and its branch, NFC throughout.

    A form row whose who names no language takes the language the paper's ops header states. A paper
    extracted before ops files existed states none, and such a row then takes the language of at least
    70% of the paper's own placed form rows, when one language holds that share.
    """
    directory = oracle_dir(given)
    extract = os.path.join(os.path.dirname(directory), "extract")
    out = []
    for path in sorted(glob.glob(os.path.join(directory, "*.oracle.tsv"))):
        stem = os.path.basename(path)[:-len(".oracle.tsv")]
        read = []
        for line in open(path, encoding="utf-8").read().split("\n")[1:]:
            parts = line.split("\t")
            if len(parts) >= 5:
                read.append([unicodedata.normalize("NFC", one) for one in parts[:5]])
        stated = paper_language(stem, extract) or CONFIGURED.get(stem)
        if stated is None:
            shares = collections.Counter(language_of(one[1]) for one in read
                                         if one[2] in FORM_KINDS and language_of(one[1]))
            total = sum(shares.values())
            if total and shares.most_common(1)[0][1] >= 0.7 * total:
                stated = shares.most_common(1)[0][0]
        for where, who, kind, form, gloss in read:
            language, placed = language_of(who), "who"
            if language is None and kind in FORM_KINDS:
                language, placed = stated, "paper"
            out.append(Row(stem, where, who, kind, form, gloss, language, BRANCHES.get(language), placed))
    return out


def example_label(where):
    """The example a row belongs to: '(12a) line 3' gives '(12a)'."""
    return re.sub(r"\s+line \d+$", "", where)


def glossed_pairs(all_rows):
    """Each segmentation row with the gloss row that follows it in the same example."""
    pairs = []
    for index, row in enumerate(all_rows[:-1]):
        if row.kind != "segmentation":
            continue
        for after in all_rows[index + 1:index + 4]:
            if after.stem != row.stem or example_label(after.where) != example_label(row.where):
                break
            if after.kind == "gloss":
                pairs.append((row, after))
                break
    return pairs


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    everything = rows(sys.argv[1] if len(sys.argv) > 1 else None)
    counted = collections.Counter()
    unplaced = collections.Counter()
    for row in everything:
        if row.kind not in FORM_KINDS:
            continue
        if row.language is None:
            unplaced[row.who] += 1
        else:
            counted[(row.branch, row.language, row.placed)] += 1
    for (branch, language, placed), number in sorted(counted.items(), key=lambda item: (item[0][0] or "", -item[1])):
        print("%-6s %-24s %-6s %6d" % (branch, language, placed, number))
    print("pairs of a segmentation and its gloss:", len(glossed_pairs(everything)))
    print("unplaced who values, form rows:", sum(unplaced.values()))
    for who, number in unplaced.most_common(40):
        print("   %5d %s" % (number, who))
