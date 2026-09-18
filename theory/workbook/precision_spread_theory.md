# Precision spread: exact identities over a set of quantities

**Purpose:** State when an exact identity carries precision from one quantity to another. That a few
computed constants raise the precision held over many, and mark the three regimes where that does and
does not multiply accuracy. **Scope:** the set of exact quantities the engine and its domains carry,
the identities among them, and `examples/0_experimental/exact_identities_spread_precision.py`, which
runs the mathematical case.

Written by the precision measurement specialist. Names are chosen to avoid meanings already in use, on
the anchor sift theorist's record: `closure` is taken for the transitive closure of the equality oracle
(`src/engine/c/engine/anchor_sift.h:443-453`), `coherence` for lag-agreement structure
(`theory/workbook/chapters/chapter_anchor_sift_workbook.tex:294` and `bench_coherence.c`), `topology`
for the induced `tau_Sigma` on the symbol carrier (`theory_bucket` delta_null, chapter terms), `span`
for a length scale (delta null's block-span sweep and the engine workbook's span table), and the
subscript `D` for a pattern support `D subset G`. This document uses `gen` for the generation operator
and the `derivation topology tau_Q` for the structure below, both on the set of QUANTITIES `Q`, a
different set from the symbol carrier.

## 1. The set and the relation

Let `Q` be a set of exact quantities. A quantity is one of two kinds.

- DEFINED: fixed by exact operations or a convergent exact series. Examples: the rationals, `sqrt(n)`,
  `pi`, `e`, `ln 2`, `zeta(2)`. A defined quantity can be computed to any number of places. Its
  precision is a budget, not a floor.
- MEASURED: a deposited value with an uncertainty fixed upstream by whoever measured it. Examples: a
  crystal cell edge (crystallography session: published to about 4 to 5 places with a bracketed
  uncertainty), a physical constant such as the Bohr radius or the Rydberg energy (particle physics
  session: `a0`, `R_inf`, `alpha`, the electron-proton mass ratio). A measured quantity has a real
  precision floor, and no arithmetic on this end lowers it.

An exact identity is a relation `q = f(q_1, ..., q_k)` that holds with no rounding, where `f` is built
from the exact operations. An identity is a hyperedge: it has `k` inputs and one output. Two kinds
appear. A unary identity has one input (`2 pi` from `pi`; `pi^{2k}` from `pi`). A multi-input identity
needs several inputs together (`sqrt(6) = sqrt(2) * sqrt(3)` needs both roots).

The quantities are not only positive reals. `Q` carries every exact number type the engine holds, and
the spread runs over each. The rationals are exact as a numerator over a denominator, the form game
theory carries its outcome distributions in. The algebraic irrationals are exact at any scale:
`sqrt(n)` from an integer square root, and the roots of unity that build a transform's twiddle table,
exact elements of the integers modulo a prime. The transcendentals are held at any scale with no
quantum imposed from this end, and a real is carried to any number of places, the sense in which
`representation.exact` refuses a second quantum. The imaginaries are exact where their parts are
rational: a Gaussian rational `a + b i`, and the unit complex number a plane rotation multiplies by,
carried exactly by the image transforms rotation chapter where the directions are rational. A
quaternion with rational components carries an exact rotation in three dimensions the same way. The
identities compose inside each type: a product of Gaussian rationals is a Gaussian rational, and a
power of a root of unity is the next twiddle, and the spread stays closed under the type it works in.
The set `Q`, its quantities, and the identity hyperedges among them are themselves a relational set,
and the derivation topology below is the structure that relational set carries.

## 2. The generation operator and the derivation topology

For a seed set `S` (the quantities computed directly, from series), define

    gen(S) = every quantity derivable from S by the identities, applied to a fixed number of places.

`gen` is extensive (`S` is a subset of `gen(S)`), monotone (`S` inside `T` gives `gen(S)` inside
`gen(T)`), and idempotent (`gen(gen(S)) = gen(S)`, because a derivation of a derivation is a
derivation). Those three properties make `gen` a Moore closure operator, and its fixed points, the
sets with `gen(S) = S`, form a lattice. This is the general object, valid for multi-input identities.

