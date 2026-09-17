#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The positive control over every entry in the cache, where the control itself reads a list of names.
#
#   Usage:  python maint/analysis/survey/crystal_edge_sweep.py sweep --out FILE [--shard K/N] [--cache DIR]
#           python maint/analysis/survey/crystal_edge_sweep.py summarize FILE [FILE ...]
#
# WHAT IT MEASURES
#
# examples/crystallography/6_oracle/proof_positive_control.py asks sixty four mineral names of the
# archive, keeps at most three entries per name, and checks each axis's recovered period against the
# published cell edge by integer equality. Its measurement, `measure_entry`, reads one structure at
# a time. Its selection is the name list. This keeps the measurement and replaces the
# selection with the cache, so the same question is put to every crystal fetched.
#
# `measure_entry` is imported, never copied. A second copy of a reader is one edit away from
# disagreeing with the first about what a deposit says, and this subject has already found that
# fault once, recorded in examples/crystallography/README.md.
#
# WHAT THE DENOMINATOR IS
#
# `measure_entry` goes through `exact_points`, which refuses a cell that is not right angled, and an
# empty return here covers that refusal, a missing cell, and a readable cell whose axes returned no
# period. This tool does not tile a cell twice to tell those apart. The refusals are counted by
# maint/analysis/survey/crystal_gate_census.py, which reads the cell text without tiling, and the
# two reports are meant to be quoted together: census admits A, this reads R, and A minus R is the
# number of admitted cells that returned no axis.
#
# WHY IT SHARDS, AND WHY THAT CANNOT MOVE A NUMBER
#
# Each entry is measured alone, with no random draw and no state carried to the next. Splitting the
# sorted entry list by index modulo N and running the parts in separate processes therefore gives
# the same rows as one process, in a different order. The summary sums over shards and sorts
# nothing it reports.
#
# FAILING CLOSED
#
# A cache with no CIF refuses. A shard whose walked count is missing from its output file refuses in
# the summary, and so does a summary whose shards do not cover every index from 0 to N minus 1 exactly
# once: a missing shard reads as fewer structures, and fewer structures reads as a smaller sweep with
# nothing wrong in it.
#
# A cell too wide for the exact scale raises exact.WillNotFit, and the positive control deliberately
# lets that stop the run. Over a whole archive one such entry would stop every other entry with it,
# so the sweep records the entry by name as a refusal of its own and continues. It is reported in
# the summary beside the misses and makes the exit status non-zero.

import argparse
import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# The dirname guard stops a missing sentinel from climbing off the top of the drive.
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "examples", "crystallography", "6_oracle"))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

import proof_positive_control as control  # noqa: E402
from representation import exact  # noqa: E402

CACHE = os.path.join(ROOT, "build", "cod")

# Row kinds in an output file. One file is one shard, and the header line is what the summary checks.
HEADER = "#shard"
AXIS = "axis"
TOO_WIDE = "too_wide"


def parse_shard(text):
    """(k, n) from 'K/N', refusing anything that does not name one part of a whole."""
    try:
        part, whole = (int(piece) for piece in text.split("/"))
    except ValueError:
        return None
    if whole < 1 or part < 0 or part >= whole:
        return None
    return part, whole


def sweep(args, out):
    shard = parse_shard(args.shard)
    if shard is None:
        out.write("  REFUSED: --shard must be K/N with 0 <= K < N, not %r.\n\n" % args.shard)
        return 1
    part, whole = shard

    out.write("\n  cache    %s\n  shard    %d/%d\n  out      %s\n\n" % (args.cache, part, whole, args.out))
    if not os.path.isdir(args.cache):
        out.write("  REFUSED: no directory at that cache path. This is not a sweep of zero.\n\n")
        return 1
    names = sorted(name for name in os.listdir(args.cache) if name.endswith(".cif"))
    if not names:
        out.write("  REFUSED: no .cif under that cache. This is not a sweep of zero.\n\n")
        return 1

    mine = [name for index, name in enumerate(names) if index % whole == part]
    walked = 0
    read = 0
    with io.open(args.out, "w", encoding="utf-8", newline="\n") as rows:
        for name in mine:
            walked += 1
            with io.open(os.path.join(args.cache, name), encoding="utf-8", errors="replace") as handle:
                text = handle.read()
            try:
                measured = control.measure_entry(text)
            except exact.WillNotFit:
                rows.write("%s\t%s\n" % (TOO_WIDE, name[:-4]))
                continue
            if measured:
                read += 1
            for axis, published, recovered, score in measured:
                rows.write("%s\t%s\t%s\t%s\t%s\t%d\t%d\n"
                           % (AXIS, name[:-4], axis, control.angstroms(published),
                              control.angstroms(recovered), 1 if recovered == published else 0,
                              score))
            if walked % 500 == 0:
                out.write("  %d of %d walked, %d read\n" % (walked, len(mine), read))
                out.flush()
        # Written last. A shard killed partway has no header, and the summary refuses it.
        rows.write("%s\t%d\t%d\t%d\t%d\n" % (HEADER, part, whole, walked, len(names)))

    out.write("\n  shard %d/%d walked %d of %d entries, %d read\n\n" % (part, whole, walked, len(names), read))
    return 0


