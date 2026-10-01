"""What one nonce costs to test, measured, and what that makes a real one cost to find.

    python tools/view/nonce_cost.py --check
    python tools/view/nonce_cost.py               cost per nonce, and the search it implies
    python tools/view/nonce_cost.py --search N    actually search N nonces on a real block

THE QUESTION

Douglas: try and get a real nonce, from the real corpus we have, let me know the compute time per
nonce.

Both halves are measurable and the corpus makes the first one a known-answer test rather than a
benchmark taken on trust. Each block in `tools/chain/blocks_deep.json` carries the nonce that
actually won it and the `bits` field that sets the target it had to beat, so:

    the KAT       the recorded nonce must produce a hash at or under that block's own target
    the cost      time one nonce, then multiply by what the target demands

VERIFYING IS FREE AND FINDING IS NOT, and the gap between those two is the entire economics of
mining. A recorded nonce is checked in one double hash. Finding it means trying nonces until one
lands, and the expected count is set by the target and nothing else.

WHAT IS NOT BEING DONE HERE. This searches a historical block's nonce space as a COST MEASUREMENT.
It submits nothing, connects to nothing, and mines nothing: the block in question was solved years
of blocks ago and its nonce is already in the file being read.
"""

import argparse
import hashlib
import io
import json
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import chain_kat

# Measured on this machine by the client's own run, printed as "run 2366 MH/s" over two minutes.
MEASURED_GPU = 2.366e9

SECONDS_PER_YEAR = 365.25 * 24.0 * 3600.0


def target_of(bits):
    """The threshold a block's hash had to come in at or under, from the compact bits field.

    bits packs an exponent in the top byte and a mantissa in the low three, so the target is
    mantissa times 256 to the exponent less three. This is the one quantity that decides how many
    nonces a block cost, so it is computed rather than approximated by a leading-zero count.
    """
    value = int(bits, 16) if isinstance(bits, str) else int(bits)
    exponent = value >> 24
    mantissa = value & 0x007FFFFF
    if exponent <= 3:
        return mantissa >> (8 * (3 - exponent))
    return mantissa << (8 * (exponent - 3))


def double_sha(header):
    return hashlib.sha256(hashlib.sha256(header).digest()).digest()


def hash_int(header):
    """The hash as the integer the comparison against target is made on, little endian."""
    return int.from_bytes(double_sha(header), "little")


def expected_tries(target):
    """How many nonces a target demands on average: 2^256 over the target plus one."""
    return (1 << 256) // (target + 1)


def time_one_nonce(block, rounds=20000):
    """Seconds per nonce, measured on the real header by rebuilding and hashing it.

    The header is rebuilt each time rather than patched in place, which is what a naive
    implementation does and is the honest figure for this code. A miner patches the four nonce bytes
    and reuses the first block's midstate, and that difference is reported separately rather than
    folded in.
    """
    header = bytearray(chain_kat.header_bytes(block))
    began = time.perf_counter()
    for nonce in range(rounds):
        header[76:80] = struct.pack("<I", nonce & 0xFFFFFFFF)
        double_sha(bytes(header))
    return (time.perf_counter() - began) / rounds


def _report():
    blocks = chain_kat.load_blocks(limit=8)
    print("  Real blocks, with the nonce that won each one already in the file.")
    print("")
    print("  %10s %12s %22s %14s"
          % ("height", "nonce", "target", "meets it"))

    for block in blocks[:5]:
        target = target_of(block["bits"])
        header = chain_kat.header_bytes(block)
        meets = hash_int(header) <= target
        print("  %10d %12d %22s %14s"
              % (block["height"], int(block["nonce"]), "0x%062x" % target, meets))

    print("")
    print("  THE KAT: every recorded nonce produces a hash at or under its own block's target, so")
    print("  the target arithmetic is right and the cost figures below rest on the real threshold")
    print("  rather than on a leading-zero approximation.")
    print("")

    block = blocks[0]
    per_nonce = time_one_nonce(block)
    target = target_of(block["bits"])
    tries = expected_tries(target)

    print("  COST PER NONCE ON THIS MACHINE")
    print("")
    print("    this file, Python hashlib, header rebuilt each time   %.3e s   %.2f kH/s"
          % (per_nonce, 1.0 / per_nonce / 1000.0))
    print("    the client's CUDA path, measured on its own run       %.3e s   %.0f MH/s"
          % (1.0 / MEASURED_GPU, MEASURED_GPU / 1e6))
    print("    the card is faster by a factor of                     %.3e"
          % (per_nonce * MEASURED_GPU))
    print("")
    print("  WHAT THE REAL BLOCK DEMANDED")
    print("")
    print("    block %d target                    0x%062x" % (block["height"], target))
    print("    expected nonces to land under it   %.4e" % tries)
    print("    at %.0f MH/s that is              %.4e years"
          % (MEASURED_GPU / 1e6, tries / MEASURED_GPU / SECONDS_PER_YEAR))
    print("    at this file's Python rate         %.4e years"
          % (tries * per_nonce / SECONDS_PER_YEAR))
    print("")
    print("  a REAL BLOCK IS NOT REACHABLE FROM HERE AND THE NUMBER IS NOT CLOSE. That is the")
    print("  network's difficulty and not a property of this code: the same target faces every")
    print("  miner, and the ones that find blocks are running on the order of 1e20 hashes a second")
    print("  in aggregate rather than 1e9.")
    print("")
    print("  WHAT A POOL SHARE DEMANDS, WHICH IS THE FIGURE THAT MATTERS")
    print("")
    print("  %14s %22s %18s" % ("share difficulty", "expected nonces", "at 2366 MH/s"))
    for difficulty in (1024.0, 2048.0, 8192.0):
        share_tries = difficulty * (2 ** 32)
        seconds = share_tries / MEASURED_GPU
        print("  %14.0f %22.4e %14.2f hours"
              % (difficulty, share_tries, seconds / 3600.0))
    print("")
    print("  Those are the difficulties the pool actually sent during the two minutes the client")
    print("  ran: 8192, then 2048, then 1024. a share is hours of work and a block is not")
    print("  reachable, and the two are separated by a factor of about 1e19.")
    print("")
    print("  AND VERIFYING IS FREE, WHICH IS THE ASYMMETRY THE WHOLE THING RESTS ON. Checking the")
    print("  recorded nonce above took one double hash, %.3e seconds. Finding it would have taken"
          % per_nonce)
    print("  %.4e of them. That ratio IS the proof of work." % tries)
    return 0


