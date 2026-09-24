# The two crystals: the record machine over the 2-adic integers

**Purpose:** the 2-adic structure of the record machine: the wrap as a projection, the operations that commute with every projection and the test that proves it, the exact quotient by an odd divisor as a 2-adic product, the lifting on the 2-adic integers and the bits it reads, the two limits of the finite windows and the solenoid between them, what passes to a limit and what does not, the crystal as a boundary measured on itself, the top projection and its limit ℝ, the odd crystals, the places of ℚ, the count each crystal keeps, and Doug's posits, each bounded.

**Scope:** the record machine (M10 and A13 in [engine_table.md](engine_table.md)) and the 5/3 lifting T as record floors ([vertical_time_compression.md](vertical_time_compression.md)). The shape is Doug's (24 September): two crystals, the finite towers and their limit, with an infinite delta between them.

**Labels.**

- **Proved:** a named test checked it on the machine.
- **Measured:** a number a named run reported, where no check holds it to a value.
- **Derived:** argued here from the engine's source or by elementary algebra. Not run on the machine.
- **Open:** not settled.
- **Posit:** Doug's, in his words, with what the math bounds of it.

## The objects

Derived.

- **The 2-adic integers ℤ₂.** An element is a sequence of bits x_0, x_1, … without end, read as Σ x_k 2^k. Sums and products carry upward, as in binary, and never stop. Equivalently, ℤ₂ = lim← ℤ/2^w: an element is a sequence of residues r_w ∈ ℤ/2^w with r_{w+1} ≡ r_w mod 2^w (Koblitz, ch. 1; Gouvêa, ch. 3).
- **A register is a 2-adic integer.** The file holds a magnitude and a sign. XOR and AND read a register as its two's complement sign-extended without end (`engine_config.h`): zeros past the top bit for a value that is not negative, ones for a negative one. That bit sequence is the value in ℤ₂. For example −1 = …1111, since 1 + …1111 carries to 0. The inclusion ℤ ⊂ ℤ₂ is a ring embedding.
- **The wrap is a projection.** WRAP(v, w) takes v modulo 2^w and reads it back signed, in [−2^{w−1}, 2^{w−1}); the machine takes w ≥ 4. It is π_w: ℤ₂ → ℤ/2^w, each residue class written by its signed representative.
  - The projections cohere: π_w ∘ π_{w+1} = π_w, and WRAP(WRAP(v, w + 1), w) = WRAP(v, w).
- **A window.** W_w = [−2^{w−1}, 2^{w−1}) ∩ ℤ, the values a wrap to w returns. π_w restricted to W_w is a bijection onto ℤ/2^w, and a wrap to w leaves every value of W_w as it is.
- **An odd c is a unit of ℤ₂.** For example 1/3 = …10101011: 3 · 1011₂ = 33 ≡ 1 mod 16, and the digits 10 repeat above the lowest two. A wrap to 8 bits gives −85, and 3 · (−85) = −255 ≡ 1 mod 256.
  - ℤ₂ ∩ ℚ is the rationals with odd denominators. Their expansions are exactly the eventually periodic ones (Gouvêa).

## Coherence: five operations commute with every projection

Derived.

- π_w is a ring homomorphism. (a + b) mod 2^w depends only on a mod 2^w and b mod 2^w, and likewise a − b and a · b: a carry goes up, never down.
- Bit k of x xor y, and of x and y, reads bit k of x and bit k of y only. π_w keeps bits 0 to w − 1 and commutes with both.
- **The coherence theorem.** Let F be a straight-line program over SUM, DIFFERENCE, PRODUCT, XOR and AND. Write F_w for the same program with every input and every step wrapped to w. By induction on the steps, π_w ∘ F = F_w ∘ π_w: on every lane, WRAP(F(x), w) = F_w(WRAP(x, w)).
- The exact F's registers widen with the program. F_w's do not: each wrapped step reads operands in W_w, and its result is no wider than 2w bits before its wrap.

## Proved: the coherence test

**Proved** (`test/engine/record_coherence_test`, 9 checks, 0 failed, cell_tracking main 46b8018; 14 checks, 0 failed, at de5bdff, with the odd crystals below).

- **The programs.** 16 random programs of 10 operations. Each operation is drawn from the five and reads two values from among the 4 signed 24-bit fields and the operations before it. A program has at most 2 products, and its last operation reads the one before it. The widest exact register is 73 bits.
- **The lanes.** 4,096 lanes for each program. Each field is 0, −1, the most negative or the most positive 24-bit value, 1, or random (random 3 times in 8).
- **Three reckonings** at w = 5, 8, 13, 16, 31 and 32, all in one record program for each drawn program:
  - (a) the exact run, then a wrap to w;
  - (b) the same program with every input and every step wrapped to w;
  - (c) the CPU's own 64-bit two's complement over the same inputs, reduced to w and read signed.
- **Result.** 393,216 of 393,216 lane-widths agree three ways (16 programs × 4,096 lanes × 6 widths). The device's records equal the host's word for word.
  - (c) is itself a projection of the same 2-adic run: the CPU's word is F_64, and π_w ∘ π_64 = π_w.
- **Broken, as the theorem expects.** One signed 24-bit field at 8 bits: a quotient by 3 and a comparison with 0, each run on the field and on its wrap, then wrapped. The quotient disagrees on 2,212 of 4,096 lanes and the comparison on 1,790. The device equals the host.

## What does not factor through the projection

Derived. An operation G factors through π_w when WRAP(G(x), w) is a function of WRAP(x, w). For each failure below, two inputs share their w low bits and the outputs differ in theirs (w ≥ 4 throughout):

- **ABSOLUTE.** −1 and 2^w − 1: their absolute values 1 and 2^w − 1 wrap to 1 and −1.
- **COMPARE.** −1 is below 0 and 2^w − 1 above it.
- **QUOTIENT.** Broken on the machine (above).
- **REMAINDER** by 3. 1 and 1 + 2^w leave 1 and (1 + 2^w) mod 3, which is 0 or 2: 2^w is not a multiple of 3.
- **GCD** with 3. gcd(3, 3) = 3 and gcd(3 + 2^w, 3) = 1.
- **LADDER.** It reads the ratio of two magnitudes and refuses a right operand that is not positive. 2^{w−1} is positive and wraps to −2^{w−1}.
- **TABLE.** It indexes by |x| mod 2^b. −1 and 2^w − 1 read rows 1 and (2^w − 1) mod 2^b, two different rows for b ≥ 2.
  - A table indexed by the two's complement residue x mod 2^b would factor through π_w for every w ≥ b: it reads only bits the projection keeps.
- **The floor shift** ⌊v / 2^k⌋, k ≥ 1. Its bits 0 to w − 1 are v's bits k to w + k − 1: it factors through π_{w+k}, not π_w. v and v + 2^w give floors 2^{w−k} apart.
- **EXACT_QUOTIENT by an even c** holds the floor shift inside it: for c = 2^k and v a multiple of it, v and v + 2^w give quotients 2^{w−k} apart.

