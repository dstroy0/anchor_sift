"""The invariance measured in fixed point, so the residual belongs to the object and not the double.

spectral_bench.py reported per-degree power holding to 1e-14 under general rotation while the
per-order magnitudes moved by 274 per cent. The mixing was real, but 1e-14 is float64's floor and
the measurement could not say whether the invariance was exact or merely sat where a double runs
out. Those are different claims and the format was hiding the difference.

Here the whole evaluation is integer fixed point at whatever width is asked for, so the question
becomes answerable by asking it twice:

    a residual that FALLS with the width belongs to the format
    a residual that STAYS belongs to the object

No trigonometry is needed inside the harmonic. The points are unit vectors, so

    cos theta = z,   sin theta = root(1 - z^2),   e^(i phi) = (x + i y) / sin theta

and e^(i m phi) is that complex value raised to the m-th power, which is repeated multiplication.
Only a square root and multiplies appear, both exact. Trigonometry is needed once, for the rotation
angles, and comes from exact_harmonics.

    python tools/audit/exact_spectral.py
    python tools/audit/exact_spectral.py --widths 64,128,192
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "examples", "proofing"))
sys.path.insert(0, os.path.join(ROOT, "tools", "view"))

import exact_harmonics
import state_deflection


def unit_points(count, places):
    """The golden placement in fixed point, heights exact and the ring radius by Newton's root."""
    scale = 1 << places
    two_pi = 2 * exact_harmonics.pi_at(places)
    golden = ((3 * scale) - exact_harmonics.binary_root(5 * scale * scale, places))
    golden = (golden * exact_harmonics.pi_at(places)) >> places
    out = []
    for k in range(count):
        # height = 1 - 2(k + 0.5)/count, exact as a rational scaled into fixed point.
        height = scale - (((2 * k + 1) * scale) // count)
        flat_square = scale - ((height * height) >> places)
        flat = exact_harmonics.binary_root(flat_square, places) if flat_square > 0 else 0
        around = (k * golden) % two_pi
        x = (flat * exact_harmonics.cosine(around, places)) >> places
        z = (flat * exact_harmonics.sine(around, places)) >> places
        out.append((x, height, z))
    return out


def turn(points, yaw, pitch, places):
    """A rotation composed of two axis turns, in fixed point throughout."""
    cy = exact_harmonics.cosine(yaw, places)
    sy = exact_harmonics.sine(yaw, places)
    cp = exact_harmonics.cosine(pitch, places)
    sp = exact_harmonics.sine(pitch, places)
    out = []
    for x, y, z in points:
        x1 = ((x * cy) - (z * sy)) >> places
        z1 = ((x * sy) + (z * cy)) >> places
        y2 = ((y * cp) - (z1 * sp)) >> places
        z2 = ((y * sp) + (z1 * cp)) >> places
        out.append((x1, y2, z2))
    return out


_NORM_CACHE = {}


def normalise(degree, order, places):
    """root((l - m)! / (l + m)!) in fixed point, exactly.

    Both factorials are exact integers, so the ratio is an exact rational and the root is Newton's
    on it scaled into the fixed point. The (2l+1)/4pi part of the full normalisation is deliberately
    left out: it is constant across the orders of a degree, so it scales P_l uniformly and cannot
    affect whether P_l is invariant. What matters is the part that varies with the order.
    """
    key = (degree, order, places)
    held = _NORM_CACHE.get(key)
    if held is not None:
        return held

    import math
    low = math.factorial(degree - order)
    high = math.factorial(degree + order)
    # root(low/high) at this width: root(low * 2^(2*places) / high).
    inside = (low << (2 * places)) // high
    value = exact_harmonics.binary_root(inside, places)
    # binary_root expects a value already scaled by 2^places; inside is scaled by 2^(2*places),
    # so the root of it is scaled by 2^places exactly, which is what is wanted.
    value = isqrt_scaled(inside)
    _NORM_CACHE[key] = value
    return value


def isqrt_scaled(value):
    """Exact integer square root, a value scaled by 2^(2p) roots to one scaled by 2^p."""
    if value <= 0:
        return 0
    guess = 1 << ((value.bit_length() + 1) // 2)
    while True:
        nxt = (guess + (value // guess)) >> 1
        if nxt >= guess:
            return guess
        guess = nxt


def power_spectrum(points, live, top, places):
    """Per-degree power, entirely in fixed point.

    a_lm accumulates over the lit points; P_l sums the squared magnitudes over orders. Returned
    scaled by 2^places so the caller never divides.
    """
    scale = 1 << places
    real = {}
    imag = {}
    for index in live:
        x, y, z = points[index]
        sin_square = scale - ((z * z) >> places)
        sin_theta = exact_harmonics.binary_root(sin_square, places) if sin_square > 0 else 0

        for degree in range(top + 1):
            # e^(i m phi) built by repeated multiplication of (x + i y)/sin theta.
            if sin_theta > 0:
                ex = (x << places) // sin_theta
                ey = (y << places) // sin_theta
            else:
                ex, ey = scale, 0
            mr, mi = scale, 0
            for order in range(degree + 1):
                legendre = exact_harmonics.legendre(degree, order, z, places)
                # The normalisation is not optional and leaving it out is what broke the first
                # attempt. Summed squared magnitudes are invariant only for ORTHONORMAL harmonics,
                # and the factor root((l-m)!/(l+m)!) varies with the order INSIDE a degree, so
                # unlike (2l+1)/4pi it does not factor out of P_l. Omitting it leaves no theorem to
                # test, and the residual came back at order one rather than at any floor.
                #
                # The factorials are exact integers and the root is Newton's, so the whole factor
                # is fixed point with nothing approximated.
                norm = normalise(degree, order, places)
                legendre = (legendre * norm) >> places
                key = (degree, order)
                real[key] = real.get(key, 0) + ((legendre * mr) >> places)
                imag[key] = imag.get(key, 0) - ((legendre * mi) >> places)
                nr = ((mr * ex) - (mi * ey)) >> places
                ni = ((mr * ey) + (mi * ex)) >> places
                mr, mi = nr, ni

    power = [0] * (top + 1)
    for (degree, order), value in real.items():
        weight = 1 if order == 0 else 2
        power[degree] += weight * (((value * value) >> places)
                                   + ((imag[(degree, order)] * imag[(degree, order)]) >> places))
    return power


def main():
    parser = argparse.ArgumentParser(description="Invariance in fixed point.")
    parser.add_argument("--widths", default="64,96,128")
    parser.add_argument("--top", type=int, default=4)
    parser.add_argument("--points", type=int, default=64)
    given = parser.parse_args()

    widths = [int(v) for v in given.widths.split(",")]
    block = [0x80000000] + [0] * 15
    state = state_deflection.states_of(block)[32]
    lit = [index for index in state_deflection.lit_of(state) if index < given.points]

    print("  %d points, degree %d, %d lit, SHA state after 32 rounds"
          % (given.points, given.top, len(lit)))
    print()
    print("  The claim under test: per-degree power does not move under rotation. If the residual")
    print("  falls as the width rises it was the format's; if it stops falling it is the object's.")
    print()
    print("    width   largest relative move in P_l   equals 2^-n")
    previous = None
    for places in widths:
        points = unit_points(given.points, places)
        pi = exact_harmonics.pi_at(places)
        before = power_spectrum(points, lit, given.top, places)
        moved = turn(points, (2 * pi) // 7, pi // 5, places)
        after = power_spectrum(moved, lit, given.top, places)

        worst = 0
        for degree in range(given.top + 1):
            if before[degree] == 0:
                continue
            gap = abs(after[degree] - before[degree])
            # relative, as an exact ratio scaled to the same fixed point
            relative = (gap << places) // abs(before[degree])
            worst = max(worst, relative)
        bits = places - worst.bit_length() if worst else places
        print("    %5d   %-30s 2^-%d" % (places, format(worst, ","), bits))
        previous = bits

    print()
    print("    A residual pinned at 2^-53 whatever the width would be float64 wearing a disguise.")
    print("    One that tracks the width is the arithmetic being exact and the invariance being")
    print("    real, which is the distinction the double could not draw.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
