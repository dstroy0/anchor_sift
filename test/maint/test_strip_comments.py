#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Grade maint/source/strip_comments.py on inputs whose stripped form was worked out by hand.
#
#   python test/maint/test_strip_comments.py
#
# Every expected output below was written by reading the input, not by running the tool, so a
# defect in the tool cannot also be a defect in its expectation. The negative controls are inputs
# the tool must refuse. A check that has never refused anything cannot be told apart from one that
# refuses nothing, and these are what show the refusals fire.

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "maint", "source"))

import strip_comments  # noqa: E402

PYTHON_IN = (
    "#!/usr/bin/env python3\n"
    "# header comment\n"
    '"""Module doc."""\n'
    "import os  # trailing\n"
    "\n"
    "\n"
    "def f(x):\n"
    '    """Doc of f."""\n'
    "    return x  # why\n"
    "\n"
    "\n"
    "class K:\n"
    '    "one line doc"\n'
    "\n"
    "    def g(self):\n"
    '        """only a docstring"""\n'
    'HASH = "#not a comment"  # a comment\n'
)

# The shebang stays, the whole-line comment and module docstring go, both trailing comments go, the
# blank pair collapses to one, the class docstring goes, and g keeps a pass for its emptied body.
PYTHON_OUT = (
    "#!/usr/bin/env python3\n"
    "import os\n"
    "\n"
    "def f(x):\n"
    "    return x\n"
    "\n"
    "class K:\n"
    "\n"
    "    def g(self):\n"
    "        pass\n"
    'HASH = "#not a comment"\n'
)

SHELL_IN = (
    "#!/usr/bin/env bash\n"
    "# whole line\n"
    "set -u  # trailing\n"
    "echo \"a # b\" 'c # d' e#f ${#ARR[@]} $#\n"
    "cat <<END\n"
    "# kept, inside a heredoc body\n"
    "END\n"
    "x=1 # gone\n"
)

# A # in quotes, inside a word, in ${#...}, in $# and in a heredoc body is not a comment.
SHELL_OUT = (
    "#!/usr/bin/env bash\n"
    "set -u\n"
    "echo \"a # b\" 'c # d' e#f ${#ARR[@]} $#\n"
    "cat <<END\n"
    "# kept, inside a heredoc body\n"
    "END\n"
    "x=1\n"
)

C_IN = 'int a; // x\n/* y\n z */ int b = "//s";\n'

# The block comment leaves its one newline, the line comment leaves none, the literal survives.
C_OUT = 'int a;\n\n int b = "//s";\n'


def refusal(text, suffix):
    """The reason rewrite refuses the text, or an empty string where it accepts it."""
    try:
        strip_comments.rewrite(text, False, suffix)
    except (ValueError, SyntaxError) as why:
        return str(why)
    return ""


def main():
    failures = []

    def grade(name, got, wanted):
        verdict = "ok" if got == wanted else "WRONG"
        print("  %-52s %s" % (name, verdict))
        if got != wanted:
            failures.append(name)
            print("    got    %r" % got)
            print("    wanted %r" % wanted)

    grade("python: comments, docstrings, emptied body",
          strip_comments.rewrite(PYTHON_IN, False, ".py"), PYTHON_OUT)
    grade("shell: # only where it opens a word",
          strip_comments.rewrite(SHELL_IN, False, ".sh"), SHELL_OUT)
    grade("c: line and block comments, literal kept",
          strip_comments.rewrite(C_IN, False, ".c"), C_OUT)

    # Negative controls. Each must be refused by the check its name gives, and the refusal message
    # is matched to confirm that check fired and not some other one.
    grade("refuses a docstring sharing its line with code (line test)",
          "shares its line with code" in refusal('x = 1; "doc"\n', ".py"), True)
    grade("refuses a string the blank collapse would change (tree test)",
          "different tree" in refusal('TEMPLATE = """a\n\n\nb"""\n', ".py"), True)
    grade("refuses a script bash -n rejects (bash -n test)",
          "bash -n refuses" in refusal("#!/usr/bin/env bash\nif true; then\n", ".sh"), True)

    # A second pass over a stripped file changes nothing.
    grade("python strip is idempotent",
          strip_comments.rewrite(PYTHON_OUT, False, ".py"), PYTHON_OUT)
    grade("shell strip is idempotent",
          strip_comments.rewrite(SHELL_OUT, False, ".sh"), SHELL_OUT)

    print("\n  %d check(s) failed" % len(failures))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
