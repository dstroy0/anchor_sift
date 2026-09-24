# Vertical time compression: floors stacked into one sweep

**Purpose:** the algebra of the record machine's stacked floors: what a stack is, what it compresses, what it leaves as it is, what bounds its file and its record, how its values and widths fill the floors of the two towers, and what is proved, measured and derived about it.

**Scope:** the record machine (M10 and A13 in [engine_table.md](engine_table.md)): `keymath` imprints a program, `key_schedule` lays it out, `cycle` sweeps it. The shape is Doug's (24 September): a floor, the operations in order above it, the next floor, and so on up, with the top conjunction performing the whole transform.

**Labels.**

- **Proved:** a named test checked it on the machine.
- **Measured:** timed on the machine.
- **Derived:** argued here from the engine's source or by elementary algebra, or computed by the replica. Not run on the machine.
- **Open:** not settled.
- **The replica** is a script that copies keymath's width rules and key_schedule's reuse (first fit, coalesced, a register freed as the step after its last reader begins) and evaluates each program exactly. It reproduces the proved lifting program below: 129 steps and a 12-limb file. Its widths include the constant-divisor narrowing (below: widths across levels).

## The objects

- **Lane.** A lane ℓ reads its atom a_ℓ, the fields of its records.
- **Floor.** A floor S_k is the set of registers live at a cut between two rounds. It is the state one round leaves and the next reads.
- **Round.** A round f_k is a straight-line list of steps. It reads S_{k−1} and leaves S_k. Its steps fill the register file while they run. At the floor, register reuse has freed everything except S_k.
- **Stack.** The stack is F = f_n ∘ … ∘ f_1, imprinted once as one key. The imprint derives every register's width across the whole composition before any lane runs.
- **Sweep.** A sweep applies F to every lane in one launch: R_ℓ = F(a_ℓ).

## The algebra

1. **Composition regroups and keeps its order.**
   - (h ∘ g) ∘ f = h ∘ (g ∘ f), but g ∘ f ≠ f ∘ g in general.
   - A stack can be cut into programs at any floor and the programs chained, and every result stays the same.
   - **Proved** for tables (M10): a table read through a table equals the ops, and the reversed order differs on some lane.
   - **Proved** for floors (below): 700 floors run as one program equal the same floors run as 700 chained programs, record for record, at four lane counts.
2. **The file holds live registers only.**
   - A register is live from the step that writes it to its last reader. With reuse on, the file needs the most limbs live at any one step, plus any gap first fit leaves between registers of different limb counts.
   - The atom is not in the file. A field step copies its field from the record, in device memory, into a register. That register counts against the file only until its last reader. A program that reads many fields, each read late and used at once, runs in a small file: one lifting level over a 4-D cone reads 625 fields in 15 limbs (derived, below).
   - The file's size follows the order of the steps. At a floor it holds that floor's registers. Inside a round it holds the registers of the floor below still to be read, and the round's own registers not yet read for the last time.
   - The step count has no bound of its own. `ENGINE_RECORD_STEPS_MAX` held one sign per step. Since 24 September each sign sits beside its register. The file (`ENGINE_RECORD_LIMBS_MOST`, 256 limbs) is now the only bound on the program.
   - The record's own length is a separate bound (below).
   - **Measured:** 4,204 steps in an 8-limb file (the stack test), and in a 12-limb file with its words carried as 33-bit fields (the chained measure).
3. **Widths are derived, never declared.**
   - Each step's width follows from its operands' widths.
   - A register the imprint can show is never negative carries that fact forward:
     - a field read unsigned, a constant, an absolute value, a gcd, a table entry;
     - a sum, product, quotient or xor of two such registers;
     - an and with one such register.
   - With that fact, an and is no wider than its never-negative operand, and an xor of two never-negative registers is no wider than the wider one. A stack of rounds on fixed-width words then keeps its words at their width through every floor, instead of growing a bit per round.
   - Every width is checked against the values: the bitwise oracle rebuilds each output bit from the raw fields and requires the sign to hold 64 bits past the written width.
4. **Time: what the stack compresses.**
   - **Chained**, each of the n floors pays a launch, a synchronization, and a round trip of its state through device memory, on top of its steps.
   - **Stacked**, the lane reads its atom once, runs every step in registers, and writes its record once. The time between floors is gone.
   - The lanes run side by side on the device. Until the device is full, a stack over L lanes costs one tower's depth for the whole batch.
   - **Measured** (below): stacked is 13 to 22 times faster than chained.
5. **Time: what the stack leaves as it is.**
   - Each lane still evaluates every step in order. Once the device is full, a sweep's time grows linearly with the number of steps.
   - The only ways to shorten that are fewer steps:
     - a table (a sub-function of up to 32 input bits becomes one lookup, and composition keeps its order);
     - narrower registers (fewer limbs a step);
     - folded, dropped and shared steps (below: steps and their reduction).
