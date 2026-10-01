#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Machine B in the boundary-field representation: where the forward state meets the target's shape.

    python examples/00_blob_viz_tools/o2_boundary.py --check      the controls, each able to fail
    python examples/00_blob_viz_tools/o2_boundary.py              the meeting sweep over a real header

THE TWO MACHINES, IN ONE FIELD

Machine A, what a nonce IS: run the double hash forward to round r of the second block and read the
256 bit state there. Placed on the sphere at the golden-spiral directions the whole view uses, that
state is a boundary field F_r.

Machine B, what a winner CAN BE: the target admits only digests whose top L bits are zero. That
constraint is a shape too, the field T of the pattern "top L bits zero, the rest free". T is computed
from the target alone and never looks at any nonce.

THE ANSWER TO THE DIFFERENCE is the angle between F_r and T. A true winner's FINAL field sits at
zero angle to T by construction, because its top L bits are the zero bits T is made of. The question
is how far back from the last round that closeness survives: the round where the winner's angle to T
drops inside the non-winners around it is the meeting round, and it is read from the data, not set.

WHY THIS IS THE HONEST TEST

If the meeting round is earlier than the round-61 anchor, a boundary-field question run to that round
prunes nonces the anchor cannot, and the recursion earns a saving the count in o2_nonce.py would then
show. If the winner only pulls away from the field at round 61 or later, the boundary field gives no
meeting the anchor does not already have, and this reports that with the winner's angle beside the
non-winners' at every round. The avalanche makes the second prediction the likely one; the point is
to measure it in this representation and not assume it.

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
import o2_nonce  # noqa: E402

MASK = 0xFFFFFFFF
ROUNDS = 64


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
    first_words, second_block = build_bend_view.header_words(header)
    first_digest = build_bend_view.round_outputs(second_block, midstate)[ROUNDS - 1]
    message = second_message_words(first_digest)
    return build_bend_view.round_outputs(message, build_sha_sphere_view.H0)


def bit_strengths(words):
    """The 256 output bits as signed departures, one per bit, most significant first."""
    strengths = []
    for word in words:
        for shift in range(31, -1, -1):
            strengths.append(((word >> shift) & 1) - 0.5)
    return strengths


def target_strengths(leading):
    """Machine B's shape: the top `leading` bits pinned to zero, the rest neutral."""
    strengths = [0.0] * 256
    for bit in range(min(leading, 256)):
        strengths[bit] = -0.5
    return strengths


def angle_to_target(basis, words, target_field):
    """The angle between a state's boundary field and the target field, above degree zero."""
    field = build_bend_view.field_of(basis, bit_strengths(words))
    return build_bend_view.angle_between(field[1:], target_field[1:])


def percentile_of(value, population):
    """The share of the population at or below `value`, in percent."""
    if not population:
        return None
    below = sum(1 for other in population if other <= value)
    return 100.0 * below / len(population)


