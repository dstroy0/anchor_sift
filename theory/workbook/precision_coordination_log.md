# Precision coordination log

**Purpose:** Record how the precision constants and the exact arithmetic under them reached the
image_transforms book and the examples, letting a later session pick up the citations without
re-deriving them. **Scope:** `theory/image_transforms/`, the precision examples under
`examples/0_experimental/`, and the constants owned by `src/engine/c/no_rounding/` and
`theory_bucket/precision/`.

Kept by the precision measurement specialist. The anchor sift engine owns the commits; this file is a
journal, not a settled-results section of
`theory/workbook/chapters/chapter_anchor_sift_workbook.tex`.

## 2026-09-16 entry one: constants located, verified, cited

Coordinated with the anchor sift engine (constants home, handoff) and the lead of the private precision
repository (precision constants, bignum use), which this public file names by role and not by name.
Everything below was read from the tree or re-derived here, never taken on report.

### Where the constants live

- Bignum, C side: `src/engine/c/no_rounding/exact_integer.h`. `AnchorExactInteger` is 108 `uint32`
  limbs (`ANCHOR_EXACT_LIMBS = 108`, line 49), base `2^32` with a 64-bit accumulator, schoolbook
  multiply. `ANCHOR_EXACT_DIGITS = 1024` (line 66) is a declared floor, not the capacity: 108 limbs
  is 3456 bits and holds 1040 decimal digits. 16 are headroom the constant does not promise (lines
  55 to 60). Schoolbook is correct at this width because Karatsuba crosses over in the thousands of
  limbs and this is a hundred (line 179).
- Bignum, Python side: `src/engine/python/representation/exact.py`. `SCALE_DIGITS = 1024` (line 74),
  arbitrary precision, the scale the C form is cross-checked against. The two forms must agree on the
  same values or a cross check between them means nothing (`exact_integer.h` line 45).
- NTT precision constants: pinned upstream in the `theory_bucket` subtree, not in `src/`. The proof is
  `theory_bucket/precision/chapters/chapter_twiddle_proof.tex`; the standalone paper, also on the
  Cryptology ePrint Archive, is `theory_bucket/twiddle_constants_article.tex`. No NTT is implemented in
  `src/` (a grep of the five moduli hits only `theory_bucket`). No code-level prime table exists to
  cite. A prime table in `src/` that nothing calls would be a knob with no reader.

### The NTT moduli, re-derived here

Each modulus below was checked by factoring `p-1`, measuring the 2-adic part, confirming the generator
is a primitive root (`g^((p-1)/q) != 1` for every prime `q | p-1`), and confirming each Proth witness
(`a^((p-1)/2) == p-1 (mod p)`). Numbers agree with `theory_bucket/twiddle_constants_article.tex` lines
198 to 200 (device primes), line 126 (goldilocks), and line 205 (the wrap finding).

| modulus              | shape           | bits | below 2^31 | p-1                   | 2-adic | generator | Proth witness |
| -------------------- | --------------- | ---- | ---------- | --------------------- | ------ | --------- | ------------- |
| 998244353            | 119·2^23+1      | 30   | yes        | 2^23·7·17             | 2^23   | 3         | (none quoted) |
| 2013265921           | 15·2^27+1       | 31   | yes        | 2^27·3·5              | 2^27   | 31        | 11            |
| 2281701377           | 17·2^27+1       | 32   | no         | 2^27·17               | 2^27   | 3         | 3             |
| 3892314113           | 29·2^27+1       | 32   | no         | 2^27·29               | 2^27   | 3         | 3             |
| 18446744069414584321 | (2^32-1)·2^32+1 | 64   | no         | 2^32·3·5·17·257·65537 | 2^32   | 7         | (none quoted) |

Two notes carried from that check and from the private repository's lead:

- The generator and the Proth witness are different numbers for `2013265921` (generator 31, witness
  11). They must not be conflated: one builds the twiddle table, the other proves the prime. For the
  other two device primes both are 3. The generators are absent from the paper's witness table,
  where the book states one it re-derives it and shows the primitive-root check instead of citing the
  paper for it.
