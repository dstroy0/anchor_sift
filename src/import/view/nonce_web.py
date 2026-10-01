#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""The alphabet and word web of the 14k (nonce, hash) units, read as connected components.

    python tools/view/nonce_web.py --check     the controls, each able to fail
    python tools/view/nonce_web.py             the web over the corpus

THE FRAMING

Each block is a WORD, the nonce followed by its hash. The ALPHABET is the sub-patterns those words are
built from, the length-L windows that appear across the corpus. A word web joins two words that share
a RARE sub-pattern, one carried by only a few words, because a common one joins everybody and says
nothing. The web is a graph, and its algebraic topology begins with H0, the connected components, which
is the same object anchor_sift builds when it takes the transitive closure of a relation into classes.

THE MEASURE

Every negative here is a boundary, not a failure: it says the words do not link on shared rare
sub-patterns at this length, which maps where the structure is not. The reading is the component
structure, the count of non-singleton components and the largest one, against a null of random units
with the same leading zeros and nonce weight. Real words that link more than random do it because they
share sub-patterns beyond chance; matching the null is the boundary that says they do not.

WHY RARE

A sub-pattern in almost every word is the leading zeros, which link everybody and carry no
information. A sub-pattern in a handful is a feature those few share, and it is the only kind that can
carry a web with structure. The rarity ceiling is swept, not chosen, so the reading is a curve over
how rare a shared pattern has to be to count.

WHAT IS HELD

Every number here is about the nonce and sits under the fail-closed partition as HELD.
"""

import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_bend_view  # noqa: E402

MASK = 0xFFFFFFFF


def unit_value(block):
    """The word as one integer: the 32-bit nonce in the high bits, the 256-bit hash below it."""
    return ((int(block["nonce"]) & MASK) << 256) | int(block["id"], 16)


def kgrams(value, width, length):
    """The set of length-`length` windows of a `width`-bit value, each as an integer."""
    mask = (1 << length) - 1
    found = set()
    for shift in range(width - length + 1):
        found.add((value >> shift) & mask)
    return found


class Union(object):
    """Union-find over the words, so shared rare patterns merge them into components."""

    def __init__(self, count):
        self.parent = list(range(count))

    def find(self, at):
        root = at
        while self.parent[root] != root:
            root = self.parent[root]
        while self.parent[at] != root:
            self.parent[at], at = root, self.parent[at]
        return root

    def join(self, first, second):
        first_root, second_root = self.find(first), self.find(second)
        if first_root != second_root:
            self.parent[first_root] = second_root


def components(values, width, length, rarity):
    """The component structure of the word web at one window length and rarity ceiling.

    Returns (non-singleton component count, largest component size). Two words are joined where they
    share a window carried by at least two and at most `rarity` words: rare enough to be a feature and
    not the leading zeros everybody has.
    """
    holders = {}
    for index, value in enumerate(values):
        for gram in kgrams(value, width, length):
            holders.setdefault(gram, []).append(index)
    union = Union(len(values))
    for gram, words in holders.items():
        if 2 <= len(words) <= rarity:
            for other in words[1:]:
                union.join(words[0], other)
    sizes = {}
    for index in range(len(values)):
        root = union.find(index)
        sizes[root] = sizes.get(root, 0) + 1
    non_singletons = sum(1 for size in sizes.values() if size > 1)
    largest = max(sizes.values()) if sizes else 0
    return non_singletons, largest


def random_units(count, width, leading, nonce_weight, seed):
    """Random words with the same leading zeros and nonce weight: the null the corpus is read against."""
    generator = random.Random(seed)
    values = []
    for _ in range(count):
        nonce = 0
        for index in generator.sample(range(32), nonce_weight):
            nonce |= 1 << index
        tail_bits = 256 - leading
        tail = generator.getrandbits(tail_bits) if tail_bits > 0 else 0
        values.append((nonce << 256) | tail)
    return values


def _check():
    failed = 0
    lines = []

    def say(text):
        lines.append(text)

    width = 288
    length = 44
    rarity = 60

    # RANDOM WORDS OF THIS LENGTH DO NOT PERCOLATE. A window of 44 bits has 2^44 values, so 400 words
    # holding a few hundred each almost never share one, and the web stays near all singletons. A short
    # window collapses everybody into one component through chance collisions, which is the chaining the
    # engine warns about, so the length is chosen long enough that random fragments. This is the control
    # that the reading is not saturated before the corpus is even seen.
    generator = random.Random(4)
    random_only = [generator.getrandbits(width) for _ in range(400)]
    _, random_largest = components(random_only, width, length, rarity)
    say("  random words, no plant: largest component %d (near 1 means the length reads rarity)"
        % random_largest)
    if random_largest > 3:
        say("    FAIL random words percolate at this length, so the web is saturated")
        failed += 1

    # A PLANTED SHARED PATTERN MAKES A COMPONENT THAT STANDS OUT. Twenty words carrying the same rare
    # 44-bit window merge into one component of twenty, far above the fragmented random floor.
    planted = [generator.getrandbits(width) for _ in range(400)]
    shared = generator.getrandbits(length)
    for index in range(30):
        planted[index] = (planted[index] & ~((1 << length) - 1)) | shared
    _, planted_largest = components(planted, width, length, rarity)
    say("  planted 30 words sharing a window: largest component %d (want at least 30)" % planted_largest)
    if planted_largest < 30:
        say("    FAIL a planted shared pattern did not form its component")
        failed += 1

    say("")
    say("%d check(s) failed" % failed)
    sys.stdout.write("\n".join(lines) + "\n")
    return failed


def main(argv):
    if "--help" in argv or "-h" in argv:
        sys.stdout.write(__doc__)
        return 0
    if "--check" in argv:
        return 1 if _check() else 0

    width = 288
    draws = 20
    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        sys.stderr.write("no chain corpus found under tools/chain\n")
        return 2

    values = [unit_value(block) for block in blocks]
    # The leading zeros and mean nonce weight the null must match, read off the corpus.
    leadings = [256 - int(block["id"], 16).bit_length() for block in blocks]
    leading = min(leadings)
    nonce_weight = sum(bin(int(block["nonce"]) & MASK).count("1") for block in blocks) // len(blocks)
    print("  %d real (nonce, hash) words, width %d bits, null at %d leading zeros, nonce weight %d"
          % (len(values), width, leading, nonce_weight))
    print("  %6s %8s %20s %24s %10s" % ("length", "rarity", "non-singletons", "largest component",
                                        "verdict"))

    for length in (40, 44, 48):
        for rarity in (60, max(60, len(values) // 20)):
            live_ns, live_largest = components(values, width, length, rarity)
            null_ns = []
            null_largest = []
            for draw in range(draws):
                units = random_units(len(values), width, leading, nonce_weight, 1000 + draw)
                ns, largest = components(units, width, length, rarity)
                null_ns.append(ns)
                null_largest.append(largest)
            null_ns.sort()
            null_largest.sort()
            high_ns = null_ns[int(0.975 * (len(null_ns) - 1))]
            high_largest = null_largest[int(0.975 * (len(null_largest) - 1))]
            verdict = "OVER" if (live_ns > high_ns or live_largest > high_largest) else "in band"
            print("  %6d %8d %20s %24s %10s"
                  % (length, rarity, "%d (null <=%d)" % (live_ns, high_ns),
                     "%d (null <=%d)" % (live_largest, high_largest), verdict))
    print("")
    print("  a web OVER the null links more words on shared rare patterns than random units do, which")
    print("  is structure in the corpus. in band is the boundary: no shared-pattern web beyond chance.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
