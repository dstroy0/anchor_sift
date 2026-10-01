#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""The valid set: every nonce whose hash clears an easy target, and the topology of that set.

    python examples/00_blob_viz_tools/nonce_validset.py --check     the controls, each able to fail
    python examples/00_blob_viz_tools/nonce_validset.py             the valid set of one real header

REVERSING THE TOPOLOGY

The forward question, does a nonce win, kept coming back flat. The reverse question is what the whole
SET of winning nonces looks like: not the one that got mined, which mining habits skew, but every
nonce whose hash falls below the target. That set is the preimage of the valid region, and its shape
is a property of the hash, alone, because it is not one draw but all of them.

WHAT IS MEASURED

At an easy target a header has many valid nonces, thousands over a range small enough to scan. If the
hash is uniform the valid nonces are a Poisson scatter: the gaps between consecutive ones are
exponential, and the count in equal bins is Poisson. Structure would show as clustering, gaps too
short and too long together, or bins too full and too empty. The reading is the gap distribution and
the bin counts against those two nulls, both of which a uniform valid set produces by construction.

WHY THIS IS CLEAN

Every nonce in the range is hashed and every valid one is kept. No search order and no mining
habit enters. The valid set is the hash's own, and a departure from Poisson is the hash's own too.

WHAT IS HELD

