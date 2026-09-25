# Ledger

**Purpose:** Every measurement, in the order it was taken, with the samples it ran on, the number, and what it settled, so no result is taken twice and none is quoted without its run.
**Scope:** runs of the engine: its modules, its tests and its sims. Samples are named by their id; "the 25" means the first 25 44b6 training samples by name.

## 2026-09-21

### The cycle against the passes it replaced

| what | samples | result | settles |
|---|---|---|---|
| the residual from the imprinted key, lane for lane against the smoothing passes and the transform | the 25, 2,500 frames | 0 of 10,485,760,000 lanes differ | the key is the program (proved) |
| time a frame | the 25 | 31 ms, against 24.5 ms for the passes | the key is not yet faster; factor the binomial as [1 1]^n next |

### Bit flips on this machine

| what | result | settles |
|---|---|---|
| the tower undone in the spiral and ratio runs | 180, then 80 voxels differ, each one bit (0x0100, 0x0400) | the code was cleared first: a rerun holding the coefficients found 0 moved |
| 44b6_0b24845f and 44b6_341df25f, re-proved from their .iapx | one voxel each wrong in the file; the disk, read past the cache, holds the right value | the machine flips single bits in memory under load; both files had been written from a bad cached copy |
| fix | every .stack read for ingestion and proof now bypasses the file cache; both samples re-ingested and proved | a cached copy can no longer vouch for itself |

### The CRC-64 fold

| what | samples | result | settles |
|---|---|---|---|
| CRC-64/XZ folded into the tower's widen, against the plain byte by byte CRC | 44b6_0113de3b | both 363bf8bdffac8f29 | the fold is the CRC (proved) |
| every sample ingested with its CRC, then proved from the file alone | the 25 | 25 of 25 hold; 8,809,343,524 of 20,971,520,000 bytes, 42.0%; set CRC 091daa41e1aceb7e; the proof at will in 19 s | the per file check at will (proved) |

### The anchor bits

Per voxel and per bit, the frames of the 100 that carry the bit; the counts were written as .oapx and read back equal.

| what | result | settles |
|---|---|---|
| bits 0 to 4 | set in about 46% of frames at nearly every voxel, in every sample | the floor: these planes carry no anchor |
| bits 6 to 11, set in every frame | from 0 voxels (5 samples) to 76,646 at bit 10 (44b6_5f15d135) | anchors are real and differ per sample |
| any voxel anchored in every sample | none | the floor is per sample, not per set |

## 2026-09-22

### The compression, keymath and key_schedule splits

| what | samples | result | settles |
|---|---|---|---|
| compression split out of the tower: 44b6_0113de3b re-encoded | 44b6_0113de3b | the .iapx byte identical to the one before the split | the coder moved unchanged (proved) |
| every .iapx decoded by the split coder, from the file alone | the 25 | 25 of 25 hold; set CRC 091daa41e1aceb7e | the decoder moved unchanged (proved) |
| keymath and key_schedule split out of the cycle: the tracker run | 44b6_0113de3b, 44b6_0b24845f | edges identical; object files identical but for the embedded .cfg | the imprint and the layout moved unchanged (proved) |
| the residual's key, sized | | weights 1,130 words, 4,520 bytes, plus a 256 byte term table, standing for 268 unit steps a voxel: 112,407,347,200 step applications a sample | a key's size is the program's reach, not its use |

### The entropy history

Per voxel and per bit, the flips in each window of 11 transitions (9 windows over 100 frames), read from each sample's .iapx; one .oapx a sample, 288 MiB, each read back whole against its CRC-64. Tables in `cell_tracking/logs/entropy/44b6_25.txt`, summarised by `maint/entropy_summary.py`.

| what | samples | result | settles |
|---|---|---|---|
| the counts against the .stack, by hand in Python | 44b6_0113de3b, 2,000 voxels × 9 windows | 0 words differ | the history is exact (proved) |
| the projection | the 25 | 25 of 25 written and read back whole, about 3.4 s a sample | |
| the floor | the 25 | bits 0 to 3 at 499 to 500 flips per thousand transitions in every window of 19 samples; 350 to 499 in 6 | the floor is half the transitions, where every voxel moves |
| a constant region | 44b6_0db75fae, 1574802b, 267148e4, 5740d24b, 587a1e22, 668e0cc7 | bits 0 to 3 drop together, identically within a window (e.g. 350, 350, 350, 350): voxels whose value never changes. 5740d24b holds it from the start; 267148e4 grows it from window 3 to about 30% of transitions | a fixed pattern term read exactly, with no flips in any bit; its cause is not established |
| direction, bits 5 to 10 | the 25 | 12 samples move toward order (last window below the first), 13 toward the floor; peaks fall in different windows; 44b6_0db75fae falls 1,293 to 532 per mille, 44b6_668e0cc7 rises 684 to 1,421 | the direction is each sample's own; the window 4 bump on 44b6_0113de3b is that sample's, not the set's |

## 2026-09-23

### The period reading

`period_read` (M18 and A12 of [engine_table.md](engine_table.md)), graded by `test/period_test.cu` through `test/period_test.sh`. The random set is 64 uniform u16 volumes of 32 × 64 × 64, three axes each, 192 axes in all.

| what | samples | result | settles |
|---|---|---|---|
| the chance floor: P kept when its margin reaches Σc²/N² | the test's planted lattices; the random set | 431 checks, 0 failed; a period on 63 of 192 random axes (33%) | Σc² is unchanged by a rearrangement, so the floor passes noise; superseded by the drawn null |
| the drawn null: P kept only when its margin stands above every margin of d keyed shuffles of the same values (A12) | the same, at d = 8 | 502 checks, 0 failed; a period on 21 of 192 random axes (10.9%), against 1/(d + 1) = 1/9 | the false-period rate is the caller's to set with d (99 draws, 1%); the floor Doug ruled; its margin rule superseded by the local peak |
| the local peak: P and 2P each above both neighbour lags, the height the smaller rise, judged against the drawn null or a set-wide top from `period_draw` (A12) | the same at d = 8, the planted z grown from 20 to 24 slices; 16 smooth ramps with noise of 24 × 64 × 64 (48 axes) | 700 checks, 0 failed; a period on 6 of 192 random axes (3.1%), below 1/(d + 1) = 1/9; on 2 of 48 smooth-ramp axes (4.2%), where the margin rule read P = 2 or 3 on every axis of the 34 × 960 × 960 timing run | smoothness is no longer read as a period; one band serves the set, since 73,158 draws a series cost 152 ms each on 34 × 960 × 960 (RTX 3070), about 75,000 GPU-hours for the set; the rule Doug ruled, and whether one band is fair across shapes is Doug's call; its strongest-peak choice and global shuffle superseded by the fundamental and the per-axis null |
| the fundamental above a per-axis null: P the smallest local peak whose height clears the band top, the band drawn per axis by shuffling each line along that axis alone (A12) | the same at d = 8; `period_power` (M19) at 8 and 19 draws | 700 checks, 0 failed; the planted periods read exactly; a period on 5 of 192 random axes (2.6%) and on 3 of 48 smooth-ramp axes (6.3%); `period_power` 599 checks, 0 failed: from 64 e up x reads 5 on 32 of 32 at 19 draws (at 8 draws, 31 with 1 multiple at 256 e), and with the plant at 1,024 e the unplanted z and y read a period on 5 of 64 at 8 draws and 2 of 64 at 19 | the fundamental is read, not a multiple; the per-axis null holds the false-period rate when another axis carries a strong period; the rule Doug ruled; the per-axis null's cost is timed in the next row |
| the per-axis null's cost | 34 × 960 × 960 (31,334,400 voxels), a smooth ramp x + y + 2z plus uniform noise 0 to 63, RTX 3070; a scratch timing program, one run | `period_draw` 455.9 ms a call (mean of 8 after a warm-up; one count of the original, then a shuffle and a count on each of 3 axes); `period_read` 1,934.2 ms at 4 draws and 9,136.5 ms at 20, so 450.1 ms a marginal draw and 133.7 ms fixed (as the run printed them from the unrounded times); 2.96 times the global shuffle's 152 ms | one band serves the set the more: about 9.1 hours a series at 73,158 draws and about 223,000 GPU-hours for the 24,386 series (3.1 and 75,000 before), arithmetic from the measured draw, not a set run; host wall-clock with the syncs, and `period_draw` allocates on every call, so part may be allocation (not separated) |

