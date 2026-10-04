#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-028
#
# Turing's method, run as a machine over the automata of exact_zeta_turing.cu. Each automaton is a fixed program of
# the record machine, checked against the host word for word; this machine sits one level up, runs them a cell at a
# time, joins what each cell returns to its neighbors', and halts with a count proven or a cell it could not close.
#
#   Usage:  python examples/0_experimental/exact_zeta_turing.py <binary> [first] [last] [rate] [pairs|transform|both]
#           python examples/0_experimental/exact_zeta_turing.py <binary> [first] [last] [rate] em
#
# For each run of the device it writes the device's input to a file in a temporary directory and reads the device's
# output back.
#
# It sits in 0_experimental and is an entry in the analytic number theory workbook, on its rail: it verifies the
# zeros up to a height it is given and says nothing past it.
#
# THE CELLS
#
# Cell nu holds the points t = 2 pi s, s = x^2 = nu^2 + j (2 nu + 1) / P, j below P = 2^p: even in t, and in theta
# to within 1 / nu across the cell. P is the least power of 2 that gives the cell `rate` points or more for each unit
# theta / pi rises across it, each zero's share. The device works out every value of the cell itself, from nothing
# but nu, p and constants that do not depend on nu: ln k and k^(-1/2) once for each k <= nu, theta / pi and the
# remainder term once for each point, each point's main sum over k <= nu, the sign of Z it certifies, the zeros it
# finds between certified signs, and the sums of Turing's method over the cell's two ranges about its first certified
# point F. A cell returns F, its last certified point, its point 0, and those sums.
#
# THE MAIN SUM
#
# By pairs, the device takes each point's nu terms one lane apiece, nu P lanes a cell. By the multiple evaluation of
# Odlyzko and Schonhage, it takes F_j = sum over k of a_k exp(-2 pi i j pos_k / P), a_k = k^(-1/2) exp(-2 pi i nu^2 ln k),
# pos_k = (2 nu + 1) ln k, at every point at once: F is the discrete Fourier transform of
# u_h / P = sum over k of q_k / (z_h - w_k), a sum of nu poles on the unit circle at the P roots of unity z_h, which a
# tree of multipole and local expansions of order ORDER over leaves of 2^BETA frequencies evaluates, with each leaf's
# near poles taken whole through the Dirichlet kernel; the main sum's half is Re(exp(i theta) F). Its lanes a cell
# grow as P, not nu P. With both, the device runs the two and writes the most their Z differ by over the cell.
#
# THE BOUND ON Z
#
# Z = 2 sum + (-1)^(nu - 1) x^(-1/2) C_0 + E, |E| <= 0.127 t^(-3/4) for t >= 200: Gabcke's bound, as Hiary, Patel and
# Yang state it (An improved explicit estimate for zeta(1/2 + it), Lemma 2.1). theta is
# (t/2) log(t / (2 pi e)) - pi/8 + 1/(48 t) + E_theta, |E_theta| <= (7/5760 + pi/960) t^(-3) + exp(-pi t) / 2
# (Brent, On asymptotic approximations to the log-Gamma and Riemann-Siegel theta functions, Theorems 5 and 6), and
# an error in theta moves Z by at most 2 sum of m^(-1/2) <= 4 nu^(1/2) times it. The device's own error, a unit of
# 2^-62 a division and a unit a constant, is bounded step by step in `arithmetic`, and the multiple evaluation's, its
# truncation with it, in `transform_error`. A sign of Z is certified where |Z| exceeds the sum of the three.
#
# By Euler-Maclaurin, Z = sum over n < N of n^(-1/2) cos(theta - t ln n) + Re(exp(i theta) N^(-s) C), with N and the
# Bernoulli terms M chosen for the cell, and Johansson's bound on the remainder, which holds at every t > 0
# (Johansson, arXiv:1309.2877, Theorem 1): `em_bounds`.
#
# THE CELLS BELOW 168 PI
#
# With em, cells `first` to `last` run by Euler-Maclaurin, from cell 1 up, and N at cell `last` + 1's F, T_a, is held
# by Riemann-Siegel over cells `last` to `last` + 2. Where the certified sign changes in (cell `first`'s F, T_a] number
# N(T_a), every zero up to T_a is on the line and simple.
#
# THE COUNT
#
# Two certified points of opposite sign, with no certified point between, hold a zero of Z between them: a zero of
# zeta on the line. N(t) = theta(t) / pi + 1 + S(t) off the ordinates, and for t_2 > t_1 > 168 pi,
# |integral of S from t_1 to t_2| <= 2.067 + 0.059 log t_2 (Trudgian, Improvements to Turing's method, Theorem 2.2).
# On a lattice step [t_i, t_(i+1)], theta lies between its ends, and the zeros certified past T are at most
# N(t) - N(T). Over a window after T, N(T) <= 1 + B / (2 pi D) + sum of d_i (Theta_(i+1) - c_i) / D, and over one
# before it N(T) >= 1 + sum of d_i (k_(i+1) + Theta_i) / D - B / (2 pi D), with d_i the steps of x^2, D their sum,
# c_i the zeros certified in (T, t_i] and k_(i+1) those in (t_(i+1), T]. N is a whole number.
#
# The sum of d_i c_i is the sum over those zeros of x^2 at the window's end less x^2 at the zero's later point, and
# the sum of d_i k_(i+1) the sum of x^2 at the zero's earlier point less x^2 at the window's start. A cell's count
# of zeros and its sums of x^2 at their ends carry the whole of both. Every step of x^2 in cell nu is (2 nu + 1) / P,
# the one from its last point to the next cell's point 0 too, and that one weighs theta / pi at point 0.
#
# THE MACHINE
#
# N is held at F of every cell, with the window back to F of the cell before and the one on to F of the cell after.
# A cell whose certified zeros fall short of the difference of N at its F and the next cell's F, and the cells about
# an F where N is not held to one value, are run again on a lattice four times finer, and the counts are taken again. Where every cell closes, every zero from the second
# cell's F to the last cell's is a certified sign change: on the line, and simple.
#
# Positive control: the device's Z at two points of the first cell against the house's main sum and remainder,
# exact_zeta_riemann_siegel's rs_cut_at; by Euler-Maclaurin, against its em_at, and at cell `last` against
# Riemann-Siegel's Z within the two bounds.

