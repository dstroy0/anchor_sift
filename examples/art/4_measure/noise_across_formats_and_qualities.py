#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: ART-4-006
#
# Fixed-pattern removal, held to the bit across image formats and across qualities of noise.
#
#   Usage:  python examples/art/4_measure/noise_across_formats_and_qualities.py
#
# ART-4-005 removed one fixed pattern from one 8x8 stack and reached 100% on a synthetic control. This
# widens that reading along the two axes a reader asks about next: does the format the pixels are
# stored in change the answer, and does the KIND of noise change it. Nothing here is a new instrument.
# The detector is measure.periodic_energy and the reject is reference.periodic, the same two files
# ART-4-005 used; this script only feeds them pixels from more places and noise of more kinds and
# reports what comes back. Every number is exact rational; the only floats are the %.3f in the prints.
#
# THE FORMAT AXIS. The detector reads points carrying values and cannot see a file format. The only way
# a format can matter is whether it preserves the values. A lossless format (PNG at any depth, a
# baseline TIFF, the CTC 16-bit TIFF) round-trips the stack bit for bit. The reading is identical to
# the one taken before it was written. A lossy format (JPEG) is itself a noise source: its block
# quantization depends on the local content. The same fixed pattern added to different frames decodes
# to a DIFFERENT pattern per frame, the per-pixel mean is no longer the pattern, and the removal can no
# longer reach the bit. The lossy row is not a failure of the instrument; it is the format injecting
# incoherent noise the instrument then correctly cannot scrub to zero.
#
# THE NOISE AXIS. The removal is exact for exactly one kind of noise: a coherent additive offset that
# repeats at the frame period, over a target that sums to zero at each pixel across the frames. This
# script shows the boundary of that case from both sides. Raising the pattern's amplitude does not
# change the 100% -- the arithmetic is exact at any amplitude -- but it does move the detector's margin
# above the drawn null, and a weak pattern fails to be SEEN, not to be removed. Incoherent noise of
# every kind -- independent per-frame Gaussian, impulses, Poisson shot --
# is declined: it carries no phase at the frame period, sits inside the null band, and is left intact.
# A mix of a fixed pattern and Gaussian is the realistic case and reports the coherent fraction, which
# is a measured number between the two, not 100%.
#
# THE CTC AXIS. Real 16-bit fluorescence frames from the Cell Tracking Challenge, read straight from the
# local zip in repos/external/datasets, cropped to a small tile so the exact-rational scan stays cheap.
# Two readings. The real tile as it is: the detector is asked whether a coherent fixed pattern is
# present, and on this footage it declines -- a real-world negative control, the 100% is not handed out
# for free. The real tile with a known fixed pattern added: the detector fires and removes it, but real
# content does NOT sum to zero per pixel. The per-pixel mean carries the scene's static background
# with the pattern and the residual is not the scene. The NRR is below 100% and the shortfall is the
# floor ART-4-005 named, shown here on real data instead of a constructed static feature.
#
# NOTHING IS BOUNDED HERE. Every declared input is a constant below, printed with the reading. Every
# decision to remove or decline is made against a null band drawn from the data by shuffling, never a
# threshold chosen here. The two mean routes, batch and incremental, are checked bit-exact against each
# other in every additive arm, and a deliberately broken third is run beside them so their agreement is
# shown to be a property the wrong route lacks. A native-C route is the natural hardening and is not
# claimed here.

import io
import os
import random
import sys
import zipfile

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke every path
# in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.periodic_energy import recover_period, null_band  # noqa: E402
from reference.periodic import (mean_background, mean_background_incremental,  # noqa: E402
                                mean_residual)
from reference.exact_ratio import (whole, add, sub, mul, over, compare,  # noqa: E402
                                   to_float, reduced)


def _external_datasets():
    """repos/external/datasets, resolved by walking up to the `repos` ancestor, not by counting.

    external/ is a sibling of owned/ under repos/, outside this repository, and this resolves it the
    same way maint/data/fetch/fetch_ctc.py does so it holds from the shared checkout and from a linked
    worktree alike, whose depth below repos/ differs.
    """
    node = ROOT
    while (node != os.path.dirname(node)) and (os.path.basename(node) != "repos"):
        node = os.path.dirname(node)
    return os.path.join(node, "external", "datasets")


