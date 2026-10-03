# Analytic number theory workbook

**Purpose:** Record what the engine's exact arithmetic shows when it is pointed at analytic number
theory, one poke at a time, claiming nothing. **Scope:** `examples/0_experimental/exact_zeta_values.py`,
`examples/0_experimental/exact_zeta_zeros.py`, `examples/0_experimental/exact_zeta_gram.py`,
`examples/0_experimental/exact_zeta_riemann_siegel.py`, `examples/0_experimental/exact_zeta_arrival.py`,
`evidence/proofs/posits/proof_set_theory.py`, and this file.

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

## Entry 1: zeta at the even integers

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

## Entry 2: the set the values live in

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

## Entry 3: the symmetry of the zeros, and a dream kept in its column

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

## Entry 4: the zeros, counted and placed by truthy and falsy verdicts

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

## Entry 5: the Gram points, and Gram's law as agreement at lag 2

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

## Entry 6: the Riemann-Siegel formula, with time held as a real

`examples/0_experimental/exact_zeta_riemann_siegel.py`, run to `t = 285` and exit 0. It computes
`Z(t)` by the Riemann-Siegel formula as the Riemann-Siegel Formula page on MathWorld prints it, read
by a web fetch: `Z(t) = 2 sum over n <= N of n^(-1/2) cos(theta(t) - t ln n) + R(t)`, with
`R(t) = (-1)^(N-1) (t / 2pi)^(-1/4) sum c_k(p) (t / 2pi)^(-k/2)` and `c_0` to `c_5` from the printed
table, each a sum of derivatives of `Psi(p) = cos 2pi(p^2 - p - 1/16) / cos 2pi p` over powers of pi.
The walk, the placing and the signs of entry 5 take seven seconds on the host this way.

Where the formula binds, and what is released in its place:

| where it is bound | as the formula states it | released here | status |
| --- | --- | --- | --- |
| time | `t` a decimal, `N = floor(sqrt(t / 2pi))`, `p = sqrt(t / 2pi) - N`, and powers of `t / 2pi` | the steer is `u`, with `t = 2pi u^4` held as its real and its operator: pi's floor at the places asked, and `naturals.pi` asked again for more. `N = floor(u^2)`, `p = u^2 - N` exactly, and `(t / 2pi)^(-1/4 - k/2) = u^-(2k+1)`, an exact rational. No square root is taken and nothing is divided by `2pi`. The delta `p` runs between 0 and 1 and is never fixed | built |
| `Psi` | a quotient, whose denominator vanishes at `p = 1/4` and `p = 3/4`, where the numerator vanishes too | the pair of the numerator and the denominator, each a power series about `p`, never divided. With `d` the denominator's first coefficient, `Psi^(j)(p) / j! = r_j / d^(j+1)`, `r_j` by products alone, and every `c_k` carried times `d^16 pi^10`, which is never negative. Where `d` reads zero at the working places, both series start one coefficient later | built. `u = 1.5` sits at `p = 1/4` exactly, and its gap against Euler-Maclaurin is 0, 0 and 5 units at 2, 4 and 8 places |
| the powers of pi | `1 / pi^(2m)` in each `c_k` | multiplied through by `pi^10` | built |
| the count of terms | `R` cut at a fixed `K`, with Gabcke's bounds on the error (his thesis, Satz 3.2.2, read for entry 7) | the last printed term, `c_5 u^-11`, read against `Z` at each point at the places `Z` is read: a reading, recorded per point, and no bound | the reading is built. Every `C_n` is built exactly by Gabcke's generator (entry 7). `R` here still stops at `c_5`: summed to the series' own least term, as a verdict, it is wanted, not built |
| the two sums | `M = N`, about `(t / 2pi)^(1/2)`, with `R(s)` an exact contour integral in the approximate functional equation | not released: `R` is taken as its asymptotic series | wanted, not built |

- The verdicts at a point. `theta` by entry 5's two routes. `Z d^16 pi^10` read toward zero at the
  places asked, and a reading of zero doubles the places. The work runs two guards deep and one is
  dropped.
- The walk. Entry 5's walk and placing, stepping in `u` from `1.2` with `theta` read at `2pi u^4`.
  It finds 128 Gram points below `t = 285`, indices 0 to 127, each alone in its bracket, and places
  each by sixteen bits in `u`, asking 5,108 values of `theta`. A bracket is settled where `Z` has one
  nonzero sign at both ends, and every bracket settles on its first reading: 470 values of `Z`, the
  deepest at 64 places, the main sum at most six terms.
- Positive control, with answers from outside. `g_0` to `g_15` from the table the Riemann-Siegel theta
  article on Wikipedia prints, each within `[2pi lo^4, 2pi hi^4]` by multiplication: `2 U^4` times
  pi's floor, and times the floor plus one, against the published value. `(-1)^n Z(g_n)` is positive
  for `n` from 0 to 125, negative at 126, with `g_126` in `u` in `[2.5893588321, 2.5893588792]`, and
  positive at 127, as the same article reports and as entry 5 reads by Euler-Maclaurin.
- `Z` against Euler-Maclaurin. `Re e^(i theta) zeta(1/2 + it)` by entry 4's two routes at the same
  real `t`, the gap in units of the last place at 2, 4 and 8 places:

  | `u` | `t` | with `R` | `R` left out |
  | --- | --- | --- | --- |
  | 1.2 | 13.02 | 0, 0, -281 | -33, -3,282, -32,823,842 |
  | 1.5 | 31.79 | 0, 0, 5 | 33, 3,371, 33,704,797 |
  | 1.8 | 65.92 | 0, 0, -1 | -29, -2,855, -28,550,818 |
  | 2.1 | 122.13 | 0, 0, 0 | 19, 1,897, 18,968,282 |
  | 2.4 | 208.35 | 0, 0, 0 | -21, -2,119, -21,190,339 |
  | 2.6 | 286.98 | 0, 0, 0 | 19, 1,957, 19,569,222 |

  The last term `c_5 u^-11` at 8 places reads -187, 71 and -10 units at `u` = 1.2, 1.5 and 1.8,
  and 0, 0 and -1 from `u = 2.1`: below `u = 2.1` the gap at 8 places is the series' own reach at
  that `t`. At every one of the 256 settled bracket ends, `Z` reads past `c_5 u^-11`.
