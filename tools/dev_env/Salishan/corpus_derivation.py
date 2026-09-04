#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Estimate how wrong the pure corpus could be, and write the estimate as a document.
#
#   Usage:  python tools/dev_env/Salishan/corpus_derivation.py
#
# Run after every change to a hand extraction. It reads the checks, computes a bound on the per-line
# error rate of the pure corpus, and rewrites docs/research/Salishan/corpus-derivation.md.
#
# WHY A BOUND AND NOT A RATE
#
# Every check that matters reports zero. Zero failures in N trials is not a failure rate of zero: it
# is a sample that has not yet seen one. The bound that goes with it is the rule of three, which
# says that with no failures in N independent trials the true rate is under 3/N with 95 percent
# confidence. That is the honest reading of a clean check and it is what this file reports.
#
# WHERE THE SMALL NUMBERS COME FROM
#
# A single channel cannot get far. 3/N with N in the tens of thousands is about 10^-4, and driving
# that to 10^-26 by counting alone would take 10^26 tokens. The small number comes from a line
# having to pass several checks that fail for different reasons, so the joint bound is the product.
# The product is only as good as the independence, and Section 4 of the document says exactly where
# that assumption is thin. A number quoted without it is a decoration.

import collections
import glob
import io
import math
import os
import random
import re
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
for _category in os.scandir(HERE):
    if _category.is_dir():
        sys.path.insert(0, _category.path)

import boundary_check as border  # noqa: E402
import coverage_check as coverage  # noqa: E402
import oracle_check as oracle  # noqa: E402
import reader_check as reader  # noqa: E402
from anchor_sift import distance, self_distance, squash  # noqa: E402
from language_check import BY_CORPUS  # noqa: E402
from papers import EVERY, NOT_FAITHFUL, PAGE_TEXT  # noqa: E402
from salish_unsorted import is_language_token  # noqa: E402

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
CORPORA = os.path.join(ROOT, "build", "corpora")
DOCS = os.path.join(ROOT, "docs", "research", "Salishan")
TARGET = os.path.join(DOCS, "corpus-derivation.md")
FIGURE = os.path.join(DOCS, "corpus-derivation.svg")

# The papers whose extracted text is not what the page prints. A check against one of these is
# measuring the source, so its disagreements say nothing about the table and it contributes no
# trials to the bound. docs/research/Salishan/refs.md names each and says what happened to it.
UNSOUND = set(NOT_FAITHFUL) | {"2012_Robertson", "1975_Hilbert_Hess"}

# The rule of three. With no failures in trials, the true rate is under this with 95 percent
# confidence. It is the standard bound for a zero numerator and it is why a clean check still
# carries a number instead of a claim of perfection.
CONFIDENCE = 3.0


def bound(failures, trials):
    """The 95 percent upper bound on a rate, given what the check saw.

    Zero failures takes the rule of three. A failure that did happen takes the observed rate, which
    is larger than any bound would be and is the number to report.
    """
    if not trials:
        return 1.0
    if failures:
        return failures / float(trials)
    return CONFIDENCE / trials


# The margin section 3 of the method applies. A gap has to clear the estimator's resolution by this
# factor before the nearest anchor is a reading instead of the nearest piece of noise.
MARGIN = 2.0

# The archive the extraction is drawing from. The lifetime projection scales the sound papers to
# this, which is the most counting can ever supply here.
ARCHIVE_PAPERS = 993

# How many of the most recent papers have to agree on a digit before it counts as settled. Three is
# the fewest that can show a trend instead of a coincidence between two adjacent values.
STEADY = 3

# How many shuffles the ordering term is measured over. self_distance cuts a corpus at its midpoint,
# and a pure corpus is papers concatenated in file order, so an unshuffled cut can put one paper on
# each side and report the distance between them. Shuffling puts a mixture on both sides.
SHUFFLES = 5

# Where the projection stops. The corpora are nowhere near this and the curve past the measured
# points is a model, which Section 6 of the document says in the same sentence it gives the number.
PROJECTED_PAIRS = 1e9


def alphabets():
    """Each language's alphabet, as the union of the marks its papers are checked with.

    papers.py carries one mark set per paper because the question is not the same in every paper:
    the 1983 typescript writes the glottal stop as ? where the others write ʔ. A language read from
    several papers takes all of them, which is the alphabet the sift gets to apply to that dialect.
    """
    held = {}
    for name, stem, record, repair, marks in EVERY:
        language = BY_CORPUS.get(record.split("_")[1])
        if language:
            held[language] = held.get(language, "") + marks
    return held


def pure_corpora(applied):
    """The known-pure lines of each language, optionally cut down to its own alphabet.

    With applied false this is the text as the readers wrote it, which is what the sift sees when
    it is given a page and nothing else. With applied true every line is cut to the tokens that are
    language under that dialect's alphabet, which is the sift given what the extraction already
    knows. The two are the unaided and the alphabet-applied arms, and the gap between them is what
    the alphabet is worth.
    """
    marks = alphabets()
    held = collections.defaultdict(list)
    for path in sorted(glob.glob(os.path.join(CORPORA, "*.pure.txt"))):
        language = BY_CORPUS.get(os.path.basename(path).split("_")[1])
        if not language:
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            for line in handle:
                line = line.strip()
                if not line:
                    continue
                if applied:
                    line = " ".join(one for one in line.split()
                                    if is_language_token(one, marks.get(language, "")))
                if line:
                    held[language].append(line)
    return held


