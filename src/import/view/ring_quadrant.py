#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Is a winning nonce's ring sector predictable from the header, across the real blockchain.

    python tools/view/ring_quadrant.py --check     the controls, each able to fail
    python tools/view/ring_quadrant.py             the corpus sweep over fold depth

THE CLAIM UNDER TEST

Every real block carries a nonce that won: its header hashed under the target. Map that nonce onto
the proven ring and it lands in a sector, a quadrant at fold depth two, a finer arc as the ring folds
deeper. The claim is that the sector is not uniform, and better, that it is PREDICTABLE from the part
of the header fixed before the nonce is chosen, the midstate. If it is, a miner narrows the search to
the predicted sector before spending a hash.

WHY THE HEADER, AND NOT THE NONCE DISTRIBUTION ITSELF

Recorded nonces are known to cluster for reasons that have nothing to do with the hash: mining
hardware searches ranges in its own order, so the nonce that gets FOUND is skewed by habit. That skew
is the same whatever header is mined, so it cannot make one header's winning sector track that
header's own midstate. A correlation between the midstate's sector and the nonce's sector therefore
cannot be a mining artifact. It is either ring structure in the hash or it is nothing, and the drawn
null separates the two: pairing each midstate with another block's nonce holds the mining skew and
breaks only the header-to-nonce link, so its agreement is the floor a real link has to clear.

THE NULL IS DRAWN, NOT DERIVED

Chance agreement at fold depth d over 2^d sectors is 2^-d, but the recorded nonces are not uniform, so
the analytic 2^-d is the wrong floor. The floor is drawn: shuffle the nonces against the midstates
many times and read the agreement each shuffle gives. A real link clears the shuffled band; a number
sitting inside it is the mining skew and not a hash weakness.

WHAT IS HELD

