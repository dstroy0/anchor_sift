# Records

**Purpose:** The commit and pull request texts written for the engine, dated, as they were written, so the reasons for each change travel with the workbook.
**Scope:** 24 and 25 September: commits to dstroy0/cell_tracking main, each with its hash and its time (UTC−4), and the three pull requests carried into dstroy0/anchor_sift with their commits. A commit's subject is its heading and its message follows. A pull request's own headings sit one level under its record. The other commits of those days keep their messages in the repository's history. The cell program's texts are in the cell workbook's records.md.

## 24 September

### 15:50, anchor_sift #6 (4c42d0e): record machine: a quotient by a constant is narrower; theory: heap, ring, lens

The pull request's text:

This PR follows #5. It brings the record machine's width fix and the theorist's heap/ring/lens theory from dstroy0/cell_tracking main (a5ec78f and 79c259f) into anchor_sift.

#### Engine

- **keymath.** A `QUOTIENT` or `EXACT_QUOTIENT` whose divisor is a `CONSTANT` c now drops ⌊log₂ c⌋ bits from its numerator's width, never below 1. `QUOTIENT` rounds toward zero, so |q| ≤ |v|/c < 2^(L − ⌊log₂ c⌋). `EXACT_QUOTIENT` does not round.
- **cycle.cu.** The device's exact quotient used to truncate its numerator to the result's limbs before the multiply-back check.
  - That was harmless while the two widths were always equal.
  - With a narrower result and an odd constant divisor, it would refuse a correct division.
  - It now works at the numerator's width, checks q·d against the whole numerator, refuses a quotient that outgrows its register, and keeps only the register's limbs.
  - The host port already divided at full precision.

#### Tests, run in this tree

| test | result |
|---|---|
| `test/engine/record_divide_test` | 19 checks, 0 failed (4 new) |
| `test/engine/record_bitwise_test` | 24 checks, 0 failed |
| `test/engine/record_table_test` | 15 checks, 0 failed |
| `test/engine/record_guide_test` | 11 checks, 0 failed |

The new divide checks:
- 40-bit factors times 3, 12 and 2^32 + 7 divide back exactly. The last case is a 3-limb numerator narrowed to a 2-limb quotient.
- A 64-bit value divided by 2^32 + 7 equals the library's quotient, in 32 bits.
- The widths are exactly the rule's.

#### Measured in a scratch run (not yet a committed test)

The 5/3 lift of 64 samples through 6 levels and back, as one record program. On 4,096 lanes the round trip is exact and the device equals the host word for word.

| | before | quotient narrowed | narrowed + mirror wraps |
|---|---|---|---|
| ring at the output | 5,059 bits | 3,586 | 1,088 |
| register file | 168 limbs | 130 | 84 |
| 128 samples × 7 levels | refused | refused | loads (164 limbs) |

With the mirror wraps, the ring is widest at the crystal and nearly symmetric around it.

#### Theory (the theorist, biohub-cell-tracking-13)

`vertical_time_compression.md` gains:
- the replica;
- steps and their reduction;
- the record's length;
- the lifting as record floors;
- the neighbor gather;
- the two boundaries;
- the heap and the ring;
- the lens.

`engine_table.md` A13 is updated to match, including a reworded table bullet: a TABLE step indexes by the magnitude.

Where the two trees had diverged, the conflicts were resolved by hand, keeping this tree's wording and its `test/engine/` and `src/engine/` paths.

The commit's text:

```text
Carried from dstroy0/cell_tracking main (a5ec78f, 79c259f) into this
tree's layout. Conflicts in engine_table.md and its chapter were resolved
by hand, keeping this tree's wording and its test/engine/ and src/engine/
paths.

keymath: a QUOTIENT or EXACT_QUOTIENT whose divisor is a CONSTANT c takes
floor(log2 c) bits off its numerator's width.

cycle.cu: the exact quotient works at its numerator's width, checks q . d
against the whole numerator, refuses a quotient past its register, and
keeps the register's limbs. Before, a narrower result with an odd
constant divisor would have refused a correct division.

test/engine/record_divide_test: 19 checks, 0 failed (4 new). Bitwise
24/0, table 15/0 and guide 11/0 still pass in this tree.

Theory (the theorist): vertical_time_compression.md gains the replica,
the steps and their reduction, the record's length, the lifting as record
floors, the neighbor gather, the two boundaries, the heap and the ring,
and the lens; engine_table.md A13 is updated to match.
```

### 16:37, de5bdff: test: the crystal as a boundary, and the odd crystals orthogonal to Z_2

