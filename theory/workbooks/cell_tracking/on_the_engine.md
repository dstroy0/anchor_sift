# The cell program on the engine

**Purpose:** Hold what the engine's books measured on the cell program's samples, and the sieve's sections that set it on the cells, so the engine book carries the machine alone and points here for the program's numbers.
**Scope:** text moved on 25 September out of the engine book: [engine_table.md](../engine/engine_table.md) (M2, M5, M9, M10, M12 and M14), [noise_sieve_tower.md](../engine/noise_sieve_tower.md) (§14 and §15, and its lines on the program's node policies, links, random numbers, edge rows and floor) and [tessera_scheduler.md](../engine/tessera_scheduler.md) (the driver's jobs). Each part names where it stood, and its words are as they stood there. Statuses follow [README.md](README.md).

## From the engine table

### M2. The residual operator

The unit sweeps against the key: **proved**, 0 of 419,430,400 lanes differ on 44b6_0113de3b's 100 frames and 0 on 400 more frames (6bba_48816121, 6bba_09961292, 6bba_cdcfe533, 44b6_0b24845f); 14.0 ms a frame against the key's 29.0 on 44b6_0113de3b, 14.3 against 28.1 on the four (**measured**). Held again after every error-wiring build of 23 September: proved on 100 frames, 0 lanes differ.

The cell program's scan runs it on the 25 at 34 bits in and 10 limbs out, 20.1 ms a frame (**measured**; cell table, S1).

### M5. The correlation operator C

The box (`--box`, 23 September) on 44b6_0113de3b: **proved**. C is read at the 27 shifts around every climbed lag and at the drift for 726,273 climbers (every forward pair and every null draw): 20,335,644 cells, 30,196,969 entries, 15.3 s. A cell meeting more labels than the kernel's table (10,507 cells) writes its raw pieces and the host merges them, with no cap. At the climbed lag, C sums to the climb's held count on all 726,273; the climbed lag is the highest of its 27 neighbours on all 726,273; at the drift, C equals `body_overlap` on all 80,697 labels.

### M9. The files

`flatten`: **measured**, 138 to 170 s on 44b6_0113de3b; the cause is its residual slab sized to half the free device memory: 107.0 s at that slab, 9.0 s one frame at a time, byte-identical output, every stage 10 to 20× slower under the big slab.

### M10. The record machine

The programs themselves (print, velocity, division, contact side) belong to the cell program.

### M12. Errors and integrity

Every wiring build checked on 44b6_0113de3b: 38/0/12 edges and 0 lanes differ, both modes.

### M14. The scheduler

`track_driver` submits through it (24 September): `--ingest` is one job and each `--run` part is one; the signum is the part's name and the whole effective request; the declaration is the largest sample's lattice in 16-bit lanes, from the source's description for `--ingest` (`engine_source_lanes`, which reads no voxel) and from the `.iapx` head otherwise; the times are 2 s holding, 20 ms sweep and 5 s idle; a job that is not taken, or is held and lost, fails its part. **Measured** on 44b6_0113de3b, with the driver and the daemon built to `build/verify_driver` (exit 0) and run in a scratch `TESSERA_STATE`. The ingest was granted its declaration of 838,860,800 bytes and peaked at 5,091,037,184 (25,392 ms), sample root ad3d9846…, set root b68d522c…. Two proves in a row were each granted 838,860,800 and peaked at 3,958,566,912 and 3,962,761,216, with the same roots. The history was then 128 bytes, two records and the seal, and the daemon ended once idle. Anchor_sift's run on the real state gave the same declarations and ingest peak, and the two prove peaks in the other order: identical requests measured 4,194,304 bytes (2^22) apart.

## From the tessera scheduler: the driver submits (24 September)

`track_driver` runs every job through tessera. `--ingest` is one job, and so is each `--run` part.

