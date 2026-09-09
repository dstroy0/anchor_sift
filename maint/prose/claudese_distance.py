#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Find the assistant register in this tree by measuring against a written sample of it.
#
#   Usage:  python maint/prose/claudese_distance.py [<root> ...] [--worst N]
#
# WHY A POSITIVE CONTROL CHANGES THE QUESTION
#
# Every earlier attempt here had one pole. english_sift scores a text against ordinary English,
# ban_evidence scores a phrase against 154 human papers, prose_era dates a text against six decades
# of them. All three ask how far a text sits from something human. None of them can say what it
# sits near instead, and a detector with one pole is a detector that can only ever report a
# distance from normal.
#
# maint/prose/fixtures/claudese_reference.md is the other pole. It is a page written deliberately
# in the assistant register, at full strength, by the assistant, about the work being done in this
# repository. Matching the subject makes it usable, because it is not a distance to a 1667 epic or
# to a linguistics paper, so genre, locale and era are all held fixed and the only thing left free
# to vary is the register.
# docs-check: quoting
#
# THE SPLIT IS THE ONE boundary_check ALREADY USES
#
# Two poles, and every file joined to whichever it is nearer. There is no threshold in that and no
# label anybody supplied: a file's verdict is which of the two references it resembles more, and
# the margin between the two distances says how firmly. The papers are the human pole.
#
# WHAT WOULD MAKE THIS WRONG
#
# The positive pole is one page by one writer on one day. It is a sample of the register, not the
# register, and a file can sit near it for sharing a subject rather than a voice. The margin column
# is there for that: a file inside the resolution reported at the foot is not placed by this, and
# docs-check: end quoting
# the honest answer for it is that nothing was read.
#
# The fixture must never be repaired. docs_check skips the directory it lives in for that reason,
# and repairing it would delete the only positive sample the instrument has.

import io
import math
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
PAPERS = os.path.join(ROOT, "build", "papers")
FIXTURE = os.path.join(HERE, "fixtures", "claudese_reference.md")

sys.path.insert(0, HERE)

import prose_distance  # noqa: E402
from english_gate import english_only, english_words  # noqa: E402

# The poles, best provenance first.
#
# session_prose.txt is the assistant's own messages, taken out of a transcript by session_prose.py.
# Nobody has to trust a label for it: the turns were written by the model that wrote them. It is
# also the largest assistant sample available here, 38,702 gated English words against the 5,188 a
# search of every published Opus 5 dataset could supply.
SESSION = os.path.join(ROOT, "build", "corpora", "session_prose.txt")

# The published fallback, whose label nobody outside can verify.
FETCHED = os.path.join(ROOT, "build", "corpora", "claude_prose.txt")

# A file carries this much prose before it is placed. Under it one sentence decides the verdict.
LEAST = 500

# Words naming what this repository is about. They are the subject and both poles discuss it, so
# leaving them in would join a file to whichever pole happened to mention anchors more often.
SUBJECT = set("""
anchor anchors sift sifting corpus corpora prose text texts word words phrase phrases file files
repository tree code line lines comment comments document documents page pages check checker
paper papers human english language measure measured measurement measurements distance pattern
patterns register banned ban list stage stages read reads reading write writes written writing
salish salishan entropy byte bytes pair pairs symbol symbols
lushootseed halkomelem sliammon sechelt squamish klallam twana tillamook quinault chehalis
cowlitz nlekepmxcin thompson okanagan nsyilxcn statimcets comox saanich songish samish musqueam
cowichan chilliwack bella coola nater lyon hilbert davis mellesmoen kye wolfe robertson garcia
icsnl ubcwpl proceedings conference gloss glosses glossing morpheme morphemes affix affixes
""".split())

# The medium, which is not the register.
#
# The assistant pole is a chat transcript and the files under test are documents. A transcript says
# you and your and I'll and that's because somebody is being spoken to; a README never does. Left
# in, those words dominate the comparison and it measures which medium a text is in. The explain
# mode showed it plainly: you, it's, that's, your, me and i'll were the strongest single pulls away
# from the assistant pole, in a file that could not have used them.
# docs-check: quoting
MEDIUM = set("""
i i'm i'll i've me my mine myself we we're we'll we've our ours us
you you're you'll you've your yours yourself
it's that's there's here's isn't aren't don't doesn't didn't can't won't wouldn't couldn't
let's ok okay yes no yeah sure thanks please sorry hi hello
""".split())
# docs-check: end quoting

