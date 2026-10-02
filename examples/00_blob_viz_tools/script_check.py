"""Does the page's own script parse, and is its frame loop watched? Asked of a template and of a built page.

    python examples/00_blob_viz_tools/script_check.py examples/00_blob_viz_tools/room_view_template.html
    python examples/00_blob_viz_tools/script_check.py --check

THE DEFECT THIS EXISTS FOR

A builder checks one thing about the script: that the template did not leave a script tag open. A
page whose tags balance and whose JavaScript does not parse builds without complaint, writes its
file, prints its summary and reports its digest, and then renders a blank canvas, because the whole
script dies on the first token that does not fit. Without this check the only reader who catches
that is a person opening the page, and nobody looks once the builder has said it succeeded.

WHAT IT DOES

Pulls the inline script bodies out of the page and hands each to node --check, which parses without
executing. Nothing runs, nothing is fetched, and the browser globals the script wants are never
touched; a parse does not need them.

A page with no inline script passes and says so. A missing node is reported and never treated as a
pass, because a check that cannot run is not a check that succeeded.
"""

import io
import os
import re
import subprocess
import sys
import tempfile

import generate_template

HERE = os.path.dirname(os.path.abspath(__file__))

# Inline bodies only. A src attribute names a file this tool is not responsible for, and the CDN
# copy of a library is not ours to parse.
BLOCK = re.compile(r"<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>", re.DOTALL | re.IGNORECASE)


def bodies(text):
    return [one for one in BLOCK.findall(text) if one.strip()]


PLACEHOLDER = re.compile(r"/\*[A-Z][A-Z0-9_]*\*/(?!\s*null\b)")


def filled(source):
    """The template with its placeholders replaced by a literal. It can be parsed.

    A template's script slot, `/*SCRIPT*/`, and a data marker written without its null are not
    valid JavaScript until a build fills them, and node refuses them with "Unexpected token". A
    template reported as failing for that reason hides any real syntax error elsewhere in it.

    Substituting `null` gives the parser the shape the built page has. A marker that already carries
    its own `null`, as `/*DATA*/ null` does, parses as it stands and is left alone. A placeholder
    inside a string or a comment is substituted too. That can only turn a passing template into a
    failing one, which shows up loudly, and never hides a failure.
    """
    return PLACEHOLDER.sub("null", source)


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
        # The temporary path is noise in the message. The name is folded back to the block it
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
# leaves its value sitting where the function was. The first call throws. The script parses, the
# page builds, the builder prints its digest, and the frame loop dies on its first turn, after
# setup has already drawn one frame. The result is a page that renders once and looks like a working
# page with a feature that does nothing, when what does nothing is every feature after the throw.
#
# A name as ordinary as `side` does it: a Vector3 near the top and an orientation test two thousand
# lines below it, in one scope, with nothing between them to make the collision visible.
TOP_VAR = re.compile(r"^var\s+(\w+)\s*=")
TOP_FUNC = re.compile(r"^function\s+(\w+)\s*\(")


def collisions(source):
    """Names declared at the top level as both a var and a function.

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
            seen_func.setdefault(found.group(1), at + 1)
    out = []
    for name, at in sorted(seen_func.items(), key=lambda pair: pair[1]):
        if name in seen_var:
            out.append((name, seen_var[name], at))
    return out


# Is every frame loop watched?
#
# WHAT THIS CANNOT DO, said first so the check is not mistaken for more than it is. A page is only
# proved to run by running it, and this tool does not have a browser. It cannot tell you the loop
# turns. It can tell you that the machinery which reports a dead loop is present and wired, and that
# wiring is the part a refactor drops without a sound.
#
# The runtime half is the toolbox's core/watch: it counts turns, catches and names a throw instead of
# letting it kill the scheduler, fails a loop that turns fewer than twice, and keeps
# window.__loopHealth for a harness to read in one call. Two turns and not one, because one turn is
# what a dead loop produces: setup draws a frame, the first turn throws, and the result is a
# complete, correct still picture that passes every other check in this file.
#
# A loop is found by what it does and never by its name. The page's own code schedules a frame with
# requestAnimationFrame or EV.nextTurn, or hands a step to EV.watchLoop. A page's loops are watched
# when its own code never schedules a frame itself, hands each loop to EV.watchLoop, and the page
# carries core/watch: through a TOOL line in a template, or under its toolbox label in a built page.
# The toolbox's own pieces are not the page's code. The watch schedules frames, and frames are
# scheduled there and nowhere else.
SCHEDULES = re.compile(r"\b(?:requestAnimationFrame|nextTurn)\s*\(")
WATCHES = re.compile(r"\bwatchLoop\s*\(")
WATCH = "core/watch"
PIECE = re.compile(r"^// ---- (.+?) ----$", re.MULTILINE)


def own_code(source):
    """The script with every toolbox piece a build inlined taken out: the page's own code."""
    kept = []
    at = 0
    label = None
    for found in PIECE.finditer(source):
        if label is None or not label.startswith("toolbox/"):
            kept.append(source[at:found.start()])
        label = found.group(1)
        at = found.end()
    if label is None or not label.startswith("toolbox/"):
        kept.append(source[at:])
    return "".join(kept)


