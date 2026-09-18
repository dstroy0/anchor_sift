# The inspection points of the engine, and what each one reveals about the run

**Purpose:** Name every place the engine exposes its own internal process to an observer, say what
can be inferred from each, and say what cannot be seen at all.
**Scope:** `src/engine/c/portable/anchor_sift.h`, `src/engine/c/portable/anchor_sift.c`,
`src/engine/c/portable/anchor_raster.h`, `src/engine/c/portable/anchor_raster.c`.
**Line citations are against commit `54f1e25`, where `anchor_sift.h` is 967 lines and
`anchor_raster.h` is 432. Check them against that commit and not against a later one.** The
measurements were taken at `9cbcc08` and earlier; `54f1e25` changed documentation only and no
`.c` file. No number below moved with it.

**Since this snapshot, the device volume renderer exists and is graded.** At `54f1e25` there was no device volume kernel and `anchor_volume_device_available` returned 0 on every build. As of 2026-09-17 the kernel is built. `render_volume` is at `src/engine/c/render/raster_cuda.cu:329`, `anchor_volume_device` at `:383`, and the probe at `:373` returns 1 where a device is present and the build carries the kernel; `bench_raster` grades the device volume against the host voxel for voxel. See `docs/rendering.md` and the README.

Every point below was read in the declaration, and the ones marked **run** were exercised on
2026-09-16 against the tree at `9cbcc08`. Points marked **declared** were read and not exercised.

## What the machine is, since that decides what is worth inspecting

A single descent over a fixed corpus and needle is a finite automaton with data dependent control
flow. The destroy test reads the corpus and can end the descent early. Corpus content decides the
depth downward. `while (placed < count)` bounds it above, and `count` is at most
`ANCHOR_STEER_ANCHORS`. Depth is therefore a steer, not a constant, and the bound above is a
constant.

Most of this document rests on that single fact. A machine whose depth the data can
move is a machine whose run has something to report, and every counter below exists because
somebody wanted to know what the data did to a particular run.

## 1. Did it steer, and how hard

| point                                         | where                | what it says                                               |
| --------------------------------------------- | -------------------- | ---------------------------------------------------------- |
| return value of `anchor_steer_plan_recursive` | `anchor_sift.h:638`  | offsets actually placed                                    |
| return value of `anchor_steer_spawn_coarms`   | `anchor_sift.h:712`  | the same, for the spawning descent                         |
| `force_full_depth`                            | `AnchorSteerDescent` | non-zero descends every level and ignores the destroy rule |

**The inference.** `placed` below `count` means the destroy test fired and the descent stopped
early. `placed` equal to `count` means it ran to the requested depth. The declaration at
`anchor_sift.c` puts it plainly at the break site: `placed` is returned so the caller learns how many
probes survived.

**The differential is the real instrument, and it is the only way to see the steer itself.** Run the
same corpus and needle twice, once with `force_full_depth` zero and once non-zero, and the
difference between the two `placed` values measures what the destroy rule decided. Nothing else
exposes that decision, because the engine does not report which level fired or why.

**Run.** `bench_sigma` reports `placed` per row and it moved with the data: 2 at alphabet 2^8 and
2^12, 1 from 2^16 up, with `count` fixed at 4 on every row. At a large alphabet the first probe cuts
the survivors far enough that a second adds nothing. That column is the steer being observed.

## 2. What it read, in the two units that are not interchangeable

Counted builds only, behind `ANCHOR_SIFT_COUNT_READS` (`anchor_sift.h:46`). At 0 the macros expand
to nothing and the object is what it was.

| point                        | where              | what it says                                                                 |
| ---------------------------- | ------------------ | ---------------------------------------------------------------------------- |
| `anchor_sift_probes`         | `anchor_sift.h:53` | corpus bytes read by an anchor probe since the last reset                    |
| `anchor_sift_verifications`  | `anchor_sift.h:56` | exact compares since the last reset, each reading at most `needle_len` bytes |
| `anchor_sift_counters_reset` | `anchor_sift.h:64` | sets both to zero                                                            |

