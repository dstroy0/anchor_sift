#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-016
#
# The Navier-Stokes equations on the unit torus, run in the engine's exact integer arithmetic over the
# sets Fefferman's problem statement names: an exact solution reproduced by two routes, the horizon a
# generic datum runs past, the two removals (viscosity, force) shown on an instance to change the
# solution, and the countable island of exactly nameable fields inside the uncountable data class. It
# claims nothing about any open problem. It presents the rigor and stops.
#
#   Usage:  python examples/0_experimental/exact_navier_stokes_on_torus.py
#
# This reads no corpus. It sits in 0_experimental: an arithmetic result shown working, not a stage
# reading. The sets are Fefferman's, read from the Clay statement: equations (1) momentum, (2)
# divergence, (3) initial datum; (8) periodic datum and force with the erratum's periodic pressure; (10)
# periodic solution; (11) smooth pressure and velocity; and (7) bounded energy, which on the torus is
# Parseval's sum over the unit cell. The period is 1, the unit vectors e_j, as the statement writes it.
#
# The arithmetic is the engine's alone: Python integers as the bignum, the decimal inputs read by
# representation.exact as (numerator, places) pairs, and booleans. No float, no Decimal, no fraction
# library. A field on R^3/Z^3 is a finite sum of modes e^{2 pi i k.x}, k in Z^3, each mode carrying a
# Laurent polynomial in pi with Gaussian INTEGER coefficients, and the whole field carrying one positive
# integer denominator, the way exact.py carries one count of decimal places. The denominator is widened
# past a power of ten for one reason: the projection onto divergence-free fields divides by |k|^2, and
# 1/3 has no exact decimal at any scale, and a decimal scale would then have to refuse
# (exact.WillNotFit) where an integer denominator carries the value exactly. Every field is normalized
# by the greatest common divisor of its denominator and every integer in it. Two fields are equal
# exactly when their integers are equal, and pi is a symbol: pi is transcendental (Lindemann 1882), and
# a Laurent polynomial in pi with integer coefficients is therefore zero exactly when every coefficient
# is zero.
#
# A derivative multiplies a mode by 2 pi i k_j, a product convolves modes (a linear convolution on Z^3,
# unaliased), the Laplacian multiplies by -4 pi^2 |k|^2, and the Leray projection removes the gradient
# part mode by mode. Every element is smooth and periodic. (8), (10) and (11) hold by construction,
# (2) is an exact identity, the pressure is in the same ring and so is periodic, and the energy is an
# exact Laurent polynomial in pi over an integer. The solution is carried as Taylor coefficients in t
# at t = 0, u(t) = sum_m u_m t^m / m!, by the recurrence
#
#   u_{m+1} = nu Laplacian u_m - P sum_{j=0}^{m} C(m,j) (u_j . grad) u_{m-j},   p_m from the same sum,
#
# which is (1) differentiated m times at t = 0 with (2) enforced by P. Nothing is rounded anywhere.
#
# Positive control: the Arnold-Beltrami-Childress field u_0 = (A sin 2 pi z + C cos 2 pi y,
# B sin 2 pi x + A cos 2 pi z, C sin 2 pi y + B cos 2 pi x) is Beltrami, curl u_0 = 2 pi u_0. The
# nonlinear term is a pure gradient and u = e^{-4 nu pi^2 t} u_0, p = -e^{-8 nu pi^2 t} |u_0|^2 / 2 solves
# (1), (2), (3) exactly. The recurrence must return u_m = (-4 nu pi^2)^m u_0 and p_m = (-8 nu pi^2)^m p_0
# to the integer, and it does.
#
# Two routes: the velocity recurrence above, with the pressure, and the vorticity recurrence
# omega_{m+1} = nu Laplacian omega_m - sum_j C(m,j) [ (u_j . grad) omega_{m-j} - (omega_j . grad) u_{m-j} ]
# with u_j recovered from omega_j by Biot-Savart, no pressure anywhere. They meet at curl u_m = omega_m at
# every order, on the exact solution and on a generic datum. Drawn null: dropping the vortex-stretching
# term (omega . grad) u, the two-dimensional form of the equation, breaks the agreement in three
# dimensions; a wrong pressure sign leaves a nonzero residual on the exact solution.
#
# Floor: none in the arithmetic. The boundary is the horizon: the Taylor coefficients of a generic datum
# occupy more modes at every order; a truncation at any fixed mode radius therefore misses some order,
# and the count it misses is measured here, not bounded. No bounding: every value is an exact integer
# and every test an exact equality.
#
# Whose forms these are, named with respect. Every object here belongs to the field, and this file only
# runs them exactly: the problem statement, its numbered conditions and the four alternatives are Charles
# Fefferman's, for the Clay Mathematics Institute, read in full including the errata; the equations are
# Navier's and Stokes's, and the inviscid case Euler's; the field with curl u proportional to u is
# Beltrami's, and the three-term example is Arnold's (1965) and Childress's (1970), reported from memory
# of the literature, unread here. The file verifies the solution itself and does not rest on the
# citation; the projection onto divergence-free fields and the pressure it defines are Leray's; the
# recovery of a velocity from its vorticity is the Biot-Savart law, and the vorticity equation is
# Helmholtz's; the energy sum over modes is Parseval's; the transcendence of pi that makes the zero test
# exact is Lindemann's (1882); the recurrence for the Taylor coefficients is the classical power-series
# method of Cauchy and Kovalevskaya. The Beale-Kato-Majda criterion that Fefferman's statement quotes is
# named in the workbook beside this file and is not used here. Nothing in this file is new mathematics.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation import exact  # noqa: E402

