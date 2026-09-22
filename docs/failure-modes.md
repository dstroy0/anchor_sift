# Failure modes, and the subtraction that removes each one

This is not a checklist. It is a sieve, and the operation is subtractive: each detector removes a
class of explanation for a number, and what is left after every subtraction is the residual. The residual
is the finding. That is the same operation as the Sigma-delta null - measurement minus what a null
would have given - applied to the apparatus and not to the data.

Fourteen modes are known, all of them from instances actually caught in this tree. **Every one of
them made a result look better than the truth.** Not one erred toward a weaker finding. That
asymmetry is itself the strongest reason to run the sieve instead of trust a number.

Status is one of: **built** where a mechanical detector exists and has been run tree-wide, **partial**
where a detector exists but has been applied only where a defect was already suspected, and **open**
where the mode is known and nothing yet catches it.

---

## 1. Absence read as measurement - *built*

Measuring a quantity that structurally cannot depend on the input, and reporting the resulting zero
or perfect agreement as a result.

**Caught:** H6 rotated the nonce, which enters at `W[3]` in round three, instead of the chaining
value, and reported a decay that never happened. H23 measured through `W[17]`, which does not depend
on `W[3]`, and reported 100.000% agreement, which was zero equalling zero. `bench_closeness` labeled
rounds 1–3 "premise holds: no" when the nonce had not entered yet.

**The subtraction:** `bench_reach.cpp`, and it is computed and not sampled. Every state bit
carries the set of input bits that can reach it, propagated through the real operations - rotation
permutes positions, shift drops them, bitwise operations union bit by bit, and addition unions
upward through the carry. Addition is the only widening operation, which makes this an
over-approximation: a path may carry no influence, but **the absence of a path is exact**. That
is the right side to err on for a precondition.

**What it settles.** The nonce reaches no state bit until four rounds have run, and saturates both
written words the moment it arrives:

| rounds run | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| bits of `state[0]` reachable from `W[3]` | 0 | 0 | 0 | 32 | 32 |

and in the schedule, `W[16]` and `W[17]` carry **zero** bits of `W[3]` while `W[18]` carries all 32 - 
which is right, since `W[18]` is the first word whose `W[t-15]` term is `W[3]`. Both of the defects
that produced H6 and H23 are visible directly in those two tables, and both would have been caught
before the measurement instead of after it.

**The control, run in the opposite direction.** An analysis that claimed reachability everywhere
would pass an absence test trivially, so both halves are needed. Over 24,000 random flips at rounds
one to six:

| | |
|---|---|
| pairs the analysis called unreachable | 21,257 |
| of those, a flip that changed the bit | **0** |
| pairs the analysis called reachable | 2,743 |
| of those, a flip that landed | 35.07% |

One violation in the first row falsifies the analysis outright. The second row has to sit away from
both extremes, and does.

**A structural fact that came free.** Every one of the 256 state bits reads all 768 input bits from
**round 21** on, the widest cone growing 256, 320, 352, 384, 416, … - thirty-two bits per round after
the first two, which is one schedule word arriving each round. This tree has never had that number
and it is exact.

## 2. Hand-derived null - *partial*

Comparing a measurement against an analytical reference derived by hand, where the derivation is
wrong.

**Caught:** H19's expected-worst-of-3840 gave a 5.47 sigma keyhole that fell to 4.19 and then to
nothing at 64x the samples. H24 modeled overshoot as geometric in nibbles and produced a 7.27x
excess; the target is not on a nibble boundary and the true figure is 1.0076. H29 and H31 compared a
max-statistic against a per-bin uniform and produced 775,000x where the permutation null gives 184.5x
 - inflated by about 4,200.

**The subtraction:** `Delta_Sigma[M] = M(x) - E_{pi ~ Pi_Sigma}[M(pi(x))]`. A permutation null cannot
be derived wrongly because it preserves the carrier's own counts by construction and not by
arithmetic.

**Status:** built in `bench_deltanull.cpp`, applied to one statistic. The keyhole scan's
expected-worst and the corpus-size ratios in H1 are both hand-derived and neither has been checked.

