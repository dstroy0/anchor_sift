#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Which interior positions the nonce can move, and where its reach closes: elision read forwards.

    python examples/00_blob_viz_tools/nonce_support.py --check     the controls, each able to fail
    python examples/00_blob_viz_tools/nonce_support.py             the support curve over a real header

WHY THIS AND NOT A FREQUENCY

theory/workbooks/orior/aiming-the-engine.md puts support before frequency. A frequency needs a null, a bar and a
correction, and most come back empty. A support is a hard fact: a position either moved under some
excitation of the nonce or it never did, and one that never did is ELIDED, independent of the nonce
at that depth, ruling out every trajectory that would need it to carry nonce information. No null, no
bar, no p-value. This reads the interior the way the research says to, instead of reading the digest
the way the refuted entries did.

WHAT IS MEASURED

Excite the nonce across many values. At every round of the compression read the whole interior state
and mark a bit position as SUPPORTED if it takes more than one value across the excitations, ELIDED
if it never moves. The support is the set of positions the nonce can still reach at that depth; its
size grows as the avalanche spreads and closes when every position is reachable. Where it closes is
the round past which nothing is elided and no hard constraint can be read, and the research measured
that at round 30 of 64 on the compression function. Past it, a reading returns a floor that looks
like a result, the trap every refuted nonce entry fell into by reading round 61 or 64.

THE NONCE'S PLACE

The nonce is word 3 of the FIRST hash's second block, so that block's rounds 1 to 3 read words no
nonce touches and must be fully elided, the positive control. The SECOND hash takes the
first hash's finished output as its message, and that output already depends on the nonce. Every
second-hash round is supported from the start. The elision window lives in the first hash's second
block, and that is where this looks.

WHAT IS HELD

Every number here is about the nonce and sits under the fail-closed partition as HELD.
"""

import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_bend_view  # noqa: E402
import build_sha_sphere_view  # noqa: E402

MASK = 0xFFFFFFFF
ROUNDS = 64


def excitations(base, count, seed):
    """Nonce values to excite with: the base, every single-bit flip of it, then random draws.

    The single-bit flips are the sharpest excitation, one input bit moved at a time. The random draws
    fill the rest a position called elided has survived many unrelated inputs, not just the 32
    adjacent ones. A position constant across all of these is elided under the tested excitation, which
    is a lower bound on its true support and never an overstatement.
    """
    values = [base & MASK]
    for bit in range(32):
        values.append((base ^ (1 << bit)) & MASK)
    stream = build_sha_sphere_view.draw(seed)
    while len(values) < count:
        values.append(next(stream) & MASK)
    return values


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


def interior_runs(block, nonces, midstate):
    """For each nonce, the per-round state of the first hash's second block and of the second hash.

    Each is ROUNDS rows of eight words, the running state plus the start. Read directly and not
    summarized, because the support needs the value at every position, not a statistic of it.
    """
    runs = []
    for nonce in nonces:
        _, second_block = build_bend_view.header_words(build_bend_view.header_bytes(block, nonce))
        first = build_bend_view.round_outputs(second_block, midstate)
        message = second_message_words(first[ROUNDS - 1])
        second = build_bend_view.round_outputs(message, build_sha_sphere_view.H0)
        runs.append((first, second))
    return runs


def support_sizes(runs, which):
    """Supported bit count per round: positions that differ from the base run under some excitation.

    `which` is 0 for the first hash's second block, 1 for the second hash. The base run is the first
    excitation; every other run is XORed against it and the differences are OR-accumulated per round,
    a bit is supported if it ever moved. The count is the population of that accumulated mask.
    """
    base = runs[0][which]
    diff = [[0] * 8 for _ in range(ROUNDS)]
    for run in runs[1:]:
        states = run[which]
        for index in range(ROUNDS):
            for word in range(8):
                diff[index][word] |= base[index][word] ^ states[index][word]
    sizes = []
    for index in range(ROUNDS):
        sizes.append(sum(bin(diff[index][word]).count("1") for word in range(8)))
    return sizes


def entry_round(first_sizes):
    """The first round of the first hash's second block whose support is non-zero: where the nonce enters."""
    for index, size in enumerate(first_sizes):
        if size > 0:
            return index
    return None


def closes_at(sizes, full):
    """The first round whose support reaches `full` and stays there: where elision completes."""
    for index in range(len(sizes)):
        if sizes[index] >= full and all(later >= full for later in sizes[index:]):
            return index
    return None


