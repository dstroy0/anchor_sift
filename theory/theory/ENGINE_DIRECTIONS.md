# Directions the engine's own proofs already license

**Purpose:** Collect the capabilities that follow from what the engine has already proved, and the Laplacian construction that replaces its planning cost with a determinant.
**Scope:** `src/engine/c/portable/anchor_steer.h`, `src/engine/c/portable/anchor_steer.c`, `src/engine/c/portable/anchor_sift.h`, `docs/steering.md`

## Contents

1. [What is already proved](#what-is-already-proved)
2. [It can search a corpus it cannot read](#it-can-search-a-corpus-it-cannot-read)
3. [It can search for a pattern nobody wrote down](#it-can-search-for-a-pattern-nobody-wrote-down)
4. [It is correct on hardware that computes wrong](#it-is-correct-on-hardware-that-computes-wrong)
5. [Its own cost is the arrangement measurement](#its-own-cost-is-the-arrangement-measurement)
6. [The census matrix is a Gram matrix](#the-census-matrix-is-a-gram-matrix)
7. [Probe selection is a determinantal point process](#probe-selection-is-a-determinantal-point-process)
8. [The destroy rule is a rank test](#the-destroy-rule-is-a-rank-test)
9. [Planning without touching the corpus](#planning-without-touching-the-corpus)
10. [What each of these would cost to be wrong](#what-each-of-these-would-cost-to-be-wrong)
11. [Sources](#sources)

## What is already proved

Three results carry everything below. All three are established, and none is proposed.

Every probe is a necessary condition of an occurrence, any conjunction of probes loses no true
occurrence and the full compare removes the false survivors. The count is exact for any probe set.

The sift is therefore a sound filter and its errors are one directional. A discrepancy is always an
over-count and is detectable without knowing the answer (`README.md:97`).

A probe's agreement at shift `d` from a true occurrence is exactly a lag `d` self-agreement event in
the corpus. Writing `A(d)` for the fraction of positions where the corpus agrees with itself at lag
`d`, the probability a probe fails to refute a wrong alignment at shift `d` is `A(d)`.

## It can search a corpus it cannot read

A probe compares `corpus[at + offset]` against `needle[offset]` and uses the result of an equality.
It never reads a value for any other purpose, never orders two symbols, and never indexes a table by
one.

So let `f` be any injective function on the alphabet. Applying `f` to every byte of both the corpus
and the needle preserves every equality and reverses none, so every probe returns what it returned
before, every survivor set is identical, and the count is unchanged. Take `f` to be a keyed
pseudorandom permutation and the engine counts occurrences in a corpus nobody running it can read,
for a needle nobody running it can read.

This is a capability the alphabet claim already bought. `README.md:99` states that nothing is
indexed and no table is built over the alphabet, and that a real-valued or unenumerable alphabet
costs nothing. An engine that never enumerates symbols cannot notice that the symbols were replaced.

**What it leaks is known exactly, and that is the unusual part.** Two positions carrying the same
byte still carry the same byte after `f`. The encoding hides values and preserves the equality
pattern, an observer learns the partition of positions into equal classes and nothing finer. That
partition is the quantity `A(d)` measures. The leak of this construction is the statistic section 5
uses as a signal, so the engine can compute and report its own exposure.

## It can search for a pattern nobody wrote down

Nothing in the necessary-condition argument requires one side of a probe to be the needle. It
requires that an occurrence satisfy the probe.

Put both ends in the corpus. A probe testing `corpus[at + o1] == corpus[at + o2]` asks whether the
window at `at` carries the same symbol at two of its own positions. A set of such probes specifies a
pattern by its internal equalities alone: which positions must agree, with no statement about what
they must agree on. Any window matching that partition satisfies every probe, so the filter stays
sound and the count stays exact under the same argument.

The search target becomes a shape. `abcabc` and `xyzxyz` satisfy the same equality pattern, and so
does any string of that form over any alphabet. This is the parameterized matching problem, and the
engine reaches it without new machinery because its primitive was equality all along.

What that finds: repeated structure with substitution, source code duplicated with the identifiers
renamed, tandem repeats in a sequence, the internal structure of a cipher's output. The verifier
changes, since a full compare against a needle is the wrong final test when there is no needle, and
the replacement is a direct check of the partition on the surviving windows.

## It is correct on hardware that computes wrong

Any probe may be replaced by a weaker necessary condition without endangering the count. The weakest
available is the probe that always agrees, and a plan of those is the empty plan, which sends every
alignment to the full compare and returns the exact answer at maximum cost.

A probe implementation whose errors run only toward agreement is therefore sound. A comparator that returns
agreement when it is uncertain, a memory that occasionally reads a stale byte in the direction of a
match, a voltage-starved ALU biased that way: each costs full compares and none costs an occurrence.
The requirement is a biased failure mode. Reliability is never needed, and a comparator can be built
to fail in the safe direction deliberately.

The converse is the thing to guard. An error toward disagreement drops a true occurrence silently,
the single failure this engine does not otherwise have. The design rule follows: every component of a
probe must be auditable for the DIRECTION of its errors, and the sound filter argument survives
unreliability in that one direction alone.

## Its own cost is the arrangement measurement

`README.md:105` records an open problem. Collision entropy is permutation invariant and cannot see an
arrangement, and a period-16 counter therefore reads 4.0 bits while the dispatcher calls a perfectly structured
corpus memoryless. The note states that fixing it needs a quantity that reads arrangement and that no
threshold on collision entropy reaches it.

The engine already measures that quantity and reports it in another column.

A short-circuiting conjunction of `k` probes, each agreeing on a wrong alignment with probability
`q`, reads `(1 - q^k) / (1 - q)` bytes per alignment in expectation. The bench prints reads per
alignment. Inverting the expression recovers `q` from a number already on the page.

Now take the prediction. Under a memoryless source the agreement probability is the collision
probability, `q = 2^-H2`, computed from the histogram the dispatcher already builds. So there are two
estimates of one quantity: one predicted from the histogram, one measured from the clock. The
histogram is permutation invariant and the measurement is not, because the measurement is an average
of `A(d)` over the shifts the search actually visits.

**The gap between predicted `q` and measured `q` is arrangement information, and it is the quantity
`README.md:105` says is needed.** A permuted corpus has an identical histogram and a different
measured `q`. The period-16 counter reads `2^-4` predicted and close to 1 measured, the largest gap
the statistic can show.

It costs nothing. Both numbers are already collected, and the second one is the reads column of a
table that is currently read as a performance result.

## The census matrix is a Gram matrix

This section changes the planner, and it starts with a fact that has to be checked instead of
assumed.

Write each corpus position as a one-hot vector over the alphabet, so `x_i` has a single 1 in the
coordinate for `corpus[i]`. Then `corpus[i] == corpus[j]` exactly when the inner product of `x_i` and
`x_j` is 1, and it is 0 otherwise. So

```
A(d) = (1/n) * sum over i of <x_i, x_{i+d}>
```

which makes `A` an autocorrelation of a vector-valued sequence. A function of that form is positive
semidefinite, so for any offsets `o_1 ... o_k` the matrix `M` with `M_ij = A(o_i - o_j)` is positive
semidefinite. It is a Gram matrix, and its entries are counts over a shared denominator.

Write `C` for the same matrix before dividing, so `C_ij` counts the positions where the corpus agrees
with itself at lag `o_i - o_j`. `C` is an integer matrix.

## Probe selection is a determinantal point process

A determinantal point process assigns a subset `S` probability proportional to `det(M_S)`, and it is
the standard construction for selecting a set whose elements are not redundant with each other.
Determinantal processes discourage redundant elements and favor spread-out, repulsive selections,
which is a restatement of what a probe set is supposed to be.

Under the Gram matrix above, `det(M_S)` is the squared volume spanned by the probe positions' corpus
embeddings. It is zero when they are linearly dependent, the fully redundant case, and
largest when they are as independent as the field allows. So:

**Choosing the probe set that maximizes `det(C_S)` is choosing the least redundant set, and it is the
mode of a determinantal point process whose kernel the census already contains.**

Two classical facts make this more than an analogy. The marginal gain from adding a probe `p` to a
set `S` is `det(C_{S+p}) / det(C_S)`, the Schur complement of `p` against `S`, known in statistics as
the leverage score and in the graph Laplacian setting as the effective resistance. Sampling by effective
resistance is exactly how spectral sparsification builds a small subgraph preserving every cut of the
original within a factor, and every undirected graph admits such a sparsifier with a near-linear
number of edges. A greedy descent that scores candidates by determinant is running the sparsification
rule, and the approximation guarantees of that literature attach to it.

**And the arithmetic is integer.** `C` is a matrix of counts. Its determinant is an integer, computed
exactly by fraction-free Gaussian elimination in the tree's own limb arithmetic, with no float
anywhere. The tree's ban on computing libraries does not bite here, because the construction was
never floating point to begin with.

This also subsumes the Sidon set proposal. A Sidon set maximizes the distinctness of pairwise
differences, which is a combinatorial proxy for spreading the probes across lags. The determinant is
the same objective measured against the actual field instead of assumed, and it answers with the
field's own counts.

## The destroy rule is a rank test

The destroy rule fires when the best candidate leaves the truthy population exactly as it found it.
In the determinant picture, a probe that prunes nothing contributes no volume, so the determinant
does not grow and the marginal `det(C_{S+p}) / det(C_S)` is at its floor. The rule is a rank
deficiency test, and the determinant is its quantitative form: the rule reports a Boolean, and the
determinant reports how far from redundant each candidate is.

**The two are not identical and the difference must be stated.** Pruning nothing is a logical
implication, that every alignment surviving `S` also survives `p`. Contributing no volume is a linear
dependence. Linear dependence relaxes the Boolean condition instead of matching it, and a
determinant can therefore be positive where the destroy rule still fires. The determinant is a
surrogate, it is computable in closed form, and the destroy rule remains the exact test.

That is the right division of labor. The determinant predicts redundancy before paying for it, the
destroy rule catches what the prediction missed, and the gap between them is measurable.

## Planning without touching the corpus

The guide records that planning cost is stated and unmeasured, and that `anchor_steer_sweep_probes`
performs about `wanted * needle_len^2 * max_length^2 * alignments / sample_stride` byte comparisons
at worst, which exceeds the scan it plans for on any but a short needle. That is the engine's
sharpest open cost problem, and the determinant removes its dominant factor.

Scoring a candidate today walks the alignments. Scoring a candidate by determinant walks a `k` by `k`
integer matrix, where `k` is at most `ANCHOR_STEER_ANCHORS`, which is 4. The corpus is touched once,
by the census that collects `C`, and never again during planning.

| | corpus touched during planning | per-candidate cost |
|---|---|---|
| survivor scoring, today | once per candidate | alignments / sample_stride |
| determinant scoring | never | a 4 by 4 integer determinant |

The census pass that collects `A(d)` for the needed lags is one pass over the corpus, the same order
as a single scan. Everything after it is arithmetic on counts.

**The falsifiable claim, stated so it can fail.** A probe set chosen by determinant reads no more
bytes per alignment than the set chosen by survivor scoring, on the same field, while costing a
planning pass that does not scale with the alignment count. If the determinant set reads measurably
more, then the linear relaxation is losing what the Boolean test keeps, and the result is that
survivor scoring carries information the Gram matrix does not. That outcome is worth as much as the
other one and costs one bench.

## What each of these would cost to be wrong

No section above changes the count, because no section alters what a probe is. The
encoding section applies a bijection to both sides, the pattern section replaces the needle with a
partition and replaces the verifier to match, the hardware section weakens probes in the sound
direction, and the three Laplacian sections change only which probes get chosen. Every one of them
sits inside the necessary-condition family, so the worst outcome available to any of them is a slower
search.

Two of them could be wrong as CLAIMS instead of as code, section 5 and section 9. Section 5
asserts that the gap between predicted and measured agreement reads arrangement, which fails if the
measured reads column is dominated by something other than agreement probability. Section 9 asserts
the determinant is a useful surrogate, which fails if the relaxation discards what the planner needs.
Both are one bench each, and both were written to be checkable instead of agreeable.

## Sources

Nothing in sections 6 through 9 originates here. Read state: every entry is cited from knowledge and
from the search results listed, with no paper read in full for this document. Bibliographic fields
were checked against those results, and theorem numbers deliberately are not given.

**Gustav Kirchhoff**, 1847, for the matrix-tree theorem: the number of spanning trees of a graph is a
cofactor of its Laplacian. A determinant counts the structures, and that is the oldest instance of
the move section 7 makes.
<https://people.orie.cornell.edu/dpw/orie6334/Fall2016/lecture13.pdf>

**Odile Macchi**, *The Coincidence Approach to Stochastic Point Processes*, 1975. Determinantal point
processes, introduced to model fermions in optical beams. The determinantal process is the repulsive
one and the permanental process is the attractive one, and repulsion is the property section 7 wants:
a determinantal process discourages redundant elements by construction instead of by a rule added
afterwards.

**Daniel A. Spielman and Nikhil Srivastava**, on sampling edges by effective resistance, and
**Joshua Batson, Daniel A. Spielman and Nikhil Srivastava**, on sparse sums of positive semidefinite
matrices. Every undirected graph admits a sparsifier preserving every cut within a multiplicative
factor, with a near-linear number of edges. The greedy determinant scoring of section 9 is that
sampling rule, and their guarantees are what a scored descent would inherit.
<https://arxiv.org/pdf/0808.4134>, <https://arxiv.org/pdf/1107.0088>

**Salomon Bochner**, for the theorem that a positive definite function is the transform of a positive
measure. That is the general form of the fact section 6 establishes directly: an autocorrelation is
positive semidefinite, so the census matrix is a Gram matrix.

**Simon Sidon**, 1932, and **Paul Erdős and Pál Turán**, 1941, for `B2` sets, whose pairwise
differences are all distinct. **James Singer**, 1938, for perfect difference sets. These are the
combinatorial ancestors of the probe-spreading argument, and section 7 replaces them with a
measurement against the field.

**Edwin T. Jaynes**, *Information Theory and Statistical Mechanics*, Physical Review 106(4), 1957,
pages 620 to 630, and the sequel at 108(2), 1957. The maximum entropy principle this whole tree is
built on, and the reason a determinantal process is the right object: it is the maximum entropy
distribution carrying prescribed marginals with negative correlation.

**Robert S. Boyer and J Strother Moore**, 1977, and **R. Nigel Horspool**, 1980, for the shift rules
that skip alignments without reading them. That is the prior art the companion document measures the
engine against.

Further reading used for the determinantal material:
<https://arxiv.org/pdf/2204.02570>, <https://arxiv.org/html/math/0204325v1>

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