```text
record_boundary_test (new, 41 checks, 0 failed). A 5/3 tower of four
levels over 64 samples as record floors, measured at its crystal:

- written onto the boundary and read back: 16384 of 16384 arbitrary
  crystals return exactly through T^-1 then T;
- precision: a flip of input bit b moves the crystal only at bit b - 12
  and above, and for b >= 12 by exactly 2^b M e_i (3918 of 3918). The
  reach per band is 12 at the level-4 lows and 10, 7, 4, 1 at the highs
  of levels 4 to 1 (3l and 3l - 2). T^-1 reaches exactly L + 2 = 6;
- through T: a constant lands on the crystal's lows alone, 2^12 z lands
  as M z, on every pair; negation and doubling pass on none;
- floors: the heap mirrors exactly at every floor; the ring is
  ring_0 + 6(n - n / 2^l), 1536 to 1896 at the crystal, and its mirror
  one bit wider per wrapped low; the pinch is ramp 9.61, +-8 3.82,
  +-1024 1.76, noise 1.00;
- the top projection x / 2^k: nested quotients commute with it, it
  never reverses a comparison (the 8-bit wrap reverses 97966 of
  196608), and a sum through it is off by at most one;
- Haar measure counted: on a 4-sample tower every input quantum at
  level w + 3 runs, and T and T^-1 send exactly 4096 onto every output
  quantum at level w (8 of 8 runs);
- volume: det M = det M^-1 = 1 exactly, by primes past Hadamard's
  bound, and M M^-1 = I.

record_coherence_test (14 checks, 0 failed, 5 new): ring programs
commute with the remainder by 3^5, 3^10, 5^4 and 7^3 (262144 of 262144
three ways), the machine joins each odd window with the 8-bit 2-adic
one into the exact run modulo 2^8 p^v (262144 of 262144), and an xor
breaks modulo 3 (827 of 4096).
```

### 16:38, 9df40f9: theory: the two crystals, the record machine over the 2-adic integers

```text
two_crystals.md (the theorist): the wrap as the projection onto
Z / 2^w; the coherence theorem and its proof on the machine (393216 of
393216); what does not factor through the projection, with a witness
pair for each operation; the exact quotient by an odd divisor as the
product by c^-1 in Z_2 (73728 of 73728); the lifting on Z_2 and the
bits each output reads; the two crystals (Z as sets, the Pruefer
group, Z_2 as the inverse limit), the infinite delta and the solenoid
(R x Z_2) / Z between them; what passes to a limit and what does not;
Doug's posits, each bounded.

README gains its row, engine_table.md A13 its pointer, and the TeX is
regenerated.
```

### 16:49, anchor_sift #7 (d45794d): test: the crystal as a boundary, the two crystals and the odd crystals

The pull request's text:

Carried from dstroy0/cell_tracking main (1e39052, 46b8018, de5bdff, 9df40f9).

#### Tests (new, both run in this tree)

**`test/engine/record_coherence_test`: 14 checks, 0 failed**

- **The 2-adic crystal.** Sum, difference, product, xor and and commute with every wrap: 393,216 of 393,216 lane-widths agree three ways. A quotient and a comparison break the agreement.
- **Odd divisors.** An exact quotient by an odd c is the product by c⁻¹ mod 2^w: 73,728 of 73,728.
- **The odd crystals.** Ring programs commute with the remainder by 3⁵, 3¹⁰, 5⁴ and 7³: 262,144 of 262,144. The machine joins each odd window with the 8-bit 2-adic one by CRT into the exact run mod 2⁸·p^v: 262,144 of 262,144. An xor breaks modulo 3.

**`test/engine/record_boundary_test`: 41 checks, 0 failed.** A 5/3 tower of 4 levels over 64 samples, measured at its crystal:

- **Written and read back.** T·T⁻¹ = id on 16,384 of 16,384 arbitrary crystals.
- **Precision.**
  - The reach per band is 12 at the level-4 lows and 10, 7, 4, 1 at the highs; T⁻¹ reaches 6.
  - A flip at bit b ≥ 12 moves the crystal by exactly 2^b·M·e_i.
- **What passes through T.**
  - A constant on every sample lands on the lows alone.
  - 2¹²·z lands as M·z.
  - Negation and doubling do not pass.
- **Floors.**
  - The heap mirrors exactly at every floor.
  - The ring is ring₀ + 6(n − n/2^l), with its mirror one bit wider per wrapped low.
  - The pinch is 9.61 for a ramp, 3.82 at ±8, 1.76 at ±1024 and 1.00 for noise.
- **The top projection x/2^k.** It commutes with the quotient, never reverses a comparison, and a sum through it is off by at most one.
- **Haar measure.** Counted exhaustively on a 4-sample tower: every output quantum receives exactly 4,096 input quanta, 8 of 8 runs.
- **Volume.** det M = det M⁻¹ = 1 exactly, and M·M⁻¹ = I.

#### Theory

`theory_bucket/cell_tracking/two_crystals.md` and its chapter, the README row, and the A13 pointer, written by the theorist. Its citations point to `test/engine/`.

The commit's text:

