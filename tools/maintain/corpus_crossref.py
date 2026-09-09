#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find corpus material used in this tree without the paper it came from named beside it.
#
#   python tools/maintain/corpus_crossref.py              all three passes
#   python tools/maintain/corpus_crossref.py --speakers   who the corpus rests on, and who is unnamed
#   python tools/maintain/corpus_crossref.py --forms      language forms only
#   python tools/maintain/corpus_crossref.py --prose      quoted paper text only
#   python tools/maintain/corpus_crossref.py --context N  lines counted as beside a use
#
# WHY THIS EXISTS
#
# Every form in these tables existed in somebody's head, and it is written down here because that
# person said it and said what it means. No measurement in this work was reachable without their
# participation and their understanding of their own language. A page that uses the material and
# names nobody has taken the part the work could never have produced for itself.
#
# THE INSTITUTIONAL DIRECTION RUNS THE OTHER WAY
#
# A paper carries its author on the title page. The person whose language it is goes into a
# footnote as a consultant, or goes in as two initials, or does not go in. Five of the twenty
# papers behind these tables name nobody at all.
#
# That direction is reversed here. The speakers are named in paper_config, they are named in the
# books, and this check keeps them named as the tree grows.
#
# The licence on the corpus turns on that attribution, and so does the condition of use in
# SECURITY.md. Neither survives an example that prints a Lushootseed word with no idea where it
# came from.
#
# The check is mechanical and it is not a judgement about intent. What it reports is a use with no
# attribution within reach of it, and every one of those is a place to name somebody.
#
# THREE PASSES, AND THEY CATCH DIFFERENT THINGS
#
#   speakers  a language named with none of its speakers named nearby, and a paper used here whose
#             speakers are recorded nowhere
#   forms     a value from the form column of a hand extraction, appearing anywhere in the tree
#   prose     a run of words from a paper's own text, appearing in this tree's prose
#
# The speakers pass runs first because it carries the most. An earlier version of this file treated
# a language name as noise to be skipped, and had it exactly backwards. A language is not an
# abstraction with no owner. Naming one while naming nobody who speaks it is the same failure as
# quoting a form with no source, one level up.
#
# That version also skipped a paper with an empty speakers list, and reproduced the institutional
# direction inside the checker. The five papers naming nobody are the five worth reporting hardest,
# because on those the record stops at a linguist and the person is already gone from it.
#
# A Salishan form carries characters that occur nowhere else in this tree. A forms match is nearly
# always a real quotation for that reason. The prose pass is looser: a long run of ordinary English
# words is still evidence, and a short one is the same sentence two people would write on their own.
#
# WHAT COUNTS AS ATTRIBUTION
#
# Within a few lines of the use: the paper's stem, any speaker named for it, any surname in its
# stem, or its ICSNL volume. Attribution one screen away from a quotation is attribution a reader
# will not connect to it. The window is small for that reason, and --context sets it.
#
# WHAT THIS CANNOT SEE
#
# It reads the corpus that is on disk. Without the closed corpus synced under build/ there is
# nothing to compare against, and it says so instead of reporting a clean tree.

import io
import os
import re
import sys
import textwrap

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)

ORACLES = os.path.join(ROOT, "build", "oracles")
PAPERS = os.path.join(ROOT, "build", "papers")

sys.path.insert(0, os.path.join(ROOT, "tools", "Salishan", "corpus_script_extraction"))

# Where this tree's own writing lives. build/ is the corpus itself and deps/ is somebody else's.
SEARCHED = ("docs", "theory", "src", "examples", "tools", "README.md", "SECURITY.md",
            "CONTRIBUTING.md")
SKIP = ("__pycache__", ".git", "build", "deps", "site")
TEXT = (".md", ".tex", ".py", ".c", ".h", ".R", ".m", ".sh")

# A form shorter than this matches by accident. Salishan forms carry characters that appear nowhere
# else here, so the bar is about run length and not about how exotic the characters are.
LEAST_FORM = 4

# A run of paper words this long is a quotation. Below it, two people writing about the same
# measurement produce the same sentence without either copying.
RUN = 8

WORD = re.compile(r"[^\W\d_]+", re.UNICODE)
ASCII_ONLY = re.compile(r"^[\x00-\x7f]+$")


