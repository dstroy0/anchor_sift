#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Fetch low frequency whale calls recorded for the purpose, as controls for Section 4.13 of
# docs/research/anchor-sift.md.
#
#   Usage:  python tools/dev_env/infrasound_domain.py
#
# The vocalizations measured earlier came from compressed archival audio, and a spectral check found the
# wolf recording carrying 99.92% of its energy above 200 Hz with nothing left below. That is not a
# sampling limit, since 48 kHz resolves 20 Hz easily. Microphones roll off at the low end and every
# psychoacoustic codec deletes what a person cannot hear, so a compressor tuned to human hearing removes
# the band where much animal communication happens.
#
# These are recorded for that band instead. They come from the NOAA PMEL Acoustics Program as uncompressed
# WAV, so no codec has been applied, and each is time compressed by the factor its name carries so that a
# call near 20 Hz lands somewhere audible. The speedup is undone here, since a measurement of arrangement
# should be taken against real time and not against a playback convenience.

import os
import re
import time
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "build", "corpora")
BASE = "https://www.pmel.noaa.gov/acoustics/whales/sounds/whalewav/%s"
AGENT = {"User-Agent": "MMgr-research/1.0 (https://github.com/dstroy0/MMgr; dquigg123@gmail.com)"}

WANTED = (
    ("infra_blue_nepacific", "nepblue24s10x.wav"),
    ("infra_blue_atlantic", "atlblue_512_64_0-50_10x.wav"),
    ("infra_fin_atlantic", "atlfin_128_64_0-50-FinWhaleAtlantic-10x.wav"),
    ("infra_blue_spacific", "etpb3_10xc-BlueWhaleSouthPacific-10x.wav"),
    ("infra_blue_west", "wblue26s10x.wav"),
    ("infra_52hz", "ak52_10x.wav"),
)

# One envelope symbol per this many milliseconds of real time, once the speedup is undone
WINDOW_MS = 100.0


def speedup(name):
    """The playback factor the file name carries, so real time can be recovered."""
    found = re.search(r"(\d+)x", name)
    return float(found.group(1)) if found else 1.0


def main():
    import av
    import numpy

    os.makedirs(OUT, exist_ok=True)
    scratch = os.path.join(OUT, "infra_scratch.wav")
    print("  %-22s %-7s %-11s %-9s %s" % ("corpus", "speedup", "true secs", "symbols", "levels"))

    for index, (name, filename) in enumerate(WANTED):
        if index:
            time.sleep(2.0)
        try:
            request = urllib.request.Request(BASE % filename, headers=AGENT)
            with urllib.request.urlopen(request, timeout=240) as response:
                blob = response.read()
        except Exception as trouble:
            print("  %-22s could not fetch: %s" % (name, str(trouble)[:60]))
            continue

        with open(scratch, "wb") as handle:
            handle.write(blob)
        try:
            container = av.open(scratch)
            stream = container.streams.audio[0]
            rate = stream.codec_context.sample_rate
            pieces = []
            for frame in container.decode(stream):
                pieces.append(frame.to_ndarray().reshape(-1).astype("float32"))
            container.close()
        except Exception as trouble:
            print("  %-22s could not decode: %s" % (name, str(trouble)[:60]))
            continue

        if not pieces:
            print("  %-22s no audio frames" % name)
            continue
        wave = numpy.concatenate(pieces)
        if wave.dtype.kind in "iu":
            wave = wave / 32768.0

        factor = speedup(filename)
        true_seconds = (len(wave) / float(rate)) * factor
        # A window of WINDOW_MS in real time is WINDOW_MS/factor in the file, since the file runs fast
        block = max(1, int(round(rate * (WINDOW_MS / 1000.0) / factor)))
        usable = (len(wave) // block) * block
        if usable < block * 200:
            print("  %-22s %-7.0f %-11.1f too short" % (name, factor, true_seconds))
            continue

        blocks = numpy.sqrt((wave[:usable].reshape(-1, block) ** 2).mean(axis=1))
        low = float(blocks.min())
        high = float(blocks.max())
        span = (high - low) or 1.0
        seated = numpy.clip(1 + 31 * (blocks - low) / span, 1, 32).astype("uint8")

        with open(os.path.join(OUT, "%s.sym" % name), "wb") as handle:
            handle.write(seated.tobytes())
        print("  %-22s %-7.0f %-11.1f %-9d %d"
              % (name, factor, true_seconds, len(seated), len(set(seated.tolist()))))

    if os.path.isfile(scratch):
        os.remove(scratch)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
