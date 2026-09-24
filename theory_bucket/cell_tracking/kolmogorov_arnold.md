# Kolmogorov and Arnold, held exactly

**Purpose:** Set the Kolmogorov–Arnold representation theorem beside the engine, part by part. The engine already has the theorem's shape in several places, arrived at by accident: sums of functions of one variable, fed through functions of one variable, stacked. This file says where that shape is, where it stops, and what finishing it would take; it can be finished deliberately.
**Scope:** The theorem, the networks built on it (KANs), and the engine parts that take its form: the tower (M9), the residual and the component tree (M2, M3), the key and the cycle (M10), the crystal (M9, [compression_table.md](compression_table.md)), the root universal (M20), and the theorem's inner function held exactly (the `ka_psi` sim). Statuses follow [README.md](README.md).

## The theorem, and what KANs did to it

**The theorem** (Kolmogorov 1957, Arnold 1957). Every continuous f on [0, 1]^n is a sum and composition of continuous functions of one variable:

  f(x_1, …, x_n) = Σ_{q=1}^{2n+1} Φ_q( Σ_{p=1}^{n} φ_{q,p}(x_p) )

The inner functions φ_{q,p} can be chosen once for every f; only the outer Φ_q depend on f. The statement is exact: an equality, not an approximation. Its catch is that the inner functions it guarantees can be very rough (nowhere differentiable), and for that reason it was long thought useless for computing.

**KANs** (Liu et al., 2024) take the shape and give up the exactness. A layer is a matrix of one-variable functions on the edges and plain sums at the nodes, x_{l+1,q} = Σ_p φ_{l,q,p}(x_{l,p}), stacked to any depth. Each φ is w · (SiLU(x) + Σ_i c_i B_i(x)), a smooth B-spline on a grid, and every coefficient is fitted in floating point by gradient descent. A KAN approximates f. Its splines are truncated to a grid, its SiLU is a float, and every sum and product rounds.

**The engine takes the other road.** It keeps the theorem's equality and gives up the fitting. Every function on an edge is an exact integer map, every node sum is exact in two's complement, and nothing rounds anywhere. That makes it not a KAN: it is the theorem's own form, held exactly, on the finite integer domain the data actually lives on. Where the engine is "imperfect", it is incomplete, not approximate.

## On a finite domain the theorem is exact and one term suffices

The engine's data never leaves a finite set of integers: a voxel is a u16 lane, a coordinate is below its extent. On a finite domain the representation needs no continuity argument and no 2n + 1 terms. With every x_p in [0, B):

  f(x_1, …, x_n) = Φ( Σ_{p=1}^{n} x_p · B^{p−1} )

The inner functions φ_p(x_p) = x_p · B^{p−1} are shifts. Their sum is the mixed-radix number of the point, which is a bijection onto [0, B^n); an outer Φ exists and equals f read at that number. It is arithmetic, not approximation: exact for every f (**proved** by construction; the mixed radix is a bijection).

This is also exactly what the engine's multi-limb keys do: they pack several quantities into one exact integer as radix digits. The component tree's key carries the face's name in its lowest limb below the residual's limbs (`max_tree_key_limb`), which makes every key distinct.

It also says where the difficulty went. The one-term form moves the whole of f into Φ, a table of B^n entries. The theorem's real content, on any domain, is that Φ and the φ can be *small*. KANs look for that smallness by fitting smooth functions. The engine looks for it by reading structure out of the data exactly: separability per axis, a period, a ladder of rungs. Both are the same search for a short description, which is Kolmogorov's other result (below).

## The engine as the theorem, part by part