### The sims

The first five sims of `engine/sims/` (M19 of [engine_table.md](engine_table.md); the sixth, `root_universal`, is under "The root universal" below, the seventh, `ask_state`, under "The ask and the state", and the eighth, `ka_psi`, under "Kolmogorov's inner function"), each an exact-integer GPU program run by `bash engine/sims/run.sh <sim>`, all under the one camera law of `sim_camera.h`. Every count below is the sim's own output; the ratios are measured, and a lane-for-lane equality is proved.

| sim | samples | result | settles |
|---|---|---|---|
| `nbody_lattice` | 24 frames of 20 × 96 × 96, 16 bodies (10 founders; divisions at frames 8, 12 and 16); gain 1, read variance 3, offset 100, fixed pattern 0 to 8 | 9 checks, 0 failed (11 with `--out`); the device truth equals the host's walk of each box, and the signal equals the host's on 4,423,680 of 4,423,680 lanes; the residuals sum to 3,271 against a spread of the square root of 636,863,096; their squares sum to 635,890,703 against 636,863,096 (0.99847) | the camera law renders exactly and holds its two moments; `lattice.npy` and `truth.tsv` are written, and the engine has not been run on them |
| `noise_floor`, the Kolmogorov mock (C11) | 4,096 streams of 512 bits from linear generators of degree 8 to 64 | Berlekamp–Massey within the degree on 4,096 of 4,096, each stream regenerated from its first L bits on 4,096 of 4,096; 286,744 of 2,097,152 bits (13.67%); keyed draws read 252 to 262 against 256 | a generated stream is found and described by its generator; the keyed draws read as random |
| `noise_floor`, the bit planes | 8,640 streams of 512 lanes a plane of the camera lattice | planes 0 to 8 random on 8,640 of 8,640 (mean L/n 0.5004); plane 9 on 850 (0.0638); plane 10 on 29 (0.0029); planes 11 to 15 on none | the camera lattice's planes 0 to 8 read as random; planes 11 to 15 have mean L/n below 0.0001 (printed 0.0000, truncated), and none of their streams reads as random; exactly zero is not shown |
| `noise_floor`, the photon transfer curve (C3, C7, C5) | 4,239,360 frame differences; planted g = 1, r² = 3 | truth route (4,226,574 pairs): slope 2.0046 against 2, intercept 5.643 against 6; data alone: slope 7.0460 against 1; neighbour coherence (4,195,200 pairs): slope 4.5292 against 1 | removing the motion by the truth recovers the planted gain (slope within 2%); the read-noise intercept, 5.643 against 6, is inside the ±6 check but not pinned by it; the data-only routes do not recover the gain, since sharp-edged moving bodies bias them |
| `noise_floor`, the neighbour correlation (C6) | the same differences, x against x + 1 | Σdd′/Σd²: −71,727/1,161,503,631 on truth-static pairs; 403,193,327/2,288,244,270 (0.1762) on every pair | the noise is uncorrelated between neighbours; the moving bodies correlate them |
| `period_power` (M18, A12) | a period 5 planted along x of 32 × 64 × 64, 32 volumes an amplitude, at 8 and 19 draws | under the strongest peak and the global shuffle, 599 checks, 1 failed on purpose; under the fundamental and the per-axis null, 599 checks, 0 failed (the tables below) | the strongest peak read a multiple and the global shuffle read periods on the unplanted axes; Doug ruled both fixed, and the fixes hold |
| `period_power`, an earlier check | the strongest plant then, 32 e, at 8 draws | exactly 5 on 15 of 32 volumes, so the check failed | replaced by "5 or a multiple", which holds at 1,024 e on 32 of 32 |
| `fixed_pattern` (ART-4-005 ported) | frame 8 × 8, 48 frames, swing 20, pattern 40, 8 draws, key 0xF17A | 10 checks, 0 failed; period 64 at 179.565 against its shuffle's 0.972 and a band top of 5.241; the residual equals the scene on 3,072 of 3,072 (100%); the wrong period 63 removes 0.2298%; no pattern (1.477) and impulses (2.064) declined; a static feature at depth 0, 5, 15, 30 leaves 100.0000%, 99.9263%, 99.3370%, 97.3480% | the fixed pattern is removed to the bit and only when it is there; a static scene feature goes with it |
| `classify_reject_recover` (ART-4-007 ported) | the same frame and draws, four cases | 7 checks, 0 failed; the fixed pattern found and removed exactly (3,072 of 3,072, 0 of 64 flagged); incoherent noise of variance 1,600 declined though its 3.523 at period 3 clears the band top of 3.294; impulses on a repeat exact on 64 of 64; incoherent noise of variance 144 on a repeat, 55 of 64 flagged and exact on 4 of the 9 where count and median agree | agreement of the two routes does not make a pixel exact: the mode and the median can agree on a wrong value |

The period reading's power, `period_power`: x reading 5, a multiple (10 or 15) or another lag, of 32 volumes, and the unplanted z and y reading a period, of 64 axes. Now, the fundamental above the per-axis null (A12):

| amplitude (e) | 8 draws: x 5 / multiple / other | 8 draws: z, y | 19 draws: x 5 / multiple / other | 19 draws: z, y |
|---|---|---|---|---|
| 0 | 1 / 0 / 4 | 7 | 0 / 0 / 2 | 4 |
| 2 | 0 / 2 / 2 | 9 | 0 / 1 / 0 | 2 |
| 8 | 0 / 2 / 1 | 7 | 1 / 0 / 0 | 3 |
| 16 | 10 / 6 / 0 | 8 | 8 / 5 / 1 | 2 |
| 32 | 26 / 3 / 0 | 10 | 25 / 4 / 0 | 4 |
| 64 | 32 / 0 / 0 | 4 | 32 / 0 / 0 | 3 |
| 128 | 32 / 0 / 0 | 3 | 32 / 0 / 0 | 4 |
| 256 | 31 / 1 / 0 | 5 | 32 / 0 / 0 | 3 |
| 1,024 | 32 / 0 / 0 | 5 | 32 / 0 / 0 | 2 |

Before, the strongest peak above the global shuffle (superseded):

