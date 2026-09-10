"""Puts SHA-256's compression function inside the ball and reads it round by round.

    python tools/view/build_sha_sphere_view.py
    python tools/view/build_sha_sphere_view.py --rounds 24 --samples 4000
    python tools/view/build_sha_sphere_view.py --sweep

  --rounds    how many of the 64 rounds to run before reading the output. Default 64.
  --samples   how many random blocks to average the avalanche over. Default 3000.
  --place     bit to direction map: spiral or index. Default spiral.
  --tau       conduction time the surface is left to smooth for. Default 0.0008.
  --degrees   highest harmonic degree carried. Default 48.
  --sweep     print the reading at several round counts and write no page.
  --out       where to write. Default sha_sphere.html beside this script.

WHAT IS ON THE SPHERE

Each of the 256 output bits of the compression function is a source. Its heat is how much that bit
still remembers the input: flip one input bit at random, and measure how far that output bit's flip
rate departs from one half. A bit that is a fair coin remembers nothing and is cold. A bit that
leans remembers something and is hot.

Depth is set the same way. A bit that remembers rides near the shell and prints a small sharp
circle. A bit that has forgotten sits deep and prints broad and dim, or nothing. Round count is the
depth in time: the further the input travelled through the rounds, the less of it reaches the
surface, the boundary reading with the number of rounds as the depth axis.

THE NULL

The bit to direction map is a choice, so the same sources are also placed at random and both spectra
are drawn on one set of axes. A degree where the chosen map beats the null is structure in which
bits lean, and not structure the map invented. At full rounds neither should carry anything above
degree zero, and the two curves should lie on each other. That is the reading, whatever it says.
"""

import io
import json
import math
import os
import sys

import settings
import sphere_field

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "sphere_view_template.html")

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

MASK = 0xFFFFFFFF


def rotate(value, by):
    return ((value >> by) | (value << (32 - by))) & MASK


def compress(block, rounds):
    """The SHA-256 compression function, stopped after `rounds` of the sixty-four.

    A standard compression run with the round loop cut short. The schedule is expanded in full
    because a round reads words the schedule has already produced; stopping the rounds is what
    limits the mixing, and no other knob is turned in this study.
    """
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

    state = [a, b, c, d, e, f, g, h]
    out = [(H0[at] + state[at]) & MASK for at in range(8)]
    return out


def digest_bits(words):
    """The 256 output bits, most significant first, as a flat list of 0 and 1."""
    bits = []
    for word in words:
        for shift in range(31, -1, -1):
            bits.append((word >> shift) & 1)
    return bits


