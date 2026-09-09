#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Put the languages in SPEECH.tsv in an order nobody chose, and keep the draw that did it.
#
#   python maint/corpus/speech_order.py            recompute the order and check it holds
#   python maint/corpus/speech_order.py --write    write the register in that order
#   python maint/corpus/speech_order.py --redraw   draw a new seed, which moves everybody
#
# WHY THE ORDER IS DRAWN AND NOT DECIDED
#
# Any order somebody picks is a ranking. Alphabetical ranks by the spelling an English keyboard
# gave the language. By oracle count ranks by how much has already been taken. By how easy the
# program is to reach ranks by who has a website. Each of those encodes a judgement made by whoever
# held the list.
#
# Noise encodes nothing. The seed is drawn from the operating system's entropy once, it is written
# into the register, and the order follows from it.
#
# THE DRAW PLACES A LANGUAGE, NOT A ROW
#
# The first version keyed every row on its own and scattered the three Lushootseed sources across
# positions 3, 6, 7 and 12. Nothing about that is unfair and it is unreadable: a language whose
# sources sit four places apart cannot be worked through in one sitting, and somebody approaching
# the Tulalip department wants the Puyallup program and the Metcalf collection in front of them at
# the same time.
#
# So the language is what the draw places, and its sources stay together underneath it. Within a
# language they run by date, oldest first, because the sources of one language are a sequence: the
# 1950s collection is what the recovery program was built out of, and reading them in that order is
# reading how the language got from there to here. A row with no date yet sorts last inside its
# language, and every run counts how many are waiting on one.
#
# THE SEED IS KEPT SO THE DRAW CAN BE CHECKED
#
# A shuffle with a thrown away seed is indistinguishable from a hand ordering that its author
# describes as a shuffle. Keeping the seed makes the whole thing checkable: recompute every key
# from the seed and the language, sort, and see the file. A run with no argument does exactly that
# and reports any row sitting where the draw did not put it.
#
# A KEY PER LANGUAGE, NOT ONE SHUFFLE OF A LIST
#
# Each language's key is a hash of the seed against its name, and the order is the sort of those
# keys. Shuffling a list instead would tie every position to the length of the list, so adding one
# language later would move all of them and the record of who was approached in what order would
# stop matching what was done. With a key per language, a language that exists keeps its key
# forever, a new source joins the language it belongs to, and a new language is placed among them
# by the same noise that placed the rest.
#
# --redraw MOVES EVERYBODY, AND IS A FLAG FOR THAT REASON
#
# It exists for the case where the register is still empty and no one has been written to. Once a
# nation has been approached in this order, redrawing throws away the record of why that one came
# first. It says so and asks for the word again.

import hashlib
import io
import os
import re
import secrets
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = HERE
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)

NAME = "SPEECH.tsv"
SEED_MARK = "# seed: "

# What the draw places. One key per distinct value here, and every row carrying that value sits
# under it.
GROUPED_BY = "language"

# Ordered inside a group. A year, or a span written 1950-1958, and the first year is what sorts.
DATED_BY = "date"

# A platform hosting many nations is a route to them and never a source of one language, so it is
# not a thing the draw can fairly place. Those rows sort after the draw and carry no key.
OUT_OF_DRAW = ("portal",)

YEAR = re.compile(r"(1[6-9][0-9]{2}|20[0-9]{2})")


def private_root():
    """The closed corpus, resolved the way private_sync.py resolves it."""
    named = os.environ.get("ANCHOR_SIFT_PRIVATE")
    if named:
        return os.path.abspath(named)
    for candidate in (os.path.join(ROOT, "deps", "salishan_corpus"),
                      os.path.join(os.path.dirname(ROOT), "private_repos", "salishan_corpus")):
        if os.path.isdir(candidate):
            return candidate
    return os.path.join(ROOT, "deps", "salishan_corpus")


