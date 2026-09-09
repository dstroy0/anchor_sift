#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Retrieve the prior art this work cites, from the archives that publish it openly.
#
#   python maint/data/fetch/fetch_prior_art.py            fetch what is missing
#   python maint/data/fetch/fetch_prior_art.py --list     what is wanted and what is held
#
# WHAT THIS IS ALLOWED TO REACH
#
# Open archives run by the publishers themselves, and nothing else. Math-Net.Ru is the Russian
# Academy of Sciences' own archive and carries Doklady Akademii Nauk, which is where Kolmogorov 1958
# and Sinai 1959 appeared. That is the publisher offering its own back catalogue, not a mirror and
# not a shadow library.
#
# A paywalled article is recorded and left. Three attempts against Baeza-Yates and Regnier returned
# 403, the last against the publisher's own tokened link, and retrying a paywall does not open it.
# The entry for it in the ledger says unread, which is the honest state and is worth more than a
# citation nobody checked.
#
# THE COURTESIES ARE THE ONLY PATH TO THE NETWORK
#
# One identifying User-Agent with a contact address, one request at a time, a pause between them
# longer than any published limit, and a cache so a second run asks for nothing. A tool that has to
# remember to be polite will forget.
#
# WHAT IT CANNOT GET IS THE OUTPUT THAT MATTERS
#
# The unmet list is the point of running this. A row that fails prints what it was, why it failed,
# and the best URL a person could try by hand, so the failure is a worklist item and not a silence.

import io
import os
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)

INTO = os.path.join(ROOT, "build", "prior_art")

# Named, with a contact address, so an archive operator can see who is asking and reach a person.
AGENT = {"User-Agent": "anchor-sift-research/1.0 "
                       "(https://github.com/dstroy0/anchor_sift; dquigg123@gmail.com)"}

# Seconds between requests that reach a host. Longer than any limit these archives publish.
PAUSE = 3.0

# Attempts per URL. A refusal is a refusal; this is for a dropped connection.
TRIES = 2

# What is wanted, why, and what a downloaded file has to contain before it counts as that paper.
#
# NO IDENTIFIER IS GUESSED HERE, AND THE REASON IS A FAILURE THIS FILE CAUSED.
#
# The first version of this carried two Math-Net.Ru paper identifiers that were invented. Both
# resolved to real PDFs of entirely different articles: Doklady 119(2) page 311 on the
# micro-inhomogeneity of alloys under heating, and Doklady 122(1) page 103 on ozone in hydrocarbon
# oxidation. Both downloads reported success and both files were the wrong paper. Rendering the
# first page and reading it is what caught it.
#
# An identifier that is not known is left empty and the entry is reported as unmet, naming the
# archive page a person should open. A wrong file that arrives quietly is worse than no file.
WANTED = (
    {
        "name": "kolmogorov_1958_new_metric_invariant.pdf",
        "cite": "Kolmogorov, A new metric invariant of transitive dynamical systems and "
                "automorphisms of Lebesgue spaces, Doklady Akademii Nauk SSSR 119(5):861-864, 1958",
        "why": "Kolmogorov-Sinai entropy is defined as a supremum over partitions, which is where "
               "the partition dependence this document observes was already answered",
        # dan22922, and the identifier came from the archive's own article page rather than from a
        # pattern. The first attempt used dan22851, which was invented and returned a metallurgy
        # paper. Confirmed at https://www.mathnet.ru/eng/dan22922: Kolmogorov, Dokl. Akad. Nauk
        # SSSR 119:5 (1958) 861-864, offering "Full-text PDF (581 kB)".
        "urls": (
            "https://www.mathnet.ru/php/getFT.phtml?jrnid=dan&paperid=22922"
            "&what=fullt&option_lang=eng",
        ),
        "by_hand": "https://www.mathnet.ru/eng/dan22922",
        # Words that have to appear in the retrieved file. Cyrillic, because the Doklady scan is the
        # Russian original: Kolmogorov's surname and the word for entropy.
        "must_hold": ("Колмогоров", "энтроп"),
    },
    {
        "name": "sinai_1959_concept_of_entropy.pdf",
        "cite": "Sinai, On the concept of entropy for a dynamic system, "
                "Doklady Akademii Nauk SSSR 124(4):768-771, 1959",
        "why": "The second half of the same result, and the paper that carries the definition into "
               "a form the field uses",
        "urls": (),
        "by_hand": "https://www.mathnet.ru/eng/dan  (search the archive for the 1959 volume 124 "
                   "issue 4 contents; the identifier is not known here and must not be guessed)",
        "must_hold": ("Синай", "энтроп"),
    },
)