def sweep(block, bits_window, top, rounds):
    """The winner's angle to the target field at each round, against the window's other nonces.

    Returns, per round, the winner's angle, the winner's percentile among the losers, and the losers'
    minimum and median angle. The meeting round is where the winner's percentile drops to the bottom.
    """
    directions = build_sha_sphere_view.place("spiral")
    basis = build_bend_view.source_basis(top, directions)
    leading = 256 - o2_nonce.target_from_bits(block["bits"]).bit_length()
    target_field = build_bend_view.field_of(basis, target_strengths(leading))

    recorded = int(block["nonce"]) & MASK
    window = 1 << bits_window
    base = recorded & ~(window - 1)
    winning_position = recorded & (window - 1)

    first_words, _ = build_bend_view.header_words(build_bend_view.header_bytes(block, base))
    midstate = build_sha_sphere_view.compress(first_words, ROUNDS)

    winner_angles = {}
    loser_angles = {round_index: [] for round_index in rounds}
    for position in range(window):
        nonce = base | position
        states = second_rounds(block, nonce, midstate)
        for round_index in rounds:
            angle = angle_to_target(basis, states[round_index], target_field)
            if angle is None:
                continue
            if position == winning_position:
                winner_angles[round_index] = angle
            else:
                loser_angles[round_index].append(angle)

    report = []
    for round_index in rounds:
        losers = loser_angles[round_index]
        winner = winner_angles.get(round_index)
        losers_sorted = sorted(losers)
        median = losers_sorted[len(losers_sorted) // 2] if losers_sorted else None
        report.append({
            "round": round_index + 1,
            "winner": winner,
            "percentile": percentile_of(winner, losers) if winner is not None else None,
            "loser_min": losers_sorted[0] if losers_sorted else None,
            "loser_median": median,
            "losers": len(losers),
        })
    return report, leading


def _check():
    failed = 0
    lines = []

    def say(text):
        lines.append(text)

    top = 8
    directions = build_sha_sphere_view.place("spiral")
    basis = build_bend_view.source_basis(top, directions)

    # A state equal to the target pattern sits at angle zero to the target field, and its bitwise
    # complement sits far from it. If these two do not straddle, the field is not reading the bits.
    leading = 32
    target_field = build_bend_view.field_of(basis, target_strengths(leading))
    zero_top = [0x00000000] * (leading // 32) + [0x89ABCDEF] * (8 - leading // 32)
    ones_top = [0xFFFFFFFF] * (leading // 32) + [0x89ABCDEF] * (8 - leading // 32)
    near = angle_to_target(basis, zero_top, target_field)
    far = angle_to_target(basis, ones_top, target_field)
    say("  a state with the target's zero top: angle %.3f; with a one top: angle %.3f" % (near, far))
    if not (near < far):
        say("    FAIL the target field does not tell a zero top from a one top")
        failed += 1

    # The second SHA block, stepped round by round, must end on the real double hash of the header.
    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        say("  no chain corpus found. The hash controls cannot run")
        say("")
        say("%d check(s) failed" % failed)
        sys.stdout.write("\n".join(lines) + "\n")
        return failed
    block = blocks[len(blocks) // 2]
    recorded = int(block["nonce"]) & MASK
    first_words, _ = build_bend_view.header_words(build_bend_view.header_bytes(block, recorded))
    midstate = build_sha_sphere_view.compress(first_words, ROUNDS)
    digest_words = second_rounds(block, recorded, midstate)[ROUNDS - 1]
    display = b"".join(struct.pack(">I", word & MASK) for word in digest_words)[::-1].hex()
    say("  stepped double hash of the recorded header: %s..." % display[:16])
    say("  the block's own id:                        %s..." % block["id"][:16])
    if display != block["id"]:
        say("    FAIL the stepped second block is not the header's double hash")
        failed += 1

    # The recorded nonce is a winner, at the last round its field sits at or below every loser's
    # angle to the target: its top bits are the zero bits the target field is made of.
    report, leading = sweep(block, 6, top, [ROUNDS - 1])
    last = report[0]
    say("  final round: winner angle %.3f, losers min %.3f median %.3f, winner percentile %.1f"
        % (last["winner"], last["loser_min"], last["loser_median"], last["percentile"]))
    if last["percentile"] is None or last["percentile"] > 50.0:
        say("    FAIL the winner is not on the low-angle side at the final round, though it is a winner")
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

    top = o2_nonce_option(argv, "--degrees", 8)
    window = o2_nonce_option(argv, "--bits", 8)
    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        sys.stderr.write("no chain corpus found under utils/maint/chain\n")
        return 2
    block = blocks[len(blocks) // 2]

    rounds = [15, 31, 39, 47, 55, 59, 60, 61, 62, 63]
    report, leading = sweep(block, window, top, rounds)
    print("  header height %d, %d leading zero bits in its target, 2^%d window, degrees to %d"
          % (block["height"], leading, window, top))
    print("  round is of the SECOND SHA block; the anchor the miner already uses is round 61")
    print("  %6s %12s %12s %14s %12s" % ("round", "winner", "losers min", "losers median",
                                         "winner pct"))
    for row in report:
        show = lambda value: ("-" if value is None else "%.3f" % value)
        print("  %6d %12s %12s %14s %12s"
              % (row["round"], show(row["winner"]), show(row["loser_min"]),
                 show(row["loser_median"]),
                 "-" if row["percentile"] is None else "%.1f" % row["percentile"]))
    print("")
    print("  the meeting round is the first where the winner's percentile drops to the floor: below")
    print("  round 61 it beats the anchor, at 61 or later it does not. Read it from the column.")
    return 0


def o2_nonce_option(argv, flag, fallback):
    if flag in argv:
        at = argv.index(flag)
        if at + 1 >= len(argv):
            sys.stderr.write("%s needs a value\n" % flag)
            raise SystemExit(2)
        return int(argv[at + 1])
    return fallback


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
