#!/usr/bin/env python3
# PQC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""The compression function's memory as a surface that bends from round to round instead of snapping.

    python examples/00_blob_viz_tools/build_bend_view.py --check          the controls, each able to fail
    python examples/00_blob_viz_tools/build_bend_view.py --sweep          the bend angles as a table, and no page
    python examples/00_blob_viz_tools/build_bend_view.py --fit            fit log n, n log n and exponential to the rise
    python examples/00_blob_viz_tools/build_bend_view.py --invariant      seeds compared with rotation taken away
    python examples/00_blob_viz_tools/build_bend_view.py --residue --chain    what the break leaves, with its floor
    python examples/00_blob_viz_tools/build_bend_view.py                  write the page
    python examples/00_blob_viz_tools/build_bend_view.py --samples 8000 --degrees 16 --out bend.html

  --samples   random blocks per seed, each flipped at one input bit. Default 4000.
  --degrees   highest harmonic degree carried. Default 12.
  --word      flip only bits of this message word, 0 to 15. Default: any of the 512 bits. In a
              block header the nonce is word 3 of the second compression block.
  --chain     measure real block headers from utils/maint/chain instead of random blocks: the flip goes
              into the second compression block, run from each header's own midstate. Even heights
              are one set and odd heights the other. --word defaults to 3, the nonce, and
              --samples, when given, cuts each half to that many headers.
  --reseed    with --chain, draw which nonce bit each header flips from a different pair of seeds.
              Zero, the default, is the fixed reference pair. A shape that is real comes back
              at the same rounds under a new seed; a chance excursion moves.
  --residue   what is left after the break, read bit by bit instead of through the sphere: see
              `_residue`.
  --draws     pairs of fair rounds drawn through the basis for the null band. Default 1000, which
              puts 25 readings in each tail; each pair costs two full projections.
  --out       where to write. Default: build/view/bend_view.html at the tree top.
  --set       opening settings for the page, as the other builders take them.

WHAT IS MEASURED

Draw a random 512 bit block, flip one input bit, and run both through the compression function,
keeping the output (H0 plus state) after EVERY round instead of only the last. For each round and
each of the 256 output bits, the flip rate's signed departure from one half is how much that bit
still follows the flipped input at that depth. An untouched bit departs by -0.5; a fair bit by
zero.

Each output bit has a fixed direction on the sphere, taken from the same golden spiral the sphere
view uses, and a fixed depth. The boundary field is then linear in the 256 departures. Every
round is one set of harmonic coefficients and the shape of round r is a linear image of round r.

WHY BEND AND NOT FADE

Going from round r to round r + 1 by crossfading the coefficients passes through their average. For
two patterns at an angle Omega in the degree's own coefficient space, the average has norm
cos(Omega / 2) of the ends, which is 0.707 for orthogonal patterns: the shape collapses toward a
plain sphere and reinflates. That collapse is the snap. Rotating each degree's pattern along the
great circle joining the two (slerp), with its norm interpolated geometrically, keeps the power
through the whole transition. One shape turns into the next the way metal bends.

WHAT THE BEND ANSWERS

The bend angle between consecutive rounds is a measurement. If round r + 1 carries on from round r
the angle is well under 90 degrees. If the function has forgotten, the angle sits where two
independent random shapes put it. Three curves separate those, and each is needed:

    same seed      round r against round r + 1, from one set of samples
    cross seed     round r from one set against round r + 1 from an independent set, which removes
                   any smoothness that only exists because both rounds were read from the same draws
    repeat         round r from one set against round r from the other, a measure of how reproducible
                   a round's own shape is; where this reaches the random band the shape is noise

The band is DRAWN: rounds of fair bits, exact binomial counts, pushed through this view's own
placement and kernel, many pairs, and the 2.5 and 97.5 percentiles of their angle. Nothing is
derived and nothing is picked. See `drawn_band` for why the basis matters.

MEASURED at 4000 samples per seed, degrees 1 to 12, 1000 drawn pairs: the band is 73.3 to
105.8 degrees. All three curves carry through round 20 and sit in the band from round 21. Past the
break the tails hold 0 and 2, 1 and 0, 1 and 2 readings of 43 or 44, against 1.1 each by chance.

WHAT IS HELD

