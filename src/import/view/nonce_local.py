#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Local entropy of the interior, not global: the wave cancels over the whole field, so read locally.

    python tools/view/nonce_local.py --check      the controls, each able to fail
    python tools/view/nonce_local.py              the local-disturbance reading over the corpus

WHY LOCAL

Every global reading of the nonce came back flat: correlation, self-delta, ring position, support, all
max entropy over the whole field. That is the wave cancelling over the whole system. It does not mean
the field is featureless. A field can be maximum entropy globally and carry massive disturbances
locally, a run of agreeing bits in one neighbourhood balanced by a run of disagreeing bits in another,
so the two sum to nothing and a global statistic sees nothing. The disturbance is real and only a
local reading finds it.

WHAT IS MEASURED

The 256 output bits sit at fixed directions on the sphere, the same golden spiral the whole view uses.
Each bit's neighbourhood is its nearest directions by angle. The local one-fraction of a neighbourhood
is how many of its bits are set, and its local entropy is the binary entropy of that fraction: one
where the neighbourhood is balanced, zero where it is a solid run. The LOCAL ORDER of a field is the
sum over neighbourhoods of one minus that entropy, the total departure from local balance. A globally
balanced field still carries local order where the bits clump, and that is the disturbance the global
statistics cancelled away.

THE NULL AND THE NUISANCE

Local order rises with imbalance, so the null must be drawn at the SAME bit weight the field carries,
or it reports the weight and calls it structure. The null here draws random fields at each measured
field's own popcount. A field whose local order sits above that weight-matched band is locally more
ordered than chance at its own weight; inside the band it is not, and the disturbance was the weight.

WHAT IS HELD

Every number here is about the nonce and sits under the fail-closed partition as HELD.
"""

import math
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_bend_view  # noqa: E402
import build_sha_sphere_view  # noqa: E402
import nonce_support  # noqa: E402

MASK = 0xFFFFFFFF
ROUNDS = 64
WIDTH = 256


def unit_vectors():
    """The 256 golden-spiral directions as unit vectors, the placement the whole view uses."""
    directions = build_sha_sphere_view.place("spiral")
    vectors = []
    for colatitude, longitude in directions:
        sine = math.sin(colatitude)
        vectors.append((sine * math.cos(longitude), sine * math.sin(longitude),
                        math.cos(colatitude)))
    return vectors


def neighborhoods(vectors, size):
    """For each direction, the indices of its `size` nearest directions by angle, itself included."""
    out = []
    for at in range(len(vectors)):
        here = vectors[at]
        order = sorted(range(len(vectors)),
                       key=lambda other: -(here[0] * vectors[other][0] + here[1] * vectors[other][1]
                                           + here[2] * vectors[other][2]))
        out.append(order[:size])
    return out


def binary_entropy(fraction):
    """The entropy of a single bit set with probability `fraction`, in bits, zero at the ends."""
    if fraction <= 0.0 or fraction >= 1.0:
        return 0.0
    return -(fraction * math.log2(fraction)) - ((1.0 - fraction) * math.log2(1.0 - fraction))


def local_order(bits, cells):
    """The total departure from local balance: sum over neighbourhoods of one minus their entropy."""
    total = 0.0
    for cell in cells:
        ones = sum(bits[index] for index in cell)
        total += 1.0 - binary_entropy(ones / float(len(cell)))
    return total


def state_bits(words):
    """The 256 bits of a state, most significant first, as 0 and 1."""
    bits = []
    for word in words:
        for shift in range(31, -1, -1):
            bits.append((word >> shift) & 1)
    return bits


def digest_bits(block, nonce, midstate):
    """The 256 bits of the finished double hash for one nonce, the winning condition's own field."""
    _, second_block = build_bend_view.header_words(build_bend_view.header_bytes(block, nonce))
    first = build_bend_view.round_outputs(second_block, midstate)
    message = nonce_support.second_message_words(first[ROUNDS - 1])
    return state_bits(build_bend_view.round_outputs(message, build_sha_sphere_view.H0)[ROUNDS - 1])


def interior_bits(block, nonce, midstate, round_index):
    """The 256 interior bits of the first hash's second block at one round, where the nonce still lives."""
    _, second_block = build_bend_view.header_words(build_bend_view.header_bytes(block, nonce))
    return state_bits(build_bend_view.round_outputs(second_block, midstate)[round_index])


def weight_matched_band(cells, weight, draws, seed):
    """Local order of random fields drawn at a fixed bit weight: the floor at that weight."""
    generator = random.Random(seed)
    scores = []
    for _ in range(draws):
        bits = [0] * WIDTH
        for index in generator.sample(range(WIDTH), weight):
            bits[index] = 1
        scores.append(local_order(bits, cells))
    scores.sort()
    count = len(scores)
    return (scores[int(0.025 * (count - 1))], scores[int(0.5 * (count - 1))],
            scores[int(0.975 * (count - 1))])


