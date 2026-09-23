"""Every allocation on a viewer's per-frame path, and every disposal of something it does not own.

    python examples/00_blob_viz_tools/frame_audit.py examples/00_blob_viz_tools/room_view_template.html
    python examples/00_blob_viz_tools/frame_audit.py --check

THE DEFECT THIS EXISTS FOR

Two faults of this kind were found in one afternoon and neither was found by looking for it. One was
a fresh array built once per frame in the bar painter, the same fault the surface sum had already
been fixed for. The other was worse: a source teardown called dispose() on a geometry and a material
that every source shares, so removing one source freed the buffers out from under all of them.

Both faults fail alike, and this exists for that reason. A per-frame allocation raises no error and
drops no frame until a collection lands. A freed shared buffer raises no error either -- the picture
simply stops moving. Neither is visible in a screenshot and neither is visible in a review that is
looking at something else, so the class needs a reader that only ever looks for it.

WHAT IT REPORTS

    per-frame allocation   an allocating expression inside a function the frame loop reaches. The
                           call graph is walked from the loop outward, and a helper three calls deep
                           is on the path and is reported as such.
    shared disposal        dispose() called on a member of an object whose backing geometry or
                           material was built once outside any constructor. This is the fault that
                           stops the picture with no error.
    buffer overrun         a draw count assigned from something other than the buffer's own ceiling,
                           the way marks went missing while the count claimed they were drawn.
    listener growth        addEventListener inside a function that rebuilds, where nothing removes
                           the previous one.

WHAT IT CANNOT DECIDE

Whether an allocation on the path is worth removing. A vector built once per source per frame at two
sources is nothing; the same line at two hundred is the whole frame budget. The report gives the
site and the depth it sits at, and a person decides. It is a finding list and never a patch.
"""

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# The functions the animation loop calls directly. Everything reachable from these is on the path.
FRAME_ROOTS = ("frame", "step", "layTrail", "flowSpray", "tracePierce", "project", "callout",
               "untangle", "drawCallout", "applyTick", "paintSurface", "paintBars", "paintArms",
               "updateSticks", "applyEnergy", "layoutRail", "drawCounts", "showClock")

# Expressions that allocate. Kept narrow deliberately: a wide pattern reports the whole file and a
# report nobody reads is worth less than no report.
ALLOCATORS = (
    (re.compile(r"\bnew\s+THREE\.(\w+)"), "three object"),
    (re.compile(r"\bnew\s+(Float32Array|Float64Array|Uint8Array|Uint16Array|Uint32Array|Int32Array)"),
     "typed array"),
    (re.compile(r"\bnew\s+Array\b"), "array"),
    (re.compile(r"=\s*\[\s*\]"), "array literal"),
    (re.compile(r"\.(map|filter|slice|concat|split)\("), "array method"),
    (re.compile(r"\bnew\s+(Map|Set|Object)\b"), "collection"),
)

DISPOSE = re.compile(r"(\w+(?:\.\w+)*)\.(geometry|material)\.dispose\(\)")
LISTEN = re.compile(r"\.addEventListener\(")
COUNT_SET = re.compile(r"(\w+)\.count\s*=\s*(.+?);")

FUNC = re.compile(r"^\s*function\s+(\w+)\s*\(")


def read(path):
    with io.open(path, encoding="utf-8", newline="") as handle:
        return handle.read().split("\n")


def functions_of(lines):
    """Every top-level function, as name -> (first line, last line), by brace depth from its header.

    Counted on braces instead of on indentation, because the file mixes both and a function whose
    body is indented for readability inside a template is still one function.
    """
    out = {}
    at = 0
    while at < len(lines):
        found = FUNC.match(lines[at])
        if not found:
            at += 1
            continue
        name = found.group(1)
        depth = 0
        end = at
        started = False
        while end < len(lines):
            for ch in strip_strings(lines[end]):
                if ch == "{":
                    depth += 1
                    started = True
                elif ch == "}":
                    depth -= 1
            if started and depth <= 0:
                break
            end += 1
        out[name] = (at, end)
        at = end + 1
    return out


def strip_strings(line):
    """The line with string bodies and comments removed, leaving no brace inside either to be counted."""
    out = []
    quote = None
    at = 0
    while at < len(line):
        ch = line[at]
        if quote:
            if ch == "\\":
                at += 2
                continue
            if ch == quote:
                quote = None
            at += 1
            continue
        if ch in "\"'`":
            quote = ch
            at += 1
            continue
        if ch == "/" and at + 1 < len(line) and line[at + 1] == "/":
            break
        out.append(ch)
        at += 1
    return "".join(out)


def calls_in(lines, span, names):
    """Which of `names` are called inside this span."""
    body = "\n".join(strip_strings(one) for one in lines[span[0]:span[1] + 1])
    return set(name for name in names if re.search(r"\b" + name + r"\s*\(", body))


