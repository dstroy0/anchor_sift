# The compression table

**Purpose:** Track, set by set, the size the crystal reaches against the floor the data allows; the gap between the two is always a number and every change to the coder is judged against that gap.
**Scope:** The `.kcr` (the Kolmogorov information crystal, Doug, 23 September) and what it holds: the tower's coefficients, the stream, the deflated side bytes, and the seal. The coder is M9 of [engine_table.md](engine_table.md), and the seal is M13. Measurements come from [ledger.md](ledger.md), plus the RSNA session's own runs where they are named. Statuses follow [README.md](README.md).

## What "the floor" means here

The true floor is the Kolmogorov complexity K(x) of a set: the length of the shortest program that prints it. K is not computable; it cannot be measured directly. What can be measured is a ladder of bounds, each one exact for a named class of coder, and each lower than the one before as the coder is allowed to see more. The crystal's size is judged against the rung for the coder it actually is, and the next rung down shows what a better coder could still take.

| rung | the bound | identity | exact for | status |
|---|---|---|---|---|
| **F0. Raw** | the source's own bytes: 2 bytes a voxel in the u16 lane | none | nothing; this is the reference every percentage is taken of | measured on every set |
| **F1. Values, order 0** | ⌈log₂(n! / Π_v c_v!)⌉ bits over a sample's n voxels, where c_v counts the voxels holding value v, plus the bits needed to state the counts | C0 | any coder that treats the voxels as a bag of values and sees no position | theory |
| **F2. Coefficients, order 0, per floor** | Σ_f ⌈log₂(n_f! / Π_v c_{f,v}!)⌉ over the tower's floors f, plus each floor's counts | C0 | a coder that sees the tower's lifted coefficients floor by floor, each floor memoryless. This is the class the Rice coder belongs to; F2 is the bound it is judged against | theory |
| **F3. Coefficients in context** | the same count, taken per context: a coefficient's value given its neighbors already coded (the parent floor, the same place one frame back, the row before) | C0 | context coders: a coefficient coded given its neighbors | theory |
| **F3′. A two-part code** | the size of an exact representation of the set (its tables and sums, [kolmogorov_arnold.md](kolmogorov_arnold.md)) plus F2 of what that representation leaves | C2 | a coder that stores a model and then the residue the model does not predict; its length is an upper bound on K(x) | theory |
| **F4. The noise floor** | Σ over voxels of the entropy of that voxel's noise given everything else known: the set's deterministic terms, local coherence, and the level the voxel sits at. For noise of spread σ that is about log₂(σ·√(2πe)) bits a voxel, however many low bit planes look like coin flips | C1, read through C3 to C8; bounded by C10 and C11 | every coder: what is left of one frame after all structure is taken, the set's model paid once and so costing nothing per frame in the limit | measured on the 25: 6.229 bits a voxel, 38.9% of raw (31.8% to 43.6% by sample), from the photon transfer curve with structure removed by local coherence (sections below) |
| **F5. The integrated noise functionals** | Σ over voxels of the code length of each voxel's residue under the noise the category functionals describe there (next section): the source's own entropy once the functionals are the real categories | C0, C13 | a coder driven by the functionals' exact counts: exact arithmetic coding comes within 2 bits of this length over a whole stream, and enumerative coding in exact integers hits it exactly | theory: the plan below (Doug, 23 September) |

Each bound is an integer count of bits, and each is a bit length of an exact integer (a multinomial coefficient); no logarithm or float is needed to state it. The cost is size: at 419,430,400 voxels a sample, the multinomial runs to billions of bits. Computing F1 to F3 exactly at that size is open: the tool is not built, and neither is its method.

**What F4 says (corrected 23 September).** On all 25 44b6 samples, bits 0 to 3 flip 499 to 500 times per thousand transitions in every window of 19 samples, and 350 to 499 in the other 6. The earlier reading here counted those planes as a floor near 25% to 31% of raw. That undercounted: bits 4 and 5 are coin flips too (below), and counting uniform planes is not the floor anyway. The floor is the entropy of each voxel's noise at its own level, measured below on 44b6_0113de3b.

## The table's algebra

Every rung and every accepted reading holds to one of these identities, as each engine member holds to its A-number in [engine_table.md](engine_table.md). A reading that cites none is not accepted. Write a voxel's value in frame t as I_t = P + S_t + n_t: P its fixed pattern, S_t the structure (the bodies and whatever the tracks carry), and n_t the noise, independent between frames and between voxels, mean 0, variance σ²(L) at level L.

