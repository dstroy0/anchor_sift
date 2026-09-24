# Vertical time compression: floors stacked into one sweep

**Purpose:** the algebra of the record machine's stacked floors: what a stack is, what it compresses, what it leaves as it is, and what is proved and measured about it.

**Scope:** the record machine (M10 and A13 in [engine_table.md](engine_table.md)): `keymath` imprints a program, `key_schedule` lays it out, `cycle` sweeps it. The shape is Doug's (24 September): a floor, the operations in order above it, the next floor, and so on up, with the top conjunction performing the whole transform.

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
2. **The file is bounded by the widest floor, not by the step count.**
   - A register is live from the step that writes it to its last reader. With reuse on, the file needs the most limbs live at any one step. That is at most the widest floor plus the round in flight.
   - The step count has no bound of its own. `ENGINE_RECORD_STEPS_MAX` held one sign per step. Since 24 September each sign sits beside its register. The file (`ENGINE_RECORD_LIMBS_MOST`, 256 limbs) is now the only bound.
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
     - narrower registers (fewer limbs a step).
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

## Open

- **A lane's own index as a register.** A lane now reads its inputs only from records. An operation giving the lane's number as a value would let one shared atom stand for a whole range of inputs, with the lanes enumerating the range and no input stored per lane.
- **The latch.** A device reduction that returns the first lane whose output meets a condition. Only that lane's index comes back to the host.
- **Depth by tables.** Which rounds' sub-functions fit a 32-bit index, and how much depth that removes.
- **The chained cost apart.** Launch, synchronization and the state's round trip through memory, each measured on its own.