- **The signum** is the BLAKE3 hash of the part's name, a NUL, and the whole effective request, so a changed setting is a new signum.
- **The declaration** is the largest sample's lattice in 16-bit lanes. For `--ingest` it comes from the source's description (`engine_source_lanes`, which reads no voxel); for every other part, from the `.iapx` head.
- **The times** are 2 s holding, 20 ms sweep and 5 s idle.
- **The daemon** is `tessera_daemon` beside the driver, which the driver starts when none answers.
- **A part fails** if its job is not taken, or is held and lost; `--override` admits a held job on its declaration.

Measured on 44b6_0113de3b, in a scratch state directory:

| run | declared and granted | peak measured |
|---|---|---|
| `--ingest` | 838,860,800 | 5,091,037,184 |
| `--run iapx-prove` | 838,860,800 | 3,958,566,912 |
| `--run iapx-prove` again | 838,860,800 | 3,962,761,216 |

The history then held two records and the seal (128 bytes), and the daemon ended once idle. Anchor_sift's run on the real state gave the same declarations and ingest peak, with the two prove peaks in the other order.

The two findings these runs gave are the scheduler's, in [tessera_scheduler.md](../engine/tessera_scheduler.md).

## From the noise sieve tower

### §6. The demon's arms: the node policies

- **Truthy/falsy probes** (fluidic draft §5) are the node policies in `maint/score_submission.py`. `stands` asks per node whether it is the size a cell is here, and `above_null` asks whether it stands above its own null draws.

| claim | status |
|---|---|
| binary probes in place of chosen thresholds | built; `stands` gave 0.12 on the older components dump, far below taking every node (0.22), because it kept 38,114 nodes against 484,255 estimated |

### §8. The three irreducible sets: true coherence

| set | in the engine | status |
|---|---|---|
| true coherence | the residual's structure above the medium: bodies and their links | built; 97.0% of 3,873 labelled edges linked on five 6bba samples by the internal count |

### §10. A universal Turing machine and the demon

| claim | status |
|---|---|
| outcomes read deterministically, with no random number anywhere | built: no pseudo random number is formed anywhere in the tracker |

### §13. The seed crystal: the edge rows

| claim | status |
|---|---|
| a flat field propagates nothing; a minimal fixed asymmetry gives every choice one direction | the Windows and Linux builds give byte identical edge rows over the 25 |

### §17. The floor laid down first: the driver

The `.cfg`'s `floor` section names where each sample's noise keys are held (`--floor <dir>` on the command line).

| claim | status |
|---|---|
| the floor section in the `.cfg`, laid down before anything else runs | the driver lays the floor down first |

### 14. The sieve on this competition: splits, entropy, and each body's harmonics

`noise_sieve_5_cell_tracking_harmonics.pdf` sets the sieve on the Biohub volumes directly. It is the source nearest the score, and each of its mechanics has a concrete form here.

**The engine holds nothing; gradients define themselves.** No gradient is tuned and no threshold is chosen: the field carves the boundaries where the data puts them. This is already the engine's rule for its cuts. It is also the rule the node policies `stands` and `above_null` were written to: a body is a node because of what it is here, not because it ranks in a chosen top n.

**One precision note.** The source speaks of a 10^−68 precision floor. The engine has no precision floor: its arithmetic is exact at every width it runs, and every width is proved before the run. The only floor is the measured one in the data (noise_sieve_tower §5).

**A split is a boundary discontinuity, judged over the whole sample.** A mitosis or a lysis is not decided in the frame it happens in. Over the sample's whole history there will be a bump in entropy at about that time, and the two differ: a mitosis is a clean fork where local entropy bumps and settles, while a lysis is an uncontained dissipation into the background. Both change the fluidics far around them. The metric pays for this: the division Jaccard is 0.1 of the score, and the engine earns none of it today (0 divisions matched on the older components dump). The test is concrete. A body's fate is already written for every body (`bodies`: split, merged, vanished, absorbed). The entropy of the region around a candidate split, taken per frame from the exact residual, can say whether a real fork happened. Two linked children and a bump that settles make a division; a bump that bleeds into the floor is a lysis.