### C0. Exact counts (F1, F2, F3, F5)

n symbols with counts c_v have exactly n! / Π_v c_v! arrangements; the enumerative code (the stream's index among them) spends ⌈log₂(n! / Π_v c_v!)⌉ bits, and no code that sees only the counts spends less. It is the bit length of an exact integer, with no logarithm formed. F1 takes it over the values, F2 per floor, F3 per context, F5 per level under the functionals.

### C1. What one frame costs, given everything else (F4)

Integer values whose noise has spread σ ≫ 1 carry H ≈ ½ log₂(2πe σ²) bits (a Gaussian's entropy at unit step). For one frame of V voxels:

  F4 = Σ_v ½ log₂(2πe σ²(L_v)) bits,

and per voxel the mean of that sum. The Gaussian form is the working estimate; C0 taken per level is its exact form (F5).

### C2. The two-part code (F3′, F4)

For N frames, a code spends M + N·V·F4 bits, with M the model: P, the gain, the read noise, the tracks. Per frame that is M/N + V·F4, which goes to V·F4 as N grows. The model is the few words; the frame's own draw is the rest.

### C3. The frame difference removes the fixed pattern (the photon transfer curve)

d = I_{t+1} − I_t = ΔS + (n_{t+1} − n_t); P cancels exactly, and var(d) = var(ΔS) + 2σ².

### C4. The second difference removes linear drift (the photon transfer curve)

e = 2I_t − I_{t−1} − I_{t+1} = (2S_t − S_{t−1} − S_{t+1}) + (2n_t − n_{t−1} − n_{t+1}), with noise variance 4σ² + σ² + σ² = 6σ². Where S moves linearly in t, e holds noise only, and var(e)/6 = σ².

### C5. The neighbor removes smooth structure (F4 by local coherence)

For x the next voxel along a row, d − d_x = (ΔS − ΔS_x) + four independent noise terms; var(d − d_x) = var(ΔS − ΔS_x) + 4σ² ≥ 4σ². So σ² ≤ var(d − d_x) / 4, with equality where the structure changes the same at both voxels: an upper bound that tightens as the structure smooths.

### C6. Correlation separates noise from structure (F4 by local coherence)

White noise has no covariance with its neighbor; corr(d, d_x) = cov(ΔS, ΔS_x) / (var(ΔS) + 2σ²). It is 0 where there is no structure and goes to 1 where structure dominates.

### C7. The photon transfer curve (F4)

Shot noise counts photons; its variance is proportional to the signal: σ²(L) = g·(L − O) + R², with g the gain, O the dark offset and R the read noise. A line fitted as σ² = g·L + c has c = R² − g·O and meets zero at L₀ = −c/g. If O = 0, then c = R².

### C8. The robust spread (the photon transfer curve)

For Gaussian noise, the median absolute deviation × 1.4826 = σ. A body that crosses a voxel in a few of its frames moves the mean and the plain variance, but not the median.

### C9. The gap in units (every row's gap)

A stream of B bits a voxel sits (B − F4) / 16 of raw above the floor, and V·(B − F4) / 8 bytes above it per frame.

### C10. No combination of frames goes below their draws (F4)

N frames of independent k-bit draws have 2^(N·k) possible values. A stamp of k bits (an AND, an OR, an XOR, a sum) names only 2^k of them; a lossless code keeps the other (N − 1)·k bits somewhere. What every frame shares is read once: ∧_t I_t gives the bits set in every frame, and ∧_t ¬I_t the bits clear in every frame. Those are the anchor bits.

### C11. A reversible walk conserves bits (F4, the crystal)

Every lifting step is an integer bijection (A8); walking the scheduler's record back or forward maps each state to exactly one state and keeps its bit count. The record holds the ops (few bits) and the draw (V·F4 a frame). It shrinks to the ops alone only when the draw came from a program, as in the mock, where the draws recovered to a 64-bit xorshift seed.

### C12. Linear complexity (the low planes)

A random sequence of n bits has linear complexity L near n/2, and L ≤ n/2 − k with probability about 2^(−2k); the "low" mark at k = 8 is about 2⁻¹⁶. A linear generator with s bits of state has L ≤ s for every n.

### C13. The coder against the count (F5)

Exact arithmetic coding spends at most ⌈Σ −log₂ p⌉ + 1 bits over a whole stream, within 2 bits of the model's length. Enumerative coding (C0) spends exactly the count. A fixed-width range coder rounds each interval; it loses a sliver per symbol.

## The floor on 44b6_0113de3b (23 September)

All from the frames themselves, read through `maint/zarr_frames.py`. The scripts are scratch (`linear_complexity.py`, `conditional_floor.py`, `photon_transfer.py`, `coherence.py`), not in the tree.

**No linear generator in the low planes (C12).** Berlekamp–Massey gives the exact shortest linear feedback shift register over GF(2) that produces a bit sequence: its linear complexity L. Random bits give L near n/2. Any linear generator (xorshift, an LFSR, any linear congruential low bit) gives L at its state size, whatever n is. "Low" below means L ≤ n/2 − 8, which random bits reach with probability about 2⁻¹⁶.

| sequences | n | bits 0 to 5 | bit 6 | bits 7 to 10 | bit 11 |
|---|---|---|---|---|---|
| 4,109 voxels in time (every 1021st) | 100 | mean L 50.22 to 50.24; 0 low | 48.72; 201 low | 43.48 to 19.43; 646 to 2,925 low | 1.79; 4,024 low (almost constant) |
| 1,024 rows of frame 50 (every 4th z and y) | 256 | 128.14 to 128.26; 0 low | 128.26; 0 low | 127.83 to 78.82; 19 to 664 low | 6.60; 996 low |
| 4 raster runs of frame 50 | 8,192 | 4,096 to 4,097; 0 low | 4,095.75; 0 low | 4,096 to 4,543 | 0 |
| controls: os.urandom | 100 / 256 | 50.19 / 128.25; 0 low | | | |
| controls: xorshift64 | 256 | exactly 64 on all 64 seeds: caught every time | | | |

Bits 0 to 5 are indistinguishable from os.urandom in every direction the test reads. Structure begins at bit 6 and grows to bit 11. This rules out linear generators only; nonlinear ones are untested. The fixed pattern does not show here: it is an offset added below the noise, which scrambles into the low bits; it is read by the per-voxel mean, not by bit linearity.

**The noise at each level (the photon transfer curve, first pass; C3, C1).** The variance of each voxel is taken from successive frame differences (Σ (I_t − I_{t−1})² / 2(n − 1)), grouped by the voxel's mean over the 100 frames:

| decile | mean level | variance | σ | log₂(σ·√(2πe)) bits | variance / mean |
|---|---|---|---|---|---|
| 0 | 47.2 | 57.8 | 7.6 | 4.97 | 1.22 |
| 1 | 79.9 | 190.4 | 13.8 | 5.83 | 2.38 |
| 2 | 119.3 | 831.1 | 28.8 | 6.90 | 6.97 |
| 3 | 152.2 | 1,276.3 | 35.7 | 7.21 | 8.39 |
| 4 | 192.8 | 2,109.6 | 45.9 | 7.57 | 10.94 |
| 5 | 244.6 | 4,190.4 | 64.7 | 8.06 | 17.13 |
| 6 | 305.5 | 9,689.8 | 98.4 | 8.67 | 31.72 |
| 7 | 371.1 | 15,631.4 | 125.0 | 9.01 | 42.12 |
| 8 | 434.3 | 28,994.8 | 170.3 | 9.46 | 66.76 |
| 9 | 523.0 | 47,819.6 | 218.7 | 9.82 | 91.43 |

Shot noise has variance proportional to the level: variance / mean constant. Here it climbs from 1.22 to 91.43. So above the dimmest decile the frame-to-frame change is mostly not noise: it is the signal moving, bodies crossing the voxel between frames. That part is deterministic given the tracks, and it is what the set's model and local coherence remove.

| reading | bits a voxel | of raw |
|---|---|---|
| each voxel's own σ as measured, motion left in (upper bound on the temporal-only model) | 7.403 | 46.3% |
| the same, empirical counts of the residual from the 100-frame mean, per σ bin | 7.687 | 48.0% |
| one frame alone, residual from the mean of 4 neighbors, order 0 (uses neighbors on both sides; not a code length a coder can spend; a reference only) | 6.287 | 39.3% |
| shot-limited floor, first estimate: variance = 1.22 × level at every decile, the gain read from the dimmest decile | about 6.00 | about 37.5% |
| the stream as the `.kcr` wrote it | 6.49 | 40.6% |

The first estimate left two things open, the dark offset and whether the gain holds at every level. The next two passes settle both.

**The photon transfer curve, motion removed in time (C3, C4, C7, C8).** Each frame difference I_t − I_{t−1} is binned by its own level (the pair's mean, in bins of 16), not by the voxel's 100-frame mean, and σ is taken from the median absolute deviation; a body crossing a voxel in a few frames drops out. 41,528 voxels (every 101st) × 99 differences. The script is scratch (`photon_transfer.py`).

| level | 24 | 40 | 56 | 72 | 88 | 104 | 120 | 200 | 312 | 408 | 504 | 600 | 1000 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| robust variance, first difference / 2 | 27.5 | 53.9 | 70.3 | 89.0 | 109.9 | 133.0 | 185.7 | 396.8 | 989.1 | 2,858.6 | 23,107.6 | 62,254.9 | 173,220.9 |
| robust variance, second difference / 6 | 29.7 | 44.3 | 61.9 | 93.8 | 118.7 | 146.5 | 161.6 | 399.0 | 952.9 | 2,060.7 | 9,261.7 | 17,092.5 | 32,971.6 |
| variance / level | 1.15 | 1.35 | 1.26 | 1.24 | 1.25 | 1.28 | 1.55 | 1.98 | 3.17 | 7.01 | 45.85 | 103.76 | 173.22 |

From level 24 to 104 the ratio holds at 1.15 to 1.35 and both estimators agree: shot noise. Above 120 the change is present in most frames, not a few; the median cannot remove it, and the ratio climbs to a plateau near 170,000. A single line fitted over every bin (138.4 × level − 23,437) is not a photon transfer curve; the steep bins dominate it, and its floor (4.97 bits) is discarded.

**The same, motion removed by local coherence (C5, C6, C7).** Whether the bright excess is noise or structure is read from space: white noise does not correlate with its neighbor, moving structure does. The frame difference d is correlated with its x, y and z neighbors, per level, over 10 frame pairs of whole frames (41,943,040 voxel-frames); subtracting the neighbor cancels the smooth structure, and var(d − d_neighbour) / 4 is the white noise per frame that remains, an upper bound. The script is scratch (`coherence.py`).

| level | 24 | 40 | 56 | 72 | 104 | 136 | 168 | 200 | 248 | 296 | 344 | 408 | 504 | 1000 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| corr x of d | 0.007 | 0.031 | 0.090 | 0.178 | 0.348 | 0.462 | 0.586 | 0.680 | 0.772 | 0.822 | 0.865 | 0.913 | 0.948 | 0.985 |
| corr y of d | 0.012 | 0.039 | 0.098 | 0.186 | 0.353 | 0.468 | 0.592 | 0.686 | 0.776 | 0.823 | 0.864 | 0.911 | 0.945 | 0.984 |
| corr z of d | 0.116 | 0.123 | 0.176 | 0.258 | 0.399 | 0.493 | 0.589 | 0.657 | 0.712 | 0.734 | 0.758 | 0.787 | 0.819 | 0.916 |
| frame variance, structure in | 35.6 | 49.5 | 73.6 | 105.7 | 189.3 | 296.9 | 477.2 | 742.6 | 1,327.4 | 2,122.1 | 3,547.5 | 8,392.6 | 29,530.8 | 212,744.2 |
| white, less the x neighbor | 37.6 | 49.2 | 67.1 | 86.9 | 123.4 | 159.4 | 197.1 | 237.0 | 303.5 | 382.4 | 487.7 | 747.8 | 1,583.7 | 3,197.9 |
| white / level | 1.57 | 1.23 | 1.20 | 1.21 | 1.19 | 1.17 | 1.17 | 1.19 | 1.22 | 1.29 | 1.42 | 1.83 | 3.14 | 3.20 |

The bright excess is structure: the difference's correlation with its neighbor climbs from 0.007 at level 24 to 0.985 at 1000. With the neighbor taken off, what is left follows one line, 1.17 to 1.23 × level from 40 to 200, the same gain the time pass found in the dim range. Fitted there: **variance = 1.162 × level + 2.46**. The line meets zero near level −2: the data carries no dark offset, and the read noise is about 1.6 in the lane's units. Above about 300 the remainder climbs again, because one neighbor cannot cancel a sharp edge; that is structure a better predictor takes, not noise. The z correlation of 0.12 at the dimmest levels is the only departure from white noise, and it is not explained.

| reading, 44b6_0113de3b | identity | bits a voxel | of raw |
|---|---|---|---|
| the frame difference, structure in | C3, C1 | 6.913 | 43.2% |
| less the neighbor, best axis, plain | C5, C1 | 6.008 | 37.6% |
| less the x neighbor, robust | C5, C8, C1 | 5.979 | 37.4% |
| **the shot line, 1.162 × level + 2.46, at every voxel-frame's level (F4)** | **C7 fitted through C5, then C1** | **5.902** | **36.9%** |
| the stream as the `.kcr` wrote it; its gap to F4 | C9 | 6.49 | 40.6% |

**What it says.** One frame of 44b6_0113de3b, given everything else, costs 5.90 bits a voxel: shot noise at gain 1.162 and read noise near 1.6, with every other change in the frame spatially coherent and so structure. The stream spends 6.49, 0.59 bits a voxel above it: 3.7 points of raw, about 310 KB a frame (4,194,304 voxels), 30.9 MB over the sample. The functionals can still take that much on this sample. The shot line is taken as holding above level 300, where it cannot be read through the structure; a camera whose noise departs from shot there would move the floor up.

## The floor on the 25 (23 September)

The same coherence pass on each of the 25 (10 frame pairs of whole frames a sample, 874 s for the 24, 0 failed). The gain and intercept are fitted to var(d − d_x) / 4 from level 40 to 200 (C5, C7); the shot-only floor is C1 on that line at every voxel-frame's level. The neighbor reading is the robust x-neighbor bound (C5, C8, C1), and "structure in" is the frame difference alone (C3, C1). The script that fits and integrates is scratch (`shot_floor.py`).

| sample | gain | intercept | white / level, 40 to 200 | corr x of d at level 40 | shot-only F4 | less the neighbor | structure in |
|---|---|---|---|---|---|---|---|
| 44b6_0113de3b | 1.162 | 2.46 | 1.172 to 1.230 | 0.031 | 5.902 (36.9%) | 5.979 (37.4%) | 6.913 (43.2%) |
| 44b6_0b24845f | 1.035 | 2.49 | 1.045 to 1.123 | 0.057 | 6.973 (43.6%) | 6.963 (43.5%) | 8.158 (51.0%) |
| 44b6_0c582fdc | 0.973 | 2.42 | 0.981 to 1.104 | 0.024 | 6.368 (39.8%) | 6.457 (40.4%) | 7.365 (46.0%) |
| 44b6_0db75fae | 1.027 | 4.09 | 1.048 to 1.137 | 0.093 | 5.518 (34.5%) | 5.269 (32.9%) | 6.443 (40.3%) |
| 44b6_12dfb391 | 1.013 | −11.74 | 0.875 to 1.105 | 0.107 | 6.533 (40.8%) | 6.591 (41.2%) | 7.653 (47.8%) |
| 44b6_144b256d | 0.980 | 5.67 | 1.008 to 1.042 | 0.031 | 6.764 (42.3%) | 6.719 (42.0%) | 7.522 (47.0%) |
| 44b6_1574802b | 0.998 | 4.12 | 1.018 to 1.103 | 0.018 | 5.375 (33.6%) | 5.399 (33.7%) | 5.946 (37.2%) |
| 44b6_18ced818 | 0.833 | 13.34 | 0.903 to 1.071 | 0.054 | 6.822 (42.6%) | 7.076 (44.2%) | 8.558 (53.5%) |
| 44b6_1d530831 | 0.917 | 8.57 | 0.962 to 1.193 | 0.019 | 6.508 (40.7%) | 6.604 (41.3%) | 7.707 (48.2%) |
| 44b6_24264f12 | 1.011 | 3.43 | 1.030 to 1.165 | 0.004 | 6.056 (37.9%) | 6.140 (38.4%) | 7.008 (43.8%) |
| 44b6_267148e4 | 1.030 | 1.74 | 1.037 to 1.071 | 0.761 | 5.688 (35.6%) | 5.219 (32.6%) | 6.870 (42.9%) |
| 44b6_2a2eff9f | 1.007 | 7.24 | 1.046 to 1.212 | 0.002 | 6.445 (40.3%) | 6.448 (40.3%) | 7.396 (46.2%) |
| 44b6_2f31fc2f | 0.901 | 5.09 | 0.926 to 1.035 | 0.014 | 6.227 (38.9%) | 6.261 (39.1%) | 7.100 (44.4%) |
| 44b6_33b596bf | 0.961 | 4.28 | 0.984 to 1.137 | 0.002 | 6.062 (37.9%) | 6.142 (38.4%) | 7.057 (44.1%) |
| 44b6_341df25f | 0.978 | 0.22 | 0.962 to 1.006 | 0.016 | 5.085 (31.8%) | 5.086 (31.8%) | 5.366 (33.5%) |
| 44b6_3a861e03 | 1.118 | 0.85 | 1.101 to 1.245 | 0.064 | 6.289 (39.3%) | 6.273 (39.2%) | 7.268 (45.4%) |
| 44b6_3bb3690f | 0.904 | 7.13 | 0.941 to 1.160 | −0.003 | 6.541 (40.9%) | 6.579 (41.1%) | 7.265 (45.4%) |
| 44b6_40c45f5a | 0.855 | 8.64 | 0.897 to 1.095 | 0.008 | 6.517 (40.7%) | 6.633 (41.5%) | 7.540 (47.1%) |
| 44b6_415c0a3a | 1.068 | 4.91 | 1.092 to 1.198 | 0.011 | 6.513 (40.7%) | 6.521 (40.8%) | 7.350 (45.9%) |
| 44b6_53f95252 | 0.821 | 21.08 | 0.928 to 1.110 | 0.071 | 6.707 (41.9%) | 6.903 (43.1%) | 8.291 (51.8%) |
| 44b6_551a5dba | 0.951 | 1.82 | 0.957 to 1.035 | −0.006 | 6.781 (42.4%) | 6.904 (43.1%) | 8.155 (51.0%) |
| 44b6_5740d24b | 1.056 | 7.02 | 1.087 to 1.212 | 0.150 | 6.145 (38.4%) | 5.900 (36.9%) | 6.702 (41.9%) |
| 44b6_587a1e22 | 1.037 | 3.35 | 1.052 to 1.105 | 0.057 | 5.394 (33.7%) | 5.419 (33.9%) | 6.118 (38.2%) |
| 44b6_5f15d135 | 0.892 | 10.62 | 0.942 to 1.089 | 0.061 | 6.708 (41.9%) | 6.766 (42.3%) | 7.711 (48.2%) |
| 44b6_668e0cc7 | 1.130 | 2.35 | 1.142 to 1.185 | 0.354 | 5.806 (36.3%) | 5.823 (36.4%) | 6.920 (43.2%) |
| **mean of the 25** | **0.986** | | | | **6.229 (38.9%)** | **6.243 (39.0%)** | **7.215 (45.1%)** |

**What it says.**
- **One camera law across the set.** The gain runs 0.821 to 1.162, mean 0.986: about one count a photon, with the offset near zero on most samples. The floor varies by sample (31.8% to 43.6%) because the samples sit at different levels, not because the noise law changes.
- **The set's floor is 38.9% of raw.** Each sample is the same size; the set's F4 is the mean. The crystal holds the 25 at 42.0% (6.721 bits a voxel), 0.492 bits a voxel above the floor: 3.1 points of raw, about 645 MB of the 8.81 GB (C9).
- **Constant regions go below the shot line.** On 44b6_0db75fae, 267148e4 and 5740d24b the neighbor bound (32.9%, 32.6%, 36.9%) falls under the shot-only floor (34.5%, 35.6%, 38.4%). All three are samples the ledger found holding a constant region (21 September): voxels that never change cost nothing, and the shot line does not know them. The fixed-pattern functional takes that part, and F4 on those samples is the lower of the two.
- **A spatially correlated category.** On most samples the dim differences are nearly white (corr x at level 40 below 0.11 on 21 of the 25). 44b6_267148e4 (0.761), 668e0cc7 (0.354) and 5740d24b (0.150) are not: something moves whole neighborhoods together at the dimmest levels, frame to frame. It is a category the functionals must write (the spatially correlated row of the plan), and it is not yet identified.
- **Two fits to check.** 44b6_12dfb391 fits a negative intercept (−11.74), and 53f95252 an intercept of 21.08 with the lowest gain (0.821). Both lines bend inside 40 to 200; a straight line is not quite their law.

## The plan: noise departure by functionals (Doug, 23 September)

There is much more room to claim, by refining the spatial noise terms and the search. The algorithm can reach the theoretical floor universally if noise departure is treated carefully, with functionals. Once the real categories of noise are known, each gets its functional, and all of them are integrated.

**The claim, stated exactly.** K(x) is not computable; no algorithm reaches it on every input. What a coder can reach is the entropy of the source's true noise: Shannon's bound, the most any coder takes on average. A coder whose per-voxel counts come from functionals that describe the real noise reaches that bound, to within a constant, on every set those categories cover. "Universal" means exactly that: universal over the sets whose noise the category functionals describe. When a set needs a category the functionals lack, the gap to F5 names it.

**The categories to write functionals for.** The four noise vectors (noise_sieve_tower.md §16), each a deterministic functional of the sample, read and never assumed. Each is a sum of exact integers, with no float:

| category | how it moves | its functional, as exact sums over the sample | what the engine already measures |
|---|---|---|---|
| **fixed pattern** (offset and gain per place) | constant in time at a voxel | per voxel, the bits that never flip, and the per-voxel constant under the frames' mean | the anchor bits: set in every frame, different in every sample (**measured**) |
| **shot** (photon counting) | independent every frame; its spread grows with the signal | the photon transfer curve: Σ (I_t − I_{t−1})² against Σ I_t per level of the signal, both exact integers; a slope proportional to the level is shot | not taken |
| **read and thermal** | independent every frame; its spread does not depend on the signal | the same curve's intercept: the spread left at zero signal | not taken; bits 0 to 3 at 499 to 500 flips per thousand are its footprint together with shot and quantization (**measured**) |
| **quantization** | uniform within one step of the lane | exactly one step wide; the known part of the lowest bit | not separated |
| **spatially correlated** (rows, columns, banding, dust, hot pixels) | shared along a line or fixed at a place | per row and per column, the sum of the noise part; per place, a departure that holds across samples | the per-location cost map is theory (noise_sieve_tower.md §7) |

**Departure.** Where the history leaves the floor the functionals predict, something is there: a body, a split, a drive (noise_sieve_tower.md §17). The coder spends bits on departure only, and the search looks only there. The same functionals that set the floor also set what the search counts as a departure. So the null draws, the climb and the sift all read against the integrated floor instead of against one sample-wide reading.

**The coder that reaches F5.** The counts come from the functionals, and the coder spends Σ −log₂ p over the stream against them. How close it gets depends on its arithmetic:
- **Exact arithmetic coding** (the interval held as an exact integer of whatever width it needs) ends within 2 bits of that sum over the whole stream, however long.
- **Enumerative coding** in exact integers (the stream's index among every stream with the same counts) spends exactly ⌈log₂(n! / Π c!)⌉ bits: the F1 and F2 counts themselves, with no loss at all. It costs a big-integer multiply per symbol; the engine's exact integer is that machinery.
- **A fixed-width range coder** (32 or 64 bits) rounds each interval down to its width and loses a sliver per symbol, small but not zero. That is a rounding; it is the fast approximation to measure against the exact two, not the design.

**Two things the 2 bits does not cover.**
- It is 2 bits from the *model's* length. If the functionals miss a real category, the loss is the mismatch between the model and the data, and F5 sits above the true floor by that much.
- Stating the model costs bits of its own: the functionals' parameters and the count tables. That is the two-part code (F3′), and a model is worth its bits only where it saves more.

It replaces the Rice coder's fixed block, k and escape (the audit's debts) with the data's own counts.

**Order of work.**
1. Measure F2 on one sample; the Rice coder's own gap is known (the list at the end).
2. Take the photon transfer curve per sample from the frames: shot and read separated, as exact sums.
3. Write each category's functional, and the spatial ones per row, column and place.
4. Integrate them into a per-voxel count table: F5, measured.
5. Build the range coder on those counts and enter each set's crystal against F5. Any gap left names a category not yet written.

## The table

| set | samples | raw (F0) | crystal | of raw | seal's share | floor | gap | status | next |
|---|---|---|---|---|---|---|---|---|---|
| **Cell tracking, 44b6** | the 25 (first 25 44b6 training samples by name), 100 × 64 × 256 × 256 u16 each | 20,971,520,000 bytes | 8,809,343,524 bytes as `.kcr` (21 September, CRC era, before the seal) | 42.0% | not in these (CRC-64, 8 bytes a sample) | F4 38.9% (6.229 bits a voxel), the mean of the 25 measured one by one (above); F1 to F3 not measured | 3.1 points of raw: 0.492 bits a voxel, about 645 MB (C9) | measured, proved lossless (25 of 25 rebuilt, set CRC `091daa41e1aceb7e`) | Re-ingest the 25 as `.kcr` and take the size with the seal. Measure F2 per floor on 44b6_0113de3b first. |
| **Cell tracking, 44b6_0113de3b alone** | 1 | 838,860,800 bytes | stream 340,189,016 bytes as the `.kcr` wrote it (21 September) | 40.6% for the stream alone (6.49 bits a voxel) | none | F4 5.902 bits a voxel, 36.9% (shot line 1.162 × level + 2.46, structure removed by local coherence); bits 0 to 5 carry no linear generator (measured) | 3.7 points of raw: 0.59 bits a voxel, about 310 KB a frame, 30.9 MB over the sample | measured | F2 on the stream; the Rice coder's share of the 0.59 is known. Then the stream variants in the next table. |
| **RSNA knee, one series, unsigned** | 1 × 34 × 960 × 960 | 62,668,800 bytes | 25,218,496 bytes, sealed `7ac2cb89…12eb2a` | 40.2% | 5.4% of the crystal; 2.1% of raw at 960 columns | not measured | none | proved (rebuilt voxel for voxel, pixel for pixel, node for node) | F2 on it. |
| **RSNA knee, one series, signed** | 1 × 24 × 640 × 640 | 19,660,800 bytes | 11,319,416 bytes, sealed `3e70b8cb…8d9966` | 57.6% (the engine table rounded it to 57.5%) | in the crystal | not measured | none | proved | Why signed runs 17 points above unsigned: the lift by 2^15 into the u16 lane, or the data itself. Compare F1 on both. |
| **RSNA knee, test_series** | 15 series, 557 slices (the RSNA session, 23 September) | 599,191,552 bytes | 192,020,272 bytes | 32.0% | in the crystals | not measured | none | measured by the RSNA session: 15 of 15 held; the prove (696 ms) held every seal node; set root `98b25a42…d7af979` | Their train set, 24,371 series, is ingesting now to `E:\rk\train`. Enter its total when it lands. |
| **DICOM headers (the side bytes)** | the knee series | none | deflated by our own LZ77 and Huffman coder | within about 1% of zlib level 9 | none | zlib 9 is a reference, not a floor | about 1% | measured, round-tripped through our inflate and zlib | none |

The seal is overhead above any floor: it is the price of every node being placeable, and a lossless coder does not undo it. Measured on the knee at 5.4% of the crystal, it scales as 16/X of raw from the rows (X the row length); it runs larger on narrow rows.

## What has been tried on the coefficients

All on 44b6_0113de3b, against the 340,189,016-byte stream, each variant decoded back and checked (ledger, 21 September).

| what | stream change | status |
|---|---|---|
| radix around the line of 2, 4, 8 neighbors along x | +13.9, +18.1, +19.7 MB | refuted: the tower already took the spatial correlation |
| the same along y | +6.4, +11.3, +12.1 MB | refuted |
| the same along t | +1.35, +2.10, +0.18 MB | refuted: real temporal structure, but the pivot shear costs more than it takes |
| each floor's rectangles row by row | −1,157,533 bytes | measured: grouping by floor helps; not built into the coder |
| shells of squared radius, each swept by angle | +658,073 bytes | refuted for the angle sweep only; the golden order (k(φ − 1) mod 1, `maint/emit_spiral_table.py`) is untested |
| 2 along t, each floor apart | −1,987,962 bytes | measured on this sample; hurts on most others (the e − 1 rows below) |
| 2, 4, 8 along t, rotated onto each floor's line | −1.88, −1.63, −1.47 MB | refuted: worse than no rotation at every n |
| pairs along t over rectangles, the savings ratio | 1.7174 here, then −8.29, 0.44, −73.2, −1.60 on four more samples | refuted: a coincidence |

The Rice coder's own numbers are scale debts in the engine table's audit: `COMPRESSION_BLOCK` 64, 64 blocks a chunk, `COMPRESSION_K_BITS` 5, `COMPRESSION_ESCAPE` 24. They were chosen, not measured, and measuring each against F2 is how the coder's share of the gap is found.

## How to close the gap, in order

1. **Measure F2 on one sample** (44b6_0113de3b). The gap between the crystal and F2 is what the Rice coder alone leaves: its block size, its k and its escape against the counts. That share of the gap is recoverable without changing the tower.
2. **Measure F3 with the contexts the ledger already points at.** Grouping by floor (−1.16 MB) and pairs along t (−1.99 MB on this sample) are contexts. F3 says what the best such context can take, and so whether to build one.
3. **Settle F4.** Measured on 44b6_0113de3b at 5.902 bits a voxel (36.9%): bits 0 to 5 carry no linear generator, and the photon transfer curve with structure removed gives gain 1.162, read noise about 1.6, and no dark offset. Measured on the 25 at 6.229 bits a voxel (38.9%), gain 0.986 on average. Still to do: the shot line above level 300, where it is assumed and not read; the constant regions and the spatially correlated category (44b6_267148e4, 668e0cc7, 5740d24b) as functionals; the bent fits (12dfb391, 53f95252); the z correlation near 0.12 at the dimmest levels; nonlinear generator classes on the low planes.
4. **The noise functionals** (the plan above): the photon transfer curve, each category's functional, F5 integrated, and the range coder that reaches it.
5. **Build the coder the measurements pick**, and enter every set's new size in this table with its floor beside it.