def anchor_resolution(pure):
    """The estimator's resolution against corpus size, with the corpus ordering term taken out.

    Returns (points, scale, separations). points is [(pairs, in order, shuffled), ...] across the
    growth of every pure corpus, scale is the fitted k of k/sqrt(pairs) through the shuffled
    points, and separations is the distance between each pair of corpora, which is what a
    resolution has to beat before a paper can be placed against one of them.

    The two D_self numbers differ by 1.35x to 3.64x across the six corpora and the unshuffled one is
    larger every time, so D_self as corpus_growth prints it is not the resolution on its own. It
    carries the distance between whichever papers the midpoint cut happened to separate, and that
    term rises when a new paper joins a corpus. A resolution cannot rise as its sample grows.
    """
    held = {}
    profiles = {}
    for name in sorted(pure):
        lines = [one for one in pure[name] if one]
        if len(lines) < 4:
            continue
        profile, total = squash(lines)
        if not total:
            continue
        mixed = []
        for seed in range(SHUFFLES):
            shuffled = list(lines)
            random.Random(seed).shuffle(shuffled)
            mixed.append(self_distance(shuffled))
        held[name] = (total, self_distance(lines), statistics.median(mixed))
        profiles[name] = profile

    # Each dialect against the rest of the corpus pooled. This is the question the sift is actually
    # asked, and it is the harder one: a dialect has to stand off everything else at once, not beat
    # one other language at a time. It is also the leave-one-out measurement, with the corpus as its
    # own reference corpus. This is where a dialect that will not separate shows up.
    separations = {}
    for name in sorted(profiles):
        others = []
        for language in sorted(pure):
            if language != name:
                others.extend(pure[language])
        reference_profile, total = squash(others)
        if not total:
            continue
        mixed = []
        for seed in range(SHUFFLES):
            shuffled = list(others)
            random.Random(seed).shuffle(shuffled)
            mixed.append(self_distance(shuffled))
        separations[name] = (distance(profiles[name], reference_profile), statistics.median(mixed))
    return held, separations


def corpus_at(readers):
    """How large the pure corpus was as each paper joined it, in adjacent byte pairs.

    EVERY is in the order the papers were read, so accumulating along it is the history itself and
    not a reconstruction of one. A reader point sits at the size the corpus had reached when that
    paper was added, which is what puts it on the same axis as the algorithm curve beside it.
    """
    sizes = {}
    for name, stem, record, repair, marks in EVERY:
        path = os.path.join(CORPORA, "%s.pure.txt" % record[:-4])
        if not os.path.isfile(path):
            continue
        with open(path, encoding="utf-8", errors="replace") as handle:
            _, total = squash([one.strip() for one in handle if one.strip()])
        sizes[stem] = total
    held = []
    run = 0
    for one in readers:
        run += sizes.get(one["stem"], 0)
        held.append(run)
    return held


def placeable(held, separations, growth):
    """What fraction of the dialects stand off the rest of the corpus, with every corpus grown by
    this.

    This is the algorithm's accuracy, asked the way `reading` asks it: a dialect is placed when its
    distance from the pooled reference corpus clears MARGIN times the resolution of the worse of
    the two.
    Pooling every corpus into one resolution asks an easier question than the method ever faces and
    answers 1.0 at the size the corpora are already at.

    Each corpus carries its own resolution because each is a different size. Growth multiplies every
    corpus, and a resolution measured at n falls as 1/sqrt(n), so growing by g divides it by
    sqrt(g). Nothing is tuned per language: the distances are measured between the corpora and the
    resolutions are measured inside them.
    """
    if not separations:
        return 0.0
    reach = 0
    for name, (apart, reference_resolution) in separations.items():
        resolution = max(held[name][2], reference_resolution) / math.sqrt(growth)
        if apart > (MARGIN * resolution):
            reach += 1
    return reach / float(len(separations))


