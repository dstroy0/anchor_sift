#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Compact exact n-qubit simulation: entangled states held by their generators, memory small, no rounding.

The dense twin (exact_qubits.py) carries all 2^n amplitudes. This carries the state the way Doug described
it: each qubit is a small tensor (a "wire"), adjacent wires are joined by a bond (the "field / coupling"),
and the bond dimension across a cut IS the entanglement there -- 1 for a product state, 2 for Bell/GHZ,
growing only with real entanglement. Memory is O(n * chi^2), not O(2^n): 100 entangled qubits live in a few
hundred numbers, not 10^30. This is a matrix-product state, but exact -- every tensor entry is a value in
the field Q(sqrt2)[i], and the bond is trimmed to its EXACT rank after each two-qubit gate by exact Gaussian
elimination (a rank-revealing factorization M = C.F over the field). No SVD, no singular values, no floats:
the compression that a float MPS does approximately, this does exactly, because rank over a field is exact.

What it shows:
  * Bell, GHZ, and non-Clifford (controlled-T) states as compact tensors with exact amplitudes.
  * <psi|psi> = 1 EXACTLY via the transfer-matrix contraction (polynomial in n -- works where 2^n cannot).
  * Bond dimensions staying at the true Schmidt rank (2 for GHZ across every cut, at any n).
  * A 100-qubit GHZ: real 100-partite entanglement, exact amplitudes 1/sqrt2, held in ~800 field elements.
  * Cross-check: for small n the compact state expanded to a dense vector equals a straight dense build,
    amplitude for amplitude -- the same host-vs-device agreement discipline the engine uses to prove itself.

Faithful to the picture: reading an amplitude is contracting the wires (the boundary lens); the bond is the
field between two objects; the exact rank is how entangled they became. No third-party libraries; Python
integers and fractions.Fraction only. hashlib is used for the witness root.

    python mps_qubits.py
