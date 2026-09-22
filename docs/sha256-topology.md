# Topological Properties of SHA-256: What We Know, What We Do Not, What We Want

**Purpose:** Take stock of every structural property of SHA-256 measured in this tree, separate what
is established from what is assumed, state the objective precisely enough to test against, and list
the angles that have not been examined so that effort goes to unopened ground instead of reopened
ground.
**Scope:** `docs/transform-workbook.md` (H1-H20), `src/sha256_core.c`, `src/bench_transform.cpp`,
`src/bench_basis.cpp`, `src/bench_invert.cpp`, `src/bench_walk.cpp`, `src/bench_corpus.cpp`,
`src/bench_cosalt.cpp`, `src/bench_keyhole.cpp`, `src/cuda_miner.cu`
**Owner:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08

## 1. What We Want, Stated So It Can Be Tested

The objective is not "mine faster." It is:

> Find a transform `T` under which the map `nonce -> SHA256d(header)` carries structure that a sift
> can use, such that the cost of finding a nonce below target falls below the cost of enumeration.

Three separable sub-goals, because they fail differently and only the third has ever been the real
target:

| goal | status | what it would take |
|---|---|---|
| **G1.** Cheaper per candidate | partly achieved | midstate reuse and the anchor early exit are in the engine. Bounded below by two compressions. |
| **G2.** Fewer candidates via a sound filter | **not achieved and provably not available from a salt** | a filter `A` with `A ⊆ D`, so §2.2 soundness applies |
| **G3.** Solve instead of search | not achieved | invert or algebraically solve the system |

The distinction between G2 and G3 matters and has been blurred repeatedly. G2 needs a *necessary
condition read cheaply*. G3 needs the *function inverted*. anchor-sift is a G2 instrument. Every
result below is best read as: G2 requires a condition the target imposes, and the digest supplies no
such condition more cheaply than the hash itself.

## 2. What We Know

Every row here was measured in this tree against the real function, with the instrument checked
against the kernel or against published data.

### 2.1 The mechanism is transparent and reversible

| fact | evidence | strength |
|---|---|---|
| The round function is a bijection on the 256-bit state for fixed `W[t]` | H14: 64 forward then 64 backward returns the exact start, 4096/4096 trials | **exact** |
| Information is never destroyed, only displaced | follows from the above | **exact** |
| `H(digest \| input) = 0`; the field carries no stochastic noise | determinism | **exact** |
| Every operation is linear in exactly one of two module structures | H9: rotate 100% GF(2) / 25.15% ℤ, xor 100% / 0.21%, add 0.02% / 100% | **exact** |
| The carry is the part of a sum that leaves the GF(2) basis, and it is biased | H10: `p_{i+1} = p_i/2 + 1/4`, matched to 4 decimals over 4M pairs | **exact** |

The last row is the only *positive structural finding* in the whole programme. It is real, it is
exactly characterised, and it is local: the bias halves per bit position and is under 0.2% by
position 8.

### 2.2 The geometry of propagation

| fact | evidence |
|---|---|
| Reach speed is exactly **64 bits per round**, linear | propagation table: 64, 128, 192, 256 across rounds 4-7 |
| That speed is structural, not statistical | the eight working variables form two shift chains, `a→b→c→d` and `e→f→g→h`; one word per chain per round is two words is 64 bits |
| Saturation lags reach by about 3 rounds | 0, 32, 96, 159, 222, 256 across rounds 5-10 |
| The wave front peaks near 160 positions at rounds 6-7 | reached minus saturated |
| **A light cone exists** and closes at round 7 of 128 | 256 bits / 64 bits per round = 4 rounds after entry at round 3 |

This is a genuine finite propagation speed. It is the most topological fact established here. It is
also the reason the cone is useless: the state is 256 bits and the schedule is 128 rounds, so the
cone covers everything in the first 5% of the computation.

### 2.3 Where structure dies

| projection | dies at | of 128 rounds |
|---|---|---|
| rotation phase (Fourier on the boundary) | round **1** | H6 |
| Fourier spectral flatness | round 8 | H8 |
| Walsh-Hadamard sequency flatness | round 8 | H12 |
| xor-basis difference | round 9 | H11 |
| modular-basis difference | round 9 | H11 |
| avalanche saturation | round 10 | H7, H15 |

**Everything dies in rounds 1 through 10.** Six independent projections, one seam. That coincidence
is itself a finding: it says the seam is a property of the construction's diffusion schedule and not
of any particular projection. A seventh projection landing in the same window should be the prior
expectation.

### 2.4 The output is statistically featureless

| measurement | result | sample |
|---|---|---|
| collision entropy `H2` | 7.999999 of 8 bits/byte | 2^24 |
| worst per-bit bias | 3.05e-5 floor, nothing above | **2^32** |
| lag autocorrelation, 20 lags incl. every rotation amount | worst \|z\| 1.78 | 2^22 |
| hitting time | geometric: mean 66,095 vs 65,536; sd = mean; median = ln2·mean | 512 streams |
| anchor survivors vs `N·2^-k` | ratios 1.00013, 0.99342, 1.07031 at k=8,16,24 | 2^32 |
| real winning nonces, 16 buckets | chi-square 17.6 on 15 df, z = +0.47 | 1000 real solves |

### 2.5 What the search space actually is

| field | width | enters at |
|---|---|---|
| nonce | 32 | `W[3]`, round 3 |
| extranonce2 | 64 (pool-set) | coinbase → merkle root → midstate **and** `W[0]` |
| ntime | ~13 of slack | `W[1]` |
| version | 16 under BIP320 | header 0-3, inside the midstate |

About **125 bits**, confirmed in use: 616 distinct version values across 1000 consecutive real
blocks.
A step in the extranonce2 dimension costs **24.0x** a nonce step and carries no landscape either
(H16).

### 2.6 The frontier

- **Forward:** 3 rounds of 128 computable before meeting the unknown, and only with extranonce2 and
  version pinned.
- **Backward:** 0 rounds. Inverting round `t` needs `W[t]`; every schedule word past 15 is generated
  from the words being solved for.

The obstruction is **circularity**, not information loss. That distinction is established, not
asserted: H14 proves nothing is lost.

### 2.7 The one exact result: algebraic degree

Everything in §2.1 through §2.6 is either a property of the mechanism or a sampled bound. This is
the
only measurement in the programme that is a **proof about the output**, and it came from looking at
intersections of difference directions, not at one direction at a time.

A k-th order differential sums `f` over all `2^k` corners of a k-dimensional cube of input
differences. If the algebraic degree of `f` over GF(2) is below `k`, it is **identically zero** for
every base point. Not small. Zero. A vanishing higher-order differential therefore proves a degree
bound
that no amount of further sampling can overturn.

Measured on reduced-round SHA-256 as a map from the nonce, `V` = vanished at every base point:

```
rounds  1  2  3  4  5  6  7  8  9 10 11 12   degree
     1  V  V  V  V  V  V  V  V  V  V  V  V   0, nonce has not entered
     2  V  V  V  V  V  V  V  V  V  V  V  V   0
     3  V  V  V  V  V  V  V  V  V  V  V  V   0
     4  .  .  .  V  V  V  V  V  V  V  V  V   exactly 3
     5  .  .  .  .  .  .  .  .  .  .  .  .   at least 12
    10  .  .  .  .  .  .  .  .  .  .  .  .   at least 12
```

**The degree goes from exactly 3 to at least 12 in one round.** The nonce carries 32 bits, so 32 is
the ceiling; the function is within a factor of three of its ceiling one round after the input
arrives, out of 128. Degree growth is the quantity that decides whether any algebraic attack has
room
to work, and this says it does not, from round 5 onward, as a matter of algebra instead of of
sampling.

This also corrects a labelling error made while producing the table. Order `k` vanishes exactly when
the degree is *below* `k`, so the degree is the **highest failing** order. The first version
reported
the lowest failing order, which labeled every row with any failure as "degree 1" and would have
hidden the exact-3 result at round 4 entirely.

## 2b. The Depth And Direction Table, 2026-09-08

Everything below is measured on this date and each row names the bench that produced it. This
supersedes any earlier depth figure in this document: the earlier ones read a single fixed state
word, and the word that survives longest turned out to be the *least* overwritten end of the shift
chain instead of the most mixed, so every earlier depth was a lower bound.

### Known

| fact | value | where |
|---|---|---|
| the round is a bijection, exactly | 20,000 round trips, 0 failures | `bench_depth` |
| forward cone growth | 32 bits per round after the first two, full at 21 | `bench_reach` |
| forward difference visibility, weight 1 | dies at **10** rounds | `bench_depth_cuda` |
| inverted difference visibility, weight 1 | real signal through **15**; crossing at 16 at 2^26 pairs | `bench_depth_cuda` |
| the decay is not geometric, it accelerates | forward 1.10, 1.34, 1.67, 1.94, 4.48, 29.73 per round | `bench_depth_cuda` |
| peak forward destruction rate | 4.89 bits/round against 5.000 for exactly 32x | `bench_depth_cuda` |
| the wall does not move with word width | 10, 9, 9, 9, 9, 9, 10 at widths 4 to 32 | `bench_narrow` |
| only one swept width is structurally damaged | width 12, Sigma1 kernel 2; Sigma0 clean throughout | `bench_space` |
| narrowing manufactures adjacent amounts | 22 pairs one apart across narrowed widths, 0 at width 32 | `bench_space` |
| the schedule word elides exactly | same W both sides cancels in the additive difference | algebra |
| nonce difference outlives state difference | dies at 11 rounds against 10 | `bench_depth_cuda` |
| schedule words independent of the nonce | 17 of 64, deepest is W17 | exact |
| backward cone from the tested word | last 3 rounds need 1 word, then 5, 6, 7, 8 | exact |
| smallest area a nonce must cross | 973 of 1024 word-rounds, 5.0% | exact |
| **light cone, entry** | message word w cannot affect the state before round **w+1** | `bench_sac shadow` |
| **light cone, propagation** | one register per round: a,e alive at 1; b,f at 2; c,g at 3; d,h at 4 | `bench_sac shadow` |
| the dead plateau is exact | **67,108,608.0** to the last digit at 2^18 trials, being 256(n-1) | `bench_sac shadow` |
| shift invariance, message words | every word's avalanche profile identical to **1 part in 10^4** at its own wavefront | `bench_sac shadow` |
| shift invariance, register chains | a-b-c-d and e-f-g-h agree to **6 significant figures** across the shift | `bench_sac shadow` |
| **the a/e asymmetry** | **2.3e-3**, which is 66x the within-chain spread. Carry geometry: both are T1 plus a *different* constant | `bench_sac shadow` |
| common mode decrement | exactly **2048 sigmas/round** at rounds 10-16, knee at 17 | `bench_sac shadow` |
| the transport channels | class 0 at **14.95**, Sigma1's 25/6/11 at 8.57/7.55/5.72, carry 31 at 6.06 | `radar_receive.py` |
| Sigma1 against Sigma0 | **12.61 against 3.34** through the same matched filter | `radar_receive.py` |
| matched filter, whole waveform | **19.16**, pre-registered from the standard | `radar_receive.py` |
| **suppression past round 23** | at least **15x**: waveform 5.78/round live, under 0.38/round deep | `radar_receive.py` |
| the target has zero Doppler | drift within 0.09 at all 15 frequencies; MTI blind-speed confirms it | `bench_sac dispersion` |
| **the wall is the chain length** | wall = words + 2 at 8, 10, 12, 14, 16 words | `bench_words` |
| the wall does not move with samples | words + 2 at 2^20, 2^24 and 2^28 alike | `bench_words` |
| all four mixing functions are bijections | rank 32, kernel 0, Sigma and sigma alike | `bench_space` |
| narrowed rank deficit in closed form | deg gcd(p(x), x^w + 1), agrees at every width | `bench_space` |
| a one-bit nonce difference stays one bit | through W27, where the mean is already 15.58 | `bench_space` |
| **the sparse path is reachable, and cheap** | W19 48%, W23 4.7e-5, W27 6e-7; nothing else beats chance | `bench_sparse` |
| the sparse path is a property of the recurrence | genesis, 125552 and an invented header agree | `bench_sparse` |
| it arrives where nothing is left | W27 feeds round 27; forward state dies at round 10 | both |
| **the sparse path traces exactly, no sampling** | linearized floor predicts every sampled rate, 0 contradictions | `bench_sparse` |
| the nonce has exactly one genuine path | floor 1 only at W19; W23 and W27 are floor 2 | `bench_sparse` |
| a cancelling word is the sparsest, not the emptiest | W0 at W25: linearized weight 0, one bit 13% of the time | `bench_sparse` |
| **merkle rolling reaches deeper than nonce rolling** | W25 at 13% against the nonce's W23 at 0.002% | `bench_sparse` |
| floor is not reachability | W0 floors at 1 on W33 and was never once observed | `bench_sparse` |
| forward round 10 is off, not small | 2.386 at 2^30 pairs against 9.706 if the slope held | `bench_depth_cuda` |
| the slope extrapolation, on the control | predicted 8026.7 / 16053.5 / 32106.9, read 8022.4 / 16048.4 / 32095.5 | `bench_depth_cuda` |
| the word statistic is not the blind one | no depth reads by bit position and not by word, either direction | `bench_depth_cuda` |
| depth against weight, forward | 10, 9, 8, 7, 6 for weights 1, 2, 3–4, 5–8, 9–16 | `bench_depth_cuda` |
| depth against weight, inverted | 14, 13, 12, 11, 9 for the same strata | `bench_depth_cuda` |
| stratum population | 256, 3.3e4, 1.8e8, 4.2e14, 1.1e25 | exact |
| exact difference propagation dies | **2 rounds**, both languages together | `bench_language` |
| algebraic degree | 3 at round 4, ≥12 at round 5 | earlier workbook |
| co-arm gain, forward | joint beats better single arm by 1–3% at every depth | `bench_depth` |
| GF(2) sees additive structure | ~3.5 bits | `bench_language` |
| additive sees GF(2) structure | 0.03 bits | `bench_language` |
| every natural corpus tested | reads additive, without exception | `bench_nature` |
| the miner's own stride | 2.0000 bits per nonce increment, exactly | measured over 2^24 |

**Scarcity is Pareto-dominant, the structural result.** Moving from weight 9–16 to weight
1 gives 4.2e22 fewer candidates *and* +3 forward rounds *and* +5 inverted rounds, simultaneously.
Nothing is traded. The exponential lives in the candidate count; the depth gain is arithmetic.

**The intercept is not a property of the function and was reported as one.** `depth = c - log2(w)`
has a slope of one round per doubling that is real, and a constant `c` that is set by how many pairs
were drawn. At 40,000 pairs `c` was 7 and it was written up as a hard wall on the argument that
weight cannot fall below one. At 4.2 million pairs it is 10, and it will move again. **The slope is
the finding; the intercept is the detection floor wearing the finding's clothes.**

Two earlier entries fell to the same sample size and are corrected and not deleted, because the
correction is the useful part: the inverted direction was "alive at 13, not yet dead", and the
forward strata 5–8 and 9–16 both read 6 rounds with the coincidence recorded as unexplained. Neither
survived more samples. The first now carries real signal through 15 and crosses at 16; the second
separates into 7 and 6 and was never an anomaly. The "14" this paragraph carried until 2026-09-09
was itself a crossing at fewer pairs, the same mistake one layer down.

### Want

- ~~Where the inverted direction actually dies.~~ Answered: **15 rounds** at weight one, with round
  16 reading noise that *shrinks* under more pairs (2.438, 1.317, 0.881). An earlier answer of 14
  here was a threshold crossing at fewer pairs and is superseded.