| amplitude (e) | 8 draws: x 5 / multiple / other | 8 draws: z, y | 19 draws: x 5 / multiple / other | 19 draws: z, y |
|---|---|---|---|---|
| 0 | 0 / 1 / 3 | 6 | 0 / 0 / 2 | 3 |
| 2 | 0 / 0 / 1 | 7 | 0 / 1 / 0 | 2 |
| 8 | 0 / 5 / 2 | 7 | 0 / 0 / 1 | 3 |
| 16 | 2 / 14 / 0 | 7 | 4 / 8 / 0 | 2 |
| 32 | 8 / 20 / 0 | 7 | 11 / 17 / 0 | 3 |
| 64 | 10 / 22 / 0 | 7 | 12 / 20 / 0 | 6 |
| 128 | 13 / 19 / 0 | 8 | 14 / 18 / 0 | 9 |
| 256 | 11 / 21 / 0 | 13 | 10 / 22 / 0 | 9 |
| 1,024 | 11 / 21 / 0 | 23 | 14 / 18 / 0 | 10 |

The check that failed before is the unplanted axes' false periods within 5σ of 1/(draws + 1): at 8 draws the plant of 1,024 e put 23 of 64 against an expected 64/9. Under the per-axis null it is 5 of 64, and the check holds.

### The scheduler's steps and the lookup table

Doug's "increase the scheduler steps to n" and "implement the lut", built into the record machine (M10 and A13 of [engine_table.md](engine_table.md)) and graded by `test/record_table_test.cu` through `test/record_table_test.sh`, run as `build/20260923_204007_record_table_test`. The alphabet is the 16-bit one, and every case runs 4,096 random lanes.

| what | samples | result | settles |
|---|---|---|---|
| a table filled by running the ops over the whole alphabet, against the ops | x²; \|x − 30000\| + 100 | the table and the ops agree word for word, device and host | a pointwise step is exactly its table (proved on these two) |
| a table read through a table | f(x) = 65535 − x, g(y) = \|y − 30000\|, against the ops for \|35535 − x\| | the two tables, one table composed on the host, and the ops all agree; f read through g differs | composition keeps program order: it regroups, it does not reorder |
| register reuse, on against off | a 21-step additive chain (a field, then ten constant-and-sum stages) | the same output, from 3 limbs reused against 21 kept | a chain needs only its live registers, so the step count n (1,024) is held apart from the 256-limb file |
| the refusals | a 17-bit index on a 16-bit field; a table step naming a table that is not there | both refused at layout | a table cannot read past its source or outside the program's tables |
| all of it | the above | 15 checks, 0 failed | the table step and register reuse are proved; which functions to tabulate is open (item 3 of [kolmogorov_arnold.md](kolmogorov_arnold.md)) |

### The root universal

The tower with reversible lookup edges between its floors (M20 and A14 of [engine_table.md](engine_table.md); Doug, 23 September: bijective edges in the stream, not read-only taps). Graded by `test/tower_edge_test.cu` through `test/tower_edge_test.sh`, run as `build/20260923_210432_tower_edge_test`, and by the sixth sim, `root_universal`, run as `build/20260923_211054_sim_root_universal` on camera-law volumes (signal 200 e plus a ramp of 1 e a column, 6 moving bodies of 150 to 400 e, read variance 3, fixed pattern 0 to 8). The edges are not in the crystal path: `engine.cu` passes none.

| what | samples | result | settles |
|---|---|---|---|
| the edge test | one edge; stacked edges on one floor; an edge on every floor with the collapsed one; four bad edges; a clean edge after them | 20 checks, 0 failed: every edge program rebuilds the exact lanes, an edge changes the crystal, a non-permutation, a width of 0, a width of 21 and floor 50 are each refused, and the clean edge still round-trips | an edge is a bijection the lower undoes, and a bad one is refused before any device work (proved) |
| the Bennett edges (Doug, 23 September: "a dimensional expansion"), `build/20260923_213400_tower_edge_test` | \|x\| of an 8-bit two's complement field and x ≥ 100, each a 16-bit edge (8 bits of x, 8 of carrier), (x, y) → (x, y ⊕ f(x)); 64 lattices of 1 × 8 × 8 × 8 alternating the two on the collapsed floor; the two on floors 1 and 2; \|x\| laid bare on 16 bits | 25 checks, 0 failed (the 20 above and 5 new): round-trip on 64 of 64; f(x) read out of the carrier, x kept and the high bits passed, on 64 of 64; only the one coefficient touched on 64 of 64; floors 1 and 2 round-trip; \|x\| laid bare refused, since x and −x collide | a function that is not a bijection rides the reversible stream at the price of width, with no engine change (proved) |
| the root stays exact | 48 volumes, 24 of 4 × 12 × 48 × 48 (81 edges) and 24 of 3 × 13 × 37 × 41 (90 edges), 6 floors each; 1 to 6 edges a volume, widths 1 to 12 bits, one 20-bit edge per extent; lift, code, wipe, decode, lower | plain exact 48 of 48, edged exact 48 of 48, crystals changed 48 of 48 | the edges survive the whole crystal path (proved) |
| the fold keeps order | 8 volumes of 4 × 12 × 48 × 48, 8-bit edges a and b on floor 1 | a then b lays the crystal of the one table b(a(i)) on 8 of 8; b then a differs on 8 of 8; a on floor 1 and b on floor 2 differ on 8 of 8 | edges on one floor fold into one table in their order; a floor between them blocks the fold (proved) |
| the price of an unfitted edge | 8 volumes of 4 × 12 × 48 × 48, one keyed random permutation a floor, coded bits a voxel | below | exact is not free: the coder pays on the low floors, and on the collapsed floor the cost does not show at three decimals (measured); a fitted edge not measured |
| all of it | the above | `root_universal`: 1,268 checks, 0 failed | the root universal is built and proved in `tower`; its place in the `.kcr` is Doug's call |

The price, coded bits a voxel (6.802 with no edge; the coefficients each floor holds in brackets):

| width (bits) | floor 0 (110,592) | floor 3 (72) | floor 6, collapsed (1) | every floor |
|---|---|---|---|---|
| 2 | 6.810 | 6.802 | 6.802 | 6.808 |
| 4 | 6.908 | 6.802 | 6.802 | 6.911 |
| 8 | 8.719 | 6.804 | 6.802 | 8.742 |
| 12 | 12.608 | 6.817 | 6.802 | 12.714 |

### The ask and the state

