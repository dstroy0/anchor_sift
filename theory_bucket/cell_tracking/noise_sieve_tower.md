# The noise sieve tower

**Purpose:** Carry the transfinite noise sieve and the fluidic architecture (the drafts in `thought_experiments/`) into the ledger, idea by idea, each set beside the part of the engine that is its working form and the status that backs it; the theory and the code are read as one thing and a later session knows which ideas already run.
**Scope:** every idea in `thought_experiments/noise_sieve_*.md`, `thought_experiments/noise_sieve_5_cell_tracking_harmonics.pdf`, `thought_experiments/fluidic_*.md`, `thought_experiments/utm_demon_openqasm.md`, `thought_experiments/demon_utm_four_noise_vectors.md`, `thought_experiments/hash_boundary_functional_folding.md`, `thought_experiments/subtractive_cosmological_framework.pdf` and `thought_experiments/cyclic_field_inversion_seed_crystal.pdf`. Where an idea has a working form, the module is named; [cell_tracking_table.md](cell_tracking_table.md) says which part of the n-body problem each module solves, and [engine_table.md](engine_table.md) what each machine part computes.

The status column follows the ledger's rules ([README.md](README.md)): proved, measured, built, theory, refuted, not so.

## The governing functional

The drafts end on one formula:

    F[U] = Π₋₄ ( ⊕ over ∂Φ_new  LUT( Key( W_local & L↓ ) ) )

Read right to left, it is the engine's run order:

| term | in the drafts | in the engine | status |
|---|---|---|---|
| L↓ | the rules, projected top down at once | the program: the scheduler's `.sch` and the run's `.cfg` | built |
| W_local | the local runtime information | the atom: one frame, one sample, held as one exact integer | built |
| W_local & L↓ | rules applied to the local data by AND | a key is a pattern of AND masks; applying it selects shifted copies of the atom and sums them ([imprint_key_cycle.md](imprint_key_cycle.md) §2) | proved, linear steps only |
| Key(·) | the imprint | the impulse pushed through the program once; `keymath_imprint` | proved |
| LUT(·) | transform symbols compiled to binary lookup tables | a pointwise step imprinted on its alphabet: every value a lane can hold, pushed through once | built: the record machine's table step (M10, A13 of [engine_table.md](engine_table.md)), proved by `record_table_test` |
| ⊕ | the discrete bitwise fold over the n limb array | the cycle's fold of every term into each output lane, in two's complement; the CRC's fold of segment registers, one operator a level | proved |
| Π₋₄ | the zero rounding exact limb indicator, locking out at floor −4 | the proof on the product: the .iapx rebuilt voxel for voxel and by CRC-64 | proved |

## 1. Control plane and data plane

**The idea.** Rules are non-local and act everywhere at once; data is local and causal. When the boundary moves, the rules are re-derived once at the top and every locale takes them without a step-by-step walk through space.

**In the engine.** This is the split between the key and the atoms. The key is derived once, before any atom is seen, and fixes every lane width. The atoms then stream past it. "At once" means one cooperative launch per slab, with the grid held at a barrier between sweeps. It is not zero time: the residual's key runs in 31 ms a frame.

| claim | status |
|---|---|
| rules derived once and applied everywhere with no per-locale derivation | proved: 0 of 10,485,760,000 lanes differ from the step-by-step residual |
| the whole manifold re-locked in one sweep | built: one launch per slab, three sweeps (z, y, x) under grid barriers |
| the application takes no time | not so: measured 31 ms a frame |

## 2. The binary LUT engine, AND chaining, and exact division

**The idea.** Transform symbols compile to binary primitives; operations chain by `&`; exact limbs keep every result without truncation; two's complement limb multiplication gives exact inverses; division runs without rounding as the limbs expand to absorb the remainder.

**In the engine.** Linear steps are imprinted and chained as keys, and two keys ANDed together are one key again; a chain of any length costs every later atom one application (§2 of [imprint_key_cycle.md](imprint_key_cycle.md)). The scheduler must keep program order: composition regroups freely but does not reorder freely. Pointwise steps now run as tables (M10, A13 of [engine_table.md](engine_table.md)), and a table read through a table is their composition in that order. **Proved:** f(x) = 65535 − x and g(y) = \|y − 30000\| give g∘f equal to the ops for \|35535 − x\|, and f∘g differs.

