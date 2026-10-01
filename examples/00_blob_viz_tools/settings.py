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
"""

import sys

# One entry per setting: its kind, the value it opens at when nothing sets it, a human line, and the
# range the bar bounds a control to. The bar kind and the command kind are the same word. int and
# float cast on the command line; color, word and text are strings there and draw their own control
# in the bar. A bounded number carries low and high; a word carries its words. The page applies
# these; nothing here draws anything.
KNOWN = {
    # what is shown
    "step": {"kind": "int", "fallback": 0, "what": "which step is selected, counting from zero"},
    "shape": {"kind": "str", "fallback": "", "what": "representation key, such as plane, sphere, hilbert, torus"},
    "transform": {"kind": "str", "fallback": "", "what": "transform key, such as none, invert, shadow, wall"},
    "overlay": {"kind": "str", "fallback": "", "what": "step key whose values drive color, or empty for off"},
    "order": {"kind": "int", "fallback": 0, "what": "sides, petals or winding, 3 to 4096"},
    "wrap": {"kind": "int", "fallback": 0, "what": "how many times the data is laid around the shape"},

    # how it is drawn
    "height": {"kind": "int", "fallback": 0, "what": "relief, 1 to 60"},
    "floor": {"kind": "int", "fallback": 0, "what": "hides cells quieter than this, 0 to 90"},
    "contrast": {"kind": "float", "fallback": 0.0, "what": "exponent the value is raised to before the ramp"},
    "theme": {"kind": "str", "fallback": "", "what": "light or dark, or empty to follow the reader's system"},
    "background": {"kind": "color", "fallback": "#0b0d12", "what": "ground color behind the page"},
    "low": {"kind": "color", "fallback": "#000000", "what": "ramp color for the low end"},
    "mid": {"kind": "color", "fallback": "#000000", "what": "ramp color at zero"},
    "high": {"kind": "color", "fallback": "#000000", "what": "ramp color for the high end"},
    "opacity": {"kind": "int", "low": 15, "high": 100, "fallback": 100,
                "what": "how present the control boxes are"},

    # where the observer is, and whether anything moves
    "yaw": {"kind": "float", "fallback": 0.0, "what": "observer angle around the object, in radians"},
    "pitch": {"kind": "float", "fallback": 0.0, "what": "observer angle above the object, in radians"},
    "distance": {"kind": "float", "fallback": 0.0, "what": "observer distance, 60 to 1400"},
    "spin": {"kind": "float", "fallback": 0.0, "what": "turns per minute the object rotates on its own, 0 for still"},
    "spinaxis": {"kind": "str", "fallback": "", "what": "up or right, the axis the spin turns about"},

    # what is already selected
    "select_from": {"kind": "float", "fallback": 0.0, "what": "low end of a value range selected on opening"},
    "select_to": {"kind": "float", "fallback": 0.0, "what": "high end of that range"},
}


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


def schema(names):
    """The bar schema for the named settings: kind, range and fallback, read from KNOWN.

    A unit lists the settings its bar carries and hands the result to the page. The bar draws a
    control per entry from exactly this. The definition the --set command reads and the definition
    the bar reads are one and the same. An unknown name exits before the page ships a bar with a
    control the command cannot set.
    """
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