- The three device primes multiply to a 94-bit number, the CRT reassembly ceiling for the device
  multiply.

### The wrap finding, reproduced

`theory_bucket/twiddle_constants_article.tex` line 205: the first device kernel agreed with the host
on `2013265921` and differed in every slot on the other two, because two residues below a modulus
above `2^31` sum past `2^32` and wrap silently in `uint32`, and the borrow in the difference does the
same. Reproduced here: for two residues just under the modulus, the `uint32`-wrapped sum reduced mod
`p` equals the true sum mod `p` for `2013265921` (below `2^31`) and disagrees for both `2281701377`
and `3892314113` (above `2^31`).

### Bignum use, from the private repository's lead

- Host arm: Python native integers, exact scaled-integer arithmetic with binary splitting at any
  precision. Operand length is unbounded. There is no fixed limb count on that cleared precision path,
  unlike the engine's fixed 108-limb C width.
- Device arm: NTT multiply over the three Proth primes, reassembled by CRT (Garner), used only when
  both operands are at least 1024 limbs. That crossover is a measured floor, not a direction.
- That repository is private, and a citation from public `anchor_sift` into one of its paths resolves
  for nobody. All citations go to `theory_bucket/twiddle_constants_article.tex`, tracked in this public
  tree and on ePrint.

### Decision: the image_transforms translation prime

The translation NTT keeps `p = 998244353 = 119·2^23+1`, primitive root 3, diverging deliberately from
the device `2^27` primes:

1. `p` is below `2^31`. The `uint32` add and subtract-borrow wrap the paper documents cannot occur.
   The translation transform is the place a single small prime helps instead of hurting.
2. The `2^23` axis length is past any image axis.
3. A single 30-bit prime cannot hold an exact convolution of full 32-bit limbs: one coefficient
   exceeds `p` almost at once. This does not bite the translation NTT because it convolves binary
   views (0/1). Every coefficient `C(l)` is an agreement count.

The private repository's lead sharpened point 3. For 0/1 views each coefficient counts agreeing positions. It is at
most the transform length; the transform length divides `p-1` and is therefore below `p` for any valid
prime. A binary view is exact with no separate precondition. Weighting the views is what can breach
`p`: the bound becomes the sum of the weight products, and past `p` a single prime counts modulo
itself, silently. The remedy is a prime above the largest coefficient, or CRT over several, the
device path with its 94-bit product. The chapter states this bound as the design's own precondition.

## 2026-09-16 entry two: examples built and graded, engine decisions

The engine set placement and the bar: `examples/0_experimental/`, build both, each carrying a
positive control, two routes able to disagree, a drawn null, and a stated floor. Both are built and
run, exit 0:

- `examples/0_experimental/ntt_twiddle_certificate.py`: re-derives all five pinned moduli (positive
  control), refuses a composite of Proth shape (49 = 3·2^4+1), refuses a false primitive-root claim
  (9 on 998244353), and reproduces the fiddled twiddle: a root of half the order passes `w0=1`,
  `sum=0`, `sum^2=0` and the group law, and fails only the order test. That reproduces
  `twiddle_constants_article.tex` lines 163 to 179.
- `examples/0_experimental/exact_translation_by_ntt.py`: the NTT correlation equals the direct O(N^2)
  count at every one of 95 lags on binary views, and its argmax recovers the planted shift. The drawn
  null sets the true-shift peak against the best spurious peak between two independent views. The
  floor is drawn on weighted views: `p = 998244353` stays exact while the too-small prime 257 misses
  56 of 95 lags.

Both ran against a reference and agreed. The translation transform earns the grade word `agrees`.
The chapter header moves per transform: the translation is graded, and the integer-field and rotation
transforms stay design only under a header that no longer claims the whole chapter is unmeasured.

