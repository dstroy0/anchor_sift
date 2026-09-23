"""Does the page's script read a key its own data does not carry?

    python examples/00_blob_viz_tools/data_check.py build/view/sha_clock_view.html
    python examples/00_blob_viz_tools/data_check.py --check

THE DEFECT THIS EXISTS FOR

Four builders share `room_view_template.html`, and only `build_sha_clock_view.py` puts a `clock` key
in the JSON it writes. Nothing else in the tree says which builder's data satisfies which template's
reads. A builder can therefore drop a key the template needs and no gate notices: every gate here asks
whether the code runs, and none asks whether the data is there.

WHAT THIS TOOL FOUND FIRST, WHICH WAS ITS OWN AUTHOR WRONG

The page above was written up as broken on the strength of one line, `CLOCK = DATA.clock`, read out
of a grep whose pattern stopped at the first space. The line is `var CLOCK = DATA.clock || null;` and
the fallback was outside the match.

Every one of the eight reads of `DATA.clock` in that template is guarded: two `if (DATA.clock)`
blocks, four ternaries carrying defaults, one short circuit, and the assignment with its `|| null`.
`DATA.sources` is `|| 2`. So the template supports a clock-less page deliberately, `CLOCK` becomes
`null` instead of `undefined`, `panelReady` returns false, and the panels are correctly absent
instead of dead. The page was the wrong page to serve and it was not a broken one.

A mechanism was asserted from a truncated regex. That is the failure this tree keeps recording under
new names: the quantity reported was not the quantity intended. It is written here because this file
was being built to catch that class and introduced an instance of it on the way.

So the tree currently has **no** page with an unguarded missing key, and that is a fact about the
templates worth knowing instead of a reason to skip the gate. What the gate refuses is the next
builder, and the next template read written without a default.

WHAT THIS ASKS INSTEAD

Take the built page, which carries both halves in one file. Pull the JSON literal out of
`var DATA = {...}`, collect every `DATA.<path>` the script reads, and walk each path into the parsed
data.

A path stops being a data path as soon as it leaves the dictionaries. `DATA.sources.length` is a
`sources` key followed by a JavaScript property, so the walk descends while the value is a mapping
and stops when it is not. Anything past that point is the language's business.

GUARDED AND UNGUARDED, BECAUSE ONLY ONE OF THEM IS A DEFECT

A template legitimately asks whether an optional key is present. `if (DATA.things)` is a question and
an absent `things` is the answer. `CLOCK = DATA.clock` is not a question.

A missing key is therefore reported either way and **fails** only when nothing guards it. A guard on
a parent covers its children, since a page that asks whether `clock` is there owns what it does
underneath `clock`, and that spares this tool from counting braces to find the enclosing block.

WHAT `--check` GRADES

Eight guard shapes, one at a time, because the first version of this file marked every one of them
guarded and would have passed anything. The prefix rule, both ways: a guard on the parent covers the
child, and covers nothing else. The brace counter, against a literal with braces inside its strings.
The walk, which has to leave the dictionaries at `sources.length` and stay inside them at
`clock.hold`.

Then a written sample carrying one unguarded absent key, because the tree has none and a checker
nobody has seen fire is a checker nobody has tested. Then both real pages, which have to come back
clean for their two different reasons.
"""

import io
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# The assignment the builders write. Named once, and a change to the builders is then a change here and
# never a silent pass on a page whose data this tool could not find.
OPENER = "var DATA = "

# A read of the data, with as many dotted segments as the source spells. The walk below decides how
# many of them are data and how many are the language's.
READ = re.compile(r"\bDATA((?:\.[A-Za-z_][A-Za-z0-9_]*)+)")

# A read sitting in a conditional's test, on this line.
TESTED = re.compile(r"\s*(\}\s*)?(else\s+)?(if|while)\s*\(")

# A read that is negated or type-tested, immediately before it.
DENIED = re.compile(r"(!|typeof\s+)$")

# A read that is an operand of a short circuit or a ternary, on either side of it. `DATA.x || 2`
# carries its own default and `DATA.x ? a : b` asks the question outright.
LEADS = re.compile(r"^\s*(&&|\|\||\?)")
FOLLOWS = re.compile(r"(\?|&&|\|\|)\s*$")

