# Dimensional Transform Workbook

**Purpose:** Record every hypothesis tested about the transform SHA256d undergoes over the nonce,
the
method used, the measurement obtained, and the verdict, so that a projection already ruled out is
not
re-derived and a projection not yet tried is visible.
**Scope:** `src/bench_corpus.cpp`, `src/bench_transform.cpp`, `src/sha256_core.c`,
`src/sha256_core.h`
**Owner:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08

## 1. The Problem As Stated

Mining searches for a nonce whose doubled digest falls at or below a target. Framed as a topology
mapping problem: find the projection under which the digest domain carries structure, so that the
information reaches the engine in a form the engine can sift.

`anchor-sift.md` §2.2 supplies the soundness half for free. An anchor is a necessary condition
copied
out of the pattern, so no selection rule can lose a true occurrence. That holds here and is not in
question anywhere in this document. §2.3 supplies the other half: a matching anchor establishes
nothing. A survivor still pays the exact compare.

What is in question is §2.5, the cost half. An anchor is priced at `q = 2^-H2`, and a filter is
worth
running when its bits can be read more cheaply than the full test. Every hypothesis below is an
attempt to find a projection where that holds.

## 2. Standing Constraint

The cost saving in a byte corpus comes from reading one byte instead of comparing a needle. In the
digest domain there is no corpus in memory: `D(n)` does not exist until it is computed, and
computing
it is the full test. So any projection that requires the digest as input cannot reduce the number of
SHA-256 evaluations, whatever structure it finds. It can only reduce work done per digest after the
digest exists.

A projection that beat this would have to read structure from the *nonce* without hashing it. That
is
a preimage-shaped claim about SHA-256, not an engineering task.

This constraint is why every hypothesis below is stated over the digest and measured for structure
and not assumed to yield speed.

## 3. Hypotheses Tested

### H1 - Corpus size governs survivor count

**Claim.** Survivors at a k-bit anchor track `N * 2^-k`, per §2.5.
**Method.** `bench_corpus.cpp:test_corpus_size`. Swept `N` from 2^20 to 2^26, `k` in {8, 12, 16,
20},
counting leading-zero-bit prefixes without early exit.
**Result.** Ratios converge on 1.0000. At `N = 2^26`: 1.0013, 1.0045, 0.9951, 1.0000 for
k = 8, 12, 16, 20.
**Verdict.** Supported. The cost model transfers to this domain exactly.
**Consequence.** No anomaly at any k. There is no scale at which the anchor over-performs.

### H2 - Entropy eddies somewhere in the full digest

**Claim.** Some bit or byte position carries a distribution away from flat. Sift the whole hash, not
the anchor window, since structure away from the leading bits would be invisible to the anchor and
still be real.
**Method.** `bench_corpus.cpp:test_entropy_eddies` over 16,777,216 digests. Per-bit one-counts
across
all 256 positions; per-byte-position histograms against uniform by chi-square on 255 df; global
collision entropy.
**Result.**

| statistic | measured | expected under flat |
|---|---|---|
| worst per-bit z | +3.05 (bit 107) | ~3.0 as the max of 256 fair coins |
| worst byte-position chi-square | 314.1 (position 12), z = +2.62 | 255 |
| collision entropy H2 | 7.999999 bits/byte | 8.000000 |

**Verdict.** Not supported at this sample size.
**Detection floor.** A per-bit bias of 4.9e-4 would show at four sigma. An eddy below that was not
ruled out and would need a larger sample.

### H3 - A repeating curve from the rotations

**Claim.** A probability set is a wave; a wave repeats. SHA-256's rotations are periodic, so some
nonce lag should show digests agreeing on more than half their bits.
**Method.** `bench_corpus.cpp:test_repeating_curve`. Bit agreement between `digest(n)` and
`digest(n+lag)` over 2,097,152 pairs, at 20 lags including every SHA-256 rotation amount
(2, 6, 7, 10, 11, 13, 17, 18, 19, 22, 25) and powers of two to 2^20.
**Result.** Worst |z| = 1.78 at lag 11. Standard error 4.3e-5.
**Verdict.** Not supported. No lag departs from 0.5.
**Detection floor.** A correlation above about 2e-4 would show at five sigma.

### H4 - Hitting time is geometric

**Claim.** First success should be geometric with mean `1/q`, per §2.5 read as Kac's lemma.
**Method.** `bench_corpus.cpp:test_hitting_time`. 512 independent digest streams at `q = 2^-16`,
recording the first nonce that clears.

**Result.**

| statistic | measured | geometric prediction |
|---|---|---|
| mean | 66,095 | 65,536 |
| standard deviation | 64,592 | 65,536 (equal to the mean) |
| median | 47,848 | 45,426 (`ln 2` times the mean) |

**Verdict.** Supported. The source is memoryless.
**Consequence.** This is the structural negative result. A memoryless source means no history
predicts the next draw, so no ordering of the nonce space is better than any other.

### H5 - The 2D boundary knows when it was rotated

**Claim.** Project the state onto its two dimensional boundary, eight words by thirty-two bits, and
transform along the bit axis. A cyclic rotation by `r` is multiplication by `exp(-2*pi*i*k*r/32)`,
so
the magnitude spectrum is invariant and the phase carries `r`.
**Method.** `bench_transform.cpp:check_rotation_identity`. Exact 32-point DFT, 256 random words and
random rotations, comparing magnitudes and phase against the predicted ramp.
**Result.** Largest magnitude drift 1.35e-13. Largest phase error 5.61e-13 rad.
**Verdict.** **Supported exactly.** The representation does know when it was rotated, to machine
precision. This is the same identity phase-correlation image registration runs on.

### H6 - That knowledge survives the rounds

**Claim.** If H5 holds, the rotation should remain readable downstream.
**Method.** `bench_transform.cpp:measure_rotation_memory`. Two chaining values differing by a
rotation of one word, same message block, run through `r` rounds; recover the rotation by circular
cross-correlation on the boundary, the phase reading computed in the cheaper domain by the
convolution theorem. 4096 trials per round count. Chance is 1/32 = 3.1%.
**Result.**

| rounds | recovered | vs chance |
|---|---|---|
| 0 | 100.00% | +356.3 sigma |
| 1 | 3.34% | +0.8 sigma |
| 2 | 2.66% | -1.7 sigma |
| 4 | 2.88% | -0.9 sigma |
| 16 | 2.47% | -2.4 sigma |
| 64 | 3.00% | -0.4 sigma |

**Verdict.** Not supported past round 0. The signal is total at round zero and at chance by round
one.
**Why.** Round one applies `Sigma0(a) = rotr(a,2) XOR rotr(a,13) XOR rotr(a,22)`. A single phase
ramp
becomes three different ramps summed, which is not a ramp. The modular addition then breaks what
remains, because carries cross bit positions and do not commute with rotation.

### H7 - Diffusion depth

**Claim.** Measure directly when one flipped input bit reaches half the state.
**Method.** `bench_transform.cpp:measure_avalanche`. 2048 trials per round count.
**Result.** 0% through round 3 (the nonce sits at schedule word three and has not entered yet), then
1.50%, 10.04%, 22.14%, 34.65%, 45.59%, and 50.00% at round 10. Flat at 50% thereafter.
**Verdict.** Saturation at round 10 of 128.

### H8 - Spectral flatness of the boundary

**Claim.** A structured state concentrates power in a few frequency bins.
**Method.** `bench_transform.cpp:measure_spectral_flatness`. Mean power per frequency over the 8x32
boundary, 4096 trials, geometric mean over arithmetic mean excluding the constant bin.
**Result.** Flatness 0.9356 at round 0 with peak/mean 1.90, rising to 0.999984 by round 8 and
0.999982 at round 64.
**Verdict.** Structure is real and measurable at rounds 0 through 4, and gone by round 8.

### H9 - A mod is linear too, in a different module

**Claim.** Addition modulo two to the thirty-second is not the nonlinear operation. It is linear
over
`Z/2^32`. The set `{0,1}^32` carries two module structures at once and each SHA-256 operation is
linear in exactly one of them.
**Method.** `bench_basis.cpp:measure_basis_linearity`. 100,000 random pairs per operation, testing
`f(x op y) == f(x) op f(y) op f(0)` in each structure.
**Result.**

| operation | linear over GF(2)^32 | linear over Z/2^32 |
|---|---|---|
| rotate right by 7 | 100.00% | 25.15% |
| xor a constant | 100.00% | 0.21% |
| add a constant | 0.02% | 100.00% |

**Verdict.** **Supported exactly.** This corrects the table in §4 as it stood before: modular
addition is not "nonlinear", it is linear in the other structure. A projection that diagonalises one
structure necessarily fails on the other, and a round applies both.

### H10 - The carry is the lift, and it is biased

**Claim.** `z_i = x_i xor y_i xor c_i` keeps the exclusive or in the GF(2) basis, and
`c_{i+1} = MAJ(x_i, y_i, c_i)` is the part that leaves it, recursing upward through every lower bit.
That recursion should show as a measurable bias.
**Method.** `bench_basis.cpp:measure_carry_structure`. 4,000,000 random pairs, counting the carry
into each bit position.
**Result.** The recursion `p_{i+1} = p_i/2 + 1/4` holds to four decimal places.

| position | measured | exact |
|---|---|---|
| 1 | 0.249511 | 0.250000 |
| 2 | 0.375026 | 0.375000 |
| 4 | 0.468800 | 0.468750 |
| 8 | 0.498034 | 0.498047 |
| 31 | 0.499937 | 0.500000 |

**Verdict.** **Supported.** This is the place in this workbook where structure is *found* instead of
 bounded. The carry into position 1 is a quarter, not a half.
**Consequence, and the limit.** This is the surface differential cryptanalysis of ARX
constructions works on, and it is why the published attacks reach the round counts they do. It is
also local: the bias halves per position and is under 0.2% by position 8, and each addition is
followed by a rotation that moves those low positions to where the next addition treats them as high
ones.

### H11 - Racing the two bases

**Claim.** If either structure holds a signal longer, a difference introduced in the basis an
operation is linear in should survive further in that basis.
**Method.** `bench_basis.cpp:measure_difference_survival`. A difference of 1 introduced in word zero
as an exclusive-or difference and as a modular difference, read back in the matching basis after `r`
rounds. Largest per-bit bias over all 256 state bits, 8192 trials. Five sigma is a bias of 0.0276.
**Result.**