| the theorem's element | the engine | exact? | status |
|---|---|---|---|
| an inner function φ on each input, then a node sum | **the tower's lifting steps.** Predict: h = x_odd − ⌊(x_left + x_right) / 2⌋ (tower.cu:60). Update: l = x_even + ⌊(h_before + h_after + 2) / 4⌋ (tower.cu:81). Each step adds to one value the outer function Φ(s) = ⌊s / 2^k⌋ of a node sum s of its neighbors; each step has the form x + Φ(Σ φ_p(x_p)) | yes. The quotient is an exact integer function, and the inverse subtracts the identical quotient; each step is a bijection on the integers (A8) | **proved**: 25 of 25 samples rebuilt voxel for voxel |
| layers stacked: Φ_{L−1} ∘ … ∘ Φ_0 | the tower's floors: 8 floors over t, z, y and x reach one coefficient for a 100 × 64 × 256 × 256 sample | yes | **proved** (same run) |
| a layer's edges as one-variable functions of each coordinate | **the residual.** L_n = [1 1]^n ∗ I is separable per axis, one one-variable convolution per axis composed, and R = 2^{\|b\|} L_s − L_{s+b} is a sum of two such terms (A1) | yes; the kernel sums to zero exactly | **proved**: 0 of 10,485,760,000 lanes differ from the step-by-step residual |
| the outer Φ after the sum | **the residual's readers.** P(x) = [R(x) > 0] and the dense rank c(x) of R(x) are one-variable monotone functions of the sum R (A2) | yes | built |
| KAN's B-spline basis B_i | **the binomial ladder.** [1 1]^n is the uniform discrete B-spline of order n: the n-fold convolution of the unit box, the definition of a uniform B-spline, taken on the integer grid with integer coefficients | yes: binomial coefficients, no float | an exact identity (standard); built as the ladder |
| KAN's grid extension: refine the spline grid without refitting | **one ladder's rungs.** B_s ∗ B_b = B_{s+b}; a finer or coarser B-spline is another rung of the same ladder, and a sweep that keeps its rungs gives every (s, b) in one pass (A1) | yes | theory: the ladder-keeping sweep is not built |
| a sum node in the network | **the cycle's fold.** Every term of the imprinted key is summed into each output lane in two's complement, one launch | yes | **proved** (the key against the passes, above) |
| a composed network is itself a function to compose again | **keys of keys.** A composed key is a step in another program (noise_sieve_tower.md §9) | yes | **proved** for linear keys |
| a general nonlinear φ on an edge | **a pointwise step as a table on the lane's alphabet.** Every value a lane can hold is pushed through the step once, and the table is the function (noise_sieve_tower.md §2). On a finite alphabet any one-variable function is exactly a table; no spline is needed and nothing is fitted | yes, by construction | theory: not built |
| KAN's SiLU base term, which takes whatever the spline does not | **the noise, determined and not absorbed**: the medium subtracted exactly, the residue held whole, and the floor measured per voxel and bit (the next section) | yes | **proved** (the residue lossless) and **measured** (the floor) |
| coefficients c_i fitted by gradient descent | nothing is fitted; a scale comes from the data (order = period, M2) or the request | none | absent, by the engine's rule (no chosen numbers) |

## Same skeleton, a different noise term

The skeleton is shared: one-variable functions on the edges, sums at the nodes, layers stacked (Doug, 23 September). The two part at the term that holds what the functions do not explain.

**In a KAN** each edge is w · (b(x) + spline(x)), with b = SiLU. The base term is one fixed function, the same on every edge of every network and for every dataset, chosen before any data is seen. Whatever the spline does not fit goes into it, or into the loss, as a residual error in floating point. Nothing says what that remainder *is*: it is minimized and then ignored.

**In the engine** the remainder is determined, three ways and exactly:
- **Subtracted.** The residual takes the medium out whole: R = 2^{|b|} L_s − L_{s+b}, whose kernel sums to exactly zero; a constant background leaves R unchanged and nothing of it survives as error (A1; **proved**, 0 of 10,485,760,000 lanes differ).
- **Held.** Every floor's highs, the residue, are kept whole in the crystal: never bounded, modeled or discarded, and rebuilt voxel for voxel (**proved**, 25 of 25).
- **Measured.** The entropy history measures the floor per voxel and per bit, as exact counts. On 44b6_0113de3b, bits 0 to 3 flip 499 to 500 times per thousand transitions in every window, at maximum entropy. Bits 5 to 10 fall from about 430 to about 20 where bodies hold them. The fixed pattern is the anchor bits, which never flip (**measured**; the counts **proved** on 2,000 voxels × 9 windows). The null draws read the field's own noise at a body's lag in frames far off in time; a body is real only where it stands above that reading (built).