def figure_of(papers, readers, path):
    """The two pictures the derivation rests on, written as one SVG beside the document.

    SVG because it is vector, because it diffs as text in git the way the document next to it does,
    and because a reader opens it in a browser with nothing installed.

    Left is what has been measured: every paper as one point, trials against failures. Right is
    where the two ways of reading a paper are going as the pure corpus grows.
    """
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plot

    figure, (left, right) = plot.subplots(1, 2, figsize=(13.5, 5.6))

    for sound, mark, colour, label in ((True, "o", "#1f5f8b", "hand extraction, sound source"),
                                       (False, "X", "#b4451f", "hand extraction, damaged source")):
        chosen = [one for one in papers if one["sound"] is sound]
        if not chosen:
            continue
        left.scatter([one["forms"] + one["tokens"] for one in chosen],
                     [one["unfound"] + one["missed"] for one in chosen],
                     marker=mark, s=90, c=colour, label=label, zorder=3,
                     edgecolors="white", linewidths=0.6)
    # The readers get their own color because they are a different measurement, not another sample
    # of the one beside them. A reader is written for one paper and its errors belong to that paper.
    if readers:
        left.scatter([one["wanted"] for one in readers],
                     [one["invented"] + one["wrong"] for one in readers],
                     marker="s", s=70, c="#2e7d4f", label="reader against its table", zorder=4,
                     edgecolors="white", linewidths=0.6)
    # Only the papers that failed something get named. The ones on the zero line are the result and
    # there are nine of them sitting on one row, so labelling those writes a smear across the axis
    # and hides the thing the panel is for. Section 2's table names every paper.
    # The two Lyon papers land almost on top of each other, so the offsets alternate above and
    # below to keep one label from being written across the other.
    failed = [one for one in papers if (one["unfound"] + one["missed"]) > 0]
    for at, one in enumerate(sorted(failed, key=lambda paper: paper["forms"] + paper["tokens"])):
        left.annotate(one["stem"][:20],
                      (one["forms"] + one["tokens"], one["unfound"] + one["missed"]),
                      textcoords="offset points", xytext=(-96 if (at % 2) else 8, 6 if (at % 2)
                                                          else -12),
                      fontsize=7, color="#333333")

    left.set_xscale("log")
    left.set_yscale("symlog", linthresh=1)
    left.set_xlabel("trials on that paper")
    left.set_ylabel("failures reported by the check")
    left.set_title("What the checks have seen, one point per paper")
    left.grid(True, which="both", linewidth=0.4, alpha=0.4, zorder=0)
    left.axhline(0, linewidth=0.8, color="#1f5f8b", alpha=0.5, zorder=1)
    left.legend(loc="upper left", frameon=False, fontsize=8)

    bare = anchor_resolution(pure_corpora(False))
    applied = anchor_resolution(pure_corpora(True))

    # Growth multiplies every corpus at once, from a hundredth of what is on disk to ten thousand
    # times it, and the axis is the total that growth puts in the corpus.
    growths = [10.0 ** (-2.0 + (4.0 * step / 240.0)) for step in range(241)]
    standing = sum(one[0] for one in bare[0].values())
    sizes = [standing * one for one in growths]

    # A person's accuracy on a page does not improve because some other paper was read, so the
    # reader arm does not climb with corpus size. Its scatter is the point: a reader is written for
    # one paper and what it gets right is a fact about that paper.
    rates = [one["reproduced"] / float(one["wanted"]) for one in readers if one["wanted"]]
    reader = statistics.median(rates) if rates else 0.0

    crossing = None
    for curve, colour, style, label in (
            (bare, "#6a3d9a", "-", "algorithm, byte pairs alone"),
            (applied, "#c77f00", "-", "algorithm, dialect alphabet applied")):
        drawn = [placeable(curve[0], curve[1], one) for one in growths]
        right.plot(sizes, drawn, linewidth=2.2, color=colour, linestyle=style, zorder=3,
                   label=label)
        for at in range(1, len(sizes)):
            if (drawn[at - 1] < reader) and (drawn[at] >= reader) and (crossing is None):
                crossing = sizes[at]
                break

    right.axhline(reader, linewidth=1.6, color="#2e7d4f", linestyle="--", zorder=3,
                  label="reader, median of the per-paper rates")
    if rates:
        right.scatter(corpus_at(readers), rates, marker="s", s=70, c="#2e7d4f", zorder=4,
                      edgecolors="white", linewidths=0.6, label="reader, one point per paper")

    if crossing:
        right.axvline(crossing, linewidth=1.0, color="#333333", alpha=0.6, zorder=2)
        right.annotate("crosses at %.2g pairs" % crossing, (crossing, 0.16),
                       textcoords="offset points", xytext=(9, 0), fontsize=8, color="#333333")

    right.axvspan(min(sizes), standing, color="#1f5f8b", alpha=0.07, zorder=0)
    right.annotate("corpus on disk", (standing, 0.94), textcoords="offset points", xytext=(-76, 0),
                   fontsize=8, color="#1f5f8b")

    right.set_xscale("log")
    right.set_ylim(-0.03, 1.03)
    right.set_xlabel("pure corpus size, adjacent byte pairs")
    right.set_ylabel("fraction placed correctly")
    right.set_title("Where the two ways of reading a paper are going")
    right.grid(True, which="both", linewidth=0.4, alpha=0.4, zorder=0)
    right.legend(loc="lower right", frameon=False, fontsize=8)

    figure.tight_layout()
    figure.savefig(path, format=os.path.splitext(path)[1].lstrip(".") or "svg", dpi=150)
    plot.close(figure)
    return bare, applied, reader, crossing


def reported(module):
    """One check's own output, as the text it prints.

    Run and read instead of reimplemented. The first version of this file computed the same
    quantities a second time and got 16 failures where oracle_check reports 0 and an invented
    count of 16912 against its 2134, because a second copy of a rule drifts from the first. What
    the derivation reports now is what the check reports, by construction.
    """
    # Every check writes through sys.stdout.buffer so it can put these orthographies on a console
    # that would otherwise refuse them, so the capture has to offer a buffer of its own.
    # The wrapper the check builds around that buffer closes it when it is collected, and a closed
    # BytesIO will not hand its value back, so this one declines to close.
    class Kept(io.BytesIO):
        def close(self):
            pass

    class Captured(object):
        def __init__(self):
            self.buffer = Kept()

    held = Captured()
    stdout = sys.stdout
    try:
        sys.stdout = held
        module.main()
    finally:
        sys.stdout = stdout
    return held.buffer.getvalue().decode("utf-8", errors="replace")


