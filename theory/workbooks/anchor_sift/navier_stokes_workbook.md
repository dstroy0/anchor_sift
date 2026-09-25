# Navier-Stokes workbook

**Purpose:** Record what the engine's exact arithmetic shows when it is pointed at the sets Fefferman's
Navier-Stokes statement names, one poke at a time, claiming nothing. **Scope:**
`examples/0_experimental/exact_navier_stokes_on_torus.py`,
`evidence/proofs/posits/proof_boundary_inheritance.py`, and this file.

Kept by the precision measurement specialist. This is a workbook, not a result. It follows the rail the
millennium book set down (`theory/theory/millennium/chapters/chapter_what_this_is.tex`) and the analytic
number theory workbook beside this file already follows:

- Claim nothing. No open problem is attacked here. Nothing below bears on whether Fefferman's (A), (B),
  (C) or (D) holds.
- Cite nothing unread. A fact that arrived by report says so in the sentence carrying it.
- Gaps go in the sentence making the claim, not in a footnote.
- Withdrawn entries stay on the page with whatever killed them. Four are recorded below.
- Draw the bar, never derive it. The boundary kind below is read off each object by a probe, never
  assigned by judgment.

We know nothing here that the field does not. Every object in these two files belongs to someone else
and is named with respect in the prior-art section; the two files only run those objects in exact
arithmetic, which adds no rounding and a second route, and they add nothing else. This is help offered
to a neighborhood, not a claim staked in it.

## The problem, stated fully

Read from Charles Fefferman's statement for the Clay Mathematics Institute, six pages including the errata
page, fetched from the Clay site on 2026-09-17 and read in full. The millennium book's chapter
(`theory/theory/millennium/chapters/chapter_navier_stokes.tex`) read the same document on 2026-09-11 and
its account agrees with this reading at every point checked.

The unknowns are a velocity `u(x,t)` in `R^n` and a pressure `p(x,t)`, `n = 2` or `3`, `t >= 0`, with
viscosity `nu > 0`:

- (1) `d/dt u_i + sum_j u_j d u_i / d x_j = nu Laplacian u_i - d p / d x_i + f_i(x,t)`
- (2) `div u = 0`
- (3) `u(x,0) = u°(x)`, with `u°` a given smooth divergence-free field
- (4) `|d_x^alpha u°(x)| <= C_{alpha K} (1+|x|)^-K` on `R^n`, for any `alpha` and `K`
- (5) `|d_x^alpha d_t^m f(x,t)| <= C_{alpha m K} (1+|x|+t)^-K` on `R^n x [0,inf)`, for any `alpha, m, K`
- (6) `p, u` in `C^inf(R^n x [0,inf))`
- (7) `int_{R^n} |u(x,t)|^2 dx < C` for all `t >= 0` (bounded energy)
- (8) `u°(x+e_j) = u°(x)`, `f(x+e_j,t) = f(x,t)` for `1 <= j <= n`, `e_j` the unit vectors; the errata add
  `p(x+e_j,t) = p(x,t)`
- (9) `|d_x^alpha d_t^m f(x,t)| <= C_{alpha m K} (1+|t|)^-K` on `R^3 x [0,inf)`, for any `alpha, m, K`
- (10) `u(x,t) = u(x+e_j,t)` on `R^3 x [0,inf)` for `1 <= j <= n`
- (11) `p, u` in `C^inf(R^n x [0,inf))`

The four alternatives, one proof of which is asked for: (A) for `nu > 0`, `n = 3`, any `u°` satisfying
(4) and `f = 0`, there exist `p, u` satisfying (1), (2), (3), (6), (7); (B) the same with (8) in place of
(4) and (10), (11) in place of (6), (7); (C) there exist `u°` and a smooth `f` satisfying (4), (5) for
which no `(p,u)` satisfies (1), (2), (3), (6), (7); (D) the same with (8), (9) and (10), (11). The Euler
equations are (1), (2), (3) with `nu = 0`, and the statement records the Beale-Kato-Majda criterion for
them: a smooth Euler solution with finite blowup time `T` has `int_0^T sup_x |curl u(x,t)| dt = inf`. The
statement also says the Euler problem is not on the Clay list. This workbook writes the statement down
and does nothing with any alternative.

