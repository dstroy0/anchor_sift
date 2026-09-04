#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch animal and human vocalizations as symbol sequences, as controls for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/vocalization_domain.py
#
# The permutation null separates every human corpus measured here from every memoryless one, and a
# structured domain under no selection, the gaps between primes, departs from it by 0.07 where human text
# departs by 0.22 to 0.68. That leaves a gap in the middle that nothing has occupied.
#
# A vocalization sits in it. Bird song and whale song are produced under selection, carry structure, and
# were not made by a person. If the measure is reading communication under selection they should fall
# between the primes and the human corpora. If it reads only arrangement they need not.
#
# The treatment matches the one given to pictures: quantize the values, read the sequence, and let the
# measure see a domain and not a recording. Audio is decoded to 8 kHz mono at one byte a sample, so
# consecutive samples are far enough apart in time that the waveform's own smoothness does not stand for
# all of the structure.

import os
import subprocess
import time
import sys
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "corpora")
AGENT = {"User-Agent": "MMgr-research/1.0 (https://github.com/dstroy0/MMgr; dquigg123@gmail.com)"}

WANTED = (
    ("voc_bird_sparrow", "Arremon abeillei - Black-capped Sparrow XC250490.mp3"),
    ("voc_whale_humpback",
     "Humpback-Whale-Song-and-Foraging-Behavior-on-an-Antarctic-Feeding-Ground-pone.0051214.s001.oga"),
    ("voc_wolf_howl", "Wolf howls.ogg"),
    ("voc_birds_dawn", "Bourne woods 2020-05-31 0823.mp3"),
    # The control the animal rows cannot be read without: a human voice through the same pipeline, so
    # the smoothness every waveform carries is present in both sides of the comparison
    ("voc_human_speech", "Bone Wars spoken Wikipedia article (English).ogg"),
    ("voc_human_speech2", "Angelo Fabroni (Spoken Wikipedia, English).ogg"),
    # A dawn chorus is many birds at once, so the human side of that comparison has to be many people at
    # once as well. One person alone in a studio is the wrong control for it.
    ("voc_human_crowd", "Shopping mall less crowded.ogg"),
    ("voc_human_crowd2", "1 minute at the alexa mall in berlin.ogg"),
    ("voc_human_market", "Flea market in the rain.ogg"),
)

RATE = 8000
FLOOR = 90000


def fetch(title):
    url = "https://commons.wikimedia.org/wiki/Special:FilePath/" + urllib.parse.quote(title)
    request = urllib.request.Request(url, headers=AGENT)
    with urllib.request.urlopen(request, timeout=240) as response:
        return response.read()


def to_samples(blob, scratch):
    """Decode a container to unsigned 8 bit mono near RATE.

    Channels are averaged and the result is decimated by averaging whole blocks, which lowpasses before
    it decimates. Taking every nth sample instead would alias the high frequencies of a bird call down
    into the band being measured, and a measurement of arrangement would then be reading the aliasing.
    """
    import av
    import numpy

    with open(scratch, "wb") as handle:
        handle.write(blob)
    try:
        # PyAV carries its own decoders, which matters because these files arrive in several containers
        # and one of them wraps Vorbis in an Ogg Skeleton that libsndfile declines to open
        container = av.open(scratch)
        stream = container.streams.audio[0]
        resampler = av.AudioResampler(format="s16", layout="mono", rate=RATE)
        pieces = []
        for frame in container.decode(stream):
            for converted in resampler.resample(frame):
                pieces.append(converted.to_ndarray().reshape(-1))
        for converted in resampler.resample(None):
            pieces.append(converted.to_ndarray().reshape(-1))
        container.close()
    except Exception as trouble:
        return None, str(trouble)[:120]

    if not pieces:
        return None, "no audio frames"
    blocks = numpy.concatenate(pieces).astype("float32") / 32768.0

    # Scaled to the range actually used, so a quiet recording is not squeezed into a handful of levels
    span = float(max(abs(blocks.max()), abs(blocks.min())) or 1.0)
    scaled = numpy.clip(((blocks / span) * 127.0 + 128.0), 1, 255).astype("uint8")
    return scaled.tobytes(), ""


def main():
    os.makedirs(OUT, exist_ok=True)

    scratch = os.path.join(OUT, "voc_scratch.bin")

    for index, (name, title) in enumerate(WANTED):
        # Commons rate limits an impolite caller, and spacing the requests is the cheap way to comply
        if index:
            time.sleep(4.0)
        try:
            blob = fetch(title)
        except Exception as trouble:
            print("  %-22s could not fetch: %s" % (name, trouble))
            continue
        samples, complaint = to_samples(blob, scratch)
        if samples is None or len(samples) < FLOOR:
            print("  %-22s %d bytes fetched, decoded to %s samples. %s"
                  % (name, len(blob), "0" if samples is None else len(samples), complaint))
            continue
        # Seated away from zero to match every other corpus here
        seated = bytearray(samples)
        with open(os.path.join(OUT, "%s.sym" % name), "wb") as handle:
            handle.write(seated)
        print("  %-22s %d samples at %d Hz, %d distinct levels"
              % (name, len(seated), RATE, len(set(seated))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
