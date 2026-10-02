# Analytic number theory workbook

**Purpose:** Record what the engine's exact arithmetic shows when it is pointed at analytic number
theory, one poke at a time, claiming nothing. **Scope:** `examples/0_experimental/exact_zeta_values.py`,
`examples/0_experimental/exact_zeta_zeros.py`, `examples/0_experimental/exact_zeta_gram.py`,
`evidence/proofs/posits/proof_set_theory.py`, and this
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

## Entry 4, 2026-10-02: the zeros, counted and placed by truthy and falsy verdicts

`examples/0_experimental/exact_zeta_zeros.py`, run and exit 0. It computes zeta in the critical strip
as exact integers at a count of decimal places, the form `representation.exact` holds. pi comes from
`representation.constants.naturals`, where Machin's and Euler's identities agree, and `ln n` from two
series that agree the same way. A value is the floor at its places, every reading of it carries the
unit of its last place, and a value asked past the scale raises `WillNotFit`. Nothing rounds.

- The verdicts. Every verdict is a field, zero false and nonzero true, and a pass writes its verdicts
  for the next pass to read. Each point carries four: whether two Euler-Maclaurin routes, at `N` and
  `2N`, agree at its places, and the signs of `Re zeta`, `Im zeta` and `|Re zeta| - |Im zeta|`. Routes
  that disagree double `N`. A sign of zero doubles the places. The three signs give the eighth of a
  turn zeta sits in. No precision, region, step or term count is assigned.
- The count. Around a closed path the eighth turns sum to eight times the zeros inside it, by the
  argument principle. Each edge is read end to end and through its midpoint, and each half carries
  `COMPARE` of the smaller `|zeta|^2` at its ends against its chord `|zeta(c) - zeta(a)|^2`, at one
  count of places, and at each end `COMPARE` of `|zeta|^2` against `|zeta'|^2` times the step squared.
  Ends at different places are asked again at the deeper one, and a verdict of zero doubles the
  places. Readings that disagree, or a negative verdict, put the midpoint into the path. An edge is
  decided where the readings agree and every verdict is positive. Each value is read toward zero, its
  sign times the floor of its size. A floor is monotone, and a nonzero `COMPARE` of two sizes read
  this way is their order.
- The line. Every box is symmetric about `Re(s) = 1/2`. By the group entry 3 verifies, a zero off the
  line brings its mirror into the same box, and a symmetric box counting one holds a zero on the line.
- The walk. Up the strip from `t = 1`, between its own edges `Re(s) = 0` and `Re(s) = 1`: an empty box
  doubles the step, a crowded box splits into halves, and a box counting one is a zero. Each zero is
  then placed by sixteen bits, one pass per bit, in squares centred on the line.
- Positive control, with an answer from outside. `zeta(2)` equals `pi^2/6` at thirty places. Below
  `t = 123` the walk finds forty zeros, as Odlyzko's table `zeros1` has them, and each placed bracket
  holds the ordinate the table prints for it at nine places, read through
  `representation.exact.units`: `14.134725142` lies in `[14.13464355, 14.13476562]`, and
  `122.946829294` in `[122.94682312, 122.94683837]`. The run asks 56,570 values, the deepest point at
  sixteen places and the widest at `N = 64`, in five minutes on the host.
- Drawn null. With the integral of the rest, `N^(1-s)/(s-1)`, left out of both routes, the gap between
  them at `s = 1/2 + 20i` grows as `N` doubles, and no point is decided. With it, the routes agree at
  `N = 8`.
- The quadrant alone. Read by the signs of `Re` and `Im` only, without the magnitude sign and the
  chord, the walk counts the boxes `[24, 32]` and `[32, 40]` empty, where each holds two zeros. On
  `Re(s) = 0` zeta turns nearly once between two samples, and the shorter way round reads it backwards.
- The chord alone. Without the step verdict the box `[98, 102]` counts empty, where it holds two. Its
  edge on `Re(s) = 0` settles on three points while zeta turns nearly once between each pair, and the
  chords between values that land almost where they began are short. The derivative sees the turning.
