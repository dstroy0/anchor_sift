#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Assemble one self-contained submission per book, in whatever shape the venue asks for.
#
#   python maint/texbuild/submission_package.py                  every book, gzipped tar
#   python maint/texbuild/submission_package.py --archive zip    every book, zip
#   python maint/texbuild/submission_package.py --archive none   directories only
#   python maint/texbuild/submission_package.py <book> ...       named books
#
# Writes build/submission/<book>/ and, unless --archive none, an archive beside it. Nothing under
# theory/ is modified: the rewrite happens on the copy, and the source keeps the shared preamble it
# has always had.
#
# THE REQUIREMENT IS NOT ANY ONE VENUE'S
#
# A submission is a directory that compiles from inside itself. Every venue enforces that and they
# differ only in what they want it wrapped in. arXiv extracts a tarball into one root and runs LaTeX
# there. Most journals ask for a zip. A repository deposit takes the directory as it stands. A venue
# that wants only the built PDF still needs the build to have worked somewhere.
#
# So the assembly and the checks below are the whole job and they are the same every time. The
# archive format is the only part that changes, and it is a flag rather than a name baked into the
# file. This started life as arxiv_package.py and that was the wrong shape: it made one venue's
# packaging look like a property of the work.
#
# WHY ANY OF IT IS NEEDED
#
# Every book reaches outside its own directory for the two files it shares with the others.
# theory/Salishan/main.tex says \input{../preamble.tex} and theory/cryptography/sha256/main.tex
# says \input{../../preamble.tex}, and preamble.tex then says \input{../macros.tex}. That resolves
# here because theory/ is the directory above them all, and it resolves nowhere else.
#
# The fix is not to restructure theory/, because one shared preamble across six books is what keeps
# a layout change reaching all of them. The fix is to copy the shared files into the book at
# packaging time and rewrite the lines that point at them.
#
# BOOKS ARE DISCOVERED, NOT LISTED
#
# build_theory.sh:26 records what happens otherwise: the four names were written into it once, and a
# book added after that line would not have built. Two of the six were missing from the tree's own
# documentation because of exactly that. This walks for main.tex at both depths for the same reason.
#
# WHAT IT REFUSES TO SHIP
#
# A submission still holding a climbing path is broken and fails on upload with a LaTeX error nobody
# can read. Every .tex in the assembled copy is re-read AFTER the rewrite, and a remaining ../ in an
# \input or \include fails that book and names the file and the line. A rule that was supposed to
# catch a path is not evidence that it did.
#
# It also refuses to carry what a LaTeX run leaves behind. See LEAVINGS.

import io
import os
import re
import shutil
import sys
import tarfile
import zipfile

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
THEORY = os.path.join(ROOT, "theory")
OUT = os.path.join(ROOT, "build", "submission")

# The files every book shares, which sit in theory/ and not in any book. These are copied into the
# submission root and the lines that reach up for them are rewritten to name them plainly.
#
# dedication.tex is here for the same reason preamble.tex is: one wording reaching all six books,
# held in one place so it cannot drift between them.
SHARED = ("preamble.tex", "macros.tex", "dedication.tex")

# An \input or \include whose argument climbs out of the directory it is read from. The name is
# captured so only the shared files are rewritten: another climbing path is a different problem and
# gets reported instead of quietly repointed.
CLIMBING = re.compile(r"(\\(?:input|include)\{)((?:\.\./)+)([^}]+)(\})")

# What a source file is. Everything else in a book directory is copied as it stands, which is how
# the matplotlib figure beside the corpus derivation chapter travels with its chapter.
TEX = ".tex"

# What the archive flag accepts, against what it writes.
ARCHIVES = ("tar.gz", "zip", "none")

# What a LaTeX run leaves beside the source, and what never belongs in a submission.
#
# build_theory.sh compiles with -output-directory so it leaves none of this. TeXworks and TeXShop
# compile IN PLACE, and a book opened in one of those to look at it comes back with main.pdf,
# main.log, main.aux, main.toc, a .aux per included chapter, and a synctex index larger than the
# whole rest of the book. Copying a book directory wholesale ships all of it.
#
# Measured once: theory/anchor_sift packaged at 1,269,699 bytes against 73,201 for the same book
# clean, and 705,688 of that was one synctex file. It would have been accepted.
LEAVINGS = (".aux", ".log", ".toc", ".lof", ".lot", ".out", ".bbl", ".blg", ".idx", ".ilg",
            ".ind", ".nav", ".snm", ".vrb", ".fls", ".fdb_latexmk", ".synctex", ".synctex.gz")


def is_leaving(name):
    """Whether a filename is something a LaTeX run dropped beside the source.

    main.pdf is excluded by name and not by extension. A PDF is otherwise a figure, and the corpus
    derivation chapter's matplotlib figure has to travel with its chapter.
    """
    lowered = name.lower()
    if lowered == "main.pdf":
        return True
    return any(lowered.endswith(one) for one in LEAVINGS)


def books():
    """Every book under theory/, as its path below theory/.

    Two depths, matching build_theory.sh: theory/<book>/ as five of them sit, and
    theory/<subject>/<book>/ as the cryptography one does.
    """
    import glob
    found = []
    for pattern in (("*", "main.tex"), ("*", "*", "main.tex")):
        for one in sorted(glob.glob(os.path.join(THEORY, *pattern))):
            found.append(os.path.relpath(os.path.dirname(one), THEORY).replace("\\", "/"))
    return found