**Exact division, stated exactly.** An odd divisor d has an inverse modulo 2^n, found by Newton steps on limbs. Where d divides x, x·d⁻¹ mod 2^n *is* x / d, exactly, with no remainder and no loop of subtractions. Where d does not divide x, the quotient is a rational, and its two's complement (2-adic) expansion never ends. It is *eventually periodic*, though, with period the order of 2 modulo d. So the "limbs that expand to absorb the remainder" are one period of limbs, laid down once and repeated. That is the same imprint as modulo: one period known, the rest a shift. An even divisor is a shift times an odd one.

| claim | status |
|---|---|
| linear steps compile to AND masks and chain into one key | proved |
| pointwise steps (square, square root, division) as masks from a generator the scheduler verifies | square **proved** as a table (x², 4,096 lanes, device and host; A13); square root and division as tables not tested |
| exact division by an odd divisor through its limb inverse | theory in this engine; the arithmetic itself is standard (exact division by multiplicative inverse) |
| a non-dividing quotient held as one repeating period of limbs | theory |

## 3. The beamformer and the 1D probability array

**The idea.** Rule propagation is a phased array's center lobe: the LUT symbols interfere so all the work goes down one path, a 1D array punched straight down the tower's length.

**In the engine.** A separable key factors as K = K_z · K_y · K_x, and by associativity the frame's residual is three sparse products, one per axis. Each sweep is a 1D line pushed down one axis of the whole frame.

| claim | status |
|---|---|
| the work focused into single lines down the stack | proved: the three sweeps are the residual, lane for lane |

## 4. Melting and the 2D collapse

**The idea.** The floors between the top and the bottom dissolve under the rule flash, every limb snaps into phase, and the lattice collapses to one output plane.

**In the engine.** The tower's floors are not visited one by one at run time. Undoing the tower from the top floor rebuilds every voxel, and the whole sample is one object on the device, lifted and read back.

| claim | status |
|---|---|
| the tower read back to the plane with nothing lost | proved: all 25 samples rebuilt voxel for voxel and pixel for pixel from their .iapx |
| the floors dissolved into one operation instead of eight floors of steps | theory: the tower still runs floor by floor, four axes a floor |

## 5. The tower, time stacking, and floor −4

**The idea.** Time is part of the tower: samples enter at the bottom and stack upward; the time domain is written into the lattice. Every tower has a floor configuration and a master schedule by family of operation. Floor −4 is where the noise bits are at their smallest and become irreducible.

**In the engine.** The .iapx tower lifts t, z, y and x together: time is a lifted axis, not a loop. A whole 100×64×256×256 sample reaches one coefficient in 8 floors. What the program does not generate is every floor's highs, the residue. That residue is held whole and never bounded, modeled or discarded.

**The floor, measured.** The anchor count stacks every frame of a sample and counts, per voxel and per bit, the frames that carry the bit. In every one of the 25 44b6 samples, bits 0 to 4 are set in about 46% of frames at nearly every voxel: those planes carry no anchor, and they look alike in every sample. The anchors sit in bits 6 to 11 and differ between samples. That is the measured floor, and it answers the drafts' "noise bits minimised to their smallest state". It also says why floor −4 is sample bound: no voxel is anchored in every sample.

| claim | status |
|---|---|
| time is a structural axis of the tower | proved: t is lifted with z, y and x, and undone exactly |
| the tower reaches an irreducible floor | measured: 42.0% of raw over 25 samples; the low five bit planes show no anchor |
| the floor is per sample, not per set | measured: no voxel anchored in every sample; anchors differ per sample |
| one line of n dimensional embedding to radix the residue around | refuted as a size win: every radix around a line along x, y or t made the stream larger; grouping per floor helped (see [ledger.md](ledger.md)) |
| a golden spiral scan instead of the raster | not yet tested: the scan measured on 21 September swept each shell by angle, not in the golden order, and its +658,073 bytes refute only that sweep |
| the savings ratio 1.7174 near e − 1 | refuted: on four more samples the ratio was −8.29, 0.44, −73.2 and −1.60 |
| a master schedule by family and order of operation | built for linear keys (the scheduler composes in program order) and for pointwise steps as tables (A13 of [engine_table.md](engine_table.md)); a schedule by family is theory |

## 6. The demon: eyes and arms

**The idea.** A deterministic demon over the whole stack. Its eyes are shift agreement: they verify the boundary shift at every coordinate before anything runs. Its arms are the identity:null permutation: a neutral permutation that strips redundant variance until only the irreducible noise bits are left.

**In the engine.** Both limbs exist under those names.