The errata page carries a second item: an equation it numbers (10) "should read" a weak form with the
signs `- int u . d theta/dt - sum int u_i u_j d theta_i/dx_j = nu int u . Laplacian theta + int f . theta

- int p (div theta)`. In the text as fetched, (10) is the periodicity of `u` and the weak form is (12),
  so the errata refer to an earlier numbering; recorded as read, and the weak form is not used here.

## Their sets, defined

Written as sets so that every later sentence names the set it is about. `n = 3` and `nu > 0` are fixed
throughout; `e_j` are the unit vectors; "smooth" is `C^inf`. Each set is Fefferman's condition as he
wrote it, and the definitions are transcribed, not designed.

- `D_4`, the whole-space data: smooth `u° : R^3 -> R^3` with `div u° = 0` and, for every multi-index
  `alpha` and every `K > 0`, a constant `C_{alpha K}` with `|d_x^alpha u°(x)| <= C_{alpha K} (1+|x|)^-K`
  on `R^3`. Rapid decay of every derivative.
- `F_5`, the whole-space forces: smooth `f : R^3 x [0,inf) -> R^3` with, for every `alpha, m, K`, a
  constant with `|d_x^alpha d_t^m f(x,t)| <= C_{alpha m K} (1+|x|+t)^-K`. Rapid decay in space and time
  together.
- `S_67(u°, f)`, the physically reasonable whole-space solutions for a datum and a force: pairs `(p, u)`
  with `p, u` smooth on `R^3 x [0,inf)`, satisfying (1) and (2) there, `u(x,0) = u°(x)`, and one constant
  `C` with `int_{R^3} |u(x,t)|^2 dx < C` for every `t >= 0`.
- `D_8`, the periodic data: smooth `u° : R^3 -> R^3` with `div u° = 0` and `u°(x+e_j) = u°(x)` for
  `j = 1, 2, 3`. No decay condition; the torus replaces it.
- `F_89`, the periodic forces: smooth `f` with `f(x+e_j, t) = f(x, t)` and, for every `alpha, m, K`, a
  constant with `|d_x^alpha d_t^m f(x,t)| <= C_{alpha m K} (1+|t|)^-K`. Rapid decay in time only.
- `S_1011(u°, f)`, the periodic solutions: pairs `(p, u)` with `p, u` smooth on `R^3 x [0,inf)`,
  satisfying (1), (2), (3), with `u(x+e_j, t) = u(x, t)` and, by the errata, `p(x+e_j, t) = p(x, t)`.
  No energy condition is written; on a period cell the energy of a smooth periodic field is finite.

The four alternatives in those names:

- (A): for every `u°` in `D_4`, `S_67(u°, 0)` is not empty.
- (B): for every `u°` in `D_8`, `S_1011(u°, 0)` is not empty.
- (C): there exist `u°` in `D_4` and `f` in `F_5` with `S_67(u°, f)` empty.
- (D): there exist `u°` in `D_8` and `f` in `F_89` with `S_1011(u°, f)` empty.

Two readings of those definitions, both from the statement and neither new. (C) is not the negation of
(A): the negation of (A) is (C) with `f = 0`, and (C) allows any `f` in `F_5`. (A) and (C) can both be
true, and likewise (B) and (D). The millennium chapter called that two different removals, and the
removal instances of entry 1 below are that shape on one field each. Fefferman's own sentence on
the unforced case is that either (A) and (B) hold, or else there is a smooth divergence-free `u°` for
which (1), (2), (3) have a solution with a finite blowup time `T`, past which the velocity becomes
unbounded; for Euler, `nu = 0`, the Beale-Kato-Majda criterion then gives
`int_0^T sup_x |curl u(x,t)| dt = inf`. Both are his sentences and nothing here touches them.

Two more sets he defines and this workbook does not use: the weak solutions, pairs `(p, u)` with `u` in
`L^2`, `p` and `f` in `L^1`, satisfying (12) for every smooth compactly supported test field `theta` and
(13) for every smooth compactly supported test function, which Leray showed always exist in three
dimensions with suitable growth; and the singular set of a weak solution, the points `(x°, t°)` near
which `u` is unbounded, whose one-dimensional parabolic Hausdorff measure Caffarelli, Kohn and Nirenberg
showed is zero, with F.-H. Lin's simpler proof. Named here because they are in the statement, and named
as his account of them, since the papers are unread here.

Our set, and where it sits in theirs. `R` is the ring of entry 1: finite sums of modes `e^{2 pi i k.x}`
over `Z^3` with Gaussian integer Laurent coefficients in `pi` over one integer denominator, real-valued
when `c_{-k}` is the conjugate of `c_k`; `R_div` its divergence-free vector fields. Then:

