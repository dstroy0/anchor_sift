# SHA-256's shift register, read as a deforming surface

A harmonic reading of the SHA-256 compression state renders a surface, and that surface deforms as
the round clock turns. This records what the deformation is, proves it belongs to the state
not to the observer or the probe, and traces it to the one structural feature of the
compression function that could produce it. The observer-invariance that makes the reading
trustworthy is stated first, because it is the calibration that lets the rest be read as measurement,
not as viewpoint.

Run the measurements with `python examples/proofing/state_deflection.py`.

## The object

SHA-256 compresses in sixty four rounds over a state of eight thirty-two bit words, which is 256
bits. The reading places those 256 bits on 256 points of a ring arrangement and expands the lit set
in spherical harmonics, so the state becomes a field on a sphere and the field has a shape. Bit `i`
lights point `i`; no mapping was invented to make the instrument fit the object, because 256 bits
and 256 points are the same count.

The compression agrees with the published digest of the empty string before any of this is read, so
the object under the instrument is SHA-256 and not an approximation of it.

## The calibration: which part of the shape is the observer's, and which is not

A shape read this way has two anisotropies, and they answer to a rotation of the observer
differently. This is standard representation theory of the rotation group, stated here because it is
the null the measurement rests on, not because it is new.

- **Deflection**, the power per degree `P_l = Σ_m |a_lm|²`, is invariant under every rotation in
  SO(3): the degree-`l` subspace carries a unitary irreducible representation of the group, and a
  magnitude built from it cannot record how the object was turned. Measured null under a whole-step
  rotation: **2.539 × 10⁻¹⁴**, which is the arithmetic and not the object.
- **Torsion**, the phase `arg a_lm` of the same coefficients, moves by exactly `−mα` under a
  rotation by `α`. It records the turn, sign included. Measured recovery of a known angle:
  **1.803 × 10⁻¹³ radians**.

So the magnitude of the anisotropy is observer-independent and its direction is observer-dependent,
and the split is exact. This is a property of the reading and holds for any lit set, SHA-256 or
otherwise. Its role here is precise: it says that a change in the shape's **magnitude** across the
clock is a change in the object, while a change in its **direction** could be either the object or
the frame. Every claim below is therefore made on a magnitude, where the observer has been divided
out, or is checked against a control that holds the frame fixed.

## The measurement, on the surface itself

The reading renders exactly one deformed surface in the scene, and it is the state's. Every
enclosing shell measures a vertex-radius standard deviation of exactly zero, so they are perfect
spheres; the state's surface measures a standard deviation of 0.999 against a mean radius of 8.795,
at 11.4 percent. Read as a radius field over the sphere and tracked across the sixty four
rounds:

| feature | degree | across the clock |
| --- | --- | --- |
| the elongation, a lemon | 2 | `q_zz ≈ −1.50` at every round, 17 percent of the mean radius |
| the offset, a cone | 1 | `d_z` swings about `0.07` and changes sign several times |

The quadrupole is a fixed feature: the surface is elongated by the same amount, in the same axis,
the whole way through. The dipole migrates and inverts, so the cone walks around the surface and
changes which pole it favours more than once.

## The claim, stated as a number

The dipole does not merely move. It moves **coherently**: its sign, taken round by round, comes in
runs, not in the alternation independent signs would give. Twenty runs against an expected
30.5, at a run-length test that assumes nothing about the values themselves:

    z = −2.87

Measured a second way, on a different object through different code (the rendered mesh in the
viewer, against the lit set in Python) the same statistic reads **z = −3.0**. Two pipelines with
no shared arithmetic land two hundredths apart.

A drift at that level is what a surface computed from a slowly changing state looks like, so the
next section is the control that pins the change to the state.

## Why it is the state and not the observer or the probe

Two interventions, because the round clock advances everything at once and an observation that the
picture changes when the clock moves does not by itself say what moved it.

**The probe was moved and nothing happened.** Holding the round fixed and swinging the neutrino beam
180 degrees in azimuth, 128 in elevation and 4.7 times in radius left the surface unchanged in every
digit: mean radius, dipole and quadrupole all identical before, during and after. One round of the
clock, with the beam untouched, then moved the dipole by five times. The surface answers to the
state and not to the probe.

**The rounds were replaced by independent states.** The real round sequence gives `z = −2.87`. A
control that swaps the rounds for independent states of the same per-round weights, everything else
identical, gives `z = 0.00` with a spread of 0.94, so the real sequence sits 3.1 control deviations
out. The drift is in the succession of states, not in the reading of any one of them.

## The mechanism, which is not exotic

SHA-256's round computes two words and shifts the other six:

    a' = T1 + T2      e' = d + T1
    b' = a            f' = e
    c' = b            g' = f
    d' = c            h' = g

Six of the eight words at round `r` are round `r−1`'s words in a new position, measured at 63 of 63
rounds. A surface computed from a state that is five-sixths carried over cannot jump between
consecutive rounds, so a coherent, autocorrelated drift is precisely the shift register showing.

**This is the whole claim, and it is worth stating without deflation.** The reading was built to
show a field. Nobody built it to expose the Merkle-Damgard shift register, and the register turned
up in it anyway: legible to the eye as a lemon whose cone walks and inverts, and holding at three
standard deviations when the drift is measured against a control. The result is not a new property
of SHA-256. It is a demonstration that a harmonic boundary reading makes a known structural property
of the compression function visible and measurable, with the observer divided out and the cause
established by intervention.

## Scope, stated plainly

- **The observer-invariance is classical.** Rotation-invariant power and orientation-carrying phase
  are standard SO(3) representation theory, the same fact behind an angular power spectrum being usable
  without its phases. It is the calibration here, not a finding.
- **What is specific to SHA-256** is the behaviour of the anisotropy across the clock: a persistent
  quadrupole, a dipole that inverts in runs at `z = −2.87`, and the trace to the shift register by
  intervention.
- **No claim is made** about a weakness in SHA-256, about its output, or about anything a
  cryptographic reduction would touch. The reading is taken on the intermediate compression state,
  which carries the shift structure by design; the digest, being the feed-forward of all sixty four
  rounds, is a different object and is not read here.

## Reproducing it

    python examples/proofing/state_deflection.py --check     the instrument, against the digest
    python examples/proofing/state_deflection.py --shape     dipole and quadrupole per round
    python examples/proofing/state_deflection.py --runs      the autocorrelation against a control

The figures, and the intervention table, are in `docs/figures/state-deformation/`.
