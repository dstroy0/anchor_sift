"""Checks whether the deficit measurements conserve across headers.

Every number in this workbook has been taken on block 125552. One header is one corpus, and the
conservation posit in anchor_sift is explicit about what that means: state what a measure must be
invariant to and check each, without inferring the rule from the case that suggested it. Being
invariant to which header is the row that has never been checked.

The distinction between a real test here and a restatement: a measurement has a *within*
header resolution, set by the bin count, and an *across* header spread. If the second is larger than
the first, the quantity is a fact about the header and not about SHA-256, and every figure in
this workbook would need re-reading as a property of block 125552.

Each header is built from the block's own fields and then **verified against that block's published
hash** before it is used. Bitcoin's serialisation reverses the two hashes and stores the integers
little-endian, and this project has already had a prevhash byte order wrong once. A header that does
not reproduce its own block id is not used, and that refusal is reported instead of measuring the wrong bytes.

Usage: python tools/conserve_headers.py [how many headers] [domain bits]
"""

import hashlib
import math
import json
import re
import statistics
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
BLOCKS = ROOT / "tools" / "blocks.json"

ROW = re.compile(r"^\s+(0|1/2|1|2|3|4|inf)\s+(\S+)\s+(\S+)\s+(\S+)\s")
FAMILY = re.compile(r"windows (\d+), bins (\d+), mean count")
RATIO = re.compile(r"order two over order one half\s*:\s*([0-9.]+)")


def build_header(block):
    """The eighty bytes as Bitcoin serialises them, hashes reversed and integers little-endian."""
    return (
        struct.pack("<I", block["version"])
        + bytes.fromhex(block["previousblockhash"])[::-1]
        + bytes.fromhex(block["merkle_root"])[::-1]
        + struct.pack("<I", block["timestamp"])
        + struct.pack("<I", block["bits"])
        + struct.pack("<I", block["nonce"])
    )


def block_id_of(header):
    """The block hash as an explorer prints it, the digest reversed."""
    once = hashlib.sha256(header).digest()
    return hashlib.sha256(once).digest()[::-1].hex()


def readings(text):
    """Returns the SHA256d deficit ratios per family and order, plus the order ratio."""
    out = {}
    in_sha = False
    bins = None
    for line in text.splitlines():
        if line.startswith("  SHA256d over the whole"):
            in_sha = True
            continue
        if not in_sha:
            continue
        family = FAMILY.search(line)
        if family:
            bins = int(family.group(2))
            continue
        order_ratio = RATIO.search(line)
        if order_ratio and bins:
            out[(bins, "two-over-half")] = float(order_ratio.group(1))
            continue
        row = ROW.match(line)
        if row and bins:
            try:
                out[(bins, row.group(1))] = float(row.group(4))
            except ValueError:
                continue
    return out


def main():
    wanted = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    domain = sys.argv[2] if len(sys.argv) > 2 else "26"

    blocks = json.loads(BLOCKS.read_text())
    # Spread across the corpus and never the first few, which would all share a difficulty
    # epoch and much of their prevhash structure.
    step = max(1, len(blocks) // wanted)
    chosen = blocks[::step][:wanted]

    exe = ROOT / "src" / "bench" / "bench_renyi_gpu.exe"
    on_device = "1"
    if not exe.exists():
        exe = ROOT / "src" / "bench" / "bench_renyi.exe"
        on_device = "0"

    print("=" * 84)
    print("  Do the deficits conserve across headers, or are they facts about block 125552")
    print("=" * 84)
    print()
    print("  %d headers, domain 2^%s, %s" % (len(chosen), domain, exe.name))
    print()

    collected = []
    for block in chosen:
        header = build_header(block)
        rebuilt = block_id_of(header)
        if rebuilt != block["id"]:
            print("  [!] height %d does not reproduce its own block id, so it is not used."
                  % block["height"])
            print("      built %s" % rebuilt)
            print("      published %s" % block["id"])
            continue

        run = subprocess.run(
            [str(exe), domain, "0", "0", "0", "0", on_device, header.hex()],
            capture_output=True, text=True,
        )
        found = readings(run.stdout)
        if not found:
            print("  [!] height %d produced no readable rows" % block["height"])
            continue
        collected.append((block["height"], found))
        print("  height %-9d verified against its published hash, %d readings"
              % (block["height"], len(found)))

    if len(collected) < 2:
        print("\n  fewer than two usable headers, nothing to compare")
        return

    print()
    print("  %-8s %-14s %12s %12s %12s %10s" %
          ("bins", "order", "mean", "across", "within", "ratio"))
    print("  %-8s %-14s %12s %12s %12s %10s" %
          ("--------", "--------------", "------------", "------------", "------------",
           "----------"))

    keys = sorted(set(collected[0][1]) & set.intersection(*[set(f) for _, f in collected]),
                  key=lambda k: (k[0], str(k[1])))

    worst = 0.0
    for key in keys:
        values = [found[key] for _, found in collected]
        bins, order = key
        across = statistics.pstdev(values)
        # The chi-square statistic behind a deficit has variance twice its degrees of freedom, so
        # one family of w windows resolves its ratio to this and no better. Nothing is fitted.
        windows = 32 if bins == 256 else 16
        if order == "inf":
            # Order infinity reads the largest bin, which is an extreme value and not a chi-square
            # quantity. Its deficit is log2(1 + max deviation), the max deviation sits near
            # sigma*sqrt(2 ln r) and its own spread is the Gumbel scale sigma/sqrt(2 ln r), so the
            # relative resolution is 1/(2 ln r) and has nothing to do with the bin count the way
            # the other orders do.
            #
            # Using the chi-square formula here gave a ratio of 10.77 and read as a conservation
            # failure. It was the wrong null, which is failure mode 2 and the same error that
            # inflated an earlier headline by 4,200.
            within = (1.0 / (2.0 * math.log(bins))) / (windows ** 0.5)
        elif order == "two-over-half":
            # A ratio between two orders, where the common scale cancels. Both are driven by the
            # same chi-square statistic, so the difference is far better resolved than either.
            within = (2.0 / (bins - 1)) ** 0.5 / (windows ** 0.5)
        else:
            within = (2.0 / (bins - 1)) ** 0.5 / (windows ** 0.5)
        ratio = across / within if within > 0 else 0.0
        worst = max(worst, ratio)
        print("  %-8d %-14s %12.6f %12.6f %12.6f %10.3f" %
              (bins, order, statistics.fmean(values), across, within, ratio))

    print()
    print("  The ratio column is the whole test. Across-header spread over the resolution one")
    print("  header already has. Near or below one says the measurement is the same measurement")
    print("  whichever header it is taken on, and that sameness is what conservation asserts. Well above one")
    print("  says every figure in this workbook is a property of block 125552.")
    print()
    print("  largest ratio over all rows: %.3f" % worst)


main()
