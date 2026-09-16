#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: ART-4-005
#
# Fixed-pattern video noise removed to the bit, by the same instrument the sound denoiser uses.
#
#   Usage:  python examples/art/4_measure/fixed_pattern_removed_to_the_bit.py
#
# Fixed-pattern noise is the coherent noise of a camera: a per-pixel offset the sensor adds to every
# frame, the same offset in the same place each time. Read a frame stack frame after frame and that
# offset repeats with a period of exactly one frame, so it is the coherent-addend case the sound
# denoiser handles, on a signal that happens to be pictures. Nothing here is ported from that file and
# nothing needs to be: reference.periodic and measure.periodic_energy read points carrying values and
# cannot tell a frame stack from a waveform. This is the README's one instrument, shown reading the
# second medium.
#
# The period is the frame size, which is the file's geometry and a declared input, not a fitted one.
# It is confirmed here anyway: measure.periodic_energy recovers it from the stack against a shuffle,
# the same way ART-4-001 recovers a still image's width. Once it is confirmed the fixed pattern is the
# per-pixel mean across frames, which reference.periodic builds, and the residual is the moving scene.
# Where the scene sums to zero at each pixel across the frames -- where the content moves and does not
# sit still anywhere -- the per-pixel mean IS the fixed pattern exactly, and the residual is the scene
# to the last bit.
#
# WHAT MAKES THE READING EVIDENCE, AND THE FLOOR
#
# Two routes build the per-pixel mean, batch and incremental, and a deliberately broken third is run
# beside them so their agreeing is shown to be a property the wrong one lacks. The null is drawn: the
# stack is shuffled, the frame period is gone, and removing at a wrong period takes nothing real.
#
# The floor is the honest limit of fixed-pattern correction and it is worth stating plainly, because
# it is why cameras need a dark frame or motion. A scene feature that never moves -- a pixel that is
# bright in every frame in the same place -- is indistinguishable from a fixed pattern, because both
# are a constant per-pixel offset across the stack. This removes it along with the noise, and the
# reduction falls by exactly the static feature's energy. That is not a defect. Noise shaped exactly
# like the signal is the one thing no instrument can reject, and a static object is signal shaped
# exactly like fixed-pattern noise.
#
# A native-C route is the natural hardening and is not claimed here.

import io
import os
import random
import sys
from fractions import Fraction

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.periodic_energy import recover_period, against_a_shuffle  # noqa: E402
from reference.periodic import (mean_background, mean_background_incremental,  # noqa: E402
                                mean_residual)
from reference.shuffles import permuted  # noqa: E402

# The declared inputs, printed with every reading and chosen by nothing the output showed.
HEIGHT = 8
WIDTH = 8
FRAMES = 48
SWING = 20           # the moving scene's amplitude at a pixel
PATTERN = 40         # the fixed pattern's amplitude, zero-mean across the frame
PEDESTAL = 128       # shifts the signed stack into the byte range for the detector's shuffle only
SEED = 0xF17A


def moving_scene(frame, frames, swing, seed):
    """A scene that sums to zero at every pixel across the frames, built from bounded pairs.

    Each pixel's values over the frames are a value and its negative, so the pixel's mean across the
    stack is zero as an integer and every sample stays inside [-swing, swing]. A scene like this moves
    everywhere and sits still nowhere, so it contributes nothing to the per-pixel mean and survives
    the rejection untouched.
    """
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