```text
Carried from dstroy0/cell_tracking main (1e39052, 46b8018, de5bdff,
9df40f9) into this tree's layout: the tests under test/engine/ with
TOP two levels up and src/engine/, and the theory under
theory_bucket/cell_tracking/ with test/engine/ in its citations.

test/engine/record_coherence_test (new, 14 checks, 0 failed):
- sum, difference, product, xor and and commute with every wrap:
  393216 of 393216 lane-widths agree three ways;
- a quotient and a comparison break the agreement;
- an exact quotient by an odd c is the product by c^-1 modulo 2^w
  (73728 of 73728);
- ring programs commute with the remainder by 3^5, 3^10, 5^4 and 7^3
  (262144 of 262144), and the machine joins each odd window with the
  8-bit 2-adic one into the exact run modulo 2^8 p^v (262144 of 262144);
- an xor breaks modulo 3.

test/engine/record_boundary_test (new, 41 checks, 0 failed): a 5/3
tower of four levels over 64 samples, measured at its crystal.
- Written onto the boundary and read back exactly (16384 of 16384).
- The precision reach per band, 12 at the lows and 10, 7, 4, 1 at the
  highs, and 6 for T^-1. A flip at bit 12 or above moves the crystal by
  exactly 2^b M e_i.
- A constant lands on the lows alone, and 2^12 z lands as M z.
  Negation and doubling do not pass through T.
- The heap mirrors exactly at every floor, and the ring is
  ring_0 + 6(n - n / 2^l).
- The top projection keeps order and commutes with the quotient.
- Haar measure is counted exhaustively on a 4-sample tower.
- det M = det M^-1 = 1 exactly.

Both run here: boundary 41/0, coherence 14/0.

Theory (the theorist): two_crystals.md and its chapter, the README row
and the A13 pointer in engine_table.md.
```

### 16:56, 24b2785: test: the crystal's identity by null permutation, and one bit changes it

```text
record_boundary_test (48 checks, 0 failed, 7 new).

The identity of a lane's structure, taken with T and null permutations
of its own samples (Doug: "an identity of T using T:null permutation
of T"). Each lane is drawn with 8 keyed shuffles. A shuffle keeps every
value, and T keeps the count, so the crystal's heap against the draws'
reads the arrangement alone.

- Identified of 256, with the crystal heap against the draws' mean:
  ramp 256 (0.13), ramp +-8 256 (0.33), ramp +-1024 254 (0.73),
  noise 21 (1.00).
- The null bounds noise at 256/9 plus five deviations. Each structured
  class stands past it. A structured lane is not promised to be
  identified: two shallow ramps under +-1024 were not.
- One to one: 8192 of 8192 draws change the crystal exactly when they
  move a value.
- Every single flipped bit changes the image, 8192 of 8192 through T
  and through T^-1.
```

### 17:28, e4eae72: sim: the knf's identity by spatial null permutation, and its departure curve

```text
knf_identity (23 checks, 0 failed), on the nbody lattice's law in a 64^3
cube over 177 frames, so the entropy history has 16 whole windows.

The data is mutated over xyz (Doug: "mutate the data over the spatial
coordinate set xyz and get its entire null permutation id"). A spatial
permutation keeps every section and the cloud. E, every voxel's centred
window densities against its z, y, x neighbours on the torus, reads the
arrangement alone.

- The 48 exact motions (theta = k pi/2 and the reflections, each with a
  keyed torus translation): the history of the moved data is the moved
  history on 48 of 48, with E and the cloud unchanged. Any other angle
  rounds on the integer lattice.
- The lattice's E is 44.6 times the free null's mean, past all 19 draws.
- The departure curve over tiles 1 to 64, as a share of the free null's:
  inside the tiles 0, .126, .349, .647, .896, .974, 1; whole tiles moved
  1.002, .492, .241, .106, .047, .008, 0. They cross between 2 and 4.
  Their sum dips to .59 at 4: the share both nulls keep, where a shuffled
  pair still shares a body.
- Exact at every tile size: the whole is its tiles plus its seams, and a
  rigid move keeps every tile's inside.
- Each body's box (zmin..zmax, ymin..ymax, xmin..xmax) has its own curve.
- With no bodies, E is not identified (-10.7 times the null's mean).
- Alike voxels, 64 volumes: 4 identified, within 5 sigma of 1/20.
- One bit: the host's walk equals the engine's history at every voxel,
  and of 8192 flipped bits 1500 leave it unchanged, each where the window
  rule says: inside a window, with bit(f-1) != bit(f+1).
```

### 17:32, ad5d085: theory: the knf's identity by spatial null permutation, and the fingerprint proved

```text
two_crystals.md and its chapter, engine_table.md A13, the README row
and the vertical time compression Open item, written by the theorist.

- The fingerprint by null permutation is Proved at 24b2785: the rates,
  and the crystal as a one-to-one ID.
- New section: the knf's identity by spatial null permutation
  (knf_identity, e4eae72).
  - Proved: the one-bit window rule, the 48 exact motions, and tiles
    plus seams.
  - Proved: the alike-voxel control is within the 1/(d+1) bound.
  - Measured: the departure curve and the bodies' curves.
- Doug's posits: the knf, the departure curve, and the two nulls
  (inverse, crossing between 2 and 4, not 1:1). The gap read as shared
  membership is not proved.
- Open: the pairwise departure-curve test between sections.
```

### 17:55, anchor_sift #8 (82db58c): sim: the knf's identity by spatial null permutation; test: the crystal's identity

The pull request's text:

From cell_tracking main 24b2785 (test), e4eae72 (sim) and ad5d085 (theory), placed at `test/engine`, `src/engine` and `theory_bucket/cell_tracking`.

#### Test: the crystal's identity

`test/engine/record_boundary_test`: 48 checks, 0 failed. It tests T against 8 null shuffles a lane. It identifies each structured class past the null's 1/(d + 1) bound, and noise within it. The crystal is a one-to-one ID: a draw changes it exactly when it moves a value, and every single flipped bit changes the image.

