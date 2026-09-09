# The engine in C

**Purpose:** Build and run the sift and its benches using only a C11 compiler, and find which bench answers which question.
**Scope:** `src/engine/c/sift/`, `src/engine/c/bench/`

```
cmake -S src/engine/c -B build/engine_c -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/engine_c
./build/engine_c/bench_lattice
./build/engine_c/bench_scaling_reads
./build/engine_c/bench_scaling_cycles
```

No ESP-IDF, no device toolchain, no Python, and nothing from the vendored library. This shares no code with `src/engine/python/` and is not a binding for it. The two implement the same construction and are checked against each other by agreeing on counts.

## What is here

| file | what it is |
|---|---|
| `sift/anchor_sift.{c,h}` | three arms and a dispatcher, with no clock and no output |
| `bench/bench_corpora.{c,h}` | the generated corpora and the two statistics a dispatch decision reads |
| `bench/bench_lattice.c` | soundness, where the claim actually lives |
| `bench/bench_scaling.c` | what the sift costs per alignment as the corpus grows |
| `bench/bench_dispatch.c` | which arm to run, and what the two thresholds should be |
| `bench/bench_coherence.c` | at what scale the corpus agrees with itself, read before the search |
| `bench/bench_sift.c` | candidates, skip distance and anchor independence over byte strings. Not wired up |
| `bench/bench_entropy.c`, `bench/bench_ab.c`, `bench/bench_cycles.c` | not wired up |

Nothing under `src/` comes from anywhere else, and nothing under `deps/` is a copy any more. `mmgr_sha256.{c,h}` used to sit in `bench/`; it is MMgr's test support and it lives in MMgr, at `deps/mmgr/test/support/`. Run `python tools/maintain/get_deps.py` to clone what this tree depends on. The three unwired drivers that include it get that directory on their include path when somebody wires them up. Nothing built here needs it: `bench_corpora` fills every corpus with splitmix64.

`bench_corpora` is shared so the scaling bench and the dispatch bench cannot disagree about what skewed means. One measures a rate against a prediction and the other scores a rule with a clock, and a rule scored on corpora the prediction never saw is a rule scored against nothing.

## bench_lattice, where the soundness claim is tested

Its core takes a base list, a displacement list, and a callback answering whether two positions carry the same symbol. The core has no dimension parameter because the geometry is entirely inside the base list, and no symbol type because it only ever asks whether two agree. A core that cannot see either one cannot depend on either one.

**3,421 rows, 465,546 true occurrences, none refused.** Alphabets of 2 to 256 symbols, patterns of 1 to 32 points, 1 to 32 anchors up to and including every point being one, dimensions 1 through 8, a complex alphabet with irrational parts compared over its storage, a rotated point set, a scatter no rectangle covers, three anchor rules that share nothing, and an order check against a permuted base list.

Occurrences are planted, and they have to be. A pattern of `p` points over `L` symbols occurs by chance about `positions / L^p` times, which is already under one at eight points over sixteen symbols. A row that checked nothing is not evidence that anything held.

## bench_scaling, and what it settles

Reads and cycles come from two builds of one source, because counting perturbs the timing it would sit beside. `ANCHOR_SIFT_COUNT_READS` is inert at its default, so the timed build is the object it was without the counters.

### The asymptotic question, and what the sweep answers

**Does the cost per alignment depend on N?** No. Across 1024 times in corpus length, the three corpora give the same answer.

| corpus | probes per alignment, 4 KB to 4 MB | verifications per alignment |
|---|---|---|
| uniform | 1.003611 → 1.003923 | 0.000000 throughout |
| skewed | 1.380587 → 1.376459 | 0.013459 → 0.013260 |
| periodic16 | 1.188197 → 1.187501 | 0.062732 → 0.062500 |

Nothing drifts. The sift is linear in N with a constant that belongs to the distribution. The total work is `O(N)` per needle and the coefficient is fixed by `H2` before the search starts. The small rise in the uniform column is the entropy estimate filling out, from `H2 = 7.9189` at 4 KB to `7.9999` at 4 MB, and the probe rate tracks it to the fourth place.