## 3. Asymmetric treatment of the two arms - *open*

Applying one operation to one member of a pair and a different operation to the other, so the
measured difference includes the difference in treatment.

**Caught:** H29 added `K` to one member and `rotr(K)` to the other and produced a 25.8% survival that
appeared to overturn H22. The same constant to both gives 0.000000%.

**The subtraction:** a swap test. Exchange the two arms and re-run. A statistic that is meant to be
symmetric must return the same number; one that is deliberately asymmetric must say so and say why.

## 4. Reading more output than the operation writes - *built*

**Caught:** H30 measured all eight output words when a SHA-256 round writes only `state[0]` and
`state[4]`. The six untouched words agreed trivially and the result read `P = 1.00000000`.

**The subtraction:** a write mask, in `bench_reach.cpp` beside the read set, since it is the same
question about what the circuit does. Every output word is assumed a copy of every input word, and
each of 2000 random trials removes the pairings that failed; what is left after every trial was carried
instead of written.

| rounds run | 1 | 2 | 3 | 4 |
|---|---|---|---|---|
| words written | 2 | 4 | 6 | 8 |
| words carried | 6 | 4 | 2 | 0 |
| share of an eight-word read that agrees for free | **75%** | 50% | 25% | 0% |

**H30 read all eight words after one round, so three quarters of its comparison agreed before the
round function was consulted.** Reading only the written words needs no correction factor and no
argument; it is just the right read.

## 5. Sample below the detectable effect - *open*

Running an experiment whose expected count under the hypothesis is far below one, and reporting the
absence of an effect as evidence.

**Caught:** H27 used `k = 8, 12, 16` at 400 states, where `k = 16` predicts 0.006 hits. Changed to
`k = 4, 6, 8` at 5000, with the detectable effect size printed alongside.

**The subtraction:** every bench prints its expected effect size and its detection floor *before* its
result. A null reads as "below the floor" and not as "absent".

## 6. Estimator ceiling set by sample size - *partial*

Reporting a plug-in estimate whose value is fixed by how many samples were drawn and not by the
distribution.

**Caught:** the Renyi order one half plug-in is `2 log2 sum sqrt(p)`. Where every observed value is a
singleton that sum is exactly `sqrt(n)`, so the estimate reads `log2 n` whatever the true entropy
is. At 2,000,000 pairs the ceiling is 20.93 bits and the estimate reads 18.25.

**The subtraction:** print the ceiling next to the estimate. Where they are close the estimate is
mostly sample size and is not a measurement.

**Status:** done in `bench_deltanull.cpp`. Every other sparse-sample estimator in the tree is
unchecked, and Good-Turing coverage is the obvious place to look next.

## 7. Degenerate pairs - *partial*

Constructing a pair that is meant to differ and failing to check that it does.

**Caught:** `bench_closeness` XORed at positions that were not distinct, so bits flipped back and some
pairs were identical. It printed "smallest output distance: 0 bits", which reads as a collision,
directly above prose saying nothing came close.

**The subtraction:** count and report the pairs whose intended difference is zero. A nonzero count is
a construction defect, not a result.

## 8. Optimiser-dependent result - *built*

A compiler folds, contracts, reassociates and hoists. A folded measurement is indistinguishable from
a computed one by reading the output.

**Caught:** `bench_engines` found an entire legacy engine that was a constant function. The tree-wide
audit then found three performance ratios that move with the build.

**The subtraction:** `tools/audit/audit_compiler.ps1` builds every bench three ways - `-O0`, `-O2`, and
`-O2 -ffp-contract=off` - and `tools/audit/audit_diff.py` compares outputs with stopwatch lines dropped.

**Result:** 19 of 22 judged benches are byte-identical across all three arms. The three that move are
all ratios of measured throughputs: extranonce cost 11.1x / 28.3x / 23.4x, expansion speedup 0.932x /
0.395x / 0.256x, delivery search-over-verify 1.08e19 / 5.46e19 / 6.15e19.

