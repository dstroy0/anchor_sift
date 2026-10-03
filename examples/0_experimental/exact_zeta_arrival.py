#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-024
#
# What each wave lands in where it joins the main sum, read at the boundaries t = 2pi n^2 by the device.
#
#   Usage:  python examples/0_experimental/exact_zeta_arrival.py [n0 ...]
#
# This reads no corpus. It sits in 0_experimental and is an entry in the analytic number theory workbook, on its
# rail: it claims nothing about the Riemann hypothesis.
#
# THE BOUNDARY
#
# The main sum of Riemann-Siegel is a sum of waves m^(-1/2) e^(i(theta - t ln m)). In the frame e^(i theta) turns, wave
# m spins at ln(x / m), x = sqrt(t / 2pi): it stands still at x = m and joins the sum there, at t = 2pi n^2 for n = m.
# There its phase is theta - t ln n = -pi n^2 - pi / 8 to theta's first terms, -pi / 8 for even n and pi - pi / 8 for
# odd. The waves already there, m < n, stand at 2pi n^2 ln m modulo a turn. The reading at a boundary is the angle
# between the arriving wave and their sum: V_n = sum over m < n of m^(-1/2) e^(-2pi i n^2 ln m) turned by the arriving
# wave's own phase, P_n = V_n e^(2pi i n^2 ln n). theta turns both alike and drops out.
#
# THE RELATION
#
# Along n, wave m's phase n^2 ln m has the constant second difference 2 ln m: a lane steps from one boundary to the
# next by u <- u r and r <- r q, with u = e^(-2pi i n^2 ln m), r = e^(-2pi i (2n + 1) ln m) and q = e^(-4pi i ln m).
# exact_zeta_arrival.cu runs that on the device, one lane a wave, and sums every boundary across its lanes with
# cycle_record_sum. At a fixed n0, u, r, q and m^(-1/2) are completely multiplicative in m: each is computed at the
# primes, from ln p and the phase n0^2 ln p reduced modulo a turn as an exact integer, and each composite m is the
# product over its least prime factor. Only the primes ask for a cosine and a sine.
#
# THE MEAN
#
# Each boundary's reading is the unit pair P_n / |P_n| at the scale S = 2^62. The tally is their exact sum and the run
# their count, and the mean at every boundary is tally / run, an exact rational: nothing is merged, rounded or dropped,
# and every boundary's mean is kept. The spread is read as |tally|^2 / (run S^2), an exact rational: run where every
# reading points one way, and near 1 where they spread like independent angles.
#
# Positive control: a window from n0 = 0 against V_n summed directly on the host, every wave's phase from its own
# logarithm, the gap in units of 2^-62, and every window's first and last boundary the same way. The bar is drawn: the
# device's V_n meets the direct sum within 2^-40 at every boundary checked.

import array
import glob
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "python"))
sys.path.insert(0, os.path.join(ROOT, "examples", "0_experimental"))
import manifest  # noqa: E402,F401
import exact_zeta_zeros as zz  # noqa: E402
from exact_zeta_zeros import compare, decimal  # noqa: E402
from representation.constants import naturals  # noqa: E402

SCALE_BITS = 62
WORK_BITS = 96
FLOORS = 16
WINDOW = 1024
CHECKED = 4096
BAR_BITS = 40
WINDOWS = (1000, 10000, 100000, 1000000)
BUILD = os.path.join(ROOT, "examples", "0_experimental", "exact_zeta_arrival.sh")


def digits_for(n0):
    """Decimal places for the phases: n0^2 ln m must keep 30 places past its whole turns."""
    return 30 + 2 * len(str(max(n0, 1)))


def least_factors(top):
    """The least prime factor of every m up to top, by a sieve."""
    least = list(range(top + 1))
    for p in range(2, int(top ** 0.5) + 1):
        if least[p] == p:
            for multiple in range(p * p, top + 1, p):
                if least[multiple] == multiple:
                    least[multiple] = p
    return least