6. **Exactness.**
   - Every step is exact integer arithmetic.
   - The host evaluates the same key with the exact integer library.
   - A device that equals the host word for word proves the port, for a stack as for any program.

## Proved and measured

- **The stack test** (`test/engine/record_bitwise_test`). 700 floors of one round each, over four 32-bit words: xor, and, sum, xor with the floor's constant, and a 32-bit wrap.
  - 4,204 steps, one program, register reuse on, an 8-limb file.
  - On 1,024 lanes the device equals the host word for word. Both equal the same rounds run on the CPU's own 64-bit two's complement at every tapped floor.
- **Stacked against chained.** The same 700 floors, run as one program of 4,204 steps (a 12-limb file) and as 700 programs of 13 steps. Each chained sweep reads the previous sweep's records from device memory. RTX 3070, the second sweep of each timed:

  | lanes | stacked, one sweep | chained, 700 sweeps | ratio | records |
  |---|---|---|---|---|
  | 1,024 | 4,274 µs | 55,899 µs | 13.1× | equal |
  | 16,384 | 4,122 µs | 71,419 µs | 17.3× | equal |
  | 262,144 | 26,048 µs | 572,534 µs | 22.0× | equal |
  | 1,048,576 | 98,783 µs | 2,088,411 µs | 21.1× | equal |

  - At 1,024 and 16,384 lanes the stacked sweep takes the same time: the device is not yet full, and the batch costs one tower's depth.
  - From 262,144 lanes the time grows with the lanes, and the ratio settles near 21×. That ratio is the cost of the time between floors, which the stack removes.
  - At 1,048,576 lanes the stacked sweep evaluates 4.4 × 10^9 steps in 98.8 ms, about 4.5 × 10^10 steps a second.
  - The measure's source is held outside the repository and has not been rerun from it.

## What the stack is not

- It does not evaluate fewer steps than the program has. The depth stays; the compression is of the time between floors and across the lanes.
- It does not change a result: a stack and its chained programs give the same records.

## Steps and their reduction

- **A lane runs every step.** Derived from `cycle.cu`: one thread runs one lane's steps one after another. A lane's time grows with its step count, not with the program's dependency depth: two steps with no path between them still run in turn. The device runs lanes side by side, never the steps of one lane.
- **keymath takes the program as given.** Derived from `keymath.cu`: the key holds exactly the steps asked for, in their order (`key->steps = request->count`).
  - A step whose operands are all constants is not folded into one constant.
  - A step no output reads is not dropped.
  - Two equal steps are not merged.
  - Every reduction of the step count is the program writer's.
- **The reductions.** Each keeps every record the same.
  - Fold: a step over constants only becomes one constant.
  - Drop: a step no output depends on is removed.
  - Share: a value computed twice is computed once and read twice. The shared register lives from its first reader to its last, and the file pays for that span.
  - Table: a chain of one-register steps becomes one table step (below: tables).
- **Sharing trades steps for file.** Derived (replica). The proved lifting program emits its four distinct constants (1, 2, 3 and 4) 33 times: two for each of its 16 floor divisions, and one 2 read by both the lows and the evens.
  - Each constant emitted once and shared: 100 steps in place of 129, and a file of 15 limbs in place of 12.
  - The forward still equals tower.cu's formulas, and T⁻¹ ∘ T is still the identity, on 500 random lines.

## The record's length

Derived from `key_schedule.cu` and `cycle.cu`:

- A member's record length, `in_limbs`, is an unsigned int with no cap of its own. Laying the key checks only that each field lies inside it: field_offset + bits ≤ 32 · in_limbs.
- A field's offset is a 32-bit bit offset, and the kernel computes the bit it reads in 32-bit arithmetic.
  - A lane can address the first 2^32 bits of each record: 2^27 limbs, 512 MiB.
  - The lay check runs in 64-bit arithmetic. It does not refuse a field that ends past bit 2^32 of a record that long, and the kernel's bit arithmetic would wrap for that field.
- A lane reads at most 3 members (`ENGINE_RECORD_MEMBERS_MAX`), one record from each, chosen by the index. Each member is its own device array. Nothing in the kernel stops the three from being the same array.
- The records sit in device memory: bodies × in_limbs × 4 bytes for each member. A record's address is computed in 64-bit arithmetic. Past the 2^32-bit offset, the device's memory is the practical bound on a record's length.
- A lane's output record holds each output at its width plus one sign bit. The lay checks their sum stays below 2^31 bits.
- The two bounds are separate. The record bounds what a lane can read, and the file bounds what it can hold at once.

## The two towers

Doug's (24 September): a second tower stacked over the first one's boundary, inverted, and the two collapse together. One is the crystal, the tower of the data's lifted floors. The other is the tower of operations, the stack above.

- **The crystal's tower T** is the 5/3 integer lifting of `src/engine/base/tower/tower.cu` (A14 in [engine_table.md](engine_table.md)). One level over a line of samples x:
  - the high d_j = x_{2j+1} − ⌊(x_{2j} + x_{2j+2}) / 2⌋;
  - the low s_i = x_{2i} + ⌊(d_{i−1} + d_i + 2) / 4⌋;
  - an edge repeats its neighbor.