- What it is not. Ten zeros on the line below `t = 50` is a computation at a height, and the field has
  verified far past it. It bears on the Riemann hypothesis exactly as far as every verification below a
  height does, and not at all past that height.

## Entry 5, 2026-10-02: the Gram points, and Gram's law as agreement at lag 2

`examples/0_experimental/exact_zeta_gram.py`, run to `t = 285` and exit 0, in a minute and a half on
the host. It computes the Riemann-Siegel theta function by truthy and falsy verdicts, places the Gram
points by it, and reads the sign of `Z` at each from the values entry 4 computes.

- The reading it is for. The sign of `Z(t)` at the Gram points is the reading the shift agreement
  detector and the null permutation identity are built for. Gram's law shows as agreement at lag 2.
  The null permutation needs 32 occurrences of each sign, about 64 Gram intervals, and both need the
  Riemann-Siegel theta function by truthy and falsy verdicts.
- The phase. `theta(t) = Im ln Gamma(1/4 + it/2) - (t/2) ln pi`, by Stirling's series after a shift
  of `M`, with `K` Bernoulli terms, every coefficient an exact rational. Two routes run, at
  `M = K = N` and at `2N`, and routes that disagree double `N`. Each arctangent is two series that
  must agree: Euler's, with pi from Euler's identity, and the Taylor series about `1/2`, with pi from
  Machin's. pi is held as its real and its operator, the floor at the places asked and
  `naturals.pi`, which is asked again for more.
- The Gram index. At a point it is `theta` over pi, decided where `theta` reads strictly between `i pi`
  and `(i + 1) pi`, each read toward zero at the same places. A reading of equal doubles the places.
  Up from `t = 10`, where `theta` increases, a cell holds as many Gram points as its ends' indices
  differ by. The walk finds 128 below `t = 285`, indices 0 to 127, each alone in its bracket, and
  places each by sixteen bits. It asks 5,198 values of `theta`, none deeper than eight places, none
  wider than `N = 4`.
- The sign of `Z`. `zeta(1/2 + it) = e^(-i theta) Z(t)`. Just below `g_n`, `Im zeta` has the sign of
  `Re zeta`, and just above it the opposite sign. This phase verdict ties `theta`, from Stirling, to
  the phase of `zeta`, from Euler-Maclaurin. A bracket is settled where the phase verdict holds at
  both ends, `Re zeta` has one nonzero sign at both, and entry 4's step verdict holds at both. Every
  sixteen-bit bracket settles on its first reading. The run asks 2,402 values of `zeta`, the widest at
  `N = 64`. The cut that a bracket not settled would take is written and has not run.
- Positive control, with an answer from outside. `g_0` to `g_15` against the table the Riemann-Siegel
  theta article on Wikipedia prints, read by a web fetch: each bracket holds its ten-place value,
  `17.8455995405` in `[17.8455810546, 17.8456420898]`. The same article reports Gram's law failing
  first at index 126. Here `(-1)^n Z(g_n)` is positive for `n` from 0 to 125, negative at 126, with
  `g_126` in `[282.4547119140, 282.4547424316]`, and positive at 127.
- Gram's law as agreement. The signs of `Z(g_n)` read as a sequence, 63 positive and 65 negative:
  agreement at lag 1 is 2 of 127, and at lag 2 is 125 of 126, by
  `measure.shift_agreement.exact_agreement`. Of 1,000 drawn orders of the same signs
  (`reference.shuffles.permuted`), none reaches 125 at lag 2, and the most any reaches is 80. The
  one failure costs one agreement at lag 2 and adds two at lag 1.
- Drawn null. With the Bernoulli terms left out of both routes, the gap between them at `t = 20` and
  eight places runs 27,385, 87,464, 210,132, 266,927, 155,769, 53,381 as `N` doubles from 1, and no
  index is decided. With them it runs 253, 1, 0.