The seventh sim, `ask_state` (M21 and A15 of [engine_table.md](engine_table.md); the terms are Doug's, 23 September), run as `build/20260923_213902_sim_ask_state`: a qubit carried exactly as the answers of a complete ask, E_i = (I + v_i·σ)/4, on the host with no GPU work. Rationals are on the exact integer; the SIC's numbers are in Q(√3), with (√3)² = 3.

| what | samples | result | settles |
|---|---|---|---|
| the two asks are complete | the rational tetrahedral ask, v = (±1, ±1, ±1)/2 with an even number of minus signs; the SIC, v = (±1, ±1, ±1)/√3 | each sums to the identity, is positive, and has a frame c·I: \|v\|² = 3/4 and frame I (r = 4 Σ p_i v_i); \|v\|² = 1 and frame (4/3)I (r = 3 Σ p_i v_i) | the state is read back from the answers alone (proved) |
| state → answers → state | 25 states: 21 pure (14 equator states from rational t, and rational points of the sphere), 4 mixed | 25 of 25 exact for each ask; the pure on the boundary 21 of 21, the mixed inside 4 of 4 | the complete ask is one to one on states (proved) |
| the crossings | the +x, +y and +z asks | (1 + r_a)/2 on 75 of 75 for each ask; weights onto +x 3/2, 3/2, −1/2, −1/2 and ½ ± ½√3 | the crossing is linear with a negative weight, so it is not classical total probability (proved) |
| the phase | the 14 equator states | all answer ½, ½ to the 0/1 ask; the complete ask tells apart 91 of their 91 pairs | the phase falls out of the ask (proved) |
| outside the valid set | (1, 0, 0, 0) | refused, no state; crosses onto +x at 3/2 and at ½ + ½√3 | no probabilities come of a distribution no state gives (proved) |
| the asks cross into each other | the SIC's answers into the rational ask's | 25 of 25 exact | (proved) |
| the valid set | the 455 distributions with denominator 12 | 55 states for the rational ask and 87 for the SIC; of the others, 104 and 72 still cross to probabilities on the x, y and z asks; recounted independently in exact fractions, the same | the valid set is stricter than the three axis crossings (measured) |
| all of it | the above | 33 checks, 0 failed | the ask and the state are exact on the host; Doug's countable numbers are theory, not built, and his sparse ψ is built in `ka_psi` (below) (A15) |

### Kolmogorov's inner function

The eighth sim, `ka_psi` (A15 of [engine_table.md](engine_table.md); the full reading is in "Kolmogorov's inner function, exactly" of [kolmogorov_arnold.md](kolmogorov_arnold.md); anchor_sift's), run as `build/20260923_221011_sim_ka_psi` in about 3 s here (the first three rows' lines are unchanged from `build/20260923_215902_sim_ka_psi`, 114 checks): the inner function ψ of Braun and Griebel's Theorem 2.1 at γ = 10, exact on the grids and, at depth, a sparse sum Σ c_j γ^−e_j with each e_j = β(L) an integer never expanded.

| what | samples | result | settles |
|---|---|---|---|
| Sprecher's ψ (2.4), n = 2 | ψ(0.58999), ψ(0.59) | 2207/4000 = 0.55175 and 11/20 = 0.55, the paper's (2.5); m_r read with the empty product as 1 (the literal typeset form gives 0.501) | Sprecher's ψ is not increasing (proved) |
| its descents | the 99,999 neighbouring pairs of D_5 | 10 descend, the first between 0.08999 and 0.09000; recounted independently in exact fractions, the same | (measured) |
| Köppen's ψ, (2.9) and (2.7) as printed, n = 2 and 3 | every point of D_1 to D_5 | the pair recursion equals the level recursion; strictly increasing; least gap γ^−β(L); widest gap G_L of G_1 = 1/γ, G_L = ½G_{L−1} − (s/2)γ^−β(L), s = 8 for (2.9) and 7 for (2.7); recounted independently, the same | both readings are strictly increasing on the grids (proved) |
| every scale | symbolic to L = 60 (n = 2, β = 2⁶⁰ − 1) and L = 38 (n = 3, β = (3³⁸ − 1)/2), both readings | the step keeps the order and the least gap stays γ^−β(L) on 59 of 59 and 37 of 37 levels; the widest gap stays above the least, at most 2^−(L−1)/γ and within Lemma 2.3; the symbolic G_L equals the measured gap on 4 of 4 | ψ extends to a continuous, strictly increasing function (proved) |
| a keyed deep point | depth 60 (n = 2), depth 38 (n = 3) | ψ of 55 and 57 terms (n = 2) and 36 (n = 3), its gap between the least and the widest | (proved) |
| the separation, Lemma 3.4 | ξ = Σ α_p ψ(d_p) on every point of D_kⁿ: n = 2 at k = 1, 2, 3; n = 3 at k = 1, 2 (up to 10⁶ points) | least gap at k = 1, in units of γ^−β(k+1), of 9.0999099999991… (n = 2, between (0.1, 0) and (0, 0.9)) and 9.0999099991… (n = 3), against the margin of 10; from k = 2, 49.50499999505… and 500,049.5000005… (n = 2) and 5,000 + 5 × 10⁻¹⁵ (n = 3); recounted independently in exact fractions, the same pairs | the lemma is false at k = 1 (proved) |
| the proof's step (3.11) | α cut at r ≤ k, the same grids | least gap 10, 50, 500,050 (n = 2) and 10, 5,000 (n = 3) units; recounted, the same | (3.11) holds, on the margin at k = 1; the tails, which do not annihilate it, still pull μ below (proved) |
| the corrected bound and the narrow ramp | \|μ_k\| ≥ γ^−nβ(k) − Σ_{p≥2} ε_{k,p}, ramp γ^−(β(k+1)+2); symbolically k = 1 to 57 (n = 2) and 1 to 35 (n = 3) | supports disjoint on 57 of 57 and 35 of 35 levels; with the paper's ramp γ^−β(k+1), on 0 of 57 and 0 of 35; the narrow ramp separates every grid tested, k = 1 included | Lemmas 3.7 and 3.8 hold at every k with the repair (proved, given (3.11)) |
| the shifts | m + 1 = 5 (n = 2) and 7 (n = 3) | a point sits in at most one gap a coordinate, so at least 3 and 4 shifts put it in a cube; with m + 1 = γ, two shifts share a gap | why γ ≥ m + 2 (the sim's check) |
| all of it | the above | 152 checks, 0 failed | the outer functions' contraction (Theorem 3.3) and ψ at the off-grid shifted points are not built |

### The exact integer: width, ladder and division

This tree's exact integer (`engine/base/no_rounding/exact_integer.{c,h}`, M1 of [engine_table.md](engine_table.md)) grew on 23 September. It gained an open width, a multiplication ladder, division, Newton's division and a Lehmer gcd, and the key machine gained the division as four record operations (M10). Doug, in order: "You have division", "2s compliment", "Mulmask exact", "add that to the exact arithmetic", "It makes no sense to not have infinite division with infinite mul", a link to Schönhage–Strassen, "We use karstsuba", "Expand the header to accept any n bits power of 2", "Static assert". The work is anchor_sift's. The engine build now compiles the exact integer from this tree by default, and this tree is the source anchor_sift's engine is to be copied from. An earlier cut of the division (Stein's binary gcd, no Newton, `build/20260923_222632_exact_divide_test`, 8 checks, 0 failed) is replaced. Every row below was re-run here on the merged source, between 23:47 and 23:56.

| what | samples | result | settles |
|---|---|---|---|
| the width | 1, 8 and 64 limbs compiled with declared floors of 9, 76 and 616 digits; 8 limbs with no floor; the tests at 128 limbs, 4,096 limbs and 4,194,304 bits | the three compile; the undeclared floor is refused at compile time (`exact_integer.h:151`); every test below passes at all three widths | any power of two from 32 bits up, with no ceiling, and a floor declared, never assumed (proved at those widths) |
| the ladder: long multiplication, Karatsuba from 32 limbs, the Schönhage–Strassen transform from 8,192 | `test/exact_transform_test` (`build/20260923_234836_exact_transform_test`, 4 checks, 0 failed at each width, 165 s): 24, 54 and 63 products, balanced and unbalanced, keyed and all ones, across every rung boundary up to half the width | the ladder, and the transform alone, equal a long multiplication kept in the test on every product | the product is exact on every rung (proved on the trials) |
| products divide back | the same products | each product divides back to its factors, exactly and with remainder, and the gcd holds a factor | (proved on the trials) |
| Newton's division: the reciprocal grown at half precision, one Newton step, corrected exactly | 24, 54 and 63 divisions, divisors to half the width | numerator = quotient · divisor + remainder, the remainder below the divisor and signed as the numerator, equal to the dispatched division | Newton's rung gives what long division gives (proved on the trials) |
| the rungs held apart | the same test with the transform, and then also Newton, raised past every size (`build/20260923_235121_exact_transform_test` and `build/20260923_235548_exact_transform_test`) | 4 checks, 0 failed at each width, both builds | Karatsuba alone and long division alone are exact too (proved on the trials) |
| long division, Knuth's algorithm D in base 2^32 | `test/exact_divide_test` (`build/20260923_234731_exact_divide_test`, 9 checks, 0 failed, at 128 limbs, 7 s): 200,000 trials of edge-shaped limbs (0, 1, 2^31 − 1, 2^31, 2^32 − 1 and 2^32 − 2 three times in four, a keyed draw otherwise), numerators up to 8 limbs; 4,000 trials at widths drawn up to 127 limbs | numerator = quotient · divisor + remainder, \|remainder\| < \|divisor\|, the remainder signed as the numerator, on every trial | the division is exact, rounding toward zero (proved on the trials) |
| the add-back step | a numerator and divisor built so the top-limb estimate runs one high | holds; anchor_sift confirmed the branch runs, with an instrumented copy | the rare branch is right (proved on the case) |
| exact division: the odd part's inverse by Newton's step x(2 − dx), a multiply and a mask | 20,000 products of drawn quotients and divisors up to 64 limbs, half the divisors with at least eight twos | the quotient returned on every product; one past each product refused as `ANCHOR_EXACT_NOT_EXACT` | (proved on the trials) |
| Lehmer's gcd (Knuth's algorithm L), which replaced Stein's binary gcd after its bit-at-a-time shifts stalled the 4,194,304-bit test | 4,000 pairs with a drawn shared factor, each part up to 32 limbs; 4,000 more against Euclid's gcd run on the long division | the gcd divides both, the shared factor divides it, and the cofactors' gcd is 1; it equals Euclid's on every pair; gcd(0, x) = \|x\| and gcd(0, 0) = 0 | (proved on the trials) |
| a zero divisor | both divisions | refused as `ANCHOR_EXACT_BY_ZERO` | (proved) |
| the record operations: quotient, remainder, gcd, exact quotient (ops 11 to 14) | `test/record_divide_test` (`build/20260923_234739_record_divide_test`, 15 checks, 0 failed, 58 s): 4,096 lanes of signed 160-bit numerators in the 64-limb register file, 512 lanes of 2,048-bit numerators in the 256-limb file | the device equals the host word for word; the division identities, the gcd and the exact quotient hold on every lane; a zero divisor and an inexact division refuse the lane on both; 3^40 divides exactly by 3^20 to 3^20; a quotient reading a later step is refused at imprint | the key machine divides exactly, on the device (proved on the lanes) |
| the sims on lowest terms | `sim_rational.h` reduced at every width by the gcd and exact division; `ka_psi` (`build/20260923_235412_sim_ka_psi`) and `ask_state` (`build/20260923_235440_sim_ask_state`) | 152 of 152 and 33 of 33, unchanged; `ka_psi` prints its values as fractions, 2207/4000 and 11/20 | the verdicts do not depend on the reduction (measured) |

The rungs' timings at 4,194,304 bits, seconds per call on balanced operands, on this host (x86-64, MSVC -O2), one reading each (**measured**). "A" is `build/20260923_235121_exact_transform_test`, with the transform held off the ladder so the ladder is Karatsuba alone. "B" is `build/20260923_235548_exact_transform_test`, with the transform and Newton both held off. At this width a call on small operands costs about 1e-4 s for a product and 4e-4 s for a division, because each call touches the whole width.

| limbs | long (B) | Karatsuba (A) | Karatsuba (B) | transform (A) | transform (B) |
|---|---|---|---|---|---|
| 2048 | 3.778e-3 | 9.537e-4 | 1.053e-3 | 1.634e-3 | 1.219e-3 |
| 4096 | 1.481e-2 | 3.771e-3 | 2.826e-3 | 3.845e-3 | 3.267e-3 |
| 8192 | 6.199e-2 | 8.055e-3 | 8.731e-3 | 9.175e-3 | 9.351e-3 |
| 16384 | | 2.435e-2 | 2.466e-2 | 2.387e-2 | 1.875e-2 |
| 32768 | | 9.734e-2 | 7.744e-2 | 6.453e-2 | 5.058e-2 |
| 65536 | | 2.301e-1 | 2.306e-1 | 1.244e-1 | 9.928e-2 |

| limbs, a 2n-limb numerator by an n-limb divisor, on Karatsuba alone (B) | long division | Newton's |
|---|---|---|
| 2048 | 4.757e-3 | 7.614e-3 |
| 4096 | 1.833e-2 | 2.311e-2 |
| 8192 | 7.256e-2 | 6.645e-2 |
| 16384 | 2.841e-1 | 1.966e-1 |
| 32768 | 1.116 | 5.746e-1 |
| 65536 | 4.302 | 1.719 |

The shape holds on both runs. Karatsuba leads the transform at 8,192 limbs, and the transform leads from 16,384. Long division leads Newton's from 32 to 4,096 limbs, and Newton's leads from 8,192. Below 32 limbs both sit at the width's floor. That is where the header puts `ANCHOR_EXACT_TRANSFORM_LIMBS` and `ANCHOR_EXACT_NEWTON_LIMBS`, both 8,192. The ratios move between readings. Karatsuba over the transform reads 1.020 and 1.315 at 16,384, 1.508 and 1.531 at 32,768, and 1.850 and 2.323 at 65,536. Long division over Newton's reads 1.092 at 8,192, 1.445 at 16,384, 1.942 at 32,768 and 2.503 at 65,536. anchor_sift's run, in the header, reads 1.44, 1.55 and 1.85 for the transform and 1.21, 1.06, 1.81 and 2.44 for Newton's. Two readings of one code path here differ by up to 1.198× (the default build's dispatched division and Newton's at 65,536, the same code), and one column read twice differs by 1.257× (Karatsuba at 32,768; the transform at 65,536, 1.253×). So a ratio within about 1.3× of 1 is not settled by one reading, and neither is the second decimal of any ratio here.

### Chaitin's Ω

`engine/sims/chaitin_omega` (anchor_sift's, 23 September; M19 of [engine_table.md](engine_table.md)) brackets Chaitin's halting probability for Tromp's binary lambda calculus. The machine reads a closed term, self-delimited in de Bruijn form, and halts where the term has a normal form. The codes are prefix free, so Ω, the sum of 2^−\|t\| over the halting terms, is a probability. Its first n bits settle the halting of every program of n bits or fewer, which is why no machine computes them all.

It runs on the device, one term a thread (`omega_kernel`, 24 September), on 16 host threads with the argument `cpu`, and, given L alone, on the engine's record machine (`omega_engine`). The runs here:

| run | budgets | build | checks |
|---|---|---|---|
| L = 30, the host | 2,048 steps and 2,048 tokens | `build/20260924_004819_sim_chaitin_omega` | 13, 0 failed |
| L = 33, the device | 2,048 and 2,048 | `build/20260924_004740_sim_chaitin_omega` | 14, 0 failed |
| L = 36, the device | 2,048 and 2,048 | `build/20260924_004859_sim_chaitin_omega` | 14, 0 failed |
| L = 36, the device | 256 and 256 | `build/20260924_004941_sim_chaitin_omega` | 13, 0 failed |
| L = 44, the device | 256 and 256 | `build/20260924_005020_sim_chaitin_omega` | 13, 0 failed |
| L = 16, the engine, a tessera job | 2,048 and 2,048 as printed | `build/20260924_024217_sim_chaitin_omega` | 16, 0 failed |
| L = 16, the host | 2,048 and 2,048 | `build/20260924_024434_sim_chaitin_omega` | 13, 0 failed |

The engine run at L = 16 (24 September) settles all 226 closed terms as halting, and it gives the host's L = 16 table line for line: 0.11664483… ≤ Ω ≤ 0.12600284…, with the lower bound equal to the halted mass plus the normal forms past L, and the upper to the lower less those normal forms plus the closed mass past L, both exactly (recomputed here from the printed binaries). Its checks are the host's 13, the job's admission and release, and one of its own: every term the engine settled, run again by `omega_run`, gives the same fate at the same step and the same normal form. No longer engine run is quoted here, so every longer bracket is the device's or the host's.

The host path has no device to compare against, so it lacks the cross-check. Budgets under 2,048 steps and tokens drop the strict busy beaver check, and both points are described below. The host runs of the day before give the same fates and bracket at L = 30 and 33. They are `build/20260924_001129_sim_chaitin_omega` (L = 30, 12 checks, 0 failed), `build/20260924_001207_sim_chaitin_omega` (L = 30 at 200,000 steps and 16,384 tokens, 12 checks, 0 failed) and `build/20260924_001712_sim_chaitin_omega` (L = 33, 12 checks, 0 failed). The device's L = 33 run gives the host's L = 33 table line for line, every fate, bound and busy beaver, champions included. These device runs shared the device with anchor_sift's 54-bit run, so their times are not quoted. L = 44 at 256 steps and tokens was run again on the idle device (`build/20260924_005724_sim_chaitin_omega`, an RTX 3070, 17,664 threads, 13 checks, 0 failed): the same fates in 28,080 ms, 120.8 million terms a second, against anchor_sift's 28,088 ms (**measured**). anchor_sift's reading of the threads (384 a multiprocessor ahead of 512 and 768 at 38 bits, the kernel bound by the cache) is not run here. The runs before the typed fate (`build/20260924_000606_sim_chaitin_omega` and `build/20260924_000643_sim_chaitin_omega`, 11 checks, 0 failed) gave the same fates and the same bracket at L = 30. A run before the growth proof (`build/20260923_235507_sim_chaitin_omega`) had 587 terms open and an upper bound of 0.12599323…. anchor_sift's hand conversion of that bound, 0.12597, was wrong and is corrected in the README.

A term is proven to grow forever (`omega_grows_forever`, 24 September) as follows. Since the watcher's last checkpoint, every step was a head step whose redex sat at spine position p or deeper. Then the checkpoint's spine part S at any position up to p was the only part reduced, and it never became a lambda eating an argument outside it. If S now stands deeper on the spine, S head-reduced to S B, and the same steps take S B to S B′ B and on without end. So S has no head normal form, neither has the term, and normal order never halts. The sim checks it on a term the earlier run left open: 01000101101010000101101010 grows forever.

A term left open, or past the space, is also tried for a simple type (`omega_simply_typed`, `OMEGA_TYPED`, 24 September): Hindley's unification with an occurs check. A simply typed term is strongly normalizing (Tait 1967), so it has a normal form and halts. A typed halt adds its mass to the lower bound. It does not write the normal form, so the busy beaver at its length stays unsettled. The same fact gives a check: no term proven to loop or to grow forever may type. At L = 30, 33 and 36, 0 terms are proven to halt by a type, and no loop or growth term types. So none of the open terms is simply typed, and the bracket is unchanged. At L = 44 one term is: the first typed halt.

The device takes every decision the host's run takes, in the same order, under budgets of at most 256 steps and 256 tokens, in a room of twice the token budget. A run is deterministic, and its budgets only stop it. So a halt, loop or growth found inside the device's budgets is found at the same step inside larger ones. A term that reaches a device budget smaller than the run's, outgrows the room, or halts in a normal form too large to key, is handed back. The host runs it under the full budgets. The fates are therefore the host's fates. A check holds it on every run: the host's own run of every term through 30 bits (or through L, when L is less) must give the device's fates and busy beavers, champions included. At L = 36, 2,048 steps and tokens handed 24,501 terms to the host, and 256 handed 75.

`--ledger <path>` plans the device's run as jobs, each length cut every 2^28 terms in rank order. Each finished job's exact tally is one flushed line: the budgets, the length, the job's first rank and count, the six fates, the contradictions, and the two busy beavers with their champions' ranks. A rerun under the same budgets keeps every whole line and runs only the missing jobs. A line with no line end, or one whose fates do not sum to its count, is not kept. Before a job's line is appended, a cut last line is given its line end. A test here at L = 31 (`build/omega_ledger_cut_verify_20260924_005246.tsv`) finds a gap in that (**measured**):

1. A first run writes 27 jobs.
2. The last line is cut inside its last field, the normal form champion's rank, 478256 cut to 47825.
3. The rerun runs that one job again, keeps 26, and appends the whole line after the cut one, now ended.
4. A third run keeps all 27, but the cut line comes first and is taken: the busy beaver at 31 still reads 267 bits, but its champion is the term of rank 47,825, not 478,256, and every check passes (14, 0 failed), since the cross-check stops at 30.

A cut anywhere before the last field leaves too few fields and is not kept, so the fates and the bracket are safe. Only a champion can be wrong. This is a known defect of the ledger, not fixed: Doug has asked for Ω to be run by the engine itself, the record machine, with no step, token or width limit, so the sim's ledger may be replaced rather than patched.

| what | samples | result | settles |
|---|---|---|---|
| the enumeration | every closed term through L bits, unranked from exact counts | the counts equal a parse of every code through 22 bits; every unranked term through 16 bits is one term of its length | the terms run are all the closed terms (proved against the parse through 22 bits; from there to L, the counts' recurrence) |
| the device against the host | every term through 30 bits run by both on each device run | the same fates and busy beavers, champions included, on every device run here | the device's fates are the host's (proved through 30 bits by the check; past 30, theory: a deterministic run that the budgets only stop, and every budget reached handed back) |
| the fates | 647,463 closed terms, run by normal-order reduction | 645,942 reach a normal form (a halt, proved); 934 return to a state they held under Brent's watcher (a loop, proved); 213 grow forever (proved); 374 stay open, 86 out of steps and 288 past the space at 2,048 steps and tokens, 47 and 327 at 200,000 steps and 16,384 tokens | 647,089 of 647,463 settled, 99.94% (measured); the larger budget settles no more |
| the typed fate | every open and outgrown term, and every loop and growth term, tried for a simple type | 0 typed at L = 30, 33 and 36; 1 at L = 44; no loop or growth term types | the typing adds nothing to the bracket through 36 bits (proved: Hindley's algorithm finds a type whenever one exists) |
| the fates at L = 33 | 3,910,730 closed terms, 2,048 steps and tokens | 3,900,966 halt; 5,663 loop; 1,180 grow forever; 2,921 stay open, 663 out of steps and 2,258 past the space; the device and the host alike | 3,907,809 of 3,910,730 settled, 99.93% (measured) |
| the fates at L = 36 | 24,325,850 closed terms, 2,048 steps and tokens, then 256 and 256 | at 2,048: 24,253,187 halt, 39,216 loop, 9,594 grow forever, 23,853 open (5,112 out of steps, 18,741 past the space); at 256: 24,253,078, 39,201, 9,070 and 24,501 (4,767 and 19,734) | 99.90% settled at 2,048 (measured); the smaller budgets leave 648 more open |
| the fates at L = 44 | 3,392,860,908 closed terms, 256 steps and 256 tokens | 3,379,796,187 halt; 1 halts by a type; 6,161,966 loop; 1,223,662 grow forever; 5,679,092 open (888,546 out of steps, 4,790,546 past the space) | 99.83% settled (measured) |
| the budgets | L = 36 at 2,048 and at 256 steps and tokens | the smaller budgets lower the lower bound by 3.19 × 10⁻⁹ (2^−28.2) and raise the upper by 2.18 × 10⁻⁸ (2^−25.5), against a gap of 0.00240096… (2^−8.7) | the budgets barely move the bracket at 36 bits (measured, from the exact dyadics) |
| the lower bound | the halted mass, plus the normal forms past L, which halt unrun | Ω ≥ 0.12254295… at L = 30, 0.12312353… at 33, 0.12358892… at 36 and 0.12443857… at 44 (256 and 256) | (proved) |
| the upper bound | the halted mass, the open mass and the closed mass past L, bounded by the parse's tail with directed rounding | Ω ≤ 0.12599214… at L = 30 (both budgets), 0.12599095… at 33, 0.12598988… at 36 and 0.12598796… at 44 (256 and 256), each the exact sum of its three parts | (proved) |
| the bits | the two bounds, exact 64-bit dyadics | lower < 1/8 ≤ upper at every L run, so Ω = 0.00… in binary | 2 bits of Ω proved; the third is not settled at L = 44 |
| BB λ | the busiest normal form at each length | 22, 24, 26, 30, 42, 52, 44, 58, 223, 160, 267, 298 and 1812 at 21 through 33 bits, and n at every length from 4 through 20 with a closed term: BusyBeaverWiki's values (OEIS A333479) at every length through 33 | under any budgets, a check at every length through the smaller of L and 33 that the run's value is at most the published one, and equal to it where every term halted; at 2,048 steps and tokens or more, equal at every such length. A length with an open term holds only a lower bound, and the published value is the true maximum, so meeting it means the run reached the champion (proved against the published values) |

From L = 30 to L = 44 the bracket narrows from 0.00344919… to 0.00154938… wide, with 1/8 still inside it. At 44 bits the lower bound is 0.00056142… below 1/8 and the upper 0.00098796… above it. The upper bound falls only by proven non-halting mass, and from 30 to 44 bits it fell by 0.00000418…, against the 0.00098796… it stands above 1/8. The lower bound rose by 0.00189562… over the same lengths (measured). anchor_sift reports a 40-bit run, made before the growth proof, that still leaves 1/8 inside the bracket. It is not run here, so its numbers are not quoted. A 54-bit ledger run was stopped at length 45 and gives no bracket.

The sources. The papers' titles, venues and pages were checked here against Crossref, and the table and the program at their pages; Barendregt's book is cited as anchor_sift gave it. Tait, "Intensional interpretations of functionals of finite type I", Journal of Symbolic Logic 32(2), 198–212, 1967: a simply typed term is strongly normalizing, the typed fate's basis. Wadsworth, "The relation between computational and denotational properties for Scott's D∞-models of the lambda-calculus", SIAM Journal on Computing 5(3), 488–521, 1976, and Barendregt, *The Lambda Calculus: Its Syntax and Semantics* (North-Holland, 1984): a term has a head normal form exactly when head reduction ends, the growth proof's basis. Thiemann and Sternagel, "Loops under Strategies", Rewriting Techniques and Applications 2009, 17–31: nontermination proved by a loop under a fixed reduction strategy, the kind of argument the growth proof makes for normal order. BusyBeaverWiki's BB λ table and OEIS A333479: the exact values 22 through 1812 at 21 through 33 bits, and 327,686 at 34. Tromp's `BB.lhs` (github tromp/AIT, `BB/`): it proves loops by a repeated redex in a term's history and by two self-replication shapes, `W W → H[W W]` and `W _ W → H[W _ W]`, reduces within 42,000,000 tokens, and stops at 36 bits.

## 2026-09-24

### π's hex digits on the engine

`pi_tower`'s BBP run on the record machine (M19 of [engine_table.md](engine_table.md), e340d08): each term a lane, a sweep one `cycle_record_run` of up to 70,656 lanes (the RTX 3070's resident threads), the sum reduced by a pair program on the same machine, and only the bits the error decides printed. Run from e340d08's source in a scratch build directory (`$TEMP/anchor_carry/build_pi`), not under `build/`. Neither tower, T or T⁻¹, is in the program (A13).

| what | samples | result | settles |
|---|---|---|---|
| the default request, resolutions 2^1 to 2^100, then the engine | hex positions 0, 999,999, 1,000,000, 9,999,999 and 99,999,999, and 9 for the cell at 2^100 | 41 checks, 0 failed; 243F6A8885A308D3…, 26C65E52CB4593…, 6C65E52CB459350050E4BB1…, 17AF5863EFED8D… and ECB840E21926EC…, each Bailey's published digits ("The BBP Algorithm for Pi", 2006, table 1 and its text), with 117 to 135 bits certified; the cell at 2^100, 0x5a308d313198a2e0, the exact turn's | the engine computes π's hex digits at a position without the digits before it (proved at those positions) |
| the rate | 10^7 and 10^8 terms | 142 sweeps in 0.371 s; 1,416 sweeps in 3.887 s, 340 steps a term lane on 49 register limbs | about 2.6e7 terms a second at 27-bit positions (measured) |
| 2^(2^30) cells, the deep path | hex position 268,435,440, 268,435,441 terms | 3,800 sweeps in 10.638 s, 2.52e7 terms a second; 127 bits certified; the cell's low 64 bits 0x8293097a8232c37f | the depth-2^30 turn read on the engine alone (measured; no second source checks it) |
| 2^googol cells, the deep path | n = 10^100, hex position 2.5e99; P = 3 × 10^100 + 64 bits, and a host turn would need SIM_EXACT_LIMBS = 2^331 | 46,844,928 of 2.5e99 terms in 663 sweeps and 64.043 s, 7.31e5 terms a second; stopped, no digit printed | at the measured rate the sum takes about 1.08e86 years; the cost is linear in the position (measured) |
| the tessera job | the default request and 2^(2^30); 2^googol | declared 3,413,540 bytes, peak 221,413,376 on both; 2^googol declared 11,542,512, its peak not read, since the run was killed | the declaration counts the sim's buffers and not the record kernel's per-thread file (measured) |

### The Gaussian step on the record machine

The Gaussian step is BBP's ×16 taken as eight floors of (a, b) ↦ (a − b, a + b), z = a + bi times 1 + i (A16 of [engine_table.md](engine_table.md); Doug, 24 September: "2 then 1").
- Graded by `test/record_gaussian_test.cu` through `test/record_gaussian_test.sh`, run from the working tree, uncommitted, as `build/20260924_222402_record_gaussian_test`.
- The program: two signed 24-bit fields, each floor one DIFFERENCE and one SUM, 18 steps, and every floor an output.
- The lanes: 4,096, every pair of the five edge values (0, −1, 1, −2^23 and 2^23 − 1), and keyed draws for the rest.

| what | samples | result | settles |
|---|---|---|---|
| the program | 18 steps over 2 fields | imprinted, laid and loaded; floor k is 24 + k bits wide, 25 to 32 | keymath widens each floor by one bit (proved) |
| device against host | 4,096 lanes | equal word for word | (proved on the lanes) |
| every floor against z(1 + i)^k | 4,096 lanes × 8 floors, the powers taken from their polar form | equal on every lane and floor | the floor is the Gaussian step (proved on the lanes) |
| four and eight floors | the same | −4z and 16z on every lane | eight steps are ×16, one hex digit (proved on the lanes) |
| parity | every floor | the two registers share their parity on every lane | each floor's image lies in the ideal (1 + i): one bit dropped a floor (proved on the lanes) |
| the width at floor 8 | the same | values in [−2^27, 2^27), 28 bits, with −2^27 reached; keymath carries 32 | the values grow half a bit a floor and the imprint a whole bit; the per-floor widths are derived in A16 (proved on the lanes at floor 8) |
| all of it | the above | 8 checks, 0 failed | the step runs exactly on the engine's record machine; it is in no engine module and not in `pi_tower` |
| A16's pole algebra, in floating point | a scratch script (`gaussian_check.py` in the session's temp directory, not in the tree); 1,001 points on [0, 1]; Simpson's rule at 200,000 panels | partial fractions and residues within 2.2e-15 of BBP's y-form, and the x-form within 3.6e-15 of its reduced form; the numerator below 5.4e-15 at ±i and e^{±3iπ/4}, and 16 and 22.6 at the other four roots; the integral within 3.3e-14 of the float π; the three pieces −2 ln 2, +2 ln 2 and π, each within 1.3e-14; the corners' widths at w = 24 are 25, 26, 27, 27, 28, 28, 28 and 28 bits | the hand algebra holds in floating point (measured; derived in A16, not run on the engine) |

## 2026-09-25

### keymath's widths by linear forms, and the record tests on tessera

keymath now carries every register as a linear form over atoms and takes the fewer of the operation's own width and the form's bound (A16 of [engine_table.md](engine_table.md); Doug, 25 September: "do the keymath rule"). The eight record tests were moved onto tessera (Doug, 25 September: the tests go through the scheduler).
- Each test is one job, submitted before its first device work and released at the end, its daemon built beside it by `maint/tessera_build.sh`.
- The eight were built and run one at a time at below-normal priority, from the working tree, uncommitted.
- An earlier run the same morning, under a narrower rule for a SUM and a DIFFERENCE over the same two registers, gave the Gaussian test the same widths.

| what | samples | result | settles |
|---|---|---|---|
| Gaussian | `build/20260925_012737_record_gaussian_test`; 4,096 lanes, 8 floors | 11 checks, 0 failed; widths 25, 25, 26, 26, 27, 27, 28 and 28, and some lane fills each one | the linear forms give 24 + ⌈k/2⌉, half a bit a floor, as the values grow (proved on the lanes) |
| guide | `build/20260925_012900_record_guide_test` | 12 checks, 0 failed | the worked example's widths hold |
| table | `build/20260925_013022_record_table_test` | 16 checks, 0 failed | (proved on the lanes) |
| divide | `build/20260925_013145_record_divide_test` | 20 checks, 0 failed | its pinned widths hold under the forms |
| bitwise | `build/20260925_013306_record_bitwise_test` | 25 checks, 0 failed | the narrowed widths 32, 20, 20, 32, 41, 41, 32 and 32 hold; the 700-floor stack and the lifting run |
| boundary | `build/20260925_013426_record_boundary_test` | 49 checks, 1 failed: the ring law ring_0 + 6n(1 − 2^{−ℓ}). The ring by floor is 1,536, 1,664, 1,696, 1,712, 1,720, 1,720, 1,712, 1,696 and 1,600. 4,096 of 4,096 lanes are rebuilt exactly, their heap mirrored at every floor and inside the ring | the ring is now ring_0 + n + 2n(1 − 2^{−ℓ}) (E4); the mirror law and the widest-at-the-crystal law hold |
| boundary, the law set | `build/20260925_020556_record_boundary_test` | the forward ring law set to ring_0 + n + 2(n − n/2^ℓ) for ℓ ≥ 1; the same ring by floor; 49 checks, 0 failed | every record test passes under the linear forms (proved) |
| coherence | `build/20260925_013651_record_coherence_test` | 15 checks, 0 failed; widest exact register 73 bits; 393,216 of 393,216 lane-widths agree three ways, and 73,728 of 73,728 for the odd divisors | (proved on the lanes) |
| order | `build/20260925_013814_record_order_test` | 18 checks, 0 failed | (proved on the lanes) |
| tessera | the eight jobs | declared or reserved: 148,013,056 (Gaussian, its peak kept from the earlier run), 24,368, 606,208, 720,896, 1,048,576, 33,554,432, 524,288 and 8,658,944 bytes; peaks 148,013,056, 143,818,752, 148,013,056, 613,584,896, 250,773,504, 647,139,328, 219,316,224 and 158,498,816 | every job is admitted and released; each peak passes its declaration, which counts only the test's own buffers (measured) |

### Finding x on floor 2

Finding x in a for less than half of a (Doug, 25 September: "say we want to find x and x is on floor 2, we have the knf, we only need to &&"; E4 of [engine_table.md](engine_table.md)).
- Graded by the sim `floor_match` (engine/sims), run from the working tree, uncommitted, as `build/20260925_015942_sim_floor_match`, a job on tessera.
- a is one 64³ camera-law frame, n = 262,144 samples. Floor 2 is the engine's: the tower lifts the frame, and the crystal's 16³ corner is lowered as its own tower.
- The index is floor 2 laid once as 16 bit planes of 128 words. A query ands the planes, lowest bit first, and a word stops once its mask is empty.

| what | samples | result | settles |
|---|---|---|---|
| floor 2 | m = 4,096 = n/64 values, 147 distinct | equal to the host's two-level lifting at 4,096 of 4,096; every value inside the 16-bit lane | the engine's floor 2 is the lifting's (proved) |
| the planes | 16 × 128 words | every bit of every floor-2 value held | (proved) |
| values on floor 2 | 1,024 drawn at keyed positions | 1,024 of 1,024 match sets equal the host's scan; 56.78 positions found a query on average, 83 at most; 1,173.85 plane words read on average, 1,340 at most | every occurrence found and no other (proved on the queries) |
| values not on floor 2 | 1,024 drawn over the lane | 1,024 of 1,024 found nowhere; 806.20 plane words read on average, 1,184 at most | (proved on the queries) |
| the reads | the 2,048 queries | at most 1,340 plane words, 5,360 bytes, against half of a, 131,072 samples, 262,144 bytes; without the early stop 2,048 words, n/128 | a query reads about 1% of half of a (measured); the lift reads all of a once to build the index |
| all of it | the above | 11 checks, 0 failed; tessera declared 3,956,736 bytes, peak 148,013,056 | the knf is not used: the planes are the index |