Routing confirmed with the engine (it commits; the specialist touches no git). All three targets sit
in the shared checkout of this repository, at its root, which is where the engine commits from. The
untracked-worktree wrinkle does not apply:

- `theory/workbook/precision_coordination_log.md` handed off as `workbook precision note`.
- `theory/image_transforms/chapters/chapter_exact_arithmetic.tex` handed off as
  `theory image_transforms note`.
- the two scripts and the updated README handed off as `examples experimental feature`.

## 2026-09-16 entry three: precision spread, the residue code, the check ladder

Douglas set a goal to raise the accuracy the engine holds by a large factor, a million and then past a
googol without bound, by a spread over exact identities, and asked every measurement session how it
takes exact measurement. Six answered. The survey and the theory are in
`theory/workbook/precision_spread_theory.md`. What was built and measured, each with a positive control,
two routes, a drawn null, and a stated floor:

- `examples/0_experimental/exact_identities_spread_precision.py`: exact identities carry precision from
  a few seed constants to unboundedly many. Checked by a second route (derived sqrt against a direct
  integer root to 240 places, pi by Machin against Euler, the ratio `5 zeta4 = 2 zeta2^2`). Null drawn
  (`sqrt6 = sqrt2 + sqrt3` refused). Floor measured (worst 65 units under a guard of `10^24`).
  Multiplier measured: 1,115,074 exactly-known constants per seed in the two-seed case, growing without
  bound.
- `examples/0_experimental/exact_residue_code_detects_uncertainty.py`: a redundant residue number
  system, an existing error-correcting code, on exact integers. Corrects one residue error, detects
  two, zero false alarms over 500 clean codewords. The exact range is the product of the moduli, up by
  more than a trillion per modulus near `2^40`, past a googol at nine of them, and unbounded.
- `examples/0_experimental/exact_check_ladder.py`: four checks stacked, each catching a fault the one
  below misses. Casting out nines misses a transposition and mod eleven catches it; a burst defeats a
  digit check and a cyclic redundancy check catches it; Hamming (7,4) corrects one bit and is defeated
  by two.
- `evidence/proofs/posits/proof_precision_spread.py`: the posit proved by constructed cases. A defined
  input carries to full scale, a measured input floors near its deposit, a measured value cancels in a
  ratio and is exact, a false identity is refused.

The three regimes, from the survey: defined quantities spread precision without bound; counting and
conservation quantities are exact but flat; measured quantities keep an upstream floor no identity
crosses, reached only through a floor-free ratio. The absolute floor is never arithmetic: the
representation imposes no quantum and has infinite variability, finer than any physical scale. The floor
is measurement and completeness, both external.

Handoff to the engine (it commits; the specialist touches no git): the five example scripts and the
README as `examples experimental feature`, `theory/workbook/precision_spread_theory.md` as
`workbook precision feature`, and `evidence/proofs/posits/proof_precision_spread.py` as
`evidence posits feature`.

## 2026-09-17 entry four: Navier-Stokes sets against the boundary function, inheritance checked

Douglas set the work: keep running their sets against our boundary function and check for inheritance,
claim nothing, show the rigor, ask the boundary function to define itself, cite what is borrowed with
respect. Built and run, each exit 0, each with a positive control, two routes, a drawn null, and a stated
floor:

- `examples/0_experimental/exact_navier_stokes_on_torus.py`: Fefferman's sets on the unit torus in the
  engine's exact integer arithmetic, Gaussian integers times powers of `pi` over one integer denominator
  per field, decimal inputs read by `representation.exact`; no fraction or math library, after Douglas
  refused a first build that used both. The ABC solution reproduced by the velocity recurrence and by
  the vorticity recurrence to the integer at orders 0 to 4; a generic datum's Taylor coefficients measured to
  outrun any fixed mode horizon (`|k|_1` climbs by one per order, 6, 18, 42, 88, 170 modes held); the
  energy identity exact at `t = 0`; the time and space scalings exact; the viscosity and force removals
  shown on instances; the countable island of nameable fields inside the data class (8).
