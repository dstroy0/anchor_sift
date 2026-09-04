#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Test whether writing a procedure leaves a mark of its own, for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/register_bands.py
#
# Four kinds of writing are held here and they differ in one thing that can be stated plainly: how much of
# a procedure they are, and how formally it is written.
#
#   source code            a procedure written to be carried out exactly, by a machine that cannot ask
#   instruction for rulers a procedure at the scale of a campaign, written for a reader long gone
#   cookery                a procedure at the scale of a kitchen, with its measurements now unreadable
#   narrative              not a procedure
#
# If being a procedure leaves a mark that does not depend on being formal, the two informal bands sit
# between the code and the narrative. If the only thing that separates writing is how formal it is, they
# sit with the narrative they are written in, since both are ordinary prose of their period.
#
# The comparison is kept inside one language wherever it can be. The French cookery is reported apart for
# that reason and not mixed in, since a difference between it and the English books would be a difference
# of language before it was anything else.
#
# What this cannot escape is who wrote any of it. A cookbook of 1390 was written by a king's cook, a
# manual on campaigns by a general, and advice for princes for a prince. Everything measured here is the
# writing of people who were taught to write, which is a small and unusual part of anyone's society, and
# no reading of these texts reaches the rest of it.

import io
import os
import statistics
import sys

import numpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from web_alphabet import web

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPORA = os.path.join(ROOT, "build", "corpora")

CAP = 300000
LEAST = 80000
RANKS = 48

BANDS = (
    ("code", "csource_", ".sym"),
    ("rulers", "rule_", ".txt"),
    ("cookery", "recipe_", ".txt"),
    ("narrative", "english_", ".txt"),
    ("cookery, french", "frecipe_", ".txt"),
)


def load(prefix, suffix):
    out = []
    for name in sorted(os.listdir(CORPORA)):
        if not (name.startswith(prefix) and name.endswith(suffix)):
            continue
        path = os.path.join(CORPORA, name)
        if suffix == ".sym":
            with open(path, "rb") as handle:
                text = "".join(chr(value) for value in handle.read(CAP))
        else:
            with open(path, encoding="utf-8", errors="replace") as handle:
                text = handle.read(CAP)
        text = text.replace("\r\n", " ").replace("\r", " ").replace("\n", " ")
        if len(text) >= LEAST:
            out.append((name[:-4], text))
    return out


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    held = {}
    for band, prefix, suffix in BANDS:
        rows = []
        for label, text in load(prefix, suffix):
            values = web(text, RANKS)
            if values is not None:
                rows.append((label, values))
        if rows:
            held[band] = rows

    out.write("  %-18s %s\n" % ("band", "texts"))
    for band, rows in held.items():
        out.write("  %-18s %d\n" % (band, len(rows)))

    inside = [band for band in ("code", "rulers", "cookery", "narrative") if band in held]
    if len(inside) < 3:
        out.write("\n  too few bands to compare\n")
        out.flush()
        return 0

    middles = {band: numpy.mean(numpy.stack([values for _, values in held[band]]), axis=0)
               for band in held}

    out.write("\n  how far each band sits from the others\n")
    out.write("  %-18s %s\n" % ("", "  ".join("%-16s" % band for band in inside)))
    for band in inside:
        row = []
        for other in inside:
            row.append("%.4f" % float(numpy.linalg.norm(middles[band] - middles[other])))
        out.write("  %-18s %s\n" % (band, "  ".join("%-16s" % value for value in row)))

    # Whether a band holds together at all, which decides whether the distances above mean anything
    out.write("\n  %-18s %-14s %s\n" % ("band", "spread inside", "nearest other band"))
    for band in inside:
        rows = held[band]
        if len(rows) < 2:
            continue
        spread = statistics.fmean(
            float(numpy.linalg.norm(one[1] - two[1]))
            for index, one in enumerate(rows) for two in rows[index + 1:])
        nearest = min((float(numpy.linalg.norm(middles[band] - middles[other])), other)
                      for other in inside if other != band)
        out.write("  %-18s %-14.4f %s at %.4f\n" % (band, spread, nearest[1], nearest[0]))

    if ("code" in middles) and ("narrative" in middles):
        span = float(numpy.linalg.norm(middles["code"] - middles["narrative"]))
        out.write("\n  where each band falls between code and narrative, as a share of the way\n")
        for band in held:
            if band in ("code", "narrative"):
                continue
            to_code = float(numpy.linalg.norm(middles[band] - middles["code"]))
            to_story = float(numpy.linalg.norm(middles[band] - middles["narrative"]))
            out.write("  %-18s %.2f of the way from code to narrative, span %.4f\n"
                      % (band, to_code / (to_code + to_story), span))

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