| rounds | xor basis | modular basis |
|---|---|---|
| 1-7 | 0.5000 (90.5 sigma) | 0.5000 (90.5 sigma) |
| 8 | 0.4968 (89.9 sigma) | 0.2003 (36.3 sigma) |
| 9 | 0.0909 (16.5 sigma) | 0.0336 (6.1 sigma) |
| 10 | 0.0139 (2.5 sigma) | 0.0189 (3.4 sigma) |
| 64 | 0.0208 (3.8 sigma) | 0.0200 (3.6 sigma) |

**Verdict.** Both die at round 9 of 128. The exclusive-or basis holds marginally further at rounds 8
and 9; neither survives past 9.
**Consequence.** Picking the structure an operation is linear in does not help, because the next
operation is linear in the other one and the round applies both. That is the mechanism, measured.

### H12 - Walsh-Hadamard instead of Fourier

**Claim.** §5 of the previous revision flagged this as the obvious next projection, since the
Fourier
transform is diagonal for rotation and wrong for exclusive or.
**Method.** `bench_basis.cpp:measure_walsh_flatness`. Sequency power across the 8x32 boundary, 4096
trials.
**Result.** Flatness 0.9023 at round 0 with peak/mean 2.11, reaching 0.999973 by round 8 and
0.999962 at round 64.
**Verdict.** Not supported past round 8. Slightly more structure visible at round 0 than the Fourier
projection found (0.9023 against 0.9356), the right direction for an exclusive-or basis, and
the same collapse by round 8.

### H13 - A vector walk to the answer

**Claim.** Walk a vector toward the answer using the approximate representation. The most probable
next step carries larger magnitude than the rest, so following it converges.
**Method.** `bench_walk.cpp`. Fitness is leading zero bits of the doubled digest, the same
quantity the target tests. Three measurements: correlation between `f(current)` and `f(neighbor)`;
best-of-32-neighbors against best-of-32-unrelated; and a head to head against plain enumeration at
identical hash budget, with restarts allowed so the walk is tested in its strongest form.
**Result.**

| step definition | correlation | z |
|---|---|---|
| nonce + 1 | 0.001657 | +0.74 |
| flip one nonce bit | 0.000258 | +0.12 |
| unrelated nonce (control) | -0.000754 | -0.34 |

| | 32 neighbors | 32 unrelated |
|---|---|---|
| mean best score | 5.3631 | 5.3521 |
| mean gap, best to second | 1.4546 | 1.4305 |

Head to head over 24 runs of 1,048,576 hashes each: walk 20.500 mean best leading zeros,
enumeration 20.375. Walk wins 11, enumeration wins 11, 2 ties. Both sit on log2(budget) = 20, the
best of N draws from a flat domain.
**Verdict.** Not supported. Every step definition matches the unrelated-nonce control, so the domain
has no neighborhoods and steepest ascent is random sampling with a costlier step.
**Note on where this method does work.** The technique is sound wherever the landscape is
correlated, so it works on alphabet and word webs. Those corpora have H2 well under 8. The
digest domain measures 7.999999 by H2, and that measurement is the same statement as this one:
no neighborhoods.

### H14 - The round loses nothing

**Claim.** The intermediate steps are memoryless but still encode information perfectly.
**Method.** `bench_invert.cpp:demonstrate_bijection`. Implement the inverse round and round-trip it.
Given the state after round t and `W[t]`: six variables come straight back out of the shift, those
give both mixing functions, which give `carry_two`, which gives `carry_one` from word zero, which
gives the remaining two. Nothing searched, nothing approximated. 4096 trials.
**Result.** 64 rounds forward then 64 backward returns the exact starting state, every trial. The
file's forward round is separately asserted equal to the kernel's.
**Verdict.** **Supported exactly.** The mechanism is reversible end to end. "Memoryless" describes
the statistics of the output, not the process. Every bit that went in is still there.
**What it does not supply.** See H15.

### H15 - Mapping what is trackable

**Claim.** Map the operations so the missing one can be found.
**Method.** `bench_invert.cpp`. Enumerate what the mining problem gives and what it withholds, and
measure over how many rounds the entropy ceiling is constructed.
**Result, the ceiling.** One flipped nonce bit, fraction of state moved after r rounds: 0.00%
through
round 3 (the nonce sits at `W[3]` and has not entered), 1.52% at round 4, 9.81%, 21.66%, 34.23%,
45.16% at round 8, 49.41% at 9, and 49.97% at round 10. Flat thereafter.
**Result, the frontier.** The searchable input is **not** the nonce alone. Bounding it that way was
an error in the first revision of this entry and is corrected here. The miner controls:

| field | width | where it lands | effect |
|---|---|---|---|
| nonce | 32 bits | header 76-79, `W[3]` of block two | inner loop |
| extranonce2 | 64 bits here (pool sets the width) | coinbase, so the merkle root | changes the midstate **and** `W[0]` |
| ntime | ~13 bits of slack within the allowed window | header 68-71, `W[1]` | rollable |
| version | 16 bits under BIP320 | header 0-3, inside the midstate | rollable |

That is roughly **125 bits** of miner-controlled freedom, not 32. The freedom is necessary instead
of
 helpful: at difficulty 1.27e14 a solution needs about 76 bits of search. A 32-bit nonce alone
would exhaust without one. This is why extranonce2 exists and why `btc_miner.cpp` rolls it when the
nonce space is spent.

Within one fixed job and one fixed extranonce2, the frontier is:

| quantity | status |
|---|---|
| midstate H0, header bytes 0-63 | known, but only for this extranonce2 and version |
| W[0] merkle tail, W[1] ntime, W[2] nbits | known for this choice of them |
| W[3] nonce | unknown, 32 bits |
| W[4..15] padding and length | known, constant |
| W[16..63] | generated from W[0..15], so unknown |
| rounds 0, 1, 2 of hash one | computable without the nonce |
| round 3 onward | needs W[3] |
| hash two's message | is hash one's output, so needs all of it |

Forward frontier: 3 rounds of 128, and only with extranonce2 and version held fixed. Moving either
of those changes the midstate, so those 3 rounds have to be recomputed too. Backward frontier: 0
rounds, because inverting round t needs `W[t]` and every schedule word past 15 is generated from the
words being solved for.

**What is measured and what is not.** H13's landscape measurements were taken over the nonce
dimension. The extranonce2 dimension passes through strictly more hashing on its way into the header
 - a coinbase double hash plus a merkle fold per branch entry, 12 or 13 of them on the live jobs seen
here - before it reaches the same compression. There is no reason to expect less mixing there, but
it
has not been measured, and saying so is not the same as having shown it.
**Verdict.** The obstruction is named exactly, and it is not loss of information. It is circularity.
The inverse needs the message; the problem asks for the message. Invertible given the input is not
the same as solvable for the input.
**Consequence.** The ceiling is complete by round 10 and held for the remaining 118. That margin is
the design. Published preimage results reach about 52 of 64 rounds at complexity near 2^255, and SAT
approaches about 20 to 24 rounds. Every projection tried in this tree dies inside rounds 0 to 9,
the same seam.

### H16 - The extranonce2 dimension

**Claim.** H13 measured only the nonce. The extranonce2 dimension was asserted to behave the same
and
never measured, and the workbook said so.
**Method.** `bench_extranonce.cpp`, using a real `mining.notify` captured from solo.ckpool.org kept
verbatim, so the coinbase layout and the 12-entry branch are what a pool actually sends. A step here
rebuilds the coinbase, its double hash, every merkle fold, the merkle root, and therefore the
midstate.
**Control first.** Moving extranonce2 moves the merkle root, moves nothing else in the header, and
moves the midstate. All three confirmed before anything was concluded.
**Result.**

| step | correlation | z |
|---|---|---|
| extranonce2 + 1 | -0.002146 | -0.43 |
| flip one extranonce2 bit | -0.004623 | -0.92 |
| complement every bit | 0.014811 | +2.96 |
| unrelated extranonce2 (control) | -0.000818 | -0.16 |

**Verdict.** Not supported. Every step sits at the control. The complement step is the largest
deviation at +2.96 sigma, which over four tests is inside what chance produces and below the five
sigma bar used throughout this workbook; it is recorded instead of dismissed.
**Cost.** 2,014,362 nonce candidates per second against 83,947 extranonce2 candidates per second:
**a step in this dimension costs 24.0 times a nonce step**, plus 13 extra double hashes per
candidate
on the coinbase and merkle path. Even had it carried a landscape, a search would need the landscape
to pay for a 24x step.

### H17 - A thousand real solves as a known answer test

**Claim.** Check the implementation against the strongest available reference: block headers solved
by other people's hardware, whose hashes are on the chain.
**Method.** `tools/chain/fetch_blocks.py` pulls 1000 recent blocks from a public explorer;
`bench_chain.cpp` rebuilds each 80-byte header from its parts, hashes it here, and compares. The
explorer's own hash is not trusted: chain linkage is verified separately, and a corpus altered in
transit fails on linkage instead of passing against its own altered hashes.
**Result.** Heights 965,111 to 966,110.

| check | result |
|---|---|
| every header hashes to the hash the chain recorded | **1000 / 1000** |
| every solve satisfies its own nbits target | **1000 / 1000** |
| every block names its predecessor's hash as parent | **all links** |

**Verdict.** No inaccuracy in the implementation. This also independently confirms the byte orders
settled in §H15: version and time little-endian, both hash fields reversed, nbits expansion, and the
digest ordering the target compares against. The newest block in the corpus,
`00000000000000000001c529d4d08cde80a6d0c0cf5752150551c991838860cb`, is the same tip the live miner
decoded from a `mining.notify` prevhash, which cross-checks the stratum path against the explorer
path by two independent routes.

**Where real winning nonces land.** 1000 solves in 16 buckets across the nonce space, 62.5 expected
each: 74, 66, 65, 65, 69, 59, 62, 62, 82, 66, 58, 53, 62, 53, 58, 46. Chi-square 17.6 on 15 df
against an expected 15, z = +0.47. Uniform. These are real answers to the real search, and they land
nowhere in particular, so there is no region of the space a miner should prefer.

**Version rolling in the wild.** 616 distinct version values across 1000 blocks, which is BIP320
rolling being actively spent as a search dimension. That is direct evidence for the correction in
§H15: bounding the input to the nonce was wrong, and the network does not do it either.

### H18 - There is no noise floor, so stop quoting one