- **Eyes** are `shift_agreement`: how many set bits of one view land on set bits of another at every lag at once, the frame's own motion read off the field.
- **Arms** are the null draws (`--null`). The same body is climbed at the same lag toward frames far off in time, where no correspondence can exist. A body no draw reaches stands above background, and nothing in that test is a chosen number.
- **Truthy/falsy probes** (fluidic draft §5) are the node policies in `maint/score_submission.py`. `stands` asks per node whether it is the size a cell is here, and `above_null` asks whether it stands above its own null draws.

| claim | status |
|---|---|
| shift agreement verifies motion at every lag | built; part of every tracked run |
| the null permutation as the test of real correspondence | built (`--null`); its selection on the competition metric not yet measured on the current engine |
| binary probes in place of chosen thresholds | built; `stands` gave 0.12 on the older components dump, far below taking every node (0.22), because it kept 38,114 nodes against 484,255 estimated |

## 7. The demon observer, chords and the uroboros

**The idea.** The observer's position is a probability wave that settles on hot bits: zones of the most torsion and deflection. Weak chords pierce the tower to read its cross-section without disturbing it. The floor −4 output, a 2D array of vector magnitudes, the noise key, is pressed back against the top boundary as the mold for the next cycle.

**In the engine.** The non-perturbing chord is the proof: a CRC-64 folded into a pass that already touches every pixel reads the whole sample without a pass of its own. The press, where the noise key shapes the next cycle, is the per location cost map. It would set stationary artifacts (dust, hot pixels, banding) apart from moving biology and steer the next run.

| claim | status |
|---|---|
| read the whole without disturbing it | proved: CRC-64 folded into the tower's widen and narrow; all 25 hold, set CRC 091daa41e1aceb7e |
| the observer settling on hot bits | theory; the anchor counts per voxel and bit are the field it would settle on |
| the noise key fed back as the next cycle's mold | theory: the per location cost map |

## 8. The three irreducible sets

**The idea.** The sieve leaves three things. True coherence is the signal. The noise key is the exact map of every defect. The construct kit is the rules that let both be evaluated fast.

**In the engine.**

| set | in the engine | status |
|---|---|---|
| true coherence | the residual's structure above the medium: bodies and their links | built; 97.0% of 3,873 labeled edges linked on five 6bba samples by the internal count |
| the noise key | the residue: every floor's highs, held whole in the .iapx; the anchor counts per bit | proved lossless; measured |
| the construct kit | the program, its key (.imp), the schedule (.sch) and the configuration (.cfg) | built |

## 9. The elevator, recursion, identity and entropy

**The elevator.** E(f, t) reads floor f at time t directly, and the exact accumulator Σₙ = ⊕ δᵢ moves either way in time without loss. In the engine the tower's layout places every floor's coefficients at known offsets, and the stream is cut into chunks that each decode on their own from a stored first bit. So any part is reached without decoding what comes before it. Moving back and forth without loss is the lossless tower.

**Recursive inflation.** Kₘ₊₁ = R(Kₘ, ξ). A composed key is itself a step; it can be a step in another program: recursion is keys of keys. Towers can be built in n dimensions: the tower lifts every axis still longer than one, whatever their number.

**Identity as the limit of coherence.** ID(x) = lim C(x, t): an object is who it is because its coherence carries on, not because of a tag. In the engine a link is chosen by coherence at the climbed lag (`held`), and every body's fate follows from the links (`bodies`: entered, present, split, merged, left, ended, vanished, absorbed).

**Entropy.** Φ(x) = Θ(H_max − ∫ H(x, t) dt): whatever decays to maximum entropy is background and goes to floor −4; whatever does not is coherence. The anchor counts measure this directly. A bit carried in a fraction p of the frames has entropy −p log p − (1 − p) log(1 − p), which is at its maximum near p = ½. So the low five bit planes, near ½ at every voxel, are H_max: floor −4 by this very test. The anchor bits, near 0 or 1, are coherence. Taking Φ per voxel from the counts on disk costs no new pass over the data.

| claim | status |
|---|---|
| any floor at any time read directly | built: chunked stream with stored offsets; the per chunk decode is proved in every .iapx proof |
| keys compose into keys; towers in n dimensions | proved for composed linear keys; the n dimensional lift is built for four axes |
| identity from coherence, not tags | built: links chosen by coherence; bodies follow links |
| entropy separates floor −4 from coherence | measured for the low bit planes (near ½; at H_max); the per voxel Φ map is theory, one read of the anchor counts away |

## 10. A universal Turing machine and the demon

