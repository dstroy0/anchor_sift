#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: ART-4-007
#
# Classify the noise on a stack of same-source images, reject it, and hand back the clean subject with
# the uncertainty stated exactly: zero where two exact routes agree, and flagged where they do not.
#
#   Usage:  python examples/art/4_measure/classify_reject_recover.py            the built-in controls
#           python examples/art/4_measure/classify_reject_recover.py --mode fixed-pattern --in DIR --out DIR
#           python examples/art/4_measure/classify_reject_recover.py --mode repeat --in DIR --out DIR
#
# This is the proofing filter. It reads a stack of same-source images laid one after another as a flat
# sequence whose period is the frame size, and a pixel and the same pixel one frame later fall in one
# phase class. The engine already reads that shape: measure.periodic_energy detects and
# reference.periodic rejects, the same files ART-4-005 and ART-4-006 use. A stack goes in; a verdict, a
# clean subject and an exact uncertainty come back. Every number is exact rational; the only floats are
# the printed ones.
#
# WHAT THE DATA CANNOT TELL YOU, AND YOU MUST DECLARE. A coherent per-pixel component across a stack is
# either the SUBJECT, when the subject is the same in every frame, or the NOISE, when the subject varies
# and a pattern is fixed. BOTH produce the same strong per-pixel mean, and no measurement on the stack
# separates them, because the split is which one you call signal. That is the caller's declaration, not
# the detector's finding. This filter takes a mode:
#   --mode fixed-pattern : the subject VARIES frame to frame; the shared per-pixel component is NOISE.
#                          Reject it by subtracting the per-pixel mean; each frame's residual is its own
#                          subject. Exact to the bit where the subject sums to zero at each pixel across
#                          the stack; the shortfall on real content is the floor, a static feature shaped
#                          exactly like the pattern.
#   --mode repeat        : the subject is the SAME in every frame; the shared component is the SUBJECT to
#                          KEEP. The noise is the per-frame deviation. Reject it by per-pixel consensus,
#                          exact where a strict majority survives; a class with no majority is the floor.
# Running fixed-pattern removal on a repeat erases the subject, and running consensus on a varying
# subject returns nothing any frame held. The mode is the guard against both, and there is no default
# that guesses it.
#
# THE UNCERTAINTY. Two independent exact routes are run for the reject. Where they land on the same
# integer the uncertainty at that pixel is exactly zero, because two different exact computations agree
# and nothing rounded. Where they differ the pixel is flagged and counted, and it is reported, never
# returned as if it were clean. NOTHING IS BOUNDED HERE: the fixed-pattern decision is the drawn null,
# and the repeat floor is the classes with no majority, neither a threshold chosen here.

import io
import os
import random
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke every path
# in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.periodic_energy import recover_period, null_band  # noqa: E402
from reference.periodic import (mean_background, mean_background_incremental,  # noqa: E402
                                mean_residual, consensus_majority, consensus_median)
from reference.exact_ratio import (whole, sub, mul, add, over, compare, to_float)  # noqa: E402

HEIGHT = 8
WIDTH = 8
FRAMES = 48
SWING = 20
PATTERN = 40
DRAWS = 8
SEED = 0xF17A