#### Sim: the knf's identity by spatial null permutation

`bash src/engine/sims/run.sh knf_identity`: 23 checks, 0 failed.

- **Setup.** The nbody lattice's law in a 64³ cube over 177 frames, which gives 16 whole entropy windows.
- **The statistic.** A spatial permutation keeps every section and the cloud. E reads the arrangement alone: each voxel's centered window densities against its torus neighbors.
- **One bit.** Of 8,192 flipped bits, 1,500 leave the knf unchanged, each where the window rule says. The knf is many-to-one.
- **Motions.** The 48 exact cube motions carry the knf and keep E and the cloud.
- **Identified.** The lattice's E is 44.6 times the free null's mean, past all 19 draws.
- **Departure curves.** The inside-tile and between-tile curves cross between tiles of 2 and 4 and sum to 0.590 at 4. The whole is its tiles plus its seams at every tile size.
- **Bodies.** Each body's box has its own curve.
- **Controls.** The empty scene is not identified. Alike-voxel controls: 4 of 64 identified, within 5σ of 1/20.

#### Build and docs

`run.sh` builds `knf_identity` with `entropy_history`, and `src/engine/README.md` lists it.

#### Theory

The theory updates `two_crystals`, the engine table, the README and vertical time compression. Every test citation now points to `test/engine/`.

#### Run here

Both runs are on the `cell_tracking` branch of this repo:

- `record_boundary_test`: 48 checks, 0 failed.
- `knf_identity`: 23 checks, 0 failed.

The commit's text:

```text
From cell_tracking main 24b2785, e4eae72 and ad5d085, placed at
test/engine, src/engine and theory_bucket/cell_tracking.

- test/engine/record_boundary_test (48 checks, 0 failed): the crystal's
  identity against 8 null shuffles a lane, and every single flipped bit
  changes the image.
- src/engine/sims/knf_identity (23 checks, 0 failed): the knf of the
  nbody lattice's law (64^3, 177 frames) against spatial null
  permutations.
  - One bit: 1500 of 8192 flips leave the knf unchanged, each where the
    window rule says. The knf is many-to-one.
  - The 48 exact cube motions carry the knf and keep E and the cloud.
  - The lattice's E is 44.6 times the free null's mean.
  - The inside and between departure curves cross between tiles of 2
    and 4, and sum to 0.590 at 4.
  - Each body's box has its own curve. The empty scene is not
    identified. Alike voxels: 4 of 64, within 5 sigma of 1/20.
- run.sh builds knf_identity with entropy_history; the README lists it.
- Theory: two_crystals, the engine table, the README and vertical time
  compression, with every test path at test/engine.
```

### 18:02, 9101bbb: theory: knf_identity in the engine table; theory_tex skips a book's built PDF

```text
- engine_table.md: M8 carries the knf's identity by spatial null
  permutation and the pairwise test as next; M19 is ten sims, with
  knf_identity's run (23 checks, 0 failed, a tessera job); A13's
  two-crystals bullet splits the identity, built, from the pairwise
  agreement, open.
- theory_tex.py: a PDF with a .tex of its own stem beside it is the
  book's build output (main.pdf from main.tex), not a chapter. It had
  generated chapter_main.tex from main.pdf; the stale sweep removed it.
  The three hand-made thought_experiments PDFs stay chapters.
- .gitignore: the LaTeX build outputs (aux, toc, synctex, out, fls,
  fdb_latexmk) and each book's main.pdf.
- two_crystals.md: American spelling, and one phrase reworded.
- The workbook's two chapters regenerated.
```

### 18:19, b2d1f44: test: the loop rule's orders both ways, and the omega stage on a finite window

```text
record_order_test (17 checks, 0 failed).

- The orders both ways. G is four shears over 32-bit words (a by b*d,
  b by the xor of a + n, d by a and b, the counter n by one), and G^-1
  takes them off in reverse. One program runs the orders 0 -> 256 ->
  -256 -> 0, 1,024 floors and 12,293 steps in a 10-limb file, every floor
  tapped. On 512 of 512 lanes every visit to order k holds the CPU's
  G^k(x), the counter reads k, and the run returns to x exactly. On the
  CPU, G carries each order to the next from -256 to 256.
- The omega stage. A floor is a table permutation of the 16-bit states,
  pi^-1 runs the negative orders, a 1-bit table reads a halt set, and an
  or beside the floor gathers each bit's lim sup. On 1,024 lanes every
  orbit returns to its start. The 528 whose cycle fits the 2,048-floor
  run are decided: +omega is the or over the cycle, the flag is exact,
  and -omega equals +omega. 329 halt and 199 run forever. Of the 496
  open, 391 show a halt and 105 halt past the run.

theory: "The ordered machine" in two_crystals, by the theorist: Doug's
posits verbatim, the loop rule and its orders, the theorems cited, and
the test as proved.
```

### 19:11, c633988: sim: Goodstein's sequences held exactly, and omega^omega^omega falls a million times

