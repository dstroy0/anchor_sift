# Birch and Swinnerton-Dyer workbook

**Purpose:** Record what the engine's exact arithmetic shows when it is pointed at the Birch and
Swinnerton-Dyer conjecture, one poke at a time, claiming nothing. **Scope:**
`examples/0_experimental/exact_congruent_number.py`, `evidence/proofs/posits/proof_group_law.py`, and
this file.

Kept by the precision measurement specialist. This is a workbook, not a result. It follows the rail the
millennium book set down (`theory_bucket/millennium/chapters/chapter_what_this_is.tex`) and the analytic
number theory and Navier-Stokes workbooks beside this file already follow:

- Claim nothing. No open problem is attacked here. Nothing below bears on whether BSD is true.
- Cite nothing unread. A fact that arrived by report says so in the sentence carrying it.
- Gaps go in the sentence making the claim, not in a footnote.
- Withdrawn entries stay on the page with whatever killed them. One is recorded below.
- Draw the bar, never derive it. No threshold is reasoned out of a distribution here.

The millennium book's toolkit chapter (`theory_bucket/millennium/chapters/chapter_the_toolkit.tex`)
recommended this problem, and that reason is what this workbook acts on: its obstruction matches the
instrument. The refined conjecture is an exact numerical identity, and the question whether a computed
number lands on an integer is precision-bound, where the other Millennium problems match the apparatus
only in subject. That chapter also drew the honest bound: the arithmetic imposes no floor, and the honest
report is the precision of the weakest input, the L-value, the period and the regulator, not the
precision of the multiply. This workbook keeps to the exact side and leaves that computed side as the
stated floor.

## The problem, stated fully

Read from Andrew Wiles's statement for the Clay Mathematics Institute, five pages, read in full. The
corpus chapter (`theory_bucket/millennium/chapters/chapter_the_corpus.tex`) records the same file at
`Downloads/millenium/birchswin.pdf`, and its bytes match what claymath.org served on 2026-09-11.

A polynomial relation `f(x, y) = 0` with rational coefficients defines a curve, classified topologically
by its genus. Faltings, proving Mordell's conjecture, gives that a curve of genus at least 2 has finitely
many rational points. Genus 0 is settled by Hilbert and Hurwitz and the criterion of Legendre: rational
points exist exactly when `p`-adic points exist for every `p`, and then there are infinitely many. Genus
1 is the elusive case. A genus-1 curve with a rational point is an elliptic curve, an abelian group with
that point as the identity, and Mordell (1922) proved the group is finitely generated:

- `C(Q) = Z^r (+) C(Q)_tors`, the Mordell-Weil group, with `r` the rank and `C(Q)_tors` a finite abelian
  group. `r = 0` exactly when `C(Q)` is finite.
- The curve has a Weierstrass model `y^2 = x^3 + a x + b` with `a, b` in `Z`, discriminant `Delta`.
- `N_p = #{solutions of y^2 = x^3 + a x + b mod p}`, and `a_p = p - N_p`.
- The incomplete L-series is `L(C, s) = prod_{p not dividing 2 Delta} (1 - a_p p^{-s} + p^{1-2s})^{-1}`,
  convergent for `Re(s) > 3/2`. The Hasse conjecture, now a theorem of Wiles, Taylor-Wiles, and
  Breuil-Conrad-Diamond-Taylor through modularity, gives it a holomorphic continuation to the whole
  plane.

The conjecture: `L(C, s) = c (s-1)^r + higher order terms` with `c != 0` and `r = rank(C(Q))`. In
particular `L(C, 1) = 0` exactly when `C(Q)` is infinite. The refined form completes the L-series with
Euler factors at `p | 2 Delta` and predicts the leading coefficient:

    c* = |Sha_C| R_inf w_inf prod_{p | 2 Delta} w_p / |C(Q)_tors|^2

where `Sha_C` is the Tate-Shafarevich group, whose order is not known to be finite in general and is
conjectured to be so, `R_inf` is the `r x r` regulator determinant of a height pairing on a basis of
`C(Q)/C(Q)_tors`, `w_inf` is a simple multiple of the real period, and the `w_p` are local factors. A
proof in the strong form would also prove `Sha_C` finite. It is known (Coates-Wiles, Gross-Zagier,
Kolyvagin, with modularity) that when `L(C, s) ~ c (s-1)^m` with `m = 0` or `1`, the conjecture holds.

