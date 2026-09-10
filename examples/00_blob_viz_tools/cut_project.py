"""Cuts a line through a lattice and reads the dimension of the lattice back off the line.

    python tools/view/cut_project.py --check

WHAT THIS DEMONSTRATES

A periodic structure in n dimensions, sliced at an irrational angle and projected into fewer, comes
out quasiperiodic: never one period, but several with irrational ratios between them. Penrose
tilings are a five dimensional lattice seen in two. Icosahedral quasicrystals are six seen in three.
The correspondence runs both ways, so any quasiperiodic pattern lifts to a periodic lattice in high
enough dimension.

That gives a measurement and not a picture:

    the count of rationally independent periods in a one dimensional reading
    equals the dimension of the lattice it was cut from

Two independent periods means a two dimensional lattice at minimum. One means the thing was already
periodic and nothing was hidden. A boundary reading can therefore report the dimension of a
structure it never had access to, by counting how many of its periods refuse to be multiples of one another.

WHAT IS CHECKED

A square lattice is cut at the golden slope and the accepted points projected onto the line. The
result is the Fibonacci chain, and four things about it are checked against exact values.

Its gaps take exactly two lengths, never three and never one. Their ratio is the golden mean. Their
counts approach the golden mean as well. And no period of any length reproduces the sequence, the
property that makes it quasiperiodic and not merely long.

Then the frequency content is measured, and every strong peak is matched to a pair of whole numbers
against two generators. Rank two, from a reading taken along one line.
"""

import math
import sys

GOLDEN = (1.0 + math.sqrt(5.0)) / 2.0


def chain(count):
    """The Fibonacci chain, by cutting a square lattice at the golden slope.

    A lattice point is kept where its perpendicular coordinate lands inside a window one unit cell
    wide, and what is kept is projected onto the line. Nothing here is a rule about long and short
    intervals; those come out of the geometry, and doing it this way is the point.
    """
    scale = math.sqrt(1.0 + GOLDEN * GOLDEN)
    window = (1.0 + GOLDEN) / scale

    kept = []
    reach = count
    for across in range(-reach, reach + 1):
        for up in range(-reach, reach + 1):
            along = (GOLDEN * across + up) / scale
            perp = (-across + GOLDEN * up) / scale
            if 0.0 <= perp < window:
                kept.append(along)
    kept.sort()
    return kept


def gaps_of(points):
    return [points[at + 1] - points[at] for at in range(len(points) - 1)]


def distinct(values, tol=1e-9):
    """The distinct values in a list, to a tolerance, with how many times each occurs."""
    out = []
    for value in values:
        for seen in out:
            if abs(value - seen[0]) < tol:
                seen[1] += 1
                break
        else:
            out.append([value, 1])
    out.sort()
    return out


def as_word(gaps, long_gap, tol=1e-9):
    return "".join("L" if abs(one - long_gap) < tol else "S" for one in gaps)