## The exact quotient by an odd divisor

- **The 2-adic map.** Derived. Division by an odd c in ℤ₂ is the product by the unit c⁻¹, and it commutes with every projection: π_w(c⁻¹ x) = π_w(c⁻¹) · π_w(x).
- **The machine's operation is not that map on wrapped inputs.** Derived. EXACT_QUOTIENT refuses a lane whose numerator c does not divide as an integer, and a wrapped multiple of c is often not a multiple of c: 3 · 50 = 150 wraps at 8 bits to −106. The wrapped program F_w replaces the exact quotient with a PRODUCT by the constant c⁻¹ mod 2^w and a WRAP.
- **The identity.** Derived: for c odd and c | v,

  WRAP(v / c, w) = WRAP(WRAP(v, w) · (c⁻¹ mod 2^w), w)

  Both sides are π_w(v · c⁻¹). At 8 bits with v = 150 and c = 3: c⁻¹ mod 256 = 171, and (−106) · 171 = −18,126 ≡ 50 mod 256.
- **Proved** (`test/engine/record_coherence_test`, its third part). c = 3, 7 and 12345, and v = PRODUCT(u, c) for a signed 24-bit field u, on the same inputs.
  - At the six widths, WRAP(EXACT_QUOTIENT(v, c), w) and WRAP(PRODUCT(WRAP(v, w), CONSTANT(c⁻¹ mod 2^w)), w) both equal WRAP(u, w).
  - 73,728 of 73,728 lane-widths agree (3 divisors × 4,096 lanes × 6 widths). The device equals the host.
  - The host's c⁻¹ is Newton's iteration in a 32-bit word, four rounds from x = c.
- **The kernel computes c⁻¹.** Derived from `cycle.cu` (`cycle_record_exact_quotient`).
  - It shifts the numerator and the divisor past the divisor's low zero bits.
  - It grows the odd part's inverse modulo 2^{32 · work} by Newton's x ← x(2 − cx) from one word, where work is the larger of the numerator's limbs and the quotient's.
  - Newton converges 2-adically. An odd c = 2m + 1 has c² = 4m(m + 1) + 1 ≡ 1 mod 8: it is its own inverse to 3 bits. If cx ≡ 1 mod 2^b, then c · x(2 − cx) = 1 − (1 − cx)² ≡ 1 mod 2^{2b}. In one word, four rounds give 6, 12, 24 and 48 bits, past the word's 32. The held limbs then double each round up to work.
  - The quotient is the low limbs of numerator · inverse, and the product back against the whole numerator proves it.
- **The 2-adic reading.** Derived. The inverse register holds π_{32 · work}(c⁻¹), a window of an element of ℤ₂ outside ℤ for every odd c other than ±1. Without the product back, the low limbs of numerator · inverse are π_{32 · work}(v · c⁻¹) for any v, a window of a 2-adic integer. The check against the whole numerator makes the result the integer v / c, or refuses the lane.

## The lifting on ℤ₂

Derived.

- **The 2-adic floor shift.** For x ∈ ℤ₂ and k ≥ 0, write x = r + 2^k y with 0 ≤ r < 2^k, x's residue. Then ⌊x / 2^k⌋ = y, the digits moved down k places. On ℤ it is the floor toward −∞, the record floor of [vertical_time_compression.md](vertical_time_compression.md). On ℤ₂ it is continuous: its bits 0 to w − 1 read x's bits k to w + k − 1.
- **T is a homeomorphism of ℤ₂^n.** Every lifting step is a shear (a, b) ↦ (a, b ± P(a)), with P built from sums and floor shifts. It is defined on ℤ₂ word for word and undone by the opposite shear. T is a bijection of ℤ₂^n that extends T on ℤ^n. T and T⁻¹ are continuous, since each output's w bits read finitely many input bits.
- **T is not a wrapped program.** Two inputs equal in their w low bits can give highs that differ in bit w − 1: adding 2^w to x_{2j} moves ⌊(x_{2j} + x_{2j+2}) / 2⌋ by 2^{w−1}. No F_w has π_w ∘ T = F_w ∘ π_w.
- **The bits one level reads.** Along one line, an interior coefficient (its neighbors inside the line), w ≥ 1. An output's w bits read each input to the count of bits given:

  | output | x_{2j+1} | x_{2j}, x_{2j+2} |
  |---|---|---|
  | the high d_j | w | w + 1 |

  | output | x_{2i} | x_{2i−1}, x_{2i+1} | x_{2i−2}, x_{2i+2} |
  |---|---|---|---|
  | the low s_i | w + 2 | w + 2 | w + 3 |

  - Upper bound. ⌊u / 2^k⌋ mod 2^w reads u mod 2^{w+k}. The high reads the evens' sum to w + 1 bits. The low reads d_{i−1} + d_i to w + 2 bits, and a high read to w + 2 bits reads its evens to w + 3.
  - Each count is exact. Adding 2^{m−1} to an input read to m bits moves the output by 2^{w−1} modulo 2^w:
    - the high: x_{2j+1} + 2^{w−1} moves d_j by 2^{w−1}; x_{2j+2} + 2^w moves it by −2^{w−1};
    - the low: x_{2i+2} + 2^{w+2} moves d_i by −2^{w+1} and s_i by −2^{w−1}; x_{2i+1} + 2^{w+1} moves d_i by 2^{w+1} and s_i by 2^{w−1}; x_{2i} + 2^{w+1} moves both highs by −2^w and s_i by 2^{w+1} − 2^{w−1} ≡ −2^{w−1}.
  - An edge repeats its neighbor and reads no more bits than the interior.
- **L levels.** A level-L low's w bits read the samples to w + 3L bits, and a level-L high's to w + 3L − 2.
  - Upper bound: a level reads the lows below it to 3 bits more, by the table.
  - Exact on the outermost sample of an interior cone. Of the level-(ℓ − 1) lows the cone reads, that sample reaches only the outermost, as its outer even. Adding 2^{m+2} to an outer even moves the low above by exactly −2^{m−1} for m ≥ 1. Adding 2^{w+3L−1} to the sample moves the outermost level-1 low of the cone by 2^{w+3L−4} in magnitude, the level-2 low by 2^{w+3L−7}, and the level-L low by 2^{w−1}.
  - As a 2-adic modulus: |T(x) − T(y)|₂ ≤ 2^{3L} |x − y|₂ along one line.
  - **Proved** on the machine, the bound and its exactness, per band: 3ℓ at the level-ℓ lows and 3ℓ − 2 at the level-ℓ highs ("The boundary", below).