- ~~Whether the wall belongs to the chain or to the word.~~ Answered: **the chain**. `bench_words`
  gives wall = word count + 2 at 8, 10, 12, 14 and 16 words, with 8 words reproducing SHA-256's
  known 10 as the control.
- ~~Whether the schedule functions are weaker than the state functions.~~ Answered: **no**, all four
  have rank 32 and kernel 0. The weakness is sparsity instead, and it is measured.
- ~~Whether the 461 word-round floor holds per nonce.~~ Answered: **no**, it is 973 of 1024 and 5.0%,
  because two blocks run per nonce and each takes only one of the two savings.
- ~~Whether the +2 in `wall = words + 2` has a mechanism.~~ Answered: **it is 3 minus 1.** See below.
- ~~Whether the sparse-nonce path is reachable and not merely existent.~~ Answered: **reachable,
  cheaply, and useless where it arrives.** See below.
- ~~Whether the 5.0% is real in instructions instead of word-rounds.~~ Answered: **no**. Both
  savings are implemented, exactly correct, and worth nothing measurable. See below.
- Whether the forward/inverted asymmetry is exploitable as a co-arm filter, the one
  application the measurements point at: the inverse arm reaches strictly deeper, so agreement
  between the arms filters harder than either alone, and the weight strata are the buckets.
- A clean backward cone for the *state* recursion. The exact schedule cone is now computed and is
  clean; the state one still depends on the round it starts from, which was chosen arbitrarily.

### Open hypotheses, from the radar and EW framing

Stated so each can fail. The framing is not decoration: these are standard techniques with known
statistics, and every one of them names a measurement this work has not made.

| # | hypothesis | how it fails | status |
|---|---|---|---|
| H1 | **The clutter is colored, not white.** The CFAR treats the 32 residue classes as independent; they share a message set and are certainly not. STAP estimates the covariance from target-free snapshots and whitens | rounds 24-64 are 41 *proven* target-free realisations, which is textbook secondary data. If the covariance comes back near-diagonal, the clutter is white and there is no gain | untested, data already dumped |
| H2 | **The per-round decrement carries the round constants.** Deviation from exactly 2048 is 1.5 where measurement error is 0.25, and rounds differ in nothing but K_t. This is Specific Emitter Identification: the *imperfections* identify the emitter | correlate the deviation against properties of K_t. No correlation means the scatter is a noise estimate that is simply wrong | **next** |
| H3 | **The probe has been a single omnidirectional element.** Flipping a *pattern* matched to a transport channel - say Sigma1's preimage {i, i-6, i-11, i-25} - is array gain on transmit, which beats any receive-side processing because it is two-way | a matched pattern that gains nothing over a single bit refutes the reading of the spectrum | untested |
| H4 | **The message schedule is a delay line, so the array steers in depth.** Word w emits at round w+1, so choosing which words carry a difference sets each element's emission time | arrivals arranged to coincide should interfere measurably; if they add incoherently the light cone is not a usable delay line | untested |
| H5 | **A differential characteristic is a transmit pattern, and a collision is null steering.** The attacker arranges message differences so everything cancels at the output, a null in the beam pattern | if adaptive-nulling mathematics gives nothing SAT search does not already get, the analogy is decorative | speculative, and the only one of these that touches the field's stated bottleneck |
| H6 | **Round 17 is an arc.** The decrement is exactly 2048 through round 16 then breaks: 2035, 1995, 1635 | a mechanism that predicts the knee from the schedule or the cone would resolve it | **RESOLVED.** It is the message schedule expansion switching on. `no_schedule` is bit-identical to the full function through round 16 and diverges at 17, the first round to consume an expanded word |
| H8 | **The difference is a two-component wave.** The XOR difference carries position and the modular difference carries magnitude; neither is conserved alone and the carry chain is the coupling that converts one into the other, as dE/dt drives B. Removing addition killing class 31 is that coupling being cut | track both weights per round. If energy oscillates between them it is a wave; if their ratio is fixed they are two quantities that merely travel together | untested |
| H9 | **It may be circularly polarized.** If the two components are in quadrature and not in phase, the difference vector *rotates* in the (XOR, modular) plane, and the handedness is a chirality of the round function | measure the phase relation between the components | **REFUTED.** The PLL locks at rotation zero and never walks while it holds. Linearly polarized: the carries add magnitude, not angle |
| H10 | **A rotating signal needs de-rotation before integration.** If H9 holds, every coherent integration in this work is decohering the thing it integrates, as uncorrected Faraday rotation does | apply a correction and see whether the matched filter gains | **moot.** H9 refuted, so there is nothing to de-rotate and nothing was being lost |
| H12 | **Every instrument here is value-averaged, and blind in the same way.** The SAC matrix asks whether flipping *position* i moves *position* j, averaged over 2^18 messages. It sees where bits go and never what values sent them there - the same failure as reading a word by its token and never its letters. SHA-256's nonlinearity is entirely value-gated: Choose is a selector driven by e, Majority by the a chain, carries by everything. A structure present in two regimes with opposite sign cancels out of the average completely | split the messages by a selector and fold each half separately | **the criticism stands; the first consequence tested does not.** Gating on Choose's selector finds nothing (see Refuted). That tests one gate bit at one round at fold resolution, so it does not clear the general worry - a regime difference not aligned to residue classes stays invisible |
| H11 | **The carry halves the linear model's power each round.** Agreement above chance runs 0.423, 0.214, 0.113 before accelerating away | measure it at other input bits and other difference weights. A halving that only holds for bit 0 at weight 1 is a coincidence of one path | **open**, and the only constant-*ratio* decay in a body where everything else decrements |
| H7 | **The assay is a crowbar.** Shorting each sub-function and watching the reflection should remove exactly that sub-function's residues: no Sigma1 removes 6/11/25, no addition removes 31 | a removed rotation whose residue still stands refutes the spectral reading entirely | **running** |

### What the published work says, and where it goes deeper than we do

Checked 2026-09-09. This calibration was not run until late, and it bounds every residue reading in
the work.

| | rounds of 64 | cost | source |
|---|---|---|---|
| **preimage, bicliques** | **52 steps** | impractical | extends the pseudo-collision line |
| pseudo-collision | 43 steps | 2^126 | reduced SHA-256 line |
| semi-free-start collision | 39 steps | - | Li et al., extended quantumly |
| practical collision | **31 steps** | practical | ASIACRYPT 2024 |
| earlier collisions | 23, 24 steps | 2^18, 2^28.5 | Sanadhya and Sarkar 2008 |
| SAT-based search | fails on full | - | reported resistant |
| **this tree's deepest probe** | **~23** | free | every bench here |
| **this tree's forward wall** | **10** | free | `bench_depth_cuda` |

**Preimage is the class mining resembles**, and it reaches deepest of all: 52 of 64 steps. That is
the
number to hold against anything this document claims, because a preimage attack asks the question a
miner asks - find an input landing in a target set - instead of the question a collision attack
asks.

Note the shape of the cost column. The attacks that reach deep cost more than brute force; the ones
that are practical stop at 31. **Depth and usability trade against each other**, and nothing in the
literature has both.

**The published frontier is three to four times deeper than our wall, and that is not a
contradiction
- it is two different measurements.** Ours asks how far a *random* one-bit difference stays
statistically visible under undirected probing. Theirs constructs a *chosen* differential path,
using local collisions and the message freedom to cancel differences as they arise. A constructed
path survives where a random one is long gone.

**So `forward dies at 10` must not be read as `nothing survives past round 10`.** It means
undirected
statistics stop seeing at 10. Something directed reaches 31 in practice. Every null result in this
document inherits that caveat, because every one of them probes instead of constructs.

The one point of agreement found: the SAC literature reports sigma1, integer addition, choice and
the message scheduler contributing to diffusion "at the earliest rounds", which is consistent with
the mixing depth of 3 measured here. The specific round at which SHA-256 satisfies the strict
avalanche criterion was not obtainable - the MDPI paper on it returns 403 to an automated fetch -
so that comparison is open.

### The published SAC dip, reproduced and then refuted

Vaughn and Borowczak report SHA-256 satisfying the strict avalanche criterion from round 23 to 53,
**failing it from 54 to 57**, and satisfying it again from 58. They call the late failure unexpected
and attribute it to a diffusion-dampening effect between sub-functions. Their earlier paper makes
the stronger claim that SHA-256 never meets the SAC at any round, with min and max pinned at
49.7688% and 50.2119% even at round 64 while the *mean* converges to 49.99997%.

`bench_sac` implements their statistic - the 512 by 256 matrix counting how often output bit j flips
when message bit i is flipped, scored by whichever entry sits furthest from one half. It is not a
near relative of anything else in this tree, which reads per-word Hamming means instead.

**Their onset reproduces exactly.** At 2^20 trials, matching their million:

| round | SAC value | sigmas |
|---|---|---|
| 21 | 0.06070614 | 899.7 |
| 22 | 0.57457638 | 152.7 |
| 23 | 0.50221729 | **4.5** |
| 24 | 0.49766350 | 4.8 |

Round 23, independently. That validates the instrument.

**The dip does not survive a ratio test.** Rounds 54 to 57 at three sample sizes:

| k | deviation from half | sigmas |
|---|---|---|
| 2^18 | 0.00438, 0.00423, 0.00404, 0.00460 | 4.5, 4.3, 4.1, 4.7 |
| 2^20 | 0.00216, 0.00220, 0.00201, 0.00217 | 4.4, 4.5, 4.1, 4.4 |
| 2^22 | 0.00110, 0.00111, 0.00114, 0.00110 | 4.5, 4.5, 4.7, 4.5 |

The absolute deviation halves each time k quadruples, which is 1/sqrt(k) exactly, and **the sigma
holds at 4.5 across a sixteenfold range**. A real leak does the reverse: it holds its deviation and
grows in sigma. This holds its sigma and shrinks its deviation, the definition of noise.

The constant is not arbitrary. The SAC value is the largest of 131,072 matrix entries, and the
largest of that many null draws peaks at sqrt(2 ln 131072) = **4.85**. Measuring 4.5 consistently is
that maximum, doing what a maximum does.

**Both papers' anomalies are the same artifact.** The 2026 dip crosses a Bonferroni threshold of
5.327 sigmas that sits only half a sigma above the null's own peak, so fluctuation crosses it
occasionally. The 2024 claim that SHA-256 never meets the SAC rests on a persistent 0.21%, which at
their million trials is 4.2 sigmas - *below* the 4.85 the null produces unaided. Their own
Bonferroni
correction fixed the second; the first needs the sample scaling to see.

**The signature of a null in this statistic is now known and is itself a function:** deviation
proportional to k^(-1/2) with sigma constant near 4.5. Anything real breaks it in a specific,
recognisable way, which makes this a reusable instrument instead of one result.

### The operation map, and where it stands against the field

Each operation isolated on the linear spine, so the only difference between arms is which single
nonlinear operation is present. Every cell measured here.

| operation | diffusion, whether | diffusion, speed | algebraic degree |
|---|---|---|---|
| **carry** (integer addition) | no - same plateau without it | **yes** - concentrates four rounds into one | **yes - effectively all of it** |
| Choose | **yes** | some - peak 3.22 falls to 2.87 | almost none - degree 5 by round 7 |
| Majority | no | no - 0.4% | almost none - degree 5 by round 7 |
| Sigma0, Sigma1, schedule, K | no, provably | no - speed exactly 1.0000 | no - degree 1 forever |

Degree by round, one nonlinear operation at a time:

| rounds | full | Maj only | Choose only | carry only | linear |
|---|---|---|---|---|---|
| 2 | 3 | 1 | 1 | 4 | 1 |
| 3 | 6 | 2 | 1 | 6 | 1 |
| 4 | 9 | 2 | 2 | 9 | 1 |
| 5 | >=18 | 3 | 3 | >=18 | 1 |
| 7 | >=18 | 5 | 5 | >=18 | 1 |

**The carry alone reproduces the whole function's degree.** The `>= 18` is this bench's cube ceiling
instead of a measurement, so what is proved is the separation - carry-only past 18 while
Choose-only sits at 3 - not the carry's absolute degree.

**Majority is redundant on four independent measures**: SAC level, dampening ratio, diffusion speed,
and algebraic degree. Both published papers also find Majority-removed indistinguishable from
unmodified. Whatever it is for, nothing here can see it.

**Where this stands against the field, checked 2026-09-09.** The carry is not unexplored ground. It
is the most heavily mapped part of the whole subject:

- Lipmaa and Moriai (FSE 2001) give **exact** algorithms for the differential probability of
  addition modulo 2^n, in log n time, closed form instead of approximate - reducing the hardest
  case from 2^(4n) to log n.
- ADP-XOR, UNAF, bit-vector differential models and work on the non-independence of chained modular
  additions extend it, with results still appearing in 2025.
- The 31-step collision is built from exactly this machinery, controlling carries through local
  collisions.

So the result above is a **rediscovery of why the field lives in carry space**, not a gap in it. The
rules there are not undefined; they were solved twenty-five years ago and are hard instead of
unmapped. What does appear to be unstated is the separation itself: both SAC papers group Choose,
Sigma1 and integer addition together as diffusion contributors, and the decomposition here says
diffusion is not why the carry matters. Choose supplies diffusion, the carry supplies degree, and
those are different jobs.

The mechanism has a shape worth keeping. Choose and Majority act inside the bit lattice where GF(2)
describes them. A carry leaves its bit position, travels where GF(2) has no coordinate, and rejoins
one position higher. The measurement says that path outside the lattice carries nearly all the
degree - and it is also why a bijection can appear to destroy information while destroying none: the
round stays invertible and the difference stays exact, but a GF(2)-shaped instrument loses the
ability to describe it and reports noise.

### The rotational ridge, and a decay law that is quantized

Reading the SAC matrix by its **maximum** takes one cell of 131,072 and discards the rest. It peaks
at sqrt(2 ln N) whatever the function does. Folding the cells onto
`(input bit - output bit) mod 32` instead puts **4096 cells behind each number**, and that is where
rotational structure would live, since a rotation makes bit j depend on bit j-r across every word
pair instead of concentrating anywhere.

| rounds | loudest residue | sigmas | walked | verdict |
|---|---|---|---|---|
| 12 | 26 | 15773.15 | - | structure |
| 13 | 26 | 13724.82 | +0 | structure |
| 14 | 26 | 11676.61 | +0 | structure |
| 15 | 26 | 9627.78 | +0 | structure |
| 16 | 26 | 7580.54 | +0 | structure |
| 17 | 26 | 5546.15 | +0 | structure |
| 18 | 26 | 3551.43 | +0 | structure |
| 19 | 26 | 1916.81 | +0 | structure |
| 20 | 26 | 789.13 | +0 | structure |
| 21 | 26 | 160.61 | +0 | structure |
| 22 | 1 | 13.13 | +7 | collapsed |
| 23 | 12 | 2.09 | - | flat |
| 32 | 8 | 2.07 | - | flat |
| 64 | 31 | 2.04 | - | flat |

**The ridge does not walk.** Residue 26 dominates for ten consecutive rounds. It is a fixed point of
the composition instead of something rotating, which answers the unwinding question negatively:
there is no moving structure to chase with an inverse rotation.

**The decay is quantized.** The first four differences are 2048.33, 2048.21, 2048.83 and 2047.24,
and one sigma of the class mean at that sample is 1.526e-5, so 2048 sigmas is **exactly 1/32**. The
ridge loses one thirty-second of its amplitude per round - one bit position of thirty-two going
diffuse - holding to four decimal places for five rounds, then accelerating into collapse at 22.

