#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Ask whether the label on a fetched corpus carries any information.
#
#   python maint/prose/oracle_agreement.py           the verdict and the numbers behind it
#   python maint/prose/oracle_agreement.py --quiet   the verdict alone
#
# WHAT THE QUESTION IS
#
# fetch_claude_prose.py takes three community uploads that all say Claude Opus 5. Nobody outside
# those uploads can verify that from the outside: a label on a public dataset is a claim by whoever
# uploaded it, and a corpus of some other model's output under that name would look the same from
# here.
#
# Three independent uploads make the claim checkable without trusting any of them. If corpora that
# all claim one model resemble each other more than any of them resembles a corpus known to be
# something else, the label is carrying information. If one sits as far from its own siblings as it
# does from the control, it is either mislabeled or a different register, and a pole built out of
# all three is a pole built out of two things.
#
# This is the oracle pattern the rest of this work uses, over labels instead of over measurements.
# The agreement is the evidence, and no single corpus is trusted to speak for itself.
#
# WHAT IT DOES NOT ANSWER
#
# It cannot say the label is right. Three uploads of the same mislabeled corpus agree perfectly,
# and so do three corpora of three different models that happen to share a register. What it
# catches is the ordinary failure: one upload among several that is not what the others are.
#
# The control matters for the same reason. Against a control too close to the subject the
# separation vanishes and nothing is shown. The control here is the human pole, the furthest
# thing in this tree from assistant prose and the pole the distance instrument already
# measures against.
#
# THE CORPORA ARE DATA AND ARE NEVER READ
#
# Third party text off a public host. It is counted and measured, and no line of it is printed.

import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)

sys.path.insert(0, HERE)

from claudese_distance import (distance, halves, profile,  # noqa: E402
                               restricted, top_words, words_of)

APART = os.path.join(ROOT, "build", "corpora", "claude_prose_by_source")
HUMAN = os.path.join(ROOT, "build", "papers")

# A corpus smaller than this cannot carry a distribution and its distances are sampling noise.
LEAST = 2000


def read(path):
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        return handle.read()


def human_text(limit=400000):
    """The human pole, as much of it as is needed to outweigh any one upload."""
    if not os.path.isdir(HUMAN):
        return ""
    held = []
    counted = 0
    for name in sorted(os.listdir(HUMAN)):
        if not name.endswith(".txt"):
            continue
        held.append(read(os.path.join(HUMAN, name)))
        counted += len(held[-1])
        if counted >= limit:
            break
    return "\n".join(held)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    quiet = "--quiet" in sys.argv

    out.write("\n  %s\n" % APART.replace("\\", "/"))
    if not os.path.isdir(APART):
        out.write("  no per source corpora. Run maint/data/fetch/fetch_claude_prose.py first.\n\n")
        out.flush()
        return 2

    names = sorted(one for one in os.listdir(APART) if one.endswith(".txt"))
    corpora = {}
    for name in names:
        words = words_of(read(os.path.join(APART, name)))
        if len(words) < LEAST:
            out.write("    %-46s %d words, too few to place\n" % (name[:46], len(words)))
            continue
        corpora[name[:-4]] = words

    if len(corpora) < 2:
        out.write("  fewer than two usable corpora. Nothing can be compared.\n\n")
        out.flush()
        return 2

    control = words_of(human_text())
    if len(control) < LEAST:
        out.write("  no human pole under build/papers. The control is what makes a distance\n")
        out.write("  mean anything, so this stops instead of reporting a bare number.\n\n")
        out.flush()
        return 2

    everything = {one: profile(words)[0] for one, words in corpora.items()}
    everything["control"] = profile(control)[0]
    axis = top_words(list(everything.values()))
    on_axis = {one: restricted(value, axis) for one, value in everything.items()}

    out.write("\n  %d corpus(es) claiming one label, against %d control words\n"
              % (len(corpora), len(control)))
    for one, words in sorted(corpora.items()):
        out.write("    %-52s %7d words\n" % (one[:52], len(words)))

    # Each corpus against its own halves. That is the floor a distance has to clear here.
    out.write("\n  own halves, the resolution floor of each\n")
    floors = {}
    for one, words in sorted(corpora.items()):
        first, second = halves(" ".join(words))
        if first is None:
            floors[one] = 0.0
            continue
        left = restricted(profile(words_of(first))[0], axis)
        right = restricted(profile(words_of(second))[0], axis)
        floors[one] = distance(left, right)
        out.write("    %-52s %.4f\n" % (one[:52], floors[one]))

    keys = sorted(corpora)
    within = []
    out.write("\n  to each other, and to the control\n")
    for at, one in enumerate(keys):
        for other in keys[at + 1:]:
            value = distance(on_axis[one], on_axis[other])
            within.append((value, one, other))
            out.write("    %-30s %-30s %.4f\n" % (one[:30], other[:30], value))
    across = []
    for one in keys:
        value = distance(on_axis[one], on_axis["control"])
        across.append((value, one))
        out.write("    %-30s %-30s %.4f\n" % (one[:30], "control", value))

    worst_within = max(within)[0]
    best_across = min(across)[0]
    floor = max(floors.values()) if floors else 0.0

    out.write("\n  furthest two that share the label   %.4f\n" % worst_within)
    out.write("  nearest one to the control         %.4f\n" % best_across)
    out.write("  largest own halves floor           %.4f\n" % floor)

    if worst_within <= floor:
        out.write("\n  every pair sharing the label sits inside its own sampling floor.\n")
        out.write("  Nothing is resolved at this size. Fetch more before trusting the label.\n\n")
        out.flush()
        return 2

    if worst_within < best_across:
        out.write("\n  AGREES. Corpora sharing the label are closer to each other than any is to\n")
        out.write("  the control, so the label carries information about the text.\n\n")
        out.flush()
        return 0

    out.write("\n  DISAGREES. At least one corpus sits further from its own siblings than it does\n")
    out.write("  from the control, so the label does not separate this text from other writing.\n")
    for value, one, other in sorted(within, reverse=True)[:3]:
        out.write("    %.4f  %s  and  %s\n" % (value, one[:34], other[:34]))
    out.write("  A pole built from all of them would be built out of more than one thing.\n\n")
    out.flush()
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
