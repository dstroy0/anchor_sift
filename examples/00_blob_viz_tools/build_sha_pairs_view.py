"""SHA-256's 256 output bits as 128 antipodal pairs, each pair a line through the center.

    python examples/00_blob_viz_tools/build_sha_pairs_view.py
    python examples/00_blob_viz_tools/build_sha_pairs_view.py --message "abc"
    python examples/00_blob_viz_tools/build_sha_pairs_view.py --out somewhere.html

  --message   the block to compress. Default the empty message, padded.
  --out       where to write. Default sha_pairs_view.html beside this script.

WHAT IS DRAWN

The 256 output bits are placed on a sphere as 128 pairs. A pair is a bit and its antipode: the two
sit at exactly opposite directions, so the line joining them is a diameter and passes through the
center exactly. Nothing else goes into the construction. A generic spiral does not have this, so the
placement is built to have it instead of hoped into it: 128 base directions are laid on a Fibonacci
spiral, and bit k rides the direction while bit k + 128 rides its negative.

THE LINE IS THE PAIR

Each line carries the joint state of its two bits, as a pair superposed comes to:

    both set     the whole diameter is hot
    both clear   the whole diameter is cold
    one and one  a gradient down the line, hot at the set end and cold at the clear end

A line is not an edge between two markers. It is the two bits read as one thing, and the mixed
case is drawn as the mix and not as a color chosen for it.

TRACKING THE PAIRS

The digest is traced round by round, sixty-four frames of two hundred and fifty-six bits, and the
slider steps them. A pair that flips as the round advances is a pair the computation is still
moving, and one that has settled has settled. At the last round the trace is the digest, printed so
it can be checked against any other implementation and not taken on trust.
"""

import io
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import out_path

TEMPLATE = os.path.join(HERE, "pairs_view_template.html")

MASK = 0xFFFFFFFF
GOLDEN = math.pi * (3.0 - math.sqrt(5.0))

K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]

H0 = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]


def rotate(value, by):
    return ((value >> by) | (value << (32 - by))) & MASK


def padded(message):
    """The one-block padding, or None where the message will not fit one block."""
    if len(message) > 55:
        return None
    bits = len(message) * 8
    data = bytearray(message)
    data.append(0x80)
    while len(data) < 56:
        data.append(0)
    for shift in range(56, -1, -8):
        data.append((bits >> shift) & 0xFF)
    return [int.from_bytes(bytes(data[at:at + 4]), "big") for at in range(0, 64, 4)]


def digest_after(block, rounds):
    """The 256 output bits after this many rounds, most significant first, as a bit string."""
    words = list(block)
    for at in range(16, 64):
        low = words[at - 15]
        high = words[at - 2]
        s0 = rotate(low, 7) ^ rotate(low, 18) ^ (low >> 3)
        s1 = rotate(high, 17) ^ rotate(high, 19) ^ (high >> 10)
        words.append((words[at - 16] + s0 + words[at - 7] + s1) & MASK)

    a, b, c, d, e, f, g, h = H0
    for at in range(rounds):
        s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
        choose = (e & f) ^ (~e & g)
        temp1 = (h + s1 + choose + K[at] + words[at]) & MASK
        s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
        major = (a & b) ^ (a & c) ^ (b & c)
        temp2 = (s0 + major) & MASK
        h, g, f, e, d, c, b, a = g, f, e, (d + temp1) & MASK, c, b, a, (temp1 + temp2) & MASK

    out = [(H0[at] + [a, b, c, d, e, f, g, h][at]) & MASK for at in range(8)]
    text = []
    for word in out:
        for shift in range(31, -1, -1):
            text.append("1" if (word >> shift) & 1 else "0")
    return "".join(text), out


def pairs():
    """128 antipodal pairs. Bit k rides a Fibonacci direction, bit k + 128 rides its negative.

    The directions are laid over 128 and never over 256, because the antipode of each is the other
    half of the 256. Laying 256 directions and hoping the halves face off is what does not land on
    the center; giving each of 128 a partner at its exact negative does.
    """
    out = []
    for k in range(128):
        height = 1.0 - 2.0 * (k + 0.5) / 128.0
        around = k * GOLDEN
        flat = math.sqrt(max(0.0, 1.0 - height * height))
        direction = [flat * math.cos(around), height, flat * math.sin(around)]
        out.append({
            "a": k,
            "b": k + 128,
            "dir": [round(one, 5) for one in direction],
        })
    return out


def main():
    argv = sys.argv[1:]
    if "--help" in argv or "-h" in argv:
        sys.stdout.write(__doc__)
        return 2

    def option(flag, fallback):
        if flag in argv:
            return argv[argv.index(flag) + 1]
        return fallback

    message = option("--message", "")
    block = padded(message.encode("utf-8"))
    if block is None:
        sys.stderr.write("--message has to fit one block, which is 55 bytes at most\n")
        return 2

    frames = []
    digest = ""
    words = None
    for rounds in range(1, 65):
        text, words = digest_after(block, rounds)
        frames.append(text)
    digest = "".join("%08x" % one for one in words)

    payload = {
        "pairs": pairs(),
        "frames": frames,
        "digest": digest,
        "source": "sha-256 compressing %s" % ("the empty message" if not message else repr(message)),
    }

    with io.open(TEMPLATE, encoding="utf-8") as handle:
        page = handle.read()
    if "/*PAIRS_DATA*/null" not in page:
        sys.stderr.write("the template has no place to put the data\n")
        return 1
    page = page.replace("/*PAIRS_DATA*/null", json.dumps(payload, separators=(",", ":")))
    if page.count("</script>") < page.count("<script"):
        sys.stderr.write("the template left a script open, so the page would not run\n")
        return 1

    out = out_path.resolve("sha_pairs_view.html", option("--out", None))
    with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)

    print("%s (%.1f KB)" % (out, os.path.getsize(out) / 1024.0))
    print("  256 bits as 128 antipodal pairs, each a diameter through the center")
    print("  64 rounds traced, %s" % payload["source"])
    print("  digest: %s" % digest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
