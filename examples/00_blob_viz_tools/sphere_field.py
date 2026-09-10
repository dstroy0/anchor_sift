"""The boundary field of a scattering ball, in spherical harmonics. Standard library only.

WHAT THIS COMPUTES

A ball of radius R holds sources in its interior. The medium scatters light so many times that
transport is diffusion, and under diffusion the boundary response to one interior source at radius
r is the Poisson kernel, whose Legendre expansion is

    P(gamma) = (1 / 4 pi R^2) sum_l (2l + 1) (r/R)^l P_l(cos gamma)

Everything here follows from that one line. The coefficient at degree l falls as (r/R)^l, and a
source near the center reaches only the low degrees and a source near the shell reaches all of
them. Depth sets bandwidth, and bandwidth sets how small a spot the source can print. Writing
r = R - d and expanding, the spot's angular radius is about d/R: a source one tenth of the way in
from the shell prints a spot a tenth of a radian across, no matter how small the source is.

Counting the modes that survive gives an area law. Degrees up to l carry (l + 1)^2 modes, the
usable l is about R/d, so the boundary holds about (R/d)^2 numbers. That is a surface area over a
squared length and it does not grow with the volume, a statement worth measuring instead
of asserting: put sources through a ball uniformly by volume and count how many boundary modes
carry anything, and the count stops climbing.

TWO KERNELS, ONE MULTIPLICATION EACH

    depth       (r/R)^l              where the source sits
    conduction  exp(-l (l+1) tau)    how long the boundary has been left to smooth

Both are diagonal in degree, so both are one multiply per coefficient. Conduction is the heat
kernel on the sphere, whose eigenfunctions are these same harmonics, so leaving the boundary to sit
for time tau is a low-pass at degree about 1/sqrt(tau) and no further computation is needed.

HEAT IS SURPRISAL

A source's strength is the information its event carried, -log2 p, in bits. The conversion to
energy is Landauer's constant, k T ln 2 per bit, which is a scale on the display and changes no
number here. Rare events are hot, common events are cool, and an event nothing was surprised by
deposits nothing.

WHAT IS MEASURED AND WHAT IS CHOSEN

Nothing here picks a direction for a source. A source whose direction is averaged away contributes
to degree zero alone, and a boundary carrying power above degree zero is reporting that a direction
was picked somewhere. `spread` does that averaging, and comparing a run against it separates the
structure in the data from the structure in the map that placed it.

    python sphere_field.py --check      the three checks below, each able to fail
"""

import math
import sys

FOUR_PI = 4.0 * math.pi


def gauss_legendre(count):
    """Nodes and weights for Gauss-Legendre quadrature on [-1, 1].

    Newton from a Chebyshev guess, which converges in four iterations at every order used here.
    Exact quadrature matters because the checks below decide whether the basis is orthonormal, and
    a basis graded with an approximate rule reports its own quadrature error as a defect.
    """
    nodes = [0.0] * count
    weights = [0.0] * count
    for index in range(count):
        x = math.cos(math.pi * (index + 0.75) / (count + 0.5))
        slope = 1.0
        for _ in range(64):
            previous, here = 1.0, x
            for degree in range(2, count + 1):
                previous, here = here, ((2 * degree - 1) * x * here - (degree - 1) * previous) / degree
            slope = count * (x * here - previous) / (x * x - 1.0)
            step = here / slope
            x -= step
            if abs(step) < 1e-15:
                break
        nodes[index] = x
        weights[index] = 2.0 / ((1.0 - x * x) * slope * slope)
    return nodes, weights


def legendre_column(top, order, x):
    """Normalized associated Legendre values for one order, every degree from `order` to `top`.

    Climbs the diagonal first and then recurs in degree, which keeps every intermediate at unit
    scale. Computing these from factorials overflows above degree about 150 and loses digits long
    before that, and the failure is quiet: the low degrees stay right and only the fine structure
    goes wrong, and a picture built on it looks plausible.
    """
    out = [0.0] * (top + 1)
    sine = math.sqrt(max(0.0, 1.0 - x * x))
    value = math.sqrt(1.0 / FOUR_PI)
    for step in range(1, order + 1):
        value *= math.sqrt((2.0 * step + 1.0) / (2.0 * step)) * sine
    if order <= top:
        out[order] = value
    if order + 1 <= top:
        out[order + 1] = math.sqrt(2.0 * order + 3.0) * x * value
    for degree in range(order + 2, top + 1):
        lead = math.sqrt((4.0 * degree * degree - 1.0) / (degree * degree - order * order))
        trail = math.sqrt(((degree - 1.0) ** 2 - order * order) /
                          (4.0 * (degree - 1.0) ** 2 - 1.0))
        out[degree] = lead * (x * out[degree - 1] - trail * out[degree - 2])
    return out


