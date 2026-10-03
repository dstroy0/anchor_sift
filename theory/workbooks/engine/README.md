# The workbook is the ledger

**Purpose:** One place where every idea the engine rests on is written down beside what stands behind it. A reader can see at a glance which claims are proved, which are measured, which are built but unmeasured, and which are still only theory.
**Scope:** `workbooks/engine/`. The thought experiments the engine's theory was carried from are in `thought_experiments/engine/`. The compression lower bound is its own workbook, `workbooks/compression/`, and the cell program is `workbooks/cell_tracking/`.

## How an entry is kept

Every claim carries one status, and the status says what backs it:

| status | what it means |
|---|---|
| **proved** | an exact check ran over the whole set and found no exception; the count is given |
| **measured** | a number was taken on named samples; the number is given, and whether it held up |
| **built** | the code exists and runs; no measurement yet says whether it helps |
| **theory** | stated, not built |
| **refuted** | measured, and the measurement went against it; kept with the number, and never tried again blind |
| **not so** | fails on its own arithmetic or in any machine, before anything is measured; kept, with the reason |
| **want** | wanted and not had: stated as a goal, with no run, build or derivation behind it; kept whole, with its open question, in [wants.md](wants.md) |

A claim changes status only when a run changes it, and the run is named. Nothing is deleted from the ledger. An idea that failed stays, with the number that failed it.

## Entries

| file | what it holds |
|---|---|
| [keys_explained.md](keys_explained.md) | the ideas a programmer's defaults push against, from first principles with the engine's numbers: transitivity carried all the way, the impulse response, shift-and-add, unbounded operations in a small kernel, folding a check into a pass, exact arithmetic with no floor, the noise read and never modeled; transitivity across modules: no module reaches another, hand-offs as plain structs composed only in the entry |
| [compression_tower.md](compression_tower.md) | the integer lifting transform as one exact step recursed until the sample is one coefficient; zigzag and Rice coding in blocks and chunks, the file to the byte; the CRC-64 folded into the widen and the narrow, joined by GF(2) advance operators: the pixel-for-pixel test compressed in time |
| [imprint_key_cycle.md](imprint_key_cycle.md) | the atom; a program's impulse response as its kernel; kernels as shift-and-add masks; running a kernel over the set in one cycle |
| [noise_sieve_tower.md](noise_sieve_tower.md) | the transfinite noise sieve and the fluidic architecture, section by section against the engine: control and data planes, the kernel and lookup table, the lifting transform and noise floor −4, the drift and the node policies, the construct kit, identity as coherence, entropy |
| [wants.md](wants.md) | what the engine is after and does not have: the drafts' claims with no working form, and Doug's conjectures, each kept whole beside its open question |
| [noise_vector_integration_table.md](noise_vector_integration_table.md) | every noise term the detector is to read, one row each: how it moves, the exact sums that read it, its form in the sensor noise model, what the 44b6 set measured, its status, and the experiment that moves it |
| [engine_table.md](engine_table.md) | the machine part by part, held to no scale: its exact algebra, what each part does and wants, every hypothesis tried with its result, and the audit of every number that still fixes a scale |
| [query_protocol_table.md](query_protocol_table.md) | the query protocol step by step: what each step asks, the algebra it holds to, what it does and wants, what was tried and what it gave, and the run behind every status |
| [vertical_time_compression.md](vertical_time_compression.md) | the register machine's stacked lifting levels: what a stack is, what it compresses and leaves as it is, what bounds its file and its record, the heap and the ring across the levels of the forward and inverse lifting cascades, the coefficient vector as a code length and the lens, and what is proved, measured and derived about each |
| [two_crystals.md](two_crystals.md) | the register machine over the 2-adic integers: the wrap as a projection, the five operations that commute with every projection and the test that proves it, the exact quotient by an odd divisor as a 2-adic product, the bits the lifting reads, the two limits of the finite windows and the solenoid between them, what passes to a limit, the coefficient vector as a boundary measured on itself, the top projection and its limit ℝ, the p-adic integers ℤ_p for odd p and the places of ℚ, the count each limit keeps, and what the math derives about Doug's conjectures (the conjectures themselves are in [wants.md](wants.md)) |
| [kolmogorov_arnold.md](kolmogorov_arnold.md) | the Kolmogorov–Arnold representation theorem held exactly: where the engine already has its shape (the integer lifting, the residual, the binomial ladder as integer B-splines, the cycle's sums), why that is not a KAN (a KAN fits float splines and rounds; the engine fits nothing and rounds nothing), and what finishes it |
| [tessera_scheduler.md](tessera_scheduler.md) | the scheduler: how jobs from separate processes share one device by memory, the accounting and its invariant, measuring by pid on Linux and Windows, one daemon per host |
| [obsignatio_seal.md](obsignatio_seal.md) | the Merkle DAG of keyed BLAKE3 nodes over every compressed file and set, what it proves, what it costs, and where it stops |
| [build_plan.md](build_plan.md) | the order the engine's wants are built in, and every ruling on them, dated |
| [ledger.md](ledger.md) | every measurement of the engine, its tests and its sims, dated, in the order it was taken, with its samples and its result |
| [engine_boundary.md](engine_boundary.md) | two rulings on what the engine may hold, with their dates and what prompted them |
| [scriptura_blocks.md](scriptura_blocks.md) | the one rule on what scriptura's SWAR memory scans may be handed, and why it settles the over-read question |
| [dependent_projects.md](dependent_projects.md) | how the projects built on the engine take it: a git dependency pinned at a commit |
| [build_time.md](build_time.md) | what the time a build takes is spent on |

The runs the ledger cites are in `runs/`, and `data/stroke_cells.txt` is the stroke cells as data.