- **Its inverse T⁻¹** runs the same two lines backward and in the other order: x_{2i} = s_i − ⌊(d_{i−1} + d_i + 2) / 4⌋, then x_{2j+1} = d_j + ⌊(x_{2j} + x_{2j+2}) / 2⌋.
- **Floor division is a record floor.** For every integer v and k ≥ 0:

  ⌊v / 2^k⌋ = EXACT_QUOTIENT(v − AND(v, 2^k − 1), 2^k)

  - The and reads v's two's complement without end. With the never-negative mask 2^k − 1 it gives v's residue modulo 2^k, in [0, 2^k), for a negative v as for a positive one.
  - v less its residue is a multiple of 2^k. The exact quotient divides it with nothing left over, and the quotient rounds toward −∞, as `tower_floor_shift` does.
  - The residue is no wider than the mask, k bits, by the never-negative width rule (3).
- **T and T⁻¹ are stacks of record floors.** Every step of a lifting level is a sum, a difference, a constant or that floor division. A level is a floor of the record machine, L levels are L floors, and the inverse is L more.
- **The operation tower over the crystal.** A program F that reads the crystal's lifted floors, and the inverse T⁻¹ that brings them back, compose into one stack F ∘ T⁻¹ by the regrouping law (1). No step between them leaves the lane, and T⁻¹ ∘ T is the identity on the machine exactly.
- **Proved** (`test/engine/record_bitwise_test`): one 5/3 level over 8 signed 16-bit samples and its inverse, 129 steps as one program, register reuse on, a 12-limb file, 4,096 lanes of edge-shaped samples.
  - The device equals the host word for word.
  - The forward floor's 4 lows and 4 highs equal tower.cu's formulas, computed on the CPU, on every lane.
  - The inverse floor returns all 8 samples exactly on every lane.

## The lifting as record floors

- **The cone.** Derived.
  - One level: a high reads 3 samples (x_{2j} to x_{2j+2}), a low reads 5 (x_{2i−2} to x_{2i+2}).
  - L levels along a line: a level-L low reads 5 consecutive level-(L−1) lows, spaced 2^{L−1} samples apart. Its span w_L = w_{L−1} + 4 · 2^{L−1}, with w_1 = 5, gives w_L = 2^{L+2} − 3 samples. It reaches 2^{L+1} − 2 samples past its center on each side.
  - Separable in D axes, one level along each axis in turn: the span is the product, (2^{L+2} − 3)^D. One level in 4-D reads 5^4 = 625 samples.
  - The replica agrees for L = 1 to 6 in 1-D and for D = 1 to 4 at one level. Its forward equals tower.cu's formulas, computed on the CPU, on every line it ran.
- **The file of one cone.** Derived (replica). Only the steps one interior low reads, in depth-first order, with each field read just before its first use:

  | levels L (1-D) | samples read | steps | file | the low's derived width |
  |---|---|---|---|---|
  | 1 | 5 | 28 | 6 limbs | 20 bits |
  | 2 | 13 | 119 | 11 limbs | 24 bits |
  | 3 | 29 | 338 | 17 limbs | 28 bits |
  | 4 | 61 | 813 | 23 limbs | 32 bits |
  | 5 | 125 | 1,800 | 29 limbs | 36 bits |
  | 6 | 253 | 3,811 | 40 limbs | 40 bits |

  | axes D (one level) | samples read | steps | file | the all-low coefficient's derived width |
  |---|---|---|---|---|
  | 1 | 5 | 28 | 6 limbs | 20 bits |
  | 2 | 25 | 163 | 9 limbs | 24 bits |
  | 3 | 125 | 838 | 12 limbs | 28 bits |
  | 4 | 625 | 4,213 | 15 limbs | 32 bits |

  - The file stays far below the samples read. The count of samples read is not a bound on the file.
  - Depth-first is one order among many, and the order with the smallest file is not known here. Finding the smallest register file for a program without recomputation is NP-complete in general (Sethi, "Complete register allocation problems", SIAM J. Comput. 4, 1975).
