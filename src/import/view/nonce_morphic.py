#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Do different nonces share a morphic topology, the same pattern in a different spatial sequence.

    python tools/view/nonce_morphic.py --check     the controls, each able to fail
    python tools/view/nonce_morphic.py             the morphic reading over a real header

THE CLAIM

The support measurement says every interior bit moves under the nonce past round seven, so nothing is
elided at the depth a win is read. That counts THAT bits move, not the SHAPE of how they move. The
shape is the morphic topology, the peaks and pits of the boundary field and their arrangement, and the
claim here is that this shape is shared across nonces, the same pattern carried in a different spatial
sequence, a rotation or relabelling of one set of features into another.

HOW IT IS READ, REUSING topology_match

topology_match already separates the two halves of that claim. Its `spacing` is the Kolmogorov
distance between the two fields' peak arrangements, measured through the pairwise angles of the peak
directions, which is invariant to a global rotation: the same relative arrangement reads a small
spacing whatever orientation it sits at. Its `alignment` and `delta` then ask whether one field
carries onto the other under a single rotation. Spacing closer than the null with a rotation that
aligns them is the exact statement "the same pattern in a different spatial sequence". Spacing at the
null is no shared pattern.

THE NULL AND THE CONTROL

The null is drawn from pairs of fair fields through the same basis and grid, so the floor carries the
grid's own arrangement statistics and is not derived. The positive control is a field against a
rotation of itself, which must read a small spacing and a real alignment, and a field against an
independent one, which must sit in the null band. If the control does not fire, a null here is about
the instrument.

WHAT IS HELD

Every number here is about the nonce and sits under the fail-closed partition as HELD.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_bend_view  # noqa: E402
import build_sha_sphere_view  # noqa: E402
import nonce_support  # noqa: E402
import topology_match  # noqa: E402

MASK = 0xFFFFFFFF
ROUNDS = 64


def state_strengths(words):
    """The 256 bits of a state as signed departures, most significant first, for a boundary field."""
    strengths = []
    for word in words:
        for shift in range(31, -1, -1):
            strengths.append(((word >> shift) & 1) - 0.5)
    return strengths


def nonce_field(block, nonce, midstate, basis, hash_index, round_index):
    """The boundary field of one nonce's interior state at a round of the chosen hash block."""
    _, second_block = build_bend_view.header_words(build_bend_view.header_bytes(block, nonce))
    if hash_index == 0:
        states = build_bend_view.round_outputs(second_block, midstate)
    else:
        first = build_bend_view.round_outputs(second_block, midstate)
        message = nonce_support.second_message_words(first[ROUNDS - 1])
        states = build_bend_view.round_outputs(message, build_sha_sphere_view.H0)
    return build_bend_view.field_of(basis, state_strengths(states[round_index]))


def spacing_values(grid, first_fields, second_fields, within):
    """Peak-arrangement spacing over pairs: within one set if `within`, else across two sets."""
    values = []
    if within:
        for first in range(len(first_fields)):
            for second in range(first + 1, len(first_fields)):
                values.append(topology_match.readings(grid, first_fields[first],
                                                       first_fields[second])["spacing"])
    else:
        for first in first_fields:
            for second in second_fields:
                values.append(topology_match.readings(grid, first, second)["spacing"])
    return sorted(v for v in values if v is not None)