- **The inverse reads fewer.** One inverse level: an even x_{2i} = s_i − ⌊(d_{i−1} + d_i + 2) / 4⌋ reads the low to w bits and the highs to w + 2; an odd x_{2j+1} = d_j + ⌊(x_{2j} + x_{2j+2}) / 2⌋ reads the lows to w + 1 and the highs to w + 3. By induction down the levels, the samples' w bits read the level-ℓ highs to at most w + ℓ + 2 bits and the level-L lows to w + L. T⁻¹ reads the crystal to at most w + L + 2 bits: |T⁻¹(c) − T⁻¹(c′)|₂ ≤ 2^{L+2} |c − c′|₂. **Proved** exact on the machine at L = 4 ("The boundary", below).
- **What the counts mean.** A wrapped T at w needs its samples to w + 3L bits. The extra bits come from the floors: a SUM, DIFFERENCE or PRODUCT reads no bit above w. Precision flows down from the top bits, 3 a level along the lows forward and 1 a level back.

## The two crystals

Doug's (24 September): two crystals, the finite towers and their limit, with an infinite delta between them.

- **The inverse crystal, ℤ₂.** Derived. ℤ₂ = lim← ℤ/2^w under the projections: compact, and each element a coherent sequence of windows. Every register the machine writes lies in it, and every WRAP is one of its projections.
- **The direct crystal, as sets.** Derived. The windows W_w ⊂ W_{w+1} have union ℤ, and every value the machine holds lies in some window. The union is of sets only.
  - A window is not closed under +: 2^{w−2} + 2^{w−2} = 2^{w−1} leaves W_w. Nor under ×.
  - No ring map ℤ/2^w → ℤ/2^{w+1} sends 1 to 1: 2^w · 1 = 0 would have to go to 2^w ≠ 0.
- **The direct crystal, as groups.** Derived. Under the injections x ↦ 2x, ℤ/2^w → ℤ/2^{w+1}, the direct limit is the Prüfer group ℤ[1/2]/ℤ, not ℤ; ℤ/2^w sits in it as the multiples of 2^{−w}.
  - The Prüfer group is the Pontryagin dual of ℤ₂ (Hewitt and Ross). The two systems are dual map for map: the dual of a projection ℤ/2^{w+1} → ℤ/2^w is an injection x ↦ 2x.
- **They agree on every finite projection.** Derived. π_w(ℤ) = π_w(ℤ₂) = ℤ/2^w for every w. Every x ∈ ℤ₂ shares its w low bits with an integer, the signed representative of π_w(x) in W_w: ℤ is dense in ℤ₂. No finite floor tells the two crystals apart.
- **The delta is infinite.** Derived.
  - ℤ is countable. ℤ₂ is in bijection with the bit sequences {0,1}^ℕ and uncountable, by Cantor's diagonal. ℤ₂ \ ℤ is uncountable.
  - Its part in ℚ, the rationals with odd denominators outside ℤ, is countable: the eventually periodic expansions. The machine reaches their windows through the exact quotient's inverse (1/3, above).
  - The computable elements of ℤ₂ are countable, and a program can produce any window of one. All but countably many elements are not computable: each has a window at every w, as every element does, yet no program produces its windows for every w.
