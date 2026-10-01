#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""The nonce and its hash as one unit: local entropy of the pair across the 14k real blocks.

    python tools/view/nonce_hash_unit.py --check     the controls, each able to fail
    python tools/view/nonce_hash_unit.py             the reading over the corpus

WHY THE PAIR AND NOT EITHER ALONE

The nonce alone and the hash alone both read flat. The pair is not the same object: the hash is a
deterministic function of the nonce and the header, a nonce and its own hash carry a link that a
nonce and a stranger's hash do not. Reading the two as one unit is reading that link. The measure is
local, because a link that is real locally can cancel over the whole unit exactly as it did for the
nonce alone.

THE MEASURE

The unit is the nonce's 32 bits followed by the hash's 256 bits, 288 in all. Its local order is the
sum over sliding windows of one minus the window's bit entropy: a window that is a solid run of the
same bit contributes one, a balanced window contributes nothing. A unit carrying local structure has
a higher local order than a unit that does not.

THE CONFOUND, HANDLED IN THE NULL

A winning hash has about seventy-eight leading zero bits by construction, a long solid run that is
pure local order and tells nothing new: it is the hash winning, which is already known. So the null
draws a unit with the SAME leading zeros, a random nonce and a hash of that many zeros then a random
tail. The winning unit read against that null carries structure only if it beats a unit whose sole
order is the leading zeros it shares. That is the whole point of the pairing test.

THE OTHER READING

The diff between the nonce's own local order and the hash tail's, per block, across the corpus. If the
nonce and its hash tail share a local-entropy relationship, the diff is narrower than a shuffled
pairing of nonces with other blocks' hash tails gives. The shuffle is the null.

WHAT IS HELD

Every number here is about the nonce and sits under the fail-closed partition as HELD.
"""

import math
import os
import random
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_bend_view  # noqa: E402

MASK = 0xFFFFFFFF


def binary_entropy(fraction):
    if fraction <= 0.0 or fraction >= 1.0:
        return 0.0
    return -(fraction * math.log2(fraction)) - ((1.0 - fraction) * math.log2(1.0 - fraction))


def sliding_local_order(bits, window):
    """Sum over cyclic windows of one minus the window's bit entropy: the unit's local order."""
    length = len(bits)
    total = 0.0
    running = sum(bits[index] for index in range(window))
    for start in range(length):
        total += 1.0 - binary_entropy(running / float(window))
        running += bits[(start + window) % length] - bits[start]
    return total


def nonce_bits(value):
    return [(value >> shift) & 1 for shift in range(31, -1, -1)]


def hash_bits(block):
    """The 256 bits of the block id, most significant first, so the leading zeros lead."""
    value = int(block["id"], 16)
    return [(value >> shift) & 1 for shift in range(255, -1, -1)]


def leading_zeros(bits):
    count = 0
    for bit in bits:
        if bit != 0:
            break
        count += 1
    return count


def matched_null_order(nonce_weight, digest, leading, window, draws, seed):
    """Local order of units drawn with the same leading zeros: a random nonce, then zeros, then a tail."""
    generator = random.Random(seed)
    scores = []
    tail_length = 256 - leading
    for _ in range(draws):
        nonce = [1 if generator.random() < (nonce_weight / 32.0) else 0 for _ in range(32)]
        tail = [generator.getrandbits(1) for _ in range(tail_length)]
        unit = nonce + ([0] * leading) + tail
        scores.append(sliding_local_order(unit, window))
    scores.sort()
    count = len(scores)
    return (scores[int(0.025 * (count - 1))], scores[int(0.5 * (count - 1))],
            scores[int(0.975 * (count - 1))])


def _check():
    failed = 0
    lines = []

    def say(text):
        lines.append(text)

    window = 8

    # A SOLID UNIT IS MAXIMUM LOCAL ORDER, a random one is near the floor. If they do not separate the
    # measure is not reading local order.
    solid = sliding_local_order([1] * 288, window)
    generator = random.Random(9)
    noise = [generator.getrandbits(1) for _ in range(288)]
    flat = sliding_local_order(noise, window)
    say("  solid unit local order %.1f, random unit %.1f: %s"
        % (solid, flat, "solid is more ordered" if solid > 5 * flat else "WRONG WAY"))
    if not (solid > 5 * flat):
        say("    FAIL a solid unit is not far above a random one")
        failed += 1

    # THE LEADING-ZERO CONFOUND IS REAL AND THE NULL HOLDS IT. A unit of 78 zeros then random has a
    # large local order from the zeros alone, and the matched null must sit right at it, a winner
    # is measured against its own leading zeros and not against a flat unit.
    zeros_then_noise = [generator.getrandbits(1) for _ in range(32)] + [0] * 78 + \
        [generator.getrandbits(1) for _ in range(178)]
    live = sliding_local_order(zeros_then_noise, window)
    band = matched_null_order(16, None, 78, window, 300, 11)
    say("  a 78-zero unit: local order %.2f, matched null %.2f to %.2f, in band %s"
        % (live, band[0], band[2], band[0] <= live <= band[2]))
    if not (band[0] <= live <= band[2]):
        say("    FAIL the matched null does not contain a unit of its own leading zeros")
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

    window = 8
    draws = 120
    if "--window" in argv:
        window = int(argv[argv.index("--window") + 1])

    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        sys.stderr.write("no chain corpus found under tools/chain\n")
        return 2

    print("  %d real blocks, unit is the 32-bit nonce then the 256-bit hash, window %d"
          % (len(blocks), window))
    print("  local order against a null holding the same leading zeros: over the band is structure")
    print("  the leading zeros cannot make. Also the nonce-to-hash-tail diff against a shuffled pairing.")
    print("")

    over = inside = under = 0
    excess = 0.0
    nonce_orders = []
    tail_orders = []
    band_cache = {}
    for block in blocks:
        bits = hash_bits(block)
        leading = leading_zeros(bits)
        nonce = nonce_bits(int(block["nonce"]) & MASK)
        unit = nonce + bits
        live = sliding_local_order(unit, window)
        # The matched null depends only on the leading-zero count and the nonce weight, not the block,
        # so it is drawn once per pair and reused. Without this the 14k nulls dominate the run.
        key = (leading, sum(nonce))
        band = band_cache.get(key)
        if band is None:
            band = matched_null_order(sum(nonce), bits, leading, window, draws, 1000 + leading)
            band_cache[key] = band
        excess += live - band[1]
        if live > band[2]:
            over += 1
        elif live < band[0]:
            under += 1
        else:
            inside += 1
        nonce_orders.append(sliding_local_order(nonce + nonce, window))
        tail_orders.append(sliding_local_order(bits[leading:] + bits[leading:], window))

    total = len(blocks)
    print("  units over the matched null: %d, in band: %d, under: %d, of %d; chance about %.1f each"
          % (over, inside, under, total, 0.025 * total))
    print("  mean local order above the matched-null median: %.4f (zero is no structure past the zeros)"
          % (excess / total))

    # The nonce-order against hash-tail-order relationship, real pairing versus shuffled.
    real = sum(abs(n - t) for n, t in zip(nonce_orders, tail_orders)) / total
    generator = random.Random(7)
    shuffled_tails = tail_orders[:]
    generator.shuffle(shuffled_tails)
    shuffled = sum(abs(n - t) for n, t in zip(nonce_orders, shuffled_tails)) / total
    print("")
    print("  mean |nonce order - hash-tail order|: real pairing %.4f, shuffled pairing %.4f"
          % (real, shuffled))
    print("  a real pairing far below the shuffled one is a nonce-to-hash local-entropy link; equal is none.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
