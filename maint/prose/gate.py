"""The whole prose gate for this tree, in one command.

    python maint/prose/gate.py [root ...] [--strict]

Three things have to run before any page or tool here is offered, and running two of them is how
findings have shipped twice.

    docs_check      comments, docstrings, markdown and TeX. The standard and the banned table.
    the .cu files   the same check, over an extension the shipped tuple does not name.
    printed_check   the text a tool prints, which docs_check blanks along with the code.

WHY THE EXTENSION LINE IS HERE

`docs_check.CHECKED` is `('.md', '.py', '.c', '.h', '.tex')`. It names the two C extensions this
tree barely uses and omits the two it is written in. Counting source files: 3 `.c`, 9 `.h`, and
against those 38 `.cpp` and 12 `.cu`. Fifty files of C-family source carry long argued note blocks
that the gate has never read, and passing one of their paths explicitly gets it skipped without a
word, so three paths in gives two files checked.

`prose_only` needs no change to handle them. It names `.md`, `.tex` and `.py` and falls through to
the C comment branch for everything else, which is already correct for CUDA. Only the tuple stands
in the way, so this extends the tuple in memory for the length of the run and touches nothing on
disk. The finding belongs upstream in `anchor_sift/maint/prose/docs_check.py`, where one line adds
`.cu` for every tree at once, and it is recorded as owed there. This is the local stand-in and it
should be deleted when that lands.

The override is announced in the output. A gate that quietly checks more than the file it borrows
its table from says would be a worse defect than the one it closes.
"""

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import docs_check
import printed_check

# The extensions the shipped tuple omits. Kept as a name so the announcement below and the override
# cannot drift apart.
MISSING = (".cu", ".cpp", ".html")


def with_the_extensions(names):
    """The shipped tuple plus anything it omits, without a duplicate if it is ever added upstream."""
    return names + tuple(one for one in MISSING if one not in names)


# What a generated page carries where its template carries a placeholder. A builder replaces the
# marker with the data, and a page holding the assignment without the marker was written by a tool.
BUILT = "var DATA = {"
MARKER = "_DATA*/null"


def generated(path):
    """Whether an .html file was written by a builder instead of by a person.

    Only the first stretch is read. The assignment sits near the top of the script and a built page
    can run to hundreds of kilobytes, most of it one line of data.
    """
    try:
        with io.open(path, "r", encoding="utf-8", errors="replace") as handle:
            head = handle.read(400000)
    except OSError:
        return False
    return BUILT in head and MARKER not in head


def without_generated(paths):
    """The same list with generated pages dropped, and the count of what went.

    A generated page's prose is its template's prose. Reporting both counts one defect twice and
    points the writer at the copy, which the next build overwrites. The template is the file to fix
    and the only one worth reporting.
    """
    kept = [one for one in paths if not (one.endswith(".html") and generated(one))]
    return kept, len(paths) - len(kept)


def run(module, roots, strict):
    """One checker, given the roots, with argv restored afterwards."""
    held = sys.argv
    sys.argv = [module.__name__] + list(roots) + (["--strict"] if strict else [])
    try:
        return module.main()
    finally:
        sys.argv = held


def main():
    strict = "--strict" in sys.argv[1:]
    roots = [one for one in sys.argv[1:] if not one.startswith("-")]

    shipped = docs_check.CHECKED
    docs_check.CHECKED = with_the_extensions(shipped)
    added = tuple(one for one in docs_check.CHECKED if one not in shipped)

    # Generated pages are dropped by wrapping the walk, for the same reason the tuple is patched
    # here: the change belongs upstream and this is the local stand-in until it lands.
    walked = docs_check.walk_markdown
    skipped = [0]

    def walk_without_generated(where):
        kept, dropped = without_generated(walked(where))
        skipped[0] += dropped
        return kept

    docs_check.walk_markdown = walk_without_generated

    sys.stdout.write("  the standard, over comments, docstrings, markdown and TeX\n")
    if added:
        sys.stdout.write("    extensions added for this run: %s   (see this file's header)\n"
                         % " ".join(added))
    try:
        worst = run(docs_check, roots, strict)
    finally:
        docs_check.walk_markdown = walked
    if skipped[0]:
        sys.stdout.write("    %d generated page(s) skipped, since a built page's prose is its\n"
                         "    template's prose and the template is the file to fix\n" % skipped[0])

    sys.stdout.write("\n  the text these tools print, which the check above blanks\n")
    # printed_check parses Python. A root holding only markdown, TeX or C reads zero files and
    # returns the sentinel, which is correct for that root and wrong to merge into a gate status:
    # the caller asked about pages and got told the Python half found nothing. Reported separately.
    printed = run(printed_check, roots, strict)
    if printed == 2:
        sys.stdout.write("    no Python under the given roots, so this half checked nothing\n")
    elif printed:
        worst = max(worst, printed)

    sys.stdout.write("\n  gate status %d\n" % worst)
    return worst


if __name__ == "__main__":
    sys.exit(main())
