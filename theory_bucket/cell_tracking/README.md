# The workbook is the ledger

**Purpose:** One place where every idea the engine rests on is written down beside what stands behind it; a later session knows at a glance which claims are proved, which are measured, which are built but unmeasured, and which are still only theory.
**Scope:** `theory/`. The thought experiments are in `thought_experiments/`: most can be tested and some cannot yet, and each is kept as it was written, with only Gemini's export artifacts removed (the `[cite: …]` markers, which pointed at nothing, and a medical disclaimer Gemini attached after misreading exact limb arithmetic).

## How an entry is kept

Every claim carries one status, and the status says what backs it:

| status | what it means |
|---|---|
| **proved** | an exact check ran over the whole set and found no exception; the count is given |
| **measured** | a number was taken on named samples; the number is given, and whether it held up |
| **built** | the code exists and runs; no measurement yet says whether it helps |
| **theory** | stated, not built |
| **refuted** | measured, and the measurement went against it; kept, with the number; it is not tried again blind |
| **not so** | fails on its own arithmetic or in any machine, before anything is measured; kept, with the reason |

A claim changes status only when a run changes it, and the run is named. Nothing is deleted from the ledger. An idea that failed stays, with the number that failed it.

## Entries

| file | what it holds |
|---|---|
| [keys_explained.md](keys_explained.md) | the ideas a programmer's defaults push against, from first principles with the engine's numbers: transitivity carried all the way, the imprint, AND and add, unbounded operations in a small key, folding a check into a pass, exact arithmetic with no floor, the noise read and never modeled |
| [imprint_key_cycle.md](imprint_key_cycle.md) | the atom; imprinting a program onto the impulse; keys as AND masks; running a key over the set in one cycle |
| [noise_sieve_tower.md](noise_sieve_tower.md) | the transfinite noise sieve and the fluidic architecture, section by section against the engine: control and data planes, the key and LUT, the tower and floor −4, the demon's eyes and arms, the construct kit, identity as coherence, entropy |
| [engine_table.md](engine_table.md) | the machine part by part, held to no scale: its exact algebra, what each part does and wants, every hypothesis tried with its result, and the audit of every number that still fixes a scale |
| [two_crystals.md](two_crystals.md) | the record machine over the 2-adic integers: the wrap as a projection, the five operations that commute with every projection and the test that proves it, the exact quotient by an odd divisor as a 2-adic product, the bits the lifting reads, the two limits of the finite windows and the solenoid between them, what passes to a limit, and Doug's posits bounded |
| [kolmogorov_arnold.md](kolmogorov_arnold.md) | the Kolmogorov–Arnold representation theorem held exactly: where the engine already has its shape (the tower's lifting, the residual, the binomial ladder as integer B-splines, the cycle's sums), why that is not a KAN (a KAN fits float splines and rounds; the engine fits nothing and rounds nothing), and what finishes it |
| [compression_table.md](compression_table.md) | the crystal's size set by set against the floor the data allows: the ladder of exact bounds from raw to the noise floor, every coder variant tried, and the order to close the gap |
| [tessera_scheduler.md](tessera_scheduler.md) | the scheduler: how jobs from separate processes share one device by memory, the accounting and its invariant, measuring by pid on Linux and Windows, one daemon per host |
| [obsignatio_seal.md](obsignatio_seal.md) | the seal: the dimensional Merkle DAG of keyed BLAKE3 nodes over every crystal and set, what it proves, what it costs, and where it stops |
| [cell_tracking_table.md](cell_tracking_table.md) | the cell program's n-body problem part by part: the physics, what the program does for each part, what it wants, every hypothesis tried with its result, and the tracker's equation as reads of the machine |
| [ledger.md](ledger.md) | every measurement, dated, in the order it was taken, with its samples and its result |

## Thought experiments

| file | origin |
|---|---|
| `thought_experiments/noise_sieve_1_rule_propagation.md` | the first draft: top-down rule propagation down the tower to floor −4 |
| `thought_experiments/noise_sieve_2_lut_beamformer_collapse.md` | adds the binary LUT engine, two's complement exact division, the beamformer and the 2D collapse |
| `thought_experiments/noise_sieve_3_tower_scheduling_floor_minus_4.md` | adds temporal stacking, the master schedule and floor −4 as the irreducible limit |
| `thought_experiments/noise_sieve_4_laplace_demon.md` | adds the demon: shift agreement as its eyes, the identity:null permutation as its arms |
| `thought_experiments/noise_sieve_5_cell_tracking_harmonics.pdf` | the sieve applied to this competition: the engine holds nothing and gradients define themselves; a split as a boundary discontinuity; mitosis and lysis judged over the whole sample by an entropy bump; each body's spherical harmonic fingerprint, dipole and quadrupole dominant |
| `thought_experiments/fluidic_1_demon_uroboros_construct_kit.md` | the fluidic tower: the demon observer, the self-feeding loop, the three irreducible sets |
| `thought_experiments/fluidic_2_elevator_identity_entropy.md` | the elevator operator, recursive inflation, identity as the limit of coherence, binary probes, entropy |
| `thought_experiments/subtractive_cosmological_framework.pdf` | a conversation, eight pages: rules propagating at field speed, not instantly; arrival as a wavefront; listening at the noise floor; phase cancellation; the identity:null permutation as field noise readings only |
| `thought_experiments/cyclic_field_inversion_seed_crystal.pdf` | exported as "Solving N-Body Problems Deterministically", though it holds no n-body method: a conversation, four pages, on the field inverting at maximum entropy, the seed crystal, and the needle snap just off zero radius that breaks symmetry and sets the next field's propagation speed |
| `thought_experiments/hash_boundary_functional_folding.md` | the boundary functional of a 2^120 hash keyspace as a threshold latch, and folding schemes that keep an accumulator one size however much is folded |
| `thought_experiments/demon_utm_four_noise_vectors.md` | the demon and a non-halting UTM treating video noise as deterministic: the residual tensor F − I split into four vector magnitudes (shot, thermal/read, fixed pattern, quantization) integrated over n frames |
| `thought_experiments/utm_demon_openqasm.md` | a UTM paired with Laplace's demon running an OpenQASM circuit: the 2^n state vector, unitaries, and measurement without dice |