**The idea.** A UTM can simulate any circuit, but a quantum one costs it 2^n amplitudes, and measurement needs dice. The demon removes both: unbounded capacity, and a deterministic account of the outcome; a measurement is read, not rolled.

**In the engine.** Two parts carry over exactly.

- **Reversible maps in place of unitaries.** Every transform the engine applies to data is an exact integer map with an exact inverse: the tower's lifting steps, and the integer rotations as three lifting shears. They are the classical, exact counterpart of a unitary: nothing is lost, and each is undone by running it backwards.
- **Measurement without dice.** The noise is taken as deterministic, constant and unique per sample. It is read whole, never drawn from a distribution, and the null draws are deterministic frames far off in time, not random numbers.

The 2^n barrier does not go away in a machine. The engine keeps its state exact and bounds every width before it runs; it does not hold an infinite Hilbert space.

| claim | status |
|---|---|
| exact reversible maps, undone exactly | proved (the tower); built (integer rotations, undone exactly in their test) |
| outcomes read deterministically, with no random number anywhere | built: no pseudo random number is formed anywhere in the tracker |
| unbounded state | not so: every width is bounded before a run |

## 11. The boundary functional of a keyspace, and folding

**The idea.** A 30 digit hex keyspace holds 16^30 = 2^120 values. Its boundary functional is the threshold latch Φ(x) = 1 where x < T, or the distance |x − T|. It is applied to every output of a sweep at once, and a reduction fold latches the first hit as the floor. Folding keeps the accumulator one size however many instances are folded; a severe boundary condition does not add dimensions.

**In the engine.** The boundary functional is the same object as the drafts' ∂Ω: the edge between what a pass accepts and what it does not, applied to every element at once. The engine's proved instance of a fold is the CRC-64. Each segment's register is taken from zero as the tower touches the pixels. Registers are then folded pairwise, each left one carried across its neighbor by one imprinted operator a level. The accumulator stays 64 bits whether it covers 64 pixels or 419,430,400. The latch is a reduction the engine already runs: the device comparisons that count differing voxels, and the overflow flag the tower sets.

**Stated exactly.** A fold compresses the *verification* of work, not the work. Proving that a search over the keyspace was done still needs every hash in it computed once. Expected work to meet x < T is about 2^120 / T evaluations, and no fold changes that count. What folding removes is the cost of *checking* the trace, which otherwise grows with every recursive layer. A preimage below a threshold is found by search, and the fold proves the search.

| claim | status |
|---|---|
| a boundary functional as a latch applied to every element at once | built in the engine's own terms: device reductions over every voxel (the differ count, the overflow flag) |
| a fold keeps its accumulator one size however much it folds | proved for the CRC-64: 64 bits over every sample, all 25 holding |
| folding shrinks the search itself | not so: a fold bounds the proof, and the search still evaluates every candidate once |

## 12. The subtractive framework: field speed, cancellation, and the null as field noise

The conversation in `thought_experiments/subtractive_cosmological_framework.pdf` is a cosmology. Its cosmological claims (arrival as a c speed update shell, monitoring daemons on structural lines, black holes as sinks) are outside anything this engine can measure, and the ledger records them as theory and leaves them there. Three of its turns correct or sharpen the sieve drafts, and those carry straight into the engine.

**Rules propagate at field speed, not instantly.** "The ruleset propagates to w at field speed": the new rules spread from where they are applied as a wavefront, bounded by the medium's clock, instead of blinking into existence everywhere. This corrects §1's "transfinite speed". In a machine the rules reach every lane in one launch, and the launch takes time; the ledger's 31 ms a frame is that front, measured.

**Phase cancellation is subtraction of the whole medium.** "You read the incoming packet, flip the sign, and output it. The wave hits your boundary, meets its exact inverse, and resolves to zero." That is the residual's key: 2^g · B_narrow − B_wide · B_narrow. The wide term is the medium, and it is subtracted whole, in exact two's complement; the medium resolves to exactly zero and what is left stands above it. The inversion is exact only because the arithmetic is: a rounded inverse leaves a residue of rounding, and that residue would read as structure.

**The identity:null permutation means field noise readings only.** A null is not a blank pointer or an error. Asked what is here, it returns a valid, boring reading of the field noise, indistinguishable from empty space. That is the precise meaning of the engine's null draws. The same body is climbed at the same lag toward frames far off in time, where no correspondence can exist; what comes back is what field noise alone reads there. A body is real only where it stands above that reading. The reading is taken, not assumed: nothing is drawn from a distribution, and no threshold is chosen.