```text
goodstein (7 checks, 0 failed), a host sim in exact integers. A value is
its hereditary tree and never expanded. b^L - 1 at a large L is one run
of b - 1 over the exponents 0 .. L - 1 in the base it was made at. With
b read as omega, the tree is an ordinal below epsilon_0.

- The bump keeps the tree: 80,256 of 80,256 values below 20,000, at
  bases 2 to 6.
- 2^^k in hereditary base 2 is omega^^k for k = 1 to 4, and the towers
  climb.
- Starts 1, 2 and 3 reach 0 in 1, 3 and 5 steps, and every value equals
  the numeric sequence's.
- Starts 4, 16 and 65536 (omega^omega, omega^omega^omega, omega^^4) each
  run 1,000,000 steps to base 1,000,002. The ordinal falls on every step.
  Every value that fits 64 bits equals the numeric sequence's (all
  1,000,000 steps for 4). At 65536 the top run holds 7,625,597,484,984
  terms as one block.
```

### 19:25, 0b10199: sim: pi turning at the boundary, and the tower it builds

```text
pi_tower (8 checks, 0 failed), a host sim in exact integers. The
boundary is the circle, and the turn is the rotation by pi - 3. Its
returns near the start are its floors, pi's partial quotients. At
resolution 2^k, the step that fills every cell is read from the floors,
without walking the turn.

- pi is bracketed by Machin's formula at 416 bits (116 terms), and
  floor(pi 2^384) is one integer at both ends. After the point it
  begins 0x243F6A8885A308D3.
- The bracket certifies 109 floors: [3; 7, 15, 1, 292, 1, 1, 1, 2, 1,
  3, 1, 14, 2, 1, 1, 2, 2, 2, 2, 1, 84, ...], the published start.
- The turn's closest returns are the floors. There are 66 record
  returns up to 2^112 steps, and each equals the convergent
  denominator q_j, in order.
- The fill step is the least count whose points touch every cell. The
  three gap theorem tests each count, with Euclid's descent for each
  gap's first hit, and doubling and halving find the least.
- The integer turn lands in the real turn's cell on every step
  searched, at every resolution. This is itself a first hit.
- From the floors, the step and the last cell equal a walk of every
  step at 2^1 to 2^24 cells. At 2^1 to 2^100 cells, the last cell's
  first touch is the fill step. 2^100 cells fill at step
  1593334768903120834487234062301 (1.593e30), which is q_57 - 1.
- A large floor is a long drift. Inside 292 the fill takes up to 71.9
  times the cells (2^8), inside 84 up to 20.9 (2^34), and inside 99 up
  to 23.8 (2^61). Elsewhere it takes 1 to 5.
```

### 19:25, 415f141: theory: Goodstein's omega-towers, and the wire and the witness

```text
By the theorist.

- two_crystals.md: "Goodstein: omega-towers held as finite objects",
  after "The ordered machine". It covers the objects, the standard
  descent, the theorems (Goodstein, Kirby-Paris, Gentzen), and the sim
  as proved (c633988). The 3^27 - 3 term run is derived, and the common
  tail is marked as an observation. Also Doug's bulk-to-boundary posit,
  contrasted with the holographic codes' redundancy.
- obsignatio_seal.md: "Doug's posits: the wire and the witness", before
  "The universal root". It holds the seal quotes verbatim and each
  bound checked: search repair, the CRC erasure and Reiger bounds,
  classical binding, exact amplitudes, the witness before sealing. The
  spine and "Do something n" are Open.
- The two chapters regenerated.
```

### 19:26, 3ff5fa3: theory: goodstein and pi_tower in the engine table

```text
M19 is now twelve sims. goodstein (7 checks, 0 failed, c633988) and
pi_tower (8 checks, 0 failed, 0b10199) run on the host. Each has what it
proves and what it measures. The chapter is regenerated.
```

### 19:28, 19fe58c: theory: pi turning at the boundary, the floors of a rotation

```text
By the theorist. The new section in two_crystals.md comes after
Goodstein.

- Doug's two quotes, verbatim as a posit. The one on tower recursion is
  recorded as the idea's history, apart from the 5/3 tower.
- Derived: it never closes (Lambert); it is dense and equidistributed
  (Weyl); the orbit is countable with measure 0, so N cells fill at a
  finite step; the record returns are the q_j (Khinchin); the drift
  runs over the intermediate returns; the descent is one Euclid step a
  level.
- The return map is cited as theory and not checked by the sim
  (Rauzy 1979).
- Proved: pi_tower's 8 checks (0b10199). Measured: the fill ratios and
  steps, and the last cell at -j alpha as an observation. The share is
  Open.
- The chapter is regenerated.
```

### 19:39, 7abe65d: sim: pi_tower's arc, the helix over our disk balanced by its torsion

