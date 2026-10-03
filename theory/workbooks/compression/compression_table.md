# The compression table

**Purpose:** Track, set by set, the size the crystal reaches against the floor the data allows. The gap between the two is always a number, and every change to the coder is judged against that gap.
**Scope:** The `.kcr` (the Kolmogorov information crystal) and what it holds: the tower's coefficients, the stream, the deflated side bytes, and the seal. The coder is M9 of [engine_table.md](../engine/engine_table.md), and the seal is M13. Measurements come from [ledger.md](ledger.md), plus the RSNA project's own runs where they are named. Statuses follow [README.md](README.md).

## What "the floor" means here

The true floor is the [Kolmogorov complexity](#src:Kolmogorov) K(x) of a set: the length of the shortest program that prints it. K is not computable, and it cannot be measured directly. What can be measured is a ladder of bounds, each one exact for a named class of coder, and each lower than the one before as the coder is allowed to see more. The crystal's size is judged against the rung for the coder it actually is, and the next rung down shows what a better coder could still take.

| rung | the bound | identity | exact for | status |
|---|---|---|---|---|
| **F0. Raw** | the source's own bytes: 2 bytes a voxel in the u16 lane | none | nothing; this is the reference every percentage is taken of | measured on every set |
| **F1. Values, order 0** | ⌈log₂(n! / Π_v c_v!)⌉ bits over a sample's n voxels, where c_v counts the voxels holding value v, plus the bits needed to state the counts | C0 | any coder that treats the voxels as a bag of values and sees no position | theory |
| **F2. Coefficients, order 0, per floor** | Σ_f ⌈log₂(n_f! / Π_v c_{f,v}!)⌉ over the tower's floors f, plus each floor's counts | C0 | a coder that sees the tower's lifted coefficients floor by floor, each floor memoryless. The Rice coder belongs to this class, and F2 is the bound it is judged against | theory |
| **F3. Coefficients in context** | the same count, taken per context: a coefficient's value given its neighbors already coded (the parent floor, the same place one frame back, the row before) | C0 | context coders: a coefficient coded given its neighbors | theory |
| **F3′. A two-part code** | the size of an exact representation of the set (its tables and sums, [kolmogorov_arnold.md](../engine/kolmogorov_arnold.md)) plus F2 of what that representation leaves | C2, C21 | a coder that stores a model and then the residue the model does not predict; its length is an upper bound on K(x) | theory; its tables are the table step (C21), proved in the engine (M10, A13; the section on built parts below), and the code itself is not measured |
| **F4. The noise floor** | Σ over voxels of the entropy of that voxel's noise given everything else known: the set's deterministic terms, local coherence, and the level the voxel sits at. For noise of spread σ that is about log₂(σ·√(2πe)) bits a voxel, however many low bit planes look like coin flips | C1, read through C3 to C8 and C14 to C20; bounded by C10 and C11 | every coder: what is left of one frame after all structure is taken, the set's model paid once and so costing nothing per frame in the limit | measured on the 25: 6.229 bits a voxel, 38.9% of raw (31.8% to 43.6% by sample), from the photon transfer curve with structure removed by local coherence (sections below) |
| **F5. The integrated noise functionals** | Σ over voxels of the code length of each voxel's residue under the noise the category functionals describe there (next section): the source's own entropy once the functionals are the real categories | C0, C13 | a coder driven by the functionals' exact counts: exact arithmetic coding comes within 2 bits of this length over a whole stream, and enumerative coding in exact integers hits it exactly | theory: the plan below |

Each bound is an integer count of bits, and each is a bit length of an exact integer (a multinomial coefficient). Stating it needs no logarithm or float. The cost is size: at 419,430,400 voxels a sample, the multinomial runs to billions of bits. Computing F1 to F3 exactly at that size is open: the tool is not built, and neither is its method.

**What F4 says.** On all 25 44b6 samples, bits 0 to 3 flip 499 to 500 times per thousand transitions in every window of 19 samples, and 350 to 499 in the other 6. Counting those planes as a floor, near 25% to 31% of raw, undercounts: bits 4 and 5 are coin flips too (below), and counting uniform planes is not the floor in any case. The floor is the entropy of each voxel's noise at its own level, measured below on 44b6_0113de3b.

## The table's algebra

Every rung and every accepted reading holds to one of these identities, as each engine member holds to its A-number in [engine_table.md](../engine/engine_table.md). A reading that cites none is not accepted. Write a voxel's value in frame t as I_t = P + S_t + n_t: P its fixed pattern, S_t the structure (the bodies and whatever the tracks carry), and n_t the noise, independent between frames and between voxels, mean 0, variance σ²(L) at level L. In C14 to C20, a row is a row of [the noise vector integration table](../engine/noise_vector_integration_table.md).

### C0. Exact counts (F1, F2, F3, F5)

n symbols with counts c_v have exactly n! / Π_v c_v! arrangements. The enumerative code (the stream's index among them) spends ⌈log₂(n! / Π_v c_v!)⌉ bits, and no code that sees only the counts spends less. It is the bit length of an exact integer, with no logarithm formed. F1 takes it over the values, F2 per floor, F3 per context, F5 per level under the functionals.

### C1. What one frame costs, given everything else (F4)

Integer values whose noise has spread σ ≫ 1 carry H ≈ ½ log₂(2πe σ²) bits (a Gaussian's entropy at unit step). For one frame of V voxels:

  F4 = Σ_v ½ log₂(2πe σ²(L_v)) bits,

and per voxel the mean of that sum. The Gaussian form is the working estimate; C0 taken per level is its exact form (F5).

### C2. The two-part code (F3′, F4)

For N frames, a code spends M + N·V·F4 bits, with M the model: P, the gain, the read noise, the tracks. Per frame that is M/N + V·F4, which goes to V·F4 as N grows. The model is the few words; the frame's own draw is the rest.

### C3. The frame difference removes the fixed pattern (the photon transfer curve)

d = I_{t+1} − I_t = ΔS + (n_{t+1} − n_t). P cancels exactly, and var(d) = var(ΔS) + 2σ².

### C4. The second difference removes linear drift (the photon transfer curve)

e = 2I_t − I_{t−1} − I_{t+1} = (2S_t − S_{t−1} − S_{t+1}) + (2n_t − n_{t−1} − n_{t+1}), with noise variance 4σ² + σ² + σ² = 6σ². Where S moves linearly in t, e holds noise only, and var(e)/6 = σ².

### C5. The neighbor removes smooth structure (F4 by local coherence)

For x the next voxel along a row, d − d_x = (ΔS − ΔS_x) + four independent noise terms, and var(d − d_x) = var(ΔS − ΔS_x) + 4σ² ≥ 4σ². So σ² ≤ var(d − d_x) / 4, with equality where the structure changes the same at both voxels: an upper bound that tightens as the structure smooths.

### C6. Correlation separates noise from structure (F4 by local coherence)

White noise has no covariance with its neighbor, which gives corr(d, d_x) = cov(ΔS, ΔS_x) / (var(ΔS) + 2σ²). It is 0 where there is no structure and goes to 1 where structure dominates.

### C7. The photon transfer curve (F4)

Shot noise counts photons, and its variance is proportional to the signal: σ²(L) = g·(L − O) + R², with g the gain, O the dark offset and R the read noise. A line fitted as σ² = g·L + c has c = R² − g·O and meets zero at L₀ = −c/g. If O = 0, then c = R².

### C8. The robust spread (the photon transfer curve)

For Gaussian noise, the median absolute deviation × 1.4826 = σ. A body that crosses a voxel in a few of its frames moves the mean and the plain variance, but not the median.

### C9. The gap in units (every row's gap)

A stream of B bits a voxel sits (B − F4) / 16 of raw above the floor, and V·(B − F4) / 8 bytes above it per frame.

### C10. No combination of frames goes below their draws (F4)

N frames of independent k-bit draws have 2^(N·k) possible values. A stamp of k bits (an AND, an OR, an XOR, a sum) names only 2^k of them. A lossless code keeps the other (N − 1)·k bits somewhere. What every frame shares is read once: ∧_t I_t gives the bits set in every frame, and ∧_t ¬I_t the bits clear in every frame. Those are the anchor bits.

### C11. A reversible walk conserves bits (F4, the crystal)

Every lifting step is an integer bijection (A8). Walking the scheduler's record back or forward maps each state to exactly one state and keeps its bit count. The record holds the ops (few bits) and the draw (V·F4 a frame). It shrinks to the ops alone only when the draw came from a program, as in the mock, where the draws recovered to a 64-bit xorshift seed.

### C12. Linear complexity (the low planes)

A random sequence of n bits has linear complexity L near n/2, and L ≤ n/2 − k with probability about 2^(−2k). The "low" mark at k = 8 is about 2⁻¹⁶. A linear generator with s bits of state has L ≤ s for every n.

### C13. The coder against the count (F5)

Exact arithmetic coding spends at most ⌈Σ −log₂ p⌉ + 1 bits over a whole stream, within 2 bits of the model's length. Enumerative coding (C0) spends exactly the count. A fixed-width range coder rounds each interval and loses a sliver per symbol.

### C14. Charge before the gain sits on the shot line (F4; rows 2 to 6)

Let a voxel collect, each frame, μ photoelectrons, D·Δt dark electrons and ε spurious ones, each a Poisson count and all before the gain. Let the offset O be added after the gain, with the level-free terms after the draw (read R², thermal σ²_J, reset σ²_kTC) independent and of mean 0. With one gain g for every electron,

  L̄ = O + g·(μ + D·Δt + ε),  σ² = g²·(μ + D·Δt + ε) + R² + σ²_J + σ²_kTC,

giving σ² = g·(L̄ − O) + R² + σ²_J + σ²_kTC exactly. Charge that enters as whole electrons before the gain moves a voxel along the transfer line and never off it. At one exposure, the dark level, the dark shot and spurious charge are read as light, and the line's intercept (C7), c = R² + σ²_J + σ²_kTC − g·O, holds none of them. Dark current is read only where the light is known to be zero. A bias frame (no light, no exposure) gives O as its mean and the level-free sum as its variance. A dark frame at Δt adds g·D·Δt to the mean and g²·D·Δt to the variance, and their ratio is g. No frame at one temperature splits R², σ²_J and σ²_kTC from each other.

### C15. The cumulant ladder of a gained count (F4, F5; rows 1, 12 and 15)

Let each electron give an independent output X in lane units, of one law for every electron, and let the count of electrons be Poisson with mean n̄. The output is a compound Poisson sum, whose cumulants are κ_r = n̄·E[X^r] for every r ≥ 1. Level-free terms added after the draw (C14) change no slope, and symmetric ones add 0 to every odd cumulant. Against the level, each cumulant is a line of slope

  s_r = E[X^r] / E[X],

giving s₁ = 1 and s₂ = g·F², with g = E[X] the gain and F² = E[X²] / E[X]² the excess factor (row 12). The transfer curve's slope (C7) is g·F², larger than g by the excess factor. One output for every electron (X = g) gives s_r = g^(r−1): F² = 1, and the rungs g, g², g³ the moment ladder is graded against (row 1). An electron-multiplying register's output for one electron is near exponential, with E[X^r] = r!·g^r. Then F² = 2, s₂ = 2g, s₃ = 6g² and s₃ = 3g·s₂.

The ladder is log-convex. For X ≥ 0, Cauchy–Schwarz gives E[X²]² ≤ E[X]·E[X³] and E[X³]² ≤ E[X²]·E[X⁴], and therefore

  s₃ ≥ s₂²,  s₂·s₄ ≥ s₃²,

each an equality only where every electron gives the same X. Both are cross-multiplied comparisons of fitted slopes, with no root or quotient formed. A ladder that breaks either is not one gained Poisson count plus symmetric level-free noise. The slope s₂ alone never splits g from F²; s₂ and s₃ together split them only once the single electron's law is named.

### C16. Thinning keeps a Poisson count Poisson (rows 13, 14 and 16)

If N is Poisson with mean λ and each of its events is kept independently with probability q, the kept count is Poisson with mean q·λ, and the kept and lost counts are independent: the generating function exp(λ·(z − 1)), taken at 1 − q + q·z, is exp(q·λ·(z − 1)). Quantum efficiency (row 14) and partition (row 13) thin the light. On Poisson light they only rescale its mean, and no reading of the frames names Q_e or a partition apart from the light's own rate. For any count with Fano factor f = var(N) / E[N], the thinned count's is

  f′ = 1 + q·(f − 1),

A thinning moves a count toward Poisson and never away, and partition is read only on a light whose f ≠ 1. The same identity splits a Poisson count among places. Photons scattered into the neighboring pixels before the draw (optical crosstalk, row 16) leave each pixel's count an independent Poisson count at its own blurred rate.

### C17. The structure function over lags (rows 7 and 10)

For noise stationary in t with autocovariance γ(k) at lag k, the structure function D(k) = E[(n_{t+k} − n_t)²] is 2·(γ(0) − γ(k)). White noise holds D(k) = D(1) = 2σ² at every lag k ≥ 1, and a random walk of step variance q holds D(k) = k·q. An octave held for 2^o frames, redrawn at every multiple of 2^o with variance v, adds 2v·min(k, 2^o) / 2^o, averaged over the frame's phase: it grows linearly to lag 2^o and holds there.

Taken less the x neighbor's difference, D_x(k) = E[(d_k − d_{k,x})²] with d_k = I_{t+k} − I_t. A term both voxels share additively cancels exactly, and each voxel's own terms add: for independent noise of one law, D_x(k) = 2·D(k). A scale a_t shared by the light (row 10) does not cancel. It adds (L − L_x)²·D_a(k), with D_a the scale's own structure function, which is zero only where the two levels are equal.

### C18. The row and column sums (rows 8, 9 and 10)

Take one frame pair's differences d over a set of voxels (the static ones). Let each be d = r + c + p + e, with r shared by the voxel's row, c by its column, p by its whole plane and e its own, all independent and of mean 0, with variances σ²_r, σ²_c, σ²_p and s. For two distinct voxels, E[d·d′] is σ²_r + σ²_p on the same row, σ²_c + σ²_p on the same column, and σ²_p otherwise. Write T = Σ d² over the M voxels. A squared sum less its own squares is the sum of its ordered pairs' products. Take A_row = Σ over rows of (Σ d)², less T; A_column likewise; A_plane = Σ over planes of (Σ d)², less T; and K_row, K_column and K_plane the ordered pairs each holds. Then

  E[A_row] = K_row·(σ²_r + σ²_p),  E[A_column] = K_column·(σ²_c + σ²_p),
  E[A_plane − A_row − A_column] = (K_plane − K_row − K_column)·σ²_p,  E[T] = M·(σ²_r + σ²_c + σ²_p + s),

for any count of voxels on any row or column, balanced or not. Each is a sum of integer products, and each variance follows by cross-multiplying over the common denominator M·K_row·K_column·(K_plane − K_row − K_column), as `noise_static_readings` does. The same three lines are E16's patterns ROWS, COLUMNS and PLANES in [engine_table.md](../engine/engine_table.md).

### C19. The single-electron tail (row 11)

Charge that enters as whole electrons before the gain joins the light's count (C14) and sits on every cumulant's line through the offset. With the level-free noise symmetric, every odd cumulant is then zero at the offset:

  κ₃ = s₃·(L̄ − O),  κ₂ = s₂·(L̄ − O) + R²,

with R² the whole level-free sum of C14. The two lines' intercepts c₂ and c₃ give O·s₃ = −c₃ and R²·s₃ = c₂·s₃ − c₃·s₂, cross-multiplied: the offset and the level-free sum apart, from frames at one exposure. A charge that does not enter as a whole electron before the gain (one made partway through the gain, which sees less of it) has its own output law X′ and rate ε′, both level-free. It adds ε′·E[X′] to the level and ε′·E[X′^r] to every cumulant. The offset κ₃ reads is O + ε′·(E[X′] − E[X′³] / s₃).

Spikes against dips read the same odd part. Where the joint law of the three frames around one is unchanged by the reflection x ↦ 2c − x, the reflection maps each spike at threshold h to a dip at h, and the expected counts are equal. The shot's own skew (s₃ > 0), a sparse tail and a body passing in one frame can each break that, and the two counts alone don't say which: row 11 is not separable here.

### C20. Crosstalk in the neighbor correlation (rows 16 and 17)

Electrical crosstalk shares a fraction α of each voxel's draw with its two neighbors along one axis after the draw: d′(v) = d(v) + α·(d(v − δ) + d(v + δ)). For d independent between voxels, with variance V,

  var(d′) = (1 + 2α²)·V,  cov(d′(v), d′(v + δ)) = 2α·V,  cov(d′(v), d′(v + 2δ)) = α²·V,

and 0 past two steps. The correlation is 2α / (1 + 2α²) at one step and α² / (1 + 2α²) at two, the same at every level, since it is a fixed fraction of whatever was drawn. With the crosstalk along x and V = 2σ², the neighbor route (C5) reads

  E[(d′ − d′_x)²] / 4 = σ²·(1 − 2α + 2α²),

where the raw route E[d′²] / 2 reads σ²·(1 + 2α²). A positive α lowers the neighbor route's slope and intercept by the same factor. Optical crosstalk scatters light before the draw, and by C16 the pixels' counts stay independent. It adds no correlation at any reach and shows only in the signal's edge spread (row 16). A correlation of the noise between neighbors (row 17) is sharing after the draw, and one that holds past the second step is not crosstalk of this form.

### C21. A pointwise step is its table (F3′; the table step)

Let f map the lane's alphabet A = {0, …, 2^b − 1} to w-bit values. Its table T_f holds f(a) at row a for every a in A. One pass of f over A fills it: 2^b evaluations, however many lanes it is read on afterward. For every lane x, T_f[x] = f(x) exactly, because the table is f's graph on A and x lies in A. One table read through another is their composition, T_g[T_f[x]] = g(f(x)), wherever f's values lie in g's alphabet. A chain of steps therefore folds into one table in program order. The fold regroups and does not reorder, since g∘f and f∘g differ in general. The table costs 2^b·w bits to state, once for the set. In the two-part code (C2) it sits in the model M, whose share per frame goes to 0 as the frames grow. Inside the reversible stream (C11), a table must be a bijection on its index bits. Any other f rides widened, (x, y) ↦ (x, y ⊕ f(x)), which is its own inverse for every f.

## The floor on 44b6_0113de3b

All from the frames themselves, read through `cell_tracking/maint/zarr_frames.py`. The scripts are scratch (`linear_complexity.py`, `conditional_floor.py`, `photon_transfer.py`, `coherence.py`), not in the tree.

**No linear generator in the low planes (C12).** Berlekamp–Massey gives the exact shortest linear feedback shift register over GF(2) that produces a bit sequence: its linear complexity L. Random bits give L near n/2. Any linear generator (xorshift, an LFSR, any linear congruential low bit) gives L at its state size, whatever n is. "Low" below means L ≤ n/2 − 8, which random bits reach with probability about 2⁻¹⁶.

| sequences | n | bits 0 to 5 | bit 6 | bits 7 to 10 | bit 11 |
|---|---|---|---|---|---|
| 4,109 voxels in time (every 1021st) | 100 | mean L 50.22 to 50.24; 0 low | 48.72; 201 low | 43.48 to 19.43; 646 to 2,925 low | 1.79; 4,024 low (almost constant) |
| 1,024 rows of frame 50 (every 4th z and y) | 256 | 128.14 to 128.26; 0 low | 128.26; 0 low | 127.83 to 78.82; 19 to 664 low | 6.60; 996 low |
| 4 raster runs of frame 50 | 8,192 | 4,096 to 4,097; 0 low | 4,095.75; 0 low | 4,096 to 4,543 | 0 |
| controls: os.urandom | 100 / 256 | 50.19 / 128.25; 0 low | | | |
| controls: xorshift64 | 256 | exactly 64 on all 64 seeds: caught every time | | | |

Bits 0 to 5 are indistinguishable from os.urandom in every direction the test reads. Structure begins at bit 6 and grows to bit 11. This rules out linear generators only; nonlinear ones are untested. The fixed pattern does not show here: it is an offset added below the noise, which scrambles into the low bits. The per-voxel mean reads it, and bit linearity cannot.

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

Shot noise has variance proportional to the level: variance / mean constant. Here it climbs from 1.22 to 91.43. So above the dimmest decile the frame-to-frame change is mostly not noise: it is the signal moving, bodies crossing the voxel between frames. That part is deterministic given the tracks, and the set's model and local coherence remove it.

| reading | bits a voxel | of raw |
|---|---|---|
| each voxel's own σ as measured, motion left in (upper bound on the temporal-only model) | 7.403 | 46.3% |
| the same, empirical counts of the residual from the 100-frame mean, per σ bin | 7.687 | 48.0% |
| one frame alone, residual from the mean of 4 neighbors, order 0 (uses neighbors on both sides and is not a code length a coder can spend; a reference only) | 6.287 | 39.3% |
| shot-limited floor, first estimate: variance = 1.22 × level at every decile, the gain read from the dimmest decile | about 6.00 | about 37.5% |
| the stream as the `.kcr` wrote it | 6.49 | 40.6% |

The first estimate left two things open, the dark offset and whether the gain holds at every level. The next two passes settle both.

**The photon transfer curve, motion removed in time (C3, C4, C7, C8).** Each frame difference I_t − I_{t−1} is binned by its own level (the pair's mean, in bins of 16), not by the voxel's 100-frame mean, and σ is taken from the median absolute deviation. A body crossing a voxel in a few frames drops out of it. 41,528 voxels (every 101st) × 99 differences. The script is scratch (`photon_transfer.py`).

| level | 24 | 40 | 56 | 72 | 88 | 104 | 120 | 200 | 312 | 408 | 504 | 600 | 1000 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| robust variance, first difference / 2 | 27.5 | 53.9 | 70.3 | 89.0 | 109.9 | 133.0 | 185.7 | 396.8 | 989.1 | 2,858.6 | 23,107.6 | 62,254.9 | 173,220.9 |
| robust variance, second difference / 6 | 29.7 | 44.3 | 61.9 | 93.8 | 118.7 | 146.5 | 161.6 | 399.0 | 952.9 | 2,060.7 | 9,261.7 | 17,092.5 | 32,971.6 |
| variance / level | 1.15 | 1.35 | 1.26 | 1.24 | 1.25 | 1.28 | 1.55 | 1.98 | 3.17 | 7.01 | 45.85 | 103.76 | 173.22 |

From level 24 to 104 the ratio holds at 1.15 to 1.35 and both estimators agree: shot noise. Above 120 the change is present in most frames, not a few. The median cannot remove it, and the ratio climbs to a plateau near 170,000. A single line fitted over every bin (138.4 × level − 23,437) is not a photon transfer curve; the steep bins dominate it, and its floor (4.97 bits) is discarded.

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

## The floor on the 25

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
- **The set's floor is 38.9% of raw.** Each sample is the same size, and the set's F4 is the mean. The crystal holds the 25 at 42.0% (6.721 bits a voxel), 0.492 bits a voxel above the floor: 3.1 points of raw, about 645 MB of the 8.81 GB (C9).
- **Constant regions go below the shot line.** On 44b6_0db75fae, 267148e4 and 5740d24b the neighbor bound (32.9%, 32.6%, 36.9%) falls under the shot-only floor (34.5%, 35.6%, 38.4%). All three are samples the engine's [ledger](../engine/ledger.md) found holding a constant region: voxels that never change cost nothing, and the shot line does not know them. The fixed-pattern functional takes that part, and F4 on those samples is the lower of the two.
- **A spatially correlated category.** On most samples the dim differences are nearly white (corr x at level 40 below 0.11 on 21 of the 25). 44b6_267148e4 (0.761), 668e0cc7 (0.354) and 5740d24b (0.150) are not: something moves whole neighborhoods together at the dimmest levels, frame to frame. It is a category the functionals must write (the spatially correlated row of the plan), and it is not yet identified.
- **Two fits to check.** 44b6_12dfb391 fits a negative intercept (−11.74), and 53f95252 an intercept of 21.08 with the lowest gain (0.821). Both lines bend inside 40 to 200. A straight line is not quite their law.

## The plan: noise departure by functionals

There is much more room to claim, by refining the spatial noise terms and the search. The algorithm can reach the theoretical floor universally if noise departure is treated carefully, with functionals. Once the real categories of noise are known, each gets its functional, and all of them are integrated.

**The claim, stated exactly.** K(x) is not computable: no algorithm reaches it on every input. What a coder can reach is the entropy of the source's true noise: [Shannon's bound](#src:Shannon), the most any coder takes on average. A coder whose per-voxel counts come from functionals that describe the real noise reaches that bound, to within a constant, on every set those categories cover. "Universal" means exactly that: universal over the sets whose noise the category functionals describe. When a set needs a category the functionals lack, the gap to F5 names it.

**The categories to write functionals for.** The four noise vectors (noise_sieve_tower.md §16), each a deterministic functional of the sample, read and never assumed. Each is a sum of exact integers, with no float:

| category | how it moves | its functional, as exact sums over the sample | what the engine already measures |
|---|---|---|---|
| **fixed pattern** (offset and gain per place) | constant in time at a voxel | per voxel, the bits that never flip, and the per-voxel constant under the frames' mean | the anchor bits: set in every frame, different in every sample (**measured**) |
| **shot** (photon counting) | independent every frame; its spread grows with the signal | the photon transfer curve: Σ (I_t − I_{t−1})² against Σ I_t per level of the signal, both exact integers; a slope proportional to the level is shot | **measured** on 24 of the kcr set: the slope g·F², rows 1, 12 and 15 of the noise vector integration table, from the exact sums of `noise_detector` (`noise_flicker_set`); the fit is scratch (`transfer_residual.py`) |
| **read and thermal** | independent every frame; its spread does not depend on the signal | the same curve's intercept: the spread left at zero signal | **measured** as the intercept's sum (rows 4 to 6); read, thermal and reset are not split at one temperature (C14); bits 0 to 3 at 499 to 500 flips per thousand are its footprint together with shot and quantization (**measured**) |
| **quantization** | uniform within one step of the lane | exactly one step wide; the known part of the lowest bit | **measured** by the value census (row 22) |
| **spatially correlated** (rows, columns, banding, dust, hot pixels) | shared along a line or fixed at a place | per row and per column, the sum of the noise part; per place, a departure that holds across samples | rows and columns **measured** by the static line sums (rows 8 and 9, `noise_lines_set`); hot pixels and dust **measured**, none found (rows 20 and 21); each shared term's pattern is priced by the root noise of a box (E16, proved on the `noise_root` sim); the per-location cost map is theory (noise_sieve_tower.md §7) |

**Departure.** Where the history leaves the floor the functionals predict, something is there: a body, a split, a drive (noise_sieve_tower.md §17). The coder spends bits on departure only, and the search looks only there. The same functionals that set the floor also set what the search counts as a departure. So the null draws, the climb and the sift all read against the integrated floor instead of against one sample-wide reading.

**The coder that reaches F5.** The counts come from the functionals, and the coder spends Σ −log₂ p over the stream against them. How close it gets depends on its arithmetic:
- **Exact arithmetic coding** (the interval held as an exact integer of whatever width it needs) ends within 2 bits of that sum over the whole stream, however long.
- **Enumerative coding** in exact integers (the stream's index among every stream with the same counts) spends exactly ⌈log₂(n! / Π c!)⌉ bits: the F1 and F2 counts themselves, with no loss at all. It costs a big-integer multiply per symbol; the engine's exact integer is that machinery.
- **A fixed-width range coder** (32 or 64 bits) rounds each interval down to its width and loses a sliver per symbol, small but not zero. That is a rounding. It is the fast approximation to measure against the exact two, not the design.

**Two things the 2 bits does not cover.**
- It is 2 bits from the *model's* length. If the functionals miss a real category, the loss is the mismatch between the model and the data, and F5 sits above the true floor by that much.
- Stating the model costs bits of its own: the functionals' parameters and the count tables. That is the two-part code (F3′), and a model is worth its bits only where it saves more.

It replaces the Rice coder's fixed block, k and escape (the audit's debts) with the data's own counts.

**Order of work.**
1. Measure F2 on one sample to learn the Rice coder's own gap (the list at the end).
2. Take the photon transfer curve per sample from the frames: shot and read separated, as exact sums. Taken on 24 of the kcr set: `noise_detector` takes the exact sums, and rows 1, 4 and 15 of the noise vector integration table hold the slope and the intercept. Read, thermal and reset stay one sum at one temperature (C14).
3. Write each category's functional, and the spatial ones per row, column and place. The rows, columns, planes, fixed pattern and stack term each have a pattern and a price in E16, proved on the sim. No functional is written.
4. Integrate them into a per-voxel count table: F5, measured.
5. Build the range coder on those counts and enter each set's crystal against F5. Any gap left names a category not yet written.

## The table

| set | samples | raw (F0) | crystal | of raw | seal's share | floor | gap | status | next |
|---|---|---|---|---|---|---|---|---|---|
| **Cell tracking, 44b6** | the 25 (first 25 44b6 training samples by name), 100 × 64 × 256 × 256 u16 each | 20,971,520,000 bytes | 8,809,343,524 bytes as `.iapx`, with a CRC-64 and no seal | 42.0% | not in these (CRC-64, 8 bytes a sample) | F4 38.9% (6.229 bits a voxel), the mean of the 25 measured one by one (above); F1 to F3 not measured | 3.1 points of raw: 0.492 bits a voxel, about 645 MB (C9) | measured, proved lossless (25 of 25 rebuilt, set CRC `091daa41e1aceb7e`) | Measure F2 per floor on 44b6_0113de3b. The `.kcr` re-ingest is the next row. |
| **Cell tracking, 44b6, as `.kcr`** | the same 25 | 20,971,520,000 bytes | 10,207,190,124 bytes as `.kcr`, sealed (set root `ad40e1d0…f53a39`, 757 s) | 48.6% | in the crystal, not taken apart | F4 38.9% (above) | not taken: the seal's share is in the crystal | measured: 25 of 25 held ([the cell build plan](../cell_tracking/build_plan.md), item 37); 44b6_587a1e22 fails its seal (the noise vector integration table) | Take the seal's share apart, then F2 per floor. |
| **Cell tracking, 44b6_0113de3b alone** | 1 | 838,860,800 bytes | stream 340,189,016 bytes as the `.iapx` writes it | 40.6% for the stream alone (6.49 bits a voxel) | none | F4 5.902 bits a voxel, 36.9% (shot line 1.162 × level + 2.46, structure removed by local coherence); bits 0 to 5 carry no linear generator (measured) | 3.7 points of raw: 0.59 bits a voxel, about 310 KB a frame, 30.9 MB over the sample | measured | F2 on the stream, to learn the Rice coder's share of the 0.59. Then the stream variants in the next table. |
| **RSNA knee, one series, unsigned** | 1 × 34 × 960 × 960 | 62,668,800 bytes | 25,218,496 bytes, sealed `7ac2cb89…12eb2a` | 40.2% | 5.4% of the crystal; 2.1% of raw at 960 columns | not measured | none | proved (rebuilt voxel for voxel, pixel for pixel, node for node) | F2 on it. |
| **RSNA knee, one series, signed** | 1 × 24 × 640 × 640 | 19,660,800 bytes | 11,319,416 bytes, sealed `3e70b8cb…8d9966` | 57.6% (57.5% in the engine table, a rounding) | in the crystal | not measured | none | proved | Why signed runs 17 points above unsigned: the lift by 2^15 into the u16 lane, or the data itself. Compare F1 on both. |
| **RSNA knee, test_series** | 15 series, 557 slices (the RSNA project) | 599,191,552 bytes | 192,020,272 bytes | 32.0% | in the crystals | not measured | none | measured in the RSNA project: 15 of 15 held; the prove (696 ms) held every seal node; set root `98b25a42…d7af979` | Their train set, 24,371 series: enter its total when its ingest completes. |
| **DICOM headers (the side bytes)** | the knee series | none | deflated by our own LZ77 and Huffman coder | within about 1% of zlib level 9 | none | zlib 9 is a reference, not a floor | about 1% | measured, round-tripped through our inflate and zlib | none |

The seal is overhead above any floor: it is the price of every node being placeable, and a lossless coder does not undo it. Measured on the knee at 5.4% of the crystal, it scales as 16/X of raw from the rows (X the row length), and it runs larger on narrow rows.

## What has been tried on the coefficients

All on 44b6_0113de3b, against the 340,189,016-byte stream, each variant decoded back and checked (ledger).

| what | stream change | status |
|---|---|---|
| radix around the line of 2, 4, 8 neighbors along x | +13.9, +18.1, +19.7 MB | refuted: the tower already took the spatial correlation |
| the same along y | +6.4, +11.3, +12.1 MB | refuted |
| the same along t | +1.35, +2.10, +0.18 MB | refuted: real temporal structure, but the pivot shear costs more than it takes |
| each floor's rectangles row by row | −1,157,533 bytes | measured: grouping by floor helps; not built into the coder |
| shells of squared radius, each swept by angle | +658,073 bytes | refuted for the angle sweep only; the golden order (k(φ − 1) mod 1, `cell_tracking/maint/emit_spiral_table.py`) is untested |
| 2 along t, each floor apart | −1,987,962 bytes | measured on this sample; hurts on most others (the e − 1 rows below) |
| 2, 4, 8 along t, rotated onto each floor's line | −1.88, −1.63, −1.47 MB | refuted: worse than no rotation at every n |
| pairs along t over rectangles, the savings ratio | 1.7174 here, then −8.29, 0.44, −73.2, −1.60 on four more samples | refuted: a coincidence |

The Rice coder's own numbers are scale debts in the engine table's audit: `COMPRESSION_BLOCK` 64, 64 blocks a chunk, `COMPRESSION_K_BITS` 5, `COMPRESSION_ESCAPE` 24. They are chosen, not measured, and measuring each against F2 is how the coder's share of the gap is found.

## Built in the engine, not yet in the crystal path

Each part is in `orior/src/engine`, with its proof in [the engine ledger](../engine/ledger.md) or [engine_table.md](../engine/engine_table.md). A crystal's size owes nothing to any of them.

| part | what it does toward the floor | proof | status |
|---|---|---|---|
| **The table step** (M10, A13; C21) | a pointwise function pushed over the lane's alphabet once and read back as a table; one table read through another is their composition. In a two-part code it is the model's part (F3′), stated once and read per lane | `record_table_test` (`test/engine/record_table_test.cu`): x² and \|x − 30000\| + 100 over the 16-bit alphabet, 4,096 lanes, the table and the ops agreeing word for word on device and host; a table read through a table against the composed ops; 15 checks, 0 failed | proved for the table step; square root and division as tables untested; not in the crystal path |
| **The tower's edges** (M20, A14) | a bijection on a floor's low index bits inside the reversible stream; any other function rides widened, (x, y) → (x, y ⊕ f(x)) | `tower_edge_test` (`test/engine/tower_edge_test.cu`), 25 checks, 0 failed, and the `root_universal` sim, 1,268 checks, 0 failed: lift, code, decode and lower exact on 48 of 48 | proved; `engine.cu` passes no edges. A keyed random edge costs 6.810 to 12.608 coded bits a voxel on floor 0 at widths 2 to 12, against 6.802 with none; a fitted edge not measured; its place in the `.kcr` is Doug's call |
| **The root noise of a box** (E16) | for each shared term (rows 8, 9, 10, 18 and 25 of the noise vector integration table), a pattern of floor means and its residual, which return the box exactly; the root is the term whose pattern and residual code smallest against the box | the `noise_root` sim, 72 checks, 0 failed: at variance 1,024 every term is the root, saving 32 to 89 per mille of the box's bits | proved on the sim; no driver part over real boxes, and the pattern is not stored in the crystal |
| **The lattice price** (`engine_lattice_bits`, engine.h) | the coder's bits for a lattice of ints, lifted by `tower_lift` and coded by `compression_encode` | the engine build compiles it | built, not yet run: nothing calls it until a driver part does |

## How to close the gap, in order

1. **Measure F2 on one sample** (44b6_0113de3b). The gap between the crystal and F2 is the Rice coder's own share: its block size, its k and its escape against the counts. That share of the gap is recoverable without changing the tower.
2. **Measure F3 with the contexts the ledger already points at.** Grouping by floor (−1.16 MB) and pairs along t (−1.99 MB on this sample) are contexts. F3 says what the best such context can take, and so whether to build one.
3. **Settle F4.** Measured on 44b6_0113de3b at 5.902 bits a voxel (36.9%): bits 0 to 5 carry no linear generator, and the photon transfer curve with structure removed gives gain 1.162, read noise about 1.6, and no dark offset. Measured on the 25 at 6.229 bits a voxel (38.9%), gain 0.986 on average. Still to do: the shot line above level 300, where it is assumed and not read; the constant regions and the spatially correlated category (44b6_267148e4, 668e0cc7, 5740d24b) as functionals; the bent fits (12dfb391, 53f95252); the z correlation near 0.12 at the dimmest levels; nonlinear generator classes on the low planes. Read on 24 of the kcr set, each measured and none yet a functional: the constant region (row 24 of the noise vector integration table), the dim z correlation (row 25) and the bending transfer curve (row 26).
4. **The noise functionals** (the plan above): the photon transfer curve, each category's functional, F5 integrated, and the range coder that reaches it.
5. **Build the coder the measurements pick**, and enter every set's new size in this table with its floor beside it.