**Verified at four times the sample**, because 2048 is 2^11 and the trials were 2^18, so every clean
power of two in that arithmetic came from the chosen sample size. At 2^20 the sigmas read 31546.74,
27450.50 and 23354.13 - **exactly double**, sqrt(k) - with differences of 4096.24 and 4096.37, so
the absolute drop held at 1/32 while the sigma grew. That is the signature of signal, and the exact
opposite of the refuted SAC dip which held its sigma and shrank its deviation.

**And the null past round 23 is now the strongest in this document**: 2.09, 2.07 and 2.04 against a
2.63 peak, with 4096 cells behind each number instead of one - roughly sixty-four times the
sensitivity the maximum had, finding nothing. The harmonic sweep agrees: the round-23 profile
transforms to a loudest tone of 1.80 against a 2.35 null, so no repeating trend, no harmonics and no
side lobes.

Not claimed: which rotation residue 26 corresponds to. After twelve rounds the effective residue is
a composition of many rotations, and attributing it to Sigma1's ROTR25 or Sigma0's ROTR22 because
they sit nearby would be reading a coincidence.

### Tested here, and untested

Naming both, because a list of what was measured is misleading without the list of what was not.

**Tested, and null:** the output set (Walsh over all 2^32-1 masks), difference propagation forward
and inverse, per-bit and per-pair correlation between intermediate state and outcome, the nonce
space by bit and by weight completely, hill climbing, the two linear languages, narrowed widths,
varied word counts, and the rank of all four mixing functions.

**Tested, and positive:** `wall = words + 2` decomposing into mixing depth 3 plus transport;
`kernel = deg gcd(p(x), x^w + 1)`; sparse schedule paths at W19, W23, W27 with measured rates; the
exact taint and cone structure that priced the miner's two savings.

**Untested here, and this is the gap the literature exposes:**

- **Constructed differential paths.** Everything here probes and nothing here builds. The published
  31-step result is a path someone designed, with local collisions arranged so differences cancel.
  We have never attempted to construct one, only to detect one, and detection is the weaker
  instrument by a factor of three in rounds.
- **Message freedom.** A collision attack varies the whole message to steer the path. Mining fixes
  all but 32 bits, so most published technique does not transfer - but that is an argument about
  applicability, not one we have measured.
- **Triples and higher combinations** of intermediate state bits. Pairs were tested and are null;
  2.7 million triples would push the null peak to about 5.4 and were judged not worth the run.
- ~~The strict avalanche criterion round count.~~ Obtained and reproduced: onset at round 23, and
  the reported 54-57 dip refuted by ratio test.
- ~~Whether any statistic in this tree has been read as a maximum without being scored as one.~~
  Audited 2026-09-09. Four benches clean, one finding.

  | bench | statistic | null peak sqrt(2 ln N) | threshold used | verdict |
  |---|---|---|---|---|
  | `bench_depth_cuda` | max of 8 words | 2.04 | 4.0 | conservative |
  | `bench_words` | max of up to 16 words | 2.35 | 4.0 | conservative |
  | `bench_depth_cuda` per-bit | max of 256 bits | 3.33 | 5.0 | conservative |
  | `bench_trap` | max of 256, 32640, 32, 33 | scored explicitly | - | correct |
  | **`bench_nature`** | **best grip over 4096 lags** | **4.08** | **none** | **uncorrected** |

  The conservative rows are safe in the direction that matters: a real signal between the null peak
  and the threshold is missed instead of invented, so the depths reported here are lower bounds and
  not false positives.

  `bench_nature` is the finding. It takes the best grip over 4096 lags, a maximum over 4096
  draws, and corrects for the alphabet baseline but not for that selection. **Its absolute grip
  figures are inflated** - the headline "GF(2) sees additive structure at ~3.5 bits" is a
  best-of-4096 and overstates by whatever the null peak contributes. The comparison between the two
  languages is probably unaffected, since both arms select their maximum over the same 4096 lags and
  inherit the same inflation, but that reasoning is an argument instead of a measurement and the
  absolute numbers should not be quoted without it.

- ~~Whether the sub-function dampening survives the same treatment.~~ Answered: reproduced at 0.5082
  against the published 0.508, then explained. Majority contributes no diffusion that Choose does
  not already provide, so measured equals A while the independence model predicts about 2A and the
  ratio is one half by construction.
- ~~Why the a half's per-slot depths looked irregular while the e half was clean.~~ Answered: both
  are exact chains, and the a half's offset depends on the chain length while the e half's does not.

### The cheesegrater, and what the field's own unknowns eliminate

The working picture was a flat plane with holes to be found. The measurements say something closer
to a badly made cheesegrater: holes exist, they are in known places, and they shut before they go
through.

| | measured |
|---|---|
| rounds 12 to 21 | a ridge at residue 26, the same residue every round |
| its decay | exactly 1/32 of amplitude per round, five rounds running |
| round 22 | collapses |
| rounds 23 to 64 | flat, at sixty-four times the sensitivity of the maximum |

A hole that closes at a known rate is not a defect, it is the diffusion working, and the design's
answer is the forty-one rounds that follow it. The 52-step preimage is somebody pushing a hole far
deeper than any probe here reaches - and paying a cost above brute force to do it, the same
statement from the other side.

**Cross-elimination against the field's own open problems.** Their unknowns and ours are not the
same set, and where one is settled the other narrows:

- **They cannot extend a constructed path past 52 steps.** We cannot construct one at all. So the
  gap between our ~23 and their 52 is entirely construction technique, not sensitivity - which the
  spectral fold proved directly by buying zero rounds with 64x the sensitivity.
- **SAT-based search is reported to fail on the full function.** That is a fourth independent
  instrument class finding nothing, alongside the statistical, spectral and algebraic ones here.
  Four unrelated methods failing in the same place is evidence about the object instead of about
  any one method.
- **Their deep attacks cost more than brute force.** So the practical frontier is 31 steps and the
  reachable frontier is 52, and nothing has both. Any claim of a usable shortcut has to beat that
  trade, and nothing measured here comes close to either end of it.

### The wacky end, kept apart from what was measured

None of these is a result. Each is a posit with a stated test, filed here so the measured sections
stay clean. Ordered by how buildable instead of how likely.

**The ridge is an eigenvector.** Residue 26 does not move for ten rounds while its amplitude decays
by a fixed factor, as the dominant eigenvector of a linear transfer operator does,
with 1/32 as the eigenvalue. **Test:** build the 32 by 32 operator that maps one round's residue
profile to the next, diagonalise it, and check whether residue 26 is the dominant eigenvector and
1/32 the leading eigenvalue. **Falsified if** the operator's dominant eigenvector is anything else,
which would make the fixed point a coincidence of this header. Buildable today.

**The constants are not optimal.** SHA-256's rotation amounts were chosen in the 1990s. **Test:**
anneal over rotation triples, scoring by the wall depth and the ridge decay rate, and see whether
the
standard's choice sits at an optimum. **Falsified if** the standard beats every neighbor, which
would be a small piece of evidence that the constants were selected instead of picked. Buildable,
and the scoring function already exists in `bench_words`.

**One bit per round is a rate, not a coincidence.** The ridge sheds exactly 1/32 of its amplitude
per round, which is one bit position of thirty-two. **Test:** whether that rate is 1/w at other word
widths, using the narrowed variants. **Falsified if** width 16 sheds 1/32 instead of 1/16.
Buildable, and it would turn a number into a law.

**The carry direction matters.** The carry moves information one bit position upward. **Test:** a
variant whose carry propagates downward instead, and whether algebraic degree still grows at the
same rate. **Falsified if** it does, which would say the extradimensionality matters and the
direction does not. Buildable but it is no longer SHA-256, so it says something about ARX instead of
 about the standard.

**Annealing must fail on the nonce space.** The winner distribution is flat by bit and by weight,
completely over all 2^32. So simulated annealing, hill climbing and every gradient method must
perform exactly at chance. **Test:** run one and confirm. **Falsified if** anything beats
enumeration, which would contradict an complete measurement and mean the complete one is wrong.
Buildable, and its value is as a fifth independent confirmation of flatness and not as a hope.

**The function has fixed points under self-feeding.** Feed the compression output back as its own
message schedule and iterate. **Test:** whether any state is fixed, or any short cycle exists.
**Falsified if** cycles are of the length a random permutation gives, as they should be.
Wacky, cheap, and almost certainly null.

**Diffusion is a Landauer-limited rate.** One bit of describability destroyed per round is a
thermodynamic quantity. **Test:** none that this tree can run. Filed as unbuildable and kept only
because the arithmetic is suggestive, not because it is a plan.

### Trends across the whole body

Patterns that hold across results instead of inside one. These are where the next questions come
from, because a trend with one exception is a lead and a trend with none is a law.

**Every decay is a constant decrement, not a constant fraction.** Nothing here decays exponentially.

| what decays | rate | shape |
|---|---|---|
| ridge amplitude | 1/32 per round | linear, then knee, then collapse |
| carry-free describability, forward | 1/16 per round | linear eleven rounds, then knee, then tail |
| total deviation mass | -4089 per round | linear, then knee |
| describability, inverse | not linear - peaked at round 7 | rise then fall |

Three of four are exactly linear over five to eleven rounds and two are exact reciprocal powers of
two a factor of two apart. Natural processes decay by half-lives; these decay by fixed amounts,
as a thing built of discrete steps, each doing one unit of work, should.

**Everything dies between 21 and 23.**

| structure | dies |
|---|---|
| rotation-equivariance | 8, abruptly |
| forward difference visibility | 10 |
| inverse describability | 14 |
| inverse difference visibility | 15 |
| residue ridge | 21 |
| forward describability | 21 |
| every probe, chi-square included | 23 |

Two unrelated statistics landing on 21 is the part worth explaining.

**Every line of attack here and in the literature broke on the same assumption: that the pieces were
independent.** This is the strongest trend in the body and it is not about SHA-256 at all - it is
about how this kind of measurement fails.

| line of work | what was assumed independent | what it actually is |
|---|---|---|
| multiple linear cryptanalysis -> multidimensional (Hermelin, Cho, Nyberg) | the linear approximations being combined | correlated; the multidimensional chi-square method exists to drop the assumption |
| rotational cryptanalysis of ARX, 2015 revisit (Khovratovich et al.) | chained modular additions form a Markov chain | they do not, so per-addition rotational probabilities cannot be multiplied. The standard formula is wrong |
| our chi-square over 42 depths | the depths | one shared message set. -4.10 sigmas became -0.32 with a seed per depth |
| our first residue-fold null | the 131072 cells | measured spread 452 against an analytic 512, so this one was nearly right, but only measurement said so |
| our synthetic harness control | the rows | the row seed offset collided with splitmix's own Weyl constant, so adjacent rows shared seven words of eight and the variance came out 6.93 times too large |

Three published literatures and three of our own instruments, all failing the same way. The lesson
is procedural and it is the thing here that transfers to any other function: **the null must be
measured through the same code path, never computed from theory.** Every correct call tonight came
from running the instrument on data whose answer was already known.

**Sensitivity stopped buying rounds a long way back.**

| instrument | sharper than the max by | extra rounds bought |
|---|---|---|
| residue fold | 64x | 0 |
| chi-square over every cell | ~80x | 0 |

Two independent demonstrations that the wall is not a sensitivity limit. What moves the frontier is
construction, and that is a different activity.

**Direction asymmetry changes sign between measures**, so the pair identifies direction
where neither does alone: differences survive longer backward, description survives longer forward.

**Structures come in two components.** The inverse-versus-forward bit profile is a geometric carry
transient plus a slow drift. The decay curves are a linear phase plus a knee plus a tail. Nothing
measured here has turned out to be one thing.

### Refuted, with what killed each

Kept and not deleted, because a refuted claim is the cheapest kind of knowledge and several of
these were structural for a while. Every row names the measurement that ended it.

| claim | status | what killed it |
|---|---|---|
| forward converges, the inverse does not | **refuted** | the inverse scales as sqrt(N) at every depth 9-14: ratios 4.00, 4.00, 3.99, 3.99, 4.22, 3.83 for 16x pairs. Both have walls; only the shapes differ |
| the inverse has no wall, 16 and climbing | **refuted** | it dies at 15; round 16 reads 2.438, 1.317, 0.881 as pairs rise, which is noise shrinking |
| one round per fourfold increase, extrapolable | **refuted** | that was the decay rate being measured, not a trend to project |
| the word statistic goes blind at round 10 | **refuted** | the per-bit refinement sees more where there is more (inverse 14: 18.5 by bit against 7.5 by word) but no depth in either direction reads by bit and not by word |
| forward round 10 is small, not off | **refuted** | at 2^30 pairs a continued slope predicts 9.706 and it reads 2.386, unmoved across 2^26/2^28/2^30. The same extrapolation on the inverse as control lands within 4 significant figures |
| decay is geometric; 29.7x forward against 2.1x inverse | **refuted** | sweeping from round 1 shows both accelerate. That compared forward at its steepest to the inverse four rounds earlier on the same shape |
| 1.469 per round (the first fitted slope) | **refuted** | the fit ran through rounds pinned at the statistic's ceiling, which are the chain holding an untouched word and carry no rate |
| the peak destruction rate tracks word width | **refuted** | peaks read 3.50, 2.05, 1.67, 3.54, 5.24, 3.03, 4.86 bits against widths 2.00 to 5.00, and the column is not measurable at that resolution anyway |
| the schedule pair is lossy because it carries shifts | **refuted** | all four functions have rank 32 and kernel 0. XOR against two rotations restores what the shift drops |
| the width sweep measures annihilated state functions at several widths | **refuted** | that is the raw-amount object. In `bench_narrow`'s clamped object Sigma0 is clean at every width and only width 12 carries a kernel |
| 461 of 512 word-rounds, 10.0% per nonce | **refuted** | two blocks run per nonce and the savings land in different ones. 973 of 1024, 5.0% |
| a 24-of-64 visibility envelope | **withdrawn** | reads 24, 24, 25, 26 at 2^20 through 2^26 pairs; it was a snapshot of two moving numbers |
| round 7 is a hard wall on `depth = c - log2(w)` | **refuted** | 7 was a sampling floor. It moves to 10 with 100x the pairs. The slope is the finding, the intercept is the detection floor |
| topology explains the forward/inverse asymmetry | **refuted** | the cone comparison runs the opposite way, backward saturating in 2 rounds against forward's 16, because a cone bounds what *could* arrive instead of what does |
| a 0.0035-bit differential bias between the languages | **refuted** | one shuffle read as the distribution. Eight shuffles give mean 0.0006 and spread 0.0038, which is -0.18 and +0.54 standard deviations |
| a repeating-key corpus is a GF(2)-only control | **refuted** | a repeating XOR key creates a period both languages see: add 1.1585 against xor 0.9213 |
| the inverted direction dies at 14 | **superseded** | 15, at more pairs |
| the 5.0% word-round saving is worth 5.0% of runtime | **refuted** | implemented and exactly correct on 200,000 nonces, and measured at 0.998, 0.978, 1.079, 0.957 - median about 1.00. Word-rounds bound arithmetic, not runtime |
| two scans agreeing over a nonce range tests the shortcut | **refuted** | an anchor survives about once in 2^32 nonces, so both arms agreeing that a range holds no share tests nothing. The check now compares anchor words against full digests nonce by nonce |
| a single timed pass can resolve a 5% effect | **refuted** | one pass each read 0.935 to 1.166 on this machine, a spread wider than the effect. Best-of-seven with alternating arms is what the figures use |
| vector walk / hill climbing finds a gradient | **refuted** | walk 20.500 against enumeration 20.375: no landscape to climb (H13) |
| a minimum weight per word measures sparsity | **refuted** | a minimum is a tail statistic: at 2^27 pairs chance alone gives a one-bit word once per word. The rate against 33/2^32 is the measurement; the first `bench_sparse` reported the minimum and had to be rewritten |
| real headers hash differently from invented ones | **refuted** | genesis, 125552 and an invented header give the same sparse words at the same rates; the padding and ten zero words change nothing |
| the sparse words step by four (19, 23, 27) | **refuted** | the exact trace floors the nonce at 2, 1, 6, 2, 4, 2, 7, 6, 5, 2, 11 across W18-W28. Only W19 is a genuine path; the floor-2 words are 18, 21, 23, 27, spaced 3, 2, 4. The step was which cancellations cleared the sampling floor |
| a linearized weight of zero means the word is not reached | **refuted** | taint and weight are different facts. W25 from a merkle difference cancels over GF(2) and still differs, through carries, at one bit 13% of the time |
| a floor of one means the path is reachable | **refuted** | W0 floors at 1 on W33 and was never observed in 2^25 pairs. The floor needs a carry-free chain and that chance falls with its length |
| the dependency matrix carries sub-binomial variance, -4.10 sigmas | **refuted** | the 42 pooled depths shared one seed, so one message set's fluctuation was counted 42 times and divided by sqrt(42). A seed per depth reads -22.5, which is -0.29 sigmas. The denominator was not the problem: the spread measured across 42 seeds is 452 against the analytic 512 |
| the residual field is smooth, with a length scale | **refuted** | autocorrelation at eight lags on both axes reads max abs 2.40 against a max-of-sixteen null peak of 2.36, and a binomial-by-construction harness reads 2.15 on the same code. The field is white in SHA-256 and in the harness alike |
| the harness control's 6.93x variance was a property of the matrix | **refuted** | it was an injected constant collision: the row seed offset was splitmix's own Weyl increment, making row b slot j+1 the identical draw to row b+1 slot j. Adjacent rows shared seven words of eight. Fixed, the control reads 469 against the analytic 512 |
| **the residue-26 ridge, and the 1/32 law as a rotational structure** | **refuted** | the fold never subtracted what all 32 classes share. Incomplete avalanche and the message-schedule light cone both offset every class equally, since neither depends on the output bit. Residue 26 sits at **-1.36 sigmas** from the class mean against a null peak of 2.63, on the *negative* side, and is never the loudest class. The 1/32 decay is real but it is the common mode's, which 26 tracked with a fixed offset. This was the largest claim in the body and it was in the book |