def page_tools(text):
    """The toolbox tools a page carries: named in a template's TOOL lines with everything they
    require, or found under their labels in a built page."""
    named = set()
    tools = generate_template.load_manifest()
    by_file = {"toolbox/" + tool["file"]: name for name, tool in tools.items()}
    for found in generate_template.DIRECTIVE.finditer(text):
        if found.group(1) == "TOOL" and found.group(2) in tools:
            named.update(generate_template.expand(found.group(2), tools, [], set()))
    for found in generate_template.TOOL_LABEL.finditer(text):
        if found.group(1) in by_file:
            named.add(by_file[found.group(1)])
    return named


def line_of(text, at):
    return text.count("\n", 0, at) + 1


def loop_watch(text):
    """(state, findings) for a whole page: state is "none", "watched" or "unwatched"."""
    code = "\n".join(own_code(body) for body in bodies(text))
    scheduled = [line_of(code, found.start()) for found in SCHEDULES.finditer(code)]
    watched = WATCHES.search(code) is not None
    if not scheduled and not watched:
        return "none", []
    findings = []
    if scheduled:
        findings.append("the page's own code schedules frames itself, outside the watch, at script line(s) %s"
                        % ", ".join(str(one) for one in scheduled[:6]))
    if watched and WATCH not in page_tools(text):
        findings.append("EV.watchLoop is called and the page does not carry %s" % WATCH)
    return ("unwatched" if findings else "watched"), findings


BUILT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "build", "view")


def check_built(path):
    """Parse a BUILT page, where the placeholder has been replaced by real data.

    THE GAP THIS CLOSES. The template pass fills every placeholder with `null`, which proves the
    surrounding JavaScript is well formed and says nothing about what the builder substitutes. A
    builder that emits malformed JSON, or JSON containing a stray backslash or an unescaped newline,
    produces a page broken in a way the template pass cannot see. So the built pages
    are parsed too, with their real data in place.

    A LIVE FILE IS HANDLED AND NOT IGNORED. build_pool_view.py runs with --watch and rewrites
    its page every thirty seconds, a read can land mid-write and a truncated page is a syntax
    error that is not a defect. The file is therefore sized, read, and sized again: if it changed
    under us the result is reported as a torn read instead of a failure, and a real error survives
    a reread while a torn one does not.
    """
    lines = ["  %s" % os.path.basename(path)]
    try:
        before = os.path.getsize(path)
        body = io.open(path, encoding="utf-8", errors="replace").read()
        after = os.path.getsize(path)
    except OSError as why:
        lines.append("    could not be read: %s" % why)
        sys.stdout.write("\n".join(lines) + "\n")
        return 0

    found = bodies(body)
    if not found:
        lines.append("    no inline script, nothing to parse")
        sys.stdout.write("\n".join(lines) + "\n")
        return 0

    failed = 0
    for at, source in enumerate(found):
        ok, why = parses(source)
        if ok is True:
            lines.append("    block %d parses with its real data, %d lines"
                         % (at + 1, source.count("\n") + 1))
        elif ok is None:
            lines.append("    block %d NOT PARSED: %s" % (at + 1, why))
            failed += 1
        elif before != after:
            lines.append("    block %d changed while being read, %d bytes to %d, so this is a torn"
                         % (at + 1, before, after))
            lines.append("    read and not a finding. It is a live page under --watch.")
        else:
            lines.append("    block %d FAILS to parse with its real data" % (at + 1))
            for row in why.split("\n")[:6]:
                lines.append("      %s" % row)
            lines.append("      the template parses, so this is what the builder SUBSTITUTED")
            failed += 1
    failed += report_loop(body, lines, "    ")
    sys.stdout.write("\n".join(lines) + "\n")
    return failed


def report_loop(text, lines, indent):
    state, findings = loop_watch(text)
    if state == "none":
        lines.append("%sno frame loop, so none to watch" % indent)
        return 0
    if state == "watched":
        lines.append("%severy frame loop runs under the watch, and a dead loop reports itself" % indent)
        return 0
    lines.append("%sLOOP UNWATCHED:" % indent)
    for finding in findings:
        lines.append("%s  %s" % (indent, finding))
    lines.append("%s  a loop that dies here renders one correct frame and passes every other check" % indent)
    return 1


