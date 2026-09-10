"""Puts a moving system inside the ball and derives it back from the boundary alone.

    python tools/view/build_orrery_view.py
    python tools/view/build_orrery_view.py --bodies 6 --frames 512 --mode shadow

  --bodies    how many orbiting bodies. Default 6.
  --frames    how many steps of the clock to precompute. Default 512.
  --mode      glow for a scattering ball, shadow for a clear one. Default glow.
  --degrees   highest harmonic degree carried. Default 48.
  --tau       conduction time the surface is left to smooth for. Default 0.0006.
  --seed      draw for the sizes and phases. Default 11.
  --out       where to write. Default orrery_view.html beside this script.

WHY A SYSTEM AND NOT A FILE

Everything else in this directory reads data nobody knows the shape of, which makes a viewer that
looks right impossible to grade. Here the interior is written down first: bodies at known radii on
known periods. The page then shows the boundary alone, derives the interior back out of it, and
prints the derived numbers next to the ones it was built from. A viewer that draws a convincing
picture and recovers the wrong radius is caught in the same glance.

TWO WAYS FOR THE INSIDE TO REACH THE OUTSIDE

    glow    the medium scatters without limit, transport is diffusion, and a body at radius r
            reaches degree l as (r/R)^l. Depth sets how wide a patch the body can print, and a body
            near the center is a broad warmth and one near the shell is a small bright spot. There
            are no shadows in this limit at all: light that has forgotten its direction cannot
            leave one behind.

    shadow  the medium is clear, transport is ballistic, and a beam from outside prints the
            silhouette of whatever it passes. Edges are as sharp as the bodies are, and a body that
            emits nothing is as visible as one that emits everything.

Those are the two limits of one transport equation and the page carries both, because they fail in
opposite directions. Diffusion sees what is bright and loses where it is. Ballistics sees where
something is and loses what it was. Shining a very bright light through a scattering ball is the
attempt to read the ballistic part before scattering buries it, and the page prints the attenuation
that attempt has to survive.

TIME IS THE INTERIOR MOVING WHILE THE BOUNDARY HOLDS STILL

The boundary never moves here. The bodies do, and the surface changes because of it. So the clock
is not supplied from outside: it is read off a fixed surface, and a run where the observer also
moves can be told apart from a run where it does not by holding the observer still and watching
whether anything keeps changing.

WHAT IS DERIVED

A single patch of the boundary is watched over the whole run, giving one number per step. Each body
crossing the line between the source and that patch prints a dip. The dips repeat on that body's
period, the period gives the radius by Kepler's third law, and the recovered radius is printed
beside the radius the body was built with. Nothing about the recovery reads the body table.
"""

import io
import json
import math
import os
import sys

import dsp
import settings
import sphere_field

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "orrery_view_template.html")