"""

import hashlib
import sys
from fractions import Fraction

Q = Fraction

# --- the field Q(sqrt2)[i]: element (a,b,c,d) means (a + b*sqrt2) + i*(c + d*sqrt2), a,b,c,d in Q ----------

def q2_mul(x, y):
    return (x[0] * y[0] + 2 * x[1] * y[1], x[0] * y[1] + x[1] * y[0])

def q2_add(x, y):
    return (x[0] + y[0], x[1] + y[1])

def q2_inv(r):
    # 1/(r0 + r1 sqrt2) = (r0 - r1 sqrt2)/(r0^2 - 2 r1^2)
    den = r[0] * r[0] - 2 * r[1] * r[1]
    return (r[0] / den, -r[1] / den)

def f_add(x, y):
    return (x[0] + y[0], x[1] + y[1], x[2] + y[2], x[3] + y[3])

def f_sub(x, y):
    return (x[0] - y[0], x[1] - y[1], x[2] - y[2], x[3] - y[3])

def f_neg(x):
    return (-x[0], -x[1], -x[2], -x[3])

def f_mul(x, y):
    xr, xi, yr, yi = (x[0], x[1]), (x[2], x[3]), (y[0], y[1]), (y[2], y[3])
    real = q2_add(q2_mul(xr, yr), tuple(-v for v in q2_mul(xi, yi)))
    imag = q2_add(q2_mul(xr, yi), q2_mul(xi, yr))
    return (real[0], real[1], imag[0], imag[1])

def f_conj(x):
    return (x[0], x[1], -x[2], -x[3])

def f_inv(x):
    xr, xi = (x[0], x[1]), (x[2], x[3])
    den = q2_add(q2_mul(xr, xr), q2_mul(xi, xi))        # |x|^2 in Q(sqrt2)
    dinv = q2_inv(den)
    rr, ri = q2_mul(xr, dinv), q2_mul((-x[2], -x[3]), dinv)
    return (rr[0], rr[1], ri[0], ri[1])

def f_iszero(x):
    return x[0] == 0 and x[1] == 0 and x[2] == 0 and x[3] == 0

F_ZERO = (Q(0), Q(0), Q(0), Q(0))
F_ONE = (Q(1), Q(0), Q(0), Q(0))
F_NEG_ONE = (Q(-1), Q(0), Q(0), Q(0))
F_I = (Q(0), Q(0), Q(1), Q(0))
INV_SQRT2 = (Q(0), Q(1, 2), Q(0), Q(0))                 # 1/sqrt2 = sqrt2/2
EXP_IPI4 = (Q(0), Q(1, 2), Q(0), Q(1, 2))               # e^{i pi/4} = (1+i)/sqrt2
EXP_INIPI4 = (Q(0), Q(1, 2), Q(0), Q(-1, 2))            # e^{-i pi/4}

# --- dense matrices over the field -----------------------------------------------------------------------

def zeros(rows, cols):
    return [[F_ZERO] * cols for _ in range(rows)]

def mat_mul(a, b):
    ra, ca, cb = len(a), len(a[0]), len(b[0])
    out = zeros(ra, cb)
    for i in range(ra):
        ai = a[i]
        oi = out[i]
        for t in range(ca):
            aik = ai[t]
            if f_iszero(aik):
                continue
            bt = b[t]
            for j in range(cb):
                oi[j] = f_add(oi[j], f_mul(aik, bt[j]))
    return out

def mat_add(a, b):
    return [[f_add(a[i][j], b[i][j]) for j in range(len(a[0]))] for i in range(len(a))]

def scalar_mul(s, a):
    return [[f_mul(s, a[i][j]) for j in range(len(a[0]))] for i in range(len(a))]

def conj_transpose(a):
    r, c = len(a), len(a[0])
    return [[f_conj(a[i][j]) for i in range(r)] for j in range(c)]

def mat_equal(a, b):
    return len(a) == len(b) and all(a[i][j] == b[i][j] for i in range(len(a)) for j in range(len(a[0])))

def rank_factorization(m):
    """Exact M = C.F with inner dim = rank(M), over the field. C = pivot columns of M, F = nonzero RREF rows."""
    rows = [list(r) for r in m]
    height = len(rows)
    width = len(rows[0]) if height else 0
    pivots = []
    pr = 0
    for col in range(width):
        sel = next((r for r in range(pr, height) if not f_iszero(rows[r][col])), None)
        if sel is None:
            continue
        rows[pr], rows[sel] = rows[sel], rows[pr]
        inv = f_inv(rows[pr][col])
        rows[pr] = [f_mul(v, inv) for v in rows[pr]]
        for r in range(height):
            if r != pr and not f_iszero(rows[r][col]):
                factor = rows[r][col]
                rows[r] = [f_sub(rows[r][j], f_mul(factor, rows[pr][j])) for j in range(width)]
        pivots.append(col)
        pr += 1
        if pr == height:
            break
    rank = len(pivots)
    c = [[m[i][p] for p in pivots] for i in range(height)]
    f = [rows[i] for i in range(rank)]
    return c, f, rank

# --- the matrix-product state ----------------------------------------------------------------------------

class MPS:
    """A chain of tensors A[k] = [M0, M1], each M_sigma a (Dl x Dr) field matrix. Bonds close to 1 at the ends."""

    def __init__(self, n):
        self.n = n
        self.tensors = [[[[F_ONE]], [[F_ZERO]]] for _ in range(n)]   # |0...0>: each site 1x1, sigma=0 -> 1

    def apply_1q(self, gate, k):
        m0, m1 = self.tensors[k]
        new0 = mat_add(scalar_mul(gate[0][0], m0), scalar_mul(gate[0][1], m1))
        new1 = mat_add(scalar_mul(gate[1][0], m0), scalar_mul(gate[1][1], m1))
        self.tensors[k] = [new0, new1]

    def apply_2q(self, gate, k):
        """Adjacent two-qubit gate on (k, k+1). gate is 4x4 indexed [t0*2+t1][s0*2+s1]; bond trimmed to rank."""
        a = self.tensors[k]
        b = self.tensors[k + 1]
        dl = len(a[0])
        dr = len(b[0][0])
        theta = [[mat_mul(a[s0], b[s1]) for s1 in range(2)] for s0 in range(2)]   # (Dl x Dr) per (s0,s1)
        out = [[zeros(dl, dr) for _ in range(2)] for _ in range(2)]
        for t0 in range(2):
            for t1 in range(2):
                acc = zeros(dl, dr)
                for s0 in range(2):
                    for s1 in range(2):
                        g = gate[t0 * 2 + t1][s0 * 2 + s1]
                        if not f_iszero(g):
                            acc = mat_add(acc, scalar_mul(g, theta[s0][s1]))
                out[t0][t1] = acc
        big = zeros(dl * 2, 2 * dr)
        for t0 in range(2):
            for t1 in range(2):
                block = out[t0][t1]
                for x in range(dl):
                    for y in range(dr):
                        big[x * 2 + t0][t1 * dr + y] = block[x][y]
        c, f, rank = rank_factorization(big)
        left = [zeros(dl, rank) for _ in range(2)]
        for t0 in range(2):
            for x in range(dl):
                for r in range(rank):
                    left[t0][x][r] = c[x * 2 + t0][r]
        right = [zeros(rank, dr) for _ in range(2)]
        for t1 in range(2):
            for r in range(rank):
                for y in range(dr):
                    right[t1][r][y] = f[r][t1 * dr + y]
        self.tensors[k] = left
        self.tensors[k + 1] = right

    def amplitude(self, bits):
        product = self.tensors[0][bits[0]]
        for k in range(1, self.n):
            product = mat_mul(product, self.tensors[k][bits[k]])
        return product[0][0]

    def norm2(self):
        left = [[F_ONE]]
        for k in range(self.n):
            a0, a1 = self.tensors[k]
            acc = None
            for a in (a0, a1):
                term = mat_mul(mat_mul(conj_transpose(a), left), a)
                acc = term if acc is None else mat_add(acc, term)
            left = acc
        return left[0][0]

    def bond_dims(self):
        return [len(self.tensors[k][0][0]) for k in range(self.n - 1)]

    def field_elements(self):
        total = 0
        for k in range(self.n):
            total += 2 * len(self.tensors[k][0]) * len(self.tensors[k][0][0])
        return total

    def to_dense(self):
        return [self.amplitude([(i >> q) & 1 for q in range(self.n)]) for i in range(1 << self.n)]

    def witness_root(self):
        digest = hashlib.blake2b(digest_size=16, key=b"mps-qubits")
        for k in range(self.n):
            for m in self.tensors[k]:
                for row in m:
                    for entry in row:
                        for part in entry:
                            digest.update(str(part).encode())
                            digest.update(b";")
        return digest.hexdigest()


# --- a plain dense engine over the same field, for cross-checking the compact one ------------------------

class Dense:
    def __init__(self, n):
        self.n = n
        self.v = [F_ZERO] * (1 << n)
        self.v[0] = F_ONE

    def apply_1q(self, gate, k):
        bit = 1 << k
        for i in range(len(self.v)):
            if not (i & bit):
                j = i | bit
                a0, a1 = self.v[i], self.v[j]
                self.v[i] = f_add(f_mul(gate[0][0], a0), f_mul(gate[0][1], a1))
                self.v[j] = f_add(f_mul(gate[1][0], a0), f_mul(gate[1][1], a1))

    def apply_2q(self, gate, k):
        b0, b1 = 1 << k, 1 << (k + 1)          # s0 = bit k, s1 = bit k+1; local index = s0*2 + s1
        seen = [False] * len(self.v)

        def gidx(base, s0, s1):
            return base | (b0 if s0 else 0) | (b1 if s1 else 0)

        for i in range(len(self.v)):
            if seen[i]:
                continue
            base = i & ~(b0 | b1)
            local = [self.v[gidx(base, s0, s1)] for s0 in range(2) for s1 in range(2)]
            for s0 in range(2):
                for s1 in range(2):
                    seen[gidx(base, s0, s1)] = True
            for t0 in range(2):
                for t1 in range(2):
                    acc = F_ZERO
                    for s0 in range(2):
                        for s1 in range(2):
                            acc = f_add(acc, f_mul(gate[t0 * 2 + t1][s0 * 2 + s1], local[s0 * 2 + s1]))
                    self.v[gidx(base, t0, t1)] = acc


# --- gates -----------------------------------------------------------------------------------------------

H = [[INV_SQRT2, INV_SQRT2], [INV_SQRT2, f_neg(INV_SQRT2)]]
X = [[F_ZERO, F_ONE], [F_ONE, F_ZERO]]
Z = [[F_ONE, F_ZERO], [F_ZERO, F_NEG_ONE]]
S = [[F_ONE, F_ZERO], [F_ZERO, F_I]]

def diag2q(d11):
    g = [[F_ZERO] * 4 for _ in range(4)]
    g[0][0] = g[1][1] = g[2][2] = F_ONE
    g[3][3] = d11
    return g

CZ = diag2q(F_NEG_ONE)
CT = diag2q(EXP_IPI4)
CT_DG = diag2q(EXP_INIPI4)
CNOT = [[F_ONE, F_ZERO, F_ZERO, F_ZERO],     # 00 -> 00
        [F_ZERO, F_ONE, F_ZERO, F_ZERO],     # 01 -> 01
        [F_ZERO, F_ZERO, F_ZERO, F_ONE],     # 11 -> 10  (control = left qubit k)
        [F_ZERO, F_ZERO, F_ONE, F_ZERO]]     # 10 -> 11


# --- rendering / demo ------------------------------------------------------------------------------------

def f_str(x):
    def q2(a, b):
        if b == 0:
            return "%s" % a
        if a == 0:
            return "%s*sqrt2" % b
        return "(%s + %s*sqrt2)" % (a, b)
    approx = (float(x[0]) + float(x[1]) * 2 ** 0.5, float(x[2]) + float(x[3]) * 2 ** 0.5)
    return "%s + %s i  (~ %.4f%+.4fi)" % (q2(x[0], x[1]), q2(x[2], x[3]), approx[0], approx[1])


def build_ghz(n):
    state = MPS(n)
    state.apply_1q(H, 0)
    for k in range(n - 1):
        state.apply_2q(CNOT, k)          # cascade of ADJACENT CNOTs spreads the GHZ down the chain
    return state


def build_scrambler(n, depth, dense=None):
    """|+..+> then an alternating brick of controlled-T: real, non-Clifford entanglement piles up, bond climbs."""
    target = dense if dense is not None else MPS(n)
    for q in range(n):
        target.apply_1q(H, q)
    for layer in range(depth):
        for k in range(layer % 2, n - 1, 2):
            target.apply_2q(CT, k)
        for q in range(n):
            target.apply_1q(H, q)          # rotate basis between bricks so entanglement genuinely accumulates
    return target if dense is None else None


def report(label, state):
    bonds = state.bond_dims()
    dense_amps = 1 << state.n
    print("  %s" % label)
    print("    qubits %d | bond dims %s | field elements %d  vs dense 2^%d = %s"
          % (state.n, bonds if state.n <= 12 else "[max %d]" % max(bonds), state.field_elements(),
             state.n, dense_amps if state.n <= 20 else "~10^%d" % round(state.n * 0.30103)))
    print("    <psi|psi> = %s" % ("EXACTLY 1" if state.norm2() == F_ONE else "NOT 1 -- bug"))
    zero = [0] * state.n
    one = [1] * state.n
    print("    <0..0|psi> = %s" % f_str(state.amplitude(zero)))
    print("    <1..1|psi> = %s" % f_str(state.amplitude(one)))
    print("    root %s" % state.witness_root()[:12])


def cross_check(name, build):
    n = 6
    mps = build(n)
    dense = Dense(n)
    build(n, dense)
    ok = all(mps.amplitude([(i >> q) & 1 for q in range(n)]) == dense.v[i] for i in range(1 << n))
    print("  cross-check %-22s compact vs dense on %d qubits, all %d amplitudes: %s"
          % (name, n, 1 << n, "AGREE" if ok else "DIFFER -- bug"))


def main():
    # Bell
    bell = MPS(2)
    bell.apply_1q(H, 0)
    bell.apply_2q(CNOT, 0)
    report("Bell (|00>+|11>)/sqrt2", bell)

    # GHZ small, with a compaction figure and bond dims visible
    report("GHZ-6 (|000000>+|111111>)/sqrt2", build_ghz(6))

    # Non-Clifford: GHZ-4 then controlled-T on the last pair -> exact e^{i pi/4} phase, still compact
    nc = build_ghz(4)
    nc.apply_2q(CT, 2)
    report("GHZ-4 + controlled-T (non-stabilizer, exact phase)", nc)

    # The punchline: 100 real entangled qubits, exact, in a few hundred numbers
    report("GHZ-100 (100-partite entanglement, exact)", build_ghz(100))

    # Honesty: a scrambling circuit where entanglement genuinely grows -- the bond climbs to the true
    # Schmidt rank per cut (not magically 2), and the exact rank factorization keeps it minimal.
    scr = build_scrambler(10, 6)
    print("  scrambler (10 qubits, depth 6): bond profile %s | field elements %d vs dense 2^10 = 1024 | <psi|psi> = %s"
          % (scr.bond_dims(), scr.field_elements(), "EXACTLY 1" if scr.norm2() == F_ONE else "NOT 1 -- bug"))

    # reversibility on the compact rep: build then invert, land on |0..0> exactly (checked densely, small n)
    r = MPS(5)
    seq = [(H, 0), (CNOT, 0), (CNOT, 1), (CT, 2), (CNOT, 3)]
    for gate, k in seq:
        (r.apply_1q if len(gate) == 2 else r.apply_2q)(gate, k)
    inverse = [(CNOT, 3), (CT_DG, 2), (CNOT, 1), (CNOT, 0), (H, 0)]
    for gate, k in inverse:
        (r.apply_1q if len(gate) == 2 else r.apply_2q)(gate, k)
    ground = MPS(5)
    back = all(r.amplitude([(i >> q) & 1 for q in range(5)]) == ground.amplitude([(i >> q) & 1 for q in range(5)])
               for i in range(1 << 5))
    print("  reversibility: 5-qubit circuit then exact inverse -> |00000> to the bit: %s" % ("yes" if back else "NO"))

    # cross-checks against the dense engine (same field), amplitude for amplitude
    def bell_build(n, dense=None):
        target = dense if dense is not None else MPS(n)
        target.apply_1q(H, 0)
        target.apply_2q(CNOT, 0)
        for k in range(1, n - 1):
            target.apply_2q(CNOT, k)
        return target if dense is None else None
    cross_check("GHZ chain", bell_build)

    def nc_build(n, dense=None):
        target = dense if dense is not None else MPS(n)
        target.apply_1q(H, 0)
        for k in range(n - 1):
            target.apply_2q(CNOT, k)
        target.apply_2q(CT, 2)
        return target if dense is None else None
    cross_check("GHZ + controlled-T", nc_build)
    cross_check("scrambler depth 6", lambda n, dense=None: build_scrambler(n, 6, dense))

    print("\n  every amplitude exact; 100 entangled qubits in %d numbers, not 2^100. no float touched the math."
          % build_ghz(100).field_elements())
    return 0


if __name__ == "__main__":
    sys.exit(main())
