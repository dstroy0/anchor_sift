"""Puts the measured SHA-256 dependency field inside the room, as a solid you stand within.

    python tools/view/build_sha_room_view.py
    python tools/view/build_sha_room_view.py --field inbit --every 16
    python tools/view/build_sha_room_view.py --glow random --shell dodecahedron

  --field     which cut of the field: outbit, inbit, residue, word. Default outbit.
  --every     keep one direction in this many, to hold the body count down. Default 8.
  --rounds    how many of the 64 rounds are carried out from the center. Default 64.
  --glow      luminosity: measured, random, or flat. Default measured.
  --seed      the draw behind --glow random. Default 4.
  --shell     the room wall: sphere, cube, hexagon, octahedron, dodecahedron. Default sphere.
  --core      the nested boundaries: sphere, cube, octahedron, cone. Default sphere.
  --source    the bench dump to read. Default src/bench/shadows.csv.
  --out       where to write. Default sha_room_view.html beside this script.

WHAT THE OBJECT IS

The voxel view already builds this field as a solid: a terrain with the rounds along one axis, the
cut along the other, and the deviation as height. It is read from outside, the way a terrain is.
This is the same measured numbers under a different transform, one that has no outside to stand at.

Every cell of the field becomes a body hanging in the room:

  direction   from the index within the cut, spread over the sphere by the golden angle, and it is
              the placement build_sha_sphere_view.py uses, and a bit sits the same way on both pages.
  radius      from the round. Round one sits near the middle and round sixty-four out at the shell,
              because a round is how far the input has travelled and radius is how far out it got.
  stopping    from the size of the deviation, on a log scale, since the field spans eight decades
              between a pinned cell and a noise cell and a linear scale shows one of them.

Putting the round on the radius makes the shape worth walking into. In the terrain the
causal cone is a staircase along an edge. Here it is a ball: a cell outside the cone is pinned
because the input has not reached it yet, and every direction reaches its cone edge at the same
round, so the pinned region closes into a bright solid with a sharp surface at that radius. That
surface is the thing to look at, and you can stand inside it or outside it.

WHY THE DEFAULT ENERGY IS THE READING

A body stops the beam where its stopping power is above the beam's energy, and the room opens at
0.34. The log scale is set so that a cell at the noise level lands just under that and a cell inside the
cone lands well over it. So on opening, the bodies casting shadows on the wall are the ones inside
the causal cone and the rest are passing lights that cast nothing. The shadow pattern is the cone.
Raising the energy eats it from the outside in, and the round at which the wall goes dark is the
round at which this dump stopped being able to tell the function from flat.

WHAT LUMINOSITY IS NOT

Luminosity is a free channel here and carries no measurement. In the room a body's brightness feeds
the color it is drawn in, alone: what stops the beam is the stopping power, what casts
the shadow is the stopping power, and the reading is the shadow. So --glow random is offered
alongside the measured one and the picture on the wall is unchanged by the choice. That is worth
being able to check and not assert, and the flag is there: turn the brightness over to a
draw, watch the shadows stay where they were, and the shape on the wall is not a thing the shading
put there.
"""

import csv
import io
import json
import math
import os
import sys

import out_path
import settings

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SOURCE = os.path.join(ROOT, "src", "bench", "shadows.csv")
TEMPLATE = os.path.join(HERE, "room_view_template.html")

GOLDEN = math.pi * (3.0 - math.sqrt(5.0))

ROUNDS = 64

# How many rows each cut of the field has, and how a row is addressed in the dump. The word cut
# arrives as sixteen message words against eight state variables and is flattened to one axis here,
# the same way the voxel view flattens it, so every cut is a list of series over the rounds.
CUTS = {
    "residue": 32,
    "outbit": 256,
    "inbit": 512,
    "word": 128,
}

