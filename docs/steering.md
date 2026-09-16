# Steering the engine with its own reading of the field

**Purpose:** Place, order and shape the engine's probes from a census of the corpus being searched, and know why doing so cannot change the count.
**Scope:** `src/engine/c/portable/anchor_steer.h`, `src/engine/c/portable/anchor_steer.c`, `src/engine/c/bench/bench_steer.c`

The engine searches by placing anchors on the needle and testing them at every alignment. An alignment that disagrees at any anchor cannot hold the needle, so it is rejected without a full compare. Which anchors it places, the order it tests them in, and the shape each one takes were all fixed before the corpus was looked at. This document covers the code that decides those three from the corpus instead.

## Every probe is a necessary condition

Each probe tests whether the corpus at some offset carries the needle's own byte at that offset (`src/engine/c/portable/anchor_steer.c:445-457`). A true occurrence agrees at every offset, so it agrees at every probe. Each probe is therefore a necessary condition of an occurrence, a conjunction of necessary conditions is itself one, and no true occurrence is lost by any probe set. Survivors are then filtered by a full compare (`src/engine/c/portable/anchor_steer.c:666`), which removes the false ones. The count is exact for any probe set whatever.

Two different invariants follow, and keeping them apart matters. Reordering a probe set leaves the surviving set itself identical, because conjunction commutes. Moving a probe or changing its shape gives a different probe set, which is a different conjunction and a different surviving set: the survivors of one probe strictly contain the survivors of that probe and a second. What stays identical across every probe set is the COUNT, because every surviving set contains all the true occurrences and the full compare removes the rest.

The survivor count depending on which probe is placed is the steering signal itself, measured in `steer_truthy_after_probe` (`src/engine/c/portable/anchor_steer.c:459-480`). A reading that held the surviving set fixed across different probe sets would leave the planner with nothing to rank.

A move that cannot change the answer is what this tree calls a null. Reordering is a null on the surviving set, and every probe set whatever is a null on the count.

One consequence shapes the whole design. A planner that samples badly, ranks wrongly, or contains a defect still produces some probe set, and every probe set yields the same count. Correctness is not a quantity the planner can spend. Speed is the only one it can spend, and that bounds the damage a bad planner does to the time it takes. The empty plan makes this vivid: destroy every probe, send every alignment to the full compare, and the answer is still exactly right at maximum cost.

## What keeps a probe inside the family

The guarantee above covers necessary conditions and nothing wider, so the value of the guarantee depends on every probe staying inside that family. Three things in the code hold the boundary. `anchor_steer_probe_fits` keeps the origin below `needle_len` and requires every position the probe reads to stay inside the needle (`src/engine/c/portable/anchor_steer.c:416-441`). Candidate generation rejects any shape failing that test before it is scored (`src/engine/c/portable/anchor_steer.c:545`). The comparison reads `needle[offset]`, the needle's own byte at the offset being tested (`src/engine/c/portable/anchor_steer.c:445-457`).

Three shapes would leave the family, and a probe type added later can leave it silently with a missing occurrence as the only symptom.

A probe reading outside the needle has nothing to compare against. A probe comparing against any value other than the needle's own byte at that offset tests something an occurrence does not have to satisfy. A predicate taken from the census instead of from the needle is the live danger in a steering engine: a rule like "skip alignments in a low-rarity region" is not implied by occurrence and drops true hits. The census chooses among probes and must never become one.

A fourth case is latent. An eye here is a conjunction of byte equalities, so the rule holds. If an eye ever becomes an actual integral, an aggregate is a necessary condition only when both sides are computed identically in exact arithmetic. Two different summation orders in floating point would let a true occurrence fail its own test.

## The census is the engine reading its own field

`anchor_field_census` counts what the corpus is made of in one pass, recording the occurrences of each byte value, the total, and how many values appear at all (`src/engine/c/portable/anchor_steer.c:25-51`). Nothing outside the corpus contributes to it. The census then decides where the engine probes that same corpus, so the instrument is turned on the field it is about to measure.

## Rarity ordering needs no logarithm