**What it does not close:** that a folded constant was folded *correctly*. For `bench_renyi` that is
settled separately by `tools/audit/verify_renyi.py`, which reimplements every printed prediction in another
language against another libm. Nothing else has that check.

**What chasing the last three stragglers turned up, which was worse than a folded constant.**
`kat_validation` and `bench_engines` produced no `-O0` output because they segfault there. The trace:

```
vmovdqa %ymm0,-0x20(%rbp)     rbp = 0x5fe0b0, so the target is 0x5fe090, which is 16 mod 32
```

`vmovdqa` is the *aligned* 256-bit move and requires 32. MinGW-w64 GCC at `-O0` hand-aligns a
pointer for one over-aligned `__m256i` local - the emitted `add $0x1f; shr $0x5; shl $0x5` is
visible in the prologue - and then places another at a fixed offset from a frame pointer it never
realigned. `-mstackrealign` changes the prologue not at all. **Nothing in this tree causes it and no
source change here avoids it**; the instruction is available and `-O2` runs it happily.

The resolution is that the `-O0` arm drops `-mavx2`. `sha256_core.c` gates its vector arm on
`__AVX2__` and the `#else` arm defers to the scalar reference, so the unoptimised build is the
reference arm - the arm a fold audit wants, since it is the arm whose arithmetic the
statistics read. `kat_validation` then runs `-O0` clean: **24 run, 0 failed.**

**And what that costs, which has to be said instead of buried.** For the two benches that exercise
the vector arm, the `-O0` column now tests different code from the other two columns, so agreement
there is evidence about the reference arm and not about the vector arm. The vector arm is covered
instead by `kat_validation` asserting it equal to the reference on the FIPS vectors, the genesis
block, block 125552 and 1000 consecutive real headers - which is a strong check, but it is a
different check, and reading the audit table as though all three columns meant the same thing for
those two rows would be exactly the kind of substitution this register exists to catch.

## 9. Prose contradicting its own table - *open*

**Caught:** H23's prose said the two "agree often" directly above a column reading 0.0000%.

**The subtraction:** every prose claim names the number it rests on, so the two can be compared
without re-deriving the claim.

## 10. Conflated quantities - *open*

**Caught:** `bench_exact` section 4 treated a characteristic - a product over one chosen intermediate
path - as a differential, the enumeration over all intermediates. Only the two zeros in that
table are informative.

**The subtraction:** naming discipline. Two quantities that differ get two names, and the name records
which one is meant.

## 11. Partial standing in for the whole - *partial*

**Caught:** reduced rounds in five benches, one output word of eight, a 64-bit prefix of a 256-bit
digest, one frame, one constant, chunk two without the header, sampling in place of enumeration.
Every one of these is a projection reported as the thing.

**The subtraction:** lead with the whole, and label a partial as partial in the same breath.
`bench_closeness` and `bench_renyi` are written that way; `bench_renyi` enumerates all `2^32` nonces
instead of sampling, and reads the whole 256-bit digest.

## 12. Max-statistic against a per-bin null - *partial*

Reporting the largest of many bins against the expectation for one bin.

**Caught:** the 775,000x of H29, corrected to 184.5x by H31.

**The subtraction:** the permutation null, or an extreme-value reference. Drawing `n` samples into
`r` bins gives an expected maximum well above `n/r`, and that expectation is the reference.

## 13. Argmax over a tied set - *partial, and freshly caught*

Selecting "the most common" value where many values share the top count, so the selection is made by
the sort's tiebreak and not by the data.

**Caught:** `bench_canary` steers a walk through delta space by following the most common outgoing
delta. Counting how many share that maximum:

| round | 0 | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|---|
| deltas tied at the peak | 1 | **12** | **21** | **19** | **17** | **29** | **17** |

From round one onward there is no single most common delta. Between twelve and twenty-nine of them
share a top count of two occurrences in 400,000 draws, and the walk follows whichever has the largest
numeric value. **The comparison between the peak-steered and tail-steered walks - the entire point of
that bench - is a comparison between two tiebreaks from round one on.**

**What remains:** the peak *value* is unaffected, since a tie does not change the height of the
maximum, only which delta carries it. The compound figure and H30's conclusion stand. The strategy
comparison does not.

