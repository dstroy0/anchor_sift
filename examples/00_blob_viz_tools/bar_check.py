"""Does every built page carry the shared control bar byte for byte, or has a copy drifted?

    python examples/00_blob_viz_tools/bar_check.py build/view/sha_clock_view.html
    python examples/00_blob_viz_tools/bar_check.py build/view/*.html
    python examples/00_blob_viz_tools/bar_check.py --check

THE DEFECT THIS EXISTS FOR

A builder injects control_bar.js whole into the page at a marker. Every page that carries the bar
carries a copy of that one file, and nothing otherwise holds the copies to their source. A page
built against an edited-in-place bar, or a builder that rewrites the text on the way in, ships a bar
that has drifted from the one shared source. The single option model then splits into several that
only look alike.

WHAT IT DOES

Reads control_bar.js, pulls the bar out of each page's inline script, and compares the two. A page
with no bar passes and says so. A page whose bar matches the source passes. A page whose bar differs
fails and names the first line that diverges. A source it cannot read is reported and never treated
as a pass, because a check that cannot run is not a check that succeeded.

The bar is the inline script whose body holds the source's own opening, the line that assigns
window.BAR. A reference to BAR.mount elsewhere in the page is a use of the bar and not a copy of it,
and it is left alone.
"""

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(HERE, "control_bar.js")

# Inline bodies only. A src attribute names a file this tool is not responsible for.
BLOCK = re.compile(r"<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>", re.DOTALL | re.IGNORECASE)

# The line a copy of the bar always carries, and a use of the bar never does.
SIGNATURE = "window.BAR = (function"


def read_source():
    """The bar source as text, or None with a reason. Read as the builder reads it to inject it."""
    try:
        with io.open(SOURCE, encoding="utf-8") as handle:
            return handle.read(), ""
    except OSError as broken:
        return None, "%s" % broken


def bar_blocks(text):
    """Every inline script body that is a copy of the bar, by its signature line."""
    return [body for body in BLOCK.findall(text) if SIGNATURE in body]


def first_divergence(page_body, source):
    """The first line where the page's bar and the source differ, or None when they match."""
    page_lines = page_body.split("\n")
    source_lines = source.split("\n")
    for at in range(max(len(page_lines), len(source_lines))):
        here = page_lines[at] if at < len(page_lines) else "<no line>"
        want = source_lines[at] if at < len(source_lines) else "<no line>"
        if here != want:
            return at + 1, here, want
    return None


def scan(text, source):
    """The findings for one page's text against the source: (lines, failed)."""
    lines = []
    blocks = bar_blocks(text)
    if not blocks:
        lines.append("  no control bar, nothing to check")
        return lines, 0

    failed = 0
    held = source.count("\n") + 1
    for at, body in enumerate(blocks):
        diverged = first_divergence(body, source)
        if diverged is None:
            lines.append("  bar block %d is the source, %d lines" % (at + 1, held))
        else:
            row, here, want = diverged
            lines.append("  bar block %d DIFFERS from the source at line %d" % (at + 1, row))
            lines.append("    page:   %s" % here.strip())
            lines.append("    source: %s" % want.strip())
            lines.append("    a page's bar is the one shared file byte for byte, or the model has split")
            failed += 1
    return lines, failed


def check(path):
    source, why = read_source()
    lines = ["  %s" % os.path.basename(path)]
    if source is None:
        lines.append("  SOURCE NOT READ: %s" % why)
        sys.stdout.write("\n".join(lines) + "\n\n1 check(s) failed\n")
        return 1

    with io.open(path, encoding="utf-8") as handle:
        text = handle.read()
    found, failed = scan(text, source)
    lines.extend(found)
    sys.stdout.write("\n".join(lines) + "\n\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


def check_all(paths):
    total = 0
    for path in paths:
        total += check(path)
    return total


# A page carrying the bar whole, one carrying it with a single character moved, and one carrying no
# bar at all. The gate exists to pass the first and the third and fail the second, and a checker
# nobody has seen fire is a checker nobody has tested.
def _sample(body):
    return "<!doctype html>\n<html><head><script>%s</script></head><body></body></html>\n" % body


def _check():
    lines = []
    failed = 0

    source, why = read_source()
    if source is None:
        sys.stdout.write("  SOURCE NOT READ: %s\n\n1 gate check(s) failed\n" % why)
        return 1

    clean = _sample(source)
    found, got = scan(clean, source)
    lines.append("  a page carrying the bar whole: %d finding(s), expecting 0" % got)
    if got != 0:
        lines.extend(found)
        failed += 1

    # One byte moved, away from the signature line. The block is still found and then seen to differ.
    # A drift that corrupts the signature would read as no bar; this proves it reads as a changed bar.
    moved = source.replace('"#000000"', '"#000001"', 1)
    if moved == source:
        lines.append("  FAIL the sample could not be perturbed, so the negative was not tested")
        failed += 1
    else:
        drift = _sample(moved)
        found, got = scan(drift, source)
        lines.append("  a page whose bar has one character moved: %d finding(s), expecting 1" % got)
        if got != 1:
            lines.extend(found)
            failed += 1

    none = _sample("var x = 1; BAR = null;")
    found, got = scan(none, source)
    lines.append("  a page with no bar: %d finding(s), expecting 0" % got)
    if got != 0:
        lines.extend(found)
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d gate check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--check" in argv:
        sys.exit(1 if _check() else 0)
    if argv:
        sys.exit(1 if check_all(argv) else 0)
    sys.stdout.write(__doc__)
    sys.exit(2)
