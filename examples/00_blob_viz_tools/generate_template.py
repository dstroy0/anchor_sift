#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Builds a foo_view.html from foo_view_template.html, taking every shared tool from one toolbox.

    python examples/00_blob_viz_tools/generate_template.py foo_view_template.html
    python examples/00_blob_viz_tools/generate_template.py foo_view_template.html --data foo.json --out foo.html
    python examples/00_blob_viz_tools/generate_template.py --verify build/view/foo_view.html
    python examples/00_blob_viz_tools/generate_template.py --check

ONE GENERATOR, ONE TOOLBOX

A page is a template plus the tools it names. The tools live in toolbox/, listed in
toolbox/manifest.tsv with the tools each one requires, and every page takes its copy of a tool from
there. A builder computes its data and calls `render`; it never pastes code into a page itself. The
page that comes out is one self-contained file: no server, no fetch at run time, openable from disk.

THE TEMPLATE

Directives are HTML comments, each alone on its line, and the generator removes the line:

    <!--NAMESPACE EV-->       the script opens with `const EV = {};`, the object every tool hangs off
    <!--TOOL core/gpu-->      a toolbox tool by its manifest name; the tools it requires come first
    <!--PART object.js-->     a file of the unit's own, read from beside the template

Pieces go into the script in the order their directives appear. A tool another tool requires goes
in once, ahead of its first use. Three slots receive the result:

    /*SCRIPT*/               the namespace line and every JS piece, each under `// ---- label ----`,
                             closed by `// ---- end ----`
    /*STYLE*/                every CSS tool, each under `/* ---- label ---- */`, closed by
                             `/* ---- end ---- */`

The closing label ends the last piece. A template's own code after a slot is never read as part of
a tool.

THE COPYRIGHT LINE

Every page carries toolbox/copyright.html once, at the end of its body: a small gray line fixed at
the top, under the page's control bar where it has one. `assemble` stamps it, and a builder that
writes its own page passes the page through `stamp` before writing.
    /*DATA*/null             the builder's data as JSON; the null keeps an unbuilt template parsing

A slot may hold any whitespace between the marker and its null. A template carries at most one data
slot, and data handed to a template with none is refused instead of dropped.

THE CHECK ON A BUILT PAGE