**Claim.** The digest field carries no background noise, because the information is held elsewhere.
**Why it is right.** SHA-256 is deterministic, so `H(digest | input)` is exactly zero. The flatness
is
not a noisy signal averaging out; it is pseudorandomness with no stochastic component at all. H14
already showed where the information is: preserved perfectly in the mechanism, recoverable by
running
the rounds backward.
**What it corrects.** Earlier revisions quoted a detection floor of 4.9e-4 as though it were a
property of the domain. It was a property of where the measurement stopped. In a natural corpus
irreducible noise eventually stops more data from helping. Here nothing does, and every added sample
tightens the bound without end.
**Method.** `cuda_miner.cu:survey_nonces` plus `bench_keyhole.cpp`, counting with warp ballots
instead of
 per-thread atomics, and a digest costs eight ballots per thread instead of 256 atomic adds.
**Result.** 4,294,967,296 digests in 3.9 s at 1.11 GH/s. Worst bit position 161, bias -2.015e-05,
-2.64 sigma, against an expected worst of about 3.0 over 256 positions.

| | detection floor at four sigma |
|---|---|
| earlier CPU survey, 2^24 | 4.9e-4 |
| this survey, 2^32 | **3.05e-5** |

**Verdict.** Sixteen times tighter, still nothing. The bound is now a statement about 4.3 billion
samples instead of about the domain.

### H19 - Salt the nonce and look for keyholes

**Claim.** Since the algorithm is known, choose salts from its own structure and sift the whole
digest
for a position that gives something away.
**Method.** `cuda_miner.cu:keyhole_scan`. For a fixed input salt, count how often each of the 256
output difference bits is set. Under a flat field every counter sits at half the sample. 15 salts,
most read off the algorithm instead of chosen arbitrarily: the Sigma0 rotation set {2,13,22}, the
Sigma1 set {6,11,25}, the sigma0 and sigma1 sets with their shifts, differences of rotation pairs,
round constant K[0], initial value word 0, and a golden-ratio constant the algorithm never uses as a
control.
**Result at 2^26 pairs.** One row crossed five sigma: salt `0x00000001`, bit 169, bias +3.338e-04,
**+5.47 sigma**. Every other row closed. Over 15 salts times 256 positions that is 3840 tests, whose
expected worst by chance alone is near 4.1 sigma, so 5.47 is above the bar but not far above it.
**Confirmation, the point.** The flagged row was retested at 2^32 pairs, 64 times the
sample. A real bias grows as sqrt(N), so 5.47 sigma should have become roughly 43 sigma.

| | worst position | bias | sigma |
|---|---|---|---|
| 2^26 pairs | 169 | +3.338e-04 | +5.47 |
| 2^32 pairs | **252** | +3.198e-05 | **+4.19** |

The worst position moved to a different bit entirely, the maximum fell instead of rose, and the bias
shrank by a factor of ten, the 1/sqrt(N) collapse of a bias whose true value is zero.
**Verdict.** Keyhole closed. It was an artifact of testing 3840 positions at once, and it is
recorded
here in full and not deleted, because a workbook that only keeps the rows that survived is not a
record of what was tried.
**Note.** This is the fourth instrument or interpretation error caught by a control in this
document.
It is also the one that would have been most tempting to report.

### H20 - Co-arm salts as a survivor divider

**Claim.** Run many salts as co-arms of one cascade, combine and diverge them, and let them sieve
themselves. The error tail falls toward zero.
**Method.** `bench_cosalt.cpp`. Six salts, five read off the algorithm's own rotation sets. For each
candidate, the leading difference bit under each salt is one arm's response. Four measurements: does
the cascade tail fall as 2^-k; are the arms independent of each other; is any joint response pattern
preferred; and the one that decides it, does the sieve keep winners.
**Result, the tail.** It falls exactly as predicted, 4,194,304 candidates:

| arms | predicted | measured | ratio |
|---|---|---|---|
| 1 | 2,097,150 | 2,093,386 | 0.99821 |
| 2 | 1,048,575 | 1,047,380 | 0.99886 |
| 4 | 262,144 | 262,988 | 1.00322 |
| 6 | 65,536 | 66,004 | 1.00714 |

Arms are independent: worst pair +2.71 sigma over 15 pairs, against an expected worst near 2.3.
Joint
occupancy of all 64 response patterns is flat, chi-square 82.6 on 63 df, z = +1.74.
**Verdict on the tail.** Supported, and it is arithmetic instead of a finding. Independent arms
halve
the survivors per arm by definition. The measurement confirms the arms really are independent, the
part that could have failed.

**Result, and this is the thing that matters.** Whether the sieve is worth running depends on
whether
what it keeps is enriched in winners. Measured against a 12-leading-zero-bit target:

| arms | survivors | winners | winner rate | enrichment |
|---|---|---|---|---|
| 0 | 4,194,304 | 1085 | 0.00025868 | 1.0000 |
| 1 | 2,093,388 | 547 | 0.00026130 | 1.0101 |
| 2 | 1,047,381 | 271 | 0.00025874 | 1.0002 |
| 4 | 262,988 | 72 | 0.00027378 | 1.0583 |
| 6 | 66,004 | 19 | 0.00028786 | 1.1128 |

Enrichment sits at 1.0 at every depth; the drift at depth 6 is 19 winners of small-number noise.
**Verdict.** The cascade discards winners at exactly the rate it discards everything else. It is a
survivor divider that divides the survivors you want along with the rest, and it costs six extra
hashes per candidate to do it.

**Why, stated against the paper's own theorem.** §2.2 makes an anchor sound because `A` is a
subconfiguration of `D`: a condition the pattern itself imposes. An occurrence must satisfy it and
none can be lost. A salt response is not in `D`. It is a property of the difference between two
candidates, not a condition the target places on one. The theorem therefore does not cover it, and
the measurement shows what happens without that cover: winners are lost in proportion.

**What would change this.** Enrichment rising with depth. That is a sound anchor does by
construction, and what a salt response would have to be shown to do by measurement. It is a single
column in the table above and it is flat.

### H21 - n dimensions at their intersections: algebraic degree

**Claim.** Everything measured so far was first order and one dimension at a time. Nothing looked at
intersections of difference directions.
**Method.** `bench_dimension.cpp`. A k-th order differential sums `f` over all `2^k` corners of a
k-dimensional cube of input differences. If the algebraic degree over GF(2) is below `k` it is
identically zero for every base point. A vanishing differential is a **proof** of a degree bound.
**Result.** Rounds 1-3 degree 0 (the nonce sits at `W[3]` and has not entered); round 4 degree
**exactly 3**; round 5 onward degree **at least 12**, past the table. Ceiling is 32.
**Verdict.** The only measurement in this workbook that proves something about the output instead of
bounding it. Degree goes from 3 to ≥12 in one round.
**Correction made in producing it.** Order `k` vanishes exactly when degree is *below* `k`, so the
degree is the **highest failing** order. The first version printed the lowest, which labeled every
row with any failure as "degree 1" and would have hidden the exact-3 result at round 4 entirely.

### H22 - Which element destroys the rotational relation

**Claim.** H6 measured that a rotational relation dies after one round, a fact about the
whole construction and does not say which part did it. Published rotational cryptanalysis
(Khovratovich and Nikolic, FSE 2010) names round constants as the element that breaks rotational
pairs, predicting that a constant-free variant should survive far.
**Method.** `bench_ablation.cpp`. Remove one element at a time and re-measure strict rotational
survival, with the prediction written down before each run.
**Result.**

| variant | r=1 | r=16 |
|---|---|---|
| BASELINE, real SHA-256 | 0.00% | 0.00% |
| constants removed | **0.00%** | 0.00% |
| constants rotation-invariant | 0.00% | 0.00% |
| addition replaced by xor | 0.00% | 0.00% |
| **no constants, no addition** | **100.00%** | **100.00%** |
| no constants, no mixing | 0.00% | 0.00% |

**Verdict. The prediction failed.** Removing the constants changed nothing. Only the variant with
neither constants nor modular addition survives, so both elements are structural and the constants
were given sole credit in error.
**The correction, and it is quantitative.** The theory does not say addition preserves the relation.
It says addition preserves it with a probability and computes that probability:
`P = (1/4)(1 + 2^(r-n) + 2^(-r) + 2^(-n))`. Measured over 4,000,000 trials at r=4, n=32:

| | value |
|---|---|
| measured | 0.265280 |
| predicted by the formula | 0.265625 |
| difference | -0.000345 |

A round applies about six additions, so per-round survival is `0.265280^6 = 3.485e-04`, giving 1.43
expected survivors in a 4096-trial table. The row read 0.00% because the relation was destroyed by
the **additions**, at a rate the table had no resolution to see. Rotation, exclusive or and the
Sigma
functions are all rotation-equivariant and cannot break it; the additions and the constants can, and
both do.
**What this buys.** The mechanism behind H6 is now named and quantified and not only observed,
and a published formula is confirmed against this code to four decimal places. It does not weaken
anything: the constants are not optional and nobody chooses them at mining time.

### H23 - The message schedule as a linear code

**Claim.** Every projection so far attacked the compression function. The schedule is a weaker
object:
`sigma0` and `sigma1` are rotations, shifts and exclusive or, so both are GF(2)-linear, and only the
three modular additions per word leave that basis. It is also where the one real structural win in
Bitcoin mining lives, since ASICBoost exploits the schedule's independence from the chaining value.
**Method.** `bench_schedule.cpp`. Confirm the linearity, measure the real expansion against its
xor-linearised twin on dense values and on sparse differences, and trace the mining case exactly.
**Result, linearity.** Confirmed over 200,000 pairs for both spread functions, and the linearised
expansion is linear as a whole map over 20,000 blocks.
**Result, dense values.** 0.0000% exact agreement at W[16] and every word after. Mean Hamming
distance 767.8 of 1536, which is 50% and therefore two unrelated values. Four dense random addends
nearly never sum without a carry.
**Result, sparse differences.** This is the question attacks ask, and the answer has shape. Measured
per word from W[18], the first expanded word the nonce reaches:

| weight | W[18] | W[19] | W[20] | W[21] | W[22]+ |
|---|---|---|---|---|---|
| 1 | 14.487% | 7.442% | 0.054% | 0.011% | 0.000% |
| 2 | 3.110% | 0.766% | 0.002% | 0.001% | 0.000% |
| 4 | 0.340% | 0.027% | 0.000% | 0.000% | 0.000% |