Every number this writes is about SHA-256 and sits under the fail-closed partition as HELD. No row
is added for it anywhere.
"""

import hashlib
import io
import json
import math
import os
import random
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_sha_sphere_view  # noqa: E402
import out_path  # noqa: E402
import settings  # noqa: E402
import sphere_field  # noqa: E402
import generate_template

TEMPLATE = os.path.join(HERE, "bend_view_template.html")

ROUNDS = 64
MASK = 0xFFFFFFFF

# One depth for every source. The only thing that changes between rounds is the departure vector
# and the field stays a linear image of it. The sphere view scales depth by each round's hottest bit,
# which is nonlinear in the data and would make the transition between rounds partly a change of
# kernel and not of memory.
DEPTH = 0.8

SEED_FIRST = 1
SEED_SECOND = 2
SEED_NULL = 7


def round_outputs(block, start=None):
    """The compression output, the starting state plus the round state, after every one of the 64 rounds.

    One run of the rounds with the output read at each step. Stopping and restarting for each round
    count would cost sixty four runs per block for the same numbers.

    `start` is the chaining value the compression begins from and feeds forward into. None is H0,
    the first block of any message. The second block of a block header begins from the midstate the
    first block left, and reading it from H0 instead measures a compression no miner ever runs.
    """
    rotate = build_sha_sphere_view.rotate
    constants = build_sha_sphere_view.K
    if start is None:
        start = build_sha_sphere_view.H0
    words = list(block)
    for index in range(16, ROUNDS):
        low = words[index - 15]
        high = words[index - 2]
        mixed_low = rotate(low, 7) ^ rotate(low, 18) ^ (low >> 3)
        mixed_high = rotate(high, 17) ^ rotate(high, 19) ^ (high >> 10)
        words.append((words[index - 16] + mixed_low + words[index - 7] + mixed_high) & MASK)

    first, second, third, fourth, fifth, sixth, seventh, eighth = start
    outputs = []
    for index in range(ROUNDS):
        spread_e = rotate(fifth, 6) ^ rotate(fifth, 11) ^ rotate(fifth, 25)
        choose = (fifth & sixth) ^ (~fifth & seventh)
        carry_one = (eighth + spread_e + choose + constants[index] + words[index]) & MASK
        spread_a = rotate(first, 2) ^ rotate(first, 13) ^ rotate(first, 22)
        majority = (first & second) ^ (first & third) ^ (second & third)
        carry_two = (spread_a + majority) & MASK
        eighth, seventh, sixth, fifth = seventh, sixth, fifth, (fourth + carry_one) & MASK
        fourth, third, second, first = third, second, first, (carry_one + carry_two) & MASK
        state = (first, second, third, fourth, fifth, sixth, seventh, eighth)
        outputs.append([(start[at] + state[at]) & MASK for at in range(8)])
    return outputs


def add_to_counter(planes, mask):
    """Add one 32 bit mask to a bit-sliced counter, one count per bit position.

    `planes[k]` holds bit k of all thirty two counts at once, adding a mask is a ripple carry
    across the planes and touches each plane once at most. Counting the thirty two bits one at a
    time would cost thirty two operations per word per round per sample.
    """
    carry = mask
    level = 0
    while carry:
        if level == len(planes):
            planes.append(0)
        overflow = planes[level] & carry
        planes[level] ^= carry
        carry = overflow
        level += 1


def counter_values(planes):
    """Read the thirty two counts back out of a bit-sliced counter."""
    out = [0] * 32
    for level, plane in enumerate(planes):
        for shift in range(32):
            if (plane >> shift) & 1:
                out[shift] += 1 << level
    return out


def departures(seed, samples, word=None):
    """Signed flip rate departure from one half, per round and per output bit.

    Returns ROUNDS rows of 256, bit 0 being the most significant bit of the first output word, the
    order the sphere view places them in.

    `word` restricts the flipped input bit to one of the sixteen message words. None flips any of
    the 512 bits, which blends the words together: word w reaches nothing before round w. The
    blend's break is an average over sixteen entry rounds and belongs to no single one of them. In a
    block header the nonce is bytes 76 to 79, which is word 3 of the second compression block, and
    that is the word whose break bears on the nonce.

    SIGNED AND NOT ABSOLUTE. The sphere view takes |rate - 1/2|, which folds sampling noise onto one
    side and gives every bit a positive floor. A field built from that is no longer mean zero above
    degree zero, and the random band would no longer be the right null for it. The signed departure
    keeps the noise centered, a round with nothing in it has nothing above degree zero.
    """
    stream = build_sha_sphere_view.draw(seed)
    counters = [[[] for _ in range(8)] for _ in range(ROUNDS)]
    for _ in range(samples):
        block = [next(stream) & MASK for _ in range(16)]
        if word is None:
            which = next(stream) % 512
        else:
            which = word * 32 + next(stream) % 32
        twin = list(block)
        twin[which // 32] ^= 1 << (which % 32)
        before = round_outputs(block)
        after = round_outputs(twin)
        for index in range(ROUNDS):
            row_before = before[index]
            row_after = after[index]
            row_counter = counters[index]
            # NOT `word`. That name is the parameter choosing which message word is flipped, and a
            # loop over output words named `word` would overwrite it, leaving every later sample
            # flipping message word 7 whatever was asked.
            for output_word in range(8):
                flipped = row_before[output_word] ^ row_after[output_word]
                if flipped:
                    add_to_counter(row_counter[output_word], flipped)

    out = []
    for index in range(ROUNDS):
        row = []
        for output_word in range(8):
            counts = counter_values(counters[index][output_word])
            for shift in range(31, -1, -1):
                row.append(counts[shift] / float(samples) - 0.5)
        out.append(row)
    return out


CHAIN_FILES = ("blocks.json", "blocks_2021.json", "blocks_ban_2021.json", "blocks_deep.json",
               "blocks_labeled.json")


def chain_directory():
    """utils/maint/chain, found by walking up from this file to the directory that holds it.

    Walked and not counted, because this tool's depth below the tree top is not something it gets
    to assume. Returns None when no ancestor holds utils/maint/chain, and the caller refuses by name.
    """
    at = HERE
    while True:
        candidate = os.path.join(at, "utils", "maint", "chain")
        if os.path.isdir(candidate):
            return candidate
        parent = os.path.dirname(at)
        if parent == at:
            return None
        at = parent


def header_bytes(block, nonce=None):
    """The exact eighty byte header, laid out the way examples/00_blob_viz_tools/chain_kat.py lays it out.

    Rebuilt here and not imported, because chain_kat.py imports numpy at load and this tree bans it.
    The two hashes are display hex and carried reversed; everything else is a little endian integer.
    A wrong byte order still yields a header-shaped object, and so every header is checked
    against its own block id before it is used.
    """
    version = int(block["version"])
    previous = bytes.fromhex(block["previousblockhash"])[::-1]
    merkle = bytes.fromhex(block["merkle_root"])[::-1]
    timestamp = int(block["timestamp"])
    bits = int(block["bits"], 16) if isinstance(block["bits"], str) else int(block["bits"])
    used = int(block["nonce"]) if nonce is None else int(nonce)
    return (struct.pack("<I", version & MASK) + previous + merkle + struct.pack("<I", timestamp & MASK)
            + struct.pack("<I", bits & MASK) + struct.pack("<I", used & MASK))


def block_id(header):
    """The block id as displayed: double SHA-256 of the header, reversed."""
    return hashlib.sha256(hashlib.sha256(header).digest()).digest()[::-1].hex()


def header_words(header):
    """The first block's sixteen words, and the second block's, padded for an eighty byte message."""
    first = [int.from_bytes(header[at:at + 4], "big") for at in range(0, 64, 4)]
    tail = bytearray(header[64:80])
    tail.append(0x80)
    while len(tail) < 56:
        tail.append(0x00)
    tail.extend((640).to_bytes(8, "big"))
    second = [int.from_bytes(bytes(tail[at:at + 4]), "big") for at in range(0, 64, 4)]
    return first, second


def load_chain():
    """Every distinct block in the chain corpus whose rebuilt header reproduces its own id.

    Returns (verified blocks sorted by height, files read, blocks refused). The five files overlap.
    Blocks are taken once each by id. A block that fails its own id is refused and counted, never
    silently dropped, because a corpus that loses blocks without saying so looks like a smaller
    clean corpus.
    """
    directory = chain_directory()
    if directory is None:
        return None, 0, 0
    seen = {}
    read = 0
    for name in CHAIN_FILES:
        path = os.path.join(directory, name)
        if not os.path.isfile(path):
            continue
        read += 1
        with io.open(path, encoding="utf-8") as handle:
            for block in json.load(handle):
                seen.setdefault(block["id"], block)
    verified, refused = [], 0
    for block in seen.values():
        if block_id(header_bytes(block)) == block["id"]:
            verified.append(block)
        else:
            refused += 1
    verified.sort(key=lambda block: block["height"])
    return verified, read, refused


def chain_halves(blocks):
    """Even heights and odd heights, trimmed to equal size by dropping the highest of the larger.

    Two sets of real headers sharing no block, interleaved so both eras fall in both. Equal size.
    One drawn null serves both; the drop is stated and not left to whichever half ran long.
    """
    even = [block for block in blocks if block["height"] % 2 == 0]
    odd = [block for block in blocks if block["height"] % 2 == 1]
    size = min(len(even), len(odd))
    return even[:size], odd[:size]


def chain_departures(blocks, seed, word=3):
    """Signed flip rate departure per round and per output bit, over real headers.

    One sample per header: flip a random bit of `word` in the SECOND compression block, starting
    from that header's own midstate. Word 3 there is the nonce. The other words of that block are the
    merkle tail, the timestamp and the bits for words 0 to 2, and fixed padding from word 4 on, a
    flip in a padding word probes a variation no real header carries.
    """
    stream = build_sha_sphere_view.draw(seed)
    counters = [[[] for _ in range(8)] for _ in range(ROUNDS)]
    for block in blocks:
        header = header_bytes(block)
        first_words, second_words = header_words(header)
        midstate = build_sha_sphere_view.compress(first_words, ROUNDS)
        which = word * 32 + next(stream) % 32
        twin = list(second_words)
        twin[which // 32] ^= 1 << (which % 32)
        before = round_outputs(second_words, midstate)
        after = round_outputs(twin, midstate)
        for index in range(ROUNDS):
            row_counter = counters[index]
            for output_word in range(8):
                flipped = before[index][output_word] ^ after[index][output_word]
                if flipped:
                    add_to_counter(row_counter[output_word], flipped)

    count = float(len(blocks))
    out = []
    for index in range(ROUNDS):
        row = []
        for output_word in range(8):
            counts = counter_values(counters[index][output_word])
            for shift in range(31, -1, -1):
                row.append(counts[shift] / count - 0.5)
        out.append(row)
    return out


def source_basis(top, directions):
    """Kernel times harmonics for every source direction, computed once.

    The field of round r is the sum over sources of departure times this basis. The basis is the
    only expensive part and it does not depend on the round. `sphere_field.coefficients` recomputes
    the harmonics for every source on every call, which is right for one field and wasteful for a
    hundred and twenty eight of them; `_check` holds the two routes to the same numbers.
    """
    gains = sphere_field.kernel(top, DEPTH, 0.0)
    out = []
    for colatitude, longitude in directions:
        rows = sphere_field.harmonics_at(top, colatitude, longitude)
        flat = []
        for degree in range(top + 1):
            for value in rows[degree]:
                flat.append(gains[degree] * value)
        out.append(flat)
    return out


def field_of(basis, strengths):
    """Flat coefficients, degree by degree in the storage order sphere_field uses."""
    size = len(basis[0])
    out = [0.0] * size
    for strength, row in zip(strengths, basis):
        if strength == 0.0:
            continue
        for index in range(size):
            out[index] += strength * row[index]
    return out


def degree_slices(top):
    """Where each degree's coefficients sit in the flat vector."""
    out = []
    start = 0
    for degree in range(top + 1):
        out.append((start, start + 2 * degree + 1))
        start += 2 * degree + 1
    return out