### What the residue fold holds once the common mode is removed

Not nothing, and what is there is the round function's own bit transport. The ranking is identical
at every depth from 6 to 19.

| rank | class | sigmas at round 12 | what it is |
|---|---|---|---|
| 1 | 0 | +3.95 | the diagonal: bit j drives bit j |
| 2 | 25 | +1.84 | Sigma1, ROTR25 |
| 3 | 6 | +1.60 | Sigma1, ROTR6 |
| 4 | 31 | +1.38 | -1 mod 32: the carry, bit k reaching bit k+1 |
| 5 | 11 | +1.31 | Sigma1, ROTR11 |
| 6 | 22 | +0.64 | Sigma0, ROTR22 |

Residue 0 holds +3.95 sigmas **constant to four significant figures across eleven rounds** while the
common mode falls by a factor of nearly three, and the scatter of the other classes is constant at
1174 over the same span. Two components: a common mode that decays and a class pattern that does
not move at all.

Classes 0 and 31 were predictable in advance and are not the finding. **The finding is that
Sigma1's three amounts appear and Sigma0's nearly do not** - about one chance in 225 at a
single depth, or one in 112 allowing that Sigma0 would have counted equally. The depths are not
independent, so that is one result repeated, not fourteen.

The mechanism: Sigma1 acts on e and feeds T1, which is added into both chains; Sigma0 acts on a and
feeds T2, which reaches the a chain only. **It also explains Majority measuring as nothing on four
separate tests: Majority and Sigma0 are both in T2, and T2 is the weak side.**

**This is not novel, and the honest comparison is unflattering.** Vaughn and Borowczak's follow-up
reaches the same conclusion by ablation - removing sub-functions and watching SAC convergence - and
names Sigma1, integer addition, Choose and the message scheduler as the consistent contributors,
every one of them in T1. Their method gives the answer far more decisively than a 1.3 to 1.8 sigma
reading of a residue spectrum. What is untried in the literature is the *route*: the SAC work keeps
the matrix but reduces it to max, mean and min, while ARX analysis skips the matrix for trail search
because wide-trail correlation machinery is unsuitable without S-boxes. No prior art was found for
folding the matrix onto the rotation lattice, but five general searches is weak evidence against a
literature that mostly lives in IACR ePrint.

### The receive chain, and what a calibrated null is worth

Processing the residue spectrum the way a radar receiver processes a return, because the problems
are the same ones: a large clutter background, a known transmitted waveform, and a target too faint
to see in one look. `tools/radar/radar_receive.py`.

| stage | what it does | why it was needed |
|---|---|---|
| clutter estimate | what every class shares, removed per round | the common mode is what the refuted ridge was measuring |
| **OS-CFAR** | background under a cell from its neighbors, by median and MAD | the earlier reading used the scatter of the other 31 classes, which **contains** 6, 11, 25 and 31 - all real targets. Targets in the training cells inflate the noise floor and mask the detection |
| coherent integration | sum rounds 6-16, where the signature is constant | gains sqrt(11) on a stationary target and nothing on noise |
| matched filter | project onto the waveform | the waveform comes from the standard, so there is no max-of-N to pay |

| class | per round | integrated | identity |
|---|---|---|---|
| 0 | 4.51 | **14.95** | the diagonal |
| 25 | 2.58 | 8.57 | Sigma1 ROTR25 |
| 6 | 2.28 | 7.55 | Sigma1 ROTR6 |
| 31 | 1.83 | 6.06 | the carry, -1 mod 32 |
| 11 | 1.73 | 5.72 | Sigma1 ROTR11 |

Matched filter **19.16**. Sigma1 through it reads **12.61** against Sigma0's **3.34**, a factor of
3.8 in the direction the T1/T2 asymmetry predicts. About four times the sensitivity of the crude
reading, of which the CFAR fix is 1.14 and the integration the rest.

**MTI is deliberately not used, and that is a result.** The clutter is linear in round. A double
delay-line canceller annihilates it exactly - but class 0's excess is *constant*, and a second
difference annihilates a constant too. That is the blind-speed problem, and it confirms
independently that the target has zero Doppler.

**Pointed past round 23**, the same chain reads a largest magnitude of 2.30 against a union null
peak of 2.45 over four statistics on five windows. Nothing. Per round the waveform is 5.78 in the
live window and under 0.38 past the collapse:

> **SHA-256's own bit-transport signature is suppressed by at least 15x past round 23.**

The null is worth that much *because* the same chain reads 19.16 on a
positive control eleven rounds earlier. Every other null in this work says "nothing found"; this
one says how much of what.

### The compositional assay, or: the crowbar test

A radar with a library of known materials says what a return is *made of*, not merely that
something is there. The library does not have to be collected here, because the variants can be
built: short out one sub-function at a time and watch what reflects back. `bench_sac ... assay`
plus `tools/radar/radar_assay.py`.

Predictions written into the source **before** the run.

| variant | prediction | full | variant | verdict |
|---|---|---|---|---|
| no Sigma1 | classes 6, 11, 25 go | 6.59 | 1.92 | **GONE** |
| no addition | class 31, the carry, goes | 5.46 | **-0.11** | **GONE** |
| no Sigma0 | classes 2, 13, 22 go | 1.74 | 2.22 | uninformative |

Remove Sigma1 and class 6 does not merely fade, it **flips sign**, from +6.83 to -4.28. Remove
integer addition and the carry channel reads -0.11: no addition means no carries means no -1 mod 32
transport, and the instrument reports exactly that with nothing left over.

**The Sigma0 row is an underpowered test, not a refutation.** Those classes were already at 1.74,
which is noise, and the removal of something that was not there cannot be detected. The
pre-registration said as much, so this is consistent and carries no information either way.

Side effects are informative: removing Sigma1 pushes the carry from 5.46 up to 10.84 and Sigma0's
classes from about 1.7 to about 5.0. Take out the dominant channel and the rest become visible,
because the CFAR background falls with it.

**This is the strongest methodological result in the body.** Every other reading here is validated
against a null. This one is validated against ground truth that we control: ablate a named
operation and its signature disappears. The residues are the operations.

**The experiment is not novel; the readout is.** Vaughn and Borowczak's follow-up (Cryptography,
May 2026) tests **all 127 combinations** of the seven sub-functions across all 64 rounds, so this
assay's seven single ablations are a strict subset of their design. What differs is what is read
off the matrix. They measure SAC compliance, a threshold on its maximum, which answers *does it
diffuse*. The residue spectrum answers *which channel does it carry* - Sigma1's classes collapse,
the carry dies with addition - and a pass/fail on a maximum cannot say that. Same matrix, different
question, and the honest claim is the narrow one.

#### Two variants that changed nothing, and both are results

`no_schedule` and `no_constant` reproduce the full function's spectrum to four significant figures.
Neither is a failure of the assay.

**Removing the schedule must change nothing before round 17, and it validates the light cone to the
round.** The expansion only produces W[16] onward, so at rounds 8 to 16 the function is still
consuming raw message words and the expansion cannot matter yet. Checked across the boundary, the
two are *bit-identical* at rounds 14, 15 and 16 - `-5126.9755`, `-3078.9525`, `-1033.5782` - and
diverge from round 17.

> **This resolves H6.** The knee is the message schedule switching on. The common mode decrements
> by exactly 2048 through round 16 and then breaks - 2035, 1995, 1635 - and round 17 is the first
> round to consume an expanded word. Before it the function eats sixteen raw independent message
> words; from it, combinations of them, so the input statistics change and the linear decrement
> stops. A control built for something else explained it.

**Removing the round constants changes nothing because the constants do not diffuse.** Adding a
fixed K_t to a uniformly distributed state leaves it uniformly distributed, so the constants cannot
move avalanche statistics. They exist to break symmetry - defeating rotational and slide attacks -
and not to mix. This agrees independently with the refuted H2: the constants left no trace in
the per-round modulation either, measured a completely different way.

In electronic-warfare terms the round constants are frequency jitter. A jittering emitter defeats
an adversary's coherent integration without carrying any more information itself,
what these measurements say they do.

### Controllability, the plateau deficit under another name

The deficit from the exact dead plateau measures how much of the field is still deterministic. That
is
the attacker's quantity in differential path construction: how many rounds a message-bit
poke retains control.

| rounds past the wavefront | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|
| fraction mixed | 0.24% | 4.8% | 11.0% | 17.2% | 23.5% |

Control is near total at the wavefront and about a quarter gone five rounds later, decaying close
to linearly. The field already exploits this in path search, but here it is
measured and not assumed, and it is the same number as the plateau deficit.

### Coherent detection against a generated reference

Every other reading here estimates structure from the data, as a receiver must with no
reference. But this receiver is also the transmitter: the input difference is chosen, and a
reference can therefore be **generated** instead of tracked. Propagating the same difference through
the
GF(2)-linear round function - no addition, no Choose, no Majority - gives an exact phase reference,
because a linear map sends a difference to a difference whatever the message is. No loop noise, no
estimation loss; better than a real receiver can have.

Mixing the true difference against every rotation of that reference and taking the best is a
phase-locked loop, and the rotation it locks to is the loop phase.

| round | lock | agreement | sigmas at 2^22 | ref weight |
|---|---|---|---|---|
| 2 | 0 | 0.92300 | 5746.4 | 11 |
| 3 | 0 | 0.71458 | 4567.0 | 27 |
| 4 | 0 | 0.61285 | 3333.3 | 52 |
| 5 | 0 | 0.57491 | 2473.7 | 65 |
| 6 | 0 | 0.51419 | 539.0 | 86 |
| 7 | 2 | 0.49903 | -38.1 | 93 |
| 8+ | walks | ~0.5000 | under 2.63 | - |

**H9 is refuted, and H10 with it.** The lock sits at rotation zero and never walks while it holds,
so the difference keeps its linear part's orientation: it is **linearly polarized**, the carries
adding magnitude and not angle. There is no handedness, and therefore nothing for a de-rotation to
recover - no coherent integration in this work was losing anything to uncorrected rotation.

**The wall at 7 is real, and this matters because this body already had a fake one.** The earlier
`depth = c - log2(w)` wall at 7 was a sampling floor and moved to 10 under 100x the pairs. This one
does not move: at 64 times the sample the agreements are identical to four decimals and the sigmas
grow as exactly sqrt(64) = 8 - 8.005, 8.005, 8.003, 8.02. Deviation held, sigma grew: signal.

**A halving law.** Agreement above chance runs 0.423, 0.214, 0.113 - halving each round to three
digits - then accelerates away at 0.075 and 0.014. **Each round, the carry destroys half of what
the linear model could still predict**, for three rounds, before collapse. That is a third
constant-ratio decay in a body where every other decay is a constant decrement, and it is the only
one attached directly to the carry.

Round 7 keeps a small anti-correlation at rotation 2, real at -38.1 sigmas but only a 0.1 per cent
deviation. Rounds 8 onward are flat against the max-of-32 peak of 2.63.

### Constructing instead of sampling, and how far that actually gets

Every instrument before this one asks what deviates from chance over random messages, and all of
them go flat by round 23. The published attacks reach 39 steps. **The gap is not sensitivity.**

A 39-step characteristic has a probability near 2^-100. No amount of sampling finds an event that
rare - our best floor is 4.7e-06 and the two numbers are not on the same scale. The published work
does not *detect* those paths, it *constructs* them, choosing the input instead of drawing it and
solving the constraints with SAT or SMT. Detection and construction are different questions, and
no sharpening of the first reaches the second.

The first step of construction was already built here without being recognised: `make_reference`
is the linearized function that differential attacks on SHA-2 start from. `bench_sac ... construct`
sweeps it **completely** - every single-bit difference and all 130,816 pairs - so the answer is a
true minimum instead of the sparsest thing a sample happened to hold.

| round | best weight, 1 bit | best weight, 2 bits | random |
|---|---|---|---|
| 8-14 | 0 | 0 | 128 |
| 16 | 2 | 4 | 128 |
| 18 | 29 | 34 | 128 |
| 22 | 91 | 94 | 128 |
| 30 | 104 | 96 | 128 |
| 40 | 99 | 92 | 128 |

**Both interesting-looking columns are traps, and both were nearly believed.**

The zeros at rounds 8 to 14 sit at bits 256, 320, 384 and 448 - message words 8, 10, 12 and 14,
which have not entered the cone yet. The sweep found the light cone, not a characteristic.

And a weight near 100 against a random 128 is not sparse, it is **the minimum of that many draws**.
The min-of-N correction is the max-of-N correction wearing a different sign:

| | expected minimum | observed |
|---|---|---|
| 512 candidates | 128 - 8*sqrt(2 ln 512) = **99.7** | 99-104 |
| 130,816 candidates | 128 - 8*sqrt(2 ln 130816) = **89.2** | 90-96 |

Both land on the null exactly. **Low-weight message differences produce no sparse linear
characteristic past round 22**. Published attacks do not use them for that reason: they build
multi-word local collisions and work in the nonlinear model with message freedom, which is a
different construction entirely.

### Seeing it: two published views

- **Shadows** - the field collapsed along each axis, scrubbable round by round.
- **Voxel field** - the same data as a turnable mesh under seven embeddings.

The embedding selector is a test, not decoration. Residue is genuinely periodic mod 32, so the
**tube** is the honest map for it; the **toroid** imposes a periodicity on the round axis that does
not exist and is included precisely because it lies. Structure appearing under one embedding and
not another belongs to the map instead of the field, so agreement across embeddings is the
invariant content - the same null-by-subtraction as every other reading here. The **balloon** puts
the value in the radius, so the silhouette is the field itself.