Every number here is about the nonce and sits under the fail-closed partition as HELD.
"""

import hashlib
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
PROOFING = os.path.normpath(os.path.join(HERE, "..", "..", "examples", "proofing"))
if PROOFING not in sys.path:
    sys.path.insert(0, PROOFING)

import build_bend_view  # noqa: E402
import build_sha_sphere_view  # noqa: E402
import four_step  # noqa: E402

MASK = 0xFFFFFFFF
RING = four_step.PRIME  # 2013265921, the proven modulus the ring lives in.


def midstate_position(block):
    """The nonce-independent part of the header, as a position on the ring.

    The nonce is header bytes 76 to 79, in the second SHA chunk, so the state after the first
    sixty-four bytes is fixed before the nonce is chosen. Its eight words folded to a single integer
    modulo the ring is a fingerprint of the header a miner holds before spending a hash.
    """
    first_words, _ = build_bend_view.header_words(build_bend_view.header_bytes(block, 0))
    midstate = build_sha_sphere_view.compress(first_words, 64)
    packed = b"".join(struct.pack(">I", word & MASK) for word in midstate)
    return int.from_bytes(packed, "big") % RING


def nonce_position(block):
    """The winning nonce as a position on the ring."""
    return (int(block["nonce"]) & MASK) % RING


def digest_position(block):
    """The winning block hash as a position on the ring, the actual output the nonce drove to."""
    return int(block["id"], 16) % RING


def previous_position(block):
    """The previous block hash as a ring position: a header quantity fixed before the nonce."""
    return int(block["previousblockhash"], 16) % RING


def merkle_position(block):
    """The merkle root as a ring position: a header quantity fixed before the nonce."""
    return int(block["merkle_root"], 16) % RING


def sector(position, depth):
    """Which of the 2^depth arcs of the ring a position falls in, the ring folded `depth` times."""
    return (position * (1 << depth)) // RING


def agreement(pairs, depth):
    """The share of (predicted position, actual position) pairs whose sectors match, at this depth."""
    if not pairs:
        return 0.0
    hits = sum(1 for predicted, actual in pairs if sector(predicted, depth) == sector(actual, depth))
    return hits / len(pairs)


def drawn_band(pairs, depth, draws, seed):
    """The agreement a shuffled pairing gives, over `draws` shuffles: the floor a real link must clear.

    Shuffling the actual positions against the predicted ones holds each column's own distribution,
    including whatever mining skew it carries, and breaks only the link between them. Returns the
    2.5th, 50th and 97.5th percentiles.
    """
    predicted = [pair[0] for pair in pairs]
    actual = [pair[1] for pair in pairs]
    generator = random.Random(seed)
    scores = []
    for _ in range(draws):
        shuffled = actual[:]
        generator.shuffle(shuffled)
        scores.append(agreement(list(zip(predicted, shuffled)), depth))
    scores.sort()
    count = len(scores)
    return (scores[int(0.025 * (count - 1))], scores[int(0.5 * (count - 1))],
            scores[int(0.975 * (count - 1))])


def _check():
    failed = 0
    lines = []

    def say(text):
        lines.append(text)

    # SECTORS PARTITION THE RING. Every position lands in exactly one arc, and the arc index runs from
    # zero to 2^depth minus one with none missing at the ends.
    for depth in (1, 2, 4, 8):
        lowest = sector(0, depth)
        highest = sector(RING - 1, depth)
        say("  depth %d: position 0 in sector %d, position RING-1 in sector %d of %d"
            % (depth, lowest, highest, 1 << depth))
        if lowest != 0 or highest != (1 << depth) - 1:
            say("    FAIL the sectors do not cover the ring")
            failed += 1

    # A PLANTED LINK IS SEEN. Pair each midstate with a nonce forced into the SAME sector, and the
    # agreement must be one. Pair it with a nonce in the NEXT sector, and the agreement must be zero.
    generator = random.Random(7)
    planted = []
    crossed = []
    for _ in range(2000):
        position = generator.randrange(RING)
        same = (sector(position, 4) * (RING >> 4)) + generator.randrange(RING >> 4)
        planted.append((position, same % RING))
        crossed.append((position, (same + (RING >> 4)) % RING))
    say("  planted same-sector agreement at depth 4: %.3f (want 1.000)" % agreement(planted, 4))
    say("  planted next-sector agreement at depth 4: %.3f (want 0.000)" % agreement(crossed, 4))
    if agreement(planted, 4) < 0.999:
        say("    FAIL a real same-sector link was not seen")
        failed += 1
    if agreement(crossed, 4) > 0.001:
        say("    FAIL a next-sector pairing was counted as agreement")
        failed += 1

    # NO LINK IS THE DRAWN BAND. Independent positions agree at about 2^-depth, and the true
    # independent agreement sits inside the shuffled band by construction.
    independent = [(generator.randrange(RING), generator.randrange(RING)) for _ in range(4000)]
    low, mid, high = drawn_band(independent, 4, 200, 11)
    live = agreement(independent, 4)
    say("  independent pairs at depth 4: agreement %.4f, shuffled band %.4f to %.4f (chance %.4f)"
        % (live, low, high, 1.0 / 16))
    if not (low <= live <= high):
        say("    FAIL independent agreement fell outside its own shuffled band")
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

    draws = 400
    if "--draws" in argv:
        at = argv.index("--draws")
        draws = int(argv[at + 1])

    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        sys.stderr.write("no chain corpus found under tools/chain\n")
        return 2

    pairs = [(midstate_position(block), nonce_position(block)) for block in blocks]
    print("  %d real headers, heights %d to %d; predictor is the midstate, actual is the nonce"
          % (len(pairs), blocks[0]["height"], blocks[-1]["height"]))
    print("  ring modulus %d, folded to depth d gives 2^d sectors" % RING)
    print("  %6s %8s %14s %22s %10s" % ("depth", "sectors", "agreement", "shuffled band",
                                        "verdict"))
    for depth in (1, 2, 3, 4, 6, 8):
        live = agreement(pairs, depth)
        low, mid, high = drawn_band(pairs, depth, draws, 1000 + depth)
        verdict = "OVER" if live > high else ("under" if live < low else "in band")
        print("  %6d %8d %14.5f %10.5f to %.5f %10s"
              % (depth, 1 << depth, live, low, high, verdict))
    print("")
    print("  agreement OVER the shuffled band is a header-to-nonce link the mining skew cannot make.")
    print("  in band is no link: the winning sector is not predictable from the header at that depth.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