# THE PROXIMITY TEST THIS REPLACED WAS USELESS AND PASSED EVERYTHING. It looked for any of `&&`,
# `||`, `?`, `if (` or `typeof` within 120 characters either side. JavaScript carries those
# everywhere, so `var CLOCK = DATA.clock;` came back guarded because an unrelated `if` sat thirty
# characters earlier. A guard has to be a syntactic relationship with this read and never a token
# sitting nearby.


def strip_strings(text, start=0):
    """The text from `start` with the contents of JSON strings blanked, so only structure is visible.

    A brace inside a string value must not be counted, and JSON has exactly one string delimiter.

    THE JAVASCRIPT RULE WAS USED HERE FIRST AND IT WAS WRONG. Blanking on any of the quote, the
    apostrophe and the backtick is right for JavaScript source and wrong for a JSON literal, because
    an apostrophe there is an ordinary character inside a value. Worse, the scan used to start at the
    top of the file, where an apostrophe in a comment above the data opened a string that never
    closed: the blanking then ran to the end of the page and took the data's own braces with it, the
    depth counter never left zero, and the tool reported DATA DOES NOT PARSE AS JSON for a page whose
    data was perfectly well formed. step_view.html carries 25 apostrophes in its data and
    voxel_view.html carries one, and one is enough.

    So the scan begins at the literal and admits one delimiter. A tool that blames the thing it is
    reading for a defect in its own reading sends the next person to fix a file that was fine.
    """
    out = []
    inside = False
    escaped = False
    for one in text[start:]:
        if inside:
            out.append(" " if one != "\n" else "\n")
            if escaped:
                escaped = False
            elif one == "\\":
                escaped = True
            elif one == '"':
                inside = False
                out[-1] = one
        else:
            out.append(one)
            if one == '"':
                inside = True
    return "".join(out)


def data_literal(text):
    """The JSON the page carries, as a string, or None with a reason.

    Braces are counted on a copy whose string contents are blanked, and the slice is taken from the
    original, so the returned text is the real literal and the counting is not fooled by a brace in
    a value.
    """
    at = text.find(OPENER)
    if at < 0:
        return None, "no '%s' in the page" % OPENER.strip()
    start = at + len(OPENER)
    if start >= len(text) or text[start] != "{":
        return None, "the data does not open with a brace"
    # Blanked from the literal onward, and indexed from there, so nothing above the data can reach
    # into the count.
    blanked = " " * start + strip_strings(text, start)

    depth = 0
    for here in range(start, len(blanked)):
        if blanked[here] == "{":
            depth += 1
        elif blanked[here] == "}":
            depth -= 1
            if depth == 0:
                return text[start:here + 1], ""
    return None, "the data's braces never close"


def guarded_at(text, start, end):
    """Whether this one read is a question about the key instead of an assumption it is there.

    Judged on the line holding the read and on the read's position within it, so the relationship is
    syntactic. Four shapes count, and each is a way of writing "if this is absent, carry on":

        if (DATA.x)          the test of a conditional
        !DATA.x              negated, or handed to typeof
        DATA.x || 2          given a default, or leading a short circuit or a ternary
        cond ? DATA.x : 2    reached only when something already asked
    """
    line_start = text.rfind("\n", 0, start) + 1
    line_end = text.find("\n", end)
    if line_end < 0:
        line_end = len(text)
    before = text[line_start:start]
    after = text[end:line_end]

    if TESTED.match(text[line_start:line_end]) and "(" in before:
        return True
    if DENIED.search(before):
        return True
    if LEADS.match(after):
        return True
    if FOLLOWS.search(before):
        return True
    return False


def reads_of(text):
    """Every dotted read of the data, as {path tuple: [(offset, guarded)]}.

    The assignment itself is excluded, since `var DATA = ` is not a read.
    """
    out = {}
    for found in READ.finditer(text):
        path = tuple(found.group(1).lstrip(".").split("."))
        out.setdefault(path, []).append((found.start(), guarded_at(text, found.start(), found.end())))
    return out


def protected(path, found):
    """Whether a path is covered by a guard on itself or on anything it hangs from.

    A line test cannot see an enclosing block, and the template writes

        if (DATA.clock) {
          opBox.max = String(DATA.clock.ticks);

    where the inner read carries no guard of its own and needs none. Instead of counting braces to
    find the block, the rule is that a guarded read of `clock` covers `clock.ticks`: once the page
    demonstrably asks whether a key is there, what it does underneath that key is its own business.

    This is the deliberate looseness in the tool. It cannot catch a page that tests for a key and
    then reads a child of it outside the test, and that shape is rare enough to trade for never
    failing a builder that is correct.
    """
    for depth in range(len(path), 0, -1):
        for _, guard in found.get(path[:depth], []):
            if guard:
                return True
    return False


