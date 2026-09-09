#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Clone what this repository depends on, instead of carrying copies of it.
#
#   Usage:  python tools/maintain/get_deps.py [--update]
#
# What this replaces. MMgr's code used to sit in this tree as four separate partial copies: its
# public headers under deps/include, twenty of its module directories under deps/src, its test
# support under deps/mmgr_sha256, and the library it depends on under deps/embedded_types. Every one
# of those was byte identical to the original and none of them recorded which commit it came from,
# so there was no way to tell a copy that was current from one that had gone stale, and no way to
# update any of them without hand copying again.
#
# A clone answers both. `git -C deps/mmgr log -1` says exactly what is checked out, and --update
# moves it. Nothing here writes into the clone.
#
# embedded_types is deliberately not listed below. MMgr fetches it itself, into its own deps directory,
# through the FetchContent block in deps/mmgr/deps/CMakeLists.txt. Cloning it here as well would put
# a second copy at a second commit, the thing this script exists to stop.
#
# THE CLOSED ONE
#
# The Salishan corpus is a dependency that almost nobody can clone. The hand extractions are forms
# transcribed out of published papers and the papers are their authors' copyright, so neither is
# this work's to redistribute and both sit in a closed repository. Its address is read from
# ANCHOR_SIFT_PRIVATE_REPO and is not written down here, because the address of a closed repository
# does not belong in a public one.
#
# Failing to clone it is expected and is reported that way, not as an error. The papers can
# be rebuilt from the public archive by anyone: tools/Salishan/get_papers.py fetches all 993 ICSNL
# papers by name and converts them. What cannot be rebuilt is the hand extraction, and that goes to
# anyone who has the papers and asks.

import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEPS = os.path.join(ROOT, "deps")

PRIVATE_ENV = "ANCHOR_SIFT_PRIVATE_REPO"

# Name, repository, and what this tree wants it for.
WANTED = (
    ("mmgr", "https://github.com/dstroy0/MMgr.git",
     "the memory library. Its test support carries the SHA-256 the older benches call, and four "
     "unwired drivers reach into its modules."),
    ("salishan_corpus", os.environ.get(PRIVATE_ENV),
     "the hand extractions and the papers they were read from. Closed, and the ordinary answer "
     "here is that you do not have it."),
)


def run(command, where):
    """A git command, with its output returned and its failure reported instead of raised."""
    finished = subprocess.run(command, cwd=where, capture_output=True, text=True)
    return finished.returncode, (finished.stdout + finished.stderr).strip()


def main():
    updating = "--update" in sys.argv
    os.makedirs(DEPS, exist_ok=True)

    for name, repository, why in WANTED:
        where = os.path.join(DEPS, name)
        print("  %s" % name)
        print("    %s" % why)

        if repository is None:
            print("    no %s set, so it is not fetched. Nothing else here needs it."
                  % PRIVATE_ENV)
            print("    to rebuild the papers from the public archive instead:")
            print("      python tools/Salishan/get_papers.py")
            continue

        if os.path.isdir(os.path.join(where, ".git")):
            if not updating:
                code, said = run(["git", "log", "-1", "--format=%h %ad %s", "--date=short"], where)
                print("    already here at %s" % (said if code == 0 else "an unreadable commit"))
                continue
            code, said = run(["git", "pull", "--ff-only"], where)
            print("    %s" % (said.splitlines()[-1] if said else "updated"))
            continue

        code, said = run(["git", "clone", "--depth", "1", repository, where], DEPS)
        if code != 0:
            trouble = said.splitlines()[-1] if said else "unknown"
            if name == "salishan_corpus":
                # Being refused here is the expected answer for everyone outside the work, and the
                # rest of the tree runs without it.
                print("    not available to this checkout: %s" % trouble)
                continue
            print("    could not clone: %s" % trouble)
            return 1
        code, said = run(["git", "log", "-1", "--format=%h %ad %s", "--date=short"], where)
        print("    cloned at %s" % (said if code == 0 else "an unreadable commit"))

    print("\n  Nothing under deps/ is carried in git. It is reproducible from this script, which is")
    print("  the same rule build/ and site/ already follow.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
