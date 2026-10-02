# Orior: an algorithm for precision measurement

**Purpose:** Find an object's information entropy, and compile the program that measures it to any part.
**Scope:** `src/`, `utils/test/`, `utils/bench/`, `utils/maint/`, `examples/`, `evidence/`, `docs/`, `theory/`

## Contents

1. [Quick start](#quick-start)
2. [The algorithm](#the-algorithm)
3. [The engine](#the-engine)
4. [The language: gnascor](#the-language-gnascor)
5. [The transpiler](#the-transpiler)
6. [The files](#the-files)
7. [Compression](#compression)
8. [No bounding, no tuning](#no-bounding-no-tuning)
9. [Areas of research](#areas-of-research)
10. [Where things are](#where-things-are)
11. [The detector and the measure are not the same reading](#the-detector-and-the-measure-are-not-the-same-reading)
12. [The transforms](#the-transforms)
13. [The sift](#the-sift)
14. [Ports](#ports)
15. [What it knows](#what-it-knows)
16. [Whose language this is](#whose-language-this-is)
17. [The condition of use](#the-condition-of-use)
18. [Where to start reading](#where-to-start-reading)
19. [What is not here](#what-is-not-here)
20. [Licensing](#licensing)
21. [A note on how this is written](#a-note-on-how-this-is-written)

## Quick start

From a fresh clone, at the repository root:

```sh
utils/maint/engine/build_engine.sh                                      # the C engine: configure, build, run the graders
python examples/any_corpus/4_measure/collision_entropy.py         # a reading that knows nothing about its corpus
python examples/crystallography/6_oracle/proof_positive_control.py  # the positive control, against published cells
sh utils/maint/texbuild/build_theory.sh                                 # the research papers
```

On Windows PowerShell the engine builds with `utils/maint/engine/build_engine.ps1`. Most examples read corpora under `build/`, which are not in git: `utils/maint/data/fetch/` fetches them. `docs/setup.md` and `docs/usage.md` cover the rest.

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

Each part is an import name in `src/python/manifest.tsv`, beside `instrument` and `render`. One row a name: the name a program imports, and the path under `src/python/` that answers it. A program puts `src/python/` on its path and imports `manifest` first. Everything downstream of `representation` sees points and values and is blind to what an object is. One instrument reads both. Seven subjects have their own directories under `representation`, the only part that knows a domain exists: `atom`, `game`, `particle`, `picture`, `sound`, `structure` and `text`. `representation.constants` derives the natural constants, each by two routes agreeing.

`src/python/README.md` is the map. `examples/` runs the same six names end to end on real corpora, one stage directory per part.

## The engine

The engine is the machine every measurement above runs on, in C under `src/c/`, its device code under `src/cu/`, and its simulations under `src/sims/`. [engine_table.md](theory/workbooks/engine/engine_table.md) holds it part by part: what each part computes, the exact algebra it holds to, what it does today, what it wants, every hypothesis tried, its status, and the next move.

**The engine is optimized for no scale.** A size, a spacing, an order, a window, a width, a cell or a voxel count is never written into the machine. Each comes in with the request or is read from the data. The machine is exact at every scale its words can hold, and where a word is too narrow it says so (a request error, or `needed_bits`) and never rounds.

A sample is held as 16-bit lanes over the axes (t, z, y, x), and the atom is all of the thing under inspection, held as one integer. Every value is in ℤ; nothing is rounded.

| step        | from → to               | what happens                                                                                       |
| ----------- | ----------------------- | -------------------------------------------------------------------------------------------------- |
| 1 ingest    | a source → lanes        | read any source format into 16-bit lanes in key order, with its side bytes                         |
| 2 seal      | lanes → signa           | the dimensional Merkle DAG over rows, planes, volumes and lanes, and the witness against the source |
| 3 lift      | lanes ↔ crystal         | the tower lifts the lattice into the stored stream, and lowers it back exactly                     |
| 4 measure   | lattice → fields        | the residual, the moments, the entropy windows                                                     |
| 5 partition | fields → bodies         | the component tree and its cut into bodies                                                         |
| 6 relate    | bodies × frames → links | overlap, matching, motion, division, the links between frames                                      |

| part                           | status                                                                                                    |
| ------------------------------ | --------------------------------------------------------------------------------------------------------- |
| M1. Exact numbers              | built; the engine build takes it from this tree                                                           |
| M2. The residual operator      | proved (exact); the sweeps 2× faster; any input width proved (the planes)                                 |
| M3. The component tree         | built, error-wired                                                                                        |
| M4. The moments                | built, error-wired                                                                                        |
| M5. The correlation operator C | built; the box proved                                                                                     |
| M6. The exact marginal         | built                                                                                                     |
| M7. One-to-one matching        | built                                                                                                     |
| M8. The entropy history        | built, error-wired                                                                                        |
| M9. The files                  | proved: the field, and the RSNA knee as `.kcr`                                                            |
| M10. The record machine        | built, error-wired; the table, register reuse and the division proved; 12 to 17 times the interpreter's speed compiled |
| M11. The golden ladder         | built                                                                                                     |
| M12. Errors and integrity      | wiring in progress                                                                                        |
| M13. The seal                  | built and proved: the crystal and the set                                                                 |
| M14. The scheduler             | ledger, frame, measure and the daemon end to end proved on Windows                                        |
| M15. The sift                  | built and run here on four configurations                                                                 |
| M16. Render                    | built and run here                                                                                        |
| M17. Memory operations         | built; the x86 arms proved, the aarch64 arms built and emitting                                           |
| M18. The period reading        | built, proved against its reference                                                                       |
| M19. The sims                  | built; every sim run recorded here passes every check                                                     |
| M20. The root universal        | built and proved in `tower`; not in the crystal path                                                      |
| M21. The ask and the state     | built as a sim; proved exact on the host                                                                  |
| M22. Exact qubit states        | built; exact on the host; the device code proved, 44 checks, 0 failed                                     |
| M23. The refinement loop       | wanted, not built                                                                                         |
| M24. The ask                   | proved: the ask on the host and in the cell, the gate, the order and its solve; theory: the run channel   |

Every status names the run behind it in the table. `src/README.md` is how to use the engine: its calls and errors, one body on one lattice, n bodies across frames, the record machine with its programs and its config, and tessera, the one daemon per device that admits every process's device jobs.

## The language: gnascor

The objective is to compile a program written in gnascor to any language, including one nobody has met, and prove it is the same program everywhere. Where the language is unknown, the engine derives it by asking. [gnascor.md](src/c/transpiler/gnascor.md) holds the language part by part, and [engine_plan.md](src/engine_plan.md) the open work.

**gnascor** is the internal language, `.g` high order and `.gsm` its assembly. It is designed and it is what a program is written in. It is not derived and its vocabulary does not move. **`L*`** is the map from gnascor to a target's spellings, and it is the derived part.

**Information is coherence.** A description at its Kolmogorov complexity holds no redundancy, every bit of it carries, and no part predicts another. A system at coherence has that property from the other side: its parts agree and the friction between them is at its floor. Compression and coherence are one measurement from two directions.

What is known before meeting anything is relations. `1,1 -> 2` is a relation and is not an addition, because addition is a spelling. Every system that computes agrees about the relation and each spells it its own way.

**The query protocol** is the form every ask takes, and it is what derivation is made of:

    [ ADDRESS ] -> ( QUALIFIER ) -> [ MEASURED COST ] -> BINARY RESULT (1 or 0)

The address names the target: a memory address, a URI, an API endpoint, an LLM context key, a register. The qualifier is a binary question asked at it, phrased to demand a state validation and never a data payload. The cost bound is the most the target may spend to answer, and no hand writes that field. An ask carrying no bound returns the cost instead of a bit. The spread of those costs is the baseline, and every bound after that is expressed against it.

**Gate, then rank. Never one score.** A relation holds or it does not, and that answer carries no noise. A cost is measured and every cost carries noise. The gate decides which candidates are admissible and the rank orders whatever survives, and the two are never added together. [query_protocol_table.md](theory/workbooks/engine/query_protocol_table.md) holds the protocol step by step.

Two branches resolve to a pair, and the pair to a four-letter mnemonic:

| left branch | right branch | pair state | mnemonic | meaning                                                   |
| ----------- | ------------ | ---------- | -------- | --------------------------------------------------------- |
| LEAD (1)    | VOID (0)     | 1, 0       | CORE     | The primary intent persists; the secondary path dissolved. |
| RITE (0)    | LEAD (1)     | 0, 1       | SHIFT    | Focus has migrated from the left domain to the right.     |
| DUAL (2)    | VOID (0)     | 2, 0       | ECHO     | An amplified state is sustained without new external input. |
| DUAL (2)    | DUAL (2)     | 2, 2       | NEXUS    | Maximum systemic coherence; both major systems are aligned. |

## The transpiler

The transpiler is the record machine's programs written for a part, and the asks that learn the part. `keymath` imprints record programs, `key_schedule` lays them out, and `cycle` runs them on the device with a host reference. The code generator writes each program's lane from a ruleset, one `.krs` a language, and every lane the device writes is held word for word against the host's.

| directory                         | what it holds                                                                                                     |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `src/c/transpiler/bootstrap/`     | the query protocol on the host: one ask (`query_ask`), every arrangement of primitives that produces a relation (`chain_build`), and the order of asks (`ask_order`) |
| `src/cu/transpiler/codegen/`      | the code generator's kernels, and its rulesets: `c.krs`, `ptx.krs`, `sass.krs`, `vhdl.krs` and `yosys.krs`         |
| `src/c/transpiler/cubin/`         | one line of SASS turned into the sixteen bytes the part runs, and a cubin written from a kernel's machine code; `machines/sm_86.kdm` and `sm_86.ksc` |
| `src/c/transpiler/emit/`          | one emitter, every container: it reads a layout file and writes what that layout describes                       |
| `src/c/transpiler/interface/`          | the cell, a probe runner: a probe asks the target one question in a child process the cell can lose               |
| `src/c/transpiler/qasm/`          | exact qubit states, read from OpenQASM                                                                            |

The method is to write C source, read the SASS it compiles to, and hold it against what NVIDIA's compiler writes for the same program (Q17). Every slot a `.krs` writes by hand is asked of the part the way `loop_back` is asked of sm_86 (Q16).

## The files

The k-files are the faces the compiler reads and writes.

| suffix | name                                      | holds                                |
| ------ | ----------------------------------------- | ------------------------------------ |
| `.ksc` | Kolmogorov system classification          | the language map                     |
| `.krs` | Kolmogorov information ruleset            | the coherence rules: one language's forms |
| `.kcr` | Kolmogorov information crystal            | information at or near its Kolmogorov complexity |
| `.knf` | Kolmogorov noise floor                    | a measured noise floor               |
| `.kcs` | Kolmogorov information construction set   | what reconstructs information        |
| `.kdm` | Kolmogorov device map                     | the hardware map                     |
| `.g`   | gnascor high order language               | semantic plain language, plus the shortcut operators |
| `.gsm` | gnascor assembly language                 | the same program with the switch thrown |

**The stem is the join and the suffix is the face.** Files sharing a stem are one member's set, whatever the stem happens to be. `pair.kdm` and `pair.knf` are a pair's map and that map's floor. `set.kcr`, `set.kcs` and `set.knf` are one set's crystal, the set that reconstructs it, and its floor. Nothing outside the filename binds them, and no member is required to carry every face.

**`.kcr`**, the crystal, read front to back: head (12 words), the seal (6 roots, every lane node, every chunk leaf), offsets and stream, the deflated side bytes, the member tables and names, EOF. Every file the machine writes is proved by reading it back: pixels voxel for voxel against a second read of the source, and every part by its seal. Integer lifting is exactly invertible.

The ingest readers are zarr v2/v3/N5 with every codec, TIFF, HDF5, npy/npz, NRRD, NIfTI, DICOM, zip and `.stack`. The export writes the crystal back out as any source format: the DICOM zip byte for byte from the side bytes, npy, NIfTI, TIFF and zarr.

## Compression

The true floor is the Kolmogorov complexity K(x) of a set: the length of the shortest program that prints it. K is not computable, and it cannot be measured directly. What can be measured is a ladder of bounds, each one exact for a named class of coder, and each lower than the one before as the coder is allowed to see more. [compression_table.md](theory/workbooks/compression/compression_table.md) holds the ladder set by set.

| rung | the bound                                   | exact for                                                                 |
| ---- | ------------------------------------------- | ------------------------------------------------------------------------- |
| F0   | raw: the source's own bytes                 | nothing; this is the reference every percentage is taken of               |
| F1   | values, order 0                             | any coder that treats the voxels as a bag of values and sees no position  |
| F2   | coefficients, order 0, per floor            | a coder that sees the tower's lifted coefficients floor by floor          |
| F3   | coefficients in context                     | context coders: a coefficient coded given its neighbors                   |
| F3′  | a two-part code                             | a coder that stores a model and then the residue the model does not predict |
| F4   | the noise floor                             | every coder: what is left of one frame after all structure is taken       |
| F5   | the integrated noise functionals            | a coder driven by the functionals' exact counts                           |

Each bound is an integer count of bits, and each is the bit length of an exact integer. Stating it needs no logarithm or float.

| set                                    | `.kcr` bytes                    | of raw | status   |
| -------------------------------------- | ------------------------------- | ------ | -------- |
| RSNA knee, 1 × 34 × 960 × 960 unsigned | 25,218,496                      | 40.2%  | proved   |
| RSNA knee, 1 × 24 × 640 × 640 signed   | 11,319,416                      | 57.5%  | proved   |
| RSNA test_series, 15 of 15             | 192,020,272 of 599,191,552      | 32.0%  | proved   |
| the noise floor (F4) on the 25         | 6.229 bits a voxel              | 38.9%  | measured |

Every crystal is rebuilt voxel for voxel, pixel for pixel and node for node.

## No bounding, no tuning

The method picks no tolerance, no threshold, and no parameter by judgment. Bounding is choosing a cutoff to make a result come out the way it was expected to. It is the failure this work is built to avoid, and it is not permitted anywhere in it.

Every comparison is exact integer arithmetic. The engine holds no floating-point value, and there is no rounding to hide a chosen bound inside. The null a departure is measured against is drawn by permuting the object's own parts, never computed from a formula that could be tuned. Where a reading appears to need a cutoff, the cutoff is swept and the reading is reported across the whole sweep, as a curve. A positive control runs beside every negative result, because a negative result with no positive control has measured nothing.

A number picked to make a result come out is not a measurement. This work does not carry one, and a contribution that adds one does not land.

## Areas of research

Twelve subjects have staged pipelines under `examples/`. Seven have run end to end and agree: language, art, crystals, proteins, sound, source code and arbitrary corpora. Chemistry, game theory, cell tracking, molecules and particle physics are being brought to the same standard. The proofs that pin the numbers are under `evidence/proofs/`. The same six parts test each other end to end and agree.

Published cell edges from the Crystallography Open Database, tiled and voxelized and handed over with nothing told to the detector, come back three of three exact, to 0.0006 angstroms against a voxel of 0.25. No other positive control here took its answer from outside the work.

A dialect border inside Lushootseed, labeled by Mellesmoen and Kye and then held out, comes back as the stressed schwa, southern, beaten by 1 of 200 random borders over the same forms.

An image read as a byte sequence returns its own width. A Vigenère cipher returns its key length. A protein backbone returns bond lengths of 1.45, 1.52 and 1.33 against chemistry's 1.46, 1.52 and 1.33. None of them was told anything.

Subtraction games return their Grundy period on 383 of 383 rows the detector can score, against periods computed by a separate exact routine, at a worst margin of 16 floors. The same detector returns a confident number on a sequence that has no period at all, and what it is reading there is the continued fraction of the sequence's slope.

The workbook holds the rest, including every row that failed and why.

## Where things are

Each directory serves one purpose.

|                | what it operates on          |                                                                                                              |
| -------------- | ---------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `src/`         | points and values, no domain | the engine: the C in `src/c/`, the device code in `src/cu/`, the Python in `src/python/`, the sims in `src/sims/` |
| `utils/test/`  | the engine                   | the correctness checks in `utils/test/src/`, laid out as `src/` is, and the published test vectors             |
| `utils/bench/` | the engine                   | the benches: how fast it is                                                                                  |
| `evidence/`    | the claims                   | the proofs, and the R and MATLAB ports                                                                       |
| `examples/`    | a corpus, through `src/`     | scripts over twelve subjects, each at `examples/<subject>/<stage>/<file>.py`                                 |
| `utils/maint/` | the repository itself        | records, gates, prose checks, the research paper build, the data fetchers and the Salishan pipeline          |
| `theory/`      | the argument                 | twenty research papers                                                                                       |
| `docs/`        | the reader                   | setup, usage, and the proofs the search kernel's count rests on                                              |

`examples/README.md` explains the stages and how to run a script. `utils/maint/README.md` maps the maintenance tools. `build/` is generated and disposable, and nothing irreplaceable is reachable through it.

## The detector and the measure are not the same reading

The engine carries many readers, one per file under `src/python/engine/analysis/measure/` and `src/python/engine/analysis/reference/`, and the examples run each on a corpus. Two of them are mistaken for each other more than any others, and reporting one as the other is an error.

The shift agreement detector reads a period or an offset, from how often a shift agrees with itself. The permutation null measure reads how far an object sits from a shuffle of its own parts, and its bit form reads the exact invariances that survive the shuffle. A number from one is not a number from the other.

What each reader has and has not been shown to do is in the workbook, row by row, including the rows that failed. Read it before quoting any reading. The one reading whose answer came from outside this work is the crystal cell edge, three of three exact from the Crystallography Open Database, recorded under Areas of research above.

## The transforms

The engine carries a large set of transforms, maps that put the object into another representation and, where they invert, back. They are integer and exact, and a transform with an inverse returns the input to the bit on the round trip.

**The number-theoretic transform.** One transform modulo the prime 998244353, the exact stand-in for the Fourier transform with no float formed and no root of unity approximated. `exact_translation_by_ntt.py` recovers a translation by NTT convolution and agrees to the digit with the direct correlation. `ntt_double_transform_inverts.py` shows the transform applied twice is a reflection. The transform is its own inverse up to reversal and scale, and `ntt_twiddle_certificate.py` certifies the prime, the primitive root and the order it rests on.

**Layout and space-filling bijections.** Every render layout is a bijection on the cell index, computed in integers and checked for zero collisions by `bench_raster`: four for a sheet (rows, serpentine, columns, diagonal) and four for a volume (slabs, boustrophedon, Morton, helix). The partition carries the same idea for reading, a Morton interleave and a Hilbert curve that fold any number of dimensions through one without being told the shape.

**Representation embeddings.** A row-major file goes back into the plane it came from given its width. A re-seating renumbers the alphabet so its values spread as little as any numbering allows. Exact decimal ingestion keeps every digit the source wrote as an integer pair and forms no float. A Gray-coded embedding places any corpus as points in a binary volume, one bit changing between neighbors.

**Exact codes.** A redundant residue number system carries an integer as residues over coprime moduli and reconstructs it by the Chinese remainder theorem, the extra moduli making it detect error. Hamming(7,4) carries four data bits as seven and corrects one flip.

**Reference backgrounds.** A maximum-entropy background is built by a transform that deletes a property. A permutation or block shuffle draws the null the whole engine measures against, a phase fold groups positions congruent modulo a period and reassembles them, and a windowed median and a self-similar context map each build a background by nearness or by shared context.

**The image transform program.** `theory/theory/image_transforms` is a research paper of exact image transforms: translation, rotation with scale and perspective, observed motion, and waves on a surface. Translation is built, and it is the number-theoretic transform above. The rest are stated in the research paper and not yet implemented in the tree, and the research paper says which is which.

The full set lives one per file under `src/python/` and in the C renderer, and the workbook records what each has been shown to do. A defensible count is eleven invertible transform families, or seventeen if every render layout is counted on its own, beside several one-way maps.

## The sift

`src/c/engine/nbody/orior/orior_*.c` holds the search and the steering that places its probes. With the portable scan beside it and the exact integer arithmetic under `src/c/types/integers/`, it builds and runs with a C11 compiler alone, four sources and no build system (`docs/setup.md`). The Python in `src/python/engine/nbody/orior/sift/` implements the same construction, shares no code with it, and the two are checked against each other by agreeing on counts.

**It is a sound filter.** A subset of a pattern's points is a necessary condition. No arrangement of anchors can lose a true occurrence. That is a proof, using no order, no dimension and no alphabet. The measurement beside it: across 35 rows of corpora, needle lengths and strides, no search ever reported fewer occurrences than exist. Errors are one directional. A discrepancy is always an over-count and is detectable without knowing the answer.

**It carries `m` bits of state**, for a pattern of length `m`, independent of alphabet and dimension. Nothing is indexed and no table is built over the alphabet. A real-valued or unenumerable alphabet therefore costs it nothing. That is a capability claim and it is separate from any speed claim.

**It searches with no pattern at all.** Given only bytes it recovered a multiple of a record period from 512 reads, at 92 shifts against 0 on a shuffle of the same bytes.

**The kernel dispatches, and grades itself.** `orior_choose` picks an engine from the field's own census, which one histogram pass already produced. The comparison is exact integer arithmetic and the engine holds no floating point value anywhere: the effective alphabet `2^H2` is `total^2 / sum(count^2)`. Asking whether it reaches 85 percent of the symbols the field uses clears its denominators into `100*total^2 >= 85*distinct*sum(count^2)`. `bench_dispatch` times every engine, prints what the dispatcher chose beside what was fastest, and scores six candidate rules against each other. Over 42 rows the rule the kernel carries names the faster engine 39 times on x64 MSVC 19.44 at Release, giving up 9131790 cycles or 0.035 of the worst rule, and 41 times under gcc on the same machine, giving up 86511 cycles or 0.000. That is a hundredfold gap in the cycles figure and it is not rounding. Both are real runs, and each number belongs to the toolchain that produced it. The bench exists for that reason, and its output is a recommendation to act on and not a figure to quote. It sweeps its threshold instead of assuming it: the interval 0.34 to 0.96 all score identically and the 0.85 the kernel carries sits inside it.

**The needle length term in the rule does nothing on this data.** Scoring flatness alone ties the kernel exactly, same rows and same cycles. The length term changes no answer on any of the 42. Flatness then length scores strictly worse than the flatness it contains, and length alone is worse than both. A tunable with no reader is an integration point and is neither removed nor described as unimplemented. It is named here and kept until a row is found where it pays.

Cycles given up is the score that matters, and it inverts the row count. Always taking the free order engine is right on 17 rows of 42, the fewest of any rule on the board, and it still gives up fewer cycles than always taking the short circuiting one, which is right on 25. Counting rows treats a row where the engines differ by one percent the same as one where they differ threefold. A rule can be wrong more often and cost less.

The dispatcher is still blind in one direction, and the blindness is a property of the statistic. A period-16 counter uses sixteen symbols evenly. Its collision entropy reads 4.0 and a perfectly structured corpus looks memoryless. Collision entropy is permutation invariant and cannot see an arrangement, and the dispatcher carries the same blindness exactly. Exact arithmetic removes the rounding, not the blindness. Reading arrangement needs a different quantity, and `orior_anchors_for` is where one enters: it takes the period the corpus repeats at and drops to a single anchor, because at a known period every anchor after the first tests the same congruence and refutes nothing new.

### Building it, and what each tool answers

One command from a fresh clone. It needs `cmake` and a C11 compiler on `PATH`. There is no network step, no submodule to fetch, no generator to run first, and no library outside the C standard headers.

```sh
utils/maint/engine/build_engine.sh               # configure, build, run the graders
utils/maint/engine/build_engine.sh --build-only  # configure and build, run nothing
```

Windows PowerShell uses `utils/maint/engine/build_engine.ps1`, and `-BuildOnly` in place of `--build-only`. It imports the MSVC environment and compiles the device rasterizer. The shell script run from Git Bash has no MSVC environment. It pins the build to gcc or clang and says so. Output lands in `build/engine_c/` and nothing reads it back. Delete it freely.

Both scripts share that directory, and a CMake cache outranks anything a script prints. Each one passes the decisive settings on every configure and wipes a cache naming a different toolchain. The PowerShell script checks the configure for a CUDA compiler before it builds and fails if the announcement does not hold.

A machine with a card should render on it without being asked, and `bench_raster` prints `device rasterizer: present` and grades all twenty configurations `host/device identical` when it does.

Two questions, two directories, and they are not the same question. `utils/test/src/` answers whether the engine is right. `utils/bench/` answers how fast it is. A failing test is a defect; a slow bench is a cost.

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
| `bench_lattice`                   | soundness in one to eight dimensions, over a rotated point set and a scatter no rectangle covers. It holds its own core, because the construction is under test, apart from the byte specialization.                                                                                                   |

**The counted build and the timed build are different binaries and cannot be mixed.** `bench_scaling_reads` links the kernel compiled with `ORIOR_COUNT_READS=1`; `bench_scaling_cycles` links the kernel compiled without it. Counting perturbs the timing it would otherwise be reported beside. A driver calling `orior_counters_reset` therefore fails to link against the timed kernel, and that failure is deliberate.

**Known gap:** `bench_lattice` needs C99 `_Complex` arithmetic and does not build under MSVC, which supplies the types without the operators. Build it with GCC or Clang. Every other target in the table was built and run on MSVC 19.44 x64 at Release. The GCC and Clang paths are exercised by the same CMake file.

### Rendering the object, flat and solid

The renderer draws the object under examination straight from engine state. What it shows is what the search saw. Two surfaces, and they are separate because a sheet and a block are different maps and not the same one at two sizes. `theory/workbooks/orior/rendering.md` covers both.

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

## Ports

The permutation null measure on its own is the part a statistician or corpus linguist reaches for.

| language          | file                                     | status                                                                       |
| ----------------- | ---------------------------------------- | ---------------------------------------------------------------------------- |
| Python            | `src/python/`                            | the reference every figure came out of                                       |
| R                 | `evidence/sims/r/departure.R`            | runs, checked against the reference                                          |
| MATLAB and Octave | `evidence/sims/matlab/orior_departure.m` | run on Octave 11.3.0, inside the reference floor; MATLAB proper not run here |

A port is correct when it lands inside the reseeding floor of the Python, since each language draws its null from a different generator and none can agree to the last digit. Checked on 200000 symbols over twelve seeds: a clustered sequence reads 0.4228 in Python and 0.4282 in R against a floor of 0.0092, and a memoryless one reads 0.9953 and 0.9933 against a floor of 0.0044. Both gaps sit at about half a floor.

## What it knows

Nothing. There is no model, no training, no corpus of examples, no prior. It has no knowledge of language, chemistry or images and never acquires any. It computes one distance and every result came out of that.

It runs on human timescales: seconds on a laptop against a database somebody else published. Its reach is unbounded, because it assumes nothing about the domain and needs only that the object is not already at maximum entropy. Every single reading is finite and carries a stated floor. Where the floor is not cleared, the honest answer is that nothing was read.

## Whose language this is

The largest language corpus, and the one everything else in the languages category is currently measured against, is Salishan speech, which was written down by a linguist or their transcriber in almost all cases.

**This work does not exist without the speakers.**

Every table in the Salishan corpus opens with the person who spoke, before the linguist who published and before anyone who read it into a file.
Where a paper cites a published dictionary and never says who spoke, its entry says so.
The Salishan theory research paper carries that index, written speaker first.

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

The research is twenty research papers under `theory/`, built with XeLaTeX. One command builds all of them:

```sh
sh utils/maint/texbuild/build_theory.sh
```

| you want                                                                         | research paper                           |
| -------------------------------------------------------------------------------- | ---------------------------------------- |
| the construction, the method, and what is settled, open or withdrawn             | `theory/workbooks/orior`                 |
| the engine part by part, the query protocol, and every claim with what backs it  | `theory/workbooks/engine`                |
| the drafts the engine's theory was carried from                                  | `theory/thought_experiments/engine`      |
| the compression floor, and every claim with what backs it                        | `theory/workbooks/compression`           |
| valence read as a necessary condition, and where the oracle enters               | `theory/theory/chemistry`                |
| a domain that supplies its own answers, and the reading it corrected             | `theory/theory/game_theory`              |
| the image transform program, exact, and which of the transforms is built         | `theory/theory/image_transforms`         |
| particles as exact charges and shells, and what a quantum number costs           | `theory/theory/particle_physics`         |
| the information theory under the nulls, and the survey of viewers                | `theory/theory/apparatus`                |
| a lit set on a sphere read as a boundary, and how deep into the rounds it reaches | `theory/theory/boundary`                |
| what the instruments cannot see, how they failed, and how to aim them            | `theory/theory/instruments`              |
| whose words the corpus holds, and how wrong it could be                          | `theory/theory/Salishan`                 |
| the posits whose experiment cannot be built                                      | `theory/thought_experiments/orior`       |
| a published cell edge read back off a voxel grid, and whose result that is       | `theory/theory/crystallography`          |
| where the structure in SHA-256 is, where it stops, and how each null was measured | `theory/theory/cryptography/sha256`     |
| exact arithmetic, the natural constants and the residue codes                    | `theory/theory/precision`                |
| the null, its delta, and where the two reconcile                                 | `theory/theory/delta_null`               |
| the corpus, the state of the field, and what this toolkit reaches                | `theory/theory/millennium`               |
| the cell tracking engine's ledger: each claim with the status that backs it      | `theory/workbooks/cell_tracking`         |
| the cell tracking thought experiments, kept as they were written                 | `theory/thought_experiments/cell_tracking` |

To read the code instead of the argument, start with `src/python/README.md`, then `src/README.md`, then `examples/README.md`, then `examples/any_corpus/`.

## What is not here

The corpora, papers, audio and rendered pages run to about 1.9 GB and none of it is in git. `utils/maint/data/salishan/get_papers.py` fetches the papers from their archive, `utils/maint/data/fetch/` fetches the other corpora, and the tools rebuild the rest.

The hand extractions are forms transcribed out of published papers. The tables are those papers' text and not this work's to redistribute.
They are not carried here.
Everything that does not read a paper or a table runs without them.

## Licensing

Every source file carries this header:

```
SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
```

Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a negotiated commercial licensing contract or an educator's license issued to you personally. It will always be free to use under the AGPL.

| license                   | text                                                                                     | terms                                                         |
| ------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| `AGPL-3.0-or-later`       | [`LICENSES/AGPL-3.0-or-later.txt`](LICENSES/AGPL-3.0-or-later.txt), also [`LICENSE`](LICENSE) | the GNU Affero General Public License version 3 or any later version |
| `LicenseRef-Commercial`   | [`LICENSES/LicenseRef-Commercial.txt`](LICENSES/LicenseRef-Commercial.txt)               | a negotiated commercial contract                              |
| `LicenseRef-Educational`  | [`LICENSES/LicenseRef-Educational.txt`](LICENSES/LicenseRef-Educational.txt)             | an educator's license, issued in writing to a named person    |

Educators: for an exception to use this in classrooms or research projects, email dstroy0 (Douglas Quigg) <dquigg123@gmail.com> from your `.edu` or `.org` faculty address.
Exceptions are granted case by case and govern your use, specifically the accreditation requirement of underlying systems in research or presentation materials.
Where an academic exemption leads to a viable market product the license shifts to a royalty ladder, set off the goodwill shown and how well students and others were credited.
A portion goes to your institution at a minimum, and straight to your department where their rules allow.

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).

## A note on how this is written

1. The workbook always keeps its own corrections.
   - Claims that were withdrawn stay on the page with the measurement that killed them.
   - A document recording only what survived is not evidence.
2. Several results are rediscoveries of published work, and where that is known the precedent is named.
   - Citation is ongoing, any corrections are appreciated and welcome, and attribution is critical.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