### A soliton in the dependency field

**The sharpest object found in this work, and it was invisible to every instrument here until the
projection stopped squaring.**

Summing `z^2` cannot separate a rate of 0 from a rate of 1, so cells that flip **every single time**
were painted identically to cells that do nothing. Counting the three states apart - `never`
(count 0), `always` (count = trials), `mixed` (everything else) - separates them, and nothing
cancels the way a signed sum would.

| round | never | always | mixed |
|---|---|---|---|
| 6 | 99,051 | **312** | 31,709 |
| 10 | 66,294 | **312** | 64,466 |
| 16 | 17,126 | **312** | 113,634 |
| 17 | 9,840 | 248 | 120,984 |
| 21 | 0 | 0 | 131,072 |

The `always` count holds at **exactly 312** for eleven consecutive rounds while `never` falls by a
factor of 5.8 and `mixed` climbs by 82,000 around it. And it is not sitting still in the field - it
is translating:

| round | bit range | width | cells | words spanned |
|---|---|---|---|---|
| 6 | 57..191 | 135 | 312 | 1..5 |
| 8 | 121..255 | 135 | 312 | 3..7 |
| 10 | 185..319 | 135 | 312 | 5..9 |
| 12 | 249..383 | 135 | 312 | 7..11 |
| 14 | 313..447 | 135 | 312 | 9..13 |
| 16 | 377..511 | 135 | 312 | 11..15 |

**A rigid object, 135 bits wide and 312 cells in area, moving at exactly 32 bits per round with zero
change in form.** That is a soliton: a shape that propagates without dispersing. Stationary in the
co-moving frame, so nothing that averaged over rounds could see it.

It is the **same slope 32** the slant-stack detected at 7.18 sigmas, but this is not a statistical
detection - it is exact, with no variance across eleven rounds.

Its shape decomposes: at round 12 it is word 7 positions 25-31 (7 bits), words 8, 9 and 10 entire
(96 bits), and word 11 entire (32 bits). Four full words and a seven-bit trailing edge, and seven is
the waterfall's fall time.

#### What the 312 cells are

The projection sums over the output axis, so `bench_sac ... cells` names them instead. The answer
is identical at rounds 8, 10 and 12.

| part | count | mechanism |
|---|---|---|
| **aligned**, residue 0 | 256 | integer addition. Flipping bit k of an addend always flips bit k of the sum, since carries only run upward, so bit k of W drives bit k of T1 and thence of `a` and `e`. Two cells per bit, four words, 32 bits: 4 x 32 x 2 = 256 |
| **skewed**, residue 25 | 56 | Sigma1's ROTR25. Seven bits (25 to 31) x eight state words |

**312 = 256 + 56 exactly**, and the word breakdown closes too: the newest word contributes 64
(pure aligned), the three behind it 78 each (64 aligned + 14 skewed), and the oldest 14 (skewed
only, its aligned cells already mixed away). 4 x 64 = 256 and 4 x 14 = 56.

The certain cells spread perfectly evenly over the eight state words - 39 each at every depth - so
both copy chains carry them identically.

**The skewed half is measured but not explained, and the obvious mechanism fails.** The natural
story is that a flip propagates carries upward, so only the *lowest* of Sigma1's three images
escapes contamination from below. That predicts residue 11 should appear for some source bits -
at k = 20 the images are k-6 = 14, k-11 = 9 and k-25 = 27, so 9 is lowest and residue 11 should
survive. It never does. **All 56 sit at residue 25 and none at 6 or 11**, at every depth measured.

So: the aligned half is understood, and the skewed half is an exact measurement with a wrong
explanation. That is a sharper open question than the one it replaced.

#### Where this meets the published work

> **Provenance warning, 2026-09-09.** The bibliographic records below are verified against Crossref
> and the IACR ePrint archive and are sound. **What these papers are said to claim is not verified
> from the papers themselves** - it came from search-engine summaries, which is provenance for a
> title and not for a claim. The section is left standing so the correction can be read against it.
> Being sourced from a snippet is how a plausible attribution becomes a citation nobody checked.

The soliton is a set of probability-one paths through the round function, and a
local-collision construction is built out of exactly those. Three points of contact, none of them
coincidental:

| published | measured here |
|---|---|
| "it is advantageous to ensure that many bits in the differential path are MSBs" (New Local Collisions for the SHA-2 Hash Family, ePrint 2007/352) | the 256 aligned cells *are* MSB-style carry-free propagation, arrived at from the other side |
| "the message expansion of SHA-2 does not play any role in the first 16 steps" | the knee at round 17, confirmed by a schedule ablation that is bit-identical through round 16 |
| generalised nonlinear local collisions that succeed with probability 1 | the "certain" cells are probability-one propagation, counted and not constructed |

**And the boundary matches exactly.** Sanadhya and Sarkar's *Deterministic Constructions of 21-Step
Collisions for the SHA-2 Hash Family* reaches 21 steps. The signed projection says probability-one
propagation **ends at round 21**: `never` and `always` both fall to zero there and `mixed` becomes
all 131,072 cells.

Two opposite methods on one number. They built forward from probability-one paths until the paths
ran out; this measured the field until determinism vanished. The plausible common cause is that a
deterministic construction reaches exactly as far as deterministic structure exists, which would
make this measurement the reason for their bound. **Recorded as a close match with a plausible
shared cause, not as a proven identity** - nothing here demonstrates the implication, only the
coincidence of the number.

### The field only desaturates: monotone destruction, no construction

Reading color saturation as construction and desaturation as destruction makes a sharp prediction,
because a hash should destroy structure and never build it. `tools/check/check_monotone.py` tests it on
the total field power - the signed residue fold summed in magnitude over all 32 classes.

| region | rises | steps | chance predicts |
|---|---|---|---|
| live, rounds 1-23 | **0** | 22 | 11 |
| floor, past round 23 | 24 | 41 | 20.5 |

**Twenty-two consecutive falls with not one rise**, which is 2^-22 = 2.4e-07 under a random-walk
null. Nothing anywhere in the live field gains structure. Past round 23 the rises are 24 of 41
against an expected 20.5, which is +1.1 sigma: each round carries its own seed, so those are
independent draws wandering around a floor instead of anything being constructed.

**And the rate is a power of two.** The decrement over rounds 8 to 16 is 65,534.9 with a spread of
8.4 - that is 2^16 = 65,536, to one part in 10^4. It is the 2048-per-class law already recorded,
summed over the 32 classes, since 2048 x 32 = 65536. The same law stated more cleanly.

### The findings applied to the miner

The light cone is a statement about which words can reach which rounds, and `btc_miner` already
bets on it twice. `SHARED_ROUNDS` and `SHARED_SCHEDULE` say how much of the second block can be
computed once per header and reused across every nonce. Both were derived by reading the
recurrences. `bench_sac ... miner` measures them on block 125552's real header, varying only the
nonce over 4,096 draws.

A Bitcoin header is 80 bytes, so the second block holds bytes 64 to 79 and its padding, and the
nonce at bytes 76 to 79 is **W[3]** of that block.

| quantity | predicted by the cone | measured | in `sha256_core.c` |
|---|---|---|---|
| first round the nonce reaches | 4th, so 3 shared | **3** | `SHARED_ROUNDS 3` |
| first expanded schedule word it reaches | W[18] | **18** | `SHARED_SCHEDULE 18` |

The round follows from word w being unable to act before round w+1. The schedule word follows from
`W[t]` reading `W[t-2]`, `W[t-7]`, `W[t-15]` and `W[t-16]`: the smallest t above 15 with any of
those equal to 3 is t = 18.

**Both are tight.** One more of either and the miner reuses work the nonce does change, which
submits wrong shares instead of slow ones.

A third check comes free from the running client. The anchor early exit fires about once in 2^32
nonces, and the lifetime counters read 1,310 anchors over 5.50 TH. 5.50e12 / 2^32 = 1,281 expected,
so the observed rate is 1.02 times chance. An early exit running hot would be passing work it should
cut; one running cold would be discarding nonces that might be shares. Neither is happening.

**A wrong first attempt, kept.** The first version of this measurement swept all 64 schedule slots
and reported that the first moving word was 3. Correct, and the wrong question: W[3] *is* the nonce,
and the miner rewrites the sixteen message words per nonce and shares only the expansion above them.
The measurement had to start at slot 16.

### Batch invariance, and a bound that was not one

Mining hardware is memoryless across candidates. A batch of nonces sharing most of their bits could
share every gate depending only on the shared part, and `tools/hardware/batch_invariant.py` computes which
bits can possibly differ, exactly, by taint. `tools/hardware/compressor_test.py` varies what that answer
depends on.

**The taint re-derives both miner constants from nothing.** 64 schedule bits is W[16] and W[17]
entire, matching `SHARED_SCHEDULE 18`. 192 state bits is three rounds of two computed words,
matching `SHARED_ROUNDS 3`. Neither constant was given to the tool, so both are maximal **for
sequential enumeration**. Everything below turns on that qualifier.

| state discipline | 3:2 | 4:2 | 7:3 |
|---|---|---|---|
| resolved each round | 4.5% | 4.5% | 4.5% |
| carried redundant | 6.4% | 6.6% | 6.4% |

Compressor topology changes the climb - 3 bit positions for 3:2 against 2 for 4:2, measured out of a
Wallace tree - and changes this total by nothing, because a carry-propagate adder erases the
difference every round. Sigma is a xor of rotations and rotation does not distribute over addition,
so `ROTR(s+c)` is not `ROTR(s)+ROTR(c)`: a and e must be settled before Sigma reads them. The
resolved row is what a design can build.

#### A retracted claim

An earlier draft of this section concluded that **the ceiling is structural, not architectural**, and
that no arrangement of blocks moves it. That was a universal bound drawn from a single unexamined
assumption: that nonces are enumerated in sequence, so the varying field is the low bits.

Nothing requires that. Enumeration order is free, and it is worth between 1.19x and 1.43x:

| batch | low b vary | high b vary | ratio |
|---|---|---|---|
| 2^1 | 4.8% | **6.9%** | 1.43x |
| 2^4 | 4.5% | **6.5%** | 1.43x |
| 2^8 | 4.5% | **6.0%** | 1.32x |
| 2^16 | 4.5% | **5.4%** | 1.19x |

Same silicon, same batch size, same nonce coverage, different counting order. A change at bit 0 can
carry across the whole word; a change at bit 31 has nowhere above it to go, so it taints one
position. **That is the same most-significant-bit fact as the soliton's 256 aligned cells**, and the
same one the local-collision literature exploits when it arranges differential paths to sit on MSBs.
Three routes, one mechanism.

#### The failure mode this shares with the others

Four claims in this work were wrong the same way: a single measurement turned into a bound. The
residue-26 ridge, the absent diagonal, the plateau read as absence, and this. Each came from
**summing a field** - z squared collapsing always-flip onto never-flip, averaging over rounds
smearing a diagonal, a percentage hiding which bit position was varying. A sum is where an unmoving
thing disappears into a moving one. Drawing the field instead shows the cliff at round 3 that no
percentage could.

### The plateau is determinism, not absence

**A correction that changes the meaning of everything built on the input-bit projection**, though
none of its numbers.

That projection sums `z^2` over the row, and `z^2` cannot tell a rate of 0 from a rate of 1: both
give `z = -/+ sqrt(n)` and the same square. **The sum is sign-blind.** A bit that changes nothing
and a bit that flips its outputs *every single time* land on the identical plateau of 67,108,608
and are drawn as the same color at the same height.

A bit with no business being there exposes it:

| still at the plateau | what it is | why it cannot be causally dead |
|---|---|---|
| bit 511 at round 17 | word 15, position 31 | word 15 entered at round 16 |
| bit 479 at round 16 | word 14, position 31 | word 14 entered at round 15 |
| bits 18, 30, 31 at round 2 | word 0 | word 0 entered at round 1 |

Flipping the top bit of an addend **always** flips the top bit of the sum, because the carry out of
bit 31 is discarded modulo 2^32. Bit 511 flips bit 31 of `a` and of `e` with probability one. Rate
1, and the same square as rate 0.

> **The plateau is where the function is still perfectly predictable, and being outside the causal
> cone is only the special case where the prediction is "no change".** The most significant bits
> ride one round longer than the rest of their word because they never generate a carry, which is
> arithmetic instead of causality.

**The cliff is where determinism ends, not where causality begins.** Every measured number survives
- the constant, the waterfall, the shift invariance, the slope-32 diagonal - but the name was wrong,
and a wrong name misleads further than a wrong number does.

It also explains a perceptual mismatch that had been nagging at the viewer: two physically opposite
states are quantized onto one pixel. A field that the eye models as having structure is rendered
as flat. The fix is to project the signed deviation instead of its square, which splits the bedrock
into two opposite surfaces.

### The light cone, measured

The staircase is a causal boundary and both of its edges are exact.

- **Entry.** Round t consumes W_t, so message word w cannot affect the state before round w+1. Below
  that edge every cell is pinned at z = -sqrt(n) exactly, giving a plateau of 67,108,608.0 to the
  last digit at 2^18 trials.
- **Propagation.** Information moves one register per round down a -> b -> c -> d and
  e -> f -> g -> h, so those words come alive at rounds 1, 2, 3 and 4.

**Shift invariance.** Aligned to its own wavefront, every message word's avalanche profile is the
same to 1 part in 10^4, degrading to 1 part in 40 five rounds out. Within the register chains it is
6 significant figures - 133888847, 133892160, 133891356, 133893525 for a, b, c, d.

**The a/e asymmetry, finally a number.** The two chains differ by 2.3e-3, which is 66 times the
within-chain spread, so it is real. At round 1 both a and e are T1 plus a constant, but *different*
constants - Sigma0(a)+Maj for one, d for the other - so the asymmetry is carry geometry.

| conditioning on the Choose selector splits the transport into two regimes | **refuted** | gating on bit 16 of e at round 8 and folding each half separately, the largest difference over 11 depths is 3.38 sigmas against a union peak of 3.42. The ratio test settles it: at 4x the sample the *deviation shrank*, 0.0066 to 0.0029 against 1/sqrt(4) = 0.5, which is noise. The sigmas only wander around the peak, 3.38 then 3.55 |
| low-weight message differences give sparse linear characteristics | **refuted** | the complete sweep's best weight-1 result past round 22 is 99-104 against an expected minimum of 99.7 for 512 candidates, and weight-2 is 90-96 against 89.2 for 130,816. **Min-of-N is max-of-N with a sign.** Both land exactly on the null |
| periodic spikes at a tilt, running deep through the field | **refuted** | seen in the voxel viewer and measured directly: the largest deep input-bit excess over rounds 24-48 is 3.18 sigmas against a max-of-512 null peak of 3.53, and the strongest autocorrelation in the bit index is lag 21 at 2.19 against a 64-lag peak of 2.88. Lag 32, the word structure, reads 0.0122. **The tilted periodic lines are real only in the shallow rounds, where they are the sixteen light-cone wavefronts 32 bits and one round apart.** Deep, they were two defects of my own renderer: a minimum box height painting every quiet cell the same size and color, and 512 rows compressed into 190 units of screen space aliasing into moire banding. The clamp is removed |

### Calibrated sensitivity, measured and not asserted

A null is worth more as a bound than as an absence. `bench_sac ... waves` injects a plane wave of
stated amplitude into a matrix that is otherwise binomial by construction, fades it, and records
where each readout loses it. That converts "nothing found" into "nothing above this amplitude".

| readout | 5-sigma floor, per-cell bias | notes |
|---|---|---|
| residue fold | **3.05e-05** | a matched filter: the injected wave is residue-structured |
| chi-square over all cells | ~1.7e-04 | generic, so about 6x worse on this shape |