- `evidence/proofs/posits/proof_boundary_inheritance.py`: the boundary kind read off each object by two
  probes (raise the scale, raise the horizon) in place of assigned by survey, with four positive controls
  of known kind and a null that shows the classifier's limit; their sets run through it; the inheritance
  of each kind through the chain `datum -> u_1 -> u_2 -> u_3` measured (format absent in the ring and
  introduced by the derivative in decimals, measurement carried exactly and canceled only by a ratio,
  completeness carried and growing); the disjoint-translate constructor's algebra shown by two routes
  with the overlapping null. It imports the ring from the example by path so one representation carries
  both.
- `examples/0_experimental/exact_navier_stokes_cascade.py`: the solution map made visible, on Douglas's
  ask to see the knot through their set definitions in place of re-proving it into the same knot. The mode
  front advancing one `|k|_1` shell per order (counts `6; 6,12; ...; 6,16,34,62,72,108`), the energy
  shells lighting up outward with the velocity and vorticity routes agreeing and Parseval summing them to
  the total, and the coefficient growth, an exact constant rate `4 pi^4/25` for ABC (entire, radius
  infinite) and a rising `pi`-degree `0,4,8,12,16,20` for a generic datum whose limit is a completeness
  boundary. Imports the ring from `exact_navier_stokes_on_torus.py`. Handoff `examples experimental
feature`, with the README row added there.
- `theory/workbook/navier_stokes_workbook.md`: the statement written down from the Clay PDF, read in
  full including the errata; the sets defined; what they knew, wanted and we know; entries 1 to 3, the
  sets on the torus, the boundary function, and the cascade; the inheritance tables; prior art named with
  respect; four withdrawn entries with what killed each. Handoff `workbook navier feature`.

Fefferman's statement was fetched from the Clay site and read in full for this entry, since the corpus at
`Downloads/millenium/` holds the five statements the Clay index listed as unsolved and not this one, as
the millennium book's corpus chapter records. The 2026 blowup paper was not read past what that book's
Navier-Stokes chapter read, and nothing here rests on it.

Handoff to the engine (it commits; the specialist touches no git): the script and the README row as
`examples experimental feature`, the posit as `evidence posits feature`, the workbook as
`workbook navier feature`, and this entry as `workbook precision note`.

## 2026-09-17 entry five: Birch and Swinnerton-Dyer, the congruent number reading

Douglas set the goal to pick up another Millennium problem. The choice is Birch and Swinnerton-Dyer,
which the millennium book's toolkit chapter already recommended, because its obstruction matches the
instrument: the refined conjecture is an exact numerical identity, and whether a computed number lands on
an integer is precision-bound. Same deliverable shape as Navier-Stokes: read Wiles's statement in full,
define the sets, run only the part exact integer and rational arithmetic honestly touches, claim nothing.
Integer-only, native ints and a reduced integer-pair rational, no fraction or math library. Built and
run, each exit 0:

- `examples/0_experimental/exact_congruent_number.py` (EXP-x-018): the congruent number problem, which
  sits on BSD. Tunnell's theta count, exact integers, reproduces Fermat's non-congruent 1 unconditionally
  and refuses 3, and matches the known status on 5, 7, 13, 15 (with the earlier wrong label on 15
  corrected). The elliptic-curve group law over `Q` is exact rational. The `n = 5` witness ties
  Fibonacci's triangle `(3/2, 20/3, 41/6)` to the infinite-order point on `y^2 = x^3 - 25 x`, whose
  double is non-integral (Nagell-Lutz), certifying congruence with no BSD. The analytic side, the L-value,
  period, and regulator, is the stated floor, and Tunnell's converse is flagged conditional on BSD.
- `evidence/proofs/posits/proof_group_law.py` (PRF-x-011): the rational points are an abelian group,
  exact, closure, identity, inverse, commutativity, associativity on two curves, the Z-module laws, and
  Nagell-Lutz integrality with the converse refused; a one-sign-wrong law fails associativity as the
  drawn null. Imports the curve from the example.
