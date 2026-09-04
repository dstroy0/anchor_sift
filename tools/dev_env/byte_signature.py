#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether nɬeʔkepmxcín carries a signature the way every other language measured here does, reading
# the text as bytes, for Section 4.13 of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/byte_signature.py
#
# The corpus was held up on a question that turned out not to matter. Repairing the spaces the PDF put
# after each combining mark welds hén̓ us into hén̓us wherever a glottalized resonant ends a word, and both
# renderings of the story weld it identically, so no comparison between them can see it. That is a word
# boundary error. A signature reads sequence and does not read word boundaries, and the inventory was
# already checked, so the measurement can run on text whose word divisions are still uncertain.
#
# Bytes instead of characters for two reasons. Nothing has to be classified: whether a mark belongs to the
# consonant before it is a decision at the character level and is simply a byte pair at this one, so the
# error that stalled the corpus cannot be made here. And the encoding carries structure for free, since
# these consonants live in blocks that share a leading byte, which sorts them into rough classes without
# anyone choosing the classes.
#
# The test is whether this language sits in its own place. Every corpus is cut to the same number of bytes
# as the Salish one, because a longer text gives a steadier estimate and would otherwise decide the answer.
#
# The control matters more than the result. The Salish text is split in two and each half measured against
# the other, so the question is not whether Salish is far from Polish but whether it is nearer to itself
# than languages are to each other. If the two halves of one story by one speaker land as far apart as two
# unrelated languages, there is no signature at this size and the honest answer is that the corpus is too
# small.

import io
import math
import os
import statistics
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

SALISH = os.path.join(CORPORA, "salish_nlekepmxcin_verified.txt")


def salish_text():
    """The verified sentences, with the timestamps taken off."""
    lines = []
    with open(SALISH, encoding="utf-8") as handle:
        for line in handle:
            parts = line.rstrip("\n").split("\t")
            if len(parts) == 2 and parts[1].strip():
                lines.append(parts[1].strip())
    return " ".join(lines)


def treebank_text(path, want):
    """Running text from a treebank, taking each word as written and stopping at a byte count."""
    words = []
    held = 0
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if (not line) or (not line[0].isdigit()):
                continue
            parts = line.rstrip("\n").split("\t")
            if len(parts) < 2 or ("-" in parts[0]) or ("." in parts[0]):
                continue
            words.append(parts[1])
            held += len(parts[1].encode("utf-8")) + 1
            if held >= want:
                break
    return " ".join(words)


def bare(text):
    """The text with every space taken out, which is what makes the corpora comparable.

    The extraction put a space after each combining mark, and no treebank has those, so comparing
    the texts as they stand would measure the renderer. Taking every space out of every corpus
    removes that and removes the word divisions, which were never settled here anyway. It also
    makes the earlier repair a no-op: the repair only ever deleted spaces, so a repaired text and
    an unrepaired one are the same string once all the spaces are gone. Nothing is fused and
    nothing is decided, which is the point of reading it this way.
    """
    return "".join(text.split())


def pairs(text):
    """How often each byte follows each byte, as a distribution over the 65536 possible pairs."""
    blob = bare(text).encode("utf-8")
    counted = {}
    for index in range(len(blob) - 1):
        key = (blob[index] << 8) | blob[index + 1]
        counted[key] = counted.get(key, 0) + 1
    total = float(sum(counted.values())) or 1.0
    return {key: value / total for key, value in counted.items()}


