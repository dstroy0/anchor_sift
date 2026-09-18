#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Strip comments from a file or tree, leaving the code and the license header.

An API conversion is driven by patterns over source lines, and prose is what those patterns trip
over: a line-anchored rewrite cannot tell a call from a sentence naming the same call, and a match
that crosses a comment boundary splices the sentence into the code. Removing the comments first
makes the rewrite mechanical. The same pass clears code arriving from another project of every word
its authors wrote about it, before anyone here reads it.

What is removed, by suffix:
  .c .h .cu .cuh .cfg   // and /* */ comments
  .py                   # comments, and every statement made of a string alone, docstrings included
  .sh                   # comments, where # opens a word outside quotes and outside a heredoc body

What is preserved:
  - the leading copyright / SPDX block, which states a license instead of describing code
  - a #! line opening a script, which the kernel reads to choose the interpreter
  - string and character literals, including escapes, so "http://x" is not read as a comment
  - the line count of C block comments, which keeps a compiler error pointing at the right line

Every Python and shell result is checked before it is written. A Python file has to parse to the
same syntax tree it had with its string statements taken out, compared by ast.dump. A shell file has
to pass bash -n. A file failing its check is refused by name and left as it was. C carries no check
here, and the build that follows is the check for it.

Usage:
    python maint/source/strip_comments.py PATH [PATH ...]      # dry run: report only
    python maint/source/strip_comments.py PATH --go            # rewrite in place

    --ext .c,.h     which suffixes to visit (default .c,.h)
    --keep-header   keep the leading copyright / SPDX block (default on)
    --no-header     strip that block too
    --exclude PAT   skip any path containing PAT (repeatable)

A file is only rewritten when the result differs, and a second run is a no-op.
"""

import argparse
import ast
import io
import os
import shutil
import subprocess
import sys
import tokenize

C_SUFFIXES = {".c", ".h", ".cu", ".cuh", ".cfg"}
PYTHON_SUFFIXES = {".py"}
SHELL_SUFFIXES = {".sh"}


def strip(text):
    """Remove // and /* */ comments. Literals survive; block comments leave their newlines."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"' or c == "'":
            q = c
            out.append(c)
            i += 1
            while i < n:
                if text[i] == "\\":  # an escape can hide the closing quote
                    out.append(text[i : i + 2])
                    i += 2
                    continue
                out.append(text[i])
                if text[i] == q:
                    i += 1
                    break
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                if text[i] == "\n":
                    out.append("\n")
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def string_statement(statement):
    """Whether a statement is a string literal standing alone, the shape a docstring takes."""
    return (isinstance(statement, ast.Expr) and isinstance(statement.value, ast.Constant)
            and isinstance(statement.value.value, str))


def statement_lists(tree):
    """Every list of statements in a syntax tree, from each body, else, finally and handler."""
    for node in ast.walk(tree):
        for field in ("body", "orelse", "finalbody"):
            held = getattr(node, field, None)
            if isinstance(held, list) and held and isinstance(held[0], ast.stmt):
                yield held


def without_string_statements(tree):
    """The tree with every string statement taken out, and pass left where a body would empty.

    This is what the stripped text has to parse back to, so it is built from the original tree and
    never from the stripped text.
    """
    for held in statement_lists(tree):
        kept = [one for one in held if not string_statement(one)]
        if not kept:
            kept = [ast.Pass()]
        held[:] = kept
    return tree