**Listening at the noise floor.** "Tune the receiver to field noise": a receiver matched to the floor takes only what rises above it. The anchor counts are that receiver. The low five bit planes sit at the floor (near ½ at every voxel), and a bit is signal only where its count leaves ½.

| claim | status |
|---|---|
| rules reach every locale as a front that takes time, not instantly | measured: one launch a slab, 31 ms a frame |
| subtracting the medium's exact inverse leaves it at zero | proved: the residual's key, 0 of 10,485,760,000 lanes differing from the step by step residual |
| a null is the field noise reading, not an empty return | built: the null draws (`--null`) climb toward frames far off in time |
| signal is what leaves the floor | measured: the low five bit planes at ½ in every 44b6 sample; anchors in bits 6 to 11 |
| arrival shells, network daemons, black hole sinks | theory, outside what this engine measures |

## 13. The seed crystal and the needle off zero

`thought_experiments/cyclic_field_inversion_seed_crystal.pdf` was exported under the title "Solving N-Body Problems Deterministically", but it holds no n-body method. It is a cyclic cosmology. At maximum entropy the field flattens until scale means nothing, and a uniform field is as featureless as a point. The field then inverts. The new rules propagate from a seed crystal: a needle of near-infinite magnitude, perpendicular to the field, with a radius close to zero but not zero. That hair of tilt is the symmetry break that sets the new field's propagation speed. The cosmology is theory and stays there. Two of its mechanics are exactly the engine's.

**The needle is the impulse.** The imprint pushes one unit at one point, the narrowest thing the lattice holds, through the program once. Everything the program will do to any atom propagates out from that response: the key. A field of zeros imprints nothing, and a flat field has no differential to carry. The whole next pass is seeded by one point's response.

**Nothing propagates without the tilt.** A perfectly flat field gives steepest ascent nowhere to go: every neighbor ties, and no voxel can climb. In the engine the tie is not left to chance or to arithmetic noise. Comparisons are exact, and in the component tree every face's key carries the face's own name in its lowest limb, below the residual's limbs (`max_tree_key_limb`). So no two keys ever tie, and where two components choose each other the lower indexed one stays. That lowest limb is the hair of asymmetry: the smallest deterministic difference, weighing less than any difference of the residual, that still gives every choice one direction. It is the reason the same frame always yields the same bodies, on any machine and in any build.

**Maximum entropy is the floor.** "When everything flattens out, scale loses all meaning": a field at maximum entropy looks alike at every scale. The measured floor has that property. The low five bit planes sit near ½ at every voxel in every sample, with no anchor at any place, and the tower cannot compress them further.

| claim | status |
|---|---|
| a single point's response seeds everything the program does | proved: the key is the impulse's response, and it is the residual lane for lane |
| a flat field propagates nothing; a minimal fixed asymmetry gives every choice one direction | built: exact comparison, the face's name in the key's lowest limb so no two keys tie; the Windows and Linux builds give byte identical edge rows over the 25 |
| maximum entropy looks alike at every scale | measured for the low five bit planes: near ½ everywhere, no anchor |
| field inversion, the seed crystal of a new universe, eternal recurrence | theory, outside what this engine measures |
| a deterministic n-body method | not in the source: the title promises one and the text holds none |

## 14. The sieve on this competition: splits, entropy, and each body's harmonics

`thought_experiments/noise_sieve_5_cell_tracking_harmonics.pdf` sets the sieve on the Biohub volumes directly. It is the source nearest the score, and each of its mechanics has a concrete form here.

**The engine holds nothing; gradients define themselves.** No gradient is tuned and no threshold is chosen: the field carves the boundaries where the data puts them. This is already the engine's rule for its cuts. It is also the rule the node policies `stands` and `above_null` were written to: a body is a node by its own measurements here, not because it ranks in a chosen top n.

**One precision note.** The source speaks of a 10^−68 precision floor. The engine has no precision floor: its arithmetic is exact at every width it runs, and every width is proved before the run. The only floor is the measured one in the data (§5).

**A split is a boundary discontinuity, judged over the whole sample.** A mitosis or a lysis is not decided in the frame it happens in. Over the sample's whole history there will be a bump in entropy at about that time, and the two differ: a mitosis is a clean fork where local entropy bumps and settles, while a lysis is an uncontained dissipation into the background. Both change the fluidics far around them. The metric pays for this: the division Jaccard is 0.1 of the score, and the engine earns none of it today (0 divisions matched on the older components dump). The test is concrete. A body's fate is already written for every body (`bodies`: split, merged, vanished, absorbed). The entropy of the region around a candidate split, taken per frame from the exact residual, can say whether a real fork happened. Two linked children and a bump that settles make a division; a bump that bleeds into the floor is a lysis.