VISCOSITY = exact.units("0.1")   # (numerator, decimal places): the engine's reading of decimal text
ORDER = 4                        # Taylor coefficients u_0 .. u_ORDER
AXES = (0, 1, 2)
ZERO_MODE = (0, 0, 0)


# ---------------------------------------------------------------- integers


def gcd(first, second):
    """The greatest common divisor, by Euclid, on absolute values."""
    first, second = abs(first), abs(second)
    while second:
        first, second = second, first % second
    return first


def lcm(first, second):
    return first * second // gcd(first, second)


def binomial(row, column):
    """C(row, column) by the multiplicative recurrence, every division exact."""
    result = 1
    for index in range(column):
        result = result * (row - index) // (index + 1)
    return result


# ---------------------------------------------------------------- Laurent polynomials in pi, Gaussian integer coefficients
#
# a poly is a dict {power of pi: (real, imaginary)} of integers, with no zero entries


def poly_add(left, right):
    total = dict(left)
    for power, (real, imaginary) in right.items():
        have_real, have_imaginary = total.get(power, (0, 0))
        total[power] = (have_real + real, have_imaginary + imaginary)
    return {power: pair for power, pair in total.items() if pair != (0, 0)}


def poly_mul(left, right):
    product = {}
    for left_power, (left_real, left_imaginary) in left.items():
        for right_power, (right_real, right_imaginary) in right.items():
            power = left_power + right_power
            real = left_real * right_real - left_imaginary * right_imaginary
            imaginary = left_real * right_imaginary + left_imaginary * right_real
            have_real, have_imaginary = product.get(power, (0, 0))
            product[power] = (have_real + real, have_imaginary + imaginary)
    return {power: pair for power, pair in product.items() if pair != (0, 0)}


def poly_scale(poly, factor):
    if factor == 0:
        return {}
    return {power: (real * factor, imaginary * factor) for power, (real, imaginary) in poly.items()}


def poly_neg(poly):
    return {power: (-real, -imaginary) for power, (real, imaginary) in poly.items()}


def poly_conj(poly):
    return {power: (real, -imaginary) for power, (real, imaginary) in poly.items()}


def poly_real(poly):
    return {power: (real, 0) for power, (real, _) in poly.items() if real != 0}


def poly_power(poly, exponent):
    result = {0: (1, 0)}
    for _ in range(exponent):
        result = poly_mul(result, poly)
    return result


def poly_gcd(poly, current):
    for real, imaginary in poly.values():
        current = gcd(current, real)
        current = gcd(current, imaginary)
        if current == 1:
            break
    return current


