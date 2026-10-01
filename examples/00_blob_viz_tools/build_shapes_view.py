#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Builds the shapes gallery, every shape the toolbox makes on the shared core, through the one generator.

    python examples/00_blob_viz_tools/build_shapes_view.py
    python examples/00_blob_viz_tools/build_shapes_view.py --set shape=klein --set transform=twist --out shapes.html

Each --set names a setting and its opening value. The page checks every one against its scheme on load, applies
what passes and names what does not. Integers and the words true and false are read as such; anything else is a
word. No data is computed here: the page samples every shape itself. It needs WebGPU, Chrome 113 or later.
"""

import argparse
import os
import sys

import generate_template

HERE = os.path.dirname(os.path.abspath(__file__))
TEMPLATE = os.path.join(HERE, "shapes_view_template.html")


def opening(pairs):
    view = {}
    for pair in pairs:
        name, _, text = pair.partition("=")
        if not name or not _:
            raise SystemExit("  --set takes name=value, and %r has no =" % pair)
        if text in ("true", "false"):
            view[name] = text == "true"
        elif text.lstrip("-").isdigit():
            view[name] = int(text)
        else:
            view[name] = text
    return view


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--set", action="append", default=[], metavar="NAME=VALUE")
    parser.add_argument("--out")
    given = parser.parse_args()
    try:
        out = generate_template.render(TEMPLATE, {"view": opening(given.set)}, out=given.out, name="shapes_view.html")
    except generate_template.Refused as why:
        sys.stderr.write("  refused: %s\n" % why)
        return 1
    print("  %s (%d bytes)" % (out, os.path.getsize(out)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