- **The solenoid.** Derived. The envelope joining the two crystals (Anchor_sift's framing) is the dyadic solenoid (Vietoris 1927; van Dantzig 1930):

  Σ₂ = lim←(S¹, z ↦ z²) = (ℝ × ℤ₂) / ℤ, with ℤ embedded diagonally, n ↦ (n, n)

  - **The transversal.** Projecting to the first circle, (t, x) ↦ t mod 1, the fiber over a point is a copy of ℤ₂, a Cantor set.
  - **The leaves.** The image of each line ℝ × {x} is a leaf: a line immersed injectively and dense in Σ₂. The leaf through (0, x) meets the fiber over 0 in the coset x + ℤ, and the leaf through 0 meets it in ℤ itself. The leaves are in bijection with ℤ₂ / ℤ, uncountably many.
  - ℤ lies along one leaf as its integer points and inside the transversal as a dense subset.
  - **Dual.** Σ₂ is the Pontryagin dual of ℤ[1/2]. The exact sequence 0 → ℤ → ℤ[1/2] → ℤ[1/2]/ℤ → 0 dualizes to 0 → ℤ₂ → Σ₂ → S¹ → 0: the solenoid is the circle extended by ℤ₂, and its fiber is the dual of the direct crystal's Prüfer group.

## Going up: what passes to the limit

Derived.

- **Unions of chains.** For a chain of structures A_0 ⊂ A_1 ⊂ … under embeddings, the union satisfies every ∀∃ sentence that holds in every A_i (Chang 1959; Łoś and Suszko 1957; Hodges, where the Fraïssé limit is built as such a union).
  - A ∀∃ sentence says: for every x there is a y with a quantifier-free relation. A witness y found in A_i stays a witness in the union, since the embeddings keep quantifier-free relations.
  - On the machine: the groups ℤ/2^w under x ↦ 2x satisfy "every x has a −x", and their union, the Prüfer group, does too.
  - The converse fails. The Prüfer group is divisible by 2, and no ℤ/2^w is: 1 has no half.
  - The windows W_w are not a chain of structures under + and ×. The theorem says nothing about them as rings.
- **Unions of bijections.** Let f_i: A_i → B_i be bijections with A_i ⊂ A_{i+1}, B_i ⊂ B_{i+1}, and f_{i+1} extending f_i. Then ∪ f_i: ∪ A_i → ∪ B_i is a bijection: any two points lie in one A_i, and any image point in one B_i.
  - Exactness passes. T restricted to W_w^n is a bijection onto its image, the restrictions extend one another, and their union is T on ℤ^n, onto ℤ^n. T⁻¹ ∘ T = id at each stage gives it on the union.
  - On ℤ₂^n exactness comes from the shear argument directly (above), not from a union.
- **What does not pass.** Finiteness and termination.
  - ω is a transitive set: every member is finite, and ω is not.
  - Every W_w is finite, and ℤ is not.
  - Every F_w terminates in a fixed number of steps on w-bit words. T on ℤ₂^n is not a finite computation: the machine computes π_w ∘ T from π_{w+3L}, one finite window at a time, never the whole.

## The boundary: the crystal measured on itself

**Proved** (`test/engine/record_boundary_test`, 41 checks, 0 failed, cell_tracking main de5bdff; 48 checks, 0 failed, at 24b2785, with the identity by null permutation in "Doug's posits"). A 5/3 tower T of L = 4 levels over n = 64 signed 24-bit samples runs as record floors. Each floor shift is three record steps: an AND with 2^k − 1, a DIFFERENCE, then EXACT_QUOTIENT by 2^k. The crystal is in Mallat order: the level-4 lows first, then the highs of levels 4 down to 1. Every program runs on the device and the host, and the records agree word for word.

- **T's matrix.** The test builds 2^12·M, column i the image of 2^12·e_i under T, and the same for T⁻¹. On multiples of 2^12 every floor is exact and the +2 offset drops out: M is T's linear part, with entries in ℤ[1/2].
- **The reach, per band.** A row's reach is 12 less the least 2-adic valuation of its entries. T's matrix reaches 12 bits from the level-4 lows, and 10, 7, 4 and 1 from the highs of levels 4, 3, 2 and 1: 3L at the lows and 3ℓ − 2 at the level-ℓ highs, the counts derived above. T⁻¹'s matrix reaches 6 = L + 2.
- **Flips.** 8,192 pairs of lanes for each map. A pair is a random input and the same input with one bit b flipped, b drawn from 0 to 22, below the sign bit: the flip moves the value by exactly ±2^b.
  - No flip moves an output below bit b − 12 for T, or below bit b − 6 for T⁻¹: 8,192 of 8,192 pairs each. The furthest reach met on the device is 12 for T and 6 for T⁻¹. Both bounds are exact.
  - A flip at b ≥ 12 moves the output by exactly ±2^b times the matrix's column: 3,918 of 3,918 such pairs for T and 3,837 of 3,837 for T⁻¹ (the counts of such pairs are measured; the check holds every one).
- **Written onto the boundary and read back.** Arbitrary 24-bit crystals run through T⁻¹ then T return exactly: 16,384 of 16,384 lanes. Every crystal is the crystal of some samples: the boundary is a whole coordinate chart of ℤ^n, and no crystal lies outside T's image.
- **What passes through T.** 2,048 pairs of each kind, the base samples below 2^21 in magnitude.
  - A constant c below 2^19 in magnitude, added to every sample, moves the 4 level-4 lows by c each and no other coefficient: 2,048 of 2,048.
  - A lattice move 2^12·z, z ∈ [−128, 127]^64, moves the crystal by exactly M·2^12·z: 2,048 of 2,048.
  - Negation and doubling: the check holds that neither passes on every pair. **Measured:** each passes on 0 of 2,048.
  - Derived. The floor commutes with adding an integer, ⌊(u + 2c) / 2⌋ = ⌊u / 2⌋ + c: a constant leaves every high unchanged and moves every low by itself, level by level. On 2^{3L}ℤ^n every floor is exact: T(x + 2^{3L}z) = T(x) + M·2^{3L}z. Negation fails on the floor, ⌊−u / 2⌋ ≠ −⌊u / 2⌋ for odd u, and doubling on the parity, 2⌊(a + b) / 2⌋ ≠ a + b for a + b odd.
- **Floors, heap and ring.** T then T⁻¹ in one program, every floor's registers an output. Each rebuilt register is wrapped at the mirror to its forward twin's width + 1, the samples included, to 25 bits. A value's heap is its magnitude's bits and one sign bit when it is not zero. A floor's ring is the sum of the imprint's widths of its registers. Four classes of 1,024 lanes: a ramp (start below 2^19 in magnitude, slope from −2,048 to 2,047), the ramp ±8, the ramp ±1,024, and noise over the 24-bit field.
  - The last floor returns every sample exactly, on every lane.
  - The heap mirrors: the heap at floor 2L − k equals the heap at floor k, on every lane.
  - Every floor's heap lies inside its ring and one sign bit for each nonzero value, on every lane.
  - The ring at forward floor ℓ is ring_0 + 6(n − n/2^ℓ), and at the mirror floor 2L − ℓ it is ring_ℓ + n/2^ℓ, one bit for each wrapped low. The ring is widest at the crystal. Floors 0 to 8: 1,536, 1,728, 1,824, 1,872, 1,896, 1,880, 1,840, 1,760 and 1,600.
  - The heap's pinch, a class's heap at floor 0 over its heap at the crystal, falls from the ramp to ±8 to ±1,024 to noise (the order is checked). **Measured:** 9.61, 3.82, 1.76 and 1.00.
- **The ring, derived.** With keymath's widths, the constant-divisor narrowing included ([vertical_time_compression.md](vertical_time_compression.md)), a level turns the n/2^{ℓ−1} lows of width W into n/2^ℓ highs of width W + 2 and n/2^ℓ lows of width W + 4. The ring grows by (n/2^ℓ)(W + 2 + W + 4) − (n/2^{ℓ−1})W = 6n/2^ℓ, and summed over the levels ring_ℓ = ring_0 + 6n(1 − 2^{−ℓ}).
  - The mirror floor adds one bit for each of its n/2^ℓ rebuilt lows, the wrap's + 1.
  - The formula reproduces the replica's column in vertical_time_compression.md (16-bit samples, n = 64, L = 6): 1,024, 1,216, 1,312, 1,360, 1,384, 1,396 and 1,402 going up, 1,398, 1,388, 1,368, 1,328 and 1,248 coming down. The replica's T⁻¹ 0 read 1,024, with the samples wrapped to 16 bits. The scratch run there wrapped them to 17 and read 1,088 = 1,024 + 64, as the formula gives.
  - The growth is 6n(1 − 2^{−L}) < 6n for every L: under 6 bits a sample, however many levels.
- **The ring's shape.** Derived: up the arc ring_0 + 6n(1 − 2^{−ℓ}), each level adding half the level before it, widest at the crystal, and back down the same arc plus n/2^ℓ. Which shape is the oval is Doug's call. His words were a "fuzzy oval brush stroke" and "the more oval the shape, the more complex the information base".
- **Haar counted.** A tower of 4 samples and one level, T and T⁻¹, each reaching 3 bits. For w = 1 and 2 every input quantum at level w + 3 is run, all 2^{4(w+3)} residue vectors, from the representatives 0 ≤ x < 2^{w+3} and from −2^{w+2} ≤ x < 2^{w+2}. An output's low w bits name its quantum at level w. In 8 of 8 runs every output quantum receives exactly 2^12 = 4,096 input quanta (derived in "Counting quanta", below).
- **Volume.** det(2^12·M) is checked against ±2^768 modulo primes below 2^31, until their product passes Hadamard's bound plus 2 bits, about 779 bits: agreement modulo all of them is equality. det M = det M⁻¹ = ±1 exactly, and the product of the two matrices is 2^24·I exactly. **Measured:** the sign is +1; the check accepts either.
  - **The sign, derived.** Each lifting step is a shear, determinant 1. The Mallat order is a chain of unshuffles, one a level: a band of 2k values into its k evens, then its k odds. The odd at 2i + 1 precedes the k − 1 − i evens after it: k(k − 1)/2 inversions, sign (−1)^{k(k−1)/2}. For k = 32, 16, 8 and 4 the exponents are 496, 120, 28 and 6, all even: det M = +1.

## The top projection and its limit ℝ

**Proved** (`test/engine/record_boundary_test`). The top projection τ_k(x) = x / 2^k toward zero, the machine's QUOTIENT by a power of two, keeps the top of the window where π_w keeps the bottom. (k, c) = (3, 3), (7, 5) and (5, 12,345), 65,536 lanes each, 196,608 in all, x and y random signed 24-bit fields.

- Nested quotients commute, every quotient toward zero: τ_k(x) / c = τ_k(x / c) on 196,608 of 196,608.
- A COMPARE through τ_k is never reversed: on every lane τ_k(x) against τ_k(y) is a tie or the order of x against y. **Measured:** 4 ties.
- A SUM through τ_k is off by at most 1: τ_k(x + y) − τ_k(x) − τ_k(y) is −1, 0 or 1 on every lane, and the check holds that a carry occurs. **Measured:** carried on 92,890.
- An 8-bit WRAP reverses comparisons τ_k keeps. **Measured:** 97,966 lanes.

Derived.

- **The two projections are dual.** π_w is a ring map and scrambles order. τ_k keeps order, weakly, and adds only up to a carry: a truncation drops a fraction of its argument's sign and of magnitude below 1, and the three dropped fractions net to −1, 0 or 1.
- **τ_k's fibers are not all one size.** τ_k⁻¹(0) = (−2^k, 2^k) ∩ ℤ holds 2^{k+1} − 1 integers, and every other fiber 2^k. π_w's fibers are the cosets of 2^wℤ, translates of one another: the Haar count ("Counting quanta") has no analogue for truncation at 0.
- **The τ tower.** τ_j ∘ τ_k = τ_{j+k}: nested quotients toward zero, the check above with c a power of two.
  - Its inverse limit lim←(ℤ, τ_1) is the sequences (a_k) with a_k = τ_1(a_{k+1}). It maps onto ℝ by (a_k) ↦ lim a_k / 2^k: a step moves a_k / 2^k by at most 2^{−(k+1)}, and t ∈ ℝ has the preimage a_k = trunc(2^k t), truncated toward zero, since trunc(trunc(y) / 2) = trunc(y / 2).
  - The map is one-to-one except at the nonzero dyadic rationals, where it is two-to-one: 1 is the limit of a_k = 2^k and of a_k = 2^k − 1, the expansions 1.000… and 0.111….
  - π_w's tower adds a bit above at each stage, and its limit is ℤ₂. τ_k's tower adds a bit below, and its limit is ℝ. The solenoid Σ₂ = (ℝ × ℤ₂)/ℤ holds both, ℝ along its leaves and ℤ₂ in its fiber.
  - This is the derived form of Doug's inverted boundary ("Doug's posits", below).

## The odd crystals

**Proved** (`test/engine/record_coherence_test`, its last part, 14 checks in all, 0 failed, de5bdff). The moduli m = 243, 59,049, 625 and 343 (3^5, 3^10, 5^4 and 7^3). 16 ring-only programs of SUM, DIFFERENCE and PRODUCT, 4,096 lanes each.

- Three reckonings agree on 262,144 of 262,144 lane-moduli: REMAINDER by m of the exact run; the run with every step reduced by REMAINDER by m; the host's arithmetic mod m. REMAINDER carries the numerator's sign, and each is read mod m.
- The CRT join y_2 + 2^8·(((y_p − y_2)·2^{−8}) rem m), with y_2 the run mod 2^8 and y_p the run mod m, equals the exact run mod 2^8·m on 262,144 of 262,144.
- XOR breaks the agreement mod 3. **Measured:** on 827 of 4,096 lanes.

Derived.

- REMAINDER by p^v, read mod p^v, is the projection ℤ_p → ℤ/p^v on the integers: the odd crystal's π. SUM, DIFFERENCE and PRODUCT commute with it, by the coherence theorem with p^v in place of 2^w.
- XOR and AND read base-2 digits and do not factor through mod 3. For XOR: 3 xor 1 = 2, while 3 ≡ 0 and 0 xor 1 = 1. For AND: 3 and 1 = 1, while 0 and 1 = 0. XOR is the one the test breaks.
- **The crystals are orthogonal.** For m odd, ℤ/2^8·m ≅ ℤ/2^8 × ℤ/m (the Chinese remainder theorem), and the join above is the inverse of the isomorphism. Over every modulus, Ẑ = lim← ℤ/N = ∏_p ℤ_p: ℤ₂ is one factor, and the odd crystals are the others.

## The places of ℚ

Derived.

- **Ostrowski** (1916): every nontrivial absolute value on ℚ is equivalent to the real one or to a p-adic one. The completions of ℚ are ℝ and the ℚ_p, one for each prime. The machine's two limits are two of them: ℝ by the τ tower and ℤ₂ ⊂ ℚ₂ by the π tower.
- **T at each place.**
  - On ℤ^n, a bijection (proved, the written boundary).
  - On ℤ₂^n, a homeomorphism that keeps Haar measure (derived; proved counted).
  - On ℝ^n, reached by the τ tower: T(x) − Mx is bounded on ℤ^n, since each floor drops less than 1 and passes through a fixed number of fixed linear steps. For x ∈ ℝ^n, 2^{−k}·T(trunc(2^k x)) → Mx as k → ∞: the real limit of T is its linear part M, and det M = 1 keeps Lebesgue measure.
  - On ℤ_p^n for odd p, T with floors does not extend. Parity is not p-adically continuous: x and x + p^N are p-adically close, |p^N|_p = p^{−N}, and have opposite parities. For x even, ⌊(x + p^N)/2⌋ − ⌊x/2⌋ = (p^N − 1)/2 ≡ −1/2 mod p, a p-adic unit however large N is.
  - M does extend. Its entries lie in ℤ[1/2] ⊂ ℤ_p and det M = 1: M ∈ SL_n(ℤ_p), an automorphism of every odd crystal ℤ_p^n that keeps its Haar measure. |det M|_v = 1 at every place v.
- **The adeles.** 𝔸 = ℝ × ∏′ ℚ_p, the restricted product, with almost every component in ℤ_p. ℚ sits in 𝔸 diagonally and discretely. 𝔸 = ℚ + (ℝ × Ẑ) and ℚ ∩ (ℝ × Ẑ) = ℤ, giving 𝔸/ℚ ≅ (ℝ × Ẑ)/ℤ, compact: the full solenoid, lim←(S¹, z ↦ z^N) over every N (Tate 1950). The dyadic solenoid Σ₂ = (ℝ × ℤ₂)/ℤ is its quotient by the odd factors ∏_{p odd} ℤ_p.
- **The product formula.** For x ∈ ℚ^×, |x|_∞ · ∏_p |x|_p = 1: with x = ±∏ p^{v_p}, |x|_∞ = ∏ p^{v_p} and |x|_p = p^{−v_p}. For 12: 12 · 1/4 · 1/3 = 1. Read as a conservation law, a rational large at some places is small at others in exact balance. The name is a reading; the theorem is the formula.

## Counting quanta

Derived.

- **Haar measure as coset counting.** A quantum at level w in ℤ₂^n is a coset of (2^wℤ₂)^n, the points with one value of π_w. The Haar measure μ gives it 2^{−wn}.
- **A shear keeps μ.** A shear (a, b) ↦ (a, b + P(a)), P continuous, is a translation of the b coordinates for each fixed a, and a translation keeps Haar measure. By Fubini the shear keeps μ on the product. T and T⁻¹ are compositions of shears and keep μ, for every n and L.
- **The count.** An output's w bits read the inputs to w + 3L bits: the preimage of a level-w output quantum is a union of level-(w + 3L) input quanta. It has measure 2^{−wn} and each of them 2^{−(w+3L)n}: it holds exactly 2^{3Ln} of them. For T⁻¹, reaching L + 2, it holds 2^{(L+2)n}.
- **Proved** at n = 4 and L = 1, both reaches 3, w = 1 and 2, from two windows of representatives: 2^12 = 4,096 on every output quantum, 8 of 8 runs ("The boundary", above).
- The window does not matter: the quanta are cosets, and a map that reads w + 3L bits sees the coset only. The test runs two windows to show it.
- On ℤ/2^w alone no such count holds for T: T is not a wrapped program. The count runs between two levels, w + 3L to w.

## The limit stage

Derived.

- **Limits with and without a modulus.** Chaitin's Ω (1975) is limit computable: the halting programs, enumerated, give an increasing computable sequence of rationals converging to it, and its digits are Δ⁰₂ by Shoenfield's limit lemma (1959). It has no computable modulus of convergence: one would compute Ω's digits, and Ω is not computable.
- T on ℤ₂ has the computable modulus w ↦ w + 3L. The machine produces w bits of T(x) from w + 3L bits of x in a fixed number of steps, at every w.
- Quotient and compare have no 2-adic limit: neither extends continuously to ℤ₂ ("What does not factor through the projection").
- **Past ω.** A machine that runs through ω steps and goes on from a limit configuration is an infinite time Turing machine (Hamkins and Lewis 2000): at a limit stage each cell takes the lim sup of its values. Koepke's ordinal Turing machines (2005) run over ordinal time on a tape of ordinal length. The device runs finite stages only: every program is a finite record with a fixed step count, and every lane's run halts.

## Subtractive coalescence

Doug's name for T. Derived.

- The 5/3 lifting's steps are predict and update, the lifting scheme of Sweldens (1996). An odd sample less its prediction from the evens is a high; an even plus a correction from the highs is a low. Each step is undone by the opposite step.
- T is not a projection. It is a bijection (proved both ways), and T⁻¹ returns every sample.
- The pinch is the predictable part moved, not information lost. A ramp's highs are near 0 and its content sits in the few level-L lows. The heap at the crystal is 1/9.61 of the samples' heap for the ramp and 1/1.00 for noise (measured, above). The heap shrinks while the ring grows by 6n(1 − 2^{−L}), and the count is kept exactly (det M = 1, Haar counted).

## Physical walls

Cited; both pages read, and only what they state is given.

- **Borsten and Kim**, "Limits to Computational Acceleration Imposed by Quantum Field Theory and Quantum Gravity", arXiv:2604.00182, 31 March 2026. Their abstract: schemes that use curved spacetimes and exotic fields, for instance time dilation, to accelerate computation are "consistently thwarted by physical effects from quantum gravity (including swampland conjectures) and quantum field theory in curved space". An observer and a computer able to withstand energy scales up to order E accelerate computation by at most O(1)E e-folds per unit time, (ln α)/τ ≲ E. The Bekenstein bound is the memory analogue: a computer of length scale D at energies up to order E with N memory states has (ln N)/D ≲ E.
  - The reading, derived from their bounds: a device of bounded energy and size runs finitely many stages in finite time and holds finitely many states. The limits ℤ₂ and ℝ are reached one finite window at a time, and the walls bound how many.
- **Aaronson**, "On black holes, holography, the Quantum Extended Church-Turing Thesis, fully homomorphic encryption, and brain uploading", Shtetl-Optimized, 27 July 2022. AdS/CFT predicts that the boundary state |ψ⟩ "encodes everything there is to know about the AdS bulk, including whatever is inside the black hole", and that "the information about what's inside the black hole will be pseudorandomly scrambled". He cites Bouland, Fefferman and Vazirani (arXiv:1910.14646).
  - The contrast, derived: T's boundary is information-complete too (every crystal is the crystal of some samples, proved) and is not scrambled. Each coefficient reads a cone of reach 3L, and T⁻¹ reads the crystal back in a number of steps linear in n.

## The knf's identity by spatial null permutation

`knf_identity` (src/engine/sims, 23 checks, 0 failed, cell_tracking main e4eae72). The nbody lattice's law in a 64³ cube over 177 frames: 176 transitions, 16 full windows of 11. The engine's `entropy_history_project` makes the knf (A7).

- **The objects.**
  - A section is one voxel's 16 windows: its bit-weighted flip density in each window, the kernel's own, less its mean over the windows.
  - E, the knf's entangled entropy: over every voxel and each of its z, y and x neighbours on the torus, the dot product of their two sections, summed.
  - A spatial null draw permutes the sections over the voxels. It keeps every section and the cloud, and E reads arrangement only.
  - A volume is identified when E stands above every one of d = 19 draws. The departure at a null is 19·E less the sum of the 19 draws' E.
  - Tile size b = 1, 2, 4, …, 64. The inside null shuffles the sections within each b³ tile and moves nothing across a seam. The between null moves whole tiles rigidly to shuffled places. At b = 64 the inside null is the free null, and at b = 1 the between null is.
  - A share is a departure over the free null's departure.

**Proved** (the checks).

- **One bit.** The host's walk equals the engine's knf at all 262,144 voxels. Of 8,192 single flipped bits, 1,500 leave the knf unchanged, and the window rule names the outcome of all 8,192 exactly.
  - The window rule, derived. A flip of bit j at frame f changes the transitions f − 1 → f and f → f + 1. When bit j differs between frames f − 1 and f + 1, exactly one of the two transitions flips, before and after, and the count holds if both transitions lie in one window. On a window's edge, or at the first or last frame, the flip moves a count.
  - The knf is therefore many-to-one: no 1:1 ID in the way the crystal is. Its identity is its rank against the null.
- **The exact motions.** The 48 motions of the cube (6 axis orders × 8 reflections), each with a keyed torus translation. The data is moved over xyz and projected again. knf(gX) = g·knf(X), E unchanged and the cloud unchanged, on 48 of 48.
  - Derived: an orthogonal matrix with integer entries is a signed permutation matrix. These 48 are the only rotations and reflections that carry ℤ³ onto itself, and any other angle rounds on the lattice.
- **The tiles.** At all 7 tile sizes the whole is its tiles plus its seams exactly. A rigid move of whole tiles keeps every tile's inside exactly: 133 of 133 draws. The inside departure at b = 1 and the between departure at b = 64 are 0 exactly.
  - Derived: since a between draw keeps every tile's inside, its departure is the seams' departure alone.
- **The control.** 64 volumes of 32³ with every voxel drawn alike (no bodies, no ramp, no fixed pattern), 19 free draws each. 4 are identified, where spatial exchangeability bounds the rate by 1/20 (3.2 expected); the check holds it within 5σ.

**Measured**, the lattice.

- E is 44.626 times the free null's mean and stands above all 19 draws.
- The departure curve, as a share of the free departure, * where E stands above every draw:

  | b | inside | between | sum |
  |---|---|---|---|
  | 1 | 0.000 | 1.002* | 1.002 |
  | 2 | 0.126* | 0.492* | 0.618 |
  | 4 | 0.349* | 0.241* | 0.590 |
  | 8 | 0.647* | 0.106* | 0.754 |
  | 16 | 0.896* | 0.047* | 0.944 |
  | 32 | 0.974* | 0.008* | 0.982 |
  | 64 | 1.000* | 0.000 | 1.000 |

  - The two cross between b = 2 and 4. The bodies' semi-axes are 2 to 7.
- **The bodies.** Each body's box (its z, y and x bounds over its life) gets its own inside curve, as a share of its own free departure.
  - Every body but one reads 0.112 to 0.196 at b = 2, 0.254 to 0.502 at 4, 0.594 to 0.895 at 8, 0.900 to 0.989 at 16 and 0.947 to 1.019 at 32.
  - Body 3 does not move and never ends. It flips nothing, its share of the whole is 0.002, and its curve is noise (1.192 at b = 4).
  - The shares of the whole sum past 1, since the boxes overlap. The largest: body 7, 0.426 (the largest box); body 11, 0.175; body 10, 0.172; body 0, 0.164.
- **The same scene without bodies** (the same camera and ramp). E is −10.675 times the null's mean and is not identified. The free departure is near 0, and the shares are noise. One between mark, at b = 16, of 14, which is chance level.

## Doug's posits

- **"Transitivity: T closed is a member of T open."** Derived bound. Read T closed as a finite stage (a window, a wrapped program F_w) and T open as the limit (ℤ or ℤ₂).
  - Bare membership passes nothing: ω is transitive, every member finite, itself infinite.
  - Membership tied to structure, each stage embedded in the next and in the limit, passes the ∀∃ sentences and exactness, and does not pass finiteness or termination.
- **"Two crystals preserve infinity; the delta between them is infinite."** Supported (derived above). The two crystals agree at every finite width, and the delta ℤ₂ \ ℤ is uncountable. Every window of every element of ℤ₂ is a value the machine can hold.
- **"The anchors are infinitely complex, bending the information field to warp into them."** Open. What the math states:
  - An infinite expansion is not infinite complexity. 1/3 = …10101011 never ends, and a program a few bits long prints any window of it: K(π_w(1/3)) ≤ K(w) + c = O(log w).
  - For a computable x ∈ ℤ₂, K(π_w(x)) ≤ K(x) + O(log w): run x's program to w digits, given w.
  - Haar-almost every element of ℤ₂ is Martin-Löf random (Martin-Löf 1966). The Haar measure on ℤ₂ is the fair coin on its digits, and the random sequences have measure 1. A random element is not computable.
  - The machine reaches finite windows only. Every register is π_w of something, and any w-bit window has K ≤ w + O(log w). Every constant in a program is a finite description, and the machine's reach is the windows of computable elements.
  - "Infinitely complex" can name only a limit object the machine never holds whole. Which object the anchors are, and whether they are random elements of ℤ₂, is open. "Bending the information field" has no definition here to derive from.
- **The inverted boundary** (Doug, 24 September: a second tower over the first one's boundary, inverted; A13 in [engine_table.md](engine_table.md)). Posit. Its derived form is the τ tower: the finite windows extended a bit above at each stage, π_w's tower, have the limit ℤ₂, and extended a bit below, τ_k's tower, the limit ℝ ("The top projection and its limit ℝ").
- **"The quanta still preserve infinity."** Posit. Derived bound: every output quantum at level w has exactly 2^{3Ln} input quanta at level w + 3L, at every w, and the count passes to ℤ₂ as Haar measure ("Counting quanta"). The machine holds finite windows only, and the physical walls bound how many.
- **"The recursion stack is ordinal."** Posit. Derived bound: every stack the device runs is finite. T's limit sits at the first limit stage ω, with a computable modulus. Stages past ω are the machines of Hamkins and Lewis and of Koepke, not built ("The limit stage").
- **"Subtractive coalescence."** Posit, Doug's name for T. Derived bound: predict and update, a bijection, the pinch the predictable part moved ("Subtractive coalescence").
- **"We can take an identity of T using T:null permutation of T"** (Doug, 24 September, restating "T, if T is identity:null permutation identity, we have the perfect universal root id for the structure"). Posit. The identity is an ID, a fingerprint of the data's structure. It is not the identity map, nor the identity edge of A14.
  - The procedure. Run T on the samples x and on d null draws σ_1 x, …, σ_d x, each σ_i a uniform random shuffle of the samples: A12's drawn null in [engine_table.md](engine_table.md). A lane is identified when its crystal's heap stands strictly below every draw's.
  - Derived. A shuffle keeps every value, the histogram and the count, and changes the arrangement only. x and its draws share one multiset of values, and any gap between T(x)'s heap and the draws' heaps reads arrangement alone. T keeps the count exactly (det M = 1, Haar counted): the gap is not T gaining or losing volume.
  - Derived. Under the null that x's arrangement is itself a uniform shuffle, x and the d draws are exchangeable, and the chance that x's heap stands strictly below all d draws is at most 1/(d + 1) (Hope 1968). This is A12's false-period rate, carried over.
  - **Proved** (`test/engine/record_boundary_test`, 48 checks, 0 failed, cell_tracking main 24b2785). d = 8 Fisher–Yates shuffles a lane from the test's seeded generator, 256 lanes a class, the ID the crystal's total heap, the four classes of "The boundary". A shuffle keeps the samples' heap exactly, on every draw. Noise is identified no more often than 256/9 plus 5 standard deviations of the binomial count, and each structured class is identified past that bound.
  - **Measured:** lanes identified, with the lane's crystal heap over the draws' mean in brackets: ramp 256 of 256 (0.13), ramp ±8 256 of 256 (0.33), ramp ±1,024 254 of 256 (0.73), noise 21 of 256 (1.00).
  - The claim is the rate, not every lane. The null bounds how often noise is identified; it promises nothing for any one structured lane. Two shallow ramps under ±1,024 were not identified: their noise swamps the slope, and their shuffles have little arrangement to destroy. A first form of the check asserted every structured lane and failed on those two.
  - **One to one** (Doug: "unique", not bit to bit; "change one bit and the permutation fails"). **Proved** in the same test.
    - 8,192 of 8,192 null draws change the crystal exactly when they move a value: T(σx) = T(x) exactly when σx = x. **Measured:** 0 draws moved none.
    - Every single flipped bit changes the image: 8,192 of 8,192 pairs through T and 8,192 of 8,192 through T⁻¹.
    - Derived: both follow from T being a bijection. The crystal is a one-to-one ID of its samples. The heap fingerprint is many-to-one: it reads the arrangement's structure, not the samples.

- **"The knf will be unique, it is the broken edge of the crystal"** and **"the only time a section of a knf will agree with another is either pure chance, or the knf belongs to more than one subset"** (Doug, 24 September, relayed by Anchor_sift). Posit. The .knf is the entropy history (M8, A7 in [engine_table.md](engine_table.md)), per Anchor_sift; the name appears nowhere in the source.
  - What the source holds. Derived from A7 and `entropy_history`. For each voxel x, bit j and window of transitions, the history keeps f_j(x), the number of transitions where bit j flips. It reads the raw 16-bit volume, before any lifting, and its parity check f_j(x) ≡ bit j of I_0(x) ⊕ I_{F−1}(x) proves it was taken whole.
  - Derived: the history is many-to-one, not a bijection. A count keeps how many transitions flipped a bit and loses which: a bit that flips at transitions 1 and 2 and one that flips at 3 and 4 give one count in one window. "Unique" can hold for it only as a statistical ID, like the heap fingerprint above, not as the crystal's one-to-one ID.
  - Derived: agreement between two sections has a chance rate. A drawn null draws the rate (A12's form): a section agreeing past all d draws has chance at most 1/(d + 1) under the null. Agreement past that rate reads as shared membership, Doug's "more than one subset". The logic is the period reading's, where agreement past the null at lag p reads the lattice as belonging to its own shifted copy.
  - The null is spatial (Doug: "mutate the data over the spatial coordinate set xyz and get its entire null permutation id"). Built as `knf_identity` ("The knf's identity by spatial null permutation", above).
  - Open: "the broken edge of the crystal". The history reads raw bits, not the crystal or the part the prediction leaves. Whether the history computed on the crystal's highs is the edge Doug means is not settled.
  - Open: the agreement test between sections, comparing departure curves body against body. The curves are printed; the pairwise test is not built.
- **The departure curve** (Doug, 24 September): "we can compare departure curves, the entropy departure curve is probably the most accurate measure because it accumulates all dimensions + time"; "each piece of information no matter how massive has its own departure curve, and it is the integral of all of its constituents"; the mutation "becomes a vector magnitude difference of null permutation plus xmax\xmin\ymax\ymin\zmax\zmin". Posit.
  - Derived: E is a sum over edges, and a departure is linear in E and in the draws' sums. The departure of a whole is the sum of its edges' departures, exactly: the integral of its constituents, with the edge as the constituent. The whole equals its tiles plus its seams at every tile size (proved).
  - Built: each body's curve over its box, the six bounds of the quote. What the "vector magnitude difference" is, as a number, is not defined here. Open.
- **The two nulls** (Doug, 24 September): "they should be very close to 1:1 with one being the inverse of the other, there may be crossover but it will be mutual in volume and universal magnitude". Posit.
  - Measured against it: the two are inverse, with the endpoints exact (inside 0 at b = 1, between 0 at b = 64), and they cross between b = 2 and 4. They are not 1:1: inside plus between dips to 0.590 at b = 4.
  - The gap 1 − (inside + between) is 0.41 at b = 4. Anchor_sift's reading, not proved: an inside-shuffled pair in a small tile still shares a body, and neither null removes that co-membership. The gap is then the share both nulls keep, shared membership at scale b, the mutual part of the quote.

## Open

- **The anchors** (above).
- **The counts in D axes.** The reaches 3ℓ and 3ℓ − 2 for T and L + 2 for T⁻¹ are proved exact along one line ("The boundary"). In D axes they are open.
- **The precision count as a test.** Proved since: `test/engine/record_boundary_test` flips input bits and meets the reach 3L on the device ("The boundary").
- **A table by the residue.** A table indexed by x mod 2^b in two's complement factors through π_w for w ≥ b. It is not built.
- **Operations that commute with T** ([vertical_time_compression.md](vertical_time_compression.md)), now on ℤ₂^n as on ℤ^n. `test/engine/record_boundary_test` proves that constants and lattice moves in 2^{3L}ℤ^n pass through T, and that negation and doubling do not. The general question is open.
- **The fingerprint's counts.** **Proved** since: `test/engine/record_boundary_test` at 24b2785 (Doug's posits, above). The fingerprint per band, not only the total heap, is open.
- **The knf's agreement as a test** (Doug's posits, above). The knf's identity by spatial null is built and run (`knf_identity`, e4eae72). The pairwise test, one body's departure curve against another's, is not built.
- **The two nulls' gap.** Whether 1 − (inside + between) measures shared membership at scale b (Anchor_sift's reading) is not proved.
- **Redundancy.** T is n-to-n and every crystal is legal (the written boundary, proved). A corrupted crystal is another crystal, and T⁻¹ returns other samples with no sign of it: T holds no error correction. A redundant residue system would carry the crystal mod more odd moduli than its range needs. A corrupted residue would then decode outside the range and be caught, and with enough moduli corrected. It would be the classical analogue, on this boundary, of the error-correcting codes of holography. Not built.