- `theory/workbook/birch_swinnerton_dyer_workbook.md`: Wiles's statement read in full; the sets defined;
  what they knew, wanted, and we know; the exact algebraic side against the computed analytic side, mapped
  to the precision document's regimes; the sets against the boundary function; prior art; one withdrawn
  entry, the 15 label.

Handoff to the engine (it commits; the specialist touches no git): the example and the README row as
`examples experimental feature`, the posit as `evidence posits feature`, the workbook as
`workbook birch feature`, and this entry as `workbook precision note`.

## 2026-09-17 entry six: the descent, the rank bound, and reaching Sha

Douglas set two follow-ons: push the descent through correctly, then attempt reaching the first part of
Sha. Both done, integer-only, validated before landing. The mechanism was steered by the anchor sift
engine: local solvability as a refute-only necessary-condition probe, the engine's sound one-directional
filter, with the Hensel level DERIVED from the form (2 v_p(J) + 1) and not a picked cap, the point that
keeps it clean under the tree's no-bounding rule. An earlier bounded mod-p^k search was dropped: it
picked a cap and, worse, a too-small cap under-counted the rank, the unsafe direction. The engine also
corrected a plan to draw a permutation null here; there is nothing to permute in a rank bound, and the
one-directional filter is the only engine principle that applies.

- `examples/0_experimental/exact_descent_rank.py` (EXP-x-019): the 2-isogeny descent giving a sound rank
  upper bound `dim Sel(alpha) + dim Sel(alpha') - 2`. Validated against known ranks over rank 0 and rank
  1: sound (bound >= rank) on every n, tight on all but n=17, and the over-approximation fallback never
  used (local solvability exact both ways). Two routes pin the rank where an explicit point's lower bound
  meets the upper bound. Then it reaches the first part of Sha: rank(E_17) = 0 unconditionally by Tunnell
  (A=16 != 8=2B); the image is then the torsion image, and the leftover dual-side Selmer classes 2, 17, 34
  are exhibited nontrivial elements of the Tate-Shafarevich group, each certified locally soluble by the
  probe and coming from no rational point. Positive control: Sha trivial where the descent is tight
  (n=5,6,7). Imports the curve and Tunnell's counts from exact_congruent_number.py. Handoff
  `examples experimental feature`, with the README row.
- `theory/workbook/birch_swinnerton_dyer_workbook.md`: new sections on the descent and on reaching Sha,
  the Open item narrowed to a full 2-descent for curves whose rank is not independently pinned. Handoff
  `workbook birch feature`.

Sound, exact, unconditional; claims only the rank upper bound and the exhibited Sha, nothing about BSD.
Handoff of this entry: `workbook precision note`.

## Open

- The delta/null theorist is revising `theory_bucket/delta_null` with the scan-arm family and the
  projection-soundness result. The NRR null cites `delta_null`; align the citation once the engine
  says the revision landed. (NRR is the noise reduction ratio, see the workbook.)
- The private repository's lead surfaced ways `exact_integer` would ingest CODATA constants wrongly and
  later corrected one: the width counts total digits not places (11 of 62 truncated constants refuse);
  the uncertainty is dropped (crystallography relies on that, now documented, with a new
  `from_measured`/`measured()` path coming but not yet on main); there is no divide. Derive outside
  the type and ingest finished text. The padding point was WITHDRAWN by that lead: `from_decimal` holds
  exactly the value of the text given, and padding 1000 places to 1024 is exact for that text; the
  fault is only a truncated expansion treated as the constant at a higher scale, a caller issue, not a
  code defect. All of this concerns `src/engine/c/no_rounding/exact_integer.{h,c}`, owned by the
  engine, and that lead handed the documentation fixes to the engine to land as `src exact bugfix`.
  None of it touches the image_transforms NTT, which works on integer views modulo `p`, not on decimal
  constant ingestion.