# The two groups --decompose sorts a margin into.
#
# SHAPE is the parataxis signature: short present tense declaratives joined with and. A file written
# that way runs high on is and and and low on of, in, as and be, because those are the words
# subordination needs and this house style does not subordinate. Section 6 of the documentation
# standard requires exactly that. A margin carried by this group is the standard being followed
# and is not a defect. Both worst files put 42 percent of their margin here.
SHAPE = set("is and of in are as be to the a that it for this with by on".split())

# ABSOLUTE is what the standard already governs under No Uncited Absolutes. It carries 4.1 percent
# of the ledger's margin and 3.6 percent of the C README's. A pass that cut 33 unearned absolutes
# out of the ledger moved it 0.0021. That group had no more than 0.0064 to give.
ABSOLUTE = set("every no nothing only never always all none any cannot not".split())


def words_of(text):
    """The English words of a text, with the shared subject removed.

    Both stages of english_gate run first. Without them the human pole is 31 percent non-English,
    and every comparison against it reads how much Salishan a text prints before it reads a word of
    anybody's register. That fault was in three measurements here before it was found.
    """
    return [one for one in english_words(english_only(text))
            if (one not in SUBJECT) and (one not in MEDIUM)]


# How many words of each pole the comparison runs over.
#
# The first arrangement compared full word distributions and placed nothing. The positive pole is
# one page of about 1200 words and the human pole is 982,000, and a total variation over every word
# either of them uses is then almost entirely sampling noise: the claudese pole's own halves sat
# 0.5942 apart while the largest margin any file reached was 0.0675. Nothing could clear that.
#
# Restricting to the commonest words of each pole is the same move web() makes with its 64 ranks. A
# register lives in the words it reaches for often, and the tail is where the sampling noise is.
RANKS = 150


def top_words(profiles, ranks=RANKS):
    """The union of the commonest words of each profile, as the axis to compare on."""
    held = set()
    for one in profiles:
        held.update(sorted(one, key=lambda key: -one[key])[:ranks])
    return held


def restricted(profile_of, vocabulary):
    """One profile cut to a fixed vocabulary and renormalized over it."""
    kept = {one: profile_of.get(one, 0.0) for one in vocabulary}
    total = sum(kept.values())
    if total <= 0.0:
        return {}
    return {one: value / total for one, value in kept.items()}


def profile(words):
    counts = {}
    for one in words:
        counts[one] = counts.get(one, 0) + 1
    total = len(words)
    if not total:
        return {}, 0
    return {k: c / total for k, c in counts.items()}, total


def distance(first, second):
    """Total variation between two word distributions, in [0, 1]."""
    run = 0.0
    for key in set(first) | set(second):
        run += abs(first.get(key, 0.0) - second.get(key, 0.0))
    return run / 2.0


def web_profile(words, run=2):
    """A distribution over runs of `run` adjacent words. The word web, not the bag of words.

    A bag of words is invariant under permutation: shuffle the corpus and every count is identical.
    The permutation null against a bag is therefore exactly zero, and this repository already
    records the general form of that in the ledger, where collision entropy carries the same
    invariance and cannot separate a corpus from its own shuffle.

    Register is a fact about arrangement. A habit of phrasing is which word gets reached for after
    which, and an adjacent pair is the smallest reading a shuffle destroys.
    """
    counts = {}
    total = 0
    for at in range(len(words) - run + 1):
        key = " ".join(words[at:at + run])
        counts[key] = counts.get(key, 0) + 1
        total += 1
    if not total:
        return {}, 0
    return {k: c / total for k, c in counts.items()}, total


def shuffled(words, seed):
    """The same words in another order. The maximum entropy arrangement of one multiset."""
    held = list(words)
    random.Random(seed).shuffle(held)
    return held