**Verdict.** The linear code describes the schedule for exactly two words past where the input
enters, then collapses by a factor of 140 in one step at W[20], which is where the difference first
re-enters through `sigma1` and is spread.
**Result, mining case, exact and not sampled.** Of 16 input words, 12 are literal constants.
Tracing which expanded words depend on W[3]: only **W[16] and W[17]**, so 2 of 48. Rounds computable
before the nonce is needed: 3 of 64. Measured speedup on the expansion alone: **1.033x**, roughly a
quarter of that end to end.
**Corrections made in producing it.** Two, both the same shape. The first table measured agreement
through W[17] and got a perfect 100% at every weight, which was zero equals zero because W[16] and
W[17] do not depend on W[3] at all. The prose also claimed early words "agree often" directly above
a
column reading 0.0000%.
**The lesson, the valuable part.** 1.033x against ASICBoost's ~20% is the gap, and the gap
is the finding. ASICBoost does not hold the nonce variable and share the remainder. It makes chunk
two byte-identical across candidates by varying the merkle root or version instead, so all 48 words
are shared instead of 2. The win comes from **choosing which dimension to vary**, not from analysing
the one everyone already varies.

### H24 - The chain as an iterated map

**Claim.** Every test so far lived inside one header's nonce space. Block N's hash is literally a
field of block N+1's header, so the sequence is an iterated map `h(n+1) = F(h(n), rest(n))`, and
iterated maps have orbits, recurrences and periods.
**Stated before measuring.** A block hash is not a uniform 256-bit value. It is conditioned on
clearing the target, so the top ~76 bits are forced and only the remainder is free. Every test uses
the free bits, because a test on the whole hash finds very large structure that is entirely the
conditioning.
**Method.** `bench_chainmap.cpp` over the 1000-block corpus.
**Result.**

| test | result |
|---|---|
| lag correlation of free 64 bits, 12 lags from 1 to 233 | worst **+1.79 sigma** at lag 3 |
| overshoot beyond target, against uniform-below-target | 76 bits 1.0000, 80 bits 1.0076, 84 bits 0.9609 |
| consecutive winning nonce correlation | -0.0147, **-0.46 sigma** |
| power spectrum, 499 bins | peak/mean **5.961** against 12.429 expected |

**Verdict.** No long-range structure at this sample size.
**Correction made in producing it, and the most spectacular-looking of the programme.** The first
version modeled the overshoot as geometric in nibbles, predicted 58.6 blocks at 80 leading zeros,
measured 426, and reported a **7.27x excess**. The target is not at a nibble boundary: nbits
`0x1702355e` puts it near 2^177.14, so P(clearing 80 bits) is 2^176/2^177.14 = 0.454 instead of
1/16. Using each block's own nbits the ratio is 1.0076. The entire effect was a boundary I had not
accounted for.
**Why no orbits were ever likely, which is structural instead of statistical.** An autonomous map
`h -> F(h)` has orbits. This one is `h(n+1) = F(h(n), rest(n))` where `rest` carries a fresh
coinbase
and a fresh nonce chosen by whoever mined that block. Fresh entropy enters at every step, so it is a
Markov chain with injection instead of a dynamical system, and a system with injection cannot recur.
**Bound instead of proof.** 1000 blocks cannot see a period longer than about 500, and the corpus
spans one difficulty adjustment.

### H25 - Co-arms across the field: relational against absolute

**Claim.** Instead of setting pins in sequence, which H27 shows is impossible here, set them all at
once across the field using many co-arms.
**The theorem behind it, which is real.** Co-arms buy a quadratic gain when the win condition is
*relational*, satisfied by a pair of arms agreeing. N arms make N(N-1)/2 pairs, so events grow as N
squared while work grows as N. That is the birthday bound and it is why a collision against a
256-bit hash costs 2^128 instead of 2^256.
**Method.** `bench_coarms.cpp`. Both conditions measured on identical digests, matching on 24 bits.
**Result.**

| arms N | pairs found | birthday N^2 | below target | linear N |
|---|---|---|---|---|
| 8192 | 1 | 2.000 | 0 | 0.00049 |
| 16384 | 6 | 8.000 | 0 | 0.00098 |
| 32768 | **32** | **31.999** | **0** | 0.00195 |

The pair column tracks N squared to three decimals. The advantage is exactly N/2, here 16384,
growing
without bound.
**Verdict.** The gain is real and very large, and mining cannot spend it. A share is a header whose
digest is at or below a target the pool sets; the pool re-hashes that one header against that one
number. Two of your candidates agreeing with each other is not a fact about the target and there is
nowhere to submit it. The birthday bound finds two inputs that agree; proof of work asks for one
input that is small.
**Consequence, which explains H20 from the other side.** The co-arm salt cascade divided winners
along with everything else because a cascade of arms is relational by construction while the target
is absolute, so the arms filtered on a property the target does not care about.
**The counterexample that proves the rule.** Equihash is a collision-finding proof of work, designed
relational precisely so memory and the birthday bound matter, and specifically to resist the
hardware
Bitcoin's absolute target rewards. Bitcoin chose the other side deliberately.

### H26 - What the human encoded, and what delivery requires

**Claim.** A human invented this and humans encode things in what they invent, so there should be a
designer's fingerprint. Separately: if we know the nonce we can rehash and rederive the solution, so
what is the problem?
**Method.** `bench_delivery.cpp`. Derive every constant from the primes; time verification against
search; test whether a known solution transfers to another header.
**Result, the fingerprint.** All 72 constants derive exactly:

| | |
|---|---|
| 64 round constants from cube roots of the first 64 primes | **64 / 64** |
| 8 initial values from square roots of the first 8 primes | **8 / 8** |

`cbrt(2) -> 0x428a2f98`, `cbrt(3) -> 0x71374491`, and so on. The entire fingerprint is the first 64
primes, two root functions and a truncation.
**Verdict on the fingerprint.** These are nothing-up-my-sleeve numbers and the choice is the point.
A freely chosen constant could hide a trapdoor only its chooser knows; a constant forced to equal
`cbrt` of the seventeenth prime cannot, because anyone can rederive it and no freedom remains to
hide
anything in. **What the human encoded is a proof that they encoded nothing else.** That is the
opposite of obfuscation.
**Result, verification against search.**

| | |
|---|---|
| verifying one known answer | 8.08e-07 seconds |
| finding one, RTX 3070 | 2.90e+14 seconds, or 9.2 million years |
| ratio | **3.59e+20** |

**Verdict.** That ratio is not an obstacle to the design, it is the design. So "if we know the
nonce"
is not a step toward the answer; it is the answer, already held.
**Result, transferability.** Block 125552's real nonce, with one merkle bit flipped, the
least a different coinbase does: leading zeros fall from ~64 to **0**, against a target needing 60.
The merkle root commits to the coinbase and the coinbase carries the payout address, so putting your
address in it invalidates every nonce anyone has ever found. That binding makes the work
belong to the payee instead of being transferable and worth nothing.

### H27 - Does the lock retain a set pin? The rake question

**Claim.** A rake defeats a pin tumbler lock because the lock retains partial progress: tolerances
make pins bind in sequence, the lock reports a set pin through feel, and a set pin stays set while
the next is worked.
**Method.** `bench_walk.cpp` section 4. Take a nonce whose digest already carries k leading zeros,
perturb it, and ask whether the zeros survive. Above chance means a pin that stays set.
**Result.**

| k | chance | flip 1 bit | nonce + 1 | unrelated | detects |
|---|---|---|---|---|---|
| 4 | 6.2500% | 6.1800% | 6.6600% | 6.3400% | a 1.3x effect at 5 sigma |
| 6 | 1.5625% | 1.4200% | 1.5400% | 1.5200% | a 1.6x effect |
| 8 | 0.3906% | 0.3200% | 0.3400% | 0.3800% | a 2.1x effect |

**Verdict.** No binding order, no feedback, no retention. All ~76 pins must be set in the same
instant and setting 40 is worth exactly nothing toward the 41st.
**Correction made in producing it.** The first version used k = 8, 12, 16 with 400 set states, which
expects 0.006 retained hits at k=16. Those zero columns said nothing at all and would have read as a
strong result. The k values here are chosen for statistical power and the detectable effect size is
printed beside each row.
**Connection.** This is the geometric hitting time of H4 seen from the other side: a memoryless
process is precisely one with no partial progress to retain. Two measurements, one property.
**The analogy's own answer.** A rake exploits manufacturing tolerance, and all three of its gifts
come from the lock being imperfect. This lock has no tolerances. It is a combination dial with no
click.

### H28 - Riding the rotating frame

**Claim.** Treat `rotr` not as an operation on the data but as the field turning under the observer.
Sit in the turning frame and `rotr` is the identity; everything else is re-expressed there.
**Method.** `bench_frame.cpp`. Sweep all 32 frames with nothing assumed about which, if any, is
preferred.
**Result, one addition.** The spectrum is real and symmetric, and the sweep found the optimum
without
being told:

| frame | holds | frame | holds |
|---|---|---|---|
| 1 | **0.375140** | 31 | **0.375375** |
| 2 | 0.312478 | 30 | 0.312477 |
| 4 | 0.265483 | 28 | 0.265651 |
| 16 | 0.249910 | | |

Frames 1 and 31 are genuinely **1.5x** better than frame 16. A preferred frame exists and riding it
costs nothing.
**Result, one full round.** Constants removed, frame 31 holds at 0.022208 and every other frame is
at
or near zero. **With the constants present, all 32 frames read 0.000000** over 400,000 trials.
**Result, riding it.** Constants removed, frame 31: 2.2226% at one round, 0.07955% at two, 0.00235%
at three, 0.00005% at four.
**A small real positive.** Measured exceeds `p^n` by about 1.6x at round two and 2.1x at rounds
three
and four, so successive rounds are slightly positively correlated in the frame instead of
independent. That is a genuine structural effect and it is the thread H29 pulls.
**Verdict.** Extrapolating the measured per-round rate: 2.249e-212 over 128 rounds against brute
force at 8.636e-78. Riding the best frame for the depth a header hash runs is about **4e133 times
less likely to succeed than guessing**. The frame exists, the sweep finds it, riding it is free, and
it is catastrophically worse than never bothering.
**What the frame change actually did.** It is legitimate and destroys no information. It relocates
the cost: `rotr` becomes free and in exchange addition acquires the 0.265 to 0.375 correction and
the
constants acquire an apparent counter-rotation. The total is conserved.