def unit_at(turns, digits, bits):
    """e^(-2pi i turns / 10^digits) at the scale 2^bits, from cos and sin at `digits`."""
    scale = 10 ** digits
    c, s = zz.cos_sin(2 * zz.pi(digits) * turns // scale, digits)
    return (c << bits) // scale, -((s << bits) // scale)


def times(a, b, bits):
    return (a[0] * b[0] - a[1] * b[1]) >> bits, (a[0] * b[1] + a[1] * b[0]) >> bits


def seeds(n0, top):
    """u, r, q and m^(-1/2) for m from 1 to top at n0, each at 2^SCALE_BITS: at the primes from ln p, and at each
    composite as the product over its least prime factor, worked at 2^WORK_BITS."""
    digits = digits_for(n0)
    scale = 10 ** digits
    least = least_factors(top)
    one = 1 << WORK_BITS
    u, r, q, amp = [None, (one, 0)], [None, (one, 0)], [None, (one, 0)], [None, one]
    for m in range(2, top + 1):
        p = least[m]
        if p == m:
            log = zz.ln(p, digits)
            u.append(unit_at(n0 * n0 * log % scale, digits, WORK_BITS))
            r.append(unit_at((2 * n0 + 1) * log % scale, digits, WORK_BITS))
            q.append(unit_at(2 * log % scale, digits, WORK_BITS))
            amp.append(naturals._integer_sqrt((one * one) // p))
        else:
            rest = m // p
            u.append(times(u[p], u[rest], WORK_BITS))
            r.append(times(r[p], r[rest], WORK_BITS))
            q.append(times(q[p], q[rest], WORK_BITS))
            amp.append(amp[p] * amp[rest] >> WORK_BITS)
    drop = WORK_BITS - SCALE_BITS
    rows = array.array("q")
    for m in range(1, top + 1):
        rows.extend((u[m][0] >> drop, u[m][1] >> drop, r[m][0] >> drop, r[m][1] >> drop,
                     q[m][0] >> drop, q[m][1] >> drop, amp[m] >> drop))
    return rows


def run_device(binary, n0, top, sweeps, work):
    """V_n for n from n0 over sweeps * FLOORS boundaries, every wave m from 1 to top a lane, and whether the host's
    records of the first sweep equal the device's."""
    given = os.path.join(work, "arrival_in_%d.bin" % n0)
    taken = os.path.join(work, "arrival_out_%d.txt" % n0)
    header = array.array("q", (top, n0, sweeps, FLOORS, min(CHECKED, top), top))
    with open(given, "wb") as handle:
        header.tofile(handle)
        seeds(n0, top).tofile(handle)
    ran = subprocess.run([binary, given, taken], capture_output=True, text=True)
    values, same, steps = {}, 0, ""
    with open(taken) as handle:
        lines = handle.read().splitlines()
    limbs = int(lines[0].split()[1])
    for line in lines[1:]:
        parts = line.split()
        if parts[0] == "host":
            same = int(parts[1])
        elif parts[0] == "steps":
            steps = line
        else:
            words = [int(w, 16) for w in parts[1:]]
            pair = []
            for half in (words[:limbs], words[limbs:]):
                v = sum(w << (32 * i) for i, w in enumerate(half))
                pair.append(v - ((v >> (32 * limbs - 1)) << (32 * limbs)))
            values[int(parts[0])] = tuple(pair)
    return values, same, steps, ran.returncode


def direct(n, digits):
    """V_n summed on the host, every wave's phase from its own logarithm, at 2^SCALE_BITS."""
    scale = 10 ** digits
    re = im = 0
    for m in range(1, n):
        c, s = unit_at(n * n * zz.ln(m, digits) % scale, digits, SCALE_BITS)
        amp = naturals._integer_sqrt((1 << (2 * SCALE_BITS)) // m)
        re += c * amp >> SCALE_BITS
        im += s * amp >> SCALE_BITS
    return re, im


class Tally:
    """The unit readings' exact sum, their count, and every boundary's mean as tally / run."""

    def __init__(self):
        self.re = self.im = self.run = 0
        self.means = {}

    def read(self, n, v, digits):
        scale = 10 ** digits
        # the arriving wave's phase, e^(+2pi i n^2 ln n): the conjugate of unit_at
        c, s = unit_at(n * n * zz.ln(n, digits) % scale, digits, SCALE_BITS)
        p_re = (v[0] * c + v[1] * s) >> SCALE_BITS
        p_im = (v[1] * c - v[0] * s) >> SCALE_BITS
        size = naturals._integer_sqrt(p_re * p_re + p_im * p_im)
        self.re += (p_re << SCALE_BITS) // (size + (size == 0))
        self.im += (p_im << SCALE_BITS) // (size + (size == 0))
        self.run += 1
        self.means[n] = (self.re, self.im, self.run)

    def spread(self, places):
        """|tally|^2 / (run S^2) at `places`: run for one direction, near 1 for independent angles."""
        return (self.re * self.re + self.im * self.im) * 10 ** places // (self.run << (2 * SCALE_BITS))


def build():
    """The newest binary newer than its sources, or a fresh one from exact_zeta_arrival.sh under the bash the path
    names first."""
    sources = (BUILD, BUILD[:-3] + ".cu")
    built = sorted(glob.glob(os.path.join(ROOT, "build", "*_exact_zeta_arrival", "exact_zeta_arrival*.exe")) +
                   glob.glob(os.path.join(ROOT, "build", "*_exact_zeta_arrival", "exact_zeta_arrival")),
                   key=os.path.getmtime)
    fresh = [b for b in built[-1:] if os.path.getmtime(b) > max(os.path.getmtime(s) for s in sources)]
    if fresh:
        return fresh[0]
    made = subprocess.run([shutil.which("bash"), BUILD], capture_output=True, text=True)
    lines = made.stdout.strip().splitlines()
    return lines[-1] if made.returncode == 0 and lines else None


def main():
    out = sys.stdout
    windows = tuple(int(a) for a in sys.argv[1:]) or WINDOWS
    out.write("  what each wave lands in where it joins the main sum, at t = 2pi n^2, on the device\n")
    out.write("  this reads angles at boundaries and claims nothing about the Riemann hypothesis\n\n")
    binary = build()
    out.write("  binary %s\n" % binary)
    work = os.path.join(ROOT, "build")

    # positive control: from n0 = 0 against the direct sum
    begun = time.perf_counter()
    sweeps = 8
    top = sweeps * FLOORS
    values, same, steps, code = run_device(binary, 0, top, sweeps, work)
    digits = digits_for(top)
    worst = 0
    for n in range(2, top, 17):
        d = direct(n, digits)
        worst = max(worst, abs(values[n][0] - d[0]), abs(values[n][1] - d[1]))
    held = int(worst < (1 << (SCALE_BITS - BAR_BITS)))
    out.write("  control: n0 = 0, %d boundaries, V_n against the direct sum at every 17th: largest gap %d units of"
              " 2^-62, within 2^-%d: %s; host equals device on the first sweep: %s; %s; %.1fs\n\n"
              % (top, worst, BAR_BITS, bool(held), bool(same), steps, time.perf_counter() - begun))
    out.flush()

    every = held * same
    for n0 in windows:
        begun = time.perf_counter()
        top = n0 + WINDOW
        values, same, steps, code = run_device(binary, n0, top, WINDOW // FLOORS, work)
        tally = Tally()
        digits = digits_for(top)
        for n in range(max(n0, 2), n0 + WINDOW):
            tally.read(n, values[n], digits)
        marks = [k for k in (16, 64, 256, 1024) if n0 + k - 1 in tally.means]
        text = "  ".join("run %d: %s" % (tally.means[n0 + k - 1][2], spread_at(tally, n0 + k - 1, 4)) for k in marks)
        spent = time.perf_counter() - begun
        # the window's own second route: its first and last boundaries summed directly on the host
        gaps = []
        for n in (max(n0, 2), n0 + WINDOW - 1):
            d = direct(n, digits)
            gaps.append(max(abs(values[n][0] - d[0]), abs(values[n][1] - d[1])))
        far = int(max(gaps) < (1 << (SCALE_BITS - BAR_BITS)))
        out.write("  n0 = %d: %d waves, boundaries %d to %d; |tally|^2 / (run S^2) at %s; host equals device: %s;"
                  " first and last boundary against the direct sum %s units of 2^-62, within 2^-%d: %s; %s;"
                  " %.1fs on the device and the readings\n"
                  % (n0, top, max(n0, 2), n0 + WINDOW - 1, text, bool(same), gaps, BAR_BITS, bool(far), steps, spent))
        out.flush()
        every *= same * far
    return 1 - every


def spread_at(tally, n, places):
    re, im, run = tally.means[n]
    v = (re * re + im * im) * 10 ** places // (run << (2 * SCALE_BITS))
    return decimal(zz.pair(v, places), places)


if __name__ == "__main__":
    raise SystemExit(main())
