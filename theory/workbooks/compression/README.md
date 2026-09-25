# The workbook is the ledger

**Purpose:** One place where every idea the compression floor rests on is written down beside what stands behind it, so a later session knows at a glance which claims are proved, which are measured, which are built but unmeasured, and which are still only theory.
**Scope:** `workbooks/compression/`. The coder and the seal are machine parts, in the engine workbook, `workbooks/engine/` (M9 and M13 of its engine_table.md).

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
| [compression_table.md](compression_table.md) | the crystal's size set by set against the floor the data allows: the ladder of exact bounds from raw to the noise floor, every coder variant tried, and the order to close the gap |
| [build_plan.md](build_plan.md) | the compression items of the build plan, dated |
| [ledger.md](ledger.md) | every measurement of the .iapx codec, its variants and the floor it answers to, dated, in the order it was taken, with its samples and its result |
