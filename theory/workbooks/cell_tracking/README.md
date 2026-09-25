# The workbook is the ledger

**Purpose:** One place where every idea the cell program rests on is written down beside what stands behind it, so a later session knows at a glance which claims are proved, which are measured, which are built but unmeasured, and which are still only theory.
**Scope:** `workbooks/cell_tracking/`. The thought experiment that sets the sieve on the cell program is in `thought_experiments/cell_tracking/`. The machine the program runs on is the engine workbook, `workbooks/engine/`.

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
| [cell_tracking_table.md](cell_tracking_table.md) | the cell program's n-body problem part by part: the physics, what the program does for each part, what it wants, every hypothesis tried with its result, the driver's stages, and the tracker's equation as reads of the machine |
| [on_the_engine.md](on_the_engine.md) | what the engine's books measured on the cell program's samples, and the sieve's sections that set it on the cells |
| [build_plan.md](build_plan.md) | the order the cell program's wants are built in, and every ruling on them, dated |
| [ledger.md](ledger.md) | every measurement of the tracker and its driver, dated, in the order it was taken, with its samples and its result |
| [scan_then_sort.md](scan_then_sort.md) | the rule that orders the driver: every frame of every sample scanned first, sorting only at the end |
| [walk_back.md](walk_back.md) | the rule every tracker stage is held to: it can be walked back to what it came from |
| [build_right_first.md](build_right_first.md) | the rule against building an interim version already known to need redoing |
| [records.md](records.md) | the commit texts written for the cell program, dated, as they were written |