def draw(seed):
    """The same small generator the other tools use, so that a seed means one scene everywhere."""
    state = (seed ^ 0x9E3779B97F4A7C15) & 0xFFFFFFFFFFFFFFFF
    while True:
        state = (state * 6364136223846793005 + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
        yield ((state >> 11) & 0x1FFFFFFFFFFFFF) / float(1 << 53)


def unit(vector):
    length = math.sqrt(sum(one * one for one in vector)) or 1.0
    return [one / length for one in vector]


def cross(left, right):
    return [left[1] * right[2] - left[2] * right[1],
            left[2] * right[0] - left[0] * right[2],
            left[0] * right[1] - left[1] * right[0]]


def sideways(axis):
    """Any unit vector at right angles to this one, taken from whichever axis it leans on least."""
    pick = [1.0, 0.0, 0.0] if abs(axis[0]) < 0.9 else [0.0, 1.0, 0.0]
    return unit(cross(axis, pick))


def system(count, seed):
    """Bodies at spread radii on Kepler periods, each on its own orbit plane.

    The period goes as the radius to the three halves, so the outer bodies are slow and the dips
    they print are rare. The run has to be long for that reason: a body at 0.85 of the way out
    crosses about a third as often as one at 0.4, and a run that stops early recovers the inner
    bodies cleanly and reports the outer ones as absent.

    Each orbit gets a plane of its own and never a tilt applied to a shared one. Tilting one plane
    leaves every orbit crossing the same two points, and a patch placed at either of them watches
    every body pass dead center. The recovery then reports the whole system from a single patch and
    looks far better than it is. That failure is what this construction exists to avoid.
    """
    stream = draw(seed)
    bodies = []
    for index in range(count):
        share = (index + 1.0) / (count + 1.0)
        radius = 0.10 + 0.80 * share
        size = 0.032 + 0.050 * next(stream)
        # Sunlight falls off with the square of the distance and a body catches it over its own
        # disc, so what it sends onward goes as size squared over radius squared.
        brightness = (size * size) / (radius * radius)

        height = 2.0 * next(stream) - 1.0
        around = 2.0 * math.pi * next(stream)
        flat = math.sqrt(max(0.0, 1.0 - height * height))
        normal = unit([flat * math.cos(around), flat * math.sin(around), height])
        first = sideways(normal)
        second = unit(cross(normal, first))

        bodies.append({
            "index": index,
            "radius": round(radius, 4),
            "size": round(size, 4),
            "period": round(math.pow(radius, 1.5), 6),
            "phase": round(next(stream) * 2.0 * math.pi, 5),
            "brightness": round(brightness, 6),
            "normal": [round(one, 5) for one in normal],
            "u": [round(one, 5) for one in first],
            "v": [round(one, 5) for one in second],
        })
    return bodies


def at_time(body, moment):
    """Where a body is at this moment, as a unit direction. Its radius is carried separately."""
    angle = body["phase"] + 2.0 * math.pi * moment / body["period"]
    here = math.cos(angle)
    there = math.sin(angle)
    return (body["u"][0] * here + body["v"][0] * there,
            body["u"][1] * here + body["v"][1] * there,
            body["u"][2] * here + body["v"][2] * there)


def watch_shadow(bodies, frames, span, patch):
    """What a fixed patch receives when the ball is clear: the source, minus whatever crosses it.

    A body blocks when its angular size covers the line from the center to the patch. This is the
    transit curve, and it carries a body only where that body's orbit happens to pass across this
    particular patch. Most pairings of body and patch never line up at all, so most of these curves
    are flat, and reading one flat curve as an empty system is the mistake the glow curve below and
    the several patches above exist to prevent.
    """
    curve = []
    for step in range(frames):
        moment = span * step / frames
        blocked = 0.0
        for body in bodies:
            spot = at_time(body, moment)
            along = spot[0] * patch[0] + spot[1] * patch[1] + spot[2] * patch[2]
            if along <= 0.0:
                continue
            apart = math.acos(max(-1.0, min(1.0, along)))
            covers = math.asin(min(1.0, body["size"] / body["radius"]))
            if apart < covers:
                shading = 1.0 - (apart / covers) ** 2
                blocked += shading * (body["size"] / body["radius"]) ** 2
        curve.append(1.0 - min(0.9, blocked))
    return curve


def watch_glow(bodies, frames, span, patch, profiles):
    """What a fixed patch receives when the ball scatters: the sum of every body's spot, moving.

    Nothing has to line up here. A body's contribution to this patch is its profile read at the
    angle between the patch and wherever the body is, and that angle swings once per orbit for
    every body and every patch. So each body prints a periodic signal on every patch, and the
    signal is smooth instead of a spike.

    That difference decides whether the recovery works. A transit is a narrow pulse, and a narrow
    pulse carries more power in its high harmonics than in its own fundamental, so reading the
    strongest peaks off one gives a tidy row of periods that are all too short. Reading a smooth
    swing gives the fundamental first: the period the body actually has.
    """
    curve = []
    for step in range(frames):
        moment = span * step / frames
        total = 0.0
        for body in bodies:
            spot = at_time(body, moment)
            along = spot[0] * patch[0] + spot[1] * patch[1] + spot[2] * patch[2]
            apart = math.acos(max(-1.0, min(1.0, along)))
            table = profiles["%.4f" % body["radius"]]
            at = int(round(apart / math.pi * (len(table) - 1)))
            total += table[at] * body["brightness"]
        curve.append(total)
    return curve


def recover(curve, span, frames, bodies):
    """Periods out of the light curve, then radii out of the periods. Reads no body table.

    The curve is turned into a spectrum and its peaks are read as periods. Kepler's third law then
    gives a radius from each period, since the period was built as the radius to the three halves
    and no other quantity went into it. The comparison printed on the page is against radii this
    function never sees, and a recovery that agrees is agreeing with the scene and not with itself.
    """
    middle = sum(curve) / len(curve)
    centred = [one - middle for one in curve]

    # Padded eight times past the transform the data alone needs. Padding adds no resolution and
    # this is not asking it to: a period whose peak lands between two bins is read at whichever bin
    # is nearer, and the radius that comes back from a period read off by half a bin is wrong by
    # more than the whole recovery is worth. The interpolation puts the peak where it belongs.
    padded = dsp.next_power(len(centred)) * 8
    magnitudes = dsp.spectrum(centred, dsp.window("hann", len(centred)), padded)

    # A peak has to stand above the noise before it is called a period, since a curve with one deep
    # dip has power at every harmonic of that dip and reading them all back gives a tidy row of
    # bodies that are not there.
    #
    # The floor is the median of the whole spectrum and never of a window around the peak. Padding
    # eight times over makes neighboring bins copies of one another, and a window of a dozen bins
    # covers less than two real ones and its median is the peak itself. Written that way the test
    # compared every peak against a slightly smaller copy of itself and passed nothing, which reads
    # as a system too faint to recover and was a window measured in the wrong units.
    ranked = sorted(magnitudes)
    floor = ranked[len(ranked) // 2]
    oversample = max(1, padded // len(centred))

    # A harmonic sum instead of a bare peak list. A body's swing is smooth and not a sine, so it
    # puts power at twice its frequency and at three times it, and those extra peaks read back as
    # bodies that are not there: 0.786 arrives again as 0.498, 0.558 as 0.351. Filtering them
    # afterwards by comparing candidates in pairs was tried and made the answer worse, since
    # a harmonic of one body sits close enough to a real period of another to take its place.
    #
    # Scoring each trial frequency by what sits at it and at its own multiples settles it without
    # comparing anything to anything. A true fundamental collects from every harmonic it has. A
    # harmonic collects from its multiples alone, because the bins below it, where its own
    # sub-harmonics would be, hold nothing.
    reach = 4
    top_bin = len(magnitudes) // reach
    score = [0.0] * top_bin
    for index in range(1, top_bin):
        total = 0.0
        for times in range(1, reach + 1):
            total += magnitudes[index * times]
        score[index] = total

    # The trial band comes from geometry and not from the scene. A body is inside the ball, so its
    # radius is under one and its period is under one with it; a body too close to the center has
    # no orbit worth the name. Without the band the harmonic sum runs away at the bottom, where
    # every one of its multiples lands in the crowded low bins and collects leakage from all of
    # them. It returned radii above 1.0, which is a body outside the ball it is orbiting inside.
    def bin_for(radius):
        period = math.pow(radius, 1.5)
        return int((1.0 / period) * span / (frames / float(padded)))

    lowest = max(oversample, bin_for(0.99))
    highest = min(top_bin - oversample, bin_for(0.05))

    found = []
    for index in range(lowest, highest):
        here = score[index]
        if floor <= 0.0 or here < floor * reach * 2.0:
            continue
        if here < max(score[index - oversample:index + oversample + 1]):
            continue
        frequency = index * (frames / float(padded)) / span
        if frequency <= 0.0:
            continue
        found.append({"period": 1.0 / frequency, "strength": here / (floor * reach)})

    # Harmonic families, folded to their fundamental. A body's swing is smooth but not a sine, so
    # it puts power at twice its frequency and three times it as well. Read as periods those come
    # back as radii the second and third harmonics imply, and every one of them lands on a body
    # that is not there: 0.786 arrives a second time as 0.498, 0.558 as 0.351, 0.443 as 0.279.
    # Six real bodies became twelve, half of them ghosts of the other half.
    #
    # A candidate is dropped where a stronger candidate already sits at a whole fraction of its
    # frequency. Where the harmonic came in stronger than its own fundamental, the fundamental
    # replaces it instead, since the body has the longer period and the harmonic is an artefact of
    # the shape of the swing.
    found.sort(key=lambda one: -one["strength"])
    kept = []
    for entry in found:
        if any(abs(entry["period"] - one["period"]) < 0.04 * one["period"] for one in kept):
            continue
        kept.append(entry)
        # A fixed ceiling, never the number of bodies. Capping at the count the scene was built
        # with hands the recovery the answer to the question it is being asked, and a recovery that
        # is told how many to find cannot report finding too many.
        if len(kept) >= 10:
            break

    out = []
    for entry in sorted(kept, key=lambda one: one["period"]):
        radius = math.pow(entry["period"], 2.0 / 3.0)
        near = min(bodies, key=lambda body: abs(body["radius"] - radius))
        out.append({
            "period": round(entry["period"], 5),
            "radius": round(radius, 4),
            "strength": round(entry["strength"], 2),
            "nearest": near["index"],
            "off_by": round(abs(near["radius"] - radius), 4),
        })
    return out


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

    count = option("--bodies", 6, int)
    frames = option("--frames", 512, int)
    mode = option("--mode", "glow")
    top = option("--degrees", 48, int)
    tau = option("--tau", 0.0006, float)
    seed = option("--seed", 11, int)
    if mode not in ("glow", "shadow"):
        sys.stderr.write("--mode takes glow or shadow\n")
        return 2
    if count < 1 or count > 12:
        sys.stderr.write("--bodies sits between 1 and 12\n")
        return 2

    bodies = system(count, seed)

    # Long enough that the slowest body crosses several times. A run cut to the inner periods
    # recovers those and reports the outer bodies as absent, which reads as a defect in the
    # recovery and is a defect in the run length.
    span = 8.0 * max(body["period"] for body in bodies)

    # Six patches, at the two poles of each of three great circles at right angles. One patch sees
    # only the bodies whose orbit crosses its own line, and with orbit planes drawn independently
    # that is a different few bodies for each patch. Recovering from one patch and reporting the
    # result as the system is the mistake this is here to make impossible: the page prints what
    # each patch found on its own and what they found together, and the gap between those is the
    # measure of what moving the observer is worth.
    patches = [
        ("+x", (1.0, 0.0, 0.0)), ("-x", (-1.0, 0.0, 0.0)),
        ("+y", (0.0, 1.0, 0.0)), ("-y", (0.0, -1.0, 0.0)),
        ("+z", (0.0, 0.0, 1.0)), ("-z", (0.0, 0.0, -1.0)),
    ]

    profiles = {}
    for body in bodies:
        key = "%.4f" % body["radius"]
        if key not in profiles:
            profiles[key] = sphere_field.zonal_profile(body["radius"], tau, top, 241)

    watched = []
    for name, patch in patches:
        glow = watch_glow(bodies, frames, span, patch, profiles)
        shade = watch_shadow(bodies, frames, span, patch)
        seen = recover(glow, span, frames, bodies)
        watched.append({
            "name": name,
            "curve": [round(one, 6) for one in glow],
            "shadow": [round(one, 6) for one in shade],
            "found": seen,
            "transits": round(1.0 - min(shade), 6),
        })

    # Merged across every patch, and ranked by how many independent axes agree.
    #
    # Peak strength was tried first as the way to tell a body from an artefact and it does not
    # work: on one patch a spurious peak scored 2419 while a real body scored 555. Strength says
    # how loud a bin is, not whether anything is there.
    #
    # Agreement does work. A body is somewhere, so every patch sees it swing. An artefact is a
    # feature of one curve, so it lives on one patch and dies on the next. Antipodal patches are
    # not independent, since a great circle through a point runs through its opposite as well, so
    # what gets counted is axes and never patches: three of three is a body, one of three is a
    # number that came out of one arithmetic.
    merged = []
    for entry in watched:
        axis = entry["name"][1]
        for one in entry["found"]:
            match = None
            for already in merged:
                if abs(already["period"] - one["period"]) < 0.08 * already["period"]:
                    match = already
                    break
            if match is None:
                merged.append({
                    "period": one["period"], "radius": one["radius"],
                    "nearest": one["nearest"], "off_by": one["off_by"],
                    "patches": [entry["name"]], "axes": [axis],
                })
            else:
                if entry["name"] not in match["patches"]:
                    match["patches"].append(entry["name"])
                if axis not in match["axes"]:
                    match["axes"].append(axis)
    for one in merged:
        one["agree"] = len(one["axes"])
    merged.sort(key=lambda one: (-one["agree"], one["period"]))

    curve = watched[4]["curve"]
    found = merged

    shipped = {}
    for key in profiles:
        shipped[key] = [round(one, 8) for one in profiles[key]]

    # What a ballistic reading has to survive. Scattering buries the straight-through part as the
    # exponential of the path in scattering lengths, so the brightness a shadow needs is that
    # exponential. Printing it keeps the shadow mode honest about being a clear-medium answer.
    depths = [1.0, 4.0, 12.0, 30.0]
    attenuation = [{"lengths": one, "survives": "%.2e" % math.exp(-one)} for one in depths]

    payload = {
        "mode": mode,
        "degrees": top,
        "tau": tau,
        "span": round(span, 5),
        "frames": frames,
        "bodies": bodies,
        "profiles": shipped,
        "curve": curve,
        "watched": watched,
        "found": found,
        "attenuation": attenuation,
        "settings": opening,
    }

    with io.open(TEMPLATE, encoding="utf-8") as handle:
        page = handle.read()
    if "/*ORRERY_DATA*/null" not in page:
        sys.stderr.write("the template has no place to put the data\n")
        return 1
    page = page.replace("/*ORRERY_DATA*/null", json.dumps(payload, separators=(",", ":")))
    if page.count("</script>") < page.count("<script"):
        sys.stderr.write("the template left a script open, so the page would not run\n")
        return 1

    out = option("--out", os.path.join(HERE, "orrery_view.html"))
    with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)

    print("%s" % out)
    print("  %d bodies, %d steps over %.2f turns of the slowest" % (count, frames, span /
                                                                    max(b["period"] for b in bodies)))
    print("  built radii:     %s" % ", ".join("%.3f" % body["radius"] for body in bodies))
    for entry in watched:
        names = ", ".join("%.3f" % one["radius"] for one in entry["found"]) or "nothing"
        print("    patch %s found %d: %s" % (entry["name"], len(entry["found"]), names))
    if not found:
        print("  together:        none stood above the noise")
        return 0

    truth = [body["radius"] for body in bodies]
    for level in (3, 2, 1):
        band = [one for one in found if one["agree"] == level]
        if not band:
            continue
        shown = []
        for one in band:
            near = min(abs(one["radius"] - was) for was in truth)
            shown.append("%.3f%s" % (one["radius"], "" if near < 0.04 else "?"))
        print("  seen on %d of 3 axes: %s" % (level, ", ".join(shown)))

    sure = [one for one in found if one["agree"] == 3]
    caught = 0
    for was in truth:
        if any(abs(one["radius"] - was) < 0.04 for one in sure):
            caught += 1
    wrong = sum(1 for one in sure if min(abs(one["radius"] - was) for was in truth) >= 0.04)
    print("  of %d bodies built, %d recovered on all three axes, with %d that match nothing"
          % (len(bodies), caught, wrong))
    return 0


if __name__ == "__main__":
    sys.exit(main())
