#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-029
#
# Harish-Chandra's spherical function of the hyperbolic plane, by two routes on the device, over a grid of the
# spectral parameter r and u = sinh^2(d / 2), held against each other within a bound on each, and against the exact
# rational series at the grid's corners.
#
#   Usage:  python examples/0_experimental/exact_zeta_spherical.py <binary> [r_bits] [u_bits]
#
# It sits in 0_experimental and is an entry in the analytic number theory workbook, on its rail.
#
# THE FUNCTION
#
# SL(2, R) acts on the upper half plane H by Mobius maps, SO(2) fixes i, and H = SL(2, R) / SO(2). A function on H
# radial about i, an eigenfunction of the Laplacian with eigenvalue -(1/4 + r^2) and 1 at i, is Harish-Chandra's
# spherical function phi_r. At hyperbolic distance d from i, with u = sinh^2(d / 2),
# phi_r = 2F1(1/2 + i r, 1/2 - i r; 1; -u). The modular surface SL(2, Z)\H is a quotient of H; its spectral theory
# reads every automorphic kernel through the phi_r, by the Selberg transform.
#
# Route one is the series in -u, real and alternating for u < 1. Route two is Pfaff's transformation,
# phi_r = (1 + u)^(-1/2 - i r) 2F1(1/2 + i r, 1/2 + i r; 1; u / (1 + u)), a complex series. Its real part is route
# one and its imaginary part is 0.
#
# THE BOUNDS
#
# Every factor of a term's growth, u ((n + 1/2)^2 + r^2) / (n + 1)^2 for route one and z ((n + 1/2)^2 + r^2) / (n + 1)^2,
# z = u / (1 + u), for route two, rises with u and with r: the grid's far corner bounds every lane. Past the last term
# the factor is below rho = u (1 + r^2 / (n + 1)^2) and the tail below the last term over 1 - rho. The device's error
# on a term grows by that factor a step and gains at most a few units of 2^-62 at each, as `bounds` counts them.

import array
import math
import os
import subprocess
import sys
import tempfile
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import exact_zeta_zeros as zz  # noqa: E402

naturals = zz.naturals

SCALE_BITS = 62
GUARD_BITS = 64
WORK = 1 << (SCALE_BITS + GUARD_BITS)
ARTANH_TERMS = 21
COS_TERMS = 18
NEWTON_STEPS = 7
CHECKED = 64
U_HIGH = Fraction(1, 2)
R_HIGH = 8
UNIT = Fraction(1 << SCALE_BITS)


