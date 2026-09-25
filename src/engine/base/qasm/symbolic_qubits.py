#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Symbolic-phase exact qubits: the delta stays a variable, the readout comes back as a function of it.

Lane 1 -- extend the field. mps_qubits.py works over Q(sqrt2)[i], a number field. Here the number field
expands to the rational-function field  Q(sqrt2)[i](w),  w = e^{i*phi(Delta)} = e^{i*k/Delta^3}, the
infinitely-variable delta carried as a formal unit on the circle (conjugation sends w -> 1/w). A field
element is a rational function num(w)/den(w) with coefficients in Q(sqrt2)[i], kept reduced by exact
polynomial GCD. Because it is a FIELD, the same rank-revealing M = C.F Gaussian elimination runs unchanged,
and a bond trims only under *absolute symbolic* linear dependence -- a coincidence at one Delta never
collapses it, only an identity true for every Delta.

Lane 3 -- the boundary lens. To read <psi|O|psi> we never expand the 2^n vector: we insert the observable
O as a local tensor and contract the physical legs from the edges inward (the standard MPS environment
sweep). The result is an exact element of Q(sqrt2)[i](w) -- an exact symbolic expression parameterized by
Delta. For the delta-Bell state (|00> + w|11>)/sqrt2 the lens returns  <X0 X1> = (w + 1/w)/2 = cos(k/Delta^3)
EXACTLY: infinity frozen between the two points, read back as an exact function of their separation.

Cross-check (host vs host): w = e^{i pi/4} is itself a value in Q(sqrt2)[i], and CPHASE(e^{i pi/4}) is the
controlled-T gate. Specializing every symbolic result at w = e^{i pi/4} reproduces the numeric engine's
controlled-T expectations to the exact rational -- the same agreement discipline the device core proves
itself by. The generic MPS below runs over either field object (KField = Q(sqrt2)[i], RatField = its
rational-function extension) with no change; that is the integration the two lanes share.

No third-party libraries; Python integers and fractions.Fraction only, on top of mps_qubits' exact field.

    python symbolic_qubits.py
