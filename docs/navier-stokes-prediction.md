# A prediction about the Navier-Stokes blowup, written before reading the proof

**Douglas Quigg (dstroy0), 2026-09-11.** Timestamped by OpenTimestamps over its own SHA-256 before
the OpenAI writeup was read. The point of the stamp is that this document's date is not self-asserted.

## What was known when this was written

Only the announcement page, `openai.com/index/navier-stokes-solution/`, read on 2026-09-11. From it:

- A solution establishing Fefferman's statement **(C)**, and also **(D)**: finite-time breakdown with
  a smooth forcing `f`, starting from rest, energy finite throughout.
- The mechanism described in prose: "a vortex, a spinning swirl of fluid, that spirals inward and
  gets increasingly elongated, like spaghetti. This central region shrinks while it speeds up in such
  a way that its energy still stays finite."
- The nonlinear terms "must both become" balanced in a precise way, leaving a smooth external force
  while the velocity grows without bound.

**Not read: the writeup, the Lean formalization, or any scaling exponent.** No figure was inspected
beyond the one caption on that page. The claim below is derived from the prose plus scaling arguments.

## The intuition being tested

Stated by Douglas before the exponents below were worked out: the mechanism is **simple wave
harmonics**, and it is the same shape as a quantum information slowdown metric - **the tighter the
knot, the slower the information propagation**.

Made quantitative: as the vortex core tightens, the time for a disturbance to travel ALONG the tube
grows relative to the time remaining before blowup. The collapse therefore becomes axially
incoherent - different heights along the tube stop being able to communicate before it blows up.

## The ansatz

Near blowup time `T`, with two length scales because the object is described as elongating:

    velocity        u   ~ (T-t)^(-alpha)
    core radius     r   ~ (T-t)^(beta_r)         transverse
    axial extent    z   ~ (T-t)^(beta_z)         longitudinal

## What is FORCED, and therefore proves little if it matches

These follow from Navier-Stokes structure and anyone deriving them gets the same answer. A match
here is not evidence for the intuition.

**F1. alpha = beta_r.** The viscous term `nu*u/r^2` and the nonlinear term `u^2/r` must scale
together, or viscosity either dominates (no blowup) or vanishes (this is Euler, not Navier-Stokes).
Equate the exponents: `alpha + 2*beta_r = 2*alpha + beta_r`.

**F2. beta_r = 1/2.** Navier-Stokes is invariant under `u -> lambda*u(lambda*x, lambda^2*t)`, which
fixes the transverse exponent at one half for a collapse respecting the equation's own scaling.

**F3. Circulation is asymptotically constant.** `Gamma ~ u*r ~ (T-t)^(beta_r - alpha) = (T-t)^0`.
This is Kelvin's theorem surviving the collapse, and it follows from F1.

**F4. Peak vorticity goes as `(T-t)^-1`.** `omega ~ u/r ~ (T-t)^(-alpha-beta_r) = (T-t)^-1`, which
sits exactly on the Beale-Kato-Majda borderline, `integral |omega|_inf dt` divergent logarithmically.

## What DISCRIMINATES, and is the actual test

**D1. `beta_z < beta_r`, strictly. The aspect ratio diverges as `(T-t)^(beta_z - 1/2)`.** Forced by
"increasingly elongated" but worth stating, because a self-similar collapse with a single length
scale would give `beta_z = beta_r` and no elongation at all.

**D2. THE ONE THAT CARRIES THE INTUITION: `beta_z` is at or near zero.**

Axial signals travel as Kelvin waves at speed of order `Gamma/r`. The traverse time is

    t_axial ~ z / (Gamma/r) = z*r/Gamma ~ (T-t)^(beta_z + beta_r)

Axial decoupling - the "slower information propagation" - requires this to exceed the time remaining:

    beta_z + beta_r < 1      and with F2,      beta_z < 1/2

The strong form of the intuition is that the tube does not shorten at all while the core collapses,
giving `beta_z = 0` and an elongation exponent of `1/2`. **Committed value: `beta_z = 0`, with
anything in `[0, 1/4]` counted as a hit and anything at or above `1/2` counted as a miss.**

**D3. Energy vanishes or stays constant at the singularity, and does not merely stay bounded.**
`E ~ u^2 * r^2 * z ~ (T-t)^(-2*alpha + 2*beta_r + beta_z) = (T-t)^(beta_z)`. With `beta_z = 0`
energy is asymptotically CONSTANT; with `beta_z > 0` it goes to zero. Either is consistent with the
announcement's "energy still stays finite", but they are different statements and the proof will pick
one.

**D4. The forcing does not concentrate.** `f` stays `O(1)` with support that does not shrink onto the
blowup point. If the proof needs `f` to sharpen as `t -> T`, the mechanism is being driven from
outside rather than by the fluid's own motion, and the intuition above is wrong about what is
happening.

## How to score this

Read the writeup, extract the exponents, and mark each line hit or miss. **F1 to F4 do not count.**
They are what the equation forces and a competent derivation reaches them without any of the
intuition above.

The intuition is confirmed only if **D2** lands - `beta_z` at or near zero, with axial decoupling as
the stated reason the collapse is possible. If `beta_z` comes out at or near `1/2`, so that the tube
shortens at the same rate the core tightens, then "tighter knot, slower propagation" was a picture
that resembled the answer and did not predict it, and this document is the record of that.

D3 and D4 are secondary and can each fail without sinking D2.

## What this is not

Not a proof, not a claim of priority over anyone's result, and not a claim that this work solved
Navier-Stokes. It is a dated statement of what a specific physical intuition predicts, written
before the source was available to check it against, so that a match afterwards means something and
a miss is on the record in the same place.
