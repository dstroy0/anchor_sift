# Ledger

**Purpose:** Every measurement, in the order it was taken, with the samples it ran on, the number, and what it settled. No result is taken twice and none is quoted without its run.
**Scope:** runs of the .kcr codec, its variants, and the measurements of the lower bound it answers to. Samples are named by their id; "the 25" means the first 25 44b6 training samples by name.

## 2026-09-21

## The .kcr codec

| what | samples | result | settles |
|---|---|---|---|
| lifting-transform codec, whole sample as one object | the 25 | 42.0% of raw; every file rebuilt voxel for voxel on the device and pixel for pixel off it | lossless compression of the frames (proved) |

## The residual's code length: radix around a line, rotation, spiral

Stream sizes against the residue as the .kcr writes it, sample 44b6_0113de3b, 340,189,016 bytes. Every alternative was decoded back and checked.

| what | result | settles |
|---|---|---|
| radix around the line of 2, 4, 8 neighbors along x | +13.9, +18.1, +19.7 MB | refuted: the lifting transform already took the spatial correlation |
| along y | +6.4, +11.3, +12.1 MB | refuted |
| along t | +1.35, +2.10, +0.18 MB | refuted: real temporal structure, but the pivot shear costs more than it takes |
| each level's subbands row by row | −1,157,533 bytes | grouping by level helps |
| each level's subbands in shells of squared radius, each shell swept by angle | +658,073 bytes | this is NOT the golden spiral: it sweeps each shell in angle order, neighbor after neighbor, where the golden order (cell_tracking/maint/emit_spiral_table.py) ranks a shell by k(φ − 1) mod 1 so no direction repeats at any prefix. It refutes the angle sweep only; the golden order is untested here |
| 2 along t, each level apart | −1,987,962 bytes | helps on this sample |
| 2, 4, 8 along t rotated onto each level's line | −1.88, −1.63, −1.47 MB | refuted: rotation is worse than no rotation at every n |

## The e − 1 ratio

The ratio of the two savings (pairs along t over rectangles) is 1.717412 on 44b6_0113de3b, near e − 1 = 1.718281.

| sample | rectangles saved | pairs along t saved | ratio |
|---|---|---|---|
| 44b6_0b24845f | 478,803 | −3,970,121 | −8.29 |
| 44b6_0c582fdc | 552,737 | −241,482 | 0.44 |
| 44b6_0db75fae | 268,296 | −19,646,805 | −73.2 |
| 44b6_12dfb391 | 469,282 | −751,835 | −1.60 |

Settles: refuted. The first ratio is a coincidence, and pairing along t hurts on most samples.

## 2026-09-23

## A synthetic test of the lower bound

A synthetic set with a known generator, against which every code length can be checked: 32 frames of 32 × 32 (32,768 voxels); each voxel's noise is Binomial(2s + 16, ½), drawn as the popcount of xorshift64 bits, where s is a disc of signal peaking at 40; a fixed-pattern offset in [0, 8) per pixel. Raw is 7 bits a voxel. Every length is the bit length of an exact integer (a product of binomial coefficients, or a multinomial), with no float. The script is scratch (`experiment.py`), not in the tree.

| what | samples | result | settles |
|---|---|---|---|
| raw | the synthetic set | 229,376 bits | the reference |
| 1. the true bound: the generating model, told its parameters | the synthetic set | 120,441 bits | the bound for this source |
| 2. ours: per pixel, the offset and the spread fitted by exact code length in one pass, 9 bits of parameters a pixel counted in | the synthetic set | 128,805 bits, 7% above the true bound, all of it the parameters | the functionals reach the bound, less what stating them costs |
| 3. theirs: the previous frame as the prediction, one global table of residues coded enumeratively | the synthetic set | 144,386 bits | |
| 4. theirs taken through our functionals: the frame differences coded per pixel by exact length | the synthetic set | 145,093 bits | a model that differences frames doubles the noise it must code; our functionals do not rescue it |
| 5. the shortest of 2, 3 and 4 | the synthetic set | 128,805 bits: row 2 | any model is a candidate, and the pipeline keeps the shortest; the bound it reaches is ours |
| 6. the noise reverse engineered: the xorshift seed solved from the parity of each voxel's noise, by one GF(2) elimination | the synthetic set | the seed recovered exactly; 0 of 32,768 parity bits wrong when rebuilt | noise from a linear generator is 64 bits and a program, not a bound |
| 7. the same solver on os.urandom noise | the synthetic set | 16,346 of 32,768 wrong: half, a coin | true noise has no seed to find; what remains is the bound |

## The noise floor on 44b6_0113de3b

Read from the frames through `cell_tracking/maint/zarr_frames.py`, about 78 s a read. The scripts are scratch (`linear_complexity.py`, `conditional_floor.py`, `photon_transfer.py`, `coherence.py`), not in the tree. The tables in full, and the algebra behind each reading, are in [compression_table.md](compression_table.md).