- Failed hypothesis: Gram's law as a steer. The hypothesis is that the zero walk could step by Gram
  intervals, one zero in each, in place of its own halving. The zeros do not keep that pattern:
  `g_126` here has `(-1)^n Z(g_n)` negative, and the article reports Gram's law failing for about a
  quarter of Gram intervals in the long run. A walk steered to it is forced toward a pattern the
  zeros break and has to repair every interval that breaks it, which slows the walk it was meant to
  speed. That steer is not built and its cost is not measured here. The walk of entry 4 steers by
  its own verdicts, the halving that follows the zeros at every scale.
- What it is not. Gram's law is a pattern known to fail: the same article reports it failing, in the
  long run, for about a quarter of Gram intervals. It is a reading here and never a steer: the zero
  walk of entry 4 steers only by its own verdicts. Reading it to `t = 285` is a computation at a
  height and bears on nothing past it.

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
| a zero | a point where `zeta(s) = 0` in the strip, with no known closed form | "the exact intersection or topological union where the field's magnitude drops to absolute `0`" | the winding of zeta around a box symmetric about the line, read from the signs of `Re zeta`, `Im zeta` and `|Re zeta| - |Im zeta|`; and the real-valued function on the critical line Turing's method reads, where a sign change brackets a zero | the winding: run (entry 4), forty zeros, each placed by sixteen bits. The sign of `Z(t)` is read at the Gram points (entry 5); a sign change of `Z` as a bracket for a zero is wanted, not built. A zero has no known closed form in the constructors, and the most any computation does with one is bracket it (the precision tradition section) |
| the digits of a zero | Riemann-Siegel or Euler-Maclaurin, to a stated precision | "you don't get trapped by infinite digits or fake mathematical blowups" | Platt's interval computation, which isolated every zero below about `3 * 10^10` to `2^-102`, with directed rounding at each step | done by the field, rigorously, and reported from a web search (the precision tradition section). Exact arithmetic sharpens the values to zero width and leaves the zeros to the same enclosure |
| the zeros as a set | counted by `N(T) ~ (T / 2pi) log(T / 2pi) - T / 2pi` | "an infinite point cloud where every branch has an answer" | every zero up to a height `T` found by the winding count, and the count checked against `N(T)`; and the same count checked against `N(T)` by Turing's method | the winding count: run below `t = 123` (entry 4), forty, as the published table has them. Turing's method: wanted, not built. A count reaches a horizon and never all of them (the bounding function section) |
| the spacing law | Montgomery's pair correlation against the GUE | "which physicists have already proven mirrors the quantum energy levels of chaotic systems" | a proof of Montgomery's conjecture | not proven: entry 3 records it as a conjecture with strong numerical support, in the column labeled a dream |
| L* on zeta | not in the problem | "treat the zeta function like an unknown piece of hardware"; "probe the field's clock-cycle-like preferences" | L* learns a finite automaton from membership and equivalence queries. Zeta would need an alphabet and a membership query, and neither is named | wanted, not built. engine_table has no L* row; its M23 holds the refinement loop, not built |
| every zero on the line | the hypothesis | "the zeroes are structurally forced to exist only along that identity membrane" | a proof | open. Nothing here bears on it |

## The device program, and what it wants

Entry 4 runs one value at a time on the host. Every point in a pass is independent of every other,
and a pass is one sweep: each part below is a sweep over lanes, each reads the records the last
pass wrote, and each writes verdict fields the next one reads. The program runs on the device as
tessera jobs, as the sims do. The rows use the engine table's columns, and the M numbers are its
parts ([engine_table.md](../engine/engine_table.md)). No scale is written into the program: the
places, `N` and the widths come from the records.