def draw(seed):
    state = (seed ^ 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
    while True:
        state = (state * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
        yield (state >> 11) & 0x1FFFFFFFFFFFFF


def avalanche(rounds, samples, seed=1):
    """How far each output bit's flip rate departs from one half, over random inputs.

    Draw a random 512-bit block, flip one of its bits at random, and count which output bits change.
    A fair output bit flips half the time. The departure from half is what that bit still remembers
    of its input, and it is read at whatever round count the compression was stopped at.
    """
    stream = draw(seed)
    flips = [0] * 256
    for _ in range(samples):
        block = [next(stream) & MASK for _ in range(16)]
        which = next(stream) % 512
        twin = list(block)
        twin[which // 32] ^= (1 << (which % 32))

        before = digest_bits(compress(block, rounds))
        after = digest_bits(compress(twin, rounds))
        for at in range(256):
            if before[at] != after[at]:
                flips[at] += 1

    leak = [abs(flips[at] / float(samples) - 0.5) for at in range(256)]
    return leak


def place(kind, seed=0x5EED):
    """A direction per output bit. Spiral spreads them evenly; index stacks them by position."""
    out = []
    if kind == "index":
        for bit in range(256):
            out.append((math.acos(1.0 - 2.0 * (bit + 0.5) / 256.0),
                        2.0 * math.pi * ((bit % 32) / 32.0)))
        return out
    for bit in range(256):
        height = 1.0 - 2.0 * (bit + 0.5) / 256.0
        out.append((math.acos(max(-1.0, min(1.0, height))), (bit * GOLDEN) % (2.0 * math.pi)))
    return out


def random_place(seed):
    stream = draw(seed)
    out = []
    for _ in range(256):
        height = 2.0 * ((next(stream) & 0x1FFFFF) / float(0x200000)) - 1.0
        around = 2.0 * math.pi * ((next(stream) & 0x1FFFFF) / float(0x200000))
        out.append((math.acos(max(-1.0, min(1.0, height))), around))
    return out


def summary(rounds, samples):
    """One line: the leak at this round count, and how far it stands above sampling noise."""
    leak = avalanche(rounds, samples)
    floor = 0.5 / math.sqrt(samples)
    strongest = max(leak)
    mean = sum(leak) / len(leak)
    above = sum(1 for one in leak if one > 3.0 * floor)
    return {"rounds": rounds, "max": strongest, "mean": mean,
            "floor": floor, "above": above}


def build(rounds, samples, args):
    leak = avalanche(rounds, samples)
    hottest = max(leak) or 1.0
    floor = 0.5 / math.sqrt(samples)

    spots = place(args["place"])
    nulls = random_place(0x51A)

    sources = []
    null_sources = []
    catalog = []
    for bit in range(256):
        heat = leak[bit]
        # A bit that remembers rides near the shell; a fair bit sits deep. Scaled to the strongest
        # bit in this run, and a round count with any structure fills the depth range while a round
        # count with none collapses to the middle.
        deep = 0.15 + 0.80 * (leak[bit] / hottest)
        colatitude, longitude = spots[bit]
        sources.append((heat, deep, colatitude, longitude))
        null_colatitude, null_longitude = nulls[bit]
        null_sources.append((heat, deep, null_colatitude, null_longitude))
        catalog.append({
            "value": bit,
            "count": 1,
            "bits": round(heat, 5),
            "heat": round(heat, 5),
            "depth": round(deep, 4),
            "spot": round(sphere_field.spot_radians(deep), 4),
            "colatitude": round(colatitude, 5),
            "longitude": round(longitude, 5),
        })

    top = args["degrees"]
    tau = args["tau"]

    coefficients = sphere_field.coefficients(sources, top, tau)
    spectrum = sphere_field.power(coefficients)
    null_spectrum = sphere_field.power(sphere_field.coefficients(null_sources, top, tau))

    grid = sphere_field.synthesize(coefficients, top, args["latitudes"], args["longitudes"])
    flat = [value for line in grid for value in line]
    low, high = min(flat), max(flat)

    effective, used = sphere_field.read_depth(spectrum, tau)
    modes, reached = sphere_field.live_modes(spectrum, 1e-4)

    depths = sorted({round(one[1], 4) for one in sources})
    profiles = {}
    for deep in depths:
        table = sphere_field.zonal_profile(deep, tau, top, 361)
        profiles["%.4f" % deep] = [round(one, 8) for one in table]

    return {
        "title": "SHA-256 compression, %d of 64 rounds" % rounds,
        "place": "sha %d rounds" % rounds,
        "heat": "bit memory",
        "degrees": top,
        "tau": tau,
        "bytes_read": samples,
        "symbols": 256,
        "grid": {
            "latitudes": args["latitudes"],
            "longitudes": args["longitudes"],
            "low": low,
            "high": high,
            "values": [[round(one, 6) for one in line] for line in grid],
        },
        "spectrum": [round(one, 12) for one in spectrum],
        "null_spectrum": [round(one, 12) for one in null_spectrum],
        "profiles": profiles,
        "sources": catalog,
        "read": {
            "depth": round(effective, 4),
            "degrees_used": used,
            "modes": modes,
            "reached": reached,
            "total_bits": round(sum(leak), 4),
        },
        "settings": args["opening"],
        "floor": round(floor, 6),
    }


def main():
    argv = sys.argv[1:]
    if "--help" in argv or "-h" in argv:
        sys.stdout.write(__doc__)
        return 2

    opening = settings.collect(argv)

    def option(flag, fallback, cast=str):
        if flag in argv:
            return cast(argv[argv.index(flag) + 1])
        return fallback

    samples = option("--samples", 3000, int)
    rounds = option("--rounds", 64, int)

    if "--sweep" in argv:
        print("  round-by-round, %d samples each. floor is 0.5 / sqrt(samples) = %.5f" %
              (samples, 0.5 / math.sqrt(samples)))
        print("")
        print("  %6s %12s %12s %14s" % ("rounds", "max leak", "mean leak", "bits above floor"))
        for count in (8, 12, 16, 20, 24, 28, 32, 40, 48, 64):
            row = summary(count, samples)
            print("  %6d %12.6f %12.6f %14d" %
                  (row["rounds"], row["max"], row["mean"], row["above"]))
        print("")
        print("  a bit above the floor still remembers its input at that round count.")
        print("  at full rounds the honest reading is zero above the floor.")
        return 0

    args = {
        "place": option("--place", "spiral"),
        "tau": option("--tau", 0.0008, float),
        "degrees": option("--degrees", 48, int),
        "latitudes": 96,
        "longitudes": 192,
        "opening": opening,
    }

    payload = build(rounds, samples, args)

    with io.open(TEMPLATE, encoding="utf-8") as handle:
        page = handle.read()
    if "/*SPHERE_DATA*/null" not in page:
        sys.stderr.write("the template has no place to put the data\n")
        return 1
    page = page.replace("/*SPHERE_DATA*/null", json.dumps(payload, separators=(",", ":")))
    if page.count("</script>") < page.count("<script"):
        sys.stderr.write("the template left a script open, so the page would not run\n")
        return 1

    out = option("--out", os.path.join(HERE, "sha_sphere.html"))
    with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)

    print("%s" % out)
    print("  %d of 64 rounds, %d samples, floor %.5f" % (rounds, samples, payload["floor"]))
    print("  strongest bit leak %.5f, %d bits above three floors" %
          (max(one["heat"] for one in payload["sources"]),
           sum(1 for one in payload["sources"] if one["heat"] > 3.0 * payload["floor"])))
    print("  depth read back %.3f over %d degrees, %d modes to degree %d" %
          (payload["read"]["depth"], payload["read"]["degrees_used"],
           payload["read"]["modes"], payload["read"]["reached"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