The wave's recovered profile is the instrument's own proof: injected at frequency 3 across 32
residues, the field autocorrelation comes back as a cosine of period 10.7, and 32/3 = 10.67. The
input and output axes agree to three digits (45.29 against 44.52, -62.98 against -62.95), the
reflection symmetry of the residue coordinate reading consistently in both directions.

**What this excludes.** No residue-structured wave with per-cell bias above 3.05e-05 survives past
round 23. The published SAC dip of 0.00272 is 89 times that floor.

**What the probe geometry contributes.** The matrix is never the function alone; it is the function
convolved with the probe. The residue coordinate exists because input and output bits were indexed
by 32-bit words, and the rotations act on that same lattice, so the ridge at residue 26 is an
interference between the two instead of a property of either. That is worth stating because it
bounds what any SAC-shaped reading can mean.

### The Doppler scan: what is moving, seen or not

Every reading before this one looks at one round at a time. Something too faint to clear the floor
in any single round is invisible to all of them however many rounds are looked at, because they are
compared one at a time and thrown away.

The rounds are not independent samples of an unknown thing. They are a deterministic sequence, so
the structure at round r is related to the structure at r+1 by the round function, and that relation
is carried in the *phase* of the residue spectrum, which every earlier reading discarded by taking a
magnitude. A structure standing still holds its phase; one drifting at v residues per round advances
it by 2*pi*f*v/32; noise does neither. Summing the complex spectrum against a velocity hypothesis
therefore adds real structure as R and noise as sqrt(R).

Each round takes its own seed. That makes it work instead of repeating the pooling mistake
above: the structure is deterministic and stays coherent whatever the seed, while the sampling noise
is made independent and decoheres. One shared seed would keep the noise coherent too and the gain
would be nothing.

Four channels are read from the same spectra: the magnitude sum, a phase-only sum with the
amplitude thrown away, a radius scan pooling every frequency at one velocity, and a sliding window
over the start round and span.

| channel | harness alone | walking wave | SHA-256 |
|---|---|---|---|
| magnitude | 4.02 | **131.24** | 3.98 |
| phase only | 4.04 | 9.15 | 4.15 |
| pooled radius | 50.75 | 21253.08 | 51.77 |
| best window | 4.07 | 94.58 | 4.37 |
| standing still | 2.19 | 3.50 | 2.25 |

**Null peak 4.66**, being the maximum over the union of all four channels: 52,299 cells, of which
the window scan alone is 42,570 because sliding start and width multiplies the grid instead of
adding to it.

**The positive control is the result worth keeping.** The wave was injected at frequency 3 walking
one residue per round, at an amplitude the ladder had already shown is below the standing floor. Its
standing-still reading is 3.50, *under* the null peak: it genuinely cannot be found by any
single-round instrument. The scan returned it at 131.24, at exactly frequency 3 and velocity -1.000,
which is a gain of 37 over the standing reading and came entirely from the motion.

Against an instrument validated that way, nothing in SHA-256's dependency matrix past round 23 is
moving, at roughly 6.5 times the sensitivity of any standing reading - an effective floor near
4.7e-06.

**Three defects, all found by the instrument's own discipline and not by inspection:**

- The scan was run on a uniform grid in velocity, but the phase a round advances is
  2*pi*(f*v)*r/32, so the coordinate the readout lives in is drift = f*v. A uniform grid in v is
  correct at one frequency and wrong at the rest: at f = 15 the step was 1.875 in drift where 42
  rounds resolve 0.195, ten times too coarse. SHA-256's loudest cell sat at f = 15, exactly where
  the grid was worst, so that reading was not trustworthy. The scan now runs uniformly in drift.
- The magnitude channel weights each round by its own amplitude, and amplitude is where the noise
  is: a round that fluctuates large contributes large whatever its phase does. A phase-only channel
  normalizes every round to unit length first, so what is asked is whether the phases line up
  instead of
   whether anything is big. A faint but perfectly coherent structure is invisible to the first
  and plain to the second.
- **Four maxima are not one maximum.** With four channels each maxed over its own grid, comparing
  any one of them to a single channel's peak is the max-of-N error one level up. Read against a
  single channel's 4.12, SHA-256's window reading of 4.37 would have been announced as a detection.
  Read against the union's 4.66 it is flat, and so is the harness at 4.07. This is the sixth time
  that correction has changed an answer in this work and the first time it was applied to a
  reporting rule and not to a number.

**A ceiling on the phase channel.** Summing R unit vectors cannot exceed R, so that statistic is
bounded above by sqrt(2R) whatever the data does: 9.17 at 42 rounds. The injected wave reads 9.15,
which is saturation instead of a measurement. Against a null peak of 4.66 the channel has about a
factor of two of usable range, so discarding amplitude is a good idea this baseline cannot afford.
It would want many more rounds than SHA-256 has.

### The dispersion relation, pre-registered before it was run

The Doppler scan asks one question of the whole field. The dispersion arm asks a finer one of each
frequency separately, and it is asked at **rounds 10 to 23** instead of past 23, because that is
the only place this function still has structure to fingerprint.

Fitting a complex exponential to `Z_f(r)` gives two numbers per frequency: a **drift**, the phase
advance per round, which is where that component is going; and a **decay**, the amplitude fall per
round, or how fast it is being elided. Together they are one complex frequency, and the shape
of drift against frequency is what identifies a mechanism and not merely detecting one.

What this can carry is **position, not value**. The phase of a component is the residue offset it
sits at, so the arm locates structure. Nothing in it recovers the value of any bit.

Written down before the run, so the reading cannot be fitted to the result afterwards:

| outcome | what it would mean |
|---|---|
| control reads drift 1.000, decay 0 at f=3 | the fit works; nothing below this line means anything without it |
| SHA drift ~0 at every loud frequency | the ridge is a standing wave, a fixed point of the composition. Confirms "it does not walk" per frequency, where the earlier reading only saw the peak not moving |
| SHA drift constant and nonzero across f | a rigid rotation, and the residue it turns at is measurable |
| SHA drift falling as 1/f | a shear instead of a rotation |
| decay flat across f | every spatial scale is elided at the same rate |
| **decay rising with f** | fine structure dies faster than coarse, which is diffusion: the signature of a smoothing operator |

The last row is worth having. The known 1/32 law is a single point on this curve, measured
at one frequency, and whether the rate depends on scale has never been asked.

One prediction against the fit itself: the 1/32 law is a *constant decrement*, not a constant
fraction. A straight-line fit to the log amplitude should show systematic curvature. If it does
not, one of the two results is wrong.

#### What it returned

**The control validates, and does more than it was asked to.** At every loud harmonic it reads
drift -1.000 and decay 0.0000 on all fourteen points, the pre-registered answer.
And the loud harmonics are the *odd* ones only - 1, 3, 5, 7, 9, 11, 13, 15 - because a square wave
has only odd harmonics and mod-32 aliasing folds 3, 9, 15, 21, 27 back into odd bins. The even rows
are noise and are marked as such. The instrument reproduced Fourier's theorem without being asked,
the strongest evidence available that the fit is doing what it claims.

**Drift is settled and it is the result.** SHA-256 reads |drift| <= 0.09 at all fifteen frequencies
with every component loud (amplitude 385 to 3683).

| freq | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| drift | -0.090 | 0.215 | -0.021 | 0.013 | 0.015 | -0.009 | -0.049 | -0.024 |

| freq | 9 | 10 | 11 | 12 | 13 | 14 | 15 |
|---|---|---|---|---|---|---|---|
| drift | -0.000 | 0.006 | 0.024 | -0.016 | -0.003 | 0.005 | 0.005 |

**The structure at rounds 10 to 23 is a standing wave at every spatial scale**, not only at the
residue-26 peak. The earlier spectral reading knew the peak did not walk; this says nothing at any
scale walks. It is a fixed point of the composition in the full sense, and it closes the unwinding
question for good: there is no rotation to chase at any frequency.

**Decay is not established, and the pre-registered reading of it does not hold.**

| | mean decay | correlation with ln(amplitude) |
|---|---|---|
| first fit, all points | -0.455 | r = 0.76, t = 4.20 |
| floor-limited fit, 12 points each | -0.193 | r = 0.68 |
| floor-limited, dropping the f2 outlier | -0.205 | r = 0.44, t = 1.70 |

The first fit was floor-limited: a component that has fallen into the noise stops falling, so those
rounds measure where the floor is instead of how fast the thing decayed - and worst for the
faintest components, which had least room to fall. "Every scale dies at the same rate"
turned out to mean, and it was the confound instead of the function.

Cutting to points ten standard errors clear of the floor **halved every decay**, from -0.455 to
-0.193. A statistic that moves by a factor of two under one reasonable methodological choice is not
a measurement yet, and the residual correlation of 0.68 says the confound is not fully gone.
Dropping the one outlier takes it to 0.44 and non-significance, but choosing to drop a point after
seeing it is not available.

**So: no claim about scale-free elision.** What it needs is a fit that is not floor-limited, which
means rounds below 10 where the amplitudes are larger, not more trials at these rounds.

### Shadows, and the theorem that ties them together

Every reading in this file is a projection. The residue fold is the field collapsed along one axis;
the chi-square is the same object flattened all the way to a scalar. Both are shadows, and a shadow
is cast from one angle. Until now nothing here had looked from a second one.

The object is three-dimensional - 512 input bits by 256 output bits by 64 rounds, 8.4 million cells
- so `bench_sac ... shadow` dumps it as four projections instead of whole, and
`tools/view/build_shadow_view.py` renders them.

**The projection-slice theorem is why this is not just a picture.** The Fourier transform of a
projection equals a slice through the transform of the object, taken perpendicular to the direction
projected along. That is the theorem tomography is built on, and it says the spectrum of a shadow
carries the object's information along one plane exactly, with nothing lost and nothing added.
Enough shadows at enough angles reconstruct the object.

It also supplies a consistency condition that can be checked and not assumed: projections along
directions related by a symmetry of the object must be identical, so their difference vanishes
exactly. **This has already been observed here without being named.** The wave control's
autocorrelation along the input axis and along the output axis read 45.29 against 44.52, 16.63
against 18.06, -62.98 against -62.95 and -52.68 against -52.56. That is the reflection symmetry of
the residue coordinate `(i - j) mod 32` cancelling to three digits: a projection-slice check that
passed, on data whose answer was known.

**Where the map is singular.** Every frequency's cone passes through v = 0 together, because the
phase ramp is identically zero there for all f. That is the degenerate point of the coordinate, and
it is why velocity resolution scales as 1/f. Running the scan in drift is the resolution of that
degeneracy. The cones intersect away from it wherever f1*v1 = f2*v2 mod 32, and those intersections
are alias points where two velocity hypotheses cannot be told apart - a scan with ambiguity points
should say so instead of pretend it is injective.

### Unknown, and honestly so

- **Why the two directions differ at all.** This is the important one and it is not answered.
  Measured: they differ, forward dying at **10** and inverted at **15** (both figures updated from
  an earlier 9 and "past 13", which were threshold crossings at fewer pairs). Not measured: the
  mechanism. Now partly constrained, though: the forward wall is the chain length plus two, exactly,
  at every word count from 8 to 16, so the forward side has a law. The inverse reaching five rounds
  further is not explained by it and no equivalent law has been found for that side. The obvious
  candidate was topology and it was tested and **failed**  - the cone
  comparison runs the opposite way, backward saturating in 2 rounds against forward's 16, because a
  cone is may-depend and bounds what *could* arrive instead of what does. A wide cone is not strong
  mixing. So the cause is elsewhere and nothing here has located it.
- Whether the two halves compose at all. Even if they did, the sum is not a fixed number: it reads
  24, 24, 25, 26 at 2^20 through 2^26 pairs. A "24 of 64 envelope" was a snapshot and is
  withdrawn. And as an attack it is not an envelope regardless, because both halves need the same
  schedule with a matching middle and nothing here has tested that.
- **Why forward terminates and the inverse decays.** The earlier entry here said the inverse had no
  wall and was still climbing. That was reading a threshold crossing instead of the signal, and it
  is withdrawn. Read as a statistic and not as a crossing, the inverse scales as the square root
  of the sample at every depth from 9 to 14 - ratios of 4.00, 4.00, 3.99, 3.99, 4.22, 3.83 for
  sixteenfold more pairs, the textbook figure. The signal was always there and was only
  ever under the threshold, so one more round per fourfold increase is the decay rate being
  measured, not a trend to extrapolate. The inverse dies at 15 and reads noise at 16, where more
  pairs make it *smaller*: 2.438, 1.317, 0.881.

  What actually differs is the shape of the approach. Forward loses a factor near 29.7 per round;
  the inverse loses about 2.1. Forward is steep enough that one round takes it from 69 standard
  errors to the floor, which looks like termination, and two candidates explain that equally well
  at the sizes first run - a genuine zero, or a slope steep enough to duck under the floor in a
  single step. Both were tested and both were subtracted:

  - Not the readout going blind. A word's mean Hamming distance is the sum of 32 bit rates, so
    opposed positions cancel there and survive a per-bit reading. The per-bit arm is a strict
    refinement and it does see more where there is more to see - inverse round 14 reads 18.5 by bit
    against 7.5 by word. It buys no reach in either direction: no depth anywhere reads by bit and
    not by word.
  - Not a steeper slope. At 2^30 pairs, 64 times the sweep, a continued 29.7x slope predicts 9.706
    at forward round 10 and the reading is 2.386 - the floor, unmoved across 2^26, 2^28, 2^30 at
    2.050, 1.782, 2.386. The same extrapolation run on the inverse as a control lands within four
    significant figures at all three sizes, so the method is sound and the forward row is a cliff.

  **The slope comparison in the paragraph above is itself withdrawn.** Sweeping from round one
  and not from round eight shows neither direction is geometric. Rounds 1 to 3 read an identical
  22989.6 because the statistic reads the least-diffused word and an eight-word shift chain
  guarantees one stays untouched - that is a ceiling, not a decay, and fitting through it reported
  1.469 per round for a curve whose own ratios reach 30. Excluding it, both directions *accelerate*:
  forward 1.10, 1.34, 1.67, 1.94, 4.48, 29.73 and inverse 1.10, 1.05, 1.07, 1.26, 1.25, 1.40, 2.10,
  1.78, 2.57, 21.09, 5.71, 3.40. So "29.7 against 2.1" compared forward at its steepest to the
  inverse at a shallow point on the same shape, four rounds earlier. Both are cliffs; the inverse's
  arrives later.

  The peak is what remains: forward destroys **4.89 bits per round** at its steepest, against 5.000
  for exactly 32x. One 32-bit word per round was the natural reading of that, and the width sweep
  tested it and did not support it. Across widths 4, 6, 8, 12, 16, 24, 32 the peak reads 3.50, 2.05,
  1.67, 3.54, 5.24, 3.03, 4.86 bits against widths of 2.00 to 5.00 - no tracking, and that column is
  not measurable at this resolution anyway. The collapse falls between two integer rounds. A
  ratio of consecutive rounds is a derivative sampled coarser than what it samples and lands where
  the grid happens to cut the fall.

  The column that does hold still is the wall: **10, 9, 9, 9, 9, 9, 10 across an eightfold change in
  word width**. A wall set by how many words sit on the shift chain is what does not move
  when the bits inside them change, and a wall set by word width would have moved. That is evidence
  for chain length and against word size, and it is not conclusive: `bench_narrow` holds eight words
  at every width, so the word count has never been varied. Varying it settles the question.

  Sub-round resolution on the peak, if it is wanted, wants the input difference weight swept instead
  of
   the rounds - a heavier difference collapses earlier and walks the fall across the grid.

  There is a second reason the peak column is not a clean comparison, and it is arithmetic instead
  of
   statistical. The rotation amounts are scaled from the standard's and rounded, so they change
  with the width, and a rotation by r on a w-bit word has orbit length w/gcd(w,r). Where the width
  shares a factor with an amount, that rotation has short orbits and mixes weakly:

  | width | Sigma0 | Sigma1 | worst gcd | peak bits |
  |---|---|---|---|---|
  | 4 | 1,2,3 | 1,2,3 | 2 | 3.50 |
  | 6 | 1,2,4 | 1,2,5 | 2 | 2.05 |
  | 8 | 1,3,6 | 2,3,6 | 2 | 1.67 |
  | 12 | 1,5,8 | 2,4,9 | 4 | 3.54 |
  | 16 | 1,7,11 | 3,6,13 | 2 | 5.24 |
  | 24 | 2,10,17 | 5,8,19 | **8** | 3.03 |
  | 32 | 2,13,22 | 6,11,25 | 2 | 4.86 |

  At width 4 the two triples are identical, so Sigma0 and Sigma1 are the same function and the
  rotation design is gone. At width 24 one amount shares a factor of 8 with the width. **The sweep
  compares seven constructions, not one construction at seven sizes**, and the peak column
  is reading. The wall holding still across all seven is the more interesting fact for surviving it.

