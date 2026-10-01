# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: VIZ-x-021
#
"""Opening state for a viewer page, as parameters instead of edits to a template.

Every generator here takes --set key=value, repeatable, and passes the result through to the page.
It decides what the viewer looks like when it opens: which representation, where the observer is,
whether it turns on its own, what is already selected. A caller that wants a particular view asks
for it instead of publishing a page and telling the reader which controls to move.

    python examples/00_blob_viz_tools/build_blob_view.py file.bin --set shape=hilbert --set spin=0.3
    python examples/00_blob_viz_tools/build_field_view.py data.csv --set theme=light --set floor=20

Unknown keys error and never ignored. A typo in a setting is silent otherwise, and a page
that opens in the wrong state looks like a bug in the viewer.

One definition per setting serves both the --set command and the shared control bar. A unit names
the settings its bar carries and hands `schema` the names; the bar draws a control per entry from
the kind, the range and the fallback held here. The command and the bar read one source, and a
setting cannot mean one thing on the command line and another in the bar.

A unit whose control covers less than a setting's full range narrows it to a sub-range here, never
wider, and the bar it injects carries that sub-range. A camera distance means a different span in a
scene built around a fixed ball than in one without, and one global range cannot carry both.
"""

import sys

# One entry per setting: its kind, the value it opens at when nothing sets it, a human line, and the
# range the bar bounds a control to. The bar kind and the command kind are the same word. int and
# float cast on the command line; color, word and text are strings there and draw their own control
# in the bar. A bounded number carries low and high; a word carries its words. The page applies
# these; nothing here draws anything.
KNOWN = {
    # what is shown
    "step": {"kind": "int", "low": 0, "fallback": 0, "what": "which step is selected, counting from zero"},
    "shape": {"kind": "str", "fallback": "", "what": "representation key, such as plane, sphere, hilbert, torus"},
    "transform": {"kind": "str", "fallback": "", "what": "transform key, such as none, invert, shadow, wall"},
    "overlay": {"kind": "str", "fallback": "", "what": "step key whose values drive color, or empty for off"},
    "order": {"kind": "int", "low": 3, "high": 4096, "fallback": 6, "what": "sides, petals or winding"},
    "wrap": {"kind": "int", "low": 1, "high": 32, "fallback": 1, "what": "how many times the data is laid around the shape"},

    # how it is drawn
    "height": {"kind": "int", "low": 1, "high": 60, "fallback": 22, "what": "relief"},
    "floor": {"kind": "int", "low": 0, "high": 90, "fallback": 0, "what": "hides cells quieter than this"},
    "contrast": {"kind": "float", "low": 0.1, "high": 2.0, "fallback": 0.6,
                 "what": "exponent the value is raised to before the ramp"},
    "theme": {"kind": "word", "words": ["light", "dark"], "fallback": "",
              "what": "light or dark, or unset to follow the reader's system"},
    "background": {"kind": "color", "fallback": "#0b0d12", "what": "ground color behind the page"},
    "low": {"kind": "color", "fallback": "#2f7fb5", "what": "ramp color for the low end"},
    "mid": {"kind": "color", "fallback": "#0a0d12", "what": "ramp color at zero"},
    "high": {"kind": "color", "fallback": "#d2552a", "what": "ramp color for the high end"},
    "opacity": {"kind": "int", "low": 15, "high": 100, "fallback": 100,
                "what": "how present the control boxes are"},

    # where the observer is, and whether anything moves
    "yaw": {"kind": "float", "fallback": 0.0, "what": "observer angle around the object, in radians"},
    "pitch": {"kind": "float", "fallback": 0.0, "what": "observer angle above the object, in radians"},
    "distance": {"kind": "float", "low": 60, "high": 1400, "fallback": 600, "what": "observer distance"},
    "spin": {"kind": "float", "low": 0, "fallback": 0.0,
             "what": "turns per minute the object rotates on its own, 0 for still"},
    "spinaxis": {"kind": "word", "words": ["up", "right"], "fallback": "up", "what": "the axis the spin turns about"},

    # what is already selected
    "select_from": {"kind": "float", "fallback": 0.0, "what": "low end of a value range selected on opening"},
    "select_to": {"kind": "float", "fallback": 0.0, "what": "high end of that range"},
}


# A unit may narrow a bounded setting to a sub-range of KNOWN. schema() reads the narrowing for a
# named unit, and the bar it injects bounds that control to the sub-range. The control then
# represents the range the command enforces, and no value valid on one is refused by the other. A
# narrowing only tightens: the containment below stops a widening, a control admitting a value the
# command refuses.
#
# A narrowing also names the unit's own fallback where its control opens at a value other than
# KNOWN's. The schema then states the default the control rests at, not a shared one it never uses.
# The fallback has to sit inside the narrowed range, checked below beside the bounds.
NARROW = {
    "room": {"opacity": {"fallback": 90}},
    "sphere": {
        "distance": {"low": 105, "high": 600, "fallback": 340},
        "opacity": {"fallback": 94},
    },
}


