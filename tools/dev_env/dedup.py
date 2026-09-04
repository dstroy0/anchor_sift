#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Find the same code written twice, when it was written twice under different names.

  dedup.py fns   [PATH ...]   whole functions that share a shape
  dedup.py block [PATH ...]   runs of statements inside functions that share a shape
  dedup.py shape [PATH ...]   the shapes themselves, largest group first: the reusable patterns
  dedup.py show  <shape-id>   one shape in full, canonical form and every site that has it

A textual diff cannot see this. Two units that both walk a table looking for a match write the same
five statements with `i`/`n`/`e` in one and `loculus`/`count`/`ent` in the other, and a hash of the text
puts them in different buckets. So the text is not what is hashed. Comments come off first through
readclean's own pass - the literal-aware one, not a regex - the result is tokenized, and every
identifier is replaced by the position at which it was first seen. Two blocks that differ only in
what things are called then reduce to the same token string and land in one bucket.

Three renaming strengths, because they answer different questions:

  --rename all     every identifier goes, types and callees included. Answers "is this the same
                   shape", which is what finds one idiom written out forty-eight times.
  --rename vars    an identifier immediately followed by `(` keeps its name, and so does anything
                   in ALL_CAPS, which in this tree is a macro. Answers "is this the same algorithm
                   over different data" - the calls and the widths still have to line up. Default.
  --rename none    nothing is renamed. Exact clones only, and the baseline the other two are read
                   against: a group that appears under `vars` and not under `none` is one the eye
                   would have to have caught by name.

Statement order is not required to match. Every unit carries two hashes: the token sequence, and the
multiset of its statements with each statement hashed on its own. Two blocks holding the same
statements in a different order collide on the second and not the first, and are reported as a
reorder rather than a copy - which is the case a sequence hash silently misses.

  --min N      the fewest tokens a unit may hold to be reported (default 24 for fns, 12 for block)
  --win N      statements in a block window (default 4)
  --nums       fold integer literals to one token as well
  --json       machine-readable, for a script that wants the groups rather than the report