def summarize(args, out):
    out.write("\n  shard files\n")
    parts = {}
    wholes = set()
    totals = set()
    walked = 0
    entries_read = set()
    axes = 0
    same = 0
    misses = []
    too_wide = []
    for path in args.files:
        out.write("    %s\n" % path)
        if not os.path.isfile(path):
            out.write("  REFUSED: no file at that path.\n\n")
            return 1
        header = None
        with io.open(path, encoding="utf-8") as handle:
            for line in handle:
                fields = line.rstrip("\n").split("\t")
                if fields[0] == HEADER:
                    header = fields
                elif fields[0] == AXIS:
                    axes += 1
                    entries_read.add(fields[1])
                    if fields[5] == "1":
                        same += 1
                    else:
                        misses.append(fields[1:5])
                elif fields[0] == TOO_WIDE:
                    too_wide.append(fields[1])
        if header is None:
            out.write("  REFUSED: %s has no shard header. The shard did not finish, and counting\n"
                      "  its rows would report a smaller sweep with nothing marked missing.\n\n" % path)
            return 1
        part, whole, shard_walked, total = (int(value) for value in header[1:5])
        if part in parts:
            out.write("  REFUSED: shard %d/%d appears twice, in %s and %s.\n\n" % (part, whole, parts[part], path))
            return 1
        parts[part] = path
        wholes.add(whole)
        totals.add(total)
        walked += shard_walked

    if len(wholes) != 1 or len(totals) != 1:
        out.write("  REFUSED: the shard files disagree on N (%s) or on the cache size (%s). They\n"
                  "  were not cut from one run.\n\n" % (sorted(wholes), sorted(totals)))
        return 1
    whole = wholes.pop()
    total = totals.pop()
    absent = sorted(set(range(whole)) - set(parts))
    if absent:
        out.write("  REFUSED: shards %s of %d are missing.\n\n" % (absent, whole))
        return 1
    if walked != total:
        out.write("  REFUSED: the shards walked %d entries and the cache held %d.\n\n" % (walked, total))
        return 1

    out.write("\n  %d entries in the cache, every one walked\n" % total)
    out.write("  %d structures read, meaning at least one axis returned a period\n" % len(entries_read))
    out.write("  %d axes measured\n" % axes)
    if axes:
        out.write("  %d of %d equal the published edge, %.1f percent\n" % (same, axes, 100.0 * same / axes))
    out.write("  %d cells too wide for the exact scale, recorded and not measured\n" % len(too_wide))
    for name in too_wide[:20]:
        out.write("    too wide  %s\n" % name)
    out.write("  %d axes differ from the published edge\n" % len(misses))
    for entry, axis, published, recovered in misses[:40]:
        out.write("    MISS  %s  %s  published %s  recovered %s\n" % (entry, axis, published, recovered))
    if len(misses) > 40:
        out.write("    and %d more\n" % (len(misses) - 40))
    out.write("\n  Quote this beside crystal_gate_census.py on the same cache: its admitted count\n"
              "  minus the structures read above is the admitted cells that returned no axis.\n\n")
    return 2 if (misses or too_wide) else 0


def main():
    parser = argparse.ArgumentParser(add_help=True)
    commands = parser.add_subparsers(dest="command")
    run = commands.add_parser("sweep", help="measure every entry in one shard of the cache")
    run.add_argument("--out", required=True, help="tab separated rows for this shard")
    run.add_argument("--shard", default="0/1", help="K/N, the entries whose sorted index mod N is K")
    run.add_argument("--cache", default=CACHE, help="directory of .cif files")
    total = commands.add_parser("summarize", help="combine shard files into one report")
    total.add_argument("files", nargs="+", help="every shard file from one run")
    args = parser.parse_args()

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if args.command == "sweep":
        status = sweep(args, out)
    elif args.command == "summarize":
        status = summarize(args, out)
    else:
        parser.print_help()
        status = 1
    out.flush()
    return status


if __name__ == "__main__":
    sys.exit(main())
