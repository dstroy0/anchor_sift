# The sift

**Purpose:** Say what the search kernel guarantees, how to build it, what each grader answers, and how it draws what it saw.
**Scope:** `src/c/engine/nbody/orior/`, `utils/test/src/`, `utils/bench/`

[`src/c/engine/nbody/orior/orior_*.c`](https://github.com/dstroy0/orior/tree/main/src/c/engine/nbody/orior) holds the search and the steering that places its probes. With the portable scan beside it and the exact integer arithmetic under [`src/c/types/integers/`](https://github.com/dstroy0/orior/tree/main/src/c/types/integers), it builds and runs with a C11 compiler alone, four sources and no build system ([Setup](setup.md#the-c-engine)). The Python in [`src/python/engine/nbody/orior/sift/`](https://github.com/dstroy0/orior/tree/main/src/python/engine/nbody/orior/sift) implements the same construction, shares no code with it, and the two are checked against each other by agreeing on counts.

**It is a sound filter.** A subset of a pattern's points is a necessary condition. No arrangement of anchors can lose a true occurrence. That is a proof, using no order, no dimension and no alphabet ([Why the count is exact](ENGINE_PROOF.md)). The measurement beside it: across 35 rows of corpora, needle lengths and strides, no search ever reported fewer occurrences than exist. Errors are one directional. A discrepancy is always an over-count and is detectable without knowing the answer.

**It carries `m` bits of state**, for a pattern of length `m`, independent of alphabet and dimension. Nothing is indexed and no table is built over the alphabet. A real-valued or unenumerable alphabet therefore costs it nothing. That is a capability claim and it is separate from any speed claim.

**It searches with no pattern at all.** Given only bytes it recovered a multiple of a record period from 512 reads, at 92 shifts against 0 on a shuffle of the same bytes.

## The kernel dispatches, and grades itself

`orior_choose` picks an engine from the field's own census, which one histogram pass already produced. The comparison is exact integer arithmetic and the engine holds no floating point value anywhere: the effective alphabet `2^H2` is `total^2 / sum(count^2)`. Asking whether it reaches 85 percent of the symbols the field uses clears its denominators into `100*total^2 >= 85*distinct*sum(count^2)`.

`bench_dispatch` times every engine, prints what the dispatcher chose beside what was fastest, and scores six candidate rules against each other. Over 42 rows the rule the kernel carries names the faster engine 39 times on x64 MSVC 19.44 at Release, giving up 9131790 cycles or 0.035 of the worst rule, and 41 times under gcc on the same machine, giving up 86511 cycles or 0.000. That is a hundredfold gap in the cycles figure and it is not rounding. Both are real runs, and each number belongs to the toolchain that produced it. The bench exists for that reason, and its output is a recommendation to act on and not a figure to quote. It sweeps its threshold instead of assuming it: the interval 0.34 to 0.96 all score identically and the 0.85 the kernel carries sits inside it.

**The needle length term in the rule does nothing on this data.** Scoring flatness alone ties the kernel exactly, same rows and same cycles. The length term changes no answer on any of the 42. Flatness then length scores strictly worse than the flatness it contains, and length alone is worse than both. A tunable with no reader is an integration point and is neither removed nor described as unimplemented. It is named here and kept until a row is found where it pays.

Cycles given up is the score that matters, and it inverts the row count. Always taking the free order engine is right on 17 rows of 42, the fewest of any rule on the board, and it still gives up fewer cycles than always taking the short circuiting one, which is right on 25. Counting rows treats a row where the engines differ by one percent the same as one where they differ threefold. A rule can be wrong more often and cost less.

The dispatcher is still blind in one direction, and the blindness is a property of the statistic. A period-16 counter uses sixteen symbols evenly. Its collision entropy reads 4.0 and a perfectly structured corpus looks memoryless. Collision entropy is permutation invariant and cannot see an arrangement, and the dispatcher carries the same blindness exactly. Exact arithmetic removes the rounding, not the blindness. Reading arrangement needs a different quantity, and `orior_anchors_for` is where one enters: it takes the period the corpus repeats at and drops to a single anchor, because at a known period every anchor after the first tests the same congruence and refutes nothing new.

## Building it, and what each tool answers

One command from a fresh clone. It needs `cmake` and a C11 compiler on `PATH`. There is no network step, no submodule to fetch, no generator to run first, and no library outside the C standard headers.

```sh
utils/maint/engine/build_engine.sh               # configure, build, run the graders
utils/maint/engine/build_engine.sh --build-only  # configure and build, run nothing
```

Windows PowerShell uses `utils/maint/engine/build_engine.ps1`, and `-BuildOnly` in place of `--build-only`. It imports the MSVC environment and compiles the device rasterizer. The shell script run from Git Bash has no MSVC environment. It pins the build to gcc or clang and says so. Output lands in `build/engine_c/` and nothing reads it back. Delete it freely.

Both scripts share that directory, and a CMake cache outranks anything a script prints. Each one passes the decisive settings on every configure and wipes a cache naming a different toolchain. The PowerShell script checks the configure for a CUDA compiler before it builds and fails if the announcement does not hold.

A machine with a card should render on it without being asked, and `bench_raster` prints `device rasterizer: present` and grades all twenty configurations `host/device identical` when it does.

Two questions, two directories, and they are not the same question. [`utils/test/src/`](https://github.com/dstroy0/orior/tree/main/utils/test/src) answers whether the engine is right. [`utils/bench/`](https://github.com/dstroy0/orior/tree/main/utils/bench) answers how fast it is. A failing test is a defect; a slow bench is a cost.

The graders the scripts run after a build are `test_steer`, `test_adversarial`, `test_arm_agreement`, `bench_steer_arms`, `bench_raster` and `bench_exact_arms`; the PowerShell script also builds and runs `test_o2_spawn`. The rest are built and left for you to run. `bench_lattice` and `bench_sigma` are built by neither script. Build one on its own with `cmake --build build/engine_c --target <name>`.

| run this                          | it answers                                                                                                                                                                                                                                                                                                 |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `test_arm_agreement`              | every engine against the naive one at the lengths that bound the input: none, one, two. A disagreement is a defect whatever it measures.                                                                                                                                                                   |
| `test_adversarial`                | thirteen cases built to break the guarantee from outside the public surface: overlapping occurrences, both boundary alignments, a field where every survivor is false, a permutation null, the probe guard including the widest line that must be admitted, and a joint projection.                        |
| `test_steer`                      | the steering, on five fields. Grades the ordering at seven needle lengths, carries a negative control ordering the commonest symbol first that must read MORE, checks the exact dispatch against four fields worked out by hand, and asserts that the widest scan engine the machine carries actually ran. |
| `test_o2_spawn`                   | the engine turned onto itself: a descent that resumes from another descent's survivors, past the four conditions one descent can place.                                                                                                                                                                   |
| `bench_dispatch`                  | which dispatch rule to carry, scored against the clock over 42 rows, sweeping its threshold instead of assuming it.                                                                                                                                                                                        |
| `bench_steer_arms`                | the scan engines graded against the portable one and then timed, at lengths straddling the thirty-two lane boundary where a vectorized tail fails if it is going to.                                                                                                                                       |
| `bench_scaling_reads`             | reads per alignment as the corpus grows. Reads travel between machines and are what an asymptotic claim is made of.                                                                                                                                                                                        |
| `bench_scaling_cycles`            | the same sweep in cycles, which belong to the machine that produced them.                                                                                                                                                                                                                                  |
| `bench_coherence`                 | at what scale the corpus agrees with itself, and what that costs the histogram bound.                                                                                                                                                                                                                      |
| `bench_sigma`                     | the oracle route against a counter table, timed as the alphabet grows and as it does not.                                                                                                                                                                                                                  |
| `bench_raster`                    | every render configuration. Four sheet layouts by five channels, each written as a PGM and graded host against device byte for byte where a device is present, then four volume layouts by the same five channels into a 32 by 32 by 32 block.                                                             |
| `bench_exact`, `bench_exact_arms` | the fixed width limb arithmetic, and every vectorized limb engine against the portable one.                                                                                                                                                                                                                |
| `bench_lattice`                   | soundness in one to eight dimensions, over a rotated point set and a scatter no rectangle covers. It holds its own core, because the construction is under test, apart from the byte specialization.                                                                                                       |

**The counted build and the timed build are different binaries and cannot be mixed.** `bench_scaling_reads` links the kernel compiled with `ORIOR_COUNT_READS=1`; `bench_scaling_cycles` links the kernel compiled without it. Counting perturbs the timing it would otherwise be reported beside. A driver calling `orior_counters_reset` therefore fails to link against the timed kernel, and that failure is deliberate.

**Known gap:** `bench_lattice` needs C99 `_Complex` arithmetic and does not build under MSVC, which supplies the types without the operators. Build it with GCC or Clang. Every other target in the table was built and run on MSVC 19.44 x64 at Release. The GCC and Clang paths are exercised by the same CMake file.

## Rendering the object, flat and solid

The renderer draws the object under examination straight from engine state. What it shows is what the search saw. Two surfaces, and they are separate because a sheet and a block are different maps and not the same one at two sizes. [`rendering.md`](https://github.com/dstroy0/orior/blob/main/theory/workbooks/orior/rendering.md) covers both.

`AnchorRasterConfig` renders a sheet: `width` by `height`, one of four layouts, one of five channels, a reduce rule for cells several alignments land on, and a gain. `AnchorVolumeConfig` renders a block: `width` by `height` by `depth`, one of four volume layouts, and the same five channels, the same two reduce rules and the same gain, named by reference to the same enums, because a channel means one thing in this tree.

| volume layout   | what it is for                                                                                                                                                                                                        |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `slabs`         | fills a sheet, then the sheet behind it. The three dimensional reading of the row layout.                                                                                                                             |
| `boustrophedon` | every other row and every other slab reversed. Consecutive alignments stay adjacent across both boundaries.                                                                                                           |
| `morton`        | interleaves the bits of x, y and z, preserving locality on all three axes at once. This reads as a solid instead of as stacked sheets. Needs power of two extents and errors others instead of remapping quietly.    |
| `helix`         | each slab's rows shifted by its depth index. A feature at a fixed corpus offset winds through the block. A shear and not a rotation, because a true helix needs trigonometry and this renderer is integer throughout. |

Every layout is a bijection on the cell index, computed in integers. `bench_raster` checks that instead of stating it: it maps every alignment through every layout at every channel and counts collisions, which must be zero. A layout that quietly folded two alignments together would still draw a plausible picture and no other check would notice.

Netpbm has no volume container. `anchor_volume_write_raw` writes the block as raw bytes, x fastest, and puts the extents, the layout, the channel, the reduce rule and the gain in a `.txt` sidecar naming the function that generated it. Any volume viewer that reads raw unsigned 8 bit will open it given those three numbers.

**The device renders both sheets and volumes, and prefers the device where it is present.** `anchor_raster_render` and the volume renderer both prefer the device. `anchor_volume_device_available` returns 1 where a device is present and the build carries the device volume kernel, and 0 otherwise. It never reports a stub as present, and `anchor_volume_render_host` stays host only and is named so. `bench_raster` grades the device against the host voxel for voxel and prints `device rasterizer: present` when it has one. Nothing falls back silently, because a stub reporting itself present is a defect.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