def measure(block, count, seed):
    """The support curves for one header, and the counts a reader needs off them."""
    first_words, _ = build_bend_view.header_words(build_bend_view.header_bytes(block, 0))
    midstate = build_sha_sphere_view.compress(first_words, ROUNDS)
    base = int(block["nonce"]) & MASK
    runs = interior_runs(block, excitations(base, count, seed), midstate)
    first_sizes = support_sizes(runs, 0)
    second_sizes = support_sizes(runs, 1)
    return {
        "first": first_sizes,
        "second": second_sizes,
        "entry": entry_round(first_sizes),
        "first_closes": closes_at(first_sizes, 256),
        "excitations": len(runs),
        "final_digest_support": second_sizes[ROUNDS - 1],
    }


def _check():
    failed = 0
    lines = []

    def say(text):
        lines.append(text)

    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        say("  no chain corpus found. The support controls cannot run")
        say("")
        say("%d check(s) failed" % failed)
        sys.stdout.write("\n".join(lines) + "\n")
        return failed
    block = blocks[len(blocks) // 2]
    result = measure(block, 256, 1)

    # POSITIVE CONTROL. The nonce is word 3 of the first hash's second block, added at round 4.
    # Rounds 1 to 3 read words no nonce touches and MUST be fully elided, support zero. If they are
    # not, the instrument is reading nonce movement where none can exist, and every later reading is
    # void. Round 4 must then be non-zero: the excitation reached the interior at all.
    before = result["first"][:3]
    at_entry = result["first"][3]
    say("  first hash second block, support at rounds 1 to 3: %s; at round 4: %d"
        % (before, at_entry))
    if any(size != 0 for size in before):
        say("    FAIL a round before the nonce enters shows support. The instrument moves nothing")
        failed += 1
    if at_entry == 0:
        say("    FAIL round 4 shows no support. The excitation never reached the interior")
        failed += 1

    # THE SUPPORT ONLY GROWS. A bit the nonce has reached does not become unreachable a round later;
    # the avalanche spreads and never retreats. A drop would be the accumulator or the stepping wrong.
    say("  first hash support is monotone up to closure: %s"
        % all(result["first"][index] <= result["first"][index + 1]
              for index in range(result["first_closes"] or (ROUNDS - 1))))
    if not all(result["first"][index] <= result["first"][index + 1]
               for index in range(result["first_closes"] or (ROUNDS - 1))):
        say("    FAIL support fell round to round before it closed, which it cannot do")
        failed += 1

    # THE SECOND HASH IS SUPPORTED FROM THE START. Its message is the first hash's finished output,
    # which already depends on the nonce. Its round 1 support is not zero. If it were, the two
    # hashes are not being chained.
    say("  second hash support at round 1: %d (must be non-zero, its input already carries the nonce)"
        % result["second"][0])
    if result["second"][0] == 0:
        say("    FAIL the second hash shows no nonce support at round 1. The chain is broken")
        failed += 1

    # THE HARD STATEMENT FOR MINING. The final digest's support is what the winning condition reads.
    # A digest bit outside the support is elided, fixed by the header alone. Full support there is the
    # honest expectation and is itself a hard statement: the winning condition is fully nonce-bound.
    say("  final digest support: %d of 256 bits move under the nonce" % result["final_digest_support"])

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

    count = 512
    if "--excitations" in argv:
        at = argv.index("--excitations")
        count = int(argv[at + 1])

    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        sys.stderr.write("no chain corpus found under utils/maint/chain\n")
        return 2
    block = blocks[len(blocks) // 2]
    result = measure(block, count, 1)

    print("  header height %d, %d nonce excitations, support is bits the nonce can still move"
          % (block["height"], result["excitations"]))
    print("  the nonce enters the first hash's second block at round %d; its support closes at round %s"
          % ((result["entry"] or 0) + 1,
             "never" if result["first_closes"] is None else str(result["first_closes"] + 1)))
    print("")
    print("  %6s %18s %14s" % ("round", "first hash support", "elided"))
    for index in range(ROUNDS):
        size = result["first"][index]
        print("  %6d %18d %14d" % (index + 1, size, 256 - size))
    print("")
    print("  the second hash is supported throughout; its final digest moves %d of 256 bits under the"
          % result["final_digest_support"])
    print("  nonce. Elided positions in the first hash are a hard fact, fixed by the header, but they")
    print("  close before the digit that decides a win, the honest reason mining is hard.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