- **Widths across levels.** Derived.
  - **The constant-divisor narrowing** (Anchor_sift, 24 September). keymath gives a quotient or exact quotient whose divisor is a constant c the dividend's width less ⌊log2 c⌋ bits, never under 1. The engine's quotient rounds toward zero and the exact quotient does not round: |q| ≤ |v|/c < 2^{w − ⌊log2 c⌋} for a w-bit dividend. The floor toward −∞ belongs to the lifting's composite of an and, a difference and an exact quotient, never to one operation. The exact quotient now works at its numerator's width and checks q · c against the whole numerator. **Proved** (`test/engine/record_divide_test`, 19 checks, 0 failed): 40-bit factors times 3, 12 and 2^32 + 7 divide back exactly, a 64-bit value over 2^32 + 7 equals the library's quotient, and the widths are exactly the rule's.
  - With it, keymath gives a high of 16-bit samples 18 bits and a low 20. Each level adds 4 bits to a low: 16, 20, 24, 28, and 40 at level 6, two limbs. Before it, 7 bits a level: 23, 30, and 58 at level 6. The proved program's file is 12 limbs under either rule.
  - The values grow far less. The low's linear part is (−1, 2, 6, 2, −1)/8 over x_{2i−2} to x_{2i+2}, with Σ|c| = 1.5. Its floors add less than 3/4.
  - Over samples |x| ≤ B: |s| ≤ 1.5B + 1 and |d| ≤ 2B. The edge cases (a line of 2 or 3, either end) repeat a neighbor and keep Σ|c| ≤ 1.5 for a low and 2 for a high.
  - The low's bound grows log2 1.5 ≈ 0.585 bits a level and the high's 1 bit, against keymath's 4.
  - A wrap to w = bit_length(bound) + 1 bits after each level holds every value in range exactly: [−2^{w−1}, 2^{w−1}) contains [−bound, bound].
  - A wrap is silent: the machine does not check that its value is in range. A wrong wrap gives a wrong record on the device and the same wrong record on the host, and device = host still holds. Only an oracle outside the machine, such as tower.cu's formulas, catches it.
- **A whole line, down and back.** Derived (replica). 64 samples, all 6 levels, then all 6 inverse levels, in one program, in the order they are emitted:

  | widths | steps | widest register | file | T⁻¹ ∘ T = id on 200 lines |
  |---|---|---|---|---|
  | derived by keymath | 1,966 | 58 bits | 130 limbs | yes |
  | wrapped at the bound after each level | 2,092 | 39 bits | 122 limbs | yes |

  - The 126 extra steps are the wraps, one for each coefficient.

## The neighbor gather

- **The limit.** In one sweep a lane reads at most 3 records. A coefficient's cone must lie in those records.
- **One axis: tiles, nothing duplicated.** Derived. Lay the line as records of t samples each. A lane reads its left, own and right tiles as its three members through the index. Its L-level coefficients reach 2^{L+1} − 2 samples to each side, which lie in the three tiles when 2^{L+1} − 2 ≤ t.
- **D axes.** Derived. A tile's one-level cone touches 3^D − 1 neighbor tiles: 8, 26 and 80 in 2, 3 and 4 axes. Three members reach the neighbors along one axis only. Two ways remain.
  - **The halo in the record.** Each record carries its tile and the halo its cone reads. One level on a tile of (2m)^D samples reads (2m + 3)^D, duplicating ((2m + 3)/(2m))^D. A lane then lifts its tile alone and recomputes what its neighbors also compute.
  - **One axis per sweep.** Each sweep lifts along one axis, with the three members as the left, own and right tiles along it. A D-axis crystal of L levels takes D · L sweeps, with no duplication and no recomputation. Each boundary between sweeps pays the chained cost.
- **What a tile costs.** Derived (replica). A lane per tile, one level, every coefficient its tile owns, in depth-first order:

  | D | tile | samples read | steps a sample | the whole grid, steps a sample | file |
  |---|---|---|---|---|---|
  | 1 | 2 | 5 | 14.0 | 8.6 | 6 limbs |
  | 1 | 16 | 19 | 9.2 | 8.5 | 8 limbs |
  | 2 | 4 | 25 | 46.5 | 16.2 | 13 limbs |
  | 2 | 256 | 361 | 18.9 | 16.1 | 179 limbs |
  | 3 | 8 | 125 | 127.8 | 23.8 | 40 limbs |
  | 3 | 512 | 1,331 | 38.9 | 23.7 | 659 limbs |
  | 4 | 16 | 625 | 330.9 | 31.4 | 167 limbs |
  | 4 | 256 | 2,401 | 115.5 | 31.3 | 1,153 limbs |

  - One level of the whole grid costs 7.5 steps a sample for each axis plus one field step: 8.5, 16, 23.5 and 31 in 1 to 4 axes. The replica's grids add one constant for each line.
  - A tile recomputes its halo. In 4-D a 16-sample tile runs 331 steps a sample against the grid's 31.
  - In this order a tile's file passes 256 limbs at 512 samples in 3-D and 256 samples in 4-D.
- **What a split costs.** Derived from the stacked-against-chained measure, which has not been rerun.
  - At 1,048,576 lanes the stacked sweep spends about 0.0224 ns a lane for each step.
  - The chained run's 700 × 13 steps account for about 214 ms of its 2,088 ms. The rest, about 2.68 ms a floor, is about 2.55 ns a lane, or about 114 step-times a lane at each boundary.
  - That floor carried 4 words a lane. The measure does not separate launch, synchronization and memory, and a boundary carrying more words may cost more.
  - On these numbers, one axis per sweep with t samples a lane pays about 114/t step-times a sample at each boundary. The halo of a 16-sample 4-D tile costs about 300 extra steps a sample.