### H29 - Pulling the thread: is the correlation usable?

**Claim.** H28's round-to-round correlation is the only positive signal besides the carry bias.
Posit
raised during the work: the error is recursive.
**Method.** `bench_thread.cpp`, four pulls in order of what they would be worth.
**Pull one, recursion. Supported.** Conditioning at each depth instead of waiting for rare
survivors, so every depth carries the same statistical weight:

| round | conditional | vs base |
|---|---|---|
| 2 | 3.5595% | **1.567x** |
| 4 | 2.9770% | 1.311x |
| 8 | 2.8125% | 1.238x |
| 12 | 3.2150% | 1.415x |

It holds at 1.2x to 2.1x over twelve rounds instead of decaying to 1.0. Surviving selects states
that
keep surviving. **The posit is confirmed.**
**Pull two, the signature. Supported.** Every predictor among 288 input bits is **bit 31**, the wrap
position for frame 31, at up to **+238 sigma**. Message bit 31 is set in only 10.03% of survivors
against a 50% base.
**Pull three, steering. Supported, then defeated.** Clearing the top bit of every word lifts
survival
from 2.23% to **21.25%**, a 9.5x per-round gain; setting it drives survival to zero. Against the
real
constants, **0.000000% across every construction** at 2,000,000 trials each.
**Pull four, keeping the delta. Supported.** Rotational-XOR: instead of demanding the delta be zero,
which the constants defeat, track it. Against the real constant, 580,180 distinct deltas in
4,000,000
trials, the most common at **0.01805%** against 2.33e-08% uniform, a concentration of **775,000 over
uniform**. Real information where exact equality had none.
**Verdict.** Five of seven sub-questions positive, and 162 orders of magnitude short: the RX
characteristic is 2^-12.4 per round where 2^-4 is needed to match brute force over 64.
**Two corrections made in producing it.** Section 3b first added `K` to one member and `rotr(K)` to
the other, which rotates the constant with the frame, preserves the relation by construction, and
reported 25.8% survival that appeared to overturn H22. And the predicted RX offset `K xor
rotr(K,31)`
did not match the observed `0x428a5095`, because the constant enters `carry_one` and passes through
mixing before reaching word zero.

### H30 - The careful sweep: every frame, every word, every constant

**Claim.** A single point is an anecdote about a space. H29's RX number was one frame, one delta,
one
constant, one output word.
**Method.** `bench_sweep.cpp`. Enumerate what is enumerable and state what is not.
**Result.**

| | |
|---|---|
| strongest single round | frame 6, word 4, P = **0.00202667** |
| across all 64 constants | best 0.00507, worst 0.00003, **mean 0.00071** |
| chained 8 rounds, geometric mean | **1.36e-05 = 2^-16.17** |
| needed to match brute force over 64 | 2^-4 |
| shortfall | **12.17 bits per round** |
| over 64 rounds | 3.572e-312 against brute force 8.636e-78 |

**Verdict.** 234 orders of magnitude short, and the chain does not chain: round zero gives 0.002
because the incoming delta is zero, and every round after collapses by about 300x. A nonzero
incoming
delta is worth far less than a zero one, so published searches need backtracking instead of
 greed.
**Correction made in producing it.** The first sweep measured all 8 output words and reported
**P = 1.00000000 at every frame**. A round writes only `state[0]` and `state[4]`; the other six are
shifts of the input, trivially rotational on output, and they outvoted the two real ones.
**Coverage, stated instead of implied.**

| swept completely | |
|---|---|
| frames | 31 of 31 |
| output words | 2 of 8, the other 6 being words a round never writes |
| round constants | 64 of 64 |
| combinations | 3,968 |

| not swept, not sweepable | |
|---|---|
| incoming delta, one word | 2^32 values, walked greedily at 8 points |
| incoming delta, full state | 2^256 values |
| fraction of the delta axis visited | **1.86e-09** |

**Resolution floor.** At 300,000 pairs the smallest measurable probability is 3.33e-06, and the
chained rounds sat at 6.67e-06, which is two occurrences. Those rounds are at the floor, so the
compound is an upper bound on a quantity that may be smaller instead of a measurement of it.
**Standing.** This is a lower bound on what is reachable, not an upper bound on what exists. A
better
trajectory may sit in the 99.9999999% never visited and nothing here rules that out.

### H31 - The Sigma-delta null, turned on this tree's own headline

**Claim.** Every error in this workbook has one shape: a measurement compared against an analytical
null derived by hand, where the null was wrong. The nibble-geometric overshoot, the
`K xor rotr(K,r)` offset, and the expected-worst-of-3840 estimate were all hand-derived, all wrong,
and each produced something that looked like a finding.
**The instrument.** From `anchor_sift/docs/research/terms.md` and `anchor-sift.md` §2.1. Let
`Pi_Sigma` be the permutations preserving the observed carrier counts and stated partition. For a
statistic `M`, the residual is

`Delta_Sigma[M] = M(x) - E_{pi ~ Pi_Sigma}[ M(pi(x)) ]`

A permutation null cannot be derived wrongly, because it preserves the carrier's own counts by
construction and not by arithmetic.
**Method.** `bench_deltanull.cpp`. `M` is the concentration of the most common rotational-XOR delta,
the statistic H29 reported as the programme's strongest positive. `pi` re-pairs the two members
while
leaving both output multisets exactly as measured. If the concentration lives in the *pairing* it is
real structure; if it lives in the *marginals*, a permutation preserves it and the residual
vanishes.
**Result.** 2,000,000 pairs, 12 null draws.

| | |
|---|---|
| M(x), the real pairing | 0.01845000% |
| E_pi[M(pi(x))] | 0.00010000%, identical on all 12 draws |
| Delta_Sigma[M] | +0.01835000% |
| **ratio, measured over null** | **184.50** |

**Verdict, and it is a correction to this workbook's own headline.** H29 reported the RX
concentration as **775,000 times uniform**. That compared a max-statistic against a per-bin uniform
probability, the wrong reference: drawing 2,000,000 samples into 2^32 bins gives an expected
maximum count of two or three by chance alone. That is the 0.0001% the permutation null
returns. **The correct figure is 184.5x, not 775,000x.** The headline was inflated by about 4,200.
**What remains.** The residual is real. All twelve null draws returned the same value, so the null
has nearly no variance at this resolution and 184.5x sits far outside it. The rotational pairing
does carry structure the marginals do not.
**What does not change.** The 234-orders-short conclusion in H30 was computed from the probability
1.845e-04, not from the concentration ratio, so it stands untouched. Only the framing was wrong.
**Standing recommendation.** Every statistic in this workbook that was compared against a
hand-derived
null should be re-run against `Pi_Sigma`. The ones with an outside reference - the 1000 real solves,
the FIPS vectors, the published rotational-probability formula - do not need it. The ones without,
including the keyhole scan's expected-worst and the corpus-size ratios, do.

### H32 - The Renyi order axis, and the order this workbook has been reading

**Claim.** Every entropy in H1 through H31 is collision entropy, Renyi order two. Order is a
continuous axis and it has never been varied. Order two was not chosen for a reason; it is what a
collision counter measures and a collision counter was what was to hand.
**The instrument.** Renyi entropy `H_alpha = (1/(1-alpha)) log2 sum p^alpha`, which is strictly
decreasing in alpha unless the distribution is uniform. Each point of the axis answers a different
question about the same distribution:

| order | reads | question |
|---|---|---|
| `0` | size of the support | how many values never occur - **the holes** |
| `1/2` | `sum sqrt(p)` | **cost of guessing**, by Arikan's bound |
| `1` | Shannon | information content |
| `2` | collision probability | cost of colliding - **everything measured so far** |
| `inf` | largest single probability | **the biggest bump** |

Arikan (IEEE Trans. Inf. Theory 42(1):99–105, 1996) bounds the expected number of guesses under the
optimal ordering by `E[G] <= (2^{H_{1/2}} + 1)/2`. Search cost is governed by order one half, whose
defining sum is over square roots and is therefore dominated by the many small probabilities instead
of
 the few large ones. **The cost of searching is a tail statistic, and order two is blind to
exactly that.** Full derivation and sources in `docs/information-theory.md`.
**Method, part one - what a flat plane predicts.** Writing bin counts as `c_i = m(1 + e_i)` with
`m = d/r` the exact mean, the deficit expands to `log2 r - H_alpha = alpha var(e) / (2 ln 2)` with
`var(e) = (r-1)/d` exactly for a multinomial. The deficit profile of a random function is a straight
line through the origin in alpha, which gives a test with no free parameter:

`deficit(2) / deficit(1/2) = 4` exactly

Domain size, bin count, window position and sample count all cancel out of a ratio between orders.
**Method, part two - enumeration, not sampling.** `bench_renyi.cpp`. All `2^32` nonces of the block
125552 header, whole SHA256d over all eighty bytes, whole 256-bit digest read. Windows of 8 bits at
all 32 positions, 16 bits at all 16 positions, and 32 bits at digest bytes 0–3, which over a `2^32`
domain is the only family where a bin can be empty and is therefore where the holes are.
**Controls.** Three, because one control can only fail in one direction. A fixed digest must report
exactly `log2(bins)` at every order and does, spread zero, at any domain size. The nonce repeated
eight times must report exactly zero at the full domain and does, spread zero. A splitmix64 chain
must report the prediction instead of zero, and at `2^32` returns ratio 0.989 at the byte windows
and 1.003 at the sixteen-bit windows, with

`deficit(2)/deficit(1/2) = 3.999987` and `3.999929`

confirming the parameter-free prediction to six significant figures over an completely enumerated
domain.
**Result, and it is a correction instead of a discovery.** `H_alpha` decreasing in alpha means
`deficit(1/2) <= deficit(2)` always. Every figure in this workbook of the form "collision entropy is
X bits below uniform, so there are X bits of advantage" answers the collision question while being
read as an answer to the search question, and it is the more generous of the two. The concrete case
is H22's rotational coherence:

| | |
|---|---|
| `H_2`, estimable from a sparse sample | 16.503259 bits |
| deficit at order 2, the collision figure | **15.496741 bits** |
| `H_1/2` plug-in | 18.254864 bits |
| ceiling on that plug-in from sample size alone | 20.931569 bits |
| `H_inf` | 12.404092 bits |
| unseen mass, `f1/n` | 0.093500 |