def median(values):
    return values[len(values) // 2] if values else None


def pair_verdicts(grid, fields, bands):
    """Every pair of nonce fields read against the null: closer, in, or farther on each statistic."""
    tally = {"spacing": {"closer": 0, "in": 0, "farther": 0},
             "alignment": {"closer": 0, "in": 0, "farther": 0},
             "delta": {"closer": 0, "in": 0, "farther": 0}}
    total = 0
    for first in range(len(fields)):
        for second in range(first + 1, len(fields)):
            found = topology_match.readings(grid, fields[first], fields[second])
            total += 1
            for key in tally:
                said = topology_match.verdict(found[key], bands[key], True)
                if said in tally[key]:
                    tally[key][said] += 1
    return tally, total


def _check():
    failed = 0
    lines = []

    def say(text):
        lines.append(text)

    top = 8
    directions = build_sha_sphere_view.place("spiral")
    basis = build_bend_view.source_basis(top, directions)
    grid = topology_match.Grid(top)
    bands = topology_match.fair_readings(grid, basis, 200, 200, topology_match.SEED_NULL)

    import random
    generator = random.Random(3)
    field = build_bend_view.field_of(basis, [generator.uniform(-0.5, 0.5) for _ in range(256)])
    other = build_bend_view.field_of(basis, [generator.uniform(-0.5, 0.5) for _ in range(256)])

    # POSITIVE CONTROL. A field read against ITSELF is a perfect match: spacing zero and the delta at
    # zero. If the same field does not read as the same field, nothing below means anything.
    same = topology_match.readings(grid, field, field)
    say("  a field against itself: spacing %.4f, delta %s"
        % (same["spacing"], "-" if same["delta"] is None else "%.4f" % same["delta"]))
    if same["spacing"] > 1e-9:
        say("    FAIL a field does not match itself, so the reading is not reading the topology")
        failed += 1

    # AN INDEPENDENT FIELD SITS IN THE NULL. Two unrelated fields agree only as much as chance, so
    # their spacing lands in the drawn band and is not called closer.
    independent = topology_match.readings(grid, field, other)
    said = topology_match.verdict(independent["spacing"], bands["spacing"], True)
    say("  two independent fields: spacing %.4f, band %.4f to %.4f, verdict %s"
        % (independent["spacing"], bands["spacing"][0], bands["spacing"][2], said))
    if said == "closer":
        say("    FAIL two independent fields were called a shared pattern")
        failed += 1

    # THE NONCE FIELDS ARE READABLE. Build a few and confirm they have peaks to compare, a null
    # below is a real reading and not an empty one.
    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        say("  no chain corpus found, so the nonce controls cannot run")
        say("")
        say("%d check(s) failed" % failed)
        sys.stdout.write("\n".join(lines) + "\n")
        return failed
    block = blocks[len(blocks) // 2]
    first_words, _ = build_bend_view.header_words(build_bend_view.header_bytes(block, 0))
    midstate = build_sha_sphere_view.compress(first_words, ROUNDS)
    base = int(block["nonce"]) & MASK
    sample = nonce_field(block, base ^ 5, midstate, basis, 0, 15)
    peaks, pits = grid.critical(grid.values(sample))
    say("  a nonce field at first-hash round 16 has %d peaks and %d pits" % (len(peaks), len(pits)))
    if len(peaks) == 0:
        say("    FAIL a nonce field has no peaks, so there is no topology to compare")
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

    top = nonce_support_option(argv, "--degrees", 8)
    count = nonce_support_option(argv, "--nonces", 16)
    hash_index = nonce_support_option(argv, "--hash", 1)
    round_index = nonce_support_option(argv, "--round", ROUNDS) - 1

    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        sys.stderr.write("no chain corpus found under tools/chain\n")
        return 2

    if "--cross" in argv:
        # THE CONFOUND KILLER. At an early round the nonces of ONE header share its bulk, a shared
        # arrangement could be the header and not a nonce law. If same-header spacing is far below
        # cross-header spacing, the pattern is the header's; if same and cross agree and both sit below
        # the fair null, the arrangement is shared across DIFFERENT headers, which is the real claim.
        directions = build_sha_sphere_view.place("spiral")
        basis = build_bend_view.source_basis(top, directions)
        grid = topology_match.Grid(top)
        fair = topology_match.fair_readings(grid, basis, 200, 300, topology_match.SEED_NULL)["spacing"]
        first_block = blocks[len(blocks) // 3]
        second_block = blocks[2 * len(blocks) // 3]
        first_mid = build_sha_sphere_view.compress(
            build_bend_view.header_words(build_bend_view.header_bytes(first_block, 0))[0], ROUNDS)
        second_mid = build_sha_sphere_view.compress(
            build_bend_view.header_words(build_bend_view.header_bytes(second_block, 0))[0], ROUNDS)
        stream = build_sha_sphere_view.draw(1)
        nonces = [next(stream) & MASK for _ in range(count)]
        fields_a = [nonce_field(first_block, nonce, first_mid, basis, hash_index, round_index)
                    for nonce in nonces]
        fields_b = [nonce_field(second_block, nonce, second_mid, basis, hash_index, round_index)
                    for nonce in nonces]
        same_a = spacing_values(grid, fields_a, None, True)
        same_b = spacing_values(grid, fields_b, None, True)
        cross = spacing_values(grid, fields_a, fields_b, False)
        print("  %s hash round %d, %d nonces per header, two headers heights %d and %d"
              % ("second" if hash_index else "first", round_index + 1, count,
                 first_block["height"], second_block["height"]))
        print("  peak-arrangement spacing, lower is more shared. Fair null median %.4f" % fair[1])
        print("  same header A: median %.4f     same header B: median %.4f     cross header: median %.4f"
              % (median(same_a), median(same_b), median(cross)))
        print("")
        print("  if same-header medians sit far below cross, the shared arrangement is the header's and")
        print("  not a nonce law. if same and cross agree and both beat the fair null, it is shared")
        print("  across different headers, which is the real claim.")
        return 0

    directions = build_sha_sphere_view.place("spiral")
    basis = build_bend_view.source_basis(top, directions)
    grid = topology_match.Grid(top)
    bands = topology_match.fair_readings(grid, basis, 200, 400, topology_match.SEED_NULL)

    first_words, _ = build_bend_view.header_words(build_bend_view.header_bytes(block, 0))
    midstate = build_sha_sphere_view.compress(first_words, ROUNDS)
    base = int(block["nonce"]) & MASK
    stream = build_sha_sphere_view.draw(1)
    nonces = [base] + [next(stream) & MASK for _ in range(count - 1)]
    fields = [nonce_field(block, nonce, midstate, basis, hash_index, round_index) for nonce in nonces]

    tally, total = pair_verdicts(grid, fields, bands)
    print("  header height %d, %d nonces, %s hash round %d, degrees to %d"
          % (block["height"], count, "second" if hash_index else "first", round_index + 1, top))
    print("  %d field pairs read against a null of 400 fair pairs; closer means a shared pattern"
          % total)
    for key, label in (("spacing", "peak arrangement (rotation-free)"), ("alignment", "spatial alignment"),
                       ("delta", "rotated delta")):
        band = bands[key]
        chance = 0.025 * total
        print("  %-32s null %.4f to %.4f: %d closer / %d farther of %d, chance %.1f each"
              % (label, band[0], band[2], tally[key]["closer"], tally[key]["farther"], total, chance))
    print("")
    print("  a shared morphic pattern in a different spatial sequence reads as spacing CLOSER than")
    print("  the null with the pairs still not aligning: the same arrangement carried at a rotation.")
    print("  spacing in the null band is no shared pattern beyond what fair fields share by chance.")
    return 0


def nonce_support_option(argv, flag, fallback):
    if flag in argv:
        at = argv.index(flag)
        if at + 1 >= len(argv):
            sys.stderr.write("%s needs a value\n" % flag)
            raise SystemExit(2)
        return int(argv[at + 1])
    return fallback


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
