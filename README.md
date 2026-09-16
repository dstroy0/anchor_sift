# Anchor sift: an algorithm for precision measurement

**Purpose:** Find an object's information entropy.
**Scope:** `src/`, `data/`, `analysis/`, `maint/`, `examples/`, `evidence/`, `theory/`

## Contents

1. [The algorithm](#the-algorithm)
2. [Areas of research](#areas-of-research)
3. [Where things are](#where-things-are)
4. [Two instruments, and they are not interchangeable](#two-instruments-and-they-are-not-interchangeable)
5. [The sift](#the-sift)
6. [Ports](#ports)
7. [What it knows](#what-it-knows)
8. [Whose language this is](#whose-language-this-is)
9. [The condition of use](#the-condition-of-use)
10. [Where to start](#where-to-start)
11. [What is not here](#what-is-not-here)
12. [Licensing, dual](#licensing-dual)
13. [A note on how this is written](#a-note-on-how-this-is-written)

## The algorithm

Measure how far something sits from the most disordered arrangement of its own parts. (Shannon's information entropy)

That is the most basic construction. 

Every domain below is that sentence with a different answer to what counts as a part: 
- atoms in a cell
- symbols in a corpus
- bytes in a file
- coordinates in a board layout

The reference is built from the object's own parts, there is no prior to estimate, no training set, no model, or neural net representation of the domain.

Building a reference by maximizing entropy under the constraints the object supplies is Jaynes's principle. The departure from it is the free energy above equilibrium.

The basic construction Identity:Null Permutation runs through all six parts. Represent the object as points carrying values, fix a partition over those points, build the maximum entropy reference that partition allows, and read the departure from it. The sift and the oracle sit either side, one discarding candidates and one supplying an answer from outside the sample.

| part | what it does |
|---|---|
| `representation` | any domain written as points carrying values, and the re-seatings that put one symbol in one place |
| `partition` | the unit(s) and the scale those points are read at |
| `reference` | the maximum entropy background under the constraints the object supplies |
| `measure` | the departure from that background |
| `sift` | the sound filter, a necessary condition over any index set |
| `oracle` | agreement with ground truth that somebody else published |

Everything downstream of `representation` sees points and values and is blind to what an object is, so one instrument reads both. Four subjects have their own directories: `text`, `sound`, `picture` and `structure`, all under `representation`, the only part that knows a domain exists.

`src/engine/python/README.md` is the map. `examples/` runs the same six names end to end on real corpora.

## Areas of research

Seven domains have been run end to end under `examples/`: language, art, crystals, proteins, sound, source code and arbitrary corpora. The proofs that pin the numbers are under `evidence/proofs/`. The same six parts test each other end-to-end and agree.

Published cell edges from the Crystallography Open Database, tiled and voxelized and handed over with nothing told to the detector, come back three of three exact, to 0.0006 angstroms against a voxel of 0.25. No other positive control here took its answer from outside the work.

A dialect border inside Lushootseed, labeled by Mellesmoen and Kye and then held out, comes back as the stressed schwa, southern, beaten by 1 of 200 random borders over the same forms.

An image read as a byte sequence returns its own width. A Vigenère cipher returns its key length. A protein backbone returns bond lengths of 1.45, 1.52 and 1.33 against chemistry's 1.46, 1.52 and 1.33. None of them was told anything.

The workbook holds the rest, including every row that failed and why.

## Where things are

Each directory serves one purpose, things are in disarray currently.

| | what it operates on | |
|---|---|---|
| `src/` | points and values, no domain | the engine |
| `evidence/` | the claims | the proofs, and the R and MATLAB ports |
| `data/` | external material | fetchers, and the Salishan pipeline |
| `analysis/` | a corpus, through `src/` | surveys the books ask for |
| `examples/` | a corpus, through `src/` | 99 numbered demonstrations, seven domains |
| `maint/` | the repository itself | records, gates, prose checks, the book build |
| `theory/` | the argument | seven books |
| `docs/` | the reader | setup and usage |

`build/` is generated and disposable, and nothing irreplaceable is reachable through it.

## Two instruments, and they are not interchangeable

Most of the confusion this work has had to correct came from reporting one as the other.

| | what it reads | external ground truth |
|---|---|---|
| shift agreement detector | a period or an offset, from how often a shift agrees with itself | three times, from published crystal cell edges |
| permutation null measure | a departure from the maximum entropy arrangement of the same multiset | none |

The permutation null measure carries most of the findings and has only been shown not to invent structure on memoryless input. Read the workbook before quoting any row of it.

## The sift

`src/engine/c/portable/anchor_sift.c` builds and runs with a C11 compiler alone. It is the whole engine in one translation unit: the search, the steering that places its probes, and the scan underneath both. The Python in `src/engine/python/sift/` implements the same construction, shares no code with it, and the two are checked against each other by agreeing on counts.

**It is a sound filter.** A subset of a pattern's points is a necessary condition, so no arrangement of anchors can lose a true occurrence. That is a proof, using no order, no dimension and no alphabet. The measurement beside it: across 35 rows of corpora, needle lengths and strides, no search ever reported fewer occurrences than exist. Errors are one directional. A discrepancy is always an over-count and is detectable without knowing the answer.

**It carries `m` bits of state**, for a pattern of length `m`, independent of alphabet and dimension. Nothing is indexed and no table is built over the alphabet. A real-valued or unenumerable alphabet therefore costs it nothing. That is a capability claim and it is separate from any speed claim.

**It searches with no pattern at all.** Given only bytes it recovered a multiple of a record period from 512 reads, at 92 shifts against 0 on a shuffle of the same bytes.

**The kernel dispatches, and grades itself.** `anchor_sift_choose` picks an engine from the field's own census, which one histogram pass already produced. The comparison is exact integer arithmetic and the engine holds no floating point value anywhere: the effective alphabet `2^H2` is `total^2 / sum(count^2)`, so asking whether it reaches 85 percent of the symbols the field uses clears its denominators into `100*total^2 >= 85*distinct*sum(count^2)`. `bench_dispatch` times every engine, prints what the dispatcher chose beside what was fastest, and scores six candidate rules against each other. Over 42 rows the rule the kernel carries names the faster engine 39 times on x64 MSVC 19.44 at Release, giving up 9131790 cycles or 0.035 of the worst rule, and 41 times under gcc on the same machine, giving up 86511 cycles or 0.000. That is a hundredfold gap in the cycles figure and it is not rounding. Both are real runs and the number belongs to the toolchain that produced it, which is why the bench exists and why its output is a recommendation to act on rather than a figure to quote. It sweeps its threshold instead of assuming it: the interval 0.34 to 0.96 all score identically and the 0.85 the kernel carries sits inside it.

**The needle length term in the shipped rule does nothing on this data.** Scoring flatness alone ties the kernel exactly, same rows and same cycles, so the length term changes no answer on any of the 42. The rule as documented, flatness then length, scores strictly worse than the flatness it contains, and the rule as originally shipped, length alone, is worse than both. A tunable with no reader is an integration point and is neither removed nor described as unimplemented, so it is named here and kept until a row is found where it pays.

Cycles given up is the score that matters, and it inverts the row count. Always taking the free order engine is right on 17 rows of 42, the fewest of any rule on the board, and it still gives up fewer cycles than always taking the short circuiting one, which is right on 25. Counting rows treats a row where the engines differ by one percent the same as one where they differ threefold, so a rule can be wrong more often and cost less.

The dispatcher is still blind in one direction, and the blindness is a property of the statistic. A period-16 counter uses sixteen symbols evenly, so its collision entropy reads 4.0 and a perfectly structured corpus looks memoryless. Collision entropy is permutation invariant and cannot see an arrangement, and the dispatcher inherits that exactly. Going exact removed the rounding, not the blindness. Reading arrangement needs a different quantity, and `anchor_sift_anchors_for` is where one entered: it takes the period the corpus repeats at and drops to a single anchor, because at a known period every anchor after the first tests the same congruence and refutes nothing new.

### Building it, and what each tool answers

One command from a fresh clone. It needs `cmake` and a C11 compiler on `PATH`. There is no network step, no submodule to fetch, no generator to run first, and no library outside the C standard headers.

```sh
maint/engine/build_engine.sh               # configure, build, run the graders
maint/engine/build_engine.sh --build-only  # configure and build, run nothing
```

Windows PowerShell uses `maint/engine/build_engine.ps1`, same two forms, and it is the one to reach for on Windows: it imports the MSVC environment and compiles the device rasterizer. The shell script run from Git Bash has no MSVC environment, so it pins the build to gcc or clang and says so. Output lands in `build/engine_c/` and nothing reads it back, so delete it freely.

Both scripts share that directory, and a CMake cache outranks anything a script prints. Each one now passes the decisive settings on every configure and wipes a cache naming a different toolchain, because the alternative was observed: after a Git Bash run, the PowerShell script announced the MSVC environment and the device arm and then produced a gcc build with no CUDA in it, and every render row read `host only` while the script reported success. The PowerShell script now checks the configure for a CUDA compiler before it builds and fails if the announcement does not hold.

A machine with a card should render on it without being asked, and `bench_raster` prints `device rasterizer: present` and grades all twenty configurations `host/device identical` when it does.

Two questions, two directories, and they are not the same question. `test/` answers whether the engine is right. `bench/` answers how fast it is. A failing test is a defect; a slow bench is a cost.

| run this | it answers |
|---|---|
| `test_arm_agreement` | every engine against the naive one at the lengths that bound the input: none, one, two. A disagreement is a defect whatever it measures. |
| `test_adversarial` | twelve cases built to break the guarantee from outside the public surface: overlapping occurrences, both boundary alignments, a field where every survivor is false, a permutation null, and the probe guard including the widest line that must be admitted. |
| `test_steer` | the steering, on five fields. Grades the ordering at seven needle lengths, carries a negative control ordering the commonest symbol first that must read MORE, checks the exact dispatch against four fields worked out by hand, and asserts that the widest scan engine the machine carries actually ran. |
| `bench_dispatch` | which dispatch rule to carry, scored against the clock over 42 rows, sweeping its threshold instead of assuming it. |
| `bench_steer_arms` | the scan engines graded against the portable one and then timed, at lengths straddling the thirty-two lane boundary where a vectorized tail fails if it is going to. |
| `bench_scaling_reads` | reads per alignment as the corpus grows. Reads travel between machines and are what an asymptotic claim is made of. |
| `bench_scaling_cycles` | the same sweep in cycles, which belong to the machine that produced them. |
| `bench_coherence` | at what scale the corpus agrees with itself, and what that costs the histogram bound. |
| `bench_raster` | every render configuration. Four sheet layouts by five channels, each written as a PGM and graded host against device byte for byte where a device is present, then four volume layouts by the same five channels into a 32 by 32 by 32 block. |
| `bench_exact`, `bench_exact_arms` | the fixed width limb arithmetic, and every vectorized limb engine against the portable one. |
| `bench_lattice` | soundness in one to eight dimensions, over a rotated point set and a scatter no rectangle covers. It holds its own core, because what is under test is the construction and not the byte specialization. |

**The counted build and the timed build are different binaries and cannot be mixed.** `bench_scaling_reads` links the kernel compiled with `ANCHOR_SIFT_COUNT_READS=1`; `bench_scaling_cycles` links the kernel compiled without it. Counting perturbs the timing it would otherwise be reported beside. A driver calling `anchor_sift_counters_reset` therefore fails to link against the timed kernel, and that failure is deliberate.

**Known gap:** `bench_lattice` needs C99 `_Complex` arithmetic and does not build under MSVC, which supplies the types without the operators. Build it with GCC or Clang. Every other target in the table was built and run on MSVC 19.44 x64 at Release for this note. The GCC and Clang paths are exercised by the same CMake file and were not re-run here.

### Rendering the object, flat and solid

The renderer draws the object under examination straight from engine state, so what it shows is what the search saw. Two surfaces, and they are separate because a sheet and a block are different maps rather than the same one at two sizes.

`AnchorRasterConfig` renders a sheet: `width` by `height`, one of four layouts, one of five channels, a reduce rule for cells several alignments land on, and a gain. `AnchorVolumeConfig` renders a block: `width` by `height` by `depth`, one of four volume layouts, and the same five channels, the same two reduce rules and the same gain, named by reference to the same enums so a channel means one thing in this tree.

| volume layout | what it is for |
|---|---|
| `slabs` | fills a sheet, then the sheet behind it. The three dimensional reading of the row layout. |
| `boustrophedon` | every other row and every other slab reversed, so consecutive alignments stay adjacent across both boundaries. |
| `morton` | interleaves the bits of x, y and z, preserving locality on all three axes at once. This is the one that reads as a solid instead of as stacked sheets. Needs power of two extents and refuses others rather than remapping quietly. |
| `helix` | each slab's rows shifted by its depth index, so a feature at a fixed corpus offset winds through the block. A shear and not a rotation, because a true helix needs trigonometry and this renderer is integer throughout. |

Every layout is a bijection on the cell index, computed in integers. `bench_raster` checks that rather than stating it: it maps every alignment through every layout at every channel and counts collisions, which must be zero. A layout that quietly folded two alignments together would still draw a plausible picture and nothing else would notice.

Netpbm has no volume container, so `anchor_volume_write_raw` writes the block as raw bytes, x fastest, and puts the extents, the layout, the channel, the reduce rule and the gain in a `.txt` sidecar naming the function that generated it. Any volume viewer that reads raw unsigned 8 bit will open it given those three numbers.

**The device renders sheets and does not render volumes.** `anchor_raster_render` prefers the device and `bench_raster` prints `device rasterizer: present` when it has one. There is no device volume kernel, `anchor_volume_device_available` returns 0 on every build, and `anchor_volume_render_host` is host only and named so. It does not fall back silently, because a stub reporting itself present is the defect this tree spent a day removing.

## Ports

The permutation null measure on its own is the part a statistician or corpus linguist reaches for.

| language | file | status |
|---|---|---|
| Python | `src/engine/python/` | the reference every figure came out of |
| R | `evidence/sims/r/departure.R` | runs, checked against the reference |
| MATLAB and Octave | `evidence/sims/matlab/anchor_sift_departure.m` | logic checked, not executed here |

A port is correct when it lands inside the reseeding floor of the Python, since each language draws its null from a different generator and none can agree to the last digit. Checked on 200000 symbols over twelve seeds: a clustered sequence reads 0.4228 in Python and 0.4282 in R against a floor of 0.0092, and a memoryless one reads 0.9953 and 0.9933 against a floor of 0.0044. Both gaps sit at about half a floor.

## What it knows

Nothing. There is no model, no training, no corpus of examples, no prior. It has no knowledge of language, chemistry or images and never acquires any. It computes one distance and every result came out of that.

It runs on human timescales: seconds on a laptop against a database somebody else published. Its reach is unbounded, because it assumes nothing about the domain and needs only that the object is not already at maximum entropy. Every single reading is finite and carries a stated floor. Where the floor is not cleared, the honest answer is that nothing was read.

## Language research: Whose language this is

The largest language corpus, and the one everything else in the languages category is currently measured against is Salishan speech, which was written down by a linguist or their transcriber in almost all cases. 

**This work does not exist without the speakers.**

Every table in the Salishan corpus opens with the person who spoke, before the linguist who published and before anyone who read it into a file. 
Where a paper cites a published dictionary and never says who spoke, its entry says so. 
The Salishan theory book carries that index, written speaker first.

The rationale is simple: 
   1. A linguist wrote the paper.
   2. A person read the paper into a table.
   3. Neither of those is whose language it is in almost every case.
   4. Here, and for any derivative, you must list the person who was teaching us about their language first.
   5. It's fair.
   6. It acknowledges their contribution.
   7. It makes performing meta-analysis about the language itself vs. the linguist or transcriptionist's style far less cumbersome over time.
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
The question there is *is this mine*, which is a question of anthropology, of philosophy, and for many communities of what is sacred. 
No amount of measurement turns it into a question an algorithm can answer.

**Every tool for language that comes out of this work requires a human to review its output.** 

That is a condition of use, not a recommendation. 
For a language with few remaining speakers, publishing a form drawn from outside the distribution as though it were the language is not a recoverable harm.

## Where to start

The research is seven books under `theory/`. Build them:

```sh
sh maint/texbuild/build_theory.sh
```

| you want | book |
|---|---|
| the construction, the method, the vocabulary | `theory/anchor_sift` |
| what is settled, what is open, what was withdrawn | `theory/workbook` |
| whose words the corpus holds, and how wrong it could be | `theory/Salishan` |
| the posits whose experiment cannot be built | `theory/thought_experiments` |
| a published cell edge read back off a voxel grid, and whose result that is | `theory/crystallography` |
| where the structure in SHA-256 is, where it stops, and how each null was measured | `theory/cryptography/sha256` |
| the corpus, the state of the field, and what this toolkit reaches | `theory/millennium` |

## What is not here

The corpora, papers, audio and rendered pages run to about 1.9 GB and none of it is in git. `maint/data/salishan/get_papers.py` fetches the papers from the public archive and the tools rebuild the rest.

The hand extractions are forms transcribed out of published papers, so the tables are those papers' text and not this work's to redistribute. 
They live in a closed repository with the papers, inventoried and signed, and reach a checkout through `maint/corpus/verify_private_sync.py`. 
Everything that does not read a paper or a table runs without them.

## Licensing, dual

Licensed AGPL-3.0-or-later, with commercial contracts available. It will always be free to use under the AGPL.

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
   - citation is ongoing, any corrections are appreciated and welcome, attribution is critical.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-11