So where a KAN has one generic base term and an unexplained remainder, the engine names the remainder at every voxel and bit and keeps every bit of it. That is also what makes the compression floor measurable ([compression_table.md](compression_table.md), F4): the noise is a measured quantity with a place, not a loss value.

| claim | status |
|---|---|
| the engine and a KAN share the skeleton: edge functions, node sums, stacked layers | the engine's instances are **proved** (the tower, the residual, the cycle); the skeleton is the theorem's |
| a KAN's base term is fixed and generic, and its remainder is minimized, never determined | the published construction (SiLU plus spline, fitted by loss) |
| the engine determines the remainder: subtracted exactly, held whole, and its floor measured per voxel and bit | **proved** (subtraction, residue) and **measured** (the floor) |

## Where it is incomplete, and what finishes it

1. **Nonlinear edges** (built, 23 September: the record machine's table step, M10 and A13 of [engine_table.md](engine_table.md)). The engine's other edges are linear: convolution taps, shifts, the lifting's neighbor sums. The theorem needs general one-variable functions. On the lane's alphabet these are exact tables: 2^16 entries a function for a u16 lane, built once by pushing every value through, and composable in program order. This is the LUT of noise_sieve_tower.md §2. **Proved** by `record_table_test`, 15 checks and 0 failed: x² and \|x − 30000\| + 100 as tables equal the ops on 4,096 lanes, device and host, and a table read through a table equals its composition and differs from it reversed. With it the partial form becomes the full one; which functions to tabulate is item 3. The tables also stand between the tower's floors (built, 23 September: M20 and A14, the root universal). Doug: "The tower is its own object, the lut is its own object, if we integrate them both we get a root universal." The tower is the additive skeleton, sums collapsed in order onto the floor, and an edge between two floors makes the collapse an outer sum with nonlinear edges (theory). **Proved:** 171 random edges on 48 camera-law volumes rebuild every lane through the whole crystal path, and two edges on one floor fold into one table in their order and no other. Two bounds hold it (theory). It is universal over the finite coefficient alphabet, every function of the indexed bits one table, exactly and not approximately; it is not the continuous-function theorem. And inside the reversible stream an edge must be a permutation; a table that is not a bijection (\|x\|, a comparison) rides widened: the Bennett embedding (x, y) → (x, y ⊕ f(x)) is a permutation of the pair for any f; the bound is one of width, b_x + b_y bits within 20, not of kind (Doug, 23 September: "a dimensional expansion"; **proved** by `tower_edge_test`, 25 of 25, A14).
2. **Outer functions beyond ⌊·/2^k⌋ and a threshold** (theory). The lifting's quotient and the residual's sign and rank are the outer functions in use. A general Φ is the same table machinery as item 1, applied after a sum.
3. **Choosing the functions without fitting** (open, Doug's call). A KAN finds its φ by descent, and the engine's rule forbids a chosen or tuned number. Two exact routes are open. The data can name the function the way it already names an order (a period read off the data). Or a fit can be solved exactly in rationals: least squares on integers has an exact rational solution through its normal equations; nothing rounds. Whether any fitted function belongs in the engine at all is Doug's ruling.
4. **Many terms, or one** (theory). On the finite domain one term suffices (above), but its Φ is huge. Keeping the functions small is the point; the target is the fewest terms and the smallest tables that hold f exactly. That size is measurable, which is item 5.
5. **The two Kolmogorovs meet in the crystal** (theory). The representation theorem is Kolmogorov 1957. The crystal's name, `.kcr`, is Kolmogorov 1965: the complexity K(x), the length of the shortest program that prints x. They meet here. A set held as an exact representation (the tables and sums of items 1 to 4) plus its exact residue is a two-part code: the model, then what the model does not predict. Its length bounds K(x) from above. An exact Kolmogorov–Arnold form of a set is a compressor, and every table it saves is bytes off the crystal. That adds a rung to the ladder in [compression_table.md](compression_table.md): the two-part code, the representation's size plus the residue's F2.

| claim | status |
|---|---|
| the tower's lifting steps have the theorem's form x + Φ(Σ φ_p(x_p)), exactly and invertibly | **proved** (25 of 25 rebuilt) |
| the binomial ladder is the uniform discrete B-spline basis, in integers | an exact identity; built as the ladder |
| on a finite integer domain the representation holds exactly with one term and radix inner functions | **proved** by construction |
| the engine is a KAN | **not so**: the same skeleton, but a KAN fits float splines, rounds throughout and absorbs its remainder in a fixed base term; the engine holds the theorem's form exactly, fits nothing, and determines its remainder |
| nonlinear edges as exact tables on the lane's alphabet complete the form | **proved** for the table step (`record_table_test`, 15 of 15; M10, A13); the functions to tabulate are open (item 3) |
| the tower with permutation edges between its floors, the root universal, rebuilds every lane and folds edges in order | **proved** (`tower_edge_test`, 25 of 25; `root_universal`, 1,268 of 1,268; M20, A14) |
| a function that is not a bijection rides the reversible stream through the Bennett embedding, at the price of width | **proved** (\|x\| and x ≥ 100 as 16-bit edges, 64 of 64; \|x\| laid bare refused; A14) |
| the root universal is universal over the finite coefficient alphabet, exactly | theory; it is not the continuous-function theorem |
| an unfitted edge's price, in coded bits a voxel | **measured**: 6.802 with none, 12.608 with a random 12-bit permutation on floor 0, no change at three decimals on the collapsed floor (M20); a fitted edge's price is not measured |
| an exact representation plus its residue is a two-part code that bounds K(x) | theory; a rung for the compression table |

## Kolmogorov's inner function, exactly

The continuous theorem, in Sprecher's version, is built on one inner function ψ. The constructive proof rests on two of its properties, that it is strictly increasing and that it is continuous. Sprecher's own ψ is not increasing. This section holds ψ exactly, in the engine's arithmetic, and proves both properties. It then tests the proof's next step, the separation of the inner sums (Braun and Griebel's section 3), finds it false at the first level, and repairs it. It is graded by the sim `ka_psi` (`engine/sims/ka_psi/ka_psi.cu`, `bash engine/sims/run.sh ka_psi`), run as `build/20260923_221011_sim_ka_psi`: 152 checks, 0 failed, about 3 s here. Items 1 to 3 print the same lines as the earlier build `build/20260923_215902_sim_ka_psi` (114 checks, 0 failed), and the separation adds the rest. The sim is anchor_sift's.

**The setting** (Braun and Griebel 2009, Theorem 2.1; A15 of [engine_table.md](engine_table.md)). Take integers n ≥ 2, m ≥ 2n, γ ≥ m + 2 and a = [γ(γ − 1)]⁻¹. Then f(x) = Σ_{q=0}^{m} Φ_q ∘ ξ(x_q), with ξ(x_q) = Σ_{p=1}^{n} α_p ψ(x_p + qa), α_1 = 1, α_p = Σ_{r≥1} γ^−(p−1)β(r) and β(r) = (nʳ − 1)/(n − 1). ψ is first defined on the terminating base-γ rationals D_k = { Σ_{r≤k} i_r γ^−r } and extended to [0, 1] as a limit. Here n = 2 and n = 3 with γ = 10, which meets γ ≥ 2n + 2.

**The arithmetic** (proved by construction). Every value on a grid is an exact integer over 2^L · γ^β(L). At depth, a value is a sparse sum Σ c_j γ^−e_j: each c_j an exact rational, and each e_j = β(L) held as an integer and never expanded (Doug, 23 September: "the exp is symbolic"). At level 60 for n = 2, β = 2^60 − 1 = 1,152,921,504,606,846,975, a number no expansion of digits could reach. A sign is decided exactly: the head is folded in until it outweighs a proven bound on the tail, and when the exponent gap is wide, bit lengths decide it. So every question of the form "is it past the limit" gets a true or false answer, not a rounded one.

1. **Sprecher's ψ fails, exactly.** Sprecher's ψ (Braun and Griebel's 2.4) at n = 2 and γ = 10 gives ψ(0.58999) = 2207/4000 = 0.55175 > ψ(0.59) = 11/20 = 0.55, the paper's (2.5) reproduced as exact rationals (**proved**). It is not increasing, and it descends between 10 of the 99,999 neighboring pairs of D_5, the first between 0.08999 and 0.09000 (**measured**). The paper's values need m_r = ⟨i_r⟩(1 + Σ_{s<r} [i_s] ⋯ [i_{r−1}]), the empty product counted as 1, as in Sprecher's own form; the sum as typeset in (2.4), with [i_1] = 0 and no leading 1, gives ψ(0.59) = 0.501. The sim takes the reading that reproduces (2.5), and an independent recount in exact fractions agrees on both values and on the 10 descents.
2. **Köppen's ψ, in both of its readings.** Köppen's correction is recursive on D_k. A level-L point whose last digit is γ − 1 is carried: it takes a midpoint of the level-(L − 1) values ψ and ψ⁺ on either side. The paper gives that midpoint two ways. (2.9)/(2.10), the form its proofs use, is ψ_L = ½ψ_{L−1} + ½ψ⁺_{L−1} + (γ − 2)/(2γ^β(L)), symmetric in the cell. (2.7) as printed puts i_k = γ − 1 inside the half, (γ − 1)/(2γ^β(L)). (2.9) averages ψ_L(d − γ^−L) with ψ_{L−1}(d + γ^−L). For n = 2 and n = 3 at γ = 10, on every point of D_1 to D_5 (10 to 100,000 points), in both readings (**proved**, exhaustively):
   - (a) the pair recursion, the scale step on (ψ, ψ⁺), equals the level-by-level recursion;
   - (b) ψ is strictly increasing on every neighboring pair;
   - (c) the least gap is exactly γ^−β(L);
   - (d) the widest gap equals G_L of the recursion G_1 = 1/γ, G_L = ½G_{L−1} − (s/2)γ^−β(L), with s = γ − 2 for (2.9) and s = γ − 3 for (2.7).
   An independent recount in exact fractions agrees on (b), (c) and (d) for every level, both n and both readings.
3. **Every scale, by chaining the one step.** Checked symbolically to L = 60 for n = 2 and L = 38 for n = 3 (β = 675,425,858,836,496,044), in both readings (**proved**):
   - the step keeps the order: γ^−β(L−1) > (γ − 1)γ^−β(L), on all 59 and 37 levels;
   - the least gap stays γ^−β(L): ½γ^−β(L−1) > ((γ + 1)/2)γ^−β(L), because γ^(n^(L−1)) > γ + 1;
   - the widest gap stays above the least and at most 2^−(L−1)/γ, and within Lemma 2.3's bound (½)^(L−2)[1/(2γ) + (γ − 2)γ^n/(γ^n − 2)];
   - the symbolic G_L equals the gap measured on D_2 to D_5, 4 of 4;
   - at a keyed depth-60 point (depth 38 for n = 3), ψ is a sparse sum out to exponent β(L), of 55 and 57 terms in the two readings for n = 2 and 36 for n = 3, and its gap ψ⁺ − ψ lies between the least and the widest.

**Why it holds, at every level** (proved by induction; the sim checks each step's inequality exactly). Inside a level-(L − 1) cell of width D, write u = γ^−β(L). The level-L points are ψ + i·u for i = 0 to γ − 2, then the carried midpoint M, then ψ⁺. Under (2.9) the two gaps beside M are each D/2 − (γ − 2)u/2. Under (2.7) they are D/2 − (γ − 3)u/2 and D/2 − (γ − 1)u/2.
- **The least gap.** g_L = min(u_L, ½(g_{L−1} − (γ − 1)u_L)) in the worst case, and g_1 = u_1. Since u_{L−1}/u_L = γ^(n^(L−1)) ≥ γ^n > γ + 1, induction gives g_L = u_L > 0: ψ is strictly increasing on every D_L.
- **The widest gap.** G_L = ½G_{L−1} − (s/2)u_L ≤ 2^−(L−1)/γ. Two points closer than γ^−L lie in one level-L cell or two neighboring ones; ψ moves by at most 2G_L between them, and that goes to 0: ψ is continuous.
- **The extension.** Between any x < y in [0, 1] lie two grid points d < d′ of some level, with ψ(d) < ψ(d′); the limit ψ on [0, 1] is strictly increasing as well as continuous.

**What it settles.** Both readings give a continuous, strictly increasing ψ; the (2.7)/(2.9) discrepancy changes only the widest gap. Sprecher's proof needed this step and his ψ does not give it. Köppen's ψ does, and Braun and Griebel prove it by bounds (Lemmas 2.3 and 2.4). Here it is held exactly to depth 60, with every inequality decided true or false.

### Separation

The theorem needs more than ψ. The inner sum ξ(d) = Σ_p α_p ψ(d_p) must hold distinct grid points apart; the outer functions can be built piece by piece on its image. Braun and Griebel prove this in three steps (the preprint, pages 12 to 15, read here).
- **Lemma 3.4.** For distinct d, d′ ∈ D_kⁿ, the difference μ_k = Σ_p α_p [ψ(d_p) − ψ(d′_p)] has |μ_k| ≥ γ^−nβ(k).
- **Lemma 3.7.** The images T_k(d) = [ξ(d), ξ(d) + (γ − 2)b_k] are disjoint, where b_k = ε_{k,2} Σ_p α_p and ε_{k,p} = Σ_{r>k} γ^−(p−1)β(r) is the tail of α_p.
- **Lemma 3.8.** The supports U_k(d) = (ξ(d) − γ^−β(k+1), ξ(d) + (γ − 2)b_k + γ^−β(k+1)) are disjoint. These are the supports of the ramps ω, whose ramp width is γ^−β(k+1). Distinct points' supports are disjoint when their ξ differ by at least (γ − 2)b_k + 2γ^−β(k+1).

The unit below is u′ = γ^−β(k+1). Because β(k + 1) = nβ(k) + 1, Lemma 3.4's margin γ^−nβ(k) is γu′ = 10 units.

**The method** (the sim; recounted here). ξ is computed exactly on every point of D_kⁿ, with ψ in the (2.9) form:
- for n = 2 at k = 1, 2 and 3 (100, 10⁴ and 10⁶ points);
- for n = 3 at k = 1 and 2 (10³ and 10⁶ points).

The values are sorted, and the least neighboring gap is found. The sim cuts α_p at the terms ≥ γ^−(β(k+1)+3) and bounds the dropped tail by twice its first term; each gap it prints is a lower bound. An independent recount in exact fractions cut α_p at two depths further apart. It finds the same tightest pair at every k, and the exact gaps below.

1. **Lemma 3.4 is false at k = 1** (**proved**). The pairs are tabled below; one unit is 10⁻³ for n = 2 and 10⁻⁴ for n = 3.
   - n = 2, the pair (0.1, 0) and (0, 0.9): μ_1 = 1/10 − (9/10)α₂, with α₂ = 0.1010001…, which is 9.0999099999991… units, below the margin of 10.
   - n = 3, the pair (0.1, 0, 0) and (0, 0.9, 0.9): μ_1 = 1/10 − (9/10)(α₂ + α₃) = 9.0999099991… units, again below 10.
   - At k = 1 the supports of Lemma 3.8 need 10.809 units (n = 2) and 10.881 (n = 3); they overlap.
   - The images of Lemma 3.7 have width (γ − 2)b_1 = 8.809 and 8.881 units, less than the least gap; they are disjoint, k = 1 included.
   - From k = 2 on, the lemma holds with room at every level tested:

   | n | k | least gap, units | tightest pair | α cut at r ≤ k (3.11) |
   |---|---|---|---|---|
   | 2 | 1 | 9.0999099999991… | (0.1, 0), (0, 0.9) | 10, on the margin |
   | 2 | 2 | 49.50499999505… | (0.04, 0.50), (0.09, 0.05) | 50 |
   | 2 | 3 | 500,049.5000005… | (0.039, 0.500), (0.094, 0.005) | 500,050 |
   | 3 | 1 | 9.0999099991… | (0.1, 0, 0), (0, 0.9, 0.9) | 10, on the margin |
   | 3 | 2 | 5,000 + 5 × 10⁻¹⁵ | (0.05, 0, 0.04), (0, 0, 0.09) | 5,000 |

2. **Where the proof breaks** (**proved** on the grids above; the argument read in the preprint).
   - The proof first bounds (3.11), μ with each α_p cut to its first k terms, α_p − ε_{k,p}. That bound holds: its least gap on every grid tested is the last column, at least the margin, and exactly on it at k = 1.
   - It then says the tails Σ_p ε_{k,p}A_{k,p}, with A_{k,p} = ψ(d_p) − ψ(d′_p), are "too small to annihilate" γ^−nβ(k). That is true, and it does not keep |μ_k| at or above γ^−nβ(k): at k = 1 the tails pull it from 10 units to 9.0999099….
   - So the lemma's bound fails at k = 1. At every k the proof's last step does not prove it.
3. **The repair** (anchor_sift's). Replace the lemma's bound and narrow the ramp.
   - **The corrected bound** (**proved**, given (3.11)). Since ψ ∈ [0, 1], each |A_{k,p}| ≤ 1; |μ_k| ≥ γ^−nβ(k) − Σ_{p≥2} ε_{k,p}, about (γ − 1)u′.
   - **The images stay apart.** The bound beats the image width (γ − 2)ε_{k,2}Σ_p α_p. The reason: for n = 2 and 3 the exponents (p − 1)β(r) are distinct positive integers; Σ_p α_p < γ/(γ − 1), and (γ − 2)γ/(γ − 1) < γ − 1 for every γ.
   - **The supports stay apart with a narrower ramp.** Use ρ = γ^−(β(k+1)+2), γ² narrower than the paper's γ^−β(k+1). The supports are then disjoint whenever γ^−nβ(k) − Σ_{p≥2} ε_{k,p} − (γ − 2)ε_{k,2}Σ_p α_p − 2ρ > 0. Each sum is taken as an upper bound: the series is cut after two terms, plus twice the third, which is valid because the exponents grow by at least 1 a term.
   - **At every scale** (**proved** at each level, exponents never expanded). The inequality holds at every k from 1 to 57 for n = 2 and 1 to 35 for n = 3. With the paper's ramp the same corrected bound covers no level, 0 of 57 and 0 of 35; the actual grids from k = 2 on are still disjoint with it (item 1 of this part).
   - **On the grids.** The narrow ramp separates the supports on every grid tested, k = 1 included (**proved**, exhaustively).
   - So Lemma 3.4 as stated is false at k = 1, and its proof has a gap at every k. The corrected bound, together with a ramp narrowed by γ², restores Lemmas 3.7 and 3.8 at every k.
4. **The shifts** (Theorem 3.3's covering).
   - The (m + 1) shifted copies of the grid use x + qa, with a = [γ(γ − 1)]⁻¹; qa = 0.0qqq… in base γ and qa ≡ qγ^−k/(γ − 1) modulo γ^−k (**proved**). The gaps between the cubes of each copy are therefore disjoint within each coordinate.
   - With m = 2n, a coordinate sits in at most one gap. So at least m − n + 1 of the shifts put the point inside a cube: 3 of 5 for n = 2, 4 of 7 for n = 3 (the sim's check).
   - With m + 1 = γ, two shifts share a gap, and for that reason the theorem asks γ ≥ m + 2.

**Not yet done** (do not read it as done). Two things remain:
- the contraction of the outer functions (Theorem 3.3), with the narrowed ramp in place of the paper's;
- ψ at the shifted points x + qa, which are off the grid.

Until both are built, the engine holds the theorem's inner function and its separation on the grid exactly, not the continuous theorem. A14's "not the continuous theorem" stands until Doug rules.

**The literature** (each record checked at Crossref or arXiv, 23 September 2026).
- D. A. Sprecher, "A numerical implementation of Kolmogorov's superpositions", Neural Networks 9(5) (1996) 765–772, doi:10.1016/0893-6080(95)00081-X; and "… II", Neural Networks 10(3) (1997) 447–457, doi:10.1016/S0893-6080(96)00073-1. The ψ that fails (item 1).
- M. Köppen, "On the training of a Kolmogorov network", ICANN 2002, LNCS 2415, 474–479, doi:10.1007/3-540-46084-5_77. The corrected ψ (items 2 and 3).
- J. Braun and M. Griebel, "On a constructive proof of Kolmogorov's superposition theorem", Constructive Approximation 30(3) (2009) 653–675, doi:10.1007/s00365-009-9054-2. The proof of Köppen's ψ by bounds.
- J. Actor and M. G. Knepley, "An algorithm for computing Lipschitz inner functions in Kolmogorov's superposition theorem", arXiv:1712.08286 (2017). anchor_sift's reading, not checked here: they computed in mpmath floats with no precision analysis, and their candidate ψ^{p,q} = α_p(x + qε) separates at every finite level but loses separation in the limit.
- F. Girosi and T. Poggio, "Representation properties of networks: Kolmogorov's theorem is irrelevant". The objection that the inner functions are too rough to compute. Neural Computation 1(4) (1989) 465–469, doi:10.1162/neco.1989.1.4.465.
- J. Schmidt-Hieber, "The Kolmogorov–Arnold representation theorem revisited", Neural Networks 137 (2021) 119–126, doi:10.1016/j.neunet.2021.01.020 (arXiv:2007.15884).
- A. C. Antoulas, I. V. Gosea and C. Poussot-Vassal, "Variable decoupling and the Kolmogorov superposition theorem for rational functions", arXiv:2605.07246 (2026).

| claim | status |
|---|---|
| Sprecher's ψ is not increasing: ψ(0.58999) = 2207/4000 > ψ(0.59) = 11/20 | **proved**, exactly (`ka_psi`; recounted independently) |
| Köppen's ψ, in both readings, is strictly increasing with least gap γ^−β(L) and continuous with widest gap G_L ≤ 2^−(L−1)/γ | **proved**: exhaustively on D_1 to D_5, symbolically to L = 60 (n = 2) and 38 (n = 3), and by induction for every L |
| Braun and Griebel's Lemma 3.4 holds: \|μ_k\| ≥ γ^−nβ(k) on D_kⁿ | **false** at k = 1 (9.0999099… units against 10, n = 2 and 3); holds at every grid tested from k = 2; its proof has a gap at every k |
| the corrected bound \|μ_k\| ≥ γ^−nβ(k) − Σ_{p≥2} ε_{k,p}, with the ramp narrowed by γ², keeps the images and supports of Lemmas 3.7 and 3.8 disjoint | **proved** at every k from 1 to 57 (n = 2) and 1 to 35 (n = 3), given (3.11), and on every grid tested |
| the outer functions' contraction (Theorem 3.3), and ψ at the off-grid shifted points | not built |
| the engine holds the continuous theorem | **not so** yet; Doug's ruling awaited |