def read_register(path):
    """The header comments, the column names, and the rows, kept apart for a write to rebuild."""
    notes = []
    header = None
    rows = []
    with io.open(path, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if line.startswith("#") or not line.strip():
                if header is None:
                    notes.append(line)
                continue
            parts = line.split("\t")
            if header is None:
                header = parts
                continue
            rows.append(dict(zip(header, parts)))
    return notes, (header or []), rows


def seed_in(notes):
    """The seed already drawn, or None where the register has never been ordered."""
    for line in notes:
        if line.startswith(SEED_MARK):
            found = line[len(SEED_MARK):].strip()
            if found:
                return found
    return None


def key_of(seed, language):
    """One language's place in the draw, as a hash of the seed against its name.

    Hex, so it sorts as text the same way it sorts as a number, and a reader with the seed and a
    hashing tool can check any one language without running this.
    """
    return hashlib.sha256(("%s\x1f%s" % (seed, language.strip()))
                          .encode("utf-8")).hexdigest()[:16]


def dated(row):
    """The year a row sorts on inside its language, and whether it has one.

    An empty date sorts after every real one. A source nobody has dated yet waits at the end of its
    language instead of silently landing at the front as year zero.
    """
    found = YEAR.search(row.get(DATED_BY) or "")
    return (0, int(found.group(1))) if found else (1, 0)


def in_draw(row):
    """Whether the draw places this row at all."""
    return (row.get("body_kind") or "").strip().lower() not in OUT_OF_DRAW


def ordered(seed, rows):
    """Every row with its language key, grouped by the draw and dated inside each group.

    A row out of the draw takes a key of all f, which sorts after every real one, and the key is
    written as empty so nobody reads it as a place the seed gave.
    """
    held = []
    for row in rows:
        if not in_draw(row):
            held.append(("f" * 16, (2, 0), "", row))
            continue
        language = (row.get(GROUPED_BY) or "").strip()
        # The tail is the row's own hash, so two undated sources of one language are separated by
        # the same noise that placed the language and never by their order in the file.
        tail = hashlib.sha256(
            ("%s\x1f%s\x1f%s" % (seed, row.get("body") or "",
                                 row.get("program") or "")).encode("utf-8")).hexdigest()[:8]
        held.append((key_of(seed, language), dated(row), tail, row))
    held.sort(key=lambda one: (one[0], one[1], one[2]))
    return held


def write_register(path, notes, header, drawn, seed, out):
    """The register in drawn order, with the seed recorded above it."""
    kept = []
    dropping = False
    for line in notes:
        if line.startswith("# THE ORDER BELOW"):
            dropping = True
        if dropping:
            if line.startswith(SEED_MARK):
                dropping = False
            continue
        kept.append(line)
    # A bare "#" is the separator this write puts back, so leaving the old one gathers a new blank
    # comment line on every run. Three had piled up before this was noticed.
    while kept and kept[-1].strip() in ("", "#"):
        kept.pop()

    header = list(header)
    for column in (DATED_BY, "order_key"):
        if column not in header:
            header.append(column)

    with io.open(path, "w", encoding="utf-8", newline="\n") as handle:
        for line in kept:
            handle.write("%s\n" % line)
        handle.write("#\n")
        handle.write("# THE ORDER BELOW WAS DRAWN, NOT CHOSEN\n")
        handle.write("#\n")
        handle.write("# order_key is sha256(seed + language), first 16 hex digits. The languages\n")
        handle.write("# are sorted by it and every source of one language sits under it, oldest\n")
        handle.write("# date first. Recompute any key from the seed and check it.\n")
        handle.write("# maint/corpus/speech_order.py in anchor_sift does all of them.\n")
        handle.write("#\n")
        handle.write("# date is the year that source's holdings begin. An empty one sorts last\n")
        handle.write("# inside its language and is a thing still to find out.\n")
        handle.write("#\n")
        handle.write("%s%s\n" % (SEED_MARK, seed))
        handle.write("\t".join(header))
        handle.write("\n")
        for key, _, _, row in drawn:
            row["order_key"] = key
            handle.write("\t".join((row.get(one) or "") for one in header))
            handle.write("\n")
    out.write("  %s\n" % path.replace("\\", "/"))
    out.write("    seed %s\n" % seed)
    out.write("    %d row(s) under %d language(s)\n"
              % (len(drawn), len({one[0] for one in drawn})))


def show(out, drawn):
    """The order as it reads, one block per language."""
    seen = None
    place = 0
    for key, when, _, row in drawn:
        language = (row.get(GROUPED_BY) or "").strip()
        if key != seen:
            seen = key
            place += 1
            out.write("\n    %2d  %-12s  %s\n" % (place, key[:12], language or "no language"))
        out.write("          %-9s %-30s %-14s %s\n"
                  % ((row.get(DATED_BY) or "no date")[:9],
                     (row.get("body") or "")[:30],
                     (row.get("body_kind") or "")[:14],
                     (row.get("program") or "")[:40]))


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")
    writing = "--write" in sys.argv
    redrawing = "--redraw" in sys.argv

    root = private_root()
    path = os.path.join(root, NAME)
    out.write("\n  %s\n" % path.replace("\\", "/"))
    if not os.path.isfile(path):
        out.write("  no register there.\n\n")
        out.flush()
        return 2

    notes, header, rows = read_register(path)
    seed = seed_in(notes)

    # A row carrying an order_key was placed by some earlier run. A file with keys and no seed is
    # therefore a file whose seed line got dropped. Drawing a fresh one there silently replaces a
    # draw that was meant to be kept forever. The first hand rewrite of this register did that.
    # The keys are still in the file and the old seed is in that run's output.
    if not seed and any((row.get("order_key") or "").strip() for row in rows):
        out.write("  rows carry an order_key and the file has no seed line.\n")
        out.write("  a draw was made here and its seed was dropped, so drawing again would\n")
        out.write("  replace it rather than reproduce it. Put the seed back:\n")
        out.write("      %s<the seed that run printed>\n" % SEED_MARK)
        out.write("  or --redraw --yes to accept a new draw and lose the old order.\n\n")
        if not redrawing:
            out.flush()
            return 1

    if redrawing or not seed:
        approached = [row for row in rows
                      if (row.get("permission") or "").strip().lower() not in ("", "not asked")]
        if approached and redrawing:
            out.write("\n  %d nation(s) have already been approached in the current order:\n"
                      % len(approached))
            for row in approached:
                out.write("    %s  %s\n" % (row.get("language", ""), row.get("permission", "")))
            out.write("\n  a redraw moves everybody and throws away the record of why those came\n")
            out.write("  first. Say so again with --redraw --yes if that is what you mean.\n\n")
            if "--yes" not in sys.argv:
                out.flush()
                return 1
        elif approached:
            out.write("  no seed, and %d row(s) have already been approached.\n" % len(approached))
            out.flush()
            return 1
        # 32 bytes out of the operating system's entropy. Not a word, not a date, and not anything
        # anybody could have picked to produce a particular order.
        seed = secrets.token_hex(32)
        out.write("  drew a new seed\n")

    drawn = ordered(seed, rows)
    undated = sum(1 for _, when, _, _ in drawn if when[0])

    if writing or redrawing:
        out.write("\n")
        write_register(path, notes, header, drawn, seed, out)
        show(out, drawn)
        if undated:
            out.write("\n  %d row(s) have no date and wait at the end of their language.\n"
                      % undated)
        out.write("\n  reconcile and sign the corpus after:\n")
        out.write("      python maint/corpus/corpus_manifest.py --write --root %s\n"
                  % root.replace("\\", "/"))
        out.write("      gpg --armor --detach-sign --yes MANIFEST.tsv\n\n")
        out.flush()
        return 0

    # No argument, so this checks the file against the draw instead of writing it.
    adrift = []
    for at, (key, _, _, row) in enumerate(drawn):
        if rows[at] is not row:
            adrift.append((at + 1, row.get(GROUPED_BY, ""), key))
    # A row out of the draw carries the all f key by design, so checking it against key_of would
    # report the portal as drifted on every run.
    stale = [row for row in rows if in_draw(row)
             and (row.get("order_key") or "") != key_of(seed, (row.get(GROUPED_BY) or ""))]

    out.write("    seed %s\n" % seed)
    out.write("    %d row(s) under %d language(s), %d with no date\n"
              % (len(rows), len({one[0] for one in drawn}), undated))
    if adrift:
        out.write("\n  ROWS NOT WHERE THE DRAW PUT THEM (%d)\n" % len(adrift))
        for at, language, key in adrift[:12]:
            out.write("    position %d should be %s (%s)\n" % (at, language, key[:12]))
    if stale:
        out.write("\n  order_key DOES NOT MATCH THE SEED (%d)\n" % len(stale))
        for row in stale[:12]:
            out.write("    %-30s recorded %s, computed %s\n"
                      % ((row.get(GROUPED_BY) or "")[:30],
                         (row.get("order_key") or "none")[:12],
                         key_of(seed, row.get(GROUPED_BY) or "")[:12]))
    if adrift or stale:
        out.write("\n  run --write\n\n")
        out.flush()
        return 1

    out.write("  every row sits where the seed put it.\n\n")
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