The ordering `H_inf < H_2 < H_1/2` is monotone in the right direction, the internal
consistency check. **The 15.497 bits is the collision advantage. The search advantage is at most
that and is smaller.**
**What cannot be said, and why it matters.** Order one half is not estimable from a sparse sample.
The plug-in is `2 log2 sum sqrt(p)`, and where every observed delta is a singleton that sum is
exactly `sqrt(n)`, so the estimate reads `log2 n` whatever the true entropy is. At 2,000,000 pairs that
ceiling is 20.93 bits and the plug-in reads 18.25, close enough to it that the number is mostly
sample size. `bench_deltanull.cpp` now prints the ceiling beside the estimate so the artefact cannot
be read as a measurement. **The only place order one half is exactly computable is where nothing is
sampled**, the whole reason `bench_renyi` enumerates.
**Verdict.** The axis is real, the prediction along it is parameter-free, and the estimator is
validated in both directions by controls. The workbook has been reading one point of a family and
quoting it as the answer to a question a different point answers.

### H33 - Which results survive the optimiser

**Claim.** A compiler folds, contracts, reassociates and hoists. Where it folds a measurement into
an immediate the bench prints a compile-time answer while appearing to compute one, and that is not
detectable by reading the output. `bench_engines` already caught an entire engine that was a
constant function; nothing structural stops the same happening to a statistic.
**Method.** `tools/audit/audit_compiler.ps1` builds every bench and `kat_validation` three ways and runs
all three: `-O0`, which folds, hoists and contracts nothing; `-O2`, the flags this tree was built
with; and `-O2 -ffp-contract=off`, since GCC fuses multiply-add by default and that changes
rounding.
`tools/audit/audit_diff.py` compares the outputs after dropping stopwatch lines, because a bench built at
`-O0` runs slower for reasons that have nothing to do with arithmetic and comparing whole files
marks
everything dirty for no reason.
**Result.** 19 of 22 judged benches produce **byte-identical numbers** across all three arms.

Clean: `ablation`, `basis`, `canary`, `chain`, `chainmap`, `closeness`, `coarms`, `corpus`,
`cosalt`, `deltanull`, `dimension`, `frame`, `invert`, `orbit`, `sweep`, `tail`, `thread`,
`transform`, `walk`.

Three moved, and all three are ratios of measured throughputs instead of properties of SHA-256:

| bench | claim | `-O0` | `-O2` | `-O2` no FMA |
|---|---|---|---|---|
| `bench_extranonce` | extranonce2 costs *n* times a nonce step | 11.1x | **28.3x** | 23.4x |
| `bench_schedule` | speedup on the expansion alone | 0.932x | **0.395x** | 0.256x |
| `bench_delivery` | ratio, search over verify | 1.08e+19 | **5.46e+19** | 6.15e+19 |

**Verdict.** No statistical or topological result in this workbook depends on the optimiser. The
three that do are performance claims, and each states as a fact about the algorithm something that
is a fact about the build. `bench_schedule` matters most of the three: the rolling-window expansion
this tree has been carrying as a pending fix measures **0.395x at `-O2`, meaning two and a half
times
slower**, and the `-O0` figure of 0.932x that made it look near-neutral is the thing that is not
relevant to a shipping build.
**What this does not close.** Neither arm proves a folded constant was folded *correctly*, which is
a
third failure mode. For `bench_renyi` that is closed separately by `tools/audit/verify_renyi.py`, which
reimplements every prediction the binary prints in another language against another libm and
compares
at the printed precision: 56 of 56 agree. Nothing else in the tree has that check yet.

### H34 - Exact reachability, and the precondition three defects needed

**Claim.** Three separate defects in this workbook have one cause: measuring an effect along a path
that does not exist, and reading the resulting nothing as a result. H6 rotated the nonce instead of
the chaining value. H23 measured through `W[17]`, which does not depend on `W[3]`, and reported
100.000% agreement, which was zero equalling zero. `bench_closeness` graded rounds 1–3 as "premise
holds: no" when the nonce had not arrived. This is failure mode one in `docs/failure-modes.md` and
it
has produced more defects here than any other.
**The instrument.** `bench_reach.cpp`. Computed, not sampled - the circuit is a fixed graph, so
reachability is decidable and "no path exists" is a constraint of a different kind from "no effect
observed". Every state bit carries the set of input bits that can reach it, over all 768 inputs of
one
compression call (512 message, 256 chaining), propagated through the real operations: rotation
permutes positions, shift drops them, bitwise operations union bit by bit, and addition unions
upward
through the carry. Addition is the only widening operation, which makes this an over-approximation -
**a path may carry no influence, but the absence of a path is exact.**
**Result, the nonce.**

| rounds run | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---|---|---|---|---|
| bits of `state[0]` reachable from `W[3]` | 0 | 0 | 0 | 32 | 32 | 32 |
| bits of `state[4]` reachable from `W[3]` | 0 | 0 | 0 | 32 | 32 | 32 |

The nonce reaches nothing for three rounds and saturates both written words the instant it arrives.
**Result, the schedule.** `W[16]` and `W[17]` carry **zero** bits of `W[3]`; `W[18]` carries all 32.
That is right instead of surprising: `W[18]` is the first word whose `W[t-15]` term is `W[3]`. H23's
defect is visible in one row of that table and would have been caught before the measurement.
**Result, diffusion.** Every one of the 256 state bits reads all 768 input bits from **round 21**
on.
The widest cone grows 256, 320, 352, 384, 416, 448, 480, … - thirty-two bits per round after the
first two, one schedule word per round. This is a hard structural constant this tree has not had.
**Control, run in the opposite direction.** An analysis claiming reachability everywhere would pass
an absence test trivially, so both halves are needed. Over 24,000 random flips at rounds 1–6:

| | |
|---|---|
| pairs the analysis called unreachable | 21,257 |
| of those, a flip that changed the bit | **0** |
| pairs the analysis called reachable | 2,743 |
| of those, a flip that landed | 35.07% |

One violation in the first row falsifies the analysis outright. The second must sit away from both
extremes, since an over-approximation admits paths carrying nothing, and it does.
**Verdict.** The precondition is now available and cheap. Before measuring how much of input `X`
reaches output `Y`, ask whether any path exists. Where none does the measurement is of absence and
belongs in no table. This also closes the "exact DAG reachability" item that has been open in §5
since the first revision, where it was listed as unbuilt.

### H35 - The arrangement of the holes, checked in every direction there is

**Claim.** Every number this workbook has produced about the digest distribution is a function of
the count multiset alone, so all of them are permutation invariant and none can see *where* the
holes sit. From `anchor_sift`'s ledger: histogram quantities describe the maximum entropy case and
are free; the arrangement is what remains. Nothing here had ever asked about it.
**The instrument.** `bench_renyi.cpp` and `bench_renyi_cuda.cu`. All `2^32` nonces of block 125552's
header enumerated on the device, whole SHA256d, and the 32-bit window at digest bytes 0–3 counted
into a four gigabyte array - the one family where a bin can be empty. 1,579,996,784 to
1,580,018,507 values are never reached depending on the run, against `1/e = 0.367879441` of the
range, matching to six significant figures.
**The null.** The permutation over arrangements of a fixed multiset, which preserves every count and
destroys every position. It is the data with one property deleted instead of a model that could be
false, which makes it the right null and not merely a sensible one.
**Method, and it widened three times.** Each step was run against a splitmix64 control that got the
identical treatment.

| directions checked | how many | largest | control | expected |
|---|---|---|---|---|
| single-bit flips of the count field | 32 | 2.28σ | - | max of 32 ≈ 2.2 |
| every mask inside any two bytes | 393,210 | 5.03σ | 4.82σ | ≈ 4.57 |
| **every mask that exists** | **4,294,967,295** | **6.81σ** | - | **6.24** |

The complete pass is a Walsh–Hadamard transform of the hole indicator over the whole `2^32` space,
16 GB of signed 32-bit, threaded, about three minutes. The tail counts are the informative part
instead of the maximum: **2510 coefficients beyond 5σ against 2462.3 expected, and 8 beyond 6σ
against 8.47.** A maximum at 6.81 has a 4% chance under the null and the two tail counts match it to
within 2% and 6%.
**Non-linear readings, which a Walsh coefficient cannot see.** Gaps between consecutive holes match
geometric across six buckets at ratios 1.000008, 1.000005, 0.999953, 1.000086, 1.001881, 0.953921.
Longest run of holes 20 against 21.72 expected; longest run of reached values 50 against 46.18.
**Verdict.** No structure in the arrangement, on any axis tested, at any width, in any direction.
**What it cost, the actual finding.** Going from every two-byte mask to every mask was
10,900 times the work and bought 1.67σ of reach. Detection reach goes as `sqrt(2 ln N)` while cost
goes as `N log N`, so **cost is exponential in the square of the reach** and the next 1.67σ costs
about a million times more. The complete-direction approach floors near 7σ for any budget that
exists, and the knee is already behind us. Derivation in `docs/information-theory.md` §5.7.
**Three defects caught on the way, all by checks and not by eye.** The transform's own
coefficient at mask zero must equal the marked count: it read −66,587,004 against 4,228,380,292, a
difference of exactly `2^32`, because signed 32-bit cannot hold a hole count that exceeds `2^31` at
reduced domains - fixed by transforming whichever of the two sides is smaller. Then Parseval failed
with a coefficient of 268,435,421 against 16,744,229 marked, which is impossible for a zero-one
indicator, and it was **non-deterministic**, a race or bad memory instead of wrong
arithmetic. Then a full run truncated mid-word while its wrapper reported success.
**What the checks are.** The self test runs the same transform code at every size from 12 to 26
stages, because the first bug lived only at large stage counts and a single small test would have
cleared it. Parseval is accumulated in a hand-written 128-bit type instead of 64, because when the
transform is correct the sum fits in 64 bits and when it is wrong the sum can wrap back into range
and look correct - **a check a wrong answer can pass is not a check.** The 128-bit type is written
by hand and not as `__int128` because this file is built by both g++ and cl and MSVC has
neither. An extension would have silently disabled on the device arm the check the host relied
on.

### H36 - The window phase, which nothing here had ever varied

