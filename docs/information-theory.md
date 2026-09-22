# Information theory on the plane

What the literature on information-theoretic cryptanalysis says, arranged against what this tree
has already measured, and the one axis that arrangement turns out to expose.

The short version: thirty-one hypotheses were graded on collision entropy, which is Rényi order
two. Order is a continuous axis running from zero to infinity, each point of it answering a
different question about the same distribution, and it has never been varied. Order two was not
chosen. It is what a collision counter measures and a collision counter was what was to hand.

---

## 1. What was fetched

### 1.1 Guessing is governed by order one half, not order two

Arikan's inequality, as restated in Ranjan and Sundaresan's survey (eprint 2018/455, Theorem 1):

> The expected number of guesses, for a user with the optimal guessing sequence, `E[G]` obeys
> the upper bound
>
>     E[G] <= (1/2) [ sum_k sqrt(p_k) ]^2 + 1/2  =  (2^{H_{1/2}(X)} + 1) / 2

with the Rényi entropy of order alpha

    H_alpha(X) = (1 / (1 - alpha)) log sum_x P(x)^alpha

and, from the same page, the property that matters:

> `H_alpha` is strictly decreasing in alpha unless the distribution is uniform on its support.

Massey's earlier bound is in Shannon entropy and is the reason the field talks about
Shannon at all here. Arikan's is sharper and names a *different order*: the quantity that governs
the cost of searching is `H_{1/2}`, whose defining sum is `sum sqrt(p)`. That sum is dominated by
the many small probabilities, not by the few large ones. **Search cost is a tail statistic.**

### 1.2 Collisions are governed by order two. Balance is that

Bellare and Kohno, *Hash Function Balance and its Impact on Birthday Attacks* (EUROCRYPT 2004,
full version eprint 2003/065), Definition 5.1:

> For `i` in `[r]` let `d_i = |h^{-1}(R_i)|` denote the size of the pre-image of `R_i` under `h`.
> The balance of `h`, denoted `mu(h)`, is defined as
>
>     mu(h) = log_r [ d^2 / (d_1^2 + ... + d_r^2) ]

and, immediately after,

> `1 / r^{mu(h)} = (d_1^2 + ... + d_r^2) / d^2` is the probability that `h(a) = h(b)` if `a, b` are
> drawn independently at random from the domain `D`.

Proposition 5.2 gives `0 <= mu(h) <= 1`, zero exactly for a constant function and one exactly for
a regular one. Corollary 6.4 gives the birthday cost as `Q_h(c) <= 1 + 2.36 sqrt(2c) r^{mu(h)/2}`.

Balance is collision entropy rescaled: `mu(h) = H_2 / log_2 r`. It is our `H2` in a different
coordinate, and it answers the collision question, which is not the search question.

### 1.3 Distinguishing cost is a divergence

Baignères, Junod and Vaudenay (ASIACRYPT 2004) and Baignères and Vaudenay (2008) put the shape of
an optimal distinguisher on a hypothesis-testing footing: the optimal statistic is the log
likelihood ratio, and the number of samples needed to separate `P` from uniform scales as the
reciprocal of a divergence between them - Kullback-Leibler, with Chernoff information as the exact
exponent and squared Euclidean distance as the usable approximation.

The chi-squared method (eprint 2017/537) gives the crisp form:

    Delta(P, Q) <= sqrt( (1/2) chi^2(P || Q) ) advantage over n samples <= sqrt( n chi^2 / 2 )

This is the principled replacement for the sigma counts this workbook has been reporting. A sigma
count says how surprising one statistic is. A divergence says how many samples any distinguisher
whatsoever would need, the number that decides whether a structure is worth anything.

### 1.4 Iterated functions lose entropy in a known amount

Flajolet and Odlyzko, *Random Mapping Statistics* (EUROCRYPT 1989), analyze about twenty parameters
of a uniformly random map on `n` points. The ones that bite here: the image is `(1 - 1/e) n`. A
random function leaves `1/e = 36.79%` of its range unreachable in one step; the giant component is
`0.75788 n`; rho and tail lengths go as `sqrt(pi n / 8)`.

