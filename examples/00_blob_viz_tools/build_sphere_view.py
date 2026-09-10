"""Writes a blob onto the inside of a scattering ball and shows what reaches the surface.

    python tools/view/build_sphere_view.py file.bin
    python tools/view/build_sphere_view.py file.bin --place pair --heat rare --degrees 48

  --place     how a symbol gets a direction: spread, random, spiral, pair. Default pair.
  --heat      rare for surprisal per event, total for surprisal times how often. Default rare.
  --depth     rare to put rare symbols near the shell, flat to put every symbol at one radius.
  --radius    the one radius flat depth uses, 0.05 to 0.99. Default 0.75.
  --degrees   highest harmonic degree carried. Default 48.
  --tau       conduction time the surface is left to smooth for. Default 0.0008.
  --bytes     how many bytes to read. Default 262144. Use 0 for the whole file.
  --offset    first byte to read. Default 0.
  --title     heading for the page. Default: the file's name.
  --out       where to write. Default: <name>_sphere.html beside the blob.

WHAT IS ON THE PAGE

Each distinct byte becomes a source inside the ball. Its heat is the surprisal of that byte in this
file, in bits, and a byte that fills the file deposits nothing and a byte seen once deposits log2 of
the length. Its depth is set the same way, which puts rare symbols near the shell where they print
small circles and common ones deep where they print wide ones.

The surface carries the sum. A circle on it is one symbol, its size is that symbol's depth, and its
temperature is that symbol's rareness. Two circles that meet are two symbols the surface can no
longer tell apart at the level the edge is being read at.

WHY BOTH A MAP AND A NULL ARE ALWAYS SHIPPED

A symbol has a rareness and a depth without anyone choosing anything. It does not have a direction.
Whatever map supplies one is a choice, and structure that map creates looks exactly like structure
the data had. So every page carries the same sources placed at random alongside the chosen map, the
spectra sit on the same axes, and a degree where the map rises above the null is the only place
worth reading. `--place spread` averages the direction away entirely and leaves degree zero, the shape
of a reading with nothing injected.
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


def draw(seed):
    """A small deterministic generator, so the null is the same null on every machine."""
    state = (seed ^ 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
    while True:
        state = (state * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
        yield ((state >> 11) & 0x1FFFFFFFFFFFFF) / float(1 << 53)


def place(kind, values, data):
    """A direction per symbol, by the named map. Returns (colatitude, longitude) per symbol.

    spread  no direction at all, handled later by averaging and not by a value here
    random  drawn from a generator that never sees the data, the null
    spiral  the golden angle walked in byte order, evenly spread and carrying byte adjacency
    pair    colatitude from the symbol and longitude from the byte that most often precedes it
    """
    out = {}
    if kind == "random" or kind == "spread":
        stream = draw(0x5EED)
        for value in values:
            out[value] = (math.acos(2.0 * next(stream) - 1.0), 2.0 * math.pi * next(stream))
        return out

    if kind == "spiral":
        for index, value in enumerate(values):
            height = 1.0 - 2.0 * (index + 0.5) / len(values)
            out[value] = (math.acos(max(-1.0, min(1.0, height))), (index * GOLDEN) % (2.0 * math.pi))
        return out

    # pair. The predecessor is read from the data, so this map carries something the data decided
    # and the spiral does not. Whether it carries anything real is what the null is there to say.
    before = {}
    for at in range(1, len(data)):
        here = data[at]
        counts = before.setdefault(here, {})
        counts[data[at - 1]] = counts.get(data[at - 1], 0) + 1
    for value in values:
        counts = before.get(value, {})
        leader = max(counts, key=counts.get) if counts else value
        out[value] = (math.acos(1.0 - 2.0 * (value + 0.5) / 256.0),
                      2.0 * math.pi * (leader + 0.5) / 256.0)
    return out


def build(data, args):
    """Turns bytes into sources, then into everything the page needs that costs anything."""
    bits, counts = sphere_field.surprisal(data)
    values = [value for value in range(256) if counts[value]]
    if not values:
        sys.stderr.write("no bytes were read, so there is nothing to place\n")
        return None

    hottest = max(bits[value] for value in values) or 1.0
    spots = place(args["place"], values, data)
    nulls = place("random", values, data)

    sources = []
    null_sources = []
    catalog = []
    for value in values:
        heat = bits[value]
        if args["heat"] == "total":
            heat = bits[value] * counts[value]
        if args["depth"] == "flat":
            deep = args["radius"]
        else:
            deep = 0.15 + 0.82 * (bits[value] / hottest)
        colatitude, longitude = spots[value]
        sources.append((heat, deep, colatitude, longitude))
        null_colatitude, null_longitude = nulls[value]
        null_sources.append((heat, deep, null_colatitude, null_longitude))
        catalog.append({
            "value": value,
            "count": counts[value],
            "bits": round(bits[value], 4),
            "heat": round(heat, 4),
            "depth": round(deep, 4),
            "spot": round(sphere_field.spot_radians(deep), 4),
            "colatitude": round(colatitude, 5),
            "longitude": round(longitude, 5),
        })

    top = args["degrees"]
    tau = args["tau"]
    spread = args["place"] == "spread"

    coefficients = sphere_field.coefficients(sources, top, tau, spread=spread)
    spectrum = sphere_field.power(coefficients)
    null_spectrum = sphere_field.power(sphere_field.coefficients(null_sources, top, tau))

    grid = sphere_field.synthesize(coefficients, top, args["latitudes"], args["longitudes"])
    flat = [value for line in grid for value in line]
    low, high = min(flat), max(flat)

    effective, used = sphere_field.read_depth(spectrum, tau)
    modes, reached = sphere_field.live_modes(spectrum, 1e-4)

    # Profiles are shipped so the page can move the edge without recomputing any physics. One per
    # distinct depth and never one per source, since two symbols at the same depth print the same
    # circle and the page was spending its whole budget rebuilding identical tables.
    depths = sorted({round(one[1], 4) for one in sources})
    profiles = {}
    for deep in depths:
        table = sphere_field.zonal_profile(deep, tau, top, 361)
        profiles["%.4f" % deep] = [round(one, 8) for one in table]

    return {
        "title": args["title"],
        "place": args["place"],
        "heat": args["heat"],
        "degrees": top,
        "tau": tau,
        "bytes_read": len(data),
        "symbols": len(values),
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
            "total_bits": round(sum(bits[value] * counts[value] for value in values), 2),
        },
        "settings": args["opening"],
    }


def main():
    argv = sys.argv[1:]
    if not argv or "--help" in argv or "-h" in argv:
        sys.stdout.write(__doc__)
        sys.stdout.write("\n" + settings.usage() + "\n")
        return 2

    opening = settings.collect(argv)

    # Every flag here takes a value, and a bare word is the file only where no flag is waiting for
    # it. Filtering on the leading dash alone reads `--place pair` as a request to open a file
    # called pair, and the message that follows names a file the caller never typed.
    taking = ("--place", "--heat", "--depth", "--radius", "--degrees", "--tau",
              "--bytes", "--offset", "--title", "--out", "--set")
    named = []
    at = 0
    while at < len(argv):
        if argv[at] in taking:
            at += 2
            continue
        if argv[at].startswith("-"):
            at += 1
            continue
        named.append(argv[at])
        at += 1

    if not named:
        sys.stderr.write("name a file to read\n")
        return 2
    path = named[0]

    def option(flag, fallback, cast=str):
        if flag in argv:
            return cast(argv[argv.index(flag) + 1])
        return fallback

    args = {
        "place": option("--place", "pair"),
        "heat": option("--heat", "rare"),
        "depth": option("--depth", "rare"),
        "radius": option("--radius", 0.75, float),
        "degrees": option("--degrees", 48, int),
        "tau": option("--tau", 0.0008, float),
        "latitudes": 96,
        "longitudes": 192,
        "title": option("--title", os.path.basename(path)),
        "opening": opening,
    }
    if args["place"] not in ("spread", "random", "spiral", "pair"):
        sys.stderr.write("--place takes spread, random, spiral or pair\n")
        return 2
    if not 0.0 < args["radius"] < 1.0:
        sys.stderr.write("--radius sits between 0 and 1\n")
        return 2

    span = option("--bytes", 262144, int)
    offset = option("--offset", 0, int)
    with io.open(path, "rb") as handle:
        handle.seek(offset)
        data = handle.read() if span == 0 else handle.read(span)
    if not data:
        sys.stderr.write("read nothing from %s at offset %d\n" % (path, offset))
        return 1

    payload = build(bytearray(data), args)
    if payload is None:
        return 1

    with io.open(TEMPLATE, encoding="utf-8") as handle:
        page = handle.read()
    body = json.dumps(payload, separators=(",", ":"))
    if "/*SPHERE_DATA*/null" not in page:
        sys.stderr.write("the template has no place to put the data\n")
        return 1
    page = page.replace("/*SPHERE_DATA*/null", body)
    if page.count("</script>") < page.count("<script"):
        sys.stderr.write("the template left a script open, so the page would not run\n")
        return 1

    out = option("--out", os.path.splitext(path)[0] + "_sphere.html")
    with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)

    print("%s" % out)
    print("  %d symbols from %d bytes, placed by %s" % (payload["symbols"],
                                                        payload["bytes_read"], args["place"]))
    print("  degrees to %d, conduction %g" % (args["degrees"], args["tau"]))
    print("  effective depth read back at %.3f over %d degrees" % (payload["read"]["depth"],
                                                                   payload["read"]["degrees_used"]))
    print("  %d modes carry anything, reaching degree %d" % (payload["read"]["modes"],
                                                             payload["read"]["reached"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