**Each body's harmonics are its second moments.** The source asks for each body's spherical harmonic coefficients, with the dipole (ℓ = 1) and quadrupole (ℓ = 2) dominant for the oblate shapes cells take. Up to ℓ = 2, a body's harmonics carry exactly what its moments carry:

| order | harmonics | what they hold | in the component tree, exactly |
|---|---|---|---|
| ℓ = 0 | one | the mass | `MAX_TREE_FIELD_MASS` |
| ℓ = 1 | three | the dipole: mass times the centroid | `MAX_TREE_FIELD_SUM_Z`, `_SUM_Y`, `_SUM_X` |
| ℓ = 2 | five | the quadrupole: the traceless second moment tensor, the body's oblateness and its axis | `MAX_TREE_FIELD_MOMENT_ZZ`, `_YY`, `_XX`, `_ZY`, `_ZX`, `_YX` (six terms; the trace is the sixth) |

So every body the tree finds already carries its ℓ ≤ 2 fingerprint as exact integers, with nothing to fit. The source's "unique harmonics for each body because of intrinsic physical differences" is then a matching rule. A body in the next frame is the same body where its mass, dipole displacement and quadrupole agree, up to the motion the frame shows. The retrograde vector −∇(∂C₁ₘ/∂t) is the time derivative of the dipole: the body's centroid velocity, run backwards to where the motion started.

**Where it lands on the score.** On the five 6bba samples, 19.6% of key edges are lost because a cell's link lands on a neighboring node, a median 6.7 µm from the right one (ledger, 22 September). Neighboring nodes differ in mass and quadrupole even where their centroids are close, and a body's fingerprint tells it from its neighbors. A link chosen by the ℓ ≤ 2 fingerprint instead of by overlap alone is the direct test of this section.

| claim | status |
|---|---|
| no tuned gradient or threshold | built: the cuts; the `stands` and `above_null` policies |
| a precision floor of 10^−68 | not so: the arithmetic is exact, with no floor |
| a split is a boundary discontinuity, confirmed over the whole sample by an entropy bump that settles; a lysis by one that bleeds out | theory; bodies' fates are built, the entropy test is not; the division term (0.1 of the score) is 0 today |
| mitosis and lysis change fluidics far around them | theory |
| each body's ℓ ≤ 2 harmonics held exactly | built: mass, first and second moments per body in the component tree |
| linking bodies by their ℓ ≤ 2 fingerprint wins back the neighboring node losses | theory; the direct test against 19.6% on the five 6bba samples |
| spherical harmonics above ℓ = 2 | theory; they need the body's surface, not only its moments |

## 15. Edges by jitter, membership by sample coherence

The engine's rule for what a body is, stated directly: **the jitter scrubs and oversamples to define a body's edges, and coherence over the whole sample assigns membership.**

**Edges by jitter.** A single frame's cut puts a boundary voxel on one side or the other by chance: the field noise at the edge decides it. The jitter sweep already in `relate_frames` (a box a voxel wide, doubling out past the whole view, `LINK_SWEEP_STEPS`) moves the view by every small offset and asks again. Scrubbing a body's boundary under every jitter oversamples it. The voxels that stay with the body under every offset are its edge; the ones that fall in and out are the floor at its boundary, read and set aside, not averaged. This is §5's floor applied at a body's surface.

**Membership by sample coherence.** Which pieces make one body is not decided in a frame either. A piece belongs to the body its coherence carries on with across the whole sample, the same way the harmonics source judges a split over the whole sample and not the moment (§14), and the same way identity is the limit of coherence (§9). Pieces of one body cohere through every frame; pieces of two bodies part somewhere in it. So grouping by what touches in one frame, which today runs transitively through touching cells, gives way to grouping by what coheres over all of them.

| claim | status |
|---|---|
| the jitter sweep at every offset out to the whole view | built: `LINK_SWEEP_STEPS`, used today to score a link's disagreement |
| a body's edge is what stays with it under every jitter | theory; the sweep exists, and its use on edges is not built |