- **Open:** which way costs less for the crystal, until the chained cost is measured apart; and a tile's file under a better order.

## The two boundaries

Doug's (24 September): the bottom boundary of the inverted tower and the bottom boundary of the upright tower are the same boundary, right next to one another, never touching.

- **The floors.**
  - T stands up from its floor 0, the samples. T⁻¹ hangs down and ends on its floor 0, the rebuilt samples.
  - An operation program F stands up from its own floor 0, the atom. In F ∘ T⁻¹, T⁻¹'s bottom is F's bottom.
  - A floor is a cut between steps. Its registers are the ones live at that cut.
- **Never touching, literally.**
  - T's floor 0 is the atom: fields in the record, in device memory, which field steps read.
  - T⁻¹'s floor 0 is registers in the file, written by steps and put into the output record.
  - **Proved** (`test/engine/record_bitwise_test`): on 4,096 lanes the rebuilt samples equal the input fields, value for value. They are never the same register. One side lives in the record read, the other in the file and the record written.
- **T is a bijection.** Derived.
  - Each lifting step adds to one half of the line a function of the other half only. The highs subtract a floored prediction made from the evens, then the lows add a floored update made from the highs.
  - A step (a, b) ↦ (a, b − P(a)) is undone by (a, c) ↦ (a, c + P(a)) for any function P, floors included: the same value comes back off.
  - Every level and every axis is a composition of such steps (Sweldens, "The lifting scheme", 1996; Calderbank, Daubechies, Sweldens and Yeo, "Wavelet transforms that map integers to integers", 1998).
  - T is a bijection of the integer vectors of each shape. T⁻¹ ∘ T = id and T ∘ T⁻¹ = id on every input, for every level count and axis order, when three things hold: the inverse repeats the forward's edge rule, it runs the steps in reverse order, and the machine refuses nothing (no register past 32 · 256 bits, every wrap in range).
- **The pair cancels.** Derived. F ∘ T⁻¹ ∘ T = F ∘ (T⁻¹ ∘ T) = F by the regrouping law. F run on the crystal's floors through T⁻¹ gives the same records as F run on the samples.
- **The pair costs steps and yields nothing.** Derived.
  - keymath does not see the identity: T⁻¹ ∘ T emitted as steps runs every one of them.
  - In the proved program T is 69 steps (8 field steps and 61) and T⁻¹ is 60. F on the samples needs only the 8 field steps.
  - When the record holds the samples, F on the samples saves every step of T and T⁻¹.
  - When the record holds only the crystal, F ∘ T⁻¹ is the way down to the samples, and T⁻¹'s steps are its price.
- **Operations between the towers.** Derived. An operation G on the lifted floors, between T and T⁻¹, gives the program T⁻¹ ∘ G ∘ T on the samples: G conjugated by T.
  - Chains cancel inside: (T⁻¹G₂T) ∘ (T⁻¹G₁T) = T⁻¹(G₂G₁)T. A chain of operations on the crystal pays one T and one T⁻¹, not a pair for each operation.
  - T⁻¹GT = id exactly when G = id. The full cancellation survives only an identity in the middle.
  - T⁻¹GT is a bijection exactly when G is one, and its inverse is T⁻¹G⁻¹T.
  - The levels above G cancel past it. Write T = T_L ∘ … ∘ T_1, level 1 first. Level j reads and writes only the all-low corner that level j − 1 left. A G that touches only coefficients outside the corner of level ℓ (the highs of level ℓ or below) acts on other coordinates than every T_j above ℓ, and commutes with them. Then T⁻¹GT = T_1⁻¹ ∘ … ∘ T_ℓ⁻¹ ∘ G ∘ T_ℓ ∘ … ∘ T_1: a G on level ℓ's highs costs ℓ levels each way, not L.
- **An edge is a record floor.** Derived from `tower_edge_kernel` (A14).
  - An edge permutes the low k bits of a coefficient through a table π (k ≤ 20) and passes its high bits.
  - For every integer v: E(v) = (v − AND(v, 2^k − 1)) + TABLE_π(AND(v, 2^k − 1)).
  - The and is v's residue, never negative and k bits wide, and the table step indexes by it. v less its residue has k low zero bits, and the sum puts π's value in them. For a 32-bit word it agrees with the kernel's (word & ~mask) | π(word & mask).
  - E is a bijection of the integers. T⁻¹ET is a bijection of the samples with inverse T⁻¹E⁻¹T. An edge on level ℓ's highs costs ℓ levels each way.
  - An edge moves a coefficient by less than 2^k. A wrap placed after an edge needs its bound raised by 2^k, or it is silently wrong.
- **Open:** which G on the lifted floors make T⁻¹GT shorter than T, G and T⁻¹ emitted apart. A G that commutes with T gives T⁻¹GT = G, run on the samples with no lifting at all. Which edges commute with T is open.

## The heap and the ring

