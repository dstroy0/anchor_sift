"""The collision-entropy leak as a time series: its mean, its fluctuation, and its trend.

A single number for the leak hides the thing worth knowing. Conventions are set by software, and
software is deployed, updated and retired, so the leak has no reason to hold still. Measured in
sliding windows it has three separable parts, and they answer different questions:

  mean          what the network's conventions cost on average, which is the number that belongs
                in a summary
  fluctuation   how much a window-sized sample wanders. The floor on this is known rather than
                estimated: a window of W blocks manufactures a deficit near log2(1 + (n-1)/W)
                on its own, so anything beyond that is real movement
  trend         whether the mean is going anywhere. A convention spreading or dying shows here and
                nowhere else, and it is the part a single number cannot carry

PER HASH

A block is the expected outcome of difficulty times 2^32 hashes, so the leak per block divided by
that is the leak per hash. It is a very small number and it is the honest intensive quantity: the
network pays this much collision entropy for every hash it computes, and it is paid whether or not
anybody is reading.
"""

import io
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
CORPUS = os.path.join(HERE, "blocks_deep.json")

SHIFT, WIDTH = 13, 16
SPAN = 1 << WIDTH
BUCKETS = 16
WINDOW = 500
STRIDE = 125


def deficit_of(values):
    """Bits of collision entropy the sample gives away against a flat field of BUCKETS width."""
    counts = [0] * BUCKETS
    for v in values:
        counts[v * BUCKETS // SPAN] += 1
    total = len(values)
    expect = total / float(BUCKETS)
    chi = sum((c - expect) ** 2 / expect for c in counts)
    return math.log2(1.0 + chi / total)


with io.open(CORPUS, encoding="utf-8") as handle:
    blocks = json.load(handle)
blocks.sort(key=lambda b: b["height"])
rolled = [(int(b["version"]) >> SHIFT) & (SPAN - 1) for b in blocks]
heights = [b["height"] for b in blocks]
diffs = [b.get("difficulty") for b in blocks]

print("  %d blocks, heights %d..%d" % (len(blocks), heights[0], heights[-1]))
print("  windows of %d blocks, stride %d, %d buckets" % (WINDOW, STRIDE, BUCKETS))
print()

series = []
for start in range(0, len(rolled) - WINDOW, STRIDE):
    chunk = rolled[start:start + WINDOW]
    series.append((heights[start + WINDOW // 2], deficit_of(chunk)))

values = [v for _, v in series]
count = len(values)
mean = sum(values) / count
sd = (sum((v - mean) ** 2 for v in values) / count) ** 0.5
floor = math.log2(1.0 + (BUCKETS - 1) / float(WINDOW))

print("=" * 78)
print("  1. THE MEAN, AND THE FLOOR UNDER IT")
print("=" * 78)
print()
print("    windows           %d" % count)
print("    mean leak         %.4f bits" % mean)
print("    window floor      %.4f bits   (what %d blocks manufacture alone)" % (floor, WINDOW))
print("    mean over floor   %.1f times" % (mean / floor))
print("    of a flat field   %.1f%% of its %.3f bits given away"
      % (100.0 * mean / math.log2(BUCKETS), math.log2(BUCKETS)))

print()
print("=" * 78)
print("  2. THE FLUCTUATION, AGAINST WHAT SAMPLING ALONE PRODUCES")
print("=" * 78)
print()
# The floor here is drawn, not derived. An earlier version of this file computed it analytically -
# chi-square's variance carried through the logarithm - and that expression gave 0.0582 where the
# true floor is 0.1022, understating it by nearly half. Shuffling the values holds the pooled
# distribution exactly fixed and destroys only the time ordering, so every window it produces is a
# sample from one unchanging distribution by construction, and whatever scatter that yields is
# sampling with nothing assumed about its shape.
import random as _random

_rng = _random.Random(0xB007)


def _scatter(sequence):
    out = []
    for start in range(0, len(sequence) - WINDOW, STRIDE):
        out.append(deficit_of(sequence[start:start + WINDOW]))
    middle = sum(out) / len(out)
    return (sum((v - middle) ** 2 for v in out) / len(out)) ** 0.5


_draws = []
for _ in range(400):
    _shuffled = list(rolled)
    _rng.shuffle(_shuffled)
    _draws.append(_scatter(_shuffled))
_draws.sort()
_null_mean = sum(_draws) / len(_draws)
_null_sd = (sum((v - _null_mean) ** 2 for v in _draws) / len(_draws)) ** 0.5
_above = sum(1 for v in _draws if v >= sd)

print("    observed scatter  %.4f bits" % sd)
print("    shuffle null      %.4f bits   (95th percentile %.4f, over %d draws)"
      % (_null_mean, _draws[int(0.95 * len(_draws))], len(_draws)))
print("    separation        %+.2f sd    p = %.4f"
      % ((sd - _null_mean) / _null_sd if _null_sd else 0.0, _above / float(len(_draws))))
print()
if _above <= 0.05 * len(_draws):
    print("    -> the leak moves by more than sampling explains. The conventions themselves")
    print("       are changing across this span, not merely being sampled differently.")
else:
    print("    -> the scatter is what sampling produces. The conventions are steady and the")
    print("       window-to-window wander carries no information.")

print()
print("=" * 78)
print("  3. THE TREND")
print("=" * 78)
print()
xs = [float(h) for h, _ in series]
xm = sum(xs) / count
ym = mean
sxy = sum((xs[i] - xm) * (values[i] - ym) for i in range(count))
sxx = sum((x - xm) ** 2 for x in xs)
slope = sxy / sxx if sxx else 0.0
resid = [values[i] - (ym + slope * (xs[i] - xm)) for i in range(count)]
rsd = (sum(r * r for r in resid) / max(count - 2, 1)) ** 0.5
slope_se = rsd / math.sqrt(sxx) if sxx else 0.0
print("    slope             %+.3e bits per block" % slope)
print("    over the span     %+.4f bits across %d blocks" % (slope * (xs[-1] - xs[0]), len(blocks)))
print("    standard error    %.3e   ->  %+.2f sd" % (slope_se, slope / slope_se if slope_se else 0.0))
print()
if slope_se and abs(slope / slope_se) >= 3.0:
    direction = "rising" if slope > 0 else "falling"
    print("    -> the leak is %s. Whatever sets these conventions is spreading or retiring." % direction)
else:
    print("    -> no trend this corpus can resolve. 48 days is short for a deployment cycle;")
    print("       this wants years, not weeks.")

print()
print("    the series, oldest first:")
widest = max(values)
for height, value in series:
    bar = "#" * int(round(value / widest * 44))
    print("      %8d  %-44s %.4f" % (height, bar, value))

print()
print("=" * 78)
print("  4. PER HASH")
print("=" * 78)
print()
usable = [d for d in diffs if d]
if usable:
    # Stated as hashes PER BIT rather than bits per hash. The reciprocal is a number near
    # 3e-24, which is a float64 approaching its own floor and carries almost no significant
    # figures; its inverse is a large exact integer that says the same thing and can be checked.
    # Everything here is integer arithmetic at full width - no float appears in the result.
    SCALE = 1 << 64
    difficulty = sum(usable) // len(usable)
    hashes_per_block = int(difficulty) * (1 << 32)
    leak_scaled = int(mean * SCALE)          # the one float, converted once, at 64 bits of it
    hashes_per_bit = (hashes_per_block * SCALE) // leak_scaled

    print("    mean difficulty over the span   %s" % format(int(difficulty), ","))
    print("    expected hashes per block       %s" % format(hashes_per_block, ","))
    print("    leak per block                  %.4f bits" % mean)
    print()
    print("    HASHES THE NETWORK MUST COMPUTE TO GIVE AWAY ONE BIT")
    print("      %s" % format(hashes_per_bit, ","))
    print("      %d decimal digits, exact integer arithmetic" % len(str(hashes_per_bit)))
    print()
    rate = 800 * (10 ** 18)                  # network hashrate, order 800 EH/s
    seconds_per_bit = hashes_per_bit // rate
    print("    At a network rate of %s hashes per second, one bit of collision entropy" % format(rate, ","))
    print("    is given away every %s seconds, which is about %d minutes."
          % (format(seconds_per_bit, ","), seconds_per_bit // 60))
    print()
    print("    That is the intensive quantity stated so it can be read: the cost is enormous")
    print("    per bit because a block is enormous, and the leak is paid whether or not")
    print("    anybody is reading it.")
