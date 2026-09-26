# Anchor sift: an algorithm for precision measurement

**Purpose:** Find an object's information entropy.
**Scope:** `src/`, `test/`, `maint/`, `examples/`, `evidence/`, `docs/`, `theory/`

## Contents

1. [Quick start](#quick-start)
2. [The algorithm](#the-algorithm)
3. [No bounding, no tuning](#no-bounding-no-tuning)
4. [Areas of research](#areas-of-research)
5. [Where things are](#where-things-are)
6. [The detector and the measure are not the same reading](#the-detector-and-the-measure-are-not-the-same-reading)
7. [The transforms](#the-transforms)
8. [The sift](#the-sift)
9. [Ports](#ports)
10. [What it knows](#what-it-knows)
11. [Whose language this is](#whose-language-this-is)
12. [The condition of use](#the-condition-of-use)
13. [Where to start reading](#where-to-start-reading)
14. [What is not here](#what-is-not-here)
15. [Licensing](#licensing)
16. [A note on how this is written](#a-note-on-how-this-is-written)

## Quick start

From a fresh clone, at the repository root:

```sh
maint/engine/build_engine.sh                                      # the C engine: configure, build, run the graders
python examples/any_corpus/4_measure/collision_entropy.py         # a reading that knows nothing about its corpus
python examples/crystallography/6_oracle/proof_positive_control.py  # the positive control, against published cells
sh maint/texbuild/build_theory.sh                                 # the fifteen books
```

On Windows PowerShell the engine builds with `maint/engine/build_engine.ps1`. Most examples read corpora under `build/`, which are not in git: `maint/data/fetch/` fetches them, and `python maint/deps/get_deps.py` clones what the C side needs. `docs/setup.md` and `docs/usage.md` cover the rest.

## The algorithm

Measure how far something sits from the most disordered arrangement of its own parts. (Shannon's information entropy)

That is the most basic construction.

Every domain below is that sentence with a different answer to what counts as a part:

- atoms in a cell
- symbols in a corpus
- bytes in a file
- coordinates in a board layout

The reference is built from the object's own parts. There is no prior to estimate, no training set, no model, and no neural net representation of the domain.

Building a reference by maximizing entropy under the constraints the object supplies is Jaynes's principle. The departure from it is the free energy above equilibrium.

The basic construction, Identity:Null Permutation, runs through all six parts. Represent the object as points carrying values, fix a partition over those points, build the maximum entropy reference that partition allows, and read the departure from it. The sift and the oracle sit either side, one discarding candidates and one supplying an answer from outside the sample.

| part             | what it does                                                                                       |
| ---------------- | -------------------------------------------------------------------------------------------------- |
| `representation` | any domain written as points carrying values, and the re-seatings that put one symbol in one place |
| `partition`      | the unit(s) and the scale those points are read at                                                 |
| `reference`      | the maximum entropy background under the constraints the object supplies                           |
| `measure`        | the departure from that background                                                                 |
| `sift`           | the sound filter, a necessary condition over any index set                                         |
| `oracle`         | agreement with ground truth that somebody else published                                           |

Each part is a directory under `src/engine/python/`, beside `instrument/` and `render/`. Everything downstream of `representation` sees points and values and is blind to what an object is. One instrument reads both. Seven subjects have their own directories under `representation`, the only part that knows a domain exists: `atom`, `game`, `particle`, `picture`, `sound`, `structure` and `text`. `representation/constants/` sits beside them.

`src/engine/python/README.md` is the map. `examples/` runs the same six names end to end on real corpora, one stage directory per part.

## No bounding, no tuning

The method picks no tolerance, no threshold, and no parameter by judgment. Bounding is choosing a cutoff to make a result come out the way it was expected to. It is the failure this work is built to avoid, and it is not permitted anywhere in it.

Every comparison is exact integer arithmetic. The engine holds no floating-point value, and there is no rounding to hide a chosen bound inside. The null a departure is measured against is drawn by permuting the object's own parts, never computed from a formula that could be tuned. Where a reading appears to need a cutoff, the cutoff is swept and the reading is reported across the whole sweep, as a curve. A positive control runs beside every negative result, because a negative result with no positive control has measured nothing.

A number picked to make a result come out is not a measurement. This work does not carry one, and a contribution that adds one does not land.

## Areas of research

Twelve subjects have staged pipelines under `examples/`. Seven have run end to end and agree: language, art, crystals, proteins, sound, source code and arbitrary corpora. Chemistry, game theory, cell tracking, molecules and particle physics are the newest and are being brought to the same standard. The proofs that pin the numbers are under `evidence/proofs/`. The same six parts test each other end to end and agree.

Published cell edges from the Crystallography Open Database, tiled and voxelized and handed over with nothing told to the detector, come back three of three exact, to 0.0006 angstroms against a voxel of 0.25. No other positive control here took its answer from outside the work.

A dialect border inside Lushootseed, labeled by Mellesmoen and Kye and then held out, comes back as the stressed schwa, southern, beaten by 1 of 200 random borders over the same forms.

An image read as a byte sequence returns its own width. A Vigenère cipher returns its key length. A protein backbone returns bond lengths of 1.45, 1.52 and 1.33 against chemistry's 1.46, 1.52 and 1.33. None of them was told anything.

Subtraction games return their Grundy period on 383 of 383 rows the detector can score, against periods computed by a separate exact routine, at a worst margin of 16 floors. The same detector returns a confident number on a sequence that has no period at all, and what it is reading there is the continued fraction of the sequence's slope.

The workbook holds the rest, including every row that failed and why.

## Where things are

Each directory serves one purpose.

|                             | what it operates on          |                                                                                                   |
| --------------------------- | ---------------------------- | ------------------------------------------------------------------------------------------------- |
| `src/`                      | points and values, no domain | the engine: the Python in `src/engine/python/`, the C in `src/engine/c/` with its benches in `bench/` |
| `test/`                     | the engine                   | the C correctness checks in `test/engine/`, the maintenance tests, and the published test vectors |
| `evidence/`                 | the claims                   | the proofs, and the R and MATLAB ports                                                            |
| `examples/`                 | a corpus, through `src/`     | 159 scripts over twelve subjects, each at `examples/<subject>/<stage>/<file>.py`                  |
| `maint/`                    | the repository itself        | records, gates, prose checks, the book build, the data fetchers and the Salishan pipeline         |
| `theory/`                   | the argument                 | seventeen books                                                                                   |
| `docs/`                     | the reader                   | setup, usage, steering, rendering and the verification notes                                      |

`examples/README.md` explains the stages and how to run a script. `maint/README.md` maps the maintenance tools. `build/` is generated and disposable, and nothing irreplaceable is reachable through it.

## The detector and the measure are not the same reading

The engine carries many readers, one per file under `src/engine/python/measure/` and `src/engine/python/reference/`, and the examples run each on a corpus. Two of them are mistaken for each other more than any others, and reporting one as the other is the error this work has spent the most effort correcting.

The shift agreement detector reads a period or an offset, from how often a shift agrees with itself. The permutation null measure reads how far an object sits from a shuffle of its own parts, and its bit form reads the exact invariances that survive the shuffle. A number from one is not a number from the other.

What each reader has and has not been shown to do is in the workbook, row by row, including the rows that failed. Read it before quoting any reading. The one reading whose answer came from outside this work is the crystal cell edge, three of three exact from the Crystallography Open Database, recorded under Areas of research above.

## The transforms

The engine carries a large set of transforms, maps that put the object into another representation and, where they invert, back. They are integer and exact, and a transform with an inverse returns the input to the bit on the round trip.

**The number-theoretic transform.** One transform modulo the prime 998244353, the exact stand-in for the Fourier transform with no float formed and no root of unity approximated. `exact_translation_by_ntt.py` recovers a translation by NTT convolution and agrees to the digit with the direct correlation. `ntt_double_transform_inverts.py` shows the transform applied twice is a reflection. The transform is its own inverse up to reversal and scale, and `ntt_twiddle_certificate.py` certifies the prime, the primitive root and the order it rests on.

**Layout and space-filling bijections.** Every render layout is a bijection on the cell index, computed in integers and checked for zero collisions by `bench_raster`: four for a sheet (rows, serpentine, columns, diagonal) and four for a volume (slabs, boustrophedon, Morton, helix). The partition carries the same idea for reading, a Morton interleave and a Hilbert curve that fold any number of dimensions through one without being told the shape.

**Representation embeddings.** A row-major file goes back into the plane it came from given its width. A re-seating renumbers the alphabet so its values spread as little as any numbering allows. Exact decimal ingestion keeps every digit the source wrote as an integer pair and forms no float. A Gray-coded embedding places any corpus as points in a binary volume, one bit changing between neighbors.

**Exact codes.** A redundant residue number system carries an integer as residues over coprime moduli and reconstructs it by the Chinese remainder theorem, the extra moduli making it detect error. Hamming(7,4) carries four data bits as seven and corrects one flip.

**Reference backgrounds.** A maximum-entropy background is built by a transform that deletes a property. A permutation or block shuffle draws the null the whole engine measures against, a phase fold groups positions congruent modulo a period and reassembles them, and a windowed median and a self-similar context map each build a background by nearness or by shared context.

**The image transform program.** `theory/theory/image_transforms` is a book of exact image transforms: translation, rotation with scale and perspective, observed motion, and waves on a surface. Translation is built, and it is the number-theoretic transform above. The rest are stated in the book and not yet implemented in the tree, and the book says which is which.

The full set lives one per file under `src/engine/python/` and in the C renderer, and the workbook records what each has been shown to do. A defensible count is eleven invertible transform families, or seventeen if every render layout is counted on its own, beside several one-way maps.

## The sift

`src/engine/c/engine/anchor_sift.c` builds and runs with a C11 compiler alone. It is the whole engine in one translation unit: the search, the steering that places its probes, and the scan underneath both. The Python in `src/engine/python/sift/` implements the same construction, shares no code with it, and the two are checked against each other by agreeing on counts.

**It is a sound filter.** A subset of a pattern's points is a necessary condition. No arrangement of anchors can lose a true occurrence. That is a proof, using no order, no dimension and no alphabet. The measurement beside it: across 35 rows of corpora, needle lengths and strides, no search ever reported fewer occurrences than exist. Errors are one directional. A discrepancy is always an over-count and is detectable without knowing the answer.

**It carries `m` bits of state**, for a pattern of length `m`, independent of alphabet and dimension. Nothing is indexed and no table is built over the alphabet. A real-valued or unenumerable alphabet therefore costs it nothing. That is a capability claim and it is separate from any speed claim.

**It searches with no pattern at all.** Given only bytes it recovered a multiple of a record period from 512 reads, at 92 shifts against 0 on a shuffle of the same bytes.

**The kernel dispatches, and grades itself.** `anchor_sift_choose` picks an engine from the field's own census, which one histogram pass already produced. The comparison is exact integer arithmetic and the engine holds no floating point value anywhere: the effective alphabet `2^H2` is `total^2 / sum(count^2)`. Asking whether it reaches 85 percent of the symbols the field uses clears its denominators into `100*total^2 >= 85*distinct*sum(count^2)`. `bench_dispatch` times every engine, prints what the dispatcher chose beside what was fastest, and scores six candidate rules against each other. Over 42 rows the rule the kernel carries names the faster engine 39 times on x64 MSVC 19.44 at Release, giving up 9131790 cycles or 0.035 of the worst rule, and 41 times under gcc on the same machine, giving up 86511 cycles or 0.000. That is a hundredfold gap in the cycles figure and it is not rounding. Both are real runs, and each number belongs to the toolchain that produced it. That is why the bench exists, and why its output is a recommendation to act on and not a figure to quote. It sweeps its threshold instead of assuming it: the interval 0.34 to 0.96 all score identically and the 0.85 the kernel carries sits inside it.

**The needle length term in the shipped rule does nothing on this data.** Scoring flatness alone ties the kernel exactly, same rows and same cycles. The length term changes no answer on any of the 42. The rule as documented, flatness then length, scores strictly worse than the flatness it contains, and the rule as originally shipped, length alone, is worse than both. A tunable with no reader is an integration point and is neither removed nor described as unimplemented. It is named here and kept until a row is found where it pays.

Cycles given up is the score that matters, and it inverts the row count. Always taking the free order engine is right on 17 rows of 42, the fewest of any rule on the board, and it still gives up fewer cycles than always taking the short circuiting one, which is right on 25. Counting rows treats a row where the engines differ by one percent the same as one where they differ threefold. A rule can be wrong more often and cost less.

The dispatcher is still blind in one direction, and the blindness is a property of the statistic. A period-16 counter uses sixteen symbols evenly. Its collision entropy reads 4.0 and a perfectly structured corpus looks memoryless. Collision entropy is permutation invariant and cannot see an arrangement, and the dispatcher inherits that exactly. Going exact removed the rounding, not the blindness. Reading arrangement needs a different quantity, and `anchor_sift_anchors_for` is where one entered: it takes the period the corpus repeats at and drops to a single anchor, because at a known period every anchor after the first tests the same congruence and refutes nothing new.

### Building it, and what each tool answers

One command from a fresh clone. It needs `cmake` and a C11 compiler on `PATH`. There is no network step, no submodule to fetch, no generator to run first, and no library outside the C standard headers.

```sh
maint/engine/build_engine.sh               # configure, build, run the graders
maint/engine/build_engine.sh --build-only  # configure and build, run nothing
```

Windows PowerShell uses `maint/engine/build_engine.ps1`, and `-BuildOnly` in place of `--build-only`. It imports the MSVC environment and compiles the device rasterizer. The shell script run from Git Bash has no MSVC environment. It pins the build to gcc or clang and says so. Output lands in `build/engine_c/` and nothing reads it back. Delete it freely.

Both scripts share that directory, and a CMake cache outranks anything a script prints. Each one now passes the decisive settings on every configure and wipes a cache naming a different toolchain, because the alternative was observed: after a Git Bash run, the PowerShell script announced the MSVC environment and the device arm and then produced a gcc build with no CUDA in it, and every render row read `host only` while the script reported success. The PowerShell script now checks the configure for a CUDA compiler before it builds and fails if the announcement does not hold.

A machine with a card should render on it without being asked, and `bench_raster` prints `device rasterizer: present` and grades all twenty configurations `host/device identical` when it does.

Two questions, two directories, and they are not the same question. `test/engine/` answers whether the engine is right. `src/engine/c/bench/` answers how fast it is. A failing test is a defect; a slow bench is a cost.

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
| `bench_lattice`                   | soundness in one to eight dimensions, over a rotated point set and a scatter no rectangle covers. It holds its own core, because what is under test is the construction and not the byte specialization.                                                                                                   |

**The counted build and the timed build are different binaries and cannot be mixed.** `bench_scaling_reads` links the kernel compiled with `ANCHOR_SIFT_COUNT_READS=1`; `bench_scaling_cycles` links the kernel compiled without it. Counting perturbs the timing it would otherwise be reported beside. A driver calling `anchor_sift_counters_reset` therefore fails to link against the timed kernel, and that failure is deliberate.

**Known gap:** `bench_lattice` needs C99 `_Complex` arithmetic and does not build under MSVC, which supplies the types without the operators. Build it with GCC or Clang. Every other target in the table was built and run on MSVC 19.44 x64 at Release. The GCC and Clang paths are exercised by the same CMake file and were not re-run for this note.

### Rendering the object, flat and solid

The renderer draws the object under examination straight from engine state. What it shows is what the search saw. Two surfaces, and they are separate because a sheet and a block are different maps and not the same one at two sizes. `docs/rendering.md` covers both.

`AnchorRasterConfig` renders a sheet: `width` by `height`, one of four layouts, one of five channels, a reduce rule for cells several alignments land on, and a gain. `AnchorVolumeConfig` renders a block: `width` by `height` by `depth`, one of four volume layouts, and the same five channels, the same two reduce rules and the same gain, named by reference to the same enums, because a channel means one thing in this tree.

| volume layout   | what it is for                                                                                                                                                                                                        |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `slabs`         | fills a sheet, then the sheet behind it. The three dimensional reading of the row layout.                                                                                                                             |
| `boustrophedon` | every other row and every other slab reversed. Consecutive alignments stay adjacent across both boundaries.                                                                                                           |
| `morton`        | interleaves the bits of x, y and z, preserving locality on all three axes at once. This reads as a solid instead of as stacked sheets. Needs power of two extents and refuses others instead of remapping quietly.                                 |
| `helix`         | each slab's rows shifted by its depth index. A feature at a fixed corpus offset winds through the block. A shear and not a rotation, because a true helix needs trigonometry and this renderer is integer throughout. |

Every layout is a bijection on the cell index, computed in integers. `bench_raster` checks that instead of stating it: it maps every alignment through every layout at every channel and counts collisions, which must be zero. A layout that quietly folded two alignments together would still draw a plausible picture and no other check would notice.

Netpbm has no volume container. `anchor_volume_write_raw` writes the block as raw bytes, x fastest, and puts the extents, the layout, the channel, the reduce rule and the gain in a `.txt` sidecar naming the function that generated it. Any volume viewer that reads raw unsigned 8 bit will open it given those three numbers.

**The device renders both sheets and volumes, and prefers the device where it is present.** `anchor_raster_render` and the volume renderer both prefer the device. `anchor_volume_device_available` returns 1 where a device is present and the build carries the device volume kernel, and 0 otherwise. It never reports a stub as present, and `anchor_volume_render_host` stays host only and is named so. `bench_raster` grades the device against the host voxel for voxel and prints `device rasterizer: present` when it has one. Nothing falls back silently, because a stub reporting itself present is the defect this tree spent a day removing.

## Ports

The permutation null measure on its own is the part a statistician or corpus linguist reaches for.

| language          | file                                           | status                                                                       |
| ----------------- | ---------------------------------------------- | ---------------------------------------------------------------------------- |
| Python            | `src/engine/python/`                           | the reference every figure came out of                                       |
| R                 | `evidence/sims/r/departure.R`                  | runs, checked against the reference                                          |
| MATLAB and Octave | `evidence/sims/matlab/anchor_sift_departure.m` | run on Octave 11.3.0, inside the reference floor; MATLAB proper not run here |

A port is correct when it lands inside the reseeding floor of the Python, since each language draws its null from a different generator and none can agree to the last digit. Checked on 200000 symbols over twelve seeds: a clustered sequence reads 0.4228 in Python and 0.4282 in R against a floor of 0.0092, and a memoryless one reads 0.9953 and 0.9933 against a floor of 0.0044. Both gaps sit at about half a floor.

## What it knows

Nothing. There is no model, no training, no corpus of examples, no prior. It has no knowledge of language, chemistry or images and never acquires any. It computes one distance and every result came out of that.

It runs on human timescales: seconds on a laptop against a database somebody else published. Its reach is unbounded, because it assumes nothing about the domain and needs only that the object is not already at maximum entropy. Every single reading is finite and carries a stated floor. Where the floor is not cleared, the honest answer is that nothing was read.

## Whose language this is

The largest language corpus, and the one everything else in the languages category is currently measured against, is Salishan speech, which was written down by a linguist or their transcriber in almost all cases.

**This work does not exist without the speakers.**

Every table in the Salishan corpus opens with the person who spoke, before the linguist who published and before anyone who read it into a file.
Where a paper cites a published dictionary and never says who spoke, its entry says so.
The Salishan theory book carries that index, written speaker first.

The rationale is simple:

1.  A linguist wrote the paper.
2.  A person read the paper into a table.
3.  Neither of those is whose language it is in almost every case.
4.  Here, and for any derivative, you must list the person who was teaching us about their language first.
5.  It's fair.
6.  It acknowledges their contribution.
7.  It makes performing meta-analysis about the language itself vs. the linguist or transcriptionist's style far less cumbersome over time.
    **here, respect is identical to research efficiency**

## The condition of use

These tools read a language and can put one back.
`to_phonemes.py`, `encode_percussive.py` and the sound representation work do what they are named for, and `regeneration_limit.py` measures how much of a source a regeneration recovers.
Saying otherwise would be a false claim about the code, and a safeguard resting on a false claim is not a safeguard.

Regeneration is faithful near the subject and escapes it with distance.
Close to the center of mass of the subject the output is a copy.
Move outward and it carries more, until at some distance it leaves the source distribution and is no longer that language.
Past that it becomes obvious nonsense and nobody is fooled.

Immediately before that boundary is a narrow band where the output is still coherent and may already not be the language.

**Nothing here marks which side of it a result fell on.**

That band is where a native speaker belongs.
The question there is _is this mine_, which is a question of anthropology, of philosophy, and for many communities of what is sacred.
No amount of measurement turns it into a question an algorithm can answer.

**Every tool for language that comes out of this work requires a human to review its output.**

That is a condition of use, not a recommendation.
For a language with few remaining speakers, publishing a form drawn from outside the distribution as though it were the language is not a recoverable harm.

## Where to start reading

The research is seventeen books under `theory/`, built with XeLaTeX. One command builds all of them:

```sh
sh maint/texbuild/build_theory.sh
```

| you want                                                                          | book                                     |
| --------------------------------------------------------------------------------- | ---------------------------------------- |
| the construction, the method, and what is settled, open or withdrawn              | `theory/workbooks/anchor_sift`            |
| valence read as a necessary condition, and where the oracle enters                | `theory/theory/chemistry`                       |
| a domain that supplies its own answers, and the reading it corrected              | `theory/theory/game_theory`                     |
| the image transform program, exact, and which of the transforms is built          | `theory/theory/image_transforms`                |
| particles as exact charges and shells, and what a quantum number costs            | `theory/theory/particle_physics`                |
| the information theory under the nulls, and the survey of viewers                 | `theory/theory/apparatus`                  |
| a lit set on a sphere read as a boundary, and how deep into the rounds it reaches | `theory/theory/boundary`                   |
| what the instruments cannot see, how they failed, and how to aim them             | `theory/theory/instruments`                |
| whose words the corpus holds, and how wrong it could be                           | `theory/theory/Salishan`                        |
| the posits whose experiment cannot be built                                       | `theory/thought_experiments/anchor_sift`             |
| a published cell edge read back off a voxel grid, and whose result that is        | `theory/theory/crystallography`                 |
| where the structure in SHA-256 is, where it stops, and how each null was measured | `theory/theory/cryptography/sha256`             |
| exact arithmetic, the natural constants and the residue codes                     | `theory/theory/precision`                       |
| the null, its delta, and where the two reconcile                                  | `theory/theory/delta_null`                      |
| the corpus, the state of the field, and what this toolkit reaches                 | `theory/theory/millennium`                      |
| the cell tracking engine's ledger: each claim with the status that backs it       | `theory/workbooks/cell_tracking`                   |
| the cell tracking thought experiments, kept as they were written                  | `theory/thought_experiments/cell_tracking` |

To read the code instead of the argument, start with `src/engine/python/README.md`, then `examples/README.md`, then `examples/any_corpus/`.

## What is not here

The corpora, papers, audio and rendered pages run to about 1.9 GB and none of it is in git. `maint/data/salishan/get_papers.py` fetches the papers from the public archive, `maint/data/fetch/` fetches the other corpora, and the tools rebuild the rest.

The hand extractions are forms transcribed out of published papers. The tables are those papers' text and not this work's to redistribute.
They live in a closed repository with the papers, inventoried and signed, and reach a checkout through `maint/corpus/verify_private_sync.py`.
Everything that does not read a paper or a table runs without them.

## Licensing

Every source file carries this header:

```
SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
```

Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a negotiated commercial licensing contract or an educator's license issued to you personally. It will always be free to use under the AGPL.

| license                  | text                                                                                     | terms                                                                      |
| ------------------------ | ---------------------------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `AGPL-3.0-or-later`      | [`LICENSES/AGPL-3.0-or-later.txt`](LICENSES/AGPL-3.0-or-later.txt), also [`LICENSE`](LICENSE) | the GNU Affero General Public License, version 3 or any later version |
| `LicenseRef-Commercial`  | [`LICENSES/LicenseRef-Commercial.txt`](LICENSES/LicenseRef-Commercial.txt)               | a negotiated commercial contract                                           |
| `LicenseRef-Educational` | [`LICENSES/LicenseRef-Educational.txt`](LICENSES/LicenseRef-Educational.txt)             | an educator's license, issued in writing to a named person                 |

Educators: for an exception to use this in classrooms or research projects, email dstroy0 (Douglas Quigg) <dquigg123@gmail.com> from your `.edu` or `.org` faculty address.
Exceptions are granted case by case and govern your use, specifically the accreditation requirement of underlying systems in research or presentation materials.
Where an academic exemption leads to a viable market product the license shifts to a royalty ladder, set off the goodwill shown and how well students and other faculty were credited.
A portion goes to your institution at a minimum, and straight to your department where their rules allow.

**Every license already offered for this work under MMgr transfers here on the same terms.**
Nobody holding one needs to do anything and no term changes because the files moved. `LICENSE` and `LICENSES/` are the same files that tree carries.

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## A note on how this is written

1. The workbook always keeps its own corrections.
   - Claims that were withdrawn stay on the page with the measurement that killed them.
   - A document recording only what survived is not evidence.
2. Several results are rediscoveries of published work, and where that is known the precedent is named.
   - Citation is ongoing, any corrections are appreciated and welcome, and attribution is critical.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-22
