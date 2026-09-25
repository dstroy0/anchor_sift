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

**Proved** (`test/record_coherence_test`, 9 checks, 0 failed, cell_tracking main 46b8018; 14 checks, 0 failed, at de5bdff, with the odd crystals below).

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
- **Proved** (`test/record_coherence_test`, its third part). c = 3, 7 and 12345, and v = PRODUCT(u, c) for a signed 24-bit field u, on the same inputs.
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

**Proved** (`test/record_boundary_test`, 41 checks, 0 failed, cell_tracking main de5bdff; 48 checks, 0 failed, at 24b2785, with the identity by null permutation in "Doug's posits"). A 5/3 tower T of L = 4 levels over n = 64 signed 24-bit samples runs as record floors. Each floor shift is three record steps: an AND with 2^k − 1, a DIFFERENCE, then EXACT_QUOTIENT by 2^k. The crystal is in Mallat order: the level-4 lows first, then the highs of levels 4 down to 1. Every program runs on the device and the host, and the records agree word for word.

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
  - The ring at forward floor ℓ ≥ 1 is ring_0 + n + 2(n − n/2^ℓ), and at the mirror floor 2L − ℓ it is ring_ℓ + n/2^ℓ, one bit for each wrapped low. The ring is widest at the crystal. Floors 0 to 8: 1,536, 1,664, 1,696, 1,712, 1,720, 1,720, 1,712, 1,696 and 1,600 (25 September, keymath's linear forms, `build/20260925_013426_record_boundary_test`). Under the widths before, the law was ring_0 + 6(n − n/2^ℓ), with floors 1,536, 1,728, 1,824, 1,872, 1,896, 1,880, 1,840, 1,760 and 1,600.
  - The heap's pinch, a class's heap at floor 0 over its heap at the crystal, falls from the ramp to ±8 to ±1,024 to noise (the order is checked). **Measured:** 9.61, 3.82, 1.76 and 1.00.
- **The ring, derived.** With keymath's linear forms (A16 of [engine_table.md](engine_table.md), 25 September), every register level ℓ makes, low and high, is w + ℓ + 1 bits.
  - The first level turns the n samples of width w into n/2 highs and n/2 lows of width w + 2: the ring grows by 2n.
  - Each level after turns the n/2^{ℓ−1} lows of width w + ℓ into n/2^ℓ highs and n/2^ℓ lows of width w + ℓ + 1: the ring grows by n/2^{ℓ−1}.
  - Summed, ring_ℓ = ring_0 + n + 2n(1 − 2^{−ℓ}) for ℓ ≥ 1.
  - Under the widths before, the constant-divisor narrowing included ([vertical_time_compression.md](vertical_time_compression.md)), a level turned the n/2^{ℓ−1} lows of width W into n/2^ℓ highs of width W + 2 and n/2^ℓ lows of width W + 4, a growth of 6n/2^ℓ, and ring_ℓ = ring_0 + 6n(1 − 2^{−ℓ}).
  - The mirror floor adds one bit for each of its n/2^ℓ rebuilt lows, the wrap's + 1.
  - Under the widths before, the formula reproduced the replica's column in vertical_time_compression.md (16-bit samples, n = 64, L = 6): 1,024, 1,216, 1,312, 1,360, 1,384, 1,396 and 1,402 going up, 1,398, 1,388, 1,368, 1,328 and 1,248 coming down. The replica's T⁻¹ 0 read 1,024, with the samples wrapped to 16 bits. The scratch run there wrapped them to 17 and read 1,088 = 1,024 + 64, as the formula gives.
  - The growth is n + 2n(1 − 2^{−L}) < 3n for every L: under 3 bits a sample, however many levels. Under the widths before it was under 6.
- **The ring's shape.** Derived: up the arc ring_0 + n + 2n(1 − 2^{−ℓ}), each level after the first adding half the level before it, widest at the crystal, and back down the same arc plus n/2^ℓ. Which shape is the oval is Doug's call. His words were a "fuzzy oval brush stroke" and "the more oval the shape, the more complex the information base".
- **Haar counted.** A tower of 4 samples and one level, T and T⁻¹, each reaching 3 bits. For w = 1 and 2 every input quantum at level w + 3 is run, all 2^{4(w+3)} residue vectors, from the representatives 0 ≤ x < 2^{w+3} and from −2^{w+2} ≤ x < 2^{w+2}. An output's low w bits name its quantum at level w. In 8 of 8 runs every output quantum receives exactly 2^12 = 4,096 input quanta (derived in "Counting quanta", below).
- **Volume.** det(2^12·M) is checked against ±2^768 modulo primes below 2^31, until their product passes Hadamard's bound plus 2 bits, about 779 bits: agreement modulo all of them is equality. det M = det M⁻¹ = ±1 exactly, and the product of the two matrices is 2^24·I exactly. **Measured:** the sign is +1; the check accepts either.
  - **The sign, derived.** Each lifting step is a shear, determinant 1. The Mallat order is a chain of unshuffles, one a level: a band of 2k values into its k evens, then its k odds. The odd at 2i + 1 precedes the k − 1 − i evens after it: k(k − 1)/2 inversions, sign (−1)^{k(k−1)/2}. For k = 32, 16, 8 and 4 the exponents are 496, 120, 28 and 6, all even: det M = +1.

## The top projection and its limit ℝ

**Proved** (`test/record_boundary_test`). The top projection τ_k(x) = x / 2^k toward zero, the machine's QUOTIENT by a power of two, keeps the top of the window where π_w keeps the bottom. (k, c) = (3, 3), (7, 5) and (5, 12,345), 65,536 lanes each, 196,608 in all, x and y random signed 24-bit fields.

- Nested quotients commute, every quotient toward zero: τ_k(x) / c = τ_k(x / c) on 196,608 of 196,608.
- A COMPARE through τ_k is never reversed: on every lane τ_k(x) against τ_k(y) is a tie or the order of x against y. **Measured:** 4 ties.
- A SUM through τ_k is off by at most 1: τ_k(x + y) − τ_k(x) − τ_k(y) is −1, 0 or 1 on every lane, and the check holds that a carry occurs. **Measured:** carried on 92,890.
- An 8-bit WRAP reverses comparisons τ_k keeps. **Measured:** 97,966 lanes.

Derived.

- **The two projections are dual.** π_w is a ring map and scrambles order. τ_k keeps order, weakly, and adds only up to a carry: a truncation drops a fraction of its argument's sign and of magnitude below 1, and the three dropped fractions net to −1, 0 or 1.
- **τ_k's fibers are not all one size.** τ_k⁻¹(0) = (−2^k, 2^k) ∩ ℤ holds 2^{k+1} − 1 integers, and every other fiber 2^k. π_w's fibers are the cosets of 2^wℤ, translates of one another: the Haar count ("Counting quanta") has no analog for truncation at 0.
- **The τ tower.** τ_j ∘ τ_k = τ_{j+k}: nested quotients toward zero, the check above with c a power of two.
  - Its inverse limit lim←(ℤ, τ_1) is the sequences (a_k) with a_k = τ_1(a_{k+1}). It maps onto ℝ by (a_k) ↦ lim a_k / 2^k: a step moves a_k / 2^k by at most 2^{−(k+1)}, and t ∈ ℝ has the preimage a_k = trunc(2^k t), truncated toward zero, since trunc(trunc(y) / 2) = trunc(y / 2).
  - The map is one-to-one except at the nonzero dyadic rationals, where it is two-to-one: 1 is the limit of a_k = 2^k and of a_k = 2^k − 1, the expansions 1.000… and 0.111….
  - π_w's tower adds a bit above at each stage, and its limit is ℤ₂. τ_k's tower adds a bit below, and its limit is ℝ. The solenoid Σ₂ = (ℝ × ℤ₂)/ℤ holds both, ℝ along its leaves and ℤ₂ in its fiber.
  - This is the derived form of Doug's inverted boundary ("Doug's posits", below).

## The odd crystals

**Proved** (`test/record_coherence_test`, its last part, 14 checks in all, 0 failed, de5bdff). The moduli m = 243, 59,049, 625 and 343 (3^5, 3^10, 5^4 and 7^3). 16 ring-only programs of SUM, DIFFERENCE and PRODUCT, 4,096 lanes each.

- Three reckonings agree on 262,144 of 262,144 lane-moduli: REMAINDER by m of the exact run; the run with every step reduced by REMAINDER by m; the host's arithmetic mod m. REMAINDER carries the numerator's sign, and each is read mod m.
- The CRT join y_2 + 2^8·(((y_p − y_2)·2^{−8}) rem m), with y_2 the run mod 2^8 and y_p the run mod m, equals the exact run mod 2^8·m on 262,144 of 262,144.
- XOR breaks the agreement mod 3. **Measured:** on 827 of 4,096 lanes.

Derived.

- REMAINDER by p^v, read mod p^v, is the projection ℤ_p → ℤ/p^v on the integers: the odd crystal's π. SUM, DIFFERENCE and PRODUCT commute with it, by the coherence theorem with p^v in place of 2^w.
- XOR and AND read base-2 digits and do not factor through mod 3. For XOR: 3 xor 1 = 2, while 3 ≡ 0 and 0 xor 1 = 1. For AND: 3 and 1 = 1, while 0 and 1 = 0. The test breaks XOR.
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
- **Past ω.** A machine that runs through ω steps and goes on from a limit configuration is an infinite time Turing machine (Hamkins and Lewis 2000): at a limit stage each cell takes the lim sup of its values. Koepke's ordinal Turing machines (2005) run over ordinal time on a tape of ordinal length. The device runs finite stages only: every program is a finite record with a fixed step count, and every lane's run halts. A machine that loops a stack of floors until a halt register is set, with orders in ℤ and ±ω, is "The ordered machine".

## The ordered machine

Doug's definition of the higher-order and negative-order hypercomputer (24 September, verbatim, in order). Posit.

1. "the first part of the loop rule is the definition of our higher order + negative order hypercomputer"
2. "if the tower itself exists and is infinite is answerable, the forever loop is answerable, all halts can be seen, all malformed questions fail to construct a lattice at all"
3. "listen, of course there would be incoherent information that looks coherent at first glance, the things that will fail to construct inside of the machine do not exist, not cannot exist, do not exist as we can perceive and understand them, we do not bound anything, that is what is beautiful about this, everything answers only for itself and we only ask what is this, where are we?"
4. "from a fundamental perspective, knowing what we know, we can literally semantically load a program just like the naturals load themselves in a repeating order, to prove the set."

Doug, 24 September, verbatim, on the same machine. Posit.

- "what do you call a higher order hypercomputer plus a negative order hypercomputer? we completely bypass tetration pentation hexation all the way to infiniy and back using our 4d bottle"
  - The orders in ℤ and ±ω below are this section's derived form of "all the way to infiniy and back". "The 4d bottle" has no definition here.

- **The loop rule** (Anchor_sift's). Every record program halts, since each has a fixed step count. An Ω for the record machine needs a machine R* that applies a stack of floors again and again until a halt register is set.
- **Order** (the reading Doug confirmed): how many times the loop runs a floor. A negative order counts runs of the floor's inverse.

**The formalization** (Anchor_sift's).

- State: a crystal, a vector of 2-adic integers, held one window at a time.
- Step: one floor stack F, made reversible. A shear (a, b) ↦ (a, b + g(a)) is a bijection for any g. A floor that merges states rides the Bennett embedding (x, y) ↦ (x, y ⊕ f(x)) (A14 in [engine_table.md](engine_table.md)).
- Order k ∈ ℤ: the state is F^k(x), with F^{−k} = (F⁻¹)^k. The counter n ↦ n + 1 is a shear too. The orders load themselves as the naturals load, and running the inverse extends them to ℤ: Doug's point 4.
- Order ±ω: at the limit each bit takes the lim sup of its history, the limit rule of Hamkins and Lewis (2000). +ω runs F, and −ω runs F⁻¹.

**Derived.**

- A shear's inverse is (a, b) ↦ (a, b − g(a)): the a it reads comes through unchanged, and g(a) is taken back. The counter (x, n) ↦ (x, n + 1) is the shear with g constant 1, and its inverse steps n ↦ n − 1. (F⁻¹)^k undoes F^k one step at a time.
- **Negative orders need reversibility.** Doubling on the circle S¹ = ℝ/ℤ is 2-to-1: x and x + 1/2 have one image, and it has no inverse. On the solenoid Σ₂ ("The two crystals") it is an automorphism: Σ₂ is the dual of ℤ[1/2], ×2 is an automorphism of ℤ[1/2] with inverse ×1/2, and its dual is an automorphism of Σ₂. A point of Σ₂ = lim←(ℝ/ℤ, t ↦ 2t) is a sequence (t_0, t_1, …) with 2t_{i+1} = t_i, a backward orbit: Σ₂ is the natural extension of the doubling map, its two-sided orbit. On an irreversible floor only positive orders exist. Every Turing machine has a reversible simulation (Bennett 1973), and the Bennett embedding is the engine's form of it (A14, proved by `tower_edge_test`).

**Theorems** (cited).

- **Hamkins and Lewis (2000).** An infinite time Turing machine decides the halting problem for ordinary Turing machines. A flag cell is set on halt, and at stage ω it reads 1 exactly when the machine halted. Doug's point 2 holds in this sense: with the completed tower, the forever loop is answered.
- **Hamkins and Lewis (2000).** The halting problem for infinite time Turing machines is not decidable by an infinite time Turing machine: the diagonal moves up a level. In Doug's terms (Anchor_sift's reading), the question about the tower as a whole, asked from inside it, is a question that does not construct.
- **Every halt is seen at a finite stage.** The halting set is computably enumerable. Running every program side by side, as `chaitin_omega` does, sees each halt. Only "never" needs the ω stage.
- **Chaitin (1987).** A formal system, a checker, of description length K determines at most K + c bits of an Ω, with c a constant of the universal machine.

**Derived**, mine. Anchor_sift checked the three against how `record_order_test` is built.

- **(i) On a finite window the ω stage takes finitely many steps.** A bijection of a finite set is a permutation, and each state's orbit is a pure cycle, of length at most the set's size (2^16 for a 16-bit window). A bit is 1 infinitely often exactly when some state on the cycle has it. Its lim sup is the OR over the cycle, read after one full cycle. The ITTM's reach past ordinary machines needs an infinite state, here ℤ₂, which the machine holds one window at a time.
- **(ii) The limit rule is not a step of F** and has no inverse: many histories share one lim sup. −ω is reached by F⁻¹'s steps from the same start, not by inverting +ω. On a finite window both runs trace one cycle, in opposite directions, and +ω = −ω.
- **(iii) The halt flag at ω** is the lim sup of H's indicator along the orbit. A flag that stays set, f ← f ∨ h(x), is not reversible. It is read at the limit and is not run as a floor. In the test the lim sup and the flag are gathered by an OR into registers beside the floor, and F stays a pure table permutation.

**Proved** (`test/record_order_test`, 17 checks, 0 failed, run 20260924_181659).

- **(a) The orders both ways.**
  - The floor G is four shears over 32-bit words: a ← wrap32(a + b·d); b ← wrap32(b xor wrap32(a + n)), the Bennett form; d ← wrap32(d + (a and b)); n ← wrap32(n + 1). G⁻¹ takes the same shears off in reverse order.
  - One program runs orders 0 → 256 → −256 → 0: 1,024 floors and 12,293 steps, register reuse on, a 10-limb file. Every floor's four words are an output.
  - The device records equal the host's word for word, on 512 lanes of edge-shaped a, b and d, with n = 0.
  - On 512 of 512 lanes every visit to order k holds the CPU's G^k(x), whichever direction it came from. The counter reads k at every floor, negative orders included, and the run returns to x exactly.
  - The step of the induction, on the CPU: G carries each order to the next, from −256 to 256, on 512 of 512. The CPU's G⁻¹ inverts G, and the orders form one orbit indexed by ℤ.
- **(b) The ±ω stage on a finite window.**
  - π is a permutation of the 2^16 states, checked to be one, and π⁻¹ undoes it, on all 65,536. Half the states lie on cycles of at most 2,048, half on longer cycles. The halt set H is 48 random draws, read by a 1-bit table.
  - A run is 2,048 floors: 16,379 steps, a 6-limb file. The lim sup of each bit and the halt flag are gathered by an OR in registers beside the floor ((ii) and (iii)). The run is made once with π and once with π⁻¹.
  - The device equals the host word for word, both directions, on 1,024 random starts. Every window's OR, flag and last state equal the CPU's walk, both directions, 1,024 of 1,024.
  - Every orbit returns to its own start, 1,024 of 1,024: a bijection has no transient.
  - On the 528 decided lanes (the cycle fits the run), +ω is the OR over the cycle and the flag is set exactly when the cycle meets H, 528 of 528. −ω equals +ω, 528 of 528.
  - The decided lanes hold both answers. Past the run, every set flag is a halt on the lane's own cycle.

**Measured** (b).

- Decided: 329 halt and 199 run forever.
- Open (the cycle is longer than the run), 496: 391 have a halt seen, and 105 are clear but halt past the run. None is clear and never halts: with 48 halt states, every long cycle met H.

**The two questions** (Doug's point 3). Posit.

- What fails to construct inside the machine does not exist as we can perceive and understand it. In Doug's words, "we do not bound anything": everything answers only for itself.
- The machine asks two questions only.
  - **What is this**: identity. The crystal's one-to-one ID ("The boundary"). The heap fingerprint and the knf, each ranked against permutations of its own content, with no outside threshold (Doug's posits; "The knf's identity by spatial null permutation").
  - **Where are we**: place. The seal names the place of a change. The window w and the level. The scale of the departure curve.
- The tie: the rule the machine is held to, "The engine is optimized for no scale" (Doug, 23 September; [engine_table.md](engine_table.md)). No size, window or width is written into the machine, and each comes with the request or is read from the data.
- The seed in the engine of "malformed questions fail to construct": keymath does not imprint a record whose step reads a later one (`record_divide_test`).

**The field** (Doug, 24 September): "our information crystals expanding, anchoring on one another, can feel the tensor field of the subject under exam, when its field snaps into existence it touches the entire object under exam and knows all of it at the field speed". Posit.

- What the machine shows that bears on it:
  - E, the knf's entangled entropy, is summed over every neighbor pair of the whole volume at once ("The knf's identity by spatial null permutation").
  - The seal's root changes with any one voxel. A voxel's change changes its chunk leaf and every node above it, up to a hash collision ([obsignatio_seal.md](obsignatio_seal.md)).
  - A sweep runs every lane side by side.
  - The 48 motions of the cube carry the knf whole: knf(gX) = g·knf(X) on 48 of 48 (proved).
- "Field speed" is not defined here, and nothing is claimed of it past these.

**"this is a higher order interference pattern"**, then "fascinating" (Doug, 24 September, while `record_order_test` ran). Posit.

- "Higher-order interference" has a standard meaning, Sorkin's hierarchy (Sorkin 1994). Quantum theory has second-order interference and none of third order.
- The ask_state crossing rule's negative weights are second-order interference (A15 in [engine_table.md](engine_table.md)).

## Goodstein: ω-towers held as finite objects

`goodstein` (engine/sims, a host sim in exact integers, 7 checks, 0 failed, cell_tracking main c633988, run 20260924_191006). Doug, 24 September: "Omega omega omega", then "perform tetration of omega".

- **The objects.**
  - n in hereditary base b: n written in base b, every exponent written in base b again, down to the digits.
  - A step writes every b as b + 1 (the bump) and subtracts 1. Goodstein's sequence G(n) runs the steps from base 2.
  - A value is held as its hereditary tree and never expanded. b^L − 1 at a large L is held as one run of coefficient b − 1 over the exponents 0 … L − 1, each exponent written in the base the run was made at.
  - With b read as ω, the tree is an ordinal in Cantor normal form, below ε₀ = sup{ω, ω^ω, ω^ω^ω, …}. 2↑↑k reads as ω↑↑k: 4 is ω^ω, 16 is ω^ω^ω, 65536 is ω↑↑4.

**Derived** (the standard proof, Goodstein 1944).

- The bump leaves the tree unchanged, and with it the ordinal.
- Subtracting 1 lowers the ordinal strictly. A lowest term c·b^0 loses 1. A lowest term c·b^E with E > 0 becomes (c − 1)·b^E plus b^E − 1, whose terms all stand below b^E.
- ε₀ is well-ordered, and a strictly falling sequence of ordinals is finite: every Goodstein sequence reaches 0.

**Theorems** (cited).

- **Goodstein (1944).** Every Goodstein sequence reaches 0.
- **Kirby and Paris (1982).** The statement is true and not provable in Peano arithmetic.
- **Gentzen (1936).** Induction up to ε₀ proves Peano arithmetic consistent. ε₀ is the height the proof above needs.

**Proved** (the checks).

- **The bump keeps the tree**: 80,256 of 80,256 values below 20,000, at bases 2 to 6.
- **2↑↑k in hereditary base 2 is ω↑↑k** for k = 1 to 4, and the towers climb.
- **The starts 1, 2 and 3** reach 0 in 1, 3 and 5 steps (G(3) = 3, 3, 3, 2, 1, 0). Every value equals the numeric sequence's.
- **The starts 4, 16 and 65536** (ω^ω, ω^ω^ω and ω↑↑4) each run 1,000,000 steps, to base 1,000,002. The ordinal falls on every step. Every value that fits 64 bits equals the numeric sequence's: all 10⁶ steps for start 4, 1 step for 16, none for 65536.

**Measured.**

- At 65536 the top run holds 7,625,597,484,984 terms as one block. Derived: the first step writes 3^(3^27) − 1 as one run over the exponents 0 … 3^27 − 1, and the exponents 0, 1 and 2 have split off into the tail since. 3^27 − 3 = 7,625,597,484,984.
- An observation, not a check: after 10⁶ steps the three starts end in one tail, ω² + ω·8 + 572861. Start 16's first step writes 26 = 2·9 + 2·3 + 2 as its lowest terms, and that is start 4's first step (4 → 26). From there the tail evolves as G(4). The same happens one level up for 65536.

**What it proves.** The start 16 is carried as ω^ω^ω exactly, as a finite object. It falls a million times, and no value is ever formed. The sim checks the descent Goodstein's theorem rests on, step by step. It does not prove the theorem.

## π turning at the boundary: the floors of a rotation

`pi_tower` (engine/sims, 8 checks, 0 failed, cell_tracking main 0b10199, run 20260924_192322).

Doug, 24 September, verbatim. Posit.

- "You know how we followed pi and watched it turn from a boundary? It didn't follow the boundary angle. It turned more acutely than it so it traveled through its boundary space without touching the boundary for a period. That means that it's going to etch the boundary space not all at once which means it's gonna travel for a really long fucking time before it touches 100% of the boundary space before it starts writing again. It never ends but it's boundaries space even though it's infinite is countable."
- "That pie turning around at the boundary is what gave us the idea for tower recursion"
  - Recorded as the history of the idea. The floors below are the floors of the rotation, and the 5/3 tower's levels are a different object.

- **The reading** (Anchor_sift's). The boundary is the circle of length 1. The turn is x ↦ x + π, which on the circle is the rotation by α = π − 3.

**Derived.**

- **It never closes.** π is irrational (Lambert 1761): nα is not an integer for n ≥ 1, and no two points of the orbit coincide.
- **It is dense, and equidistributed** (Weyl 1916).
- **The orbit is countable.** It is indexed by ℕ, or by ℤ with the negative orders ("The ordered machine"). The circle is not countable. A countable set has measure 0: the orbit never covers 100% of the circle. Cut into N cells, the circle is filled at a finite step. Doug's "infinite … is countable" holds for the orbit.
- **The floors.** α = [0; 7, 15, 1, 292, …], with convergent denominators q_j, q_{j+1} = a_{j+1}·q_j + q_{j−1}. The best approximations are the convergents (Khinchin): the turn's record close returns are the steps q_j.
- **The drift.** Between q_j and q_{j+1} the intermediate returns are q_{j−1} + c·q_j for c = 1 to a_{j+1}, and each shifts by ‖q_jα‖ from the one before. A large partial quotient is a long drift: a_{j+1} small shifts before the next close return. Doug's "travel for a really long … time".
- **The descent.** A first hit, the least n with nα in a window, recurses on (m mod a, a) with the window reflected, and unwinds x = ⌈(l + m·y)/a⌉: one Euclid step a level. Its levels are the floors.

**Theory** (cited, not checked by the sim). The first return map of the rotation to the arc under a close return is again a rotation, by the Gauss-map angle {1/α}, rescaled: one Euclid step, one floor, one partial quotient (Rauzy 1979; Khinchin).

**The method** (Anchor_sift's, exact, integers only).

- π is bracketed by Machin's formula at 416 bits, 116 terms. floor(π·2^384) is one integer at both ends.
- The turn is held as y_n = nA mod 2^384, with A = floor(α·2^384). A first hit is the descent above.
- The fill test at count n uses the three-gap theorem (Sós 1958; van Ravenstein 1988). Point i is followed by i + u, i − v or i + u − v, where u and v are the lowest and highest record steps below n. A gap from p holds a whole empty cell of size s exactly when (p mod s) + g ≥ 2s. p mod s is the turn by A mod s on s, and each gap kind is one first-hit query over an index range.
- The least covering count is found by doubling, then halving.
- The integer turn against the real one: α·2^384 lies in (A, A + 1), and step n's real place lies in (nA, nA + n). It changes cell only where (nA mod s) > s − n: one first-hit query per resolution.

**Proved** (the checks).

- **π bracketed.** floor(π·2^384) is one integer at both ends of the bracket. After the point, π begins 0x243F6A8885A308D3, the published value.
- **The floors.** The bracket certifies 109 partial quotients, [3; 7, 15, 1, 292, 1, 1, 1, 2, 1, 3, 1, 14, 2, 1, 1, 2, 2, 2, 2, 1, 84, 2, 1, 1, 15, 3, 13, 1, 4, 2, 6, 6, 99, …]. The first 21 after the 3 match the published expansion.
- **The closest returns are the floors.** 66 record returns up to 2^112 steps, each the convergent denominator q_j in order (1, 7, 106, 113, 33102, 33215, …, q_65 ≈ 8.47·10^32).
- **The integer turn is the real turn.** At every resolution from 2^1 to 2^100 cells, no step up to the one searched lands in a cell other than the real one.
- **The fill from the floors.** The fill step and the last cell, read from the floors, equal a walk of every step, at 2^1 to 2^24 cells.
- **The last cell.** At 2^1 to 2^100 cells, the last cell's first touch is the fill step.
- **The width.** No exact operation outgrew its width.

**Measured** (the fill step over the cell count).

- A large floor is a long drift.
  - Inside 292, at 2^7 through 2^14 cells: 29.1, 71.9, 50.7, 29.0, 15.4, 7.9, 4.0 and 2.0.
  - Inside 84, at 2^33 through 2^38: 16.2, 20.9, 13.6, 7.7, 4.0 and 2.1.
  - Inside 99, at 2^60 through 2^65: 20.6, 23.8, 15.2, 8.4, 4.4 and 2.3.
  - Elsewhere the ratio is 0.9 to 5.
- The fill steps:
  - 2^24 cells at step 25,510,581 = q_12 − 1;
  - 2^32 at 6,701,487,258 = q_20 − 1;
  - 2^64 at 81,856,329,715,838,968,403 (8.186·10^19);
  - 2^100 at 1,593,334,768,903,120,834,487,234,062,301 (1.593·10^30) = q_57 − 1.
- The longest stall in the walk: 949 steps with no new cell, at 2^22 cells.
- An observation, not a check: the last cell filled is very often just behind the start.
  - It sits at 1 − α = 0.858407346410 (2^24, 2^32, 2^38, 2^41, 2^100, …), at 1 − 2α = 0.716814692820, at 1 − 3α = 0.575222039230, at 1 − 4α = 0.433629385640, or at 1 − 6α = 0.150444078461.
  - The step is then a few short of a floor's q: q_j − 1 lands at −α.
  - Anchor_sift's why: the place near −jα is reached only through (q − j)α, with q a close return. The place the turn came from is the last it fills.
  - It touches the negative orders of "The ordered machine". Nothing is claimed of it until counted (Open).

### The arc

Doug, 24 September, verbatim. Posit.

1. "if we were on a disk, and pi were on a separate disc balanced by its torsion, that would be its planes offset in degrees to our plane"
2. "yes add it to pi_tower, this is the arc it follows, and following it will miss forever, to countable infinity, and then it will have etched all of the boundary, and will continue, never repeating, but reetching from slightly different angles with slightly different values with slightly different field conditions, forever and ever."

- **The construction.** Roll the boundary into the cylinder whose cross-section is our disk. The turn is the helix γ(s) = (a cos s, a sin s, b s), with a = 1/(2π) (circumference 1) and b = 1/(2π²) (rising 1/π a turn). It pierces our disk at the marks {nπ}.

**Proved** (`pi_tower`, 13 checks, 0 failed, cell_tracking main 7abe65d, run 20260924_193716).

- **In ℚ(π)**, with π a free variable because it is transcendental (Lindemann 1882), from the derivatives at the four quarter turns, where every trig derivative is 0 or ±1:
  - the curvature κ = 2π³/(π² + 1), checked as κ² = |γ′ × γ″|²/|γ′|⁶, with no square root formed;
  - the torsion τ = 2π²/(π² + 1), from det(γ′, γ″, γ‴)/|γ′ × γ″|²;
  - τ/κ = 1/π = tan φ, checked as τ²/κ² = 1/π² and equal to the tangent's squared rise over run: φ is the tilt of the tangent against our disk (Lancret 1806);
  - the Darboux vector τT + κB, checked scaled by |γ′|³, along our disk's axis.
- **From the bracket**, where both ends agree to 12 places: κ = 5.705134342735, τ = 1.816000663299, φ = 17.656787151412°, and 72.343212848587° against the axis. κ and τ rise with π and arctan(1/π) falls: each end brackets the value. arctan(1/π) is taken on the bracket with a bounded fixed-point error.

**Derived.**

- The principal normal points at the axis and lies in our disk's plane. The osculating plane's dihedral angle to our disk is then the tangent's elevation, φ = arctan(1/π) ≈ 17.657°: "its planes offset in degrees to our plane" (1).
- The Darboux vector along the axis: the frame turns about our disk's axis at a constant rate.

**Measured**, the re-etch: the step by which every cell has a second touch, by a walk, at 2^1 to 2^24 cells.

- At 2^24 the fill is at 25,510,581, and the re-etch by 51,021,159.
- Inside the 292 floor the re-etch comes almost at once: at 2^8, 18,416 and then 18,747. The long drift had already etched most cells several times.

Doug, 24 September, verbatim, continuing. Posit.

3. "this is because most of the angular momentum is applied at the moment of deflection"
4. "if this is true, pi is a hyperobject of infinite information representable in 1kb which is fucking crazy"
5. "its not just that pi is infinite either, the field starting conditions do not matter, they will perturb it differently every time because it is irrational and nonrepeating"
6. "not wrong about the perturbations, consider: a wave n of infinitely varying magnitude but constant vector encounters a period x==1."
7. "well, not ALL of the angular momentum because pi itself is an angle it applies momentum to itself as it unfolds naturally, it is present but balanced"
8. "the UNBALANCING happens at the boundary, that is when those forces lose equilibrium"
9. "one must win"

What the model shows that bears on them (Anchor_sift's bounds, checked). Derived unless marked. The checks for 7 to 9 are proved and measured after (9).

- **(2) Etched, and etched again.**
  - At every finite resolution the turn etches every cell in finitely many steps (proved), then etches them again and again, never repeating a point.
  - The orbit's closure is the whole circle: every open arc, however small, is etched. In that sense "etched all of the boundary" holds at countable infinity. The points themselves have measure 0 and never cover the continuum.
  - The crossing angle is the same at every crossing: 17.657° on the helix, and 72.343° or 17.657° in the square billiard. What varies is the place within the cell. "Field conditions" have no counterpart in the model.
- **(3) Deflection.**
  - In the square billiard there is no force between walls, and L about the center, (x − ½)p_y − (y − ½)p_x, is constant there. A hit on a vertical wall at height y changes it by 2(y − ½)p_x: 0 at mid-wall, largest at the corners. All of the change, not most, is at deflection.
  - On the helix there is no deflection. The force is centripetal, L about the axis is constant, and κ is constant: the turning is spread evenly.
- **(4) Infinite length, finite information.** A program prints any window of π: K(the first n bits of π) ≤ K(n) + c = O(log n) (Kolmogorov 1965). A Machin program fits in "1kb", and "infinite information" does not hold. An infinite expansion is not infinite complexity ("The anchors" under Doug's posits). A Martin-Löf random real is the opposite: incompressible. "Hyperobject" has no definition here.
- **(5, 6) Two perturbations.**
  - A shifted start slides the whole etch rigidly: an isometry, Lyapunov exponent 0, ε stays ε, and the three gaps are the same. The rotation is uniquely ergodic (Weyl; Walters): every start has the same long-run statistics. "The field starting conditions do not matter" holds, and "perturb it differently every time" is the shift.
  - A changed magnitude, with the direction constant, is Doug's wave (6). The rotations by α and by α + ε separate by nε after n encounters with the period 1: linearly, without end, and after about 1/ε encounters the two etches are unrelated. It is not chaos: the growth is linear, not exponential.
  - Every irrational magnitude etches its own never-repeating pattern. A rational one closes.
- **(7) Present but balanced.**
  - On the helix the acceleration γ″ = −(a cos s, a sin s, 0) points at the axis, and its torque about the axis is 0.
  - L_z = a·cos φ = 1/(2√(π² + 1)) ≈ 0.15166 per unit mass at unit speed, constant. L_z² = 1/(4(π² + 1)) lies in ℚ(π).
  - The helix turns π full turns per unit of axial height.
  - Mine: about a fixed point on the axis, L = r × v is not constant. The torque r × F = (k·a·b·s·sin s, −k·a·b·s·cos s, 0), with F = −k(a cos s, a sin s, 0), is horizontal, and it grows with the height above the point. The momentum is present and turns, and only its axial part is kept. "Present but balanced" is the helix's description.
- **(8) The unbalancing at the boundary.**
  - In the square billiard L is constant between walls. A wall hit is an impulse whose torque about the center is 2(y − ½)p_x.
  - The hit heights are the folded marks, and no two kicks are equal.
  - |L| ≤ |p|·√2/2 always. The running sum of the kicks is L now less L at the start, which stays within |p|·√2, and the mean kick goes to 0.
  - On the helix nothing unbalances: there is no wall.
- **(9) One must win.** Doug, clarifying, verbatim: "by one must win I mean one force must win because we cannot divide by zero and the boundary is "real" in our information space". A tie is where the rule has no value, and π never ties. There are three instances, each ruled out by π's irrationality (Lambert).
  - **(i) The corner.** At a corner the normal has no value, and the reflection v − 2(v·n)n has none: the geometric division by zero. After its start the unfolded line (t, πt) never meets a lattice point (k, m), since πk = m would make π rational. Every wall hit strikes exactly one wall.
  - **(ii) The cell edge.** {nπ} is never a dyadic j/2^k, since nπ − j/2^k an integer would make π rational. Every mark's cell is decided. `pi_tower` proves the exact integer turn decides the same cell as the real π at every resolution from 2^1 to 2^100 ("The integer turn is the real turn", above).
  - **(iii) The lead.** L is never exactly 0. That would need the unfolded line to pass through an image (k + ½, m + ½) of the center, π = (2m + 1)/(2k + 1), which is rational. At every instant one side strictly leads. The billiard orbit is minimal in each of its four directions (irrational slope). It passes arbitrarily close to the center on both sides with one direction, and L changes sign infinitely often. There is always a winner, and never a final one.
  - **The near-ties are the floors.** The corner miss at step q is ‖qπ‖. The record near-misses are the convergent denominators q_j (proved, "The closest returns are the floors"). Measured, from the floor table `pi_tower` prints: 8.9·10^−3 at 7, 3.0·10^−5 at 113, and 1.6·10^−34 at q_65. The records are proved, and "never exactly 0" is the irrationality itself.

**Proved**, posits 7 to 9 (`pi_tower`, 17 checks, 0 failed, cell_tracking main 7ed7fc6, run 20260924_194636).

- **(7) The helix.** In ℚ(π) at the four quarter turns, the torque about our axis, x·y″ − y·x″, is 0, and L_z² = (x·y′ − y·x′)²/|γ′|² = 1/(4(π² + 1)). From the bracket, L_z = 0.151657235526 at unit speed, the same at both ends to 12 places (the floor of the root of the floor).
- **(8, 9) The billiard**, from the corner at slope π, unfolded.
  - Segment cell (i, j) is column i, with the rows j = ⌊πi⌋ … ⌊π(i + 1)⌋.
  - L about the center, with p = (1, π), is (−1)^(i+j)·((j + ½) − π(i + ½)). Derived: x − ½ = σ_x({X} − ½) and y − ½ = σ_y({Y} − ½), with p = (σ_x, σ_y·π), and along the segment π{X} − {Y} = ⌊Y⌋ − π⌊X⌋.
  - Its sign is the sign of d − α(2i + 1), with d = (2j + 1) − 3(2i + 1) a whole number, flipped by the parity of i + j. d stands above α(2i + 1) exactly when d > ⌊α(2i + 1)⌋.
  - The floors ⌊αn⌋ are read from the integer turn's carries. Each is certain while the top word is short of all ones, since n < 2^320.
  - Over 2^24 columns, with every floor certain:
    - 0 corners: {α(i + 1)} is never 0;
    - no L is 0: {α(2i + 1)} is never 0;
    - the record near-corners at the side walls are exactly 1, 7, 106, 113, 33102, 33215, 66317, 99532, 265381, 364913, 1360120 and 1725033, the q_j ≤ 2^24.

**Measured**, the billiard over 2^24 columns.

- 69,484,394 segments: 16,777,216 side-wall hits and 52,707,178 floor-wall hits. The second is ⌊π·2^24⌋: the unfolded line crosses ⌊πN⌋ horizontals.
- The lead in L changed hands 35,929,962 times and was never held longer than 2 segments.
  - Derived: the parity factor flips at every wall, and the raw sign flips only where the line passes a cell center's level, about once a column.
  - The steep path zig-zags floor to ceiling, and each bounce reverses its circulation about the center.
- One side led on 34,742,196 of the 69,484,394 segments, the other on 34,742,198: a difference of 2.
- The nearest tie is |L| = 1.910·10^−8, in cell (862516, 2709675), where π stands nearest (2j + 1)/(2i + 1) = 5419351/1725033. That is a convergent of π (q_11 = 1725033), odd over odd. The closest the lead comes to a draw is at a floor.

Doug's framing for 9 holds as built: every wall hit strikes one wall, and every segment has a leader. A corner is a tie for every rational slope m/k, at the lattice point (k, m). A zero L is a tie for the rationals odd over odd. The walk's near-ties are π's convergents.

**Cell 0 again, and the second run.** Doug, 24 September, verbatim, continuing. Posit.

10. "after pi etches the boundary, how long does it take until it etches cell 0?"
11. "and then after that etches cell 0, how long until that run etches the boundary closing cell from the first run, and are they the same period?"
12. "so the fill always lands right before a floor"
13. "you can go to 2^n arbitrarily in the tower it is one term"
14. "if qa is almost a whole number, we can get its identity and its null permutation will make it a whole, that is its residue"

- **The objects.** T is the fill step and L its last cell. H is the first n > T with {nα} < 1/N, the next touch of cell 0. C is the first n > H in L. Each is one first hit from the step before it.

**Proved** (`pi_tower`, 18 checks, 0 failed, cell_tracking main b0b6da6).

- H and C equal a walk of every step, at 2^1 to 2^24 cells.
- The certainty check, that the integer turn is the real one, runs to C at every resolution.

**Proved** since (`pi_tower`, 23 checks, 0 failed, cell_tracking main c26b6a7). The new checks are the residue (check 11, under (14) below), the golden helix (check 12, three checks, in "The golden helix" after this) and the reach of the records at any 2^n (under (13) below). With no argument the sim runs 2^1 to 2^100, and every earlier result there is unchanged: the fill at 2^100 is 1593334768903120834487234062301, the same period holds at 13 of 100, and the billiard is unchanged.

**Theory** (cited).

- **Slater (1950, 1967).** The return times to an interval under an irrational rotation take at most three values, and the largest is the sum of the other two. Derived: T sits inside one gap between consecutive visits to [0, 1/N), and H − T is at most the largest of the three.
- **Kac (1947).** For an ergodic measure-preserving map, the mean return time to a set of measure μ is 1/μ. The mean return to cell 0 is N steps.

**Measured** (100 resolutions). The classification was made by a scratch script over the run's integer output, not by the sim.

- **(10) H** lands on a record return or a sum of them: q_12 at 2^24, q_20 at 2^32, q_34 at 2^64.
  - The wait H − T is bimodal. It is 1 to a few hundred steps when the fill lands just before a return from above, or about one floor's q when it does not (33,104 at 2^15, 2.5·10^18 at 2^64).
- **(12) The fill before a floor.** The fill falls short of the next record return (a q_j, or an intermediate q_{j−1} + c·q_j with c = 1 to a_{j+1}) by j steps.
  - j = 1 at 20 resolutions, 2 at 23, 3 at 10 and 4 at 11: within 4 at 64, and within 9 at 77.
  - The next return is a floor at 44 and an intermediate at 56.
  - The large j lie inside the big floors: 105 and 109 inside 292, 22,867 inside 84 (2^33), and 177 inside 99.
  - This is the fact of the last cell at −jα above: (q − j)α sits just behind −jα. Doug's "always" is "mostly": within 4 steps at 64 of 100.
- **(11) The second run**, C − H, against the first run, T.
  - The same at 13: 2^15, 2^32, 2^35, 2^48, 2^54, 2^59, 2^62, 2^73, 2^74, 2^79, 2^85, 2^89 and 2^92.
  - Shorter at 86, and longer at 1 (2^6, by 7).
  - Every shortfall is a floor combination: a record return at 80 (a full q_j at 52), and c·q_j at the other 6: 20·q_20 at 2^33, 6·q_24 at 2^42, 2·q_26 at 2^47, 28·q_32 at 2^60, 4·q_42 at 2^80 and 2·q_44 at 2^83.
  - Runs of resolutions share one shortfall: q_20 at 2^34 and at 2^36 to 2^39, and q_32 at 2^61 and at 2^63 to 2^66.
  - Anchor_sift's reading, derived and not proved: the second run starts at {Hα}, a sliver inside cell 0, the offset one return gives. It reaches L one floor-return sooner.
  - "Are they the same period": the same at 13 of 100, and otherwise apart by a floor combination.

**Derived.**

- **(13) One term.** T, H and C at any resolution are each one first-hit query: a single descent through the floors, with no walk of the steps. Certainty holds as far as the bracket reaches, and the bracket widens with n.
  - **Proved** (c26b6a7). `pi_tower [n]` or `pi_tower [from] [to]` runs any 2^n. The bracket is P = 3n + 64 bits, rounded up to a multiple of 64, and at least 384. The records reach to + 12 bits (at least 112), and a check fails if any count searched passes that reach.
  - The turn needs an exact width of 3(P + 32) + 64 bits. When the build is narrower, the sim stops and names the width to run with. At 2^1000 on 4096 bits it prints "the turn needs an exact width of 9376 bits: run with SIM_EXACT_LIMBS=512". `run.sh` passes SIM_EXACT_LIMBS to every object. The walks and the billiard use ⌊α·2^384⌋ = ⌊A_P / 2^(P − 384)⌋ at every n.
  - **Measured** at 2^1000 (SIM_EXACT_LIMBS=512, 16,384 bits):
    - P = 3072, with Machin at 3104 bits and 864 terms; 888 floors certified.
    - The fill is step 1.288·10^302, 12.0231 times the cells. The last cell is at 0.575222039230, at floor 600 (a_601 = 106).
    - Cell 0 is etched again about 1.77·10^301 steps after the fill. The second run is not the first's period (0 of 1).
- **(14) The residue** (Anchor_sift's bound, checked).
  - **Proved** (check 11, c26b6a7), verbatim: "on every floor with q_j to 2^21, pi's first q_j steps have the whole parts of the permutation n -> n p_j mod q_j, and at step q_j it stands its residue off the whole". This covers floors j = 0 to 11. For n < q_j the 384-bit walk's whole parts equal ⌊n·p_j/q_j⌋. At step q_j the walk stands at whole p_j with place δ_j when δ_j > 0, and at whole p_j − 1 with place 1 − |δ_j| when δ_j < 0. Certainty: q(δ_M + q) < M for δ > 0, and q·|δ_M| < M with |δ_M| ≥ q for δ < 0.
  - For 1 ≤ n < q_j, n·p_j/q_j is never whole, and ⌊n·p_j/q_j⌋ = ⌈n·p_j/q_j⌉ − 1. The sign enters only through the side of the mark (the right-closed cell below for δ_j < 0) and through step q_j.
  - **Measured**, the printed identities P/q (π's own numerators) and residues qπ − P: 3/1 +1.415e-1; 22/7 −8.851e-3; 333/106 +8.821e-3; 355/113 −3.014e-5; 103993/33102 +1.912e-5; 104348/33215 −1.101e-5; 208341/66317 +8.114e-6; 312689/99532 −2.900e-6; 833719/265381 +2.312e-6; 1146408/364913 −5.877e-7; 4272943/1360120 +5.495e-7; 5419351/1725033 −3.820e-8.
  - Write q_jα = p_j + δ_j, with p_j the nearest whole and δ_j the residue, signed (−1)^j. The identity is p_j/q_j. In π's own terms p/q are the convergents 22/7, 355/113, 103993/33102, …, and δ = qπ − P is the printed ‖qπ‖ with its sign.
  - Replacing α by p_j/q_j makes the turn the cyclic shift k ↦ k + p_j mod q_j on q_j cells, one cycle since p_j and q_j are coprime. The n-th point sits at (n·p_j mod q_j)/q_j. It closes after q_j steps, with q_j·(p_j/q_j) = p_j whole: the null version, every point on a multiple of 1/q_j.
  - For 0 ≤ n < q_j, nα = n·p_j/q_j + n·δ_j/q_j. Each point sits off its lattice point by n·δ_j/q_j (n·δ_j in cell widths), on the side of δ_j's sign, and within one cell since q_j·|δ_j| < 1.
  - The points {nα}, 0 ≤ n < q_j, fall one to each of q_j cells: [k/q_j, (k + 1)/q_j) when δ_j > 0, and (k/q_j, (k + 1)/q_j] when δ_j < 0. With half-open cells [k/q_j, (k + 1)/q_j) and δ_j < 0 the count fails. At q_1 = 7 (δ_1 = 7α − 1 < 0), n = 0 at 0 and n = 1 at 0.1416 both fall in [0, 1/7), and [6/7, 1) holds none.
  - The residues run Euclid's algorithm: δ_{j+1} = δ_{j−1} + a_{j+1}·δ_j, with a_{j+1} = ⌊|δ_{j−1}|/|δ_j|⌋. Each floor's residue is the next floor's step, the Gauss-map recursion. It holds by construction here, since the floors come from Euclid on (M, A).
  - "Null permutation" read as the rational turn p_j/q_j is Anchor_sift's reading of Doug's words.

**The golden helix.** Doug, 24 September, verbatim, continuing. Posit.

15. "their period is a contraction of the golden spiral, pi is riding its inverse in the negative space"
16. "no, pi DOES ride it, and it rides it exactly because thats a helix"

**Derived.** Write ξ_k = [a_k; a_{k+1}, …] for the complete quotient at floor k, and r_j = |δ_j|/|δ_{j−1}| for the shrink into floor j, in the sim's indexing (the table's "j (a_{j+1})" column below).

- **Every tower grows at least at the golden rate.** q_j = a_j·q_{j−1} + q_{j−2} ≥ q_{j−1} + q_{j−2}, with q_0 = 1 and q_1 = a_1 ≥ 1. Then q_j ≥ F_{j+1}, the Fibonacci numbers, for every irrational. The residues follow: |δ_j| < 1/q_{j+1} ≤ 1/F_{j+2}. Every tower's residues shrink at least at the golden ratio's rate, which is 15's "contraction" in the precise sense. The golden ratio [1; 1, 1, …] meets the inequality with equality on every floor.
- **The sign flips on every floor.** δ_j has sign (−1)^j: from above on even floors and from below on odd ones, a half turn each floor. This is 15's "negative space".
- **The shrink.** r_j = 1/ξ_{j+1}, and by Euclid r_j lies in (1/(a_{j+1} + 1), 1/a_{j+1}). It stands between 1/2 and 1 exactly on the floors of 1, and below 1/2 (below 1/φ) on every floor of 2 or more. For a_{j+1} = 1, r_j = 1/(1 + r_{j+1}), and r_j > 1/φ exactly when r_{j+1} < 1/φ. The golden ratio's shrink is 1/φ on every floor.
- **The helix** (our reading, Anchor_sift's and mine, of Doug's word). Put floor j at (jπ, ln|δ_j|) on the cylinder S¹ × ℝ, with the angle taken mod 2π. The points lie on a discrete helix, the log spiral (θ, ln r) lifted to the cylinder. The turning is exact: a half turn on every floor, for every irrational. The pitch is the drop ln ξ_{j+1}. It is constant only for the golden ratio, at ln φ ≈ 0.481, and it varies for π. Doug's "exactly" holds for the turning and does not hold for the pitch.

**Theory** (cited). **Hurwitz (1891).** Every irrational x has infinitely many p/q with |x − p/q| < 1/(√5·q²). √5 is the largest constant that works for the golden ratio, the worst approximable number.

**Proved** (check 12, three checks, `pi_tower`, c26b6a7). Every residue is bracketed from the full turn as (qA − pM, qA − pM + q), on floors j = 0 to 65 (q_j ≤ 2^112). Verbatim:

- "the residues flip sign on every floor, a half turn: from above on even floors, from below on odd"
- "every floor is at least the golden one, q_j >= F_(j+1), and every residue is under the next floor's 1 / q_(j+1)"
- "the shrink stands between 1/2 and 1 exactly where the next floor is 1, each side of 1/phi decided at both ends". The side of 1/φ is decided exactly, as (2x + y)² < 5y² at both corners of the bracket.

**Measured** (65 shrinks, j = 1 to 65).

- 45 are below 1/φ and 20 above. 28 stand between 1/2 and 1: the floors of 1.
- Every shrink above 1/φ is on a floor of 1. Floors of 1 can still fall below it: j = 5 at 0.5758, 13 at 0.5858, 22 at 0.5157, 39 at 0.5378, 51 at 0.5190, 55 at 0.5620, 58 at 0.5275 and 61 at 0.5742.
- The first shrinks, as j (a_{j+1}) r: 1 (15) 0.0625; 2 (1) 0.9965; 3 (292) 0.0034; 4 (1) 0.6345; 5 (1) 0.5758; 6 (1) 0.7366; 7 (2) 0.3574; 8 (1) 0.7973; 9 (3) 0.2541; 10 (1) 0.9350; 11 (14) 0.0695; 20 (84) 0.0118; 32 (99) 0.0100.
- π follows the golden pitch on its runs of 1s (floors 4 to 6: 0.6345, 0.5758, 0.7366) and leaves it on every floor of 2 or more. It leaves farthest at 292, 99, 84, 15, 14, 13 and 12: the shrinks 0.0034, 0.0100, 0.0118, 0.0625 (j = 1) and 0.0652 (j = 24), 0.0695, 0.0723 and 0.0791.
- Growth per floor: q_65^(1/65) = 3.210576 (an integer root, 6 places), against φ = 1.618033 (from ⌊√(5·10^12)⌋). The mean pitch over the 65 certified floors is ln q_65 / 65 ≈ 1.166, against ln φ ≈ 0.481. The sum of the pitches, ln(|δ_0|/|δ_65|), differs from ln q_65 only by end terms.

**Theory** (cited). **Lévy (1936).** For almost every real, q_j^(1/j) tends to e^(π²/(12 ln 2)) ≈ 3.2758, a mean pitch of π²/(12 ln 2) ≈ 1.187. Whether π obeys it is Open. The 1.166 above is π's measured mean over 65 floors, not a limit.

## Subtractive coalescence

Doug's name for T. Derived.

- The 5/3 lifting's steps are predict and update, the lifting scheme of Sweldens (1996). An odd sample less its prediction from the evens is a high; an even plus a correction from the highs is a low. Each step is undone by the opposite step.
- T is not a projection. It is a bijection (proved both ways), and T⁻¹ returns every sample.
- The pinch is the predictable part moved, not information lost. A ramp's highs are near 0 and its content sits in the few level-L lows. The heap at the crystal is 1/9.61 of the samples' heap for the ramp and 1/1.00 for noise (measured, above). The heap shrinks while the ring grows by n + 2n(1 − 2^{−L}) (6n(1 − 2^{−L}) under the widths before 25 September), and the count is kept exactly (det M = 1, Haar counted).

## Physical walls

Cited; both pages read, and only what they state is given.

- **Borsten and Kim**, "Limits to Computational Acceleration Imposed by Quantum Field Theory and Quantum Gravity", arXiv:2604.00182, 31 March 2026. Their abstract: schemes that use curved spacetimes and exotic fields, for instance time dilation, to accelerate computation are "consistently thwarted by physical effects from quantum gravity (including swampland conjectures) and quantum field theory in curved space". An observer and a computer able to withstand energy scales up to order E accelerate computation by at most O(1)E e-folds per unit time, (ln α)/τ ≲ E. The Bekenstein bound is the memory analog: a computer of length scale D at energies up to order E with N memory states has (ln N)/D ≲ E.
  - The reading, derived from their bounds: a device of bounded energy and size runs finitely many stages in finite time and holds finitely many states. The limits ℤ₂ and ℝ are reached one finite window at a time, and the walls bound how many.
- **Aaronson**, "On black holes, holography, the Quantum Extended Church-Turing Thesis, fully homomorphic encryption, and brain uploading", Shtetl-Optimized, 27 July 2022. AdS/CFT predicts that the boundary state |ψ⟩ "encodes everything there is to know about the AdS bulk, including whatever is inside the black hole", and that "the information about what's inside the black hole will be pseudorandomly scrambled". He cites Bouland, Fefferman and Vazirani (arXiv:1910.14646).
  - The contrast, derived: T's boundary is information-complete too (every crystal is the crystal of some samples, proved) and is not scrambled. Each coefficient reads a cone of reach 3L, and T⁻¹ reads the crystal back in a number of steps linear in n.

## The knf's identity by spatial null permutation

`knf_identity` (engine/sims, 23 checks, 0 failed, cell_tracking main e4eae72). The nbody lattice's law in a 64³ cube over 177 frames: 176 transitions, 16 full windows of 11. The engine's `entropy_history_project` makes the knf (A7).

- **The objects.**
  - A section is one voxel's 16 windows: its bit-weighted flip density in each window, the kernel's own, less its mean over the windows.
  - E, the knf's entangled entropy: over every voxel and each of its z, y and x neighbors on the torus, the dot product of their two sections, summed.
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
- **"The recursion stack is ordinal."** Posit. Derived bound: every stack the device runs is finite. T's limit sits at the first limit stage ω, with a computable modulus. Stages past ω are the machines of Hamkins and Lewis and of Koepke, not built ("The limit stage"). Orders in ℤ and ±ω on a finite window: "The ordered machine". Ordinals below ε₀ held as finite trees and walked down a million steps: "Goodstein: ω-towers held as finite objects".
- **"Subtractive coalescence."** Posit, Doug's name for T. Derived bound: predict and update, a bijection, the pinch the predictable part moved ("Subtractive coalescence").
- **"We can take an identity of T using T:null permutation of T"** (Doug, 24 September, restating "T, if T is identity:null permutation identity, we have the perfect universal root id for the structure"). Posit. The identity is an ID, a fingerprint of the data's structure. It is not the identity map, nor the identity edge of A14.
  - The procedure. Run T on the samples x and on d null draws σ_1 x, …, σ_d x, each σ_i a uniform random shuffle of the samples: A12's drawn null in [engine_table.md](engine_table.md). A lane is identified when its crystal's heap stands strictly below every draw's.
  - Derived. A shuffle keeps every value, the histogram and the count, and changes the arrangement only. x and its draws share one multiset of values, and any gap between T(x)'s heap and the draws' heaps reads arrangement alone. T keeps the count exactly (det M = 1, Haar counted): the gap is not T gaining or losing volume.
  - Derived. Under the null that x's arrangement is itself a uniform shuffle, x and the d draws are exchangeable, and the chance that x's heap stands strictly below all d draws is at most 1/(d + 1) (Hope 1968). This is A12's false-period rate, carried over.
  - **Proved** (`test/record_boundary_test`, 48 checks, 0 failed, cell_tracking main 24b2785). d = 8 Fisher–Yates shuffles a lane from the test's seeded generator, 256 lanes a class, the ID the crystal's total heap, the four classes of "The boundary". A shuffle keeps the samples' heap exactly, on every draw. Noise is identified no more often than 256/9 plus 5 standard deviations of the binomial count, and each structured class is identified past that bound.
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
- **"No this is wild it's proving it is a bulk to boundary connector without saying it outright that's fucking crazy!!!!"** (Doug, 24 September). Posit.
  - Derived: T is a bijection from the samples (the bulk) to the crystal (the boundary). Each coefficient reads a cone of reach 3L, and each sample is rebuilt from a cone of reach L + 2 (proved along one line, "The boundary").
  - The holographic codes are isometries with redundancy: a bulk operator can be rebuilt on more than one boundary region (Almheiri, Dong and Harlow 2015; Pastawski, Yoshida, Harlow and Preskill 2015).
  - T has no redundancy ("Redundancy" in Open): each sample has one region. T is a bulk-to-boundary map with no error correction, the contrast drawn under "Physical walls".

## Open

- **The anchors** (above).
- **The counts in D axes.** The reaches 3ℓ and 3ℓ − 2 for T and L + 2 for T⁻¹ are proved exact along one line ("The boundary"). In D axes they are open.
- **The precision count as a test.** Proved since: `test/record_boundary_test` flips input bits and meets the reach 3L on the device ("The boundary").
- **A table by the residue.** A table indexed by x mod 2^b in two's complement factors through π_w for w ≥ b. It is not built.
- **Operations that commute with T** ([vertical_time_compression.md](vertical_time_compression.md)), now on ℤ₂^n as on ℤ^n. `test/record_boundary_test` proves that constants and lattice moves in 2^{3L}ℤ^n pass through T, and that negation and doubling do not. The general question is open.
- **The fingerprint's counts.** **Proved** since: `test/record_boundary_test` at 24b2785 (Doug's posits, above). The fingerprint per band, not only the total heap, is open.
- **The knf's agreement as a test** (Doug's posits, above). The knf's identity by spatial null is built and run (`knf_identity`, e4eae72). The pairwise test, one body's departure curve against another's, is not built.
- **The two nulls' gap.** Whether 1 − (inside + between) measures shared membership at scale b (Anchor_sift's reading) is not proved.
- **`record_order_test`** ("The ordered machine"). **Proved** since: 17 checks, 0 failed.
- **Ω for R*.** The loop machine's Ω is not built.
- **The last cell behind the start** ("π turning at the boundary"). How many of the 100 resolutions end at −jα is not counted.
- **The arc's momentum as checks** ("The arc", posits 7 to 9). **Proved** since: `pi_tower`, 17 checks, 0 failed, at 7ed7fc6.
- **The residue as a check** ("The arc", posit 14). For each floor with q_j ≤ 364,913, the integer turn's carries equal the permutation's wraps at every step n < q_j (q·c_n + k_{n+1} − k_n = p), giving the in-cell offset exactly as n·δ. **Proved** since: `pi_tower`, 23 checks, 0 failed, c26b6a7 (check 11, floors to 2^21).
- **Any 2^n as a request argument** ("The arc", posit 13). **Proved** since: `pi_tower`, 23 checks, 0 failed, c26b6a7.
- **Whether π obeys Lévy's constant** ("The golden helix"). π's mean pitch over 65 certified floors is 1.166, against Lévy's 1.187 for almost every real.
- **Redundancy.** T is n-to-n and every crystal is legal (the written boundary, proved). A corrupted crystal is another crystal, and T⁻¹ returns other samples with no sign of it: T holds no error correction. A redundant residue system would carry the crystal mod more odd moduli than its range needs. A corrupted residue would then decode outside the range and be caught, and with enough moduli corrected. It would be the classical analog, on this boundary, of the error-correcting codes of holography. Not built.

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
- C. H. Bennett, "Logical reversibility of computation", IBM J. Res. Dev. 17, 1973.
- G. J. Chaitin, "Algorithmic Information Theory", Cambridge, 1987 (the incompleteness theorem for Ω's bits).
- J. H. Lambert, "Mémoire sur quelques propriétés remarquables des quantités transcendantes circulaires et logarithmiques", Mém. Acad. Sci. Berlin 17, 1761 (published 1768).
- H. Weyl, "Über die Gleichverteilung von Zahlen mod. Eins", Math. Ann. 77, 1916.
- V. T. Sós, "On the distribution mod 1 of the sequence nα", Ann. Univ. Sci. Budapest. Eötvös Sect. Math. 1, 1958.
- T. van Ravenstein, "The three gap theorem (Steinhaus conjecture)", J. Austral. Math. Soc. A 45, 1988.
- J. Machin's formula, in W. Jones, "Synopsis Palmariorum Matheseos", London, 1706.
- A. Ya. Khinchin, "Continued Fractions", University of Chicago Press, 1964 (best approximations are convergents).
- G. Rauzy, "Échanges d'intervalles et transformations induites", Acta Arith. 34, 1979.
- N. B. Slater, "The distribution of the integers N for which {θN} < φ", Proc. Cambridge Philos. Soc. 46, 1950.
- N. B. Slater, "Gaps and steps for the sequence nθ mod 1", Proc. Cambridge Philos. Soc. 63, 1967, 1115–1123.
- M. Kac, "On the notion of recurrence in discrete stochastic processes", Bull. Amer. Math. Soc. 53, 1947.
- F. Lindemann, "Über die Zahl π", Math. Ann. 20, 1882.
- A. Hurwitz, "Ueber die angenäherte Darstellung der Irrationalzahlen durch rationale Brüche", Math. Ann. 39, 1891.
- P. Lévy, "Sur le développement en fraction continue d'un nombre choisi au hasard", Compositio Math. 3, 1936.
- M. A. Lancret, "Mémoire sur les courbes à double courbure", Mémoires présentés à l'Institut 1, 1806.
- A. N. Kolmogorov, "Three approaches to the quantitative definition of information", Problems Inform. Transmission 1, 1965.
- P. Walters, "An Introduction to Ergodic Theory", Springer, 1982 (the unique ergodicity of an irrational rotation).
- R. L. Goodstein, "On the restricted ordinal theorem", J. Symbolic Logic 9, 1944.
- L. Kirby and J. Paris, "Accessible independence results for Peano arithmetic", Bull. London Math. Soc. 14, 1982.
- G. Gentzen, "Die Widerspruchsfreiheit der reinen Zahlentheorie", Math. Ann. 112, 1936.
- A. Almheiri, X. Dong and D. Harlow, "Bulk locality and quantum error correction in AdS/CFT", JHEP 04, 2015, 163.
- F. Pastawski, B. Yoshida, D. Harlow and J. Preskill, "Holographic quantum error-correcting codes: toy models for the bulk/boundary correspondence", JHEP 06, 2015, 149.
- R. D. Sorkin, "Quantum mechanics as quantum measure theory", Mod. Phys. Lett. A 9, 1994.
- A. C. A. Hope, "A simplified Monte Carlo significance test procedure", J. Royal Stat. Soc. B 30, 1968.
- L. Borsten and H. Kim, "Limits to Computational Acceleration Imposed by Quantum Field Theory and Quantum Gravity", arXiv:2604.00182, 2026 (the abstract page read, 24 September 2026).
- S. Aaronson, "On black holes, holography, the Quantum Extended Church-Turing Thesis, fully homomorphic encryption, and brain uploading", Shtetl-Optimized, 27 July 2022, scottaaronson.blog/?p=6599 (the post read, 24 September 2026).