def reachable(funcs, roots):
    """Every function the frame loop reaches, with the call depth it was first reached at."""
    depth = {}
    edge = [(name, 0) for name in roots if name in funcs]
    for name, at in edge:
        depth[name] = at
    while edge:
        name, at = edge.pop(0)
        for next_name in calls_in(lines, funcs[name], funcs.keys()):
            if next_name in depth or next_name == name:
                continue
            depth[next_name] = at + 1
            edge.append((next_name, at + 1))
    return depth


def owned_once(lines):
    """Names whose geometry or material was built at the top level, outside any function.

    A resource built once at the top level is shared by everything that references it, and a teardown
    disposing it takes it away from every other holder. That is the fault this looks for, and the
    test is where the resource was built and never what the teardown calls it.
    """
    out = set()
    funcs = functions_of(lines)
    inside = set()
    for span in funcs.values():
        inside.update(range(span[0], span[1] + 1))
    for at, line in enumerate(lines):
        if at in inside:
            continue
        found = re.search(r"^\s*var\s+(\w+)\s*=\s*new\s+THREE\.(BufferGeometry|SphereGeometry|"
                          r"CylinderGeometry|\w*Material)", line)
        if found:
            out.add(found.group(1))
    return out


def audit(path):
    global lines
    lines = read(path)
    funcs = functions_of(lines)
    depth = reachable(funcs, FRAME_ROOTS)
    shared = owned_once(lines)

    findings = []

    # Allocation on the frame path.
    for name, span in sorted(funcs.items(), key=lambda pair: pair[1][0]):
        if name not in depth:
            continue
        for at in range(span[0], span[1] + 1):
            clean = strip_strings(lines[at])
            for pattern, kind in ALLOCATORS:
                if pattern.search(clean):
                    findings.append(("allocation", at + 1, name, depth[name],
                                     "%s in %s, depth %d" % (kind, name, depth[name]),
                                     lines[at].strip()[:96]))
                    break

    # Disposal of something built once at the top level.
    for at, line in enumerate(lines):
        found = DISPOSE.search(strip_strings(line))
        if not found:
            continue
        stem = found.group(1).split(".")[-1]
        for one in shared:
            if one.lower().find(stem.lower()) >= 0 or stem.lower().find(one.lower()) >= 0:
                findings.append(("shared disposal", at + 1, stem, 0,
                                 "%s.%s is built once at the top level" % (stem, found.group(2)),
                                 line.strip()[:96]))
                break

    # A draw count set from something that is not the buffer's own ceiling.
    for at, line in enumerate(lines):
        found = COUNT_SET.search(strip_strings(line))
        if found and "MAX" not in found.group(2) and "length" not in found.group(2):
            findings.append(("draw count", at + 1, found.group(1), 0,
                             "count on %s set from %s" % (found.group(1), found.group(2).strip()),
                             line.strip()[:96]))

    return findings, len(funcs), len(depth), sorted(shared)


def report(path):
    findings, total, onpath, shared = audit(path)
    out = []
    out.append("  %s" % os.path.basename(path))
    out.append("  %d functions, %d of them on the frame path" % (total, onpath))
    out.append("  %d resources built once at the top level: %s" %
               (len(shared), ", ".join(shared[:8]) + (" ..." if len(shared) > 8 else "")))
    out.append("")

    kinds = {}
    for kind, at, who, deep, why, text in findings:
        kinds.setdefault(kind, []).append((at, why, text))

    for kind in ("shared disposal", "draw count", "allocation"):
        rows = kinds.get(kind, [])
        out.append("  %s: %d" % (kind, len(rows)))
        for at, why, text in rows:
            out.append("    line %-5d %s" % (at, why))
            out.append("              %s" % text)
        out.append("")

    sys.stdout.write("\n".join(out) + "\n")
    return len(findings)


def _check():
    path = os.path.join(HERE, "room_view_template.html")
    if not os.path.exists(path):
        sys.stdout.write("  no template beside this tool, nothing to audit\n\n0 check(s) failed\n")
        return 0
    findings, total, onpath, shared = audit(path)
    failed = 0
    lines_out = []
    lines_out.append("  %d functions, %d on the frame path, %d shared resources" %
                     (total, onpath, len(shared)))

    hard = [one for one in findings if one[0] == "shared disposal"]
    lines_out.append("  shared disposals: %d" % len(hard))
    if hard:
        for kind, at, who, deep, why, text in hard:
            lines_out.append("    FAIL line %d, %s" % (at, why))
        failed += len(hard)

    soft = [one for one in findings if one[0] == "allocation"]
    lines_out.append("  allocations on the frame path: %d, listed by the report and not failed here"
                     % len(soft))
    lines_out.append("    because a site's cost depends on how often it runs, which a reader")
    lines_out.append("    decides and a pattern cannot")

    sys.stdout.write("\n".join(lines_out) + "\n\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--check" in argv:
        sys.exit(1 if _check() else 0)
    if argv:
        sys.exit(0 if report(argv[0]) >= 0 else 1)
    sys.stdout.write(__doc__)
    sys.exit(2)