def papers():
    """Every paper, as its stem against the names that count as citing it."""
    try:
        from paper_config import PAPERS as CONFIG
    except ImportError:
        return {}
    held = {}
    for paper in CONFIG:
        names = {paper.stem}
        # A stem is written CamelCase or underscore separated and carries the surnames.
        for piece in re.split(r"[_\-]", paper.stem):
            for word in re.findall(r"[A-Z][a-z]{3,}", piece) or [piece]:
                if len(word) >= 4 and not word.isdigit():
                    names.add(word)
        for who in (getattr(paper, "speakers", None) or ()):
            for word in re.findall(r"[^\W\d_]{4,}", who, re.UNICODE):
                names.add(word)
        held[paper.stem] = {"names": names, "oracle": paper.oracle,
                            "language": getattr(paper, "language", ""),
                            "speakers": tuple(getattr(paper, "speakers", None) or ()),
                            "note": getattr(paper, "note", "") or ""}
    return held


def language_names(known):
    """What the languages are called, against the people who speak them.

    A language is not an abstraction with no owner. Every one of these has living or recorded
    speakers and this corpus holds their words. A page that names nɬeʔkepmxcín and names nobody who
    speaks it has taken the language and left the speakers out. That is the same failure as quoting
    a form with no source, one level up, and it is checked the same way.

    The first pass here treated these as noise and skipped them. They are the opposite of noise.
    """
    held = {}
    for row in known.values():
        name = (row.get("language") or "").strip()
        if not name:
            continue
        # The same name is written with and without its leading n, and with ł for ɬ.
        for spelling in (name, name.lstrip("n"), name.replace("ɬ", "ł"), name.replace("ł", "ɬ")):
            if spelling:
                held.setdefault(spelling, set()).update(row.get("speakers") or ())
    return held


def forms_by_paper(known):
    """Every form in every hand extraction, against the papers it appears in."""
    held = {}
    if not os.path.isdir(ORACLES):
        return held
    skip = language_names(known)
    oracle_to_stem = {}
    for stem, row in known.items():
        oracle_to_stem[row["oracle"]] = stem
    for name in sorted(os.listdir(ORACLES)):
        if not name.endswith(".tsv"):
            continue
        stem = oracle_to_stem.get(name, name[:-11])
        with io.open(os.path.join(ORACLES, name), encoding="utf-8", errors="replace") as handle:
            header = None
            for line in handle:
                parts = line.rstrip("\n").split("\t")
                if header is None:
                    header = parts
                    continue
                row = dict(zip(header, parts))
                form = (row.get("form") or "").strip()
                if len(form) < LEAST_FORM:
                    continue
                # An all ASCII form is a word somebody could write without the paper.
                if ASCII_ONLY.match(form):
                    continue
                if form in skip:
                    continue
                held.setdefault(form, set()).add(stem)

    # A form that is a tail of a longer one reports the same quotation twice, since ɬeʔkepmxcín sits
    # inside nɬeʔkepmxcín. A reader wants the longest match named, so the shorter tail is dropped.
    # The outer form can itself have been dropped by an earlier round, since a whole sentence is a
    # form and so is every word in it. Reading held[longer] without checking raised a KeyError on
    # the first Nsyilxcən sentence long enough to contain three shorter forms.
    ordered = sorted(held, key=len, reverse=True)
    for at, longer in enumerate(ordered):
        if longer not in held:
            continue
        for shorter in ordered[at + 1:]:
            if shorter in longer and shorter in held and held[shorter] <= held[longer]:
                del held[shorter]
    return held


def tree_files():
    for one in SEARCHED:
        full = os.path.join(ROOT, one)
        if os.path.isfile(full):
            yield full
            continue
        for base, dirs, names in os.walk(full):
            dirs[:] = [d for d in dirs if d not in SKIP]
            for name in sorted(names):
                if name.endswith(TEXT):
                    yield os.path.join(base, name)


def cited_near(lines, at, names, context):
    """Whether any name for the paper appears within `context` lines of a use."""
    low = max(0, at - context)
    high = min(len(lines), at + context + 1)
    window = "\n".join(lines[low:high])
    return any(name in window for name in names)


def person_of(who):
    """Every way one speakers entry names its person, without the community after the comma.

    An entry is written "K̓weswapáw̓ (Linda Redan), Qayqáyten": the person, then where they are
    from. A name written in the language and again in English is one person written two ways, and
    a page that carries either one has named them. A leading title comes off as well, since the
    books write Margaret Siwallace where paper_config writes Dr. Margaret Siwallace.
    """
    person = who.split(",")[0].strip()
    held = [person]
    held.extend(one.strip() for one in re.findall(r"\(([^)]+)\)", person))
    outside = re.sub(r"\([^)]*\)", "", person).strip()
    if outside:
        held.append(outside)
    for one in list(held):
        without = re.sub(r"^(?:Dr\.?|Mr\.?|Mrs\.?|Ms\.?|Elder)\s+", "", one).strip()
        if without != one:
            held.append(without)
    return [one for one in held if len(one) >= 4]


