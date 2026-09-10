#!/usr/bin/env python3
# repotools-stamp: lib/repotools/boot.py 348a8353fbfc289b
# repo_tools - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Finding the toolkit from inside it, and the preamble every tool copies to get here.

THE PREAMBLE

Every runnable script under this toolkit opens with these four lines, before any repotools import:

    import os, sys
    _at = os.path.dirname(os.path.abspath(__file__))
    while _at != os.path.dirname(_at) and not os.path.isdir(os.path.join(_at, "lib", "repotools")):
        _at = os.path.dirname(_at)
    sys.path.insert(0, os.path.join(_at, "lib"))

This is the single duplicated fragment in the toolkit, and it is duplicated because it is the code
that finds the shared code. Everything after it is imported once.

WHY IT WALKS

The alternative is counting:

    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "lib"))

Counting fixes a script's distance from the root, so the script breaks the day it moves one level.
Thirty nine scripts in the anchor_sift tree computed their root by counting, and sorting that tree
into categories moved every one of them and broke all thirty nine at once.

THE LOOP GUARD

`_at != os.path.dirname(_at)` stops the walk at the filesystem root. Without it, a script launched
from outside any checkout walks to `C:\\` or `/` and then loops on a directory that is its own
parent. The guard turns that into a clean import failure at a known line.
"""

import os

# A directory is the toolkit root when it holds all of these. Three markers instead of one, because
# `lib` alone matches most Python projects and `code` alone matches half the trees on this machine.
TOOLKIT_MARKERS = ("lib/repotools", "repo/repo_template", "code")


def toolkit_root(start=None):
    """Absolute path to the repo_tools checkout holding this package.

    Walks up from this file, or from `start` when one is given, until a directory carries every
    entry in TOOLKIT_MARKERS. Raises when the walk reaches the filesystem root, because a toolkit
    that cannot find itself has to fail at import and not at the first template read.
    """
    at = os.path.dirname(os.path.abspath(start or __file__))
    while True:
        if all(os.path.exists(os.path.join(at, marker.replace("/", os.sep))) for marker in TOOLKIT_MARKERS):
            return at
        parent = os.path.dirname(at)
        if parent == at:
            raise SystemExit(
                "repotools: no toolkit root above %s (want %s)" % (start or __file__, " + ".join(TOOLKIT_MARKERS))
            )
        at = parent


def find_toolkit_root(start=None):
    """The toolkit root, or None where there is not one above `start`.

    The non-raising form of toolkit_root, for a caller that reaches for the toolkit as one
    candidate among several and has somewhere else to look when it is absent.

    A fetch installs the sets a repository asked for and never repo/repo_template or code/, so a
    tool running out of a fetched tree has no toolkit above it. toolkit_root raising there ended
    the run before the caller reached its remaining candidates and before it could print what it
    had tried, which is the shape gates.py was written against: the failure arrives as something
    unrelated instead of as the thing that went wrong.
    """
    try:
        return toolkit_root(start)
    except SystemExit:
        return None


def installed_root(start):
    """The directory holding the lib/repotools that `start` imports from.

    The toolkit root when a tool runs from inside the toolkit, and the fetch directory when it
    runs from a repository that fetched it. This is the walk documented at the top of this file,
    given a name so a tool needing its own siblings does not repeat it.
    """
    at = os.path.dirname(os.path.abspath(start))
    while at != os.path.dirname(at) and not os.path.isdir(os.path.join(at, "lib", "repotools")):
        at = os.path.dirname(at)
    return at


def toolkit_at(*parts):
    """Absolute path to `parts` under the toolkit root."""
    return os.path.join(toolkit_root(), *parts)