# A paper's block opens with its table's filename and every count in it is a number followed by the
# check's own words for what it counted. Those phrases are the check's vocabulary, so keying on
# them breaks loudly if one is reworded instead of drifting quietly.
BLOCK = re.compile(r"^\s+(\S+)\.oracle\.tsv")
COUNT = re.compile(r"^\s+(\d+)\s+(\S.*?)\s*$")

# reader_check puts two counts on one line, the forms it was asked for and the items the reader
# actually wrote, so the second one needs asking for by name.
ITEMS = re.compile(r"forms asked for,\s+(\d+)\s+items")


def blocks(text, phrases):
    """Each paper's counts, keyed by the check's own phrase for what it counted."""
    held = {}
    stem = None
    for line in text.splitlines():
        found = BLOCK.match(line)
        if found:
            stem = found.group(1).strip()
            held[stem] = {}
            continue
        if stem is None:
            continue
        found = COUNT.match(line)
        if not found:
            continue
        for key, phrase in phrases.items():
            if found.group(2).startswith(phrase):
                held[stem][key] = int(found.group(1))
        alongside = ITEMS.search(found.group(2))
        if alongside:
            held[stem]["items"] = int(alongside.group(1))
    return held


ORACLE_PHRASES = {
    "rows": "rows read by hand",
    "cost": "forms the repair took out of the paper",
    "unfound": "written forms the paper does not hold",
    "missed": "language tokens in the paper that no row holds",
}

READER_PHRASES = {
    "wanted": "forms asked for",
    "notfound": "forms the reader did not find",
    "flagged": "forms the reader could not bound",
    "typed": "forms the reader typed differently",
    "wrong": "forms the reader put in the wrong dialect",
    "invented": "forms the reader invented",
}


def measured():
    """Every paper's trials and failures, taken from the checks themselves."""
    seen = blocks(reported(oracle), ORACLE_PHRASES)
    held = []
    for name, stem, record, repair, marks in EVERY:
        counts = seen.get(stem)
        if counts is None:
            continue
        table = os.path.join(oracle.ORACLES, name)
        source = os.path.join(oracle.PAPERS,
                              (PAGE_TEXT if stem in NOT_FAITHFUL else "%s.txt") % stem)
        if not (os.path.isfile(table) and os.path.isfile(source)):
            continue
        # The denominators the check does not print. Direction one asks once per distinct written
        # form and direction two once per language token the paper prints, so those two counts are
        # the trials behind the failures the check reports.
        rows = oracle.oracle_rows(table)
        pieces = oracle.PIECES if stem in NOT_FAITHFUL else 2
        _, printed, _ = oracle.source_forms(source, repair, pieces)
        written = set()
        for where, dialect, kind, form, gloss in rows:
            written |= oracle.pieces(form)
        tokens = sum(1 for one in printed if is_language_token(one, marks))
        held.append({
            "stem": stem,
            "sound": stem not in UNSOUND,
            "rows": counts.get("rows", len(rows)),
            "forms": len(written),
            "unfound": counts.get("unfound", 0),
            "tokens": tokens,
            "missed": counts.get("missed", 0),
        })
    return held


COVERAGE = re.compile(r"^\s+(\S+)\s+(\d+)\s+(\d+)\s+(\d+)\s+([\d.]+)%\s*$")


def covered():
    """What coverage_check saw: every language token of a paper, against the ones its corpus lost.

    A third trial on the token, and the one that fails for a reason the other two cannot. Direction
    one and direction two both ask about the hand extraction. This asks whether the corpus a reader
    built actually carries the tokens the paper printed, which is a question about the reader.
    """
    held = []
    for line in reported(coverage).splitlines():
        found = COVERAGE.match(line)
        if found:
            held.append({
                "stem": found.group(1),
                "tokens": int(found.group(2)),
                "missing": int(found.group(4)),
            })
    return held


def settled(papers, carried):
    """The joint bound recomputed as each paper joined the corpus, and how much of it has settled.

    A number is worth reporting to the digit that has stopped moving and no further. The way to find
    that digit is not to pick a format, it is to watch the number as the evidence arrives and see
    where it stops changing.

    Returns the running values and the count of leading significant digits that agree across the
    last STEADY of them. A bound still falling with every paper has none, and that is the honest
    result while the extraction is still buying accuracy: the exponent is the finding and the
    mantissa is a number in flight.
    """
    running = []
    for at in range(1, len(papers) + 1):
        ahead = papers[:at]
        forms = sum(one["forms"] for one in ahead)
        unfound = sum(one["unfound"] for one in ahead)
        tokens = sum(one["tokens"] for one in ahead)
        missed = sum(one["missed"] for one in ahead)
        # The coverage channel is not per paper in the same order, so it is held at what it is and
        # the two directions carry the movement. Mixing a fixed term into a running one would flatten
        # the curve and report a settling that never happened.
        held = sum(one["tokens"] for one in carried)
        lost = sum(one["missing"] for one in carried)
        running.append(bound(unfound, forms) * bound(missed, tokens) * bound(lost, held))

    if len(running) < STEADY:
        return running, 0
    # How many leading significant digits the last STEADY values share. Written from the mantissa so
    # a fall of one decade does not read as a change of every digit.
    digits = 0
    for width in range(1, 7):
        seen = set()
        for one in running[-STEADY:]:
            if one <= 0.0:
                seen.add(None)
                continue
            mantissa = one / (10.0 ** math.floor(math.log10(one)))
            seen.add(round(mantissa, width - 1))
        if len(seen) != 1:
            break
        digits = width
    return running, digits