- `R_div` is a subset of `D_8`: every element is a trigonometric polynomial. Smooth and periodic, and
  the divergence is an exact identity. That is the inclusion the whole of entry 1 rests on.
- `R_div` meets `D_4` only at zero: a nonzero periodic field does not decay. So the ring reaches (B) and
  (D)'s data and none of (A) and (C)'s, and the table below says `not run` for the whole-space sets.
- `R_div` is closed under the constructors of the recurrence (products, derivatives, Leray's projection
  with the denominator widened). Every Taylor coefficient of a solution with datum in `R_div` is in
  `R_div`; shown to order 4 and true by construction at every order.
- The solution itself, `u(t)` for `t > 0`, is not in `R`: for the ABC datum it is `e^{-4 nu pi^2 t} u_0`,
  whose amplitude is not a Laurent polynomial in `pi` with integer coefficients, and for a generic datum
  the horizon table shows the mode set has no finite bound. `R` names the datum and the coefficients at
  one instant; `S_1011` is where the solution lives, and the ring only reaches into it through the
  coefficients.
- For the ABC datum `u_0`, `S_1011(u_0, 0)` is not empty, by the two identities entry 1 verifies exactly,
  `curl u_0 = 2 pi u_0` and `(u_0 . grad) u_0 = grad(|u_0|^2/2)`, which make the closed form a solution at
  every `t` since time enters only as a scalar factor. That is one datum's instance of (B), known since
  Arnold and Childress, and it is not (B).

## What they knew, what they wanted, what we know

Three lists, kept apart. The first two are Fefferman's statement, read; the third is the two files, run.

**What they knew**, as the statement records it, in his order and his attributions:

- In two dimensions the analogs of (A) and (B) have been known for a long time, Ladyzhenskaya, and
  also for the harder case of Euler. The three-dimensional difficulties are absent there.
- In three dimensions (A) and (B) hold when `u°` satisfies a smallness condition. For general `u°`,
  (A) and (B) hold, also for `nu = 0`, when `[0, inf)` is replaced by a short interval `[0, T)` with `T`
  depending on the datum; the largest such `T` is the blowup time. Either (A) and (B) hold, or some
  smooth divergence-free `u°` has a solution with finite blowup time, and for `nu > 0` the velocity is
  then unbounded near it.
- For Euler with finite blowup time, the vorticity satisfies the Beale-Kato-Majda divergence quoted
  above. It blows up rapidly. Many numerical computations appear to show Euler blowup, and the
  extreme numerical instability of the equations makes reliable conclusions hard to draw. He points to
  Bertozzi and Majda's book for these results.
- Leray, 1934: weak solutions of (1), (2), (3) in three dimensions always exist with suitable growth.
  Uniqueness of weak Navier-Stokes solutions is not known. For Euler it is false: Scheffer, then
  Shnirelman, built weak solutions with compact support in spacetime, a fluid at rest that starts moving
  with no stimulus and returns to rest.
- Scheffer, then Caffarelli, Kohn and Nirenberg, then F.-H. Lin: partial regularity. The singular set of
  a suitable weak solution has one-dimensional parabolic Hausdorff measure zero. It contains no
  spacetime curve. He calls it the best partial regularity theorem known so far and says it appears very
  hard to go further.
- His closing sentence: standard methods from PDE appear inadequate, and some deep, new ideas are
  probably needed.
- Past the statement, and recorded as the millennium chapter recorded it on 2026-09-11: a 2026 paper
  and a Lean repository were published against (C) and (D); the chapter read the formalized statement
  against his six points and found each matched, built nothing, and read neither proof. Nothing here
  adds to that.

**What they wanted**: a proof of one of (A), (B), (C), (D), in the sets defined above. He says the leeway
is deliberate, to give solvers room while retaining the heart of the problem: whether smooth, physically
reasonable solutions exist for every reasonable datum, or whether some datum breaks down. "Physically
reasonable" is defined, not left open: smooth, with bounded energy on `R^3`, or smooth and periodic on
the torus with the periodic pressure of the errata. The Euler case is wanted too, in his words, and is
not on the Clay list.

**What we know**, each line with its set and its scope, and nothing past the scope:

- On `R_div`, a subset of `D_8`, the residual of (1) with (2) is computable exactly, and for the ABC
  datum it is zero at every Taylor order checked, orders 0 to 4, by two routes that agree to the
  integer. The closed form is a solution for every `t` by the two identities verified; that is an
  instance of (B) for one datum, known since Arnold and Childress.
- For a generic datum in `R_div` the Taylor coefficients to order 4 are exact, divergence-free,
  real-valued, and the vorticity route agrees at every order; their mode support grows by one in
  `|k|_1` per order, measured. No fixed horizon holds the solution. What happens past order 4, and
  whether the series converges, and for how long, is not known here.
- At `t = 0`, on both data, the energy identity holds exactly, with the nonlinear term and the pressure
  moving no energy. That is one instant; (7) is every instant.
- The time and space scalings hold exactly on the coefficients to order 3; the viscosity is a parameter
  a scaling moves.
- On one datum each, the solution sets of Euler and of Navier-Stokes do not contain each other's member,
  and the forced and unforced sets do not; the residuals are exact and proportional to `nu` or equal to
  `f`. Two instances, no theorem.
- `R_div` is countable and `D_8` is not. The exactly nameable data are a measure-zero island in the
  data class; everything the ring does is on that island.
- The boundary kind of each object above, read by probe: none on the ABC coefficients and on the exact
  ring, completeness on a generic datum's horizon, format on any decimal report of a coefficient with
  `pi` in it, measurement on a deposited amplitude and none on the ratio that cancels it. Through the
  chain `datum -> u_3`: the ring carries no format kind; measurement is carried to every order, exactly
  on the ABC family; completeness is carried and grows.
- The disjoint-translate constructor splits the bilinear term exactly when supports are disjoint and not
  when they overlap, in one variable on a lattice of eighths. Its algebra, not their corollary.
- We do not know whether (A), (B), (C) or (D) holds. We have not read the 2026 proof. We have computed
  no blowup, no weak solution, no singular set, and no solution on `R^3`. The two files reach one
  countable island inside `D_8` and read it exactly; they reach nothing past it.

## Entry 1, 2026-09-17: the sets, run on the unit torus

`examples/0_experimental/exact_navier_stokes_on_torus.py`, run and exit 0. The arithmetic is the
engine's own: Python integers as the bignum, decimal inputs read by `representation.exact` as
`(numerator, places)` pairs, and booleans; no float, no fraction library. A field on `R^3/Z^3` is a
finite sum of modes `e^{2 pi i k.x}`, `k` in `Z^3`, each mode carrying a Laurent polynomial in `pi` with
Gaussian integer coefficients, and the whole field carrying one positive integer denominator, the way
`exact.py` carries one count of places. The denominator is widened past a power of ten for one reason:
Leray's projection divides by `|k|^2`, and `1/3` has no exact decimal at any scale, and a decimal scale
would then have to refuse where an integer denominator carries the value exactly. Every field is normalized
by the common divisor of its integers. Equality is equality of integers, and `pi` is a symbol:
Lindemann's theorem makes term-by-term zero the exact zero test. Every element is smooth and periodic,
(8), (10), (11) hold by construction; (2) is an exact identity; the pressure is in the same ring and so
periodic, the errata's condition; the energy on the unit cell is Parseval's exact sum. The solution is
carried as Taylor coefficients at `t = 0` by the recurrence that (1) gives when differentiated `m` times,
with (2) enforced by Leray's projection. Nothing is rounded.

- Positive control, the Arnold-Beltrami-Childress field with `A, B, C = 1, 2, 3`, `nu = 1/10`, orders 0
  to 4. Beltrami `curl u_0 = 2 pi u_0`, exact. `(u_0.grad)u_0 = grad(|u_0|^2/2)`, exact, and its Leray
  part is zero. The recurrence returns `u_m = (-4 nu pi^2)^m u_0` and `p_m = (-8 nu pi^2)^m (-|u_0|^2/2)`
  at every order, to the coefficient. The residual of (1) with (2) is zero at every order.
- Two routes. The vorticity recurrence, Helmholtz's equation with velocities recovered by Biot-Savart and
  no pressure anywhere, meets the velocity route at `curl u_m = omega_m` at every order, on the exact
  solution and on a generic datum, and Biot-Savart returns `u_m` from `omega_m`. Drawn nulls: dropping the
  vortex-stretching term, the two-dimensional form of the equation, breaks the agreement at order 1 in
  three dimensions; flipping the pressure sign leaves a nonzero residual.
