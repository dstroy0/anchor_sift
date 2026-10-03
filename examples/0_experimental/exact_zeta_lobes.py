#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-027
#
# The two device stages of exact_zeta_lobes.cu driven over one cell: the curves the Riemann-Siegel remainder R holds
# at every point, and the logarithm the main sum's phase turns by. One lane a point, each stage checked against the
# host word for word, each output held against the exact value it stands for.
#
#   Usage:  python examples/0_experimental/exact_zeta_lobes.py [binary]
#
# This reads no corpus. It sits in 0_experimental and is an entry in the analytic number theory workbook, on its rail;
# it claims nothing about the Riemann hypothesis. Without a binary it builds one through exact_zeta_lobes.sh.
#
# THE CELL
#
# Lane l stands at x = nu + l / 2^b over a cell of 2^b + 1 points, with X = nu 2^b + l and z = 1 - 2 p = Zt / 2^b,
# Zt = 2^b - 2 l. The sign is s = (-1)^(nu - 1).
#
# THE CURVE STAGE
#
# C_n(z) is the sum over j of g_(n,j) z^j, each g a Taylor coefficient of C_n held as an integer at the binary scale
# 2^E, read by Horner's rule as H_n = sum over j of g_(n,j) Zt^j 2^(b (J_n - 1 - j)). Curve n's part of R x^(1/2) is
# s C_n(z) x^(-n), and over the common denominator X^K it is the integer T_n = s H_n 2^(b n) X^(K - n), each output
# at its own binary exponent. The coefficients come from Gabcke's generator in exact_zeta_riemann_siegel.py, trimmed
# where they fall below the scale, and each lane's C_n(z) read back from the device is held against c_at's exact
# rational.
#
# THE LOG STAGE
#
# A = ln(X / (nu 2^b)) = 2 artanh(l / D), D = 2 nu 2^b + l, one series a lane. With c_k = Lambda / (2k + 1), Lambda
# the least common multiple of the odd numbers below 2L, the first L terms sum to 2 l S / (Lambda D^(2L - 1)) with
# S = sum over k < L of c_k l^(2k) D^(2(L - 1 - k)). The stage outputs the four integers l S, D^(2L - 1), l^(2L + 1)
# and D^2 - l^2: A lies at or above 2 l S / (Lambda D^(2L - 1)) and below that plus the tail
# 2 l^(2L + 1) / ((2L + 1) D^(2L - 1) (D^2 - l^2)). Each lane's bracket is held against zz's exact 2 artanh(l / D).

import array
import os
import shutil
import subprocess
import sys
import tempfile
from fractions import Fraction
from math import lcm

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "src", "python"))
sys.path.insert(0, HERE)
import exact_zeta_riemann_siegel as rs  # noqa: E402
import exact_zeta_zeros as zz  # noqa: E402

NU = 2
B = 9
LANES = (1 << B) + 1
CHECKED = 64
CURVES = 3
SCALE_BITS = 256
LOG_TERMS = 48
TERMS_MAX = 160
GAMMA_DIGITS = 100
CURVE_DIGITS = 50
CURVE_TOL = Fraction(1, 10 ** 18)
LOG_DIGITS = 200
LOG_SLACK = Fraction(1, 10 ** 190)
BUILD = os.path.join(HERE, "exact_zeta_lobes.sh")


def sample_lanes():
    """Lanes spread across the whole cell, both ends and the midpoint among them."""
    return sorted(set(range(0, LANES, 8)) | {LANES - 1})


def toward_zero(a, b):
    quotient = abs(a) // abs(b)
    return quotient if (a >= 0) == (b > 0) else -quotient


def curve_coefficients():
    """Gabcke's Taylor coefficients of C_0 through C_K, each at the binary scale 2^E, trimmed past the last that the
    scale still resolves."""
    decimal = 10 ** GAMMA_DIGITS
    curve = rs.Curve(GAMMA_DIGITS)
    out = []
    for n in range(CURVES + 1):
        raw = curve.gamma(n, TERMS_MAX)
        binary = [toward_zero(g << SCALE_BITS, decimal) for g in raw]
        last = max([j for j, g in enumerate(binary) if g != 0], default=0)
        out.append(binary[: last + 1])
    return out