```text
pi_tower now has 13 checks, 0 failed (build/20260924_193716_sim_pi_tower).
Doug: pi on its own disc, balanced by its torsion, is a plane offset in
degrees from ours, and this is the arc it follows. Rolled onto the
cylinder over our disk, the turn is the helix of radius 1/(2 pi) that
rises 1/pi a turn, piercing the disk at the marks {n pi}.

- In Q(pi), where pi is a free variable because it is transcendental,
  the Frenet frame from the helix's derivatives at the four quarter
  turns gives curvature 2 pi^3/(pi^2+1) and torsion 2 pi^2/(pi^2+1).
  tau/kappa = 1/pi, the tangent of the tilt against our disk (Lancret).
  The Darboux vector tau T + kappa B lies along our disk's axis.
- From the bracket, each value agreeing at both ends to 12 places:
  curvature 5.705134342735, torsion 1.816000663299, and a tilt of
  17.656787151412 degrees against our disk (72.343212848587 against
  the axis).
- The bracket now hands back pi 2^416 between its two ends, and
  arctan(1/pi) is taken on it with a bounded error.
- The walk also measures the re-etch, the step by which every cell is
  etched a second time. At 2^24, fill is at 25,510,581 and the re-etch
  by 51,021,159. Inside the 292 floor it follows almost at once: at
  2^8, 18,416 and 18,747.
```

### 19:48, 7ed7fc6: sim: pi_tower's balance on the arc and its loss at the boundary

```text
pi_tower now has 17 checks, 0 failed (build/20260924_194636_sim_pi_tower).
Doug: "present but balanced"; "the UNBALANCING happens at the
boundary"; "one force must win because we cannot divide by zero".

- On the helix the pull points at our axis. In Q(pi), at all four
  quarter turns, the torque about the axis is zero and
  L_z^2 = 1/(4(pi^2+1)) at unit speed. From the bracket,
  L_z = 0.151657235526.
- The square billiard from the corner at slope pi, unfolded. The
  segment in lattice cell (i, j) carries
  L = (-1)^(i+j) ((j + 1/2) - pi (i + 1/2)) about the centre. A zero L
  would need pi = (2j+1)/(2i+1), and a corner would need pi (i+1) whole.
  Walked over 2^24 columns from the integer turn's carries, with every
  floor certain:
  - 69,484,394 segments; 16,777,216 side-wall hits and 52,707,178
    floor-wall hits (floor(pi 2^24)); 0 corners;
  - no segment's L is zero;
  - the record near-corners are exactly 1, 7, 106, 113, ...,
    1725033, the q_j.
  Measured: the lead changes hands 35,929,962 times and is never held
  longer than 2 segments; one side leads on 34,742,196 of 69,484,394.
  The nearest tie is |L| = 1.910e-8 in cell (862516, 2709675), where
  pi stands nearest 5419351/1725033, a convergent.
```

### 19:53, b0b6da6: sim: pi_tower's second run, cell 0 again and then the first run's last cell

```text
pi_tower now has 18 checks, 0 failed. Doug asked: after pi etches the
boundary, how long until it etches cell 0; then how long until that run
etches the first run's closing cell; and are the two the same period?

At every resolution 2^1 to 2^100, both steps are read from the floors.
Each is one first hit from the step before it: H is the first step
after the fill T with {n alpha} < 1/N, and C is the first step after H
in the fill's last cell. The integer turn's certainty now runs to C. At
2^1 to 2^24 both equal a walk of every step.

Measured:
- H lands on a record return or a sum of them, e.g. q_12 at 2^24,
  q_20 at 2^32 and q_34 at 2^64.
- The fill is short of the next record return by 1 to 4 steps at 64
  resolutions and by up to 9 at 77. It is short by 22,867 inside the
  84 floor.
- The second run, C - H, has the first run's period at 13 of 100
  resolutions. It is shorter at 86 and longer at 1 (2^6, by 7). Each
  shortfall is a floor combination: a record return at 80 (a floor q_j
  at 52), and c q_j at the other 6.
```

### 19:58, cc5eb6b: theory: the arc, its balance and the boundary, and the second run

```text
By the theorist, in "pi turning at the boundary" of two_crystals.md, with
M19 of the engine table.

- The arc: Doug's posits 1 to 9 verbatim. The helix over our disk:
  kappa checked as kappa^2 with no square root formed, tau, tau/kappa =
  1/pi as the tilt, and the Darboux vector along the axis, in Q(pi)
  (Lindemann). The bracket values to 12 places. The re-etch.
- The balance: zero torque about the axis, and L_z. The billiard's L per
  unfolded cell, with no corners, no zero L, and the near-corners at the
  q_j. The lead changes and the nearest tie at a convergent. "One force
  must win" as three ties, each ruled out because pi is irrational.
- Cell 0 again, and the second run: Doug's posits 10 to 14. H and C by
  first hits, proved against the walk. Slater's return times and Kac's
  mean as theory. The wait, the fill's distance from the next record
  return, and the second run's period, measured. The residue reading
  of posit 14 is derived, with the one-per-cell statement's open side
  depending on the residue's sign.
- M19: pi_tower at 17 checks (the arc and balance, 7ed7fc6), then 18
  (the second run, b0b6da6).
- The chapters are regenerated.
```

### 20:16, c26b6a7: sim: pi_tower's residue, its golden helix, and any 2^n as the request

