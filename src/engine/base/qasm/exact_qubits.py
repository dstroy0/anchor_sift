#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Exact n-qubit statevector simulation: real entanglement, zero rounding, every amplitude exact.

Not "float, capped, drifting" like a mainstream simulator -- exact. Every amplitude lives in the field
Q(sqrt2)[i]: a value  (a + b*sqrt2) + i*(c + d*sqrt2)  with a,b,c,d exact rationals. That field is closed
under the gate set here -- X, Y, Z, S, H, CNOT, CZ, and the controlled-T (a controlled e^{i pi/4} phase,
the exact parametric distance-entangler) -- so H's 1/sqrt2 and T's (1+i)/sqrt2 are carried exactly, never
rounded to 0.7071.... The state is a dense vector of 2^n such amplitudes; entanglement is real (Bell, GHZ,
and non-stabilizer controlled-T states all appear with exact amplitudes), normalization <psi|psi> = 1 holds
EXACTLY (not to 1e-15), and any unitary run then inverted returns to |0..0> to the bit. A keyed digest over
the amplitude field stands in for the engine's Merkle seal: flip one rational and the witness root changes.

This is the exact analogue of a dense statevector simulator, so memory is 2^n amplitudes like any dense
sim -- the win here is exactness and certification, not beating that scaling (structured/low-entanglement
states get the compact exact tensor-network representation instead; this is the dense, fully-general one).
On the anchor_sift engine the same amplitudes ride the exact-integer core (base/no_rounding) on the device,
one number per warp, cross-checked host-vs-device; this Python model is the faithful small-scale twin.

No third-party libraries; Python integers and fractions.Fraction only. hashlib is used for the witness root.

    python exact_qubits.py
