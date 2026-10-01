#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Machine B in the boundary field, steered in exact NTT limbs: no float, no format floor.

    python tools/view/o2_ntt_boundary.py --check     the controls, each able to fail
    python tools/view/o2_ntt_boundary.py             the meeting sweep over a real header

WHY EXACT AND NOT A FLOAT ANGLE

An angle between two fields taken in float64 carries a floor near 4e-16 that belongs to the FORMAT
and not to the boundary. Steering on it cannot discriminate past that floor whatever the data holds.
The steering here is the exact cross-correlation of the two bit fields, taken through the proven NTT
ring twiddle_proof.py establishes and four_step.py folds. The bit values are 0 and 1 and the length
is 256, so every correlation entry is at most 256, well under the modulus, and the residue IS the
true integer. No value is ever rounded, so the discrimination is bounded by the data and not by a
float floor. That is the difference between a steer that bottoms out and one that does not.

THE TWO MACHINES

Machine A, what a nonce IS: forward the double hash to round r of the second block, read the 256 bit
state, and that is the field F_r.

Machine B, what a winner CAN BE: the target admits only digests whose top L bits are zero, and that
zero pattern is a field T computed from the target alone.

THE ANSWER TO THE DIFFERENCE is the exact cross-correlation of F_r with T. The round where the
winner's correlation pulls away from the losers around it is the meeting round, read from the data.
Earlier than the round-61 anchor and a boundary-field question prunes what the anchor cannot; at 61
or later it gives nothing new, and the exact number says which, with no float floor to hide behind.

WHAT IS HELD

Every number here is about the nonce and sits under the fail-closed partition as HELD.
"""

import os
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
import o2_nonce  # noqa: E402

MASK = 0xFFFFFFFF
ROUNDS = 64
WIDTH = 256  # Output bits, and the transform length. A power of two, which the fold wants.


def state_bits(words):
    """The 256 bits of a state as the number the target is compared against, most significant first.

    Bitcoin reads the double hash little-endian, a winner's leading zeros sit at the top of THAT
    number, not at the top of the big-endian SHA words. Reading the words big-endian and then taking
    the whole 32 bytes little-endian puts bit 0 at the leading-zero end, so the target pattern below
    lines up with where a winner is actually zero. An intermediate round is read the same way, which
    is a consistent field order and not a claim that the round-r state is a hash.
    """
    raw = b"".join(struct.pack(">I", word & MASK) for word in words)
    value = int.from_bytes(raw, "little")
    return [(value >> (255 - bit)) & 1 for bit in range(256)]


def target_bits(leading):
    """Machine B's shape: a one at each of the top `leading` bit positions a winner drives to zero."""
    pattern = [0] * WIDTH
    for bit in range(min(leading, WIDTH)):
        pattern[bit] = 1
    return pattern


def cyclic_convolve(left, right):
    """The exact CYCLIC convolution of two length-WIDTH sequences, folded in the proven ring.

    four_step.convolve pads to a linear convolution of length len(left)+len(right); this instead
    folds both inputs at WIDTH and takes the pointwise product back, which is the cyclic convolution
    the correlation below needs. The transform is the same proven fold either way.
    """
    left_hat = four_step.fold(left, four_step.PRIME, four_step.GENERATOR, WIDTH)
    right_hat = four_step.fold(right, four_step.PRIME, four_step.GENERATOR, WIDTH)
    product = [left_hat[i] * right_hat[i] % four_step.PRIME for i in range(WIDTH)]
    return four_step.fold(product, four_step.PRIME, four_step.GENERATOR, WIDTH, inverse=True)


def exact_correlation(field, pattern):
    """The exact cyclic cross-correlation of two bit vectors, through the proven NTT ring.

    corr[s] = sum over n of field[n] * pattern[(n + s) mod WIDTH], every entry a true integer.
    Convolving the field with the reversed pattern gives corr at the negated index, so the placement
    below reads it back in order. The values are 0 and 1 and the length is 256, so no entry can reach
    the modulus and the residue is the integer with nothing rounded.
    """
    reversed_pattern = [pattern[(WIDTH - n) % WIDTH] for n in range(WIDTH)]
    raw = cyclic_convolve(field, reversed_pattern)
    return [raw[(WIDTH - shift) % WIDTH] for shift in range(WIDTH)]