- Drawn null. With `R` left out, the gap is 0.19 to 0.33 at every `u` shown, and the sign of
  `(-1)^n Z(g_n)` differs from the one with `R` at `n` = 33, 62, 70, 90, 105, 113 and 126.
- The cost. One value of `Z` takes 5 to 80 milliseconds on the host at 2 to 32 places. At
  `u = 2.1` and 8 places it takes 8 milliseconds against 2.6 seconds by Euler-Maclaurin, and at
  `u = 2.6`, 6 milliseconds against 18.4 seconds.
- What it is not. An asymptotic series read at the places it is read, below a height. Agreement
  with Euler-Maclaurin at eight places is two computations meeting, and the sign of `Z` at a Gram
  point is a reading there. It bears on nothing past `t = 285`.

## Entry 7: every C_n, where each vanishes, and the seam between the cells

`examples/0_experimental/exact_zeta_riemann_siegel.py`, the same run as entry 6, exit 0. Three papers
were read for it, page by page, from copies here:
- Siegel, "Über Riemanns Nachlaß zur analytischen Zahlentheorie" (1932), in the Barkan and Sklar
  translation;
- Berry, "The Riemann-Siegel expansion for the zeta function: high orders and remainders", Proc. R. Soc.
  Lond. A 450 (1995), 439-462;
- Gabcke, "Neue Herleitung und explizite Restabschätzung der Riemann-Siegel-Formel", dissertation,
  Göttingen 1979, in the re-set copy whose footnotes and references run to 2011.

What they say that bears on this entry:

- Siegel replaces the saddle `xi = (s - 1) / (2 pi i m)` by `eta` because `m` must be an integer
  (p. 279), and that integer makes the terms depend on `t` discontinuously (p. 285).
- Gabcke, p. 54: where `t_M = 2pi M^2` and `N` steps from `M - 1` to `M`, `R_K(t)` is not continuous,
  and its jump is at most `2 c(K) t_M^(-(2K+3)/4)`.
- Gabcke, p. 55, Satz 3.2.2: for `t >= 200`, `|R_0| < 0.127 t^(-3/4)` up to `|R_9| < 1837 t^(-21/4)`,
  and the bounds are optimal for `K <= 4`. On p. 58, numerical study suggests `|R_10|` is
  overestimated by a factor of about `10^6`.
- Gabcke, foreword, p. v: whether `C_0` with `|R_0| < 0.127 t^(-3/4)` always decides the sign of `Z`
  "liegt aber wohl außerhalb der heutigen mathematischen Möglichkeiten". Footnote 3 there says the
  error can change sign inside a cell, and it is averaged over `[2pi N^2, 2pi (N + 1)^2]`.
- Gabcke, introduction, footnote 9: the main sum alone has two complex conjugate zeros near
  `t = 221.08`, where `Z` has two real zeros.
- Gabcke, pp. 58-59, section 3.3. Siegel writes (p. 285) that it is not trivial that `|R_K(t)|` does
  not go to zero as `K` grows with `t` fixed. Lower bounds `|C_2n(z)| >= w_2n` would prove it, and they
  fail: `C_2n` for `2n` = 4, 8 and 10 each has one simple zero in `0 < z < 1`, and only `|C_2n| >= 0`
  holds there. At `t = 2pi M^2` the series splits into two power series of radius 0, and the
  divergence holds at those `t`. Footnote 7 adds that a proof has since appeared, Berry 1995.
- Gabcke, p. 53: the bound of Satz 3.1.3 comes only from expanding `g(tau, z)` in powers of `tau`. In
  powers of `z` the coefficients would be polynomials in `tau`, with "fast unüberwindlichen
  Schwierigkeiten".
- Berry: `C_r` has its least term near `r* = 2pi t`, with a remainder of order `exp(-pi t)` across a
  Stokes line. His Appendix B gives `C_4l(1)` and `C_(4l+2)(1)` in closed form, from Gabcke's
  argument by continuity.

Every `C_n`, held as its real and its operator:

- **The generator.** With `z = 1 - 2p` and `F(z) = Psi(p)`, Gabcke's generator (his Table III) gives
  `C_n(z) = 2^(-2n) sum over k of d_k^(n) F^(3n-4k)(z) / ((3n - 4k)! pi^(2n-2k))`.
  - The `d` follow `d_k^(n+1) = (3n + 1 - 4k)(3n + 2 - 4k) d_k^(n) + d_(k-1)^(n)`, except
    `d_3l^(4l) = lambda_l`.
  - The `lambda` follow `(l + 1) lambda_(l+1) = sum 2^(4k+1) |E_(2k+2)| lambda_(l-k)` on the Euler
    numbers.
  - Every `d` is an integer.
- **F's coefficients.** `F` is entire and even. Its coefficient of `z^(2j)` comes from the product of the
  series of `cos(pi z^2 / 2 + 3pi/8)` and of `sec(pi z)`. It is a sum of rationals times
  `pi^(2j - m)`, times `sin(pi/8)` or `cos(pi/8)`, which are `sqrt(2 -+ sqrt 2) / 2`.
