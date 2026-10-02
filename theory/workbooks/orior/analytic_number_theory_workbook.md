# Analytic number theory workbook

**Purpose:** Record what the engine's exact arithmetic shows when it is pointed at analytic number
theory, one poke at a time, claiming nothing. **Scope:** `examples/0_experimental/exact_zeta_values.py`,
`examples/0_experimental/exact_zeta_zeros.py`, `evidence/proofs/posits/proof_set_theory.py`, and this
file.

This is a workbook, and it claims no result. It follows the rail the
millennium research paper set down (`theory/theory/millennium/chapters/chapter_what_this_is.tex`), because that
research paper already refused the exact temptation this one has to refuse:

- Claim nothing. No open problem is attacked here. A method that led a research paper would already claim to
  reach something; nothing of that kind is claimed or supported.
- Cite nothing unread. A fact that arrived by report says so in the sentence carrying it.
- Gaps go in the sentence making the claim, not in a footnote.
- Withdrawn entries stay on the page with whatever killed them.
- Draw the bar, never derive it. A threshold reasoned out of a distribution inherits every variance
  source it forgot.

What this workbook has that a pen-and-paper one lacks is exact arithmetic: every number below is
carried with no rounding, and checked by a second route. That buys verification to any number of
places. It does not buy a proof, and the difference is the reason for the rail above.

## Entry 1, 2026-09-16: zeta at the even integers

`examples/0_experimental/exact_zeta_values.py`, run and exit 0. It computes the Riemann zeta function
at the even integers, `zeta(2k) = c_k * pi^(2k)`, with `c_k` an exact rational from the Bernoulli
numbers, and checks the values a second way that never touches `pi`.

- The values: `zeta(2) = 1.644934...`, `zeta(4) = 1.082323...`, up to `zeta(16)`, with coefficients
  `1/6, 1/90, 1/945, 1/9450, 1/93555, 691/638512875, 2/18243225, 3617/325641566250`. `pi` is computed
  to 80 places by Machin's formula and by Euler's, and they agree.