def angle_between(first, second):
    """Angle between two vectors, in degrees, or None when either has no length.

    None and not zero or ninety, because a vector with no length has no direction and any number
    reported for it would read as a measurement.
    """
    dot = sum(one * two for one, two in zip(first, second))
    length_first = math.sqrt(sum(one * one for one in first))
    length_second = math.sqrt(sum(two * two for two in second))
    if length_first == 0.0 or length_second == 0.0:
        return None
    cosine = max(-1.0, min(1.0, dot / (length_first * length_second)))
    return math.degrees(math.acos(cosine))


def slerp(first, second, fraction):
    """One degree's coefficients a fraction of the way along the bend from `first` to `second`.

    Direction follows the great circle between the two unit vectors and the norm moves
    geometrically. The power neither dips nor bulges on the way. Where the two are parallel the
    great circle is undefined and the straight line is the same path.
    """
    # A single number has no great circle to follow. Degree zero is one coefficient, and past the
    # break its sign wanders; two unit vectors of opposite sign in one dimension sit at an angle of
    # pi with nothing perpendicular to turn through, and the formula below divides by sin(pi), which
    # in floating point is 1.2e-16 and not zero. The straight line is the only path there is.
    if len(first) == 1:
        return [first[0] + (second[0] - first[0]) * fraction]
    length_first = math.sqrt(sum(one * one for one in first))
    length_second = math.sqrt(sum(two * two for two in second))
    if length_first == 0.0 or length_second == 0.0:
        return [one + (two - one) * fraction for one, two in zip(first, second)]
    unit_first = [one / length_first for one in first]
    unit_second = [two / length_second for two in second]
    cosine = max(-1.0, min(1.0, sum(one * two for one, two in zip(unit_first, unit_second))))
    omega = math.acos(cosine)
    length = length_first ** (1.0 - fraction) * length_second ** fraction
    if math.sin(omega) == 0.0:
        return [(one + (two - one) * fraction) * length for one, two in zip(unit_first, unit_second)]
    weight_first = math.sin((1.0 - fraction) * omega) / math.sin(omega)
    weight_second = math.sin(fraction * omega) / math.sin(omega)
    return [(weight_first * one + weight_second * two) * length
            for one, two in zip(unit_first, unit_second)]


def fair_departures(generator, samples):
    """One round's departures for 256 bits that remember nothing, drawn exactly.

    Each bit's flip count is a sum of `samples` fair coins, taken as the population count of that
    many random bits. That is the binomial itself and not a normal approximation to it.
    """
    # bit_count and not bin().count("1"): the same count of the same draw, measured at 5.4 against
    # 33.0 microseconds for a 7077 bit draw. Every drawn null is unchanged and six times cheaper.
    return [generator.getrandbits(samples).bit_count() / float(samples) - 0.5
            for _ in range(256)]


def drawn_band(basis, samples, draws, seed):
    """The angle between two rounds that remember nothing, drawn through this view's own basis.

    Returns (2.5th percentile, median, 97.5th percentile) over `draws` pairs.

    WHY THROUGH THE BASIS AND NOT BETWEEN RANDOM VECTORS. The real noise is not isotropic in the
    coefficient dimension, 168 at degree 12: the kernel weights degree l by DEPTH to the l. The low
    degrees carry most of it and the effective dimension is far below 168. A band drawn from
    isotropic Gaussian vectors in the nominal dimension comes out too narrow, and past the break
    both tails of every curve overflow it: the null reporting its own shape as a finding.

    Pushing fair bits through the same placement and the same kernel draws the band from the
    distribution the measurement actually has.
    """
    generator = random.Random(seed)
    angles = []
    for _ in range(draws):
        first = field_of(basis, fair_departures(generator, samples))
        second = field_of(basis, fair_departures(generator, samples))
        found = angle_between(first[1:], second[1:])
        if found is not None:
            angles.append(found)
    angles.sort()
    count = len(angles)
    return (angles[int(0.025 * (count - 1))], angles[int(0.5 * (count - 1))],
            angles[int(0.975 * (count - 1))])


def above_zero(flat, top):
    """Everything above degree zero, the shape; degree zero is only the size."""
    return flat[1:]


def shape_energy(flat):
    """The size of the shape, the norm of everything above degree zero."""
    return math.sqrt(sum(value * value for value in flat[1:]))


def drawn_energy(basis, samples, draws, seed):
    """The shape energy a round of fair bits has, drawn through this view's own basis.

    Returns (2.5th percentile, median, 97.5th percentile) over `draws` rounds.

    THE ANGLE CANNOT SEE THIS AND IT IS A SEPARATE QUESTION. The bend angle asks whether a shape
    points where the last one did. A round could carry information as EXCESS SIZE while pointing
    somewhere random, and the angle test would pass it as noise. A round whose shape energy sits
    above what fair bits produce is carrying something the angle does not report.
    """
    generator = random.Random(seed)
    energies = []
    for _ in range(draws):
        energies.append(shape_energy(field_of(basis, fair_departures(generator, samples))))
    energies.sort()
    count = len(energies)
    return (energies[int(0.025 * (count - 1))], energies[int(0.5 * (count - 1))],
            energies[int(0.975 * (count - 1))])


def measure(samples, top, draws, word=None, chain=None):
    """Every curve the page draws and the sweep prints, from two independent sets of samples.

    `chain` is None for random blocks, or a dict holding the two header sets from `chain_halves` as
    "first" and "second", each already cut to `samples` headers, and the two seeds that pick which
    nonce bit each header has flipped as "seeds". The halves share no header. The cross seed and
    repeat curves compare two independent sets of real blocks the way they compare two seeds.
    """
    directions = build_sha_sphere_view.place("spiral")
    basis = source_basis(top, directions)
    if chain is None:
        first_rows = departures(SEED_FIRST, samples, word)
        second_rows = departures(SEED_SECOND, samples, word)
        source = ("any of the 512 input bits" if word is None
                  else "message word %d only, random blocks" % word)
    else:
        first_rows = chain_departures(chain["first"], chain["seeds"][0], word)
        second_rows = chain_departures(chain["second"], chain["seeds"][1], word)
        source = ("word %d of the second compression block, from each header's own midstate,"
                  " even heights against odd heights, bit seeds %d and %d"
                  % (word, chain["seeds"][0], chain["seeds"][1]))
    first_fields = [field_of(basis, row) for row in first_rows]
    second_fields = [field_of(basis, row) for row in second_rows]

    slices = degree_slices(top)
    same, cross, repeat = [], [], []
    per_degree = []
    for index in range(ROUNDS):
        repeat.append(angle_between(above_zero(first_fields[index], top),
                                    above_zero(second_fields[index], top)))
        if index + 1 < ROUNDS:
            same.append(angle_between(above_zero(first_fields[index], top),
                                      above_zero(first_fields[index + 1], top)))
            cross.append(angle_between(above_zero(first_fields[index], top),
                                       above_zero(second_fields[index + 1], top)))
            row = []
            for degree in range(1, top + 1):
                low, high = slices[degree]
                row.append(angle_between(first_fields[index][low:high],
                                         first_fields[index + 1][low:high]))
            per_degree.append(row)

    band = drawn_band(basis, samples, draws, SEED_NULL)
    energy_band = drawn_energy(basis, samples, draws, SEED_NULL + 1)
    entries = [entry_round(first_rows), entry_round(second_rows)]
    entry = None if None in entries else max(entries)
    return {
        "source": source,
        "entry": entry,
        "directions": directions,
        "basis": basis,
        "first_rows": first_rows,
        "second_rows": second_rows,
        "first_fields": first_fields,
        "second_fields": second_fields,
        "energy_first": [shape_energy(field) for field in first_fields],
        "energy_second": [shape_energy(field) for field in second_fields],
        "energy_band": energy_band,
        "same": same,
        "cross": cross,
        "repeat": repeat,
        "per_degree": per_degree,
        "band": band,
    }


