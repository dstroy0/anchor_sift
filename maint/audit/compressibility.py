"""The axis every other test in this tree misses: algorithmic structure, not distribution.

Everything else here is statistical. Uniform shares, flat autocorrelation, full algebraic degree, no
co-variation between positions. The digits of pi pass every one of those tests, and the digits of pi
compress to about a kilobyte. So passing them establishes nothing about whether a sequence has a
short generating program, and that is exactly the property that would matter.

    a sequence can be perfectly uniform and perfectly compressible at the same time

This runs the other axis. Three sequences are compared under identical treatment:

    sha       leading bits of SHA-256 over consecutive nonces, which is what mining searches
    pi        hexadecimal digits of pi, which HAVE a short program by construction
    random    the operating system's entropy source, which by assumption has none

The pi arm is the point. It is the positive control for the thing being hunted: a sequence known to
have a kilobyte program. If the instrument cannot separate pi from random, then it cannot separate
SHA from random either, and saying so is the result.

WHAT THIS CAN AND CANNOT DO

Kolmogorov complexity is uncomputable, so no tool decides this. A compressor gives an UPPER bound:
if it compresses, structure exists. Failing to compress proves nothing, because the compressor is
looking for repetition and a generating program is not repetition. That asymmetry is the honest
limit and the pi arm measures it directly rather than leaving it as a caveat.

    python maint/audit/compressibility.py
"""

import argparse
import hashlib
import lzma
import math
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT, "examples", "proofing"))


def sha_stream(count, take_bytes=4):
    """Leading bytes of SHA-256 over consecutive nonces: the sequence mining walks."""
    out = bytearray()
    for nonce in range(count):
        digest = hashlib.sha256(struct.pack("<Q", nonce)).digest()
        out.extend(digest[:take_bytes])
    return bytes(out)


def pi_stream(length):
    """Hexadecimal digits of pi, packed two per byte. The positive control."""
    try:
        import digit_reach
        text = digit_reach.hex_of_pi(length * 2)
    except Exception:
        return None
    out = bytearray()
    for at in range(0, len(text) - 1, 2):
        out.append(int(text[at:at + 2], 16))
    return bytes(out[:length])


def random_stream(length):
    """The operating system's entropy source. Assumed to have no short program."""
    return os.urandom(length)


def block_entropy(data, order):
    """Empirical entropy per byte at a given block order, in bits.

    A sequence with structure at that order shows a deficit against eight bits per byte. This is
    the statistical half, included so the two axes can be compared on the same data.
    """
    if len(data) <= order:
        return 0.0
    counts = {}
    for at in range(len(data) - order):
        key = data[at:at + order + 1]
        counts[key] = counts.get(key, 0) + 1
    total = float(sum(counts.values()))
    entropy = 0.0
    for seen in counts.values():
        share = seen / total
        entropy -= share * math.log2(share)
    return entropy / (order + 1)


def lempel_ziv(data, cap=200000):
    """Count of distinct phrases in the Lempel-Ziv parse, a complexity proxy with no dictionary."""
    view = data[:cap]
    seen = set()
    phrases = 0
    start = 0
    at = 0
    while at < len(view):
        at += 1
        piece = view[start:at]
        if piece not in seen:
            seen.add(piece)
            phrases += 1
            start = at
    return phrases, len(view)


def measure(name, data):
    raw = len(data)
    deflated = len(zlib.compress(data, 9))
    squeezed = len(lzma.compress(data, preset=9))
    phrases, walked = lempel_ziv(data)
    # The LZ phrase count for an incompressible sequence approaches n / log2(n).
    expected_phrases = walked / math.log2(max(walked, 2))
    print("  %-8s raw %9s   zlib %9s (%.4f)   lzma %9s (%.4f)"
          % (name, format(raw, ","), format(deflated, ","), deflated / float(raw),
             format(squeezed, ","), squeezed / float(raw)))
    print("           LZ phrases %s over %s bytes, ratio to incompressible %.4f"
          % (format(phrases, ","), format(walked, ","), phrases / expected_phrases))
    print("           block entropy, order 1 %.5f   order 2 %.5f   (8.0 is flat)"
          % (block_entropy(data[:120000], 1) * 2, block_entropy(data[:120000], 2) * 3))
    return deflated / float(raw), squeezed / float(raw), phrases / expected_phrases


def main():
    parser = argparse.ArgumentParser(description="Algorithmic structure, not distribution.")
    parser.add_argument("--bytes", type=int, default=2000000)
    given = parser.parse_args()

    length = given.bytes
    print("  %s bytes per sequence" % format(length, ","))
    print()
    print("=" * 78)
    print("  COMPRESSION: an upper bound on complexity. Compressing proves structure;")
    print("  failing to compress proves nothing, which is what the pi arm is here to show.")
    print("=" * 78)
    print()

    results = {}
    results["random"] = measure("random", random_stream(length))
    print()
    results["sha"] = measure("sha", sha_stream(length // 4, 4))
    print()
    pi_data = pi_stream(length // 20)
    if pi_data:
        results["pi"] = measure("pi", pi_data)
    else:
        print("  pi        unavailable, so the positive control did not run")
    print()

    print("=" * 78)
    print("  READING")
    print("=" * 78)
    print()
    if "pi" in results:
        print("    pi has a kilobyte program by construction. Its compression ratio here is %.4f"
              % results["pi"][1])
        print("    against random's %.4f. If those are the same, the instrument cannot see a"
              % results["random"][1])
        print("    generating program, and its verdict on SHA is therefore empty.")
        print()
        gap = abs(results["pi"][1] - results["random"][1])
        if gap < 0.01:
            print("    THE INSTRUMENT IS BLIND. It does not separate a sequence with a known short")
            print("    program from one assumed to have none. So it cannot say whether SHA has")
            print("    structure, and reporting that SHA 'does not compress' would be reporting")
            print("    the compressor's limits as a property of SHA.")
            print()
            print("    That is the honest state of the question, and it is not a small one: the")
            print("    gap between a thousand-bit description and a 2^48 search is assumed by all")
            print("    of modern cryptography and proven by none of it. No empirical tool settles")
            print("    it, because Kolmogorov complexity is uncomputable and every practical")
            print("    compressor looks for repetition, which a generating program is not.")
        else:
            print("    The instrument separates them by %.4f, so its verdict on SHA carries that"
                  % gap)
            print("    much weight and no more.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
