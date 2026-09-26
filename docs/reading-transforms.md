# Reading Transforms

**Purpose:** Write out every transform a boundary reading passes through, from the interior state to
the pixel, with its action on the coefficients, whether it is diagonal in degree, what it leaves
invariant, and what it costs. Keep the pieces in one table, and a transform already priced is not
priced again while a transform never tried stays visible.
**Scope:** `tools/view/sphere_field.py`, `tools/view/boundary_read.py`, `tools/view/reading_rank.py`,
`tools/view/grid_error.py`, `examples/proofing/natural_constants.py`, `tools/view/room_view_template.html`
**Owner:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-10

## 1. The Object Every Transform Acts On

A reading is a real function on a closed boundary. Expanded in real spherical harmonics to
degree `L`:

```
f(n) = sum over l from 0 to L, sum over m from -l to +l of  a_lm  Y_lm(n)
```

The reading is the vector `a`, of length `(L+1)^2`. At the ceiling the clock runs to, `L = 10`, that
is 121 real numbers. Everything below is an operator on that vector, and the table is the catalogue
of them.

Two facts about the vector before any operator touches it.

**Its length is the bound on what a reading can say.** A reading to degree `L` carries `(L+1)^2` real
numbers about its source, whatever the source is. 256 sources read at degree 8 arrive as 81 numbers,
so 175 directions of the source space are absent from the reading. The eight-letter octant alphabet
is rank 8, absent in 248, with 7 free numbers left once the weight is fixed. Measured in
`reading_rank.py`.

**Degree 15 dips and then recovers.** At full depth the least live singular value is 3.47e-3
at degree 15 against 1.75 at degree 14. The exactly-complete degree is about 500 times worse
conditioned than the incomplete degree beneath it, recovery arrives by 17, and saturation follows.
Completeness of count and health of conditioning are separate properties.

## 2. The Transform Table

`diag` asks whether the operator is diagonal in degree: whether it acts on each degree `l` by one
number, without moving power between degrees. Cost is per reading unless stated.

| # | transform | what moves | action on `a_lm` | diag | invariant | cost | in the tree |
|---|---|---|---|---|---|---|---|
| T1 | rotation, general | orientation in SO(3) | `a_lm -> sum_m' D^l_{m'm}(R) a_lm'` | block | `P_l` | `O(L^3)` | `boundary_read.turn_between` |
| T2 | rotation about the read axis | angle `alpha` about `z` | phase moves by `-m alpha` | yes | `P_l`, and each `abs(a_lm)` | `O(L^2)` | `boundary_read.deflection`, `torsion` |
| T3 | depth, outward carry | source radius `r` in a shell `R` | `a_lm -> (r/R)^l a_lm` | yes | direction of each degree | `O(L^2)` | `sphere_field.kernel` |
| T4 | conduction, smoothing | time `tau` on the boundary | `a_lm -> exp(-l(l+1) tau) a_lm` | yes | direction of each degree | `O(L^2)` | `sphere_field.kernel` |
| T5 | pixel prefilter | screen footprint `sigma` | `a_lm -> exp(-l(l+1) sigma^2/2) a_lm` | yes | direction of each degree | `O(L^2)` | not built |
| T6 | band truncation | ceiling `L` | keep `l <= L`, zero above | yes | every kept coefficient | free | `state.degrees` |
| T7 | parity, reflection | through the origin | `a_lm -> (-1)^l a_lm` | yes | `P_l` | `O(L^2)` | implicit |
| T8 | screw, index shift | index `n` in a golden placement | rotation `n gamma`, slide `-2n/N` | yes | `P_l` | `O(L^2)` | `boundary_read.screw_of` |
| T9 | synthesis | none; leaves coefficient space | `f(n) = sum a_lm Y_lm(n)` | no | none | `O(L^2)` per point | `sphere_field.synthesize` |
| T10 | gradient | none; leaves coefficient space | `d/dtheta`, `d/dphi` by recurrence | `l +- 1` | none | `O(L^2)` per point | not built |
| T11 | translation | the origin itself | mixes every degree | **no** | nothing per degree | `O(L^3)` | avoided |
| T12 | octant indicator | choice of region | project onto 8 indicators | **no** | total weight | rank 8 | `reading_rank.octant_matrix` |
| T13 | linear interpolation | a mesh cell | not an operator on `a` at all | not applicable | vertex values | `O(1)` per pixel | the current viewer |