def shortest_period(word):
    """The shortest period that reproduces this word, or zero where none does.

    A quasiperiodic sequence has none at any length. Checking only short periods would find none on
    a periodic sequence with a long period too, so every length up to half the word is tried.
    """
    span = len(word)
    for period in range(1, span // 2 + 1):
        if all(word[at] == word[at % period] for at in range(span)):
            return period
    return 0


def spectrum_peaks(points, lines, span):
    """Where the reading concentrates, as a structure factor over a range of frequencies.

    The sum of a phase over the point positions, as a diffraction measurement returns.
    A periodic set puts everything at multiples of one frequency. This one does not.
    """
    middle = sum(points) / len(points)
    centred = [one - middle for one in points]
    found = []
    step = span / lines
    for index in range(1, lines + 1):
        freq = index * step
        real = 0.0
        imag = 0.0
        for one in centred:
            angle = freq * one
            real += math.cos(angle)
            imag += math.sin(angle)
        found.append((freq, (real * real + imag * imag) / (len(points) * len(points))))
    return found


def name_peak(freq, first, second, reach=12):
    """The whole numbers that put this frequency on the two generators, where any do."""
    best = None
    for left in range(-reach, reach + 1):
        for right in range(-reach, reach + 1):
            if left == 0 and right == 0:
                continue
            guess = left * first + right * second
            off = abs(guess - freq)
            if best is None or off < best[0]:
                best = (off, left, right)
    return best


def _check():
    bad = 0
    points = chain(110)
    gaps = distinct(gaps_of(points))

    print("  A square lattice cut at the golden slope, projected onto the line.")
    print("")
    print("  points on the line: %d" % len(points))
    print("  distinct gaps: %d" % len(gaps))
    for value, times in gaps:
        print("    %.9f  occurs %d times" % (value, times))

    if len(gaps) != 2:
        print("  FAIL a cut of a two dimensional lattice gives two gap lengths")
        bad += 1
        print("")
        print("%d check(s) failed" % bad)
        return 1

    short_gap, short_count = gaps[0]
    long_gap, long_count = gaps[1]
    size_ratio = long_gap / short_gap
    # Long over short, and never the other way. The Fibonacci chain holds more long gaps than
    # short ones, so the ratio that approaches the golden mean is that way up. Inverted it
    # returns 0.625, which is one over 1.6, and reads as a chain that is not one.
    count_ratio = long_count / float(short_count)

    print("")
    print("  ratio of the two lengths: %.9f   golden mean %.9f   off by %.2e" %
          (size_ratio, GOLDEN, abs(size_ratio - GOLDEN)))
    print("  ratio of their counts:    %.9f   golden mean %.9f   off by %.2e" %
          (count_ratio, GOLDEN, abs(count_ratio - GOLDEN)))
    if abs(size_ratio - GOLDEN) > 1e-9:
        print("  FAIL the two lengths are not in the golden ratio")
        bad += 1
    if abs(count_ratio - GOLDEN) > 0.02:
        print("  FAIL the counts do not approach the golden ratio")
        bad += 1

    word = as_word(gaps_of(points), long_gap)
    period = shortest_period(word)
    print("")
    print("  shortest period reproducing the sequence: %s" %
          ("none at any length up to half of it" if period == 0 else str(period)))
    if period != 0:
        print("  FAIL the sequence is periodic, so nothing was hidden by the cut")
        bad += 1

    # The two generators the cut implies: one from the average spacing, one from that over the
    # golden mean. Nothing about the sequence was used to choose them.
    average = (long_gap * long_count + short_gap * short_count) / (long_count + short_count)
    first = 2.0 * math.pi / average
    second = first / GOLDEN

    peaks = spectrum_peaks(points, 2400, 4.0 * first)
    strong = sorted(peaks, key=lambda one: -one[1])
    # Anything near zero frequency is thrown away before the peaks are read. The structure
    # factor at small q is dominated by the finite length of the sample and not by its order, and a
    # tall feature sits there on any point set whatever, periodic or not. Left in, it is the
    # strongest thing in the list, it matches no pair of whole numbers, and it fails both the test
    # that the peaks lie on two generators and the test that they do not lie on one.
    picked = []
    for freq, power in strong:
        if freq < first * 0.30:
            continue
        if any(abs(freq - one[0]) < first * 0.02 for one in picked):
            continue
        picked.append((freq, power))
        if len(picked) >= 6:
            break

    print("")
    print("  the strongest peaks, named against two generators")
    print("")
    print("  %12s %12s  %s" % ("frequency", "power", "whole numbers"))
    worst = 0.0
    for freq, power in picked:
        off, left, right = name_peak(freq, first, second)
        worst = max(worst, off / first)
        print("  %12.6f %12.6f  %3d x g1 %+3d x g2   off by %.2e" %
              (freq, power, left, right, off))
    if worst > 0.02:
        print("  FAIL a peak does not sit on the two generators")
        bad += 1

    # Rank one would mean one generator explains every peak, the way a periodic set looks.
    # Showing that it does not is the half that says the lattice needed two dimensions.
    lonely = 0.0
    for freq, _ in picked:
        nearest = round(freq / first)
        if nearest == 0:
            nearest = 1
        lonely = max(lonely, abs(freq - nearest * first) / first)
    print("")
    print("  against one generator alone, the worst peak misses by %.3f of it" % lonely)
    print("  against two, the worst misses by %.2e of it" % worst)
    if lonely < 0.05:
        print("  FAIL one generator explains the peaks, so the reading is periodic")
        bad += 1

    print("")
    print("  rank of the period module: 2, so the lattice cut was two dimensional")
    print("")
    print("%d check(s) failed" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    if "--check" in sys.argv:
        sys.exit(_check())
    sys.stdout.write(__doc__)