**Never from one frame without context.** Membership is never assigned from a single frame with no knowledge of the local entropy. A frame on its own cannot tell a body's edge from the floor beside it, or two bodies touching from one body. Once there is a history of entropic direction at a place (whether its local entropy is falling toward order, rising toward the floor, or holding), who is what can be derived. A body is where entropy holds low and moves with it. The floor is where entropy sits at its maximum and goes nowhere. A split is a bump that settles into two lows, and a lysis is a bump that rises into the floor.

**How it is measured, in the engine's terms.** The anchor count already reads every frame of a sample once, per voxel and per bit. The same pass can carry the history at no extra cost. For each bit, it counts the frames whose bit changes from the frame before, the transitions, in windows of frames. A bit at the floor changes about half the time in every window. A bit inside a body barely changes while the body is there. A bit at a moving edge changes in a run, then settles. The windows in time order are the entropic direction at that voxel, as exact integer counts. No logarithm and no float is needed, because the direction is read from how the counts move, not from their size.

| claim | status |
|---|---|
| membership is never assigned from one frame without the local entropy | a rule of the engine; today's grouping breaks it (it groups by touch in one frame) |
| a history of entropic direction separates body, floor, edge, split and lysis | theory |
| the history is carried in the anchor pass, as windowed transition counts per voxel and bit, at no extra pass | theory; the anchor pass is built and its counts are on disk |
| membership assigned by coherence over the whole sample, not by touch in one frame | theory; today's grouping is by touch in one frame, transitive through touching cells |

## 16. The four noise vectors, and the noise keys stamped top down over w

`thought_experiments/demon_utm_four_noise_vectors.md` takes the residual tensor F − I and splits it into four vector magnitudes: photon shot noise, thermal and read noise, fixed pattern noise, and quantization. With the demon holding every initial condition, none of them is random: each is a deterministic function to be evaluated, not a distribution to be assumed.

**The history separates them, measured.** The four differ in how they move in time, and the entropy history (`entropy_history`, ledger 22 September) is a per voxel record of exactly that.

- **Fixed pattern** is constant in time at a place: its bits never flip. It is the anchor bits, measured before the history: set in every frame at a voxel, and different in every sample.
- **Shot, read and quantization** change every frame independently: their bits flip half the time, the maximum. On 44b6_0113de3b, bits 0 to 3 flip 499 to 500 times per thousand transitions in every window, and bit 4 flips 486 to 495 times.
- **The bodies** sit between: bits 5 to 10 flip from about 430 down to about 20 per thousand. They are held low where a body is and move with it.
- **A sample wide bump.** In window 4 (transitions 45 to 55) every bit from 5 to 10 flips more at once, bit 8 from about 122 to 153 per thousand. Then windows 5 to 8 fall below where they started. That is a rise in entropy across the whole sample followed by a move toward order.