def direct_correlation(field, pattern):
    """The same correlation by its definition, O(N^2), slow and beyond doubt. The reference."""
    out = []
    for shift in range(WIDTH):
        total = 0
        for n in range(WIDTH):
            total += field[n] * pattern[(n + shift) % WIDTH]
        out.append(total)
    return out


def second_message_words(first_digest):
    """The sixteen words of the second SHA block: the first hash's output, padded for 32 bytes."""
    tail = bytearray()
    for word in first_digest:
        tail.extend(struct.pack(">I", word & MASK))
    tail.append(0x80)
    while len(tail) < 56:
        tail.append(0x00)
    tail.extend((256).to_bytes(8, "big"))
    return [int.from_bytes(bytes(tail[at:at + 4]), "big") for at in range(0, 64, 4)]


def second_rounds(block, nonce, midstate):
    """Every round of the second SHA block for one nonce, each the running state plus the start."""
    header = build_bend_view.header_bytes(block, nonce)
    _, second_block = build_bend_view.header_words(header)
    first_digest = build_bend_view.round_outputs(second_block, midstate)[ROUNDS - 1]
    message = second_message_words(first_digest)
    return build_bend_view.round_outputs(message, build_sha_sphere_view.H0)


def zero_shift(field, pattern):
    """The exact agreement at zero shift: positions where the field bit and the pattern bit are both one."""
    return exact_correlation(field, pattern)[0]


def signed_state(words):
    """The 256 bits as plus or minus one, a max-entropy field's self-similarity averages to zero."""
    return [(2 * bit) - 1 for bit in state_bits(words)]