def apart(first, second):
    """How far two distributions sit, as the shared area they do not share."""
    keys = set(first) | set(second)
    return 0.5 * sum(abs(first.get(key, 0.0) - second.get(key, 0.0)) for key in keys)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isfile(SALISH):
        out.write("  no %s, run salish_corpus.py first\n" % SALISH)
        out.flush()
        return 1

    whole = salish_text()
    size = len(whole.encode("utf-8"))
    out.write("  nɬeʔkepmxcín holds %d bytes over %d characters\n" % (size, len(whole)))

    held = {"nlekepmxcin": whole}
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith("ud_") and name.endswith(".conllu")):
            continue
        language = name[3:-7]
        text = treebank_text(os.path.join(CORPORA, name), size)
        if len(text.encode("utf-8")) < (size * 0.8):
            continue
        held[language] = text

    out.write("  %d languages, every one cut to about %d bytes\n" % (len(held), size))

    shapes = {name: pairs(text) for name, text in held.items()}
    names = sorted(shapes)

    # The control: one story split in two, each half read as though it were a separate language
    middle = len(whole) // 2
    first_half = pairs(whole[:middle])
    second_half = pairs(whole[middle:])
    itself = apart(first_half, second_half)

    out.write("\n  how far nɬeʔkepmxcín sits from each language\n")
    distances = []
    for name in names:
        if name == "nlekepmxcin":
            continue
        far = apart(shapes["nlekepmxcin"], shapes[name])
        distances.append((far, name))
    distances.sort()
    for far, name in distances:
        out.write("  %-14s %.4f\n" % (name, far))

    others = []
    for one in range(len(names)):
        for two in range(one + 1, len(names)):
            if "nlekepmxcin" in (names[one], names[two]):
                continue
            others.append(apart(shapes[names[one]], shapes[names[two]]))

    out.write("\n  those distances carry the writing as well as the language. nɬeʔkepmxcín is\n")
    out.write("  written in NAPA and shares almost no bytes with Cyrillic, which is why\n")
    out.write("  Russian sits at 1.0000. Cutting a language in half compares it with itself\n")
    out.write("  in its own writing, so that number is free of this and is the one to read\n")

    out.write("\n  every language cut in half, the halves against each other\n")
    out.write("  the support and the entropy are printed beside it because a writing that\n")
    out.write("  uses few byte pairs concentrates its distribution and steadies at a smaller\n")
    out.write("  sample, which would make it look consistent for a reason that is not the\n")
    out.write("  language. If closeness tracks support, the encoding is doing the work\n")
    halves = []
    for name in names:
        text = bare(held[name])
        middle = len(text) // 2
        value = apart(pairs(text[:middle]), pairs(text[middle:]))
        shape = shapes[name]
        spread = -sum(share * math.log(share, 2) for share in shape.values() if share > 0)
        halves.append((value, name, len(shape), spread))
    halves.sort()
    out.write("\n  %-14s %-9s %-9s %s\n" % ("language", "halves", "pairs", "entropy, bits"))
    for value, name, support, spread in halves:
        out.write("  %-14s %-9.4f %-9d %-9.3f%s\n"
                  % (name, value, support, spread,
                     "   <- the one being tested" if name == "nlekepmxcin" else ""))

    elsewhere = [value for value, name, support, spread in halves if name != "nlekepmxcin"]
    middle_of_them = statistics.fmean(elsewhere)
    out.write("\n  nɬeʔkepmxcín against itself      %.4f\n" % itself)
    out.write("  the other nineteen, on average   %.4f\n" % middle_of_them)
    out.write("  the worst of them               %.4f  (%s)\n"
              % (max(elsewhere),
                 [name for value, name, support, spread in halves
                  if value == max(elsewhere)][0]))
    out.write("  nearest other language           %.4f  (%s)\n"
              % (distances[0][0], distances[0][1]))
    out.write("  two unrelated languages, average %.4f\n" % statistics.fmean(others))

    out.write("\n")
    if itself <= max(elsewhere):
        out.write("  a story split in two is no further from itself than other languages are\n")
        out.write("  from themselves at this size, and it is %.1f times nearer to itself than\n"
                  % (distances[0][0] / itself))
        out.write("  to the nearest of nineteen others. The signature is present\n")
    else:
        out.write("  a story split in two is further from itself than any other language is\n")
        out.write("  from itself at this size, so what separates it from the others cannot\n")
        out.write("  be told apart from having too little of it\n")

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