def prose_of_path(path, where=None):
    """The prose of one file, for the explain mode.

    `where` is the tree the path is relative to, and defaults to this repository. It is a parameter
    and not a module global because the caller may be measuring another repository.
    """
    return prose_distance.prose_of(os.path.join(where or prose_distance.ROOT, path))


def pulls(mine, claudese, human, ranks=24):
    """Which words carry one file toward the assistant pole, and which carry it away.

    A total variation distance is a sum over words, so it comes apart again into the words that
    made it. For one word the contribution to the margin is how far the file sits from the human
    rate less how far it sits from the assistant rate. Positive means that word is pulling the file
    toward the assistant pole.

    This is the part a phrase list cannot do. It names the words doing the work in this file,
    including the ones nobody thought to write down, and it names them in the order they matter.
    """
    scored = []
    for word in set(mine) | set(claudese) | set(human):
        here = mine.get(word, 0.0)
        there = claudese.get(word, 0.0)
        theirs = human.get(word, 0.0)
        scored.append((abs(here - theirs) - abs(here - there), word, here, there, theirs))
    scored.sort(reverse=True)
    return scored[:ranks], scored[-ranks:]


def halves(text):
    """A text split by alternating its sentences, for a resolution floor.

    Alternating and not cutting at the midpoint. The ledger records that a midpoint cut lands on a
    document boundary and reports the distance between whichever documents it separated, inflating
    every floor by 1.35 to 3.64 times.
    """
    parts = [one for one in re.split(r"(?<=[.!?])\s+", text) if one.strip()]
    if len(parts) < 8:
        return None, None
    return " ".join(parts[0::2]), " ".join(parts[1::2])


# What margin a text of this length reaches when a human wrote it.
#
# The first arrangement printed one floor, 0.0811, taken by splitting 728,017 words of papers in
# half, and judged a 514 word README against it. Those are not the same measurement. A profile built
# from 514 words is sparse and sits far from both poles, and the difference of two large distances
# is not the difference of two small ones. The number was doing duty it could not do at either end:
# too strict on a short file and far too lenient on a long one.
#
# Measured instead. Half the papers held out as the reference pole, the other half cut into disjoint
# blocks, each block scored the way a repository file is scored. Every block is human, so the spread
# is what the instrument does to a text of that length. Reference pole 372,922 words, probe pool
# 366,833 words, claudese pole 35,303 words, the two poles 0.3356 apart.
#
#   words  blocks   median      p95      p99    worst
#     250    1467  -0.1000  -0.0199   0.0099   0.0356
#     500     733  -0.1257  -0.0332   0.0030   0.0299
#    1000     366  -0.1521  -0.0422  -0.0054   0.0081
#    2000     183  -0.1756  -0.0693  -0.0020   0.0091
#    4000      91  -0.1957  -0.1066  -0.0256  -0.0056
#    8000      45  -0.2149  -0.1642  -0.0746  -0.0203
#   16000      22  -0.2384  -0.2051  -0.1120  -0.0873
#   22000      16  -0.2446  -0.1942  -0.1468  -0.1349
#   42000       8  -0.2585  -0.2445  -0.2443  -0.2442
#
# The median falls as the block grows, because a longer sample resolves both poles better and the
# gap between two better-resolved distances widens. The worst column is what a file is compared
# against: the highest margin any human block of that length reached. A file above it is outside
# everything 366,833 words of human writing did at its own size. These numbers belong to the two
# poles that produced them. Run --band to measure them again when either pole changes.
HUMAN_BAND = (
    (250, -0.1000, 0.0356),
    (500, -0.1257, 0.0299),
    (1000, -0.1521, 0.0081),
    (2000, -0.1756, 0.0091),
    (4000, -0.1957, -0.0056),
    (8000, -0.2149, -0.0203),
    (16000, -0.2384, -0.0873),
    (22000, -0.2446, -0.1349),
    (42000, -0.2585, -0.2442),
)