Restrict to unary identities and the structure is a preorder: `q` precedes `q'` when `q'` is derivable
from `q` alone within a bounded loss. A preorder induces an Alexandrov topology, whose open sets are
the up-sets. Call it the derivation topology `tau_Q`. It is a genuine topology, and it is NOT
`tau_Sigma`: `tau_Sigma` sits on the symbol carrier of one text, `tau_Q` sits on the set of numeric
quantities. The multi-input identities are what carry `tau_Q` past a topology to the Moore closure
`gen`, since a hyperedge is not an edge and its reachability is not additive: `gen({sqrt2, sqrt3})`
holds `sqrt6`, while `gen({sqrt2})` and `gen({sqrt3})` separately do not.

## 3. The spread theorem

**Claim.** If every quantity in a seed `S` is computed to `N + g` places, and every identity floors its
result with a loss under one unit in the last worked place, then every quantity in `gen(S)` reached in
at most `d` derivation steps is known to at least `N + g - d` places. A guard `g` of `ceil(log10(d))`
places holds the loss, and `gen(S)` is known to `N` places.

**Argument.** Induction on derivation depth. A seed holds at `N + g` places. Each exact operation on
scaled integers (add, subtract, multiply with a rescale, divide) floors, losing under one unit in the
last worked place; this is the same floor `representation.exact` and `src/engine/c/no_rounding/`
carry. A chain of `d` such steps loses under `d` units, and a value reached in `d` steps holds to
`N + g - d` places. The guard absorbs `d` while `10^g > d`.

The prototype measures this directly. Over the seven root derivations it checks, the worst gap between
the identity route and a direct integer square root is 65 units in the last worked place, against a
guard of `10^24`. The floor is real, tiny, and bounded.

**Consequence.** Computing the seed `S` to `N + g` places yields `gen(S)` to `N` places. The cost is
`|S|` direct series computations. The reward is `|gen(S)|` quantities at `N` places. The accuracy
multiplier is `|gen(S)| / |S|`.

## 4. The multiplier is unbounded in the defined regime

Take the root family. Seed the `k` prime square roots. The identity `sqrt(prod p^e) = prod sqrt(p)^e`
puts `sqrt(n)` in the generated set for every `n` whose prime factors are among the seed primes, the `k`-smooth
integers. The count of `k`-smooth integers up to a bound grows without limit in the bound, and the
multiplier grows without limit. The prototype counts it: from the two seeds `sqrt(2)` and `sqrt(3)`
alone, the generated set holds the square root of 2,230,148 distinct 3-smooth integers up to `10^800`, which is
1,115,074 exactly-known constants per seed. Adding seeds raises the count at far smaller bounds: three
seeds reach 1,143 per seed at `10^12`, ten seeds reach 146,955, fifteen seeds pass 200,000.

The same holds for two more families. The zetas: `zeta(2k) = rational * pi^{2k}` puts every even zeta
in the generated set of the single seed `pi`, checked by the exact `pi`-free ratio `5 zeta(4) = 2 zeta(2)^2`.
The logs: `ln(prod p^e) = sum e * ln(p)` puts `ln(q)` for every smooth rational `q` in the generated set of the
prime logs, checked against a direct series for `ln(6)`.

The incremental spread is greedy: add the seed with the largest marginal gain. The high-reach seeds are
the small primes (2 divides half the smooth integers), `pi` (every even zeta, and the physical-constant
family that carries a `pi`), and the defined constants generally. Those are the candidates that pull the
most others up.

## 5. Three regimes

The spread does not multiply accuracy everywhere. The six domains surveyed fall into three regimes, and
the regime, not the domain, decides whether an identity raises precision.

**Regime A, defined.** Identities raise precision without bound. The natural constants above. Particle
physics reports one hub, the Rydberg energy `R_inf`, from which every hydrogen-like level
`E(n,Z) = -R_inf Z^2/n^2` and radius `r(n,Z) = a0 n^2/Z` follows by an exact rational identity in the
hub. Game theory reports minimum Shannon entropy decided with no logs by `prod p_i^{p_i} = 2^{-H}`,
cleared to integers through the least common multiple of the share denominators, and an entropy order
becomes an exact rational comparison (`src/engine/python/representation/game/rules.py`, `measure/outcome_entropy.py`,
as reported). Removable uncertainty in this regime is zero.

