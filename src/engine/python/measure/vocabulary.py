#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# How often a text uses each of a vocabulary the whole set shares.
#
#   Usage:  from measure.vocabulary import common_vocabulary, word_profile
#
# The unit where authorship has been found since the disputed Federalist papers were settled on
# function word frequencies alone, and this work's own numbers say the same thing sharply.
#
# Seven writers, thirty one works, all English prose of nearly one period, so the language, the
# script and the century are fixed and only the writer changes. Which character follows which gets
# 35.5 percent, only two and a half times chance, with a writer's own works sitting 0.0600
# apart against 0.0680 for two writers. How often each common word is used gets 77.4 percent, with
# 0.0220 against 0.0331.
#
# That split was predicted before it was measured, and the reason is the same one that runs through
# the language results: the character web follows a writing system. It pairs Zulu with Xhosa when
# they share an alphabet, loses Tamil from Malayalam when their scripts diverge, and moves twice as
# far for a change of characters as for no change at all. Seven writers sharing an alphabet entirely
# leave it nothing to work with, and the misses say so plainly: Conrad taken for Eliot, Eliot for
# Conrad and for Stevenson, Doyle for Stevenson, which is period and register.
#
# One caution that belongs with this measure and not with the character one. The objection that a
# text is not one distribution was raised against the whole approach and measured as negligible,
# because letter frequencies barely move within a book. Word frequencies move a great deal between
# chapters and speakers, and this reading is built on exactly that quantity, so part of its 77.4
# percent is carried by a drift the character reading was immune to.
#
# The vocabulary is chosen from every text together and never from each one. A writer is therefore
# described by how they use a shared vocabulary, not by which vocabulary they happen to have.

import re

import numpy

# Words kept, taken by frequency over the whole set.
COMMON_WORDS = 150

# A text shorter than this many words gives a profile that is a reading of the sample.
LEAST_WORDS = 5000

WORD = re.compile(r"[a-z']+")


def common_vocabulary(texts, how_many=COMMON_WORDS):
    """The `how_many` commonest words across every text together.

    Taking them per text would describe each one by the words it happens to hold, which is a
    different question and an easier one.
    """
    counts = {}
    for text in texts:
        for word in WORD.findall(text.lower()):
            counts[word] = counts.get(word, 0) + 1
    return sorted(counts, key=lambda word: -counts[word])[:how_many]


def word_profile(text, vocabulary, least=LEAST_WORDS):
    """How often this text uses each word of a shared vocabulary, as shares of its own length.

    Returns None where the text holds too few words.
    """
    words = WORD.findall(text.lower())
    if len(words) < least:
        return None

    counts = {}
    for word in words:
        counts[word] = counts.get(word, 0) + 1
    total = float(len(words))
    return numpy.asarray([counts.get(word, 0) / total for word in vocabulary],
                         dtype=numpy.float64)