def confirms(path, must_hold, out):
    """Whether the retrieved file is the paper that was asked for.

    A PDF that downloads is not the paper that was wanted, and treating it as one is the failure
    this whole file is written around. Two invented identifiers both returned real PDFs of unrelated
    articles and both reported success.

    The check reads the file's own text for words the paper must contain. Where the file is a page
    scan and yields no text, it cannot be confirmed, and cannot-confirm is reported as a refusal
    rather than a pass: a scan has to be rendered and read by a person, and that is a worklist item.
    """
    try:
        from pypdf import PdfReader
    except ImportError:
        out.write("      cannot confirm: no pypdf installed. Refusing to keep an unchecked file.\n")
        return False

    try:
        text = "\n".join((page.extract_text() or "") for page in PdfReader(path).pages)
    except Exception as trouble:
        out.write("      cannot confirm: %s\n" % str(trouble)[:60])
        return False

    if len(text.strip()) < 400:
        out.write("      cannot confirm: the file is a page scan and yields no text.\n")
        out.write("      Render it and read the first page before citing anything from it.\n")
        return False

    missing = [one for one in must_hold if one.lower() not in text.lower()]
    if missing:
        out.write("      WRONG PAPER: the file does not contain %s\n" % " ".join(missing))
        return False
    return True


def fetch(url, out):
    """One URL, or None with the reason printed. Never retries a refusal."""
    for attempt in range(TRIES):
        try:
            request = urllib.request.Request(url, headers=AGENT)
            with urllib.request.urlopen(request, timeout=120) as answer:
                held = answer.read()
            if held[:4] != b"%PDF":
                out.write("      not a PDF: %s\n" % url[:88])
                return None
            return held
        except urllib.error.HTTPError as refused:
            # A status is a decision by the host and is reported as one. 403 and 404 are answers.
            out.write("      HTTP %d: %s\n" % (refused.code, url[:80]))
            return None
        except Exception as trouble:
            if attempt == (TRIES - 1):
                out.write("      %s: %s\n" % (type(trouble).__name__, str(trouble)[:60]))
                return None
            time.sleep(PAUSE * (attempt + 2))
    return None


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    os.makedirs(INTO, exist_ok=True)

    listing = "--list" in sys.argv
    got = []
    unmet = []

    for one in WANTED:
        path = os.path.join(INTO, one["name"])
        if os.path.isfile(path):
            out.write("  held      %s\n" % one["name"])
            got.append(one)
            continue
        if listing:
            out.write("  wanted    %s\n" % one["name"])
            continue

        if not one["urls"]:
            out.write("  no source  %s\n" % one["name"])
            out.write("      no identifier is known and none will be guessed.\n")
            unmet.append(one)
            continue

        out.write("  fetching  %s\n" % one["name"])
        held = None
        for url in one["urls"]:
            held = fetch(url, out)
            time.sleep(PAUSE)
            if held is not None:
                break
        if held is None:
            unmet.append(one)
            continue

        # Written to a scratch name first. A file that cannot be confirmed never takes the name the
        # rest of the tree would cite it by.
        pending = path + ".pending"
        with open(pending, "wb") as handle:
            handle.write(held)
        out.write("      %d bytes, confirming\n" % len(held))

        if not confirms(pending, one["must_hold"], out):
            os.remove(pending)
            unmet.append(one)
            continue
        os.replace(pending, path)
        out.write("      confirmed\n")
        got.append(one)

    out.write("\n  %d held, %d not retrieved\n" % (len(got), len(unmet)))

    # The unmet list is the deliverable when a fetch fails. Every row carries what it is, why it was
    # wanted, and where a person should go, so it is a worklist and not a complaint.
    if unmet:
        out.write("\n  COULD NOT RETRIEVE, to be fetched by hand\n")
        for one in unmet:
            out.write("\n    %s\n" % one["cite"])
            out.write("      wanted for: %s\n" % one["why"])
            out.write("      try:        %s\n" % one["by_hand"])
    out.write("\n")
    out.flush()
    return 1 if unmet else 0


if __name__ == "__main__":
    raise SystemExit(main())