- The energy identity at `t = 0`, `d/dt int |u|^2 = -2 nu int |grad u|^2`, holds exactly on both data:
  on the ABC datum both sides are `-56/5 pi^2` with `int |u_0|^2 = 14`. On the generic datum the two
  pieces that vanish are shown to vanish, `int u.(u.grad)u = 0` and `int u.grad p = 0`, and the null is
  a field with divergence, `u_0 + grad cos 2 pi x`, which moves energy through a pressure. This is the
  mechanism behind (7) for `f = 0`, shown at one instant on one instance; it is not (7).
- The horizon, on a generic divergence-free datum `g_0 = (sin 2 pi y + sin 2 pi z, sin 2 pi z, sin 2 pi x)`,
  not Beltrami, with a surviving Leray part and a nonzero pressure from order 1:

  | order                    | 0   | 1   | 2   | 3   | 4   |
  | ------------------------ | --- | --- | --- | --- | --- |
  | largest `\|k\|_1`        | 1   | 2   | 3   | 4   | 5   |
  | largest `\|k\|_inf`      | 1   | 1   | 2   | 3   | 4   |
  | modes held               | 6   | 18  | 42  | 88  | 170 |
  | outside `\|k\|_inf <= 1` | 0   | 0   | 16  | 62  | 144 |
  | outside `\|k\|_inf <= 2` | 0   | 0   | 0   | 16  | 66  |

  `|k|_1` climbs by exactly one per order, because a product of modes adds their index vectors. A
  truncation at any fixed radius misses some order, and the count it misses is measured, not bounded.
  Every coefficient stays divergence-free and real-valued.

- Symmetries, exact on the coefficients. Time scaling `v(x,t) = mu u(x, mu t)` solves (1)-(3) at viscosity
  `mu nu` with `v_m = mu^(m+1) u_m`, checked at `mu = 3`; the wrong exponent `mu^m` is refused. Space
  scaling `v(x,t) = lam u(lam x, lam^2 t)` at the same `nu` keeps the period and gives
  `v_m = lam^(1+2m) u_m(lam x)`, checked at `lam = 2`. The viscosity is a parameter a scaling moves.
- The two removals, on instances. At `nu = 0` the ABC field is stationary and solves Euler exactly; in
  (1) at `nu = 1/10` its residual is `4 nu pi^2 u_0`, nonzero; the decaying viscous field's residual in
  Euler at `t = 0` is `-4 nu pi^2 u_0`, nonzero. The field `e^-t g_0` solves the forced equation with
  `f` equal to its own residual, real and periodic, nonzero at orders 0 to 2, and in the unforced equation
  its residual is that `f`. Neither solution set inherits the other's membership on these instances.
  This is the millennium chapter's argument from the shapes of the statements, that removing the force
  and removing the viscosity are different removals, shown exactly on one field each. It says nothing
  about blowup and nothing about the 2026 paper's construction, which is not represented here.
- The island. `F_b = sum_n 2 b_n n^-n cos(2 pi n x) e_y`, for a bit sequence `b`, is divergence-free
  and real-valued at every truncation, distinct sequences give distinct fields, and the bits read back
  from the coefficients. The full sums are smooth, since `n^-n` beats every power of `n`, and periodic,
  so they sit in (8). The bit sequences are uncountable (Cantor, `proof_set_theory.py`) and the ring is
  countable. The exactly nameable data are a countable island in the data class.

## Entry 2, 2026-09-17: the boundary function asked to define itself

`evidence/proofs/posits/proof_boundary_inheritance.py`, run and exit 0. `proof_domain_boundaries.py`
named three kinds of boundary from a survey. A survey assigns the kind by judgment. Here the kind is not
assigned: two probes are applied to the object, raise our scale by one and raise our horizon by one, and
the object answers. FORMAT is what the scale probe moves, COMPLETENESS what the horizon probe moves,
MEASUREMENT a gap to the target that neither probe moves, NONE no gap. `measurement` means exactly
`unmoved by both of our probes`, and from this side `external` means the same. The verdict is only as
good as the probes: the drawn null cuts the horizon probe from a completeness object and the classifier
reports measurement, the limit stated and not hidden.

Positive controls, kind fixed by construction: the NTT length on `119 * 2^23 + 1` at horizon `2^25`
reads `format`; the 3-ary tree count at horizon 7 of 12 reads `completeness`; a deposit of six places
against its true value reads `measurement`; `22/7` against itself reads `none`.