Three rows carry the weight of the table.

**T5 is not built and is one addition away.** Its action is T4's action with a different time. Section
5 spends that.

**T11 is the exception that proves the rule.** Translation is the only physical move in the table that
mixes degrees, and section 4 says why. It is avoided in the tree by giving each source its own depth
factor in T3 instead of moving an origin.

**T13 is in the table to be seen for what it is.** It is not a transform of the reading. It is a
straight line drawn between two samples of the reading, and section 6 measures how far that line
sits from the curve it replaces.

## 3. The Composition Law

Rows T3 to T8 are all diagonal. Diagonal operators on the same eigenspaces commute, and composing
them multiplies one number per degree. So the entire chain from an interior state to a screen pixel
collapses to a single vector of `L+1` gains:

```
a_lm(screen) = g_l a_lm(state)

g_l = (r/R)^l  exp(-l(l+1) tau_total)  [l <= L]  (-1)^(l if reflected)

tau_total = tau_conduction + tau_pixel
```

The two smoothing times add. The heat kernel on the sphere is a semigroup, so
`exp(-l(l+1) tau_1) exp(-l(l+1) tau_2) = exp(-l(l+1)(tau_1 + tau_2))`, and smoothing for `tau_1` then
`tau_2` is smoothing once for the sum. Nothing about that is an approximation.

Two consequences, and they are the reason the table is worth keeping.

**The whole physical and imaging chain is 11 multiplications.** At `L = 10`, `g` is eleven numbers,
recomputed when the depth, the smoothing or the ceiling changes and never per pixel. The viewer
already forms this vector: `sphere_field.kernel` returns exactly `g` for T3 and T4 together.

**A correct pixel filter is free.** It is one addend inside a `tau` that is already being applied.
There is no second pass, no extra sampling, and no new operator: the filter enters the product the
chain was already forming.

## 4. Why They Are Diagonal, And Why One Is Not

The table is not a coincidence and does not have to be memorised. The Laplace-Beltrami operator on
the sphere has the degree `l` subspace as its eigenspace with eigenvalue `-l(l+1)`:

```
Delta Y_lm = -l(l+1) Y_lm
```

Any operator that commutes with `Delta` preserves its eigenspaces, and therefore acts on each degree
separately. Every diagonal row of the table commutes with `Delta`:

* **T3, depth.** The field between the source and the boundary satisfies `Delta f = 0` in the shell.
  Harmonic continuation outward is the solution of Laplace's equation there, and separating variables
  gives `(r/R)^l` as the radial factor. The exponent is the degree because the degree is the
  eigenvalue's index.
* **T4 and T5, smoothing.** Both are `exp(tau Delta)`, the heat semigroup. An operator built as a
  function of `Delta` commutes with it by construction.
* **T1, T2, T7, T8, rotations and parity.** These are isometries of the sphere, and `Delta` is built
  from the metric, so they commute with it. Each degree `l` subspace is an irreducible unitary
  representation of SO(3) of dimension `2l+1`, and rotation therefore mixes orders inside a degree
  while moving no power between degrees.
* **T6, truncation.** A spectral projection onto a set of eigenspaces.

**T11 does not commute with `Delta`, and cannot.** A translation is not a map of the sphere to itself,
so there is no `Delta` on the sphere for it to commute with. Re-expanding a field about a shifted
origin mixes every degree into every other, at `O(L^3)` and with no per-degree number to carry it.
Every cheap operation in this tree is diagonal, and the operation the tree avoids fails to be.