def check_text(text, name):
    """(lines, failed) for one template's text."""
    found = bodies(text)
    lines = ["  %s" % name]
    if not found:
        lines.append("  no inline script, nothing to parse")
        return lines, 0

    failed = 0
    for at, source in enumerate(found):
        held = source.count("\n") + 1
        ok, why = parses(filled(source))
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

        for clash, var_at, func_at in collisions(source):
            lines.append("  block %d COLLISION on '%s': var at line %d, function at line %d"
                         % (at + 1, clash, var_at, func_at))
            lines.append("    both hoist, the assignment wins, and the first call throws")
            failed += 1
    failed += report_loop(text, lines, "  ")
    return lines, failed


def check(path):
    with io.open(path, encoding="utf-8", newline="") as handle:
        text = handle.read()
    lines, failed = check_text(text, os.path.basename(path))
    sys.stdout.write("\n".join(lines) + "\n\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


# The faults this tool exists for, written out. The tool is asked to find each before it is trusted
# on anything else. A checker that has never caught its own defect is a checker nobody has tested.
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

# A loop under a name that is not turn, scheduling itself: unwatched, and found by what it does.
LOOSE_LOOP = ("<script>\nfunction spinOnce(now) { draw(now); requestAnimationFrame(spinOnce); }\n"
              "requestAnimationFrame(spinOnce);\n</script>\n")
# The same step under the watch, in a template that names the tool.
WATCHED_LOOP = ("<!--NAMESPACE EV-->\n<!--TOOL core/watch-->\n<script>/*SCRIPT*/</script>\n"
                "<script>\nfunction spinOnce(now) { draw(now); }\nEV.watchLoop(\"sample\", spinOnce).wake();\n</script>\n")
# The watch called with the tool left out.
UNTOOLED_LOOP = "<script>\nEV.watchLoop(\"sample\", function () {}).wake();\n</script>\n"
# A built page: the watch's own scheduling sits inside its toolbox piece and is not the page's code.
BUILT_LOOP = ("<script>const EV = {};\n// ---- toolbox/core/clock.js ----\n"
              "EV.nextTurn = (vsync, turn) => requestAnimationFrame(turn);\n"
              "// ---- toolbox/core/watch.js ----\nEV.watchLoop = (label, step) => ({ wake: () => EV.nextTurn(true, step) });\n"
              "// ---- end ----\nEV.watchLoop(\"sample\", () => {}).wake();\n</script>\n")


def _check():
    lines = []
    failed = 0

    def expect(label, ok):
        nonlocal failed
        lines.append("  %s%s" % ("" if ok else "FAIL ", label))
        if not ok:
            failed += 1

    clash = collisions(KNOWN_CLASH)
    expect("the known collision is found: %s" % [one[0] for one in clash], len(clash) == 1 and clash[0][0] == "side")
    expect("a scoped shadow and a near miss stay quiet", collisions(KNOWN_CLEAN) == [])

    # The placeholder substitution could hide a genuine error. A template unparseable only because of
    # its placeholders must pass, and one carrying a placeholder and a real syntax error must fail.
    benign = "/*SCRIPT*/\nconst DATA = /*DATA*/;\nfunction go() { return DATA; }\n"
    ok, why = parses(filled(benign))
    expect("a template with only its slots unfilled parses once filled", ok is True)
    broken = "/*SCRIPT*/\nconst DATA = /*DATA*/;\nfunction go() { return DATA; ;;) }\n"
    ok, why = parses(filled(broken))
    expect("a real syntax error survives the filling and still fails", ok is False)

    state, found = loop_watch(LOOSE_LOOP)
    expect("a loop named spinOnce that schedules itself is unwatched: %s" % state, state == "unwatched")
    state, found = loop_watch(WATCHED_LOOP)
    expect("the same step under EV.watchLoop, the tool named, is watched: %s" % state, state == "watched")
    state, found = loop_watch(UNTOOLED_LOOP)
    expect("EV.watchLoop without core/watch on the page is unwatched: %s" % state, state == "unwatched")
    state, found = loop_watch(BUILT_LOOP)
    expect("frames scheduled inside the toolbox's own pieces are the watch's, not the page's: %s" % state,
           state == "watched")
    state, found = loop_watch("<script>\nvar x = 1;\n</script>\n")
    expect("a page with no loop has none to watch: %s" % state, state == "none")

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")

    for name in sorted(os.listdir(HERE)):
        if name.endswith("_template.html"):
            failed += check(os.path.join(HERE, name))

    # AND THE BUILT PAGES, WITH THEIR REAL DATA IN PLACE. The pass above proves the template's
    # JavaScript is well formed around a `null`; only this one sees what the builder actually
    # substituted. A page present on disk is graded; a page never built is not invented.
    if os.path.isdir(BUILT):
        sys.stdout.write("\n  the built pages, with real data substituted\n")
        for name in sorted(os.listdir(BUILT)):
            if name.endswith(".html"):
                failed += check_built(os.path.join(BUILT, name))
    return failed


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--check" in argv:
        sys.exit(1 if _check() else 0)
    if argv:
        sys.exit(1 if check(argv[0]) else 0)
    sys.stdout.write(__doc__)
    sys.exit(2)