def _check_narrowings():
    """Each narrowing names a KNOWN setting, keeps any bound inside its range, and rests its fallback there."""
    for unit, narrowing in NARROW.items():
        for name, bound in narrowing.items():
            if name not in KNOWN:
                raise ValueError("narrowing for %s names unknown setting %s" % (unit, name))
            rule = KNOWN[name]
            low = bound.get("low")
            high = bound.get("high")
            if (low is not None or high is not None) and rule.get("low") is None and rule.get("high") is None:
                raise ValueError("%s has no range to narrow for %s" % (name, unit))
            if low is not None and rule.get("low") is not None and low < rule["low"]:
                raise ValueError("%s narrows below KNOWN for %s: %s under %s"
                                 % (name, unit, low, rule["low"]))
            if high is not None and rule.get("high") is not None and high > rule["high"]:
                raise ValueError("%s narrows above KNOWN for %s: %s over %s"
                                 % (name, unit, high, rule["high"]))
            fallback = bound.get("fallback")
            if fallback is not None:
                floor = low if low is not None else rule.get("low")
                ceiling = high if high is not None else rule.get("high")
                if floor is not None and fallback < floor:
                    raise ValueError("%s fallback for %s sits below its range: %s under %s"
                                     % (name, unit, fallback, floor))
                if ceiling is not None and fallback > ceiling:
                    raise ValueError("%s fallback for %s sits above its range: %s over %s"
                                     % (name, unit, fallback, ceiling))


_check_narrowings()


def _range(rule):
    """The range line for one rule: its words, its bounds, or empty when it is open."""
    if "words" in rule:
        return ", ".join(rule["words"])
    low = rule.get("low")
    high = rule.get("high")
    if low is not None and high is not None:
        return "%s to %s" % (low, high)
    if low is not None:
        return "at least %s" % low
    if high is not None:
        return "at most %s" % high
    return ""


def usage():
    """The settings table, for a generator's own help text."""
    lines = ["  --set key=value, repeatable. Known keys:"]
    for name in sorted(KNOWN):
        rule = KNOWN[name]
        lines.append("    %-12s %-6s %-14s %s" % (name, rule["kind"], _range(rule), rule["what"]))
    return "\n".join(lines)


def schema(names, narrow=None):
    """The bar schema for the named settings: kind, range and fallback, read from KNOWN.

    A unit lists the settings its bar carries and hands the result to the page. The bar draws a
    control per entry from exactly this. The definition the --set command reads and the definition
    the bar reads are one and the same. An unknown name exits before the page ships a bar with a
    control the command cannot set.

    A unit whose control is narrower than a setting's full range names its narrowing, and the entry
    carries the sub-range NARROW holds for it instead of the KNOWN range.
    """
    bounds = {}
    if narrow is not None:
        if narrow not in NARROW:
            sys.stderr.write("no narrowing named %s\n" % narrow)
            raise SystemExit(1)
        bounds = NARROW[narrow]
    out = {}
    for name in names:
        if name not in KNOWN:
            sys.stderr.write("no setting named %s to put in the bar. Known:\n%s\n" % (name, usage()))
            raise SystemExit(1)
        rule = KNOWN[name]
        entry = {"kind": rule["kind"], "fallback": rule["fallback"]}
        for key in ("low", "high", "words"):
            if key in rule:
                entry[key] = rule[key]
        if name in bounds:
            for key in ("low", "high", "fallback"):
                if key in bounds[name]:
                    entry[key] = bounds[name][key]
        out[name] = entry
    return out


def collect(argv):
    """Reads every --set from a command line and returns them as a dict the page understands.

    Values are converted to the kind the page expects. The page never has to guess whether "3" is
    a number or a word. A key that is not known, or a value that is not the right kind, exits with
    a message: a setting that does not apply is worse than one that was never given, because the
    page opens looking wrong and the fault is invisible.
    """
    out = {}
    at = 0
    while at < len(argv):
        if argv[at] != "--set":
            at += 1
            continue
        if at + 1 >= len(argv):
            sys.stderr.write("--set needs a key=value\n")
            raise SystemExit(1)
        pair = argv[at + 1]
        if "=" not in pair:
            sys.stderr.write("--set %s is not key=value\n" % pair)
            raise SystemExit(1)
        name, _, text = pair.partition("=")
        name = name.strip()
        if name not in KNOWN:
            sys.stderr.write("unknown setting %s. Known:\n%s\n" % (name, usage()))
            raise SystemExit(1)
        kind = KNOWN[name]["kind"]
        try:
            if kind == "int":
                out[name] = int(text)
            elif kind == "float":
                out[name] = float(text)
            else:
                out[name] = text
        except ValueError:
            sys.stderr.write("setting %s wants %s, got %s\n" % (name, kind, text))
            raise SystemExit(1)
        at += 2
    return out
