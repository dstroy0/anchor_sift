# Exact Simulation

Carry the amplitude itself and round nothing.

A quantum state is a vector of complex amplitudes. A floating-point simulator stores each one as a
pair of floating-point numbers. There `1/sqrt2` becomes `0.70710678...`, the norm drifts off one,
and a circuit run forward then inverted lands *near* the start instead of *on* it. The simulators
here keep every amplitude as an exact element of a number field. Nothing is rounded: the norm is
exactly one, two equal states are equal to the bit, and an inverse circuit returns to the start
state exactly.

Every table and value below is printed output of the simulators.

## The field

The standard gate set `{X, Y, Z, S, H, CNOT, CZ, controlled-T}` needs only a short list of numbers:
`0, 1, -1, i, -i, 1/sqrt2, (1+i)/sqrt2`. All of them live in

    Q(sqrt2)[i] = { (a + b*sqrt2) + i*(c + d*sqrt2) : a, b, c, d in Q }

and an element is four exact rationals. The field is closed under `+ - * /`, and every amplitude a
circuit over that gate set can reach stays inside it. `H`'s `1/sqrt2 = (1/2)*sqrt2` and the
controlled phase's `(1+i)/sqrt2` are held exactly and never decay. The ring `Z[1/sqrt2, i]` inside
this field is where exact Clifford+T synthesis is carried out [2]. The reference
implementation carries the quadruple as four exact rationals and uses no numeric library.

## Compact form (matrix product state)

The state is held as one small tensor per qubit, joined by bonds, as in a matrix product state [3].
The bond across a cut is the exact Schmidt rank there. After every two-qubit gate the bond is
trimmed by a rank-revealing factorization `M = C*F` computed by exact Gaussian elimination over the
field. No singular value is ever formed. Cost scales with the entanglement actually present, not
with the qubit count.

| state | qubits | bond dims | field elements | vs dense |
|---|---|---|---|---|
| Bell `(|00>+|11>)/sqrt2` | 2 | `[2]` | 8 | `2^2 = 4` |
| GHZ-6 | 6 | `[2,2,2,2,2]` | 40 | `2^6 = 64` |
| GHZ-4 + controlled-T | 4 | `[2,2,2]` | 24 | `2^4 = 16` |
| GHZ-100 | 100 | `[max 2]` | **792** | `2^100 ~ 10^30` |
| scrambler (10q, depth 6) | 10 | `[2,3,6,8,8,8,6,3,2]` | 552 | `2^10 = 1024` |

- `<psi|psi> = EXACTLY 1` for every one of them.
- Reversibility: a 5-qubit circuit then its exact inverse returns to `|00000>` to the bit.
- Cross-checks against the dense simulator on 6 qubits, all 64 amplitudes: **AGREE** (GHZ chain,
  GHZ + controlled-T, scrambler depth 6).

A hundred entangled qubits is real 100-partite entanglement in 792 numbers, not `2^100` amplitudes.
The scrambler's rising-then-falling bond profile is the entanglement light-cone measured exactly.

## Symbolic form (a parameter carried, not pinned)

The field is extended to `Q(sqrt2)[i](w)`, where `w = e^{i*phi(Delta)}` is a distance-dependent phase
carried as a *formal* unit on the circle: `conj(w) = 1/w`, and `w * conj(w) = 1` exactly. Amplitudes
become exact rational functions of `w`, reduced by polynomial GCD. The same rank-revealing
factorization runs unchanged. A bond trims only under linear dependence that holds for *every*
`Delta`.

An observable is read by contracting from the boundary: instead of expanding the state to `2^n`
numbers, the operator is inserted locally and the physical legs are contracted from the edges
inward, returning `<psi|O|psi>` as one exact field element.

On `(|00> + w|11>)/sqrt2`:

    <X0 X1> = (w + 1/w)/2 = cos(k/Delta^3)
    <Z0 Z1> = 1
    <X0>    = 0
    <psi|psi> = 1        (EXACTLY 1 -- the unitary phase cancels)

and on `(|000> + w|111>)/sqrt2`: `<X0 X1 X2> = cos(k/Delta^3)`, bond dims `[2,2]`. A product state
`|+++>` with a single-qubit phase stays rank one: bond dims `[1,1]`.

The contraction reads the separation back as an exact function of it; the `Delta` never becomes a
number.

## Cross-check between representations

Specializing `w = e^{i*pi/4}` makes `CPHASE(e^{i*pi/4})` the controlled-T gate. The symbolic
simulator and the numeric one must agree at that point:

    symbolic <X0X1> at w = e^{i pi/4} : (1/2)*sqrt2
    numeric  <X0X1> (controlled-T)    : (1/2)*sqrt2
    cos(pi/4) = 1/sqrt2               : AGREE
    norm at w = e^{i pi/4}            : 1  (EXACTLY 1)

Two independent representations landing on the same exact element is the agreement a verified
computation is built on.

## Scope

Exact arithmetic, an exact state, and an exact reading are general-purpose: they serve chemistry,
physics, and the verification of any circuit, and they reveal nothing about what a given circuit
computes. The claim is exactness as a substrate, and the three forms a state takes on it: dense,
compact, symbolic.

## Availability

The values above are printed by a reference implementation in Python over exact rationals. A C
implementation of the dense, compact and symbolic forms, with its tests, is in the orior repository
[1].

## References

1. D. Quigg. orior. https://github.com/dstroy0/orior. 2026.
2. V. Kliuchnikov, D. Maslov, M. Mosca. *Fast and efficient exact synthesis of single-qubit
   unitaries generated by Clifford and T gates*. Quantum Information and Computation 13(7-8),
   607-630. 2013.
3. G. Vidal. *Efficient classical simulation of slightly entangled quantum computations*. Physical
   Review Letters 91, 147902. 2003.