def recover_signed(residue):
    """The small signed integer a residue stands for, since every autocorrelation entry is within 256."""
    return residue - four_step.PRIME if residue > (four_step.PRIME // 2) else residue


def self_delta(field):
    """The exact energy in a field's delta from itself away from the zero shift: its departure from flat.

    THE SECOND INSTRUMENTATION. The first asks how a field agrees with the target. This asks how a
    field agrees with ITSELF at every nonzero shift, which is the cyclic autocorrelation. A field of
    maximum entropy reflects onto itself only at shift zero and averages to nothing elsewhere, so the
    off-peak energy is small. A field carrying structure, composite rather than max entropy, repeats
    onto itself at some shift and the off-peak energy stands up. The number is the sum of the squared
    autocorrelation over every shift but zero, exact through the proven ring, a departure is
    structure and not a float floor.
    """
    auto = exact_correlation(field, field)
    return sum(recover_signed(auto[shift]) ** 2 for shift in range(1, WIDTH))


def sweep_self(block, bits_window, rounds):
    """The winner's self-delta at each round against the window's losers: does its field carry structure."""
    recorded = int(block["nonce"]) & MASK
    window = 1 << bits_window
    base = recorded & ~(window - 1)
    winning_position = recorded & (window - 1)

    first_words, _ = build_bend_view.header_words(build_bend_view.header_bytes(block, base))
    midstate = build_sha_sphere_view.compress(first_words, ROUNDS)

    winner = {}
    losers = {index: [] for index in rounds}
    for position in range(window):
        states = second_rounds(block, base | position, midstate)
        for index in rounds:
            energy = self_delta(signed_state(states[index]))
            if position == winning_position:
                winner[index] = energy
            else:
                losers[index].append(energy)

    report = []
    for index in rounds:
        ordered = sorted(losers[index])
        won = winner.get(index)
        at_or_below = sum(1 for other in ordered if other <= won)
        report.append({
            "round": index + 1,
            "winner": won,
            "percentile": 100.0 * at_or_below / len(ordered) if ordered else None,
            "loser_min": ordered[0] if ordered else None,
            "loser_median": ordered[len(ordered) // 2] if ordered else None,
            "loser_max": ordered[-1] if ordered else None,
        })
    return report


def sweep(block, bits_window, rounds):
    """The winner's exact agreement with the target shape at each round, against the window's losers."""
    leading = 256 - o2_nonce.target_from_bits(block["bits"]).bit_length()
    pattern = target_bits(leading)

    recorded = int(block["nonce"]) & MASK
    window = 1 << bits_window
    base = recorded & ~(window - 1)
    winning_position = recorded & (window - 1)

    first_words, _ = build_bend_view.header_words(build_bend_view.header_bytes(block, base))
    midstate = build_sha_sphere_view.compress(first_words, ROUNDS)

    winner = {}
    losers = {index: [] for index in rounds}
    for position in range(window):
        states = second_rounds(block, base | position, midstate)
        for index in rounds:
            score = zero_shift(state_bits(states[index]), pattern)
            if position == winning_position:
                winner[index] = score
            else:
                losers[index].append(score)

    report = []
    for index in rounds:
        ordered = sorted(losers[index])
        won = winner.get(index)
        at_or_below = sum(1 for other in ordered if other <= won)
        report.append({
            "round": index + 1,
            "winner": won,
            "percentile": 100.0 * at_or_below / len(ordered) if ordered else None,
            "loser_min": ordered[0] if ordered else None,
            "loser_median": ordered[len(ordered) // 2] if ordered else None,
        })
    return report, leading


def _check():
    failed = 0
    lines = []

    def say(text):
        lines.append(text)

    # THE EXACT TRANSFORM IS THE EXACT CONVOLUTION. The NTT correlation must equal the direct one to
    # the integer, or the steering is reading a different map than it thinks.
    generator = 1234567
    field = [(generator * (n + 1)) % 2 for n in range(WIDTH)]
    pattern = target_bits(72)
    through_ntt = exact_correlation(field, pattern)
    direct = direct_correlation(field, pattern)
    say("  NTT correlation against a direct one, %d entries: %s"
        % (WIDTH, "identical" if through_ntt == direct else "DIFFER"))
    if through_ntt != direct:
        first = next(k for k in range(WIDTH) if through_ntt[k] != direct[k])
        say("    FAIL entry %d: ntt %d, direct %d" % (first, through_ntt[first], direct[first]))
        failed += 1

    # NO ENTRY REACHES THE MODULUS, so every residue is the true integer and nothing wrapped. The
    # largest possible entry is WIDTH, and the modulus is far above it.
    say("  largest correlation entry %d, modulus %d, so no entry wrapped: %s"
        % (max(direct), four_step.PRIME, "true" if max(direct) < four_step.PRIME else "FALSE"))
    if max(direct) >= four_step.PRIME:
        failed += 1

    # ZERO SHIFT IS THE AGREEMENT COUNT. Against a pattern of all ones it must equal the field's own
    # bit count, which is an independent route to the same integer.
    ones = [1] * WIDTH
    agreement = zero_shift(field, ones)
    popcount = sum(field)
    say("  zero-shift agreement with an all-ones pattern %d, field bit count %d: %s"
        % (agreement, popcount, "agree" if agreement == popcount else "DISAGREE"))
    if agreement != popcount:
        failed += 1

    # THE SELF-DELTA IS THE EXACT AUTOCORRELATION ENERGY. Through the ring with sign recovery it must
    # equal a direct autocorrelation to the integer, or the second instrumentation reads a different
    # map than it claims.
    signed = [1 if ((generator * (n + 3)) % 3) else -1 for n in range(WIDTH)]
    through_ring = self_delta(signed)
    direct_auto = 0
    for shift in range(1, WIDTH):
        total = sum(signed[n] * signed[(n + shift) % WIDTH] for n in range(WIDTH))
        direct_auto += total * total
    say("  self-delta through the ring %d, direct autocorrelation %d: %s"
        % (through_ring, direct_auto, "agree" if through_ring == direct_auto else "DISAGREE"))
    if through_ring != direct_auto:
        failed += 1

    # A CONSTANT FIELD IS PURE STRUCTURE, a RANDOM field is max entropy and near flat off the peak.
    # The constant must carry far more self-delta, or the statistic is not reading structure. An
    # alternating field is NOT the flat case: it is maximally periodic and maxes out like the
    # constant, which is the statistic being right, not wrong.
    constant = [1] * WIDTH
    state = 0xC0FFEE
    noise = []
    for _ in range(WIDTH):
        state = (state * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
        noise.append(1 if ((state >> 40) & 1) else -1)
    solid = self_delta(constant)
    flat = self_delta(noise)
    say("  self-delta of a constant field %d, of a random field %d: %s"
        % (solid, flat, "structure over noise" if solid > 10 * flat else "WRONG WAY"))
    if not (solid > 10 * flat):
        failed += 1

    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        say("  no chain corpus found, so the hash controls cannot run")
        say("")
        say("%d check(s) failed" % failed)
        sys.stdout.write("\n".join(lines) + "\n")
        return failed
    block = blocks[len(blocks) // 2]

    # The winner is below target, at the final round its top-L bits are zero and its agreement with
    # the "these bits are one" pattern is the LOWEST it can be: it must sit at or near the floor of the
    # losers around it.
    report, leading = sweep(block, 6, [ROUNDS - 1])
    last = report[0]
    say("  final round, %d leading zeros: winner agreement %d, losers min %d median %d, percentile %.1f"
        % (leading, last["winner"], last["loser_min"], last["loser_median"], last["percentile"]))
    if last["winner"] != 0:
        say("    FAIL the winner's top-L bits are not all zero at the final round, though it is a winner")
        failed += 1
    if last["percentile"] is None or last["percentile"] > 50.0:
        say("    FAIL the winner is not on the low-agreement side at the final round")
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
    if "--bits" in argv:
        at = argv.index("--bits")
        if at + 1 >= len(argv):
            sys.stderr.write("--bits needs a value\n")
            return 2
        window = int(argv[at + 1])

    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        sys.stderr.write("no chain corpus found under tools/chain\n")
        return 2
    block = blocks[len(blocks) // 2]
    rounds = [15, 31, 39, 47, 55, 59, 60, 61, 62, 63]

    if "--scan" in argv:
        # REPRODUCIBILITY. One header's winner percentile could be a draw. This runs the second
        # instrumentation over several evenly spaced headers and reads whether the winner lands in a
        # tail (structure) at the same rounds, or wanders, which is max entropy.
        focus = [47, 55, 59, 60, 61, 63]
        count = 8
        picks = [blocks[(index * len(blocks)) // count] for index in range(count)]
        print("  the SECOND instrumentation over %d headers, 2^%d window, winner percentile per round"
              % (count, window))
        print("  a real structure lands the winner in the same tail across headers; noise wanders")
        print("  %8s %s" % ("height", " ".join("r%02d" % (r + 1) for r in focus)))
        tails = {r: 0 for r in focus}
        for chosen in picks:
            report = sweep_self(chosen, window, focus)
            cells = []
            for row in report:
                pct = row["percentile"]
                cells.append("  -  " if pct is None else "%5.1f" % pct)
                if pct is not None and (pct >= 90.0 or pct <= 10.0):
                    tails[row["round"] - 1] += 1
            print("  %8d %s" % (chosen["height"], " ".join(cells)))
        print("")
        print("  headers with the winner in a tail (<=10 or >=90) at each round, chance is about 1.6 of %d:"
              % count)
        print("  %s" % " ".join("r%02d:%d" % (r + 1, tails[r]) for r in focus))
        return 0

    if "--self" in argv:
        leading = 256 - o2_nonce.target_from_bits(block["bits"]).bit_length()
        report = sweep_self(block, window, rounds)
        print("  header height %d, %d leading zeros, 2^%d window: the SECOND instrumentation"
              % (block["height"], leading, window))
        print("  self-delta is the exact off-peak autocorrelation energy: a field's structure, its")
        print("  departure from max entropy. A winner percentile far from the middle is the signal.")
        print("  %6s %16s %14s %16s %12s" % ("round", "winner", "losers min", "losers median",
                                             "winner pct"))
        for row in report:
            show = lambda value: ("-" if value is None else str(value))
            print("  %6d %16s %14s %16s %12s"
                  % (row["round"], show(row["winner"]), show(row["loser_min"]),
                     show(row["loser_median"]),
                     "-" if row["percentile"] is None else "%.1f" % row["percentile"]))
        print("")
        print("  a winner sitting near 0 or 100 and STAYING there across rounds is structure the")
        print("  losers do not share. Bouncing across the middle is max entropy: no difference to get.")
        return 0

    report, leading = sweep(block, window, rounds)
    print("  header height %d, %d leading zero bits in its target, 2^%d window"
          % (block["height"], leading, window))
    print("  round is of the SECOND SHA block; the miner's anchor is round 61. Agreement is exact,")
    print("  through the proven NTT ring, a low winner percentile is signal and not a float floor.")
    print("  %6s %10s %12s %14s %12s" % ("round", "winner", "losers min", "losers median",
                                         "winner pct"))
    for row in report:
        show = lambda value: ("-" if value is None else str(value))
        print("  %6d %10s %12s %14s %12s"
              % (row["round"], show(row["winner"]), show(row["loser_min"]),
                 show(row["loser_median"]),
                 "-" if row["percentile"] is None else "%.1f" % row["percentile"]))
    print("")
    print("  the meeting round is the first where the winner percentile drops to the floor and stays.")
    print("  below 61 it beats the anchor; at 61 or later the boundary field adds nothing the anchor")
    print("  does not already have. The number is exact, so read it straight.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
