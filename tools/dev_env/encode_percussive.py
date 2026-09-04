#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Re-encode an existing corpus into a percussive representation, for the universals test in
# docs/research/anchor-sift.md.
#
# Section 4.13 measures six alphabetic texts. All six are written in scripts where one mark is one
# sound, so a regularity found in all of them could belong to that script family instead of to
# language. Morse carries the same words with the same meaning over two marks and two silences, so it
# separates the two: whatever survives the re-encoding was never a property of the alphabet.
#
#   Usage:  python tools/dev_env/encode_percussive.py [source] [target]
#
# Morse is also the sharpest case for one of the two regularities. Its letter codes were assigned by
# hand with the shortest given to the most frequent letters, so the brevity law is built into the
# encoding and not merely expected of it.

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

CODE = {
    "a": ".-", "b": "-...", "c": "-.-.", "d": "-..", "e": ".", "f": "..-.",
    "g": "--.", "h": "....", "i": "..", "j": ".---", "k": "-.-", "l": ".-..",
    "m": "--", "n": "-.", "o": "---", "p": ".--.", "q": "--.-", "r": ".-.",
    "s": "...", "t": "-", "u": "..-", "v": "...-", "w": ".--", "x": "-..-",
    "y": "-.--", "z": "--..",
    "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
    "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
}

# One space between letters and a slash between words, which is how Morse is written down. Both are
# silences in the transmitted form and both are single bytes here, so the detector meets two candidate
# boundaries and picks whichever is the more regular.
LETTER_GAP = " "
WORD_GAP = "/"


def shuffled_table():
    """Reassign the same set of codes to different letters.

    Morse had regional variants that gave different codes to the same letters, so a code table is a
    choice and not part of the message. Permuting it keeps every code length that Morse has and
    destroys which letter each one was given to, which separates the two regularities: how often a
    word recurs cannot depend on how its letters are spelled, and how long a code is was somebody's
    decision. The permutation is fixed so a run reproduces.
    """
    letters = sorted(CODE.keys())
    codes = [CODE[letter] for letter in letters]
    order = list(range(len(codes)))
    state = 0x243F6A88

    for slot in range(len(order) - 1, 0, -1):
        state = ((state * 1103515245) + 12345) & 0x7FFFFFFF
        pick = state % (slot + 1)
        order[slot], order[pick] = order[pick], order[slot]

    return {letters[index]: codes[order[index]] for index in range(len(letters))}


def main():
    source = sys.argv[1] if len(sys.argv) > 1 else os.path.join(CORPORA, "english_1813_austen.txt")
    target = sys.argv[2] if len(sys.argv) > 2 else os.path.join(CORPORA, "morse_from_english_1813.txt")
    dialect = sys.argv[3] if len(sys.argv) > 3 else "standard"

    if dialect == "shuffled":
        # Built before the old table is dropped, since it is built out of the old table
        replacement = shuffled_table()

        CODE.clear()
        CODE.update(replacement)

    if not os.path.isfile(source):
        print("no source at %s" % source)
        return 1

    with open(source, encoding="utf-8", errors="replace") as handle:
        text = handle.read()

    out = []
    letters = 0
    words = 0
    pending = []

    for character in text.lower():
        code = CODE.get(character)
        if code is not None:
            pending.append(code)
            letters += 1
            continue
        if pending:
            out.append(LETTER_GAP.join(pending))
            pending = []
            words += 1
        # Every run of anything not encodable is one word gap, so punctuation and layout do not each
        # become a separator and inflate the count
        if out and (not out[-1].endswith(WORD_GAP)):
            out.append(WORD_GAP)

    if pending:
        out.append(LETTER_GAP.join(pending))
        words += 1

    body = "".join(out)

    os.makedirs(CORPORA, exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="") as handle:
        handle.write(body)

    print("%s\n  %d letters and %d words became %d bytes over %d distinct marks"
          % (os.path.basename(target), letters, words, len(body), len(set(body))))
    return 0


if __name__ == "__main__":
    sys.exit(main())