| part | the algebra it holds to | does today | wants | tried, and what it gave | status | next |
|---|---|---|---|---|---|---|
| **Z1. The constants** | `ln n = k ln 2 + 2 artanh((n - 2^k) / (n + 2^k))` and `ln n = j ln 3 + 2 artanh((n - 3^j) / (n + 3^j))`, each a floor at its scale, and the two agreeing through `naturals._agree`. pi by Machin and Euler the same way. Each constant is held as its real and its operator: the floor at its places and the series that gives the next place. | On the host, in `representation.constants.naturals`, each `(n, digits)` asked once. | `ln n` and pi as record programs (M10) at the places the record carries, each with its second route and their agreement written as a field. The device has pi as `pi_tower` (M19), bracketed by Machin, and has no `ln`. A deeper pass extends a constant's series from the terms it holds. | The run to `t = 123` asks `ln n` for every `n` up to 128 at up to 36 digits, and both routes agree on every one: exit 0. | host only | the artanh series as a record program, checked lane for lane against `naturals` |
| **Z2. The powers** | `n^-s = exp(-sigma ln n) (cos(t ln n) - i sin(t ln n))`, and its derivative `-ln n n^-s`. exp by `x = r - k ln 2` with `0 < r <= ln 2`, a Taylor series in `r`, then a shift by `k` either way. cos and sin by taking whole turns of `2 pi` off, then one series. Every term is a floor at places plus `GUARD`, twenty digits. | On the host, one `(point, n)` at a time. | One lane per `(point, n)`, `n` from 1 to `2N`, the point and its places read from its record. A series runs while its term is nonzero: a lane whose term reads zero adds zero, and the sweep ends where the sum of every lane's term field is zero. The record machine's operations carry it (M10: product, sum, difference, absolute, compare, and the divisions). | On the host every power at sixteen places plus the guard is 120 bits, inside the record machine's 160-bit lanes, where it divides 4,096 lanes at once. | not built | exp, cos and sin as record programs over one sweep of lanes |
| **Z3. The sum and its tail** | Euler-Maclaurin cut at `N`: the head, the sum of `n^-s` for `n < N`, then `C N^-s`, with `C = N / (s - 1) + 1/2 + sum over k from 1 to N of B_2k / (2k)! s(s+1)...(s+2k-2) N^(1-2k)`, an exact complex rational. `C'` is carried beside it through the derivative of the rising product. Two routes, at `N` and `2N`, share the powers. Each of the eight values, `zeta` and `zeta'` from each route, real and imaginary, is read toward zero: its sign times the floor of its size, the guard dropped. | On the host. | `B_2k / (2k)!` built once on the host and read by every lane as a table (M10's table). The head as an exact sum over a point's lanes. `C` and `C'` per point at the width the record names: a lane too narrow refuses as a request error (M12) and never rounds. | `C` and `C'` measured on the host: about 340 bits at `N = 8`, about 2,160 at `N = 32`, and 6,733 to 6,871 at `N = 64` with `t` at sixteen places. At `N = 64` that is past the 2,048-bit lanes and past `ANCHOR_EXACT_LIMBS` at its 4,096-bit default. | not built | `C` per point on M1's ladder, multiply and Newton division, at the width read from `N` and the point's places |
| **Z4. The point verdicts** | Four fields per point: `agree = NOT(Re one - Re two) NOT(Im one - Im two)`, and `COMPARE` of `Re zeta` with 0, of `Im zeta` with 0, and of `|Re zeta|` with `|Im zeta|`. A point is decided where the product of `agree` and the three absolute signs is nonzero. Its eighth of a turn is `2q + ((1 - sign_size) / 2 + q) % 2`, with `q = (1 - sign_im) + (1 - sign_re sign_im) / 2`. An undecided point is asked again at `places (1 + agree)` and `N (2 - agree)`. | On the host, in `Steering.sweep`. | A record per point, holding the point's two pairs, its places, `N`, the four values and the four verdicts, written by the sweep and read by the next. `COMPARE`, product and absolute are record operations (M10). The points asked again are compacted from the field `NOT(decided)` by a sum over it. | The run to `t = 123` writes 56,570 values, the deepest at sixteen places and the widest at `N = 64`. | host only | the record's layout, and the compaction as one sweep |
| **Z5. The edge verdicts** | Per half of an edge: `NOT(places_a - places_c)`, the chord `COMPARE(min(|zeta_a|^2, |zeta_c|^2), |zeta_c - zeta_a|^2)`, and at each end `COMPARE(|zeta|^2 10^(2q), |zeta'|^2 |c - a|^2)`. The turn from `a` to `c` is `(d_c - d_a + 4) % 8 - 4`, and the edge's turns read end to end and through the midpoint agree or not. A settled edge is the product of the positive verdicts. A negative verdict puts the midpoint into the path, a zero doubles the places, and unequal places ask both ends at the deeper. | On the host, in `Steering.count`. | One lane per half edge, reading the two point records at its ends. The places each point is asked at next, and the midpoints put into the path, written as fields and compacted by a sum over them. The turns summed per box, an exact sum over the box's lanes. | The quadrant alone counts `[24, 32]` and `[32, 40]` empty, and the chord alone counts `[98, 102]` empty (entry 4). With the step verdict every box below `t = 123` counts as the published table has it. | host only | the half edge as a record program reading two records |
| **Z6. The walk and the placing** | An empty box doubles the step, a box counting one is a zero, a crowded box splits into halves. Each zero is placed one bit per pass by the lower square centred on the line counting one. | On the host, in `Steering.walk` and `Steering.place`. | Nothing on the device past Z1 to Z5. The host reads the counts per box from the device and writes the next pass's boxes; each pass is one sweep of Z2 to Z5. | Forty zeros below `t = 123`, each placed by sixteen bits, each bracket holding the published ordinate: exit 0, five minutes on the host. | host only | the host loop over device passes |
| **Z7. The job** | One device, one daemon; a job declares its bytes, is admitted on its standing, and its peak is kept under its signum (M14). | The program runs on the host and asks the device nothing. | The program as a tessera job, beside the sims: `sim_job_submit` before its first device allocation and `sim_job_release` at its end. The signum is the host BLAKE3 of the program's name and arguments, the height and the bits. The declaration is the bytes of a pass, read from the records the last pass wrote: the points asked, times `2N` lanes, times the width at places plus the guard, and the records. Growth past it is told back, and the next run with the same signum is asked against the kept peak. | none | not built | the job's submit and release around the host loop, with the declaration read from the records |
| **Z8. The phase** | `theta(t)` by Stirling's series after a shift of `M`, two routes at `M = K = N` and `2N` (entry 5). Each `arg(1/4 + k + it/2)` is an arctangent of a rational by Euler's series and by the Taylor series about `1/2`, agreeing. The Gram index at a point is `theta` over pi, decided where `theta` reads strictly between `i pi` and `(i + 1) pi`. | On the host, in `exact_zeta_gram.py`, each `(p, q, digits)` arctangent asked once. | One lane per `(point, k)`, `k` below the shift, each an arctangent series run while its term is nonzero, as Z2's series run. The Stirling terms per point as Z3's tail is, from the same table of `B_2k / (2k)!`. The index and its two verdicts written to the point's record, and the midpoint's index read by the next pass to cut a bracket. | To `t = 285`, 5,198 values of `theta`, none deeper than eight places, none wider than `N = 4`. | host only | the arctangent series as a record program beside Z1's |

## Open, not done

- Entry 4 counts below `t = 123`, one value at a time on the host, in five minutes. The device
  program and its wants are the table above, and none of it is built.
- Entry 5 reads `theta` and the Gram points on the host, and Z8 above is its device part, not built.
- Computing `zeta(s)` in the critical strip needs complex arithmetic and an accelerated method,
  Riemann-Siegel or Euler-Maclaurin. Entry 4 uses Euler-Maclaurin, and Riemann-Siegel is not built.
  A computation there is a numerical observation at the places it reads, never a statement about all
  zeros.
- Whether a non-trivial zero has a closed form in the constructors is a separate question from where
  it sits, and it is not addressed here.

## Withdrawn

Nothing withdrawn yet. The rail keeps this heading, and a later reader knows a pulled claim would
appear here with what killed it, instead of vanishing.