**Regime B, counting.** Quantities are exact integers or rationals by their nature, and identities
propagate exactly with nothing to raise: the multiplier is one. Chemistry reports the
conservation identities, stoichiometry balancing atom counts and the valence handshake
`sum valence = 2 * bond count`, plus one defined constant, the Avogadro number, exact by the 2019 SI
definition. Particle physics reports the integer capacities `2(2l+1)` and `2n^2` and the Madelung
closure to 118. The engine carries the set-algebra identity that the alignments a probe set rejects are
a union, and every LEGAL probe set gives the same count after the full compare, where an illegal probe
reading outside the pattern is not covered and the survivor set before the compare is a superset
(`docs/steering.md:118`, `T subset S_p for every legal probe p`, as reported by the anchor sift
theorist), and the transitive closure of the equality oracle into classes.
These are exact and load-free, and they do not multiply precision because the quantities have none to
gain.

**Regime C, measured.** An irreducible upstream floor. Crystallography reports that the recovered
period equals the published edge to the digit and never finer, and that the metric tensor is
deliberately left out of the exact path, because a general cell angle has a transcendental cosine that
does not stay in exact integers or rationals (`crystal.py:240`, as reported). That domain also carries a
completeness floor of its own, separate from the deposit: a right-angle gate, `RIGHT_ANGLE_SLACK = 0.01`
at `crystal.py:112`, admits a cell to the exact path only where every angle is within `0.01` of 90, and
a census over 8885 COD entries refused 4411 of them, family-dependent (garnet 97.5 percent admitted,
feldspar 2.9 percent), reported from `maint/analysis/survey/crystal_gate_census.py`. Two further
judgment-picked parameters, `EXACT_TILES = 4` and a harmonic-family cap of 2, sit in the period reader
and can decide which period is reported; the crystallography session notes their effect is unmeasured,
so the reader is not parameter-free. Chemistry reports bond lengths,
masses, and electronegativities as the measured oracle. Particle physics reports `a0`, `R_inf`,
`alpha`, and the mass ratio as measured, `R_inf` to about `10^-12` relative. Protein reports the
deposited coordinate at three places as the floor, with two independently refined copies of one
molecule agreeing on the exact integer torsion term at zero residues, since last-place refinement
noise makes each one distinct.

Regime C has one opening. An identity can form a RATIO in which the measured constant cancels, and the
ratio is then floor-free and exact. Particle physics reports the cleanest case: within one spectral
series, `lambda(H-beta) / lambda(H-alpha) = 20/27` exactly, with `R_inf` canceled, and a whole ladder
of line ratios is physical-constant-free and exact while the absolute scale still carries the CODATA
uncertainty. The spread reaches Regime C only by cancellation, predicting exact ratios, never by
raising an absolute past its deposit. Where the absolute is needed with its uncertainty, the engine now
carries it: `anchor_exact_from_measured` and `representation.exact.measured(text, digits)` return the
value and its bracketed uncertainty at one scale (on `origin/main` at `656be3e`, reported by the lead
of the private precision repository).

## 6. Two floors: precision and completeness

The spread raises precision. It does not raise completeness, and the two are separate floors.

Game theory reports the sharpest statement: an unsolved game tree, chess, has an unbounded winning-path
tree whose entropy is estimated at a horizon the domain refuses to fold into the number. No spread buys
back an unsolved tree, because the limit is a missing computation, not a rounding. Particle physics
reports the same shape from physics: the Bohr model omits fine structure, the Lamb shift, and QED, and
the model truncation dominates far above the constant uncertainty. Protein reports it as deposition: the
arithmetic is already exact, and a scheme that wants more precision has to lift the experiment, not the
computation.

This is the engine's own division seen again. The workbook records that soundness belongs to the
construction and cost belongs to the domain's distribution
(`theory/workbook/chapters/chapter_anchor_sift_workbook.tex`). The precision spread is a
construction-side statement, like soundness: it is exact wherever the quantity is defined. The
completeness and measurement floors are domain-side, and no identity on this end crosses them.

The absolute floor is not on this end at all. The mathematics imposes no quantum: a defined quantity is
exact, its precision a budget paid in compute, under no ceiling. The variability runs finer than any
scale a reader names, past the Planck length and past any bound named after it. The arbitrary-precision
path carries the scale as a runtime argument (`representation.exact`) with no limit in the code, and the
redundant residue code drives the exact range past any fixed width, a googol and every bound beyond it,
by adding moduli. A build may fix a width, the C arm's 108 limbs among them, but that is one arm's
compile-time choice, and the residue code passes straight through it; it is not a ceiling on the
quantity. Nothing rounds silently either: where a value will not fit a declared scale the arithmetic
refuses loudly (`exact.WillNotFit`) in place of rounding. The floor of zero on this end is checked
and not merely asserted. The absolute floor is entirely external, with exactly two sources, neither of
them arithmetic.
One is MEASUREMENT: the physical deposit, and beneath it the limits of the experiment. The other is
COMPLETENESS: the part not yet computed, an unsolved tree, an un-modeled term, or a gate that admits
only part of a corpus. A spread, a residue code, a widened range: not one of them reaches those two,
and all of them drive the arithmetic's own share of the floor to zero, where it already sits. The
accuracy is never limited by our arithmetic. It is limited by the world we measure and by what we have
not finished computing.