def harmonics_at(top, colatitude, longitude):
    """Every real harmonic up to `top` at one direction, as rows indexed by degree.

    Row l holds 2l + 1 values ordered from -l to +l, matching how coefficients are stored.
    """
    x = math.cos(colatitude)
    rows = [[0.0] * (2 * degree + 1) for degree in range(top + 1)]
    root_two = math.sqrt(2.0)
    for order in range(top + 1):
        column = legendre_column(top, order, x)
        if order == 0:
            for degree in range(top + 1):
                rows[degree][degree] = column[degree]
            continue
        cosine = math.cos(order * longitude) * root_two
        sine = math.sin(order * longitude) * root_two
        for degree in range(order, top + 1):
            rows[degree][degree + order] = column[degree] * cosine
            rows[degree][degree - order] = column[degree] * sine
    return rows


def kernel(top, radius_fraction, tau):
    """The per-degree gain of depth and conduction together.

    Depth is (r/R)^l and conduction is exp(-l(l+1) tau). Both are diagonal, so the pair is one
    number per degree and all of the physics between a source and the boundary is this list.
    """
    out = []
    gain = 1.0
    for degree in range(top + 1):
        smoothing = math.exp(-degree * (degree + 1.0) * tau)
        out.append(gain * smoothing)
        gain *= radius_fraction
    return out


def coefficients(sources, top, tau, spread=False):
    """Harmonic coefficients of the boundary field from a list of interior sources.

    Each source is (strength, radius_fraction, colatitude, longitude). The addition theorem turns
    the zonal kernel about a source's own axis into a sum over this basis, and a source costs one
    evaluation of the harmonics at its direction and nothing on a grid. Synthesis onto a grid
    happens once at the end, for the whole field and not per source.

    With `spread` the direction is averaged over the sphere before the sum, which leaves degree
    zero standing and zeroes every other degree exactly. That is the reading with no direction
    chosen, and it is computed and never approximated by drawing many directions.
    """
    total = [[0.0] * (2 * degree + 1) for degree in range(top + 1)]
    for strength, radius_fraction, colatitude, longitude in sources:
        gains = kernel(top, radius_fraction, tau)
        if spread:
            total[0][0] += strength * gains[0] * math.sqrt(1.0 / FOUR_PI)
            continue
        rows = harmonics_at(top, colatitude, longitude)
        for degree in range(top + 1):
            weight = strength * gains[degree]
            row = rows[degree]
            keep = total[degree]
            for at in range(2 * degree + 1):
                keep[at] += weight * row[at]
    return total


def power(total):
    """Power per degree, summed over order. Independent of how the sphere is oriented."""
    return [sum(value * value for value in row) for row in total]


def synthesize(total, top, latitudes, longitudes):
    """The field on a latitude by longitude grid, separably.

    Summing the basis at every grid point costs the grid times the mode count, which is twenty
    million multiplications on the grid this tool uses. Splitting the sum into a Legendre part per
    latitude and a trigonometric part per longitude costs under one million for the same answer.
    """
    grid = []
    root_two = math.sqrt(2.0)
    for row_index in range(latitudes):
        colatitude = math.pi * (row_index + 0.5) / latitudes
        x = math.cos(colatitude)
        by_cos = [0.0] * (top + 1)
        by_sin = [0.0] * (top + 1)
        for order in range(top + 1):
            column = legendre_column(top, order, x)
            cos_sum = 0.0
            sin_sum = 0.0
            for degree in range(order, top + 1):
                here = column[degree]
                cos_sum += total[degree][degree + order] * here
                sin_sum += total[degree][degree - order] * here
            by_cos[order] = cos_sum * (1.0 if order == 0 else root_two)
            by_sin[order] = sin_sum * (0.0 if order == 0 else root_two)
        line = []
        for column_index in range(longitudes):
            longitude = 2.0 * math.pi * column_index / longitudes
            value = by_cos[0]
            for order in range(1, top + 1):
                angle = order * longitude
                value += by_cos[order] * math.cos(angle) + by_sin[order] * math.sin(angle)
            line.append(value)
        grid.append(line)
    return grid


def surprisal(data):
    """Bits of surprise per byte value, from the byte's own frequency in this data.

    A value that fills the file carries nothing and a value seen once carries log2 of the length.
    Values absent from the data are given zero and never infinity, since a source that never fired
    deposits nothing and an infinity here would poison every sum downstream in silence.
    """
    counts = [0] * 256
    for byte in data:
        counts[byte] += 1
    span = float(len(data)) or 1.0
    bits = [0.0] * 256
    for value in range(256):
        if counts[value]:
            bits[value] = -math.log(counts[value] / span, 2.0)
    return bits, counts