```text
pi_tower now has 23 checks, 0 failed, at 2^1 to 2^100 and at 2^1000.

- The residue (Doug: "if qa is almost a whole number, we can get its
  identity and its null permutation will make it a whole, that is its
  residue"). On every floor with q_j up to 2^21 (j = 0 to 11), pi's
  first q_j steps have the whole parts of the permutation
  n -> n p_j mod q_j, and at step q_j the walk stands delta_j off the
  whole. The identities print as 3/1, 22/7, 333/106, 355/113, ...
  5419351/1725033, each with its signed residue.
- The golden helix (Doug: "their period is a contraction of the golden
  spiral"; "pi DOES ride it"). The residues flip sign every floor,
  q_j >= F_(j+1), and |delta_j| < 1/q_(j+1). The shrink
  |delta_j|/|delta_(j-1)| is above 1/2 exactly where a_(j+1) = 1, and
  each side of 1/phi is decided at both ends of the bracket. Measured
  over 65 shrinks: 45 below the golden 1/phi, 20 above, 28 between 1/2
  and 1. The growth a floor, q_65^(1/65), is 3.210576, against
  phi = 1.618033.
- Any 2^n (Doug: "you can go to 2^n arbitrarily in the tower it is one
  term"). pi_tower [n] or pi_tower [from] [to]; with no argument it
  reads 2^1 to 2^100. The turn's precision is 3n + 64 bits rounded up to
  a word, at least 384. The walks and the billiard read floor(alpha
  2^384) from it. A width too small is refused by name, and
  SIM_EXACT_LIMBS in run.sh sets the width for every object. At 2^1000
  (3072 bits, SIM_EXACT_LIMBS=512) the fill is step 1.288e302, 12.02
  times the cells, on floor 600 (a = 106).
```

### 20:19, 14eabb2: theory: pi's residue, the golden helix, and any 2^n

```text
By the theorist, in "The arc" of two_crystals.md, with M19 of the engine
table.

- (13) and (14) are now Proved by pi_tower c26b6a7 (23 checks, 0
  failed): any 2^n as the request, with the width it needs named, and
  the residue as check 11. The 2^1000 run and the printed identities are
  Measured.
- The golden helix: Doug's posits 15 and 16 verbatim. Derived:
  q_j >= F_(j+1), |delta_j| < 1/q_(j+1), the sign flip each floor, and
  the shrink 1/xi_(j+1) with its band. Also derived, our reading and
  marked as such: the helix on the cylinder, exact in its turning, with
  a pitch that varies. Check 12 is Proved, and the 65 shrinks and the
  growth a floor are Measured. Hurwitz and Levy are cited, and whether
  pi obeys Levy's constant is Open.
- M19: pi_tower takes its resolutions from the request, SIM_EXACT_LIMBS
  sets the width, and the 23-check results are added.
- The chapters are regenerated.
```

### 21:16, e340d08: sim: pi_tower's deepest turns on the engine, by BBP on the record machine

```text
The turn at depth n is alpha's bit n, and the BBP formula reads it where it
stands. Each term is a lane of the record machine: 16^(d - i) mod 8i + j by
base-16 powering, every square taken mod 8i + j, its fraction floored to W
bits. A tail program takes the terms past d, and a pair program adds lanes
mod 2^W in rounds, so a sweep reduces on the engine. keymath sizes every
register, the scheduler lays them with reuse, and tessera admits the job.
The error interval, 4 (N + T) + 1 units, certifies the leading bits.

13. On the engine, pi's first 64 bits are 0x243F6A8885A308D3, and the hex
    digits at Bailey's positions 10^6, 10^6 + 1, 10^7 and 10^8 are his.
14. The engine's cell at the deepest resolution asked for, its low 64 bits,
    is the exact turn's.

A resolution past 2^20, whole or base^exponent, is held as (2, n): its
precision and widths print exact, and the engine sums the depth-n terms
sweep by sweep, printing terms done and the rate. At 2^(2^30) it finishes,
268435441 terms in 10.6 s; at 10^100 it runs 7.3e5 terms a second of
2.5e99. Digits print only once every term is summed.

pi_tower: 41 checks, 0 failed.
```

### 21:27, 8598302: theory: where the two towers stand in the engine, and pi's BBP on the engine

```text
A13 now says it plainly: in the engine T and T^-1 are tower.cu's own
kernels, called by the crystal path and root_universal. As record floors
they exist only in record_bitwise_test and record_boundary_test, no engine
module emits them, and no engine path runs F o T^-1. The record programs
the engine runs today (the cell program's, chaitin_omega's reduct,
pi_tower's BBP terms) use neither tower. The work order gains the two
towers in the engine as item 8.

M19 records pi_tower's BBP digits on the record machine (e340d08, 41
checks): Bailey's positions matched through 10^8, the cell at 2^100 equal
to the exact turn's, 2^(2^30) finished in 10.6 s, and 2^googol measured at
7.3e5 terms a second of 2.5e99, stopped with no digit printed. The ledger
gains 24 September with the same runs.
```

## 25 September

### 01:03, f153047: sim: pi_plane, pi's bits laid out in the plane and read against shuffles