def entry_round(rows):
    """The first round index where any output bit flipped in any sample, or None when none ever did.

    Rounds before the flipped word enters are not measurements. Every bit reads exactly -0.5, the
    fields of those rounds are identical, and the angle between identical fields is zero, which the
    carry would count as a perfect match. For word 3 that reported the shape "carrying through round
    2" and set the break before the word had entered at all.
    """
    for index, row in enumerate(rows):
        if any(value != -0.5 for value in row):
            return index
    return None


def carry_through(curve, band, start=0):
    """The last round index of the LEADING run below the drawn band's lower edge, or None.

    The run starts at `start`, the entry round, because nothing before it was measured.

    WHY THE LEADING RUN AND NOT THE LAST DIP. The band is a 95 percent interval for one pair, and
    past the break about forty rounds are pure noise, a curve is expected to dip under the band
    about once by chance. Taking the last dip anywhere reports shape carrying through round 56 off
    a single 71 degree reading at round 41 and a 78 at round 56. The loudest of many readings against a one-reading bar is how a sweep manufactures findings, and
    anisotropy_detector.py already records that rule.

    Carry depth is where the curve first enters the band. Later dips are counted separately by
    `chance_dips` against what the band itself predicts.
    """
    found = None
    for index in range(start, len(curve)):
        value = curve[index]
        if value is None or value >= band[0]:
            break
        found = index
    return found


def chance_dips(curve, band, after):
    """Readings past index `after` under the band and over it, against what chance predicts for each.

    Each edge of the band is a 2.5 percent tail. With no structure at all 2.5 percent of the
    readings past the break fall under it and 2.5 percent over it. Both tails are counted because
    an overflow on both sides at once is what a band of the wrong shape produces, and an overflow on
    one side only is what structure produces.
    """
    start = 0 if after is None else after + 1
    tail = [value for value in curve[start:] if value is not None]
    under = sum(1 for value in tail if value < band[0])
    over = sum(1 for value in tail if value > band[2])
    return under, over, 0.025 * len(tail), len(tail)


def _sweep(samples, top, draws, word=None, chain=None):
    result = measure(samples, top, draws, word, chain)
    band = result["band"]
    print("  flipped bit in %s" % result["source"])
    print("  %d samples per seed, degrees 1 to %d, dimension %d"
          % (samples, top, (top + 1) * (top + 1) - 1))
    print("  band for rounds that remember nothing, fair bits through this basis, %d pairs:" % draws)
    print("  %.2f to %.2f degrees, median %.2f" % (band[0], band[2], band[1]))
    print("")
    energy_band = result["energy_band"]
    print("  shape energy of a fair round, drawn the same way: %.5f to %.5f, median %.5f"
          % (energy_band[0], energy_band[2], energy_band[1]))
    print("")
    print("  %6s %12s %12s %12s %12s %12s"
          % ("round", "same seed", "cross seed", "repeat", "energy A", "energy B"))

    def shown(value):
        return "%12s" % ("-" if value is None else "%.2f" % value)

    for index in range(ROUNDS):
        same = result["same"][index] if index < len(result["same"]) else None
        cross = result["cross"][index] if index < len(result["cross"]) else None
        print("  %6d %s %s %s %12.5f %12.5f"
              % (index + 1, shown(same), shown(cross), shown(result["repeat"][index]),
                 result["energy_first"][index], result["energy_second"][index]))
    print("")
    print("  %-50s %-10s %s" % ("", "carries", "after the break: under / over the band, chance each"))
    for label, key in (("shape carries into the next round, same seed", "same"),
                       ("shape carries into the next round, cross seed", "cross"),
                       ("a round's own shape reproduces across seeds", "repeat")):
        depth = carry_through(result[key], band, result["entry"] or 0)
        under, over, expected, tail = chance_dips(result[key], band, depth)
        print("  %-50s %-10s %d / %d of %d, chance %.1f each"
              % (label, _round_label(depth), under, over, tail, expected))

    print("")
    depth = carry_through(result["repeat"], band, result["entry"] or 0)
    start = 0 if depth is None else depth + 1
    for label, key in (("seed A", "energy_first"), ("seed B", "energy_second")):
        tail = result[key][start:]
        under = sum(1 for value in tail if value < energy_band[0])
        over = sum(1 for value in tail if value > energy_band[2])
        print("  shape energy after the break, %s: %d under / %d over the fair band of %d rounds,"
              " chance %.1f each" % (label, under, over, len(tail), 0.025 * len(tail)))
    return 0


def _round_label(index):
    return "none" if index is None else "round %d" % (index + 1)


def degree_spectrum(flat, top):
    """Power per degree from 1 to `top`. Rotating the sphere leaves every one of these unchanged."""
    out = []
    for degree in range(1, top + 1):
        low = degree * degree
        out.append(sum(value * value for value in flat[low:low + 2 * degree + 1]))
    return out


def pearson(first, second):
    """Correlation of two equal-length lists, or None when either is constant."""
    count = float(len(first))
    mean_first = sum(first) / count
    mean_second = sum(second) / count
    spread_first = math.sqrt(sum((value - mean_first) ** 2 for value in first))
    spread_second = math.sqrt(sum((value - mean_second) ** 2 for value in second))
    if spread_first == 0.0 or spread_second == 0.0:
        return None
    return sum((one - mean_first) * (two - mean_second)
               for one, two in zip(first, second)) / (spread_first * spread_second)


def rotation_invariant(result, samples, top, draws):
    """Whether two independent seeds agree on a round's shape once orientation is taken away.

    WHY ROTATION. The angle between seed A's round and seed B's asks whether they point the same way.
    Structure that is real but not tied to where the placement put it would show up in both seeds at
    different orientations and fail that test. Power per degree does not change under rotation.
    Two seeds carrying one structure agree on it whatever the orientation.

    WHY NOT CORRELATE THE RAW SPECTRA. The kernel tilts every spectrum the same way, DEPTH to the 2l
    times (2l + 1). Two rounds of pure noise have spectra that correlate strongly across degree.
    Each spectrum is divided by the fair spectrum first, drawn as the mean over fair rounds through
    this basis, and the comparison is of the residual shape: which degrees carry more than fair bits
    give and which carry less. The null for that correlation is drawn from pairs of fair rounds,
    independent of the draws that set the fair spectrum.
    """
    basis = result["basis"]
    generator = random.Random(SEED_NULL + 2)
    fair_spectra = [degree_spectrum(field_of(basis, fair_departures(generator, samples)), top)
                    for _ in range(draws)]
    expected = [sum(spectrum[degree] for spectrum in fair_spectra) / float(draws)
                for degree in range(top)]

    def normalized(flat):
        return [power / expected[degree] if expected[degree] > 0.0 else 0.0
                for degree, power in enumerate(degree_spectrum(flat, top))]

    null = []
    generator = random.Random(SEED_NULL + 3)
    for _ in range(draws):
        first = normalized(field_of(basis, fair_departures(generator, samples)))
        second = normalized(field_of(basis, fair_departures(generator, samples)))
        found = pearson(first, second)
        if found is not None:
            null.append(found)
    null.sort()
    count = len(null)
    band = (null[int(0.025 * (count - 1))], null[int(0.5 * (count - 1))], null[int(0.975 * (count - 1))])

    rows = []
    for index in range(ROUNDS):
        first = normalized(result["first_fields"][index])
        second = normalized(result["second_fields"][index])
        rows.append((pearson(first, second), sum(first) / top, sum(second) / top))
    return band, rows