## References

- C. C. Chang, "On unions of chains of models", Proc. AMS 10, 1959.
- J. Łoś and R. Suszko, "On the extending of models (IV)", Fund. Math. 44, 1957.
- W. Hodges, "Model Theory", Cambridge, 1993 (unions of chains; Fraïssé limits).
- N. Koblitz, "p-adic Numbers, p-adic Analysis, and Zeta-Functions", 2nd ed., Springer, 1984.
- F. Q. Gouvêa, "p-adic Numbers: An Introduction", 2nd ed., Springer, 1997.
- E. Hewitt and K. A. Ross, "Abstract Harmonic Analysis I", Springer, 1963 (the duals of ℤ₂, the Prüfer group and the solenoid).
- L. Vietoris, "Über den höheren Zusammenhang kompakter Räume und eine Klasse von zusammenhangstreuen Abbildungen", Math. Ann. 97, 1927.
- D. van Dantzig, "Über topologisch homogene Kontinua", Fund. Math. 15, 1930.
- P. Martin-Löf, "The definition of random sequences", Information and Control 9, 1966.
- A. Ostrowski, "Über einige Lösungen der Funktionalgleichung φ(x)·φ(y) = φ(xy)", Acta Math. 41, 1916.
- J. Tate, "Fourier analysis in number fields and Hecke's zeta-functions", thesis, Princeton, 1950; in J. W. S. Cassels and A. Fröhlich (eds.), "Algebraic Number Theory", Academic Press, 1967.
- W. Sweldens, "The lifting scheme: a custom-design construction of biorthogonal wavelets", Appl. Comput. Harmon. Anal. 3, 1996.
- G. J. Chaitin, "A theory of program size formally identical to information theory", J. ACM 22, 1975.
- J. R. Shoenfield, "On degrees of unsolvability", Annals of Math. 69, 1959.
- J. D. Hamkins and A. Lewis, "Infinite time Turing machines", J. Symbolic Logic 65, 2000.
- P. Koepke, "Turing computations on ordinals", Bull. Symbolic Logic 11, 2005.
- A. C. A. Hope, "A simplified Monte Carlo significance test procedure", J. Royal Stat. Soc. B 30, 1968.
- L. Borsten and H. Kim, "Limits to Computational Acceleration Imposed by Quantum Field Theory and Quantum Gravity", arXiv:2604.00182, 2026 (the abstract page read, 24 September 2026).
- S. Aaronson, "On black holes, holography, the Quantum Extended Church-Turing Thesis, fully homomorphic encryption, and brain uploading", Shtetl-Optimized, 27 July 2022, scottaaronson.blog/?p=6599 (the post read, 24 September 2026).