## 7. The redundant residue code, and the exponential range

The exactness has a second use past the spread: it makes an error-correcting code detect real
uncertainty and never its own arithmetic. A residue number system carries an integer as its remainders
against pairwise coprime moduli, reconstructed by the Chinese remainder theorem. Adding redundant moduli
past the ones a value needs turns the representation into a code, the redundant residue number system,
with the error-correcting capability of a Reed-Solomon code: two redundant moduli correct one error and
detect two, and `r` of them correct `floor(r/2)` and detect `r`. This is an existing code from coding
theory, run here on exact integers.

Two things follow that neither half gives alone, both shown in
`examples/0_experimental/exact_residue_code_detects_uncertainty.py`. First, the exact range is the
product of the moduli, and it grows by more than a trillion for each modulus near `2^40` added, with no
fixed width to stop it. The growth is exponential in the count of moduli: nine such moduli pass a googol
of exact range, and the climb does not end. Second, because every residue is an exact integer and
nothing rounds, a nonzero syndrome is a real disagreement. The code detects genuine uncertainty and
never a rounding artifact, and its false-alarm rate on clean codewords is zero, measured over five
hundred of them.

That second property is the two-route discipline made into a code. Two exact readings compared residue
by residue agree exactly or name where they differ, the protein session's enantiomer case: two
independently refined copies of one molecule disagree on the exact torsion term at every residue, and an
exact compare reports the disagreement where a rounded one would have merged them. The code turns that
comparison into detection and, with enough redundancy, correction. That is how exact precision is used
to detect uncertainty: the redundancy measures it.

## 8. Expand to all sets

Every domain surveyed carries the same object: a set of quantities `Q` with an exact-identity
hypergraph, the generation operator, and the derivation topology `tau_Q`. The structure is domain-blind, as
the rest of this engine is. What differs across domains is only which regime a quantity's identities sit
in. The map, as each session reported it:

| domain             | representation                                               | the identity that carries                          | regime                       | floor                                                                     |
| ------------------ | ------------------------------------------------------------ | -------------------------------------------------- | ---------------------------- | ------------------------------------------------------------------------- |
| natural constants  | scaled integers at `10^-N`                                   | `sqrt`, `zeta(2k)=c*pi^{2k}`, `ln` sums            | A                            | none (defined)                                                            |
| particle physics   | exact integer tuples; rationals                              | `E,r` from `R_inf`; line ratios cancel it          | A on ratios, C on absolutes  | CODATA constants, model                                                   |
| game theory        | exact `Fraction`                                             | `prod p^p = 2^{-H}` cleared to integers            | A on the decision            | unsolved tree (completeness)                                              |
| image transforms   | residues mod `p=119*2^23+1`; `Fraction`                      | binomial `2^n` scale; NTT with CRT widening        | A                            | prime bound, lifted by CRT                                                |
| chemistry          | small integers                                               | stoichiometry, valence handshake; Avogadro defined | B, plus one defined constant | measured masses and lengths                                               |
| crystallography    | scaled integers at `10^-1024` angstrom, refusing on overflow | period equals edge; lag harmonics `a -> n*a`       | C                            | the deposit, plus a right-angle gate refusing ~half of COD (completeness) |
| protein            | truncated integers at `10^-3` angstrom                       | reflection: `S,C` invariant, `Y` negates           | C                            | the deposition                                                            |
| anchor sift engine | `size_t` counts; 108-limb exact integer                      | union of rejections; equality classes              | B                            | none below the integer width                                              |

Reading the table: the spread multiplies precision in Regime A, is exact but flat in Regime B, and in
Regime C reaches only the floor-free ratios. The natural constants and the particle-physics line ratios
are where a millionfold gain lives; the measured absolutes are where it does not, and the honest
statement of the goal names both.

## 9. What this buys the goal to raise accuracy about a million times

- In the defined regime the multiplier is unbounded and passes one million at a finite reach, measured
  at 1,115,074 constants per seed in the two-seed root case. The accuracy the engine holds rises a
  millionfold by computing a few hubs and taking the set they generate.