| what | samples | result | settles |
|---|---|---|---|
| Berlekamp–Massey controls | os.urandom, 512 × 256 bits and 2,048 × 100; xorshift64, 64 seeds × 256 bits | urandom mean L 128.25 and 50.19, 0 low; xorshift L = 64 on all 64 | the test separates a linear generator from random bits every time |
| linear complexity, bits 0 to 5 | 44b6_0113de3b: 4,109 voxels in time (n 100), 1,024 rows of frame 50 (n 256), 4 raster runs (n 8,192) | mean L 50.22 to 50.24, 128.14 to 128.26, 4,096 to 4,097; 0 low in every direction | the low six bit planes carry no linear generator; indistinguishable from os.urandom (nonlinear generators untested) |
| linear complexity, bits 6 to 11 | the same | in time, mean L falls 48.72 → 43.48 → 36.68 → 26.56 → 19.43 → 1.79, low 201 → 4,024; along rows from bit 7 | structure begins at bit 6; bit 11 is almost constant |
| noise variance by signal level, from successive frame differences | 44b6_0113de3b, 4,109 voxels × 100 frames, by mean decile | from σ 7.6 at level 47.2 (variance / mean 1.22) to σ 218.7 at level 523.0 (variance / mean 91.43) | variance grows far faster than shot noise above the dimmest decile: the frame-to-frame change there is mostly cells moving, which the tracks predict |
| the conditional noise floor, motion left in | the same | 7.403 bits a voxel (46.3%) by each voxel's σ; 7.687 (48.0%) by empirical counts per σ bin | an upper bound for a temporal-only model; above the stream's 6.49 |
| one frame alone against its 4 neighbors, zeroth-order | frame 50, 462,400 voxels | 6.287 bits a voxel (39.3%) | a reference only: it uses neighbors on both sides, and no coder can spend it |
| the shot-limited noise floor, first estimate | extrapolated from the dimmest decile: variance = 1.22 × level at every decile | about 6.00 bits a voxel, 37.5% of raw | superseded by the two rows below |
| the photon transfer curve, motion removed in time | 44b6_0113de3b, 41,528 voxels (every 101st) × 99 differences, each binned by its pair's level; σ from the median absolute deviation | variance / level 1.15 to 1.35 from level 24 to 104, first and second differences agreeing; 1.55 at 120, 3.17 at 312, 45.85 at 504, a plateau near 170,000 past 700 | shot noise in the dim range; above 120 the change is in most frames, and the median cannot take it; the all-bins fit (138.4 × level − 23,437, 4.97 bits) is not a curve and is discarded |
| the same, structure removed by neighbor differencing | 44b6_0113de3b, 10 frame pairs of whole frames, 41,943,040 voxel-frames; the frame difference against its x, y and z neighbors | corr(d, d_x) 0.007 at level 24, 0.348 at 104, 0.680 at 200, 0.985 at 1000; var(d − d_x) / 4 at 1.17 to 1.23 × level from 40 to 200; fitted variance = 1.162 × level + 2.46 | the bright excess is structure, not noise; the noise is shot at gain 1.162 with read noise about 1.6 and no dark offset; the z correlation of 0.12 at the dimmest levels is not explained |
| F4, measured | the same | 5.902 bits a voxel (36.9%) by the photon transfer line; 5.979 (37.4%) less the x neighbor, robust; 6.008 (37.6%) best axis, plain; 6.913 (43.2%) structure in | one frame given everything else costs 5.90 bits a voxel; the stream's 6.49 is 0.59 above it: 3.7 points of raw, about 310 KB a frame |

## The noise floor on the 25 samples

The same two passes on the other 24; the per-sample table is in [compression_table.md](compression_table.md), and each reading cites its identity there.

| what | samples | result | settles |
|---|---|---|---|
| the photon transfer curve, motion removed in time | the other 24, 4 at a time, 714 s, 0 failed | the per-bin robust noise floor, structure partly in: 5.289 (44b6_341df25f) to 8.422 bits a voxel (18ced818) | the time pass alone cannot part structure from noise on bright samples; superseded by the coherence pass |
| the same, structure removed by neighbor differencing | the other 24, 2 at a time, 874 s, 0 failed | gain 0.821 to 1.162, mean 0.986; intercept −11.74 to 21.08, near zero on most; shot-only F4 5.085 to 6.973 bits a voxel, mean 6.229 (38.9%); the neighbor bound mean 6.243 (39.0%); structure in, mean 7.215 (45.1%) | one sensor noise model across the dataset, about one count a photon; the dataset's noise floor is 38.9% of raw, 3.1 points (0.492 bits a voxel, about 645 MB) under the compressed files' 42.0% |
| the constant regions against the photon transfer line | 44b6_0db75fae, 267148e4, 5740d24b | the neighbor bound 32.9%, 32.6%, 36.9% under the shot-only 34.5%, 35.6%, 38.4% | voxels that never change cost nothing, and the photon transfer line does not see them; the three are the engine ledger's constant-region samples |
| dim noise correlated in space | the 25, corr x of the frame difference at level 40 | below 0.11 on 21 samples; 0.761 on 44b6_267148e4, 0.354 on 668e0cc7, 0.150 on 5740d24b | a spatially correlated noise category on those three, not identified |
| bent fits | 44b6_12dfb391, 53f95252 | intercepts −11.74 and 21.08 | a straight line is not quite their law between level 40 and 200 |