Every number here is about the nonce and sits under the fail-closed partition as HELD.
"""

import hashlib
import math
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_bend_view  # noqa: E402

MASK = 0xFFFFFFFF


def valid_nonces(prefix, target, scan):
    """Every nonce in [0, scan) whose header double hash, as the compared number, is below target."""
    found = []
    for nonce in range(scan):
        header = prefix + struct.pack("<I", nonce & MASK)
        digest = hashlib.sha256(hashlib.sha256(header).digest()).digest()
        if int.from_bytes(digest, "little") < target:
            found.append(nonce)
    return found


def valid_with_leading(prefix, base_target, scan):
    """Every nonce below `base_target`, each with the leading-zero count of its hash number.

    One scan records the whole nested family: the survivors at a tighter target are those whose
    leading-zero count reaches it. The descent needs no rescan, only a threshold on this count.
    """
    found = []
    for nonce in range(scan):
        header = prefix + struct.pack("<I", nonce & MASK)
        digest = hashlib.sha256(hashlib.sha256(header).digest()).digest()
        value = int.from_bytes(digest, "little")
        if value < base_target:
            found.append((nonce, 256 - value.bit_length() if value > 0 else 256))
    return found


def survival_gap(survivors, next_level_set):
    """Mean nearest-neighbor gap for survivors that advance a level and for those that do not.

    If which survivor advances is independent of where it sits, the two means agree. A survivor whose
    advancing is predictable from its local density in the current set would split them.
    """
    positions = sorted(nonce for nonce, _ in survivors)
    gap_of = {}
    for index, nonce in enumerate(positions):
        left = positions[index] - positions[index - 1] if index > 0 else None
        right = positions[index + 1] - positions[index] if index + 1 < len(positions) else None
        candidates = [gap for gap in (left, right) if gap is not None]
        gap_of[nonce] = min(candidates) if candidates else 0
    advanced = [gap_of[nonce] for nonce, _ in survivors if nonce in next_level_set]
    stayed = [gap_of[nonce] for nonce, _ in survivors if nonce not in next_level_set]
    mean_adv = sum(advanced) / float(len(advanced)) if advanced else None
    mean_stay = sum(stayed) / float(len(stayed)) if stayed else None
    return mean_adv, mean_stay, len(advanced), len(stayed)


def split_band(gaps, advanced_count, draws, seed):
    """The gap-mean difference a RANDOM split of the survivors into an advanced set of this size gives."""
    generator = random.Random(seed)
    scores = []
    for _ in range(draws):
        shuffled = gaps[:]
        generator.shuffle(shuffled)
        advanced = shuffled[:advanced_count]
        stayed = shuffled[advanced_count:]
        if advanced and stayed:
            scores.append((sum(advanced) / len(advanced)) - (sum(stayed) / len(stayed)))
    scores.sort()
    length = len(scores)
    return (scores[int(0.025 * (length - 1))], scores[int(0.975 * (length - 1))])


def gap_stats(nonces):
    """Mean and coefficient of variation of the gaps between consecutive valid nonces.

    A Poisson scatter has exponential gaps, whose coefficient of variation, the ratio of the gap
    standard deviation to the gap mean, is one. Clustering pushes it above one, a lattice below it.
    """
    if len(nonces) < 3:
        return None, None
    gaps = [nonces[index + 1] - nonces[index] for index in range(len(nonces) - 1)]
    mean = sum(gaps) / float(len(gaps))
    variance = sum((gap - mean) ** 2 for gap in gaps) / float(len(gaps))
    return mean, (math.sqrt(variance) / mean if mean > 0 else None)


def bin_dispersion(nonces, scan, bins):
    """The index of dispersion of the per-bin valid counts: variance over mean, one for Poisson."""
    counts = [0] * bins
    width = scan / float(bins)
    for nonce in nonces:
        index = int(nonce / width)
        counts[index if index < bins else bins - 1] += 1
    mean = sum(counts) / float(bins)
    if mean <= 0:
        return None
    variance = sum((count - mean) ** 2 for count in counts) / float(bins)
    return variance / mean


def cov_band(count, scan, draws, seed):
    """The gap coefficient of variation a uniform valid set of this size over this range gives."""
    generator = random.Random(seed)
    scores = []
    for _ in range(draws):
        picks = sorted(generator.sample(range(scan), count))
        _, cov = gap_stats(picks)
        if cov is not None:
            scores.append(cov)
    scores.sort()
    length = len(scores)
    return (scores[int(0.025 * (length - 1))], scores[int(0.5 * (length - 1))],
            scores[int(0.975 * (length - 1))])


def dispersion_band(count, scan, bins, draws, seed):
    """The bin index of dispersion a uniform valid set of this size gives."""
    generator = random.Random(seed)
    scores = []
    for _ in range(draws):
        picks = generator.sample(range(scan), count)
        value = bin_dispersion(picks, scan, bins)
        if value is not None:
            scores.append(value)
    scores.sort()
    length = len(scores)
    return (scores[int(0.025 * (length - 1))], scores[int(0.5 * (length - 1))],
            scores[int(0.975 * (length - 1))])


def _check():
    failed = 0
    lines = []

    def say(text):
        lines.append(text)

    generator = random.Random(5)
    scan = 1 << 20
    count = 2000

    # A UNIFORM SET IS POISSON. Its gap coefficient of variation sits at one, inside the band drawn at
    # its own size, and its bin dispersion at one too. If these do not hold the estimator is wrong.
    uniform = sorted(generator.sample(range(scan), count))
    _, cov = gap_stats(uniform)
    dispersion = bin_dispersion(uniform, scan, 64)
    cband = cov_band(count, scan, 200, 11)
    say("  uniform set: gap variation %.3f, band %.3f to %.3f; bin dispersion %.3f"
        % (cov, cband[0], cband[2], dispersion))
    if not (cband[0] <= cov <= cband[2]):
        say("    FAIL a uniform set fell outside its own gap-variation band")
        failed += 1

    # A CLUSTERED SET IS NOT POISSON. Draw the valid nonces from a few tight clumps and the gap
    # variation and the bin dispersion both rise far over the uniform band. If they do not, the
    # instrument cannot see clustering and a null from it is empty.
    clustered = []
    for _ in range(count):
        center = generator.randrange(0, scan, scan // 20)
        clustered.append((center + generator.randrange(scan // 400)) % scan)
    clustered = sorted(set(clustered))
    _, clustered_cov = gap_stats(clustered)
    clustered_dispersion = bin_dispersion(clustered, scan, 64)
    dband = dispersion_band(count, scan, 64, 200, 13)
    say("  clustered set: gap variation %.3f (over %.3f); bin dispersion %.3f (over %.3f)"
        % (clustered_cov, cband[2], clustered_dispersion, dband[2]))
    if clustered_cov <= cband[2] or clustered_dispersion <= dband[2]:
        say("    FAIL a clustered set did not clear the uniform bands")
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

    leading = 12
    scan_bits = 24
    if "--leading" in argv:
        leading = int(argv[argv.index("--leading") + 1])
    if "--scan" in argv:
        scan_bits = int(argv[argv.index("--scan") + 1])

    blocks, read, refused = build_bend_view.load_chain()
    if not blocks:
        sys.stderr.write("no chain corpus found under utils/maint/chain\n")
        return 2
    block = blocks[len(blocks) // 2]
    prefix = build_bend_view.header_bytes(block, 0)[:76]
    target = 1 << (256 - leading)
    scan = 1 << scan_bits

    if "--descent" in argv:
        # ASK WHICH IT IS FROM THE SURVIVOR SETS. Scan once at an easy target, then tighten level by
        # level. At each level, is which survivor advances predictable from its local density in the
        # current set? If the set is a uniform scatter the advancing survivors are a random split and
        # their mean local gap matches those that stay; a predictable descent would split them.
        base = 10
        found = valid_with_leading(prefix, 1 << (256 - base), scan)
        print("  header height %d, descent from %d leading zeros, scanning 2^%d nonces"
              % (block["height"], base, scan_bits))
        print("  %6s %10s %14s %16s %22s %10s"
              % ("level", "survivors", "advance", "gap adv/stay", "random-split band", "verdict"))
        for level in range(base, base + 5):
            survivors = [(nonce, lead) for nonce, lead in found if lead >= level]
            next_set = set(nonce for nonce, lead in found if lead >= level + 1)
            if len(survivors) < 100 or not next_set:
                break
            mean_adv, mean_stay, adv_count, stay_count = survival_gap(survivors, next_set)
            gaps = []
            positions = sorted(nonce for nonce, _ in survivors)
            for index, nonce in enumerate(positions):
                left = positions[index] - positions[index - 1] if index > 0 else None
                right = positions[index + 1] - positions[index] if index + 1 < len(positions) else None
                candidates = [gap for gap in (left, right) if gap is not None]
                gaps.append(min(candidates) if candidates else 0)
            band = split_band(gaps, adv_count, 400, 5000 + level)
            difference = (mean_adv - mean_stay) if (mean_adv is not None and mean_stay is not None) else 0.0
            verdict = "PREDICTS" if (difference < band[0] or difference > band[1]) else "in band"
            print("  %6d %10d %14d %16s %10.1f to %.1f %10s"
                  % (level, len(survivors), adv_count,
                     "%.0f/%.0f" % (mean_adv or 0, mean_stay or 0), band[0], band[1], verdict))
        print("")
        print("  in band at every level is the boundary: which survivor advances is a uniform split of")
        print("  the set, unpredictable from where it sits. PREDICTS is local density telling you which.")
        return 0

    print("  header height %d, easy target of %d leading zero bits, scanning 2^%d nonces"
          % (block["height"], leading, scan_bits))
    nonces = valid_nonces(prefix, target, scan)
    print("  valid nonces found: %d (expected about %d)" % (len(nonces), scan >> leading))
    if len(nonces) < 50:
        print("  too few valid nonces to read the set; raise --leading is lower or --scan higher")
        return 0

    mean, cov = gap_stats(nonces)
    dispersion = bin_dispersion(nonces, scan, 64)
    cband = cov_band(len(nonces), scan, 300, 4242)
    dband = dispersion_band(len(nonces), scan, 64, 300, 4243)
    print("")
    print("  gap coefficient of variation: %.4f, uniform band %.4f to %.4f -> %s"
          % (cov, cband[0], cband[2],
             "CLUSTERED" if cov > cband[2] else ("lattice" if cov < cband[0] else "Poisson")))
    print("  bin index of dispersion:      %.4f, uniform band %.4f to %.4f -> %s"
          % (dispersion, dband[0], dband[2],
             "CLUSTERED" if dispersion > dband[2] else ("even" if dispersion < dband[0] else "Poisson")))
    print("")
    print("  Poisson on both is the boundary: the valid set is a uniform scatter, no topology to")
    print("  reverse. Over the band on either is clustering in the valid set, a shape in the hash.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
