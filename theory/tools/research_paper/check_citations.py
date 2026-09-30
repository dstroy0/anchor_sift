#!/usr/bin/env python3
r"""Print every line citation a research paper change added beside the lines it names, at the commit it is pinned to.

    python tools/research_paper/check_citations.py --since 5ce1632 --source ../anchor_sift --pin 1044ca6 \
        --pin-prefix bench/driver/=d65d219 \
        --alias anchor_sift.h=src/engine/c/engine/anchor_sift.h \
        --alias anchor_sift.c=src/engine/c/engine/anchor_sift.c \
        --alias .c=src/engine/c/engine/anchor_sift.c \
        --alias chapter_anchor_sift_workbook.tex=theory/workbook/chapters/chapter_anchor_sift_workbook.tex \
        --local README.md PUBLIC/delta_null

A research paper cites another repository by line, as \texttt{path:N} or \texttt{path:N-M}, and a bare \texttt{:N} on the
same source line means the file named last. A line number is a claim about one commit, and each citation is
resolved against the commit its path is pinned to and printed beside the sentence that cites it. Reading that
output is the check: a line that exists and says something else is as wrong as a line that does not exist,
and only a reader can tell the two apart.

WHAT IS READ. The lines added between --since and the working tree under the named paths of this repository.
Citations older than --since are not read, because they belong to whatever commit they were written against,
and this tool would report them against the wrong one.

IT FAILS CLOSED. Exit 1 when any citation does not resolve: the file is absent at its pin, or the range runs
past its end. Exit 3 when the diff holds no citation, because zero citations over a diff that should hold
some reads the same as a clean pass. Exit 2 on a usage error. Exit 0 only when at least one citation was read
and every one resolved.
"""

import argparse
import re
import subprocess
import sys

TEXTTT = re.compile(r"\\texttt\{((?:[^{}]|\{\})*)\}")
CITE = re.compile(r"^(?P<path>[A-Za-z0-9_./\-*{}, ]*?)?:(?P<spec>[0-9]+(?:-[0-9]+)?)$")


def run(args, cwd):
    done = subprocess.run(args, cwd=cwd, capture_output=True, text=True, encoding="utf-8")
    return done.returncode, done.stdout, done.stderr


def clean(text):
    return text.replace("\\allowbreak{}", "").replace("\\_", "_")


def pairs(values, flag):
    mapping = {}
    for value in values:
        key, sep, target = value.partition("=")
        if not sep or not key or not target:
            raise SystemExit("check_citations: %s takes KEY=VALUE, got %r" % (flag, value))
        mapping[key] = target
    return mapping


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("paths", nargs="+", help="pathspecs in this repository whose added lines are read")
    parser.add_argument("--since", required=True, help="the commit the change is measured from")
    parser.add_argument("--source", required=True, help="a checkout of the cited repository")
    parser.add_argument("--pin", required=True, help="the commit cited paths resolve at by default")
    parser.add_argument("--pin-prefix", action="append", default=[], metavar="PREFIX=REV",
                        help="cited paths starting with PREFIX resolve at REV instead")
    parser.add_argument("--alias", action="append", default=[], metavar="SHORT=PATH",
                        help="a short name the research paper writes for a full path in the cited repository")
    parser.add_argument("--local", action="append", default=[], metavar="PATH",
                        help="a cited path that belongs to this repository's working tree")
    args = parser.parse_args()

    prefixes = pairs(args.pin_prefix, "--pin-prefix")
    aliases = pairs(args.alias, "--alias")

    code, research_paper, err = run(["git", "rev-parse", "--show-toplevel"], ".")
    if code != 0:
        print("check_citations: not inside a git checkout: %s" % err.strip())
        return 2
    research_paper = research_paper.strip()
    code, source, err = run(["git", "rev-parse", "--show-toplevel"], args.source)
    if code != 0:
        print("check_citations: --source is not a git checkout: %s" % err.strip())
        return 2
    source = source.strip()
    print("research paper repository:   %s, added lines since %s under %s" % (research_paper, args.since, " ".join(args.paths)))
    print("cited repository:  %s, default pin %s" % (source, args.pin))
    for prefix, rev in sorted(prefixes.items()):
        print("  pinned prefix:   %s at %s" % (prefix, rev))

    code, diff, err = run(["git", "diff", "-U0", args.since, "--"] + args.paths, research_paper)
    if code != 0:
        print("check_citations: git diff failed: %s" % err.strip())
        return 2
    added = [line[1:] for line in diff.split("\n") if line.startswith("+") and not line.startswith("+++")]
    print("added lines read:  %d" % len(added))

    cache = {}
    total = 0
    unresolved = 0
    for line in added:
        last = None
        for match in TEXTTT.finditer(line):
            cite = CITE.match(clean(match.group(1)))
            if cite is None:
                continue
            path = cite.group("path") or ""
            if path:
                last = aliases.get(path, path)
            if last is None:
                continue
            total += 1
            low, _, high = cite.group("spec").partition("-")
            low = int(low)
            high = int(high) if high else low
            if last in args.local:
                where, pin = "local", "working tree"
            else:
                where = "source"
                pin = next((rev for prefix, rev in prefixes.items() if last.startswith(prefix)), args.pin)
            key = (where, pin, last)
            if key not in cache:
                if where == "local":
                    try:
                        with open("%s/%s" % (research_paper, last), encoding="utf-8") as handle:
                            cache[key] = handle.read().split("\n")
                    except OSError:
                        cache[key] = None
                else:
                    code, body, _ = run(["git", "show", "%s:%s" % (pin, last)], source)
                    cache[key] = body.split("\n") if code == 0 else None
            lines = cache[key]
            before = clean(line[max(0, match.start() - 260):match.start()])
            print("\n=== %s:%s  [%s %s]" % (last, cite.group("spec"), where, pin))
            print("CITED BY: ...%s" % before)
            if lines is None or low < 1 or high > len(lines):
                print("  UNRESOLVED")
                unresolved += 1
                continue
            for at in range(low, min(high, low + 9) + 1):
                print("  %5d| %s" % (at, lines[at - 1][:150]))
            if high > low + 9:
                print("  ... %d more" % (high - low - 9))

    print("\ncitations: %d, unresolved: %d" % (total, unresolved))
    if total == 0:
        print("check_citations: no citation found. Refusing to report that as a pass.")
        return 3
    return 1 if unresolved else 0


if __name__ == "__main__":
    sys.exit(main())