def _invariant(samples, top, draws, word=None, chain=None):
    result = measure(samples, top, draws, word, chain)
    band, rows = rotation_invariant(result, samples, top, draws)
    depth = carry_through(result["repeat"], result["band"], result["entry"] or 0)
    print("  flipped bit in %s" % result["source"])
    print("  seed A against seed B, degree spectra divided by the fair spectrum, rotation removed")
    print("  null, drawn from %d pairs of fair rounds: correlation %.3f to %.3f, median %.3f"
          % (draws, band[0], band[2], band[1]))
    print("  power against fair is the mean over degrees of power divided by the fair power; 1 is fair")
    print("")
    print("  %6s %14s %10s %14s %14s" % ("round", "correlation", "verdict", "power A / fair", "power B / fair"))
    start = result["entry"] or 0
    for index in range(start, ROUNDS):
        correlation, power_first, power_second = rows[index]
        if correlation is None:
            verdict, shown = "no spread", "-"
        else:
            shown = "%.3f" % correlation
            verdict = "over" if correlation > band[2] else ("under" if correlation < band[0] else "in")
        print("  %6d %14s %10s %14.3f %14.3f" % (index + 1, shown, verdict, power_first, power_second))

    after = (depth + 1) if depth is not None else start
    tail = [row[0] for row in rows[after:] if row[0] is not None]
    over = sum(1 for value in tail if value > band[2])
    under = sum(1 for value in tail if value < band[0])
    print("")
    print("  after round %d, where the oriented shape stops reproducing: %d over / %d under the null of"
          " %d rounds, chance %.1f each" % (after, over, under, len(tail), 0.025 * len(tail)))
    return 0


def least_squares(inputs, outputs):
    """Slope and intercept of the straight line through the points, or None when the inputs are flat."""
    count = float(len(inputs))
    mean_in = sum(inputs) / count
    mean_out = sum(outputs) / count
    spread = sum((value - mean_in) ** 2 for value in inputs)
    if spread == 0.0:
        return None
    slope = sum((one - mean_in) * (two - mean_out) for one, two in zip(inputs, outputs)) / spread
    return slope, mean_out - slope * mean_in


# Three models with two parameters each. No model wins by having more to fit with. Each is a
# straight line in a transformed input, and each is scored in the space it is fitted in.
MODELS = (
    ("log n", lambda round_number: math.log(round_number)),
    ("n log n", lambda round_number: round_number * math.log(round_number)),
    ("linear in n", lambda round_number: float(round_number)),
)


def fit_rise(curve, first_index, last_index):
    """Fit the rise of one curve from `first_index` to `last_index` in two spaces.

    In ANGLE space each model is angle = a * g(n) + b. In LOG ANGLE space it is
    log(angle) = a * g(n) + b, where "linear in n" becomes exponential growth and "log n" becomes a
    power law. Both spaces are reported because the question "is this curve log n shaped" does not
    say which space it is asked in, and choosing one would decide the answer before the fit did.

    Returns rows of (space, model, residual sum of squares), sorted within each space.
    """
    rounds = [index + 1 for index in range(first_index, last_index + 1)]
    angles = [curve[index] for index in range(first_index, last_index + 1)]
    if any(value is None or value <= 0.0 for value in angles) or len(rounds) < 3:
        return []
    out = []
    for space, targets in (("angle", angles), ("log angle", [math.log(value) for value in angles])):
        scored = []
        for name, transform in MODELS:
            inputs = [transform(round_number) for round_number in rounds]
            line = least_squares(inputs, targets)
            if line is None:
                continue
            slope, intercept = line
            residual = sum((target - (slope * value + intercept)) ** 2
                           for value, target in zip(inputs, targets))
            scored.append((residual, name))
        scored.sort()
        for residual, name in scored:
            out.append((space, name, residual))
    return out


def _fit(samples, top, draws, word=None, chain=None):
    result = measure(samples, top, draws, word, chain)
    band = result["band"]
    depth = carry_through(result["repeat"], band, result["entry"] or 0)
    print("  flipped bit in %s" % result["source"])
    if depth is None:
        print("  no round's shape reproduces across seeds. There is no rise to fit")
        return 2
    # The rise starts at the quietest transition before the break, where consecutive shapes are
    # closest, and ends at the last transition inside the carry. A transition index i joins rounds i
    # and i + 1. The last one wholly inside the carry is depth - 1.
    for key in ("same", "cross"):
        curve = result[key]
        last = min(depth - 1, len(curve) - 1)
        usable = [index for index in range(0, last + 1) if curve[index] is not None and curve[index] > 0.0]
        if len(usable) < 3:
            print("  %s seed: fewer than three transitions to fit" % key)
            continue
        first = min(usable, key=lambda index: curve[index])
        print("")
        print("  %s seed, transitions from round %d to round %d, %d points"
              % (key, first + 1, last + 2, last - first + 1))
        for space, name, residual in fit_rise(curve, first, last):
            print("    %-10s %-12s residual %.6g" % (space, name, residual))
    return 0


def fair_pair_sums(generator, samples):
    """Two rounds of fair bits and one pattern of signs, reduced to the eight sums a correlation needs.

    Returns (sum x, sum y, sum s, sum xy, sum xs, sum ys, sum xx, sum yy) over the 256 bits.

    WHY SUMS AND NOT THE ROUNDS. A residue of size d shared by both sets adds d times the sign
    pattern to each, and every sum the correlation reads then moves by an exact identity in d:
    sum (x + ds)(y + ds) is sum xy + d sum xs + d sum ys + 256 d squared, and so on. One draw of the
    pair therefore answers every planted size exactly, where drawing fresh pairs for each size would
    cost the whole null again per size and pair nothing with nothing.
    """
    first = fair_departures(generator, samples)
    second = fair_departures(generator, samples)
    pattern = generator.getrandbits(256)
    signs = [1.0 if (pattern >> shift) & 1 else -1.0 for shift in range(256)]
    return (sum(first), sum(second), sum(signs),
            sum(one * two for one, two in zip(first, second)),
            sum(one * sign for one, sign in zip(first, signs)),
            sum(two * sign for two, sign in zip(second, signs)),
            sum(one * one for one in first), sum(two * two for two in second))


def planted_correlation(sums, planted):
    """The correlation of a fair pair once a residue of size `planted` is added to both, or None."""
    total_x, total_y, total_s, cross, cross_x, cross_y, square_x, square_y = sums
    count = 256.0
    shifted_x = total_x + planted * total_s
    shifted_y = total_y + planted * total_s
    shared = cross + planted * (cross_x + cross_y) + planted * planted * count
    power_x = square_x + 2.0 * planted * cross_x + planted * planted * count
    power_y = square_y + 2.0 * planted * cross_y + planted * planted * count
    covariance = shared - shifted_x * shifted_y / count
    spread_x = power_x - shifted_x * shifted_x / count
    spread_y = power_y - shifted_y * shifted_y / count
    if spread_x <= 0.0 or spread_y <= 0.0:
        return None
    return covariance / math.sqrt(spread_x * spread_y)