def with_static_feature(scene, frame, depth):
    """The scene with a pixel held bright in every frame, so it no longer sums to zero there.

    The floor case: a static feature is a constant per-pixel offset across the stack, which is exactly
    the shape of fixed-pattern noise, so it cannot be told apart and is removed with it.
    """
    shaped = list(scene)
    for step in range(len(shaped) // frame):
        shaped[step * frame + 0] += depth
    return shaped


def broken_background(values, period):
    """A deliberately wrong per-pixel mean, to prove the two-route check can fail."""
    sums = [0] * period
    counts = [0] * period
    for index, value in enumerate(values):
        sums[index % period] += value
        counts[index % period] += 1
    means = [Fraction(sums[phase], counts[phase] + 1) for phase in range(period)]
    return [means[index % period] for index in range(len(values))]


def reduction(noisy, cleaned, target):
    """The share of the injected noise energy the rejection removed, exact."""
    injected = sum((Fraction(noisy[n]) - target[n]) ** 2 for n in range(len(target)))
    left = sum((cleaned[n] - target[n]) ** 2 for n in range(len(target)))
    if injected == 0:
        return Fraction(1)
    return Fraction(1) - Fraction(left, 1) / injected


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    frame = HEIGHT * WIDTH
    scene = moving_scene(frame, FRAMES, SWING, SEED)
    pattern = fixed_pattern(frame, PATTERN, SEED)
    stack = [scene[n] + pattern[n % frame] for n in range(len(scene))]
    byte_view = [value + PEDESTAL for value in stack]
    if not all(0 <= value <= 255 for value in byte_view):
        out.write("control left the byte range; adjust SWING, PATTERN or PEDESTAL\n")
        out.flush()
        return 1

    out.write("  fixed-pattern video noise removed to the bit\n")
    out.write("  declared inputs: frame=%dx%d frames=%d swing=%d pattern=%d pedestal=%d seed=0x%X\n\n"
              % (HEIGHT, WIDTH, FRAMES, SWING, PATTERN, PEDESTAL, SEED))

    # 1. confirm the frame period against the drawn null (geometry declared, read back anyway)
    found, live, dead = recover_period(byte_view, frame)
    out.write("  identify: detector period %s (frame size %d)\n" % (found, frame))
    out.write("  identify: dispersion ratio live %.3f vs its own shuffle %.3f\n"
              % (float(live), float(dead)))

    # 2. reject with two routes that must be able to disagree
    back_batch = mean_background(stack, frame)
    back_incr = mean_background_incremental(stack, frame)
    back_broken = broken_background(stack, frame)
    routes_agree = back_batch == back_incr
    broken_splits = (back_batch != back_broken) and (back_incr != back_broken)
    out.write("  reject: batch and incremental routes agree bit-exact: %s\n" % routes_agree)
    out.write("  reject: the broken route splits from both (the check has teeth): %s\n" % broken_splits)

    cleaned = mean_residual(stack, frame, back_batch)
    exact = all(cleaned[n] == scene[n] for n in range(len(scene)))
    nrr = reduction(stack, cleaned, scene)
    out.write("  reject: residual equals the moving scene as integers: %s\n" % exact)
    out.write("  reject: noise reduction ratio %s = %.4f%%\n\n" % (nrr, float(nrr) * 100.0))

    # 3. the null
    shuffled = list(permuted(byte_view, SEED))
    null_found, null_live, null_dead = recover_period(shuffled, frame)
    out.write("  null: shuffled stack detector period %s live %.3f vs shuffle %.3f\n"
              % (null_found, float(null_live) if null_live is not None else float("nan"),
                 float(null_dead) if null_dead is not None else float("nan")))
    wrong = frame - 1
    wrong_cleaned = mean_residual(stack, wrong)
    wrong_nrr = reduction(stack, wrong_cleaned, scene)
    out.write("  null: rejecting at the wrong period %d reduces noise by %.4f%% (near zero)\n\n"
              % (wrong, float(wrong_nrr) * 100.0))

    # 4. the floor: a static scene feature is shaped exactly like fixed-pattern noise
    out.write("  floor: a static scene feature cannot be told from a fixed pattern\n")
    out.write("  %-10s %-14s %s\n" % ("depth", "reduction", "what the loss is"))
    for depth in (0, 5, 15, 30):
        shaped = with_static_feature(scene, frame, depth)
        dirty = [shaped[n] + pattern[n % frame] for n in range(len(shaped))]
        got = mean_residual(dirty, frame)
        floor_nrr = reduction(dirty, got, shaped)
        note = "full rejection" if depth == 0 else "a static feature, indistinguishable from the pattern"
        out.write("  %-10d %-14.4f %s\n" % (depth, float(floor_nrr) * 100.0, note))

    out.write("\n  depth zero is the full rejection: the scene moves everywhere, the pattern is fixed,\n")
    out.write("  so the pattern is removed to the bit and the scene is kept. every row below it is the\n")
    out.write("  reason a fixed-pattern correction needs a dark frame or motion: a thing that never\n")
    out.write("  moves is signal wearing the noise's exact shape, and no instrument separates those.\n")
    out.flush()
    return 0 if (routes_agree and broken_splits and exact) else 1


if __name__ == "__main__":
    raise SystemExit(main())