def read_depth(spectrum, tau, first=1, last=None):
    """Recovers r/R from the slope of the spectrum, undoing conduction first.

    For one source the spectrum is q^2 (r/R)^(2l) exp(-2 l (l+1) tau) (2l+1) / 4 pi, so dividing
    out everything except the depth term leaves a straight line in degree whose slope is 2 log(r/R).
    Several sources at different depths give a mixture and this reports the effective depth of it,
    summarizing them without separating them.

    Returns (radius_fraction, degrees_used). A spectrum with fewer than three usable degrees
    returns zero degrees used, because a slope through two points is a definition instead of a
    measurement.
    """
    top = len(spectrum) - 1
    if last is None:
        last = top
    xs = []
    ys = []
    peak = max(spectrum) if spectrum else 0.0
    for degree in range(first, min(last, top) + 1):
        here = spectrum[degree]
        if here <= 0.0 or here < peak * 1e-12:
            continue
        shape = (2.0 * degree + 1.0) / FOUR_PI
        undone = math.log(here / shape) + 2.0 * degree * (degree + 1.0) * tau
        xs.append(float(degree))
        ys.append(undone)
    if len(xs) < 3:
        return 0.0, 0
    count = float(len(xs))
    mean_x = sum(xs) / count
    mean_y = sum(ys) / count
    top_sum = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    low_sum = sum((x - mean_x) ** 2 for x in xs)
    if low_sum <= 0.0:
        return 0.0, 0
    slope = top_sum / low_sum
    return math.exp(slope / 2.0), len(xs)


def live_modes(spectrum, floor):
    """How many harmonic modes carry more than `floor` of the total power.

    This is the count the area law is about. It rises with the bandwidth the sources reach and
    stops rising when they stop getting shallower, however many more are added.
    """
    total = sum(spectrum)
    if total <= 0.0:
        return 0, 0
    kept = 0
    reached = 0
    for degree, here in enumerate(spectrum):
        if here / total > floor:
            kept += 2 * degree + 1
            reached = degree
    return kept, reached


def spot_radians(radius_fraction):
    """Angular radius of the spot one source prints, from its depth.

    The spectrum falls as (r/R)^l, so the degree where it has dropped by e is 1 / ln(R/r) and the
    angular scale is its reciprocal. A source at the center returns pi, since its spot is the whole
    sphere, and there the claim that a spot is larger than its source becomes a number.
    """
    if radius_fraction <= 0.0:
        return math.pi
    if radius_fraction >= 1.0:
        return 0.0
    return min(math.pi, math.log(1.0 / radius_fraction))


def zonal_profile(radius_fraction, tau, top, samples=721):
    """One source's boundary response against angle from its own direction.

    This is the spot itself, sampled from its center to the far side. It falls away from the center
    and never rises again, and a level cuts it at one angle and the region above that level is a
    circle. Everything about overlap below rests on the profile being monotone, and conduction
    keeps it so because a heat kernel cannot sharpen anything.
    """
    gains = kernel(top, radius_fraction, tau)
    out = []
    for index in range(samples):
        gamma = math.pi * index / (samples - 1.0)
        x = math.cos(gamma)
        total = gains[0] / FOUR_PI
        if top >= 1:
            total += gains[1] * 3.0 * x / FOUR_PI
        previous, here = 1.0, x
        for degree in range(2, top + 1):
            previous, here = here, ((2 * degree - 1) * x * here - (degree - 1) * previous) / degree
            total += gains[degree] * (2.0 * degree + 1.0) * here / FOUR_PI
        out.append(total)
    return out


def cap_radius(profile, level):
    """The angle at which a profile crosses `level`, in radians, by walking a monotone table.

    Returns zero where the peak never reaches the level, and pi where the profile stays above it
    everywhere. The second case is a source deep enough that its circle has swallowed the sphere,
    and reporting it as a circle of radius pi keeps the caller from treating a swallowed sphere as
    a missing spot.
    """
    samples = len(profile)
    if not samples or profile[0] < level:
        return 0.0
    for index in range(1, samples):
        if profile[index] < level:
            span = profile[index - 1] - profile[index]
            part = 0.0 if span <= 0.0 else (profile[index - 1] - level) / span
            return math.pi * (index - 1.0 + part) / (samples - 1.0)
    return math.pi


def between(first, second):
    """Angle between two directions given as (colatitude, longitude).

    Nothing outside this pair enters, and that makes it the quantity worth reporting: an
    observer free to move anywhere over the sphere changes every direction and changes no angle
    between a pair of them.
    """
    one_colatitude, one_longitude = first
    two_colatitude, two_longitude = second
    dot = (math.sin(one_colatitude) * math.sin(two_colatitude) *
           math.cos(one_longitude - two_longitude) +
           math.cos(one_colatitude) * math.cos(two_colatitude))
    return math.acos(max(-1.0, min(1.0, dot)))