**Is the histogram bound right?** It is exact where the corpus has no arrangement and it is wrong by a bounded constant where it has one, and in both cases the error is flat in N.

- Uniform: predicted `1 + 2^-8 = 1.003906`, measured 1.003923. Nothing survives to verification.
- Skewed: measured 0.013260 against a predicted 0.011917, a ratio of 1.11 that holds at every length. The excess belongs to the 32 needles, not to the corpus: the survival of a needle is the product of its four anchor symbol probabilities, that product is heavy tailed on a skewed alphabet, and the same 32 needles are used at every N. A fixed sample cannot drift.
- Periodic16: predicted `2^-16`, measured exactly `1/16`, a ratio converging on 4096.

**So the failure is asymptotically well behaved too.** Where the bound breaks it breaks to a constant and not to a growing function of N. The sift stays `O(N)`; it filters less than the histogram promised and it filters by a fixed factor less.

### Why periodic16 misses by exactly 4096

The ratio converges from above as N grows: 4111, 4100, 4097, 4096, 4096, 4096.

The reason is not that the anchor offsets collide. At a needle length of 64 they are 0, 23, 46 and 53, which are 0, 7, 14 and 5 modulo sixteen, and no two of them agree. The reason is that a corpus of period sixteen is a single orbit under translation. Position `p` carries `p mod 16`. A needle taken at offset `s` therefore has `needle[o] = (s + o) mod 16`, and an alignment at `at` matches that anchor when `(at + o) ≡ (s + o) mod 16`. The offset cancels. Whatever offset an anchor was placed at, it tests `at ≡ s (mod 16)`. Four probes therefore ask one question four times, and one alignment in sixteen survives all of them.

The probe count confirms the mechanism to four places. One probe always runs, it succeeds one time in sixteen, and the three behind it then succeed for certain, which is `1 + 3/16 = 1.1875`. Measured: 1.187501.

## bench_coherence, the reading taken before the search

The miss above does not have to be met. It can be computed before the search, from one pass over lags that is cheap next to the search itself.

Where `k` anchors collapse onto one independent probe, the histogram overstates the filter by exactly `2^((k-1) * H2)`. For four anchors on a corpus of period sixteen at `H2 = 4.0`, that is `2^12 = 4096`.

| corpus | H2 | period found | agrees | at chance | margin |
|---|---|---|---|---|---|
| uniform | 7.999 | none | | 0.0039 | 0.0001 |
| skewed | 1.598 | none | | 0.3336 | 0.0007 |
| periodic16 | 4.000 | **16** | 1.0000 | 0.0625 | 1.0000 |

| corpus | independent anchors | histogram says | coherence says | measured | off histogram | off coherence |
|---|---|---|---|---|---|---|
| uniform | 4 | 0.000000000 | 0.000000000 | 0.000000000 | nothing survived | nothing survived |
| skewed | 4 | 0.011789708 | 0.011789708 | 0.013251748 | 1.1 | 1.12 |
| periodic16 | 1 | 0.000015259 | 0.062500000 | 0.062503577 | **4096.2** | **1.00** |

The period is recovered with nothing supplied. Each candidate is scored against its own multiples, not by taking the tallest lag: a period of sixteen agrees with itself at 32, 48 and 64 alike, and which of those stands tallest is settled by noise. Scoring against multiples is the same reading `measure.periodicity.sequence_period` performs in the Python engine, where it was caught against a period chemistry fixes at three. The two share no code.

**What this changes about the order of operations.** Coherence is read first and everything downstream follows from it: how many anchors carry information, what spacing keeps them off one residue class, and which of the two predictions to believe. Collision entropy is permutation invariant. No bound built from H2 alone can see arrangement, because a corpus and its own shuffle carry identical H2. Coherence is the reading that can, and it is one pass.

### Setting the anchor count from the recovered size

`anchor_sift_run` takes the plan and places the anchors the coherence reading calls for. Where a period is found the anchors after the first refute nothing the first did not already refute, so the count drops to one.

