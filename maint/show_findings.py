"""Prints each prose finding with the whole line it sits on, ready to be rewritten.

Fixing a finding needs the sentence, not the token. The gate prints a file, a line and a phrase,
which is enough to locate but not enough to rewrite, and rewriting from the phrase alone is how a
replacement ends up saying less than the original did.

    python maint/show_findings.py src hooks          # checked kinds
    python maint/show_findings.py --unread src       # kinds the gate does not read
    python maint/show_findings.py --tsv src          # tab separated, for building a fix table

One line of output per finding, so two findings on one source line appear twice and both get
rewritten in the same pass instead of one being cleared and the other left standing.
"""

import io
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHECK = os.path.join(HERE, "tools", "prose", "docs_check.py")
UNREAD = os.path.join(os.path.dirname(os.path.abspath(__file__)), "grade_unread.py")

SITE = re.compile(r"^\s*(?:prose|BREAK)\s+(.+?):(\d+):\s*(.*)$")


def main():
    argv = [one for one in sys.argv[1:] if not one.startswith("-")]
    unread = "--unread" in sys.argv
    as_tsv = "--tsv" in sys.argv
    targets = argv or ["src"]

    if unread:
        call = [sys.executable, UNREAD] + targets
    else:
        call = [sys.executable, CHECK] + targets
    done = subprocess.run(call, capture_output=True, text=True)

    held = {}
    shown = 0
    for line in (done.stdout + done.stderr).split("\n"):
        found = SITE.match(line)
        if not found:
            continue
        name, number, what = found.group(1), int(found.group(2)), found.group(3)
        path = name if os.path.isabs(name) else os.path.join(HERE, name)
        if path not in held:
            try:
                with io.open(path, encoding="utf-8", errors="replace") as handle:
                    held[path] = handle.read().split("\n")
            except OSError:
                held[path] = []
        lines = held[path]
        text = lines[number - 1] if 0 < number <= len(lines) else "<line not found>"
        token = what.split("'")[1] if "'" in what else what
        if as_tsv:
            print("%s\t%d\t%s\t%s" % (name, number, token, text))
        else:
            print("%s:%d  [%s]" % (name, number, token))
            print("    %s" % text.rstrip())
        shown += 1

    if not as_tsv:
        print("")
        print("%d finding(s) with their lines" % shown)
    return 0


if __name__ == "__main__":
    sys.exit(main())
