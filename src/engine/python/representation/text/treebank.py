#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Reading a treebank, where each token arrives with the reading it actually had.
#
#   Usage:  from representation.text.treebank import read_sentences, capped, TOKEN_CAP
#
# No other text source here carries an annotation, only characters. Readings sharing a surface form
# are therefore counted and never estimated.
#
# Two things about it decide how anything measured from it may be read.
#
# It records the reading a word had where it appeared and not every reading it could have. A longer
# corpus therefore finds more ambiguity, and languages of unlike corpus size cannot be compared.
# The corpora here run seventeenfold in size, and `capped` exists for that reason: every language is
# cut to one token count on whole sentences before the columns are set beside each other.
#
# Folding case is the routine move and it is wrong for German. A capital mid-sentence there marks a
# noun, and the same letters lowercase are a verb: Essen is the meal and essen is to eat. Folding
# throws that channel away and then reports German as the most ambiguous language in the set, which
# is a fact about the preprocessing. Keeping it starves the first word instead, where everything is
# capitalized whether it is a noun or not. So the first word is folded and every word after it keeps
# what it was written with.

# Tokens every language is cut to. Readings per word climb with corpus size, and these corpora run
# from twenty thousand tokens to 1.2 million, so any column set beside another is cut to this first.
TOKEN_CAP = 60000


def read_sentences(path, fold_case=True):
    """Every sentence as its tokens in order, each with the reading that sentence gave it.

    Yields (form, reading) pairs where reading is lemma, part of speech and features joined. Multi
    word tokens and empty nodes are skipped, since their identifiers carry a dash or a dot and they
    duplicate tokens that are already counted.
    """
    sentences = []
    building = []

    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            trimmed = line.rstrip("\n")
            if not trimmed.strip():
                if building:
                    sentences.append(building)
                    building = []
                continue
            if not trimmed[0].isdigit():
                continue

            parts = trimmed.split("\t")
            if len(parts) < 6 or ("-" in parts[0]) or ("." in parts[0]):
                continue

            form = parts[1].lower() if fold_case else parts[1]
            reading = "%s|%s|%s" % (parts[2].lower(), parts[3], parts[5])
            building.append((form, reading))

    if building:
        sentences.append(building)
    return sentences


def read_sentences_both(path):
    """The same, with each token carried as folded, as written, and its reading.

    For the case question, where the two keyings have to be compared on identical sentences.
    """
    sentences = []
    building = []

    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            trimmed = line.rstrip("\n")
            if not trimmed.strip():
                if building:
                    sentences.append(building)
                    building = []
                continue
            if not trimmed[0].isdigit():
                continue

            parts = trimmed.split("\t")
            if len(parts) < 6 or ("-" in parts[0]) or ("." in parts[0]):
                continue

            written = parts[1]
            reading = "%s|%s|%s" % (parts[2].lower(), parts[3], parts[5])
            building.append((written.lower(), written, reading))

    if building:
        sentences.append(building)
    return sentences


def capped(sentences, limit):
    """The leading whole sentences whose tokens come to at most `limit`.

    Whole sentences, because cutting inside one would leave a fragment whose first word is not the
    first word of a sentence. The first word is where the case convention differs.

    Returns the sentences kept and how many tokens they hold.
    """
    kept = []
    total = 0
    for sentence in sentences:
        if total + len(sentence) > limit:
            break
        kept.append(sentence)
        total += len(sentence)
    return kept, total
