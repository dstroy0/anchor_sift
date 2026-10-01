"""SHA-256 running, inside the room, on its own operation clock with time as the radius.

    python tools/view/build_sha_clock_view.py
    python tools/view/build_sha_clock_view.py --message "abc" --rounds 16
    python tools/view/build_sha_clock_view.py --glow random --shell dodecahedron

  --message   the block to compress. Default the empty message, padded.
  --rounds    how many of the 64 rounds are traced. Default 64.
  --glow      luminosity: value, random, or flat. Default value.
  --seed      the draw behind --glow random. Default 4.
  --degrees   highest harmonic degree the boundary is expanded to. Default 10.
  --tau       conduction time the surface is left to smooth for. Default 0.0008.
  --sources   how many neutrino points are carried, 1 to 12. Default 2.
  --shell     the room wall: sphere, cube, hexagon, octahedron, dodecahedron. Default sphere.
  --core      the nested boundaries: sphere, cube, octahedron, cone. Default sphere.
  --out       where to write. Default sha_clock_view.html beside this script.

WHAT IS BEING WATCHED

The operation, and not a summary of it. The other SHA pages here read a finished measurement: a
dependency field, a leak per output bit, a spectrum. This one runs the compression function and
draws the state while it is still moving, one operation at a time, at whatever rate the reader sets.

The working state is eight words of thirty-two bits. Each word is drawn as a ring of thirty-two
bodies and the eight rings are stacked as eight latitudes, so the whole live state is two hundred
and fifty-six bodies on one globe. A body is a bit. It is lit when the bit is set.

TIME IS THE RADIUS

The globe is not a fixed size. Its radius is the clock, so the state starts small near the middle
and inflates outward as the computation runs, reaching the shell at the last operation traced. The
reader standing still therefore has the computation arrive at them and pass, and where they are
standing decides which part of the run they are inside of. Depth in this room has meant distance
from a boundary on every other page; here it is time, and it is the same axis the round-depth
experiment puts the leak against.

THE SPIN

SHA-256's mixing is rotations. Sigma1 reads e as three rotations by 6, 11 and 25 and exclusive-ors
them; Sigma0 reads a by 2, 13 and 22. Drawn as rings those are literal spins, and a rotation
operation turns the ring it reads through each of its three amounts before the result settles. That
is the operation itself and not an illustration of it: the bit that ends up in position j came from
position j plus the rotate, and the ring turning is that sentence.

Once a round, at the last operation, the register shifts: b takes a, c takes b, d takes c, f takes
e, g takes f, h takes g. Eight rings turning through each other, once per round, sixty-four times.

THE SERIALISATION

The reference round assigns its eight words at once. Watching it that way there is nothing to watch,
so the round is written out in the order the arithmetic actually forces:

    0  Sigma1(e)                       reads e, spins it by 6, 11, 25
    1  Ch(e, f, g)                     reads e, f, g
    2  T1 = h + Sigma1 + Ch + K + W    reads h, and the round's key and schedule word
    3  Sigma0(a)                       reads a, spins it by 2, 13, 22
    4  Maj(a, b, c)                    reads a, b, c
    5  T2 = Sigma0 + Maj
    6  e = d + T1                      writes e
    7  a = T1 + T2, and the register shifts

Nothing is reordered and nothing is skipped. Operation 6 writes exactly d + T1, the new e,
and operation 7 writes T1 + T2 and moves the six carried words, using the values they held before
the write. The digest that falls out at the end is the digest, and the run prints it so that can be
checked against any other implementation and not taken on trust.

WHAT LUMINOSITY IS NOT

Brightness is a free channel and carries no reading. What stops the carried beam is the bit being
set, what casts the shadow is the stopping, and the pattern on the wall is the state. So --glow
random is offered next to the measured one: turn the brightness over to a draw, watch the shadows
stay exactly where they were, and the pattern on the wall is not something the shading put there.
"""

import io
import json
import math
import os
import sys

import settings
import out_path
import sphere_field

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "room_view_template.html")

MASK = 0xFFFFFFFF
WORDS = 8
WIDTH = 32
BITS = WORDS * WIDTH

SHELLS = ("sphere", "cube", "hexagon", "octahedron", "dodecahedron")
CORES = ("sphere", "cube", "octahedron", "cone")
GLOWS = ("value", "random", "flat")

NAMES = ("a", "b", "c", "d", "e", "f", "g", "h")

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

# The range of depths the room splits into bands, and the depth the state is held at inside it.
#
# HOLD is a single number. The state is eight words of thirty-two bits at every operation, so its
# size carries no information and must not move. Depth stays a setting because the boundary reading
# is taken against it, but the reader sets it and the clock never touches it.
INNER = 0.12
OUTER = 0.82