**Why they are two numbers and not one.** A probe read is one byte. A verification is up to
`needle_len` bytes and is exactly one only when the first byte differs. Reporting a single total
would merge a cheap unit with an expensive one. This is the accounting the read floor argument runs
in, and it is the reason that argument is stated in read events.

**A counted run and a timed run are different runs, and the header says so.** "A cycle count and a
read count cannot come from the same run: counting perturbs the timing it would be reported beside."
Any table putting cycles and reads in the same row is reporting two runs, and should say so.

**Declared.** Not exercised here; the builds available were timed builds.

## 3. Whether the fast path actually ran

| point                              | where               | what it says                         |
| ---------------------------------- | ------------------- | ------------------------------------ |
| `anchor_steer_scan_calls`          | `anchor_sift.h:912` | scans performed since the last reset |
| `anchor_steer_wide_calls`          | `anchor_sift.h:915` | scans served by a vectorized engine  |
| `anchor_steer_scan_counters_reset` | `anchor_sift.h:918` | sets both to zero                    |

**The inference, and it is not the one a differential gives.** A differential proves two engines
agree. These two prove the engine the machine carries actually ran. The header records the case that
motivated them: an AVX2 engine was built, graded against portable and benched at 33 times its rate
while the planner went on running its own scalar loop, and nothing in the suite said so. A vectorized
engine that reports itself present and never gets called produces no wrong answer. Every count
stays identical and every test keeps passing.

**Run.** The wiring check reports `avx2 | 189 | 189 | 100% | ok`. Wide calls equal total calls,
the ratio is 1 and the claim is not vacuous.

## 4. What it decided the field looks like

`anchor_field_project`, `anchor_sift.h:513`, writes four observables through the
`AnchorFieldProjection` args.

| point                   | what it says                                                                                          |
| ----------------------- | ----------------------------------------------------------------------------------------------------- |
| return value            | 1 projected, 0 refused. On a refusal it is the ONLY signal, because no refusal path writes `distinct` |
| `distinct`              | surviving component count, after merges                                                               |
| `ranks`                 | one rarity rank per position, rarest first. Rank 0 is the class that refutes most alignments          |
| `class_of_position`     | which class each position fell in                                                                     |
| `members_in_class`      | how many positions each class holds, the field's frequency distribution                               |
| `rarity_place_of_class` | where each class sits in the rarity order                                                             |

**The inferences worth naming.** `distinct` of 1 means the closure collapsed the whole field into one
class, the projection refutes nothing, and the run will cost a full scan. `distinct` equal to
`length` means every position is its own class and the projection is at full strength.
`members_in_class` is the only place the frequency distribution is visible, and it decides
which classes merge past rank 255.

**Run.** All four exercised. A 400 class field reports `distinct` 400 with 145 classes sharing a
rank, and the merged classes have mean occurrence 9.00 under both of two arrangements carrying
identical frequency multisets. That is the rarity ordering at work. A chained tolerance field
reports `distinct` 1 and writes exactly 1 rank value across 1200 positions.

## 5. Where every alignment died, the execution trace

`anchor_raster.h:84` names five channels. The volume renderer writes one voxel per alignment.

| channel                      | what it says                                                   |
| ---------------------------- | -------------------------------------------------------------- |
| `ANCHOR_CHANNEL_DEATH_LEVEL` | the probe index that rejected the alignment, brighter is later |
| `ANCHOR_CHANNEL_SURVIVED`    | binary, bright where every probe agreed                        |
| `ANCHOR_CHANNEL_RARITY`      | rarity rank of the corpus byte at the alignment                |
| `ANCHOR_CHANNEL_BYTE`        | the corpus byte itself, which renders the object raw           |
| `ANCHOR_CHANNEL_PROVEN`      | two valued: proven to hold no occurrence, or undetermined      |

**`DEATH_LEVEL` is the per-alignment execution trace and it is the strongest inspection point here.**
Every other counter is an aggregate over the run. This one records, for each alignment separately,
which probe killed it. Reading it tells you the order the probes did their work in and how much each
one was worth, which no single number can.

