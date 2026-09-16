# Steering the engine with its own reading of the field

**Purpose:** Place, order and shape the engine's probes from a census of the corpus being searched, and know why doing so cannot change the count.
**Scope:** `src/engine/c/portable/anchor_steer.h`, `src/engine/c/portable/anchor_steer.c`, `src/engine/c/bench/bench_steer.c`

The engine searches by placing anchors on the needle and testing them at every alignment. An alignment that disagrees at any anchor cannot hold the needle, so it is rejected without a full compare. Which anchors it places, the order it tests them in, and the shape each one takes were all fixed before the corpus was looked at. This document covers the code that decides those three from the corpus instead.

## Every arrangement of the probes is a null

An alignment survives only when every probe agrees with the needle, and the survivor is then verified with a full compare (`src/engine/c/portable/anchor_steer.c:666`). Agreement across a probe set is a conjunction, and a conjunction does not depend on the order its terms are tested in. Reordering the probes, moving them, or changing their shape therefore leaves the surviving set identical and leaves the count identical.

A move that cannot change the answer is what this tree calls a null. The arrangements of a probe set form a group of such moves, and choosing among them is steering.

One consequence shapes the whole design. A planner that samples badly, ranks wrongly, or contains a defect still produces some arrangement, and every arrangement yields the same count. Correctness is not a quantity the planner can spend. Speed is the only one it can spend, and that bounds the damage a bad planner does to the time it takes. An approximate planner is therefore safe to build and safe to interrupt.

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

The stronger property is that correctness never depends on termination. Every intermediate state of the descent is a complete valid arrangement, because every arrangement is a null and every null yields the same count. The refinement can be stopped at any instant and the measurement taken from it is correct. Running longer buys speed and cannot buy or lose an answer.

The halting problem asks whether termination can be decided for an arbitrary program. Here the question does not arise, because no answer depends on it. That is a stronger position than a decidable halt. The loop therefore carries no iteration cap and no watchdog. A bound enforced at compile time does not need one, and a runtime check would imply the bound were in doubt. `anchor_steer_spawn_coarms` returns the depth it reached, and `bench_steer.c` asserts that depth instead of trusting this section.

## Spawning and destroying

A level that finds no candidate leaving fewer survivors than it started with has found a probe that rejects nothing an earlier probe had not already rejected. Placing it would read a byte per alignment and buy none. The descent stops there and every level below it is destroyed with it, and the returned count tells the caller how many probes survived (`src/engine/c/portable/anchor_steer.c:383-386`).

`anchor_sift_anchors_for` already does this for one case, returning a single anchor on a periodic corpus because at a period every anchor tests the same congruence (`src/engine/c/portable/anchor_sift.c:223-232`). The rule here measures the redundancy per level against the field, so it also reaches fields whose redundancy no period search would name.

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

One read per alignment is the floor for any arrangement, because an alignment must be looked at at least once to be rejected. The coarm route reached it on this field.

## Running the graders

```sh
maint/engine/build_engine.sh
```

The script configures, builds named targets and runs the graders. `bench_steer` grades the ordering against `anchor_sift_naive` at seven needle lengths, measures the probe reduction, carries a negative control that orders the commonest symbol first and must read more, checks the exact dispatch against four fields whose answers are derived by hand, and grades arms, eyes and coarms on a synthetic field and on the license text.

Two drivers in `src/engine/c/bench/` do not compile with MSVC and the script does not build them. `bench_dispatch.c:105` uses `CLOCK_MONOTONIC`, which is POSIX. `bench_lattice.c:500` onward does not parse. Both predate this work and neither is on the path the engine needs.

## What is not checked here

The planner costs are stated in the header as worst cases and are not measured. `anchor_steer_sweep_probes` performs `wanted * needle_len^2 * max_length * alignments / sample_stride` byte comparisons at worst, which exceeds the scan it plans for on any but a short needle. `sample_stride` is the control and no default is recommended, because the crossover was not measured.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