**Each body's harmonics are its second moments.** The source asks for each body's spherical harmonic coefficients, with the dipole (ℓ = 1) and quadrupole (ℓ = 2) dominant for the oblate shapes cells take. Up to ℓ = 2, a body's harmonics carry exactly what its moments carry:

| order | harmonics | what they hold | in the component tree, exactly |
|---|---|---|---|
| ℓ = 0 | one | the mass | `MAX_TREE_FIELD_MASS` |
| ℓ = 1 | three | the dipole: mass times the centroid | `MAX_TREE_FIELD_SUM_Z`, `_SUM_Y`, `_SUM_X` |
| ℓ = 2 | five | the quadrupole: the traceless second moment tensor, the body's oblateness and its axis | `MAX_TREE_FIELD_MOMENT_ZZ`, `_YY`, `_XX`, `_ZY`, `_ZX`, `_YX` (six terms; the trace is the sixth) |

So every body the tree finds already carries its ℓ ≤ 2 fingerprint as exact integers, with nothing to fit. The source's "unique harmonics for each body because of intrinsic physical differences" is then a matching rule. A body in the next frame is the same body where its mass, dipole displacement and quadrupole agree, up to the motion the frame shows. The retrograde vector −∇(∂C₁ₘ/∂t) is the time derivative of the dipole: the body's centroid velocity, run backwards to where the motion started.

**Where it lands on the score.** On the five 6bba samples, 19.6% of key edges are lost because a cell's link lands on a neighbouring node, a median 6.7 µm from the right one (ledger, 22 September). Neighbouring nodes differ in mass and quadrupole even where their centroids are close, and a body's fingerprint tells it from its neighbours. A link chosen by the ℓ ≤ 2 fingerprint instead of by overlap alone is the direct test of this section.

| claim | status |
|---|---|
| no tuned gradient or threshold | built: the cuts; the `stands` and `above_null` policies |
| a precision floor of 10^−68 | not so: the arithmetic is exact, with no floor |
| a split is a boundary discontinuity, confirmed over the whole sample by an entropy bump that settles; a lysis by one that bleeds out | theory; bodies' fates are built, the entropy test is not; the division term (0.1 of the score) is 0 today |
| mitosis and lysis change fluidics far around them | theory |
| each body's ℓ ≤ 2 harmonics held exactly | built: mass, first and second moments per body in the component tree |
| linking bodies by their ℓ ≤ 2 fingerprint wins back the neighbouring node losses | theory; the direct test against 19.6% on the five 6bba samples |
| spherical harmonics above ℓ = 2 | theory; they need the body's surface, not only its moments |

### 15. Edges by jitter, membership by sample coherence

The engine's rule for what a body is, stated directly: **the jitter scrubs and oversamples to define a body's edges, and coherence over the whole sample assigns membership.**

**Edges by jitter.** A single frame's cut puts a boundary voxel on one side or the other by chance: the field noise at the edge decides it. The jitter sweep already in `relate_frames` (a box a voxel wide, doubling out past the whole view, `LINK_SWEEP_STEPS`) moves the view by every small offset and asks again. Scrubbing a body's boundary under every jitter oversamples it. The voxels that stay with the body under every offset are its edge; the ones that fall in and out are the floor at its boundary, read and set aside, not averaged. This is noise_sieve_tower §5's floor applied at a body's surface.

**Membership by sample coherence.** Which pieces make one body is not decided in a frame either. A piece belongs to the body its coherence carries on with across the whole sample, the same way the harmonics source judges a split over the whole sample and not the moment (§14), and the same way identity is the limit of coherence (noise_sieve_tower §9). Pieces of one body cohere through every frame; pieces of two bodies part somewhere in it. So grouping by what touches in one frame, which today runs transitively through touching cells, gives way to grouping by what coheres over all of them.

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