Their sets, read by the probes, on `u_2` of the generic datum (its modes reach `|k|_inf = 2`):

| object                                                 | gap | scale probe | horizon probe | kind                    |
| ------------------------------------------------------ | --- | ----------- | ------------- | ----------------------- |
| `u_2` in decimals, 30 places, modes `\|k\|_inf <= 1`   | yes | moves       | moves         | format and completeness |
| `u_2` in decimals, 30 places, modes `\|k\|_inf <= 2`   | yes | moves       | silent        | format                  |
| `u_2` in the ring, modes `\|k\|_inf <= 1`              | yes | silent      | moves         | completeness            |
| `u_2` in the ring, modes `\|k\|_inf <= 2`              | no  | silent      | silent        | none                    |
| `u_2` from `A` deposited to 6 places, against true `A` | yes | silent      | silent        | measurement             |
| `u_1 / u_0 = -4 nu pi^2`, deposit against true `A`     | no  | silent      | silent        | none                    |

The format kind is a property of the report, not of the object: the same coefficient reads `format` in
decimals, because a coefficient carrying `pi` has no last digit, and reads `none` in the ring, which has
no scale. The measurement kind is the deposit's, and it is canceled only by the ratio in which the
amplitude cancels, the floor-free ratio of the precision document's Regime C.

## Entry 3, 2026-09-17: the cascade and the coefficient growth, made visible

`examples/0_experimental/exact_navier_stokes_cascade.py`, run and exit 0. It reads the same ring and
recurrence, and shows the solution map as a picture instead of a table, exactly and in integers. Douglas
asked for a way to see the knot through their own set definitions, in place of attacking it by another
proof that reaches the same knot, and this is that: it shows the knot and does not cut it.

- The mode front, pure integers. The count of modes each order carries, grouped by `|k|_1`, for the
  generic datum. The front advances by exactly one shell per order, `1, 2, 3, 4, 5, 6` at orders 0 to 5,
  because a product of two modes adds their index vectors. The counts per shell are
  `6; 6, 12; 6, 12, 24; 6, 14, 24, 44; 6, 14, 34, 44, 72; 6, 16, 34, 62, 72, 108`. This is energy
  reaching a finer scale each order, read with no `pi` in it. Null: the ABC datum, an eigenfunction, keeps
  its whole front on `|k|_1 = 1` at every order. It does not cascade.
- The energy shells, exact. Whether a shell `|k|^2 = r` carries energy is the exact test that a ring
  quantity is zero, and it needs no numeric `pi`. The generic datum lights up more shells each order,
  `[1]`, `[1,2]`, `[1,2,3,5]`, up to eighteen shells at order 5. Two routes agree to the integer: the
  per-order energy from the velocity coefficients and from the vorticity coefficients recovered by
  Biot-Savart. The shell energies sum to the total at every order, Parseval, exact. Null: ABC keeps all
  its energy in `|k|^2 = 1` at every order, and a route with one mode dropped is caught.
- The coefficient growth, the knot. For ABC the energy obeys the exact law
  `E(u_{m+1}) = (16 nu^2 pi^4) E(u_m) = (4 pi^4 / 25) E(u_m)`, a single ring quantity, constant in the
  order. A constant rate makes the time series `sum u_m t^m/m!` the entire function `e^{-4 nu pi^2 t} u_0`,
  so the analyticity radius is infinite and the datum never blows up, matching the closed form of entry 1.
  For the generic datum the energy is an exact Laurent polynomial in `pi` whose `pi`-degree rises by four
  every order, `0, 4, 8, 12, 16, 20`, an integer signal that the coefficients grow. The rate's limit is
  the reciprocal of the time the solution stays analytic, and a finite radius is a blowup. Every finite
  order bounds the rate from one side. No finite order reaches the limit, and reaching it needs a step
  outside exact arithmetic. That is the completeness boundary of the precision document, the same shape
  as the horizon on the zeros of zeta in the analytic-number-theory workbook. It claims nothing about
  whether the radius is finite, and nothing about (A) through (D).

The reading that the radius of the time-Taylor series is the interval of analyticity, and that a finite
radius is the first singular time, is classical: Foias and Temam on the time-analyticity of the
Navier-Stokes solutions, and Kato. Cited from memory of the literature, unread here; the file verifies
only the exact per-order quantities.