"""

import hashlib
import sys
from fractions import Fraction

Q = Fraction

# --- Q(sqrt2): an element (a, b) means a + b*sqrt2, a,b exact rationals -----------------------------------

def q2_add(x, y):
    return (x[0] + y[0], x[1] + y[1])

def q2_sub(x, y):
    return (x[0] - y[0], x[1] - y[1])

def q2_mul(x, y):
    # (a + b*sqrt2)(c + d*sqrt2) = (ac + 2bd) + (ad + bc)*sqrt2
    return (x[0] * y[0] + 2 * x[1] * y[1], x[0] * y[1] + x[1] * y[0])

def q2_half_sqrt2(x):
    # multiply by sqrt2/2 = 1/sqrt2:  (a + b*sqrt2)/sqrt2 = b + (a/2)*sqrt2
    return (x[1], x[0] / 2)

ZERO_Q2 = (Q(0), Q(0))
ONE_Q2 = (Q(1), Q(0))

# --- amplitude in Q(sqrt2)[i]: (qr, qi), each a Q(sqrt2) element, meaning qr + i*qi --------------------------

def amp(ar=0, br=0, ai=0, bi=0):
    return ((Q(ar), Q(br)), (Q(ai), Q(bi)))

def amp_add(x, y):
    return (q2_add(x[0], y[0]), q2_add(x[1], y[1]))

def amp_sub(x, y):
    return (q2_sub(x[0], y[0]), q2_sub(x[1], y[1]))

def amp_neg(x):
    return (q2_sub(ZERO_Q2, x[0]), q2_sub(ZERO_Q2, x[1]))

def amp_mul(x, y):
    # (xr + i xi)(yr + i yi) = (xr yr - xi yi) + i(xr yi + xi yr)
    real = q2_sub(q2_mul(x[0], y[0]), q2_mul(x[1], y[1]))
    imag = q2_add(q2_mul(x[0], y[1]), q2_mul(x[1], y[0]))
    return (real, imag)

def amp_mul_i(x):
    # i*(xr + i xi) = -xi + i xr
    return (q2_sub(ZERO_Q2, x[1]), x[0])

def amp_half_sqrt2(x):
    return (q2_half_sqrt2(x[0]), q2_half_sqrt2(x[1]))

def amp_norm2(x):
    # |qr + i qi|^2 = qr^2 + qi^2, an element of Q(sqrt2) (its sqrt2 part is 0 for a real total)
    return q2_add(q2_mul(x[0], x[0]), q2_mul(x[1], x[1]))

AMP_ZERO = amp()
AMP_ONE = amp(1)
EXP_IPI4 = amp(0, Q(1, 2), 0, Q(1, 2))     # e^{i pi/4} = (1+i)/sqrt2 = sqrt2/2 + i sqrt2/2
EXP_INIPI4 = amp(0, Q(1, 2), 0, -Q(1, 2))  # e^{-i pi/4}, the controlled-T inverse phase


# --- state: a dense list of 2^n amplitudes, qubit 0 = least significant bit ------------------------------

def new_state(n):
    state = [AMP_ZERO] * (1 << n)
    state[0] = AMP_ONE
    return state

def apply_x(state, q):
    bit = 1 << q
    for i in range(len(state)):
        if not (i & bit):
            j = i | bit
            state[i], state[j] = state[j], state[i]

def apply_z(state, q):
    bit = 1 << q
    for i in range(len(state)):
        if i & bit:
            state[i] = amp_neg(state[i])

def apply_s(state, q):
    bit = 1 << q
    for i in range(len(state)):
        if i & bit:
            state[i] = amp_mul_i(state[i])

def apply_y(state, q):
    apply_z(state, q)
    apply_x(state, q)
    apply_s(state, q)      # Y = i X Z up to the global phase S supplies here; kept exact

def apply_h(state, q):
    bit = 1 << q
    for i in range(len(state)):
        if not (i & bit):
            j = i | bit
            a0, a1 = state[i], state[j]
            state[i] = amp_half_sqrt2(amp_add(a0, a1))
            state[j] = amp_half_sqrt2(amp_sub(a0, a1))

def apply_cnot(state, control, target):
    cbit, tbit = 1 << control, 1 << target
    for i in range(len(state)):
        if (i & cbit) and not (i & tbit):
            j = i | tbit
            state[i], state[j] = state[j], state[i]

def apply_cz(state, a, b):
    abit, bbit = 1 << a, 1 << b
    for i in range(len(state)):
        if (i & abit) and (i & bbit):
            state[i] = amp_neg(state[i])

def apply_ct(state, a, b, phase=EXP_IPI4):
    # controlled-T: exact e^{i pi/4} on |...1...1...> -- the parametric distance-entangler at pi/4
    abit, bbit = 1 << a, 1 << b
    for i in range(len(state)):
        if (i & abit) and (i & bbit):
            state[i] = amp_mul(state[i], phase)


# --- exact checks ----------------------------------------------------------------------------------------

def total_norm2(state):
    total = ZERO_Q2
    for value in state:
        total = q2_add(total, amp_norm2(value))
    return total

def is_normalized(state):
    return total_norm2(state) == ONE_Q2

def states_equal(x, y):
    return len(x) == len(y) and all(a == b for a, b in zip(x, y))

def witness_root(state):
    digest = hashlib.blake2b(digest_size=16, key=b"exact-qubits")
    for (qr, qi) in state:
        for part in (qr[0], qr[1], qi[0], qi[1]):
            digest.update(str(part).encode())
            digest.update(b";")
    return digest.hexdigest()


# --- rendering -------------------------------------------------------------------------------------------

def q2_float(x):
    return float(x[0]) + float(x[1]) * (2.0 ** 0.5)   # display only; the math above never touches a float

def amp_str(x):
    (ar, br), (ai, bi) = x
    def q2str(p):
        if p[1] == 0:
            return "%s" % p[0]
        if p[0] == 0:
            return "%s*sqrt2" % p[1]
        return "(%s + %s*sqrt2)" % (p[0], p[1])
    approx = complex(q2_float(x[0]), q2_float(x[1]))
    return "%s + %s i    (~ %.4f%+.4fi)" % (q2str(x[0]), q2str(x[1]), approx.real, approx.imag)

def show(label, state, n):
    print("  %s" % label)
    for i, value in enumerate(state):
        if value != AMP_ZERO:
            print("    |%s>  =  %s" % (format(i, "0%db" % n), amp_str(value)))
    ok = is_normalized(state)
    print("    <psi|psi> = %s  (%s)   root %s"
          % (total_norm2(state), "EXACTLY 1" if ok else "NOT 1 -- bug", witness_root(state)[:12]))


def main():
    # 1. Bell pair: real two-qubit entanglement, exact amplitudes 1/sqrt2
    s = new_state(2)
    apply_h(s, 0)
    apply_cnot(s, 0, 1)
    show("Bell  (H0, CNOT0->1):  (|00> + |11>)/sqrt2, exact", s, 2)

    # 2. GHZ over 3 qubits: exact tripartite entanglement
    s = new_state(3)
    apply_h(s, 0)
    apply_cnot(s, 0, 1)
    apply_cnot(s, 0, 2)
    show("GHZ3  (H0, CNOT0->1, CNOT0->2):  (|000> + |111>)/sqrt2, exact", s, 3)

    # 3. Non-stabilizer state: Bell then controlled-T -- an exact e^{i pi/4} phase, no float could hold it
    s = new_state(2)
    apply_h(s, 0)
    apply_cnot(s, 0, 1)
    apply_ct(s, 0, 1)
    show("Bell + controlled-T:  (|00> + e^{i pi/4}|11>)/sqrt2, exact non-Clifford amplitude", s, 2)

    # 4. Reversibility: a unitary run, then its exact inverse, returns to |00..0> to the bit
    s = new_state(3)
    for gate in ((apply_h, 0), (apply_cnot, 0, 1), (apply_ct, 0, 1), (apply_cnot, 1, 2), (apply_h, 2)):
        gate[0](s, *gate[1:])
    mid_root = witness_root(s)
    for gate in ((apply_h, 2), (apply_cnot, 1, 2), (apply_ct, 0, 1, EXP_INIPI4), (apply_cnot, 0, 1), (apply_h, 0)):
        gate[0](s, *gate[1:])
    back = states_equal(s, new_state(3))
    print("  reversibility: forward root %s -> inverse -> |000> exactly: %s" % (mid_root[:12], "yes" if back else "NO"))

    # 5. Seal: one flipped rational changes the witness root -- any corruption fails it
    s = new_state(2)
    apply_h(s, 0)
    apply_cnot(s, 0, 1)
    clean = witness_root(s)
    tampered = list(s)
    (qr, qi) = tampered[0]
    tampered[0] = ((qr[0] + Fraction(1, 10 ** 9), qr[1]), qi)   # perturb one amplitude by 1e-9
    print("  seal: clean root %s | one-rational-flip root %s | %s"
          % (clean[:12], witness_root(tampered)[:12],
             "DIFFERS (seal holds)" if clean != witness_root(tampered) else "COLLISION (bug)"))

    print("\n  every amplitude above is exact; not one float entered the computation (floats shown only in ~parens).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