"Iteration entropy" (arXiv 1712.01407) carries this to repeated application and to Rényi and
min-entropy instead of Shannon alone.

The holes are not a defect. **A random function is supposed to have them, and it is supposed to
have exactly `1/e` of them.**

---

## 2. The arrangement: order is the axis

Every result above is a statement about the same object - the output distribution - read at a
different Rényi order. Written out, the axis is:

| order | reads | what it answers | who |
|---|---|---|---|
| `alpha = 0` | size of the support | how many values never occur - **the holes** | Flajolet–Odlyzko |
| `alpha = 1/2` | `sum sqrt(p)` | cost of guessing - **the search** | Arikan |
| `alpha = 1` | Shannon | information content | Massey |
| `alpha = 2` | collision probability | cost of colliding - **balance** | Bellare–Kohno |
| `alpha = inf` | largest single probability | **the biggest bump** | min-entropy |

Holes at one end, bumps at the other, guessing and collisions at two interior points. The plane is
one plane; the order is the angle it is viewed from. This tree has looked at it from one angle.

### 2.1 What a flat plane predicts along that axis

Write the bin counts as `c_i = m (1 + e_i)` with `m = d/r` the exact mean. For a random function the
`e_i` are small and the deficit `log_2 r - H_alpha` expands to

    deficit(alpha) = alpha * var(e) / (2 ln 2)        with  var(e) = (r - 1) / d  exactly

The deficit profile of a random function is **a straight line through the origin in alpha**. That
gives a test with no free parameter at all:

    deficit(2) / deficit(1/2) = 4    exactly

Every scale - domain size, bin count, window position, how many samples were taken - cancels out of
a ratio between two orders. Curvature in that line, or a ratio away from four, is structure that
cannot be explained away by the size of the experiment.

Where the mean count falls to one the expansion stops applying and the counts go Poisson, whose
moments about a unit mean are the Bell numbers `1, 2, 5, 15`. Both regimes are real here: a 32-bit
window read over a `2^32` domain is the Poisson case, and it is the only place a bin can
be empty. That is where the holes live.

---

## 3. What this says about work already in the workbook

### 3.1 Every advantage quoted from an `H2` measurement overstates the search advantage

`H_alpha` is decreasing in alpha, so `H_{1/2} >= H_2`, so

    deficit(1/2) <= deficit(2)

and for anything near flat the first is about **a quarter** of the second. Every figure in this
workbook of the form "collision entropy is `X` bits below uniform, so there are `X` bits of
advantage" is therefore an answer to the collision question being read as an answer to the search
question, and it is the more generous of the two.

The concrete case: H22's rotational coherence measured `H2 = 16.503` against a uniform `32`, a
deficit of `15.497` bits, with a permuted control at `32.069`. That deficit is real and the control
is sound. What it does not say is that `15.497` bits of search advantage exist, because search is
governed by order one half. The honest statement is `deficit(1/2) <= 15.497`, and the actual value
needs the same histogram re-read at order one half. **That re-read is cheap and has not been done.**

This is not a small correction of presentation. It is the difference between the quantity that was
measured and the quantity the project is about.

### 3.2 Bellare and Kohno's own SHA-1 numbers have an unsubtracted null

Section 11 of their full version computes the balance of SHA-1 restricted to a `2^32` domain, at
byte-aligned output windows of 8, 16 and 24 bits, and reports the values are high. Subtracting the
random-function null instead of eyeballing the values:

| window | their measured deficit | random function predicts | ratio |
|---|---|---|---|
| 8 bits | `1.0462e-08` | `1.0707e-08` | 0.9771 |
| 16 bits | `1.3770e-06` | `1.3758e-06` | 1.0009 |
| 24 bits | `2.34378e-04` | `2.34356e-04` | 1.0001 |

Their own resolution at width 8 is `sqrt(2/255) = 8.8%`, so 0.977 is centred. **The whole of SHA-1's
measured imbalance is the imbalance any function drawn at random would show, to four significant
figures.** The paper says the balance is high. The sharper statement available from the same table
is that the deficit is exactly generic, and that is a much stronger claim about SHA-1 than "high".