def _residue(samples, top, draws, word=None, chain=None):
    """What the break leaves behind, read bit by bit, with the smallest residue this run could see.

    THE CLAIM UNDER TEST. Past the break the flip rate of every output bit should sit at one half.
    The two independent sets, even and odd heights, should share nothing but chance. A residue
    the break fails to clear would be a departure pattern both sets carry, and it would show as a
    positive correlation between their 256 raw departures at rounds where the shape has gone.

    WHY RAW BITS AND NOT THE SPHERE. The field keeps degrees 1 to 12, 168 numbers from 256, and
    weights them by the kernel. A residue sitting in the part the projection drops is invisible to
    the angle. The correlation of the raw departures reads all 256.

    WHERE THE BREAK IS. Read from the data: the first round after the flipped word enters whose
    correlation falls inside the drawn band for one pair of fair rounds. That round was CHOSEN for
    sitting low. It is left out, and the residue is read over every round after it.

    THE NULL AND THE FLOOR ARE ONE DRAW. `draws` times the number of rounds after the break, pairs of
    fair rounds, each carrying a sign pattern. The same draws give the band for one round, the band
    for the mean over the rounds after the break, and, by planting a shared residue of size d into
    each pair, how often a residue of that size lifts the mean over the band. The floor is the
    smallest d on a ladder of halvings in power, starting at the sampling spread of one bit, that is
    seen in at least half the draws. A reading inside the band says no residue at or above the floor,
    and nothing about one below it.

    A residue planted this way adds d to a fair draw instead of drawing binomially around one half
    plus d. At the sizes the floor lands on the two differ in the variance by d squared, far below
    the sampling spread.
    """
    result = measure(samples, top, draws, word, chain)
    entry = result["entry"]
    if entry is None:
        print("  the flipped word never reached the output. There is nothing to read")
        return 1
    first_rows = result["first_rows"]
    second_rows = result["second_rows"]
    readings = [pearson(first_rows[index], second_rows[index]) if index >= entry else None
                for index in range(ROUNDS)]

    spread = 0.5 / math.sqrt(samples)
    print("  flipped bit in %s" % result["source"])
    print("  %d samples per set; sampling spread of one bit's flip rate %.6f" % (samples, spread))

    # The band for one round needs no more than the pool below gives, but the break has to be known
    # to size the pool. So the band for one round is drawn first from its own `draws` pairs.
    generator = random.Random(SEED_NULL + 4)
    single = sorted(planted_correlation(fair_pair_sums(generator, samples), 0.0) for _ in range(draws))
    low, high = single[int(0.025 * (draws - 1))], single[int(0.975 * (draws - 1))]
    print("  one pair of fair rounds, %d draws: correlation %.4f to %.4f" % (draws, low, high))

    broken = None
    for index in range(entry, ROUNDS):
        if readings[index] is not None and readings[index] <= high:
            broken = index
            break
    if broken is None or broken == entry:
        print("  CONTROL FAILED the known window did not read above the band before it broke"
              " (entered round %d, first round inside the band %s)"
              % (entry + 1, "none" if broken is None else broken + 1))
        return 1
    tail = list(range(broken + 1, ROUNDS))
    print("  the word enters at round %d; the correlation first falls inside the band at round %d,"
          " which is left out; %d rounds after it are read" % (entry + 1, broken + 1, len(tail)))
    print("")
    print("  %6s %12s %8s" % ("round", "correlation", "band"))
    for index in range(entry, ROUNDS):
        value = readings[index]
        place = "over" if value > high else ("under" if value < low else "in")
        print("  %6d %12.5f %8s" % (index + 1, value, place))

    over_rounds = [index + 1 for index in tail if readings[index] > high]
    under_rounds = [index + 1 for index in tail if readings[index] < low]
    print("")
    print("  after the break, one round at a time: %d over %s, %d under %s, chance %.1f each"
          % (len(over_rounds), over_rounds, len(under_rounds), under_rounds, 0.025 * len(tail)))

    pool_generator = random.Random(SEED_NULL + 5)
    pools = []
    for _ in range(draws):
        pools.append([fair_pair_sums(pool_generator, samples) for _ in tail])

    def means(planted):
        out = []
        for pool in pools:
            values = [planted_correlation(sums, planted) for sums in pool]
            out.append(sum(values) / len(values))
        return out

    null = sorted(means(0.0))
    null_low, null_mid, null_high = (null[int(0.025 * (draws - 1))], null[int(0.5 * (draws - 1))],
                                     null[int(0.975 * (draws - 1))])
    observed = sum(readings[index] for index in tail) / len(tail)
    at_or_above = sum(1 for value in null if value >= observed)
    print("")
    print("  mean correlation over the %d rounds after the break: %.5f" % (len(tail), observed))
    print("  the same mean over fair rounds, %d draws: %.5f to %.5f, median %.5f"
          % (draws, null_low, null_high, null_mid))
    print("  fair draws at or above the reading: %d of %d" % (at_or_above, draws))
    if observed > 0.0:
        print("  a shared residue of %.6f per bit, %.3f of the sampling spread, would give this mean"
              % (spread * math.sqrt(observed / (1.0 - observed)), math.sqrt(observed / (1.0 - observed))))

    print("")
    print("  %22s %22s %24s" % ("planted residue", "share of spread", "draws lifted over band"))
    floor = None
    step = 0
    while True:
        planted = spread * 2.0 ** (-step / 2.0)
        lifted = sum(1 for value in means(planted) if value > null_high)
        print("  %22.7f %22.4f %20d of %d" % (planted, planted / spread, lifted, draws))
        if step == 0 and 2 * lifted < draws:
            print("  CONTROL FAILED a residue the size of the sampling spread was not seen")
            return 1
        if 2 * lifted >= draws:
            floor = planted
        # Stopped where the planted residue lifts no more draws than the band lets through by
        # chance, the point past which the ladder is measuring the band and not the plant.
        if lifted <= 0.025 * draws:
            break
        step += 1
    print("")
    print("  floor: the smallest planted residue seen in at least half the draws is %.7f per bit,"
          " %.4f of the sampling spread" % (floor, floor / spread))
    verdict = ("OVER the fair band" if observed > null_high
               else ("UNDER the fair band" if observed < null_low else "inside the fair band"))
    print("  reading: the mean after the break is %s" % verdict)
    return 0


def build(samples, top, draws, opening, word=None, chain=None):
    result = measure(samples, top, draws, word, chain)
    band = result["band"]
    slices = degree_slices(top)

    # The page recomputes the field and the bend itself. It is given references from this side to
    # grade its own arithmetic against on load. Two routes to the same numbers, and a page whose
    # basis or bend disagrees with this file reports it instead of drawing a plausible wrong shape.
    probe_directions = [(0.4, 0.3), (1.2, 2.2), (2.0, 4.1), (2.9, 5.5), (1.57, 0.0)]
    probe_fields = []
    reference_round = 0
    coefficients = result["first_fields"][reference_round]
    for colatitude, longitude in probe_directions:
        rows = sphere_field.harmonics_at(top, colatitude, longitude)
        total = 0.0
        for degree in range(top + 1):
            low, high = slices[degree]
            for offset, value in enumerate(rows[degree]):
                total += coefficients[low + offset] * value
        probe_fields.append(total)

    halfway = []
    for degree in range(top + 1):
        low, high = slices[degree]
        halfway.extend(slerp(result["first_fields"][0][low:high],
                             result["first_fields"][1][low:high], 0.5))

    return {
        "title": "SHA-256 compression memory, bending round to round",
        "degrees": top,
        "rounds": ROUNDS,
        "samples": samples,
        "depth": DEPTH,
        "fields": [[round(value, 9) for value in field] for field in result["first_fields"]],
        "fields_second": [[round(value, 9) for value in field] for field in result["second_fields"]],
        "energy": {"first": result["energy_first"], "second": result["energy_second"],
                   "low": result["energy_band"][0], "median": result["energy_band"][1],
                   "high": result["energy_band"][2]},
        "same": result["same"],
        "cross": result["cross"],
        "repeat": result["repeat"],
        "per_degree": result["per_degree"],
        "band": {"low": band[0], "median": band[1], "high": band[2], "draws": draws},
        "carry": {
            "same": carry_through(result["same"], band, result["entry"] or 0),
            "cross": carry_through(result["cross"], band, result["entry"] or 0),
            "repeat": carry_through(result["repeat"], band, result["entry"] or 0),
        },
        "reference": {
            "directions": probe_directions,
            "round": reference_round,
            "fields": probe_fields,
            "halfway": halfway,
        },
        "settings": opening,
    }


