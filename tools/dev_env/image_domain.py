#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Treat an image as a domain and recover its width without being told it is an image, for Section 4.11
# of docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/image_domain.py
#
# Section 4.2 holds the invariant across thirteen geometries and dimensions one to eight, so a picture is
# not an extension of this construction, it is the case the construction was written for: a domain whose
# alphabet is a range of values and whose arrangement is two dimensional.
#
# Reading a picture row by row leaves its second dimension as a periodicity, since a pixel and the pixel
# below it are one width apart in the sequence. So the shift detector should return the width of the
# image from the bytes alone, the same way Section 4.11 returns the record period of a fixed width file
# from 512 reads without being given a pattern. Two machine made controls are included: noise, which has
# no width to find, and a gradient, which has one and did not come from a person.

import io
import os
import random
import sys
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "corpora")
AGENT = {"User-Agent": "MMgr-research/1.0"}

WANTED = (
    ("art_hokusai", "The Great Wave off Kanagawa.jpg"),
    ("art_vermeer", "Johannes Vermeer (1632-1675) - The Girl With The Pearl Earring (1665).jpg"),
    ("art_starry", "Van Gogh - Starry Night - Google Art Project.jpg"),
)

SIDE = 512


def fetch(title, width):
    url = ("https://commons.wikimedia.org/wiki/Special:FilePath/"
           + urllib.parse.quote(title) + "?width=%d" % width)
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=180) as response:
        return response.read()


def agreement(data, lag):
    """Share of positions equal to the position one lag away, which is what a shift test reads."""
    if lag >= len(data):
        return 0.0
    hits = 0
    total = len(data) - lag
    for index in range(0, total, 7):
        if data[index] == data[index + lag]:
            hits += 1
    return hits / float(len(range(0, total, 7)))


def report(name, data, width):
    marks = []
    for lag in range(1, min(1200, len(data) // 4)):
        marks.append((agreement(data, lag), lag))
    marks.sort(reverse=True)
    best = marks[0]
    found = [lag for _, lag in marks[:8]]
    print("  %-14s %-8d %-9d %-9s %s"
          % (name, width, best[1], "%.4f" % best[0], " ".join(str(value) for value in found[:6])))


def main():
    from PIL import Image

    os.makedirs(OUT, exist_ok=True)
    print("  %-14s %-8s %-9s %-9s %s" % ("domain", "true w", "top lag", "agree", "top six lags"))

    for name, title in WANTED:
        try:
            blob = fetch(title, SIDE)
        except Exception as trouble:
            print("  %-14s could not fetch: %s" % (name, trouble))
            continue
        picture = Image.open(io.BytesIO(blob)).convert("L")
        width, height = picture.size
        data = picture.tobytes()
        with open(os.path.join(OUT, "%s.sym" % name), "wb") as handle:
            handle.write(data)
        report(name, data, width)

    rng = random.Random(0x1A9E)
    noise = bytes(rng.randrange(256) for _ in range(SIDE * SIDE))
    report("ctl_noise", noise, SIDE)

    gradient = bytearray()
    for row in range(SIDE):
        for column in range(SIDE):
            gradient.append((row + column) % 256)
    report("ctl_gradient", bytes(gradient), SIDE)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
