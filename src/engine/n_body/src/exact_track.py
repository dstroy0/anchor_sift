#!/usr/bin/env python3
"""Cell tracking in exact arithmetic: integer field, integer basins, rational motion, integer score.

Usage:
    python src/exact_track.py grade --root <volumes> --sample <sample> --frame 12
    python src/exact_track.py arc-truth --limit 200
    python src/exact_track.py score --limit 25 --frames 40
    python src/exact_track.py score --limit 25 --frames 40 --control

Build the engine first:
    bash engine/build_engine.sh

NO FLOATING POINT VALUE IS FORMED HERE AND NUMPY IS NOT IMPORTED. The volume is decoded by zarr and
handed to the engine as its raw bytes. Everything the engine returns is an integer: limbs, counts,
index sums, peak indices, adjacency pairs. Positions are Fractions built from those integers, motion
is Fraction arithmetic, rounding to a voxel is floor division, and every comparison is exact.

LENGTH IS COUNTED IN ONE UNIT. A y or x voxel is 13/32 um and a z voxel is 13/8 um, four times as
long, so the unit is the y voxel and a z step counts four. Squared distance is 16 dz^2 + dy^2 + dx^2
in that unit, an integer or a Fraction, and the common factor (13/32)^2 is left off because it
orders nothing differently.

Subcommands and their flags:

    grade       the CUDA engine against the portable C11 reference on one or more frames; every
                output must be equal
        --root --split --sample --frame --frames
    arc-truth   motion predictors against the answer key alone, in exact arithmetic
        --root --split --limit
    score       detect, link and score over labelled samples
        --root --split --sample --limit --frames --control --engine

    --root      directory holding train/ and test/ (default: this repository)
    --split     train or test (default train)
    --sample    sample name prefix
    --limit     how many samples in name order (default 3)
    --frame     one frame to grade (default 40)
    --frames    grade: comma separated frames; score: frames below this index the key reaches
                (default 40)
    --control   online linker only: reverse every prediction, the control on its motion
    --engine    device or host, which engine computes the basins and overlaps (default device)
    --view-motion  remove: measure the view's own motion between consecutive frames over every lag
                with exact number theoretic transforms (engine/shift_agreement) and compare frame t's
                voxel v with frame t+1's voxel v + lag. keep: compare voxel v with voxel v.
                (default remove)
    --linker    culminate: feed every frame, accumulate exact basin overlap between consecutive
                frames, and read the chains once at the end as the heaviest one-to-one matching of
                accumulated overlap; scored for every object and for the set held to the sample's
                published cell count per frame, ranked by the overlap its chain carries.
                online: the earlier per-frame linker with fitted motion and neighbour flow, kept
                only as the baseline it is measured against. (default culminate)
"""

import argparse
import ctypes
import math
import os
import sys
import time
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

LIMBS = 9

# Voxel extents in micrometres, exact.
VOXEL_UM = (Fraction(13, 8), Fraction(13, 32), Fraction(13, 32))

# Scale of each axis in the common unit, the y voxel.
AXIS_UNITS = (4, 1, 1)

# The two smoothing scales in micrometres, exact. Chosen scales, the same two the earlier residual
# used, and named here as the choices they are.
SMOOTH_UM = Fraction(6, 5)
BACKGROUND_UM = Fraction(2)


def binomial_order(scale_um, voxel_um):
    """The even binomial order whose variance n/4 voxels^2 lies nearest (scale/voxel)^2, exactly."""
    target = 4 * (scale_um / voxel_um) ** 2
    return 2 * math.floor(target / 2 + Fraction(1, 2))


SMOOTH_ORDERS = tuple(binomial_order(SMOOTH_UM, voxel) for voxel in VOXEL_UM)
BACKGROUND_ORDERS = tuple(binomial_order(BACKGROUND_UM, voxel) for voxel in VOXEL_UM)


class BinomialBasinsRequest(ctypes.Structure):
    """Laid out to match BinomialBasinsRequest in engine/binomial_basins.h."""
    _fields_ = [
        ("volume", ctypes.POINTER(ctypes.c_ushort)),
        ("depth", ctypes.c_uint),
        ("height", ctypes.c_uint),
        ("width", ctypes.c_uint),
        ("smooth_orders", ctypes.c_uint * 3),
        ("background_orders", ctypes.c_uint * 3),
        ("room", ctypes.c_uint),
        ("peak_indices", ctypes.POINTER(ctypes.c_uint)),
        ("sizes", ctypes.POINTER(ctypes.c_uint)),
        ("sums", ctypes.POINTER(ctypes.c_ulonglong)),
        ("peak_limbs", ctypes.POINTER(ctypes.c_uint)),
        ("adjacency_room", ctypes.c_uint),
        ("adjacency", ctypes.POINTER(ctypes.c_uint)),
        ("adjacency_count", ctypes.POINTER(ctypes.c_uint)),
        ("labels", ctypes.POINTER(ctypes.c_uint)),
        ("residual_limbs", ctypes.POINTER(ctypes.c_uint)),
        ("positive_words", ctypes.POINTER(ctypes.c_ulonglong)),
        ("joined_room", ctypes.c_uint),
        ("joined", ctypes.POINTER(ctypes.c_uint)),
        ("joined_count", ctypes.POINTER(ctypes.c_uint)),
    ]


class BasinOverlapRequest(ctypes.Structure):
    """Laid out to match BasinOverlapRequest in engine/basin_overlap.h."""
    _fields_ = [
        ("labels_before", ctypes.POINTER(ctypes.c_uint)),
        ("positive_before", ctypes.POINTER(ctypes.c_ulonglong)),
        ("labels_after", ctypes.POINTER(ctypes.c_uint)),
        ("positive_after", ctypes.POINTER(ctypes.c_ulonglong)),
        ("axes", ctypes.c_uint),
        ("extents", ctypes.c_uint * 8),
        ("lag", ctypes.c_int * 8),
        ("voxels", ctypes.c_uint),
        ("room", ctypes.c_uint),
        ("peaks_before", ctypes.POINTER(ctypes.c_uint)),
        ("peaks_after", ctypes.POINTER(ctypes.c_uint)),
        ("counts", ctypes.POINTER(ctypes.c_uint)),
    ]


_library = None


def engine():
    """The engine library, loaded once."""
    global _library
    if _library is None:
        name = "cell_tracking_engine.dll" if sys.platform == "win32" else "libcell_tracking_engine.so"
        path = os.path.join(ROOT, "build", name)
        if not os.path.isfile(path):
            raise RuntimeError("%s is not built; run bash engine/build_engine.sh" % path)
        if sys.platform == "win32" and os.environ.get("CUDA_PATH"):
            for sub in ("bin", os.path.join("bin", "x64")):
                folder = os.path.join(os.environ["CUDA_PATH"], sub)
                if os.path.isdir(folder):
                    os.add_dll_directory(folder)
        _library = ctypes.CDLL(path)
        for entry in (_library.binomial_basins_run, _library.binomial_basins_host):
            entry.argtypes = [ctypes.POINTER(BinomialBasinsRequest)]
            entry.restype = ctypes.c_long
        for entry in (_library.basin_overlap_run, _library.basin_overlap_host):
            entry.argtypes = [ctypes.POINTER(BasinOverlapRequest)]
            entry.restype = ctypes.c_long
    return _library


class ShiftAgreementRequest(ctypes.Structure):
    """Laid out to match ShiftAgreementRequest in engine/shift_agreement.h."""
    _fields_ = [
        ("axes", ctypes.c_uint),
        ("extents", ctypes.c_uint * 8),
        ("weights", ctypes.c_uint * 8),
        ("before", ctypes.POINTER(ctypes.c_ulonglong)),
        ("after", ctypes.POINTER(ctypes.c_ulonglong)),
        ("lag", ctypes.c_int * 8),
        ("agreement", ctypes.c_uint),
        ("padded", ctypes.c_uint * 8),
        ("counts", ctypes.POINTER(ctypes.c_uint)),
    ]


def agreement_counts(before_words, after_words, extents, weights, on_device):
    """(lag, agreement, counts, padded) for two bit packed views, counts over every padded lag."""
    library = engine()
    entry = library.shift_agreement_run if on_device else library.shift_agreement_host
    entry.argtypes = [ctypes.POINTER(ShiftAgreementRequest)]
    entry.restype = ctypes.c_long
    padded = []
    for extent in extents:
        power = 1
        while power < 2 * extent - 1:
            power *= 2
        padded.append(power)
    total = 1
    for power in padded:
        total *= power
    counts = (ctypes.c_uint * total)()
    request = ShiftAgreementRequest()
    request.axes = len(extents)
    for axis, extent in enumerate(extents):
        request.extents[axis] = extent
        request.weights[axis] = weights[axis]
    request.before = before_words
    request.after = after_words
    request.counts = counts
    if entry(ctypes.byref(request)) != 0:
        raise RuntimeError("the engine refused the shift agreement")
    return (tuple(request.lag[axis] for axis in range(len(extents))), request.agreement, list(counts),
            tuple(padded))


