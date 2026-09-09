#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Language relationships written down from philology, before anything here is measured.
#
#   Usage:  from oracle.families import FAMILY, DRAVIDIAN, INDO_ARYAN
#
# These tables are an answer this work did not produce and cannot influence. Almost every
# measurement here has lacked one. They belong to the oracle part for that reason and not because
# they concern language: of the three ways a partition gets fixed, only supervision adds information
# the sample did not already carry, so anything holding an outside answer lives
# here and nowhere else.
#
# They are written down before the distances are computed, which lets a grouping be scored instead
# of admired afterward.
#
# What agreement with them is worth, set down here so no caller has to restate it. A family tree is a
# reconstruction argued from cognates and sound correspondences, so agreement is agreement with a
# scholarly consensus and not a check against a fact, and where the two disagree nothing here can
# say whether the instrument or the reconstruction is wrong. That is a different kind of check from
# the protein bond lengths, where valence fixes the answer whatever anyone believes. Those are an
# oracle. This is a strong prior.

# Every language the book corpus holds, by family.
FAMILY = {
    "danish": "germanic", "norwegian": "germanic", "swedish": "germanic",
    "icelandic": "germanic", "dutch": "germanic", "german": "germanic",
    "afrikaans": "germanic",
    "french": "romance", "italian": "romance", "spanish": "romance",
    "portuguese": "romance", "catalan": "romance", "romanian": "romance",
    "polish": "slavic", "czech": "slavic", "russian": "slavic",
    "serbian": "slavic", "slovenian": "slavic",
    "finnish": "uralic", "hungarian": "uralic",
    "welsh": "celtic", "irish": "celtic",
    "greek": "hellenic", "hebrew": "semitic", "persian": "iranian",
    "japanese": "japonic", "chinese": "sinitic", "tagalog": "austronesian",
    "vietnamese": "austroasiatic", "urdu": "indic", "hindi": "indic",
    "esperanto": "constructed",
}

# The languages the parallel corpus adds, which reaches families the book catalog never held.
PARALLEL = {
    "tamil": "dravidian", "malayalam": "dravidian", "telugu": "dravidian",
    "hindi": "indic", "marathi": "indic", "nepali": "indic", "gujarati": "indic",
    "bengali": "indic", "punjabi": "indic",
    "burmese": "tibeto-burman", "thai": "tai", "korean": "koreanic",
    "indonesian": "austronesian", "malay": "austronesian", "cebuano": "austronesian",
    "malagasy": "austronesian",
    "armenian": "armenian", "albanian": "albanian", "georgian": "kartvelian",
    "amharic": "semitic", "arabic": "semitic",
    "turkish": "turkic", "kazakh": "turkic",
    "latvian": "baltic", "lithuanian": "baltic",
    "estonian": "uralic", "ukrainian": "slavic", "swahili": "bantu",
    "vietnamese": "austroasiatic", "haitian": "creole",
}

# Dravidian. Its branchings are ordered well enough to give a graded prediction instead of a
# grouping: Tamil and Malayalam nearest, having split around the ninth century; Kannada beside that
# pair; Telugu furthest, being South Central and older still.
DRAVIDIAN = ("tamil", "malayalam", "kannada", "telugu")

# Three Indo-Aryan languages of the same subcontinent, written in related scripts, which have to
# fall outside the Dravidian set. If they do not, the reading is following the writing systems of a
# region and not its languages.
INDO_ARYAN = ("hindi", "bengali", "marathi")


def every_family():
    """The book and parallel tables joined, the parallel one winning where both name a language."""
    joined = dict(FAMILY)
    joined.update(PARALLEL)
    return joined


def score_against(reading, families=None):
    """How many languages with a relative present sit nearest one of their own.

    `reading` maps a language to a vector. Returns how many landed on a relative, how many were
    scoreable at all, and the misses, which are usually the informative part: Dutch to Norwegian,
    French to Spanish, Czech to Russian, Albanian to Italian is a reading finding the right
    neighborhood and then picking wrongly inside it.

    The denominator is the count of scoreable languages and never the count present. A family with
    one member in the run cannot have a neighbor inside it, and scoring those as errors is what
    turned an honest 15 of 22 into a misleading 15 of 28.
    """
    import numpy

    table = families if families is not None else every_family()
    names = sorted(reading)
    eligible = set(scoreable(names, table))

    right = 0
    misses = []
    for name in names:
        if name not in eligible:
            continue
        nearest = min((float(numpy.linalg.norm(reading[name] - reading[other])), other)
                      for other in names if other != name)[1]
        if table.get(nearest) == table.get(name):
            right += 1
        else:
            misses.append((name, nearest, table.get(nearest, "unknown")))
    return right, len(eligible), misses


def dravidian_check(reading):
    """The family's ordered prediction scored against a reading, as numbers and not as prose.

    Three examples printed this same block from three copies of it, leaving three places for the
    verdict to drift from the prediction. What is returned holds no formatting. A caller writes the
    numbers however it likes and none of them can disagree about what was asked.

    `reading` maps a language to a vector. Returns a dict whose entries are None where the
    languages needed for that part are absent:

        pair, kannada, telugu   the three distances the ordered prediction is about
        order_holds             whether pair < kannada < telugu, the predicted order
        within, across          Dravidian to Dravidian, and Dravidian to Indo-Aryan
        apart_holds             whether the family sits closer to itself than to Indo-Aryan
        strays                  Dravidian languages whose nearest neighbor is outside the family
    """
    import numpy

    def apart(one, two):
        return float(numpy.linalg.norm(reading[one] - reading[two]))

    found = {"pair": None, "kannada": None, "telugu": None, "order_holds": None,
             "within": None, "across": None, "apart_holds": None, "strays": None}

    if all(name in reading for name in DRAVIDIAN):
        pair = apart("tamil", "malayalam")
        kannada = min(apart("kannada", "tamil"), apart("kannada", "malayalam"))
        telugu = min(apart("telugu", "tamil"), apart("telugu", "malayalam"))
        found["pair"] = pair
        found["kannada"] = kannada
        found["telugu"] = telugu
        found["order_holds"] = (pair < kannada) and (kannada < telugu)

    inside = [name for name in DRAVIDIAN if name in reading]
    outside = [name for name in INDO_ARYAN if name in reading]
    if inside and outside:
        within = [apart(one, two)
                  for index, one in enumerate(inside) for two in inside[index + 1:]]
        across = [apart(one, two) for one in inside for two in outside]
        if within and across:
            found["within"] = float(numpy.mean(within))
            found["across"] = float(numpy.mean(across))
            found["apart_holds"] = found["within"] < found["across"]
        found["strays"] = [name for name in inside
                           if min((apart(name, other), other)
                                  for other in reading if other != name)[1] not in inside]
    return found


def scoreable(names, families=None):
    """The subset of `names` that has a relative present. Nothing outside it can be scored.

    A family holding one language in a run cannot have a neighbor inside it, so its nearest is
    outside its family whatever the instrument measures. Scoring those as errors is what turned an
    honest 15 of 22 into a misleading 15 of 28, and it is why Greek sitting nearest Hebrew was
    called a script artifact when neither language had a relative in the set at all.
    """
    table = families if families is not None else every_family()
    held = [name for name in names if table.get(name) is not None]
    return [name for name in held
            if sum(1 for other in held if table.get(other) == table.get(name)) >= 2]
