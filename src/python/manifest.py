#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Where each import name of the Python container lies, read from manifest.tsv beside this file.

    sys.path.insert(0, os.path.join(ROOT, "src", "python"))
    import manifest

The container's parts sit at the paths their category gives them, and a program imports them by name:
`from measure.web import ...`, `from representation import exact`. Importing this module puts one finder
first on sys.meta_path, and the finder answers exactly the names manifest.tsv holds, each at its row's path.
A name with no row is left to the finders after it.
"""

import importlib.machinery
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TABLE = os.path.join(HERE, "manifest.tsv")


def rows():
    """{import name: absolute path}, from manifest.tsv."""
    held = {}
    with open(TABLE, encoding="utf-8") as handle:
        for line in handle:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            name, path = line.split("\t")
            held[name] = os.path.join(HERE, *path.split("/"))
    return held


class ManifestFinder:
    """A meta path finder for the names manifest.tsv holds."""

    def __init__(self, held):
        self.held = held

    def find_spec(self, fullname, path=None, target=None):
        where = self.held.get(fullname)
        if where is None:
            return None
        if where.endswith(".py"):
            return importlib.util.spec_from_file_location(fullname, where)
        package = os.path.join(where, "__init__.py")
        if os.path.isfile(package):
            return importlib.util.spec_from_file_location(fullname, package, submodule_search_locations=[where])
        spec = importlib.machinery.ModuleSpec(fullname, None, is_package=True)
        spec.submodule_search_locations = [where]
        return spec


if not any(isinstance(finder, ManifestFinder) for finder in sys.meta_path):
    sys.meta_path.insert(0, ManifestFinder(rows()))
