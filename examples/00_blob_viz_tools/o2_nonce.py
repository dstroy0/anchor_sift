#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""The recursive spawn pointed at the nonce, counting hashes against a plain scan.

    python examples/00_blob_viz_tools/o2_nonce.py --check          the controls, each able to fail
    python examples/00_blob_viz_tools/o2_nonce.py                  the measurement table over a real header
    python examples/00_blob_viz_tools/o2_nonce.py --bits 20        search a 2^20 window instead of the default set

WHAT IS MEASURED, AND WHY A TIE IS THE HONEST ANSWER

A nonce is a winner when the header's double SHA-256 carrying it comes in under the target. The only
way to read anything about a nonce's digest is to compute it: SHA offers no cheaper necessary
condition than the hash itself. So the FIRST question the recursion asks has to hash every candidate,
and once it has, the digest is cached and every later question is free. The hashes a run spends is
therefore the number of distinct candidates hashed, which the first question drives to the whole
window. That equals a plain scan. The recursion adds structure and no saving. The count shows it, and
not the claim being asserted.

WHERE A SAVING COULD COME FROM, AND THE HOOK THAT WOULD SHOW IT

A saving needs a necessary condition that is CHEAPER than a full hash and that a real winner always
passes. `--cheap` names one, evaluated without hashing, asked as the first question so only the
candidates it keeps are ever hashed. If it prunes, the hash count drops below the scan and the ratio
prints under one. If it is not actually necessary and drops the true winner, the positive control
below fails, and the run reports the condition unsound instead of crediting it with a saving. That is
the safety: a cheap condition earns a saving only by keeping every winner, and the known nonce is the
witness.

THE POSITIVE CONTROL

The header is a real block whose winning nonce the chain recorded. The search hides the low bits of
that nonce and looks for it in the window around it. A run is believed only when it returns exactly
that nonce and the nonce reproduces the block's own id. A cheap condition that breaks this is
reported, not trusted.

WHAT IS HELD