- The second route: Euler's convolution identity, `sum_{j=1}^{k-1} zeta(2j) zeta(2k-2j) =
(k + 1/2) zeta(2k)`. Every term carries `pi^(2k)`. The factor cancels and the identity is an exact
  rational statement about the `c_k`, derived a different way than the Bernoulli formula. It holds on
  the computed coefficients. A wrong coefficient, `zeta(4) = pi^4/80` in place of `/90`, breaks it, the
  drawn null.
- Prior art: the closed form for `zeta(2k)` is Euler's, eighteenth century, and standard. This file
  reproduces the values in exact integers and verifies them by the convolution identity; it does not
  originate them.

**What this is and is not.** These are the VALUES of zeta at the even integers. The Riemann hypothesis
is a statement about the ZEROS of `zeta(s)` in the critical strip, and no zero is computed or touched
here. Nothing in this entry bears on it.

## Entry 2, 2026-09-16: the set the values live in

`evidence/proofs/posits/proof_set_theory.py`, run and exit 0. It proves, by construction, four standard
facts and connects them to the measurement floor.

- The generation operator is a Moore closure: extensive, monotone, idempotent, with closed sets closed
  under intersection. One round of derivation is extensive and monotone but not idempotent, the null;
  a closure is the fixed point.
- The exactly-nameable quantities are countable: a finite description over a finite alphabet lands at a
  finite index, and the enumeration is shown injective and a contiguous prefix of the naturals on a
  sample.
- The reals are not countable: Cantor's diagonal builds, from any finite table, a real differing from
  every row.
- A countable set has measure zero: it is covered by intervals of total length below any `epsilon`,
  while the unit interval is not.
- Prior art: Cantor 1891 for the diagonal, Turing 1936 for the computable reals being a countable
  subset, and the standard result that the computable reals have measure zero. Reported from a web
  search, not from the primary papers, which are unread here; the constructions are reproduced and
  verified in the file. The file stands on the reproduction, and the citation carries none of its weight.

**The connection, stated carefully.** A zeta value at an even integer is `c_k * pi^(2k)`, an exactly
nameable number, one point in the countable set. A measured quantity is a real the engine can only
bracket to its deposit, and almost every real has no finite description. It lies in the uncountable
complement. The measurement floor of the precision document is that boundary. This is an observation
about where exact and measured quantities sit, and it makes no claim about any open problem.

## Entry 3, 2026-09-16: the symmetry of the zeros, and a dream kept in its column

`examples/0_experimental/zeta_zero_symmetry.py`, run and exit 0. What is proven and what is dreamed are
kept in separate columns here, by design.

PROVEN, exactly. The zero set is invariant under a Klein four-group: the functional equation's
involution `s -> 1 - s`, conjugation `s -> conj(s)`, and their composition `s -> 1 - conj(s)`, whose
fixed set is the critical line `Re(s) = 1/2`. On Gaussian rationals the file verifies the three
maps are involutions, the group closes, the fixed set is the critical line, and an orbit on the line
collapses from four points to a conjugate pair. This is the same shape as the transform's wave inversion
one level down: an involution and the fixed set it turns around, `m -> -m` fixing `0` and `n/2`, and
`s -> 1 - conj(s)` fixing the critical line. The two symmetries are theorems, the functional equation
and the real coefficients; the file verifies only the group they generate, which needs no zero.

DREAMED, and left as a dream. The zeros carry a fine structure that looks universal: rescaled by the
local mean spacing, their pair correlation matches the Gaussian Unitary Ensemble of random Hermitian
matrices. Montgomery conjectured it in 1973, Dyson recognized the GUE form on sight, and Odlyzko gave it
strong numerical support at heights near `10^20`. The DENSITY is a theorem, the Riemann-von Mangoldt
count `N(T) ~ (T / 2pi) log(T / 2pi) - T / 2pi`. That the distribution is exactly that one universal
form, and that every zero is a fixed point of `s -> 1 - conj(s)`, the Riemann hypothesis itself, is a
conjecture with strong numerical support and no proof. It is fun to dream that a single fingerprint
forces it. The dream is not a proof, and it stays in this column labeled a dream. Proof is proof. Prior
art: Montgomery 1973, Dyson, Odlyzko; reported from a web search, papers unread.

## Entry 4, 2026-10-01: the zeros, counted and placed by sign bits

`examples/0_experimental/exact_zeta_zeros.py`, run and exit 0, in 70 seconds. It computes zeta in the
critical strip, in brackets: integers at a scale `2^-b`, with Euler-Maclaurin's proven remainder bound
carried in the bracket. Every rounding is carried.

- The bits. Each point is asked two bits, `Re zeta > 0` and `Im zeta > 0`. A bracket holding zero
  leaves a bit undecided, and that point alone asks again at twice the scale. Each edge between two
  points is asked one bit: does zeta over the whole edge stay on one side of a line through zero? An
  undecided edge splits at its midpoint. The quarter turns around a box sum to four times the zeros
  inside it, by the argument principle. No precision, region or step is assigned. Every point starts at
  `2^-24`, and the deepest point the run needed sat at `2^-96`.
- The line. Every box is symmetric about `Re(s) = 1/2`. By the group entry 3 verifies, a zero off the
  line brings its mirror into the same box, and a symmetric box counting one holds a zero on the line.
- The walk. Up the strip from `t = 1`, between its own edges `Re(s) = 0` and `Re(s) = 1`: an empty box
  doubles the step and a crowded box halves it. It found ten zeros, each alone in its box. Each was
  then placed by sixteen bits, one count per bit, in squares centred on the line.
- Positive control, with an answer from outside. Each of the ten placed brackets holds the ordinate
  Odlyzko's table prints for it, read from the table at nine places: `14.134725142` lies in
  `[14.13464355, 14.13476562]`, and the other nine likewise.
- Drawn null. Zeta without the integral of the rest, `N^(1-s)/(s-1)`, counts one zero between `t = 1`
  and `t = 10`, where there is none, and eleven below `t = 50`, where there are ten.
- What it is not. Ten zeros on the line below `t = 50` is a computation at a height, and the field has
  verified far past it. It bears on the Riemann hypothesis exactly as far as every verification below a
  height does, and not at all past that height.

## The problem, stated fully

Written here so it sits in one place a later entry can find, and not adopted as a target. The Riemann zeta function is
`zeta(s) = sum_{n>=1} n^{-s}` for `Re(s) > 1`, continued analytically to the whole complex plane apart
from a simple pole at `s = 1`. Its trivial zeros are the negative even integers. Its non-trivial zeros
lie in the critical strip `0 < Re(s) < 1`. The Riemann hypothesis is that every non-trivial zero has
real part exactly `1/2`, the critical line. This workbook writes the statement down and does nothing
with it.

## The bounding function for zeta

Placing zeta in the boundary table of the precision document, section 10:

- The values at the even integers are DEFINED: `zeta(2k) = c_k pi^{2k}`, an exact rational times an
  exact transcendental. Their boundary is a FORMAT boundary, the precision scale, raisable without
  limit; there is no measurement floor and no completeness floor on a value.
- The values at the odd integers, Apery's `zeta(3)` and up, are also defined, computed by a convergent
  series to any precision, the same format boundary. No closed form in `pi` is known for them, a fact
  about the FORM and not a boundary on the precision.
- The ZEROS carry a COMPLETENESS boundary. A computation names finitely many, to a stated precision, at
  a horizon: Titchmarsh named 1041, Turing extended the method, Odlyzko reached 20 billion near the
  `10^23`-rd, Gourdon the first `10^13`. None of those is all of them, and no precision closes the gap;
  only more computation moves the horizon, and the horizon never reaches a statement about every zero.
  That is the completeness boundary of section 6, on its most famous instance.

Zeta sits in two regimes at once, like particle physics: its values are defined and unbounded in
precision, and its zeros carry the completeness boundary the hypothesis lives behind.

## Constructors, and what inherits their proof

The exact quantities are built by a fixed set of constructors: the exact integer and rational
operations, the identity hyperedges, and the convergent exact series for the transcendentals, `pi` by
Machin and by Euler, a logarithm by artanh, a root by the integer square root.
`evidence/proofs/posits/proof_precision_theorems.py` proves those constructors sound: scale invariance,
the no-alias convolution, CRT bijectivity, the Fermat inverse, exact accumulation.
`proof_set_theory.py` proves the generation operator over them is a Moore closure.

A quantity built only from proven constructors inherits their proof. `zeta(2k) = c_k pi^{2k}` is a
rational from the Bernoulli recurrence times a power of `pi` from a proven series, combined by proven
exact multiplication. Its exactness is not a new thing to prove; it is the constructors' exactness
carried through. The convolution identity is then a check that the carried value is the intended one, a
second route in the sense Blum, Luby and Rubinfeld gave result checking: a simpler independent
computation that catches a faulty one without trusting it. What is never inherited is a statement about
the zeros, because no constructor produces one.

## Prior art, two threads

- Result checking by agreement. That a value is trusted only when a second, independent route confirms
  it is program result checking and self-testing/correcting: Blum and Kannan; Blum, Luby and Rubinfeld,
  "Self-Testing/Correcting with Applications to Numerical Problems", JCSS 1993. The engine's discipline,
  two routes or it does not ship, is that idea. Reported from a web search, the papers unread here, and
  the file stands on the reproduction.
- The computational path on zeta. Others walked it without exact arithmetic. Riemann's unpublished
  formula, recovered by Siegel in 1932; Titchmarsh's 1930s machine computation of 1041 zeros; Turing in
  1953, whose method reads the real-valued function on the critical line (Odlyzko, "Alan Turing and the
  Riemann Zeta Function"); the Odlyzko-Schonhage algorithm and Odlyzko's 20 billion zeros near the
  `10^23`-rd; Gourdon's `10^13`. They used floating point, high-precision floating point and interval
  arithmetic, and they computed the ZEROS this workbook has not touched. Exact arithmetic adds no
  rounding and a second route on the VALUES; it does not yet reach where their work is. Reported from a
  web search, papers unread.

## The precision-as-obstacle tradition, and where exact arithmetic sits

A whole line of work reached for verified arithmetic because floating point could not carry a proof.
The statement is standard: floating point is subject to rounding and is not suitable for a numerically
verified proof. Verified computing uses interval arithmetic, carrying each quantity as an interval
guaranteed to contain the true value, with directed rounding at each step. On zeta, David Platt isolated
every non-trivial zero with imaginary part below about `3 * 10^10` to an absolute precision of `2^-102`,
and verified the list complete with a provably correct version of Turing's method, at a cost in multi-precision
certified numerics far above hardware floating point. That is an independent verification of the
hypothesis up to that height, and it was possible only by leaving floating point behind.

Where exact arithmetic sits in that tradition is worth stating exactly, because it is easy to overstate.
Exact arithmetic is the limit of the interval: a zero-width interval, the value carried with no rounding
at all, when the value is exactly nameable. The zeta VALUES at the even integers are built by the constructors. A non-trivial ZERO is not: no
closed form in them is known. It does have a finite description, the `n`-th zero above the real
axis, and a bracket around it narrows as far as asked. It is a computable real, in the countable
set of entry 2. Whether its imaginary part is irrational, algebraic or transcendental is not known.
No arithmetic, exact included, carries it at zero width. The most any computation does with a zero is bracket it, and
Platt's `2^-102` interval is that bracket done rigorously. Exact arithmetic does not supersede that
work; it sharpens the value side to zero width and leaves the zero side to the same verified enclosure
the field already uses. Reported from a web search, the papers unread here.

This is the honest reason the earlier entries touch the values and not the zeros: the values are built by
the constructors exact arithmetic carries, and the zeros are reached only through a bracket.

## Where they are bound, and what is wanted in their place

The same table the Navier-Stokes workbook keeps, for the zeros. The wants are quoted from a
sounding board that read the point-cloud approach onto zeta. The test is what would answer each
want, and the status says what has been run. No row bears on the hypothesis.

| where it is bound | as the problem states it | wanted | what would test it | status |
| --- | --- | --- | --- | --- |
| the critical strip | `0 < Re(s) < 1`, the non-trivial zeros inside it | "flatten and normalize between 0 and 1" | nothing: the strip's real part already runs from 0 to 1, and the critical line is its midpoint | holds by the definition of the strip |
| the critical line, `Re(s) = 1/2` | the hypothesis puts every non-trivial zero on it | "the exact identity symmetry boundary of the field"; "like the cellular membrane interface or the solid wall in your fluid model" | the fixed set of `s -> 1 - conj(s)` | proven, exactly (entry 3): the line is that fixed set. That the zeros sit on it is the hypothesis, open |
| the symmetry, and the `1,1 -> 2` table | `zeta(conj s) = conj zeta(s)` from the real coefficients, and the functional equation | "How your `1,1 -> 2` truth table syntax represents the complex conjugate symmetry that forces the zeroes to stay on the line" | the Klein four-group of entry 3: it takes a zero to an orbit of four, which collapses to a conjugate pair on the line. An orbit of four off the line is allowed by the group. The symmetry alone does not force a zero onto the line. The table is the sum of two bits, and no step from it to the group is written | the group is proven (entry 3); the forcing is the hypothesis, open; the table-to-group step is wanted, not written |
| a zero | a point where `zeta(s) = 0` in the strip, with no known closed form | "the exact intersection or topological union where the field's magnitude drops to absolute `0`" | the winding of zeta around a box symmetric about the line, read from the sign bits of `Re zeta` and `Im zeta` | run (entry 4): ten zeros, each placed by sixteen bits. A zero has no known closed form in the constructors, and the most any computation does with one is bracket it (the precision tradition section) |
| the digits of a zero | Riemann-Siegel or Euler-Maclaurin, to a stated precision | "you don't get trapped by infinite digits or fake mathematical blowups" | Platt's interval computation, which isolated every zero below about `3 * 10^10` to `2^-102`, with directed rounding at each step | done by the field, rigorously, and reported from a web search (the precision tradition section). Exact arithmetic sharpens the values to zero width and leaves the zeros to the same enclosure |
| the zeros as a set | counted by `N(T) ~ (T / 2pi) log(T / 2pi) - T / 2pi` | "an infinite point cloud where every branch has an answer" | every zero up to a height `T` found by the winding count, and the count checked against `N(T)` | run below `t = 50` (entry 4): ten, as the published table has them. A count reaches a horizon and never all of them (the bounding function section) |
| the spacing law | Montgomery's pair correlation against the GUE | "which physicists have already proven mirrors the quantum energy levels of chaotic systems" | a proof of Montgomery's conjecture | not proven: entry 3 records it as a conjecture with strong numerical support, in the column labeled a dream |
| L* on zeta | not in the problem | "treat the zeta function like an unknown piece of hardware"; "probe the field's clock-cycle-like preferences" | L* learns a finite automaton from membership and equivalence queries. Zeta would need an alphabet and a membership query, and neither is named | wanted, not built. engine_table has no L* row; its M23 holds the refinement loop, not built |
| every zero on the line | the hypothesis | "the zeroes are structurally forced to exist only along that identity membrane" | a proof | open. Nothing here bears on it |

## Open, not done

- Entry 4 counts below `t = 50`. Euler-Maclaurin sums about `t / 2pi` terms per value. Far up the
  strip that cost wants the Riemann-Siegel formula, whose remainder bound is not carried here.
- The sign of `Z(t)` at the Gram points is the reading the shift agreement detector and the null
  permutation identity are built for. Gram's law shows as agreement at lag 2. The null permutation
  needs 32 occurrences of each sign, about 64 Gram intervals. Both need the Riemann-Siegel theta
  function in brackets, and that is not built.
- Whether a non-trivial zero has a closed form in the constructors is a separate question from where
  it sits, and it is not addressed here.

## Withdrawn

Nothing withdrawn yet. The rail keeps this heading, and a later reader knows a pulled claim would
appear here with what killed it, instead of vanishing.