- **The wall is the chain length, and the word count is what proves it.** `bench_narrow` found the
  wall unmoved across an eightfold change in word width, which was evidence and not proof because it
  holds eight words at every width. `bench_words` generalises the round to any even word count -
  majority and Sigma0 from the low half's head, choice and Sigma1 from the high half's head, joined
  the way the standard joins them - and eight words reproduces `bench_depth_cuda`'s wall of 10
  exactly, the control that makes the other rows readable.

  | words | wall | words + 2 |
  |---|---|---|
  | 8 | 10 | 10 |
  | 10 | 12 | 12 |
  | 12 | 14 | 14 |
  | 14 | 16 | 16 |
  | 16 | 18 | 18 |

  **wall = chain length + 2**, exact at every count. And the offset is structure instead of
  measurement: the same table comes back identical at 2^20, 2^24 and 2^28 pairs, a 256-fold range
  with no drift at all. The cliff result predicts exactly that - a collapse that happens inside one
  round does not move when samples are added, the same fact the 2^30 test read from the
  other side when forward round 10 stayed at the floor under 64 times the pairs. The two findings
  explain each other.

  Six words is the row that does not wall within 30 rounds, and it is the degenerate case: at
  three words per half, choice reads the entire high half and majority the entire low half, so the
  functions no longer select among words.

  **The +2 is 3 minus 1, and reading each slot separately shows it.** Only two slots are mixed by
  the round at all: slot zero takes T1 + T2 and slot `half` takes d + T1. Every other slot is
  `state[i] = state[i-1]`, a copy that transports a difference without touching it. So the tail of
  the chain holds whatever the join produced `count-1` rounds earlier, and the wall should be a
  mixing depth plus a transport delay. Measuring each slot's own death depth instead of the largest
  across slots:

  | words | slots from the e join to the tail | dies at |
  |---|---|---|
  | 8 | 4, 5, 6, 7 | 7, 8, 9, 10 |
  | 10 | 5, 6, 7, 8, 9 | 8, 9, 10, 11, 12 |
  | 12 | 6, 7, 8, 9, 10, 11 | 9, 10, 11, 12, 13, 14 |

  **Every slot at or below the e join dies at exactly k + 3.** The last slot is `count - 1`, so
  `wall = (count - 1) + 3 = count + 2`. The 3 is the round function's mixing depth - how long T1 and
  T2 take to saturate a freshly computed word - and it does not depend on the word count, so
  the wall tracked the count one for one. The -1 is that the chain is `count - 1` hops
  from the join to the tail instead of `count`.

  The a half is not as clean - 6, 7, 7, 9 against 7, 8, 9, 10 at eight words - because those slots
  feed majority and Sigma0 and are read back, so they are not pure transport. The e half is, and it
  is the half that sets the wall.

  This also makes the wall predictable instead of searchable: read slot `count - 1` alone, or
  measure the mixing depth once and compute any width from it.

- **The schedule functions are not weaker, and rank says so exactly.** The suspicion was that the
  schedule pair should be lossy where the state pair is not, since sigma0 and sigma1 each carry a
  shift and a shift discards bits where a rotation cannot. All four are GF(2)-linear, so this needs
  no sampling: each is a 32 by 32 matrix and its image is two to its rank.

  | function | serves | terms | rank | kernel |
  |---|---|---|---|---|
  | Sigma0 | state | ROTR2 ^ ROTR13 ^ ROTR22 | 32 | 0 |
  | Sigma1 | state | ROTR6 ^ ROTR11 ^ ROTR25 | 32 | 0 |
  | sigma0 | schedule | ROTR7 ^ ROTR18 ^ SHR3 | 32 | 0 |
  | sigma1 | schedule | ROTR17 ^ ROTR19 ^ SHR10 | 32 | 0 |

  **Every one is a bijection.** Exclusive-or against two rotations restores what the shift drops, so
  the schedule pair collides no earlier than the state pair. There is no compression here.

  Narrowed, they do lose rank, and the deficit has a closed form. A rotation right by a on a w-bit
  word is multiplication by x^(w-a) in GF(2)[x]/(x^w + 1), so three rotations exclusive-ored is
  multiplication by a three-term polynomial and the kernel is **deg gcd(p(x), x^w + 1)** exactly.
  `bench_space` checks that against the elimination at eight widths and it agrees at every one,
  including the two nonzero cases - Sigma0 losing 4 ranks at width 6 and Sigma1 losing 2 at width
  12.

  **Those deficits are in `bench_space`'s object, not `bench_narrow`'s, and the difference
  matters.**
  `bench_space` uses the raw scaled amounts, which can come out zero and make a term the identity;
  `bench_narrow` forces every amount nonzero and the three distinct. Measuring the clamped object
  directly instead of inferring it: Sigma0 carries **no kernel at any width**, clamping having
  repaired the width-6 case entirely, and the only damaged width in the sweep is **12, where Sigma1
  loses 2**. An earlier draft of this document said the width sweep measures partly annihilated
  state functions at several widths; that was read off the raw table and is withdrawn. One width is
  affected, not several, and the width-6 annihilation exists only in the object `bench_narrow` does
  not use.

  The two narrowed SHA-256s in this tree remain different objects and their rows must not be read
  against each other. `bench_narrow` never touches the schedule pair at all, since it feeds
  independent random words instead of expanding a schedule, so the sigma columns bear on nothing it
  reports.

  **The clamping also manufactures structure the standard does not have**, the fourth and
  probably worst reason the width sweep is not one construction at seven sizes. Where two amounts
  scale onto the same value the distinctness rule steps one of them by exactly one, leaving two
  amounts adjacent. sigma1 shows it at every narrowed width - 2,3 then 3,4 then 4,5 then 6,7 then
  9,10 then 11,12 then 13,14 - while the real sigma1 is 17, 19, 10 and has no adjacent pair at all.
  Counted across the sweep: **22 pairs of amounts sit one apart at the narrowed widths and 0 do at
  width 32.** None of SHA-256's four functions has an adjacent pair; nearly every narrowed one does.

- **Where the schedule is weak is sparsity, not rank.** A one-bit nonce flip expanded through the
  standard's schedule over 4096 random headers: the mean difference weight saturates at word 22,
  nineteen words after the nonce enters, but the **minimum stays at one bit through word 27**. A
  single-bit difference can cross 24 words of expansion without fanning out at all, for the right
  header. W19 = W3 + sigma0(W4) + W12 + sigma1(W17) has only W3 tainted, so the difference passes
  through additively unchanged whenever no carry fires - mean 1.94 is the carries, minimum 1 is when
  none of them do. The mean says the schedule has finished mixing five words before the tail does.

- **The sparse nonce path is reachable, and it arrives where nothing is left to attack.** `bench_space`
  found a one-bit difference surviving to W27 over random schedule words. `bench_sparse` asks the
  same of a real block, using the tree's own known-answer headers - genesis and 125552, whose hashes
  and nonces the chain recorded - and of the shape a miner actually hashes, which is not sixteen
  random words but four header words, 0x80000000, ten zeros and a length.

  The first version of that bench reported the *minimum* weight per word and was wrong to. A minimum
  is a tail statistic that grows more extreme with the sample whether or not anything is there: at
  2^27 pairs chance alone delivers a one-bit word about once per word. A minimum of one across
  the deep words is what the null predicts. `bench_space`'s figure survives only because its sample
  was 256 times smaller, where chance gives 0.001 and four hits are not chance. Counting the rate
  and holding it against 33/2^32 separates the two.

  | word | genesis | 125552 | invented header | against chance |
  |---|---|---|---|---|
  | 3 | 100% | 100% | 100% | the flip itself |
  | 19 | 47.8% | 46.9% | 53.9% | 7.0e7 |
  | 23 | 3088 | 6322 | 6424 | 6.2e3 |
  | 27 | 114 | 39 | 79 | 1.1e2 |

  **Words 19, 23 and 27 carry paths in sixty-four does.** The step of four looked
  like a period and is not one - see the exact trace below, which dissolves it. The rates are
  4.8e-1, 4.7e-5 and 6e-7. A one-bit difference at W27 costs about 1.7
  million nonce pairs to find, which is nothing; W31 would cost around 1e8 and fell below this
  sample's floor instead of being shown absent. All three headers agree, the invented one included,
  so **this is the recurrence and not the header** - the padding and the ten zero words change
  nothing about it.

  What it is worth is the part to keep. A schedule path at W27 enters the compression at round 27,
  and forward state difference visibility dies at round 10. The path arrives seventeen rounds after
  the state stopped carrying anything, so there is nothing there for it to attach to. Reachable,
  cheap, and pointed at saturated ground.

  There is an architectural reason this is hard to spend even where it is real. A differential
  between nonce n and n^(1<<b) is information that exists only when both are held at once, and a
  branchless memoryless nonce enumeration evaluates each nonce as an independent trial - it discards
  the relation by construction. Using it means computing a difference to avoid recomputing a value,
  which pays only when the shared part is large. The taint analysis prices that, and
  the 5.0% is that structure in the only form the architecture can currently spend.

- **The path can be traced exactly, and once traced it needs no sampling at all.** Replacing addition
  with exclusive-or gives the difference the schedule carries when no carry ever fires, which is
  thirty-two words of arithmetic per input bit and no pairs. That is the *floor*: a word cannot come
  out below its linearized weight except by a carry cancelling something. `bench_sparse` computes it
  for a difference placed in each of the four header words a miner can actually move.

  It immediately dissolves the step of four. For the nonce the floors at words 18 through 28 are
  **2, 1, 6, 2, 4, 2, 7, 6, 5, 2, 11** - so W19 is the only genuine one-bit path from a nonce, and
  W23 and W27 have floor **2**. Their one-bit events are a carry cancelling a bit, not a path. The
  floor-2 words are 18, 21, 23, 27, spaced 3, 2, 4. There is no period; the apparent step of four
  was which floor-2 words happened to produce cancellations above the sampling floor.

  Four categories, and the sampling agrees with every one of them at 2^25 pairs across all four
  input words, with zero contradictions:

  | trace says | meaning | observed |
  |---|---|---|
  | floor 1 | a carry-free chain reaches one bit | common where the chain is short, absent where it is long |
  | **cancels** | GF(2) terms sum to zero, so the real difference is *only* carries | often one bit - these are among the **sparsest** words, not the emptiest |
  | floor 2 | one carry must cancel one bit | uncommon but reachable, order 0.2% |
  | floor 3+ | two or more bits must cancel | never observed |

  The `cancels` category is worth keeping and it inverts the naive reading of a
  linearization. A word whose linear path vanishes is not a word the difference fails to reach - it
  is a word where nothing survives *but* the carries, and a carry-only difference is frequently a
  single bit. W25 from a merkle difference is exactly that: linearized weight zero, and one bit in
  13% of pairs.

  An earlier draft of this document reported the trace's zero as "not reached". That conflated a
  word the difference never touches with a word whose contributions cancel, which are different
  facts; taint is now propagated separately from weight.

- **Which header word is moved changes how deep a sparse difference reaches, and the nonce is the
  worst of the four.** The `t-16` and `t-7` terms pass a difference through with no sigma applied.
  A difference placed early can chain through them untouched.

  | roll | word | rate |
  |---|---|---|
  | merkle root, W0 | W23 | 56% |
  | merkle root, W0 | **W25** | **13%** |
  | nonce, W3 | W19 | 52% |
  | nonce, W3 | W23 | 0.002% |

  **Merkle rolling reaches W25 at 13% where nonce rolling reaches W23 at 0.002%** - six words deeper
  and about 6500 times more often, for a difference a miner already moves when it rolls the
  extranonce. W0 also has floor 1 at W33, and it was **never observed** in 2^25 pairs: a floor is
  what a chain with no carry anywhere achieves, and the chance of that falls with the chain's
  length. **Floor is not reachability**, and W33 is the row that proves it.

  What this does not do is help. W23 and W25 enter the compression at rounds 23 and 25, and forward
  state difference visibility dies at round 10. Deeper in the schedule is still thirteen rounds past
  where the state stopped carrying anything.

- **Both savings are now implemented, exactly correct, and worth nothing measurable.**
  `sha256_scan_scalar_early` hoists the eighteen shared schedule words and three shared rounds of
  the first block out of the nonce loop, and stops the second block after 61 rounds because the
  round moves e to f to g to h and so the anchor word is the e of sixty-one rounds - the last three
  cannot change it.

  Correctness is not in question. `bench_early` compares the shortcut's anchor word against word
  seven of the fully computed double digest on **200,000 consecutive nonces** and finds **zero
  disagreements**. An earlier version of that check only compared two scans over a range and was
  vacuous: an anchor survives about once in 2^32 nonces, so both arms agreeing that a range holds no
  share tested nothing.

  The speed is another matter. Best-of-seven alternating trials, four times over:

  | | MH/s | mean seconds to a share, difficulty 1, one thread |
  |---|---|---|
  | conventional scalar | ~1.58 | ~2700 |
  | hoisted scalar | ~1.57 | ~2700 |
  | eight-lane AVX2, as `btc_miner` runs | ~8.4 | ~510 |

  Ratios of 0.998, 0.978, 1.079 and 0.957 - straddling one, median about 1.00. **There is no
  measurable speedup.** The 5.0% figure was a count of word-rounds, and word-rounds bound arithmetic
  instead of runtime; a modern core is limited by instruction-level parallelism and by what the
  compiler can vectorise, and removing 5% of the adds changes neither. This was flagged as
  unverified when the 5.0% was first written down, and it did not survive verification.

  A single-pass timing would have reported this wrong in either direction: one pass each read from
  0.935 to 1.166 on this machine, a spread wider than the effect. Best-of-seven with alternating
  arms is what the numbers above use.

  The two savings have also **not** been carried into the eight-lane arm, so `btc_miner` does not
  have them, and on this evidence there is no reason to port them.