A tool's label is its toolbox path, `toolbox/core/gpu.js`. `--verify` finds every such label in a
page and holds the text under it to the toolbox file byte for byte. A page built against an edited
copy, or edited after it was built, fails and names the tool.
"""

import io
import json
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLBOX = os.path.join(HERE, "toolbox")

DIRECTIVE = re.compile(r"^[ \t]*<!--(NAMESPACE|TOOL|PART) ([^ >]+)-->[ \t]*\r?\n", re.MULTILINE)
SCRIPT_SLOT = "/*SCRIPT*/"
STYLE_SLOT = "/*STYLE*/"
DATA_SLOT = re.compile(r"/\*DATA\*/\s*null")
KINDS = ("js", "css")
COPYRIGHT = "copyright.html"

# A JS piece's label line, and a CSS piece's. The toolbox prefix marks the pieces --verify holds.
JS_LABEL = "// ---- %s ----"
CSS_LABEL = "/* ---- %s ---- */"
JS_END = JS_LABEL % "end"
CSS_END = CSS_LABEL % "end"
TOOL_LABEL = re.compile(r"(?://|/\*) ---- (toolbox/[^ ]+) ----(?: \*/)?$", re.MULTILINE)


class Refused(Exception):
    """A template or a manifest the generator does not build from, with the reason."""


def read(path):
    with io.open(path, encoding="utf-8", newline="") as handle:
        return handle.read()


def load_manifest(toolbox=TOOLBOX):
    """Every tool by name: its file, the tools it requires, and its kind. Refuses a broken manifest."""
    path = os.path.join(toolbox, "manifest.tsv")
    if not os.path.isfile(path):
        raise Refused("no manifest at %s" % path)
    tools = {}
    rows = read(path).replace("\r\n", "\n").split("\n")
    for number, row in enumerate(rows[1:], 2):
        if not row.strip():
            continue
        cells = row.split("\t")
        if len(cells) != 4:
            raise Refused("manifest line %d: name, file, requires, kind" % number)
        name, file, requires, kind = cells
        if kind not in KINDS:
            raise Refused("manifest line %d: kind %s is not one of %s" % (number, kind, ", ".join(KINDS)))
        if name in tools:
            raise Refused("manifest line %d: %s is listed twice" % (number, name))
        if not os.path.isfile(os.path.join(toolbox, file)):
            raise Refused("manifest line %d: %s has no file %s" % (number, name, file))
        needs = [] if requires == "-" else requires.split(",")
        tools[name] = {"file": file, "requires": needs, "kind": kind}
    for name, tool in tools.items():
        for need in tool["requires"]:
            if need not in tools:
                raise Refused("%s requires %s, and the manifest has no such tool" % (name, need))
    for name in tools:
        expand(name, tools, [], set())
    return tools


def expand(name, tools, order, seen, path=()):
    """Appends `name` to `order` after everything it requires, each tool once. Refuses a cycle."""
    if name in path:
        raise Refused("the manifest requires in a circle: %s" % " -> ".join(path + (name,)))
    if name in seen:
        return order
    if name not in tools:
        raise Refused("no tool called %s in the manifest" % name)
    for need in tools[name]["requires"]:
        expand(need, tools, order, seen, path + (name,))
    seen.add(name)
    order.append(name)
    return order


def pieces_of(template_text, parts_dir, tools, toolbox=TOOLBOX):
    """The namespace, and every piece in order as (label, kind, text). Refuses a missing piece."""
    namespace = None
    pieces = []
    seen = set()
    for found in DIRECTIVE.finditer(template_text):
        what, value = found.group(1), found.group(2)
        if what == "NAMESPACE":
            if namespace is not None:
                raise Refused("two NAMESPACE directives")
            namespace = value
        elif what == "TOOL":
            for name in expand(value, tools, [], seen):
                tool = tools[name]
                label = "toolbox/" + tool["file"]
                pieces.append((label, tool["kind"], read(os.path.join(toolbox, tool["file"]))))
        else:
            path = os.path.join(parts_dir, value)
            if not os.path.isfile(path):
                raise Refused("no part %s beside the template" % value)
            kind = "css" if value.endswith(".css") else "js"
            pieces.append((value, kind, read(path)))
    return namespace, pieces


def fill(page, slot, text, why):
    if page.count(slot) != 1:
        raise Refused("%s, and the template has %d %s slots" % (why, page.count(slot), slot))
    at = page.index(slot)
    return page[:at] + text + page[at + len(slot):]


def assemble(template, data=None, parts_dir=None, toolbox=TOOLBOX):
    """The page text a template builds to. Refuses a template it cannot build exactly."""
    text = read(template)
    tools = load_manifest(toolbox)
    namespace, pieces = pieces_of(text, parts_dir or os.path.dirname(os.path.abspath(template)), tools, toolbox)
    page = DIRECTIVE.sub("", text)

    script = [] if namespace is None else ["const %s = {};" % namespace]
    styles = []
    for label, kind, body in pieces:
        if kind == "css":
            styles.extend([CSS_LABEL % label, body])
        else:
            script.extend([JS_LABEL % label, body])
    if len(script) > (namespace is not None):
        script.append(JS_END)
    if script:
        page = fill(page, SCRIPT_SLOT, "\n".join(script), "the template names script pieces")
    if styles:
        styles.append(CSS_END)
        page = fill(page, STYLE_SLOT, "\n".join(styles), "the template names style tools")

    slots = len(DATA_SLOT.findall(page))
    if slots > 1:
        raise Refused("the template has %d data slots and a page takes one" % slots)
    if data is not None:
        if slots == 0:
            raise Refused("data was given and the template has no /*DATA*/null slot")
        # "</" inside a string would close the script element early; "<\/" is the same JSON string.
        encoded = json.dumps(data, separators=(",", ":")).replace("</", "<\\/")
        page = DATA_SLOT.sub(lambda _found: encoded, page)
    return stamp(page, toolbox)


def stamp(page, toolbox=TOOLBOX):
    """The page with the copyright line at the end of its body: before </body>, or at the end of a page
    whose body is implied. A page already carrying it is returned as it is."""
    if 'id="copyright"' in page:
        return page
    line = read(os.path.join(toolbox, COPYRIGHT))
    at = page.rfind("</body>")
    if at < 0:
        return page.rstrip("\n") + "\n" + line
    return page[:at] + line + page[at:]


def render(template, data=None, out=None, name=None, parts_dir=None):
    """Builds the template and writes the page. Returns the path written.

    `out` is used as given. Without it the page goes where out_path sends generated pages, under
    `name`, which defaults to the template's file name less `_template`.
    """
    page = assemble(template, data, parts_dir)
    if out is None:
        import out_path
        name = name or os.path.basename(template).replace("_template", "")
        out = out_path.resolve(name)
    else:
        parent = os.path.dirname(os.path.abspath(out))
        if not os.path.isdir(parent):
            os.makedirs(parent, exist_ok=True)
    with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)
    return out


def verify_text(page, toolbox=TOOLBOX):
    """Every toolbox piece in a page against its file: (lines, failed)."""
    lines = []
    failed = 0
    for found in TOOL_LABEL.finditer(page):
        label = found.group(1)
        path = os.path.join(toolbox, label[len("toolbox/"):])
        if not os.path.isfile(path):
            lines.append("  %s: NO SUCH TOOL in the toolbox" % label)
            failed += 1
            continue
        want = read(path)
        start = found.end() + 1
        got = page[start:start + len(want)]
        after = page[start + len(want):]
        ends = after.startswith("\n// ---- ") or after.startswith("\n/* ---- ") or \
            re.match(r"\s*</(script|style)>", after) is not None
        if got != want or not ends:
            row = next((at for at, (a, b) in enumerate(zip(got.split("\n"), want.split("\n"))) if a != b),
                       min(got.count("\n"), want.count("\n")))
            lines.append("  %s DIFFERS from the toolbox near its line %d" % (label, row + 1))
            failed += 1
        else:
            lines.append("  %s is the toolbox copy, %d lines" % (label, want.count("\n") + 1))
    if not lines:
        lines.append("  no toolbox pieces, nothing to hold")
    return lines, failed


def verify(path):
    lines, failed = verify_text(read(path))
    sys.stdout.write("  %s\n%s\n\n%d check(s) failed\n" % (os.path.basename(path), "\n".join(lines), failed))
    return failed


# A toolbox and templates written into a scratch directory, each case built to pass or to be refused.
# Every refusal below is a case the generator must be able to reach, and each is shown reached.
def _scratch(files):
    root = tempfile.mkdtemp(prefix="generate_template_")
    for name, text in files.items():
        path = os.path.join(root, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with io.open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
    return root


MANIFEST_HEAD = "name\tfile\trequires\tkind\n"
SAMPLE_TOOLBOX = {
    "box/manifest.tsv": MANIFEST_HEAD + "base\tbase.js\t-\tjs\nturn\tturn.js\tbase\tjs\n"
                        "draw\tdraw.js\tbase,turn\tjs\ntheme\ttheme.css\t-\tcss\n",
    "box/base.js": "NS.base = 1;",
    "box/turn.js": "NS.turn = NS.base + 1;",
    "box/draw.js": "NS.draw = NS.turn + 1;",
    "box/theme.css": ":root { --ink: #000000; }",
    "box/copyright.html": '<div id="copyright">line</div>\n',
}
SAMPLE_TEMPLATE = ("<style>/*STYLE*/\nb { color: red; }</style>\n<!--NAMESPACE NS-->\n<!--TOOL draw-->\n<!--TOOL turn-->\n"
                   "<!--TOOL theme-->\n<!--PART unit.js-->\n<script>/*SCRIPT*/\nvar DATA = /*DATA*/ null;\n"
                   "</script>\n")


def _check():
    lines = []
    failed = 0

    def expect(label, ok):
        nonlocal failed
        lines.append("  %s%s" % ("" if ok else "FAIL ", label))
        if not ok:
            failed += 1

    def refused(files, data=None):
        root = _scratch(dict(SAMPLE_TOOLBOX, **files))
        try:
            assemble(os.path.join(root, "unit_template.html"), data, toolbox=os.path.join(root, "box"))
        except Refused as why:
            return str(why)
        return None

    try:
        tools = load_manifest()
        expect("the real toolbox manifest loads: %d tools, every file present, no cycle" % len(tools), True)
    except Refused as why:
        expect("the real toolbox manifest loads: %s" % why, False)

    root = _scratch(dict(SAMPLE_TOOLBOX, **{"unit_template.html": SAMPLE_TEMPLATE, "unit.js": "NS.unit = 4;"}))
    box = os.path.join(root, "box")
    page = assemble(os.path.join(root, "unit_template.html"), {"x": "</script>"}, toolbox=box)
    order = [page.index(JS_LABEL % ("toolbox/" + name)) for name in ("base.js", "turn.js", "draw.js")]
    expect("required tools come first, in order", order == sorted(order) and page.index("unit.js") > order[-1])
    expect("a tool two others require goes in once", page.count(JS_LABEL % "toolbox/base.js") == 1)
    expect("the script opens with the namespace", "<script>const NS = {};\n" in page)
    expect("directive lines leave nothing behind", "<!--" not in page and "\n\n<script>" not in page)
    expect("the style tool lands in the style slot", "<style>/* ---- toolbox/theme.css ---- */\n:root" in page)
    expect("data fills its slot, and </ inside a string cannot close the script",
           'var DATA = {"x":"<\\/script>"};' in page)
    found, got = verify_text(page, box)
    expect("a fresh page holds every tool byte for byte: %d finding(s)" % got, got == 0 and len(found) == 4)
    moved = page.replace("NS.turn = NS.base + 1;", "NS.turn = NS.base + 2;")
    found, got = verify_text(moved, box)
    expect("a page with one character moved in a tool fails: %d finding(s)" % got, got == 1)
    longer = page.replace("NS.turn = NS.base + 1;", "NS.turn = NS.base + 1; NS.extra = 0;")
    found, got = verify_text(longer, box)
    expect("a page with text added after a tool fails: %d finding(s)" % got, got == 1)
    expect("each slot closes its pieces, ahead of the template's own code",
           "\n/* ---- end ---- */\nb { color: red; }" in page and "\n// ---- end ----\nvar DATA" in page)
    expect("the copyright line sits once, at the end of an implied body",
           page.endswith('</script>\n<div id="copyright">line</div>\n') and page.count('id="copyright"') == 1)
    expect("stamping a stamped page leaves one line", stamp(page, box) == page)
    expect("a page with </body> takes the line just before it",
           stamp("<body><p>x</p></body></html>", box) == '<body><p>x</p><div id="copyright">line</div>\n</body></html>')
    unclosed = page.replace("\n/* ---- end ---- */", "")
    found, got = verify_text(unclosed, box)
    expect("a style tool with the template's own rules run on after it fails: %d finding(s)" % got, got == 1)

    cases = [
        ("two data slots", {"unit_template.html": SAMPLE_TEMPLATE.replace("</script>", "/*DATA*/null</script>"),
                            "unit.js": ""}, {}),
        ("data with no slot", {"unit_template.html": SAMPLE_TEMPLATE.replace("/*DATA*/ null", "0"),
                               "unit.js": ""}, {}),
        ("a tool the manifest lacks", {"unit_template.html": SAMPLE_TEMPLATE.replace("TOOL turn", "TOOL spin"),
                                       "unit.js": ""}, None),
        ("a part missing beside the template", {"unit_template.html": SAMPLE_TEMPLATE}, None),
        ("script pieces with no script slot", {"unit_template.html": SAMPLE_TEMPLATE.replace("/*SCRIPT*/", ""),
                                               "unit.js": ""}, None),
        ("a manifest that requires in a circle", {"unit_template.html": SAMPLE_TEMPLATE, "unit.js": "",
                                                  "box/manifest.tsv": SAMPLE_TOOLBOX["box/manifest.tsv"].replace(
                                                      "base\tbase.js\t-", "base\tbase.js\tdraw")}, None),
        ("a manifest row naming a missing file", {"unit_template.html": SAMPLE_TEMPLATE, "unit.js": "",
                                                  "box/manifest.tsv": SAMPLE_TOOLBOX["box/manifest.tsv"] +
                                                  "ghost\tghost.js\t-\tjs\n"}, None),
    ]
    for label, files, data in cases:
        why = refused(files, data)
        expect("refused, %s: %s" % (label, why or "BUILT"), why is not None)

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d gate check(s) failed\n" % failed)
    return failed


def main(argv):
    if "--check" in argv:
        return 1 if _check() else 0
    if "--verify" in argv:
        paths = [one for one in argv if one != "--verify"]
        return 1 if sum(verify(path) for path in paths) else 0
    if not argv:
        sys.stdout.write(__doc__)
        return 2
    template = argv[0]
    data = None
    out = None
    if "--data" in argv:
        data = json.loads(read(argv[argv.index("--data") + 1]))
    if "--out" in argv:
        out = argv[argv.index("--out") + 1]
    try:
        sys.stdout.write("  wrote %s\n" % render(template, data, out))
    except Refused as why:
        sys.stderr.write("  refused: %s\n" % why)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