## Their sets against the boundary function

| Fefferman's set                                       | what the ring does with it                                                                                                    | kind, by probe                                                        |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- |
| (1) momentum, the equation behind `S_67` and `S_1011` | residual exact on any element of `R_div`; solution as Taylor coefficients                                                     | none on the ABC family; completeness on a generic datum (the horizon) |
| (2) divergence, the condition on every `D` and `S`    | exact identity, carried by every coefficient                                                                                  | none                                                                  |
| (3) datum, `u°` in `D_8`                              | any element of `R_div`; a deposited amplitude                                                                                 | none; measurement for the deposit                                     |
| `D_4`, `F_5`, `S_67`                                  | not represented: `R_div` meets `D_4` at zero                                                                                  | not run                                                               |
| (7) on the unit cell, the energy `S_67` bounds        | Parseval's sum, exact; `d/dt E = -2 nu int \|grad u\|^2` at `t = 0`, exact                                                    | none at the instant checked                                           |
| `D_8` with the errata's periodic pressure             | by construction: datum, force and pressure all periodic                                                                       | none                                                                  |
| `F_89`, decay of `f` in `t`                           | not probed: time is carried at `t = 0` only                                                                                   | not run                                                               |
| `S_1011`, smooth periodic pairs                       | by construction for every coefficient; the solution itself is outside `R`                                                     | none on the coefficients; the solution is reached only through them   |
| `nu > 0`                                              | moved exactly by the time scaling                                                                                             | format, in the sense a symmetry moves it                              |
| Euler, `nu = 0`                                       | the ABC field is a stationary exact solution                                                                                  | none; nothing about blowup or the Beale-Kato-Majda integral           |
| (A), (B)                                              | the ring reaches one exact family in `D_8` and finitely many orders of a generic datum                                        | completeness; claims nothing                                          |
| (C), (D)                                              | the 2026 paper's datum and force are not represented here, and the paper is unread here past what the millennium chapter read | not run                                                               |
| the weak solutions and the singular set               | not represented                                                                                                               | not run                                                               |

## Constructors, and what inherits their proof

A ring element is built by a fixed set of constructors: exact integer arithmetic with one denominator
per field, the mode convolution (a linear convolution on `Z^3`, unaliased, the no-alias theorem of
`proof_precision_theorems.py`), the derivative multiplier `2 pi i k_j`, Leray's projection, and the
Taylor recurrence. A coefficient built
only from proven constructors inherits their proof, as the analytic number theory workbook states for the
zeta values. What each boundary kind does through the chain `datum -> u_1 -> u_2 -> u_3`, measured:

| kind                 | at the datum                                  | through the chain                                    | inherited?                                          |
| -------------------- | --------------------------------------------- | ---------------------------------------------------- | --------------------------------------------------- |
| format, in the ring  | absent                                        | scale probe silent at every order                    | no format kind exists to inherit                    |
| format, in decimals  | absent: the datum's coefficients are rational | moves from order 1 on: the derivative brings `pi` in | introduced by the constructors, then carried        |
| measurement, ABC     | the deposit's gap                             | `gap_m = (-4 nu pi^2)^m gap_0`, exactly              | carried exactly, unamplified; canceled by the ratio |
| measurement, generic | the deposit's gap                             | nonzero at every order                               | carried; no order lowers it                         |
| completeness         | 0 modes outside `\|k\|_inf <= 1`              | 0, 0, 16, 62                                         | carried and growing                                 |

Two more inheritances, one run and one read:

- The disjoint-translate constructor. The millennium chapter's account of the 2026 paper's Corollary 10.6
  is that the periodic case is built by summing integer translates of a compactly supported solution
  whose supports stay disjoint. What that sum inherits from its pieces through the bilinear term rests
  on one exact fact, and the posit shows it on piecewise polynomials with integer coefficients on a
  lattice of eighths, `y = 8x`: with pieces `(y-a)^2 (b-y)^2` on `[0, 2]` and `[4, 6]`, the bilinear
  term of the sum splits into the pieces' bilinear terms by coefficients and by the exact integral of
  the squared difference, which is `0`; with the second piece moved to `[1, 3]`, the drawn null, both
  routes refuse and the integral of the squared cross term over `y` is `156928/5005`. The linear terms
  split regardless. The construction is theirs. Only its algebra is run here, in one variable, and
  nothing here checks the paper's own proof of that corollary, which was not read.