It is also the methodological point this tree keeps relearning: the interesting quantity is never
the measurement, it is the measurement divided by what a random function would have given.

### 3.3 Sigma counts should be divergences

Defect ten in the workbook - comparing a max-statistic against a per-bin uniform and getting
775,000x where the Sigma-delta null gives 184.5x - is the same error the distinguishing literature
solved in 2004. A divergence is the right currency because it converts directly into the number of
samples any distinguisher would need, the only thing that decides whether a structure is
exploitable. This is not yet done and it is the largest unresolved methodological debt.

---

## 4. The compiler audit

Raised mid-session, and correct: a compiler folds, contracts, reassociates and hoists, and a folded
measurement is indistinguishable by eye from a computed one. `bench_engines` already caught an
entire engine that was a constant function; nothing structural stops the same happening to a
statistic. Results that depend on the optimiser are not results.

Two arms, both mechanical:

**Differential.** `tools/audit/audit_compiler.ps1` builds every bench three ways - `-O0`, `-O2`, and `-O2
-ffp-contract=off` - and runs all three. `-O0` folds nothing, hoists nothing and contracts nothing,
. A bench whose three outputs are byte-identical computed its numbers instead of inheriting them.
GCC contracts multiply-add into FMA by default, which changes rounding, so the third arm separates
that from folding proper.

**Constant pool.** `tools/audit/audit_constants.py` reads every double in a binary's read-only data and
reports which of the numbers the bench printed were already sitting there before it ran.

Neither arm proves a folded constant was folded *correctly*, a third failure mode. For
`bench_renyi` that is closed separately: `tools/audit/verify_renyi.py` reimplements every prediction the
binary prints, in another language against another libm, and compares at the printed precision.

---

## 5. What the anchor-sift posits say about all of this

Four posits in `anchor_sift/examples/proofs/posits` are proved and not asserted, each on
constructed domains where the answer is known by design instead of inferred from the case that
suggested it. Three of them bear directly here and one of them reframes this entire document.

### 5.1 Histogram quantities are free, and everything above is a histogram quantity

From the ledger:

> Histogram quantities are permutation invariant, so they describe the maximum entropy case and are
> free. The arrangement is what remains after that.

**Every number `bench_renyi` produces is a histogram quantity.** All seven Rényi orders, the
Bellare–Kohno balance, the count of holes, the Arikan guessing factor - each is a function of the
multiset of bin counts and of nothing else. Shuffling which value carries which count leaves every
one of them exactly unchanged.

So the headline result - that SHA256d's output histogram over an completely enumerated `2^32`
nonce domain is that of a random function to six significant figures - is, in the ledger's own
terms, **entailed instead of discovered**. It is the maximum-entropy case, and it was always going
to be the answer. That is worth having as a measured fact instead of an assumption, but it is not a
finding about SHA-256's arrangement, because no permutation-invariant quantity can be.

The arrangement is what remains, and it is where anything would have to live. `bench_renyi` now runs
the Walsh spectrum of the hole indicator against a splitmix control, the first arrangement
statistic in this tree.

### 5.2 The null must delete the property being asked about

Proved in `proof_null_property.py` on four constructed clouds - lattice or scatter crossed with
patterned or random values - where a value-permuting null can only reveal order in the values and a
position-moving null can only reveal order in the geometry, so the predicted hits fall on a diagonal
and anything off it refutes the posit.

The permutation null over arrangements of a fixed multiset satisfies this exactly for the question
asked here: it preserves every count and destroys every position, so it deletes the arrangement and
keeps the
counts. The ledger's reason it cannot be wrong is worth quoting because it is stronger than
"we chose a sensible baseline":

> Drawing uniformly from the arrangements of a fixed multiset is the least committal distribution
> consistent with the observed histogram, so it asserts nothing beyond the quantity already measured.
> Every other background in this work is a model and can be false. This one is the data with one
> property deleted.

### 5.3 A quantity that fails to conserve indicates the instrument

`proof_conservation.py` states what a measure must be invariant to and checks each, instead of
inferring the rule from the case that suggested it. Written out for the deficit measured here:

| transformation | required |
|---|---|
| relabel the window values by any fixed bijection | **exactly** invariant, the histogram is unchanged |
| reverse or permute the order of nonce enumeration | **exactly** invariant, counts do not see order |
| split the domain and recombine the counts | **exactly** invariant |
| read a different window position | invariant within the stated spread |
| **run on a different block header** | invariant within the stated spread - **never checked** |

The last row is the gap. Every measurement in this tree is on block 125552's header. One header is
one corpus, and the homogeneity check that posit demands has not been run. It is the same shape as
failure mode 14 applied to the header and not to the seed.

The posit's other half is sharper still, and this document has the same debt:

> the spread over seeds is the floor below which no difference between two corpora means anything.
> That floor has been used all through this work and never measured.

Here the ratios `1.00967` for SHA and `0.98900` for splitmix differ by about 2% at the byte windows,
against an analytic per-family floor of `sqrt(2/(r-1))/sqrt(windows)` = 1.57%. That comparison is
sound only because the floor is derivable exactly for a multinomial. Where a floor is not derivable
it has to be measured by reseeding, and that has not been done anywhere in this tree.

### 5.4 The symbol width has to match the scale of the structure

`proof_symbol_width.py` builds a domain whose structure sits at one width and no other, and sweeps
**both the width and the phase**, because a detector is not told where the units begin and a slice
of
the right width at the wrong offset splits every unit across two symbols.

Every window in `bench_renyi` is byte-aligned: 8 bits at 32 positions, 16 at 16, 32 at 2. **The
phase
has never been swept.** Structure living at an offset of one to seven bits would be split across two
symbols at every window read here and would be invisible to all of it. That is a cheap gap to close
and it is not closed.

### 5.5 The content has to be printed, not only the statistic

`proof_corpus_audit.py` records that nine problems in that work were found by reading output and
none
by a statistic going out of range. This tree prints statistics almost exclusively. The exception is
recent and it earned its keep immediately: extending the leading-zero table past 44 bits showed that
the single deep nonce is block 125552's own solved nonce, rediscovered by the enumeration, the
strongest external check available here and had been sitting one row below the cut.

## 5.6 The cost term is the finding

Widening the search for structure in the hole arrangement, one step at a time:

| what was checked | how many directions | what it cost | what it found |
|---|---|---|---|
| single-bit flips of the count field | 32 | one pass over 4 GB, seconds | nothing, max 2.28σ |
| every mask inside any two bytes | 393,210 | byte-pair histograms and six small transforms, seconds | nothing, max 5.03σ against a control at 4.82 |
| **every mask there is** | **4,294,967,295** | **16 GB and 1.4e11 butterflies, minutes** | nothing, max 6.79σ against an expected 6.24 |

Each step multiplies the cost by orders of magnitude and returns the same answer. That pattern is
not an accident of this particular search, and the ledger already names why:

> Histogram quantities are permutation invariant, so they describe the maximum entropy case and are
> free. The arrangement is what remains after that, and Proposition 2 states that no knowledge of a
> domain removes the exact compare, so the cost of an arrangement is made of checks that have to be
> performed. Deriving it would be obtaining the irreducible half without paying for it, the
> thing Proposition 2 denies.

The free half was free: SHA256d's output histogram matches a random function's to six significant
figures and was always going to. The other half is made of checks, and the number of checks scales
with the space being checked. Testing every linear direction over `2^32` values costs `n log n`;
testing every quadratic one costs more; the set of structures that could exist is larger than the
space itself by an amount no budget closes.

**This is the same asymmetry that makes mining work, arriving from the other side.** Knowing the
function completely - which we do, it is in `sha256_core.c` - removes none of the checks. That is
worth stating plainly because it is the answer to "we know the hash, we know what they did to it":
knowing the transform does not reduce the count of things that have to be verified, and the count is
the cost.

### 5.7 The knee, and where it sits

The cost does not merely grow. It floors, with a knee, and the position of the knee is derivable
instead of a matter of opinion.

Checking `N` directions means taking a maximum over `N` statistics, so the threshold a real signal
has to clear is the expected largest of `N` nulls:

    reach   R(N) = sqrt(2 ln N)  minus a slowly varying correction
    cost    C(N) ~ N log N in time and N in memory