def strip_python(text):
    """Remove # comments and string statements from Python source.

    Returns the stripped text, or raises ValueError naming why the file cannot be stripped safely.
    A string statement sharing a line with other code is refused, since cutting it would cut code.
    A body left holding nothing but string statements keeps one pass in the place of the first.
    """
    # One line ending throughout. ast counts \r\n and a lone \r as line breaks, and str.splitlines
    # also breaks at form feeds and other separators that ast does not count, so neither matches the
    # other without this. A \r that was inside a string literal changes that literal's value, and the
    # tree comparison at the end refuses the file.
    text = text.replace("\r\n", "\n").replace("\r", "\n")
    lines = [one + "\n" for one in text.split("\n")]
    if text.endswith("\n"):
        lines.pop()
    tree = ast.parse(text)

    # Lines to drop whole, and lines whose tail from a column onward is a comment.
    dropped = set()
    replaced = {}
    for held in statement_lists(tree):
        strings = [one for one in held if string_statement(one)]
        if not strings:
            continue
        emptied = len(strings) == len(held)
        for place, statement in enumerate(strings):
            first = lines[statement.lineno - 1]
            last = lines[statement.end_lineno - 1]
            indent = len(first) - len(first.lstrip(" \t"))
            # Code ahead of the string on its first line, or code after it on its last line other
            # than a comment, would be dropped with the lines. Refused instead.
            tail = last[statement.end_col_offset:].strip()
            if (statement.col_offset != indent) or (tail and not tail.startswith("#")):
                raise ValueError("a string statement at line %d shares its line with code"
                                 % statement.lineno)
            if emptied and place == 0:
                replaced[statement.lineno] = first[:indent] + "pass\n"
                dropped.update(range(statement.lineno + 1, statement.end_lineno + 1))
            else:
                dropped.update(range(statement.lineno, statement.end_lineno + 1))

    cut_from = {}
    for token in tokenize.generate_tokens(io.StringIO(text).readline):
        if token.type != tokenize.COMMENT:
            continue
        row, column = token.start
        if row == 1 and column == 0 and token.string.startswith("#!"):
            continue
        cut_from[row] = column

    out = []
    for number, line in enumerate(lines, start=1):
        if number in dropped:
            continue
        if number in replaced:
            out.append(replaced[number])
            continue
        if number in cut_from:
            kept = line[:cut_from[number]].rstrip()
            if not kept.strip():
                continue
            out.append(kept + "\n")
            continue
        out.append(line)
    stripped = "".join(out)

    wanted = ast.dump(without_string_statements(ast.parse(text)))
    if ast.dump(ast.parse(stripped)) != wanted:
        raise ValueError("the stripped text parses to a different tree than the original")
    return stripped


def heredoc_word(line, at):
    """The terminating word of a heredoc opening at `at` in `line`, and whether tabs are stripped.

    Returns (word, strip_tabs), or (None, False) where `<<` at `at` opens no heredoc: a here-string
    `<<<`, or no word after it.
    """
    if line.startswith("<<<", at):
        return None, False
    rest = line[at + 2:]
    strip_tabs = rest.startswith("-")
    if strip_tabs:
        rest = rest[1:]
    rest = rest.lstrip(" \t")
    if not rest:
        return None, False
    if rest[0] in "'\"":
        close = rest.find(rest[0], 1)
        if close < 0:
            return None, False
        return rest[1:close], strip_tabs
    word = []
    for one in rest:
        if one.isspace() or one in ";&|()<>":
            break
        if one != "\\":
            word.append(one)
    return ("".join(word) or None), strip_tabs


def strip_shell(text):
    """Remove # comments from a shell script. A # opens a comment only as the first byte of a word.

    Quotes are followed across lines, a backslash escapes the next byte outside single quotes, and
    a heredoc body is copied as it stands. A #! first line stays.
    """
    out_lines = []
    lines = text.split("\n")
    quote = None
    heredocs = []
    number = 0
    while number < len(lines):
        line = lines[number]
        number += 1

        if heredocs and quote is None:
            word, strip_tabs = heredocs[0]
            out_lines.append(line)
            if (line.lstrip("\t") if strip_tabs else line) == word:
                heredocs.pop(0)
            continue

        if number == 1 and line.startswith("#!"):
            out_lines.append(line)
            continue

        kept = []
        at = 0
        while at < len(line):
            one = line[at]
            if quote == "'":
                kept.append(one)
                if one == "'":
                    quote = None
                at += 1
                continue
            if quote == '"':
                if one == "\\" and at + 1 < len(line):
                    kept.append(line[at:at + 2])
                    at += 2
                    continue
                kept.append(one)
                if one == '"':
                    quote = None
                at += 1
                continue
            if one == "\\" and at + 1 < len(line):
                kept.append(line[at:at + 2])
                at += 2
                continue
            if one in "'\"":
                quote = one
                kept.append(one)
                at += 1
                continue
            if one == "<" and line.startswith("<<", at):
                word, strip_tabs = heredoc_word(line, at)
                if word is not None:
                    heredocs.append((word, strip_tabs))
                kept.append(line[at:at + 2])
                at += 2
                continue
            if one == "#" and (at == 0 or line[at - 1] in " \t;&|()<>"):
                break
            kept.append(one)
            at += 1

        joined = "".join(kept)
        if quote is None and not joined.strip() and line.strip():
            continue
        out_lines.append(joined.rstrip() if quote is None else joined)

    return "\n".join(out_lines)


