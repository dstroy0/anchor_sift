# The two crystals: the record machine over the 2-adic integers

**Purpose:** the 2-adic structure of the record machine: the wrap as a projection, the operations that commute with every projection and the test that proves it, the exact quotient by an odd divisor as a 2-adic product, the lifting on the 2-adic integers and the bits it reads, the two limits of the finite windows and the solenoid between them, what passes to a limit and what does not, and Doug's posits, each bounded.

**Scope:** the record machine (M10 and A13 in [engine_table.md](engine_table.md)) and the 5/3 lifting T as record floors ([vertical_time_compression.md](vertical_time_compression.md)). The shape is Doug's (24 September): two crystals, the finite towers and their limit, with an infinite delta between them.

**Labels.**

- **Proved:** a named test checked it on the machine.
- **Derived:** argued here from the engine's source or by elementary algebra. Not run on the machine.
- **Open:** not settled.

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

**Proved** (`test/engine/record_coherence_test`, 9 checks, 0 failed, cell_tracking main 46b8018).

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

- **The 2-adic floor shift.** For x ∈ ℤ₂ and k ≥ 0, write x = r + 2^k y with r ∈ [0, 2^k), x's residue. Then ⌊x / 2^k⌋ = y, the digits moved down k places. On ℤ it is the floor toward −∞, the record floor of [vertical_time_compression.md](vertical_time_compression.md). On ℤ₂ it is continuous: its bits 0 to w − 1 read x's bits k to w + k − 1.
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
- **The inverse reads fewer.** One inverse level: an even x_{2i} = s_i − ⌊(d_{i−1} + d_i + 2) / 4⌋ reads the low to w bits and the highs to w + 2; an odd x_{2j+1} = d_j + ⌊(x_{2j} + x_{2j+2}) / 2⌋ reads the lows to w + 1 and the highs to w + 3. By induction down the levels, the samples' w bits read the level-ℓ highs to at most w + ℓ + 2 bits and the level-L lows to w + L. T⁻¹ reads the crystal to at most w + L + 2 bits: |T⁻¹(c) − T⁻¹(c′)|₂ ≤ 2^{L+2} |c − c′|₂. Whether this bound is exact is open.
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

## Open

- **The anchors** (above).
- **The inverse's count.** Whether T⁻¹'s bound of w + L + 2 bits is exact, and both counts in D axes.
- **The precision count as a test.** Two lines equal in their w + 3L − 1 low bits whose level-L lows differ in bit w − 1, on the machine.
- **A table by the residue.** A table indexed by x mod 2^b in two's complement factors through π_w for w ≥ b. It is not built.
- **Operations that commute with T** ([vertical_time_compression.md](vertical_time_compression.md)), now on ℤ₂^n as on ℤ^n.

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
