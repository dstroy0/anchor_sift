#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch the Cell Tracking Challenge datasets for theory/cell_tracking.
#
#   Usage:  python maint/data/fetch/fetch_ctc.py                 list the manifest, fetch nothing
#           python maint/data/fetch/fetch_ctc.py --fetch NAME     one dataset, training arm
#           python maint/data/fetch/fetch_ctc.py --fetch NAME --test   the test arm as well
#           python maint/data/fetch/fetch_ctc.py --tier small     every dataset under 200 MB
#
# NOTHING IS FETCHED BY DEFAULT AND THAT IS DELIBERATE. The full table is about 3.4 GB of 2D
# training data and about 360 GB of 3D, and one row of it, Fluo-N3DL-TRIF, is 320 GB training
# against 467 GB test on its own. A fetcher that pulls its whole manifest on a bare invocation is a
# fetcher that fills a disk before anyone reads its output. Run it bare first and read the total.
#
# WHERE THIS WRITES. repos/external/datasets at tree level, outside this repository, flat names and
# no nesting. That directory is not a git repository at all. Nothing here can be committed by
# accident. The rule this repo's .gitignore already states is the same one: what a tool can fetch is
# not carried here. What the repository keeps is this manifest.
#
# WHY THESE DATASETS AND NOT A LEADERBOARD. The permutation null measure carries most of the
# findings in this work and has no positive control from outside it, which theory/workbook calls the
# largest single gap in the work. The shift agreement detector has three, all from published crystal
# cell edges. These datasets ship published ground truth tracking annotations, which is what a
# positive control is: an answer that existed before the measurement and was not supplied by it.
#
# TWO ROWS ARE NOT LIKE THE OTHERS AND THEY ARE THE ONES TO START ON. The marker the challenge
# writes as a cross, here `perfect`, means the segmentation masks are exact because the data is
# computer generated. On those rows a tracking error is a linking error and cannot be a segmentation
# error, which separates the two halves of the problem. Every other row carries `silver`, meaning
# the reference segmentation is itself an annotation and a reading against it is bounded by how good
# that annotation is. Start where the segmentation cannot be blamed.

import argparse
import io
import os
import shutil
import sys
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)

# repos/external/datasets, which is three levels above this repository: anchor_sift sits in
# public/, public/ in owned/, owned/ in repos/, and external/ is owned/'s sibling. Douglas created
# it on 2026-09-15 and FIRST_OBJECTIVES item 19 calls it "external datasets/".
#
# Counted wrong once, by two levels instead of three, which put a dataset in
# repos/owned/external/datasets. That directory did not exist and was created silently by the
# fetch. Nothing failed and the only evidence was the path printed in the header. Resolved
# against a landmark now and not by counting, the same reason the ROOT walk above exists.
OUT = ROOT
while (OUT != os.path.dirname(OUT)) and (os.path.basename(OUT) != "repos"):
    OUT = os.path.dirname(OUT)
OUT = os.path.join(OUT, "external", "datasets")

BASE = "https://data.celltrackingchallenge.net"

AGENT = {"User-Agent": "anchor-sift-research/1.0"}