- Fefferman's statement to the Lean statement. That is a reading, not a computation, and the millennium
  chapter did it on six points and found each matched. Nothing here adds to it, and nothing here was
  machine-checked either.

## Prior art, named with respect

Every object above is the field's. The problem statement, its numbered conditions, the four alternatives
and the errata are Charles Fefferman's for the Clay Mathematics Institute, read in full. The equations
are Navier's and Stokes's, the inviscid case Euler's. The field with `curl u` proportional to `u` is
Beltrami's; the three-term example is Arnold's (1965) and Childress's (1970), reported from memory of the
literature and unread here. The file verifies the solution itself and does not rest on the citation.
The projection onto divergence-free fields and the pressure it defines are Leray's. The recovery of a
velocity from its vorticity is the Biot-Savart law; the vorticity equation is Helmholtz's. The energy sum
over modes is Parseval's. The transcendence of `pi` is Lindemann's (1882). The Taylor recurrence is the
classical power-series method of Cauchy and Kovalevskaya. The Beale-Kato-Majda criterion is quoted from
Fefferman's statement and not used. Cantor's diagonal and the Moore closure are credited in
`proof_set_theory.py`. Machin's formula (1706) supplies `pi` where a decimal is needed. The 2026 paper on
finite-time blowup and its Lean repository are described only as the millennium chapter described them,
and that chapter states what it did not read. Result checking by an independent route is Blum, Luby and
Rubinfeld's, credited in the analytic number theory workbook. Nothing in either file is new mathematics,
and neither file wants it to be.

## Open, not done

- The whole-space conditions (4) to (7) need a representation with decay on `R^3`, which the periodic
  ring is not. A compactly supported piecewise-polynomial representation in three variables would reach
  the disjoint-translate constructor in its own setting; the one-variable algebra above has the shape of
  that setting and is not it.
- Condition (9), decay of the force in time, needs the time dependence carried past `t = 0`. The Taylor
  coefficients at one instant do not see it.
- The horizon count is measured to order 4 on one datum. A second datum and a higher order would show
  whether `|k|_1` climbing by one per order is the general rule it looks like or the property of this
  datum. It is stated above as measured, on this datum, to this order.

## Withdrawn

- **Withdrawn.** The first build of both files, which carried the coefficients as Gaussian rationals from
  a fraction library and the binomials from a math library. **What killed it:** Douglas, on reading it.
  The engine's arithmetic is Python integers as the bignum, decimal text read by `representation.exact`,
  and booleans, with no other arithmetic beside them; a library that carries rationals for us is a
  second arithmetic under the one this tree is built to trust, and the exact path exists so that there
  is no second arithmetic. Rebuilt on integers with one denominator per field, and every result above
  was reproduced to the integer: the energy `14`, the rate `-56 pi^2 / 5`, the mode counts
  `6, 18, 42, 88, 170`. The one number that changed is the overlap integral, `613/44024445576151040`
  over `x` in the first build and `156928/5005` over `y = 8x` in this one, because the lattice moved to
  eighths; both are nonzero, and that is all the null asks of them. Recorded first because it was the
  largest fault.
- **Withdrawn.** That the mode radius `|k|_inf` of the generic datum's Taylor coefficients grows at every
  order. **What killed it:** the run. At order 1 the radius is 1, the same as at order 0, because the
  first products of unit modes land on modes like `(0, 1, 1)`, whose sup-norm is still 1. Replaced by
  the measured statement: `|k|_1` climbs by exactly one per order, and `|k|_inf` never falls and ends
  higher. The first wording was derived from the shape of a convolution and not drawn from the output.
- **Withdrawn.** That the format kind, in a decimal report, is present at every order of the chain. **What
  killed it:** the run. At the datum the coefficients are `+-i/2`, terminating rationals, and the scale
  probe is silent there. The kind appears at order 1, when the derivative multiplies by `2 pi i k`.
  Replaced by the measured statement that the constructors introduce it. The better finding was in the
  refusal.
- **Withdrawn**, for the duration of one run. That two bit patterns produced two distinct fields whose
  bits read back. The first build of the island summed `cos 2 pi x` for every `n` in place of
  `cos 2 pi n x`. Every bit landed on one mode. The check `bits read back` refused it; the harmonic
  was corrected and the check passed. Recorded because a wrong construction had produced `distinct:
True` by accident, and only the second check caught it.
