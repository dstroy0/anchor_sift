"""A dark room you stand inside, with a beam you carry and things that stop it.

    python tools/view/build_room_view.py
    python tools/view/build_room_view.py --shell cube --things 9 --seed 4
    python tools/view/build_room_view.py --blob firmware.bin

  --shell     the enclosing wall: sphere, cube, hexagon, octahedron, dodecahedron. Default sphere.
  --core      the shell holding the lights: sphere, cube, octahedron, cone. Default cube.
  --things    how many lights hang inside. Default 160.
  --seed      draw for their places, sizes and stopping power. Default 4.
  --blob      take the objects from a file instead of the draw, one per common byte value.
  --out       where to write. Default room_view.html beside this script.

WHAT THIS IS FOR

Everything else here looks at a boundary from outside it. This puts the reader inside, because the
outside of one shell is the inside of the next one and there is no vantage point that is not inside
something. Zooming in far enough passes through the inner shell and leaves you among the objects.
Zooming out far enough puts the inner shell behind you and leaves you inside the room.

THE BEAM

The light is carried, not fixed. Moving it sweeps the shadows across the wall, and a shadow that
sweeps is worth more than a shadow that sits: two objects that overlap from one place separate from
the next, and the rate a shadow moves against the wall gives the depth of the thing casting it.

Objects have a stopping power apiece and the beam has an energy. An object stops the beam where its
stopping power is above that energy, so turning the energy up switches shadows off one at a time,
weakest first. That is the only honest way to draw a probe that mostly passes through: a surface is
opaque to a neutron most of the time and to a neutrino almost never, and the difference between
those two sentences is a cross-section falling with energy and not a wall becoming a window.

WHY THE SHELL SHAPE IS A CONTROL

The wall can be a sphere, a cube, a hexagonal drum or a solid with twelve faces. The shadow pattern
looks different on each and carries the same thing. Offering the choice makes that checkable. What
a boundary can hold is set by its area and the finest detail that reaches it, and not by its shape.
Switching the wall and watching the reading survive is how that stops being an assertion.
"""

import io
import json
import math
import os
import sys

import settings

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "room_view_template.html")

SHELLS = ("sphere", "cube", "hexagon", "octahedron", "dodecahedron")
CORES = ("sphere", "cube", "octahedron", "cone")


def draw(seed):
    """The same small generator the other tools here use, so one seed means one room."""
    state = (seed ^ 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
    while True:
        state = (state * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
        yield ((state >> 11) & 0x1FFFFFFFFFFFFF) / float(1 << 53)


def place(stream, depth):
    """A point at this depth, drawn evenly over the directions and not evenly over the angles."""
    height = 2.0 * next(stream) - 1.0
    around = 2.0 * math.pi * next(stream)
    flat = math.sqrt(max(0.0, 1.0 - height * height))
    return [round(flat * math.cos(around) * depth, 4),
            round(height * depth, 4),
            round(flat * math.sin(around) * depth, 4)]


def drift(stream, speed):
    """A velocity in a direction nobody chose, at the speed asked for.

    Drawn over the sphere of directions and never by picking three numbers in a box, since a box
    favours its corners and a cloud drawn that way drifts along the diagonals. The bias is small
    enough to look like nothing and large enough to survive averaging, the worst size for
    a defect to be.
    """
    height = 2.0 * next(stream) - 1.0
    around = 2.0 * math.pi * next(stream)
    flat = math.sqrt(max(0.0, 1.0 - height * height))
    return [round(flat * math.cos(around) * speed, 5),
            round(height * speed, 5),
            round(flat * math.sin(around) * speed, 5)]


def from_draw(count, seed):
    """A cloud of small lights, confined by the shell and moving inside it.

    They carry a velocity and never an orbit. An orbit is a path somebody laid down for them, and
    what is wanted here is a population that goes where it goes and turns back at the wall, since
    the wall being a wall to them is the thing worth showing. It is a window to whoever is looking
    in from outside and a hard boundary to everything inside, and those are not in conflict: what
    leaves is the light, and what stays is the body that emitted it.
    """
    stream = draw(seed)
    things = []
    for index in range(count):
        things.append({
            "index": index,
            "at": place(stream, 0.12 + 0.70 * next(stream)),
            "vel": drift(stream, 0.05 + 0.16 * next(stream)),
            "size": round(0.008 + 0.018 * next(stream), 4),
            "stops": round(0.15 + 0.85 * next(stream), 4),
            "glow": round(0.35 + 0.65 * next(stream), 4),
        })
    return things


def from_blob(data, count, seed):
    """Objects taken from a file: the commonest byte values, sized and placed by what they are.

    A byte's share of the file sets how much of the beam it stops, so the values a file is built
    out of are the ones that cast shadows and the rare ones let the beam through. Depth is the
    reverse, putting the common values out near the wall where their shadows are small and sharp.
    """
    counts = [0] * 256
    for byte in data:
        counts[byte] += 1
    ranked = sorted(range(256), key=lambda value: -counts[value])[:count]
    if not ranked or counts[ranked[0]] == 0:
        return []

    stream = draw(seed)
    top = float(counts[ranked[0]])
    things = []
    for index, value in enumerate(ranked):
        share = counts[value] / top
        height = 2.0 * next(stream) - 1.0
        around = 2.0 * math.pi * next(stream)
        flat = math.sqrt(max(0.0, 1.0 - height * height))
        depth = 0.25 + 0.55 * share
        things.append({
            "index": index,
            "value": value,
            "count": counts[value],
            "at": [round(flat * math.cos(around) * depth, 4),
                   round(height * depth, 4),
                   round(flat * math.sin(around) * depth, 4)],
            "size": round(0.04 + 0.10 * share, 4),
            "stops": round(0.12 + 0.86 * share, 4),
            "turn": round(0.12 + 0.4 * next(stream), 4),
        })
    return things


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

    shell = option("--shell", "sphere")
    core = option("--core", "cube")
    count = option("--things", 160, int)
    seed = option("--seed", 4, int)
    blob = option("--blob", "")

    if shell not in SHELLS:
        sys.stderr.write("--shell takes one of: %s\n" % ", ".join(SHELLS))
        return 2
    # Checked here and never left to the page. An unknown shape reaches the page as a word it does
    # not recognise, the page falls through to its own default, and the caller gets a sphere while
    # having asked for something else with no message anywhere saying so.
    if core not in CORES:
        sys.stderr.write("--core takes one of: %s\n" % ", ".join(CORES))
        return 2
    # Up to a few hundred. The cloud is meant to read as a lot of small lights and not as a handful
    # of marked objects, and a shadow map costs the same whatever it is drawing.
    if count < 1 or count > 400:
        sys.stderr.write("--things sits between 1 and 400\n")
        return 2

    if blob:
        with io.open(blob, "rb") as handle:
            data = bytearray(handle.read(1 << 20))
        things = from_blob(data, count, seed)
        source = os.path.basename(blob)
        if not things:
            sys.stderr.write("read nothing from %s\n" % blob)
            return 1
    else:
        things = from_draw(count, seed)
        source = "a draw on seed %d" % seed

    payload = {
        "shell": shell,
        "core": core,
        "source": source,
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

    out = option("--out", os.path.join(HERE, "room_view.html"))
    with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)

    stoppers = sum(1 for one in things if one["stops"] > 0.5)
    print("%s" % out)
    print("  %d lights held by a %s, inside a %s room, from %s" % (len(things), core, shell, source))
    print("  %d of them stop a beam at half energy" % stoppers)
    return 0


if __name__ == "__main__":
    sys.exit(main())
