"""Which of a page's optional features come out inert, said out loud at build time.

    python examples/00_blob_viz_tools/inert_report.py [page.html ...]

THE FAILURE THIS EXISTS FOR

A room page built to answer a question about the operation clock can have no clock. It parses, its
frame loop runs, the server returns 200, and every gate in this tree passes it, because none of that
is wrong: `build_sha_room_view.py` supplies no `clock` key, every read of that key in the template
is guarded, and a room without a clock is a supported mode. The guards do their work, the defaults
apply, and what ships is a live page whose clock controls do nothing.

The defect is not in the page. It is that nobody is told which half of the page is asleep.

WHY THIS IS NOT A GATE

`data_check.py` is the gate, and it fails a page that reads a key nothing supplies and nothing
guards. That is a defect and it should fail.

An absent optional key is not a defect and must never fail a build. It is a fact about the page that
the person who just built it needs, and the only moment they reliably read anything is the moment
the build prints. So this prints and returns nothing to fail on.

The output is a receipt: this page has no clock and no sources. A reader who wanted a transport
knows before they open it, instead of after they have drawn a conclusion from a control that was
never wired.

WHAT IT READS

The built page, not the builder, because the built page is the artifact somebody opens and the only
place the data and the template are both present. The guard analysis is `data_check`'s, imported
instead of restated, and a page therefore cannot be graded one way by the gate and another way here.
"""

import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import data_check


def inert_of(text):
    """The optional keys a page asks for and does not carry, as sorted dotted paths.

    Optional means guarded: the page tests for the key before reading it. An unguarded absence is a
    defect, it belongs to `data_check`, and it is excluded here instead of being reported twice.
    """
    literal, why = data_check.data_literal(text)
    if literal is None:
        return None, why
    try:
        data = json.loads(literal)
    except ValueError as trouble:
        return None, "the data is not JSON: %s" % trouble

    found = data_check.reads_of(text)
    missing = set()
    for path in found:
        reached, depth, _ = data_check.walk(data, path)
        if reached:
            continue
        if not data_check.protected(path, found):
            # An unguarded absence. The gate's finding, not this one's.
            continue
        missing.add(".".join(path[:depth + 1]))

    # A child is not reported beside its parent. Where `clock` is absent, `clock.ticks` is absent
    # for the same reason and naming both says one thing twice.
    shortest = set()
    for one in sorted(missing, key=len):
        if not any(one.startswith(prefix + ".") for prefix in shortest):
            shortest.add(one)
    return sorted(shortest), ""


def lines_for(text, name=None):
    """The receipt, as lines a builder can print. Empty where the page carries everything."""
    absent, why = inert_of(text)
    if absent is None:
        return ["  the page's data could not be read: %s" % why,
                "  `data_check` reads it the same way and reports the same, so this is one finding",
                "  and it belongs to the gate. See this file's header on the apostrophe."]
    if not absent:
        return []
    lead = "  " if name is None else "  %s: " % name
    return ["%sthis page has no %s" % (lead, ", no ".join(absent)),
            "  the template asks for each of those and falls back, so the controls they drive are",
            "  present and do nothing. Build with a payload carrying them to wake them up."]


def report(text, name=None, stream=None):
    """Print the receipt, and return the absent keys for a caller with more of its own to say."""
    absent, _ = inert_of(text)
    for line in lines_for(text, name):
        (stream or sys.stdout).write(line + "\n")
    return absent or []


def _check():
    lines = []
    failed = 0

    def say(one):
        lines.append(one)

    # A page that carries everything has to produce no receipt, and a page missing a guarded key has
    # to produce one. Both are built here so the check does not depend on what is in build/view.
    whole = 'var DATA = {"clock": {"ticks": 4}, "things": []};\n' \
            'if (DATA.clock) { use(DATA.clock.ticks); }\n' \
            'var n = DATA.things.length;\n'
    without = 'var DATA = {"things": []};\n' \
              'if (DATA.clock) { use(DATA.clock.ticks); }\n' \
              'var n = DATA.things.length;\n'
    # An absence nothing guards belongs to data_check, and this has to stay quiet about it.
    unguarded = 'var DATA = {"things": []};\n' \
                'var t = DATA.clock.ticks;\n'

    say("  a page carrying every key it reads")
    got = inert_of(whole)[0]
    say("    reports %s" % (got if got else "nothing, which is right"))
    if got:
        say("  FAIL a complete page produced a receipt")
        failed += 1

    say("  a page whose guarded key is absent")
    got = inert_of(without)[0]
    say("    reports %s" % got)
    if got != ["clock"]:
        say("  FAIL the absent optional key was not named, or its child was named beside it")
        failed += 1

    say("  a page whose absent key is not guarded, and the gate owns that one")
    got = inert_of(unguarded)[0]
    say("    reports %s" % (got if got else "nothing, and data_check fails it instead"))
    if got:
        say("  FAIL an unguarded absence was reported here as well as by the gate")
        failed += 1
    say("")

    pages = sorted(one for one in os.listdir(HERE) if one.endswith("_view.html"))
    if pages:
        say("  the built pages beside this tool")
        for one in pages:
            with io.open(os.path.join(HERE, one), encoding="utf-8", newline="") as handle:
                absent, why = inert_of(handle.read())
            if absent is None:
                say("    %-24s unreadable: %s" % (one, why))
            else:
                say("    %-24s %s" % (one, ", ".join(absent) if absent else "carries everything"))

    sys.stdout.write("\n".join(lines) + "\n\n%d check(s) failed\n" % failed)
    return failed


def main():
    argv = [one for one in sys.argv[1:] if not one.startswith("-")]
    if "--check" in sys.argv[1:] or not sys.argv[1:]:
        return 1 if _check() else 0
    for path in argv:
        with io.open(path, encoding="utf-8", newline="") as handle:
            text = handle.read()
        absent = report(text, os.path.basename(path))
        if not absent:
            sys.stdout.write("  %s carries every key it reads\n" % os.path.basename(path))
    return 0


if __name__ == "__main__":
    sys.exit(main())