The congruent number problem is the oldest instance and the one this workbook runs. A squarefree positive
integer `n` is congruent when it is the area of a right triangle with rational sides, and this holds
exactly when `C_n : y^2 = x^3 - n^2 x` has `C_n(Q)` infinite, which BSD ties to `L(C_n, 1) = 0`. Tunnell,
assuming BSD for the converse and unconditionally for the forward direction, reduced the question for `n`
odd squarefree to an integer count of a ternary quadratic form.

## Their sets, defined

Written as sets so every later sentence names the set it is about. The definitions are transcribed from
Wiles, not designed. `E` is an elliptic curve `y^2 = x^3 + a x + b` over `Q`.

- `E(Q)`, the rational points with the point at infinity `O`, under the chord-tangent law: three
  collinear points sum to `O`, and `O` is the identity. It is an abelian group,
  `E(Q) = Z^r (+) E(Q)_tors`.
- `E(Q)_tors`, the points of finite order, a finite abelian group. By Nagell and Lutz its points have
  integer coordinates, and by Mazur its shape is one of fifteen groups.
- `r = rank E(Q)`, the number of independent infinite-order generators; `r = 0` exactly when `E(Q)` is
  finite.
- The local counts `N_p` and `a_p = p - N_p`, one integer per prime of good reduction, bounded by Hasse,
  `a_p^2 <= 4 p`.
- `L(E, s)`, the L-series built from the `a_p`, and its analytic rank, the order of vanishing at `s = 1`.
- `Sha_E`, the Tate-Shafarevich group; `R_inf`, the regulator; `w_inf`, the real period; the Tamagawa
  factors `w_p`.

The conjecture in those names: the weak form is `analytic rank = r`; the strong form is the leading-
coefficient identity above. The congruent-number sets: `T(n)`, the rational right triangles of area `n`;
`C_n(Q)`, the rational points of `y^2 = x^3 - n^2 x`; and the two theta counts
`A(n) = #{2x^2 + y^2 + 8z^2 = n}` and `B(n) = #{2x^2 + y^2 + 32z^2 = n}`. The theorem chain: `T(n)`
nonempty exactly when `C_n(Q)` is infinite, and Tunnell relates that to `A(n)` and `B(n)`.

Our set, and where it sits in theirs. The example carries an elliptic curve over `Q` with the exact
chord-tangent law, in reduced integer-pair rationals. It reaches `E(Q)` exactly: the group law, the order
of a point, torsion versus infinite order by Nagell-Lutz, and the integer counts `N_p`, `A(n)`, `B(n)`.
It does not reach `L(E, s)`, `R_inf`, `w_inf`, or `Sha_E`, which are computed reals or an object whose
finiteness is open. The exact side is the algebra and the counting; the analytic side is left as the
floor.

## What they knew, what they wanted, what we know

Three lists, kept apart. The first two are Wiles's statement, read; the third is the two files, run.

**What they knew**, as the statement records it, in his attributions:

- Diophantus used the chord-tangent construction to get a second rational point from one; Fermat saw it
  could give infinitely many, and introduced descent, which can show the count is finite or zero. Fermat
  proved `n = 1` is not a congruent number.
- Poincare (1901) began the modern theory of rational points and asked about the minimal number of
  generators. Mordell (1922) proved `E(Q)` finitely generated; Weil extended it to number fields and
  abelian varieties.
- Faltings (1983) proved Mordell's conjecture: genus at least 2 gives finitely many rational points, not
  effectively.
- Hasse conjectured the holomorphic continuation of `L(C, s)`, now proved through modularity by Wiles,
  Taylor-Wiles, and Breuil-Conrad-Diamond-Taylor.
- Coates and Wiles (1977): for a curve with complex multiplication and `L(C, 1) != 0`, `C(Q)` is finite.
  Gross and Zagier (for `L(C, 1) = 0`, `L'(C, 1) != 0`) and Kolyvagin (1990) gave, with modularity, that
  `L(C, 1) != 0` implies `r = 0` and the rank-1 analytic case implies `r = 1`. So the conjecture holds
  when `L` vanishes to order 0 or 1.