# Inside the first boundary. The room splits the shell into three, so the innermost surface sits at
# a third of it, and the state and the envelope drawn around the state both have to fit within that
# surface. At 0.62 the state sat at twice the first boundary's radius and its envelope crossed the
# second, which put the object outside the boundary it is meant to be read on.
HOLD = 0.22


def draw(seed):
    """The same small generator the other tools here use, so one seed means one room."""
    state = (seed ^ 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
    while True:
        state = (state * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
        yield ((state >> 11) & 0x1FFFFFFFFFFFFF) / float(1 << 53)


def rotate(value, by):
    return ((value >> by) | (value << (WIDTH - by))) & MASK


def padded(message):
    """The one-block padding, refused and not truncated when the message will not fit.

    A block is 512 bits and the padding costs a one bit, the length as 64 bits, and the zeroes
    between, so 55 bytes is the most that fits in one block. Longer messages need the chaining of a
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


def as_bits(state):
    """The eight words as one string of 256 characters, word by word, most significant bit first."""
    out = []
    for word in state:
        for shift in range(WIDTH - 1, -1, -1):
            out.append("1" if (word >> shift) & 1 else "0")
    return "".join(out)


def trace(block, rounds):
    """Runs the compression function and records the state after every single operation.

    The round is serialised exactly as STEPS describes it and no value is invented along the way:
    operation six writes d + T1, the new e, and operation seven writes T1 + T2 and moves
    the six carried words using the values they held before that write. Running the whole thing and
    reading the digest off the end is what checks that, and main prints it.
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
            frames.append(as_bits(state))

    digest = [(H0[at] + state[at]) & MASK for at in range(WORDS)]
    return frames, digest


def distinct(frames):
    """The states the run actually passes through, and the tick to state map.

    Six of the eight operations in a round form temporaries and leave the eight words alone, and a
    trace of five hundred and twelve operations holds about a hundred and thirty different states
    and four hundred repeats of them. Shipping the repeats would be shipping the same string four
    times over, and the harmonic expansion below would be computed four times for the same input.
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


def harmonic_basis(top):
    """The real harmonics at each of the 256 bit directions, evaluated once.

    A direction belongs to a bit and never to a state, so this is computed here and reused for
    every state and not recomputed inside the sum. It is the difference between evaluating the
    basis a hundred and thirty times over and evaluating it once.
    """
    rows = []
    for word in range(WORDS):
        for bit in range(WIDTH):
            down = math.pi * (word + 0.5) / float(WORDS)
            around = 2.0 * math.pi * bit / float(WIDTH)
            table = sphere_field.harmonics_at(top, down, around)
            rows.append([value for degree in table for value in degree])
    return rows


def expand(states, basis, top):
    """The depth-free harmonic coefficients of each state, as one flat list per state.

    Every bit sits at the same radius at a given operation, because the radius is the clock. The
    kernel is diagonal in degree, so the whole depth dependence is one factor per degree that
    multiplies every coefficient of that degree. Leaving it out here and applying it in the page is
    not an approximation: it is the same product, formed where the radius is known. The page can
    then move the depth and the degree ceiling while the reader watches, and it is the reading.
    """
    width = (top + 1) * (top + 1)
    out = []
    for frame in states:
        total = [0.0] * width
        for at in range(BITS):
            if frame[at] != "1":
                continue
            row = basis[at]
            for slot in range(width):
                total[slot] += row[slot]
        out.append([round(one, 6) for one in total])
    return out


def ring(word, bit):
    """A direction for this bit: its word chooses a latitude, its position chooses the angle.

    Eight rings of thirty-two on one globe. The latitudes are the interiors of the eight equal
    bands, so no ring lands on a pole where thirty-two bodies would pile into one place, and the
    rings stay evenly spaced in angle and not in height.
    """
    down = math.pi * (word + 0.5) / float(WORDS)
    around = 2.0 * math.pi * bit / float(WIDTH)
    across = math.sin(down)
    return (across * math.cos(around), math.cos(down), across * math.sin(around))


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
    glow = option("--glow", "value")
    seed = option("--seed", 4, int)
    shell = option("--shell", "sphere")
    core = option("--core", "sphere")
    points = option("--sources", 2, int)
    top = option("--degrees", 10, int)
    tau = option("--tau", 0.0008, float)

    # Checked here and never left to the page. An unknown word reaches the page as a word it does
    # not recognise, the page falls through to its own default, and the caller gets a sphere while
    # having asked for something else with no message anywhere saying so.
    if glow not in GLOWS:
        sys.stderr.write("--glow takes one of: %s\n" % ", ".join(GLOWS))
        return 2
    if shell not in SHELLS:
        sys.stderr.write("--shell takes one of: %s\n" % ", ".join(SHELLS))
        return 2
    if core not in CORES:
        sys.stderr.write("--core takes one of: %s\n" % ", ".join(CORES))
        return 2
    if rounds < 1 or rounds > 64:
        sys.stderr.write("--rounds sits between 1 and 64\n")
        return 2
    # One source cannot give depth and twelve share the light budget twelve ways. Both ends are
    # allowed and the reader is told what they cost instead of being kept from the choice.
    if points < 1 or points > 12:
        sys.stderr.write("--sources sits between 1 and 12\n")
        return 2
    # The rings are eight latitudes of thirty-two, so degree 16 is the finest structure the
    # placement can carry in longitude and degree 8 the finest in latitude. Past that the expansion
    # is fitting the layout and not the state, and the page would show detail nothing put there.
    if top < 1 or top > 16:
        sys.stderr.write("--degrees sits between 1 and 16 for this layout\n")
        return 2

    block = padded(message.encode("utf-8"))
    if block is None:
        sys.stderr.write("--message has to fit one block, which is 55 bytes at most\n")
        return 2

    frames, digest = trace(block, rounds)
    ticks = len(frames)
    states, index = distinct(frames)
    coefficients = expand(states, harmonic_basis(top), top)

    stream = draw(seed)
    things = []
    for word in range(WORDS):
        for bit in range(WIDTH):
            unit = ring(word, bit)
            where = word * WIDTH + bit
            if glow == "random":
                lit = round(next(stream), 4)
            elif glow == "flat":
                lit = 0.5
            else:
                lit = 0.0
            things.append({
                "index": where,
                "word": NAMES[word],
                "bit": bit,
                # The place the page starts it at. The clock rewrites the radius every tick and the
                # ring angle every spin, so this is an opening position and not the body's home.
                "at": [round(unit[0] * INNER, 5),
                       round(unit[1] * INNER, 5),
                       round(unit[2] * INNER, 5)],
                # Still. A bit goes where the operation puts it and never anywhere on its own, so
                # the drift the drawn room gives its population would be a lie about this one.
                "vel": [0.0, 0.0, 0.0],
                # Small enough that the winding stays visible. At twice this the halos of adjacent
                # bits overlap, the turns merge into a band of blobs, and the helix the placement
                # exists to show is the first thing lost.
                "size": 0.007,
                "stops": 0.5,
                "glow": lit,
            })

    steps = [{"label": one[0], "reads": list(one[1]), "writes": list(one[2]),
              "spins": one[3], "by": list(one[4])} for one in STEPS]

    payload = {
        "shell": shell,
        "core": core,
        "sources": points,
        "source": "sha-256 compressing %s, %d rounds"
                  % ("the empty message" if not message else repr(message), rounds),
        "things": things,
        "clock": {
            "ticks": ticks,
            "rounds": rounds,
            "ops": OPS,
            "words": WORDS,
            "width": WIDTH,
            "inner": INNER,
            "outer": OUTER,
            "hold": HOLD,
            "names": list(NAMES),
            "steps": steps,
            "glow": glow,
            "states": states,
            "index": index,
            "degrees": top,
            "tau": tau,
            "harmonics": coefficients,
            "digest": "".join("%08x" % one for one in digest),
        },
        "settings": opening,
    }

    with io.open(TEMPLATE, encoding="utf-8") as handle:
        page = handle.read()
    if "/*ROOM_DATA*/null" not in page:
        sys.stderr.write("the template has no place to put the data\n")
        return 1
    page = page.replace("/*ROOM_DATA*/null", json.dumps(payload, separators=(",", ":")))
    if page.count("</script>") < page.count("<script"):
        sys.stderr.write("the template left a script open, so the page would not run\n")
        return 1

    out = out_path.resolve("sha_clock_view.html", option("--out", None))
    with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)

    # The digest, printed so the trace can be checked against any other implementation and not
    # taken on trust. At the full sixty-four rounds on the empty message this is the published one.
    print("%s (%.1f KB)" % (out, os.path.getsize(out) / 1024.0))
    print("  %d bits on %d rings, %d operations over %d rounds"
          % (BITS, WORDS, ticks, rounds))
    print("  luminosity %s, %d neutrino points, time runs %.2f to %.2f of the shell"
          % (glow, points, INNER, OUTER))
    print("  %d distinct states of %d operations, expanded to degree %d, tau %g"
          % (len(states), ticks, top, tau))
    print("  digest after %d rounds: %s" % (rounds, payload["clock"]["digest"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