- In the measured regime the absolutes keep their floor. The gain there is the floor-free ratio, where
  the measured constant cancels and the prediction is exact, plus accumulation: an exact count loses
  nothing however many are added, as the image transforms session states for the translation counts.
- The method is the incremental spread: compute next the hub with the largest marginal gain, the small
  primes and `pi` and `R_inf` and the defined constants, the ones that pull the most others up.

## 10. The boundary function, for every domain

Every exact representation has a boundary, the point past which it cannot go exactly, and the boundary
is one of three kinds. Naming the kind is the boundary function.

- FORMAT boundary, raisable. A chosen parameter caps the representation, and a larger choice moves it
  without limit. The number theoretic transform's length divides `p - 1`, capped at the 2-adic order of
  the prime, `2^23` here, and `2^27`, `2^32`, `2^48` on larger primes or by CRT (proven in
  `examples/0_experimental/ntt_double_transform_inverts.py` and `ntt_twiddle_certificate.py`). The exact
  integer's width is fixed at 3456 bits in the C arm and unbounded on the Python path, and the residue
  code's range is the product of its moduli, raised past a googol by adding them
  (`exact_residue_code_detects_uncertainty.py`). A format boundary is engineering, and the mathematics
  under it has none.
- MEASUREMENT boundary, external. The deposit's own precision, fixed upstream: a crystal edge to four or
  five places, a protein coordinate to `10^-3` angstrom, a physical constant to its CODATA uncertainty.
  No identity on this end crosses it, proven in `evidence/proofs/posits/proof_precision_spread.py` where
  a measured input floors near its deposit. Only a better experiment lowers it.
- COMPLETENESS boundary, external. The part not computed or not modeled: an unsolved game tree scored at
  a horizon, a Bohr spectrum without QED, a right-angle gate admitting only part of a corpus. No
  arithmetic buys it back; only more computation or a better model does.

The three boundaries, per domain:

| domain                 | boundary function                                                                        | kind                                       |
| ---------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------ |
| image transforms / NTT | length `n` divides `p - 1`, cap `2^23` on this prime                                     | format, raised by prime or CRT             |
| precision / constants  | C width 3456 bits; Python scale unbounded; residue range is the product of moduli        | format, raisable                           |
| crystallography        | deposit to about 5 places; right-angle gate `abs(angle - 90) <= 0.01`                    | measurement, and completeness at the gate  |
| protein                | coordinate at `10^-3` angstrom; exact equality is same coordinates or an exact transform | measurement                                |
| chemistry              | measured masses and lengths; the counting layer has none                                 | measurement on the real-valued part        |
| particle physics       | CODATA constants, `R_inf` to about `10^-12`; the model omits QED                         | measurement, and completeness in the model |
| game theory            | the unsolved tree, scored at a horizon                                                   | completeness                               |
| anchor sift engine     | pair-rank projection refused past `UINT32_MAX`; counts none below the width              | format                                     |

The topology reads the boundary. A format boundary is where the representation folds: the transform is
cyclic on `Z/nZ`, a circle, and its double is the involution `m -> -m`, its own inverse, with fixed
points at `0` and `n/2` where the fold turns around. That is the wave inversion of section 7 stated as a
group law, `-(-m) = m`, proven in one line and verified exact in `ntt_double_transform_inverts.py`. The
measurement and completeness boundaries are not folds in the representation. They sit outside it, in the
world and in the computation not yet done. No fold of the arithmetic reaches them.

Prior art. The transform's order-four structure, with its square the reflection operator `P` where
`(P x)[m] = x[-m]`, is classical (McClellan and Parks, "Eigenvalue and eigenvector decomposition of the
discrete Fourier transform", IEEE 1972; arXiv:0808.3214). The number theoretic transform as the
finite-field Fourier transform, with the length condition `n | p - 1`, is Pollard, "The fast Fourier
transform in a finite field", Math. Comp. 1971 (survey arXiv:2211.13546). The redundant residue number
system's error correction, matching a Reed-Solomon code, is standard coding theory. The precision
constants rest on the twiddle proof already in this tree, `theory_bucket/twiddle_constants_article.tex`,
which carries its own citations. Each result above is reproduced in exact integers by the example named
beside it. The citations record what is known, and the examples are the proof.

See [[ntt-precision-constants]] for the constants the image transforms transform rests on, and the
coordination log beside this file for how the survey was gathered.