## 5. Reading A Picture Off The Coefficients

### 5.1 What a pixel asks for

A pixel does not ask for the field at a point. It asks for the field averaged over the solid angle
it covers. Every antialiasing scheme is an attempt to answer that average.

**Supersampling estimates the average.** Take `k` samples inside the pixel and average them: cost
scales with `k`, and the error falls about as `1/k`. It converges toward the answer and arrives at it
only in the limit.

**A band-limited field has the average in closed form.** Convolution on the sphere is multiplication
in degree. Averaging the field against a kernel `K` is therefore `a_lm -> K_l a_lm`, with no sampling
anywhere. Choosing `K` to be the heat kernel of width `sigma` gives T5, and one evaluation of the
prefiltered field is the pixel's area average exactly.

So the comparison is not between one scheme and a cheaper scheme. Supersampling approximates a
quantity this field hands over in one multiplication.

### 5.2 The footprint and the time

The width to filter at is the pixel's own angular size on the boundary, available per fragment from
the screen-space derivatives of the direction vector:

```
sigma  = length of the change in direction across one pixel   (radians)
tau_pixel = sigma^2 / 2
```

Two properties follow that a mip chain has to be built to imitate. The width varies per pixel, so
the filter is continuous in distance and in surface angle with no levels and no transitions between
them. And the width enters `tau_total`, so it is applied by the same eleven multiplications section 3
already pays for.

### 5.3 Where the degrees stop mattering

The prefilter also says which degrees can be skipped. `exp(-l(l+1) tau)` falls below a threshold
`epsilon` once

```
l(l+1) > ln(1/epsilon) / tau,   so   l_max  is about  sqrt(2 ln(1/epsilon)) / sigma
```

At `epsilon = 1/256`, one level of an eight-bit channel, `l_max` is about `3.33 / sigma`.

**Stated honestly, this saving is small.** `l_max` reaches down to 10 only when `sigma` is about
0.33 radians, which happens when the object spans a few tens of pixels. Above that size every one of
the 121 terms contributes something visible and none may be dropped. The level-of-detail behavior is
real, it is derived instead of authored, and it earns nothing at the sizes the viewer is normally
used at. The accuracy in 5.4 is the return; this is a footnote to it.

### 5.4 The grid against the coefficients, measured

`grid_error.py` compares the drawn picture against the field the coefficients hold. The viewer
samples 121 coefficients at 2,701 vertices of a 36 by 72 grid, 5.0 degrees to a cell, and the
rasterizer fills each cell with two planes.

Error per degree, for unit power in that degree alone, as a fraction of the picture's own contrast:

| degree | largest | typical | gradient median | gradient 95th |
|---|---|---|---|---|
| 1 | 0.0010 | 0.0004 | 1.25 deg | 5.85 deg |
| 4 | 0.0107 | 0.0026 | 3.22 deg | 19.15 deg |
| 7 | 0.0277 | 0.0058 | 5.34 deg | 31.94 deg |
| 10 | 0.0592 | 0.0108 | 7.47 deg | 47.15 deg |

The value error climbs as the square of the degree, as a linear interpolant must: interpolating a
wave of length `lambda` over a step `h` is wrong by about `(pi h / lambda)^2 / 2`, and a degree `l`
harmonic has length `360/l` degrees.

Error for named fields:

| field | largest | typical | gradient median |
|---|---|---|---|
| flat spectrum to degree 10 | 0.0312 | 0.0050 | 5.85 deg |
| 63 deposits at `r/R` = 0.80 | 0.0273 | 0.0061 | 6.67 deg |
| 63 deposits at `r/R` = 0.60 | 0.0174 | 0.0034 | 6.05 deg |
| 63 deposits at `r/R` = 0.40 | 0.0075 | 0.0015 | 2.14 deg |