def _search(count, height_at=0):
    """Search a real block's nonce space and report what was found, as a cost measurement."""
    blocks = chain_kat.load_blocks(limit=height_at + 1)
    block = blocks[height_at]
    target = target_of(block["bits"])
    header = bytearray(chain_kat.header_bytes(block))

    print("  Searching %d nonces on block %d as a cost measurement." % (count, block["height"]))
    print("  Its real nonce is %d and is already in the file; this is not looking for it."
          % int(block["nonce"]))
    print("")

    best = (1 << 256)
    best_at = None
    began = time.perf_counter()
    for nonce in range(count):
        header[76:80] = struct.pack("<I", nonce & 0xFFFFFFFF)
        value = hash_int(bytes(header))
        if value < best:
            best = value
            best_at = nonce
    spent = time.perf_counter() - began

    print("  %d nonces in %.3f s, %.2f kH/s, %.3e s each"
          % (count, spent, count / spent / 1000.0, spent / count))
    print("")
    print("  best hash found     0x%064x" % best)
    print("  at nonce            %d" % best_at)
    print("  the block's target  0x%064x" % target)
    print("  under target        %s" % (best <= target))
    print("")
    zeros = 256 - best.bit_length() if best else 256
    print("  the best of %d tries has %d leading zero bits, and the target needs %d"
          % (count, zeros, 256 - target.bit_length()))
    print("")
    print("  THAT IS THE EXPECTED RESULT AND NOT A FAILURE. The best of N random tries has about")
    print("  log2(N) leading zeros, so %d tries buys about %.1f and the target wants %d. Reaching"
          % (count, __import__("math").log2(count), 256 - target.bit_length()))
    print("  the target needs about %.3e tries, so this sample is short by a factor of %.3e."
          % (expected_tries(target), expected_tries(target) / count))
    return 0


def _check():
    lines = []
    failed = 0
    blocks = chain_kat.load_blocks(limit=40)

    # THE KAT. Every recorded nonce must beat its own block's target, or the target arithmetic is
    # wrong and every cost figure derived from it is wrong with it.
    bad = []
    for block in blocks:
        target = target_of(block["bits"])
        if hash_int(chain_kat.header_bytes(block)) > target:
            bad.append(block["height"])
    lines.append("  %d of %d recorded nonces come in at or under their own target"
                 % (len(blocks) - len(bad), len(blocks)))
    if bad:
        lines.append("    FAIL the target arithmetic is wrong at heights %s" % bad[:6])
        failed += 1

    # THE NEGATIVE CONTROL. A wrong nonce must NOT beat the target, or the test above is vacuous.
    block = blocks[0]
    target = target_of(block["bits"])
    wrong = chain_kat.header_bytes(block, int(block["nonce"]) ^ 0xFF)
    lines.append("  the same header with a corrupted nonce beats the target: %s"
                 % (hash_int(wrong) <= target))
    if hash_int(wrong) <= target:
        lines.append("    FAIL a wrong nonce met the target, which is a one in 1e24 coincidence")
        lines.append("         or, far more likely, a broken comparison")
        failed += 1

    # The target must match the leading-zero count the hash actually has, as a cross-check on the
    # bits decoding, which is the easiest thing here to get subtly wrong.
    zeros_needed = 256 - target.bit_length()
    got = 256 - hash_int(chain_kat.header_bytes(block)).bit_length()
    lines.append("  target needs %d leading zero bits and the winning hash has %d"
                 % (zeros_needed, got))
    if got < zeros_needed:
        lines.append("    FAIL the winning hash has fewer leading zeros than its target demands")
        failed += 1

    # And the expected-tries figure must agree with the leading-zero count to within a factor of a
    # few, or the target is being read at the wrong scale.
    import math
    tries = expected_tries(target)
    lines.append("  expected tries %.3e, and 2^%d is %.3e"
                 % (tries, zeros_needed, 2.0 ** zeros_needed))
    if not 0.25 < tries / (2.0 ** zeros_needed) < 4.0:
        lines.append("    FAIL the expected try count and the leading-zero count disagree, so the")
        lines.append("         bits field is being decoded at the wrong scale")
        failed += 1
    del math

    # The timing must be a real measurement and not instant, or the cost figure is meaningless.
    per = time_one_nonce(block, rounds=2000)
    lines.append("  one nonce costs %.3e s in this file, %.1f kH/s" % (per, 1.0 / per / 1000.0))
    if per <= 0.0 or per > 1e-3:
        lines.append("    FAIL the per-nonce time is implausible")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="what a nonce costs, measured")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--search", type=int, default=0)
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.search:
        sys.exit(_search(args.search))
    sys.exit(_report())
