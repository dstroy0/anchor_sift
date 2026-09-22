"""Does the page's own script parse? Asked of the template before a build, and of the build after.

    python tools/view/script_check.py tools/view/room_view_template.html
    python tools/view/script_check.py --check

THE DEFECT THIS EXISTS FOR

The builders check one thing about the script: that the template did not leave a script tag
open. A page whose tags balance and whose JavaScript does not parse builds
without complaint, writes its file, prints its summary and reports its digest -- and then renders a
blank canvas, because the whole script died on the first token that did not fit.

Nothing in the tree caught that, and the only reader who would was a person opening the page. Every
edit to a four thousand line template was therefore one typo away from a silent blank page, found
only by looking, and nobody looks once the builder has said it succeeded.

WHAT IT DOES

Pulls the inline script bodies out of the page and hands each to node --check, which parses without
executing. Nothing runs, nothing is fetched, and the browser globals the script wants are never
touched -- a parse does not need them.

A page with no inline script passes and says so. A missing node is reported and not silently
treated as a pass, because a check that cannot run is not a check that succeeded.
"""

import io
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))

# Inline bodies only. A src attribute names a file this tool is not responsible for, and the CDN
# copy of a library is not ours to parse.
BLOCK = re.compile(r"<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>", re.DOTALL | re.IGNORECASE)


def bodies(text):
    return [one for one in BLOCK.findall(text) if one.strip()]


def parses(source):
    """(ok, message) from node --check on this source, written to a temporary file it then removes.

    A file and never a pipe, because node --check reads a path and the error it prints names that
    path and a line inside it, and that naming is the part worth returning.
    """
    handle = tempfile.NamedTemporaryFile("w", suffix=".js", delete=False, encoding="utf-8")
    try:
        handle.write(source)
        handle.close()
        done = subprocess.run(["node", "--check", handle.name],
                              capture_output=True, text=True, timeout=60)
        if done.returncode == 0:
            return True, ""
        # The temporary path is noise in the message, so the name is folded back to the block it
        # came from by the caller and stripped here.
        return False, re.sub(re.escape(handle.name), "<script>", done.stderr).strip()
    except FileNotFoundError:
        return None, "node is not on the path, so the script was not parsed"
    except subprocess.TimeoutExpired:
        return None, "node did not finish, so the script was not parsed"
    finally:
        try:
            os.unlink(handle.name)
        except OSError:
            pass


# A top-level `var name =` and a top-level `function name(` in one script scope.
#
# THE FAULT THIS CATCHES, WHICH A PARSE CANNOT
#
# Both declarations hoist. The function is bound first, then the var's assignment runs at load and
# leaves its value sitting where the function was, so the first call throws. The script parses, the
# page builds, the builder prints its digest, and the frame loop dies on its first turn -- after
# setup has already drawn one frame. The result is a page that renders once and looks like a working
# page with a feature that does nothing, when what does nothing is every feature after the throw.
#
# It happened here with a name as ordinary as `side`: a Vector3 near the top and an orientation test
# two thousand lines below it, in one scope, with nothing between them to make the collision visible.
TOP_VAR = re.compile(r"^var\s+(\w+)\s*=")
TOP_FUNC = re.compile(r"^function\s+(\w+)\s*\(")


def collisions(source):
    """Names declared at the top level as both a var and a function, and duplicate functions.

    Only column-zero declarations count. Anything indented is inside something, and a shadowed name
    there is a scope.
    """
    seen_var = {}
    seen_func = {}
    for at, line in enumerate(source.split("\n")):
        found = TOP_VAR.match(line)
        if found:
            seen_var.setdefault(found.group(1), at + 1)
            continue
        found = TOP_FUNC.match(line)
        if found:
            name = found.group(1)
            if name in seen_func:
                seen_func[name] = seen_func[name]
            else:
                seen_func[name] = at + 1
    out = []
    for name, at in sorted(seen_func.items(), key=lambda pair: pair[1]):
        if name in seen_var:
            out.append((name, seen_var[name], at))
    return out