SHELLS = ("sphere", "cube", "hexagon", "octahedron", "dodecahedron")
CORES = ("sphere", "cube", "octahedron", "cone")
GLOWS = ("measured", "random", "flat")

# The band the template divides bodies among is taken from the radius, over this drawn range. Held
# here so the rounds fill the range exactly instead of landing inside part of it, which would leave
# an empty middle and an empty rim that mean nothing.
INNER = 0.12
OUTER = 0.82

# A pinned cell reads about 1.3e8 and a noise cell about 1e2, so the field is read as a decade count
# and never as a value. The floor is one standard error: below it there is nothing to grade, and
# without it a cell that came back at zero takes the logarithm to minus infinity.
FLOOR = 1.0


def draw(seed):
    """The same small generator the other tools here use, so one seed means one room."""
    state = (seed ^ 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
    while True:
        state = (state * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
        yield ((state >> 11) & 0x1FFFFFFFFFFFFF) / float(1 << 53)


def read_field(path, want):
    """Reads one cut of the bench dump into a dense table indexed [row][round].

    The dump carries every cut in one file and names each row by kind, so the whole file is walked
    once and the rows that are not wanted are dropped as they arrive. A round is stored one-based in
    the dump and zero-based here.
    """
    rows = [[0.0] * ROUNDS for _ in range(CUTS[want])]
    seen = 0

    with io.open(path, newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            if row["kind"] != want:
                continue
            first = int(row["a"])
            second = int(row["b"])
            at = int(row["round"]) - 1
            if at < 0 or at >= ROUNDS:
                continue
            where = first * 8 + second if want == "word" else first
            if where >= CUTS[want]:
                continue
            rows[where][at] = float(row["value"])
            seen += 1

    return rows, seen


def direction(index, total):
    """A direction for this row of the cut, spread over the sphere by the golden angle.

    Even over the sphere and not even over the angles. Stepping the two angles on a grid crowds the
    poles, and a crowded pole in a room reads as a real feature of the field and not as the
    placement, the single thing the placement must not do.
    """
    height = 1.0 - 2.0 * (index + 0.5) / float(total)
    around = (index * GOLDEN) % (2.0 * math.pi)
    flat = math.sqrt(max(0.0, 1.0 - height * height))
    return (flat * math.cos(around), height, flat * math.sin(around))


def decades(value, top):
    """The size of a deviation as a fraction of the widest decade span in this dump.

    The field runs from a cell pinned at about 1.3e8 down to a cell sitting in noise at about 1e2,
    which is eight decades. Read linearly, every cell outside the first few rounds is zero and the
    object is a bright speck in an empty ball. Read as a decade count, the cone and the noise are
    both visible and the fall between them is the shape.
    """
    return math.log10(max(abs(value), FLOOR)) / top


def build(rows, args):
    """One body per cell of the field, placed by round and direction and graded by deviation."""
    total = len(rows)
    carried = args["rounds"]
    stream = draw(args["seed"])

    widest = FLOOR
    for series in rows:
        for value in series[:carried]:
            if abs(value) > widest:
                widest = abs(value)
    top = math.log10(widest) or 1.0

    things = []
    index = 0
    for where in range(0, total, args["every"]):
        unit = direction(where, total)
        for at in range(carried):
            value = rows[where][at]
            strength = decades(value, top)

            # The round is the radius. Round one near the middle, the last round carried out at the
            # shell, and the whole drawn range filled so the template divides them among its
            # boundaries by where they actually fall.
            part = 0.0 if carried < 2 else at / float(carried - 1)
            deep = INNER + (OUTER - INNER) * part

            # Sized by strength as well as graded by it. A pinned cell is a body and a noise cell is
            # a speck, so the cone has a volume to it instead of being a color change across a
            # cloud of one size.
            size = 0.005 + 0.013 * strength

            if args["glow"] == "random":
                glow = round(next(stream), 4)
            elif args["glow"] == "flat":
                glow = 0.5
            else:
                glow = round(strength, 4)

            things.append({
                "index": index,
                "row": where,
                "round": at + 1,
                "value": round(value, 3),
                "at": [round(unit[0] * deep, 5),
                       round(unit[1] * deep, 5),
                       round(unit[2] * deep, 5)],
                # Still, and never drifting. The bodies in the drawn room are a population that goes
                # where it goes; these are measurements that were taken at a place. A cell that
                # wandered off its radius would be reporting a round it was not measured at, and the
                # cone would smear away over the first few seconds the page was left open.
                "vel": [0.0, 0.0, 0.0],
                "size": round(size, 5),
                "stops": round(0.10 + 0.88 * strength, 4),
                "glow": glow,
            })
            index += 1

    return things, top


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

    field = option("--field", "outbit")
    every = option("--every", 8, int)
    carried = option("--rounds", ROUNDS, int)
    glow = option("--glow", "measured")
    seed = option("--seed", 4, int)
    shell = option("--shell", "sphere")
    core = option("--core", "sphere")
    source = option("--source", SOURCE)

    # Checked here and never left to the page. An unknown word reaches the page as a word it does
    # not recognise, the page falls through to its own default, and the caller gets a sphere while
    # having asked for something else with no message anywhere saying so.
    if field not in CUTS:
        sys.stderr.write("--field takes one of: %s\n" % ", ".join(sorted(CUTS)))
        return 2
    if glow not in GLOWS:
        sys.stderr.write("--glow takes one of: %s\n" % ", ".join(GLOWS))
        return 2
    if shell not in SHELLS:
        sys.stderr.write("--shell takes one of: %s\n" % ", ".join(SHELLS))
        return 2
    if core not in CORES:
        sys.stderr.write("--core takes one of: %s\n" % ", ".join(CORES))
        return 2
    if carried < 2 or carried > ROUNDS:
        sys.stderr.write("--rounds sits between 2 and %d\n" % ROUNDS)
        return 2
    if every < 1 or every > CUTS[field]:
        sys.stderr.write("--every sits between 1 and %d for this cut\n" % CUTS[field])
        return 2

    if not os.path.exists(source):
        sys.stderr.write("no %s yet - run: src/bench/bench_sac.exe 18 45 64 shadow\n" % source)
        return 1

    rows, seen = read_field(source, field)
    if not seen:
        sys.stderr.write("%s carries no %s rows\n" % (source, field))
        return 1

    things, top = build(rows, {
        "every": every, "rounds": carried, "glow": glow, "seed": seed,
    })

    # A body count large enough to stall the page is worth refusing instead of shipping. The room
    # walks every body once a frame and renders the casters again for each face of each source's
    # shadow cube, so the cost is real and it lands on the reader and not here.
    if len(things) > 6000:
        sys.stderr.write("that is %d bodies, which will not run. raise --every\n" % len(things))
        return 2

    payload = {
        "shell": shell,
        "core": core,
        "source": "sha-256 %s field, %d rounds, %s luminosity" % (field, carried, glow),
        "things": things,
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

    out = out_path.resolve("sha_room_view.html", option("--out", None))
    with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)

    # The round the shadows stop at, read off the same numbers the page was built from and printed
    # so what it drew is printed. A caller who never opens the page still gets the reading.
    energy = 0.34
    lit = [one["round"] for one in things if one["stops"] > energy]
    edge = max(lit) if lit else 0

    print("%s (%.1f KB)" % (out, os.path.getsize(out) / 1024.0))
    print("  %d bodies from the %s field, one per cell, %d directions over %d rounds"
          % (len(things), field, len(range(0, CUTS[field], every)), carried))
    print("  field spans %.2f decades, luminosity %s" % (top, glow))
    print("  at the opening energy %.2f, %d of them cast a shadow, out to round %d"
          % (energy, len(lit), edge))
    return 0


if __name__ == "__main__":
    sys.exit(main())