**Claim.** From the symbol-width posit in `anchor_sift`: a detector is not told where the units
begin, and a slice of the right width at the wrong offset splits every unit across two symbols.
Every window this tree has ever read is byte-aligned, so seven of the eight alignments had never
been looked at, at any width. Structure sitting at an offset of one to seven bits would have been
split at every window in every run recorded here and invisible to all of them.
**Method.** `tools/audit/sweep_phase.ps1`. Eight runs at `2^28`, one per phase, each reading the digest as
a ring so every phase covers all 256 bits instead of running off the end into a short final window.
The splitmix64 control runs at every phase too, because a pseudorandom function has no preferred
alignment and its spread across phases is the floor.
**Why `2^28` and not `2^32`.** The resolution of a deficit ratio depends on the bin count and not on
the domain: the chi-square statistic behind it has variance twice its degrees of freedom, so one
window resolves its deficit to `sqrt(2/(r-1))` whatever the domain size. Eight runs at `2^28` are
each exactly as sensitive to a phase difference as one run at `2^32`, at a sixteenth of the cost.
**Result.** Mean spread of the deficit ratio across the eight phases:

| family | SHA256d | control | ratio |
|---|---|---|---|
| sixteen-bit windows | 0.003340 | 0.003349 | **0.997** |
| byte windows | 0.015619 | 0.011374 | 1.373 |

**Verdict.** No phase dependence. The sixteen-bit family is the sharp instrument here and it reads
0.997 - SHA256d varies with alignment exactly as much as a pseudorandom function does, which is to
say not at all. The byte-window ratio of 1.373 is a ratio of two spread estimates each built from
eight numbers, so each carries about 27% relative uncertainty and their ratio about 38%; both
spreads also sit below the 1.57% resolution of that family, meaning both are measuring sampling
noise instead of anything about alignment. It is not a finding and it should not be read as one.
**What this closes.** The symbol-width posit's second half, the phase. Its first half, the width,
was already covered by reading at 8, 16 and 32 bits.

### H37 - The digest heard against its own nonce, with scale and unit left free

**Claim.** Every statistic in this workbook is a histogram, and a histogram throws away the order
its inputs arrived in. H35 walked the value axis in all 4.29 billion linear directions. **The nonce
axis is a different axis, it is the the miner walks, and nothing here had ever looked along it,
because no histogram can.**
**The reframing.** Nonce is time and the digest is the waveform, which makes this an audio problem.
Two things follow that this tree had not done. Fourier is linear over the integers and sees
*periodic* structure, where every arrangement test run here was Walsh, linear over GF(2), which sees
*dyadic* structure - the two are blind to different things and a comb was invisible to all of it.
And the audio work in `anchor_sift` carries the scale lesson: in `vocalization_scale.py` a
representation choice decided an answer and was wrong by four orders of magnitude, because a
statistic at 8 kHz per sample read inside a single call and never saw how calls were arranged.
**The controls, and the second one is the important one.** A splitmix64 chain must come out white. A
comb with a period deliberately written into it must come out with that period showing - **a
spectrum tool that reports flat for everything is broken in a way only a positive control catches.**
**What the comb demonstrated before it was used as a control.** At a fixed grid of two envelope
scales:

| comb, period 137 | reading | expected |
|---|---|---|
| sample scale | **63,427x** the mean power, period 137.0 | 17.3 |
| envelope, block 80 | 12.3 | 12.5 |
| envelope, block 400 | 11.3 | 11.1 |

Same signal, same data. One representation choice turns "screamingly present" into "absent",
because 137 samples is 1.7 envelope symbols at block 80 and falls below Nyquist. **A period of 137
falls straight between the rungs of a two-rung ladder.**
**So scale and unit were unbound.** The unit runs over all 32 digest bytes and the scale over a
geometric ladder of 12 blocks, which is 384 readings per signal instead of 3. All 32 bytes come
from one hash, so sweeping the unit costs memory and not work. The comb was then hidden in **byte 19
of 32**. A fixed-byte reading misses it 31 times in 32 and the sweep has to find it to pass.
**Result**, 2^20 nonces, best cell of 384 per signal:

| signal | byte | block | largest peak | expected | period |
|---|---|---|---|---|---|
| SHA256d | 8 | 2 | 18.031 | 17.327 | - |
| splitmix64 control | 23 | 1 | 18.187 | 17.327 | - |
| comb control | **19** | **1** | **1156.267** | 17.327 | **137.0** |

**Verdict.** The sweep found the hidden comb, at the right byte and the exact period. SHA256d's
largest peak over the entire grid is **smaller than the pseudorandom control's**. No periodic
structure along the nonce axis, at any of 32 units, at any of 12 scales. Confirmed separately at
2^26 nonces where the comb reads 63,427 and SHA256d reads 17.586 against an expected 17.329.
**The principle this is a case of.** Everything stays unbound in scale or unit until the answer is
final. A bench that fixes either is reporting a result about that choice and not about the object,
and the comb puts a number on what that costs: five orders of magnitude, in the direction of
reporting a real signal as absent.
**Listening is reading the output.** `bench_sound.cpp` writes five seconds of each signal as an
eight-bit wav at 8 kHz. The corpus audit posit records that nine problems in that work were found by
reading output and none by a statistic leaving its range; a spectrum table is a statistic. The comb
is audibly different from the other two and they are not tellable apart.

### H38 - Where the closeness premise is worth spending, and the localities inside it

**Claim.** `bench_closeness` measured the premise on the whole function, found nothing, and this
workbook read that as the premise being false. That was too strong. The premise has a **depth**: it
does not fail, it expires. The question is therefore not whether to keep it but where to spend it,
and that is a number nothing here had asked for.
**The instrument.** `bench_depth.cpp`. A difference is placed on the chaining value instead of the
message, because a message difference does not reach the state until four rounds have run and would
measure absence at every shallower depth - the defect H34 exists to prevent, avoided here instead of
 corrected afterwards. Correlations are turned into bits through the mutual information of a
bivariate normal, `-log2(1 - c^2)/2`, because a correlation is not additive and a bit is, and only
bits can be divided by the rounds spent.
**Two co-arms, coupled instead of independent.** A round writes `state[0]` and `state[4]` and
shifts the rest along, so those are the only two places it puts anything. Both are driven by the
same input difference on the same pair, which makes them co-arms - an earlier attempt in
this tree used independent arms and was structurally guaranteed to null. The joint reading is the
multiple correlation of the input distance on both at once.
**Result, pooled.**

| rounds mixed | arm A `state[0]` | arm B `state[4]` | joint R | bits/round | control |
|---|---|---|---|---|---|
| 1 | 0.6665 | 0.6459 | 0.7360 | **0.5629** | −0.0035 |
| 2 | 0.3086 | 0.5108 | 0.5199 | 0.1137 | 0.0043 |
| 3 | 0.0857 | 0.2700 | 0.2736 | 0.0187 | 0.0026 |
| 4 | 0.0134 | 0.1329 | 0.1332 | 0.0032 | −0.0009 |
| 5 | 0.0011 | 0.0299 | 0.0299 | 0.00013 | −0.0040 |
| 6 and beyond | at control | at control | | 0 | ~0 |

**There is no interior maximum.** Bits per round falls about five-fold per round, so the shallowest
depth is always the most efficient and there is no clever depth to steer to on the pooled curve.
**Three things fell out of that table.** The co-arm gain is real but small - the joint exceeds the
better single arm at every depth, by one to three percent, so the two arms do carry slightly
different parts. `state[4]` holds correlation about ten times longer than `state[0]`, which is
structural: `state[0] = carry_one + carry_two` mixes both carries plus `mix_low` and `majority`
while `state[4] = state[3] + carry_one` is a single addition. And it cross-checks `bench_closeness`
independently: that bench put the difference on the nonce, which enters at round 4, so its death at
round 10 is this one's death at round 6, offset by exactly four.
**The pooled curve is a mean, and it was hiding the answer.** Stratified by how many bits differ,
using the distance of the mean output distance from 16 in standard errors - a statistic that stays
defined when the weight is fixed, where a correlation does not:

| bits differ | r=1 | r=2 | r=3 | r=4 | r=5 | r=6 | dies at |
|---|---|---|---|---|---|---|---|
| 1 | −2272.8 | −1693.9 | −1017.8 | **−525.7** | −117.3 | 5.5 | **7** |
| 2 | −2048.5 | −1147.1 | −421.2 | −114.4 | −8.3 | −1.0 | 6 |
| 3 to 4 | −1749.3 | −661.3 | −130.2 | −15.7 | 0.3 | −0.6 | 5 |
| 5 to 8 | −1292.2 | −236.3 | −13.6 | −0.1 | −0.7 | 2.0 | 4 |
| 9 to 16 | −715.2 | −36.4 | −1.2 | **−0.4** | 1.2 | 0.1 | 3 |

At four rounds a one-bit difference reads **525.7 standard errors** and a sixteen-bit difference
reads **0.4**. Three orders of magnitude apart, inside the single number the pooled table reported.
**The law, and the wall it implies.** Death depth falls by exactly one round per doubling of the
weight, so `depth ≈ 7 - log2(w)`, which is linear in the logarithm and makes weight the exponential
lever on depth. Inverting it is the part worth having: the weight needed to reach depth `d` is
`w = 2^(7-d)`. At `d = 7` that is one bit. At `d = 8` it is half a bit.

**Weight is bounded below by one, so round seven is a wall instead of a slope.** There is no
difference that reaches round eight by this route, because the lever runs out instead of because
the signal happens to be small there. The one-bit difference is the deepest probe that exists and it
dies at seven rounds of sixty-four, which is 5.5% of a doubled hash. Every deeper result in the
published literature buys its depth some other way - by searching for a characteristic that holds
with low probability and not by making the difference lighter - and that is a different currency
with a different price.

And the decay within a stratum is **parabolic in log space** instead of exponential: fitting
`ln|z| = a + br + cr^2` gives `c` between −0.29 and −0.58 on every stratum with enough points. That
matters practically - a signal decaying faster than exponentially cannot be extrapolated
exponentially, and any estimate of how deep a characteristic reaches that assumes a constant
per-round factor is optimistic.
**The same law read from the other side, the useful direction.** Rounds to saturation is
`7 - log2(w)`: more saturation needs less depth. A sixteen-bit difference is flat by round three and
a one-bit difference takes seven. If the object is to reach the flat plane cheaply, use heavy
differences; if the object is to see anything at all, use light ones.
**Which lands on the miner's own stride.** An increment `n -> n+1` flips exactly **2.0000** bits on
average, measured over 2^24 steps - the carry chain makes it two regardless of where in the range it
sits. So sequential nonce scanning generates differences in the weight-two stratum, which dies at
round six of the seven that are reachable at all. **The miner is already walking the
deepest-surviving stratum without trying**, and there is one round of depth available above it,
obtainable only by stepping the nonce so that consecutive candidates differ in a single bit - a Gray
code order instead of a counting one. That is one round out of sixty-four, and it is all of
what this axis has left to give.