Inverting the first and substituting:

    N = exp(R^2 / 2)        so        C ~ exp(R^2 / 2) * (R^2 / 2)

**The cost is exponential in the square of the reach.** That is the knee, and it is savage:

| reach wanted | directions needed | relative to what was just run |
|---|---|---|
| 4.57σ | 393,210 | 1/10,900 |
| **6.24σ** | **4.29e9** | **1, and it cost 16 GB and minutes** |
| 8σ | ~4.3e15 | ~1,000,000x, about 17 petabytes |
| 10σ | ~7.7e23 | not on this planet |

Going from every two-byte mask to every mask was 10,900 times the work and bought **1.67σ**. The
next
1.67σ costs about a million times more than that, and the one after costs ten billion times more
again. The complete-direction approach floors at about 7σ for any budget that exists.

**The knee is already behind us, and the way past it is not more directions.** More directions is
the move whose price is exponential in the square of what it buys. Getting further needs a
statistic where a signal, if there is one, is concentrated in a few places known in advance instead
of
 spread across billions of equally plausible ones - which is a statement about having a
hypothesis, not about having a bigger machine.

## 6. Still unknown

- ~~**The phase sweep.**~~ Run, H36. Eight phases, sixteen-bit family reads a spread ratio of 0.997
  against its control. No alignment dependence.
- **A second header.** One block's header is one corpus. Nothing here has been asked to conserve
  across a different one, the homogeneity check posit 5.3 demands. One hypothesis, cheap
  now that the enumeration is on the device.
- **A reduced-width analogue.** An 8-bit-word SHA-256 has a state small enough to enumerate
  completely. That is the axis where speed still converges the representation, because it replaces
  every sampled result in this workbook with an exact one instead of buying another `sqrt(2 ln N)`
  of reach against an exponential price. It is the only open item that is a better object instead of
   a bigger search.
- **The order one half re-read of every histogram already collected.** Cheap, and it changes what
  the existing advantage figures mean.
- **Divergences in place of sigma counts**, throughout.
- **The functional graph proper.** Image size, rho and tail lengths, component structure of the
  compression function as a map on a restricted domain, against Flajolet–Odlyzko's constants.
- **Whether the deficit line stays straight at reduced rounds.** Round eight is where closeness
  dies; the order axis has never been swept at a partial round, and a curvature that appears and
  then flattens would locate the mixing in a coordinate nothing here uses.

---

## Sources

- E. Arikan, *An Inequality on Guessing and Its Application to Sequential Decoding*, IEEE Trans.
  Inf. Theory 42(1):99–105, 1996. Restated with the constants in
  [eprint 2018/455](https://eprint.iacr.org/2018/455.pdf).
- J. Massey, *Guessing and Entropy*, ISIT 1994.
  [ETH archive](https://www.isiweb.ee.ethz.ch/archive/massey_pub/pdf/BI633.pdf)
- M. Bellare and T. Kohno, *Hash Function Balance and its Impact on Birthday Attacks*, EUROCRYPT
  2004. [eprint 2003/065](https://eprint.iacr.org/2003/065),
  [full version](https://homes.cs.washington.edu/~yoshi/papers/Hash/balance.pdf)
- T. Baignères and S. Vaudenay, *The Complexity of Distinguishing Distributions*, ICITS 2008.
  [Springer](https://link.springer.com/chapter/10.1007/978-3-540-85093-9_20)
- W. Dai, V. T. Hoang, S. Tessaro, *Information-theoretic Indistinguishability via the Chi-squared
  Method*. [eprint 2017/537](https://eprint.iacr.org/2017/537.pdf)
- P. Flajolet and A. Odlyzko, *Random Mapping Statistics*, EUROCRYPT 1989.
  [Springer](https://link.springer.com/chapter/10.1007/3-540-46885-4_34)
- *Iteration Entropy*. [arXiv 1712.01407](https://arxiv.org/pdf/1712.01407)
- D. Malone and W. Sullivan, *Guesswork is not a Substitute for Entropy*, ITT 2005.
  [TCD](https://www.maths.tcd.ie/~dwmalone/p/itt05.pdf)