def _check():
    lines = []
    failed = 0

    def say(text):
        lines.append(text)

    ulp = sys.float_info.epsilon

    # POSITIVE CONTROL, and a null here means nothing without it. A pattern turned by a known angle
    # per step must read back that angle.
    for planted in (10.0, 45.0, 90.0, 135.0):
        radians = math.radians(planted)
        first = [1.0, 0.0, 0.0, 0.0, 0.0]
        second = [math.cos(radians), math.sin(radians), 0.0, 0.0, 0.0]
        got = angle_between(first, second)
        # acos loses about sqrt(ulp) near the ends of its range. The bound is the conditioning of
        # acos at this cosine and not a number picked for comfort.
        bound = math.degrees(math.sqrt(ulp) / max(math.sin(radians), math.sqrt(ulp))) * 4.0
        say("  a pattern turned %.0f degrees reads %.12f" % (planted, got))
        if abs(got - planted) > bound:
            say("    FAIL the angle does not read back what was planted")
            failed += 1

    # THE PROPERTY THE WHOLE VIEW RESTS ON. Between orthogonal patterns a crossfade's midpoint has
    # norm 1/sqrt(2) and a bend's has norm 1. If the bend dipped too, there would be nothing to show.
    first = [1.0, 0.0, 0.0]
    second = [0.0, 1.0, 0.0]
    faded = [0.5 * (one + two) for one, two in zip(first, second)]
    bent = slerp(first, second, 0.5)
    faded_norm = math.sqrt(sum(value * value for value in faded))
    bent_norm = math.sqrt(sum(value * value for value in bent))
    say("  midpoint between orthogonal patterns: fade norm %.12f, bend norm %.12f"
        % (faded_norm, bent_norm))
    if abs(bent_norm - 1.0) > 8.0 * ulp:
        say("    FAIL the bend loses power on the way")
        failed += 1
    if abs(faded_norm - math.sqrt(0.5)) > 8.0 * ulp:
        say("    FAIL the crossfade reference is wrong")
        failed += 1

    # The bend has to land on both ends exactly, or the animation jumps at every round boundary.
    ends = (slerp([3.0, 1.0], [-1.0, 2.0], 0.0), slerp([3.0, 1.0], [-1.0, 2.0], 1.0))
    say("  the bend starts at %s and ends at %s" % (ends[0], ends[1]))
    if max(abs(one - two) for one, two in zip(ends[0], [3.0, 1.0])) > 16.0 * ulp or \
            max(abs(one - two) for one, two in zip(ends[1], [-1.0, 2.0])) > 16.0 * ulp:
        say("    FAIL the bend does not meet its ends")
        failed += 1

    # A vector with no length has no direction, and the angle says so instead of inventing one.
    if angle_between([0.0, 0.0], [1.0, 0.0]) is not None:
        say("    FAIL an empty vector was given an angle")
        failed += 1
    say("  an empty vector is given no angle")

    # Two routes to one field: the cached basis here, and sphere_field.coefficients.
    top = 6
    directions = build_sha_sphere_view.place("spiral")[:40]
    generator = random.Random(3)
    strengths = [generator.uniform(-0.5, 0.5) for _ in directions]
    cached = field_of(source_basis(top, directions), strengths)
    sources = [(strength, DEPTH, colatitude, longitude)
               for strength, (colatitude, longitude) in zip(strengths, directions)]
    direct = [value for row in sphere_field.coefficients(sources, top, 0.0) for value in row]
    worst = max(abs(one - two) for one, two in zip(cached, direct))
    say("  cached basis against sphere_field.coefficients: largest difference %.3e" % worst)
    scale = max(abs(value) for value in direct) or 1.0
    if worst > scale * 64.0 * ulp * len(directions):
        say("    FAIL the two routes to the field disagree")
        failed += 1

    # The bit-sliced counter against counting one bit at a time.
    generator = random.Random(11)
    masks = [generator.getrandbits(32) for _ in range(3000)]
    planes = []
    for mask in masks:
        add_to_counter(planes, mask)
    sliced = counter_values(planes)
    naive = [sum((mask >> shift) & 1 for mask in masks) for shift in range(32)]
    say("  bit-sliced counter against a naive count over 3000 masks: %s"
        % ("agrees" if sliced == naive else "DISAGREES"))
    if sliced != naive:
        failed += 1

    # The round outputs must end on the real compression function's output, or every round before it
    # is a reading of something else.
    block = [generator.getrandbits(32) for _ in range(16)]
    stepped = round_outputs(block)[ROUNDS - 1]
    whole = build_sha_sphere_view.compress(block, ROUNDS)
    say("  round %d of the stepped run equals the full compression: %s" % (ROUNDS, stepped == whole))
    if stepped != whole:
        failed += 1
    partway = round_outputs(block)[15]
    stopped = build_sha_sphere_view.compress(block, 16)
    say("  round 16 of the stepped run equals a compression stopped at 16: %s" % (partway == stopped))
    if partway != stopped:
        failed += 1

    # THE FLIPPED WORD HAS TO BE THE WORD ASKED FOR. Message word w is added into temp1 at round w + 1
    # and at no earlier round, and addition is injective, a flip of word w leaves every output of
    # rounds 1 to w untouched and changes the round w + 1 output in every single sample. That is an
    # exact count and no bound is needed. It is the check that would have caught a loop variable
    # spelled `word` overwriting the parameter and flipping word 7 in every sample after the first.
    for chosen in (3, 15):
        per_sample = 64
        rows = departures(SEED_FIRST, per_sample, chosen)
        before_entry = sum(value + 0.5 for index in range(chosen) for value in rows[index])
        at_entry = sum(value + 0.5 for value in rows[chosen]) * per_sample
        say("  word %d: flips counted before round %d: %.0f; bit flips at round %d over %d samples: %.0f"
            % (chosen, chosen + 1, before_entry * per_sample, chosen + 1, per_sample, at_entry))
        if before_entry != 0.0:
            say("    FAIL a round before word %d enters shows a flip" % chosen)
            failed += 1
        if at_entry < per_sample:
            say("    FAIL round %d shows fewer flipped bits than samples. Word %d was not the one flipped"
                % (chosen + 1, chosen))
            failed += 1

    # THE HEADER ROUTE, against a block whose id is fixed and public: the genesis block. The corpus
    # check in `load_chain` compares each header to its own id, but a check that has only ever seen
    # the corpus cannot say whether the corpus or the layout is at fault, and one that has never
    # refused anything has not been shown to refuse. The same header with the nonce moved by one
    # must NOT reproduce the id.
    genesis = {"version": 1, "previousblockhash": "00" * 32,
               "merkle_root": "4a5e1e4baab89f3a32518a88c31bc87f618f76673e2cc77ab2127b7afdeda33b",
               "timestamp": 1231006505, "bits": "1d00ffff", "nonce": 2083236893,
               "id": "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"}
    header = header_bytes(genesis)
    matches = block_id(header) == genesis["id"]
    moved = block_id(header_bytes(genesis, genesis["nonce"] + 1)) == genesis["id"]
    say("  genesis header rebuilt reproduces its id: %s; with the nonce moved by one: %s" % (matches, moved))
    if not matches:
        say("    FAIL the header layout does not rebuild a known block")
        failed += 1
    if moved:
        say("    FAIL a wrong nonce reproduced the id. The id comparison refuses nothing")
        failed += 1

    # Two routes to the first SHA-256 of that header: the library, and the second compression block
    # stepped round by round from the midstate the first block leaves. That is the exact compression
    # `chain_departures` reads. Started from H0 instead it must disagree, or the midstate is inert.
    first_words, second_words = header_words(header)
    midstate = build_sha_sphere_view.compress(first_words, ROUNDS)
    digest = hashlib.sha256(header).digest()
    stepped = b"".join(struct.pack(">I", value) for value in round_outputs(second_words, midstate)[ROUNDS - 1])
    from_h0 = b"".join(struct.pack(">I", value) for value in round_outputs(second_words)[ROUNDS - 1])
    say("  second block from the midstate equals the library's SHA-256 of the header: %s;"
        " from H0 instead: %s" % (stepped == digest, from_h0 == digest))
    if stepped != digest:
        say("    FAIL the second block stepped from the midstate is not the header's hash")
        failed += 1
    if from_h0 == digest:
        say("    FAIL the midstate changed nothing")
        failed += 1

    # The entry count again, now through `chain_departures`: word 3 of the second block is added at
    # round 4. Rounds 1 to 3 show no flip and round 4 shows at least one per header. Headers here
    # are genesis with the timestamp moved. The check needs no corpus on disk.
    headers = [dict(genesis, timestamp=genesis["timestamp"] + offset) for offset in range(64)]
    rows = chain_departures(headers, SEED_FIRST, 3)
    before_entry = sum(value + 0.5 for index in range(3) for value in rows[index]) * len(headers)
    at_entry = sum(value + 0.5 for value in rows[3]) * len(headers)
    say("  chain word 3: flips counted before round 4: %.0f; bit flips at round 4 over %d headers: %.0f"
        % (before_entry, len(headers), at_entry))
    if before_entry != 0.0:
        say("    FAIL a round before the nonce enters shows a flip")
        failed += 1
    if at_entry < len(headers):
        say("    FAIL round 4 shows fewer flipped bits than headers. The nonce was not the word flipped")
        failed += 1

    # Two routes to a planted correlation: the eight sums `_residue` reads every planted size from,
    # and the correlation of the planted rounds formed directly. Drawn twice from one seed so both
    # routes see the same bits. A plant of the opposite sign must NOT agree, or the sums are not
    # carrying the plant at all.
    planted = 0.013
    sums = fair_pair_sums(random.Random(5), 64)
    replay = random.Random(5)
    first = fair_departures(replay, 64)
    second = fair_departures(replay, 64)
    pattern = replay.getrandbits(256)
    signs = [1.0 if (pattern >> shift) & 1 else -1.0 for shift in range(256)]
    direct = pearson([value + planted * sign for value, sign in zip(first, signs)],
                     [value + planted * sign for value, sign in zip(second, signs)])
    opposite = pearson([value - planted * sign for value, sign in zip(first, signs)],
                       [value - planted * sign for value, sign in zip(second, signs)])
    through_sums = planted_correlation(sums, planted)
    bound = 64.0 * ulp * 256.0
    say("  planted correlation from eight sums %.15f, formed directly %.15f, opposite plant %.15f"
        % (through_sums, direct, opposite))
    if abs(through_sums - direct) > bound:
        say("    FAIL the sums do not reproduce the planted correlation")
        failed += 1
    if abs(through_sums - opposite) <= bound:
        say("    FAIL a plant of the opposite sign agrees. The sums do not carry the plant")
        failed += 1

    # And the measurement must be able to tell a structured round from an empty one. Round 1 leaves
    # most output bits untouched. Its departures are far from zero; a fair bit sits at zero.
    rows = departures(SEED_FIRST, 200)
    untouched = sum(1 for value in rows[0] if value == -0.5)
    say("  round 1: %d of 256 output bits never flip, as round 1 must show" % untouched)
    if untouched == 0:
        say("    FAIL round 1 shows no untouched bit. The departures are not reading the rounds")
        failed += 1

    sys.stdout.write("\n".join(lines) + "\n\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


def option(argv, flag, fallback, cast):
    if flag in argv:
        at = argv.index(flag)
        if at + 1 >= len(argv):
            sys.stderr.write("%s needs a value\n" % flag)
            raise SystemExit(2)
        return cast(argv[at + 1])
    return fallback


def main(argv):
    if "--help" in argv or "-h" in argv:
        sys.stdout.write(__doc__)
        return 0
    if "--check" in argv:
        return 1 if _check() else 0

    asked = option(argv, "--samples", None, int)
    top = option(argv, "--degrees", 12, int)
    draws = option(argv, "--draws", 1000, int)
    word = option(argv, "--word", None, int)
    if (asked is not None and asked <= 0) or top <= 0 or draws <= 0:
        sys.stderr.write("samples, degrees and draws must all be positive\n")
        return 2
    if word is not None and not 0 <= word < 16:
        sys.stderr.write("--word names one of the sixteen message words, 0 to 15\n")
        return 2

    chain = None
    samples = 4000 if asked is None else asked
    if "--chain" in argv:
        if word is None:
            word = 3
        blocks, read, refused = load_chain()
        if blocks is None:
            sys.stderr.write("--chain found no utils/maint/chain above %s\n" % HERE.replace("\\", "/"))
            return 2
        if not blocks:
            sys.stderr.write("--chain read %d corpus file(s) and verified no header, %d refused\n"
                             % (read, refused))
            return 2
        even, odd = chain_halves(blocks)
        if asked is not None and asked > len(even):
            sys.stderr.write("--samples %d asks for more headers per half than the %d the corpus holds\n"
                             % (asked, len(even)))
            return 2
        samples = len(even) if asked is None else asked
        # Reseed zero is the fixed reference pair, and an unmarked run reproduces it. A
        # nonzero reseed moves both seeds past the null seeds, which run from SEED_NULL to
        # SEED_NULL + 5, a flip choice never shares a stream with a drawn null.
        reseed = option(argv, "--reseed", 0, int)
        if reseed < 0:
            sys.stderr.write("--reseed takes zero or a positive integer\n")
            return 2
        seeds = ((SEED_FIRST, SEED_SECOND) if reseed == 0
                 else (SEED_NULL + 6 + 2 * reseed, SEED_NULL + 7 + 2 * reseed))
        chain = {"first": even[:samples], "second": odd[:samples], "seeds": seeds}
        print("  chain corpus: %d file(s), %d distinct headers verified against their own ids, %d refused;"
              " %d even and %d odd heights used, heights %d to %d"
              % (read, len(blocks), refused, len(chain["first"]), len(chain["second"]),
                 blocks[0]["height"], blocks[-1]["height"]))
    elif "--reseed" in argv:
        sys.stderr.write("--reseed picks which nonce bits the chain headers flip. It needs --chain\n")
        return 2

    if "--residue" in argv:
        return _residue(samples, top, draws, word, chain)
    if "--sweep" in argv:
        return _sweep(samples, top, draws, word, chain)
    if "--fit" in argv:
        return _fit(samples, top, draws, word, chain)
    if "--invariant" in argv:
        return _invariant(samples, top, draws, word, chain)

    if not os.path.isfile(TEMPLATE):
        sys.stderr.write("no template at %s\n" % TEMPLATE.replace("\\", "/"))
        return 2
    opening = settings.collect(argv)
    payload = build(samples, top, draws, opening, word, chain)

    try:
        page = generate_template.assemble(TEMPLATE, payload)
    except generate_template.Refused as why:
        sys.stderr.write("%s: %s\n" % (os.path.basename(TEMPLATE), why))
        return 1
    if page.count("</script>") < page.count("<script"):
        sys.stderr.write("the template left a script open. The page would not run\n")
        return 1

    out = out_path.resolve("bend_view.html", option(argv, "--out", None, str))
    with io.open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(page)

    band = payload["band"]
    print(out.replace("\\", "/"))
    print("  %d samples per seed, degrees to %d, random band %.2f to %.2f degrees"
          % (samples, top, band["low"], band["high"]))
    print("  shape carries round to round, same seed, through %s"
          % _round_label(payload["carry"]["same"]))
    print("  shape carries round to round, cross seed, through %s"
          % _round_label(payload["carry"]["cross"]))
    print("  a round's own shape reproduces across seeds through %s"
          % _round_label(payload["carry"]["repeat"]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