**`PROVEN` is the soundness observable.** Its two values are proven and undetermined. A probe can
prove an alignment holds no occurrence and can never prove that it does, and the whole construction
rests on that asymmetry. The channel makes the asymmetry visible instead of leaving it in prose.

**Run.** Volume sweep, 4 layouts by 5 channels, 20 rows, every row filled 32768 voxels with 0
collisions. Each layout is a bijection from alignments onto voxels and nothing is overwritten or
skipped.

**One thing this renderer does NOT let you inspect, recorded as R9.** `anchor_volume_render_host`
takes a `census` parameter and discards it, building its own from `corpus`. A caller supplying a
census over a reference distribution does not get it used. The declaration now says so.

## 6. What it would choose, before it chooses

| point                       | where               | what it says                                             |
| --------------------------- | ------------------- | -------------------------------------------------------- |
| `anchor_field_census`       | `anchor_sift.h:265` | occurrences per symbol and the total, for a byte field   |
| `anchor_steer_probe_order`  | `anchor_sift.h:303` | needle offsets in rarity order                           |
| `anchor_steer_prefers_free` | `anchor_sift.h:334` | which arm the kernel picks for this census               |
| `anchor_steer_probe_fits`   | `anchor_sift.h:771` | whether one probe shape is legal against a needle length |

**The inference.** These are the planner's inputs and its decision, exposed before the run instead
of after. `probe_fits` is the boundary function. Enumerating it maps the whole legal probe set,
so the sweep's argmax becomes checkable.

**Run.** `probe_fits` exercised across steps 0, 1, 2, 7, 13, 64 and 100000 at length one, all legal.
`bench_dispatch` prints six rules scored two ways, by rows won and by cycles given up, and the two
scores disagree, and both are printed for that reason.

## 7. What the machine says about itself

| point                                          | where                                        | what it says                                             |
| ---------------------------------------------- | -------------------------------------------- | -------------------------------------------------------- |
| `anchor_steer_avx2_engine` and the arm getters | `anchor_sift.h:957`, `exact_arm.h:60` onward | a pointer, or NULL where the processor does not carry it |
| `anchor_volume_device_available`               | `anchor_raster.h:282`                        | 0 on every build at 54f1e25                              |

**The inference.** These ask the processor instead of trusting the build. A NULL means absent and is
distinguishable from present and broken, and a capability probe answering 0 honestly keeps a
stub from reporting itself present.

## 8. What cannot be inspected, and why that is deliberate

**The symbol.** `AnchorField` carries an `AnchorSameAt` oracle and an opaque `const void *field`
pointer the engine never dereferences. Equality is the whole interface: no order, no hash, no element
size, no alphabet enumeration. An observer holding the engine's state cannot recover what any symbol
was.

**That refusal is what is being bought and what is being paid for, and both are now measured.** It
buys independence from alphabet size, priced in F14 at a 7.4 times constant factor per corpus symbol
with a crossover near six times the corpus length. It costs `m` bits of state where exact streaming
matching is reachable in `O(log^2 m)`, because that route runs on Karp-Rabin fingerprinting and
fingerprinting needs arithmetic on symbols. One interface decision, two currencies.

**Which level the destroy rule fired at, and why.** `placed` gives the depth reached. The engine does
not report which level ended it or what the survivor count was when it did. The `force_full_depth`
differential recovers the fact that it fired and the cost of its firing, and not the reason.

**Reads and cycles in one run.** Stated above and repeated here because it is the easiest of these to
violate by accident.

## 9. The shape of the whole set

Three of these are aggregates over a run: the read counters, the scan counters, the projection's
`distinct`. Four are inputs exposed before the decision: census, probe order, prefers_free,
probe_fits. One is a per-alignment trace: the raster's `DEATH_LEVEL`. One is a control instead of an
observable: `force_full_depth`, which exists to let a differential isolate the steer.

The gap worth naming is between the aggregate and the trace. `placed` says the descent stopped early
and `DEATH_LEVEL` says which probe killed each alignment, and nothing in between reports the survivor
count at each level, the number the destroy rule actually compares. A caller wanting that
today runs the descent twice and subtracts.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
