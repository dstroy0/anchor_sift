#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Copy the whole Crystallography Open Database into build/, by its rsync mirror.
#
#   Usage:  python maint/data/fetch/fetch_cod_bulk.py --source <rsync url> [--mirror DIR] [--flat DIR]
#           python maint/data/fetch/fetch_cod_bulk.py --flatten-only [--mirror DIR] [--flat DIR]
#
#   The COD publishes its experimental CIF files as the rsync module `cif`:
#
#           --source rsync://www.crystallography.net/cif/
#
#   The source can also come from ANCHOR_SIFT_COD_RSYNC. There is no default. A fetch tool that
#   falls back to an address when nobody named one is the case the root rules forbid by name.
#
# WHY RSYNC AND NOT THE HTTP ROUTE
#
# maint/data/fetch/fetch_cod_doped.py fetches by search term over HTTP, one request per entry, and
# its header says that route stops being the polite one in the thousands. The archive is a public
# service run by people. One rsync over the whole tree costs them one connection and a file
# listing; hundreds of thousands of HTTP requests cost them hundreds of thousands of requests. A
# second rsync transfers only what changed, so re-running this is close to free for both ends.
#
# The module is `cif`. `pcod-cif` on the same server holds PREDICTED structures, and `hkl` holds
# structure factors. Neither is a deposited crystal, and neither is read here.
#
# WHY THERE ARE TWO DIRECTORIES
#
# The mirror keeps the archive's own layout, nested by identifier (cif/1/00/00/1000000.cif). A later
# rsync compares against it and sends only differences. Every reading in
# examples/crystallography lists a flat directory of NNNNNNN.cif files. Teaching each reading to
# walk a tree would change every stage's reader to serve one fetch, so the flatten step copies into
# the flat cache instead and the readers stay as they are. The cost is disk: the files exist twice.
#
# WHAT THIS NEVER DOES
#
# It deletes nothing. rsync runs without --delete. An entry the archive withdraws stays in the
# mirror. The flatten step copies into build/cod beside what the HTTP fetch put there, and leaves
# families.tsv, the search result files and every existing entry in place. Removing files is a
# decision for a person, and a fetch tool that makes it silently removes the evidence a later
# reading would need to notice the withdrawal.
#
# FAILING CLOSED
#
# A mirror holding no CIF after the sync is refused by name. The same applies to a flatten that finds
# two files with one basename in the mirror. COD identifiers are unique. A collision means the
# layout differs from the one this was written against, and copying either file over the other would
# destroy one of them.

import argparse
import filecmp
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. The dirname guard stops a
# missing sentinel from climbing off the top of the drive.
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)

MIRROR = os.path.join(ROOT, "build", "cod_mirror")
FLAT = os.path.join(ROOT, "build", "cod")
SOURCE_VARIABLE = "ANCHOR_SIFT_COD_RSYNC"


def cif_files(tree):
    """Every .cif under `tree`, as (basename, full path), in a stable order."""
    found = []
    for where, directories, files in os.walk(tree):
        directories.sort()
        for name in sorted(files):
            if name.endswith(".cif"):
                found.append((name, os.path.join(where, name)))
    return found


def sync(source, mirror, out):
    """One rsync of the archive into the mirror. Returns rsync's exit status.

    rsync is run from the mirror's parent with a relative destination. The Windows builds of rsync
    read a drive letter in a destination as a remote host name, and a relative path avoids the
    question entirely.
    """
    os.makedirs(mirror, exist_ok=True)
    parent, leaf = os.path.split(os.path.normpath(mirror))
    command = ["rsync", "-a", "--stats", source, leaf + "/"]
    out.write("  running  %s\n  from     %s\n\n" % (" ".join(command), parent))
    out.flush()
    return subprocess.call(command, cwd=parent)


def flatten(mirror, flat, out):
    """Copy each mirror CIF into the flat cache where it is absent or its bytes differ.

    Returns (copied, unchanged) or None after refusing a basename collision.

    The comparison is on content, and a size mismatch only lets it skip the read. A modification time
    cannot stand in for it. The flat cache already holds entries the HTTP fetch wrote, stamped with
    the day they were fetched, and a later revision in the archive of the same size would read as
    current against that stamp and never be copied.
    """
    entries = cif_files(mirror)
    seen = {}
    for name, path in entries:
        if name in seen:
            out.write("  REFUSED: two files named %s in the mirror:\n    %s\n    %s\n"
                      % (name, seen[name], path))
            out.write("  COD identifiers are unique, so the mirror layout is not the expected one.\n"
                      "  Copying one over the other would destroy a file.\n\n")
            return None
        seen[name] = path

    os.makedirs(flat, exist_ok=True)
    copied = 0
    unchanged = 0
    for name, path in entries:
        target = os.path.join(flat, name)
        if (os.path.isfile(target) and os.path.getsize(target) == os.path.getsize(path)
                and filecmp.cmp(target, path, shallow=False)):
            unchanged += 1
            continue
        shutil.copy2(path, target)
        copied += 1
    return copied, unchanged


def main():
    parser = argparse.ArgumentParser(add_help=True)
    parser.add_argument("--source", default=os.environ.get(SOURCE_VARIABLE),
                        help="rsync url of the archive's cif module, or set %s" % SOURCE_VARIABLE)
    parser.add_argument("--mirror", default=MIRROR, help="where the nested mirror is kept")
    parser.add_argument("--flat", default=FLAT, help="the flat cache the readings list")
    parser.add_argument("--flatten-only", action="store_true",
                        help="skip the sync and copy the mirror as it stands")
    args = parser.parse_args()

    out = sys.stdout
    out.write("\n  mirror   %s\n  flat     %s\n" % (args.mirror, args.flat))

    if not args.flatten_only:
        if not args.source:
            out.write("\n  REFUSED: no source named. Pass --source or set %s.\n" % SOURCE_VARIABLE)
            out.write("  The archive's module is rsync://www.crystallography.net/cif/ and it is\n")
            out.write("  not assumed.\n\n")
            return 1
        out.write("  source   %s\n\n" % args.source)
        status = sync(args.source, args.mirror, out)
        if status != 0:
            out.write("\n  rsync exited %d. The mirror is partial; running this again resumes it.\n\n"
                      % status)
            return status

    if not os.path.isdir(args.mirror):
        out.write("\n  REFUSED: no mirror directory at that path. This is not a mirror of zero.\n\n")
        return 1

    held = len(cif_files(args.mirror))
    out.write("\n  %d CIF files in the mirror\n" % held)
    if held == 0:
        out.write("  REFUSED: the mirror holds no CIF. This is not a corpus of zero.\n\n")
        return 1

    result = flatten(args.mirror, args.flat, out)
    if result is None:
        return 1
    copied, unchanged = result
    out.write("  %d copied into the flat cache, %d already current\n" % (copied, unchanged))
    out.write("  %d CIF files in the flat cache now\n\n"
              % sum(1 for name in os.listdir(args.flat) if name.endswith(".cif")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