The depth kernel is doing the work in that last column. A deeper reading carries less high-degree
power by T3, and the same grid draws it more accurately. The grid is wrong in proportion to the fine
structure the state happens to hold.

**Read the gradient column.** The surface is shaded, and shading takes its normal from
the gradient. A linear interpolant has a constant gradient inside a triangle, so the drawn normal is
a staircase across a field whose gradient turns smoothly. At degree 10 the median normal is 7.5
degrees off and one sample in twenty is more than 47 degrees off. That is the 5-degree quilt visible
on the reconstruction, and it is a far larger error than the 1 percent in the value column.

A per-fragment evaluation has no interpolation error in either column, because there is no
interpolation. T10 supplies the exact gradient in closed form for the same reason T9 supplies the
exact value: the derivative of the expansion is another expansion.

### 5.5 What the grid would cost to fix as a grid

| grid | vertices | largest | typical | gradient median |
|---|---|---|---|---|
| 36 by 72 | 2,701 | 0.0300 | 0.0051 | 5.83 deg |
| 72 by 144 | 10,585 | 0.0077 | 0.0013 | 2.89 deg |
| 144 by 288 | 41,905 | 0.0019 | 0.0003 | 1.46 deg |
| 288 by 576 | 166,753 | 0.0005 | 0.0001 | 0.73 deg |

Four times the vertices for a quarter of the error, the second-order convergence of a linear
interpolant, confirmed at 3.95 against a predicted 4.

### 5.6 The two working sets

| | grid pass | per fragment |
|---|---|---|
| samples produced | 2,701 | as many as there are pixels |
| basis | read from a table | built by recurrence |
| bytes touched per pass | 1.25 MB | 484 |
| samples at 900 px across | not applicable | 636,172, or 236 times the grid's |

The grid pass is bound by a 1.25 MB table that does not fit in cache. A fragment evaluation reads the
121 coefficients and computes the basis from the direction, so its working set is 484 bytes at any
sample count. **No frame time is claimed here.** These are sizes and counts; throughput belongs to a
measurement in the page, and section 8 lists it as unmeasured.

### 5.7 Where this fails

**Anisotropy.** The heat kernel is isotropic and a pixel's footprint near the silhouette is
stretched. A single `sigma` over-blurs across the short axis. The exact fix wants a directional
kernel, which is not diagonal in degree and therefore leaves section 3 behind. The honest position is
the same trade a trilinear filter makes against an anisotropic one.

**Edges that are not band-limited.** T5 is exact for a band-limited field. The boundary field is
band-limited by construction, since a truncated expansion is what a reading is. The room's walls, the
beam stops and the arms have real corners, and prefiltering those rings. So the split is: the field
gets the exact prefilter, the geometry keeps conventional coverage antialiasing. Applying T5 to the
geometry would be a Gibbs artifact sold as a feature.

## 6. Invariants, And The Split They Give

`P_l = sum over m of a_lm^2` is invariant under every element of SO(3), because the degree `l`
subspace is a unitary irrep. Under a rotation by `alpha` about the read axis, `arg a_lm` moves by
exactly `-m alpha`.

A reading therefore splits exactly:

* **Power per degree is intrinsic.** It is a property of the source, carrying no information about
  where the reader stands.
* **Phase is contextual.** It is a property of the source and the reader together, and it moves by a
  known amount under a known rotation.

The split is exact and needs no estimator. Deflection and torsion in `boundary_read.py` are the two
halves.

## 7. The Constants, And Which Kind They Are

Every constant in the table is a computed number. `natural_constants.py` produces them to any
requested length by integer arithmetic, verified at 60 places:

```
pi              3.141592653589793238462643383279502884197169399375105820974944
root two        1.414213562373095048801688724209698078569671875376948073176679
root five       2.236067977499789696409173668731276235440618359611525724270897
golden angle    2.399963229728653322231555506633613853124999011058115042935112
harmonic unit   0.282094791773878143474039725780386292922025314664499428422042
```