def walk(data, path):
    """How far `path` gets into `data`, and whether it got there.

    Descends while the value is a mapping. The first segment that is not a key of a mapping ends the
    walk: if the value it was asked of is a mapping, the key is missing; if not, the remaining
    segments are JavaScript property access and the data path was satisfied.
    """
    here = data
    for depth, segment in enumerate(path):
        if not isinstance(here, dict):
            return True, depth, None
        if segment not in here:
            return False, depth, sorted(here.keys())
        here = here[segment]
    return True, len(path), None


def check(path):
    with io.open(path, encoding="utf-8", newline="") as handle:
        text = handle.read()

    lines = ["  %s" % os.path.basename(path)]
    failed = 0

    literal, why = data_literal(text)
    if literal is None:
        lines.append("  NO DATA FOUND: %s" % why)
        sys.stdout.write("\n".join(lines) + "\n\n1 check(s) failed\n")
        return 1
    try:
        data = json.loads(literal)
    except ValueError as broken:
        lines.append("  DATA DOES NOT PARSE AS JSON: %s" % broken)
        sys.stdout.write("\n".join(lines) + "\n\n1 check(s) failed\n")
        return 1

    lines.append("  data carries %d top level key(s), %d bytes" % (len(data), len(literal)))

    found = reads_of(text)
    lines.append("  script reads %d distinct path(s)" % len(found))

    missing = []
    for path_bits in sorted(found):
        ok, depth, near = walk(data, path_bits)
        if not ok:
            missing.append((path_bits, depth, near, protected(path_bits, found)))

    for path_bits, depth, near, covered in missing:
        spelled = "DATA." + ".".join(path_bits)
        absent = ".".join(path_bits[:depth + 1])
        if covered:
            lines.append("  optional %s: absent, and the page asks before reading it" % spelled)
        else:
            lines.append("  MISSING %s: no '%s' in the data, and nothing guards the read"
                         % (spelled, absent))
            lines.append("    whatever depends on it renders empty, and nothing throws")
            if near:
                lines.append("    the data has: %s" % ", ".join(near[:12]))
            failed += 1

    if not missing:
        lines.append("  every path the script reads is carried by the data")

    sys.stdout.write("\n".join(lines) + "\n\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


# The real pages this tool is graded on. Both have to come back clean, and for different reasons:
# the clock page carries every key it reads, and the room page is missing four of them and asks
# before reading every one. A finding on either is a defect in this file.
KNOWN_CLEAN = ("sha_clock_view.html", "sha_room_view.html")

# The known positive, and it is written here because the tree does not contain one. Every template
# read of an absent key is currently guarded, which is a fact about the templates and not a reason
# to ship a checker nobody has seen fire. The shape below is what the gate exists to refuse: a
# key the data lacks, read with no question asked about it.
KNOWN_BROKEN = "\n".join((
    'var DATA = {"shell": "sphere", "clock": {"ticks": 512}};',
    'var CLOCK = DATA.clock;',
    'var TICKS = DATA.clock.ticks;',
    'var SPIN = DATA.spin;',
    'if (DATA.things) { paint(DATA.things.count); }',
))

# `spin` is absent and unguarded, so one finding. `things` is absent and asked about, so none. The
# clock and its ticks are present. One finding is therefore the expected answer entire.
KNOWN_BROKEN_FINDINGS = 1


def _check():
    lines = []
    failed = 0

    # The brace counter, against a literal whose values hold braces. A page's data is mostly strings
    # and an early stop would truncate the JSON and report every key as missing.
    tricky = 'var DATA = {"a": "} not the end {", "b": {"c": 1}}\nvar OTHER = 2;'
    literal, why = data_literal(tricky)
    lines.append("  a brace inside a string does not end the scan: %s"
                 % ("held" if literal and json.loads(literal).get("b") == {"c": 1} else "FAILED " + why))
    if not literal or json.loads(literal).get("b") != {"c": 1}:
        failed += 1

    # The apostrophe, both places it appears, because the first version of the blanker treated it as
    # a delimiter and lost the data's braces to it. step_view.html has 25 in its values.
    quoted = "// the page's own comment\nvar DATA = {\"who\": \"Douglas's\", \"n\": {\"k\": 2}}\nvar X = 1;"
    literal, why = data_literal(quoted)
    got = json.loads(literal) if literal else {}
    lines.append("  an apostrophe in a value and in a comment above it: %s"
                 % ("held" if got.get("who") == "Douglas's" and got.get("n") == {"k": 2}
                    else "FAILED " + why))
    if got.get("who") != "Douglas's" or got.get("n") != {"k": 2}:
        failed += 1

    # The walk has to stop leaving the dictionaries. Otherwise every `.length` in the source is
    # reported as a missing key and the real findings arrive buried.
    sample = {"sources": [1, 2, 3], "clock": {"tau": 0.5}}
    ok, _, _ = walk(sample, ("sources", "length"))
    lines.append("  a property past the data reads as satisfied: %s" % ("yes" if ok else "NO"))
    if not ok:
        failed += 1
    ok, depth, near = walk(sample, ("clock", "hold"))
    lines.append("  a key absent inside a carried mapping is caught: %s at depth %d"
                 % ("yes" if not ok else "NO", depth))
    if ok or depth != 1:
        failed += 1

    # Each guard shape has to read as a guard, and a bare assignment has to not. This is the test the
    # first version of this file failed: a 120 character window called every one of them guarded.
    shapes = (
        ("if (DATA.a) { go(); }", ("a",), True),
        ("var x = !DATA.b;", ("b",), True),
        ("var x = DATA.c || 2;", ("c",), True),
        ("var x = ready ? DATA.d : 0;", ("d",), True),
        ("var x = typeof DATA.e;", ("e",), True),
        ("var CLOCK = DATA.f;", ("f",), False),
        ("paint(DATA.g);", ("g",), False),
        ("var n = DATA.h + 1;", ("h",), False),
    )
    wrong = []
    for source, path, wanted in shapes:
        got = reads_of(source).get(path, [(0, None)])[0][1]
        if got != wanted:
            wrong.append("%s read as %s" % (source, "guarded" if got else "unguarded"))
    lines.append("  8 guard shapes, each read for its syntax: %d wrong" % len(wrong))
    for one in wrong:
        lines.append("    FAIL %s" % one)
    failed += len(wrong)

    # The prefix rule. It covers a read inside `if (DATA.clock) {` is covered without counting
    # braces. A guard on the parent has to cover the child, and a guard on nothing has to cover
    # nothing.
    found = reads_of("if (DATA.clock) { go(DATA.clock.ticks); }\nvar S = DATA.spin;")
    covered = protected(("clock", "ticks"), found)
    bare = protected(("spin",), found)
    lines.append("  a guard on the parent covers the child: %s, and covers nothing else: %s"
                 % ("yes" if covered else "NO", "yes" if not bare else "NO"))
    if not covered or bare:
        failed += 1

    lines.append("")

    # The known positive, written above because the tree has none. A checker nobody has seen fire is
    # a checker nobody has tested.
    made = os.path.join(ROOT, "build", "view", "_data_check_sample.html")
    os.makedirs(os.path.dirname(made), exist_ok=True)
    with io.open(made, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(KNOWN_BROKEN)
    lines.append("  the written sample, expecting %d finding(s)" % KNOWN_BROKEN_FINDINGS)
    sys.stdout.write("\n".join(lines) + "\n")
    lines = []
    got = check(made)
    os.unlink(made)
    if got != KNOWN_BROKEN_FINDINGS:
        lines.append("    FAIL got %d, so the tool does not catch what it exists for" % got)
        failed += 1

    # The real pages, both of which have to come back clean.
    for name in KNOWN_CLEAN:
        where = os.path.join(ROOT, "build", "view", name)
        if not os.path.exists(where):
            lines.append("  %s is not built, so the tool was not graded on it" % name)
            failed += 1
            continue
        lines.append("  grading against %s, expecting 0" % name)
        sys.stdout.write("\n".join(lines) + "\n")
        lines = []
        got = check(where)
        if got:
            lines.append("    FAIL got %d on a page that should pass" % got)
            failed += 1

    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d gate check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    argv = sys.argv[1:]
    if "--check" in argv:
        sys.exit(1 if _check() else 0)
    if argv:
        sys.exit(1 if check(argv[0]) else 0)
    sys.stdout.write(__doc__)
    sys.exit(2)