# Is the frame loop watched?
#
# WHAT THIS CANNOT DO, said first so the check is not mistaken for more than it is. A page is only
# proved to run by running it, and this tool does not have a browser. So it cannot tell you the loop
# turns. What it can tell you is that the machinery which WOULD report a dead loop is still present
# and still wired, and that wiring is the part a refactor silently drops.
#
# The runtime half lives in the page: a counter per completed turn, a guard that catches and names a
# throw instead of letting it kill the scheduler, a watchdog that fails if fewer than two turns
# complete, and window.__loopHealth for a harness to read in one call. Two turns and not one,
# because one turn is what a dead loop produces -- setup draws a frame, the first turn throws,
# and the result is a complete correct still picture that passes every other check in this file.
#
# Verified against a page with a deliberate throw injected after the first turn: it reports
# ok false, turns 1, and shows the error on screen. A guard nobody has seen fire is a guard nobody
# has tested.
LOOP_PARTS = (
    ("a frame loop", "function turn()"),
    ("a turn counter", "loopTurns"),
    ("a guard around the loop", "guardedTurn"),
    ("a watchdog timer", "LOOP_WATCH_MS"),
    ("a reported failure", "loopFailed"),
    ("a machine-readable result", "__loopHealth"),
)


def loop_guard(source):
    """Which parts of the loop watch are missing, for a page that has a frame loop at all."""
    if "function turn()" not in source:
        return None
    return [name for name, token in LOOP_PARTS if token not in source]


def check(path):
    with io.open(path, encoding="utf-8", newline="") as handle:
        text = handle.read()

    found = bodies(text)
    lines = ["  %s" % os.path.basename(path)]
    if not found:
        lines.append("  no inline script, nothing to parse")
        sys.stdout.write("\n".join(lines) + "\n\n0 check(s) failed\n")
        return 0

    failed = 0
    for at, source in enumerate(found):
        held = source.count("\n") + 1
        ok, why = parses(source)
        if ok is True:
            lines.append("  block %d parses, %d lines" % (at + 1, held))
        elif ok is None:
            lines.append("  block %d NOT PARSED, %d lines: %s" % (at + 1, held, why))
            failed += 1
        else:
            lines.append("  block %d FAILS to parse, %d lines" % (at + 1, held))
            for row in why.split("\n")[:6]:
                lines.append("    %s" % row)
            failed += 1

        missing = loop_guard(source)
        if missing is None:
            lines.append("  block %d has no frame loop, so none to watch" % (at + 1))
        elif missing:
            lines.append("  block %d LOOP UNWATCHED, missing: %s" % (at + 1, ", ".join(missing)))
            lines.append("    a loop that dies here renders one correct frame and passes every")
            lines.append("    other check in this file")
            failed += 1
        else:
            lines.append("  block %d loop is watched, and a dead loop reports itself" % (at + 1))

        for name, var_at, func_at in collisions(source):
            lines.append("  block %d COLLISION on '%s': var at line %d, function at line %d"
                         % (at + 1, name, var_at, func_at))
            lines.append("    both hoist, the assignment wins, and the first call throws")
            failed += 1

    sys.stdout.write("\n".join(lines) + "\n\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


# The fault this tool exists for, written out, so the tool is asked to find it before it is trusted
# on anything else. A checker that has never caught its own defect is a checker nobody has tested,
# and the whole point of the collision above is that it is invisible without one.
KNOWN_CLASH = "\n".join((
    "var side = 1;",
    "function elsewhere() { return 2; }",
    "function side(a, b) { return a - b; }",
))

KNOWN_CLEAN = "\n".join((
    "var sideways = 1;",
    "function side(a, b) { return a - b; }",
    "function holder() { var side = 3; return side; }",
))


def _check():
    lines = []
    failed = 0

    # The known positive, first. Nothing below is worth reading if this comes back empty.
    clash = collisions(KNOWN_CLASH)
    lines.append("  the known collision: %d found" % len(clash))
    if len(clash) != 1 or clash[0][0] != "side":
        lines.append("    FAIL the tool did not find the fault it was written for")
        failed += 1
    else:
        lines.append("    'side' as a var at line %d and a function at line %d, which is the shape"
                     % (clash[0][1], clash[0][2]))

    # The known negative. A near miss and a properly scoped shadow must both stay quiet, or every
    # real finding arrives buried in ones that are not.
    quiet = collisions(KNOWN_CLEAN)
    lines.append("  the known clean sample: %d found" % len(quiet))
    if quiet:
        lines.append("    FAIL a scoped shadow or a near miss was reported as a collision")
        failed += 1
    else:
        lines.append("    an indented shadow is a scope and a similar name is not a collision")

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")

    for name in sorted(os.listdir(HERE)):
        if name.endswith("_template.html"):
            failed += check(os.path.join(HERE, name))
    return failed


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--check" in argv:
        sys.exit(1 if _check() else 0)
    if argv:
        sys.exit(1 if check(argv[0]) else 0)
    sys.stdout.write(__doc__)
    sys.exit(2)