**Verdict.** The corpus has one average best stride and there are localities inside it. Low-weight
differences are where the premise survives, by about a factor of two in depth, and steering there
keeps the premise instead of rejecting it. This is not a departure from what SHA-256 should
do - fewer active bits diffuse more slowly, and steering toward low-weight differences is what
published differential cryptanalysis already does. It is a locality that every pooled measurement in
this workbook averaged away.
**A defect caught in the reading, and its direction matters.** The bit flips were drawn
independently, so two could land on the same bit and cancel, and a stratum labeled "9 to 16"
quietly contained lower weights. That is failure mode 7 and it had already been fixed once in
`bench_closeness`, then reintroduced here. The contamination made high-weight strata appear to
survive *deeper* than they do: with distinct positions the 5-to-8 row at four rounds moves from
−3.2 to −0.1 and the 3-to-4 row from −22.4 to −15.7. **The subtle error was hiding real tail
error**,
and correcting it sharpened the separation instead of weakening it. The bench now asserts the
realised weight equals the requested one and stops instead of printing a mislabeled row.

## 4. What The Results Say Together

The premise in H5 is correct and is not the failure point. The boundary representation reads a
rotation off the phase exactly. H6 measures how far that reaches: one round.

The reason is that no single projection serves all three of SHA-256's operations at once. H9
sharpens
how to state this. The obstruction is not that modular addition is nonlinear, because it is
perfectly
linear over `Z/2^32`. The obstruction is that the set carries two module structures and the round
alternates between them.

| operation | linear over GF(2)^32 | linear over Z/2^32 | diagonal in |
|---|---|---|---|
| rotate | yes, a permutation matrix | no, 25.15% | DFT over Z32, as a phase ramp |
| exclusive or | yes | no, 0.21% | Walsh-Hadamard over GF(2)^32 |
| add mod 2^32 | no, 0.02% | yes | neither of those two |

Rotate and exclusive or alone are GF(2)-linear and would fall to linear algebra. Addition is what
forces the change of structure, and the carry recursion measured in H10 is the mechanism: it is
the part of the sum that leaves the GF(2) basis. SHA-256 interleaves all three for 64
rounds, twice.

H11 then asks whether committing to either structure buys anything, and answers no: a difference
introduced in either basis dies at round 9 of 128.

H1 through H4 then say the output of that composition is indistinguishable from a flat memoryless
source at the sample sizes reached. `anchor-sift.md` §2.4 calls maximum entropy the base case for
the
anchor construction; the digest domain sits on it to six decimal places. That is the case
where an informed anchor measure buys nothing over an uninformed one, because there is nothing to be
informed about.

## 5. What Is Still Worth Running

Closed since the first revision: the larger H2 sample (H18, floor now 3.05e-5), Walsh-Hadamard
(H12),
and the message schedule (H23). What remains:

- **Re-run every hand-nulled statistic against `Pi_Sigma`.** H31 found this workbook's headline
  inflated by about 4,200 because it used a hand-derived reference. The keyhole scan's
  expected-worst-of-3840 and the corpus-size ratios in H1 were both hand-derived and neither has
  been
  permutation-checked. This is the highest-value item on the list because it revises results already
  recorded instead of adding new ones.
- **Backtracking characteristic search.** H30's chain is greedy and collapses 300x after round zero
  because a nonzero incoming delta is worth far less than a zero one. Published searches add
  backtracking for exactly this reason. That is the step between round 10 and round 31 in the
  literature.
- **The delta axis at better resolution.** H30 visited 1.86e-09 of it and the chained rounds sat at
  two occurrences in 300,000, the sampling floor instead of a measurement. The GPU makes a
  much larger sample cheap and would separate "small" from "at the floor".
- ~~**Exact DAG reachability.**~~ Built, H34. The nonce reaches nothing for three rounds, `W[17]`
  carries none of it and `W[18]` carries all of it, and every state bit reads every input bit from
  round 21. The sampled light cone in H15 should now be re-read against the exact one.
- **Reduced-width analogue.** An 8-bit-word SHA-256 has a state small enough to enumerate
  completely, which would turn every sampled result in this workbook into an exact one.
- **Rounds 5 through 9.** Every projection dies in that window and none characterises its interior.
- **Periodic disturbance on co-arms.** From `anchor_sift/docs/research/hourly_supposition.md` item 1:
  introducing a periodic disturbance is reported to move joint error toward zero by several orders
  of
  magnitude on an undisturbed co-arm. Nothing in this tree has tested that, and it is the most
  concrete untested claim available. It would apply here as a structured perturbation on one arm of
  an RX pair with the residual read on the other.

## 6. What Would Change The Conclusion

Any of these would reopen the question, and none has been observed:

- A per-bit bias above 3.05e-5 that survives a larger sample.
- A lag correlation above 2e-4 at any lag.
- Rotation recovery above chance at any round count greater than zero, with the constants present.
- A hitting-time distribution departing from geometric.
- An RX characteristic whose per-round probability exceeds 2^-4, and 64 rounds needs to
  match brute force. The best measured is 2^-16.17.
- Enrichment rising with cascade depth in H20's last column.
- A `Delta_Sigma[M]` residual that grows instead of shrinks as the sample rises.

## 6b. What This Workbook Cannot Say

Stated because a document that only lists what it ruled out reads as stronger than it is.

- It has visited 1.86e-09 of the delta axis and none of the 2^256 full-state delta space.
- Its deepest chain is 8 rounds against a function that runs 128.
- Six of its thirty-one hypotheses were measured against hand-derived nulls that have not been
  permutation-checked.
- Nothing in it is a proof of absence. H21 is the only entry that proves anything, and what it proves
  is a degree bound, not the absence of structure.

## 7. Provenance

Every number in this document was produced by a binary in this tree against the real function, not
quoted. The reduced-round instrument in `sha256_core.c:sha256_block_compress_partial` is asserted
equal to `sha256_block_compress` at 64 rounds over 512 random blocks
(`bench_transform.cpp:check_instrument`), so the instrument cannot drift from what it measures. The
SHA-256 implementation itself is validated against FIPS 180-4 vectors, the genesis block, and block
125552 in `kat_validation.cpp`.

**Nine defects were found and corrected while producing this document.** All are recorded because a
workbook that hides them is not a record, and because the pattern across them is the most useful
thing in the file: **every single one produced a result that looked better than the truth.** Not one
erred toward a weaker finding.

| # | where | the defect | what it claimed |
|---|---|---|---|
| 1 | H6 | rotated the *nonce*, which enters at `W[3]` and does not reach the state until round 3 | zero recovery at rounds 0-2 through absence, read as a decay that never happened |
| 2 | H6 | `recover_rotation` correlated the boundaries in the wrong order, peaking at `32-r` | 3.2% at round 0 where construction requires 100% |
| 3 | H19 | expected-worst over 3840 tests derived by hand | a keyhole at **+5.47 sigma** that dissolved to +4.19 at 64x the sample, with the worst bit moving |
| 4 | H23 | measured agreement through `W[17]`, which does not depend on `W[3]` | a perfect **100.000%** characteristic that was zero equals zero |
| 5 | H23 | prose claimed early words "agree often" | printed directly above a column reading 0.0000% |
| 6 | H24 | overshoot modeled as geometric in nibbles; the target is not at a nibble boundary | a **7.27x excess**, which corrected to 1.0076 |
| 7 | H27 | k = 8, 12, 16 at 400 states, expecting 0.006 hits at k=16 | zero columns that said nothing, reading as a strong result |
| 8 | H29 | added `K` to one member and `rotr(K)` to the other, rotating the constant with the frame | **25.8% survival** that appeared to overturn H22 |
| 9 | H30 | measured all 8 output words; a round writes only `state[0]` and `state[4]` | **P = 1.00000000** at every frame, six untouched words outvoting two real ones |
| 10 | H29/H31 | concentration compared against per-bin uniform instead of a max-statistic null | **775,000x**, which the permutation null corrected to **184.5x** |

Ten, not nine, once H31's own correction is counted. Six were caught by a control that had been
built
before the measurement; three by a re-run at higher sample size; one by the Sigma-delta null.

**The methodological conclusion, which outlasts every specific number above.** A hand-derived
analytical null is the single largest source of false findings in this work, accounting for defects
3, 6, 7 and 10. The `Pi_Sigma` permutation null of H31 cannot fail in that way because it preserves
the carrier's counts by construction. Every statistic here compared against a hand-derived reference
should be re-run against it, and §5 lists that as the highest-value remaining item for exactly this
reason.

**Instrument validation.** The reduced-round instrument in
`sha256_core.c:sha256_block_compress_partial` is asserted equal to `sha256_block_compress` at 64
rounds over 512 random blocks (`bench_transform.cpp:check_instrument`). The SHA-256 implementation
is
validated against FIPS 180-4 vectors, the genesis block, block 125552, and **1000 consecutive real
block headers, 1000 of 1000** (`bench_chain.cpp`). The rotational probability formula is confirmed
against published theory to four decimals (H22). The round constants are derived from the primes
instead of copied (H26).

**External references used.** `anchor_sift/docs/research/anchor-sift.md` §2.2, §2.3, §2.4, §2.5 for
the anchor construction and its cost model; `anchor_sift/docs/research/terms.md` and
`anchor-sift.md`
§2.1 for the Sigma-delta null; `anchor_sift/docs/research/hourly_supposition.md` items 1, 4, 9, 11
and 16 for the co-arm disturbance, known-doping-as-salt, the bounding prohibition, mutation over
transformation, and the sampling-limit continuum. Published cryptanalysis fetched 2026-09-08:
Khovratovich and Nikolic FSE 2010 for rotational cryptanalysis, Ashur and Liu 2016 for
rotational-XOR, Mendel/Nad/Schlaffer EUROCRYPT 2013 for the 31-step collision, Khovratovich et al.
for the 52-step preimage at 2^255.