def check_agreement_by_brute_force(trials=6):
    """Both engines against a direct count at every lag, on small random views. True when all agree."""
    import random
    generator = random.Random(20260916)
    for trial in range(trials):
        axes = 1 + trial % 3
        extents = tuple(generator.randint(2, 7) for _ in range(axes))
        weights = tuple(generator.randint(1, 5) for _ in range(axes))
        voxels = 1
        for extent in extents:
            voxels *= extent
        before_bits = [generator.random() < 0.4 for _ in range(voxels)]
        after_bits = [generator.random() < 0.4 for _ in range(voxels)]

        def pack(bits):
            words = (ctypes.c_ulonglong * ((voxels + 63) // 64))()
            for position, bit in enumerate(bits):
                if bit:
                    words[position // 64] |= 1 << (position % 64)
            return words

        def coordinates(position):
            result = []
            for extent in reversed(extents):
                result.append(position % extent)
                position //= extent
            return tuple(reversed(result))

        results = [agreement_counts(pack(before_bits), pack(after_bits), extents, weights, device)
                   for device in (True, False)]
        if results[0] != results[1]:
            return False
        _, _, counts, padded = results[0]
        for index in range(len(counts)):
            rest = index
            lag = []
            for size in reversed(padded):
                coordinate = rest % size
                rest //= size
                lag.append(coordinate if coordinate < size // 2 else coordinate - size)
            lag = tuple(reversed(lag))
            direct = 0
            for position in range(voxels):
                if not before_bits[position]:
                    continue
                moved = tuple(value + step for value, step in zip(coordinates(position), lag))
                if all(0 <= value < extent for value, extent in zip(moved, extents)):
                    flat = 0
                    for value, extent in zip(moved, extents):
                        flat = flat * extent + value
                    direct += 1 if after_bits[flat] else 0
            if direct != counts[index]:
                return False
    return True


def view_motion(before, after, shape, on_device):
    """(lag, agreement): the view's own motion from one frame to the next, and how many positive
    voxels agree at it, over every lag at once. The lag is in voxels per axis, z y x."""
    library = engine()
    entry = library.shift_agreement_run if on_device else library.shift_agreement_host
    entry.argtypes = [ctypes.POINTER(ShiftAgreementRequest)]
    entry.restype = ctypes.c_long
    request = ShiftAgreementRequest()
    request.axes = len(shape)
    for axis, extent in enumerate(shape):
        request.extents[axis] = extent
        # A step along an axis weighs its length squared in the y voxel unit.
        request.weights[axis] = AXIS_UNITS[axis] ** 2
    request.before = before.positive
    request.after = after.positive
    request.counts = ctypes.POINTER(ctypes.c_uint)()
    if entry(ctypes.byref(request)) != 0:
        raise RuntimeError("the engine refused the shift agreement")
    return tuple(request.lag[axis] for axis in range(len(shape))), request.agreement


def run_overlap(before, after, voxels, on_device, shape=None, lag=None):
    """[(object before, object after, shared positive voxels)] between two consecutive frames' Basins.

    Voxel v of the first frame is compared with voxel v + lag of the next, lag zero when not given.
    Ascending by object before, then object after. Every count is an exact integer tally.
    """
    entry = engine().basin_overlap_run if on_device else engine().basin_overlap_host
    room = run_overlap.room
    extents = shape if shape is not None else (voxels,)
    offsets = lag if lag is not None else (0,) * len(extents)
    while True:
        peaks_before = (ctypes.c_uint * room)()
        peaks_after = (ctypes.c_uint * room)()
        counts = (ctypes.c_uint * room)()
        request = BasinOverlapRequest(before.labels, before.positive, after.labels, after.positive,
                                      len(extents), (ctypes.c_uint * 8)(*extents),
                                      (ctypes.c_int * 8)(*offsets),
                                      voxels, room, peaks_before, peaks_after, counts)
        total = entry(ctypes.byref(request))
        if total < 0:
            raise RuntimeError("the engine refused the overlap")
        if total <= room:
            break
        # The pairs did not fit; the count they need is known now, so the second call is exact.
        room = total
    run_overlap.room = max(run_overlap.room, room)
    index_before = {peak: slot for slot, peak in enumerate(before.peaks)}
    index_after = {peak: slot for slot, peak in enumerate(after.peaks)}
    triples = []
    for slot in range(total):
        # Only pairs of objects: a basin whose peak is not positive holds no object.
        first = index_before.get(peaks_before[slot])
        second = index_after.get(peaks_after[slot])
        if first is not None and second is not None:
            triples.append((first, second, counts[slot]))
    return triples


run_overlap.room = 1 << 16


def limbs_to_int(limbs):
    """A two's complement value from its limbs, least significant first."""
    value = 0
    for position, limb in enumerate(limbs):
        value |= int(limb) << (32 * position)
    if value >> (32 * len(limbs) - 1):
        value -= 1 << (32 * len(limbs))
    return value


class Basins:
    """One frame's basins, every value an integer."""

    def __init__(self, peaks, sizes, sums, values, adjacency, labels, residual, positive, joined):
        self.peaks = peaks            # peak raster indices, ascending
        self.sizes = sizes            # positive voxels per basin
        self.sums = sums              # (z, y, x) index sums per basin
        self.values = values          # residual at each peak, a Python int
        self.adjacency = adjacency    # (object, object) pairs, object indices into peaks
        self.labels = labels          # ctypes array: each voxel's peak index, or None
        self.residual = residual      # ctypes array of limbs, or None
        self.positive = positive      # ctypes array of sign words, bit v set where voxel v is positive
        self.joined = joined          # (object, object) pairs touching through two positive voxels


def run_basins(frame_bytes, shape, on_device, want_labels=True, want_residual=False,
               want_values=False):
    """Calls the engine on one frame. Returns a Basins; values is None unless want_values."""
    depth, height, width = shape
    voxels = depth * height * width
    volume = (ctypes.c_ushort * voxels).from_buffer_copy(frame_bytes)

    # No two positive peaks touch, since each is strictly the highest of its 26 neighbours, so at
    # most one lies in any 2x2x2 block. The room follows from the geometry and is never exceeded.
    room = ((depth + 1) // 2) * ((height + 1) // 2) * ((width + 1) // 2)
    peak_indices = (ctypes.c_uint * room)()
    sizes = (ctypes.c_uint * room)()
    sums = (ctypes.c_ulonglong * (room * 3))()
    peak_limbs = (ctypes.c_uint * (room * LIMBS))()
    labels = (ctypes.c_uint * voxels)() if want_labels else None
    residual = (ctypes.c_uint * (voxels * LIMBS))() if want_residual else None
    positive = (ctypes.c_ulonglong * ((voxels + 63) // 64))()
    adjacency_room = run_basins.adjacency_room
    joined_room = run_basins.adjacency_room
    entry = engine().binomial_basins_run if on_device else engine().binomial_basins_host

    while True:
        adjacency = (ctypes.c_uint * (adjacency_room * 2))()
        adjacency_count = ctypes.c_uint(0)
        joined = (ctypes.c_uint * (joined_room * 2))()
        joined_count = ctypes.c_uint(0)
        request = BinomialBasinsRequest(
            volume, depth, height, width,
            (ctypes.c_uint * 3)(*SMOOTH_ORDERS), (ctypes.c_uint * 3)(*BACKGROUND_ORDERS),
            room, peak_indices, sizes, sums, peak_limbs,
            adjacency_room, adjacency, ctypes.pointer(adjacency_count),
            labels if labels is not None else ctypes.POINTER(ctypes.c_uint)(),
            residual if residual is not None else ctypes.POINTER(ctypes.c_uint)(),
            positive, joined_room, joined, ctypes.pointer(joined_count))
        count = entry(ctypes.byref(request))
        if count < 0:
            raise RuntimeError("the engine refused the frame")
        if adjacency_count.value <= adjacency_room and joined_count.value <= joined_room:
            break
        # The pairs did not fit; the counts they need are known now, so the second call is exact.
        adjacency_room = max(adjacency_room, adjacency_count.value)
        joined_room = max(joined_room, joined_count.value)
    run_basins.adjacency_room = max(run_basins.adjacency_room, adjacency_count.value, joined_count.value)

    peaks = list(peak_indices[:count])
    index_of = {peak: slot for slot, peak in enumerate(peaks)}
    pairs = adjacency[:adjacency_count.value * 2]
    return Basins(
        peaks=peaks,
        sizes=list(sizes[:count]),
        sums=[tuple(sums[slot * 3:slot * 3 + 3]) for slot in range(count)],
        values=[limbs_to_int(peak_limbs[slot * LIMBS:(slot + 1) * LIMBS]) for slot in range(count)]
        if want_values else None,
        adjacency=[(index_of[pairs[2 * slot]], index_of[pairs[2 * slot + 1]])
                   for slot in range(adjacency_count.value)],
        labels=labels,
        residual=residual,
        positive=positive,
        joined=[(index_of[joined[2 * slot]], index_of[joined[2 * slot + 1]])
                for slot in range(joined_count.value)])


run_basins.adjacency_room = 1 << 18


def open_frames(root, split, name):
    """The raw volume of one sample as a zarr array of shape (T, Z, Y, X)."""
    import zarr
    return zarr.open(os.path.join(root, split, name + ".zarr"), mode="r")["0"]


def frame_bytes(volume, frame):
    """One frame's raw intensities as little endian unsigned 16 bit bytes, raster order."""
    data = volume[frame]
    if data.dtype.str != "<u2":
        raise RuntimeError("expected little endian uint16 voxels, found %s" % data.dtype.str)
    return data.tobytes(order="C")


def read_truth(root, split, name):
    """(nodes, edges) from one .geff: nodes maps id to (t, (z, y, x)) in integer voxels."""
    import zarr
    group = zarr.open(os.path.join(root, split, name + ".geff"), mode="r")
    ids = group["nodes/ids"][:].tolist()
    columns = {axis: group["nodes/props/%s/values" % axis][:].tolist() for axis in "tzyx"}
    nodes = {}
    for slot, node in enumerate(ids):
        coordinates = tuple(columns[axis][slot] for axis in "zyx")
        if not all(isinstance(value, int) for value in coordinates):
            raise RuntimeError("the answer key carries a non-integer coordinate")
        nodes[int(node)] = (int(columns["t"][slot]), coordinates)
    edges = [tuple(int(value) for value in pair) for pair in group["edges/ids"][:].tolist()] \
        if "edges/ids" in group else []
    return nodes, edges


def decimal(numerator, denominator, places=2):
    """numerator/denominator written to fixed decimal places, by integer division."""
    scaled = (abs(numerator) * 10 ** places * 2 + denominator) // (2 * denominator)
    sign = "-" if numerator * denominator < 0 else ""
    whole, fraction = divmod(scaled, 10 ** places)
    return "%s%d.%0*d" % (sign, whole, places, fraction)


# ---- grade ---------------------------------------------------------------------------------------

def command_grade(args):
    names = sample_names(args)
    frames = [int(value) for value in args.frames.split(",")] if args.frames else [args.frame]
    engine()
    graded = 0
    passed = 0
    print("  orders: smooth %s, background %s" % (SMOOTH_ORDERS, BACKGROUND_ORDERS))
    brute = check_agreement_by_brute_force()
    print("  shift agreement on small random views, both engines against a direct count at every lag: %s"
          % ("equal" if brute else "DIFFER"))
    for name in names:
        volume = open_frames(args.root, args.split, name)
        shape = tuple(volume.shape[1:])
        for frame in frames:
            if frame >= volume.shape[0]:
                continue
            raw = frame_bytes(volume, frame)
            clock = time.perf_counter_ns()
            device = run_basins(raw, shape, True, want_labels=True, want_residual=True, want_values=True)
            device_ns = time.perf_counter_ns() - clock
            clock = time.perf_counter_ns()
            host = run_basins(raw, shape, False, want_labels=True, want_residual=True, want_values=True)
            host_ns = time.perf_counter_ns() - clock
            checks = {
                "residual": bytes(device.residual) == bytes(host.residual),
                "labels": bytes(device.labels) == bytes(host.labels),
                "signs": bytes(device.positive) == bytes(host.positive),
                "peaks": device.peaks == host.peaks,
                "sizes": device.sizes == host.sizes,
                "sums": device.sums == host.sums,
                "peak values": device.values == host.values,
                "adjacency": device.adjacency == host.adjacency,
                "joined": device.joined == host.joined,
            }
            if frame + 1 < volume.shape[0]:
                # The overlap with the next frame, by both engines, on the device's own basins.
                following = run_basins(frame_bytes(volume, frame + 1), shape, True)
                voxels = shape[0] * shape[1] * shape[2]
                device_motion = view_motion(device, following, shape, True)
                checks["view motion"] = device_motion == view_motion(device, following, shape, False)
                checks["overlap"] = \
                    run_overlap(device, following, voxels, True, shape, device_motion[0]) \
                    == run_overlap(device, following, voxels, False, shape, device_motion[0])
                print("    view motion z y x %s, agreement %d" % (device_motion[0], device_motion[1]))
            graded += 1
            passed += 1 if all(checks.values()) else 0
            print("  %s frame %d: %d peaks, %d adjacent pairs. device %s s, portable %s s"
                  % (name, frame, len(device.peaks), len(device.adjacency),
                     timing(device_ns), timing(host_ns)))
            print("    " + "   ".join("%s %s" % (key, "equal" if same else "DIFFER")
                                     for key, same in checks.items()))
    print("\n  %d of %d frames exact" % (passed, graded))
    return 0 if passed == graded else 1


def timing(nanoseconds):
    """Wall clock seconds for display, from the integer nanosecond clock."""
    return decimal(nanoseconds, 10 ** 9, 3)


# ---- motion --------------------------------------------------------------------------------------

def slope(points):
    """Least squares slope of equally spaced points, exactly: sum((i - mean) p_i) / sum((i - mean)^2)."""
    count = len(points)
    offsets = [Fraction(2 * index - (count - 1), 2) for index in range(count)]
    denominator = sum(offset * offset for offset in offsets)
    return tuple(sum(offset * point[axis] for offset, point in zip(offsets, points)) / denominator
                 for axis in range(3))


def arc_step(window):
    """The next displacement along the arc through five positions, in exact rational arithmetic.

    The slope fitted to the first four positions and the slope fitted to the last four sit one frame
    apart. Their ratio, taken as complex numbers in the y-x plane, is the turn and the change of pace
    over one frame, and applying it once more to the later slope carries the arc forward. A ratio of
    Gaussian rationals is a Gaussian rational, so no angle is ever formed and nothing is rounded. z is
    held, as the answer key showed cells keep their z slice.
    """
    earlier = slope(window[:-1])
    later = slope(window[1:])
    earlier_norm = earlier[1] * earlier[1] + earlier[2] * earlier[2]
    if earlier_norm == 0:
        return (Fraction(0), later[1], later[2])
    # later * later / earlier, with (y, x) read as y + i x, is later^2 * conj(earlier) / |earlier|^2.
    square_y = later[1] * later[1] - later[2] * later[2]
    square_x = 2 * later[1] * later[2]
    return (Fraction(0),
            (square_y * earlier[1] + square_x * earlier[2]) / earlier_norm,
            (square_x * earlier[1] - square_y * earlier[2]) / earlier_norm)


def straight_step(window):
    """The fitted slope across the whole window, z held."""
    fitted = slope(window)
    return (Fraction(0), fitted[1], fitted[2])


def squared_units(first, second):
    """Squared distance in the y voxel unit between two positions given in voxels."""
    return sum(AXIS_UNITS[axis] ** 2 * (first[axis] - second[axis]) ** 2 for axis in range(3))


def median(values):
    """The lower median of exact values."""
    ordered = sorted(values)
    return ordered[(len(ordered) - 1) // 2]


def command_arc_truth(args):
    names = sample_names(args, need_truth=True)
    errors = {"stay": [], "straight": [], "arc": [], "history": [], "straight z": [],
              "history z": []}
    for name in names:
        nodes, edges = read_truth(args.root, args.split, name)
        following = {}
        preceding = {}
        for source, target in edges:
            following.setdefault(source, []).append(target)
            preceding.setdefault(target, []).append(source)
        for start in nodes:
            before = preceding.get(start, [])
            if len(before) == 1 and len(following.get(before[0], [])) == 1:
                continue
            chain = [start]
            while len(following.get(chain[-1], [])) == 1:
                step = following[chain[-1]][0]
                if nodes[step][0] != nodes[chain[-1]][0] + 1:
                    break
                chain.append(step)
            positions = [tuple(Fraction(value) for value in nodes[node][1]) for node in chain]
            for last in range(4, len(positions) - 1):
                window = positions[last - 4:last + 1]
                history = positions[:last + 1]
                truth = positions[last + 1]
                here = window[-1]
                errors["stay"].append(squared_units(here, truth))
                for key, predictor in (("straight", straight_step), ("arc", arc_step)):
                    step = predictor(window)
                    predicted = tuple(here[axis] + step[axis] for axis in range(3))
                    errors[key].append(squared_units(predicted, truth))
                # Unbounded variants: the whole history instead of five frames, and z fitted
                # instead of held.
                for key, points, fit_z in (("history", history, False), ("straight z", window, True),
                                           ("history z", history, True)):
                    fitted = slope(points)
                    step = (fitted[0] if fit_z else Fraction(0), fitted[1], fitted[2])
                    predicted = tuple(here[axis] + step[axis] for axis in range(3))
                    errors[key].append(squared_units(predicted, truth))
    count = len(errors["stay"])
    print("  %d predictions over 5 frame windows, from %d samples" % (count, len(names)))
    print("  squared error in y voxels^2 (multiply by 169/1024 for um^2), exact:")
    print("  %-9s %-16s %s" % ("predictor", "median", "mean"))
    for key in ("stay", "straight", "arc", "history", "straight z", "history z"):
        values = errors[key]
        middle = median(values)
        mean = sum(values) / len(values)
        print("  %-9s %-16s %s" % (key, decimal(middle.numerator, middle.denominator, 3),
                                   decimal(mean.numerator, mean.denominator, 3)))
    return 0


def command_parallax_truth(args):
    """Whether labelled steps depend on depth, per sample, exactly.

    For every labelled edge the step (dz, dy, dx) and the source depth z. Per sample, the least squares
    slope of dy and of dx against z, as exact Fractions, and what that slope amounts to across the
    depth the sample's labelled cells span, in y voxels, beside the sample's median step length.
    """
    names = sample_names(args, need_truth=True)
    print("  %-24s %5s %6s  %-14s %-14s %-9s %s" % ("sample", "edges", "depth", "dy per z", "dx per z",
                                                    "across", "median |step|"))
    consistent = 0
    measured = 0
    for name in names:
        nodes, edges = read_truth(args.root, args.split, name)
        rows = []
        for source, target in edges:
            if source not in nodes or target not in nodes:
                continue
            if nodes[target][0] != nodes[source][0] + 1:
                continue
            here = nodes[source][1]
            there = nodes[target][1]
            rows.append((here[0], there[1] - here[1], there[2] - here[2], there[0] - here[0]))
        depths = [row[0] for row in rows]
        if len(rows) < 3 or len(set(depths)) < 2:
            continue
        count = len(rows)
        depth_total = sum(depths)
        denominator = count * sum(depth * depth for depth in depths) - depth_total * depth_total
        slopes = []
        for column in (1, 2):
            values = [row[column] for row in rows]
            numerator = count * sum(depth * value for depth, value in zip(depths, values)) \
                - depth_total * sum(values)
            slopes.append(Fraction(numerator, denominator))
        span = max(depths) - min(depths)
        across_squared = (slopes[0] * span) ** 2 + (slopes[1] * span) ** 2
        lengths = [16 * row[3] ** 2 + row[1] ** 2 + row[2] ** 2 for row in rows]
        typical = median(lengths)
        measured += 1
        # The depth-dependent part is at least the size of a typical step across the labelled depth.
        if across_squared >= typical:
            consistent += 1
        print("  %-24s %5d %6d  %-14s %-14s %-9s %d"
              % (name[:24], count, span, decimal(slopes[0].numerator, slopes[0].denominator, 3),
                 decimal(slopes[1].numerator, slopes[1].denominator, 3),
                 math.isqrt(across_squared.numerator // across_squared.denominator), math.isqrt(typical)))
    print("\n  %d of %d samples: the depth-dependent part of the step, across the labelled depth, is at "
          "least a typical step" % (consistent, measured))

    # The frame's own motion: in each sample and frame, the common step of every labelled cell stepping
    # out of that frame, taken as the median vector, and what is left of each step once it is removed.
    raw_lengths = []
    residual_lengths = []
    drifts = []
    for name in names:
        nodes, edges = read_truth(args.root, args.split, name)
        by_frame = {}
        for source, target in edges:
            if source in nodes and target in nodes and nodes[target][0] == nodes[source][0] + 1:
                here = nodes[source][1]
                there = nodes[target][1]
                by_frame.setdefault(nodes[source][0], []).append(
                    tuple(there[axis] - here[axis] for axis in range(3)))
        for steps in by_frame.values():
            if len(steps) < 3:
                continue
            common = tuple(median([step[axis] for step in steps]) for axis in range(3))
            drifts.append(sum(AXIS_UNITS[axis] ** 2 * common[axis] ** 2 for axis in range(3)))
            for step in steps:
                raw_lengths.append(sum(AXIS_UNITS[axis] ** 2 * step[axis] ** 2 for axis in range(3)))
                residual_lengths.append(sum(AXIS_UNITS[axis] ** 2 * (step[axis] - common[axis]) ** 2
                                            for axis in range(3)))
    if raw_lengths:
        print("\n  frame motion, over %d frames with at least three labelled steps:" % len(drifts))
        print("    median |common step|           %d y voxels" % math.isqrt(median(drifts)))
        print("    median |step|                  %d y voxels   (squared %d)"
              % (math.isqrt(median(raw_lengths)), median(raw_lengths)))
        print("    median |step - common step|    %d y voxels   (squared %d)"
              % (math.isqrt(median(residual_lengths)), median(residual_lengths)))
        print("    mean squared |step|            %s" % decimal(sum(raw_lengths), len(raw_lengths), 2))
        print("    mean squared |step - common|   %s" % decimal(sum(residual_lengths), len(residual_lengths), 2))
    return 0


def sample_names(args, need_truth=False):
    """Sample names in name order, filtered by --sample and cut by --limit."""
    here = os.path.join(args.root, args.split)
    names = sorted(entry[:-len(".zarr")] for entry in os.listdir(here) if entry.endswith(".zarr"))
    if need_truth:
        names = [name for name in names if os.path.isdir(os.path.join(here, name + ".geff"))]
    if getattr(args, "sample", None):
        names = [name for name in names if name.startswith(args.sample)]
    limit = getattr(args, "limit", None)
    return names[:limit] if limit else names


# ---- linking -------------------------------------------------------------------------------------

def centroid(basins, index):
    """An object's centroid in voxels, as exact Fractions."""
    size = basins.sizes[index]
    return tuple(Fraction(total, size) for total in basins.sums[index])


def nearest(value):
    """The integer nearest an exact value, half rounding up, by floor division."""
    return (2 * value.numerator + value.denominator) // (2 * value.denominator)


def fitted_step(times, values):
    """Least squares slope of exact values against integer frame times.

    (n sum(t v) - sum(t) sum(v)) / (n sum(t^2) - sum(t)^2). Two detections give their displacement per
    frame; five consecutive ones give the fitted slope measured best against the answer key.
    """
    count = len(times)
    time_total = sum(times)
    denominator = count * sum(when * when for when in times) - time_total * time_total
    # The weight of each value is n t - sum(t), an integer. Carried over one common denominator, the
    # whole numerator is a single integer sum and the Fraction is formed once.
    common = math.lcm(*(value.denominator for value in values))
    numerator = sum((count * when - time_total) * value.numerator * (common // value.denominator)
                    for when, value in zip(times, values))
    return Fraction(numerator, common * denominator)


class Track:
    """One track, carried in exact values.

    times, ys and xs hold its last five real detections. z is its last real z, held because cells keep
    their z slice. step is the fitted slope of those detections in y and x, or None with one. move is
    its last displacement when its last two detections were consecutive frames, with moved_at the
    frame it arrived; neighbours read it as flow.
    """

    __slots__ = ("times", "ys", "xs", "z", "real", "held", "alive", "step", "move", "moved_at")

    def __init__(self, frame, position, held):
        self.times = [frame]
        self.ys = [position[1]]
        self.xs = [position[2]]
        self.z = position[0]
        self.real = 1
        self.held = held
        self.alive = True
        self.step = None
        self.move = None
        self.moved_at = None

    def detect(self, frame, position, held):
        """Records a real detection."""
        if self.times[-1] == frame - 1:
            self.move = (position[1] - self.ys[-1], position[2] - self.xs[-1])
            self.moved_at = frame
        self.times = (self.times + [frame])[-5:]
        self.ys = (self.ys + [position[1]])[-5:]
        self.xs = (self.xs + [position[2]])[-5:]
        self.z = position[0]
        self.real += 1
        self.held = held
        self.step = (fitted_step(self.times, self.ys), fitted_step(self.times, self.xs))


def link_sample(frames, basins_at, shape, control=False):
    """Links objects across frames. Returns (links, kept, lengths), all over (frame, object index).

    links maps (frame, object) to (next frame, object). kept maps a frame to the set of object indices
    that survive coherence over time. Every choice below is described in the module docstring of
    src/basin_link.py; here every one of them is carried in exact arithmetic.
    """
    depth, height, width = shape
    tracks = []
    owner = {}
    links = {}
    object_counts = {}
    previous = None
    previous_adjacency = {}

    for frame in frames:
        basins = basins_at(frame)
        count = len(basins.peaks)
        object_counts[frame] = count
        positions = [centroid(basins, index) for index in range(count)]
        adjacency = {}
        for left, right in basins.adjacency:
            adjacency.setdefault(left, []).append(right)
            adjacency.setdefault(right, []).append(left)
        by_peak = {peak: index for index, peak in enumerate(basins.peaks)}

        if previous is None or frame != previous + 1:
            for track in tracks:
                track.alive = False
            for index in range(count):
                tracks.append(Track(frame, positions[index], index))
                owner[(frame, index)] = len(tracks) - 1
            live = list(range(len(tracks) - count, len(tracks)))
            previous = frame
            previous_adjacency = adjacency
            continue

        claims = {}
        for number in live:
            track = tracks[number]
            elapsed = frame - track.times[-1]
            own = track.step
            if track.held is not None:
                # Held last frame: its own fitted motion averaged with the last moves of the tracks
                # holding the basins its basin touched, where those moves were observed last frame.
                moves = []
                for other in previous_adjacency.get(track.held, ()):
                    neighbour = tracks[owner[(previous, other)]]
                    if neighbour.moved_at == previous:
                        moves.append(neighbour.move)
                if moves:
                    flow = (sum(move[0] for move in moves) / len(moves),
                            sum(move[1] for move in moves) / len(moves))
                    own = flow if own is None else ((own[0] + flow[0]) / 2, (own[1] + flow[1]) / 2)
            if own is None:
                predicted_y = track.ys[-1]
                predicted_x = track.xs[-1]
            else:
                # Travelling or held, the prediction is the last real position carried forward by the
                # frames elapsed, so a travelling track's values never gain denominators.
                sign = -1 if control else 1
                predicted_y = track.ys[-1] + sign * elapsed * own[0]
                predicted_x = track.xs[-1] + sign * elapsed * own[1]
            voxel_z = nearest(track.z)
            voxel_y = nearest(predicted_y)
            voxel_x = nearest(predicted_x)
            if not (0 <= voxel_y < height and 0 <= voxel_x < width):
                track.alive = False
                continue
            target = by_peak.get(basins.labels[(voxel_z * height + voxel_y) * width + voxel_x])
            held_before = track.held
            track.held = None
            if target is not None:
                claims.setdefault(target, []).append((number, predicted_y, predicted_x, held_before))

        # The elder keeps a contested object; equal age falls to the nearer prediction, then the
        # older track number. Distances are formed only where two tracks want one object.
        claimed = set()
        for target, claimants in claims.items():
            if len(claimants) == 1:
                winner = claimants[0]
            else:
                eldest = max(tracks[claim[0]].real for claim in claimants)
                claimants = [claim for claim in claimants if tracks[claim[0]].real == eldest]
                goal = positions[target]
                winner = claimants[0] if len(claimants) == 1 else min(claimants, key=lambda claim: (
                    16 * (tracks[claim[0]].z - goal[0]) ** 2 + (claim[1] - goal[1]) ** 2
                    + (claim[2] - goal[2]) ** 2,
                    claim[0]))
            number, _, _, held_before = winner
            if held_before is not None:
                links[(previous, held_before)] = (frame, target)
            owner[(frame, target)] = number
            tracks[number].detect(frame, positions[target], target)
            claimed.add(target)

        live = [number for number in live if tracks[number].alive]
        for index in range(count):
            if index not in claimed:
                tracks.append(Track(frame, positions[index], index))
                owner[(frame, index)] = len(tracks) - 1
                live.append(len(tracks) - 1)
        previous = frame
        previous_adjacency = adjacency

    ordered = list(frames)
    kept = {}
    lengths = {}
    for position, frame in enumerate(ordered):
        has_before = position > 0 and ordered[position - 1] == frame - 1
        has_after = position + 1 < len(ordered) and ordered[position + 1] == frame + 1
        kept[frame] = set()
        for index in range(object_counts[frame]):
            real = tracks[owner[(frame, index)]].real
            lengths[(frame, index)] = real
            if real >= 2 or not (has_before and has_after):
                kept[frame].add(index)
    links = {source: target for source, target in links.items()
             if source[1] in kept[source[0]] and target[1] in kept[target[0]]}
    return links, kept, lengths


# ---- culmination ---------------------------------------------------------------------------------

class HeaviestMatchingRequest(ctypes.Structure):
    """Laid out to match HeaviestMatchingRequest in engine/heaviest_matching.h."""
    _fields_ = [
        ("before", ctypes.POINTER(ctypes.c_uint)),
        ("after", ctypes.POINTER(ctypes.c_uint)),
        ("counts", ctypes.POINTER(ctypes.c_uint)),
        ("pairs", ctypes.c_uint),
        ("before_count", ctypes.c_uint),
        ("after_count", ctypes.c_uint),
        ("chosen", ctypes.POINTER(ctypes.c_ubyte)),
    ]


def heaviest_matching(triples, before_count, after_count):
    """{object before: object after}, the one-to-one pairing carrying the most overlap, exactly.

    Solved by engine/heaviest_matching.c: successive shortest paths on 64 bit integer costs, one
    connected component at a time.
    """
    library = engine()
    library.heaviest_matching_run.argtypes = [ctypes.POINTER(HeaviestMatchingRequest)]
    library.heaviest_matching_run.restype = ctypes.c_long
    count = len(triples)
    request = HeaviestMatchingRequest(
        (ctypes.c_uint * max(1, count))(*[before for before, _, _ in triples]),
        (ctypes.c_uint * max(1, count))(*[after for _, after, _ in triples]),
        (ctypes.c_uint * max(1, count))(*[shared for _, _, shared in triples]),
        count, before_count, after_count,
        (ctypes.c_ubyte * max(1, count))())
    if library.heaviest_matching_run(ctypes.byref(request)) < 0:
        raise RuntimeError("the engine refused the matching")
    return {triples[slot][0]: triples[slot][1] for slot in range(count) if request.chosen[slot]}


def culminate(frames, basins_at, shape, on_device):
    """Feeds every frame, accumulates exact overlap, and reads the chains once at the end.

    Returns (links, counts, weights, accumulated): links maps (frame, object) to (next frame, object);
    counts maps a frame to its object count; weights maps (frame, object) to the overlap carried by
    the chain through it; accumulated maps a frame to its overlap triples with the next frame.
    """
    depth, height, width = shape
    voxels = depth * height * width
    accumulated = {}
    counts = {}
    culminate.lags = {}
    previous = None
    previous_basins = None
    for frame in frames:
        basins = basins_at(frame)
        counts[frame] = len(basins.peaks)
        if previous is not None and frame == previous + 1:
            if culminate.compensate:
                # The view's own motion between the two frames, measured over every lag at once, is
                # removed before overlap is counted, so overlap measures the objects' own motion.
                lag, _ = view_motion(previous_basins, basins, shape, on_device)
            else:
                lag = (0, 0, 0)
            culminate.lags[previous] = lag
            accumulated[previous] = run_overlap(previous_basins, basins, voxels, on_device, shape, lag)
        previous = frame
        previous_basins = basins
    previous_basins = None

    links = {}
    for frame, triples in accumulated.items():
        for before, after in heaviest_matching(triples, counts[frame], counts[frame + 1]).items():
            links[(frame, before)] = (frame + 1, after)

    # The overlap each chain carries, summed along the whole chain: the accumulated evidence.
    overlap_of = {(frame, before, after): count for frame, triples in accumulated.items()
                  for before, after, count in triples}
    successor = links
    predecessor = {target: source for source, target in links.items()}
    weights = {}
    for frame in frames:
        for index in range(counts[frame]):
            node = (frame, index)
            if node in weights:
                continue
            start = node
            while start in predecessor:
                start = predecessor[start]
            chain = [start]
            while chain[-1] in successor:
                chain.append(successor[chain[-1]])
            total = sum(overlap_of[(first[0], first[1], second[1])]
                        for first, second in zip(chain, chain[1:]))
            for member in chain:
                weights[member] = total
    return links, counts, weights, accumulated


culminate.compensate = True
culminate.lags = {}


def _grow_once(frames, basins_at, shape, on_device, leaf_lag):
    """One build of the tree. leaf_lag maps (frame, leaf) to the lag that leaf's peak is carried by;
    where a leaf is absent the frame's one global lag is used. Returns the pieces grow_tree assembles.
    """
    depth, height, width = shape
    plane = height * width
    voxels = depth * plane
    counts = {}
    forward = {}
    backward = {}
    joined = {}
    peak_pos = {}
    overlaps = {}
    global_lags = {}
    previous = None
    previous_basins = None

    def position(peak):
        z, rest = divmod(peak, plane)
        y, x = divmod(rest, width)
        return (z, y, x)

    def land(pos, lag, index, basins):
        z, y, x = pos[0] + lag[0], pos[1] + lag[1], pos[2] + lag[2]
        if not (0 <= z < depth and 0 <= y < height and 0 <= x < width):
            return None
        return index.get(basins.labels[(z * height + y) * width + x])

    for frame in frames:
        basins = basins_at(frame)
        counts[frame] = len(basins.peaks)
        joined[frame] = list(basins.joined)
        peak_pos[frame] = [position(peak) for peak in basins.peaks]
        index = {peak: slot for slot, peak in enumerate(basins.peaks)}
        if previous is not None and frame == previous + 1:
            previous_index = {peak: slot for slot, peak in enumerate(previous_basins.peaks)}
            global_lag = view_motion(previous_basins, basins, shape, on_device)[0] if culminate.compensate else (0, 0, 0)
            global_lags[previous] = global_lag
            back = tuple(-step for step in global_lag)
            forward[previous] = {}
            for leaf, pos in enumerate(peak_pos[previous]):
                lag = leaf_lag.get((previous, leaf), global_lag) if leaf_lag else global_lag
                target = land(pos, lag, index, basins)
                if target is not None:
                    forward[previous][leaf] = target
            backward[frame] = {}
            for leaf, pos in enumerate(peak_pos[frame]):
                lag = leaf_lag.get((frame, leaf)) if leaf_lag else None
                lag = tuple(-step for step in lag) if lag is not None else back
                source = land(pos, lag, previous_index, previous_basins)
                if source is not None:
                    backward[frame][leaf] = source
            if grow_tree.pick:
                overlaps[previous] = {(before, after): count for before, after, count
                                      in run_overlap(previous_basins, basins, voxels, on_device, shape, global_lag)}
        previous = frame
        previous_basins = basins
    previous_basins = None

    objects = {}
    object_of = {}
    for frame in frames:
        parent = list(range(counts[frame]))

        def root(leaf):
            while parent[leaf] != leaf:
                parent[leaf] = parent[parent[leaf]]
                leaf = parent[leaf]
            return leaf

        came_from = backward.get(frame, {})
        goes_to = forward.get(frame, {})
        for left, right in joined[frame]:
            if grow_tree.merge_split and (frame - 1) in objects and left in came_from and right in came_from:
                # Two joined leaves whose peaks came from one object of the earlier frame are the two
                # halves of a cell the residual over-cut, not two cells: they are one object. The
                # earlier frame's objects are already built, so the source object is known. A genuine
                # division comes from two separate objects and is not merged here.
                same_origin = object_of.get((frame - 1, came_from[left])) == object_of.get((frame - 1, came_from[right]))
            else:
                same_origin = left in came_from and came_from.get(right) == came_from[left]
            same_destination = left in goes_to and goes_to.get(right) == goes_to[left]
            if same_origin or same_destination:
                first, second = root(left), root(right)
                if first != second:
                    parent[second] = first
        grouped = {}
        for leaf in range(counts[frame]):
            grouped.setdefault(root(leaf), []).append(leaf)
        objects[frame] = [frozenset(members) for _, members in sorted(grouped.items())]
        for number, members in enumerate(objects[frame]):
            for leaf in members:
                object_of[(frame, leaf)] = number

    links = {}
    predecessors = {}
    for frame, mapping in forward.items():
        later = frame + 1
        if later not in counts:
            continue
        candidates = {}
        for leaf, target in mapping.items():
            candidates.setdefault(object_of[(frame, leaf)], set()).add(object_of[(later, target)])
        confirmed = {}
        for leaf, source in backward.get(later, {}).items():
            confirmed.setdefault(object_of[(later, leaf)], set()).add(object_of[(frame, source)])
        # A target reached by two or more source objects is a merge: its own peak can back-land to
        # only one of them, so the strict mutual test drops the rest. Where merge_target is set, a
        # source whose peak lands in such a target is linked to it even without the back-landing.
        incoming = {}
        if grow_tree.merge_target:
            for source, targets in candidates.items():
                for target in targets:
                    incoming.setdefault(target, set()).add(source)
        for source, targets in candidates.items():
            if grow_tree.forward_only:
                # A source's peak landing in a target is the link, back-landing or not. f is a
                # function, one target per source leaf, so this never over-links the source side; the
                # pick arbitrates a source whose leaves land in several. This recovers the edges where
                # the peak lands home but the target's own back-landing went elsewhere (a merge, or a
                # target grown larger).
                mutual = set(targets)
            else:
                mutual = {target for target in targets if source in confirmed.get(target, ())}
                if grow_tree.merge_target:
                    mutual |= {target for target in targets if len(incoming.get(target, ())) >= 2}
            if grow_tree.pick and len(mutual) >= 2:
                weight = {}
                for (before, after), count in overlaps.get(frame, {}).items():
                    if object_of[(frame, before)] == source and object_of[(later, after)] in mutual:
                        weight[object_of[(later, after)]] = weight.get(object_of[(later, after)], 0) + count
                if weight:
                    best = max(weight.values())
                    mutual = {target for target in mutual if weight.get(target, 0) == best}
            if mutual:
                links[(frame, source)] = {(later, target) for target in mutual}
                for target in mutual:
                    predecessors.setdefault((later, target), set()).add(source)
    return {"forward": forward, "objects": objects, "object_of": object_of, "links": links,
            "predecessors": predecessors, "peak_pos": peak_pos, "counts": counts}


def grow_tree(frames, basins_at, shape, on_device):
    """A tree that starts empty and grows as the frames arrive, decided by truthy relations only.

    Leaves are basins. Every relation is read from the field and is true or false, never a count:
    where a leaf's peak lands in the next frame (a function f, and its back g), and which leaves are
    joined through two positive voxels. From those: continue, split, merge, and fragments (joined
    leaves that split from or merge into one leaf are one object). Nothing is decided frame by frame;
    the relations are gathered and the objects and links read once.

    grow_tree.pick: where a source still branches, keep the object it shares the most positive voxels
    with, the lowest local entropy of the overlap, an exact-integer count with ties left as a split.

    grow_tree.step: land each object's peak by its OWN last exact displacement, a single integer
    vector, not the one global lag. A first build gives every object its incoming step from its one
    predecessor; a second build carries each object forward by that step. This is accumulation, not
    averaging: one exact measurement per object, nothing meaned, since there is no error to cancel.

    Returns (links, objects, events).
    """
    result = _grow_once(frames, basins_at, shape, on_device, None)
    if grow_tree.step:
        peak_pos = result["peak_pos"]
        objects = result["objects"]
        object_of = result["object_of"]
        predecessors = result["predecessors"]

        def object_peak(frame, number):
            members = objects[frame][number]
            return peak_pos[frame][max(members)]

        # Each object's own last step: its peak minus its single predecessor's peak, an exact vector.
        leaf_lag = {}
        for (frame, number), sources in predecessors.items():
            if len(sources) != 1:
                continue
            predecessor = next(iter(sources))
            here = object_peak(frame, number)
            there = object_peak(frame - 1, predecessor)
            step = tuple(here[axis] - there[axis] for axis in range(3))
            for leaf in objects[frame][number]:
                leaf_lag[(frame, leaf)] = step
        result = _grow_once(frames, basins_at, shape, on_device, leaf_lag)

    links = result["links"]
    objects = result["objects"]
    predecessors = result["predecessors"]
    events = {"continue": 0, "split": 0, "no predecessor": 0, "merge": 0}
    for source, children in links.items():
        events["split" if len(children) >= 2 else "continue"] += 1
    for node, sources in predecessors.items():
        if len(sources) >= 2:
            events["merge"] += 1
    for frame in frames:
        for number in range(len(objects[frame])):
            if (frame, number) not in predecessors:
                events["no predecessor"] += 1
    if grow_tree.resolve:
        links, objects, rejoined = resolve_branches(links, objects, frames)
        events["rejoined as fragments"] = rejoined
    grow_tree.forward = result["forward"]
    return links, objects, events


grow_tree.resolve = True
grow_tree.local_flow = False
grow_tree.pick = False
grow_tree.step = False
grow_tree.merge_split = False
grow_tree.merge_target = False
grow_tree.forward_only = False
grow_tree.forward = {}


def resolve_branches(links, objects, frames):
    """Branches read at the end of the series: those that meet again were fragments of one object.

    For every object that continues into several, each branch is followed forward while it continues
    into exactly one object. Two branches whose single continuations land in one object were one
    object all along, and at every frame from the split to the meeting the two are unified. Branches
    that never meet are left apart: that is a division. Nothing is counted or thresholded; the only
    question asked is whether two continuations arrive at the same object.

    Returns (links, objects, rejoined): links and objects over the unified objects, and how many
    branch pairs were found to rejoin.
    """
    parent = {}

    def root(node):
        parent.setdefault(node, node)
        while parent[node] != node:
            parent[node] = parent[parent[node]]
            node = parent[node]
        return node

    def union(first, second):
        first, second = root(first), root(second)
        if first != second:
            parent[max(first, second)] = min(first, second)

    rejoined = 0
    for node, children in sorted(links.items()):
        if len(children) < 2:
            continue
        ordered = sorted(children)
        for position, first in enumerate(ordered):
            for second in ordered[position + 1:]:
                if root(first) == root(second):
                    continue
                # Each branch is followed only while it continues into exactly one object. A branch
                # that divides again has no single continuation to compare, and following every
                # descendant instead merged almost everything: in dense tissue any two fanning
                # branches meet something eventually.
                left = first
                right = second
                visited = [(left, right)]
                while left != right:
                    left_next = links.get(left, set())
                    right_next = links.get(right, set())
                    if len(left_next) != 1 or len(right_next) != 1:
                        break
                    left = next(iter(left_next))
                    right = next(iter(right_next))
                    visited.append((left, right))
                if left == right:
                    rejoined += 1
                    for left_node, right_node in visited[:-1]:
                        union(left_node, right_node)

    # Unified objects: the leaves of every member, and links between the unified objects.
    unified = {}
    renumber = {}
    for frame in frames:
        groups = {}
        for number, members in enumerate(objects[frame]):
            groups.setdefault(root((frame, number)), set()).update(members)
        unified[frame] = []
        for key in sorted(groups):
            renumber[key] = (frame, len(unified[frame]))
            unified[frame].append(frozenset(groups[key]))
    unified_links = {}
    for node, children in links.items():
        source = renumber[root(node)]
        for child in children:
            unified_links.setdefault(source, set()).add(renumber[root(child)])
    return unified_links, unified, rejoined

FAILURE_TYPES = ("missed", "division", "merged", "no shared voxels", "taken", "outweighed", "unlinked")


def failure_type(source, target, nodes, successors, tied, chosen, overlap, predecessor):
    """The one type a failing labelled edge belongs to, tested in a fixed order.

    missed            an endpoint was tied to no kept object
    division          the key gives the source two successors
    merged            another labelled node in either frame is tied to the same object
    no shared voxels  the two objects share no positive voxel: the cell moved beyond its own extent
    taken             the true target object was paired with a different object before
    outweighed        the source object was paired with another object sharing at least as much
    unlinked          anything else
    """
    if source not in tied or target not in tied:
        return "missed"
    if successors.get(source, 0) >= 2:
        return "division"
    for node, place in tied.items():
        if node not in (source, target) and place in (tied[source], tied[target]):
            return "merged"
    before, after = tied[source], tied[target]
    if overlap.get((before[0], before[1], after[1]), 0) == 0:
        return "no shared voxels"
    if after in predecessor and predecessor[after] != before:
        return "taken"
    if before in chosen:
        return "outweighed"
    return "unlinked"


def target_per_frame(root, split, name, frames_in_sample):
    """The sample's published cell count per frame, nearest integer, from its .geff metadata."""
    import json
    path = os.path.join(root, split, name + ".geff", "zarr.json")
    if not os.path.isfile(path):
        return None
    with open(path, "r", encoding="utf-8") as handle:
        meta = json.load(handle)
    attributes = meta.get("attributes", meta)
    estimate = attributes.get("geff", {}).get("estimated_number_of_nodes",
                                              attributes.get("estimated_number_of_nodes"))
    if estimate is None:
        return None
    return nearest(Fraction(int(estimate), frames_in_sample))


# ---- score ---------------------------------------------------------------------------------------

def command_score(args):
    names = sample_names(args, need_truth=True)
    engine()
    culminate.compensate = args.view_motion == "remove"
    grow_tree.local_flow = getattr(args, "flow", False)
    grow_tree.pick = getattr(args, "pick", False)
    grow_tree.step = getattr(args, "step", False)
    grow_tree.merge_split = getattr(args, "merge_split", False)
    grow_tree.merge_target = getattr(args, "merge_target", False)
    grow_tree.forward_only = getattr(args, "forward_only", False)
    print("  Scored against the published answer key, recall over its edges. A labelled node is the")
    print("  object whose basin its own voxel climbs to. Exact arithmetic throughout.\n")
    print("  %-24s %-6s %s" % ("sample", "edges", "correct/wrong/no link/missed"))
    totals = {}
    failures = []
    grow_events = {}
    started = time.perf_counter_ns()
    for name in names:
        nodes, edges = read_truth(args.root, args.split, name)
        volume = open_frames(args.root, args.split, name)
        shape = tuple(volume.shape[1:])
        frames = sorted({frame for frame, _ in nodes.values() if frame < min(args.frames, volume.shape[0])})
        if not frames:
            continue
        node_peak = {}

        def basins_at(frame):
            basins = run_basins(frame_bytes(volume, frame), shape, args.engine == "device")
            depth, height, width = shape
            for node, (node_frame, (z, y, x)) in nodes.items():
                if node_frame == frame:
                    node_peak[node] = basins.labels[(z * height + y) * width + x]
            basins_at.peaks[frame] = basins.peaks
            basins_at.sizes[frame] = basins.sizes
            basins_at.sums[frame] = basins.sums
            return basins

        basins_at.peaks = {}
        basins_at.sizes = {}
        basins_at.sums = {}
        successors = {}
        for source, _ in edges:
            successors[source] = successors.get(source, 0) + 1
        kept_sets = {}
        if args.linker == "grow":
            tree_links, tree_objects, events = grow_tree(frames, basins_at, shape, args.engine == "device")
            for key in events:
                grow_events[key] = grow_events.get(key, 0) + events[key]
            leaf_object = {}
            for frame, members_list in tree_objects.items():
                for index, members in enumerate(members_list):
                    for leaf in members:
                        leaf_object[(frame, leaf)] = index
            tied = {}
            for node, peak in node_peak.items():
                frame = nodes[node][0]
                leaf = {value: slot for slot, value in enumerate(basins_at.peaks[frame])}.get(peak)
                if leaf is not None and (frame, leaf) in leaf_object:
                    tied[node] = (frame, leaf_object[(frame, leaf)])
            counts_here = {"correct": 0, "branched": 0, "wrong": 0, "nolink": 0, "missed": 0}
            frame_set = set(frames)
            for source, target in edges:
                if source not in nodes or target not in nodes:
                    continue
                if nodes[source][0] not in frame_set or nodes[target][0] not in frame_set:
                    continue
                if source not in tied or target not in tied:
                    counts_here["missed"] += 1
                    continue
                made = tree_links.get(tied[source], set())
                if not made:
                    counts_here["nolink"] += 1
                elif made == {tied[target]} or (tied[target] in made and len(made) == successors.get(source, 0)):
                    # One link to the true target, or a division: exactly as many links as the key
                    # gives this node successors, the true target among them.
                    counts_here["correct"] += 1
                elif tied[target] in made:
                    # The true target is one of several branches. Not counted correct: a link set
                    # that holds many objects contains the answer without choosing it.
                    counts_here["branched"] += 1
                else:
                    counts_here["wrong"] += 1
            pooled = totals.setdefault("grow", {"correct": 0, "branched": 0, "wrong": 0, "nolink": 0,
                                                "missed": 0})
            for key in pooled:
                pooled[key] += counts_here[key]
            object_counts = [len(tree_objects[frame]) for frame in frames]
            largest = max(len(members) for frame in frames for members in tree_objects[frame])
            print("  %-24s %-6d grow %d/%d/%d/%d/%d   objects per frame %d-%d, most leaves in one object %d"
                  % (name[:24], sum(counts_here.values()), counts_here["correct"], counts_here["branched"],
                     counts_here["wrong"], counts_here["nolink"], counts_here["missed"],
                     min(object_counts), max(object_counts), largest), flush=True)
            continue
        if args.linker == "online":
            links, kept, _ = link_sample(frames, basins_at, shape, control=args.control)
            kept_sets["online"] = kept
        else:
            links, counts, weights, accumulated = culminate(frames, basins_at, shape,
                                                            args.engine == "device")
            overlap = {(frame, before, after): shared for frame, triples in accumulated.items()
                       for before, after, shared in triples}
            # Every object read at the end of the series, and the same set held to the published
            # target, ranked by the overlap its whole chain carries.
            kept_sets["all"] = {frame: set(range(counts[frame])) for frame in frames}
            target = target_per_frame(args.root, args.split, name, volume.shape[0])
            ranked = {}
            for frame in frames:
                order = sorted(range(counts[frame]), key=lambda index: (-weights[(frame, index)], index))
                ranked[frame] = set(order[:target]) if target is not None else set(order)
            kept_sets["target"] = ranked

        row = []
        for label, kept in kept_sets.items():
            tied = {}
            for node, peak in node_peak.items():
                frame = nodes[node][0]
                index = {value: slot for slot, value in enumerate(basins_at.peaks[frame])}.get(peak)
                if index is not None and index in kept[frame]:
                    tied[node] = (frame, index)
            chosen = {source: target for source, target in links.items()
                      if source[1] in kept[source[0]] and target[1] in kept[target[0]]}
            predecessor = {target: source for source, target in chosen.items()}
            counts_here = {"correct": 0, "wrong": 0, "nolink": 0, "missed": 0}
            frame_set = set(frames)
            for source, target in edges:
                if source not in nodes or target not in nodes:
                    continue
                if nodes[source][0] not in frame_set or nodes[target][0] not in frame_set:
                    continue
                if source not in tied or target not in tied:
                    counts_here["missed"] += 1
                    outcome = "missed"
                else:
                    made = chosen.get(tied[source])
                    if made is None:
                        counts_here["nolink"] += 1
                    elif made == tied[target]:
                        counts_here["correct"] += 1
                    else:
                        counts_here["wrong"] += 1
                    outcome = "correct" if made == tied[target] else None
                if label != "all" or args.linker != "culminate":
                    continue
                if outcome is None:
                    outcome = failure_type(source, target, nodes, successors, tied, chosen, overlap,
                                           predecessor)
                step = tuple(nodes[target][1][axis] - nodes[source][1][axis] for axis in range(3))
                record = {"type": outcome, "step": step,
                          "step units": sum(AXIS_UNITS[axis] ** 2 * step[axis] ** 2 for axis in range(3))}
                if source in tied and target in tied:
                    before, after = tied[source], tied[target]
                    first = [Fraction(total, basins_at.sizes[before[0]][before[1]])
                             for total in basins_at.sums[before[0]][before[1]]]
                    second = [Fraction(total, basins_at.sizes[after[0]][after[1]])
                              for total in basins_at.sums[after[0]][after[1]]]
                    record["object units"] = sum(AXIS_UNITS[axis] ** 2 * (second[axis] - first[axis]) ** 2
                                                 for axis in range(3))
                    record["shared"] = overlap.get((before[0], before[1], after[1]), 0)
                    made = chosen.get(before)
                    record["chosen shared"] = overlap.get((before[0], before[1], made[1]), 0) if made else 0
                    record["size before"] = basins_at.sizes[before[0]][before[1]]
                    record["size after"] = basins_at.sizes[after[0]][after[1]]
                failures.append(record)
            pooled = totals.setdefault(label, {"correct": 0, "wrong": 0, "nolink": 0, "missed": 0})
            for key in pooled:
                pooled[key] += counts_here[key]
            row.append("%s %d/%d/%d/%d" % (label, counts_here["correct"], counts_here["wrong"],
                                           counts_here["nolink"], counts_here["missed"]))
        edge_total = sum(counts_here.values())
        print("  %-24s %-6d %s" % (name[:24], edge_total, "   ".join(row)), flush=True)

    for label, pooled in totals.items():
        grand = sum(pooled.values())
        if grand:
            print("\n  POOLED, %s, over %d ground truth edges:" % (label, grand))
            for key, text in (("correct", "correct link"), ("branched", "target among branches"),
                              ("wrong", "wrong link"), ("nolink", "no link made"),
                              ("missed", "endpoint undetected")):
                if key in pooled:
                    print("    %-22s %5d   %s%%" % (text, pooled[key], decimal(100 * pooled[key], grand, 1)))
    if failures:
        print_failure_table(failures)
    if grow_events:
        print("\n  tree growth: %s" % ", ".join("%s %d" % item for item in grow_events.items()))
    print("\n  %s s" % timing(time.perf_counter_ns() - started))
    return 0


def print_failure_table(records):
    """Every labelled edge by outcome type, with exact medians of its motion and overlap.

    Lengths are in the y voxel unit: a z step counts four. Squared lengths are shown as their integer
    square root so they read as distances, and every median is the lower median of exact values.
    """
    failed = [record for record in records if record["type"] != "correct"]
    print("\n  LABELLED EDGES BY OUTCOME TYPE, every run of the culminating linker, all objects kept")
    print("  %-17s %6s %6s  %-12s %-9s %-9s %-9s %-9s %-9s %s"
          % ("type", "edges", "fail%", "step dz dy dx", "|step|", "|objects|", "shared", "chosen", "size", "size"))
    print("  %-17s %6s %6s  %-12s %-9s %-9s %-9s %-9s %-9s %s"
          % ("", "", "", "median", "median", "median", "median", "median", "before", "after"))
    for kind in ("correct",) + FAILURE_TYPES:
        rows = [record for record in records if record["type"] == kind]
        if not rows:
            continue

        def middle(key, rows=rows):
            values = [row[key] for row in rows if key in row]
            return median(values) if values else None

        steps = [row["step"] for row in rows]
        signed = tuple(median([step[axis] for step in steps]) for axis in range(3))
        share = decimal(100 * len(rows), len(failed), 1) if kind != "correct" and failed else "-"

        def root_of(value):
            if value is None:
                return "-"
            whole = math.isqrt(value.numerator // value.denominator) if isinstance(value, Fraction) \
                else math.isqrt(value)
            return str(whole)

        def plain(value):
            return "-" if value is None else str(value)

        print("  %-17s %6d %6s  %-12s %-9s %-9s %-9s %-9s %-9s %s"
              % (kind, len(rows), share, "%d %d %d" % signed, root_of(middle("step units")),
                 root_of(middle("object units")), plain(middle("shared")), plain(middle("chosen shared")),
                 plain(middle("size before")), plain(middle("size after"))))


def main():
    parser = argparse.ArgumentParser(description="Cell tracking in exact arithmetic.")
    commands = parser.add_subparsers(dest="command", required=True)

    grade = commands.add_parser("grade", help="the CUDA engine against the portable reference")
    arc = commands.add_parser("arc-truth", help="motion predictors against the answer key")
    score = commands.add_parser("score", help="detect, link and score")
    parallax = commands.add_parser("parallax-truth", help="whether labelled steps depend on depth")
    parallax.add_argument("--limit", type=int, default=200)
    for sub in (grade, arc, score, parallax):
        sub.add_argument("--root", default=ROOT)
        sub.add_argument("--split", default="train")
    grade.add_argument("--sample")
    grade.add_argument("--limit", type=int, default=1)
    grade.add_argument("--frame", type=int, default=40)
    grade.add_argument("--frames")
    arc.add_argument("--limit", type=int, default=200)
    score.add_argument("--sample")
    score.add_argument("--limit", type=int, default=3)
    score.add_argument("--frames", type=int, default=40)
    score.add_argument("--control", action="store_true")
    score.add_argument("--linker", default="culminate", choices=("culminate", "online", "grow"))
    score.add_argument("--view-motion", default="remove", choices=("remove", "keep"))
    score.add_argument("--flow", action="store_true",
                       help="grow only: land each peak by the local flow (the mean displacement of its "
                            "joined neighbours), not the one global lag")
    score.add_argument("--pick", action="store_true",
                       help="grow only: where a source still branches, keep the one it shares the most "
                            "voxels with (lowest local entropy); an exact tie stays a split")
    score.add_argument("--step", action="store_true",
                       help="grow only: land each object's peak by its own last exact displacement, "
                            "one measurement per object, not the one global lag and not any mean")
    score.add_argument("--merge-split", action="store_true",
                       help="grow only: two joined objects whose peaks came from one earlier object "
                            "are one over-cut cell and are unified; a division from two objects is not")
    score.add_argument("--merge-target", action="store_true",
                       help="grow only: a source whose peak lands in a target reached by two or more "
                            "sources (a merge) is linked to it without the strict back-landing")
    score.add_argument("--forward-only", action="store_true",
                       help="grow only: link a source to wherever its peak lands, with no back-landing "
                            "requirement; the pick arbitrates. Subsumes merge-target.")
    score.add_argument("--engine", default="device", choices=("device", "host"))
    args = parser.parse_args()

    if args.command == "grade":
        return command_grade(args)
    if args.command == "arc-truth":
        return command_arc_truth(args)
    if args.command == "parallax-truth":
        return command_parallax_truth(args)
    return command_score(args)


if __name__ == "__main__":
    raise SystemExit(main())
