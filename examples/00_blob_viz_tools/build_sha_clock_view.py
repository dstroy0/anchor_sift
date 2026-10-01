"""SHA-256 running, one operation at a time, drawn as the engine's own render of its bytes.

    python examples/00_blob_viz_tools/build_sha_clock_view.py
    python examples/00_blob_viz_tools/build_sha_clock_view.py --message "abc" --rounds 16

  --message   the block to compress. Default the empty message, padded.
  --rounds    how many of the 64 rounds are traced. Default 64.
  --out       where to write. Default sha_clock_view.html beside this script.

WHAT IS BEING WATCHED

The operation, and not a summary of it. The other SHA pages here read a finished measurement. This
one runs the compression function and draws the state while it is still moving, one operation at a
time, at whatever rate the reader sets on the clock.

The working state is eight words of thirty-two bits, which is thirty-two bytes. Each distinct state
the run passes through is handed to the engine's own volume renderer on the byte channel: one voxel
per byte, the byte's value, no search and no needle that means anything. The page draws those bytes
and nothing it computed itself. It is what the engine sees of the state, not a second drawing of it.

TIME IS THE CLOCK

The clock scrubs the operations. Six of the eight operations in a round only form temporaries and
leave the eight words alone. The run repeats states, and the distinct ones are rendered once and
replayed by a tick-to-state index. Standing on a tick, the reader sees the state the engine rendered
at that operation.

THE ARM THAT DREW IT

The render prefers the device and falls back to the host, and the two produce the same bytes; the
choice is speed alone. The page names the arm that drew the bytes it carries, taken from the render
call's own answer. The reader then knows whether a device was present when the page was built.

THE SERIALIZATION

The reference round assigns its eight words at once. Watching it that way there is nothing to watch.
The round is written out in the order the arithmetic forces:

    0  Sigma1(e)                       reads e, spins it by 6, 11, 25
    1  Ch(e, f, g)                     reads e, f, g
    2  T1 = h + Sigma1 + Ch + K + W    reads h, and the round's key and schedule word
    3  Sigma0(a)                       reads a, spins it by 2, 13, 22
    4  Maj(a, b, c)                    reads a, b, c
    5  T2 = Sigma0 + Maj
    6  e = d + T1                      writes e
    7  a = T1 + T2, and the register shifts

Nothing is reordered and nothing is skipped. Operation 6 writes exactly d + T1, the new e, and
operation 7 writes T1 + T2 and moves the six carried words, using the values they held before the
write. The digest that falls out at the end is the digest, and the run prints it so it can be
checked against any other implementation and not taken on trust.
"""

import io
import json
import os
import re
import sys

import settings
import out_path

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
TEMPLATE = os.path.join(HERE, "clock_view_template.html")
BAR_SOURCE = os.path.join(HERE, "control_bar.js")

# The render package lives in the engine tree, not beside this tool. It is reached by path and not
# copied. The page draws what the shipped renderer produces and never a transcription of it.
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))
import render

MASK = 0xFFFFFFFF
WORDS = 8
WIDTH = 32
BYTES = WORDS * 4

NAMES = ("a", "b", "c", "d", "e", "f", "g", "h")

# The render extent: one slab per word, each slab the word's four bytes in a row. Thirty-two voxels
# for the thirty-two state bytes, the byte channel carrying each byte's value. SLABS places voxel
# z*4 + x at word z, byte x, matching the order the state is packed in.
EXTENT = render.VolumeConfig(width=4, height=1, depth=WORDS, layout=render.VOLUME_SLABS,
                             channel=render.CHANNEL_BYTE, reduce=render.REDUCE_MAX, gain=1)

# The round written out in the order the arithmetic forces. Each entry is the label the page shows,
# the words the operation reads, the words it writes, and the rotation it turns a ring through.
STEPS = (
    ("Σ1(e)", (4,), (), 4, (6, 11, 25)),
    ("Ch(e, f, g)", (4, 5, 6), (), -1, ()),
    ("T1 = h + Σ1 + Ch + K + W", (7,), (), -1, ()),
    ("Σ0(a)", (0,), (), 0, (2, 13, 22)),
    ("Maj(a, b, c)", (0, 1, 2), (), -1, ()),
    ("T2 = Σ0 + Maj", (), (), -1, ()),
    ("e = d + T1", (3,), (4,), -1, ()),
    ("a = T1 + T2, register shifts", (), (0, 1, 2, 3, 5, 6, 7), -1, ()),
)
OPS = len(STEPS)

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
    return ((value >> by) | (value << (WIDTH - by))) & MASK


def padded(message):
    """The one-block padding, errored and not truncated when the message will not fit.

    A block is 512 bits and the padding costs a one bit, the length as 64 bits, and the zeroes
    between. 55 bytes is the most that fits in one block. Longer messages need the chaining of a
    second block, which is a second compression and not the thing this page draws.
    """
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


def schedule(block):
    """The full sixty-four word message schedule, expanded before any round reads it."""
    words = list(block)
    for at in range(16, 64):
        low = words[at - 15]
        high = words[at - 2]
        s0 = rotate(low, 7) ^ rotate(low, 18) ^ (low >> 3)
        s1 = rotate(high, 17) ^ rotate(high, 19) ^ (high >> 10)
        words.append((words[at - 16] + s0 + words[at - 7] + s1) & MASK)
    return words


def as_corpus(state):
    """The eight words as thirty-two bytes, word by word, most significant byte first.

    This is the corpus the engine renders. A word is four bytes big-endian, and the eight words run
    a through h, matching the order the extent's slabs are read in.
    """
    return b"".join(word.to_bytes(4, "big") for word in state)