- **Held exactly.** Each `C_n` is held exactly, and only reading it at a point asks for digits.
- **A reading at a point.** It sums the Taylor series on `count` and `2 count` terms, the second at
  twice the extra digits, and the two must agree. The terms of the `sec` series grow as `4^j` and cancel
  to `F`'s: the extra digits grow with `count`.
- **Controls.**
  - `C_0` to `C_5` match MathWorld's `c_0` to `c_5` rational for rational.
  - `d_k^(8)` matches Gabcke's Table II, and `lambda_1` to `lambda_4` = 2, 82, 10,572 and 2,860,662,
    as his p. 77 prints them in primes.
  - `C_0(1)` to `C_10(1)` against the sum row of his Table IV at 50 places are apart by -2, 3, -3,
    -3, -1, 0, -2, 2, 1, 4 and -4 units of the 50th place. His Table IV and Table V sum rows, two
    routes to the same `C_n(1)`, differ by up to 5 units there, and that is the bar.
  - The controls, the zeros below, the fine sweep and the seam take 11.5 seconds on the host
    together.

Where each vanishes. The zeros of `C_n` on `0 < z < 1`:
- **How they are read.** They are the sign changes read on `2^m` and `2^(m+1)` parts, `m` from 6 and
  growing until the two counts agree, and each is halved to `2^-128`.
- **Odd `C_n`.** An odd `C_n` is zero at `z = 0` by parity, and its sign just past 0 is the sign of
  its `z` coefficient.
- **Where in a cell.** A zero `z` gives `p = (1 - z) / 2` and `(1 + z) / 2`. The term `C_n u^-(2n+1)`
  vanishes at `t = 2pi (N + p)^2` in every cell `N`.

| `C_n` | zeros | `z` | `p` in a cell |
| --- | --- | --- | --- |
| 0, 2, 5, 6, 7, 9, 11, 13, 15, 16, 17, 19, 20, 21, 24 | 0 | | |
| 1 | 1 | 0.803175201847263648200143847748 | 0.098412399076, 0.901587600923 |
| 3 | 1 | 0.710803418901810534756142447745 | 0.144598290549, 0.855401709450 |
| 4 | 1 | 0.980281968817316802120874647142 | 0.009859015591, 0.990140984408 |
| 8 | 1 | 0.997036830589145376737869912457 | 0.001481584705, 0.998518415294 |
| 10 | 1 | 0.299816770654618333121409389802 | 0.350091614672, 0.649908385327 |
| 12 | 2 | 0.616207504929399468039218038437 and 0.998443905470315328716740114168 | 0.191896247535, 0.808103752464 and 0.000778047264, 0.999221952735 |
| 14 | 1 | 0.993917155860395878889175207422 | 0.003041422069, 0.996958577930 |
| 18 | 1 | 0.999641199400873460953351005305 | 0.000179400299, 0.999820599700 |
| 22 | 1 | 0.999921721380642164402814225180 | 0.000039139309, 0.999960860690 |
| 23 | 1 | 0.588456350810734142509251472159 | 0.205771824594, 0.794228175405 |

- **Against Gabcke.** One simple zero each in `C_4`, `C_8` and `C_10`, as he reports on p. 59.
- **The other zeros.** `C_12` has two, and the zeros of `C_4`, `C_8`, `C_12`, `C_14`, `C_18` and
  `C_22` sit within `0.01` of `z = 1`, the integer `x` where the cells meet.
- **The fine sweep.** Two zeros between neighbors of the coarse grid would not show on it. On
  `[63/64, 1]` at `2^14` and `2^15` parts the counts agree for every `C_n` to `C_24`. They read one
  for `C_8`, `C_12`, `C_14`, `C_18` and `C_22`, and none for the rest.
- **What the table is.** A reading on the grids named, at the places read. It is not a count proven
  complete.

The seam:
- **What it is.** Where `x` crosses `nu + 1`, `S` gains a term and `R` changes cell (entry 6's
  header). The rest is the jump of the terms `R` leaves out, `-2 (-1)^nu` times the sum over even
  `k >= 6` of `C_k(1) u^-(2k+1)`.
- **Against the exact `C_k(1)`.** Read at 20 places against that sum for even `k` from 6 to 16, the
  ratio is 1.00000000 at `x` = 2, 3, 4, 6 and 8, and 0.99999999 at 5, 7 and 9. The seam is the left-out
  terms to eight places.
- **Fewer terms.** With `k` only to 12, through Berry's Appendix B, the ratio at `x = 2` read
  1.0000006.

