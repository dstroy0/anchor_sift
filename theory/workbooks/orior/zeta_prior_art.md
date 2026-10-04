# Prior art for the zeta rail: the zeros against a known reference

**Purpose:** a notes section on the outside work the orior zeta entries sit beside, kept apart from
the entries to keep a claim here from leaking into one there. Each note says what the work states, where it
touches the engine's exact-arithmetic zeta rail
([analytic_number_theory_workbook.md](analytic_number_theory_workbook.md)), and how closely it was
read. **Scope:** the papers pulled for the resonance reading and the known-carrier reading, and the
threads they belong to. No note bears on the hypothesis.

**How closely read.**
- **Read:** opened here and read, with the pages given.
- **Reported:** from a web search or cited by a paper read here, not opened.
- **From knowledge:** stated from training, not from a copy read here.

Nothing here is a result of the engine. The engine's own runs are the entries.

## The explicit formula as a pairing of zeros against primes

- **von Mangoldt (1895), Landau's explicit formula.** Read, in Balanzario and co-authors below. The
  sum of the von Mangoldt function to `x` is `x - sum over zeros rho of x^rho / rho` plus lower terms.
  Landau (1911): `Lambda(x) = -(2 pi / T) sum over 0 < gamma <= T of x^rho + R`, `R` of order
  `log T / T`. The sum over the zeros against the known power `x^rho` is of order `T` when `x` is a
  prime power and small otherwise: the zeros locked to the prime powers. This is the lock-in the
  engine's rail reads in `w = exp(i theta) F`, where `F` carries the prime side.
- **Gonek's uniform bound.** Reported. `R <= x log(2 T x) log log(3 x) / T`, uniform in `x` and `T`.
  It makes Landau's formula a usable reference at a finite height, the regime the engine runs in.
- **Balanzario, Cardenas Romero and Chacon Serna, "A smooth version of Landau's explicit formula"
  (arXiv:2311.04347, 2023).** Read, pp. 1-4. A Gaussian weight on the von Mangoldt sum, matched by a
  Gaussian weight on the sum over zeros: both sides of the formula carry a bell-shaped window. Under
  the hypothesis, whether a number is prime is settled by the location of about `mu log^(3/2) mu`
  zeros, and Heisenberg's inequality (the Fourier uncertainty bound) argues that count cannot be cut.
  The two matched Gaussians, one on each side, are the two-window form the engine's carrier reading
  wants: a window on the primes and a window on the zeros, read against each other.

## The spectral and trace-formula program

- **Polya and Hilbert.** From knowledge. The zeros as the spectrum of a selfadjoint operator, so that
  RH becomes a selfadjointness or positivity statement. The motivation for the pair below.
- **Berry, "The Riemann-Siegel expansion for the zeta function: high orders and remainders"
  (Proc. R. Soc. Lond. A 450, 1995).** Read, pp. 1-5. `Z(t) = exp(i theta(t)) zeta(1/2 + i t)` is real.
  Its remainder past the main sum is one tail of `exp(+i(theta - t ln n))` added and one tail of
  `exp(-i(theta - t ln n))` subtracted (his eq. 13): two counter-rotating combs, each the conjugate of
  the other, one added and one taken off. The series diverges, its terms falling until order about
  `2 pi t` and then rising, and the critical line is a Stokes line of the expansion, the remainder of
  order `exp(-pi t)`. The engine's `C_0 = F(z) = cos((pi/2)(z^2 + 3/4)) / cos(pi z)` is Keating's
  lowest coefficient of this same expansion (entry 7), and `w` and its conjugate are the two combs.
- **Connes, "Trace formula in noncommutative geometry and the zeros of the Riemann zeta function"
  (arXiv:math/9811068, 1998).** Read, pp. 1-7. The critical zeros are an absorption spectrum, missing
  lines, while off-line zeros would appear as resonances. The explicit formula is a trace formula on
  the space of adele classes `A / k^*`, the space the engine's two crystals build in part
  ([two_crystals.md](../engine/two_crystals.md), "The places of Q"). RH for every `L`-function with
  Grossencharakter is equivalent to the positivity of the Weil distribution, a sign on the pairing of
  a test function on the zeros against its transform on the primes. The "crucial negative sign" in the
  fluctuations is why the zeros read as absorption, a dip, not emission. The engine certifies a
  zero as a sign change of `Z`, a crossing to a null, a dip in this sense.