"""

import hashlib
import io
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from strip_comments import rewrite

ROOT = os.getcwd()

# C11 sec 6.4.1 keywords plus the ones this tree's dialect adds. A keyword is structure, not a name,
# so it never renames: `while` and `for` must not collide.
KEYWORDS = set("""auto break case char const continue default do double else enum extern float for goto if
    inline int long register restrict return short signed sizeof static struct switch typedef union
    unsigned void volatile while _Alignas _Alignof _Atomic _Bool _Complex _Generic _Imaginary
    _Noreturn _Static_assert _Thread_local static_assert alignas alignof bool true false NULL
    defined include define ifndef ifdef endif elif pragma error undef line""".split())

TOKEN = re.compile(
    r"""
      (?P<id>[A-Za-z_][A-Za-z_0-9]*)
    | (?P<num>0[xX][0-9A-Fa-f]+[uUlL]*|\d+\.?\d*([eE][-+]?\d+)?[uUlLfF]*)
    | (?P<str>"(\\.|[^"\\])*"|'(\\.|[^'\\])*')
    | (?P<op><<=|>>=|\.\.\.|->|\+\+|--|<<|>>|<=|>=|==|!=|&&|\|\||[-+*/%&|^!<>=]=|\#\#|[-+*/%&|^~!<>=?:;,.(){}\[\]\#])
    """,
    re.VERBOSE,
)


def tokenize(text, first_line=1):
    """The code as (kind, text, line) triples. Comments are gone; whitespace never survives.

    The line travels with the token so a hit can be reported where it is, rather than only as a
    shape. Nothing downstream reads past the second element, so a shape does not see it.
    """
    out = []
    for m in TOKEN.finditer(text):
        kind = m.lastgroup
        if kind in ("id", "num", "str", "op"):
            out.append((kind, m.group(), first_line + text.count("\n", 0, m.start())))
    return out


def mask_comments(text):
    """Replace every comment byte with a space, leaving literals and every newline where they are.

    readclean's `rewrite` deletes comment lines outright, which is right for reading and wrong for
    reporting: a hit at token line 137 of the stripped text is not line 137 of the file, and the two
    drift further apart the more prose a file carries. Blanking in place keeps every offset, so a
    line number is the line number. Literals survive, so "http://x" is still one token and not a
    comment, which is the same reason readclean does not use a regex.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"' or c == "'":
            q = c
            out.append(c)
            i += 1
            while i < n:
                if text[i] == "\\":
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
                out.append(" ")
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            while i < n and not (text[i] == "*" and i + 1 < n and text[i + 1] == "/"):
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
            out.append("  ")
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def split_pp(text):
    """Separate the preprocessor directives from the code, keeping each directive whole.

    A directive is not a statement and its parenthesis is not a call: walking back from a `{` over
    `#define MMGR_CONFIN_IO(w) ...` finds a name that belongs to a macro and reads the struct behind
    it as that macro's body. So the directive lines are lifted out first, and what is left is code
    with the directives blanked to spaces - the offsets do not move, and neither does any line.

    A directive continues while its line ends in a backslash (C11 sec 5.1.1.2), so the continuation
    lines belong to it too.
    """
    lines = text.split("\n")
    directives, keep, i = [], [], 0
    while i < len(lines):
        if lines[i].lstrip().startswith("#"):
            body, first = [], i
            while i < len(lines):
                body.append(lines[i])
                keep.append("")
                if not lines[i].rstrip().endswith("\\"):
                    break
                i += 1
            directives.append((first + 1, "\n".join(body).replace("\\\n", " ")))
        else:
            keep.append(lines[i])
        i += 1
    return "\n".join(keep), directives


def canon(tokens, rename, fold_nums):
    """Rewrite the token list so that only its shape survives.

    An identifier becomes I<k>, where k is how many distinct renameable identifiers were seen before
    it. First appearance is what fixes k, so the same shape reaches the same string no matter what
    the names were, and two different shapes cannot reach it by accident: a name reused later in the
    block still maps to the k it was given.
    """
    seen = {}
    out = []
    for i, tok in enumerate(tokens):
        kind, txt = tok[0], tok[1]
        if kind == "id":
            if txt in KEYWORDS or rename == "none":
                out.append(txt)
                continue
            if rename == "vars":
                nxt = tokens[i + 1][1] if i + 1 < len(tokens) else ""
                # A callee and a macro are what the block is made OF, not what it is made about.
                if nxt == "(" or (txt.isupper() and len(txt) > 2):
                    out.append(txt)
                    continue
            out.append("I%d" % seen.setdefault(txt, len(seen)))
        elif kind == "num":
            out.append("N" if fold_nums else txt)
        elif kind == "str":
            out.append("S")
        else:
            out.append(txt)
    return out


def statements(tokens):
    """Split a token list at the `;` and the braces, at depth 0 of any parenthesis.

    A `for (a; b; c)` header holds two semicolons that do not end a statement, and they sit inside
    parentheses, which is what separates them.
    """
    out, cur, paren = [], [], 0
    for tok in tokens:
        txt = tok[1]
        if txt == "(":
            paren += 1
        elif txt == ")":
            paren = max(0, paren - 1)
        cur.append(tok)
        if paren == 0 and txt in (";", "{", "}"):
            out.append(cur)
            cur = []
    if cur:
        out.append(cur)
    return [s for s in out if s]


def digest(strings):
    h = hashlib.sha256()
    for s in strings:
        h.update(s.encode("utf-8"))
        h.update(b"\x00")
    return h.hexdigest()[:12]


def bag_digest(stmts, rename, fold_nums):
    """A hash of the statements as a set rather than a sequence.

    Each statement canonicalizes on its own, so a name introduced in one statement does not fix the
    numbering of the next. That is what makes the hash blind to order.
    """
    parts = sorted(digest(canon(s, rename, fold_nums)) for s in stmts)
    return digest(parts)


# --- carving the source into units -------------------------------------------


def functions(tokens):
    """Every function body in a token list, as (name, tokens-of-body-with-signature).

    A definition is an identifier followed by a parenthesis that closes, and then a `{`, all at brace
    depth 0. A declaration reaches the `;` instead and is walked past. A `struct ... { }` initializer
    does not open at depth 0 behind a closing parenthesis, so it is not mistaken for one.
    """
    out = []
    i, n, depth = 0, len(tokens), 0
    start_sig = 0
    while i < n:
        txt = tokens[i][1]
        if txt == "{" and depth == 0:
            # Walk back over the signature to the token that ended the previous unit.
            j = i - 1
            par = 0
            name = None
            while j >= start_sig:
                t = tokens[j][1]
                if t == ")":
                    par += 1
                elif t == "(":
                    par -= 1
                    if par == 0 and j > 0 and tokens[j - 1][0] == "id":
                        name = tokens[j - 1][1]
                        break
                j -= 1
            k, d = i, 0
            while k < n:
                if tokens[k][1] == "{":
                    d += 1
                elif tokens[k][1] == "}":
                    d -= 1
                    if d == 0:
                        break
                k += 1
            if name:
                out.append((name, tokens[j - 1 : k + 1]))
            i = k + 1
            start_sig = i
            continue
        if depth == 0 and txt == ";":
            start_sig = i + 1
        if txt == "{":
            depth += 1
        elif txt == "}":
            depth = max(0, depth - 1)
        i += 1
    return out


def sources(paths, excludes):
    for p in paths:
        if os.path.isfile(p):
            yield p
            continue
        for dp, _, fns in os.walk(p):
            q = dp.replace("\\", "/")
            if any(x in q for x in excludes):
                continue
            for f in sorted(fns):
                if f.endswith((".c", ".h")) and f != "unity_runner.c":
                    r = os.path.join(dp, f).replace("\\", "/")
                    if not any(x in r for x in excludes):
                        yield r


def load(p):
    """A file, comments off, tokenized, with the directives kept apart from the code.

    This is readclean's `code` view, taken as tokens rather than as lines.
    """
    text = io.open(p, encoding="utf-8", errors="replace").read()
    code, directives = split_pp(mask_comments(text))
    return tokenize(code), [(ln, tokenize(d, ln)) for ln, d in directives]


def rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


# --- the three reports --------------------------------------------------------


def collect_fns(files, rename, fold_nums, min_tokens):
    units = []
    for p in files:
        toks, directives = load(p)
        # A function-like macro is a unit of its own: the borrow maps in this tree are written as
        # macros, and a shape written twenty times as a macro is duplicated exactly as much as one
        # written twenty times as a function.
        for ln, d in directives:
            if len(d) < min_tokens:
                continue
            c = canon(d, rename, fold_nums)
            units.append(
                {
                    "file": rel(p),
                    "name": "#%s:%d" % (d[1][1] if len(d) > 1 else "pp", ln),
                    "tokens": len(d),
                    "seq": digest(c),
                    "bag": bag_digest(statements(d), rename, fold_nums),
                    "canon": " ".join(c),
                }
            )
        for name, body in functions(toks):
            if len(body) < min_tokens:
                continue
            c = canon(body, rename, fold_nums)
            units.append(
                {
                    "file": rel(p),
                    "name": name,
                    "tokens": len(body),
                    "seq": digest(c),
                    "bag": bag_digest(statements(body), rename, fold_nums),
                    "canon": " ".join(c),
                }
            )
    return units


def collect_blocks(files, rename, fold_nums, min_tokens, win):
    units = []
    for p in files:
        toks, _ = load(p)
        for name, body in functions(toks):
            stmts = [s for s in statements(body) if len(s) > 1]
            for i in range(0, max(0, len(stmts) - win + 1)):
                window = [t for s in stmts[i : i + win] for t in s]
                if len(window) < min_tokens:
                    continue
                c = canon(window, rename, fold_nums)
                units.append(
                    {
                        "file": rel(p),
                        "name": "%s[%d:%d]" % (name, i, i + win),
                        "tokens": len(window),
                        "seq": digest(c),
                        "bag": bag_digest(stmts[i : i + win], rename, fold_nums),
                        "canon": " ".join(c),
                    }
                )
    return units


def group(units, key):
    g = {}
    for u in units:
        g.setdefault(u[key], []).append(u)
    return {k: v for k, v in g.items() if len(v) > 1}


def distinct_sites(members):
    """One site per (file, name): a window that slid one statement is not a second occurrence."""
    seen, out = set(), []
    for m in members:
        k = (m["file"], m["name"].split("[")[0])
        if k in seen:
            continue
        seen.add(k)
        out.append(m)
    return out


def report(units, mode, top, as_json):
    by_seq = group(units, "seq")
    by_bag = group(units, "bag")

    rows = []
    for h, members in by_seq.items():
        sites = distinct_sites(members)
        if len(sites) < 2:
            continue
        rows.append(
            {
                "id": h,
                "kind": "copy",
                "sites": len(sites),
                "tokens": sites[0]["tokens"],
                "saving": sites[0]["tokens"] * (len(sites) - 1),
                "canon": sites[0]["canon"],
                "where": [{"file": s["file"], "name": s["name"], "tokens": s["tokens"]} for s in sites],
            }
        )

    # A bag group that is not already one sequence group is the reorder case: the same statements,
    # written in a different order.
    for h, members in by_bag.items():
        seqs = {m["seq"] for m in members}
        if len(seqs) < 2:
            continue
        sites = distinct_sites(members)
        if len(sites) < 2:
            continue
        rows.append(
            {
                "id": h,
                "kind": "reorder",
                "sites": len(sites),
                "tokens": sites[0]["tokens"],
                "saving": sites[0]["tokens"] * (len(sites) - 1),
                "canon": sites[0]["canon"],
                "where": [{"file": s["file"], "name": s["name"], "tokens": s["tokens"]} for s in sites],
            }
        )

    rows.sort(key=lambda r: (-r["saving"], -r["sites"], r["id"]))
    rows = rows[:top]

    if as_json:
        print(json.dumps(rows, indent=2))
        return

    if not rows:
        print("no group of two or more shares a shape at this threshold")
        return

    print("%-14s %-8s %5s %7s %8s  %s" % ("shape", "kind", "sites", "tokens", "saving", "first site"))
    print("-" * 100)
    for r in rows:
        print(
            "%-14s %-8s %5d %7d %8d  %s :: %s"
            % (
                r["id"],
                r["kind"],
                r["sites"],
                r["tokens"],
                r["saving"],
                r["where"][0]["file"],
                r["where"][0]["name"],
            )
        )
    print()
    print(
        "%d shapes, %d tokens duplicated. `dedup.py show <shape>` for one in full."
        % (len(rows), sum(r["saving"] for r in rows))
    )

    if mode == "shape":
        for r in rows[:top]:
            print("\n" + "=" * 100)
            print("### %s  %s  %d sites, %d tokens each" % (r["id"], r["kind"], r["sites"], r["tokens"]))
            print("=" * 100)
            for w in r["where"]:
                print("    %s :: %s" % (w["file"], w["name"]))
            print("\n" + wrap(r["canon"]))


def wrap(s, width=110):
    out, line = [], ""
    for tok in s.split(" "):
        if len(line) + len(tok) + 1 > width:
            out.append(line)
            line = tok
        else:
            line = (line + " " + tok).strip()
    if line:
        out.append(line)
    return "\n".join("    " + x for x in out)


def show(units, shape_id):
    hit = [u for u in units if u["seq"] == shape_id or u["bag"] == shape_id]
    if not hit:
        print("no shape %s at this threshold - widen --min or change --rename" % shape_id)
        return
    print("### %s  %d sites" % (shape_id, len(distinct_sites(hit))))
    for u in distinct_sites(hit):
        print("    %s :: %s  (%d tokens)" % (u["file"], u["name"], u["tokens"]))
    print("\ncanonical form:\n" + wrap(hit[0]["canon"]))


def main():
    args = sys.argv[1:]
    mode = args[0] if args and args[0] in ("fns", "block", "shape", "show") else "fns"
    rest = [a for a in args[1:] if not a.startswith("--")]
    flags = [a for a in args if a.startswith("--")]

    def flag(name, default):
        for f in flags:
            if f.startswith("--" + name + "="):
                return f.split("=", 1)[1]
        return default

    rename = flag("rename", "vars")
    fold_nums = "--nums" in flags
    as_json = "--json" in flags
    win = int(flag("win", "4"))
    top = int(flag("top", "25"))
    excludes = ["build", ".git", "__pycache__", "docs/learn"]

    if mode == "show":
        shape_id = rest[0]
        paths = rest[1:] or ["src"]
    else:
        shape_id = None
        paths = rest or ["src"]

    min_tokens = int(flag("min", "12" if mode == "block" else "24"))
    files = list(sources(paths, excludes))
    if not files:
        print("no .c or .h under %s" % ", ".join(paths))
        return 1

    if mode == "block" or (mode == "show" and win):
        units = collect_blocks(files, rename, fold_nums, min_tokens, win)
        units += collect_fns(files, rename, fold_nums, max(min_tokens, 24))
    else:
        units = collect_fns(files, rename, fold_nums, min_tokens)

    if mode == "show":
        show(units, shape_id)
        return 0

    print(
        "%d files, %d units, --rename %s%s, --min %d%s\n"
        % (
            len(files),
            len(units),
            rename,
            ", numbers folded" if fold_nums else "",
            min_tokens,
            ", --win %d" % win if mode == "block" else "",
        )
    )
    report(units, mode, top, as_json)
    return 0


if __name__ == "__main__":
    sys.exit(main())