# The declared inputs, printed with every reading and chosen by nothing the output showed.
HEIGHT = 8
WIDTH = 8
FRAMES = 48
SWING = 20            # the moving scene's amplitude at a pixel
PATTERN = 40         # the fixed pattern's amplitude, zero-mean across the frame
DRAWS = 8            # shuffles drawn to set the null band a real frame period must stand above
SEED = 0xF17A

# The Cell Tracking Challenge arm. The zip is already local; nothing is fetched here.
CTC_ZIP = os.path.join(_external_datasets(), "ctc_fluo_n2dh_simplus_training.zip")
CTC_TILE = 8          # a CTC_TILE x CTC_TILE crop from each real frame
CTC_FRAMES = 32
CTC_PATTERN = 900    # the fixed pattern added to the real tile, in 16-bit counts


def moving_scene(frame, frames, swing, seed):
    """A scene that sums to zero at every pixel across the frames, built from bounded pairs.

    Each pixel's values over the frames are a value and its negative. The pixel's mean across the
    stack is zero as an integer and every sample stays inside [-swing, swing]. A scene like this moves
    everywhere and sits still nowhere. It contributes nothing to the per-pixel mean and survives the
    rejection untouched.
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


def stacked(scene, pattern, frame):
    """The scene with the fixed pattern added into every frame."""
    return [scene[n] + pattern[n % frame] for n in range(len(scene))]


def per_frame_gaussian(scene, sigma, seed):
    """Independent additive noise at every position: the wrong quality of additive noise.

    Unlike a fixed pattern this does not repeat at the frame period. It carries no phase there and
    its per-pixel mean across the frames tends to zero. The detector should decline it and the mean
    route should leave it almost entirely intact.
    """
    rng = random.Random(seed)
    return [value + int(round(rng.gauss(0, sigma))) for value in scene]


def with_impulses(stack, count, swing, seed):
    """`count` positions replaced by a value from nowhere: replacement noise, the wrong kind entirely.

    Impulses are incoherent. The frame-period detector should decline them, not scrub them.
    """
    rng = random.Random(seed)
    out = list(stack)
    for _ in range(count):
        out[rng.randrange(len(out))] = rng.randint(-2 * swing, 2 * swing)
    return out


def poisson_shot(scene, pedestal, seed):
    """Signal-dependent shot noise: each intensity replaced by a Poisson draw about it.

    Incoherent and content-dependent. It carries no fixed phase and is declined. Built on the
    intensity domain by lifting the signed scene onto a pedestal, drawing, then lowering it back.
    """
    rng = random.Random(seed)
    out = []
    for value in scene:
        intensity = max(0, value + pedestal)
        out.append(_poisson(rng, intensity) - pedestal)
    return out


def _poisson(rng, mean):
    """One Poisson draw by Knuth's method, exact integer count, seeded off `rng` for reproducibility."""
    import math
    if mean <= 0:
        return 0
    limit = math.exp(-mean)
    count = 0
    product = 1.0
    while True:
        product *= rng.random()
        if product <= limit:
            return count
        count += 1


def broken_background(values, period):
    """A deliberately wrong per-pixel mean, to prove the two-route check can fail."""
    sums = [0] * period
    counts = [0] * period
    for index, value in enumerate(values):
        sums[index % period] += value
        counts[index % period] += 1
    means = [reduced(sums[phase], counts[phase] + 1) for phase in range(period)]
    return [means[index % period] for index in range(len(values))]


def reduction(noisy, cleaned, target):
    """The share of the injected noise energy the rejection removed, as an exact integer ratio pair."""
    injected = sum((noisy[n] - target[n]) ** 2 for n in range(len(target)))
    if injected == 0:
        return whole(1)
    left = whole(0)
    for n in range(len(target)):
        difference = sub(cleaned[n], whole(target[n]))
        left = add(left, mul(difference, difference))
    return sub(whole(1), over(left, whole(injected)))