The theory states the ordering term as rarity, the negative log probability of the symbol an anchor tests. Ordering by that quantity does not require evaluating it. The negative logarithm decreases monotonically in the probability, and every probability over one corpus shares the denominator, so ordering by rarity descending is ordering by raw occurrence count ascending. Both orderings agree on every input.

`anchor_steer_magnitude` returns the total minus the symbol's own count (`src/engine/c/portable/anchor_steer.c:53-60`). The value is an integer, it orders identically to rarity, and it is not an entropy in bits. A symbol absent from the corpus returns the largest magnitude available, which is correct: an anchor testing a symbol the field never produces rejects every alignment at once.

## Truthy and falsy steering

The steering signal is the survivor vector and not the symbol histogram. Each alignment is truthy while it is still standing and falsy once some probe has rejected it. `steer_truthy_after` counts how many currently truthy alignments would remain truthy if a given probe were placed (`src/engine/c/portable/anchor_steer.c:219-238`), and the descent spawns the probe leaving fewest.

Measuring survivors directly accounts for correlation between positions. A histogram says how often a symbol appears; it does not say whether the alignments that agreed at one position tend to agree at another. The survivor count answers the second question, because it is taken over the population that actually survived.

## Recursion over levels, one probe each

`anchor_steer_plan_recursive` reorders offsets a caller has already placed, and `anchor_steer_spawn_coarms` chooses the positions itself (`src/engine/c/portable/anchor_steer.h:214`, `src/engine/c/portable/anchor_steer.h:259`). Both descend through the same core.

A single pass ranks every anchor against the whole field. That is the correct question to ask first and the wrong one to ask second. Once the first probe has rejected most alignments, the ones still standing are the subset that agreed with one particular symbol. Within that subset the remaining probes have different pruning power than they had over the field. Each level here ranks against the alignments that survived the levels above it, taking the conditional distribution in place of the marginal one.

### Signature

```c
size_t anchor_steer_spawn_coarms(size_t *offsets, size_t wanted, const uint8_t *corpus,
                                 size_t corpus_len, const uint8_t *needle, size_t needle_len,
                                 uint8_t *scratch, size_t scratch_len, size_t sample_stride);
```

* `offsets` [BORROWS] out. Chosen offsets, written in evaluation order. Owned by the caller.
* `wanted` in. How many coarms to spawn, at most `ANCHOR_STEER_ANCHORS`.
* `corpus`, `corpus_len` [BORROWS] in. The bytes the search will run over.
* `needle`, `needle_len` [BORROWS] in. The bytes to find.
* `scratch`, `scratch_len` [BORROWS] out. Survivor flags, one byte per alignment. Size it at `corpus_len - needle_len + 1`.
* `sample_stride` in. Plan on every Nth alignment. A value of 0 is treated as 1.

Returns the number of coarms placed, at most `wanted`. Returns 0 without writing `offsets` when a pointer is null, when `wanted` exceeds `ANCHOR_STEER_ANCHORS`, or when `scratch_len` does not reach the alignment count (`src/engine/c/portable/anchor_steer.c:293-309`). The kernel allocates nothing. A buffer too small is refused instead of being worked around.

## Why halting is the wrong question

Two separate properties hold, and the second one carries the argument.

The descent is bounded. One probe is placed per level, a placed probe is never reconsidered, and the depth is `wanted`, which the guard holds at or under `ANCHOR_STEER_ANCHORS` (`src/engine/c/portable/anchor_steer.c:299-302`). That constant is 4 (`src/engine/c/portable/anchor_steer.h:68`). No branch in the descent lets corpus content change how many levels run, only which probe a level picks. The depth is fixed before the program starts, and the loop terminates for the reason a `for` loop over a fixed array does.

The stronger property is that correctness never depends on termination. Every intermediate state of the descent is a complete valid probe set, and every probe set yields the same count. The refinement can be stopped at any instant and the measurement taken with the plan it had reached is correct. Running longer buys speed and cannot buy or lose an answer.

**There are two loops and only one of them has that property.** Plan refinement is anytime and can run as long as anyone wants it to. The sweep over alignments has to run to completion, and stopping it early loses occurrences. A reader who takes the anytime property as a property of the search itself will stop the measurement and get a wrong count.