def check_shell(text):
    """Raise ValueError where bash -n refuses the text. Skipped, and said so, where bash is absent."""
    bash = shutil.which("bash")
    if bash is None:
        raise ValueError("bash is not on PATH, so the stripped script cannot be checked")
    run = subprocess.run([bash, "-n"], input=text.encode("utf-8"), capture_output=True)
    if run.returncode != 0:
        raise ValueError("bash -n refuses the stripped script: %s"
                         % run.stderr.decode("utf-8", "replace").strip())


def header_of(text, marker):
    """The leading copyright / SPDX lines, if the file opens with them, in the given comment marker.

    A #! line ahead of the block is taken with it, since it has to stay first.
    """
    head = []
    for line in text.split("\n"):
        s = line.strip()
        if not head and s.startswith("#!"):
            head.append(line)
            continue
        if s.startswith(marker) and ("Copyright" in s or "SPDX" in s or s == marker):
            head.append(line)
            continue
        break
    return head


def collapse(text):
    """Collapse the blank runs a removal leaves to one line, and trim trailing space."""
    out, blank = [], 0
    for line in text.split("\n"):
        if line.strip() == "":
            blank += 1
            if blank > 1:
                continue
        else:
            blank = 0
        out.append(line.rstrip())
    return "\n".join(out).lstrip("\n")


def rewrite(text, keep_header, suffix=".c"):
    """The file's text with its comments gone. Raises ValueError where a check refuses the result."""
    if suffix in PYTHON_SUFFIXES:
        marker, strip_body = "#", strip_python
    elif suffix in SHELL_SUFFIXES:
        marker, strip_body = "#", strip_shell
    else:
        marker, strip_body = "//", strip

    # Without the header, a #! first line stays in the body, and strip_python and strip_shell each
    # keep it where they meet it on line 1.
    head = header_of(text, marker) if keep_header else []
    body = "\n".join(text.split("\n")[len(head) :]) if head else text
    body = strip_body(body)
    new = ("\n".join(head) + "\n" if head else "") + collapse(body)
    new = new if new.endswith("\n") else new + "\n"

    if suffix in SHELL_SUFFIXES:
        check_shell(new)
    if suffix in PYTHON_SUFFIXES:
        # The header and the collapse sit outside strip_python, so the finished text is parsed once
        # more against the same tree.
        wanted = ast.dump(without_string_statements(ast.parse(text)))
        if ast.dump(ast.parse(new)) != wanted:
            raise ValueError("the finished text parses to a different tree than the original")
    return new


def walk(paths, exts, excludes):
    for p in paths:
        if os.path.isfile(p):
            yield p
            continue
        for dp, _, fns in os.walk(p):
            if any(x in dp.replace("\\", "/") for x in excludes):
                continue
            for f in sorted(fns):
                if os.path.splitext(f)[1] in exts:
                    q = os.path.join(dp, f).replace("\\", "/")
                    if not any(x in q for x in excludes):
                        yield q


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("paths", nargs="+")
    ap.add_argument("--go", action="store_true", help="rewrite in place")
    ap.add_argument("--ext", default=".c,.h")
    ap.add_argument("--no-header", dest="keep_header", action="store_false")
    ap.add_argument("--exclude", action="append", default=["__pycache__", ".pio", "unity_runner.c"])
    a = ap.parse_args()

    exts = set(a.ext.split(","))
    unknown = exts - (C_SUFFIXES | PYTHON_SUFFIXES | SHELL_SUFFIXES)
    if unknown:
        print("no comment syntax is known for %s" % ", ".join(sorted(unknown)))
        return 2

    files = changed = removed = 0
    refused = []
    for p in walk(a.paths, exts, a.exclude):
        files += 1
        t = io.open(p, encoding="utf-8", errors="replace", newline="").read()
        try:
            new = rewrite(t, a.keep_header, os.path.splitext(p)[1])
        except (ValueError, SyntaxError) as why:
            refused.append((p, str(why)))
            continue
        if new == t:
            continue
        changed += 1
        removed += t.count("\n") - new.count("\n")
        if a.go:
            io.open(p, "w", encoding="utf-8", newline="").write(new)

    print(
        "visited %d, would change %d, lines removed %d" % (files, changed, removed)
        if not a.go
        else "visited %d, changed %d, lines removed %d" % (files, changed, removed)
    )
    for p, why in refused:
        print("REFUSED %s: %s" % (p.replace("\\", "/"), why))
    if not a.go:
        print("DRY RUN - pass --go to rewrite")
    return 1 if refused else 0


if __name__ == "__main__":
    sys.exit(main())