def trace(block, rounds):
    """Runs the compression function and records the state after every single operation.

    The round is serialized exactly as STEPS describes it and no value is invented along the way:
    operation six writes d + T1, the new e, and operation seven writes T1 + T2 and moves the six
    carried words using the values they held before that write. Running the whole thing and reading
    the digest off the end is what checks that, and main prints it.
    """
    words = schedule(block)
    state = list(H0)
    frames = []

    for at in range(rounds):
        a, b, c, d, e, f, g, h = state

        s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
        choose = (e & f) ^ (~e & g)
        temp1 = (h + s1 + choose + K[at] + words[at]) & MASK
        s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
        major = (a & b) ^ (a & c) ^ (b & c)
        temp2 = (s0 + major) & MASK

        for op in range(OPS):
            if op == 6:
                state = [a, b, c, d, (d + temp1) & MASK, f, g, h]
            elif op == 7:
                state = [(temp1 + temp2) & MASK, a, b, c, state[4], e, f, g]
            frames.append(as_corpus(state))

    digest = [(H0[at] + state[at]) & MASK for at in range(WORDS)]
    return frames, digest


def distinct(frames):
    """The states the run actually passes through, and the tick-to-state map.

    Six of the eight operations in a round form temporaries and leave the eight words alone, and a
    trace of five hundred and twelve operations holds about a hundred and thirty different states
    and four hundred repeats of them. Rendering the repeats would render the same state four times
    over. The distinct ones are rendered once and the index replays them.
    """
    order = []
    seen = {}
    index = []
    for frame in frames:
        if frame not in seen:
            seen[frame] = len(order)
            order.append(frame)
        index.append(seen[frame])
    return order, index


def render_states(states):
    """Each distinct state rendered by the engine's volume arm, as a list of voxel byte lists.

    The byte channel reads neither the needle nor the probes. The renderer requires a needle of at
    least one byte, and a needle of one byte makes every state byte an alignment. One zero byte is
    passed and no probe. Returns the voxels and the arm that drew them, or None where the render
    errored.
    """
    needle = b"\x00"
    probes = []
    out = []
    arm = None
    for corpus in states:
        rendered = render.render_volume(EXTENT, corpus, needle, probes)
        if rendered.bytes is None:
            return None, None
        out.append(list(rendered.bytes))
        arm = rendered.arm
    return out, arm


def main():
    argv = sys.argv[1:]
    if "--help" in argv or "-h" in argv:
        sys.stdout.write(__doc__)
        sys.stdout.write("\n" + settings.usage() + "\n")
        return 2

    opening = settings.collect(argv)

    def option(flag, fallback, cast=str):
        if flag in argv:
            return cast(argv[argv.index(flag) + 1])
        return fallback

    message = option("--message", "")
    rounds = option("--rounds", 64, int)

    if rounds < 1 or rounds > 64:
        sys.stderr.write("--rounds sits between 1 and 64\n")
        return 2

    block = padded(message.encode("utf-8"))
    if block is None:
        sys.stderr.write("--message has to fit one block, which is 55 bytes at most\n")
        return 2

    frames, digest = trace(block, rounds)
    ticks = len(frames)
    states, index = distinct(frames)
    voxels, arm = render_states(states)
    if voxels is None:
        sys.stderr.write("the renderer errored on a state\n")
        return 1

    steps = [{"label": one[0], "reads": list(one[1]), "writes": list(one[2]),
              "spins": one[3], "by": list(one[4])} for one in STEPS]

    payload = {
        "clock": {
            "ticks": ticks,
            "rounds": rounds,
            "ops": OPS,
            "words": WORDS,
            "names": list(NAMES),
            "steps": steps,
            "index": index,
            "extent": {"width": EXTENT.width, "height": EXTENT.height, "depth": EXTENT.depth},
            "layout": "slabs",
            "channel": "byte",
            "arm": arm,
            "source": "sha-256 compressing %s, %d rounds"
                      % ("the empty message" if not message else repr(message), rounds),
            "states": voxels,
            "digest": "".join("%08x" % one for one in digest),
        },
        "settings": opening,
        # The bar's schema, read from the one settings source. The page draws its appearance controls
        # from these and never a copy written into the template.
        "schema": settings.schema(["background", "opacity"]),
    }

    with io.open(TEMPLATE, encoding="utf-8") as handle:
        page = handle.read()
    place = re.search(r"/\*CLOCK_DATA\*/\s*null", page)
    if place is None:
        sys.stderr.write("the template has no place to put the data\n")
        return 1
    page = page[:place.start()] + json.dumps(payload, separators=(",", ":")) + page[place.end():]

    # The shared control bar is injected whole, keeping the page one self-contained file with one
    # source for the bar across every unit that carries it.
    with io.open(BAR_SOURCE, encoding="utf-8") as handle:
        bar = handle.read()
    slot = re.search(r"/\*CONTROL_BAR\*/", page)
    if slot is None:
        sys.stderr.write("the template has no place for the control bar\n")
        return 1
    page = page[:slot.start()] + bar + page[slot.end():]

    if page.count("</script>") < page.count("<script"):
        sys.stderr.write("the template left a script open. The page would not run\n")
        return 1

    out = out_path.resolve("sha_clock_view.html", option("--out", None))
    with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)

    # The digest, printed so the trace can be checked against any other implementation and not taken
    # on trust. At the full sixty-four rounds on the empty message this is the published one.
    print("%s (%.1f KB)" % (out, os.path.getsize(out) / 1024.0))
    print("  %d bytes on %d words, %d operations over %d rounds, drawn by the %s arm"
          % (BYTES, WORDS, ticks, rounds, arm))
    print("  %d distinct states of %d operations, rendered once and replayed by the index"
          % (len(states), ticks))
    print("  digest after %d rounds: %s" % (rounds, payload["clock"]["digest"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