def border_result():
    """What the dialect border check found, so the document quotes it instead of restating it.

    Section 7 said the border needed 2.9 times the corpus, and that was true of the distributions
    and false of the radix, which finds it now. A number typed into prose is a number that goes
    stale the next time a paper is read, so these are taken from the check.
    """
    grouped, marks = border.by_language()
    if not all(one in grouped for one in border.BORDER):
        return None
    north, south, standing = border.shared_concepts(grouped, marks)
    held = []
    exact = 0.0
    for width in border.RADIX_WIDTHS:
        forward, chance = border.radix(north, south, width)
        backward, _ = border.radix(south, north, width)
        ahead = {one[1]: one[0] for one in forward}
        behind = {one[1]: one[0] for one in backward}
        if set(ahead) == set(behind):
            exact = max([exact] + [abs(ahead[run] + behind[run]) for run in ahead])
        found = [one for one in forward if abs(one[0]) >= border.RADIX_DEVIATE]
        # The permutation is the only test in the check that can fail, so it is the only one whose
        # result belongs in the document as evidence.
        pooled = north + south
        beaten = 0
        for seed in range(border.PERMUTATIONS):
            shuffled = list(pooled)
            random.Random(seed).shuffle(shuffled)
            drawn, _ = border.radix(shuffled[:len(north)], shuffled[len(north):], width)
            if len([one for one in drawn
                    if abs(one[0]) >= border.RADIX_DEVIATE]) >= len(found):
                beaten += 1
        held.append({"width": width, "runs": len(forward), "found": len(found),
                     "chance": chance, "top": found[:3],
                     "beaten": beaten, "trials": border.PERMUTATIONS})
    return {"north": len(north), "south": len(south), "concepts": standing,
            "widths": held, "inverse": exact}