Doug's framing (24 September, paraphrased): domain and range are complete and defined across the whole function. Information heaps, and stretched out it looks fuzzed, but it always stays within the domain's bound, "ever ringed". Abstractly it is a fuzzy oval brush stroke, and the more oval the shape, the more complex the information.

- **The heap** of a floor, on one lane: Σ over the floor's registers of the value's magnitude bits, plus 1 for the sign where the value is nonzero.
- **The ring** of a floor: Σ over the floor's registers of the imprint's widths. It belongs to the program and is the same on every lane.
- **Measured in a scratch run** (Anchor_sift's `ovoid_measure.cu`, not a committed test). One program: T over 64 signed 16-bit samples at 6 levels, then T⁻¹, with the widths before the constant-divisor narrowing.
  - 4,096 lanes in four classes by lane mod 4: a clean ramp, the ramp with noise of ±8, the ramp with noise of ±1,024, and raw noise over the whole 16-bit range.
  - The round trip is exact on 4,096 of 4,096 lanes at 3 and 6 levels, and the device equals the host word for word.
  - The mean heap:

  | floor | ramp | ±8 | ±1,024 | noise | ring |
  |---|---|---|---|---|---|
  | T0 | 857 | 851 | 856 | 960 | 1,024 |
  | T1 | 435 | 542 | 754 | 957 | 1,344 |
  | T2 | 229 | 389 | 702 | 955 | 1,504 |
  | T3 | 131 | 314 | 673 | 956 | 1,584 |
  | T4 | 87 | 279 | 658 | 956 | 1,624 |
  | T5 | 71 | 266 | 651 | 956 | 1,644 |
  | T6, the crystal | 70 | 265 | 650 | 956 | 1,654 |
  | T⁻¹ 5 | 71 | 266 | 651 | 956 | 1,663 |
  | T⁻¹ 4 | 87 | 279 | 658 | 956 | 1,703 |
  | T⁻¹ 3 | 131 | 314 | 673 | 956 | 1,827 |
  | T⁻¹ 2 | 229 | 389 | 702 | 955 | 2,163 |
  | T⁻¹ 1 | 435 | 542 | 754 | 957 | 3,011 |
  | T⁻¹ 0 | 857 | 851 | 856 | 960 | 5,059 |

  - The heap pinches at the crystal by 12× for the ramp, 3.2× at ±8 and 1.3× at ±1,024, and not at all for noise.
  - The live bits peak at the last cut (5,079), not at the crystal (1,656).
  - 128 samples at 7 levels are refused: 93-bit registers overflow the 256-limb file.
- **The ring is the domain's bound.** Derived. The imprint's width W_r bounds register r's magnitude for every input in the fields' domain: |v_r| < 2^{W_r}. The magnitude part of the heap is at most the ring on every floor of every lane. The sign bits can add one bit a nonzero register: heap ≤ ring + the floor's nonzero registers. A 16-bit field holding −32,768 fills its 16 bits and takes a sign bit besides.
- **The crystal is the mirror's plane.** Derived. T⁻¹ undoes the levels in reverse: after T_L⁻¹ to T_{k+1}⁻¹, the line holds T_k ∘ … ∘ T_1 of the samples. The inverse floor k holds the forward floor k's values, register for register, and the heap is an exact mirror across the crystal on every lane. The replica checks this on 300 lines.
- **The ring is not a mirror.** Derived. A width follows the path of steps that made the register, never its value, and nothing narrows it back. keymath cannot see T⁻¹ ∘ T = id. The inverse side's widths grow from the crystal's: at T⁻¹ 0, registers of 82 bits before the narrowing, and 58 after it, hold 16-bit values.
- **Two fixes.**
  - The constant-divisor narrowing (built and proved, above).
  - The wrap at the mirror (derived, not built). The inverse floor k holds the forward floor k's values, each within its forward register's width b. WRAP(v, b + 1) on each rebuilt register passes its value through unchanged, and WRAP(v, 16) on the rebuilt samples is exact on 16-bit input. The bound comes from the mirror, not from the values. It needs T⁻¹ ∘ T = id: with an operation between the towers the mirror breaks, and a wrap placed by it is silently wrong.
- **The ring under the three rules.** Derived (replica). The first column reproduces the scratch run's ring exactly.

  | floor | before the narrowing | narrowed | narrowed, wrapped at the mirror |
  |---|---|---|---|
  | T0 | 1,024 | 1,024 | 1,024 |
  | T1 | 1,344 | 1,216 | 1,216 |
  | T2 | 1,504 | 1,312 | 1,312 |
  | T3 | 1,584 | 1,360 | 1,360 |
  | T4 | 1,624 | 1,384 | 1,384 |
  | T5 | 1,644 | 1,396 | 1,396 |
  | T6, the crystal | 1,654 | 1,402 | 1,402 |
  | T⁻¹ 5 | 1,663 | 1,408 | 1,398 |
  | T⁻¹ 4 | 1,703 | 1,434 | 1,388 |
  | T⁻¹ 3 | 1,827 | 1,514 | 1,368 |
  | T⁻¹ 2 | 2,163 | 1,730 | 1,328 |
  | T⁻¹ 1 | 3,011 | 2,274 | 1,248 |
  | T⁻¹ 0 | 5,059 | 3,586 | 1,024 |
  | steps; widest register; file | 1,966; 82 bits; 171 limbs | 1,966; 58 bits; 130 limbs | 2,092; 43 bits; 84 limbs |
  | 128 samples, 7 levels | 93 bits; 330 limbs, refused | 65 bits; 261 limbs, refused | 47 bits; 164 limbs |

  - Wrapped at the mirror, each inverse floor's ring is the forward floor's plus one bit for each wrapped register. The wrap's signed range needs one bit over the forward register's magnitude width. Floor 0 is exact at 1,024.
  - The narrowing alone leaves 128 samples at 7 levels over the file. The wrap at the mirror brings it to 164 limbs.
  - **Measured in a scratch run** (Anchor_sift, on the device, 4,096 lanes; the round trip is exact and the device equals the host in every run):
    - Narrowed: the ring equals the replica's column floor for floor, in a 130-limb file. The run has 1,955 steps; the replica's 11 more are its own constant 2s. The live bits peak at the last cut, 3,606.
    - Wrapped at the mirror: T⁻¹ 5 to T⁻¹ 1 equal the replica's column, in an 84-limb file of 2,081 steps. The run wrapped the samples to 17 bits, not 16, and its T⁻¹ 0 reads 1,088. The live bits peak at 1,546, at cut 1,023, against 1,010 at the crystal.
    - 128 samples at 7 levels: refused under the narrowing alone, its widest register 65 bits. Wrapped at the mirror, it loads in 164 limbs and 4,193 steps, with the ring 2,048 at the samples, 2,810 at the crystal and 2,176 at the rebuilt samples, and the round trip is exact on every lane.
- **The crystal as a code length.** Derived.
  - The heap alone is not a code length: nothing in it says where one value ends and the next begins.
  - The ring supplies the framing. For each register r, write its magnitude's bit count m_r in ⌈log2(W_r + 1)⌉ bits, then, where m_r > 0, the m_r − 1 bits under the leading one and the sign. The decoder knows every W_r from the program.
  - The code's length is Σ_r ⌈log2(W_r + 1)⌉ + Σ_r m_r: the heap plus the framing, less one bit for each nonzero register. Any prefix code on the counts m_r serves in place of the fixed field.
  - T is a bijection. Decoding the crystal and running T⁻¹ gives the lane back: K(x | the program) ≤ that length + c, for a constant c, the length of a fixed decoder.
  - The code states each coefficient alone, by its length and its bits, the same way for every register of a floor of the tower. It is a memoryless coder of the tower's coefficients, the class of rung F2 in [compression_table.md](compression_table.md). Its length is at least F2's multinomial terms for the same coefficients, and F2 is the tighter rung. As a two-part code it is F3′ with an empty model ([kolmogorov_arnold.md](kolmogorov_arnold.md), item 5).
  - The bound runs one way. K can be far below the crystal's code: a lane printed by a short program whose samples show no smoothness gets a noise-sized crystal.
- **Which shape is the oval.** Stated, not resolved; it is Doug's call.
  - The heap across the floors is an hourglass for simple data, pinched at the crystal. Its waist fills in as the complexity rises, and noise shows none.
  - The space between the heap and the ring is an oval, largest for simple data.

## The lens

Doug's posit (24 September): "The crystal is a lens between our universe and information space: the cleaner the crystal, the better the lensing and tetrated resources."

- **What the measure supports.** Measured in the scratch run above: the crystal concentrates a lane's structure. The ramp's 857 bits go to 70, 12×, and the pinch ranks the four classes by their complexity. A cleaner crystal, a sparser heap, is a sharper focus, and the pinch is a per-lane reading of how much structure the lens sees.
- **What bounds it.** Derived.
  - T is a bijection: the crystal holds the lane exactly and adds or loses nothing. No prefix code of the crystal is shorter than K(x | the program) − c. The lens reaches toward K and never below it.
  - By counting, fewer than 2^{n−j} codewords are shorter than n − j bits. Of the 2^n lanes of n bits, fewer than a 2^{−j} fraction can be coded j or more bits short, by any lossless coder, the crystal included. No lossless map shortens most inputs.
  - Noise gets no focus: measured, 960 bits to 956.
  - The lens's gain on a lane is at most n − K(x | the program) + c, the lane's own compressibility. The 5/3 lens sees only the smoothness its lifting predicts, and its gain is usually far less.
- **The tetration.** Derived. A gain of tetrated size needs a lane whose description is tetrated-small against its length. Such lanes exist, printed by tiny programs, but by counting they are a vanishing fraction, and the 5/3 lens need not find them. Any such gain comes from the input's description, never from the lens.
- **Open.**
  - Whether a ladder of lenses (more levels, other liftings, tables at the crystal) comes closer to K on a named class of lanes.
  - What "tetrated resources" measures, and against what bound.

## F ∘ T⁻¹ for a linear F

Derived.

- T⁻¹ is not linear, because its floors are not. F ∘ T⁻¹ is not a matrix even when F is one, and it cannot be folded into one matrix exactly.
- Its distance from the linear inverse W⁻¹ (the same two lines without floors), for the same coefficients c, along one line:
  - An even sample's floor, ⌊(d_{i−1} + d_i + 2)/4⌋ against (d_{i−1} + d_i)/4, moves the even by −1/2, −1/4, 0 or 1/4.
  - An odd sample's floor, ⌊(a + b)/2⌋ against (a + b)/2, moves the odd by 0 or −1/2.
  - The highs are read exact from c. An inverse level that receives its lows with error at most ε returns evens with error at most ε + 1/2 and odds with error at most ε + 1.
  - Over L levels, ‖T⁻¹c − W⁻¹c‖∞ ≤ L.
  - For a linear F with ‖F‖∞ its largest row sum of |entries|: |F(T⁻¹c) − F(W⁻¹c)| ≤ L · ‖F‖∞ along one line.
- In D axes the highs of one axis carry the error of the axes inverted before them. The bound there is open.
- As a stack, F ∘ T⁻¹ saves the time between F and T⁻¹ (item 4), not steps: its step count is F's plus T⁻¹'s.

## The lane index and the latch

- **The lane index.** Derived from `cycle.cu`: the kernel holds each lane's number as a 64-bit loop variable, and no step reads it. A step that writes it into a register is open.
- **The latch.** Derived. The first lane that meets a condition is the minimum over lanes of ℓ where the condition holds, with ∞ where it does not. The minimum is associative, commutative and idempotent. Any grouping returns the same lane as a serial scan from lane 0: a tree of depth ⌈log2 lanes⌉, or a device-wide atomic minimum. The latch is not built.

## Tables

Derived.

- A chain of steps that each read one register, starting from a register of b ≤ 32 bits, is one function of that register. One table step of 2^b rows replaces the chain, and composition keeps its order (M10, proved).
- The table reads the low b bits of the register's magnitude: the file holds a magnitude and a sign.
  - A register that can be negative indexes by |v|, and v and −v read the same row.
  - A signed register goes into a table after it is made never negative, for example by adding 2^{b−1} to a b-bit signed field.
- Two never-negative registers u and v, of b_u and b_v bits with b_u + b_v ≤ 32, index one table as u · 2^{b_v} + v. A constant, a product, a sum and the table step compute any function of the pair: 4 steps, or 3 when the constant is shared.
- A table of b index bits and out_bits bits holds 2^b · ⌈out_bits/32⌉ · 4 bytes: 4 GiB at b = 30 with one-limb rows, 16 GiB at b = 32. On an 8 GB device one table of one-limb rows fits up to b = 30.

## Open

- **A lane's own index as a register.** A lane now reads its inputs only from records. An operation giving the lane's number as a value would let one shared atom stand for a whole range of inputs, with the lanes enumerating the range and no input stored per lane.
- **The latch.** A device reduction that returns the first lane whose output meets a condition. Only that lane's index comes back to the host.
- **Depth by tables.** Which rounds' sub-functions fit a 32-bit index, and how much depth that removes.
- **The chained cost apart.** Launch, synchronization and the state's round trip through memory, each measured on its own.
- **The neighbor gather.** For D axes: the halo in the record, or one axis per sweep. Which costs less waits on the chained cost apart. A tile's file under a better order than depth-first is also open.
- **The smallest file.** An order of the lifting's steps with a smaller file than depth-first, or a proof that none exists.
- **F ∘ T⁻¹ in D axes.** The bound on its distance from the linear F ∘ W⁻¹, and any particular F that runs through T⁻¹ in fewer steps than the two apart.
- **Operations that commute with T.** Which operations on the lifted floors, edges included, commute with T, and run on the samples with no lifting.
- **The heap and the wrap at the mirror as tests.** The scratch runs committed as tests, and the heap tabled under the narrowed widths. **Proved** since: `test/engine/record_boundary_test` (41 checks, 0 failed, cell_tracking main de5bdff) runs T then T⁻¹ over 64 samples at 4 levels with the mirror wraps, every floor an output. The heap mirrors on every lane, the ring is ring_0 + 6(n − n/2^ℓ) at floor ℓ and one bit wider for each wrapped low at its mirror, and the pinch orders the four classes; the ring derived in [two_crystals.md](two_crystals.md).
- **The oval.** Which shape it is, the heap's hourglass or the gap between heap and ring, is Doug's call.
- **The lens.** Whether a ladder of lenses comes closer to K on a named class of lanes, and what "tetrated resources" measures.
- **The whole crystal as one stack.** The proof above is one level along one line. All levels along all four axes as record floors, against tower.cu's own crystal, is not built.