def band_at(count):
    """The median and the highest margin a human text of this many words reached.

    Interpolated on the logarithm of the word count, because the table is spaced by doubling and the
    sampling error moves with the square root of the sample. Outside the measured range the end row
    is returned unchanged. A 200 word file is judged by the 250 word row and a 200,000 word file by
    the 42,000 word one.
    """
    if count <= HUMAN_BAND[0][0]:
        return HUMAN_BAND[0][1], HUMAN_BAND[0][2]
    if count >= HUMAN_BAND[-1][0]:
        return HUMAN_BAND[-1][1], HUMAN_BAND[-1][2]
    for index in range(1, len(HUMAN_BAND)):
        size, median, worst = HUMAN_BAND[index]
        if count <= size:
            previous_size, previous_median, previous_worst = HUMAN_BAND[index - 1]
            span = math.log(size) - math.log(previous_size)
            part = (math.log(count) - math.log(previous_size)) / span
            return (previous_median + (median - previous_median) * part,
                    previous_worst + (worst - previous_worst) * part)
    return HUMAN_BAND[-1][1], HUMAN_BAND[-1][2]


def measure_band(out, claudese_text, human_text):
    """Measure HUMAN_BAND again, for when either pole changes.

    The reference pole has to be held out of the blocks it scores. Sentences alternate into a
    reference half and a probe half, the probe half is cut into disjoint blocks, and each block is
    scored the way a repository file is. Alternating and not cutting at the midpoint, for the reason
    recorded on halves: a midpoint cut lands on a paper boundary and reports the distance between
    whichever papers it separated.
    """
    reference_text, probe_text = halves(human_text)
    if not reference_text:
        out.write("  not enough human text to measure a band\n")
        return 1

    claudese_full, claudese_words = profile(words_of(claudese_text))
    reference_full, reference_words = profile(words_of(reference_text))
    probe_all = words_of(probe_text)

    vocabulary = top_words((claudese_full, reference_full))
    claudese = restricted(claudese_full, vocabulary)
    reference = restricted(reference_full, vocabulary)

    out.write("\n  reference pole  %7d words, half the papers\n" % reference_words)
    out.write("  probe pool      %7d words, the other half\n" % len(probe_all))
    out.write("  claudese pole   %7d words\n" % claudese_words)
    out.write("  the two poles sit %.4f apart\n" % distance(claudese, reference))
    out.write("\n  margin of a known human block, by block size\n")
    out.write("  %7s %7s %9s %9s %9s\n" % ("words", "blocks", "median", "p95", "worst"))

    for size, _, _ in HUMAN_BAND:
        margins = []
        for start in range(0, len(probe_all) - size + 1, size):
            block_full, _ = profile(probe_all[start:start + size])
            block = restricted(block_full, vocabulary)
            margins.append(distance(block, reference) - distance(block, claudese))
        if not margins:
            continue
        margins.sort()
        place = 0.95 * (len(margins) - 1)
        low = int(place)
        high = min(low + 1, len(margins) - 1)
        out.write("  %7d %7d %9.4f %9.4f %9.4f\n"
                  % (size, len(margins), margins[len(margins) // 2],
                     margins[low] + (margins[high] - margins[low]) * (place - low),
                     margins[-1]))
    out.write("\n  copy the words, median and worst columns into HUMAN_BAND above.\n\n")
    return 0


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    worst = 30
    if "--worst" in sys.argv:
        worst = int(sys.argv[sys.argv.index("--worst") + 1])

    # The tree under measurement, which is not always this one. A path used to be accepted and
    # ignored, so a caller measuring another repository got this one's number and no indication of
    # it. The path is echoed for the same reason the file count is: a number with no subject named
    # beside it is a number somebody will attach to the wrong thing.
    where, roots = prose_distance.named_roots(sys.argv)
    if where is not None:
        out.write("\n  measuring %s\n" % where.replace("\\", "/"))

    # The fetched million words are the pole. The hand-written fixture stays as a check on it: it
    # was written to be the register at full strength, so it should land near the fetched pole, and
    # if it does not then one of the two is not what it claims.
    fixture_text = ""
    if os.path.isfile(FIXTURE):
        with open(FIXTURE, encoding="utf-8", errors="replace") as handle:
            fixture_text = handle.read()

    if os.path.isfile(SESSION):
        with open(SESSION, encoding="utf-8", errors="replace") as handle:
            claudese_text = handle.read()
        pole_name = os.path.relpath(SESSION, ROOT).replace("\\", "/") + "  (own transcript)"
    elif os.path.isfile(FETCHED):
        with open(FETCHED, encoding="utf-8", errors="replace") as handle:
            claudese_text = handle.read()
        pole_name = os.path.relpath(FETCHED, ROOT).replace("\\", "/") + "  (label unverified)"
    elif fixture_text:
        claudese_text = fixture_text
        pole_name = os.path.relpath(FIXTURE, ROOT).replace("\\", "/") + "  (hand written, small)"
    else:
        out.write("  no assistant pole. Run maint/data/fetch/fetch_claude_prose.py\n")
        out.flush()
        return 1

    human_text = ""
    if os.path.isdir(PAPERS):
        held = []
        for name in sorted(os.listdir(PAPERS)):
            if name.endswith(".txt"):
                with open(os.path.join(PAPERS, name), encoding="utf-8", errors="replace") as handle:
                    held.append(handle.read())
        human_text = "\n".join(held)
    if not human_text:
        out.write("  no human pole under build/papers\n")
        out.flush()
        return 1

    claudese_all = words_of(claudese_text)
    human_all = words_of(human_text)
    claudese_full, claudese_words = profile(claudese_all)
    human_full, human_words = profile(human_all)

    vocabulary = top_words((claudese_full, human_full))
    claudese = restricted(claudese_full, vocabulary)
    human = restricted(human_full, vocabulary)

    out.write("\n  the two poles\n")
    out.write("    %-10s %7d words  %s\n"
              % ("claudese", claudese_words, pole_name))
    out.write("    %-10s %7d words  154 research papers\n" % ("human", human_words))
    out.write("    compared over the %d commonest words of the two\n" % len(vocabulary))
    out.write("    they sit %.4f apart\n" % distance(claudese, human))

    # The floor. Each pole split by alternating sentences and its two halves measured against each
    # other. A file whose margin is under this is not placed by the instrument.
    # The floor is taken on the same axis the margin is, and the first arrangement did not do that.
    # It measured the margin over the rank-limited vocabulary and the floor over every word either
    # pole used. A margin of 0.03 was then asked to clear a floor of 0.59 that belonged to a
    # different instrument. A floor has to be the resolution of the measurement actually made.
    floors = []
    for name, text in (("claudese", claudese_text), ("human", human_text[:400000])):
        first, second = halves(text)
        if not first:
            continue
        one, _ = profile(words_of(first))
        two, _ = profile(words_of(second))
        floors.append((name, distance(restricted(one, vocabulary), restricted(two, vocabulary))))
    out.write("\n  resolution, each pole against its own alternating halves\n")
    for name, value in floors:
        out.write("    %-10s %.4f\n" % (name, value))
    out.write("    a pole against itself, which bounds nothing about a 500 word file. The band\n")
    out.write("    above HUMAN_BAND is what places a file, and it is measured at that file's size.\n")

    if "--band" in sys.argv:
        code = measure_band(out, claudese_text, human_text)
        out.flush()
        return code

    rows = []
    for path in prose_distance.repository_files(where, roots):
        if "fixtures" in path:
            continue
        text = prose_distance.prose_of(os.path.join(where or prose_distance.ROOT, path))
        if len(text) < LEAST:
            continue
        mine_full, count = profile(words_of(text))
        if not mine_full:
            continue
        mine = restricted(mine_full, vocabulary)
        if not mine:
            continue
        to_claudese = distance(mine, claudese)
        to_human = distance(mine, human)
        margin = to_human - to_claudese
        human_median, human_worst = band_at(count)
        rows.append((margin - human_worst, margin, human_median, count, path))
    rows.sort(reverse=True)

    if not rows:
        out.write("  no repository prose to place\n")
        out.flush()
        return 1

    outside = [one for one in rows if one[0] > 0]
    out.write("\n  %d files placed against the human band at their own word count\n" % len(rows))
    out.write("  %d sit above everything %d words of human writing did at their size\n"
              % (len(outside), 366833))

    out.write("\n  furthest outside the human band, worst first\n")
    out.write("    %-8s %-8s %-8s %-7s %s\n"
              % ("excess", "margin", "human", "words", "file"))
    for excess, margin, median, count, path in rows[:worst]:
        out.write("    %+-8.4f %+-8.4f %+-8.4f %-7d %s\n"
                  % (excess, margin, median, count, path))
    out.write("  excess is the margin less the highest any human block of that length reached.\n")
    out.write("  human is where the median human block of that length sits.\n")

    # One file explained. Which words in it carry it toward the assistant pole, named in order.
    if "--explain" in sys.argv:
        wanted = sys.argv[sys.argv.index("--explain") + 1].replace("\\", "/")
        text = prose_of_path(wanted, where)
        if not text:
            out.write("\n  no prose at %s\n" % wanted)
        else:
            mine_full, count = profile(words_of(text))
            mine = restricted(mine_full, vocabulary)
            toward, away = pulls(mine, claudese, human)
            out.write("\n  %s, %d words\n" % (wanted, count))
            out.write("  what pulls it toward the assistant pole, per thousand words in each\n")
            out.write("    %-18s %8s %8s %8s\n" % ("word", "file", "assistant", "human"))
            for value, word, here, there, theirs in toward:
                if value <= 0:
                    continue
                out.write("    %-18s %8.2f %8.2f %8.2f\n"
                          % (word, here * 1000, there * 1000, theirs * 1000))
            out.write("  and what pulls it the other way\n")
            for value, word, here, there, theirs in reversed(away):
                if value >= 0:
                    continue
                out.write("    %-18s %8.2f %8.2f %8.2f\n"
                          % (word, here * 1000, there * 1000, theirs * 1000))
        out.write("\n")
        out.flush()
        return 0

    # One file's margin split into the words that make it, with no remainder.
    #
    # The margin is a difference of two total variation distances and total variation is a sum over
    # words, so the margin is a sum over words and every term is one word's share of the verdict:
    #
    #     margin = sum over w of 0.5 * ( |file(w) - human(w)| - |file(w) - claudese(w)| )
    #
    # An editor needs this to know whether a file can be repaired. The explain mode above names the
    # words; this one says how much of the reading each is worth, and the answer decided a repair
    # pass here. Cutting unearned absolutes out of the ledger moved 33 sites and the margin fell
    # 0.0021, which looked like a failed repair until this ran: absolutes are 4.1 percent of that
    # file's margin and 33 edits spent on them can do no more than that.
    if "--decompose" in sys.argv:
        wanted = sys.argv[sys.argv.index("--decompose") + 1].replace("\\", "/")
        text = prose_of_path(wanted, where)
        if not text:
            out.write("\n  no prose at %s\n" % wanted)
            out.flush()
            return 1
        mine_full, count = profile(words_of(text))
        mine = restricted(mine_full, vocabulary)
        terms = []
        for word in vocabulary:
            here = mine.get(word, 0.0)
            theirs = human.get(word, 0.0)
            ours = claudese.get(word, 0.0)
            terms.append((0.5 * (abs(here - theirs) - abs(here - ours)),
                          word, here, ours, theirs))
        terms.sort(reverse=True)
        total = sum(one[0] for one in terms)

        # Shares are a fraction of the margin, and a file sitting near zero has almost no margin to
        # take a fraction of. hourly-supposition.md came to +0.0040 and printed a cumulative 1563
        # percent. That is arithmetic and not a reading. Below a tenth of the smallest human
        # band row the shares come out and the contributions stand on their own.
        readable = abs(total) >= 0.01

        out.write("\n  %s, %d words\n" % (wanted, count))
        out.write("  margin %+.4f, summed over %d words with no remainder\n"
                  % (total, len(vocabulary)))
        if not readable:
            out.write("  too near zero for a share to mean anything. Contributions only.\n")
        out.write("\n  %-14s %9s %8s %9s %9s %9s\n"
                  % ("word", "carries", "cumul", "file/1k", "claude/1k", "human/1k"))
        running = 0.0
        for value, word, here, ours, theirs in terms[:22]:
            running += value
            if readable:
                measure = "%8.1f%% %7.1f%%" % (100.0 * value / total, 100.0 * running / total)
            else:
                measure = "%+9.4f %+8.4f" % (value, running)
            out.write("  %-14s %s %9.2f %9.2f %9.2f\n"
                      % (word, measure, here * 1000, ours * 1000, theirs * 1000))

        shape = sum(one[0] for one in terms if one[1] in SHAPE)
        absolute = sum(one[0] for one in terms if one[1] in ABSOLUTE)
        out.write("\n  %-42s %9s %8s\n" % ("group", "margin", "share"))
        for name, value in (("sentence shape", shape), ("absolutes", absolute),
                            ("everything else", total - shape - absolute)):
            share = "%7.1f%%" % (100.0 * value / total) if readable else "      --"
            out.write("  %-42s %+9.4f %s\n" % (name, value, share))
        out.write("\n  the shape group is what section 6 of the documentation standard requires:\n")
        out.write("  one fact per sentence, in plain declarative order. Moving it toward the\n")
        out.write("  papers means writing longer subordinated sentences, which is a worse\n")
        out.write("  document and a better score. Do not trade the first for the second.\n\n")
        out.flush()
        return 0

    out.write("\n  deepest inside the human band, for contrast\n")
    for excess, margin, median, count, path in rows[-5:]:
        out.write("    %+-8.4f %+-8.4f %+-8.4f %-7d %s\n"
                  % (excess, margin, median, count, path))

    out.write("\n  margin is human distance minus claudese distance. Positive means the file reads\n")
    out.write("  more like the assistant sample than like the papers.\n")

    # The permutation null, run against each pole itself. This is the check that says whether the
    # measure above can see anything at all.
    out.write("\n  the permutation null, each pole against a shuffle of its own words\n")
    out.write("    %-12s %-16s %s\n" % ("pole", "bag of words", "word web"))
    webs = {}
    for name, words in (("claudese", claudese_all), ("human", human_all)):
        turned = shuffled(words, 0x5EED)
        bag_real, _ = profile(words)
        bag_null, _ = profile(turned)
        web_real, _ = web_profile(words)
        web_null, _ = web_profile(turned)
        webs[name] = web_real
        out.write("    %-12s %-16.4f %.4f\n"
                  % (name, distance(bag_real, bag_null), distance(web_real, web_null)))
    out.write("    a bag of words returns exactly zero, because a shuffle does not change one.\n")
    out.write("    every distance printed above this line was taken on that bag, so every one of\n")
    out.write("    them reads composition and none of them reads arrangement.\n")

    if ("claudese" in webs) and ("human" in webs):
        out.write("\n  the two poles as word webs sit %.4f apart\n"
                  % distance(webs["claudese"], webs["human"]))

    # The whole tree as one web. A single file holds a few hundred words and its web is nearly all
    # noise. No web distance is reported per file for that reason. The repository as one body is
    # 400,000 words and is the reading a web can actually be asked for.
    whole = []
    for path in prose_distance.repository_files(where, roots):
        if "fixtures" in path:
            continue
        whole.extend(words_of(prose_distance.prose_of(os.path.join(where or prose_distance.ROOT, path))))
    if whole and ("claudese" in webs):
        ours, count = web_profile(whole)
        null, _ = web_profile(shuffled(whole, 0x5EED))
        own = distance(ours, null)
        to_claudese = distance(ours, webs["claudese"])
        to_human = distance(ours, webs["human"])
        out.write("\n  the whole tree as one web, %d words\n" % len(whole))
        out.write("    against its own shuffle   %.4f\n" % own)
        out.write("    to the assistant pole     %.4f\n" % to_claudese)
        out.write("    to the human pole         %.4f\n" % to_human)
        out.write("    margin %+.4f toward %s\n"
                  % (to_human - to_claudese,
                     "the assistant" if to_claudese < to_human else "the humans"))
        nearer = [one for one in (to_claudese, to_human) if one < own]
        out.write("    a web distance is only worth reading against how far a shuffle already\n")
        out.write("    sits, and that is %.4f here.\n" % own)
        if not nearer:
            out.write("    both poles sit further than the shuffle, so neither is resolved. At\n")
            out.write("    these sizes a bigram web is carried by which words a corpus happens to\n")
            out.write("    hold, and the tree resembles its own scrambled self more than it\n")
            out.write("    resembles either reference. Nothing was read.\n")

    out.write("\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