def rewrite(text):
    """One file's text with the shared inputs brought in, and what was left climbing.

    Returns (text, rewritten, refused). rewritten names the shared files repointed. refused holds
    any other climbing path, which is not this function's to decide about.
    """
    rewritten = []
    refused = []

    def one(found):
        opener, climb, name, closer = found.groups()
        target = os.path.basename(name)
        if target in SHARED:
            rewritten.append(target)
            return "%s%s%s" % (opener, target, closer)
        refused.append("%s%s" % (climb, name))
        return found.group(0)

    return CLIMBING.sub(one, text), rewritten, refused


def assemble(book, out):
    """One book copied into out, with the shared files inside it. Returns what was rewritten."""
    source = os.path.join(THEORY, book)
    if os.path.isdir(out):
        shutil.rmtree(out)
    shutil.copytree(source, out, ignore=lambda where, names: [one for one in names
                                                             if is_leaving(one)])
    for name in SHARED:
        shutil.copy2(os.path.join(THEORY, name), os.path.join(out, name))

    rewritten = []
    refused = []
    for where, _dirs, names in os.walk(out):
        for name in sorted(names):
            if not name.endswith(TEX):
                continue
            path = os.path.join(where, name)
            with open(path, encoding="utf-8") as handle:
                text = handle.read()
            changed, did, would_not = rewrite(text)
            if changed != text:
                with open(path, "w", encoding="utf-8", newline="\n") as handle:
                    handle.write(changed)
            rewritten.extend((os.path.relpath(path, out), one) for one in did)
            refused.extend((os.path.relpath(path, out), one) for one in would_not)
    return rewritten, refused


def still_climbing(out):
    """Any \\input or \\include left pointing above the submission root, with its line number.

    Read back off the assembled copy and not predicted from the rewrite, because what ships is the
    copy.
    """
    held = []
    for where, _dirs, names in os.walk(out):
        for name in sorted(names):
            if not name.endswith(TEX):
                continue
            path = os.path.join(where, name)
            with open(path, encoding="utf-8") as handle:
                for number, line in enumerate(handle, 1):
                    if CLIMBING.search(line):
                        held.append((os.path.relpath(path, out), number, line.strip()))
    return held


def bundle(out, kind):
    """The assembled directory wrapped as the venue asked. Returns (name, bytes), or None.

    Every path inside the archive sits under one top-level directory named for the book, which is
    what an extract-into-one-root venue needs and what a person unpacking it locally wants anyway.
    """
    base = os.path.basename(out)
    if kind == "none":
        return None
    if kind == "tar.gz":
        archive = "%s.tar.gz" % out
        if os.path.isfile(archive):
            os.remove(archive)
        with tarfile.open(archive, "w:gz") as handle:
            handle.add(out, arcname=base)
    else:
        archive = "%s.zip" % out
        if os.path.isfile(archive):
            os.remove(archive)
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as handle:
            for where, _dirs, names in os.walk(out):
                for name in sorted(names):
                    full = os.path.join(where, name)
                    handle.write(full, os.path.join(base, os.path.relpath(full, out)))
    return os.path.basename(archive), os.path.getsize(archive)


def wanted_archive(argv):
    """The archive kind named on the command line, defaulting to a gzipped tar."""
    if "--archive" not in argv:
        return "tar.gz"
    at = argv.index("--archive")
    if (at + 1) >= len(argv):
        raise SystemExit("submission_package: --archive wants one of %s" % ", ".join(ARCHIVES))
    kind = argv[at + 1]
    if kind not in ARCHIVES:
        raise SystemExit("submission_package: unknown archive %r, wants one of %s"
                         % (kind, ", ".join(ARCHIVES)))
    return kind


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    argv = sys.argv[1:]
    kind = wanted_archive(argv)
    skip = {"--archive", kind}
    named = [one for one in argv if (one not in skip) and not one.startswith("-")]
    status = 0

    for book in (named or books()):
        if not os.path.isfile(os.path.join(THEORY, book, "main.tex")):
            out.write("  no such book: %s\n" % book)
            status = 1
            continue

        flat = book.replace("/", "_")
        target = os.path.join(OUT, flat)
        rewritten, refused = assemble(book, target)
        left = still_climbing(target)

        out.write("  %s\n" % book)
        for path, name in rewritten:
            out.write("    brought in   %-34s in %s\n" % (name, path))
        for path, name in refused:
            out.write("    NOT MINE     %-34s in %s\n" % (name, path))
            status = 1
        if left:
            for path, number, line in left:
                out.write("    STILL CLIMBS %s:%d  %s\n" % (path, number, line))
            out.write("    %s is not shippable and no archive was written\n" % book)
            status = 1
            continue

        made = bundle(target, kind)
        if made is None:
            out.write("    %s/  directory only\n" % flat)
        else:
            out.write("    %s  %d bytes\n" % made)

    out.write("\n  Assembled under %s\n" % os.path.relpath(OUT, ROOT))
    out.write("  A package is not a submission until it has compiled from inside its own\n")
    out.write("  directory. Nothing here has compiled anything.\n")
    out.flush()
    return status


if __name__ == "__main__":
    raise SystemExit(main())
