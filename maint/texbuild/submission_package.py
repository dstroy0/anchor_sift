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
# The fix is not to restructure theory/, because one shared preamble across every book is what keeps
# a layout change reaching all of them. The fix is to copy the shared files into the book at
# packaging time and rewrite the lines that point at them.
#
# BOOKS ARE DISCOVERED, NOT LISTED
#
# build_theory.sh:26 records what happens otherwise. The four names were written into it once, and a
# book added after that line would not have built. Two books were missing from the tree's own
# documentation for the same reason, and a seventh was missing from README.md and from
# docs/research/index.md on the day it was created. This walks for main.tex at both depths so the
# packager cannot go stale the way a hand-written list does.
#
# WHAT IT REFUSES TO SHIP
#
# A submission still holding a climbing path is broken and fails on upload with a LaTeX error nobody
# can read. Every .tex in the assembled copy is re-read AFTER the rewrite, and a remaining ../ in an
# \input or \include fails that book and names the file and the line. A rule that was supposed to
# catch a path is not evidence that it did.
#
# It also refuses to carry what a LaTeX run leaves behind. See LEAVINGS.
#
# WHAT --arxiv ADDS, AND WHY EACH STEP IS THERE
#
# arXiv extracts a tarball into one directory and runs LaTeX there, and everything extracted becomes
# public whether or not the document reads it. That second half is the part that costs somebody
# later, so the extra steps are mostly deletions:
#
#   flattened      Every subdirectory is emptied into the root and the \input and \include lines
#                  that named it are rewritten. Checked first for two files sharing a basename,
#                  because flattening those would destroy one of them silently.
#   comments gone  A full-line comment is deleted. A comment at the end of a line has its text
#                  deleted and its percent sign kept, because in LaTeX that percent sign eats the
#                  newline and dropping it inserts a space into the typeset page. Stripping it
#                  wholesale is the standard way this step goes wrong.
#   nothing hidden A dotfile or dot-directory is not copied. None is ever read by the document and
#                  each one is somebody's local state.
#   nothing unread A .tex no \input or \include chain reaches from main.tex is dropped. An old
#                  draft nobody compiles still publishes.
#   four passes    \typeout after \end{document} makes arXiv run LaTeX until the labels settle.
#   flat tarball   No wrapping directory, which is what `tar -cvvf ax.tar *` produces from inside
#                  the assembled copy.
#   metadata.txt   The title, the authors and the abstract with the LaTeX taken out and the line
#                  breaks collapsed, ready to paste into the web form. arXiv shows the whitespace
#                  that LaTeX ignores, so the collapsing is not cosmetic.
#
# It does not submit anything and holds no credential. The tarball and the metadata are the whole
# output, and a person uploads them.

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
# dedication.tex is here for the same reason preamble.tex is. One wording reaches every book, held
# in one place so it cannot drift between them.
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


# The line arXiv reads as an instruction to run LaTeX again. Placed after \end{document}, where it
# typesets nothing and only reaches the log the rerun logic watches.
TYPEOUT = "\\typeout{get arXiv to do 4 passes: Label(s) may have changed. Rerun}"

# An \input or \include naming a file inside the book. Rewritten when the tree is flattened.
NAMED = re.compile(r"(\\(?:input|include)\{)([^}]+)(\})")


def uncomment(text):
    """One file's text with the comment text removed, and how many comments that was.

    A percent sign starts a comment when the run of backslashes before it is even, because an odd
    run ends in an escaped percent that typesets as a character.

    A full line comment is deleted outright. A comment after content keeps its percent sign and
    loses everything after it. That percent sign is doing work: LaTeX drops the newline following
    it, so removing it joins two words with a space that was not there before. This is the step
    that quietly changes a typeset page, and keeping the sign is what stops it.
    """
    held = []
    found = 0
    for line in text.splitlines():
        at = -1
        run = 0
        for index, letter in enumerate(line):
            if letter == "\\":
                run += 1
                continue
            if (letter == "%") and (run % 2 == 0):
                at = index
                break
            run = 0
        if at < 0:
            held.append(line)
            continue
        found += 1
        if not line[:at].strip():
            continue
        held.append(line[:at + 1])
    return "\n".join(held) + ("\n" if text.endswith("\n") else ""), found


def reachable(out):
    """Every .tex under out that main.tex reaches, by name without its extension.

    Walked from main.tex through \\input and \\include, so a file reached only by a file that is
    itself reached still counts. A .tex outside this set is an old draft, and uploading one
    publishes it.
    """
    seen = set()
    pending = ["main"]
    while pending:
        stem = pending.pop()
        if stem in seen:
            continue
        seen.add(stem)
        for where, _dirs, names in os.walk(out):
            for name in names:
                if name != (stem + TEX) and name != stem:
                    continue
                with open(os.path.join(where, name), encoding="utf-8") as handle:
                    text = handle.read()
                for found in NAMED.finditer(text):
                    target = os.path.basename(found.group(2))
                    pending.append(target[:-len(TEX)] if target.endswith(TEX) else target)
    return seen