## The quasicrystal program

- **Dyson, "Birds and Frogs" (Notices of the AMS, February 2009).** Read, pp. 212-216 (the
  quasicrystal passage, pp. 214-215). Verbatim: "a fourth joke of nature is a similarity in behavior
  between quasi-crystals and the zeros of the Riemann Zeta function"; "I am now making the outrageous
  suggestion that we might use quasi-crystals to prove the Riemann Hypothesis". A quasicrystal is a
  point-mass distribution whose Fourier transform is again a point-mass distribution. If RH holds, the
  zeros are a one-dimensional quasicrystal whose transform sits on the logarithms of the prime powers
  (he cites Odlyzko's transform of the zeros). His plan: enumerate and classify the one-dimensional
  quasicrystals, far richer than the higher-dimensional ones and not tied to any rotational symmetry,
  and a unique one stands for every Pisot-Vijayaraghavan number. If one of them matches the zeta
  zeros, RH is proved.
  - **Derived here, elementary algebra.** The `1, 1, 2` carrier of the workbook's posit (6) has period
    matrix `[[1,1],[1,0]]^2 [[2,1],[1,0]] = [[5,2],[3,1]]`, trace 6 and determinant -1, with
    eigenvalues `3 +- sqrt(10)`. `3 + sqrt(10)` is a root of `x^2 - 6 x - 1`, a monic integer
    polynomial, and its conjugate `3 - sqrt(10)` has size below 1: `3 + sqrt(10)` is a Pisot number,
    and a unit, since `3^2 - 10 = -1`. The `1, 1, 2` carrier is therefore a one-dimensional Pisot
    quasicrystal, in the family Dyson proposed to classify.
  - **The metallic companions.** The `1, 1, 1, ...` carrier of posit (6) is the golden ratio
    `phi = (1 + sqrt(5)) / 2`, a root of `x^2 - x - 1`, convergent denominators the Fibonacci numbers,
    conjugate `(1 - sqrt(5)) / 2` of size below 1: a Pisot unit. The `2, 2, 2, ...` carrier is the
    silver ratio `1 + sqrt(2)`, a root of `x^2 - 2 x - 1`, convergents the Pell numbers, conjugate
    `1 - sqrt(2)` of size below 1: a Pisot unit. Both are metallic means, `x^2 = n x + 1` at `n = 1`
    and `n = 2`. `phi` is the worst-approximable number (Hurwitz, the `sqrt(5)` bound): a carrier
    stepped by it spreads the most evenly of any quadratic irrational, the flattest known reference.
    The `1, 1, 2` carrier is golden on each run of two 1s and departs on the 2, a period-3 kick (the
    golden-helix reading of [two_crystals.md](../engine/two_crystals.md)); overlaid on `phi` the two
    agree on the 1, 1 and beat at the 2.
  - **The whole family, derived.** A purely periodic continued fraction of period `k` has matrix the
    product of `k` copies of `[[a_i,1],[1,0]]`, determinant `(-1)^k`. A 2 by 2 matrix's eigenvalues
    multiply to its determinant: the growth constant `lambda > 1` pairs with a conjugate of size
    `1 / lambda`, and every periodic comb's growth is a quadratic Pisot unit. `phi` (golden, `n = 1`),
    `1 + sqrt(2)` (silver, `n = 2`), `(3 + sqrt(13)) / 2` (bronze, `n = 3`), `3 + sqrt(10)` (`1, 1, 2`)
    and `(19 + sqrt(365)) / 2` (`2, 2, 3`) are all of them.
  - **From knowledge.** A quadratic Pisot number gives a cut-and-project set whose diffraction is pure
    point, sharp Bragg peaks (Meyer; Bombieri and Taylor): each comb diffracts to points, the
    sharp-line case Dyson's program turns on. A finite sum of pure-point combs is pure point, and
    combining members builds a carrier with lines at a chosen set of frequencies, a matched filter. The
    members' lines are algebraic and `log p` is transcendental (Lindemann): a line lands on a prime
    power only to a precision, the window's width at a finite height. The general Pisot substitution
    conjecture, that every Pisot substitution gives pure-point diffraction, is open.
- **Shaughnessy, "Quasicrystal Scattering and the Riemann Hypothesis" (arXiv:2410.03673, 2026).**
  Read, pp. 1-8. Scatterers at `ln(p_n)` give a scattering amplitude `sum p_n^(-2 pi i k)`, tied to
  `-zeta'/zeta`, whose zeros appear as Lorentzian peaks at `gamma / 2 pi`, the normalized peak
  coefficient scaling as `p_L^(beta - 1/2)`: growing above the line, vanishing below it, and exactly 1
  on it. It claims a proof of RH, that the Fourier self-duality of the prime quasicrystal,
  `F[F[chi]] = chi(-.)`, forces every coefficient to be of order 1 and so `beta = 1/2`. Reported
  status: an arXiv preprint claiming to settle RH; the construction was read here, the proof was not
  checked, and a claimed proof of this kind stands only once it is refereed. The mechanism, a peak
  that would grow off the line set against a self-duality that forbids it, is the tuned-and-opposed
  shape in the literature.
  - **Remmen** and **Baez** are cited there for the same amplitude and quasicrystal pictures.
    Reported, unread.

## The known-carrier reading: fractional parts of the zeros

- **Rademacher (1956), Hlawka (1975).** Reported, from Ford and Zaharescu below. For a fixed `alpha`,
  the fractional parts `{alpha gamma}` over the zeros' ordinates `gamma` are uniformly distributed
  modulo 1, unconditionally (Hlawka), which RH plus Weyl's criterion gives at once (Rademacher).
- **Ford and Zaharescu, "On the distribution of imaginary parts of zeros of the Riemann zeta function"
  (arXiv:math/0405459, 2004).** Read, pp. 1-4. Under RH, the exponential sum of the zeros against the
  known frequency `alpha`, `sum over 0 < gamma <= T of exp(2 pi i j alpha gamma)`, is of order `T`,
  against the `T log T` terms: the zeros are biased against that reference, not evenly spread. The bias
  density `g_alpha` is zero unless `alpha` is a rational multiple of `(log p) / 2 pi` for a prime `p`;
  at `alpha = a (log p) / (2 pi q)` it has global minima at `t = k / q`, each a shortage of zeros
  there. Their Figure 1, from Odlyzko's zeros to height `T = 600000`: `alpha = (log 2) / 2 pi` shows
  one pattern, `alpha = (log 5) / (3 . 2 pi)` shows three dips (`q = 3`), and `alpha = (log 6) / 2 pi`,
  with 6 not a prime power, is noise. A known log-prime carrier reads a deterministic bias off the
  zeros: the engine's carrier reading, with the carrier chosen and known.
- **Ford, Soundararajan and Zaharescu, "... II" (arXiv:0805.2745, Math. Ann.).** Read, pp. 1-2.
  Extends the bias to connect it to Montgomery's pair correlation and to primes in short intervals,
  and conjectures the law holds for the indicator of an interval.
- **Ford, Meng and Zaharescu, "Simultaneous Distribution of the Fractional Parts of Riemann Zeta
  Zeros" (arXiv:1511.06814, 2016).** Read, pp. 1-2. Several references at once,
  `{alpha_1 gamma, ..., alpha_n gamma}`, where a Diophantine condition on the `alpha` governs the joint
  law and a matrix `M` with `M alpha^T = P` collects the prime-power resonances. The multi-carrier
  form of the reading above.

## What none of these do that the engine's rail does

- Each correlates the zeros, once found, with a known reference, or reads the zeros as a spectrum. None
  reads a known sequence placed in the lattice the engine reads `Z` on, with the moments of `w` taken
  against it and the same taken with the sequence's steps shuffled, as the drawn null.
- None carries its values as exact windows checked by the host word for word. The engine's zeros to
  `6295757.960979` are certified sign changes (entries 9, 14, 15), not floating-point readings.
- The spectral, quasicrystal and carrier threads all read the same pairing of the zeros against the
  prime powers from different sides. The engine holds both sides of that pairing in one field, `w` and
  its conjugate, and can read a chosen carrier against it exactly. What it cannot reach is the
  all-functions positivity those threads turn on: that is the hypothesis.
