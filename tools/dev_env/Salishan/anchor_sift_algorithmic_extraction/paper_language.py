#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Read which language a paper is about out of the paper's own front matter.
#
#   Usage:  python tools/dev_env/paper_language.py
#
# A sifted file carries no language name because taking one from a filename would be inventing it.
# The paper does not have that problem. It names its language in its title and its abstract, often
# several times and under several names.
#
# The name is read off the paper, never assigned. Each language below is listed with the names the
# literature uses for it, including the ones communities use for themselves and the older names
# outsiders gave them, because a 1974 paper and a 2024 paper on the same language rarely agree. A
# paper is attributed only where its front matter names one language and no other, which leaves the
# comparative papers unattributed, correctly.

import collections
import glob
import io
import os
import re
import sys

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
PAPERS = os.path.join(ROOT, "build", "papers")

# How much of a paper counts as its front matter. Title, authors and abstract sit well inside this,
# and a comparative paper's references do not, which keeps a citation from naming the subject.
FRONT = 60

# Each language with every name papers use for it. First entry is the name used in output.
NAMES = (
    ("Lushootseed", ("lushootseed", "puget salish", "puget sound salish", "skagit",
                     "snohomish", "dxʷləšucid", "twulshootseed")),
    ("Nsyilxcən", ("nsyilxcən", "nsyilxcen", "nsilxcin", "okanagan", "colville",
                   "nqilxwcen", "nqílxwcən", "colville-okanagan")),
    ("St'át'imcets", ("st'át'imcets", "statimcets", "st’át’imcets", "lillooet", "stl'atl'imx")),
    ("nɬeʔkepmxcín", ("nɬeʔkepmxcín", "nlekepmxcin", "nłeʔkepmxcín", "thompson river salish",
                      "thompson salish", "nlaka'pamux", "nlakapamux")),
    ("Nuxalk", ("nuxalk", "bella coola")),
    ("Halkomelem", ("halkomelem", "halq'eméylem", "halqemeylem", "hul'q'umi'num",
                    "hulquminum", "musqueam", "cowichan", "chilliwack")),
    ("Squamish", ("squamish", "skwxwú7mesh", "skwxwu7mesh")),
    ("Sechelt", ("sechelt", "shashishalhem", "she shashishalhem")),
    ("Comox", ("mainland comox", "ayajuthem", "ʔayʔaǰuθəm", "sliammon", "island comox",
               "comox")),
    ("Twana", ("twana", "skokomish")),
    ("Straits", ("straits salish", "northern straits", "saanich", "lummi", "songish",
                 "samish", "sooke")),
    ("Klallam", ("klallam", "clallam", "nəxʷsƛ̕ayʔəmúcən")),
    ("Secwepemctsín", ("secwepemctsín", "secwepemctsin", "shuswap")),
    ("Coeur d'Alene", ("coeur d'alene", "coeur d’alene", "snchitsu'umshtsn")),
    ("Spokane", ("spokane", "npoqiniscn")),
    ("Kalispel", ("kalispel", "pend d'oreille", "pend d’oreille")),
    ("Montana Salish", ("montana salish", "flathead", "seliš", "salish-pend")),
    ("Nxaʔamxcín", ("nxaʔamxcín", "nxaamxcin", "columbian salish", "moses-columbia")),
    ("Tillamook", ("tillamook", "siletz")),
    ("Quinault", ("quinault",)),
    ("Cowlitz", ("cowlitz",)),
    ("Upper Chehalis", ("upper chehalis", "chehalis")),
    ("Nooksack", ("nooksack",)),
    ("Tsamosan", ("tsamosan",)),
)


def named_in(path, front=FRONT):
    """Which languages a paper's front matter names, most mentioned first."""
    held = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            held.append(line)
            if len(held) >= front:
                break
    text = " ".join(" ".join(one.split()) for one in held).casefold()

    counted = collections.Counter()
    for name, aliases in NAMES:
        for one in aliases:
            counted[name] += text.count(one.casefold())
    return [(name, times) for name, times in counted.most_common() if times]


def attribution(found):
    """The one language a paper is about, where its front matter names one and no other."""
    if not found:
        return None
    if len(found) == 1:
        return found[0][0]
    # Named at least twice as often as anything else, which is what separates a paper about a
    # language from a paper that mentions it once while comparing three others.
    if found[0][1] >= (2 * found[1][1]):
        return found[0][0]
    return None


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    counted = collections.Counter()
    unattributed = 0
    rows = []
    for path in sorted(glob.glob(os.path.join(PAPERS, "*.txt"))):
        found = named_in(path)
        one = attribution(found)
        if one:
            counted[one] += 1
        else:
            unattributed += 1
        rows.append((os.path.basename(path)[:-4], one, found[:3]))

    out.write("  %d papers, %d attributed to one language, %d not\n"
              % (len(rows), len(rows) - unattributed, unattributed))
    out.write("\n  %-22s %s\n" % ("language", "papers"))
    for name, times in counted.most_common():
        out.write("  %-22s %d\n" % (name, times))

    out.write("\n  a sample of what was not attributed, with what its front matter names\n")
    shown = 0
    for stem, one, found in rows:
        if one or shown >= 8:
            continue
        shown += 1
        out.write("    %-40s %s\n"
                  % (stem[:40], ", ".join("%s %d" % (a, b) for a, b in found) or "nothing"))
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