```text
pi's bits after the point, certified by Machin's bracket on the exact
integer (the first 64 are 0x243F6A8885A308D3), laid out as pictures and
read against keyed Fisher-Yates shuffles of the same bits, which keep
the count of ones.

- Every width at once: the longest run of equal bits at every difference,
  on the device, checked by the host.
- Shapes: rows of width 7, 16, 32, 64, 106, 113, 128 and 256, the tower,
  the disc by rows and by rings, the square spiral, the twindragon, the
  integer sphere by latitudes and by meridians, and the golden sphere's
  Fibonacci differences. Each is read for its longest straight line.
- The ones' spread over residues and blocks, and the twindragon by depth
  from its edge.
- The rings mod floor(pi 2^k), drawn as circles and unrolled, each bit
  read against its parent and along every spiral slope, on the bits the
  pictures showed and on pi's next block.
- --cells: the bits under a path drawn over the ring-filled disc.
- --blind N [--blind-from B --balanced 1]: blind pairs, a block of pi
  beside a shuffle of itself, the answer written only to
  blind_answer.txt.
- --funnels N: runs of equal bits traced ring by ring outward, read for
  depth, three bars' fit to one ratio, and parent agreement, on the six
  blind blocks and N fresh ones.

Every layout reads like its shuffles. The lowest, the disc_rings chord
of 26 zeros from bit 519, is 22 of 9,999, about 1 in 10 over the
session's readings. The rings' radial agreement, 20 of 999 on the bits
shown, is chance on the next block. The blind pairs: 6 of 6 in the first
round (1 in 64 by chance), 2 of 5 in the second before it stopped. The
funnel readings are ordinary on the six blind blocks and on ten fresh
ones (376, 201, 639 and 918, 841, 815 of 999 reach pi's).
```

### 02:10, 5362f72: record machine: every register's width read from its linear form

```text
keymath carries every register as a linear form over atoms: integer
coefficients plus a constant. A sum or difference adds its operands'
forms, a product by a constant scales the other's, a constant is its
value, and a wrap that passes its register through keeps that register's
form. Every other register, fields included, is an atom. The width is
the fewer of the operation's own rule and the form's bound,
|c| + sum |c_i| (2^(b_i) - 1). A coefficient past 2^62 makes the
register an atom.

Terms that cancel drop out, so (a - b) + b is a's width, and a Gaussian
floor (a - b, a + b) grows half a bit a floor, as its values do: over
eight floors of 24-bit fields the widths are 25 25 26 26 27 27 28 28,
where the rule before gave 25 to 32. A 5/3 tower's registers at level l
are w + l + 1 bits, lows and highs alike, where a low gained 4 bits a
level before.

The README's width table, and a paragraph on the forms, say the same.
```

### 02:10, 5821459: test: every record test a tessera job, and the Gaussian step's widths

```text
Each record test is one job on the device's tessera daemon, submitted
before its first device work with the bytes it declares, and released at
the end. maint/tessera_build.sh builds the daemon beside the test and
the tessera objects the test links.

record_gaussian_test runs BBP's x16 as eight floors of (a - b, a + b) on
4,096 lanes: floor k is z (1 + i)^k, floors 4 and 8 are -4z and 16z,
each floor's pair shares its parity, and floor k is 24 + ceil(k / 2)
bits, with some lane filling every width. record_boundary_test's forward
ring law is now ring_0 + n + 2(n - n / 2^l), the widths the linear forms
give.

Run one at a time at below-normal priority: gaussian 11, guide 12,
table 16, divide 20, bitwise 25, boundary 49, coherence 15 and order 18
checks, 0 failed.
```

### 02:10, c3ff54e: sim: floor_match, finding x on floor 2 by an and over bit planes

```text
a is one 64^3 camera frame. The engine's tower lifts it, and the
crystal's 16^3 corner, lowered as its own tower, is floor 2: m = n / 64
values, equal to the host's two-level lifting at every coefficient.
Floor 2 is laid once as 16 bit planes. A query x reads no value, only
the and over the planes of each plane where x's bit is 1 and its
complement where it is 0, and a word stops once its mask is empty.

1,024 values on floor 2 and 1,024 not: every match set equals the
host's scan, and the most any query read was 1,340 plane words, against
half of a, 131,072 samples. The lift reads a once to build the index.
11 checks, 0 failed, a tessera job.
```

### 02:10, 5e97dbf: theory: the engine in math, the Gaussian step, and widths by linear forms

```text
The engine table opens with the engine in math, E0 to E15, each part's
algebra stated as the code holds it. A16 is the Gaussian step: BBP's
base as a power of 1 + i, the record floor (a - b, a + b), pi as four
times one step's turn with BBP's logarithms cancelling, and the width
made fluid by keymath's linear forms, built and proved at every floor.

E1's width table, E4 and A13 carry the new widths and the tower's ring,
ring_0 + n + 2n(1 - 2^-l), and E4 gains matching on floor 2
(floor_match). two_crystals and vertical_time_compression keep the old
ring as history. The ledger gains 24 September's Gaussian run and 25
September's: the eight record tests on tessera, and floor_match.
```

### 08:26, 0523a6e: theory: the driver's stages, OrganoidTracker and Hawkins into them, and the residual at any width

The engine's part of the commit's text. The rest is the cell program's, in the cell workbook's records.md.

```text
The engine
table's M2 gains the unit sweep's planes: any declared width, the width
returned, a value past it refused, proved by linearity against the
16-bit path (336 checks, 0 failed). The scale audit and the offers
follow.
```