import array
import math
import os
import subprocess
import sys
import tempfile
import time
from fractions import Fraction

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import exact_zeta_riemann_siegel as rs  # noqa: E402
import exact_zeta_zeros as zz  # noqa: E402

naturals = zz.naturals

SCALE_BITS = 62
GUARD_BITS = 64
WORK = 1 << (SCALE_BITS + GUARD_BITS)
ARTANH_TERMS = 21
COS_TERMS = 18
GAMMA_TERMS = 56
NEWTON_STEPS = 8
FOLDS = 33
LANE_BITS = 22
CHECKED = 64
FINEST = 22
COARSEST = 4
ROUNDS = 4
ORDER = 28
BETA = 4
E1_TERMS = 48
SINC_TERMS = 18
METHODS = {"pairs": 0, "transform": 1, "both": 2, "em": 3}
PI_LOW = Fraction(314159265, 100000000)
PI_HIGH = Fraction(314159266, 100000000)
LN_TWO_HIGH = Fraction(693148, 1000000)
SUMS = ("low_before", "low_after", "high_upto", "high_after", "zeros_upto", "zeros_after", "zeros_q_upto",
        "zeros_q_after", "zeros_p_upto", "zeros_p_after", "loose")


def floor_at_scale(value):
    """A value held at WORK, floored to 2^62."""
    return value >> GUARD_BITS