**The subtraction:** count the ties at the argmax and print the count beside it. Done in
`bench_canary.cpp`.

## 14. A result that exists at one seed - *open*

Thirty-two of the fixed seeds in this tree are the same constant. A statistic that appears at one
seed and not at others is a draw, not a finding.

**The subtraction:** sweep the seed and report the spread across seeds beside the headline. The
detection floor is then measured instead of derived.

**Why it matters here:** the three-arm compiler audit already establishes that 19 benches are
deterministic - the same seed gives the same answer under three different builds. Determinism is not
stability. Nothing yet tests whether the answers move when the seed does.

## 15. The same formula written twice - *built, and it caught itself*

Two copies of one statistic, differing in a case one of them handles and the other does not.

**Caught, in the sieve's own instrument.** `bench_renyi` had three copies of the deficit sum: the
general one over bins, an inline one over the count histogram, and a third inside the Arikan block.
The empty-bin rule is opposite at order one and at every other order - a bin holding nothing
contributes exactly `-1` at a positive order and exactly `0` at order one, since the count in front
of the logarithm goes to zero faster than the logarithm goes to minus infinity. The general copy knew
both rules. The histogram copy applied the first rule to order one and put **0.2965 in a table where
0.8272 belonged**, on the headline full-domain run.

**Caught again, one layer out.** The Poisson prediction at order one was missing a `- log2(mean)`
term. That term is exactly zero when the mean count is one, the full-domain case, so the
wrong formula **agreed perfectly at the only point it was being read at** and disagreed everywhere
else. A defect that hides precisely at the operating point is the worst kind to leave in, and it was
only visible because a smoke run at a smaller domain existed.

**The subtraction:** one function, `deficit_term`, that knows the empty-bin rule for every order, and
every path goes through it. Not a check on the copies - the removal of the copies.

**A limit worth stating.** `tools/audit/verify_renyi.py` reimplements the predictions in another language
against another libm, and it is the check that closed mode 8's remaining gap. It carried the same
missing `- log2(mean)` term. An independent implementation written by the same author reproduces the
author's misconceptions faithfully; what it catches is transcription and folding, not a wrong idea.
The thing that caught the wrong idea was running at a domain where the term does not vanish.

---

## What the sieve has removed so far

| mode | detector | status | what it removed |
|---|---|---|---|
| 1 absence as measurement | exact reachability, `bench_reach` | **built** | 3 defects, and it predates them |
| 4 over-reading the output | write mask, `bench_reach` | **built** | 75% of H30's one-round read |
| 8 optimiser | three-arm build diff | **built** | 3 performance claims; 19 benches cleared |
| 14 one seed | seed sweep, `audit_seeds` | **built** | H22 confirmed not a draw |
| 15 formula written twice | one `deficit_term`, no copies | **built** | 2 wrong numbers in `bench_renyi` |
| 2 hand null | `Pi_Sigma` permutation | partial | a factor of 4,200 from the headline |
| 13 tied argmax | tie count at the peak | partial | the canary's strategy comparison |
| 6 estimator ceiling | ceiling printed beside estimate | partial | the order-1/2 plug-in as a measurement |
| 11 partial for whole | lead with the whole | partial | five reduced-round claims |
| 7 degenerate pairs | zero-difference counter | partial | a false 0-bit output distance |
| 3, 5, 9, 10, 12 | - | **open** | nothing yet |

Five modes are closed, five are partial, five have no detector. Of what remains, mode 3 (the swap
test) and mode 5 (printing the detection floor before the result) are both mechanical and are next.
Modes 9 and 10 are discipline instead of instrumentation and will not yield to a tool.

Mode 15 arrived last and deserves the most weight, because it was caught inside the instrument
built to catch the others. The sieve does not exempt itself. Both of its instances were found by
running the same code at a domain it was not designed around, the cheapest detector on this
whole list, and still not a habit: **run every bench at a second scale, and compare the shape
instead of the number.** A statistic that is a property of the function scales predictably; one that
is a property of the apparatus does not.
