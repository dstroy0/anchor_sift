# The workbook is the ledger

**Purpose:** One place where every idea the engine rests on is written down beside what stands behind it, so a later session knows at a glance which claims are proved, which are measured, which are built but unmeasured, and which are still only theory.
**Scope:** `workbooks/engine/`. The thought experiments the engine's theory was carried from are in `thought_experiments/engine/`. The compression floor is its own workbook, `workbooks/compression/`, and the cell program is `workbooks/cell_tracking/`.

## How an entry is kept

Every claim carries one status, and the status says what backs it:

| status | what it means |
|---|---|
| **proved** | an exact check ran over the whole set and found no exception; the count is given |
| **measured** | a number was taken on named samples; the number is given, and whether it held up |
| **built** | the code exists and runs; no measurement yet says whether it helps |
| **theory** | stated, not built |
| **refuted** | measured, and the measurement went against it; kept, with the number, so it is not tried again blind |
| **not so** | fails on its own arithmetic or in any machine, before anything is measured; kept, with the reason |

A claim changes status only when a run changes it, and the run is named. Nothing is deleted from the ledger. An idea that failed stays, with the number that failed it.

## Entries

| file | what it holds |
|---|---|
| [keys_explained.md](keys_explained.md) | the ideas a programmer's defaults push against, from first principles with the engine's numbers: transitivity carried all the way, the imprint, AND and add, unbounded operations in a small key, folding a check into a pass, exact arithmetic with no floor, the noise read and never modelled |
| [imprint_key_cycle.md](imprint_key_cycle.md) | the atom; imprinting a program onto the impulse; keys as AND masks; running a key over the set in one cycle |
| [noise_sieve_tower.md](noise_sieve_tower.md) | the transfinite noise sieve and the fluidic architecture, section by section against the engine: control and data planes, the key and LUT, the tower and floor −4, the demon's eyes and arms, the construct kit, identity as coherence, entropy |
| [engine_table.md](engine_table.md) | the machine part by part, held to no scale: its exact algebra, what each part does and wants, every hypothesis tried with its result, and the audit of every number that still fixes a scale |
| [vertical_time_compression.md](vertical_time_compression.md) | the record machine's stacked floors: what a stack is, what it compresses and leaves as it is, what bounds its file and its record, the heap and the ring across the floors of the two towers, the crystal as a code length and the lens, and what is proved, measured and derived about each |
| [two_crystals.md](two_crystals.md) | the record machine over the 2-adic integers: the wrap as a projection, the five operations that commute with every projection and the test that proves it, the exact quotient by an odd divisor as a 2-adic product, the bits the lifting reads, the two limits of the finite windows and the solenoid between them, what passes to a limit, the crystal as a boundary measured on itself, the top projection and its limit ℝ, the odd crystals and the places of ℚ, the count each crystal keeps, and Doug's posits bounded |
| [kolmogorov_arnold.md](kolmogorov_arnold.md) | the Kolmogorov–Arnold representation theorem held exactly: where the engine already has its shape (the tower's lifting, the residual, the binomial ladder as integer B-splines, the cycle's sums), why that is not a KAN (a KAN fits float splines and rounds; the engine fits nothing and rounds nothing), and what finishes it |
| [tessera_scheduler.md](tessera_scheduler.md) | the scheduler: how jobs from separate processes share one device by memory, the accounting and its invariant, measuring by pid on Linux and Windows, one daemon per host |
| [obsignatio_seal.md](obsignatio_seal.md) | the seal: the dimensional Merkle DAG of keyed BLAKE3 nodes over every crystal and set, what it proves, what it costs, and where it stops |
| [build_plan.md](build_plan.md) | the order the engine's wants are built in, and every ruling on them, dated |
| [ledger.md](ledger.md) | every measurement of the engine, its tests and its sims, dated, in the order it was taken, with its samples and its result |
| [engine_boundary.md](engine_boundary.md) | two rulings on what the engine may hold, with their dates and what prompted them |
| [scriptura_blocks.md](scriptura_blocks.md) | the one rule on what scriptura's SWAR memory scans may be handed, and why it settles the over-read question |
| [peer_sessions.md](peer_sessions.md) | how other sessions that build on the engine take it: a git dependency pinned at a commit |
| [build_time.md](build_time.md) | what the time a build takes is spent on |
| [records.md](records.md) | the commit and pull request texts written for the engine, dated, as they were written |

The runs the ledger cites are in `runs/`, and `data/stroke_cells.txt` is the stroke cells as data.