def run_speakers(out, context):
    """Who this corpus rests on, and the three ways a page can fail to say so.

    unrecorded  a paper used here whose speakers are recorded nowhere. The record stops at a
                linguist and the person is already out of it. An earlier version skipped these,
                which reproduced inside the checker the thing the checker is against.
    absent      a speaker named in paper_config and named in none of this tree's own writing. A
                person in a config file and invisible in the work is not a person who has been
                credited.
    nearby      a language named in a file with no speaker of it within reach of the line.
    """
    known = papers()
    if not known:
        out.write("  no paper_config, cannot name a speaker\n")
        return 0
    languages = language_names(known)
    if not languages:
        out.write("  no languages in paper_config\n")
        return 0

    # One read of the tree, held whole, because every check below asks a question of all of it.
    tree = []
    for path in tree_files():
        with io.open(path, encoding="utf-8", errors="replace", newline="") as handle:
            tree.append((os.path.relpath(path, ROOT).replace("\\", "/"),
                         handle.read().split("\n")))

    findings = 0

    out.write("\n  WHOSE WORDS THESE ARE\n")
    for stem in sorted(known, key=lambda one: (known[one]["language"], one)):
        row = known[stem]
        if not row["speakers"]:
            continue
        for who in row["speakers"]:
            spellings = person_of(who)
            carried = sum(1 for _, lines in tree
                          if any(any(one in line for one in spellings) for line in lines))
            out.write("    %-22s %-46s %s\n"
                      % (row["language"][:22], who[:46],
                         "%d file(s)" % carried if carried else "NAMED NOWHERE HERE"))
            if not carried:
                findings += 1

    silent = [stem for stem in sorted(known) if not known[stem]["speakers"]]
    if silent:
        out.write("\n  UNRECORDED, the paper is used here and names nobody (%d of %d)\n"
                  % (len(silent), len(known)))
        # The note is printed with the paper because it says where the record stops. Every one of
        # these traces to a dictionary or a dissertation, and the person is named in that or in
        # nothing. Printing the blank alone would read as an accusation against the paper, and
        # printing the chain gives somebody the next place to look.
        for stem in silent:
            out.write("    %-38s %s\n" % (stem[:38], known[stem]["language"]))
            for line in textwrap.wrap(known[stem]["note"], 92):
                out.write("        %s\n" % line)
        out.write("\n    Each of these stops at a published source. Registering that source in\n")
        out.write("    citations.py and reading it for who spoke is how a name gets back on.\n")

    out.write("\n  NEARBY, a language named with no speaker of it within %d lines\n" % context)
    for shown, lines in tree:
        seen = set()
        for at, line in enumerate(lines):
            for name, speakers in languages.items():
                if name not in line or name in seen:
                    continue
                # Any part of any speaker's name counts. They are written several ways across the
                # tree, in their own orthography and in English, and the check is whether a reader
                # meets a person here at all.
                parts = set()
                for who in speakers:
                    parts |= set(re.findall(r"[^\W\d_]{4,}", who, re.UNICODE))
                if parts and cited_near(lines, at, parts, context):
                    continue
                seen.add(name)
                findings += 1
                out.write("    %s:%d  %s   %s\n"
                          % (shown, at + 1, name,
                             ("speakers: " + "; ".join(sorted(speakers)))[:88] if speakers
                             else "NO SPEAKER OF IT IS RECORDED ANYWHERE"))
    out.write("\n  %d finding(s), over %d speaker(s) and %d paper(s) that name none\n"
              % (findings, sum(len(known[stem]["speakers"]) for stem in known), len(silent)))
    return findings


def run_forms(out, context):
    known = papers()
    if not known:
        out.write("  no paper_config, cannot name a source\n")
        return 0
    forms = forms_by_paper(known)
    if not forms:
        out.write("  no hand extractions under build/oracles\n")
        out.write("  run tools/maintain/private_sync.py\n")
        return 2

    out.write("\n  %d distinct forms from %d papers\n" % (len(forms), len(known)))

    findings = 0
    for path in tree_files():
        with io.open(path, encoding="utf-8", errors="replace", newline="") as handle:
            text = handle.read()
        lines = text.split("\n")
        shown = os.path.relpath(path, ROOT).replace("\\", "/")
        seen = set()
        for at, line in enumerate(lines):
            for form, stems in forms.items():
                if form not in line or form in seen:
                    continue
                names = set()
                for stem in stems:
                    names |= known[stem]["names"]
                if cited_near(lines, at, names, context):
                    continue
                seen.add(form)
                findings += 1
                out.write("    %s:%d  %s   from %s\n"
                          % (shown, at + 1, form, ", ".join(sorted(stems))))
    out.write("\n  %d uncited form use(s)\n" % findings)
    return findings