Every number here is about the nonce and sits under the fail-closed partition as HELD.
"""

import hashlib
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_bend_view  # noqa: E402

MASK = 0xFFFFFFFF

# The outcomes o2_run reports, the same set the C driver in src/host/search/o2_spawn.h carries.
O2_FOUND, O2_ABSENT, O2_REFUSED, O2_STALLED = "found", "absent", "refused", "stalled"


def o2_run(same, positions, questions, max_depth=0):
    """The recursive spawn, one question at a time over the survivors, verifying the last candidate.

    A faithful re-statement of src/host/search/o2_spawn.c: each question is asked only of the
    positions still alive, a lone survivor is verified against every remaining question before it is
    called found, and stopping early leaves a correct superset. `same(position, question)` returns a
    truthy value where the position satisfies the question. Returns a dict of survivors, depth,
    oracle_calls, outcome and the alive list.
    """
    if positions <= 0 or questions <= 0:
        return {"survivors": 0, "depth": 0, "oracle_calls": 0, "outcome": O2_REFUSED, "alive": []}
    ceiling = questions if max_depth == 0 else min(max_depth, questions)

    alive = [1] * positions
    survivors = positions
    depth = 0
    oracle_calls = 0

    for question in range(ceiling):
        for at in range(positions):
            if alive[at] == 0:
                continue
            oracle_calls += 1
            if not same(at, question):
                alive[at] = 0
                survivors -= 1
        depth += 1

        if survivors == 0:
            return {"survivors": 0, "depth": depth, "oracle_calls": oracle_calls,
                    "outcome": O2_ABSENT, "alive": alive}
        if survivors == 1:
            candidate = next(at for at in range(positions) if alive[at])
            for rest in range(question + 1, questions):
                oracle_calls += 1
                if not same(candidate, rest):
                    alive[candidate] = 0
                    return {"survivors": 0, "depth": depth, "oracle_calls": oracle_calls,
                            "outcome": O2_ABSENT, "alive": alive}
            return {"survivors": 1, "depth": depth, "oracle_calls": oracle_calls,
                    "outcome": O2_FOUND, "alive": alive}

    outcome = O2_STALLED if ceiling < questions else O2_REFUSED
    return {"survivors": survivors, "depth": depth, "oracle_calls": oracle_calls,
            "outcome": outcome, "alive": alive}


def synthetic_cross_check():
    """The exact field src/host/search/test_o2_spawn.c builds. The two drivers must agree on it.

    Same linear congruential draw, same seed, same plant. If this Python run does not reproduce the C
    run's depth and oracle-call count to the number, one of the two drivers is not the other and the
    measurement below cannot be trusted to mean what the C capability means.
    """
    positions, questions, target, seed = 4096, 12, 1729, 0x51A7
    mask = (1 << questions) - 1
    signature = []
    state = seed
    for at in range(positions):
        state = (state * 1664525 + 1013904223) & MASK
        drawn = state & mask
        if at == target:
            drawn = mask
        elif drawn == mask:
            drawn &= ~1
        signature.append(drawn)

    def same(position, question):
        return (signature[position] >> question) & 1

    result = o2_run(same, positions, questions)
    found = next((at for at in range(positions) if result["alive"][at]), None)
    return result, found, target


def target_from_bits(bits):
    """The 256 bit target a compact nbits encodes."""
    packed = int(bits, 16) if isinstance(bits, str) else int(bits)
    exponent = packed >> 24
    mantissa = packed & 0xFFFFFF
    if exponent <= 3:
        return mantissa >> (8 * (3 - exponent))
    return mantissa << (8 * (exponent - 3))


def digest_int(prefix, nonce):
    """The block hash as the number the target is compared against: the double SHA read little-endian."""
    header = prefix + struct.pack("<I", nonce & MASK)
    once = hashlib.sha256(header).digest()
    twice = hashlib.sha256(once).digest()
    return int.from_bytes(twice, "little")


def nonce_field(block, bits_hidden, cheap=None):
    """A window of nonce candidates around a header's recorded nonce, and the questions to ask them.

    Returns (positions, questions, same, base, winning_position, target, prefix, counters). Position p
    is the nonce `base | p`, where base fixes the high bits at the recorded nonce's. Question 0 is
    `cheap` when one is given and hash-free; the rest are leading-zero-bit conditions and a final exact
    `digest < target`, each of which reads the cached digest. `counters` holds the hashes actually
    spent and the cheap calls, a run's cost is read and not assumed.
    """
    recorded = int(block["nonce"]) & MASK
    window = 1 << bits_hidden
    low_mask = window - 1
    base = recorded & ~low_mask
    winning_position = recorded & low_mask
    target = target_from_bits(block["bits"])
    leading = 256 - target.bit_length()
    prefix = build_bend_view.header_bytes(block, base)[:76]

    cache = {}
    counters = {"hashes": 0, "cheap": 0}

    def value_at(position):
        cached = cache.get(position)
        if cached is None:
            counters["hashes"] += 1
            cached = digest_int(prefix, base | position)
            cache[position] = cached
        return cached

    offset = 1 if cheap is not None else 0
    questions = leading + 1 + offset

    def same(position, question):
        if cheap is not None and question == 0:
            counters["cheap"] += 1
            return cheap(base | position)
        rung = question - offset
        if rung < leading:
            return ((value_at(position) >> (255 - rung)) & 1) == 0
        return value_at(position) < target

    return positions_pack(window, questions, same, base, winning_position, target, prefix, counters)


def positions_pack(window, questions, same, base, winning_position, target, prefix, counters):
    """Bundles what nonce_field returns, named and not a bare tuple a caller must order by hand."""
    return {"positions": window, "questions": questions, "same": same, "base": base,
            "winning_position": winning_position, "target": target, "prefix": prefix,
            "counters": counters}


def plain_scan(block, bits_hidden):
    """Every nonce in the window hashed once, the winners named. The count the recursion is measured against."""
    recorded = int(block["nonce"]) & MASK
    window = 1 << bits_hidden
    base = recorded & ~(window - 1)
    target = target_from_bits(block["bits"])
    prefix = build_bend_view.header_bytes(block, base)[:76]
    winners = []
    for position in range(window):
        if digest_int(prefix, base | position) < target:
            winners.append(base | position)
    return winners, window


def measure(block, bits_hidden, cheap=None):
    """One header, one window: the recursion's hashes and winner against a plain scan's."""
    field = nonce_field(block, bits_hidden, cheap)
    result = o2_run(field["same"], field["positions"], field["questions"])
    found_position = next((at for at in range(field["positions"]) if result["alive"][at]), None)
    found_nonce = None if found_position is None else (field["base"] | found_position)

    scan_winners, window = plain_scan(block, bits_hidden)
    recorded = int(block["nonce"]) & MASK
    reproduces = found_nonce is not None and build_bend_view.block_id(
        build_bend_view.header_bytes(block, found_nonce)) == block["id"]
    return {
        "window": window,
        "o2_hashes": field["counters"]["hashes"],
        "o2_cheap": field["counters"]["cheap"],
        "o2_outcome": result["outcome"],
        "o2_depth": result["depth"],
        "found_nonce": found_nonce,
        "recorded_nonce": recorded,
        "reproduces_id": reproduces,
        "scan_hashes": window,
        "scan_winners": scan_winners,
        "leading_zeros": 256 - field["target"].bit_length(),
    }


def _check():
    failed = 0
    lines = []

    def say(text):
        lines.append(text)

    # THE TWO DRIVERS ARE ONE. The Python spawn must reproduce the C spawn on the C test's own field.
    result, found, target = synthetic_cross_check()
    say("  synthetic field, against src/host/search/test_o2_spawn.c:")
    say("    outcome %s, depth %d, %d oracle calls, found %s (C: found, depth 12, 8189, position %d)"
        % (result["outcome"], result["depth"], result["oracle_calls"], found, target))
    if not (result["outcome"] == O2_FOUND and result["depth"] == 12
            and result["oracle_calls"] == 8189 and found == target):
        say("    FAIL the Python spawn does not reproduce the C spawn. The nonce numbers are not comparable")
        failed += 1

    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        say("  no chain corpus found. The nonce controls cannot run")
        say("")
        say("%d check(s) failed" % failed)
        sys.stdout.write("\n".join(lines) + "\n")
        return failed
    block = blocks[len(blocks) // 2]
    say("  header height %d, id %s..." % (block["height"], block["id"][:16]))

    # THE NULL, MEASURED. With no cheap condition, the recursion hashes the whole window, ties the
    # scan, and still finds the recorded nonce.
    null = measure(block, 12)
    say("  no cheap condition, 2^12 window:")
    say("    o2 hashes %d, scan hashes %d, ratio %.4f; found nonce %s, recorded %s, reproduces id %s"
        % (null["o2_hashes"], null["scan_hashes"], null["o2_hashes"] / float(null["scan_hashes"]),
           null["found_nonce"], null["recorded_nonce"], null["reproduces_id"]))
    if null["o2_hashes"] != null["scan_hashes"]:
        say("    FAIL the recursion did not tie the scan, though its first question must hash every candidate")
        failed += 1
    if null["found_nonce"] != null["recorded_nonce"] or not null["reproduces_id"]:
        say("    FAIL the recursion did not recover the recorded winner")
        failed += 1

    # A TRIVIALLY TRUE CHEAP CONDITION PRUNES NOTHING. It must not be credited with a saving.
    passes_all = measure(block, 12, cheap=lambda nonce: True)
    say("  cheap condition that always passes: o2 hashes %d, cheap calls %d, ratio %.4f"
        % (passes_all["o2_hashes"], passes_all["o2_cheap"],
           passes_all["o2_hashes"] / float(passes_all["scan_hashes"])))
    if passes_all["o2_hashes"] != passes_all["scan_hashes"]:
        say("    FAIL a condition that prunes nothing changed the hash count")
        failed += 1

    # AN UNSOUND CHEAP CONDITION DROPS THE WINNER, and the positive control has to catch it and
    # not report a saving. The window is small so the discarded winner is deterministic.
    winning_position = passes_all["recorded_nonce"] & (passes_all["window"] - 1)
    base = passes_all["recorded_nonce"] & ~(passes_all["window"] - 1)
    unsound = measure(block, 12, cheap=lambda nonce: (nonce & (passes_all["window"] - 1)) != winning_position)
    caught = (unsound["found_nonce"] != unsound["recorded_nonce"]) or (not unsound["reproduces_id"])
    say("  cheap condition that drops the winner: found nonce %s, recorded %s, caught %s"
        % (unsound["found_nonce"], unsound["recorded_nonce"], caught))
    if not caught:
        say("    FAIL an unsound cheap condition was credited instead of caught")
        failed += 1
    _ = base

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

    widths = [8, 12, 16, 20]
    if "--bits" in argv:
        at = argv.index("--bits")
        if at + 1 >= len(argv):
            sys.stderr.write("--bits needs a value\n")
            return 2
        widths = [int(argv[at + 1])]

    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        sys.stderr.write("no chain corpus found under utils/maint/chain\n")
        return 2
    block = blocks[len(blocks) // 2]
    print("  header height %d, id %s, %d leading zero bits in its target"
          % (block["height"], block["id"], 256 - target_from_bits(block["bits"]).bit_length()))
    print("  %6s %14s %14s %8s %10s %12s" % ("bits", "o2 hashes", "scan hashes", "ratio",
                                             "o2 depth", "found == won"))
    for width in widths:
        row = measure(block, width)
        ratio = row["o2_hashes"] / float(row["scan_hashes"])
        agree = (row["found_nonce"] == row["recorded_nonce"]) and row["reproduces_id"]
        print("  %6d %14d %14d %8.4f %10d %12s"
              % (width, row["o2_hashes"], row["scan_hashes"], ratio, row["o2_depth"], agree))
    print("")
    print("  a ratio of 1.0000 is the recursion tying the scan: with no cheaper-than-a-hash")
    print("  necessary condition, the first question hashes every candidate. Supply one with --cheap")
    print("  in code to see the ratio move, and the winner check will catch one that is not sound.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
