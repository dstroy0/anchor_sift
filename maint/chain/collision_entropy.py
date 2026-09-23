"""Every measured deviation, converted to bits of collision entropy leaked.

Chi-square answers whether a distribution departs from uniform. It does not say how much that
departure is worth, and it is not comparable across measurements with different bin counts, so a
chi-square of 17723 over sixteen bins and one of 36.62 over twenty-four cannot be read against each
other as they stand.

Collision entropy is the same statement in a unit that is comparable and that means something.
For counts over n bins drawn from N samples,

    sum of p squared  =  (1 + chi-square / N) / n
    H2                =  log2(n) - log2(1 + chi-square / N)

so the deficit below a uniform field's log2(n) is exactly log2(1 + chi-square / N), in bits. That is
how much collision probability the field gives away by not being flat, and bits are bits whatever
the bin count.

The floor comes out of the same expression. A uniform field produces a chi-square near its degrees
of freedom, n - 1, so the deficit chance alone manufactures is

    floor  =  log2(1 + (n - 1) / N)

which falls as one over N. That is the answer to what to target: a deficit above the floor is real,
and the depth needed to resolve a deficit of d bits is N of about (n - 1) / (2^d - 1).

Nothing is fitted here. Every chi-square below was produced by a script in this tree, and the
conversion is algebra.
"""

import math

# name, bins, samples, observed chi-square, where it came from
READINGS = [
    ("version rolling window, 16 buckets", 16, 6980, 17723.1, "integrate.py"),
    ("version rolling window, at N=1000", 16, 1000, 2882.8, "version_rake.py"),
    ("hour of day", 24, 6980, 36.62, "diurnal_fix.py"),
    ("day of week", 7, 6980, 12.26, "diurnal_fix.py"),
    ("nonce across the 32-bit range, 8 cells", 8, 1000, 12.2, "kat_nonces.py"),
    ("difficulty target values", 2, 1000, 11.2, "kat_holes.py, a control"),
    ("Foundry USA, hour of day", 24, 1803, 33.23, "check_pool_phase.py"),
    ("AntPool, hour of day", 24, 1311, 19.91, "check_pool_phase.py"),
    ("MARA Pool, hour of day", 24, 343, 36.31, "check_pool_phase.py"),
]


def deficit(bins, samples, chi):
    """Bits of collision entropy given away, against a flat field of the same width."""
    return math.log2(1.0 + chi / float(samples))


def floor_of(bins, samples):
    """The deficit chance alone manufactures at this width and depth."""
    return math.log2(1.0 + (bins - 1) / float(samples))


def depth_for(bins, bits):
    """Samples needed before a deficit of `bits` clears the floor."""
    return (bins - 1) / (2.0 ** bits - 1.0)


print("=" * 88)
print("  EVERY READING IN BITS OF COLLISION ENTROPY")
print("=" * 88)
print()
print("  %-40s %6s %7s %9s %9s %7s"
      % ("reading", "bins", "H2 max", "leaked", "floor", "ratio"))
print("  " + "-" * 84)

for name, bins, samples, chi, source in READINGS:
    lost = deficit(bins, samples, chi)
    floor = floor_of(bins, samples)
    ratio = lost / floor if floor > 0 else 0.0
    mark = "  <-- real" if ratio >= 3.0 else ("  marginal" if ratio >= 1.6 else "")
    print("  %-40s %6d %7.3f %9.4f %9.4f %7.1fx%s"
          % (name[:40], bins, math.log2(bins), lost, floor, ratio, mark))

print()
print("  'leaked' is bits of collision entropy the field gives away by not being flat.")
print("  'floor' is what chance manufactures at that width and depth: log2(1 + (n-1)/N).")
print("  'ratio' is leaked over floor, which is the only fair comparison across bin counts.")

print()
print("=" * 88)
print("  WHAT THE VERSION WINDOW ACTUALLY COSTS")
print("=" * 88)
print()
bins, samples, chi = 16, 6980, 17723.1
lost = deficit(bins, samples, chi)
print("  A flat 16-bucket field carries %.3f bits of collision entropy." % math.log2(bins))
print("  The measured window carries    %.3f bits." % (math.log2(bins) - lost))
print("  It gives away                  %.3f bits, which is %.1f%% of the total."
      % (lost, 100.0 * lost / math.log2(bins)))
print()
print("  Read as collision probability: two blocks drawn at random share a bucket with")
print("  probability %.4f, against %.4f for a flat field. That is %.2f times more often."
      % ((1.0 + chi / samples) / bins, 1.0 / bins, 1.0 + chi / samples))
print()
print("  Across the full 65536-value window rather than 16 buckets, the top twenty values hold")
print("  26.7%% of blocks where flat would give 0.03%%, so the collision excess is larger still.")

print()
print("=" * 88)
print("  WHAT TO TARGET: DEPTH NEEDED TO RESOLVE A GIVEN LEAK")
print("=" * 88)
print()
print("  A deficit of d bits sits at the floor when N = (n-1) / (2^d - 1). Below that depth the")
print("  leak cannot be told from chance however large the chi-square looks.")
print()
print("  %-14s" % "leak (bits)" + "".join("%12s" % ("n=%d" % b) for b in (8, 16, 24, 32, 64)))
print("  " + "-" * 74)
for bits in (0.5, 0.1, 0.05, 0.01, 0.005, 0.001):
    row = "  %-14.3f" % bits
    for b in (8, 16, 24, 32, 64):
        row += "%12.0f" % depth_for(b, bits)
    print(row)

print()
print("  So for the daily cycle at 24 bins: the leak measured is %.4f bits, and the depth at"
      % deficit(24, 6980, 36.62))
print("  which that stops being noise is N = %.0f. The corpus holds 6980, which is why the"
      % depth_for(24, deficit(24, 6980, 36.62)))
print("  reading is marginal rather than settled - it sits close to its own floor.")
print()
print("  And the version window at 16 bins leaks %.3f bits, which clears its floor at N = %.0f."
      % (deficit(16, 6980, 17723.1), depth_for(16, deficit(16, 6980, 17723.1))))
print("  Two blocks would have settled it. That is the difference between the two findings,")
print("  stated in one number instead of two incomparable chi-squares.")