class Constants:
    """Every constant the automata read, at 2^62, each within a unit, none of them depending on the cell."""

    def __init__(self):
        self.pi = naturals._pi_machin(WORK)
        decimal = SCALE_BITS * 30103 // 100000 + 61 * GAMMA_TERMS // 100 + 40
        gamma = rs.Curve(decimal).gamma(0, GAMMA_TERMS)
        self.gamma = [rs.compare(g, 0) * ((abs(g) << SCALE_BITS) // 10 ** decimal) for g in gamma]
        self.ln2 = floor_at_scale(zz._ln_by_two(2, WORK))
        self.artanh = [(1 << SCALE_BITS) // (2 * k + 1) for k in range(ARTANH_TERMS)]
        self.cosine = []
        power = WORK
        for k in range(COS_TERMS):
            self.cosine.append((1 - 2 * (k % 2)) * floor_at_scale(power // math.factorial(2 * k)))
            power = power * self.pi * self.pi // (WORK * WORK)
        self.c96 = (1 << (SCALE_BITS + 2 * (SCALE_BITS + GUARD_BITS))) // (96 * self.pi * self.pi)
        self.slope = slope(self)
        self.pi_scaled = floor_at_scale(self.pi)
        self.fact = [(1 << SCALE_BITS) // math.factorial(n + 1) for n in range(E1_TERMS)]
        self.sinc = []
        power = WORK
        for n in range(SINC_TERMS):
            self.sinc.append((1 - 2 * (n % 2)) * floor_at_scale(power // math.factorial(2 * n + 1)))
            power = power * self.pi * self.pi // (WORK * WORK)


def put(handle, v):
    mag = abs(v)
    limbs = [(mag >> (32 * i)) & 0xFFFFFFFF for i in range(max(1, (mag.bit_length() + 31) // 32))]
    array.array("q", (len(limbs),)).tofile(handle)
    array.array("I", limbs).tofile(handle)
    array.array("q", (rs.compare(v, 0),)).tofile(handle)


def root_ceiling(value, k):
    """The least integer r with r^k >= value, for value >= 0."""
    r = max(0, int(round(float(value) ** (1.0 / k))) - 2)
    while Fraction(r) ** k < value:
        r += 1
    return r


def newton_error(v):
    """The device's error on w^(-1/2), 1 <= w <= v, in units of 2^-62, after NEWTON_STEPS of Newton's rule from
    2^(-g - 1), 4^g < w <= 4^(g + 1), which is below the root and above half of it.

    With R = 2^62 w^(-1/2), a step's floors take y below y (3 - w y^2) / 2 by at most 1.5 units, and the floors of
    y^2 and of w y^2 put it above by at most y (w + 2) / 2^63, below (w + 2)^(1/2) units. r = y / R then stays above
    the sequence rho' = min(g(rho), g(1 + up / R)) - 1.5 / R, g(r) = r (3 - r^2) / 2, from rho = 1/2, taken here at
    2^256 and rounded down. g rises on [0, 1], and the start at 1/2 is the worst."""
    scale = 1 << 256
    s = root_ceiling(Fraction(v), 2)
    up = root_ceiling(Fraction(v + 2), 2) + 1
    down = 3 * s * scale // (2 << SCALE_BITS) + 1
    up_ratio = up * s * scale // (1 << SCALE_BITS) + 1

    def g(r):
        square = -(-r * r // scale)
        return r * (3 * scale - square) // (2 * scale)

    rho = scale // 2
    for _ in range(NEWTON_STEPS):
        rho = min(g(rho), g(scale + up_ratio)) - down
    return max(-(-(scale - rho) * (1 << SCALE_BITS) // scale), up) + 1


def slope(constants):
    """A bound on |C_0'| over [-1, 1] from its Taylor coefficients at 2^62, with their error."""
    return Fraction(sum(n * (abs(g) + 1) for n, g in enumerate(constants.gamma)), 1 << SCALE_BITS)


def unit_errors():
    """e_ln, the error on a folded logarithm, and e_cos, on cos(pi s) by Horner's rule, in units of 2^-62.

    Every value a product is taken back from is below 12 times 2^62 in size: the partial sums of cos below
    cosh(pi) < 11.6 and of artanh below 1.05. The device wraps each such value to 76 bits, and a value that size passes
    the wrap unchanged."""
    y_top = Fraction(1, 3)
    tail = Fraction(1 << SCALE_BITS) * y_top ** (2 * ARTANH_TERMS) / ((2 * ARTANH_TERMS + 1) * (1 - y_top ** 2))
    e_y2 = 2 * y_top + 1 + Fraction(1, 1 << 60)
    held = Fraction(105, 100)
    e_acc = Fraction(2)
    for _ in range(ARTANH_TERMS - 1):
        e_acc = e_acc * (y_top ** 2 + Fraction(1, 1 << 60)) + held * e_y2 + 3
    e_half = e_acc * y_top + held + 1
    e_ln = 2 * e_half + 2 * (tail + 1) + FOLDS + 1
    cosh_pi = Fraction(1160, 100)
    e_cos = Fraction(2)
    for _ in range(COS_TERMS - 1):
        e_cos = e_cos + cosh_pi + 3
    return e_ln, e_cos + 1


def arithmetic(nu, c0_slope):
    """The device's error on Z and on theta / pi over cell nu, in units of 2^-62, from its steps.

    Every value a product is taken back from is below 12 times 2^62 in size: the partial sums of C_0 below 1.01 and
    Newton's y (3 - w y^2) below 3, besides those of unit_errors.

    ln k and ln s each carry e_ln; theta / pi = S ln s / 2^p - s - 1/8 + 2^p / (96 pi^2 S) carries s e_ln and three
    floors; the pair's 2 s ln k carries 2 s e_ln and a floor. x = S s^(-1/2) / 2^p carries s times the root's error
    and a floor, z twice that, and x^(-1/2), from the x the device holds, half of it more."""
    s_top = (nu + 1) ** 2
    e_ln, e_cos = unit_errors()
    e_theta = s_top * e_ln + 4
    e_q = e_theta + 2 * s_top * e_ln + 1
    e_term = e_cos + PI_HIGH * e_q + Fraction(101, 100) * newton_error(nu) + 1
    e_x = s_top * newton_error(s_top) + 1
    e_gamma = 3 * GAMMA_TERMS + 1 + 2 * e_x * c0_slope
    e_root = newton_error(nu + 1) + e_x / 2 + 1
    e_held = e_gamma + Fraction(101, 100) * e_root + 1
    return 2 * nu * e_term + e_held, e_theta, e_held


def sine_low(x):
    """A lower bound on sin x for 0 <= x <= pi / 2, x a Fraction: x - x^3 / 6."""
    return x - x ** 3 / 6


def transform_error(nu, p, e_theta, e_held):
    """The multiple evaluation's error on Z over cell nu at P = 2^p points, in units of 2^-62.

    Its main sum's half is Re(exp(i theta) F), F_j = sum over h of (u_h / P) exp(-2 pi i j h / P), and u_h / P is
    the sum over k of q_k / (z_h - w_k), each pole's charge q_k = -a_k (1 - exp(-2 pi i pos_k)) w_k / P at most
    2 k^(-1/2) / P in size. The poles as the device holds them, pos_k and a_k each within its error, are poles of the
    same kind: F over them is F over the true poles within the sum over k of e_a + 2 pi k^(-1/2) (2 nu + 1) e_ln, and
    what follows is the error on F over the poles held.

    Truncation: a pole of a source box S at level l, carried to a target box T of its interaction list, |T - S| >= 3
    boxes, is 1 / (z - w) = (1 / (sigma_S D)) sum of binom(m + n, n) x^n y^m, |x|, |y| <= rho / |D|, rho = pi / 2^l,
    |D| = 2 sin(|Delta| pi / 2^l) >= 2 sin(3 pi / 2^l); the terms left out, those with m >= N or n >= N, sum to at most
    c^N / ((1 - c) |D|), c = 2 rho / |D|, at each of the P / 2^l points of T. Each source box is in at most six lists,
    and the charges sum to at most 4 nu^(1/2) / P: over all the points, the sum over l of
    24 nu^(1/2) c_l^N / ((1 - c_l) 2^l |D_l|).

    Arithmetic, each expansion's error in the norm sum over m of w^m |e_m|, w = 1/2: a pole's leaf terms
    (q / sigma) eta^m carry e_q + 2 (m + 1). The shift to a parent multiplies the norm by at most 4/3, M_c,j's weight
    in M_p,m being binom(m, j) |s|^(m - j) |r|^j with |s|, |r| <= 1/2, and adds N + 6 a child for its roundings. The
    shift across, L_n = (1 / D) sum of binom(m + n, n) c^n d^m M_m with |c|, |d| = rho / |D| <= 0.22, takes the norm to
    a plain sum over n of at most 1.27 / |D| times it, and adds (4 N + 2) / |D| + 2 N. The shift down keeps the plain
    sum, L_p,n's weights binom(n, j) |s|^(n - j) |r|^j summing over j to (|s| + |r|)^n <= 1, and adds 8 N. Summed
    over the points as the truncation is, a level's errors reach the P / 2^l points of each of at most six targets. A
    point adds its leaf's Horner's rule, 2 N, and its near field, five leaves of at most W / 2 + 1 poles, each
    e_cos + 40. The transform's p stages each add 2 + A e_w at each of the 2^(p - s) values feeding an output, A the
    sum over h of |u_h / P|, at most 2 nu^(1/2) (ln P + 3) by the Dirichlet kernel's Lebesgue constant, and e_w the
    twiddle's error. cos theta and sin theta carry e_cos + pi e_theta against |F| <= 2 nu^(1/2), and
    Z = 2 Re(exp(i theta) F) + the remainder term."""
    e_ln, e_cos = unit_errors()
    order, top, width = ORDER, p - BETA, 1 << BETA
    points = 1 << p
    root_nu = root_ceiling(Fraction(nu), 2)
    e_a = Fraction(101, 100) * newton_error(nu) + e_cos + PI_HIGH * 2 * nu * nu * e_ln + 2
    held = nu * e_a + 2 * root_nu * 2 * PI_HIGH * (2 * nu + 1) * e_ln
    e_q = (e_cos * 4 + 2 * PI_HIGH + 6) / points + 1
    unit = Fraction(1 << SCALE_BITS)
    truncation = Fraction(0)
    arithmetic_sum = Fraction(0)
    leaf_norm = 2 * (e_q + 2) + 4 * sum(Fraction(m, 2 ** m) for m in range(order))
    # the poles lie in pos within [0, (2 nu + 1) ln nu], and at level l in at most this many boxes
    reach = (2 * nu + 1) * ln_high(nu)

    def holding(level):
        return min(2 ** level, math.ceil(reach * 2 ** level / points) + 1)

    for level in range(3, top + 1):
        rho = PI_HIGH / 2 ** level
        d_low = 2 * sine_low(3 * PI_LOW / 2 ** level)
        c = 2 * rho / d_low
        truncation += 24 * root_nu * c ** order / ((1 - c) * 2 ** level * d_low) * unit
        # every pole's leaf norm carried up top - level shifts, and each shift's roundings carried the rest of the way
        multipoles = nu * leaf_norm * Fraction(4, 3) ** (top - level) + sum(
            holding(finer) * (order + 6) * Fraction(4, 3) ** (finer - 1 - level) for finer in range(level + 1, top + 1))
        across = Fraction(127, 100) / d_low * multipoles + holding(level) * ((4 * order + 2) / d_low + 2 * order)
        arithmetic_sum += Fraction(points, 2 ** level) * 6 * across + points * 8 * order
    near = 5 * (width // 2 + 1) * (e_cos + 40)
    arithmetic_sum += points * (2 * order + near)
    spread = 2 * root_nu * (p * LN_TWO_HIGH + 3)
    e_w = e_cos + PI_HIGH
    stages = 2 * points * (2 + spread * e_w)
    e_f = held + truncation + arithmetic_sum + stages
    return 2 * (e_f + 2 * root_nu * (e_cos + PI_HIGH * e_theta) + 2) + e_held


def em_ratios(terms):
    """r_k = (B_2k / (2k)!) / (B_(2k-2) / (2k - 2)!) for k from 2 to `terms`, at 2^62, each toward zero."""
    out = []
    for k in range(2, terms + 1):
        num_k, den_k = zz.bernoulli_over_factorial(k)
        num_j, den_j = zz.bernoulli_over_factorial(k - 1)
        num, den = num_k * den_j, den_k * num_j
        out.append(rs.compare(num * den, 0) * ((abs(num) << SCALE_BITS) // abs(den)))
    return out


def em_terms(level):
    """M, the Bernoulli terms Euler-Maclaurin takes at widening `level`."""
    return 20 + 10 * level


def em_heads(nu, terms):
    """N for cell nu at M = `terms`: the least with |s + j| / (2 pi N) <= 1/2 for every j < 2M over the cell."""
    t_high = 2 * PI_HIGH * (nu + 1) ** 2
    return max(2, math.ceil((t_high + 2 * terms) / PI_LOW))


def em_bounds(nu, heads, terms):
    """The bound on Z and on theta / pi over cell nu by Euler-Maclaurin at N = `heads` and M = `terms`, whole units
    of 2^-62.

    zeta(s) = sum over n < N of n^(-s) + N^(-s) C, C = N / (s - 1) + 1/2 + sum over k <= M of B_2k / (2k)! (s)_(2k-1)
    N^(1 - 2k), and |R| <= 4 |(s)_2M| / ((2 pi)^(2M) (sigma + 2M - 1) N^(sigma + 2M - 1)) for N >= 2 and sigma + 2M > 1:
    Johansson, arXiv:1309.2877, Theorem 1, at a = 1 with no derivative. It holds at every t, and |(s)_2M| rises with t: the cell's top bounds it.

    theta's error moves Z = sum over n < N of n^(-1/2) cos(theta - t ln n) + Re(exp(i theta) N^(-s) C) by at most
    the sum of n^(-1/2) and |C| times it. The device's own error is carried step by step: each term of the pair
    stage as in `arithmetic`, and through the Euler-Maclaurin stage, t = 2 pi S / 2^p, 1 / (s - 1), and each tau_k
    from tau_(k-1) by r_k, 1 / N, s + 2k - 3, 1 / N and s + 2k - 2, each error grown by the step's factor and a unit a
    division."""
    unit = Fraction(1 << SCALE_BITS)
    s_top = (nu + 1) ** 2
    t_low = 2 * PI_LOW * nu * nu
    t_high = 2 * PI_HIGH * s_top
    root_heads = root_ceiling(Fraction(heads), 2)
    sigma = Fraction(1, 2)
    # Johansson's remainder, its square first, at the cell's top
    square = Fraction(16)
    for j in range(2 * terms):
        square *= (j + sigma) ** 2 + t_high ** 2
    square /= (2 * PI_LOW) ** (4 * terms) * (2 * terms - sigma) ** 2 * Fraction(heads) ** (4 * terms - 1)
    remainder = Fraction(root_ceiling(square * unit * unit, 2) + 1)
    # theta by Brent at the cell's foot, exp(-x) below 1 over exp's first 40 Taylor terms
    x = PI_LOW * t_low
    e_theta = (Fraction(7, 5760) + PI_HIGH / 960) / t_low ** 3 + 1 / (
        2 * sum(x ** k / math.factorial(k) for k in range(40)))
    # the size of C, and the device's error on it
    e_ln, e_cos = unit_errors()
    e_point = s_top * e_ln + 4
    e_q = e_point + 2 * s_top * e_ln + 1
    e_cs = e_cos + PI_HIGH * e_q
    e_t = 2 * s_top + 2
    e_inverse = 2 * (e_t / t_low ** 2 + 1)
    size = Fraction(1, 2) + t_high
    held = Fraction(heads) / t_low + Fraction(1, 2)
    a = size / (12 * heads)
    e_tau = 2 + e_t / (12 * heads)
    held += a
    e_c = heads * e_inverse + e_tau
    ratios = em_ratios(terms)
    for k in range(2, terms + 1):
        r = Fraction(abs(ratios[k - 2]) + 1, 1 << SCALE_BITS)
        w = 2 * k - 3 + size
        e1 = e_tau * r + a + 2
        a1 = a * r
        e2 = e1 / heads + 2
        a2 = a1 / heads
        e3 = e2 * w + a2 * e_t + 4
        a3 = a2 * w
        e4 = e3 / heads + 2
        a4 = a3 / heads
        e_tau = e4 * (w + 1) + a4 * e_t + 4
        a = a4 * (w + 1)
        held += a
        e_c += e_tau
    e_rotated = 2 * e_cs * held + e_c + 2
    e_em = Fraction(101, 100) * e_rotated + held * newton_error(heads) + 1
    e_term = e_cos + PI_HIGH * e_q + Fraction(101, 100) * newton_error(heads) + 1
    e_arith = (heads - 1) * e_term + e_em + 2
    phase = e_theta * (2 * root_heads + held) * unit
    return math.ceil(e_arith + remainder + phase), math.ceil(e_point + e_theta * unit / PI_LOW)


def analytic(nu):
    """Gabcke's bound and theta's on Z, and theta's on theta / pi, over cell nu, in units of 2^-62."""
    t_low = 2 * PI_LOW * nu * nu
    unit = Fraction(1 << SCALE_BITS)
    gabcke = root_ceiling((Fraction(127, 1000) * unit) ** 4 / t_low ** 3, 4)
    e_theta = (Fraction(7, 5760) + PI_HIGH / 960) / t_low ** 3 + Fraction(1, 1 << 200)
    phase = 4 * root_ceiling(Fraction(nu), 2) * e_theta * unit
    return gabcke + phase, e_theta * unit / PI_LOW


def bounds(nu, c0_slope, p, method):
    """The bound on Z and on theta / pi over cell nu at 2^p points, whole units of 2^-62: the pairs' arithmetic, or
    the multiple evaluation's where it gives the verdict."""
    e_arith, e_q, e_held = arithmetic(nu, c0_slope)
    if method != "pairs":
        e_arith = transform_error(nu, p, e_q, e_held)
    e_z, e_theta = analytic(nu)
    return math.ceil(e_arith + e_z), math.ceil(e_q + e_theta)


class Cell:
    """What the device returns for cell nu at P = 2^p points, its values of S = x^2 2^p lifted to 4^-FINEST."""

    def __init__(self, nu, p, lines):
        self.nu, self.p = nu, p
        self.lift = 1 << (2 * FINEST - p)
        rows = {line.split()[0]: line.split()[1:] for line in lines}
        _, _, points, first, last = (int(v) for v in rows["cell"])
        self.points, self.first, self.last = points, first, last
        self.at = {key: [int(v, 16) for v in rows[key]] for key in ("first", "last", "origin")}
        self.control = [int(v, 16) for v in rows["control"]]
        self.sums = {key: int(rows[key][0], 16) for key in SUMS}
        self.failed = sum(1 for v in rows["host"] if v != "1")
        self.steps = [int(v) for v in rows["steps"]]
        self.apart = (int(rows["apart"][0], 16), int(rows["apart"][1])) if "apart" in rows else None

    def sign(self, which):
        return self.at[which][0]

    def x2(self, which):
        return self.at[which][1] * self.lift

    def end_x2(self):
        """x^2 at the cell's last point."""
        return ((self.nu ** 2 << self.p) + ((1 << self.p) - 1) * (2 * self.nu + 1)) * self.lift

    def crossing(self):
        """The step of x^2 from the cell's last point to the next cell's point 0, at 4^-FINEST."""
        return (2 * self.nu + 1) * self.lift


def rises(nu):
    """How far theta / pi rises across cell nu, near enough to choose its lattice: 2 x^2 ln x - x^2 at its ends."""
    def theta(x):
        return 2 * x * x * math.log(x) - x * x
    return theta(nu + 1) - theta(nu)


def lattice(nu, rate):
    """The p of cell nu: the least with 2^p at least `rate` times theta / pi's rise across it."""
    return max(COARSEST, math.ceil(math.log2(rate * rises(nu))))


class Control:
    """Each cell's lattice from one local cost, its every term a field measured on the run.

    A cell at 2^p points holds r = 2^p / Z points a zero, Z = theta / pi's rise across it. Two zeros closer than a step
    hide between the same two points, and with the spacing of the GUE, small gaps g at density (pi^2 / 3) g^2, the zeros
    missed number mu = c Z / r^3, c = pi^2 / 18. A cell missing one is run again, and the cost of closing it from p is
    C(p) = T(p) + (1 - exp(-mu(p))) C(q), q the next lattice up, T(p) the time a run at 2^p points takes. The points
    cost T, the misses cost the run they force, and p is the least C, moved at most one a cell.

    c is held as the ratio of the zeros missed to the sum of Z / r^3 over the cells measured, starting from the GUE's
    value with the weight of PRIOR cells' worth of misses; a cell's misses are the shortfall N holds it to.
    T(p) = f + a 2^p, f and a fit by least squares to the runs timed, f from FIXED and a from the first run until two
    lattices are timed. None of it touches the proof: the count certifies whatever lattice a cell runs on."""

    PRIOR = 4.0
    FIXED = 2.0

    def __init__(self):
        self.missed = Fraction(0)
        self.exposure = Fraction(0)
        self.timed = []
        self.last_p = None

    def c(self):
        prior = Fraction(PI_LOW ** 2 / 18)
        return (prior * self.PRIOR + self.missed) / (self.PRIOR + self.exposure)

    def measure(self, nu, p, missed):
        z = rises(nu)
        self.missed += missed
        self.exposure += Fraction(z ** 4) / Fraction(8 ** p)

    def timing(self, p, seconds):
        self.timed.append((1 << p, seconds))

    def cost(self, p):
        sizes = {n for n, _ in self.timed}
        if len(sizes) >= 2:
            n_bar = sum(n for n, _ in self.timed) / len(self.timed)
            s_bar = sum(s for _, s in self.timed) / len(self.timed)
            a = (sum((n - n_bar) * (s - s_bar) for n, s in self.timed) /
                 sum((n - n_bar) ** 2 for n, _ in self.timed))
            a = max(a, 0.0)
            f = max(s_bar - a * n_bar, 0.0)
        elif self.timed:
            n, s = self.timed[-1]
            f = min(self.FIXED, s)
            a = (s - f) / n
        else:
            f, a = self.FIXED, 1e-6
        return f + a * (1 << p)

    def close_cost(self, nu, p):
        """C(p): the time to close cell nu from 2^p points, the reruns it is expected to force included."""
        z = rises(nu)
        c = float(self.c())
        total = self.cost(FINEST)
        for q in range(FINEST - 1, p - 1, -1):
            mu = c * z ** 4 / 8.0 ** q
            total = self.cost(q) + (1.0 - math.exp(-mu)) * total
        return total

    def choose(self, nu, above=None):
        """The p of least C for cell nu, past `above` where given, within one of the last cell's."""
        low = COARSEST if above is None else above + 1
        options = [p for p in range(max(low, math.ceil(math.log2(rises(nu)))), FINEST + 1)]
        p = min(options, key=lambda q: self.close_cost(nu, q))
        if above is None and self.last_p is not None:
            p = min(max(p, self.last_p - 1), self.last_p + 1)
            self.last_p = p
        elif above is None:
            self.last_p = p
        return p


def run_cell(binary, constants, nu, p, method, level=0, listing=0):
    """Cell nu at 2^p points from the device, its main sum by `method`; by Euler-Maclaurin at widening `level`; with
    `listing`, every point's sign, S, Z and w written out beside the sums, at the path the cell keeps."""
    terms = em_terms(level) if method == "em" else 0
    heads = em_heads(nu, terms) if method == "em" else 0
    per_point = heads - 1 if method == "em" else nu
    piece = 1 << p
    while piece * per_point >= 1 << LANE_BITS:
        piece >>= 1
    if method == "em":
        bound, theta_bound = em_bounds(nu, heads, terms)
    else:
        bound, theta_bound = bounds(nu, constants.slope, p, method)
    folder = tempfile.mkdtemp(prefix="turing_")
    given, taken = os.path.join(folder, "in.bin"), os.path.join(folder, "out.txt")
    with open(given, "wb") as handle:
        array.array("q", (1 << p, min(CHECKED, piece), nu, p, ARTANH_TERMS, COS_TERMS, GAMMA_TERMS, NEWTON_STEPS,
                          piece, METHODS[method], ORDER, BETA, E1_TERMS, SINC_TERMS, heads, terms, listing)).tofile(handle)
        for v in ([constants.ln2] + constants.gamma + constants.artanh + constants.cosine +
                  [constants.c96, bound, theta_bound, constants.pi_scaled] + constants.fact +
                  constants.sinc + (em_ratios(terms) if method == "em" else [])):
            put(handle, v)
    # the multiple evaluation's longest programs hold frames past the device's stack limit, and are kept as PTX: built
    # again as C source, they go to NVRTC, which compiles a program of their length far slower than the run
    # a run whose checks fail writes nothing the machine reads; it is run once more, and both failures are printed
    for attempt in range(2):
        ran = subprocess.run([binary, given, taken], capture_output=True, text=True,
                             env=dict(os.environ, CYCLE_RECORD_KEEP_PTX="1"))
        if not ran.returncode:
            break
        print(ran.stdout.strip()[-2000:])
        print(ran.stderr.strip()[-2000:])
        print("  cell %d at 2^%d points: the device run failed, attempt %d" % (nu, p, attempt + 1))
    if ran.returncode:
        raise SystemExit("  cell %d at 2^%d points: the device run failed" % (nu, p))
    with open(taken) as handle:
        cell = Cell(nu, p, [line for line in handle if not line.startswith("point")])
    cell.path = taken
    return cell, bound


def ln_high(t):
    """An upper bound on ln t, from the bits of t's ceiling."""
    return math.ceil(t).bit_length() * LN_TWO_HIGH


def trudgian(x2):
    """Trudgian's bound at t = 2 pi x^2, x^2 at 4^-FINEST, over 2 pi, at 4^-FINEST."""
    t = 2 * PI_HIGH * Fraction(x2, 4 ** FINEST)
    return (Fraction(2067, 1000) + Fraction(59, 1000) * ln_high(t)) * 4 ** FINEST / (2 * PI_LOW)


def joined(before, after):
    """1 where the last certified sign of `before` and the first of `after` differ: a zero between them."""
    return int(before.sign("last") != after.sign("first"))


def below(cell, back):
    """N at cell's F is at least this, over the window from back's F."""
    s, start = back.sums, back.x2("first")
    weight = cell.x2("first") - start
    theta = s["low_after"] * back.lift + cell.sums["low_before"] * cell.lift
    zeros = s["zeros_p_after"] * back.lift - s["zeros_after"] * start + joined(back, cell) * (back.x2("last") - start)
    return 1 + Fraction(theta + (zeros << SCALE_BITS), weight << SCALE_BITS) - trudgian(cell.x2("first")) / weight


def above(cell, ahead):
    """N at cell's F is at most this, over the window on to ahead's F, or to the cell's last point where none is."""
    s, start = cell.sums, cell.x2("first")
    end = ahead.x2("first") if ahead else cell.end_x2()
    weight = end - start
    theta = s["high_after"] * cell.lift
    if ahead:
        theta += cell.crossing() * ahead.at["origin"][3] + ahead.sums["high_upto"] * ahead.lift
    zeros = s["zeros_after"] * end - s["zeros_q_after"] * cell.lift
    return 1 + trudgian(end) / weight + Fraction(theta - (zeros << SCALE_BITS), weight << SCALE_BITS)


def between(cell, ahead):
    """The zeros certified after cell's F, up to ahead's F."""
    return cell.sums["zeros_after"] + joined(cell, ahead)


def t_of(x2):
    return 2 * math.pi * x2 / 4 ** FINEST


def control(cell):
    """The device's Z against the house's at two points of the cell, at 2^-62 and 40 places."""
    print("  positive control, cell %d:" % cell.nu)
    places = 40
    for j, z in zip((0, cell.points // 3), cell.control):
        device = Fraction(z, 1 << SCALE_BITS)
        s = (cell.nu ** 2 << cell.p) + j * (2 * cell.nu + 1)
        x = naturals._integer_sqrt(s * 10 ** (2 * places) >> cell.p)
        main, remainder = rs.rs_cut_at((cell.nu, rs.zz.pair(x - cell.nu * 10 ** places, places), places), 0)
        house = Fraction(main + remainder, 10 ** places)
        print("    s = %d^2 + %d (2 %d + 1) / 2^%d  device Z %.15f  house Z %.15f  apart %.3e" %
              (cell.nu, j, cell.nu, cell.p, float(device), float(house), abs(float(device - house))))


def control_em(cell, other=None, bounds_sum=None):
    """Euler-Maclaurin's Z at two points of a cell against the house's exact_zeta_zeros routes, and where `other` is
    the same cell by Riemann-Siegel, against its Z within the two bounds."""
    print("  positive control, cell %d by Euler-Maclaurin:" % cell.nu)
    places = 40
    for at, (j, z) in enumerate(zip((0, cell.points // 3), cell.control)):
        device = Fraction(z, 1 << SCALE_BITS)
        big_s = (cell.nu ** 2 << cell.p) + j * (2 * cell.nu + 1)
        x = naturals._integer_sqrt(big_s * 10 ** (2 * places) >> cell.p)
        house = Fraction(rs.em_at((cell.nu, rs.zz.pair(x - cell.nu * 10 ** places, places), 30)), 10 ** 30)
        line = "    s = %d^2 + %d (2 %d + 1) / 2^%d  device Z %.15f  house Z %.15f  apart %.3e" % (
            cell.nu, j, cell.nu, cell.p, float(device), float(house), abs(float(device - house)))
        if other is not None:
            gap = abs(device - Fraction(other.control[at], 1 << SCALE_BITS))
            line += "  from Riemann-Siegel's %.3e, within %.3e: %s" % (
                float(gap), float(bounds_sum / 2 ** SCALE_BITS), gap <= Fraction(bounds_sum, 1 << SCALE_BITS))
        print(line)


def main_em(binary, first, last, rate):
    """Every zero up to T_a, cell `last` + 1's F, by Euler-Maclaurin over cells `first` to `last`, against N(T_a)
    held by Turing's method over cells `last`, `last` + 1 and `last` + 2 by Riemann-Siegel.

    A dead reckoning walk: each point's Z is a fix, its bound the error about it, and a point clearing its bound is a
    certified sign. Where the count falls short, a cell with a mark of two uncertified points, or every cell where
    none has one, widens its search, four times the points and ten Bernoulli terms more with N to match, until the
    count closes or the rounds run out. If the certified sign changes in (t at cell `first`'s F, T_a] reach N(T_a),
    each is a zero on the line and simple, and none lies below: the count is at most N(T_a) less N at the start."""
    sys.stdout.reconfigure(line_buffering=True)
    constants = Constants()
    above_cells = {}
    for nu in (last, last + 1, last + 2):
        above_cells[nu], _ = run_cell(binary, constants, nu, lattice(nu, rate), "pairs")
    target = above_cells[last + 1]
    low = math.ceil(below(target, above_cells[last]))
    high = math.floor(above(target, above_cells[last + 2]))
    print("  T_a = %.6f, cell %d's F by Riemann-Siegel: %d <= N(T_a) <= %d" % (t_of(target.x2("first")), last + 1, low, high))
    cells, levels = {}, {}
    for nu in range(first, last + 1):
        levels[nu] = 0
        cells[nu], bound = run_cell(binary, constants, nu, lattice(nu, rate), "em", 0)
        print("  cell %d at 2^%d points by Euler-Maclaurin, N = %d, M = %d: bound on Z %.3e, %d zeros past F, %d loose" %
              (nu, cells[nu].p, em_heads(nu, em_terms(0)), em_terms(0), bound / 2 ** SCALE_BITS,
               cells[nu].sums["zeros_after"], cells[nu].sums["loose"]))
    control_em(cells[first])
    print("  steps of the pole, point, pair, verdict and count programs, then Euler-Maclaurin's: %s" %
          cells[first].steps)
    rs_bound, _ = bounds(last, constants.slope, cells[last].p, "pairs")
    em_bound, _ = em_bounds(last, em_heads(last, em_terms(0)), em_terms(0))
    control_em(cells[last], above_cells[last], rs_bound + em_bound)

    def counted():
        joins = [between(cells[nu], cells[nu + 1]) for nu in range(first, last)]
        return sum(joins) + between(cells[last], target)

    count = counted()
    for round_ in range(ROUNDS + 1):
        print("  round %d: %d sign changes certified in (%.6f, %.6f], N(T_a) %d" %
              (round_, count, t_of(cells[first].x2("first")), t_of(target.x2("first")), low))
        if count >= low or round_ == ROUNDS:
            break
        need_fix = [nu for nu in cells if cells[nu].sums["loose"] > 0] or list(cells)
        for nu in need_fix:
            if cells[nu].p + 2 <= FINEST:
                levels[nu] += 1
                cells[nu], _ = run_cell(binary, constants, nu, cells[nu].p + 2, "em", levels[nu])
        count = counted()
    failed = sum(cell.failed for cell in cells.values()) + sum(cell.failed for cell in above_cells.values())
    proven = (count == high) and (failed == 0)
    print("  %s; %d host checks failed" %
          ("every zero in (0, %.6f] is on the line and simple: %d" % (t_of(target.x2("first")), count) if proven
           else "the count does not close", failed))
    return 0 if proven else 1


def main():
    binary = sys.argv[1]
    if len(sys.argv) > 5 and sys.argv[5] == "em":
        first = int(sys.argv[2]) if len(sys.argv) > 2 else 1
        last = int(sys.argv[3]) if len(sys.argv) > 3 else 10
        rate = int(sys.argv[4]) if len(sys.argv) > 4 else 4
        if first < 1 or 2 * last * last <= 168:
            raise SystemExit("  Euler-Maclaurin runs from cell 1 up, and its last cell must start past t = 168 pi")
        return main_em(binary, first, last, rate)
    first = int(sys.argv[2]) if len(sys.argv) > 2 else 10
    last = int(sys.argv[3]) if len(sys.argv) > 3 else 20
    rate = int(sys.argv[4]) if len(sys.argv) > 4 else 4
    method = sys.argv[5] if len(sys.argv) > 5 else "pairs"
    if 2 * first * first <= 168 or last < first + 2 or method not in METHODS:
        raise SystemExit("  the first cell must start past t = 168 pi, at nu = 10 or above, three cells are the least, "
                         "and the method is one of %s" % ", ".join(METHODS))
    sys.stdout.reconfigure(line_buffering=True)
    constants = Constants()
    control_ = Control() if rate == 0 else None
    cells = {}

    def shortfall(nu):
        """The zeros cell nu misses, from N held at its F and the next cell's: 0 where it closes."""
        low = math.ceil(below(cells[nu], cells[nu - 1]))
        high = math.floor(above(cells[nu + 1], cells[nu + 2]))
        return max(0, high - low - between(cells[nu], cells[nu + 1]))

    def timed(nu, p):
        began = time.time()
        cell, bound = run_cell(binary, constants, nu, p, method)
        if control_:
            control_.timing(p, time.time() - began)
        return cell, bound

    for nu in range(first, last + 1):
        p = control_.choose(nu) if control_ else lattice(nu, rate)
        cells[nu], bound = timed(nu, p)
        if control_ and nu - 3 >= first:
            m = nu - 2
            control_.measure(m, cells[m].p, shortfall(m))
        if nu == first:
            control(cells[nu])
            print("  steps of the pole, point, pair, verdict and count programs, then the multiple evaluation's: %s" %
                  cells[nu].steps)
        print("  cell %d at 2^%d points: bound on Z %.3e, F %d, %d zeros past F, %d loose%s" %
              (nu, cells[nu].p, bound / 2 ** SCALE_BITS, cells[nu].first, cells[nu].sums["zeros_after"],
               cells[nu].sums["loose"], "; c %.3f, a run %.2f s at 2^%d" %
               (float(control_.c()), control_.timed[-1][1], cells[nu].p) if control_ else ""))
        if cells[nu].apart:
            print("    the transform's Z and the pairs' differ by %.3e at most, at point %d" %
                  (cells[nu].apart[0] / 2 ** SCALE_BITS, cells[nu].apart[1]))
    for round_ in range(ROUNDS + 1):
        held = {}
        for nu in range(first + 1, last + 1):
            ahead = cells.get(nu + 1) if nu < last else None
            held[nu] = (math.ceil(below(cells[nu], cells[nu - 1])), math.floor(above(cells[nu], ahead)))
        loose = [nu for nu, (low, high) in held.items() if low != high]
        short = [nu for nu in range(first + 1, last) if held[nu + 1][1] - held[nu][0] > between(cells[nu], cells[nu + 1])]
        count = sum(between(cells[nu], cells[nu + 1]) for nu in range(first + 1, last))
        print("  round %d: %d zeros certified, %d cells short %s, %d points where N is not held to one value" %
              (round_, count, len(short), short[:12], len(loose)))
        if not short or round_ == ROUNDS:
            break
        coarse = set(short) | {m for nu in loose for m in (nu - 1, nu, nu + 1) if first <= m <= last}
        for nu in sorted(coarse):
            if cells[nu].p + 2 <= FINEST and not control_:
                cells[nu], _ = run_cell(binary, constants, nu, cells[nu].p + 2, method)
            elif control_ and cells[nu].p < FINEST:
                cells[nu], _ = timed(nu, control_.choose(nu, cells[nu].p))
    failed = sum(cell.failed for cell in cells.values())
    (low_a, high_a), (low_z, high_z) = held[first + 1], held[last]
    print("  T_a = %.6f: %d <= N(T_a) <= %d" % (t_of(cells[first + 1].x2("first")), low_a, high_a))
    print("  T_b = %.6f: %d <= N(T_b) <= %d" % (t_of(cells[last].x2("first")), low_z, high_z))
    print("  zeros certified in (T_a, T_b]: %d; N(T_b) - N(T_a) <= %d" % (count, high_z - low_a))
    proven = (high_z - low_a <= count) and (failed == 0)
    print("  %s; %d host checks failed" %
          ("every zero in (T_a, T_b] is on the line and simple: %d" % count if proven else "the count does not close",
           failed))
    return 0 if proven else 1


if __name__ == "__main__":
    sys.exit(main())