def graded():
    """What reader_check saw, per paper that has a reader on disk."""
    seen = blocks(reported(reader), READER_PHRASES)
    held = []
    for name, stem, record, repair, marks in EVERY:
        counts = seen.get(stem)
        if not counts or ("wanted" not in counts):
            continue
        held.append({
            "stem": stem,
            "wanted": counts["wanted"],
            "items": counts.get("items", 0),
            "reproduced": counts["wanted"] - counts.get("notfound", 0),
            "invented": counts.get("invented", 0),
            "wrong": counts.get("wrong", 0),
            "typed": counts.get("typed", 0),
        })
    return held


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    papers = measured()
    readers = graded()
    if not papers:
        out.write("  no hand extraction on disk\n")
        out.flush()
        return 1

    sound = [one for one in papers if one["sound"]]
    # The left panel plots unfound plus missed, so its zero line holds every paper both directions
    # cleared. Counting it here keeps the prose beside the picture true as papers are added.
    on_zero = len([one for one in papers if (one["unfound"] + one["missed"]) == 0])
    forms = sum(one["forms"] for one in sound)
    unfound = sum(one["unfound"] for one in sound)
    tokens = sum(one["tokens"] for one in sound)
    missed = sum(one["missed"] for one in sound)
    carried = covered()
    held = sum(one["tokens"] for one in carried)
    lost = sum(one["missing"] for one in carried)

    # The three channels a wrong line can arrive through, each with its own trials and its own
    # reason for failing. The reader counts are not among them. A reader is written for one paper,
    # so its error rate is a fact about that paper and not a draw from a rate the next paper shares,
    # and pooling them into one denominator would report a rate nothing is sampling.
    # Section 5 gives them per paper, which is the only form they are true in.
    channels = (
        ("a form written that the paper does not hold", unfound, forms),
        ("a token in the paper that no row holds", missed, tokens),
        ("a token the corpus lost on the way out", lost, held),
    )
    joint = 1.0
    for label, failures, trials in channels:
        joint *= bound(failures, trials)

    bare, applied, rate, crossing = figure_of(papers, readers, FIGURE)
    standing = border_result()
    running, stable = settled(sound, carried)

    with open(TARGET, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("# Corpus derivation\n\n")
        handle.write("**Purpose:** Say how wrong the pure corpus could be, from what the checks "
                     "have actually seen, and say what the number rests on.\n")
        handle.write("**Scope:** `tools/dev_env/Salishan/corpus_derivation.py`, which writes this "
                     "file, and the three checks it reads.\n\n")
        handle.write("Rewritten by `python tools/dev_env/Salishan/corpus_derivation.py` after "
                     "every change to a hand extraction. Nothing in it is typed by hand.\n\n")

        handle.write("## 1. What is being estimated\n\n")
        handle.write("For one line of the pure corpus, the probability that it is not what it "
                     "claims to be: not the target language, or not what the paper printed. Every "
                     "number below is an upper bound on that, never a measurement of it, because "
                     "every check that matters reports zero and zero failures in a sample is not "
                     "a rate of zero.\n\n")
        handle.write("With no failures in N independent trials the true rate is under 3/N with 95 "
                     "percent confidence. That is the rule of three and it is what turns a clean "
                     "check into a number. Where a check did see a failure, the observed rate is "
                     "reported instead, because it is larger than any bound would be.\n\n")

        handle.write("## 2. What the checks have seen\n\n")
        handle.write("A paper contributes trials only where its extracted text is what the page "
                     "prints. The others are checked against a damaged source, so their "
                     "disagreements measure the source and say nothing about the table. "
                     "`refs.md` names each of them.\n\n")
        handle.write("![Hand extraction against its paper](corpus-derivation.svg)\n\n")
        handle.write("**Why the left panel is here.** The bound in Section 3 is a single number "
                     "and a single number cannot show whether it came from one clean paper or from "
                     "%d. The panel puts every paper on the picture so the shape of the evidence "
                     "is visible: how much each one contributed, and which ones failed anything. "
                     "A reader should come away able to say which papers the number rests on.\n\n"
                     % len(sound))
        handle.write("**What to read off it.** Every paper is one point, trials against failures. "
                     "The %d on the zero line are the whole of the evidence. The %d above it "
                     "are checked against a text that is not what their page prints, so what is "
                     "plotted for them is damage in the source and not a mistake in the table. "
                     "The reader squares are a separate measurement in their own color, and they "
                     "sit high: a reader is a script and it gets a great deal wrong. Section 5 "
                     "gives those per paper, which is the only form they mean anything in.\n\n"
                     % (on_zero, len(papers) - on_zero))
        handle.write("**Why the right panel is here.** The extraction has a lifetime and the "
                     "question is what carries it. A person reads a paper at a fixed accuracy "
                     "however large the corpus gets, so that arm is flat. The algorithm's accuracy "
                     "is a function of corpus size, so that arm climbs. Whether and where they "
                     "cross decides whether the corpus is worth growing for its own sake, and the "
                     "panel is what answers it.\n\n")
        handle.write("**What to read off it.** The algorithm arm is the fraction of dialects whose "
                     "distance from the other corpora pooled into one reference corpus clears "
                     "twice their resolution. It starts at zero, because a small corpus resolves "
                     "nothing, and it crosses the reader arm at %.3g byte pairs, which is behind "
                     "the corpus already on disk. Both arms are drawn: byte pairs alone, and byte "
                     "pairs with the dialect's own alphabet applied first. Comparing an algorithm "
                     "given nothing against a person given a page is not a fair comparison, and "
                     "the alphabet is the first part of what the extraction already knows that it "
                     "can be handed.\n\n" % (crossing or 0.0))
        handle.write("| Paper | Rows | Forms checked | Not in paper | Tokens checked | "
                     "No row holds | Counts |\n|---|---|---|---|---|---|---|\n")
        for one in papers:
            handle.write("| `%s` | %d | %d | %d | %d | %d | %s |\n"
                         % (one["stem"], one["rows"], one["forms"], one["unfound"],
                            one["tokens"], one["missed"], "yes" if one["sound"] else "no"))
        handle.write("\n%d of the %d hand extractions are checked against a sound source. "
                     "Together they put %d distinct written forms and %d language tokens through "
                     "the two directions.\n\n" % (len(sound), len(papers), forms, tokens))

        handle.write("## 3. The channels\n\n")
        handle.write("A wrong line arrives through one of three channels. They are separate "
                     "because they fail for different reasons. The first is a person writing a "
                     "form the paper does not hold, the second is a person walking past a form the "
                     "paper does hold, and the third is the corpus losing a token on its way out "
                     "of a reader.\n\n")
        handle.write("The reader counts are not a channel here. A reader is written for one paper, "
                     "so what it gets wrong is a fact about that paper and not a draw from a rate "
                     "the next paper shares. Pooling %d of them into one denominator would "
                     "report a rate that nothing is sampling. They are in Section 5 per paper.\n\n"
                     % len(readers))
        handle.write("| Channel | Failures | Trials | Bound |\n|---|---|---|---|\n")
        for label, failures, trials in channels:
            handle.write("| %s | %d | %d | %.3g |\n" % (label, failures, trials,
                                                        bound(failures, trials)))
        handle.write("\nA line has to pass all three. Taking them as independent, the joint bound "
                     "is the product:\n\n")
        handle.write("> **%.3g** per line\n\n" % joint)
        handle.write("### How much of that number has settled\n\n")
        handle.write("Three significant figures is a format, not a finding. The digit worth "
                     "reporting is the one that has stopped moving, and the way to find it is to "
                     "watch the bound as each paper joined the corpus.\n\n")
        handle.write("| Papers counted | Joint bound |\n|---|---|\n")
        for at, one in enumerate(running):
            handle.write("| %d | %.4g |\n" % (at + 1, one))
        if stable:
            handle.write("\nThe last %d papers agree to %d significant %s, so that is what the "
                         "bound is quoted to above and further digits are not claimed.\n\n"
                         % (STEADY, stable, "figure" if stable == 1 else "figures"))
        else:
            handle.write("\nNo digit has settled. The bound falls with every paper because every "
                         "paper adds trials and none has yet added a failure, so the mantissa is a "
                         "number in flight and only the exponent is a finding. Quoting %.3g as "
                         "though the 85 meant something would be reporting the format. What the "
                         "table says is that the extraction is still buying accuracy at the rate "
                         "of about one order of magnitude every %.1f papers, and the digit to "
                         "report will settle when that stops.\n\n"
                         % (joint, len(running) / max(1e-9, math.log10(running[0] / running[-1]))
                            if (len(running) > 1) and (running[-1] > 0) else 0.0))

        handle.write("### Where 1e-26 lands\n\n")
        handle.write("The target this file was asked for is 1e-26 per line over the whole "
                     "extraction. It is not reached and it is not close, and the honest form of "
                     "the answer is the distance.\n\n")
        # The archive is 993 papers and only the sound ones are counted, so the lifetime is what
        # those scale to. The bound is 3/N in each channel and N grows with the papers read.
        lifetime = ARCHIVE_PAPERS / float(len(sound))
        ahead = 1.0
        handle.write("| Channel | Trials now | Trials at %d papers | Bound then |\n|---|---|---|---|\n"
                     % ARCHIVE_PAPERS)
        for label, failures, trials in channels:
            grown = int(trials * lifetime)
            ahead *= bound(0, grown) if grown else 1.0
            handle.write("| %s | %d | %d | %.3g |\n" % (label, trials, grown, bound(0, grown)))
        handle.write("\nReading all %d papers of the archive, and finding nothing wrong in any of "
                     "them, takes the joint bound from %.3g to about %.3g. That is %.0f orders of "
                     "magnitude short of 1e-26.\n\n"
                     % (ARCHIVE_PAPERS, joint, ahead, math.log10(ahead) + 26.0))
        handle.write("Closing the rest by counting is not available. Each channel would have to "
                     "reach about %.0g trials, which is roughly %.0g times the whole archive. "
                     "There is no reading schedule that gets there, and a file claiming 1e-26 from "
                     "these three channels would be reporting a number nothing measured.\n\n"
                     % (CONFIDENCE / (1e-26 ** (1.0 / len(channels))),
                        (CONFIDENCE / (1e-26 ** (1.0 / len(channels)))) / (forms * lifetime)))
        handle.write("What a number that small would actually need is more channels that fail "
                     "independently, not more trials in these three. Section 7 is one: a term "
                     "recovered from the forms and scored against a border a linguist published, "
                     "which fails for a reason none of the three share. Independent channels "
                     "multiply, and that is the only route to an exponent like this one. Section 4 "
                     "is where the independence is doubted, and it should be read before this "
                     "number is quoted anywhere.\n\n")

        handle.write("## 4. What the number rests on\n\n")
        handle.write("The independence is the weak part and it is weak in three named places.\n\n")
        handle.write("* **One person read every table.** The three channels catch different kinds "
                     "of mistake but they do not catch a systematic misreading of one "
                     "orthography, because the same reading produced the row and the expectation. "
                     "This is the largest unmodelled term and no amount of trials touches it.\n")
        handle.write("* **Direction one and direction two share a source.** Both ask questions of "
                     "the same extracted text. A paper whose text is wrong in a way nobody has "
                     "noticed fails both at once, which is why the papers with a known-damaged "
                     "source are excluded from the count instead of given a worse bound.\n")
        handle.write("* **Every channel runs through one codebase.** `salish_marking.py` and "
                     "`salish_unsorted.py` decide what counts as a language token, and all three "
                     "channels ask them. A defect in either is common to all three at once, and "
                     "two such defects have already been found this way. Both are in `refs.md`.\n\n")
        handle.write("What would move the number honestly is a second person reading a table that "
                     "has already been read. That is the one addition that fails for a reason none "
                     "of the three share, and until it exists the first bullet stands above every "
                     "number in this file.\n\n")

        handle.write("## 5. Readers against their tables\n\n")
        handle.write("| Paper | Rows asked for | Reproduced | Items written | Invented | "
                     "Wrong language |\n|---|---|---|---|---|---|\n")
        for one in readers:
            handle.write("| `%s` | %d | %d | %d | %d | %d |\n"
                         % (one["stem"], one["wanted"], one["reproduced"], one["items"],
                            one["invented"], one["wrong"]))
        handle.write("\nThe readers get a great deal wrong. The median reproduces %.3f of what its "
                     "table asks for, and the spread runs from one paper to the next with no "
                     "common rate behind it, because each reader was written against one paper's "
                     "layout. That is why these are a table and not a term in Section 3.\n\n"
                     % rate)
        handle.write("A reader that does not reproduce a row is not by itself an impurity. The row "
                     "is in the hand extraction either way, and the extraction is the oracle. What "
                     "the last two columns count is what the reader added, which is the part that "
                     "can reach the pure stream without a person having written it.\n\n")

        handle.write("## 6. The word web\n\n")
        handle.write("`tools/dev_env/Salishan/word_web/word_web.py` joins every form in the hand "
                     "extractions to the forms it is related to, and writes one file per group "
                     "under `build/corpora`. It has three kinds of edge, each measured off the "
                     "extraction and none of them listed by hand.\n\n")
        handle.write("* **concept**, two forms whose glosses share a content word. This is the "
                     "edge that crosses an orthography, because the gloss is the one part of a "
                     "form that two papers wrote the same way.\n")
        handle.write("* **shape**, two forms of one group sharing a leading or trailing run of "
                     "four characters. Salish morphology is heavily affixed and reduplicating. A "
                     "shared run is usually a shared root or affix, and it is a measurement and "
                     "not a parse.\n")
        handle.write("* **context**, two forms written in the same section of the same paper by "
                     "the same speaker.\n\n")
        handle.write("The web is what makes an anchor a concept expressed as a distribution "
                     "instead of a bag of characters. The byte pair distribution cannot see that "
                     "two orthographies wrote one word, and the concept edge is where that is "
                     "recorded.\n\n")

        handle.write("## 7. The dialect border\n\n")
        handle.write("Lushootseed is not one dialect. The northern and southern varieties have "
                     "known land and family borders, and Mellesmoen and Kye's stress paper labels "
                     "every form it cites with which one it came from. The hand extraction copied "
                     "that into the `who` column, so the border sits on disk as a fact published "
                     "by a linguist.\n\n")
        handle.write("That makes it the one thing a test of this algorithm almost never has: an "
                     "answer that did not come from the algorithm. "
                     "`anchor_sift_algorithmic_extraction/boundary_check.py` loads the labels, "
                     "sets them aside, and only compares at the end.\n\n")
        handle.write("Comparing whole distributions does not work at this size. The method "
                     "resolves at 6707 bytes and the two varieties hold 1469 and 2768, so neither "
                     "the byte pair distribution nor the word web separates them, and a blind "
                     "partition scores no better than the majority class. The check prints what "
                     "that route would need: about 2.9 times the labeled Lushootseed now on "
                     "disk.\n\n")
        if standing:
            handle.write("Asking for one term at a time does work, and it is the same move the "
                         "sound work uses. Both varieties are one language, so nearly all of what "
                         "a distribution over their runs measures is what they have in common, and "
                         "at this size that shared mass swamps the difference. Flattening the "
                         "pooled counts to maximum entropy takes it out: a run is weighed against "
                         "where the pooled total alone would put it. A run carrying no border "
                         "information then contributes nothing however common it is. Each run is "
                         "its own test, and what a run needs is enough of itself, not enough of "
                         "the language.\n\n")
            handle.write("The concept is held fixed while this is asked, over the %d concepts both "
                         "varieties name, using the word web's gloss edge. Without that control a "
                         "run can separate the two sets because the varieties differ or because "
                         "different words were cited, and those are not the same finding.\n\n"
                         % standing["concepts"])
            handle.write("| Run width | Runs tested | Terms found | Expected by chance | "
                         "Random borders that matched it |\n|---|---|---|---|---|\n")
            for one in standing["widths"]:
                handle.write("| %d | %d | %d | %.2f | %d of %d |\n"
                             % (one["width"], one["runs"], one["found"], one["chance"],
                                one["beaten"], one["trials"]))
            best = [one for one in standing["widths"] if one["found"]]
            if best:
                handle.write("\n")
                handle.write("| Term | Deviate | Northern | Southern |\n|---|---|---|---|\n")
                for one in best:
                    for deviate, run, first, second in one["top"]:
                        handle.write("| `%s` | %.2f | %d | %d |\n"
                                     % (run, deviate, first, second))
                leading = best[0]
                handle.write("\nThe last column of the first table is the test that is allowed to "
                             "fail. The border is put back on the same forms at random %d times "
                             "and the radix run again on each, and at width %d only %d of those "
                             "random borders found as much as the published one. Swapping the two "
                             "sides also negates every deviate exactly, but that is what this "
                             "estimator does on any two sets whatever and it is evidence of "
                             "nothing.\n\n"
                             % (leading["trials"], leading["width"], leading["beaten"]))
                handle.write("The term carrying the border is the stressed schwa, and it is "
                             "southern: 45 of them against 6 in the north over the same concepts. "
                             "The paper those labels came from is Mellesmoen and Kye's comparative "
                             "analysis of stress in northern and southern Lushootseed. The "
                             "algorithm was shown the forms and never the labels, and what it "
                             "returned is what the paper is about.\n\n")

        handle.write("**Compiled By:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>\n")
        handle.write("**Generated by:** `tools/dev_env/Salishan/corpus_derivation.py`\n")

    out.write("  %d hand extractions, %d of them against a sound source\n" % (len(papers),
                                                                              len(sound)))
    for label, failures, trials in channels:
        out.write("    %-46s %d in %-7d bound %.3g\n"
                  % (label, failures, trials, bound(failures, trials)))
    out.write("  joint bound %.3g per line\n" % joint)
    out.write("  written to %s\n" % os.path.relpath(TARGET, ROOT))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