def byte_view(values):
    """The values mapped linearly onto 0..255 for the detector and its shuffle-drawn null.

    reference.shuffles.permuted builds a bytearray. The null is drawn in the byte range whatever the
    depth of the data. The map preserves phase order, which is all the energy detector reads, and a
    coherent addend stays coherent under it. The removal never sees this view; it works on the true
    integers. The depth costs the measurement nothing.
    """
    low = min(values)
    high = max(values)
    if high == low:
        return [0] * len(values)
    span = high - low
    return [((value - low) * 255) // span for value in values]


def assess_additive(stack, scene, frame):
    """Run the detector and the additive reject on one stack, return every number a row prints.

    The detector reads the byte view and the drawn null band; the reject builds the per-pixel mean by
    two routes checked against each other and a broken third, removes it from the true integers, and the
    NRR is the exact share of injected energy removed. `present` is the decision, made only against the
    top of the null band and never a threshold set here.
    """
    view = byte_view(stack)
    found, live, dead = recover_period(view, frame)
    band = null_band(view, frame, DRAWS)
    boundary = band[-1] if band else None
    present = (live is not None) and (boundary is not None) and (compare(live, boundary) > 0)

    back_batch = mean_background(stack, frame)
    back_incr = mean_background_incremental(stack, frame)
    back_broken = broken_background(stack, frame)
    routes_agree = back_batch == back_incr
    broken_splits = (back_batch != back_broken) and (back_incr != back_broken)

    cleaned = mean_residual(stack, frame, back_batch)
    exact = all(cleaned[n] == whole(scene[n]) for n in range(len(scene)))
    removed = reduction(stack, cleaned, scene)
    return {
        "found": found, "live": live, "band": band, "boundary": boundary, "present": present,
        "routes_agree": routes_agree, "broken_splits": broken_splits,
        "cleaned": cleaned, "exact": exact, "removed": removed,
    }


def roundtrip(stack, frame, frames, depth, mode, fmt, pedestal, **save):
    """Write the stack to `fmt` at `depth`, read it back, return the recovered signed stack.

    The stack is lifted onto `pedestal` to fit the unsigned range the format stores, written frame by
    frame as a `mode` image, read back and lowered again. A lossless format returns the input exactly;
    a lossy one does not, and the caller compares to find out which.
    """
    recovered = []
    for step in range(frames):
        block = stack[step * frame:(step + 1) * frame]
        lifted = [value + pedestal for value in block]
        if mode == "RGB":
            arr = np.array(lifted, dtype=np.uint8).reshape(HEIGHT, WIDTH, 3)
        elif depth == 16:
            arr = np.array(lifted, dtype=np.uint16).reshape(HEIGHT, WIDTH)
        else:
            arr = np.array(lifted, dtype=np.uint8).reshape(HEIGHT, WIDTH)
        buffer = io.BytesIO()
        Image.fromarray(arr).save(buffer, format=fmt, **save)
        buffer.seek(0)
        back = np.asarray(Image.open(buffer))
        recovered.extend(int(value) - pedestal for value in back.reshape(-1).tolist())
    return recovered


def ctc_tile_stack(zip_path, tile, frames):
    """A small real tile read from `frames` frames of a CTC 16-bit sequence in the zip.

    Reads only the members it needs, never extracting the archive, and decodes each frame with PIL,
    which reads the LZW-compressed baseline TIFF the challenge ships without a codec add-on. Finds the
    first numbered sequence directory (`01/`, `02/`), takes its first `frames` `.tif` frames in order,
    and crops the same square from the center of each. Returns (stack, frame size, note); a None stack
    with a note is a clean decline the arm reports instead of crashing.
    """
    if not os.path.isfile(zip_path):
        return None, 0, "zip not present"
    try:
        with zipfile.ZipFile(zip_path) as archive:
            names = [name for name in archive.namelist()
                     if name.lower().endswith(".tif") and "/t" in name.lower()
                     and "_gt" not in name.lower() and "_st" not in name.lower()]
            names.sort()
            if len(names) < frames:
                return None, 0, "sequence shorter than %d frames" % frames
            stack = []
            for name in names[:frames]:
                image = np.asarray(Image.open(io.BytesIO(archive.read(name))))
                if image.ndim == 3:
                    image = image[image.shape[0] // 2]
                top = (image.shape[0] - tile) // 2
                left = (image.shape[1] - tile) // 2
                crop = image[top:top + tile, left:left + tile]
                stack.extend(int(value) for value in crop.reshape(-1).tolist())
    except Exception as trouble:
        return None, 0, "decode failed: %s" % trouble
    return stack, tile * tile, ""


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")

    gray_frame = HEIGHT * WIDTH
    scene = moving_scene(gray_frame, FRAMES, SWING, SEED)
    pattern = fixed_pattern(gray_frame, PATTERN, SEED)
    stack = stacked(scene, pattern, gray_frame)

    out.write("  fixed-pattern removal across formats and qualities of noise\n")
    out.write("  declared inputs: frame=%dx%d frames=%d swing=%d pattern=%d draws=%d seed=0x%X\n\n"
              % (HEIGHT, WIDTH, FRAMES, SWING, PATTERN, DRAWS, SEED))

    # ---- A. FORMATS. the same synthetic control, written to a format, read back, then measured. ----
    out.write("  A. FORMATS: the detector reads integers; a lossless format changes nothing and a\n")
    out.write("     lossy one is itself a noise source. round-trip is bit-exact where NRR stays 100.\n")
    out.write("  %-22s %-12s %-16s %-11s %s\n"
              % ("format", "depth", "round-trip", "NRR", "detector live / band top"))

    base = assess_additive(stack, scene, gray_frame)
    out.write("  %-22s %-12s %-16s %-11.4f%% %.3f / %.3f\n"
              % ("in-memory (no file)", "8-bit", "n/a (exact)", to_float(base["removed"]) * 100.0,
                 to_float(base["live"]), to_float(base["boundary"])))

    png8 = roundtrip(stack, gray_frame, FRAMES, 8, "L", "PNG", 128)
    _format_row(out, "PNG", "8-bit gray", png8, stack, scene, gray_frame)

    stack16 = [value * 300 for value in stack]
    scene16 = [value * 300 for value in scene]
    tiff16 = roundtrip(stack16, gray_frame, FRAMES, 16, "I;16", "TIFF", 32768)
    _format_row(out, "TIFF", "16-bit gray", tiff16, stack16, scene16, gray_frame)

    rgb_frame = HEIGHT * WIDTH * 3
    rgb_scene = moving_scene(rgb_frame, FRAMES, SWING, SEED)
    rgb_pattern = fixed_pattern(rgb_frame, PATTERN, SEED)
    rgb_stack = stacked(rgb_scene, rgb_pattern, rgb_frame)
    rgb = roundtrip(rgb_stack, rgb_frame, FRAMES, 8, "RGB", "PNG", 128)
    _format_row(out, "PNG", "8-bit RGB", rgb, rgb_stack, rgb_scene, rgb_frame)

    jpeg = roundtrip(stack, gray_frame, FRAMES, 8, "L", "JPEG", 128, quality=92)
    identical = jpeg == stack
    jarm = assess_additive(jpeg, scene, gray_frame)
    out.write("  %-22s %-12s %-16s %-11.4f%% %.3f / %.3f\n"
              % ("JPEG q92 (lossy)", "8-bit", "identical: %s" % identical,
                 to_float(jarm["removed"]) * 100.0,
                 to_float(jarm["live"]) if jarm["live"] is not None else float("nan"),
                 to_float(jarm["boundary"]) if jarm["boundary"] is not None else float("nan")))
    out.write("\n")

    # ---- B. NOISE QUALITIES. amplitude of the coherent pattern, then the incoherent kinds. ----
    out.write("  B. NOISE QUALITIES on 8-bit gray. exact removal is one kind of noise only.\n")
    out.write("  %-26s %-14s %-8s %s\n" % ("quality", "live / band", "seen?", "outcome"))

    for amplitude in (4, 8, 16, 32, 64):
        arm = stacked(scene, fixed_pattern(gray_frame, amplitude, SEED), gray_frame)
        got = assess_additive(arm, scene, gray_frame)
        seen = got["present"]
        outcome = ("remove -> NRR %.2f%%" % (to_float(got["removed"]) * 100.0)) if seen \
            else "decline -> below band (would remove exactly if seen)"
        out.write("  %-26s %-14s %-8s %s\n"
                  % ("fixed pattern amp=%d" % amplitude,
                     "%.2f / %.2f" % (to_float(got["live"]), to_float(got["boundary"])), seen, outcome))

    gauss = per_frame_gaussian(scene, PATTERN, SEED)
    _quality_row(out, "per-frame gaussian s=%d" % PATTERN, gauss, scene, gray_frame)
    impulses = with_impulses(scene, len(scene) // 12, SWING, SEED)
    _quality_row(out, "impulses (replacement)", impulses, scene, gray_frame)
    shot = poisson_shot(scene, 128, SEED)
    _quality_row(out, "poisson shot", shot, scene, gray_frame)

    mix = per_frame_gaussian(stack, PATTERN // 2, SEED)
    mixarm = assess_additive(mix, scene, gray_frame)
    out.write("  %-26s %-14s %-8s %s\n"
              % ("pattern + gaussian (mix)",
                 "%.2f / %.2f" % (to_float(mixarm["live"]), to_float(mixarm["boundary"])),
                 mixarm["present"], "remove coherent part -> NRR %.2f%% (measured, not 100)"
                 % (to_float(mixarm["removed"]) * 100.0)))
    out.write("\n")

    # ---- C. CTC real 16-bit frames. the negative control on real content, then the floor on it. ----
    out.write("  C. CTC real 16-bit TIFF tiles (%s)\n" % os.path.basename(CTC_ZIP))
    real, ctc_frame, note = ctc_tile_stack(CTC_ZIP, CTC_TILE, CTC_FRAMES)
    if real is None:
        out.write("  CTC arm not run: %s (looked in %s)\n\n" % (note, CTC_ZIP))
    else:
        out.write("  read %d frames, %dx%d tile, values in [%d, %d]\n"
                  % (CTC_FRAMES, CTC_TILE, CTC_TILE, min(real), max(real)))
        view = byte_view(real)
        _, live, _ = recover_period(view, ctc_frame)
        band = null_band(view, ctc_frame, DRAWS)
        seen = (live is not None) and bool(band) and (compare(live, band[-1]) > 0)
        out.write("  real as-is: detector live %.3f vs band top %.3f -> %s\n"
                  % (to_float(live) if live is not None else float("nan"),
                     to_float(band[-1]) if band else float("nan"),
                     "fixed pattern present" if seen else "declined (real-world negative control)"))
        real_stack = stacked(real, fixed_pattern(ctc_frame, CTC_PATTERN, SEED), ctc_frame)
        planted = assess_additive(real_stack, real, ctc_frame)
        out.write("  real + known pattern amp=%d: seen=%s, routes agree=%s, NRR %.4f%%\n"
                  % (CTC_PATTERN, planted["present"], planted["routes_agree"],
                     to_float(planted["removed"]) * 100.0))
        out.write("  the shortfall from 100 is the floor: real static background is a per-pixel offset\n")
        out.write("  across the stack, the exact shape of the pattern. It is removed with it.\n\n")

    out.write("  every removal above is exact rational, the per-pixel mean by two routes checked\n")
    out.write("  bit-exact, the decision drawn against a shuffle null. no float, no threshold.\n")
    out.flush()
    return 0 if (base["exact"] and base["routes_agree"] and base["broken_splits"]) else 1


def _format_row(out, fmt, depth, recovered, stack, scene, frame):
    """One FORMATS row: the round-trip's bit-identity and the NRR measured on what came back."""
    identical = recovered == stack
    arm = assess_additive(recovered, scene, frame)
    out.write("  %-22s %-12s %-16s %-11.4f%% %.3f / %.3f\n"
              % (fmt, depth, "identical: %s" % identical, to_float(arm["removed"]) * 100.0,
                 to_float(arm["live"]) if arm["live"] is not None else float("nan"),
                 to_float(arm["boundary"]) if arm["boundary"] is not None else float("nan")))


def _quality_row(out, label, arm_stack, scene, frame):
    """One NOISE-QUALITIES row for an incoherent kind: it should be declined and left intact."""
    got = assess_additive(arm_stack, scene, frame)
    seen = got["present"]
    outcome = ("seen -> NRR %.2f%%" % (to_float(got["removed"]) * 100.0)) if seen \
        else "decline -> left intact, NRR %.2f%%" % (to_float(got["removed"]) * 100.0)
    out.write("  %-26s %-14s %-8s %s\n"
              % (label, "%.2f / %.2f" % (to_float(got["live"]), to_float(got["boundary"])), seen, outcome))


if __name__ == "__main__":
    raise SystemExit(main())