def poly_divide(poly, divisor):
    return {power: (real // divisor, imaginary // divisor) for power, (real, imaginary) in poly.items()}


def poly_text(poly):
    if not poly:
        return "0"
    pieces = []
    for power in sorted(poly):
        real, imaginary = poly[power]
        if imaginary == 0:
            gaussian = str(real)
        elif real == 0:
            gaussian = "%d i" % imaginary
        else:
            gaussian = "(%d + %d i)" % (real, imaginary)
        if power == 0:
            pieces.append(gaussian)
        elif power == 1:
            pieces.append("%s pi" % gaussian)
        else:
            pieces.append("%s pi^%d" % (gaussian, power))
    return " + ".join(pieces)


# ---------------------------------------------------------------- a scalar quantity: a poly over one integer


class Ratio:
    """A Laurent polynomial in pi over one positive integer, normalized by their common divisor."""
    __slots__ = ("poly", "den")

    def __init__(self, poly, den=1):
        if den < 0:
            poly, den = poly_neg(poly), -den
        divisor = poly_gcd(poly, den) if poly else den
        self.poly = poly_divide(poly, divisor)
        self.den = den // divisor

    def is_zero(self):
        return not self.poly

    def __eq__(self, other):
        if not isinstance(other, Ratio):
            return NotImplemented
        return self.poly == other.poly and self.den == other.den

    def __ne__(self, other):
        if not isinstance(other, Ratio):
            return NotImplemented
        return not self == other

    def add(self, other):
        common = lcm(self.den, other.den)
        return Ratio(poly_add(poly_scale(self.poly, common // self.den),
                              poly_scale(other.poly, common // other.den)), common)

    def scale(self, numerator, denominator=1):
        return Ratio(poly_scale(self.poly, numerator), self.den * denominator)

    def real_part(self):
        return Ratio(poly_real(self.poly), self.den)

    def __repr__(self):
        if self.den == 1:
            return poly_text(self.poly)
        return "(%s) / %d" % (poly_text(self.poly), self.den)


# ---------------------------------------------------------------- a scalar field on the unit torus


class Scalar:
    """A finite sum of modes, each carrying a poly, over one positive integer denominator.

    Normalized on construction: the denominator and every integer in every poly share no common divisor,
    so two scalars are equal exactly when their modes and denominator are equal.
    """
    __slots__ = ("modes", "den")

    def __init__(self, modes=None, den=1):
        modes = {mode: poly for mode, poly in (modes or {}).items() if poly}
        if den < 0:
            modes, den = {mode: poly_neg(poly) for mode, poly in modes.items()}, -den
        divisor = den
        for poly in modes.values():
            divisor = poly_gcd(poly, divisor)
            if divisor == 1:
                break
        if not modes:
            divisor = den
        self.modes = {mode: poly_divide(poly, divisor) for mode, poly in modes.items()}
        self.den = den // divisor

    def is_zero(self):
        return not self.modes

    def __eq__(self, other):
        if not isinstance(other, Scalar):
            return NotImplemented
        return self.den == other.den and self.modes == other.modes

    def __ne__(self, other):
        if not isinstance(other, Scalar):
            return NotImplemented
        return not self == other

    def add(self, other):
        common = lcm(self.den, other.den)
        total = {mode: poly_scale(poly, common // self.den) for mode, poly in self.modes.items()}
        for mode, poly in other.modes.items():
            scaled = poly_scale(poly, common // other.den)
            total[mode] = poly_add(total[mode], scaled) if mode in total else scaled
        return Scalar(total, common)

    def neg(self):
        return Scalar({mode: poly_neg(poly) for mode, poly in self.modes.items()}, self.den)

    def sub(self, other):
        return self.add(other.neg())

    def scale(self, numerator, denominator=1):
        """The scalar times numerator / denominator, both integers."""
        return Scalar({mode: poly_scale(poly, numerator) for mode, poly in self.modes.items()},
                      self.den * denominator)

    def times(self, ratio):
        """The scalar times a Ratio."""
        return Scalar({mode: poly_mul(poly, ratio.poly) for mode, poly in self.modes.items()},
                      self.den * ratio.den)

    def mul(self, other):
        """The product of two scalar fields: a linear convolution of their mode sets, exact and unaliased."""
        product = {}
        for left_mode, left_poly in self.modes.items():
            for right_mode, right_poly in other.modes.items():
                mode = (left_mode[0] + right_mode[0], left_mode[1] + right_mode[1], left_mode[2] + right_mode[2])
                term = poly_mul(left_poly, right_poly)
                product[mode] = poly_add(product[mode], term) if mode in product else term
        return Scalar(product, self.den * other.den)

    def derivative(self, axis):
        """d/dx_axis: each mode times 2 pi i k_axis."""
        return Scalar({mode: poly_mul(poly, {1: (0, 2 * mode[axis])}) for mode, poly in self.modes.items()},
                      self.den)

    def laplacian(self):
        """Each mode times -4 pi^2 |k|^2."""
        return Scalar({mode: poly_mul(poly, {2: (-4 * (mode[0] ** 2 + mode[1] ** 2 + mode[2] ** 2), 0)})
                       for mode, poly in self.modes.items()}, self.den)

    def without_mean(self):
        return Scalar({mode: poly for mode, poly in self.modes.items() if mode != ZERO_MODE}, self.den)


# ---------------------------------------------------------------- vector fields: a tuple of three scalars


def vec(*components):
    return tuple(components)


def zero_vec():
    return vec(Scalar(), Scalar(), Scalar())


def vec_add(left, right):
    return tuple(left[axis].add(right[axis]) for axis in AXES)


def vec_sub(left, right):
    return tuple(left[axis].sub(right[axis]) for axis in AXES)


def vec_scale(vector, numerator, denominator=1):
    return tuple(vector[axis].scale(numerator, denominator) for axis in AXES)


def vec_times(vector, ratio):
    return tuple(vector[axis].times(ratio) for axis in AXES)


def vec_is_zero(vector):
    return all(vector[axis].is_zero() for axis in AXES)


def vec_eq(left, right):
    return all(left[axis] == right[axis] for axis in AXES)


def vec_laplacian(vector):
    return tuple(vector[axis].laplacian() for axis in AXES)


def divergence(vector):
    total = Scalar()
    for axis in AXES:
        total = total.add(vector[axis].derivative(axis))
    return total


def gradient(scalar):
    return tuple(scalar.derivative(axis) for axis in AXES)


def curl(vector):
    return vec(vector[2].derivative(1).sub(vector[1].derivative(2)),
               vector[0].derivative(2).sub(vector[2].derivative(0)),
               vector[1].derivative(0).sub(vector[0].derivative(1)))


def advect(carrier, carried):
    """(carrier . grad) carried, component by component."""
    result = []
    for axis in AXES:
        total = Scalar()
        for along in AXES:
            total = total.add(carrier[along].mul(carried[axis].derivative(along)))
        result.append(total)
    return tuple(result)


def dot(left, right):
    total = Scalar()
    for axis in AXES:
        total = total.add(left[axis].mul(right[axis]))
    return total


def modes_of(vector):
    modes = set()
    for axis in AXES:
        modes |= set(vector[axis].modes)
    return modes


def norm_of(mode):
    return mode[0] ** 2 + mode[1] ** 2 + mode[2] ** 2


def common_numerators(vector):
    """The three components brought to one denominator: their polys scaled, and that denominator."""
    common = lcm(lcm(vector[0].den, vector[1].den), vector[2].den)
    numerators = [{mode: poly_scale(poly, common // vector[axis].den) for mode, poly in vector[axis].modes.items()}
                  for axis in AXES]
    return numerators, common


def norm_multiple(modes):
    """The least common multiple of |k|^2 over the nonzero modes: the one integer every projection divides by."""
    multiple = 1
    for mode in modes:
        norm = norm_of(mode)
        if norm:
            multiple = lcm(multiple, norm)
    return multiple


def leray(vector):
    """The divergence-free part: for each mode k, v_k - k (k . v_k) / |k|^2. The mean mode is kept.

    The division is carried by the denominator: every numerator is multiplied by the least common
    multiple M of the |k|^2 present. K (k . v_k) M / |k|^2 is an integer, and the field's denominator
    takes the factor M.
    """
    numerators, common = common_numerators(vector)
    modes = modes_of(vector)
    multiple = norm_multiple(modes)
    result = [dict(), dict(), dict()]
    for mode in modes:
        norm = norm_of(mode)
        components = [numerators[axis].get(mode, {}) for axis in AXES]
        if norm == 0:
            for axis in AXES:
                result[axis][mode] = poly_scale(components[axis], multiple)
            continue
        along = {}
        for axis in AXES:
            along = poly_add(along, poly_scale(components[axis], mode[axis]))
        for axis in AXES:
            result[axis][mode] = poly_add(poly_scale(components[axis], multiple),
                                          poly_neg(poly_scale(along, (multiple // norm) * mode[axis])))
    return tuple(Scalar(result[axis], common * multiple) for axis in AXES)


def pressure_of(nonlinear):
    """The pressure whose gradient is the gradient part of `nonlinear`: p_k = i (k . n_k) / (2 pi |k|^2)."""
    numerators, common = common_numerators(nonlinear)
    modes = modes_of(nonlinear)
    multiple = norm_multiple(modes)
    result = {}
    for mode in modes:
        norm = norm_of(mode)
        if norm == 0:
            continue
        along = {}
        for axis in AXES:
            along = poly_add(along, poly_scale(numerators[axis].get(mode, {}), mode[axis]))
        result[mode] = poly_mul(poly_scale(along, multiple // norm), {-1: (0, 1)})
    return Scalar(result, common * 2 * multiple)


def biot_savart(vorticity):
    """The mean-free divergence-free field with the given curl: u_k = i (k x w_k) / (2 pi |k|^2)."""
    numerators, common = common_numerators(vorticity)
    modes = modes_of(vorticity)
    multiple = norm_multiple(modes)
    result = [dict(), dict(), dict()]
    for mode in modes:
        norm = norm_of(mode)
        if norm == 0:
            continue
        omega = [numerators[axis].get(mode, {}) for axis in AXES]
        cross = [poly_add(poly_scale(omega[2], mode[1]), poly_neg(poly_scale(omega[1], mode[2]))),
                 poly_add(poly_scale(omega[0], mode[2]), poly_neg(poly_scale(omega[2], mode[0]))),
                 poly_add(poly_scale(omega[1], mode[0]), poly_neg(poly_scale(omega[0], mode[1])))]
        for axis in AXES:
            result[axis][mode] = poly_mul(poly_scale(cross[axis], multiple // norm), {-1: (0, 1)})
    return tuple(Scalar(result[axis], common * 2 * multiple) for axis in AXES)


def parseval(left, right):
    """The integral over the unit cell of left . right for real fields: sum_k left_k conj(right_k)."""
    total = Ratio({})
    for axis in AXES:
        piece = {}
        for mode, poly in left[axis].modes.items():
            other = right[axis].modes.get(mode)
            if other is not None:
                piece = poly_add(piece, poly_mul(poly, poly_conj(other)))
        total = total.add(Ratio(piece, left[axis].den * right[axis].den))
    return total.real_part()


# ---------------------------------------------------------------- the recurrences


def viscous(vector, viscosity):
    """nu times a field, nu read as (numerator, places)."""
    return vec_scale(vector, viscosity[0], 10 ** viscosity[1])


def taylor_velocity(datum, viscosity, order):
    """Taylor coefficients u_0..u_order and pressures p_0..p_{order-1} of the solution of (1)-(3)."""
    velocities = [datum]
    pressures = []
    for step in range(order):
        nonlinear = zero_vec()
        for split in range(step + 1):
            term = advect(velocities[split], velocities[step - split])
            nonlinear = vec_add(nonlinear, vec_scale(term, binomial(step, split)))
        pressures.append(pressure_of(nonlinear))
        diffusion = viscous(vec_laplacian(velocities[step]), viscosity)
        velocities.append(vec_sub(diffusion, leray(nonlinear)))
    return velocities, pressures


def taylor_vorticity(datum_vorticity, viscosity, order, stretching=True):
    """Taylor coefficients omega_0..omega_order by the vorticity equation, velocities by Biot-Savart."""
    vorticities = [datum_vorticity]
    for step in range(order):
        transport = zero_vec()
        for split in range(step + 1):
            carrier = biot_savart(vorticities[split])
            carried = biot_savart(vorticities[step - split])
            term = advect(carrier, vorticities[step - split])
            if stretching:
                term = vec_sub(term, advect(vorticities[split], carried))
            transport = vec_add(transport, vec_scale(term, binomial(step, split)))
        diffusion = viscous(vec_laplacian(vorticities[step]), viscosity)
        vorticities.append(vec_sub(diffusion, transport))
    return vorticities


def residual(velocities, pressures, viscosity, step):
    """Order-`step` Taylor coefficient of (1) with (2): u_{m+1} + sum C(m,j)(u_j.grad)u_{m-j} - nu Lap u_m + grad p_m."""
    nonlinear = zero_vec()
    for split in range(step + 1):
        term = advect(velocities[split], velocities[step - split])
        nonlinear = vec_add(nonlinear, vec_scale(term, binomial(step, split)))
    total = vec_add(velocities[step + 1], nonlinear)
    total = vec_sub(total, viscous(vec_laplacian(velocities[step]), viscosity))
    return vec_add(total, gradient(pressures[step]))


# ---------------------------------------------------------------- data


def unit_mode(axis):
    return tuple(1 if index == axis else 0 for index in AXES)


def mirror_of(mode):
    return (-mode[0], -mode[1], -mode[2])


def sine(axis, numerator=1, denominator=1):
    """(numerator/denominator) sin(2 pi x_axis): coefficients -i/2 at +e_axis and +i/2 at -e_axis."""
    plus = unit_mode(axis)
    return Scalar({plus: {0: (0, -numerator)}, mirror_of(plus): {0: (0, numerator)}}, 2 * denominator)


def cosine(axis, numerator=1, denominator=1):
    """(numerator/denominator) cos(2 pi x_axis): coefficient 1/2 at both +e_axis and -e_axis."""
    return harmonic(unit_mode(axis), numerator, denominator)


def harmonic(mode, numerator=1, denominator=1):
    """(numerator/denominator) cos(2 pi k.x) for a mode k: half the amplitude at +k and at -k."""
    return Scalar({mode: {0: (numerator, 0)}, mirror_of(mode): {0: (numerator, 0)}}, 2 * denominator)


def abc_field(amp_a, amp_b, amp_c):
    """The Arnold-Beltrami-Childress field on the unit torus, curl u = 2 pi u. Amplitudes as (numerator, denominator)."""
    return vec(sine(2, *amp_a).add(cosine(1, *amp_c)),
               sine(0, *amp_b).add(cosine(2, *amp_a)),
               sine(1, *amp_c).add(cosine(0, *amp_b)))


def generic_field(amplitude=(1, 1)):
    """A divergence-free field that is not Beltrami and whose nonlinear term is not a gradient."""
    return vec(sine(1, *amplitude).add(sine(2)), sine(2), sine(0))


def is_real_field(vector):
    """A field is real-valued when the coefficient at -k is the conjugate of the one at k."""
    for axis in AXES:
        for mode, poly in vector[axis].modes.items():
            if vector[axis].modes.get(mirror_of(mode), {}) != poly_conj(poly):
                return False
    return True


def mode_radius(vector):
    """The largest |k|_inf over the modes carried, the box horizon the field needs."""
    modes = modes_of(vector)
    return max((max(abs(mode[0]), abs(mode[1]), abs(mode[2])) for mode in modes), default=0)


def mode_reach(vector):
    """The largest |k|_1 over the modes carried: a product of modes adds their vectors. This is the count of
    factors the coefficient has multiplied together, and it climbs by one per order."""
    modes = modes_of(vector)
    return max((abs(mode[0]) + abs(mode[1]) + abs(mode[2]) for mode in modes), default=0)


def modes_outside(vector, radius):
    return sum(1 for mode in modes_of(vector) if max(abs(mode[0]), abs(mode[1]), abs(mode[2])) > radius)


def decay_rate(viscosity, factor):
    """(factor * nu) pi^2 as a Ratio: -4 nu pi^2 for the velocity, -8 nu pi^2 for the pressure."""
    return Ratio({2: (factor * viscosity[0], 0)}, 10 ** viscosity[1])


def ratio_power(ratio, exponent):
    return Ratio(poly_power(ratio.poly, exponent), ratio.den ** exponent)


# ---------------------------------------------------------------- the reports


def report_exact_solution(out):
    """The ABC field: Beltrami, gradient nonlinearity, the recurrence against the closed form, two routes."""
    out.write("  positive control: the Arnold-Beltrami-Childress solution, exact to the integer\n")
    amplitudes = ((1, 1), (2, 1), (3, 1))
    datum = abc_field(*amplitudes)
    rate = decay_rate(VISCOSITY, -4)
    pressure_rate = decay_rate(VISCOSITY, -8)

    real_valued = is_real_field(datum)
    divergence_free = divergence(datum).is_zero()
    beltrami = vec_eq(curl(datum), vec_times(datum, Ratio({1: (2, 0)})))
    nonlinear = advect(datum, datum)
    half_speed = dot(datum, datum).scale(1, 2)
    gradient_nonlinearity = vec_eq(nonlinear, gradient(half_speed))
    projection_vanishes = vec_is_zero(leray(nonlinear))

    velocities, pressures = taylor_velocity(datum, VISCOSITY, ORDER)
    closed_form = all(vec_eq(velocities[step], vec_times(datum, ratio_power(rate, step))) for step in range(ORDER + 1))
    closed_pressure = half_speed.neg().without_mean()  # the pressure is defined up to a constant
    pressure_form = all(pressures[step] == closed_pressure.times(ratio_power(pressure_rate, step))
                        for step in range(ORDER))
    residual_zero = all(vec_is_zero(residual(velocities, pressures, VISCOSITY, step)) for step in range(ORDER))

    vorticities = taylor_vorticity(curl(datum), VISCOSITY, ORDER)
    routes_meet = all(vec_eq(curl(velocities[step]), vorticities[step]) for step in range(ORDER + 1))
    recovered = all(vec_eq(biot_savart(vorticities[step]), velocities[step]) for step in range(ORDER + 1))

    # the energy identity at t = 0: d/dt int |u|^2 = -2 nu int |grad u|^2, with (7) as its consequence
    energy = parseval(datum, datum)
    energy_rate = parseval(datum, velocities[1]).scale(2)
    dissipation = parseval(datum, vec_laplacian(datum)).scale(2 * VISCOSITY[0], 10 ** VISCOSITY[1])
    energy_identity = energy_rate == dissipation

    # drawn nulls: the wrong pressure sign, and the two-dimensional vorticity equation in three dimensions
    wrong_pressures = [pressure.neg() for pressure in pressures]
    wrong_sign_caught = not vec_is_zero(residual(velocities, wrong_pressures, VISCOSITY, 0))
    flat_vorticities = taylor_vorticity(curl(datum), VISCOSITY, ORDER, stretching=False)
    stretching_needed = not vec_eq(curl(velocities[1]), flat_vorticities[1])

    out.write("    A, B, C = 1, 2, 3 ; nu = %d at %d place(s) ; orders 0..%d\n" % (VISCOSITY[0], VISCOSITY[1], ORDER))
    out.write("    real-valued: %s ; divergence-free (2): %s ; Beltrami curl u = 2 pi u: %s\n"
              % (real_valued, divergence_free, beltrami))
    out.write("    (u.grad)u = grad(|u|^2/2): %s ; its Leray projection is zero: %s\n"
              % (gradient_nonlinearity, projection_vanishes))
    out.write("    recurrence gives u_m = (-4 nu pi^2)^m u_0 at every order: %s\n" % closed_form)
    out.write("    pressure p_m = (-8 nu pi^2)^m (-|u_0|^2/2) at every order: %s\n" % pressure_form)
    out.write("    residual of (1) with (2) is zero at every order: %s\n" % residual_zero)
    out.write("    vorticity route meets the velocity route, curl u_m = omega_m: %s ; Biot-Savart returns u_m: %s\n"
              % (routes_meet, recovered))
    out.write("    energy int |u_0|^2 = %s ; d/dt energy at 0 = %s ; -2 nu int |grad u_0|^2 = %s ; equal: %s\n"
              % (energy, energy_rate, dissipation, energy_identity))
    out.write("    null, pressure sign flipped: residual nonzero: %s\n" % wrong_sign_caught)
    out.write("    null, stretching term dropped: routes disagree at order 1: %s\n\n" % stretching_needed)
    return (real_valued and divergence_free and beltrami and gradient_nonlinearity and projection_vanishes
            and closed_form and pressure_form and residual_zero and routes_meet and recovered
            and energy_identity and wrong_sign_caught and stretching_needed)


def report_horizon(out):
    """A generic datum: the Taylor coefficients occupy more modes at every order; the horizon is measured."""
    out.write("  the horizon: a generic datum's coefficients outrun any fixed mode radius\n")
    datum = generic_field()
    divergence_free = divergence(datum).is_zero()
    not_beltrami = not vec_eq(curl(datum), vec_times(datum, Ratio({1: (2, 0)})))
    nonlinear = advect(datum, datum)
    projection_survives = not vec_is_zero(leray(nonlinear))

    velocities, pressures = taylor_velocity(datum, VISCOSITY, ORDER)
    residual_zero = all(vec_is_zero(residual(velocities, pressures, VISCOSITY, step)) for step in range(ORDER))
    vorticities = taylor_vorticity(curl(datum), VISCOSITY, ORDER)
    routes_meet = all(vec_eq(curl(velocities[step]), vorticities[step]) for step in range(ORDER + 1))
    still_divergence_free = all(divergence(velocities[step]).is_zero() for step in range(ORDER + 1))
    still_real = all(is_real_field(velocities[step]) for step in range(ORDER + 1))

    # the energy identity on the generic datum: the nonlinear term and the pressure move no energy
    nonlinear_moves_none = parseval(datum, nonlinear).is_zero()
    pressure_moves_none = parseval(datum, gradient(pressures[0])).is_zero()
    energy_rate = parseval(datum, velocities[1]).scale(2)
    dissipation = parseval(datum, vec_laplacian(datum)).scale(2 * VISCOSITY[0], 10 ** VISCOSITY[1])
    energy_identity = energy_rate == dissipation
    # the null for the identity: a field with divergence, u_0 + grad(cos 2 pi x), moves energy through a pressure
    leaky = vec_add(datum, gradient(cosine(0)))
    leaky_has_divergence = not divergence(leaky).is_zero()
    leaky_moves_energy = not parseval(leaky, gradient(cosine(0))).is_zero()

    radii = [mode_radius(velocities[step]) for step in range(ORDER + 1)]
    reaches = [mode_reach(velocities[step]) for step in range(ORDER + 1)]
    counts = [len(modes_of(velocities[step])) for step in range(ORDER + 1)]
    reach_grows = all(reaches[step + 1] == reaches[step] + 1 for step in range(ORDER))
    radius_grows = radii[ORDER] > radii[0] and all(radii[step + 1] >= radii[step] for step in range(ORDER))
    pressure_present = any(not pressure.is_zero() for pressure in pressures)

    out.write("    divergence-free: %s ; not Beltrami: %s ; Leray part of (u.grad)u survives: %s\n"
              % (divergence_free, not_beltrami, projection_survives))
    out.write("    residual zero at every order: %s ; routes meet at every order: %s\n" % (residual_zero, routes_meet))
    out.write("    every coefficient divergence-free: %s ; every coefficient real-valued: %s ; a pressure appears: %s\n"
              % (still_divergence_free, still_real, pressure_present))
    out.write("    int u.(u.grad)u = 0: %s ; int u.grad p = 0: %s ; energy identity: %s\n"
              % (nonlinear_moves_none, pressure_moves_none, energy_identity))
    out.write("    null, a field with divergence: has divergence %s, moves energy through a pressure %s\n"
              % (leaky_has_divergence, leaky_moves_energy))
    out.write("    order:                 %s\n" % "  ".join("%4d" % step for step in range(ORDER + 1)))
    out.write("    largest |k|_1:         %s\n" % "  ".join("%4d" % reach for reach in reaches))
    out.write("    largest |k|_inf:       %s\n" % "  ".join("%4d" % radius for radius in radii))
    out.write("    modes held:            %s\n" % "  ".join("%4d" % count for count in counts))
    for radius in (1, 2):
        missed = [modes_outside(velocities[step], radius) for step in range(ORDER + 1)]
        out.write("    outside |k|_inf <= %d:  %s\n" % (radius, "  ".join("%4d" % count for count in missed)))
    out.write("    |k|_1 climbs by one per order: %s ; |k|_inf never falls and ends higher: %s (the horizon; no scale closes it)\n\n"
              % (reach_grows, radius_grows))
    return (divergence_free and not_beltrami and projection_survives and residual_zero and routes_meet
            and still_divergence_free and still_real and nonlinear_moves_none and pressure_moves_none
            and energy_identity and leaky_has_divergence and leaky_moves_energy and reach_grows and radius_grows)


def stretched_by(vector, factor):
    """v(factor x) times factor: every mode index multiplied by the integer factor, the amplitude too."""
    return tuple(Scalar({(factor * mode[0], factor * mode[1], factor * mode[2]): poly_scale(poly, factor)
                         for mode, poly in vector[axis].modes.items()}, vector[axis].den) for axis in AXES)


def report_scaling(out):
    """The two exact symmetries: time scaling moves the viscosity, space scaling keeps the period."""
    out.write("  symmetries, exact on the coefficients: the viscosity is a parameter a scaling moves\n")
    datum = generic_field()
    depth = 3
    velocities, _ = taylor_velocity(datum, VISCOSITY, depth)

    # v(x,t) = mu u(x, mu t) solves (1)-(3) with viscosity mu nu: coefficients v_m = mu^{m+1} u_m
    mu = 3
    scaled_viscosity = (mu * VISCOSITY[0], VISCOSITY[1])
    scaled, _ = taylor_velocity(vec_scale(datum, mu), scaled_viscosity, depth)
    time_scaling = all(vec_eq(scaled[step], vec_scale(velocities[step], mu ** (step + 1)))
                       for step in range(depth + 1))

    # v(x,t) = lam u(lam x, lam^2 t) solves (1)-(3) with the same nu and period 1/lam: v_m = lam^{1+2m} u_m(lam x)
    lam = 2
    space_scaled, _ = taylor_velocity(stretched_by(datum, lam), VISCOSITY, depth)
    space_scaling = all(vec_eq(space_scaled[step], vec_scale(stretched_by(velocities[step], lam), lam ** (2 * step)))
                        for step in range(depth + 1))

    # the null: the wrong exponent, mu^m in place of mu^{m+1}, is refused at order 0 already
    wrong_exponent = all(vec_eq(scaled[step], vec_scale(velocities[step], mu ** step)) for step in range(depth + 1))

    out.write("    time scaling mu = %d: v_m = mu^(m+1) u_m at viscosity mu nu, orders 0..%d: %s\n"
              % (mu, depth, time_scaling))
    out.write("    space scaling lam = %d: v_m = lam^(1+2m) u_m(lam x) at the same nu, period kept: %s\n"
              % (lam, space_scaling))
    out.write("    null, exponent mu^m: %s (refused)\n\n" % wrong_exponent)
    return time_scaling and space_scaling and not wrong_exponent


def report_removals(out):
    """Removing the viscosity and removing the force are different removals, on an exact instance each."""
    out.write("  the two removals, on instances: neither solution set inherits the other's membership\n")
    datum = abc_field((1, 1), (2, 1), (3, 1))
    depth = 2
    no_viscosity = (0, 0)

    # viscosity removed: the ABC field is a stationary Euler solution; with viscosity it decays
    euler, euler_pressures = taylor_velocity(datum, no_viscosity, depth)
    stationary = all(vec_is_zero(euler[step]) for step in range(1, depth + 1))
    euler_ok = all(vec_is_zero(residual(euler, euler_pressures, no_viscosity, step)) for step in range(depth))
    # the stationary field's residual in (1) at viscosity nu is -nu Laplacian u_0 = 4 nu pi^2 u_0, nonzero
    stationary_in_viscous = residual(euler, euler_pressures, VISCOSITY, 0)
    expected = vec_times(datum, decay_rate(VISCOSITY, 4))
    viscous_residual = vec_eq(stationary_in_viscous, expected) and not vec_is_zero(stationary_in_viscous)
    # and the decaying field's residual in Euler at t = 0 is u_1 = -4 nu pi^2 u_0, nonzero
    viscous_velocities, viscous_pressures = taylor_velocity(datum, VISCOSITY, depth)
    decaying_in_euler = residual(viscous_velocities, viscous_pressures, no_viscosity, 0)
    euler_residual = (vec_eq(decaying_in_euler, vec_times(datum, decay_rate(VISCOSITY, -4)))
                      and not vec_is_zero(decaying_in_euler))

    # force removed: w(t) = e^{-t} g_0 solves the forced equation with f := its residual, and not the unforced one
    generic = generic_field()
    prescribed = [vec_scale(generic, (-1) ** step) for step in range(depth + 2)]
    forced_pressures = []
    for step in range(depth + 1):
        nonlinear = zero_vec()
        for split in range(step + 1):
            nonlinear = vec_add(nonlinear, vec_scale(advect(prescribed[split], prescribed[step - split]),
                                                     binomial(step, split)))
        forced_pressures.append(pressure_of(nonlinear))
    forces = [residual(prescribed, forced_pressures, VISCOSITY, step) for step in range(depth + 1)]
    force_needed = all(not vec_is_zero(force) for force in forces)
    force_periodic_and_smooth = all(is_real_field(force) for force in forces)
    # the same field against the unforced equation: the residual is the force itself, nonzero
    unforced_residual = residual(prescribed, forced_pressures, VISCOSITY, 0)
    not_unforced = vec_eq(unforced_residual, forces[0]) and not vec_is_zero(unforced_residual)

    out.write("    nu = 0 on the ABC datum: stationary (u_m = 0, m >= 1): %s ; Euler residual zero: %s\n"
              % (stationary, euler_ok))
    out.write("    the stationary field in (1) at nu = %d at %d place(s): residual = 4 nu pi^2 u_0, nonzero: %s\n"
              % (VISCOSITY[0], VISCOSITY[1], viscous_residual))
    out.write("    the decaying field in Euler at t = 0: residual = -4 nu pi^2 u_0, nonzero: %s\n" % euler_residual)
    out.write("    e^(-t) g_0 solves the forced equation with f = its residual, f nonzero at orders 0..%d: %s ; f real and periodic: %s\n"
              % (depth, force_needed, force_periodic_and_smooth))
    out.write("    the same field in the unforced equation: residual = f, nonzero: %s\n\n" % not_unforced)
    return (stationary and euler_ok and viscous_residual and euler_residual and force_needed
            and force_periodic_and_smooth and not_unforced)


def report_island(out):
    """The ring is countable; the data class holds a copy of the bit sequences, which are not."""
    out.write("  the island: exactly nameable fields are countable, the data class (8) is not\n")
    depth = 12
    patterns = ["101100111000", "110010100011"]
    fields = []
    for pattern in patterns:
        component = Scalar()
        for index, bit in enumerate(pattern, start=1):
            if bit == "1":
                component = component.add(harmonic((index, 0, 0), 2, index ** index))
        fields.append(vec(Scalar(), component, Scalar()))
    divergence_free = all(divergence(field).is_zero() for field in fields)
    real_valued = all(is_real_field(field) for field in fields)
    distinct = not vec_eq(fields[0], fields[1])
    # the coefficient at mode n is b_n / n^n, and it names the bit: the map from patterns is injective
    recovered = ["".join("1" if (index, 0, 0) in field[1].modes else "0" for index in range(1, depth + 1))
                 for field in fields]
    injective = recovered == patterns

    out.write("    F_b = sum_n 2 b_n n^-n cos(2 pi n x) e_y, truncated at n = %d, two bit patterns\n" % depth)
    out.write("    divergence-free: %s ; real-valued: %s ; distinct fields: %s ; bits read back: %s\n"
              % (divergence_free, real_valued, distinct, injective))
    out.write("    the full sums are smooth (n^-n beats every power of n) and periodic. They sit in (8);\n")
    out.write("    the bit sequences are uncountable (Cantor, proof_set_theory.py) and the ring is countable.\n\n")
    return divergence_free and real_valued and distinct and injective


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  Navier-Stokes on the unit torus in exact integer arithmetic: rigor shown, nothing claimed\n\n")
    results = [
        report_exact_solution(out),
        report_horizon(out),
        report_scaling(out),
        report_removals(out),
        report_island(out),
    ]
    if all(results):
        out.write("  every check lands: the exact solution is reproduced two ways to the integer, the\n")
        out.write("  generic datum's horizon grows at every order, the symmetries hold exactly, the removals\n")
        out.write("  change the solution on the instance, and the ring is a countable island in the data class.\n")
    else:
        out.write("  a check missed: refuted as stated.\n")
    out.flush()
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