def archive_size():
    """How many papers the ICSNL archive lists, from the index fetched beside them.

    get_papers.py writes icsnl_index.tsv when it reads the archive page. Without it there is no
    honest denominator and the coverage line is left off instead of guessed at.
    """
    target = os.path.join(PAPERS, "icsnl_index.tsv")
    if not os.path.isfile(target):
        return 0
    held = set()
    with io.open(target, encoding="utf-8", errors="replace") as handle:
        header = None
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if header is None:
                header = parts
                continue
            row = dict(zip(header, parts))
            if row.get("kind") == "pdf" and row.get("url"):
                held.add(row["url"].rsplit("/", 1)[-1])
    return len(held)


def run_prose(out, context):
    if not os.path.isdir(PAPERS):
        out.write("\n  no papers under build/papers\n")
        return 2

    # One pass over the papers builds the index, keyed on a run of lowercase words.
    index = {}
    count = 0
    for name in sorted(os.listdir(PAPERS)):
        if not name.endswith(".txt"):
            continue
        count += 1
        stem = name[:-4]
        with io.open(os.path.join(PAPERS, name), encoding="utf-8", errors="replace") as handle:
            words = [one.lower() for one in WORD.findall(handle.read())]
        for at in range(len(words) - RUN + 1):
            index.setdefault(" ".join(words[at:at + RUN]), set()).add(stem)

    out.write("\n  %d papers, %d distinct %d-word runs\n" % (count, len(index), RUN))
    # What this pass did not read is the more useful number. The archive index lists every ICSNL
    # paper ever published and build/papers holds the ones the readers open. A clean result here
    # covers that fraction and says nothing about the rest, and reporting the finding count alone
    # would read as a complete answer.
    whole = archive_size()
    if whole:
        out.write("    the archive lists %d papers, so this read %d%% of it\n"
                  % (whole, round(100.0 * count / whole)))
        out.write("    a clean result covers those and proves nothing about the other %d\n"
                  % (whole - count))
        out.write("    python tools/Salishan/get_papers.py --all fetches them\n")

    findings = 0
    for path in tree_files():
        with io.open(path, encoding="utf-8", errors="replace", newline="") as handle:
            lines = handle.read().split("\n")
        shown = os.path.relpath(path, ROOT).replace("\\", "/")
        for at, line in enumerate(lines):
            words = [one.lower() for one in WORD.findall(line)]
            if len(words) < RUN:
                continue
            for start in range(len(words) - RUN + 1):
                run = words[start:start + RUN]
                # An alphabet is not a quotation. salish_purity.py lists its letters one per token
                # and matched a paper's own letter list, which is two people writing down the same
                # alphabet. A real sentence carries several words somebody chose.
                if sum(1 for one in run if len(one) >= 3) < 3:
                    continue
                key = " ".join(run)
                stems = index.get(key)
                if not stems:
                    continue
                window = "\n".join(lines[max(0, at - context):at + context + 1])
                if any(stem in window for stem in stems):
                    continue
                findings += 1
                out.write("    %s:%d  \"%s\"\n       from %s\n"
                          % (shown, at + 1, key, ", ".join(sorted(stems))))
                break
    out.write("\n  %d uncited prose run(s)\n" % findings)
    return findings


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    context = 6
    if "--context" in sys.argv:
        context = int(sys.argv[sys.argv.index("--context") + 1])

    picked = {"--forms", "--prose", "--speakers"} & set(sys.argv)
    both = not picked
    total = 0
    if both or ("--speakers" in sys.argv):
        out.write("\n  SPEAKERS, whose words these are and where they are not said\n")
        total += run_speakers(out, context)
    if both or ("--forms" in sys.argv):
        out.write("\n  FORMS, a hand extraction's own column\n")
        total += run_forms(out, context)
    if both or ("--prose" in sys.argv):
        out.write("\n  PROSE, a run of a paper's own words\n")
        total += run_prose(out, context)

    out.write("\n  attribution is looked for within %d lines of a use\n" % context)
    out.write("  a finding is a place to name the paper, not a verdict about intent\n\n")
    out.flush()
    return 1 if total else 0


if __name__ == "__main__":
    raise SystemExit(main())
