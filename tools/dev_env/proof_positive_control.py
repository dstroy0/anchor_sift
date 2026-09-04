#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Proof of the posit that a negative control cannot show an instrument works, from the posits section of
# docs/research/anchor-sift-ledger.md.
#
#   Usage:  python tools/dev_env/proof_positive_control.py
#
# Every control in this work until the protein structures was a memoryless process, and one of those can
# only show that an instrument does not invent structure. It cannot show that the instrument finds
# structure that is present, and the protein case demonstrated the difference by being reported as
# unstructured twice.
#
# A crystal is the cleanest positive control available. Its periodicity is not inferred from the
# measurement: the Crystallography Open Database publishes the cell edge for every entry, so the answer
# is a number someone else measured and wrote down. Tiling a published cell reproduces the real periodic
# arrangement, and the instrument is then asked to return the edge without being told it.
#
# Only cells with right angles are used, so the fractional to Cartesian conversion is a scaling and no
# crystallographic machinery is needed to get the geometry right.

import io
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

AGENT = {"User-Agent": "MMgr-research/1.0 (https://github.com/dstroy0/MMgr; dquigg123@gmail.com)"}
SEARCH = "https://www.crystallography.net/cod/result?format=json&text=%s&count=%d"
CIF = "https://www.crystallography.net/cod/%s.cif"

VOXEL = 0.25
TILES = 6
WANTED = ("halite", "fluorite", "pyrite")


def fetch(url):
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=180) as response:
        return response.read().decode("utf-8", "replace")


def number(text):
    """A CIF value carries its uncertainty in brackets, which is not part of the number."""
    return float(re.sub(r"\(.*?\)", "", text).strip())


def parse_cif(text):
    """Cell edges and fractional atom sites, for a cell whose angles are all right."""
    cell = {}
    for key in ("a", "b", "c", "alpha", "beta", "gamma"):
        found = re.search(r"_cell_%s\s+(\S+)" % ("length_" + key if len(key) == 1 else "angle_" + key),
                          text)
        if not found:
            return None, None
        cell[key] = number(found.group(1))
    for angle in ("alpha", "beta", "gamma"):
        if abs(cell[angle] - 90.0) > 0.01:
            return None, None

    lines = text.splitlines()
    sites = []
    index = 0
    while index < len(lines):
        if lines[index].strip() != "loop_":
            index += 1
            continue
        index += 1
        headers = []
        while index < len(lines) and lines[index].strip().startswith("_"):
            headers.append(lines[index].strip())
            index += 1
        wanted = ("_atom_site_fract_x", "_atom_site_fract_y", "_atom_site_fract_z")
        if not all(name in headers for name in wanted):
            continue
        spots = [headers.index(name) for name in wanted]
        kind = headers.index("_atom_site_type_symbol") if "_atom_site_type_symbol" in headers else None
        while index < len(lines):
            row = lines[index].strip()
            if (not row) or row.startswith(("_", "#", "loop_", "data_")):
                break
            parts = row.split()
            if len(parts) >= len(headers):
                try:
                    sites.append((number(parts[spots[0]]), number(parts[spots[1]]),
                                  number(parts[spots[2]]),
                                  parts[kind] if kind is not None else "X"))
                except ValueError:
                    pass
            index += 1
    return cell, sites


def build(cell, sites):
    """Tile the cell into a crystal and voxelize, which is the domain the instrument sees."""
    places = {}
    for tx in range(TILES):
        for ty in range(TILES):
            for tz in range(TILES):
                for fx, fy, fz, kind in sites:
                    x = (fx + tx) * cell["a"]
                    y = (fy + ty) * cell["b"]
                    z = (fz + tz) * cell["c"]
                    places[(int(x / VOXEL), int(y / VOXEL), int(z / VOXEL))] = kind
    return places


def recover_period(places, axis, limit):
    """Agreement between a point and the point `lag` voxels along one axis, swept over lag."""
    marks = []
    for lag in range(1, limit):
        hits = 0
        tried = 0
        for key, value in places.items():
            probe = list(key)
            probe[axis] += lag
            tried += 1
            if places.get(tuple(probe)) == value:
                hits += 1
        if tried:
            marks.append((hits / float(tried), lag))
    marks.sort(reverse=True)
    return marks


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", newline="")
    out.write("  %-12s %-9s %-11s %-11s %-8s %-10s %s\n"
              % ("mineral", "cod id", "published a", "true voxels", "top lag", "true frac",
                 "measured"))

    for index, name in enumerate(WANTED):
        if index:
            time.sleep(2.0)
        try:
            found = json.loads(fetch(SEARCH % (urllib.parse.quote(name), 6)))
        except Exception as trouble:
            out.write("  %-14s search failed: %s\n" % (name, str(trouble)[:40]))
            continue

        for entry in found:
            try:
                cell, sites = parse_cif(fetch(CIF % entry["file"]))
            except Exception:
                continue
            if (cell is None) or (len(sites) < 2):
                continue

            places = build(cell, sites)
            if len(places) < 2000:
                continue
            edge = int(round(cell["a"] / VOXEL))
            marks = recover_period(places, 0, min(edge * 2 + 6, 200))
            best = marks[0][1] if marks else -1

            # The cell edge is not a whole number of voxels, so the true period falls between two lags.
            # The share of agreement at the upper one should carry the fraction between them, which is
            # the quantization giving back what it appeared to discard
            exact = cell["a"] / VOXEL
            low = int(exact)
            table = {lag: share for share, lag in marks}
            below = table.get(low, 0.0)
            above = table.get(low + 1, 0.0)
            split = (above / (below + above)) if (below + above) > 0.0 else float("nan")
            out.write("  %-12s %-9s %-11.4f %-11.2f %-8d %-10.3f %.3f\n"
                      % (name, entry["file"], cell["a"], exact, best, exact - low, split))
            break

    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
