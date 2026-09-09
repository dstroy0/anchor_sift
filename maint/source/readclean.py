#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Three reading passes over a source file. Writes nothing, ever.

  code   <file> ...    comments stripped: the structure, with nothing to take on trust
  blind  <file> ...    comments stripped AND every name this project chose replaced, so the code
                       is read for what it DOES instead of for what it is called
  claims <file> ...    every comment paired with the code under it, so the prose can be checked
                       against what the code does instead of read as if it were true

  --keep a,b,c         names to leave alone under blind
  --lang py|c|r|m      read the file as this language instead of guessing from its extension

WHY BLIND. A name is a claim, and it is the claim nobody checks. A function called `verify` is read
as verifying. A variable called `clean` is read as clean. With the names replaced, only what the
statements do is left, and anything that then looks wrong is wrong instead of being a mismatch the
reader was primed not to see.

WHY CLAIMS. A comment is a promise about the code under it, made when the code looked different.
Pairing the two puts the promise beside what kept it or broke it. Everything else in this tree that
reads comments is checking how they are written; this one is for whether they are still true.

THE LANGUAGES ARE THE ONES src/ HAS

  .py            Python, and most of the tree is Python. The engine, the tools and the examples
                 are Python and everything else is a port of the measure.
  .c .h          C, the search kernel.
  .R .r          R, the measure port.
  .m             MATLAB and Octave, the other measure port.

Python is read with tokenize. A `#` inside a string stays inside the string, and a docstring is
recognized as the statement it is. The other three are read with a scanner that tracks string and
character literals, which is enough for these files and is not a parser.

WHERE THE SCANNER IS APPROXIMATE, AND IT SAYS SO

MATLAB writes a transpose and a string delimiter with the same character. `a'` is a transpose and
`'a'` is a string, and telling them apart needs to know whether the previous token was a value. The
scanner uses that rule: a quote straight after an identifier, a digit, a closing bracket or a dot
is a transpose, and anything else opens a string. That is right for ordinary code and it can be
fooled. A file where it matters gets read with --lang and a human eye.

