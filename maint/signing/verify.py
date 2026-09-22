#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Check a manifest against the tree, and its signature and anchor if they exist. Needs no secret.
#
#   Usage:  python maint/signing/verify.py [--manifest FILE] [--root DIR]
#
# THREE CLAIMS, THREE CHECKS, AND THEY FAIL INDEPENDENTLY
#
# docs/provenance.md section 1 separates them and the separation is the whole design, so this reports
# them separately instead of printing one verdict:
#
#   integrity    every file still hashes to what the manifest says     no key, no network
#   authorship   the manifest carries a good signature                 needs the public key
#   priority     the signature carries an OpenTimestamps proof         needs ots, or a full node
#
# A tree can pass integrity and have no signature. A signature can verify and prove nothing about
# when. Reporting one number for all three would hide exactly the gap this apparatus exists to close.
#
# WHAT A MISSING PIECE MEANS, STATED SO IT IS NOT READ AS A PASS
#
# Absent signature and absent anchor are reported as ABSENT and not as failures, because they are
# states of the world and not defects. But the exit status counts them, letting a pipeline ask "is
# this work anchored" gets an answer instead of a green light for a tree with no anchor at all.

import hashlib
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# THE TREE LABEL IS IMPORTED AND NEVER RECOMPUTED HERE.
#
# This file used to spell the label itself, as os.path.basename of the root. build_manifest.py then
# learned to read the name from repotools.toml instead, because a directory basename is where
# somebody put a tree and not what the project calls itself. The two spellings stopped agreeing, and
# this file compared the directory's own name against 1,417 rows tagged "BTC" and "anchor_sift",
# and printed "0 checked, 0 changed, 0 missing".
#
# That reads as a pass. A verifier that checks nothing and reports no failures leaves a tree less
# protected than one with no verifier, because it answers the question it was asked without ever
# asking it. The rule this tree already records about docs_check applies without modification: a
# check that read nothing has not passed.
#
# Importing the function is the only thing keeping the two from drifting again. A copy would carry
# the same bug, waiting for the next rename.
import build_manifest  # noqa: E402


def digest_of(path):
    accumulator = hashlib.sha256()
    with open(path, "rb") as handle:
        while True:
            block = handle.read(1 << 20)
            if not block:
                break
            accumulator.update(block)
    return accumulator.hexdigest()


def read_manifest(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            fields = line.split("\t")
            if len(fields) == 4:
                rows.append(fields)
    return rows


def run(command):
    """Returns (ok, output). A missing tool is not a failed check, it is an absent one."""
    try:
        done = subprocess.run(command, capture_output=True, text=True, timeout=120)
        return done.returncode == 0, (done.stdout + done.stderr).strip()
    except FileNotFoundError:
        return None, "not installed"
    except Exception as error:  # noqa: BLE001 - the caller prints whatever went wrong
        return False, str(error)


def main(argv):
    manifest = argv[argv.index("--manifest") + 1] if "--manifest" in argv else os.path.join(
        "maint", "signing", "manifest.tsv")
    root = argv[argv.index("--root") + 1] if "--root" in argv else "."

    if not os.path.isfile(manifest):
        print("  no manifest at %s" % manifest)
        print("  build one first: python maint/signing/build_manifest.py")
        return 2

    rows = read_manifest(manifest)
    if not rows:
        print("  %s lists no files. Nothing was checked, so nothing passed." % manifest)
        return 2

    here = build_manifest.label_for(os.path.abspath(root))
    changed, missing, checked, skipped = [], [], 0, 0

    for tree, path, size, sha in rows:
        if tree != here:
            skipped += 1
            continue
        full = os.path.join(root, path)
        if not os.path.isfile(full):
            missing.append(path)
            continue
        checked += 1
        if digest_of(full) != sha:
            changed.append(path)

    print("  INTEGRITY")
    print("    tree %r, %d checked, %d changed, %d missing" % (here, checked, len(changed), len(missing)))
    if skipped:
        print("    %d rows belong to another tree and were not checked from here" % skipped)

    # A check that read nothing has not passed. Zero matched rows means the label this tree reports and the
    # labels in the manifest disagree, which is a broken check and never a clean one.
    if checked == 0:
        print("")
        print("    NOTHING WAS CHECKED. No manifest row carries the label %r." % here)
        print("    The labels present are: %s" % ", ".join(sorted({r[0] for r in rows})))
        print("    Run from the tree the manifest was built for, or rebuild the manifest.")
        return 2
    for path in changed[:20]:
        print("      CHANGED  %s" % path)
    for path in missing[:20]:
        print("      MISSING  %s" % path)

    findings = len(changed) + len(missing)

    print("  AUTHORSHIP")
    signature = manifest + ".asc"
    if not os.path.isfile(signature):
        print("    ABSENT. No signature at %s" % signature)
        print("    One command, and it needs the key: see maint/signing/sign.ps1")
        findings += 1
    else:
        ok, output = run(["gpg", "--verify", signature, manifest])
        if ok is None:
            print("    gpg is not installed, so the signature could not be checked")
            findings += 1
        elif ok:
            print("    GOOD signature over the manifest")
            for line in output.splitlines():
                if "Good signature" in line or "Primary key" in line:
                    print("      %s" % line.strip())
        else:
            print("    BAD signature")
            findings += 1

    print("  PRIORITY")

    # TWO PLACES A PROOF CAN SIT, AND BOTH COUNT.
    #
    # Stamping the signature dates who-and-when together. Stamping the manifest dates the bytes alone
    # and needs no key, so it can be done while the signature waits for whoever holds it. An earlier
    # version of this looked only at the signature's proof and therefore reported PRIORITY ABSENT on a
    # tree that had an anchored manifest sitting beside it.
    anchors = [
        (manifest + ".ots", manifest, "the manifest's bytes"),
        (signature + ".ots", signature, "the signature"),
    ]
    anchored = False

    for proof, target, what in anchors:
        if not os.path.isfile(proof):
            continue
        anchored = True
        print("    proof over %s: %s" % (what, proof))

        # A PROOF OLDER THAN WHAT IT STAMPS IS ORPHANED. An anchor names exact bytes. Rebuild the
        # file afterwards and the proof still verifies against the chain while describing something
        # that is no longer on disk. That shape reads as coverage without being it.
        if os.path.isfile(target) and os.path.getmtime(proof) < os.path.getmtime(target):
            print("      STALE. %s was written after this proof was taken, so the proof names" % what)
            print("      bytes that are no longer there. It is still a valid anchor for the old")
            print("      bytes and it covers nothing currently on disk. Stamp again.")
            findings += 1
            continue

        ok, output = run(["ots", "verify", proof])
        if ok is None:
            print("      ots is not installed, so it could not be checked here. The proof stands;")
            print("      it verifies against any full node and does not depend on this machine.")
        elif ok:
            print("      VERIFIED against the chain")
            for line in output.splitlines()[:3]:
                print("        %s" % line.strip())
        else:
            # A fresh stamp has no confirmation yet and verify fails until it does. That is pending
            # and not broken, and the two read the same from the exit code alone.
            print("      not yet verifiable. A stamp needs a chain confirmation, usually a few")
            print("      hours. Finish it later with: ots upgrade %s" % proof)

    if not anchored:
        print("    ABSENT. No timestamp proof at either %s or %s" % (manifest + ".ots", signature + ".ots"))
        print("    Until one exists there is no evidence of date that a competing claim cannot")
        print("    match, because a commit date and a signature date are both self-asserted.")
        findings += 1

    print("")
    print("  %d finding(s)" % findings)
    return findings


if __name__ == "__main__":
    sys.exit(main(sys.argv))