def log_constants():
    """Lambda, the least common multiple of the odd numbers below 2L, and c_k = Lambda / (2k + 1) for k < L."""
    big_lambda = 1
    for odd in range(1, 2 * LOG_TERMS, 2):
        big_lambda = lcm(big_lambda, odd)
    return big_lambda, [big_lambda // (2 * k + 1) for k in range(LOG_TERMS)]


def put_word(handle, value):
    array.array("q", (value,)).tofile(handle)


def put_mantissa(handle, value):
    magnitude = abs(value)
    limbs = [(magnitude >> (32 * i)) & 0xFFFFFFFF for i in range((magnitude.bit_length() + 31) // 32)]
    array.array("q", (len(limbs),)).tofile(handle)
    if limbs:
        array.array("I", limbs).tofile(handle)
    array.array("q", ((value > 0) - (value < 0),)).tofile(handle)


def write_input(path, gammas, cs):
    with open(path, "wb") as handle:
        for word in (LANES, CHECKED, NU, B, CURVES, SCALE_BITS, LOG_TERMS):
            put_word(handle, word)
        for n in range(CURVES + 1):
            put_word(handle, len(gammas[n]))
        for n in range(CURVES + 1):
            for g in gammas[n]:
                put_mantissa(handle, g)
        for c in cs:
            put_mantissa(handle, c)


def build():
    """The binary's path, from the newest build or from exact_zeta_lobes.sh under the bash the path names first."""
    sources = (BUILD, os.path.join(HERE, "exact_zeta_lobes.cu"))
    import glob

    built = sorted(glob.glob(os.path.join(ROOT, "build", "*_exact_zeta_lobes", "exact_zeta_lobes*")), key=os.path.getmtime)
    fresh = [b for b in built[-1:] if os.path.getmtime(b) > max(os.path.getmtime(s) for s in sources)]
    if fresh:
        return fresh[0]
    made = subprocess.run([shutil.which("bash"), BUILD], capture_output=True, text=True)
    lines = made.stdout.strip().splitlines()
    if made.returncode or not lines:
        print(made.stdout.strip()[-2000:])
        print(made.stderr.strip()[-2000:])
        raise SystemExit("  the build failed")
    return lines[-1]


def run(binary):
    folder = tempfile.mkdtemp(prefix="lobes_")
    given, taken = os.path.join(folder, "in.bin"), os.path.join(folder, "out.txt")
    gammas = curve_coefficients()
    big_lambda, cs = log_constants()
    write_input(given, gammas, cs)
    ran = subprocess.run([binary, given, taken], capture_output=True, text=True,
                         env=dict(os.environ, CYCLE_RECORD_KEEP_PTX="1"))
    if ran.returncode:
        print(ran.stdout.strip()[-2000:])
        print(ran.stderr.strip()[-2000:])
        raise SystemExit("  the device run failed")
    return parse(taken), gammas, big_lambda, cs


def parse(path):
    lines = open(path).read().splitlines()
    stages, at = {}, 0
    while at < len(lines):
        head = lines[at].split()
        if head and head[0] == "stage":
            name, out_limbs, at = head[1], int(head[3]), at + 1
            outputs = []
            while lines[at].split()[0] == "output":
                _, field, offset, bits, exponent = lines[at].split()
                outputs.append((field, int(offset), int(bits), int(exponent)))
                at += 1
            rows = []
            for _ in range(LANES):
                rows.append(sum(int(x, 16) << (32 * i) for i, x in enumerate(lines[at].split()[:out_limbs])))
                at += 1
            host = int(lines[at].split()[1])
            stages[name] = {"outputs": outputs, "rows": rows, "host": host}
            at += 2
        else:
            at += 1
    return stages


def field(word, offset, bits):
    value = (word >> offset) & ((1 << bits) - 1)
    return value - (1 << bits) if value >> (bits - 1) else value


def read_lane(stage, lane):
    word = stage["rows"][lane]
    return {name: field(word, offset, bits) for name, offset, bits, _ in stage["outputs"]}


def check_curves(stage, gammas, lanes):
    """Each sampled lane's C_n read back from the device, against c_at's exact rational. Returns the largest gap; its
    floor across the cell is the device's 160-term truncation, widest where z reaches the cell's ends."""
    sign = 1 - 2 * ((NU - 1) % 2)
    worst = Fraction(0)
    for lane in lanes:
        got = read_lane(stage, lane)
        big_x = NU * (1 << B) + lane
        z_num = (1 << B) - 2 * lane
        for n in range(CURVES + 1):
            terms = len(gammas[n])
            device = Fraction(sign * got["curve%d" % n], big_x ** (CURVES - n) * (1 << (SCALE_BITS + B * (terms - 1))))
            exact = Fraction(rs.c_at(n, z_num, 1 << B, CURVE_DIGITS), 10 ** (CURVE_DIGITS + rs.GUARD))
            worst = max(worst, abs(device - exact))
    return worst


def check_logs(stage, big_lambda, lanes):
    """Each sampled lane's bracket on A against zz's exact 2 artanh(l / D). Returns whether every bracket holds the
    exact value, and the largest bracket width."""
    scale = 10 ** LOG_DIGITS
    held, widest = True, Fraction(0)
    for lane in lanes:
        if lane == 0:
            continue
        got = read_lane(stage, lane)
        big_d = 2 * NU * (1 << B) + lane
        lower = Fraction(2 * got["numerator"], big_lambda * got["power"])
        tail = Fraction(2 * got["tail"], (2 * LOG_TERMS + 1) * got["power"] * got["gap"])
        exact = Fraction(2 * zz._artanh(lane, big_d, scale), scale)
        held = held and (lower - LOG_SLACK <= exact <= lower + tail + LOG_SLACK)
        widest = max(widest, tail)
    return held, widest


def main():
    binary = sys.argv[1] if len(sys.argv) > 1 else build()
    stages, gammas, big_lambda, cs = run(binary)
    print("  cell: nu = %d, b = %d, %d points; curves C_0 .. C_%d at 2^-%d; the logarithm by %d terms" %
          (NU, B, LANES, CURVES, SCALE_BITS, LOG_TERMS))
    print("  coefficients a curve: %s" % ", ".join(str(len(gammas[n])) for n in range(CURVES + 1)))
    lanes = sample_lanes()
    host = stages["curves"]["host"] == 1 and stages["log"]["host"] == 1
    worst = check_curves(stages["curves"], gammas, lanes)
    curves_ok = worst <= CURVE_TOL
    logs_ok, widest = check_logs(stages["log"], big_lambda, lanes)
    print("  the curves: C_n read back from the device meets c_at's exact rational to %.3e across the cell, the "
          "residual the 160-term truncation at z = +-1, inside %.3e: %s" % (float(worst), float(CURVE_TOL), curves_ok))
    print("  the logarithm: every bracket holds zz's exact 2 artanh(l / D), the widest %.3e wide: %s" %
          (float(widest), logs_ok))
    print("  the host's records %s the device's word for word" % ("equal" if host else "differ from"))
    good = host and curves_ok and logs_ok
    print("  both stages check out" if good else "  a stage does not check out")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