Nothing here writes to the file it reads. Every mode prints.
"""

import ast
import io
import os
import re
import sys
import tokenize

# Per language: the line comment, the block comment, the quotes that open a string, and whether a
# backslash escapes inside one.
LANGUAGES = {
    "py": {"line": "#", "block": None, "quotes": "\"'", "escape": True},
    "c": {"line": "//", "block": ("/*", "*/"), "quotes": "\"'", "escape": True},
    "r": {"line": "#", "block": None, "quotes": "\"'", "escape": True},
    "m": {"line": "%", "block": ("%{", "%}"), "quotes": "\"'", "escape": False},
}

BY_SUFFIX = {".py": "py", ".c": "c", ".h": "c", ".R": "r", ".r": "r", ".m": "m"}

# Names a language supplies. Blinding these would leave text nobody can read.
KEYWORDS = {
    "py": set(dir(__builtins__) if isinstance(__builtins__, type(sys)) else __builtins__) | {
        "self", "cls", "def", "class", "return", "import", "from", "as", "if", "elif", "else",
        "for", "while", "try", "except", "finally", "with", "lambda", "yield", "raise", "assert",
        "global", "nonlocal", "pass", "break", "continue", "and", "or", "not", "in", "is",
        "True", "False", "None", "os", "sys", "io", "re", "math", "json", "time", "hashlib"},
    "c": {"int", "char", "long", "short", "float", "double", "void", "unsigned", "signed",
          "const", "static", "extern", "struct", "union", "enum", "typedef", "sizeof", "return",
          "if", "else", "for", "while", "do", "switch", "case", "default", "break", "continue",
          "goto", "inline", "restrict", "volatile", "register", "NULL", "size_t", "uint8_t",
          "uint16_t", "uint32_t", "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t", "bool"},
    "r": {"function", "if", "else", "for", "while", "repeat", "break", "next", "return", "TRUE",
          "FALSE", "NULL", "NA", "Inf", "NaN", "in", "library", "require", "c", "length", "sum",
          "mean", "seq", "rep", "which", "sort", "table", "matrix", "list", "vector", "sapply",
          "lapply", "vapply", "nrow", "ncol", "max", "min", "abs", "log", "exp", "sqrt", "print"},
    "m": {"function", "end", "if", "elseif", "else", "for", "while", "switch", "case", "otherwise",
          "break", "continue", "return", "true", "false", "nargin", "nargout", "numel", "length",
          "size", "zeros", "ones", "sum", "mean", "sort", "find", "max", "min", "abs", "log",
          "exp", "sqrt", "disp", "error", "fprintf", "isempty", "unique", "histc", "accumarray"},
}

WORD = re.compile(r"[A-Za-z_][A-Za-z_0-9]*")

# What each language's definitions look like, for blind. One pattern per kind, and the kind names
# the placeholder, which leaves a reader able to tell a function from a variable.
DEFINED = {
    "py": (("fn", re.compile(r"^\s*(?:async\s+)?def\s+([A-Za-z_]\w*)", re.M)),
           ("cls", re.compile(r"^\s*class\s+([A-Za-z_]\w*)", re.M)),
           ("var", re.compile(r"^([A-Za-z_]\w*)\s*=", re.M))),
    "c": (("fn", re.compile(r"^[A-Za-z_][\w \t*]*?\b([A-Za-z_]\w*)\s*\([^;]*\)\s*\{", re.M)),
          ("ty", re.compile(r"\btypedef\b[^;]*?\b([A-Za-z_]\w*)\s*;", re.S)),
          ("mac", re.compile(r"^\s*#\s*define\s+([A-Za-z_]\w*)", re.M))),
    "r": (("fn", re.compile(r"^\s*([A-Za-z_.][\w.]*)\s*(?:<-|=)\s*function", re.M)),
          ("var", re.compile(r"^\s*([A-Za-z_.][\w.]*)\s*<-(?!\s*function)", re.M))),
    "m": (("fn", re.compile(r"^\s*function\s+(?:\[[^\]]*\]|\w+)\s*=\s*([A-Za-z_]\w*)", re.M)),
          ("fn", re.compile(r"^\s*function\s+([A-Za-z_]\w*)\s*\(", re.M))),
}


def language_of(path, given):
    """Which language to read a file as."""
    if given:
        return given
    return BY_SUFFIX.get(os.path.splitext(path)[1], "py")


def header_of(lines):
    """The licence block at the top, which states a licence instead of describing code."""
    if not lines:
        return []

    # A C licence block opens with /* and runs to its close, and it carries description lines
    # after the SPDX line. Stopping at the first of those printed an opening with no closing,
    # which reads as a file that will not compile.
    if lines[0].lstrip().startswith("/*"):
        held = []
        for line in lines:
            held.append(line)
            if line.rstrip().endswith("*/"):
                break
        return held

    held = []
    for line in lines:
        bare = line.strip()
        if bare.startswith(("#!", "#", "//", "%")) and (
                "Copyright" in line or "SPDX" in line or bare in ("#", "//", "%")
                or bare.startswith("#!")):
            held.append(line)
            continue
        break
    return held


def split_python(text):
    """Every line as (code, comment), using tokenize, which never guesses at a quote.

    A docstring is an expression statement holding one string, and it is a comment for reading
    purposes even though the language keeps it at runtime.
    """
    code = text.split("\n")
    comments = [[] for _ in code]
    blanked = list(code)
    try:
        marks = list(tokenize.generate_tokens(io.StringIO(text).readline))
    except (tokenize.TokenError, IndentationError, SyntaxError):
        return code, comments

    # A docstring is the first statement of a module, class or function body, and asking the
    # parser is the only way to know that. Guessing from the token before it read every dict value
    # after a colon as a docstring and deleted it: DOMAIN in catalog.py came out with every key
    # present and every value gone.
    strings = set()
    try:
        tree = ast.parse(text)
    except SyntaxError:
        tree = None
    if tree is not None:
        for node in ast.walk(tree):
            if not isinstance(node, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef,
                                     ast.ClassDef)):
                continue
            body = getattr(node, "body", None)
            if not body:
                continue
            first = body[0]
            if (isinstance(first, ast.Expr) and isinstance(first.value, ast.Constant)
                    and isinstance(first.value.value, str)):
                strings.add((first.value.lineno, first.value.col_offset))

    cut = []
    for mark in marks:
        if mark.type == tokenize.COMMENT:
            row = mark.start[0] - 1
            comments[row].append(mark.string)
            cut.append((mark.start, mark.end))
        elif mark.type == tokenize.STRING and mark.start in strings:
            for row in range(mark.start[0] - 1, mark.end[0]):
                comments[row].append("<docstring>")
            cut.append((mark.start, mark.end))

    for (srow, scol), (erow, ecol) in cut:
        srow -= 1
        erow -= 1
        if srow == erow:
            blanked[srow] = blanked[srow][:scol] + blanked[srow][ecol:]
        else:
            blanked[srow] = blanked[srow][:scol]
            for row in range(srow + 1, erow):
                blanked[row] = ""
            blanked[erow] = blanked[erow][ecol:]
    return blanked, comments


def split_scanned(text, profile):
    """Every line as (code, comment), for a language read with a character scanner."""
    line_mark = profile["line"]
    block = profile["block"]
    quotes = profile["quotes"]
    escape = profile["escape"]

    code = []
    comments = []
    in_block = False
    for raw in text.split("\n"):
        kept = []
        said = []
        at = 0
        quote = None
        previous = ""
        while at < len(raw):
            rest = raw[at:]
            if in_block:
                if block and rest.startswith(block[1]):
                    in_block = False
                    said.append(block[1])
                    at += len(block[1])
                    continue
                said.append(raw[at])
                at += 1
                continue
            if quote:
                kept.append(raw[at])
                if escape and raw[at] == "\\" and at + 1 < len(raw):
                    kept.append(raw[at + 1])
                    at += 2
                    continue
                if raw[at] == quote:
                    quote = None
                at += 1
                continue
            if block and rest.startswith(block[0]):
                in_block = True
                said.append(block[0])
                at += len(block[0])
                continue
            if rest.startswith(line_mark):
                said.append(rest)
                break
            if raw[at] in quotes:
                # MATLAB writes transpose with the same character as a string delimiter. A quote
                # straight after a value is a transpose; anything else opens a string.
                if raw[at] == "'" and previous and (previous.isalnum()
                                                    or previous in ")]}._'"):
                    kept.append(raw[at])
                    previous = raw[at]
                    at += 1
                    continue
                quote = raw[at]
            kept.append(raw[at])
            if not raw[at].isspace():
                previous = raw[at]
            at += 1
        code.append("".join(kept))
        comments.append(["".join(said)] if said else [])
    return code, comments


def split(text, language):
    if language == "py":
        return split_python(text)
    return split_scanned(text, LANGUAGES[language])


def defined_names(text, language, keep):
    """The names this file chose, as name against the placeholder it takes under blind."""
    counts = {}
    held = {}
    for kind, pattern in DEFINED.get(language, ()):
        for found in pattern.finditer(text):
            name = found.group(1)
            if name in held or name in keep or name in KEYWORDS.get(language, set()):
                continue
            if len(name) < 2:
                continue
            counts[kind] = counts.get(kind, 0) + 1
            held[name] = "%s%d" % (kind, counts[kind])
    return held


def blinded(code, names, language):
    """The code with every chosen name replaced by its placeholder.

    A name inside a string literal is data and stays. Rewriting those turned
    os.path.join(ROOT, "examples") into os.path.join(var2, "fn2"), because this file happens to
    define a function called examples, and the reader is then looking at a path that does not
    exist. Python is masked with tokenize, which is exact. The others are masked by scanning for
    quotes, the same approximation the comment scanner already makes.
    """
    if not names:
        return code
    pattern = re.compile(r"\b(%s)\b" % "|".join(re.escape(one) for one in
                                                sorted(names, key=len, reverse=True)))

    def swap(line):
        return pattern.sub(lambda found: names[found.group(1)], line)

    if language == "py":
        held = []
        for line in code:
            try:
                marks = list(tokenize.generate_tokens(io.StringIO(line).readline))
            except (tokenize.TokenError, IndentationError, SyntaxError):
                held.append(swap(line))
                continue
            spans = sorted((mark.start[1], mark.end[1]) for mark in marks
                           if mark.type == tokenize.STRING and mark.start[0] == mark.end[0] == 1)
            if not spans:
                held.append(swap(line))
                continue
            out = []
            at = 0
            for start, end in spans:
                out.append(swap(line[at:start]))
                out.append(line[start:end])
                at = end
            out.append(swap(line[at:]))
            held.append("".join(out))
        return held

    quotes = LANGUAGES[language]["quotes"]
    held = []
    for line in code:
        out = []
        run = []
        quote = None
        for character in line:
            if quote:
                out.append(character)
                if character == quote:
                    quote = None
                continue
            if character in quotes:
                out.append(swap("".join(run)))
                run = []
                out.append(character)
                quote = character
                continue
            run.append(character)
        out.append(swap("".join(run)))
        held.append("".join(out))
    return held


def show(out, path, mode, keep, language):
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    code, comments = split(text, language)
    header = header_of(text.split("\n"))

    out.write("\n%s\n" % ("=" * 90))
    out.write("### %s   [%s]\n" % (path.replace("\\", "/"), language))
    out.write("%s\n" % ("=" * 90))
    for line in header:
        out.write("%s\n" % line)

    if mode == "claims":
        pending = []
        for at, line in enumerate(code):
            if comments[at]:
                pending.extend(comments[at])
                continue
            if not line.strip():
                continue
            if pending:
                for one in pending:
                    out.write("  %s\n" % one)
                pending = []
            out.write("      %4d  %s\n" % (at + 1, line.rstrip()))
        for one in pending:
            out.write("  %s\n" % one)
        return

    body = code
    if mode == "blind":
        names = defined_names(text, language, keep)
        body = blinded(code, names, language)
        out.write("# %d name(s) blinded\n" % len(names))

    blank = 0
    for at, line in enumerate(body):
        if at < len(header):
            continue
        if not line.strip():
            blank += 1
            if blank > 1:
                continue
        else:
            blank = 0
        out.write("%s\n" % line.rstrip())


def main():
    args = sys.argv[1:]
    mode = args[0] if args and args[0] in ("code", "blind", "claims") else "code"
    keep = set()
    language = None
    wanted = []
    at = 0
    while at < len(args):
        one = args[at]
        if one in ("code", "blind", "claims"):
            pass
        elif one == "--keep":
            at += 1
            keep = {part.strip() for part in args[at].split(",") if part.strip()}
        elif one == "--lang":
            at += 1
            language = args[at]
            if language not in LANGUAGES:
                print("unknown language %s" % language, file=sys.stderr)
                return 2
        elif one.startswith("-"):
            print("unknown flag %s" % one, file=sys.stderr)
            return 2
        else:
            wanted.append(one)
        at += 1

    if not wanted:
        print(__doc__)
        return 2

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    seen = 0
    for one in wanted:
        if os.path.isdir(one):
            for base, dirs, names in os.walk(one):
                dirs[:] = [d for d in dirs if d not in ("__pycache__", ".git", "build")]
                for name in sorted(names):
                    if os.path.splitext(name)[1] in BY_SUFFIX:
                        show(out, os.path.join(base, name), mode, keep,
                             language_of(name, language))
                        seen += 1
            continue
        if not os.path.isfile(one):
            out.write("\n  no file at %s\n" % one)
            continue
        show(out, one, mode, keep, language_of(one, language))
        seen += 1
    out.write("\n  %d file(s) read. Nothing was written.\n\n" % seen)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