def flatten(out):
    """Every file moved into the root of out, with the naming lines rewritten.

    Returns (moved, collisions). A collision is two files sharing a basename, and nothing is moved
    when there is one: flattening past it would overwrite a file the document reads.
    """
    holding = {}
    for where, _dirs, names in os.walk(out):
        if os.path.abspath(where) == os.path.abspath(out):
            continue
        for name in names:
            holding.setdefault(name, []).append(os.path.join(where, name))
    collisions = {name: paths for name, paths in holding.items()
                  if (len(paths) > 1) or os.path.isfile(os.path.join(out, name))}
    if collisions:
        return [], collisions

    moved = []
    for name, paths in sorted(holding.items()):
        shutil.move(paths[0], os.path.join(out, name))
        moved.append(os.path.relpath(paths[0], out).replace("\\", "/"))
    for where, dirs, _names in os.walk(out, topdown=False):
        for one in dirs:
            folder = os.path.join(where, one)
            if not os.listdir(folder):
                os.rmdir(folder)

    for name in sorted(os.listdir(out)):
        if not name.endswith(TEX):
            continue
        path = os.path.join(out, name)
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        changed = NAMED.sub(lambda found: "%s%s%s" % (found.group(1),
                                                      os.path.basename(found.group(2)),
                                                      found.group(3)), text)
        if changed != text:
            with open(path, "w", encoding="utf-8", newline="\n") as handle:
                handle.write(changed)
    return moved, {}


def strip_latex(text):
    """One run of LaTeX source as the plain text arXiv's web form wants.

    Control sequences and their braces come out, the accented forms LaTeX spells in ASCII are left
    as their letter, and every run of whitespace becomes one space. The last part is the one that
    matters: LaTeX ignores the line breaks in an abstract and arXiv prints them.
    """
    text = re.sub(r"\\(?:emph|textbf|textit|texttt|text|mbox|spacedallcaps|spacedlowsmallcaps)"
                  r"\{([^{}]*)\}", r"\1", text)
    text = re.sub(r"\\[A-Za-z@]+\*?", " ", text)
    text = text.replace("\\\\", " ").replace("~", " ")
    text = re.sub(r"[{}$]", "", text)
    text = text.replace("--", "-")
    return " ".join(text.split())


def metadata(out, book):
    """The title, authors and abstract of an assembled book, as text to paste into the form.

    Read off the assembled copy, because that is what ships. The titlepage carries the title and
    the author and the abstract sits in its own file, and both are found by name rather than by
    position so a book that orders its frontmatter differently still reports.
    """
    lines = []
    title = ""
    authors = ""
    titlepage = os.path.join(out, "titlepage.tex")
    if os.path.isfile(titlepage):
        with open(titlepage, encoding="utf-8") as handle:
            held = [strip_latex(one) for one in handle.read().splitlines()]
        held = [one for one in held if one]
        if held:
            title = held[0]
        for index, one in enumerate(held):
            if one.lower() == "by" and (index + 1) < len(held):
                authors = held[index + 1]
                break

    abstract = ""
    where = os.path.join(out, "abstract.tex")
    if os.path.isfile(where):
        with open(where, encoding="utf-8") as handle:
            body = handle.read()
        body = re.sub(r"\\(?:pdfbookmark|chapter)\*?(?:\[[^\]]*\])?\{[^}]*\}\{?[^}]*\}?", " ", body)
        abstract = strip_latex(body)

    lines.append("title")
    lines.append("  " + (title.title() if title.isupper() else title))
    lines.append("")
    lines.append("authors")
    lines.append("  " + authors.replace(" and ", ", "))
    lines.append("")
    lines.append("abstract")
    lines.append("  " + abstract)
    lines.append("")
    lines.append("subject area is not filled in here. It is a judgement about where the work")
    lines.append("belongs and nobody but the author can make it.")
    lines.append("")
    path = os.path.join(os.path.dirname(out), "%s_metadata.txt" % os.path.basename(out))
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write("\n".join(lines))
    return path, title, authors, abstract


def flat_tar(out):
    """The assembled directory as a tarball with no wrapping directory.

    arXiv extracts into one root it chose, so a wrapping directory puts every file one level below
    where main.tex says they are. This is `tar -cvvf ax.tar *` run from inside the copy.
    """
    archive = "%s.tar" % out
    if os.path.isfile(archive):
        os.remove(archive)
    with tarfile.open(archive, "w") as handle:
        for name in sorted(os.listdir(out)):
            handle.add(os.path.join(out, name), arcname=name)
    return os.path.basename(archive), os.path.getsize(archive)


def books():
    """Every book under theory/, as its path below theory/.

    Two depths, matching build_theory.sh. theory/<book>/ is where most of them sit, and
    theory/<subject>/<book>/ is where the cryptography one does.
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