| corpus | anchors placed | probes per alignment at 4 | at the chosen count | saved | survivors |
|---|---|---|---|---|---|
| uniform | 4 | 1.003932 | 1.003932 | 0.0% | unmoved |
| skewed | 4 | 4.000000 | 4.000000 | 0.0% | unmoved |
| periodic16 | 1 | 1.187511 | 1.000000 | **15.8%** | unmoved |

Survivors have to stay put and do. The anchors dropped were refuting nothing. The bench checks it on every row instead of assuming it.

**Be clear about the size of this.** Fifteen percent of the probes is a few percent of the search, because the probes are one byte each and the verification behind them reads the whole needle. The reason to read coherence first is not this saving. It is that a corpus with a period cannot be filtered below `1/P` by anchors, however many are placed, and knowing that before the search is the difference between choosing a different discriminator and paying four times over for one bit.

**What it does not settle.** The periodic corpus here is a clean single orbit, the extreme case. On a clean orbit no anchor spacing helps, since the offset cancels out of the test entirely. A real corpus carries partial coherence, and the collapse would be partial with it. The spacing is computed and reported but not acted on: justifying that needs a partially coherent corpus, and there is not one here. `anchor_sift_anchors_for` returns 1 on any corpus that clears the detection floor, where a partially coherent corpus would want a count somewhere between one and four.

That is permutation invariance in the open. The histogram sees sixteen symbols at H2 exactly 4.0 and cannot see that the positions are one orbit, and no statistic of that order can.

**The verification floor was an artifact of a small corpus.** At 2789 bytes, one guaranteed occurrence per needle is a large share of the alignments, so the arms converged. At 4 MB the 32 guaranteed occurrences sit in 134 million alignment tests and the floor is gone.

## bench_dispatch, which chose the rule the kernel now ships

The dispatcher used to branch on needle length alone. It never read `plan->collision_entropy` or `plan->distinct_symbols`. `ANCHOR_SIFT_FLAT_SHARE` and the whole of `two_to_the()` were unreachable, and the compiler said so on every build.

The repair was not to switch to the documented rule, because the documented rule is also wrong. `bench_dispatch` sweeps both thresholds over every combination instead of scoring the two that were written by hand, and it reports what it finds per corpus as well as overall.

| rule | picked fastest | cycles given up |
|---|---|---|
| always inorder | 25 of 42 | 258,444,233 |
| always free | 17 of 42 | 54,159,531 |
| needle length alone, as shipped | 21 of 42 | 178,923,873 |
| flatness then length, as documented | 33 of 42 | 153,483,501 |
| flatness alone | 41 of 42 | 1,975,242 |

**The flatness threshold survives the sweep and the needle length ceiling does not.** Every threshold from 0.34 to 0.96 scores identically, because the three corpora read 0.96, 0.33 and 1.00 and nothing lies between them. The 0.85 the kernel carried sits inside that interval and stays. The ceiling of 16 is beaten by having no ceiling: the free order arm wins on a skewed corpus at every needle length from 4 to 256, by 2.95 times on average and 3.42 times at its widest.

Counting rows is the weaker of the two scores and both are printed. A rule that gets a row wrong where the arms differ by one percent has cost one percent, and cycles given up is what a dispatcher exists to minimize. On that score the shipped rule was giving up ninety times what the fixed one gives up.

Per corpus, for a caller who holds one:

| corpus | flatness | run this | free arm at |
|---|---|---|---|
| uniform | 0.9639 | `anchor_inorder` | no length |
| skewed | 0.3320 | `anchor_free` | every length |
| periodic16 | 1.0000 | `anchor_inorder` | no length |

## One defect left, unfixed because it is a decision

**Horspool is gone from the kernel and the older drivers still call it.** `bench_cycles.c` puts `anchor_sift_horspool` in its arms table. That driver does not compile, because no such symbol exists in the tree.

Horspool was also the wrong comparison. It needs an ordered index set and a shift table the size of the alphabet; the sift needs neither. Timing the two side by side on a byte line runs the sift in the one domain where discarding order buys nothing.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
