#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Admit sifted candidates into a pure corpus, one batch at a time, on the corpus's own curve.
#
#   Usage:  python tools/dev_env/corpus_admit.py
#
# A candidate does not have to look like a member. The corpus at this n has not seen its own
# alphabet: support is still climbing on every one of these languages, so resembling what is
# already there is the wrong test and would keep the corpus small forever.
#
# What can be asked is whether the corpus stays on its curve. A pure corpus growing on more of the
# same language adds support slowly and holds its split-half distance roughly level. Tipping in the
# whole sifted set does neither: Comox goes from 407 cells and D_self 0.196 to 2586 cells and 0.457,
# which is a second distribution arriving, not more of the first.
#
# So candidates are sorted by distance to the corpus and admitted in batches while D_self stays
# inside the band the corpus was already in. Admission stops at the first batch that leaves it.
# What is admitted is written out. What is not is kept, with the batch number that rejected it, so
# the boundary is visible and not left implied.

import collections
import glob
import io
import os
import sys

# Every Salishan category on the import path, so this can use a sibling from another one.
for _category in os.scandir(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))):
    if _category.is_dir():
        sys.path.insert(0, _category.path)

from anchor_sift import distance, self_distance, squash, support
from corpus_growth import candidates_by_language, pure_by_language

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
SIFTED = os.path.join(ROOT, "build", "corpora", "sifted")

# How many candidates to test at once. One line moves a distribution too little to measure.
BATCH = 40

# How far above the corpus's own D_self a batch may push it before it is refused.
SLACK = 1.25


def admit(pure, found):
    """Candidates admitted in batches while the corpus stays on its curve."""
    profile, _ = squash(pure)
    floor = self_distance(pure)
    ranked = sorted(found, key=lambda one: distance(squash([one])[0], profile))

    held = list(pure)
    taken = []
    refused = []
    for at in range(0, len(ranked), BATCH):
        batch = ranked[at:at + BATCH]
        trial = held + batch
        if self_distance(trial) <= (SLACK * floor):
            held = trial
            taken.extend(batch)
        else:
            refused.extend(ranked[at:])
            break
    return taken, refused, floor, self_distance(held)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    pure = pure_by_language()
    found = candidates_by_language()

    out.write("  %-16s %-8s %-11s %-9s %-9s %-8s %s\n"
              % ("language", "pure", "candidates", "admitted", "D_self", "after", "support"))
    for name in sorted(pure):
        if not found.get(name):
            continue
        taken, refused, floor, after = admit(pure[name], found[name])
        profile, _ = squash(pure[name] + taken)
        out.write("  %-16s %-8d %-11d %-9d %-9.4f %-8.4f %d\n"
                  % (name[:16], len(pure[name]), len(found[name]), len(taken),
                     floor, after, support(profile)))

        target = os.path.join(SIFTED, "%s.admitted.pure.txt" % name.replace(" ", ""))
        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write("# %s admitted into the pure corpus from the sifted candidates.\n" % name)
            handle.write("# Admitted in batches of %d while the corpus split-half distance stayed\n"
                         % BATCH)
            handle.write("# within %.2f of what it was before any were added: %.4f, ending %.4f.\n"
                         % (SLACK, floor, after))
            handle.write("# %d of %d candidates admitted. The rest are in the .refused file, and\n"
                         % (len(taken), len(found[name])))
            handle.write("# refused means the corpus left its own curve, not that the line is wrong.\n")
            for one in taken:
                handle.write("%s\n" % one)

        target = os.path.join(SIFTED, "%s.refused.txt" % name.replace(" ", ""))
        with open(target, "w", encoding="utf-8", newline="") as handle:
            handle.write("# %s candidates the corpus curve refused.\n" % name)
            handle.write("# Sorted by distance to the corpus, nearest first, so the boundary is\n")
            handle.write("# at the top of this file and the least like anything is at the bottom.\n")
            for one in refused:
                handle.write("%s\n" % one)

    out.write("\n  languages with candidates and no pure corpus to grow, left as candidates\n")
    for name in sorted(found):
        if name not in pure:
            out.write("    %-18s %d\n" % (name, len(found[name])))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