# name, dimensions, megabytes training, megabytes test, segmentation reference, what it holds.
# Sizes are the ones the challenge prints beside each link, read from the live pages on 2026-09-15.
# `perfect` rows are computer generated and their masks are exact. `silver` rows carry a reference
# annotation that is itself a reading.
WANTED = (
    ("BF-C2DL-HSC", "2D", 1600, 1600, "silver", "mouse hematopoietic stem cells, hydrogel microwells"),
    ("BF-C2DL-MuSC", "2D", 1200, 1300, "silver", "mouse muscle stem cells, hydrogel microwells"),
    ("DIC-C2DH-HeLa", "2D", 37, 41, "silver", "HeLa on flat glass, differential interference contrast"),
    ("Fluo-C2DL-Huh7", "2D", 36, 36, "none", "hepatocarcinoma expressing YFP-TIA-1"),
    ("Fluo-C2DL-MSC", "2D", 72, 71, "silver", "rat mesenchymal stem cells, polyacrylamide"),
    ("Fluo-N2DH-GOWT1", "2D", 53, 46, "silver", "GFP-GOWT1 mouse stem cells"),
    ("Fluo-N2DL-HeLa", "2D", 182, 168, "silver", "HeLa expressing H2b-GFP"),
    ("PhC-C2DH-U373", "2D", 40, 38, "silver", "glioblastoma-astrocytoma U373, phase contrast"),
    ("PhC-C2DL-PSC", "2D", 124, 106, "silver", "pancreatic stem cells on polystyrene"),
    ("Fluo-N2DH-SIM+", "2D", 91, 96, "perfect", "simulated HL60 nuclei, MitoGen"),
    ("Fluo-C3DH-A549", "3D", 244, 294, "silver", "GFP-actin A549 lung cancer in Matrigel"),
    ("Fluo-C3DH-H157", "3D", 7000, 7100, "silver", "GFP-transfected H157 lung cancer in Matrigel"),
    ("Fluo-C3DL-MDA231", "3D", 182, 179, "silver", "MDA231 breast carcinoma in collagen"),
    ("Fluo-N3DH-CE", "3D", 3100, 1700, "silver", "C. elegans developing embryo"),
    ("Fluo-N3DH-CHO", "3D", 98, 105, "silver", "CHO nuclei overexpressing GFP-PCNA"),
    ("Fluo-N3DL-DRO", "3D", 5800, 5900, "none", "developing Drosophila melanogaster embryo"),
    ("Fluo-N3DL-TRIC", "3D", 20600, 19900, "none", "Tribolium castaneum embryo, cartographic projection"),
    ("Fluo-N3DL-TRIF", "3D", 320000, 467000, "none", "Tribolium castaneum embryo, full"),
    ("Fluo-C3DH-A549-SIM", "3D", 314, 327, "perfect", "simulated A549 in Matrigel, FiloGen"),
    ("Fluo-N3DH-SIM+", "3D", 3100, 5900, "perfect", "simulated HL60 nuclei, MitoGen"),
)

# Under this many megabytes a dataset is in the small tier. Picked so the tier holds every 2D row
# that is not a gigabyte-scale brightfield sequence, and the smallest useful 3D rows with it.
SMALL = 200

# Megabytes left unclaimed on the target volume. A long unattended transfer shares the disk with
# whatever else runs, and stopping one dataset short is recoverable where a full disk is not.
HEADROOM = 20480


def flat_name(name, arm):
    """The one filename a dataset's arm lands under, flat and with no directory in it."""
    return "ctc_%s_%s.zip" % (name.replace("+", "plus").replace("-", "_").lower(), arm)


def url_for(name, arm):
    """The challenge's own link for one dataset and arm."""
    return "%s/%s-datasets/%s.zip" % (BASE, "training" if arm == "training" else "test", name)


def free_megabytes(path):
    """Megabytes available on the filesystem holding `path`, or its nearest existing parent."""
    probe = path
    while probe and not os.path.isdir(probe):
        parent = os.path.dirname(probe)
        if parent == probe:
            break
        probe = parent
    usage = shutil.disk_usage(probe)
    return usage.free / (1024.0 * 1024.0)


def selected(args):
    """The rows a run was asked for, as (name, arm) pairs, in manifest order."""
    skip = set(args.skip or ())
    rows = []
    for name, dims, train_mb, test_mb, reference, _ in WANTED:
        if name in skip:
            continue
        if args.fetch and (name != args.fetch):
            continue
        if args.tier == "small" and (train_mb > SMALL):
            continue
        if args.tier == "perfect" and (reference != "perfect"):
            continue
        if not (args.fetch or args.tier):
            continue
        rows.append((name, "training", train_mb))
        if args.test:
            rows.append((name, "test", test_mb))
    return rows