def _check():
    failed = 0
    lines = []

    def say(text):
        lines.append(text)

    vectors = unit_vectors()
    cells = neighborhoods(vectors, 8)

    # A SOLID FIELD IS PURE LOCAL ORDER, a balanced checkerboard-like field is not. All ones gives the
    # maximum local order, WIDTH, since every neighbourhood is a solid run. A field drawn at weight 128
    # sits far below it. If they do not separate, the statistic is not reading local order.
    solid = local_order([1] * WIDTH, cells)
    generator = random.Random(5)
    balanced = [0] * WIDTH
    for index in generator.sample(range(WIDTH), 128):
        balanced[index] = 1
    mixed = local_order(balanced, cells)
    say("  local order of a solid field %.1f, of a balanced field %.1f: %s"
        % (solid, mixed, "solid is more ordered" if solid > 2 * mixed else "WRONG WAY"))
    if not (solid > 2 * mixed):
        say("    FAIL the statistic does not separate a solid field from a balanced one")
        failed += 1
    if abs(solid - WIDTH) > 1e-6:
        say("    FAIL an all-ones field is not maximum local order")
        failed += 1

    # THE WEIGHT-MATCHED NULL CONTAINS A RANDOM FIELD OF THAT WEIGHT. A field drawn at weight 128 sits
    # inside the band drawn at weight 128, by construction, so the null is calibrated to the nuisance.
    band = weight_matched_band(cells, 128, 300, 11)
    live = local_order(balanced, cells)
    say("  a weight-128 field: local order %.2f, weight-128 band %.2f to %.2f, in band %s"
        % (live, band[0], band[2], band[0] <= live <= band[2]))
    if not (band[0] <= live <= band[2]):
        say("    FAIL a random field fell outside its own weight-matched band")
        failed += 1

    # A LOCALLY CLUMPED FIELD OF THE SAME WEIGHT CLEARS THE BAND. Put all the ones in one polar cap and
    # the weight is unchanged but the local order is far above the weight-matched floor: a real local
    # disturbance the global weight cannot explain.
    clumped = [0] * WIDTH
    order = sorted(range(WIDTH), key=lambda index: vectors[index][2])
    for index in order[:128]:
        clumped[index] = 1
    clumped_order = local_order(clumped, cells)
    say("  a weight-128 field with the ones clumped in a cap: local order %.2f, over the band %s"
        % (clumped_order, clumped_order > band[2]))
    if not (clumped_order > band[2]):
        say("    FAIL a clumped field did not clear its weight-matched band, so local order is blind")
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

    size = 8
    sample = 2000
    if "--neighbors" in argv:
        size = int(argv[argv.index("--neighbors") + 1])
    if "--sample" in argv:
        sample = int(argv[argv.index("--sample") + 1])

    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        sys.stderr.write("no chain corpus found under tools/chain\n")
        return 2

    vectors = unit_vectors()
    cells = neighborhoods(vectors, size)

    if "--interior" in argv:
        # THE OPEN BOUNDARY. The digest is flat; the interior before round 7 is the one window the
        # support measurement leaves, where the nonce has entered but not fully mixed. Read the local
        # order of the interior state at each early round, against a null drawn at that state's own bit
        # weight. Structure over the null before round 7 is the partial mixing; whether it is gone by
        # round 7 is where the readable window closes.
        import nonce_support as support_module
        block = blocks[len(blocks) // 2]
        first_words, _ = build_bend_view.header_words(build_bend_view.header_bytes(block, 0))
        midstate = build_sha_sphere_view.compress(first_words, ROUNDS)
        count = 400
        stream = build_sha_sphere_view.draw(1)
        nonces = [next(stream) & MASK for _ in range(count)]
        print("  header height %d, %d nonces, interior of the first hash's second block, neighbourhood %d"
              % (block["height"], count, size))
        print("  local order against a null at each state's own weight; over the band is local structure")
        print("  %6s %14s %16s %12s" % ("round", "mean local order", "over/in/under", "mean excess"))
        for round_index in range(3, 12):
            over = inside = under = 0
            excess = 0.0
            live_mean = 0.0
            for nonce in nonces:
                bits = interior_bits(block, nonce, midstate, round_index)
                weight = sum(bits)
                live = local_order(bits, cells)
                live_mean += live
                band = weight_matched_band(cells, weight, 60, 7000 + round_index * 31 + weight)
                excess += live - band[1]
                if live > band[2]:
                    over += 1
                elif live < band[0]:
                    under += 1
                else:
                    inside += 1
            print("  %6d %14.3f %16s %12.4f"
                  % (round_index + 1, live_mean / count, "%d/%d/%d" % (over, inside, under),
                     excess / count))
        print("")
        print("  over the band before round 7 is the partial-mixing structure; at the null from round 7")
        print("  on is the readable window closed, which the support measurement placed at round 7.")
        return 0

    step = max(1, len(blocks) // sample)
    chosen = blocks[::step]

    print("  %d of %d real headers, neighbourhood size %d, winning-nonce DIGEST field"
          % (len(chosen), len(blocks), size))
    print("  local order is the total departure from local balance; the null is drawn at each")
    print("  field's own bit weight, a reading over the band is local structure the weight cannot make")
    print("")

    over = 0
    inside = 0
    under = 0
    excess = 0.0
    for block in chosen:
        first_words, _ = build_bend_view.header_words(build_bend_view.header_bytes(block, 0))
        midstate = build_sha_sphere_view.compress(first_words, ROUNDS)
        bits = digest_bits(block, int(block["nonce"]) & MASK, midstate)
        weight = sum(bits)
        live = local_order(bits, cells)
        band = weight_matched_band(cells, weight, 120, 1000 + block["height"])
        excess += live - band[1]
        if live > band[2]:
            over += 1
        elif live < band[0]:
            under += 1
        else:
            inside += 1

    total = len(chosen)
    print("  winning-nonce digests over the weight-matched band: %d, in band: %d, under: %d, of %d"
          % (over, inside, under, total))
    print("  chance is 2.5%% over and 2.5%% under, about %.1f each" % (0.025 * total))
    print("  mean local order above the weight-matched median: %.4f (zero is no local structure)"
          % (excess / total))
    print("")
    print("  a digest carrying local structure its weight cannot make lands over the band well beyond")
    print("  chance. At chance, the winning condition is locally as flat as a random field of its weight.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
