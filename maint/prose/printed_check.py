"""The prose standard, applied to the text these tools print instead of the text they carry.

    python tools/prose/printed_check.py [root ...]

WHY THIS EXISTS

`docs_check.py` reads the comments and docstrings of a source file and blanks the code. For a
library, blanking the code is correct. The checkers in `tools/view` are not shaped like libraries
when they run: each one prints several paragraphs of argument about what it measured, and a person
reads those paragraphs the way they read a page. None of that text sits in a comment, so none of it
was gated.

The gap was found by reading output instead of by any check, and it had already let two findings
through into tools written under the standard.

docs-check: quoting
`quotient_coherence` printed 'which is the average of those two' and `reading_rank` printed
'which is why 64 distinct signatures out of 64 rounds is not evidence'.
docs-check: end quoting

Both phrases sit on the banned table, both sat in text a reader sees, and both survived a clean run
of `docs_check`.

WHAT IT READS

The string literals handed to `say`, `print` and `sys.stdout.write`, taken from the parse tree so
that a string built across several lines is read once and a string in a comment is not read twice.
The banned table comes from `docs_check` itself through the symlink in this directory, so there is
one table and this file does not hold a copy of it to drift.

Exit status follows `docs_check`: zero clean, one for findings, two for the sentinel that says no
file was read. Never a count. `docs_check` records why, and the reasons apply here unchanged: a count
wraps at 256, so 256 findings would exit clean, and returning 2 for a real pair of findings is
indistinguishable from the run that read nothing.
"""

import ast
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import docs_check

# The calls whose arguments reach a reader. `write` covers `sys.stdout.write` without needing to
# know what the module was imported as.
REPORTING = ("say", "print", "write")

DEFAULT_ROOTS = (os.path.join(os.path.dirname(HERE), "view"),)


def patterns():
    return [(one, re.compile(one, re.IGNORECASE)) for one in docs_check.BANNED]


def printed_strings(path):
    """Every string literal reaching a reader, as (line, text), each reported once.

    A literal nested inside a formatting expression is reached once through the call it sits in.
    Walking the call would reach it again for every enclosing node, so the visited set is by
    position and not by value: two identical sentences on different lines are two findings.
    """
    with open(path, "r", encoding="utf-8") as handle:
        tree = ast.parse(handle.read(), path)

    seen = set()
    out = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if isinstance(node.func, ast.Name):
            name = node.func.id
        elif isinstance(node.func, ast.Attribute):
            name = node.func.attr
        else:
            continue
        if name not in REPORTING:
            continue
        for piece in ast.walk(node):
            if not isinstance(piece, ast.Constant) or not isinstance(piece.value, str):
                continue
            where = (piece.lineno, piece.col_offset)
            if where in seen:
                continue
            seen.add(where)
            out.append((piece.lineno, piece.value))
    return sorted(out)


def sources_under(root):
    if os.path.isfile(root):
        return [root] if root.endswith(".py") else []
    out = []
    for here, folders, files in os.walk(root):
        folders[:] = [one for one in folders if one != "__pycache__"]
        out.extend(os.path.join(here, one) for one in files if one.endswith(".py"))
    return sorted(out)


def main():
    roots = sys.argv[1:] or list(DEFAULT_ROOTS)
    table = patterns()
    found = 0
    checked = 0
    for root in roots:
        for path in sources_under(root):
            checked += 1
            try:
                strings = printed_strings(path)
            except SyntaxError as trouble:
                sys.stdout.write("  unreadable %s: %s\n" % (path, trouble))
                found += 1
                continue
            for line, text in strings:
                # One site is one finding. Several patterns in the table overlap and match the same
                # span, and reporting each of them printed the same line twice with nothing to tell
                # the two apart. The first hit names the site and the writer fixes the sentence.
                for _, pattern in table:
                    hit = pattern.search(text)
                    if hit:
                        sys.stdout.write("  printed %s:%d: token '%s' in: %s\n"
                                         % (os.path.relpath(path), line, hit.group(0),
                                            " ".join(text.split())[:72]))
                        found += 1
                        break
    sys.stdout.write("  %d file(s) checked, %d finding(s) in printed text\n" % (checked, found))

    # An empty run is not a clean run, and the reasoning here is `docs_check`'s. Reporting success
    # over zero files hides the failure a hook cannot see, and pointing this at a path that does not
    # exist is the everyday way to arrive there.
    if checked == 0:
        sys.stdout.write("  no files were read. Nothing was checked, so nothing passed.\n")
        for one in roots:
            sys.stdout.write("    %s%s\n" % (one, "" if os.path.exists(one) else "   does not exist"))
        return 2
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