- Tunnell (1983) proved, for `n` odd squarefree, that `n` congruent implies `A(n) = 2 B(n)`
  unconditionally, and the converse assuming BSD.
- Elkies used a point of infinite order to disprove Euler's 1769 conjecture, finding
  `2682440^4 + 15365639^4 + 18796760^4 = 20615673^4`.

**What they wanted**: a proof of the conjecture, weak or strong, for elliptic curves over `Q`. The strong
form would give an effective way to find generators of `E(Q)`, which the ineffective Mordell-Weil theorem
does not.

**What we know**, each line with its set and its scope, and nothing past the scope:

- On an elliptic curve over `Q`, the chord-tangent law is an exact abelian group. Closure, identity,
  inverse, commutativity and associativity hold on every triple tried, on a curve with `Z/2 x Z/2`
  torsion and an infinite-order point, and on a curve with `Z/6` torsion. The Z-module laws hold, and
  `[6]P` agrees across three routes.
- Torsion versus infinite order is an exact decision. A torsion point is integral (Nagell-Lutz),
  verified on both torsion groups. Integrality alone is not sufficient: `(-4, 6)` on `y^2 = x^3 - 25 x`
  is integral yet has infinite order, its double already non-integral, and no multiple up to 40 returns
  to `O`.
- For `n = 5`, two exact routes certify congruence unconditionally: Fibonacci's triangle `(3/2, 20/3,
  41/6)`, an exact area-5 right triangle whose half-hypotenuse squared is the doubled point's
  x-coordinate `1681/144`, and the infinite-order point on `C_5`.
- Tunnell's counts reproduce the known statuses exactly on `n = 1, 3, 5, 7, 13, 15`: unequal for the
  non-congruent `1` and `3`, equal for the congruent `5, 7, 13, 15`. `n = 1` recovers Fermat
  unconditionally, `A(1) = 2 != 4 = 2 B(1)`. Both theta counts agree across two bounding-box routes.
- We do not know whether BSD holds. We have computed no L-value, no regulator, no period, and no element
  of `Sha`. The unconditional direction of Tunnell (unequal counts prove non-congruent) is all the
  criterion gives us; the converse is conditional on BSD, and a bounded search for a triangle or a point
  proves no absence.

## The exact algebraic side and the computed analytic side

BSD's quantities split cleanly across the regimes of the precision document
(`theory/workbook/precision_spread_theory.md`, section 5), the same split the Navier-Stokes workbook
found.

| BSD quantity | what the engine does | regime |
|---|---|---|
| the group law on `E(Q)` | exact rational, chord-tangent | A, defined and exact |
| torsion order, Nagell-Lutz test | exact rational and integer | B, counting |
| `\|E(Q)_tors\|^2`, `r!`, the integer factors of `c*` | exact integers | B, counting |
| `N_p`, `a_p`, Hasse bound | exact integer counts | B, counting |
| `A(n)`, `B(n)`, Tunnell's counts | exact integer counts | B, counting |
| the rank `r` | exact once a Mordell-Weil basis is given; finding the basis is open | B on a given basis; completeness otherwise |
| `L^{(r)}(E, 1)`, the leading coefficient | a computed real, needs modular symbols or Dokchitser | C, measured or computed |
| `R_inf` the regulator, `w_inf` the real period | computed reals from height and period algorithms | C, measured |
| `\|Sha_E\|` | conjecturally a finite integer, not known finite in general | completeness, external |

The reading, stated as the toolkit chapter did: the arithmetic imposes no floor. The honest bound on any
BSD check is the precision of its weakest input, the regulator or the period, not the width of the
multiply. An arithmetic with no floor does not give its inputs one. So the exact side reaches the group,
the torsion, the counts, and the integer factors of the identity; the analytic side is a computed real
this work does not touch, and `Sha` sits behind a finiteness that is itself open.

## Their sets against the boundary function

The boundary function of the precision document (`proof_domain_boundaries.py`, and the self-defining
probe form in `proof_boundary_inheritance.py`) names each set's boundary kind.

| Fefferman's, here Wiles's, set | what the ring does with it | kind |
|---|---|---|
| `E(Q)` under the group law | exact on every point | none on the algebra |
| `E(Q)_tors` | exact order and Nagell-Lutz test | none |
| `N_p`, `a_p` | exact integer counts, Hasse-bounded | none |
| `A(n)`, `B(n)` | exact integer counts | none |
| the rank `r` | exact on a given basis; finding one is open | completeness |
| `L^{(r)}(E, 1)`, `R_inf`, `w_inf` | not computed here; computed reals | measurement, computed |
| `Sha_E` | not computed; finiteness open | completeness, external |
| the congruent-number converse | Tunnell equality implies congruent only under BSD | completeness, external |

## Constructors, and what inherits their proof

A rational point is built from a fixed set of constructors: the exact rational operations on integer
pairs, and the chord-tangent law composed from them. `proof_group_law.py` proves those constructors give
an abelian group with the Z-module structure, and a quantity built only from them inherits the proof: the
order of a point, `[n]P`, the torsion test, and the infinite-order witness are the group law carried
through, not new things to prove. The one axiom that is not a short check is associativity, the
Cayley-Bacharach theorem, equivalently Riemann-Roch on the genus-one curve; the file verifies the
implementation realizes it on a sample and does not reprove it in general. What is never inherited is a
statement about `L`, `R_inf`, or `Sha`, because no constructor here produces one.

## Prior art, named with respect

Every object here belongs to the field. The problem statement and its sets are Andrew Wiles's for the
Clay Mathematics Institute, read in full. The chord-tangent construction is Diophantus's and Fermat's;
Fermat proved `n = 1` not congruent and introduced descent; Fibonacci found the `n = 5` triangle. The
group structure of the rational points is Poincare's (1901); finite generation is Mordell's (1922) and
Weil's. The integrality of torsion is Nagell's and Lutz's; the classification of torsion is Mazur's. The
local bound is Hasse's. The continuation of the L-series is Hasse's conjecture, proved through modularity
by Wiles, Taylor-Wiles, and Breuil-Conrad-Diamond-Taylor. The rank results are Coates and Wiles's, Gross
and Zagier's, and Kolyvagin's. The congruent-number criterion is J. Tunnell, "A classical Diophantine
problem and modular forms of weight 3/2", Invent. Math. 72 (1983). Faltings proved Mordell's conjecture;
Elkies used a point of infinite order against Euler's conjecture. Cited from Wiles's statement and from
memory of the literature, unread here except that statement; the two files verify only the exact rational
and integer quantities and rest on no unread result. This workbook adds no new mathematics.

## Open, not done

- The rank `r` of a curve is exact once a Mordell-Weil basis is given, but finding the basis, and proving
  a given set generates, is the hard part and is not attempted here. A descent, even a 2-descent, would
  reach it for small curves and is a larger poke than this entry.
- The analytic side needs `L^{(r)}(E, 1)`, the real period and the regulator. The toolkit chapter's honest
  shape is established algorithms for the L-value, modular symbols or Dokchitser, with this engine
  supplying precision underneath, and the first task is to find whether that seam works at all. Not
  started.
- Tunnell's criterion here is run on odd squarefree `n`. The even case has its own form and is not run.
- Whether `Sha` is finite is open in general, and no element of it is computed here.

## Withdrawn

- **Withdrawn.** The status label that `n = 15` is not a congruent number, carried in the first draft of
  the example's known-status table. **What killed it:** the run and a second look. 15 is congruent, by the
  right triangle `(15/2, 4, 17/2)` of area 15, and it is squarefree. Tunnell's count for 15 is
  `A = 2 B = 0`, consistent with congruent, and the arithmetic was never wrong; the hand-written label
  was. Replaced by the correct status, and the check was strengthened to compare the equality of the
  counts against the known boolean status at every `n`, equal exactly when congruent, which now holds on
  the whole sample. Recorded because a wrong oracle label passed a check that only looked at the unequal
  direction, and the fix was to make the check look both ways.