The triangle between the two pairs (entry 6's header):
- **The sides.** Over each cell, `D = Z_RS - Z_EM` and `E = S - R` give three sides: `a = int |D|`,
  `b = int |E|` and `c = int |(D, E)| = b + delta`.
- **What it is read by.** The excess `kappa = (c^2 - a^2 - b^2) / a^2` and the angle
  `cos gamma = -kappa a / 2b`.
- **How it is run.** Euler-Maclaurin's `C` comes from the device (Z3), with `triangle first last`.
- **Where S and R cross.** There `E` is zero, and `delta`'s integrand is a spike of height `|D|` and
  width `|D / E'|`. In cell 4, the crossings read from `p = 0.686` to `0.990` sit about 0.03 apart.
  Each has `|D|` between `1.2 e-10` and `9.9 e-10`, `|E'|` between 80 and 240, and a width of about
  `10^-12` of `p`. A grid would need `2^36` to `2^40` parts to see one.
- **The growth.** The trapezoid on a spike grows by about `(D^2 / |E'|) ln 2` per crossing at every
  doubling of the parts. It stops only where the step reaches the spike's width, and that doubling is
  what made each cell take longer and longer.
- **The relation.** Each spike is held as its relation instead. With `D0 = D(p0)` and `k = |E'(p0)|`,
  it is `g(u) = D0^2 / (sqrt(D0^2 + k^2 u^2) + k |u|)`, `u = p - p0`. Its integral from 0 to `L` is
  `(L D0^2 / (sqrt(D0^2 + k^2 L^2) + kL) + (D0^2 / k) asinh(kL / |D0|)) / 2`, exactly. `delta` is the
  sum of those and the trapezoid of `f` less every `g`, which no longer grows.
- **Finding the crossings.** They are `E`'s sign changes, from Riemann-Siegel alone, each halved to
  `2^-64`.
- **Controls on the relation.** On a spike wide enough to resolve, `D0 = 10^-3`, `k = 2` and
  `L = 0.7`, the trapezoid's gap from the closed form falls by exactly 4 per doubling, from `2^16` to
  `2^19` parts. `ln` by the two artanh routes meets the logarithm of entry 4 at every digit.

| cell | `a` | `b` | `c - b` | `kappa` | `a / b` | `cos gamma` | parts | points | seconds |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 1.8170 e-6 | 1.7444 | 5.534 e-12 | 4.8 | 1.042 e-6 | -2.52 e-6 | `2^6` | 67 | 70 |
| 2 | 4.2946 e-8 | 1.7378 | 1.047 e-14 | 18.7 | 2.471 e-8 | -2.3 e-7 | `2^8` | 332 | 120 |
| 3 | 4.7616 e-9 | 1.6885 | 1.626 e-16 | 23.2 | 2.820 e-9 | -3 e-8 | `2^9` | 858 | 109 |
| 4 | 9.3134 e-10 | 1.6461 | 5.768 e-18 | 20.8 | 5.65 e-10 | -5.910 e-9 | `2^10` | 1,908 | 147 |
| 5 | 2.5325 e-10 | 1.6879 | 3.642 e-19 | 18.1 | 1.50 e-10 | -1.363 e-9 | `2^10` | 2,961 | 883 |

- **The angle.** In every cell the triangle is a needle, `a` against `b`, and its angle is past right
  by an amount that reads nonzero at the places shown.
- **The device.** The device equals the host on every sweep.
- **The grid alone, overturned.** Before the relation, the trapezoid alone read cells 1 to 3 at
  `kappa` = 1.1, 10.8 and 2.3. The parts were `2^4`, `2^13` and `2^6`, taking 98, 1,020 and 268
  seconds. Those grids agreed at 2^m and 2^(m+1) parts while both missed every spike, and the
  readings are kept here with what overturned them.
- **A prediction, overturned.** From those readings, `kappa` was predicted high in cell 4 and low in
  cell 5. Held exactly, `kappa` reads 4.8, 18.7, 23.2, 20.8 and 18.1 across cells 1 to 5, and the
  prediction fails with the readings it came from.
- **The fault that stopped cells 4 and 5.** `d^16 pi^10` reads small near `p = 1/4`. The first change
  to `rs_at` counted the digits that multiplier lost and asked again until it lost none. That count is
  a property of `p` and not of the work, and it never reached zero. `rs_at` now sets the work once to
  the digits asked, the guard and the digits lost.
- **Cell 5's time.** It takes six times cell 4's, against 1.6 times the points. What grows there is
  not yet read.

What it is not. Each `C_n` is exact, and each zero is a bracket read at the places named, a reading
on a grid, never a count proven complete. The seam and the triangle are readings below `x = 9` and in
five cells. None of it bears on the zeros of `Z` or on the hypothesis.

## Entry 8: the triangle's dimension, and what each wave lands in at its boundary

`examples/0_experimental/exact_zeta_riemann_siegel.py` for the dimension, and
`examples/0_experimental/exact_zeta_arrival.py` with its device program `exact_zeta_arrival.cu` for
the boundaries.

**The terms, as asked.** "it's a coordinate system, dimension, and time." Read here, without a
claim that it is the reading meant:
- the coordinates are the triangle's three sides;
- the dimension is each side's scaling exponent between neighboring cells,
  `ln(side_nu / side_(nu+1)) / ln(x_(nu+1) / x_nu)` with `x` at each cell's midpoint;
- the time is `t`, walked cell by cell.

**The dimension.** With `R` through MathWorld's `c_5`, the exponent of `a` reads 7.33, 6.54, 6.49 and
6.49 between cells 1 to 5. That is `x^-6.5 = u^-13`, the size of the first term `R` leaves out,
`c_6 u^-13`. The exponent of `b` reads 0.01, 0.09, 0.10, -0.13 and 0.20 between cells 1 to 6, from
`b`'s limit on `2^11` and `2^12` parts, each within `8 e-7` of the limit on `2^10` and `2^11`. The
exponent of `delta` reads 12.3, 12.4, 13.3 and 13.8.

`|E|` has a corner at each crossing of `S` and `R`, 25 of them in cell 4, and `|D|` one. The trapezoid
takes each corner by the line through its two points. With that, `a` and `b` settle as the grid halves, the
gap shrinking four times a halving. Without it, `b` over cell 4 reads 1.64704 on `2^8` parts and
1.64615 on `2^10`, a step of `9 e-4` from the grid alone, where the cut moves it `4 e-11`.

**The cut test.** If `a`'s dimension is the cut, then `R` through `C_K` moves it to `(2K + 3) / 2`. `R`
through `C_K` from the exact curves of entry 7 equals MathWorld's `R` at `K = 5` to 0 units at 30
digits, `S` too, at five points that include `p = 1/4`. Through `C_6`, the exponent of `a` reads 8.22,
7.90, 7.75 and 7.67 between cells 2 to 6, against 7.5. Through `C_8` it reads 10.62, 10.13, 9.91 and
9.79, against 9.5. Through `C_10` it reads 13.11, 12.46, 12.13 and 11.95, against 11.5. All three come down onto the cut from above and none goes below it in these cells.

**The omitted curves.** `a` is predicted from the exact curves alone, with no Euler-Maclaurin and no
device: `|sum C_k(1 - 2p) x^(-k - 1/2)|` over the cell for `k` from `K + 1` to `K + 3`, the terms `R`
leaves out (`omitted first last K`). It needs no grid. With `z = 1 - 2p` and `X = nu + 1/2`, each
weight is `x^(-k - 1/2) = X^(-1/2) (2 / (2 nu + 1))^k (1 - z / (2X))^(-k - 1/2)`, a series in `z`
with rational coefficients. The integrand is then one power series in `z` times `X^(-1/2)`. Its zeros
are halved to `2^-(4 (digits + GUARD))`, and between them the integral is the antiderivative's
difference, term by term. The series at `n` and `2n` terms agree at 24 places, and the run at 60
places agrees with it at all 24. The trapezoid on the same integrand closes on it four times a
halving, `2.8 e-6`, `7.0 e-7` and `1.7 e-7` on `2^9` to `2^11` parts over cell 4 through `C_6`.
Each cell takes a quarter of a second where the triangle takes hours. Between cells, the exponent
it gives against the one measured:

| `R` through | exponent from the omitted curves | measured |
|---|---|---|
| `C_5`, five curves | 7.265, 6.536, 6.493, 6.490 | 7.33, 6.54, 6.493, 6.489 |
| `C_6` | 8.218, 7.895, 7.750, 7.673 | 8.222, 7.896, 7.751, 7.673 |
| `C_8` | 10.607, 10.133, 9.909, 9.786 | 10.617, 10.134, 9.910, 9.786 |
| `C_10` | 13.089, 12.451, 12.132, 11.950 | 13.106, 12.455, 12.134, 11.951 |

Past the measured cells it gives, between cells 5 to 9, 6.491, 6.494, 6.496 and 6.497 through
`C_5`; and between cells 6 to 9, 7.627, 7.597 and 7.576 through `C_6`, 9.711, 9.662 and 9.628
through `C_8`, and 11.836, 11.760 and 11.707 through `C_10`. Only between cells 1 and 2 do the
curves fall short, by 0.07, where `x` is 2 and the series is at its weakest.

Through `C_6`, `C_8` and `C_10` the omitted curves have one zero in every cell from 1 to 9. Through
`C_5` they have one in cells 1 to 5 and none from cell 6 on. `C_6`, the curve leading them, has
none of its own.

**Hypotheses, quoted, with what tests them.**
- "it scrapes its boundary and that pops its dimensionality up". The excess over `(2K + 3) / 2` is
  0.72, 0.40, 0.25 and 0.17 between cells 2 to 6 through `C_6`, and 1.12, 0.63, 0.41 and 0.29 through
  `C_8`, larger at every cell, and 1.61, 0.96, 0.63 and 0.45 through `C_10`. The omitted curves give each
  of them: the shape of `|C_(K+1)|` with its next two curves, weighted by `x^(-k - 1/2)` across a cell
  of width 1.
- "It's like a cyclical spring". Through `C_5` the exponent goes below 6.5 at cell 3 and comes back
  toward it from below across cells 5 to 9, as the omitted curves give it. It does not go back above
  6.5 in those cells. Through `C_6`, `C_8` and `C_10` it stays above the cut.
- "for C8 it looks like that is the pressure that escaped the other dimension reducing its
  potentiality to field mean". From `C_6` to `C_8` on the same grid, `b` falls with `a` in every
  cell, by 0.68, 0.54, 0.29, 0.28 and 0.18 of `a`'s fall over cells 2 to 6.
- "we can put the triangle in pi and trace its origin points to derive angular momentum". Each
  triangle's angle opposite `c` is a right angle less than `1 e-7` off, which puts `c` on the
  diameter of its circle. By the law of cosines the amount off is `kappa / 4` times `2a / c`, the
  angle `a` takes from the center: what the circle holds is `kappa`, which the three sides already give.

**The ball.** "the ball sticks to the triangle, and the triangle plane is spatially unconstrained so
it can be upside down, we are looking at an object on a plane in a sphere"; "that gives smooth
natural movement for the complex integral that is the curve, for all degrees of freedom n". Read with
`sphere first last K m`, over cells 2 to 6 through `C_10` on `2^8` parts:
- **The sphere.** Each wave `z_n = e^(i theta) n^-s` is one complex coordinate of radius `n^(-1/2)`,
  and the point `(z_1, ..., z_nu)` keeps `|z|^2 = H_nu`, the harmonic number. It holds within 68
  units of `10^-44` at every point.
- **The turning.** Wave `n` turns at `theta'(t) - ln n`, with mass `1 / n`. `theta'` is
  `Re psi(1/4 + it/2) / 2 - ln(pi) / 2`, `psi` by Stirling's series in two routes that agree, and it
  meets `theta`'s central difference to 28 places at `t` = 25, 100 and 1000.
- **The boundaries.** Wave `n` joins at `t = 2pi n^2` turning at `-1 / (48 t^2)` to its first
  term: `-3.299 e-5`, `-6.515 e-6`, `-2.061 e-6`, `-8.443 e-7` and `-4.072 e-7` for `n` = 2 to 6. The
  angular momentum `L = sum (theta' - ln n) / n` steps there by that over `n`, `2.2 e-6` at `n = 3`,
  and the energy `sum (theta' - ln n)^2 / 2n` by its square over `2n`, `7 e-12`.
- **The shadows.** `Z = 2 Re W + R`, with `W` the sum of the waves. `Z` changes sign 9, 17, 27, 38 and
  49 times in cells 2 to 6, the same on `2^9` parts. With the three zeros below `8 pi` that is 143 to
  `t = 98 pi`, as the zero count `N(T)` gives at 307.9. `E` changes sign 8, 13, 25, 28 and 49 times,
  the triangle's crossings, and `D` once a cell.
- **The sideways shadow.** `D x^11.5` is one curve across the cells, changing sign with each and of
  size 6.78, 6.52, 6.43, 6.39, 6.37 and 6.35 `e-7` at `x` = 2 to 7, the same on either side of each
  boundary to three figures.

**The boundaries.** The main sum is the waves `m^(-1/2) e^(i(theta - t ln m))`.
- **Where each wave joins.** In the frame `e^(i theta)` turns, wave `m` spins at `ln(x / m)`, still at
  `x = m`, where it joins the sum, at `t = 2pi n^2` for `n = m`.
- **Its angle there.** The arriving wave's phase there is `-pi n^2 - pi / 8` to `theta`'s first terms:
  `-pi / 8` for even `n` and `pi - pi / 8` for odd. Read at every boundary to `n = 1600`, it matches
  that to a sine of `8.3 e-4` at most, at the smallest `n`.
- **What it lands in.** The waves already there stand at `2pi n^2 ln m` modulo a turn, and the
  logarithms of the primes are linearly independent over the rationals.
- **The reading.** At each boundary, the angle between the arriving wave and the sum of the waves
  already there.

**The relation, on the device.** Along `n`, wave `m`'s phase `n^2 ln m` has the constant second
difference `2 ln m`.
- **One lane a wave.** Each lane steps from one boundary to the next by `u <- u r` and `r <- r q`, at
  the scale `2^62`.
- **The seeds.** At a window's first boundary every seed is completely multiplicative in `m`. Only
  the primes ask for a cosine and a sine, and each composite is a product over its least prime factor.
- **The sum.** Each boundary is summed across its lanes by `cycle_record_sum`, the exact sum across
  lanes built for this. It accumulates every limb into its own column, and merges and rounds nothing.
- **The mean.** Each boundary's unit reading goes into a tally, and the mean at every boundary is
  tally over run, an exact rational.
- **The spread.** It is read as `|tally|^2 / (run S^2)`: `run` where every reading points one way,
  near 1 for independent angles.

**Controls.**
- **The control window.** In a window from `n0 = 0`, the device's sum at every 17th boundary meets
  the direct exact sum on the host within 16,654 units of `2^-62`, inside the drawn bar of `2^-40`.
- **Each window's own check.** At the first and last boundary of each window, the device's sum
  meets the direct exact sum on the host within the bar. The gaps, in units of `2^-62`, are 491 and
  772,737 at 1000; 4,988 and 1,483,898 at 10,000; 49,994 and 1,101,445 at 100,000; and 498,988 and
  734,973 at 1,000,000. The last boundary carries a window's stepped floors, about `3 e-13` at most.
- **The port check.** The host's records of every window's first sweep equal the device's word for
  word.
- **The spread, by a second route.** Over the window at 1000, the spread at runs 16, 64, 256 and
  1024 reads 4.2482, 2.9868, 0.5102 and 0.1521. The angles read from direct host sums in floating
  point give 4.2482, 2.9868, 0.5102 and 0.1522.

| window | waves | spread at run 16 | 64 | 256 | 1024 | device seconds |
| --- | --- | --- | --- | --- | --- | --- |
| 1000 to 2023 | 2,024 | 4.2482 | 2.9868 | 0.5102 | 0.1521 | 1.0 |
| 10000 to 11023 | 11,024 | 0.8661 | 0.1571 | 0.4037 | 1.2314 | 1.5 |
| 100000 to 101023 | 101,024 | 0.3049 | 3.1449 | 0.6269 | 0.4733 | 4.4 |
| 1000000 to 1001023 | 1,001,024 | 3.6411 | 4.5746 | 0.9102 | 0.0953 | 31.9 |

**What the table shows.**
- **Spread around the circle.** The readings go all the way around, and by run 1024 no window holds
  one direction.
- **The spread at run 1024.** Three windows read below 1, more even than independent angles, and one
  above. Four windows do not make a trend.

**What it is not.** These are readings of angles at boundaries, in four windows, at the places read.
Whether the angles are equidistributed, and how evenly, is a question about all `n`, and none of it
bears on the zeros of `Z` or on the hypothesis.

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

Entries 4 to 6 run on the host, in Python, one value at a time, apart from Z3's coefficient `C`,
which entry 6's triangle sweeps on the device. Every point in a pass is independent of every other,
and a pass is one sweep: each part below is a sweep over lanes, each reads the records the last
pass wrote, and each writes verdict fields the next one reads. A program is a list of record steps;
keymath imprints it, the scheduler lays it out, the record compiler emits it for the device, and it
runs as a tessera job ([prg_sch/README.md](../../../src/c/engine/prg_sch/README.md)). The same
program on the host, from the exact integer library, is its port check. The rows use the engine table's columns, and the M numbers are its
parts ([engine_table.md](../engine/engine_table.md)). No scale is written into the program: the
places, `N` and the widths come from the records.

| part | the algebra it holds to | does | wants | tried, and what it gave | status | next |
|---|---|---|---|---|---|---|
| **Z1. The constants** | `ln n = k ln 2 + 2 artanh((n - 2^k) / (n + 2^k))` and `ln n = j ln 3 + 2 artanh((n - 3^j) / (n + 3^j))`, each a floor at its scale, and the two agreeing through `naturals._agree`. pi by Machin and Euler the same way. Each constant is held as its real and its operator: the floor at its places and the series that gives the next place. | On the host, in `representation.constants.naturals`, each `(n, digits)` asked once. | `ln n` and pi as record programs (M10) at the places the record carries, each with its second route and their agreement written as a field. The device has pi as `pi_tower` (M19), bracketed by Machin, and has no `ln`. A deeper pass extends a constant's series from the terms it holds. | The run to `t = 123` asks `ln n` for every `n` up to 128 at up to 36 digits, and both routes agree on every one: exit 0. | host only | the artanh series as a record program, checked lane for lane against `naturals` |
| **Z2. The powers** | `n^-s = exp(-sigma ln n) (cos(t ln n) - i sin(t ln n))`, and its derivative `-ln n n^-s`. exp by `x = r - k ln 2` with `0 < r <= ln 2`, a Taylor series in `r`, then a shift by `k` either way. cos and sin by taking whole turns of `2 pi` off, then one series. Every term is a floor at places plus `GUARD`, twenty digits. | On the host, one `(point, n)` at a time. | One lane per `(point, n)`, `n` from 1 to `2N`, the point and its places read from its record. A series runs while its term is nonzero: a lane whose term reads zero adds zero, and the sweep ends where the sum of every lane's term field is zero. The record machine's operations carry it (M10: product, sum, difference, absolute, compare, and the divisions). | On the host every power at sixteen places plus the guard is 120 bits, which four 32-bit limbs hold, 128 bits. The exact limb arithmetic is a power-of-two count of 32-bit limbs, and its width doubles with no ceiling (`exact_integer_widths.h`). | not built | exp, cos and sin as record programs over one sweep of lanes |
| **Z3. The sum and its tail** | Euler-Maclaurin cut at `N`: the head, the sum of `n^-s` for `n < N`, then `C N^-s`, with `C = N / (s - 1) + 1/2 + sum over k from 1 to N of B_2k / (2k)! s(s+1)...(s+2k-2) N^(1-2k)`, an exact complex rational. `C'` is carried beside it through the derivative of the rising product. Two routes, at `N` and `2N`, share the powers. Each of the eight values, `zeta` and `zeta'` from each route, real and imaginary, is read toward zero: its sign times the floor of its size, the guard dropped. On the device `C` is carried at a fixed scale `S` as `tau_1 = s / 12N` and `tau_k = tau_(k-1) (s + 2k - 3)(s + 2k - 2) rho_k`, `rho_k = B_2k (2k - 2)! / (B_(2k-2) (2k)! N^2)`. Every term sits near the scale, each `tau` wrapped to a width from a bound on it. | `C` on the device for entry 6's triangle: `exact_zeta_tail.cu`, one lane a point, 35 steps a term, the shared record holding `S`, `S / 2` and every `rho_k S`. The head, `C'` and entry 4's walk stay on the host. | `B_2k / (2k)!` built once on the host and read by every lane as a table (M10's table). The head as an exact sum over a point's lanes. `C` and `C'` per point at the power-of-two width the record names, doubled where the value needs more: a lane too narrow refuses as a request error (M12) and never rounds. | `C` and `C'` measured on the host: about 340 bits at `N = 8`, about 2,160 at `N = 32`, and 6,733 to 6,871 at `N = 64` with `t` at sixteen places. Each takes the power-of-two width that holds it: 16 limbs, 512 bits, at `N = 8`; 128 limbs, 4,096 bits, at `N = 32`; and 256 limbs, 8,192 bits, at `N = 64`. The exact rational spends 98 percent of a value's time in gcd reductions, 3.5 of 3.57 seconds at `t = 190` and 21 places. On the device, at `N` from 1 to 64 over 128 points, the records equal the host's run of the same program word for word at every `N`, and `C` meets the exact rational at its own relative precision, 3 parts in `10^37` at `N = 64`. At `N = 64` the program is 2,224 steps in a file of 92 limbs, and 128 lanes sweep in 5.5 milliseconds once it is compiled; a launch costs about 0.4 seconds of its own. Fed by it, Euler-Maclaurin meets the host's to one unit at 21 places. | `C` built and run | the head's powers (Z2) in the same job, and both routes in one launch |
| **Z4. The point verdicts** | Four fields per point: `agree = NOT(Re one - Re two) NOT(Im one - Im two)`, and `COMPARE` of `Re zeta` with 0, of `Im zeta` with 0, and of `|Re zeta|` with `|Im zeta|`. A point is decided where the product of `agree` and the three absolute signs is nonzero. Its eighth of a turn is `2q + ((1 - sign_size) / 2 + q) % 2`, with `q = (1 - sign_im) + (1 - sign_re sign_im) / 2`. An undecided point is asked again at `places (1 + agree)` and `N (2 - agree)`. | On the host, in `Steering.sweep`. | A record per point, holding the point's two pairs, its places, `N`, the four values and the four verdicts, written by the sweep and read by the next. `COMPARE`, product and absolute are record operations (M10). The points asked again are compacted from the field `NOT(decided)` by a sum over it. | The run to `t = 123` writes 56,570 values, the deepest at sixteen places and the widest at `N = 64`. | host only | the record's layout, and the compaction as one sweep |
| **Z5. The edge verdicts** | Per half of an edge: `NOT(places_a - places_c)`, the chord `COMPARE(min(|zeta_a|^2, |zeta_c|^2), |zeta_c - zeta_a|^2)`, and at each end `COMPARE(|zeta|^2 10^(2q), |zeta'|^2 |c - a|^2)`. The turn from `a` to `c` is `(d_c - d_a + 4) % 8 - 4`, and the edge's turns read end to end and through the midpoint agree or not. A settled edge is the product of the positive verdicts. A negative verdict puts the midpoint into the path, a zero doubles the places, and unequal places ask both ends at the deeper. | On the host, in `Steering.count`. | One lane per half edge, reading the two point records at its ends. The places each point is asked at next, and the midpoints put into the path, written as fields and compacted by a sum over them. The turns summed per box, an exact sum over the box's lanes. | The quadrant alone counts `[24, 32]` and `[32, 40]` empty, and the chord alone counts `[98, 102]` empty (entry 4). With the step verdict every box below `t = 123` counts as the published table has it. | host only | the half edge as a record program reading two records |
| **Z6. The walk and the placing** | An empty box doubles the step, a box counting one is a zero, a crowded box splits into halves. Each zero is placed one bit per pass by the lower square centred on the line counting one. | On the host, in `Steering.walk` and `Steering.place`. | Nothing on the device past Z1 to Z5. The host reads the counts per box from the device and writes the next pass's boxes; each pass is one sweep of Z2 to Z5. | Forty zeros below `t = 123`, each placed by sixteen bits, each bracket holding the published ordinate: exit 0, five minutes on the host. | host only | the host loop over device passes |
| **Z7. The job** | One device, one daemon; a job declares its bytes, is admitted on its standing, and its peak is kept under its signum (M14). | The program runs on the host and asks the device nothing. | The program as a tessera job, beside the sims: `sim_job_submit` before its first device allocation and `sim_job_release` at its end. The signum is the host BLAKE3 of the program's name and arguments, the height and the bits. The declaration is the bytes of a pass, read from the records the last pass wrote: the points asked, times `2N` lanes, times the width at places plus the guard, and the records. Growth past it is told back, and the next run with the same signum is asked against the kept peak. | none | not built | the job's submit and release around the host loop, with the declaration read from the records |
| **Z8. The phase** | `theta(t)` by Stirling's series after a shift of `M`, two routes at `M = K = N` and `2N` (entry 5). Each `arg(1/4 + k + it/2)` is an arctangent of a rational by Euler's series and by the Taylor series about `1/2`, agreeing. The Gram index at a point is `theta` over pi, decided where `theta` reads strictly between `i pi` and `(i + 1) pi`. | On the host, in `exact_zeta_gram.py`, each `(p, q, digits)` arctangent asked once. | One lane per `(point, k)`, `k` below the shift, each an arctangent series run while its term is nonzero, as Z2's series run. The Stirling terms per point as Z3's tail is, from the same table of `B_2k / (2k)!`. The index and its two verdicts written to the point's record, and the midpoint's index read by the next pass to cut a bracket. | To `t = 285`, 5,198 values of `theta`, none deeper than eight places, none wider than `N = 4`. | host only | the arctangent series as a record program beside Z1's |
| **Z9. Riemann-Siegel** | `Z = 2 sum over n <= N of n^(-1/2) cos(theta - t ln n) + R`, with `t = 2pi u^4`, `N = floor(u^2)`, `p = u^2 - N`, and `R` from `c_0` to `c_5` (entry 6). `Psi` as two power series about `p`, its derivatives `r_j / d^(j+1)` by products, every term carried times `d^16 pi^10`. | On the host, in `exact_zeta_riemann_siegel.py`. | One lane per `(point, n)`, `n` up to `N`, each a Z2 power. The two series of `Psi` per point, sixteen coefficients each, as one record, and the `r_j` recurrence over it. The table of `c_k` read by every lane as Z3's Bernoulli table is. | To `t = 285`, 470 values of `Z`, the deepest at 64 places, the main sum at most six terms, the walk and the signs in seven seconds. Measured on the host at `u` = 1.2 and 2.6: the values take 138 to 195 bits at 1 to 8 places, 8 limbs, and 348 to 381 at 64 places, 16 limbs; their products take 391 to 517 bits, 16 or 32 limbs, and 1,019 to 1,075 at 64 places, 32 or 64 limbs. | host only | the `Psi` record and its recurrence as a record program |

## Open, not done

- Entry 4 counts below `t = 123`, one value at a time on the host, in five minutes. The device
  program and its wants are the table above, and none of it is built.
- Entry 5 reads `theta` and the Gram points on the host, and Z8 above is its device part, not built.
- Entry 6 reads `Z` on the host, and Z9 above is its device part, not built. Every `C_n` is built
  (entry 7), and `R` still stops at `c_5`: `R` to the series' own least term, and the exact remainder
  in place of the series, are wanted, not built.
- Entry 7's zeros of `C_n` are read on grids, and a count proven complete on `0 < z < 1` is wanted,
  not built. What grows in triangle cell 5, six times cell 4's time, is not yet read.
- Asked of the triangle, quoted: "The fractal feels like maybe five terms it's definitely 3. Maybe it
  is all xyzdt terms"; "So it turns into a probability wave function"; "Then we use that to vector
  walk the fractal for proofing". Then: "it's a coordinate system, dimension, and time". Entry 8
  reads them as the three sides, each side's scaling exponent between cells, and `t`. The vector walk
  over them is wanted, not built.
- Entry 8's spread of the arrival angles is read in four windows of 1,024 boundaries. More windows,
  and whole stretches of boundaries, are wanted. The triangle measured past cell 6, against what the
  omitted curves give there, is wanted.
- Computing `zeta(s)` in the critical strip needs complex arithmetic and an accelerated method,
  Riemann-Siegel or Euler-Maclaurin. Entry 4 uses Euler-Maclaurin across the strip, and entry 6
  Riemann-Siegel on the line. Riemann-Siegel off the line, for entry 4's boxes, is not built.
  A computation there is a numerical observation at the places it reads, never a statement about all
  zeros.
- Whether a non-trivial zero has a closed form in the constructors is a separate question from where
  it sits, and it is not addressed here.

## Withdrawn

Nothing withdrawn yet. The rail keeps this heading, and a later reader knows a pulled claim would
appear here with what killed it, instead of vanishing.