def byte_view(values):
    """The values mapped linearly onto 0..255 for the detector and its shuffle-drawn null.

    reference.shuffles.permuted builds a bytearray. The null is drawn in the byte range whatever the
    depth of the data. The map preserves phase order, which is all the energy detector reads. The reject
    never sees this view; it works on the true integers. The depth costs the recovery nothing.
    """
    low = min(values)
    high = max(values)
    if high == low:
        return [0] * len(values)
    span = high - low
    return [((value - low) * 255) // span for value in values]


def moving_scene(frame, frames, swing, seed):
    """A subject that sums to zero at each pixel across the frames, built from bounded pairs."""
    rng = random.Random(seed)
    length = frame * frames
    scene = [0] * length
    half = frames // 2
    for pixel in range(frame):
        members = [rng.randint(1, swing) for _ in range(half)]
        members = members + [-value for value in members]
        if frames % 2:
            members.append(0)
        rng.shuffle(members)
        for step, value in enumerate(members):
            scene[pixel + step * frame] = value
    return scene


def fixed_pattern(frame, amplitude, seed):
    """One offset per pixel, zero-mean across the frame, the same in every frame of the stack."""
    rng = random.Random(seed ^ 0x5A5A)
    pattern = [rng.randint(-amplitude, amplitude) for _ in range(frame)]
    shift = sum(pattern) // frame
    return [value - shift for value in pattern]


def repeating_subject(frame, frames, seed):
    """One image held identical in every frame: the case --mode repeat is written for."""
    rng = random.Random(seed)
    one = [rng.randint(0, 200) for _ in range(frame)]
    return [one[index % frame] for index in range(frame * frames)], one


def with_impulses(stack, count, seed):
    """`count` positions replaced by a value from nowhere: replacement noise."""
    rng = random.Random(seed)
    out = list(stack)
    for _ in range(count):
        out[rng.randrange(len(out))] = rng.randint(0, 255)
    return out


def per_frame_noise(base, sigma, seed):
    """Independent additive noise at every position: incoherent, no phase at the frame period."""
    rng = random.Random(seed)
    return [value + int(round(rng.gauss(0, sigma))) for value in base]


def reduction(noisy, cleaned, target):
    """The share of the injected noise energy the reject removed, as an exact integer ratio pair."""
    injected = sum((noisy[n] - target[n]) ** 2 for n in range(len(target)))
    if injected == 0:
        return whole(1)
    left = whole(0)
    for n in range(len(target)):
        difference = sub(cleaned[n], whole(target[n]))
        left = add(left, mul(difference, difference))
    return sub(whole(1), over(left, whole(injected)))


def detect_fixed_pattern(stack, frame):
    """Whether a coherent component stands at the frame period above the drawn null band."""
    view = byte_view(stack)
    period, live, dead = recover_period(view, frame)
    band = null_band(view, frame, DRAWS)
    top = band[-1] if band else None
    present = (period == frame) and (live is not None) and (top is not None) and (compare(live, top) > 0)
    return present, live, top


def reject_fixed_pattern(stack, frame):
    """Subtract the shared per-pixel mean; return the per-frame subjects and the exact uncertainty.

    Two routes build the mean, batch and incremental. The uncertainty at a pixel is zero where they
    agree, and for the mean they agree everywhere; a nonzero count here would be a defect in one route,
    not a property of the data. The clean subject is each frame's residual.
    """
    batch = mean_background(stack, frame)
    incr = mean_background_incremental(stack, frame)
    cleaned = mean_residual(stack, frame, batch)
    uncertain = [1 if batch[index] != incr[index] else 0 for index in range(frame)]
    return cleaned, batch, uncertain


def reject_repeat(stack, frame):
    """Keep the per-pixel consensus subject; flag the classes with no majority as the floor.

    Two routes build the consensus, greatest count and median. Where they agree the value has a strict
    majority of the frames behind it and the recovery is exact; where they differ the class has no
    majority. That class is the floor, and it is flagged, not returned as clean.
    """
    by_count = consensus_majority(stack, frame)[:frame]
    by_median = consensus_median(stack, frame)[:frame]
    uncertain = [1 if by_count[index] != by_median[index] else 0 for index in range(frame)]
    return by_count, uncertain


def report_control(out, label, mode, stack, frame, truth):
    """Run one built-in control in the given mode and state classification, recovery and uncertainty."""
    if mode == "fixed-pattern":
        present, live, top = detect_fixed_pattern(stack, frame)
        out.write("  %-26s mode fixed-pattern: coherent component present: %s (live %.2f / band %.2f)\n"
                  % (label, present, to_float(live) if live is not None else float("nan"),
                     to_float(top) if top is not None else float("nan")))
        if not present:
            out.write("  %-26s declined: no fixed pattern above the null; uncertainty is not zero.\n\n" % "")
            return
        cleaned, pattern, uncertain = reject_fixed_pattern(stack, frame)
        exact = all(cleaned[n] == whole(truth[n]) for n in range(len(truth)))
        nrr = reduction(stack, cleaned, truth)
        out.write("  %-26s reject per-pixel mean -> subject == truth bit-exact: %s, NRR %.4f%%\n"
                  % ("", exact, to_float(nrr) * 100.0))
        out.write("  %-26s uncertainty: %d of %d pixels flagged (%s)\n\n"
                  % ("", sum(uncertain), frame,
                     "exact zero everywhere" if sum(uncertain) == 0 else "route defect"))
        return

    # repeat
    cleaned, uncertain = reject_repeat(stack, frame)
    flagged = sum(uncertain)
    resolved = [cleaned[i] for i in range(frame) if not uncertain[i]]
    truth_resolved = [truth[i] for i in range(frame) if not uncertain[i]]
    exact_where_resolved = resolved == truth_resolved
    out.write("  %-26s mode repeat: subject by per-pixel consensus\n" % label)
    out.write("  %-26s exact where a strict majority survives: %s; %d of %d pixels flagged (the floor)\n\n"
              % ("", exact_where_resolved, flagged, frame))


def run_controls(out):
    """Both modes, each on the stack it is written for and on a stack that exposes its boundary."""
    out.write("  classify -> reject -> clean subject, uncertainty stated exactly\n")
    out.write("  declared inputs: frame=%dx%d frames=%d seed=0x%X draws=%d\n\n"
              % (HEIGHT, WIDTH, FRAMES, SEED, DRAWS))
    frame = HEIGHT * WIDTH

    scene = moving_scene(frame, FRAMES, SWING, SEED)
    pattern = fixed_pattern(frame, PATTERN, SEED)
    additive = [scene[n] + pattern[n % frame] for n in range(len(scene))]
    truth_scene = [scene[n] for n in range(len(scene))]
    report_control(out, "fixed pattern, varies", "fixed-pattern", additive, frame, truth_scene)

    gaussian_vary = per_frame_noise(scene, PATTERN, SEED)
    report_control(out, "incoherent, varies", "fixed-pattern", gaussian_vary, frame,
                   [scene[n] for n in range(len(scene))])

    subject_stack, one = repeating_subject(frame, FRAMES, SEED)
    impulses = with_impulses(subject_stack, len(subject_stack) // 10, SEED)
    report_control(out, "impulses on a repeat", "repeat", impulses, frame, one)

    gaussian_repeat = per_frame_noise(subject_stack, 12, SEED)
    report_control(out, "incoherent on a repeat", "repeat", gaussian_repeat, frame, one)

    out.write("  fixed-pattern removes a shared pattern from a varying subject to the bit and declines\n")
    out.write("  incoherent noise. repeat keeps a shared subject and recovers it exactly where a majority\n")
    out.write("  survives, flagging the rest. neither mode guesses which the shared component is.\n")


def load_stack(in_dir):
    """A same-size stack from a directory of images, flattened one frame after another."""
    import numpy as np
    from PIL import Image
    names = sorted(name for name in os.listdir(in_dir)
                   if name.lower().endswith((".png", ".tif", ".tiff", ".pgm")))
    if len(names) < 3:
        return None, 0, 0, None, "fewer than three images"
    sizes = set()
    frames = []
    for name in names:
        image = np.asarray(Image.open(os.path.join(in_dir, name)).convert("L"))
        sizes.add(image.shape)
        frames.append([int(value) for value in image.reshape(-1).tolist()])
    if len(sizes) != 1:
        return None, 0, 0, None, "images are not one size. The stack is not registered: %s" % sorted(sizes)
    height, width = sizes.pop()
    stack = []
    for frame in frames:
        stack.extend(frame)
    return stack, width * height, len(names), (height, width), ""


def run_real(out, mode, in_dir, out_dir):
    """Apply the filter to a real same-size stack in the declared mode, writing outputs and a map."""
    import numpy as np
    from PIL import Image
    stack, frame, count, shape, why = load_stack(in_dir)
    if stack is None:
        out.write("  stack not usable: %s\n" % why)
        out.write("  register the pages to one size first; translation alone cannot absorb a scale drift,\n")
        out.write("  and scale and rotation registration are design-only today.\n")
        return 1
    height, width = shape
    os.makedirs(out_dir, exist_ok=True)
    if mode == "fixed-pattern":
        present, live, top = detect_fixed_pattern(stack, frame)
        out.write("  %d frames, %dx%d, mode fixed-pattern: pattern present: %s (live %.2f / band %.2f)\n"
                  % (count, width, height, present,
                     to_float(live) if live is not None else float("nan"),
                     to_float(top) if top is not None else float("nan")))
        if not present:
            out.write("  declined: no fixed pattern above the null. nothing removed, and that is the finding.\n")
            return 0
        cleaned, pattern, uncertain = reject_fixed_pattern(stack, frame)
        low = min(v[0] // v[1] for v in cleaned)
        for index in range(count):
            block = cleaned[index * frame:(index + 1) * frame]
            arr = np.array([(v[0] // v[1]) - low for v in block], dtype=np.uint16).reshape(height, width)
            Image.fromarray(arr).save(os.path.join(out_dir, "clean_%03d.png" % index))
        plow = min(v[0] // v[1] for v in pattern)
        parr = np.array([(v[0] // v[1]) - plow for v in pattern[:frame]], dtype=np.uint16).reshape(height, width)
        Image.fromarray(parr).save(os.path.join(out_dir, "shared_pattern.png"))
        out.write("  wrote clean_000..%03d.png and shared_pattern.png; %d of %d pixels flagged\n"
                  % (count - 1, sum(uncertain), frame))
        return 0

    cleaned, uncertain = reject_repeat(stack, frame)
    arr = np.array([int(v) for v in cleaned], dtype=np.uint8).reshape(height, width)
    Image.fromarray(arr).save(os.path.join(out_dir, "consensus.png"))
    umap = np.array([255 if flag else 0 for flag in uncertain], dtype=np.uint8).reshape(height, width)
    Image.fromarray(umap).save(os.path.join(out_dir, "uncertainty.png"))
    out.write("  %d frames, %dx%d, mode repeat: consensus.png written; %d of %d pixels flagged (floor)\n"
              % (count, width, height, sum(uncertain), frame))
    return 0


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    argv = sys.argv[1:]
    mode = in_dir = out_dir = None
    for index, token in enumerate(argv):
        if token == "--mode" and index + 1 < len(argv):
            mode = argv[index + 1]
        if token == "--in" and index + 1 < len(argv):
            in_dir = argv[index + 1]
        if token == "--out" and index + 1 < len(argv):
            out_dir = argv[index + 1]
    if in_dir and out_dir:
        if mode not in ("fixed-pattern", "repeat"):
            out.write("  --mode must be fixed-pattern or repeat: the data cannot tell which the shared\n")
            out.write("  component is. You declare it. See the header.\n")
            out.flush()
            return 2
        code = run_real(out, mode, in_dir, out_dir)
        out.flush()
        return code
    run_controls(out)
    out.flush()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