- **The schedule's constants have never been narrowed by anything here.** The triples above are the
  state functions, Sigma0 = ROTR2 ^ ROTR13 ^ ROTR22 and Sigma1 = ROTR6 ^ ROTR11 ^ ROTR25. The
  message schedule's own are sigma0 = ROTR7 ^ ROTR18 ^ SHR3 and sigma1 = ROTR17 ^ ROTR19 ^ SHR10,
  and `bench_narrow` never sees them because it feeds independent random words instead of expanding
  a schedule. Given that a nonce travels through sigma0 and sigma1 and not through Sigma0 and
  Sigma1, the orbit argument aimed at those four constants is the sharper form of this question and
  is not yet asked.

  **Forward is off at round 10, not merely small, bounded at least 16x below a continued slope.**
  Why the round function should terminate in one direction and decay in the other is still not
  explained here. The direction of the asymmetry is at least the expected one: slow backward
  diffusion is what meet-in-the-middle preimage attacks on reduced SHA-256 exploit, so the inverse
  reaching deeper agrees with the literature. The measured rates, 29.7 against 2.1, are this tree's
  own and are not something we have found a published figure to check against.

- **Every depth arm before this one measured state diffusion with the schedule contributing zero.**
  Those arms hand the same schedule word to both members of a pair, and in the additive difference
  that word cancels identically: `(h + S1 + Ch + K + W) - (h' + S1' + Ch' + K + W)` contains no W.
  The nonce elides itself, so the curve comes out smooth - there is only one mechanism in
  it, the state chain unwinding - and it is the wrong experiment for mining, where the difference
  lives in the nonce and expands through the schedule instead of cancelling.

  The nonce arm places one bit in message word three, expands it with the standard's schedule, and
  reads the same statistic. It sits at the exact ceiling through round 6, which the dependency table
  predicts instead of explains away: the nonce first appears in W3, enters the state at round 3,
  and needs three more rounds to reach the far end of the shift chain. It then dies at **11
  rounds**,
  one past the state difference's 10.

- **The nonce's reach is exact, not statistical, and it prices the inner loop.** W[at] draws on
  at-16, at-15, at-7 and at-2, so taint from W3 propagates by four edges and 17 of the 64 schedule
  words never see it - those are computed once per header instead of once per nonce. Running the
  same argument from the other end: Bitcoin compares the hash as a little-endian number. A
  rejection reads word seven alone, and the backward cone from it needs 1, 1, 1, 5, 6, 7 words over
  the last six rounds before widening to all eight.

  | | word-rounds |
  |---|---|
  | all sixty-four rounds, eight words each | 512 |
  | less the front rounds every nonce shares | 24 |
  | less the narrow tail no rejection reads | 27 |
  | smallest area for one block in isolation | 461 |

  **That 461 was then checked against the miner and does not survive as a per-nonce figure.**
  `sha256_scan_scalar` runs two compressions per nonce, not one - 128 rounds of eight words, 1024
  word-rounds - and the two savings land in different blocks instead of both in one:

  - The **first** block takes the midstate as input and its rounds 0 to 2 read W0, W1 and W2, none
    of which the nonce touches, so the front saving of 24 applies. Its whole eight-word output
    becomes the second block's message, so no tail saving applies to it.
  - The **second** block's message is the entire nonce-dependent first digest, so no front saving
    applies. Only `word[7]` is read by the anchor, so the tail saving of 27 applies to it.

  | | word-rounds |
  |---|---|
  | two blocks per nonce, eight words each | 1024 |
  | less the first block's shared front | 24 |
  | less the second block's narrow tail | 27 |
  | **smallest area a nonce must actually cross** | **973** |

  **5.0% per nonce, not 10%.** The miner currently takes neither saving: both calls go through the
  generic full-64-round `sha256_block_compress`, which rebuilds all 48 expanded schedule words each
  time, including W16 and W17 which no nonce affects. Word-rounds are still not instructions, so
  this bounds the arithmetic and not the runtime.

## 3. What We Do Not Know

Stated as gaps and not as conclusions, because several are cheap to close and one is not.

1. **The message schedule has never been measured on its own.** Every projection so far has been
   applied to the chaining value. The schedule is a different and weaker object: `σ0` and `σ1` are
   rotations, shifts and xors, which are *fully GF(2)-linear*. Only the three modular additions in
   `W[t] = σ1(W[t-2]) + W[t-7] + σ0(W[t-15]) + W[t-16]` leave that basis. Treated as a code over
   GF(2) with carry corrections, the expansion of 16 words to 64 is a linear map plus a bounded
   nonlinear perturbation. **This is the most structured object in SHA-256 and we have not touched
   it.**
2. **Exact DAG reachability, as opposed to the statistical light cone.** The propagation front was
   measured by sampling. The circuit is a fixed DAG, so reachability is *computable exactly*: after
   `r` rounds, which input bits can provably affect which output bits. Statistical measurement can
   only ever say "no effect observed"; the DAG says "no path exists." Those are different claims and
   only one of them is a constraint you can solve against.
3. **Rounds 5 through 9 in detail.** Every projection dies in this window and none has characterised
   its interior. The decay curve's shape there is unmeasured.
4. **The state as a torus and not as eight rows.** The Fourier and Walsh work transformed each
   32-bit row independently. The bit axis is genuinely cyclic under rotation, and the word axis is a
   shift register, so the natural object is a product space, not eight separate circles. A transform
   over that product has not been tried.
5. **Cycle structure of the round permutation.** For fixed `W[t]` the round is a permutation of a
   2^256 set. Permutations have cycle structure, fixed points, and order. None of this has been
   examined, at any round count, even on a reduced-width analogue.
6. **Full differential characteristics.** Per-bit difference bias was measured; the probability of a
   *specific complete output difference* given a specific input difference was not. That is the
   object real SHA-2 cryptanalysis works with.
7. **Reduced-width analogues.** Nothing has been tried on a SHA-256 variant with 8-bit or 16-bit
   words, where the full state is small enough to enumerate completely and structure can be seen
   directly and not sampled.
8. **Whether the seam at rounds 1-10 has internal structure across projections.** Six projections die
   in one window. Whether they die in the same *order* on the same *positions* is unmeasured, and
   would say whether there is one mechanism or six.

## 4. Every Angle Examined, With Verdicts

| # | angle | verdict | where it failed |
|---|---|---|---|
| H1 | corpus size vs `N·2^-k` | model holds exactly | nothing to exploit |
| H2 | entropy eddies, full digest | none above floor |  - |
| H3 | repeating curve, 20 lags | none | rotations do not survive composition |
| H4 | hitting time | geometric | memoryless, so no history predicts |
| H5 | boundary knows rotation | **exact, 1e-13** |  - |
| H6 | that knowledge survives rounds | dies at **round 1** | `Σ0` turns one ramp into three summed |
| H7 | diffusion depth | saturates round 10 |  - |
| H8 | Fourier spectral flatness | flat by round 8 |  - |
| H9 | mod is linear in the other module | **exact** |  - |
| H10 | carry bias | **exact, real structure** | local; halves per position |
| H11 | racing the two bases | both die round 9 | next op is linear in the other basis |
| H12 | Walsh-Hadamard | flat by round 8 | wrong basis for the additions |
| H13 | vector walk / hill climbing | walk 20.500 vs enumeration 20.375 | no landscape to climb |
| H14 | round is a bijection | **exact** | but see H15 |
| H15 | trackable quantities | fwd 3, bwd 0 | circularity |
| H16 | extranonce2 dimension | no landscape, 24.0x cost |  - |
| H17 | 1000 real solves | 1000/1000 | implementation correct |
| H18 | no noise floor, deep survey | floor to 3.05e-5 | nothing above it |
| H19 | keyhole scan, structured salts | one flagged, **closed on retest** | multiple comparisons |
| H20 | co-arm salt cascade | tail exact, **enrichment 1.0** | salt response ∉ `D` |

## 5. The Angle That Keeps Recurring, And Why It Fails

Five separate proposals in this programme reduce to the same shape, and it is worth naming so the
sixth is recognised on arrival:

> Find a cheap test `t(n)` correlated with `Occ(n)`, and use it to skip candidates.

H13 (walk), H19 (keyholes), H20 (co-arm salts) are all this. Each fails at the same joint, and §2.2
of `anchor-sift.md` names the joint exactly:

**An anchor is sound because `A ⊆ D`.** It is a condition *copied out of the pattern being searched
for*. That makes rejection exact and lossless. A test that is merely *correlated* with the
target - a salt response, a neighborhood score, a landscape gradient - is not a subconfiguration of
`D`, so Proposition 1 does not apply to it, and H20 measured the consequence directly: enrichment
1.0, winners discarded in exact proportion.

The only genuine `A ⊆ D` available here is *the target condition itself*: leading zero bits of the
digest. That is already the anchor the engine uses. It is sound, it costs a full hash to read, and
§2.5 prices it at exactly zero saving beyond the tail of the second compression.

**So G2 is not closed by argument, it is closed by definition of what is in `D`.** Reopening it
needs
a necessary condition on the digest readable without computing the digest. Nobody has one.

## 6. Where The Exponential Gains Came From, And Whether They Transfer

The gains in the anchor-sift programme came from domains where:

1. the corpus is **already in memory**. An anchor probe is one load against `needle_len` compares;
2. the domain is **skewed**, `H2` well under maximum. An informed measure beats an uninformed one
   by up to the measured factor of 6.4;
3. the pattern's structure **survives the transform**, because a rotation is a permutation of `D` and
   changes no term in either predicate.

Against the digest domain:

| condition | in a corpus | here |
|---|---|---|
| probe cost vs verify cost | 1 : needle_len | **1 : 1** |
| `H2` | well under 8 (skewed) | **7.999999** |
| structure survives transform | yes, rotation is a permutation of `D` | dies at round 1 |

All three conditions fail, and they fail for the same underlying reason: the domain was *engineered*
to make them fail. §2.4 of the paper calls maximum entropy the base case of the construction, the
case where an informed measure buys nothing because there is nothing to be informed about. The
digest
domain sits on that base case to six decimal places.

The transforms are not the thing that failed. The transforms are sound and H5 shows one working to
machine precision. What failed is that this domain is the paper's own worst case.

## 7. What Would Change The Conclusion

Any one of these, none observed:

- Enrichment rising with cascade depth in H20's last column.
- A per-bit bias surviving resampling at 10x the current 2^32.
- A projection whose structure survives past round 10.
- A lag correlation above 2e-4 anywhere.
- Exact DAG reachability showing output bits provably unreachable after many rounds.
- A message-schedule property that constrains the compression input.
- Hitting time departing from geometric.

## 8. Where The Published Literature Stands

Fetched 2026-09-08, so this tree's results can be placed against the field and not guessed at.
The relevant point for us: **every published result is on step-reduced SHA-256**, and the best of
them
stop well short of 64, let alone the 128 a Bitcoin header runs.

| result | reach | complexity | source |
|---|---|---|---|
| collision, practical | 28 steps | practical | Mendel, Nad, Schläffer, EUROCRYPT 2013 |
| collision | 31 steps | ≤ 2^65.5 | same |
| semi-free-start collision | 38 steps |  - | same |
| preimage | 41 steps |  - | Aoki et al. |
| **preimage, best known** | **52 steps** | **2^255** | Khovratovich et al., via bicliques |
| pseudo-collision | 52 steps |  - | via meet-in-the-middle plus bicliques |

Two things worth reading off this table.

First, the best preimage attack reaches 52 of 64 steps at complexity 2^255, against a brute-force
cost of 2^256. That is a factor of two. It is a genuine cryptanalytic result and it is of no
operational use whatsoever, the normal condition of results in this area.

Second, and more useful to us: the field's frontier is at **31 steps for practical collision work**,
and this tree measured every projection dying by **round 10**. Those numbers are consistent. The
automated differential-characteristic search that Mendel et al. built is the tool that pushes
from round 10 to round 31, and it is a large piece of dedicated machinery. The gap between where
hand-built projections die and where the best published work dies is about twenty rounds of tooling,
and
the gap from there to 128 is the security margin.

Sources: [Improving Local Collisions: New Attacks on Reduced
SHA-256](https://eprint.iacr.org/2015/350.pdf) · [Preimage Attacks on 41-Step SHA-256 and 46-Step
SHA-512](https://eprint.iacr.org/2009/479.pdf) · [Converting Meet-in-the-Middle Preimage Attack into
Pseudo Collision Attack](https://www.iacr.org/archive/fse2012/75490268/75490268.pdf) · [Quantum
Collision Attacks on Reduced SHA-256 and SHA-512](https://eprint.iacr.org/2021/292.pdf) · [Security
Evaluation of SHA-224, SHA-512/224, and
SHA-512/256](https://www.cryptrec.go.jp/exreport/cryptrec-ex-2401-2014.pdf) · [SHA-256 Limited
Statistical Analysis](http://www.femto-second.com/papers/SHA256LimitedStatisticalAnalysis.pdf)

## 9. Recommended Order Of Attack

Ordered by information gained per hour, given everything above:

1. **Exact DAG reachability** (§3.2). Cheap, exact instead of statistical, and it either finds a
   provable constraint or converts a statistical claim into a proof. Highest value per effort.
2. **The message schedule alone** (§3.1). The most structured object in the function and entirely
   unexamined here. `σ0`/`σ1` are GF(2)-linear; only three additions per word are not.
3. **Reduced-width analogue** (§3.7). An 8-bit-word SHA-256 has a small enough state to enumerate
   completely, turning every sampled measurement in this document into an exact one.
4. **Rounds 5-9 interior** (§3.3). Where all six projections die. Map the decay instead of the
   endpoints.
5. **Cycle structure of the round permutation** (§3.5). Genuinely topological, genuinely unexamined.
6. Torus transform (§3.4), full differentials (§3.6), cross-projection seam structure (§3.8).

## 10. Honest Statement Of Where This Stands

Twenty hypotheses. Three supported exactly, and one of those - the carry bias - is a real structural
finding. Every other supported result is a property of the *mechanism* instead of of the *output*,
and the mechanism's transparency does not convert into a solution because the obstruction is
circularity instead of opacity.

The remaining eight gaps in §3 are real gaps and several are cheap. They are worth closing on their
own terms, and closing them would make several claims here proofs instead of bounds. What they are
unlikely to do is change the engineering answer, because the engineering answer does not rest on
them: it rests on §5, a statement about what belongs to `D`, and no measurement changes what
is in a set.

The distinction worth holding onto: **this document is not evidence that no structure exists. It is
a record of twenty places it was looked for, with the sensitivity of each search stated.** Those are
different claims, and only the second one has been earned.

And "with the sensitivity of each search stated" is the load-bearing clause, so it has to be true of
every row rather than most of them. H13 - the nonce landscape - did not meet it. Its null was drawn
and its head-to-head was fair, but both of its arms read the digest through `fitness()`, the count
of leading zero bits, and nothing in the bench established what size of gradient that readout could
still have missed. An unbounded null was being quoted as though it excluded everything.

`bench_walk.cpp` §5 now fixes that floor by injection rather than by argument. A known smooth
gradient is added to the score - `alpha * set_bits(nonce)`, which moves by exactly one per single-bit
step, so alpha is the gradient in the same units the readout carries - and faded until §1's own
statistic loses it. Measured, with the unrelated-nonce control held beside it at every rung:

| alpha, bits per single-bit step | flip correlation | z | control z | |
|---|---|---|---|---|
| 0.125 | 0.054942 | 24.57 | 0.09 | seen |
| **0.0625** | **0.013947** | **6.24** | **0.15** | **seen, and this is the floor** |
| 0.03125 | 0.003023 | 1.35 | 0.18 | lost |
| 0 (the real bench) | -0.000777 | -0.35 | 0.21 | lost |

So the earned claim is: **no gradient of 0.0625 leading-zero bits per single-bit step or stronger.**
Not "the landscape is flat", and not "every ordering strategy is retired". Below that floor, and for
any structure that does not reach the leading-zero count at all, these arms are silent and their
silence is not evidence.

For mining the narrower claim is still the whole answer, because the target test IS the leading-zero
count - a landscape invisible to this readout cannot lower the cost of finding a block. The
engineering conclusion is untouched. The general one was overstated and is now bounded.