def listing(out):
    """The manifest as a table, with the totals that decide whether a transfer is reasonable."""
    out.write("  Cell Tracking Challenge, celltrackingchallenge.net, read 2026-09-15.\n")
    out.write("  Nothing is fetched without --fetch or --tier.\n\n")
    out.write("  %-20s %-4s %10s %10s %-8s %s\n"
              % ("name", "dims", "train MB", "test MB", "masks", "what it holds"))
    totals = {"2D": [0, 0], "3D": [0, 0]}
    for name, dims, train_mb, test_mb, reference, note in WANTED:
        totals[dims][0] += train_mb
        totals[dims][1] += test_mb
        out.write("  %-20s %-4s %10d %10d %-8s %s\n"
                  % (name, dims, train_mb, test_mb, reference, note))
    out.write("\n")
    for dims in ("2D", "3D"):
        out.write("  %s total: %.1f GB training, %.1f GB test\n"
                  % (dims, totals[dims][0] / 1024.0, totals[dims][1] / 1024.0))
    everything = sum(totals[d][0] + totals[d][1] for d in totals)
    out.write("  everything: %.1f GB\n\n" % (everything / 1024.0))
    out.write("  Fluo-N3DL-TRIF alone is %.0f GB of that. Ask before it moves.\n"
              % ((320000 + 467000) / 1024.0))
    out.write("\n  The two `perfect` rows carry exact masks because they are generated. A\n")
    out.write("  tracking error on them is a linking error and cannot be a segmentation error.\n")
    out.write("  --tier perfect selects them.\n")


def fetch(name, arm, megabytes, out):
    """One dataset arm to `OUT`, skipped where the file is already there."""
    target = os.path.join(OUT, flat_name(name, arm))
    if os.path.isfile(target):
        out.write("  %-28s already here\n" % flat_name(name, arm))
        return True
    if not os.path.isdir(OUT):
        os.makedirs(OUT)
    address = url_for(name, arm)
    out.write("  %-28s %6d MB  %s\n" % (flat_name(name, arm), megabytes, address))
    out.flush()
    # Written beside the target and moved on success. An interrupted transfer never leaves
    # something that looks like a complete dataset.
    partial = target + ".part"
    try:
        request = urllib.request.Request(address, headers=AGENT)
        with urllib.request.urlopen(request) as source, open(partial, "wb") as sink:
            while True:
                chunk = source.read(1 << 20)
                if not chunk:
                    break
                sink.write(chunk)
        os.replace(partial, target)
    except Exception as trouble:
        if os.path.isfile(partial):
            os.remove(partial)
        out.write("      failed: %s\n" % trouble)
        return False
    return True


def main():
    parser = argparse.ArgumentParser(description="Cell Tracking Challenge datasets.")
    parser.add_argument("--fetch", metavar="NAME", help="one dataset by its challenge name")
    parser.add_argument("--tier", choices=("small", "perfect", "all"), help="a group of datasets")
    parser.add_argument("--test", action="store_true", help="the test arm as well as training")
    parser.add_argument("--skip", action="append", metavar="NAME",
                        help="exclude a dataset by name, repeatable")
    args = parser.parse_args()

    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    rows = selected(args)
    if not rows:
        listing(out)
        out.flush()
        return 0

    wanted_mb = sum(megabytes for _, _, megabytes in rows)
    free_mb = free_megabytes(OUT)
    out.write("  %d files, %.1f GB, into %s\n" % (len(rows), wanted_mb / 1024.0, OUT))
    out.write("  %.1f GB free on that volume.\n\n" % (free_mb / 1024.0))
    if wanted_mb > free_mb:
        out.write("  REFUSED: that does not fit, short by %.1f GB.\n"
                  % ((wanted_mb - free_mb) / 1024.0))
        out.write("  Narrow the selection with --skip, or free space first. Nothing was fetched.\n")
        out.flush()
        return 1

    done = 0
    for name, arm, megabytes in rows:
        # Checked per file and not once at the start, because an unattended run competes with
        # whatever else is writing to this volume. A transfer that begins inside the margin and
        # ends outside it fills a disk, and a filled disk is somebody else's failed build.
        if free_megabytes(OUT) < (megabytes + HEADROOM):
            out.write("  stopped before %s %s: under %d MB of headroom would be left.\n"
                      % (name, arm, HEADROOM))
            break
        done += 1 if fetch(name, arm, megabytes, out) else 0
    out.write("\n  %d of %d present.\n" % (done, len(rows)))
    out.flush()
    return 0 if done == len(rows) else 1


if __name__ == "__main__":
    raise SystemExit(main())