def overlaps(sources, top, tau, level, samples=721):
    """Which circles meet at this level, with how much angle to spare.

    A source's circle has a radius set by its depth and the level the edge is read at. Two circles
    meet when the angle between their directions is less than the sum of their radii, so the test
    needs the two radii and the angle between the pair and no orientation at all.

    The level is a reading, never a measurement. Raising it shrinks every circle and breaks the
    weakest overlaps first, and sweeping it is how a set of coincidences is separated into the ones
    that need the circles fat and the ones that survive the circles being cut to nothing.
    """
    radii = []
    for strength, radius_fraction, colatitude, longitude in sources:
        profile = zonal_profile(radius_fraction, tau, top, samples)
        scaled = [value * strength for value in profile]
        radii.append(cap_radius(scaled, level))

    found = []
    for first in range(len(sources)):
        for second in range(first + 1, len(sources)):
            if radii[first] <= 0.0 or radii[second] <= 0.0:
                continue
            apart = between((sources[first][2], sources[first][3]),
                            (sources[second][2], sources[second][3]))
            room = radii[first] + radii[second] - apart
            if room > 0.0:
                found.append((first, second, apart, room))
    return radii, found


def distinguishable(radii):
    """How many circles of this size the sphere holds without them lying on top of one another.

    The surface is continuous and two circle centres can be any distance apart, so the sphere
    discriminates without limit until the circles are asked to be told apart. Once they are, the
    count is the sphere's area over one circle's area, and it is finite the moment the circles have
    any size at all. This is the same area law the mode count reports, arrived at by measuring the
    spots instead of counting the harmonics, and the two agreeing is worth more than either alone.
    """
    kept = [one for one in radii if one > 0.0]
    if not kept:
        return 0
    mean = sum(kept) / len(kept)
    if mean >= math.pi:
        return 1
    area = 2.0 * math.pi * (1.0 - math.cos(mean))
    if area <= 0.0:
        return 0
    return int(FOUR_PI / area)


def _check():
    """Three checks, each able to fail, run against exact answers and not against a snapshot."""
    bad = 0
    top = 24

    # Orthonormality. Every pair integrates to one or zero, by Gauss-Legendre in colatitude and an
    # exact rule in longitude. A basis that is not orthonormal makes every power below meaningless.
    nodes, weights = gauss_legendre(top + 8)
    longitudes = 2 * top + 4
    worst = 0.0
    picked = [(2, 1), (3, -2), (5, 0), (7, 4)]
    for left in picked:
        for right in picked:
            total = 0.0
            for node, weight in zip(nodes, weights):
                colatitude = math.acos(node)
                for step in range(longitudes):
                    longitude = 2.0 * math.pi * step / longitudes
                    rows = harmonics_at(top, colatitude, longitude)
                    first = rows[left[0]][left[0] + left[1]]
                    second = rows[right[0]][right[0] + right[1]]
                    total += weight * first * second * (2.0 * math.pi / longitudes)
            want = 1.0 if left == right else 0.0
            worst = max(worst, abs(total - want))
    print("  orthonormal to %.2e" % worst)
    if worst > 1e-10:
        print("  FAIL basis is not orthonormal")
        bad += 1

    # Depth recovery. One source at a known radius, read back from the slope of its spectrum.
    for want in (0.3, 0.55, 0.8, 0.92):
        total = coefficients([(1.0, want, 1.1, 0.4)], top, 0.0)
        got, used = read_depth(power(total), 0.0, 1, 16)
        off = abs(got - want)
        print("  depth %.2f read back %.4f over %d degrees" % (want, got, used))
        if off > 1e-6 or used < 3:
            print("  FAIL depth recovery is off by %.2e" % off)
            bad += 1

    # Conduction has to be undone exactly, or the recovered depth moves when the boundary is left
    # to smooth. This is the check that caught the sign of the exponent being applied twice.
    total = coefficients([(1.0, 0.7, 0.9, 2.0)], top, 0.004)
    got, used = read_depth(power(total), 0.004, 1, 12)
    print("  depth 0.70 under conduction read back %.4f over %d degrees" % (got, used))
    if abs(got - 0.7) > 1e-6:
        print("  FAIL conduction is not undone")
        bad += 1

    # No direction chosen leaves degree zero standing and nothing above it.
    total = coefficients([(1.0, 0.9, 0.5, 1.0), (2.0, 0.4, 2.0, 3.0)], top, 0.0, spread=True)
    above = max(power(total)[1:])
    print("  with no direction chosen, power above degree zero is %.2e" % above)
    if above != 0.0:
        print("  FAIL a spread source reached a degree above zero")
        bad += 1

    print("")
    print("%d check(s) failed" % bad)
    return 1 if bad else 0


if __name__ == "__main__":
    if "--check" in sys.argv:
        sys.exit(_check())
    sys.stdout.write(__doc__)