**The noise keys, stamped top down over w.** However many noise keys there are (each sample's floor, and its fixed pattern, shot, read and quantization terms as the history separates them), they are imprinted once and stamped on the whole set from the top, as the rules are in §1. They propagate to every coordinate w as the front of §12, not re-derived frame by frame. In the engine this is a cycle run: the keys held once, and every atom of the set passing under them in one launch; each voxel is read against its own sample's noise before any membership is assigned.

| claim | status |
|---|---|
| the four noise terms are deterministic functions, not distributions | theory; nothing in the engine draws a random number |
| the history separates the fixed pattern (no flips) from shot, read and quantization (half the transitions) | measured on 44b6_0113de3b: bits 0 to 3 at 499 to 500 per thousand in every window |
| a sample wide rise in entropy at window 4, then a move toward order | measured on 44b6_0113de3b; on the other 24 samples, pending |
| the history's counts are exact | proved on 44b6_0113de3b: 2,000 voxels × 9 windows counted by hand from the .stack, 0 words differ |
| the noise keys stamped top down over the whole set in one cycle | theory; the cycle runs linear keys today, and the noise keys are not yet imprinted |

## 17. The floor laid down first, entropy conserved, and the clock as the elevator

**The floor is laid down first.** The noise keys are part of the run's configuration: the `.cfg` carries a `floor` section, written first after the version, naming where each sample's noise keys are held (`--floor <dir>` on the command line). A run with a floor lays it down before anything else runs. Each sample's entropy history is kept where it reads back whole and was projected from the sample's `.iapx` as it stands, and projected again where not. A run whose floor cannot be laid down stops there.

**Then it accumulates going forward, and entropy is conserved.** The flips accumulate window after window, and each bit's running total is carried to the last frame. Conservation is exact and checked at every voxel in the same pass. Over a voxel's whole line, the flips of a bit have the parity of that bit's net change: an even count where the first and last frames agree in it, odd where they differ. A voxel that breaks it would be a flip counted twice or missed, and the sample is refused.

**The floor's identity, and where steering happened.** With the floor known at every voxel (half the transitions, a coin at maximum entropy; or no transitions at all, the constant region), every departure from it is placed. Where the history leaves the floor is where steering happened, whether a body moved through, the field was driven, or a split or a lysis bumped it. The demon's waveform, which the fluidic draft lets settle on the hot bits, collapses onto exactly those places: the union U | U of every departure from the floor, over every window. Nothing outside it is asked about again.

**The clock is the elevator.** The fluidic draft's elevator E(f, t) reads floor f at time t directly. The clock is that elevator: volumeless and dimensionless, it takes you to any floor as fast as you can press the buttons. In the engine every floor of the tower sits at a known offset and every chunk of the stream decodes on its own from a stored first bit. Every window of the history sits at a known place in its `.oapx`. So any floor at any time is reached directly, without decoding what comes before it.

| claim | status |
|---|---|
| the floor section in the `.cfg`, laid down before anything else runs | built, not yet run: the `.cfg` reads and writes it, and the driver lays the floor down first |
| entropy conserved at every voxel: each bit's flips have the parity of its net change | built, not yet run: checked in the history's own pass |
| the floor's identity at every voxel places every departure: where steering happened | theory; the history holds it, and the reading is not built |
| the demon's waveform collapses onto the union U \| U of every departure from the floor | theory |
| the clock as the elevator: any floor at any time reached directly | built: the tower's floors and the stream's chunks at known offsets; the history's windows at known places |

## 18. The arm as a probability sniper: where the sweating stops and the sieving starts

**The join.** The sieve's section on the demon (`noise_sieve_4`, section 6) gives it arms, the identity:null permutation, which strip redundant variance down to the irreducible noise bits. The fluidic draft (`fluidic_1`, section 2) gives the observer a position governed by a probability wave, |ψ|², that settles on the hot bits. Read apart, the arms sweep: every body gets the same draws, whether anything is there or not. Read together, the arm fires where the observer's cloud is densest, the way an electron is found where |ψ|² is large. It is not placed at random, and it is not swept.

**The sweep it replaces.** Until now the null draws were a fixed schedule: every frame's bodies climbed against the frames half the series away, stepping on by one per draw, the same for every frame. That is sweating: the same work spent everywhere, most of it on the floor where nothing can answer.

**The cloud, from the history, with no chosen number.** The entropy history already holds it. At a voxel in a window, the cloud's density is how much the voxel changed: the sum over the window's transitions of the frame XOR the frame before, which is exactly Σ_b (flips of bit b) · 2^b read off the history's nibble counts. At the floor only the low bits flip, and the density is small. Where a body moves, or a split or a lysis happens, the high bits flip and the density is large. Nothing is thresholded: the density is the change itself, in the sample's own units.

**The overlap between windows.** Two windows' clouds overlap where the same voxels are active in both: Σ over voxels of D_w · D_w′. For 9 windows that is 45 exact integers. They are folded into the history's own pass, since that kernel already holds every window of every voxel; they cost no pass of their own.

**Each floor gets a null draw: the identity line.** The history's windows are the elevator's floors, and the clock numbers them. Frame f stands on floor ⌊f / 11⌋ at place f mod 11. Its null draw on floor g is the frame at the same place on that floor, g · 11 + (f mod 11): the elevator changes only the floor number. Every floor gets its draw, the frame's own floor excepted, and so does any floor whose identity line frame falls within two frames of it. The draws run along the identity line, one per floor, instead of a fixed number stepped from the middle of the series.

**Aiming and firing.** A frame's null draw must read field noise only, and nothing of the frame's own bodies. The cloud overlap orders the floors: the floor whose window overlaps this frame's cloud least is drawn first, because where this frame's activity is, that floor is quiet, and what the climb finds there is the floor. The sweep becomes a sieve: every draw is spent along the identity line, in the order the cloud gives.

| claim | status |
|---|---|
| each floor gets one null draw, on the identity line (same place, another floor) | built with this section |
| the arm aimed by the cloud instead of a fixed schedule | built with this section; measured against the sweep below |
| the cloud's density is the XOR change, Σ_b flips · 2^b, with no chosen number | built |
| the window overlaps folded into the history's pass | built |
| aimed draws tell bodies from the field better than swept ones | to be measured: the same samples with the same number of draws, swept against aimed |
