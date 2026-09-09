#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# How long the words are, which turns out to carry what four thousand numbers were carrying.
#
#   Usage:  from measure.word_lengths import word_lengths, length_spread
#
# Here because of a result that went against the machinery. Coarsening an alphabet down to two
# symbols left the close language pairs closer than the far pairs, and at two symbols the only
# distinction left is whether a character is the commonest one, which for most languages is the
# space. What came through the reduction was word length, and the lengths matched the pairings: Zulu
# 5.70 against Xhosa 5.88, Spanish 4.41 against French 4.66. Finnish at 6.41 sits away from Spanish
# for that reason.
#
# Put to the same question, twenty one numbers do what four thousand ninety six were doing. How the
# word lengths are distributed puts 15 of 34 languages nearest a relative. The character square puts
# 15 of 34. Mean length and its spread alone, which is two numbers, puts 12.
#
# They are not the same signal, since they fail on different languages. The lengths lose Estonian to
# Romanian and Finnish to Lithuanian. The square loses Afrikaans to Finnish and Dutch to Turkish.
# Partly complementary and neither better.
#
# The prediction that went with this was wrong and the correction is worth carrying. Word length was
# expected to rescue the families the square lost, since Uralic and Dravidian are agglutinative and
# should have long words throughout. Estonian reads 4.08 and Finnish 6.30, a wide gap inside one
# family, and it is not noise: Estonian lost its final vowels. Dravidian splits the same way,
# Malayalam at 8.84 and Telugu at 6.96. What failed the square fails the lengths, for its own
# reasons.
#
# What this measure cannot do at all is more useful than what it does. Chinese, Japanese and Thai
# mark no word boundaries, so the descriptor does not exist for them. That is the plainest case of
# this reading not being one reading across writing systems.

import re

import numpy

# Lengths above this are counted at this, so one runaway token cannot move the distribution.
LONGEST = 20

# A text shorter than this many words gives a distribution that is a reading of the sample.
LEAST_WORDS = 5000

SPLIT = re.compile(r"\s+")

# Writing systems that mark no word boundary, for which none of this exists.
NO_BOUNDARIES = ("chinese", "japanese", "thai", "burmese", "khmer", "lao")


def word_lengths(text, longest=LONGEST, least=LEAST_WORDS):
    """Mean word length and its deviation, as two numbers.

    Returns None where the text holds too few words for the mean to mean anything.
    """
    words = [word for word in SPLIT.split(text) if word]
    if len(words) < least:
        return None
    lengths = numpy.asarray([min(len(word), longest) for word in words], dtype=numpy.float64)
    return numpy.asarray([float(lengths.mean()), float(lengths.std())], dtype=numpy.float64)


def length_spread(text, longest=LONGEST, least=LEAST_WORDS):
    """How the word lengths are distributed, as shares over lengths 0 to `longest`.

    Twenty one numbers, and on the family question they match a square of four thousand ninety six.
    Returns None where the text holds too few words.
    """
    words = [word for word in SPLIT.split(text) if word]
    if len(words) < least:
        return None
    lengths = numpy.asarray([min(len(word), longest) for word in words], dtype=numpy.int64)
    spread = numpy.bincount(lengths, minlength=longest + 1).astype(numpy.float64)
    return spread / spread.sum()


def marks_boundaries(language):
    """Whether the descriptor exists for a language at all.

    Worth asking before a comparison instead of after. Where a language marks no word boundary, the
    measure does not exist for it. That is not a gap in the corpus.
    """
    return language.lower() not in NO_BOUNDARIES