The golden angle is `pi (3 - root five)`, the index step of T8. The harmonic unit is `1 / (2 root pi)`,
the degree zero harmonic and the scale every other one is built on.

**The verification carries no trusted digit string.** SHA-256's 64 round constants are defined as the
first 32 bits of the fractional parts of the cube roots of the first 64 primes, and its 8 starting
words the same for the square roots of the first 8 primes. Recomputing them from the primes and
comparing against FIPS 180-4 checks 2,048 independently published bits. All 2,048 agree. The tool
also grades every copy of the table in this tree against the definition: fifteen copies found, one of
them the tool's own reference, and all fifteen match.

Pi is checked twice more, against a 50-digit prefix and against a second computation from Euler's
arctangent identity. Machin's and Euler's identities share no term, so agreement between them is not
two copies of one mistake.

**The measured value this produced.** The double the golden placement runs on sits 4.441e-16 radians
from the true golden angle. Over 63 indices the accumulated difference is about 2.8e-14 radians, which
is negligible and is now a number instead of an assumption.

### 7.1 The other kind of constant

The 2022 CODATA adjustment (Mohr et al. 2025) lists each fundamental physical constant with a value
and an uncertainty. About half read `(exact)`, because the 2019 redefinition of the SI fixed the speed
of light, the Planck constant, the elementary charge, the Boltzmann constant and the Avogadro constant
by definition. The rest carry an uncertainty no amount of computing will shrink: the fine-structure
constant at 1.5e-10 relative, the Newtonian constant of gravitation at 2.2e-5, every particle mass at
its own figure.

**No constant of that kind appears in the reading path.** Confirmed by search across every source
file in the tree. The consequence is worth stating plainly: the reading engine carries no
experimental uncertainty at all. Its only floors are chosen ones, and there are three.

| floor | what sets it | how to move it |
|---|---|---|
| degree ceiling | the reading's rank, `(L+1)^2` | raise `L`, and pay `O(L^2)` |
| number format | double at 16 digits, shader float at 7 | carry more digits |
| calibrated null | a move that changes nothing, measured | a better null |

The null is the only one of the three that is measured, and it measures this tree's own arithmetic
and not the world. The power-under-rotation null floor stands at 4.005e-16 from `null_harness.py`.

## 8. Not Settled

* **T5 and T10 are unbuilt.** The math above is written and the shader is not. Nothing here is a
  frame time, and the claim that a fragment evaluation is faster than a table read is an
  architectural argument from working-set sizes, not a measurement.
* **The anisotropic case has no answer** beyond accepting the isotropic kernel's over-blur.
* **The `l_max` constant** of `3.33 / sigma` follows from a threshold of one level in eight bits.
  The crossover where dropping degrees begins to pay has not been measured against a real frame.
* **T11's cost** is quoted as `O(L^3)` from the shape of the re-expansion and has not been timed
  here, because the tree avoids it.
* **Depth and degree do not interact in the choice.** Depth multiplies a column by about a constant
  without reordering degrees, so the price and the structure are chosen separately. Measured, and
  the mechanism is T3's diagonality.

## References

* Mohr, Newell, Taylor and Tiesinga (2025). *CODATA recommended values of the fundamental physical
  constants: 2022*. Reviews of Modern Physics 97, 025002. doi:10.1103/RevModPhys.97.025002.
  Copy in the citations corpus at `sources/physics/metrology/revmodphys_97_025002.pdf`,
  SHA-256 `e7fa786c5b66640784451f40883c886bddaee52d87521382af71c55e1636af41`.
* FIPS 180-4, *Secure Hash Standard*, for the round constants section 7 recomputes.
* `docs/boundary-reading.md` and `docs/boundary-counting.md` for the rank bound.
* `docs/octant-lexicon.md` for T12.
* `theory/theory/cryptography/sha256/chapters/chapter_boundary.tex` for the theory these tools serve.
