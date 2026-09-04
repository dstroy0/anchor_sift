#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Write the binary sound representation of every held recording.
#
#   Usage:  python tools/dev_env/Salishan/sound_representation/binary_sound.py [<stem> ...]
#
# Reads build/audio/ and writes build/sound/<stem>.bits.tsv, one row per 10 ms frame: the time, the
# segment field, and the prosody field. perceived_sound.py holds the method and says why it has the
# shape it has.
#
# What the run prints is the delta. The thresholds are cut so every bit splits the frames in half
# and the axes are rotated so no bit restates another, which is the sample brought to the highest
# entropy it can carry, with every state reachable. A recording that then used all of those states
# evenly would be noise. The gap between that reference and what the recording actually does is the
# structure in it, and it is measured with the same total variation and entropy the corpus work
# uses, out of anchor_sift.py.
#
# The support figure is what keeps the delta honest. A 24 bit field has 16.8 million states and a
# twenty minute recording has 135 thousand frames, so most states are unreachable at this sample
# size whatever the recording does. The delta against uniform is therefore near 1 on the wide field
# by construction, and the entropy against the field width is the reading to take.
#
# So the segment field is also reported at the narrow widths where its states are sampled. The bits
# come out of a rotation ordered by how much the recording varies along each axis, so the leading
# ones carry the most and a prefix of the field is the best code of that width. At 12 bits a
# recording of this length has 33 frames per state, and a delta measured there is a fact about the
# recording. At 24 it is a fact about the frame count.

import io
import os
import sys

import numpy
import soundfile

ROOT = os.path.abspath(__file__)
while (ROOT != os.path.dirname(ROOT)) and not os.path.isdir(os.path.join(ROOT, "build")):
    ROOT = os.path.dirname(ROOT)
AUDIO = os.path.join(ROOT, "build", "audio")
SOUND = os.path.join(ROOT, "build", "sound")
HERE = os.path.dirname(os.path.abspath(__file__))

sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "anchor_sift"))

from anchor_sift import entropy, support  # noqa: E402

from perceived_sound import PROSODY_BITS, SEGMENT_BITS, code_profile, represented  # noqa: E402

# The prefixes of the segment field the delta is also reported at. 6 bits is 64 states, which a
# four minute recording covers hundreds of times over, and 14 is where the state count passes the
# frame count on the shortest recording held.
WIDTHS = (6, 8, 10, 12, 14)


def mono(path):
    """One recording as a single channel of samples, and its rate.

    Averaged across channels. Two of the three held recordings are stereo and neither carries a
    different take on the two sides, so the average is the recording and not a mixdown of two.
    """
    samples, rate = soundfile.read(path, dtype="float64", always_2d=True)
    return samples.mean(axis=1), rate


def from_uniform(profile, width):
    """Total variation between an observed code distribution and the flat one over 2^width states.

    Written out instead of handed to anchor_sift.distance, because the reference has 2^width cells
    and building a dictionary that size to compare against costs more than the answer. The states
    nothing landed on each contribute their whole share of the flat distribution, which is the
    second term.
    """
    states = float(1 << width)
    flat = 1.0 / states
    run = sum(abs(one - flat) for one in profile.values())
    return (run + ((states - len(profile)) * flat)) / 2.0


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    wanted = sys.argv[1:]
    if not os.path.isdir(AUDIO):
        out.write("  no build/audio, fetch the recordings first\n")
        out.flush()
        return 1
    os.makedirs(SOUND, exist_ok=True)
    done = 0
    for name in sorted(os.listdir(AUDIO)):
        stem = os.path.splitext(name)[0]
        if wanted and (stem not in wanted):
            continue
        samples, rate = mono(os.path.join(AUDIO, name))
        at, segment, prosody = represented(samples, rate)
        path = os.path.join(SOUND, "%s.bits.tsv" % stem)
        with open(path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write("seconds\tsegment\tprosody\n")
            for row in range(len(at)):
                handle.write("%.3f\t%s\t%s\n"
                             % (at[row],
                                "".join(str(one) for one in segment[row]),
                                "".join(str(one) for one in prosody[row])))
        out.write("  %s\n" % stem)
        out.write("    %d Hz, %.1f s, %d frames\n" % (rate, len(samples) / float(rate), len(at)))
        for label, field, width in (("segment", segment, SEGMENT_BITS),
                                    ("prosody", prosody, PROSODY_BITS)):
            profile, total = code_profile(field)
            if not total:
                continue
            out.write("    %-8s %d bit field, %d of %d states used, H %.2f of %d, "
                      "%.4f from flat\n"
                      % (label, width, support(profile), 1 << width, entropy(profile), width,
                         from_uniform(profile, width)))
        # How evenly each bit on its own splits the frames. The thresholds are medians, so a column
        # that is not close to half is a column whose values are tied at the median.
        even = segment.mean(axis=0)
        out.write("    each segment bit is set on %.3f to %.3f of frames\n"
                  % (even.min(), even.max()))
        for width in WIDTHS:
            profile, total = code_profile(segment[:, :width])
            if not total:
                continue
            out.write("      segment at %2d bits, %5d of %6d states, %5.1f frames a state, "
                      "H %5.2f, %.4f from flat\n"
                      % (width, support(profile), 1 << width, total / float(1 << width),
                         entropy(profile), from_uniform(profile, width)))
        done += 1
    out.write("\n  %d recordings written to build/sound/\n" % done)
    out.flush()
    return 0 if done else 1


if __name__ == "__main__":
    raise SystemExit(main())
