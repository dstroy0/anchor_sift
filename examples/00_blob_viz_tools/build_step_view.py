"""Traces SHA-256 twice, a message and the same message with one bit flipped, and renders it.

Every reading in this work is about what a difference does as it travels. A single trace cannot
show that: it shows a value, and a value on its own says nothing about propagation. So this runs
the compression on a pair and keeps every intermediate from both sides, plus the exclusive-or
between them: the difference itself.

What becomes visible, none of which a table of digests shows:

  the light cone     no difference anywhere until the flipped word enters at its round
  the carry          a difference at one bit position spreading upward inside a sum
  the sigma spread   one bit becoming three at separated positions
  saturation         the round where the difference stops growing because half the bits already
                     differ

No GPU: this is one hash pair.

    python tools/view/build_step_view.py [--bit N]

Writes tools/step_view.html, which is self-contained.
"""

import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "step_view_template.html")
TARGET = os.path.join(HERE, "step_view.html")

MASK = 0xFFFFFFFF

K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
    0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
    0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
    0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
    0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
    0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
    0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
    0xc67178f2,
]

START = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
         0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]

# A real 512-bit message tail, so the trace is of something that occurs and not of zeros.
# Word 3 is what --bit 96 through 127 varies.
TAIL = [0x9d10aa52, 0x4dcc1dd0, 0x1b04864c, 0x9895d4b1]


def rotr(value, by):
    return ((value >> by) | (value << (32 - by))) & MASK


def expand(message):
    words = list(message)
    for slot in range(16, 64):
        two = words[slot - 2]
        fifteen = words[slot - 15]
        low = rotr(fifteen, 7) ^ rotr(fifteen, 18) ^ (fifteen >> 3)
        high = rotr(two, 17) ^ rotr(two, 19) ^ (two >> 10)
        words.append((words[slot - 16] + low + words[slot - 7] + high) & MASK)
    return words


def trace(message):
    """Every intermediate of every round, kept and never discarded."""
    words = expand(message)
    a, b, c, d, e, f, g, h = START
    rounds = []
    for at in range(64):
        big1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)
        ch = g ^ (e & (f ^ g))
        big0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)
        maj = (a & b) | (c & (a ^ b))
        t1 = (h + big1 + ch + K[at] + words[at]) & MASK
        t2 = (big0 + maj) & MASK
        h, g, f = g, f, e
        e = (d + t1) & MASK
        d, c, b = c, b, a
        a = (t1 + t2) & MASK
        rounds.append({
            "W": words[at], "S1": big1, "Ch": ch, "S0": big0, "Maj": maj,
            "T1": t1, "T2": t2,
            "a": a, "b": b, "c": c, "d": d, "e": e, "f": f, "g": g, "h": h,
        })
    return words, rounds


def main():
    flip = 0
    argv = sys.argv[1:]
    if "--bit" in argv:
        flip = int(argv[argv.index("--bit") + 1])

    message = [0] * 16
    message[0], message[1], message[2], message[3] = TAIL
    message[4] = 0x80000000
    message[15] = 640

    other = list(message)
    other[flip // 32] ^= (1 << (flip % 32))

    base_words, base_rounds = trace(message)
    flip_words, flip_rounds = trace(other)

    keys = ["W", "S1", "Ch", "S0", "Maj", "T1", "T2", "a", "b", "c", "d", "e", "f", "g", "h"]
    payload = {
        "flipped": flip,
        "flippedWord": flip // 32,
        "flippedBit": flip % 32,
        "keys": keys,
        "message": message,
        "schedule": {"base": base_words, "flip": flip_words},
        "rounds": [],
    }
    for at in range(64):
        payload["rounds"].append({
            "base": [base_rounds[at][k] for k in keys],
            "flip": [flip_rounds[at][k] for k in keys],
        })

    with io.open(TEMPLATE, encoding="utf-8") as handle:
        page = handle.read()

    # A template whose script tag is never closed still runs when the file is opened directly,
    # because nothing follows the script to get swallowed. Published, the wrapper's closing tags
    # land inside the unterminated script, where they are a JavaScript syntax error, and the whole
    # page is dead. That failure is invisible from here, so refuse to write it.
    if "</script>" not in page:
        raise SystemExit("template is truncated: the script tag is never closed")

    page = page.replace("/*STEP_DATA*/null", json.dumps(payload, separators=(",", ":")))

    with io.open(TARGET, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)

    weights = [bin(base_rounds[at]["a"] ^ flip_rounds[at]["a"]).count("1") for at in range(64)]
    first = next((at for at in range(64) if weights[at]), None)
    print("wrote %s (%.1f KB)" % (os.path.relpath(TARGET, os.path.dirname(os.path.dirname(HERE))),
                                  os.path.getsize(TARGET) / 1024.0))
    print("  flipped input bit %d, which is word %d bit %d"
          % (flip, flip // 32, flip % 32))
    print("  a first differs at round %s" % (first if first is not None else "never"))
    print("  difference weight in a, rounds 0-11: %s" % weights[:12])
    return 0


if __name__ == "__main__":
    sys.exit(main())