The bound in the first paragraph is still doing work once the anytime property is stated, and it is doing different work. The anytime property gives safety, since every reachable plan is correct. The bound gives liveness, since the planner emits a plan and the sweep begins. In a design that plans and then sweeps, an anytime planner that never returns produces no measurement at all.

The halting problem asks whether termination can be decided for an arbitrary program. Here the question does not arise, because no answer depends on it. That is a stronger position than a decidable halt. The loop therefore carries no iteration cap and no watchdog. A bound enforced at compile time does not need one, and a runtime check would imply the bound were in doubt. `anchor_steer_spawn_coarms` returns the depth it reached, and `bench_steer.c` asserts that depth instead of trusting this section.

## Spawning and destroying

A level that finds no candidate leaving fewer survivors than it started with has found a probe that rejects nothing an earlier probe had not already rejected. Placing it would read a byte per alignment and buy none. The descent stops there and every level below it is destroyed with it, and the returned count tells the caller how many probes survived (`src/engine/c/portable/anchor_steer.c:383-386`).

`anchor_sift_anchors_for` already does this for one case, returning a single anchor on a periodic corpus because at a period the offsets cancel and every anchor tests the same congruence (`src/engine/c/portable/anchor_sift.h:136-141`). The rule here reaches further. The header warns that a period found is not a period the whole corpus keeps, that a partially coherent corpus wants a count between one and the full set, and that nothing there measures that case (`src/engine/c/portable/anchor_sift.h:145-147`). This rule measures it, along with redundancy from constant runs, local low entropy and correlated positions, none of which a period argument sees.

The two are different kinds of statement and the guide keeps them apart. The period argument is a theorem over every corpus of that period. This rule is an observation about one field, taken on a sample of it when `sample_stride` is above one, so "pruned nothing on this sample" does not establish "can prune nothing". Being wrong costs speed and cannot cost the count.

Destroying the levels below a destroyed probe costs nothing, and the reason is an induction rather than a budget.

The destroy test compares the minimum over every candidate against the current population (`src/engine/c/portable/anchor_steer.c:383-386`). When it fires, the minimum leaves the population unchanged, so every candidate leaves it unchanged. Placing one would prune nothing, and the next level would inherit the identical population. Its candidate set is the same set or a subset of it, since the enumeration bounds are arguments and constants that do not vary by level (`src/engine/c/portable/anchor_steer.c:537-542`) and the coarm descent only ever removes a placed position from consideration. Every candidate in a subset of a set that all left the population unchanged also leaves it unchanged, so the next level's minimum is the whole population and its test fires too. By induction every level below prunes nothing.

Stopping is therefore equivalent to continuing, and the probe set is not smaller than the field would have supported.

The induction needs one property of the enumeration: the candidate set is non-increasing along the descent. Both planners have it. The sweep enumerates the same set at every level, and the coarm descent removes each placed position from consideration (`src/engine/c/portable/anchor_steer.c:341-353`), which is a strict subset. A set that grows at a deeper level voids the theorem, because a candidate absent from the level that fired has never been shown to prune nothing. A set that varies for any other reason voids it as well, since the two cases become indistinguishable from inside.

The argument is exact over the population the planner sees, which is the sampled one when `sample_stride` is above one. Against the full field it carries the same sample caveat as the destroy rule itself.

## Arms and eyes are one shape

An arm reads one position and an eye reads a line of them. `AnchorProbe` records an origin, a step and a length, and an arm is a probe of length one (`src/engine/c/portable/anchor_steer.h:277-283`). One test walks both. `docs/arm-records.md` states the same thing about readings: the difference between a region integral and a line integral lives in the support and not in the arithmetic applied to it.

`anchor_steer_sweep_probes` considers every origin in the needle, every step that keeps the probe inside it, and every length up to a caller's maximum, scoring each shape by survivors (`src/engine/c/portable/anchor_steer.c:537-542`). A step of zero at a length above one reads one position repeatedly, and `anchor_steer_probe_fits` refuses it (`src/engine/c/portable/anchor_steer.c:430-435`).

## An eye does not reduce reads

Measured on the AGPL license text tracked in this repository, 24654 bytes and 24631 alignments, needle length 24, built with MSVC 14.44 at the default CMake configuration and graded against `anchor_sift_naive`:

| route | probes | reads | reads per alignment |
|---|---|---|---|
| spatial, unsteered | 4 | 26425 | 1.072 |
| recursive reorder | 4 | 26276 | 1.066 |
| coarms spawned | 2 | 24635 | 1.000 |
| eyes and arms swept | 1 | 26168 | 1.062 |

Every route returned the reference count. The sweep spawned one eye of length 2 at origin 0 with step 19, and it read more than the two coarms did. An eye of length L reads up to L bytes per alignment where an arm reads one, so it moves the same bytes the equivalent arms move and removes only the branch decisions between them. Reach for an eye where branches cost more than reads, and measure before assuming that holds.

One read per alignment is the floor for a scheme that decides each alignment from reads taken at that alignment, because such a scheme has to look at an alignment to reject it. The coarm route reached that floor on this field.

It is not a floor on string search. Boyer-Moore, Horspool, Sunday and the factor-based methods skip alignments outright: a mismatch at one alignment proves non-occurrence across a range, and the skipped alignments are never read. Horspool averages about `corpus_len / needle_len` comparisons, so its reads per alignment fall below one and keep falling as the needle grows.

The engine gives that up deliberately. A bad-character shift table is indexed by symbol, and `README.md:91` claims state proportional to the needle, no table over the alphabet, and no cost for a real-valued or unenumerable alphabet. Sublinear skipping by shift table trades that claim away. The good suffix rule is the exception worth knowing about: it is precomputed from the needle alone, it skips alignments, and it needs no alphabet table, so sublinear behavior is reachable without giving up the capability. Nothing here implements it.

## Running the graders

```sh
maint/engine/build_engine.sh
```

The script configures, builds named targets and runs the graders. `bench_steer` grades the ordering against `anchor_sift_naive` at seven needle lengths, measures the probe reduction, carries a negative control that orders the commonest symbol first and must read more, checks the exact dispatch against four fields whose answers are derived by hand, and grades arms, eyes and coarms on a synthetic field and on the license text.

Two drivers in `src/engine/c/bench/` do not compile with MSVC and the script does not build them. `bench_dispatch.c:105` uses `CLOCK_MONOTONIC`, which is POSIX. `bench_lattice.c:500` onward does not parse. Both predate this work and neither is on the path the engine needs.

## What is not checked here

The planner costs are stated in the header as worst cases and are not measured. `anchor_steer_sweep_probes` performs `wanted * needle_len^2 * max_length^2 * alignments / sample_stride` byte comparisons at worst. One factor of `max_length` counts the lengths enumerated and the second comes from scoring, since a candidate of length L costs up to L comparisons and those sum to about `max_length / 2`. `anchor_steer_probe_fits` rejects shapes that do not fit, so the real count sits below that figure.

`sample_stride` is the control and no default is recommended, because the crossover was not measured.

Reads are the wrong statistic for a contiguous eye and the table above inherits that. A step-1 eye of length L is one wide load that the machine may satisfy in a single memory transaction, and counting L reads charges it for work done once. Short-circuiting also makes the trip count vary, and a varying trip count costs a mispredicted branch per alignment. The branchless free-order arm exists for that reason (`src/engine/c/portable/anchor_sift.h:106-110`). An eye evaluated branchlessly trades L reads for one predictable branch. Deciding whether eyes ever pay needs a cycle measurement, and none was taken.

The exact dispatch was graded against eleven fields swept from flat to concentrated, agreeing with the double form of the same rule on all eleven. That shows the change is harmless. It does not show it was needed, because no field was constructed whose double-form verdict falls inside the old series error of the threshold. Until one is, the improvement is argued from the algebra and not demonstrated.

The dispatch comparison needs headroom above `total^2`. Its right side reaches `85 * distinct * sum(count^2)`, about 2^14.4 times `total^2` at 256 distinct symbols, putting a four gigabyte corpus near 2^79. `AnchorExactInteger` holds 108 limbs of 32 bits, or 3456 bits (`src/engine/c/portable/exact_limbs.h:49`, `src/engine/c/portable/exact_limbs.h:72`), which covers that with room left. No bench exercises a corpus near that size. The headroom is read off the declaration and has not been measured.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