"""

import sys

from mps_qubits import (
    f_add as k_add, f_sub as k_sub, f_neg as k_neg, f_mul as k_mul,
    f_conj as k_conj, f_inv as k_inv, f_iszero as k_iszero,
    F_ZERO as K_ZERO, F_ONE as K_ONE, F_I as K_I,
    INV_SQRT2 as K_INV_SQRT2, EXP_IPI4 as K_EXP_IPI4,
)

# --- polynomials in w over K = Q(sqrt2)[i], as dict {exponent: K element}; empty dict = zero -------------

def p_iszero(p):
    return not p

def p_trim(p):
    return {e: c for e, c in p.items() if not k_iszero(c)}

def p_add(a, b):
    out = dict(a)
    for e, c in b.items():
        out[e] = k_add(out.get(e, K_ZERO), c)
    return p_trim(out)

def p_neg(a):
    return {e: k_neg(c) for e, c in a.items()}

def p_sub(a, b):
    return p_add(a, p_neg(b))

def p_mul(a, b):
    out = {}
    for ea, ca in a.items():
        for eb, cb in b.items():
            e = ea + eb
            out[e] = k_add(out.get(e, K_ZERO), k_mul(ca, cb))
    return p_trim(out)

def p_scale(a, k):
    return p_trim({e: k_mul(c, k) for e, c in a.items()})

def p_shift(a, t):
    return {e + t: c for e, c in a.items()}

def p_degree(a):
    return max(a)

def p_divmod(a, b):
    # ordinary polynomials (nonnegative exponents), b nonzero, over the field K
    q = {}
    r = dict(a)
    bdeg = p_degree(b)
    binv = k_inv(b[bdeg])
    while r:
        rdeg = p_degree(r)
        if rdeg < bdeg:
            break
        coeff = k_mul(r[rdeg], binv)
        shift = rdeg - bdeg
        q[shift] = k_add(q.get(shift, K_ZERO), coeff)
        for e, c in b.items():
            ne = e + shift
            r[ne] = k_sub(r.get(ne, K_ZERO), k_mul(coeff, c))
            if k_iszero(r[ne]):
                del r[ne]
    return q, r

def p_gcd(a, b):
    a, b = dict(a), dict(b)
    while not p_iszero(b):
        _, r = p_divmod(a, b)
        a, b = b, r
    if p_iszero(a):
        return {}
    return p_scale(a, k_inv(a[p_degree(a)]))     # monic


# --- the field Q(sqrt2)[i](w): reduced (num, den) rational functions ---------------------------------------

def rat_make(num, den):
    if p_iszero(num):
        return ({}, {0: K_ONE})
    if p_iszero(den):
        raise ZeroDivisionError("rational function with zero denominator")
    low = min(min(num), min(den))                # clear negative exponents by an equal shift
    num, den = p_shift(num, -low), p_shift(den, -low)
    g = p_gcd(num, den)
    num, _ = p_divmod(num, g)
    den, _ = p_divmod(den, g)
    lead_inv = k_inv(den[p_degree(den)])         # make denominator monic -> canonical
    return (p_scale(num, lead_inv), p_scale(den, lead_inv))

def rat_add(x, y):
    return rat_make(p_add(p_mul(x[0], y[1]), p_mul(y[0], x[1])), p_mul(x[1], y[1]))

def rat_sub(x, y):
    return rat_add(x, (p_neg(y[0]), y[1]))

def rat_neg(x):
    return (p_neg(x[0]), x[1])

def rat_mul(x, y):
    return rat_make(p_mul(x[0], y[0]), p_mul(x[1], y[1]))

def rat_inv(x):
    return rat_make(x[1], x[0])

def rat_iszero(x):
    return p_iszero(x[0])

def rat_conj(x):
    # w on the unit circle: conjugation sends w -> 1/w and conjugates the K coefficients
    num = {-e: k_conj(c) for e, c in x[0].items()}
    den = {-e: k_conj(c) for e, c in x[1].items()}
    return rat_make(num, den)

def rat_equal(x, y):
    return rat_iszero(rat_sub(x, y))

def rat_embed(c):
    return rat_make({0: c}, {0: K_ONE})

def k_pow(v, e):
    out = K_ONE
    for _ in range(e):
        out = k_mul(out, v)
    return out

def rat_eval(x, kval):
    num = K_ZERO
    for e, c in x[0].items():
        num = k_add(num, k_mul(c, k_pow(kval, e)))
    den = K_ZERO
    for e, c in x[1].items():
        den = k_add(den, k_mul(c, k_pow(kval, e)))
    return k_mul(num, k_inv(den))

RAT_ZERO = ({}, {0: K_ONE})
RAT_ONE = ({0: K_ONE}, {0: K_ONE})
RAT_OMEGA = ({1: K_ONE}, {0: K_ONE})             # w itself


# --- field objects: the generic MPS runs over either one unchanged ---------------------------------------

class KField:
    zero, one = K_ZERO, K_ONE
    add, sub, neg, mul, inv, conj, iszero = (
        staticmethod(k_add), staticmethod(k_sub), staticmethod(k_neg),
        staticmethod(k_mul), staticmethod(k_inv), staticmethod(k_conj), staticmethod(k_iszero))

    @staticmethod
    def embed_k(c):
        return c

class RatField:
    zero, one = RAT_ZERO, RAT_ONE
    add, sub, neg, mul, inv, conj, iszero = (
        staticmethod(rat_add), staticmethod(rat_sub), staticmethod(rat_neg),
        staticmethod(rat_mul), staticmethod(rat_inv), staticmethod(rat_conj), staticmethod(rat_iszero))

    @staticmethod
    def embed_k(c):
        return rat_embed(c)


# --- generic exact linear algebra over a field object ----------------------------------------------------

def zeros(fld, rows, cols):
    return [[fld.zero] * cols for _ in range(rows)]

def mat_mul(fld, a, b):
    ra, ca, cb = len(a), len(a[0]), len(b[0])
    out = zeros(fld, ra, cb)
    for i in range(ra):
        for t in range(ca):
            aik = a[i][t]
            if fld.iszero(aik):
                continue
            for j in range(cb):
                out[i][j] = fld.add(out[i][j], fld.mul(aik, b[t][j]))
    return out

def mat_add(fld, a, b):
    return [[fld.add(a[i][j], b[i][j]) for j in range(len(a[0]))] for i in range(len(a))]

def scalar_mul(fld, s, a):
    return [[fld.mul(s, a[i][j]) for j in range(len(a[0]))] for i in range(len(a))]

def conj_transpose(fld, a):
    r, c = len(a), len(a[0])
    return [[fld.conj(a[i][j]) for i in range(r)] for j in range(c)]

def rank_factorization(fld, m):
    rows = [list(r) for r in m]
    height, width = len(rows), len(rows[0])
    pivots, pr = [], 0
    for col in range(width):
        sel = next((r for r in range(pr, height) if not fld.iszero(rows[r][col])), None)
        if sel is None:
            continue
        rows[pr], rows[sel] = rows[sel], rows[pr]
        inv = fld.inv(rows[pr][col])
        rows[pr] = [fld.mul(v, inv) for v in rows[pr]]
        for r in range(height):
            if r != pr and not fld.iszero(rows[r][col]):
                factor = rows[r][col]
                rows[r] = [fld.sub(rows[r][j], fld.mul(factor, rows[pr][j])) for j in range(width)]
        pivots.append(col)
        pr += 1
        if pr == height:
            break
    rank = len(pivots)
    c = [[m[i][p] for p in pivots] for i in range(height)]
    f = [rows[i] for i in range(rank)]
    return c, f, rank


# --- generic exact matrix-product state ------------------------------------------------------------------

class MPS:
    def __init__(self, n, fld):
        self.n, self.fld = n, fld
        self.tensors = [[[[fld.one]], [[fld.zero]]] for _ in range(n)]

    def apply_1q(self, gate, k):
        fld = self.fld
        m0, m1 = self.tensors[k]
        self.tensors[k] = [
            mat_add(fld, scalar_mul(fld, gate[0][0], m0), scalar_mul(fld, gate[0][1], m1)),
            mat_add(fld, scalar_mul(fld, gate[1][0], m0), scalar_mul(fld, gate[1][1], m1))]

    def apply_2q(self, gate, k):
        fld = self.fld
        a, b = self.tensors[k], self.tensors[k + 1]
        dl, dr = len(a[0]), len(b[0][0])
        theta = [[mat_mul(fld, a[s0], b[s1]) for s1 in range(2)] for s0 in range(2)]
        big = zeros(fld, dl * 2, 2 * dr)
        for t0 in range(2):
            for t1 in range(2):
                acc = zeros(fld, dl, dr)
                for s0 in range(2):
                    for s1 in range(2):
                        g = gate[t0 * 2 + t1][s0 * 2 + s1]
                        if not fld.iszero(g):
                            acc = mat_add(fld, acc, scalar_mul(fld, g, theta[s0][s1]))
                for x in range(dl):
                    for y in range(dr):
                        big[x * 2 + t0][t1 * dr + y] = acc[x][y]
        c, f, rank = rank_factorization(fld, big)
        left = [zeros(fld, dl, rank) for _ in range(2)]
        right = [zeros(fld, rank, dr) for _ in range(2)]
        for t0 in range(2):
            for x in range(dl):
                for r in range(rank):
                    left[t0][x][r] = c[x * 2 + t0][r]
        for t1 in range(2):
            for r in range(rank):
                for y in range(dr):
                    right[t1][r][y] = f[r][t1 * dr + y]
        self.tensors[k], self.tensors[k + 1] = left, right

    def amplitude(self, bits):
        fld = self.fld
        product = self.tensors[0][bits[0]]
        for k in range(1, self.n):
            product = mat_mul(fld, product, self.tensors[k][bits[k]])
        return product[0][0]

    def bond_dims(self):
        return [len(self.tensors[k][0][0]) for k in range(self.n - 1)]


def expectation(fld, mps, ops):
    """Boundary lens: <psi|O|psi> by inserting each local operator and contracting the legs edge-inward."""
    left = [[fld.one]]
    for k in range(mps.n):
        site = [mps.tensors[k][0], mps.tensors[k][1]]
        op = ops[k]
        acc = None
        for sp in range(2):
            for s in range(2):
                coeff = op[sp][s]
                if fld.iszero(coeff):
                    continue
                term = mat_mul(fld, mat_mul(fld, conj_transpose(fld, site[sp]), left), site[s])
                term = scalar_mul(fld, coeff, term)
                acc = term if acc is None else mat_add(fld, acc, term)
        left = acc if acc is not None else zeros(fld, len(site[0][0]), len(site[0][0]))
    return left[0][0]


# --- gates and observables over a field object -----------------------------------------------------------

def gate_h(fld):
    s = fld.embed_k(K_INV_SQRT2)
    return [[s, s], [s, fld.neg(s)]]

def gate_x(fld):
    return [[fld.zero, fld.one], [fld.one, fld.zero]]

def gate_cnot(fld):
    z, o = fld.zero, fld.one
    return [[o, z, z, z], [z, o, z, z], [z, z, z, o], [z, z, o, z]]

def gate_cphase(fld, phase):
    z, o = fld.zero, fld.one
    return [[o, z, z, z], [z, o, z, z], [z, z, o, z], [z, z, z, phase]]

def obs_i(fld):
    return [[fld.one, fld.zero], [fld.zero, fld.one]]

def obs_x(fld):
    return [[fld.zero, fld.one], [fld.one, fld.zero]]

def obs_z(fld):
    return [[fld.one, fld.zero], [fld.zero, fld.neg(fld.one)]]


# --- rendering -------------------------------------------------------------------------------------------

def k_short(c):
    a, b, cc, d = c

    def real(x, y):
        if y == 0:
            return "%s" % x
        if x == 0:
            return ("%s" % y if y != 1 else "") + "sqrt2" if y != 1 else "sqrt2"
        return "(%s+%ssqrt2)" % (x, y)
    re = real(a, b)
    im = real(cc, d)
    if cc == 0 and d == 0:
        return re
    if a == 0 and b == 0:
        return "%s i" % im
    return "%s + %s i" % (re, im)

def p_str(p):
    if p_iszero(p):
        return "0"
    parts = []
    for e in sorted(p):
        c = k_short(p[e])
        if e == 0:
            parts.append(c)
        elif e == 1:
            parts.append("(%s)w" % c if c not in ("1",) else "w")
        else:
            parts.append("(%s)w^%d" % (c, e) if c not in ("1",) else "w^%d" % e)
    return " + ".join(parts)

def rat_str(x):
    num, den = x
    if den == {0: K_ONE}:
        return p_str(num)
    return "(%s) / (%s)" % (p_str(num), p_str(den))


# --- demo ------------------------------------------------------------------------------------------------

def build_delta_bell(fld, phase):
    state = MPS(2, fld)
    state.apply_1q(gate_h(fld), 0)
    state.apply_2q(gate_cnot(fld), 0)
    state.apply_2q(gate_cphase(fld, phase), 0)
    return state

def build_delta_ghz(fld, phase, n):
    state = MPS(n, fld)
    state.apply_1q(gate_h(fld), 0)
    for k in range(n - 1):
        state.apply_2q(gate_cnot(fld), k)
    state.apply_2q(gate_cphase(fld, phase), n - 2)
    return state


def main():
    rf = RatField
    kf = KField

    print("Lane 1 -- w = e^{i k/Delta^3} carried symbolically over Q(sqrt2)[i](w)")
    bell = build_delta_bell(rf, RAT_OMEGA)
    print("  delta-Bell (|00> + w|11>)/sqrt2   bond dims %s" % bell.bond_dims())
    print("    <00|psi> = %s" % rat_str(bell.amplitude([0, 0])))
    print("    <11|psi> = %s" % rat_str(bell.amplitude([1, 1])))
    norm = expectation(rf, bell, [obs_i(rf), obs_i(rf)])
    print("    <psi|psi> = %s   (%s -- unitary phase, w cancels)"
          % (rat_str(norm), "EXACTLY 1" if rat_equal(norm, RAT_ONE) else "NOT 1 -- bug"))

    print("\nLane 3 -- boundary lens: <psi|O|psi> contracted edge-inward, exact function of Delta")
    xx = expectation(rf, bell, [obs_x(rf), obs_x(rf)])
    zz = expectation(rf, bell, [obs_z(rf), obs_z(rf)])
    x0 = expectation(rf, bell, [obs_x(rf), obs_i(rf)])
    print("    <X0 X1> = %s        = (w + 1/w)/2 = cos(k/Delta^3)" % rat_str(xx))
    print("    <Z0 Z1> = %s" % rat_str(zz))
    print("    <X0>    = %s" % rat_str(x0))

    print("\n  delta-GHZ3 (|000> + w|111>)/sqrt2")
    ghz = build_delta_ghz(rf, RAT_OMEGA, 3)
    xxx = expectation(rf, ghz, [obs_x(rf), obs_x(rf), obs_x(rf)])
    print("    bond dims %s   <X0 X1 X2> = %s   = cos(k/Delta^3)" % (ghz.bond_dims(), rat_str(xxx)))

    print("\n  bond trims only under ABSOLUTE symbolic dependence:")
    prod = MPS(3, rf)
    phase_1q = [[RAT_ONE, RAT_ZERO], [RAT_ZERO, RAT_OMEGA]]     # diag(1, w): a local Delta-phase, no coupling
    for q in range(3):
        prod.apply_1q(gate_h(rf), q)
    prod.apply_1q(phase_1q, 0)
    print("    |+++> with a single-qubit phase on wire 0: bond dims %s (product stays rank 1)"
          % prod.bond_dims())

    print("\nCross-check (host vs host): specialize w = e^{i pi/4}; CPHASE(e^{i pi/4}) = controlled-T")
    sym_xx = rat_eval(xx, K_EXP_IPI4)
    num_bell = build_delta_bell(kf, kf.embed_k(K_EXP_IPI4))
    num_xx = expectation(kf, num_bell, [obs_x(kf), obs_x(kf)])
    agree = (sym_xx == num_xx)
    print("    symbolic <X0X1> at w=e^{i pi/4} : %s" % k_short(sym_xx))
    print("    numeric  <X0X1> (controlled-T)  : %s" % k_short(num_xx))
    print("    cos(pi/4) = 1/sqrt2 ; %s" % ("AGREE" if agree else "DIFFER -- bug"))

    sym_norm = rat_eval(norm, K_EXP_IPI4)
    print("    norm at w=e^{i pi/4} : %s (%s)"
          % (k_short(sym_norm), "EXACTLY 1" if sym_norm == K_ONE else "NOT 1 -- bug"))

    print("\n  the delta never became a number; the lens read the field back as an exact function of it.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