def put(handle, v):
    mag = abs(v)
    limbs = [(mag >> (32 * i)) & 0xFFFFFFFF for i in range(max(1, (mag.bit_length() + 31) // 32))]
    array.array("q", (len(limbs),)).tofile(handle)
    array.array("I", limbs).tofile(handle)
    array.array("q", ((v > 0) - (v < 0),)).tofile(handle)


def constants():
    """1 / pi, the artanh constants 1 / (2k + 1), and the cos constants (-1)^k pi^(2k) / (2k)!, at 2^62."""
    pi = naturals._pi_machin(WORK)
    inv_pi = (1 << (2 * SCALE_BITS + GUARD_BITS)) // pi
    artanh = [(1 << SCALE_BITS) // (2 * k + 1) for k in range(ARTANH_TERMS)]
    cosine = []
    power = WORK
    for k in range(COS_TERMS):
        cosine.append((1 - 2 * (k % 2)) * ((power // math.factorial(2 * k)) >> GUARD_BITS))
        power = power * pi * pi // (WORK * WORK)
    return inv_pi, artanh, cosine


def growth(x, r, n):
    """A term's factor from n to n + 1: x ((n + 1/2)^2 + r^2) / (n + 1)^2."""
    return x * ((Fraction(2 * n + 1, 2)) ** 2 + r * r) / (n + 1) ** 2


def series_terms(x, r, need):
    """The least count of terms whose tail, at x and r, is below `need`, with that tail and the largest partial sum."""
    term, n, total, largest = Fraction(1), 0, Fraction(1), Fraction(1)
    while True:
        rho = x * (1 + r * r / Fraction((n + 1) ** 2))
        if rho < 1 and term / (1 - rho) < need:
            return n + 1, term / (1 - rho), largest
        term = term * growth(x, r, n)
        total += term
        largest = max(largest, total, term)
        n += 1


def bounds(u_high, r_high):
    """The term counts of both routes, and the bound on each route's error over the grid, in units of 2^-62.

    Route one's term n + 1 is three products taken back to the scale and one division, each within a unit, from term
    n, whose error it grows by u ((n + 1/2)^2 + r^2) / (n + 1)^2. Route two's is a complex product, a product by z and
    a division, five units, from term n's error grown by z ((n + 1/2) + r)^2 / (n + 1)^2. ln(1 + u) by 21 terms of
    artanh in y <= 1/5 is within 8 units, r ln(1 + u) / pi within 8 r + 3, cos and sin within 270 units and pi times
    the angle's error, and Newton's root from 4/5 within 4. The last two products add their factors' errors times
    the other's size and a unit each."""
    need = Fraction(1, 1 << 64)
    z_high = u_high / (1 + u_high)
    first, first_tail, first_largest = series_terms(u_high, r_high, need)
    second, second_tail, _ = series_terms(z_high, r_high, need)
    error, total = Fraction(0), Fraction(0)
    for n in range(first):
        total += error
        error = error * growth(u_high, r_high, n) + 4
    first_error = total + first_tail * UNIT
    error, total, size, term = Fraction(0), Fraction(0), Fraction(0), Fraction(1)
    for n in range(second):
        total += error
        size += term
        grow = z_high * (Fraction(2 * n + 1, 2) + r_high) ** 2 / (n + 1) ** 2
        error = error * grow + 5
        term = term * grow
    turn_error = 8 * r_high + 3
    cis_error = 270 + 4 * turn_error
    turned_error = 2 * (cis_error * size + total) + 2
    second_error = turned_error + 4 * size * 2 + 1 + 2 * second_tail * UNIT
    return first, second, first_error, second_error, first_largest


def exact_first(u, r, need):
    """Route one exactly: the partial sum to a tail below `need`, and that tail."""
    count, tail, _ = series_terms(u, r, need)
    term, total = Fraction(1), Fraction(1)
    for n in range(count - 1):
        term = -term * growth(u, r, n)
        total += term
    return total, tail


def run(binary, r_bits, u_bits):
    r_count = R_HIGH << r_bits
    u_count = int(U_HIGH * (1 << u_bits))
    lanes = r_count * u_count
    u_high = Fraction(u_count - 1, 1 << u_bits)
    r_high = Fraction(r_count - 1, 1 << r_bits)
    first, second, first_error, second_error, largest = bounds(u_high, r_high)
    inv_pi, artanh, cosine = constants()
    folder = tempfile.mkdtemp(prefix="spherical_")
    given, taken = os.path.join(folder, "in.bin"), os.path.join(folder, "out.txt")
    with open(given, "wb") as handle:
        array.array("q", (lanes, min(CHECKED, lanes), u_count, ARTANH_TERMS, COS_TERMS, first, second,
                          NEWTON_STEPS)).tofile(handle)
        for v in [1 << (SCALE_BITS - u_bits), 1 << (SCALE_BITS - r_bits), inv_pi] + artanh + cosine:
            put(handle, v)
    ran = subprocess.run([binary, given, taken], capture_output=True, text=True,
                         env=dict(os.environ, CYCLE_RECORD_KEEP_PTX="1"))
    if ran.returncode:
        print(ran.stdout.strip()[-2000:])
        print(ran.stderr.strip()[-2000:])
        raise SystemExit("  the device run failed")
    lines = open(taken).read().splitlines()
    places = [(int(line.split()[2]), int(line.split()[3])) for line in lines if line.startswith("output ")]
    rows = [line for line in lines if not line.split()[0] in ("out_limbs", "output", "host", "steps")]
    host = [line for line in lines if line.startswith("host ")][0].split()[1] == "1"
    steps = [line for line in lines if line.startswith("steps ")][0].split()[1]

    def read(row, place):
        word = 0
        for at, limb in enumerate(row.split()):
            word |= int(limb, 16) << (32 * at)
        offset, bits = place
        value = (word >> offset) & ((1 << bits) - 1)
        return value - (1 << bits) if value >> (bits - 1) else value

    values = [[read(row, place) for place in places] for row in rows]
    return (values, host, steps, lanes, r_count, u_count, first, second, first_error, second_error, largest)


def main():
    binary = sys.argv[1]
    r_bits = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    u_bits = int(sys.argv[3]) if len(sys.argv) > 3 else 7
    (values, host, steps, lanes, r_count, u_count, first, second, first_error, second_error,
     largest) = run(binary, r_bits, u_bits)
    print("  grid: r in [0, %d) by 2^-%d, u in [0, 1/2) by 2^-%d: %d lanes; %s steps; route one %d terms, route two %d" %
          (R_HIGH, r_bits, u_bits, lanes, steps, first, second))
    print("  bounds: route one %.3e, route two %.3e; route one's partial sums below %.3e" %
          (float(first_error / UNIT), float(second_error / UNIT), float(largest)))
    apart = max(abs(row[0] - row[1]) for row in values)
    imaginary = max(abs(row[2]) for row in values)
    together = math.ceil(first_error + second_error)
    origin = all(values[ri * u_count][0] == 1 << SCALE_BITS for ri in range(r_count))
    print("  the routes differ by %.3e at most, within %.3e: %s" %
          (apart / 2 ** SCALE_BITS, together / 2 ** SCALE_BITS, apart <= together))
    print("  route two's imaginary part is %.3e at most, within %.3e: %s" %
          (imaginary / 2 ** SCALE_BITS, float(second_error / UNIT), imaginary <= second_error))
    print("  phi_r = 1 at u = 0 for every r: %s" % origin)
    control = True
    for ri, ui in ((0, u_count - 1), (r_count // 2, u_count // 2), (r_count - 1, u_count - 1), (r_count - 1, 1)):
        r, u = Fraction(ri, 1 << r_bits), Fraction(ui, 1 << u_bits)
        exact, tail = exact_first(u, r, Fraction(1, 1 << 80))
        device = Fraction(values[ri * u_count + ui][0], 1 << SCALE_BITS)
        gap = abs(device - exact)
        within = gap <= first_error / UNIT + tail
        control = control and within
        print("    r = %s, u = %s: device %.15f, exact %.15f, apart %.3e, within the bound: %s" %
              (r, u, float(device), float(exact), float(gap), within))
    held = host and apart <= together and imaginary <= second_error and origin and control
    print("  %s; the host's records %s the device's word for word" %
          ("both routes agree at every lane within their bounds" if held else "the routes do not hold",
           "equal" if host else "differ from"))
    return 0 if held else 1


if __name__ == "__main__":
    sys.exit(main())
