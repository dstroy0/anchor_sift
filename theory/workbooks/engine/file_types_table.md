# Engine file types

Every file extension the engine and its projects write or read. A new extension is Doug's to name. Before one is
proposed, it is checked against this table and against the whole biohub tree, orior_python included.

## In use

| Extension | What it is | Named by |
|---|---|---|
| `.kcr` | The compressed file, named for Kolmogorov complexity: the engine's own compression format. It reads every source format, takes each format's own compression out, and can rebuild the data into any format (Doug). krep kind "KCR\0", version 1. The only compressed format. | Doug |
| `.krs` | A ruleset: how the emitter defines the forms in one language (`ptx.krs`, `c.krs`, `vhdl.krs`). | |
| `.kcs` | A construction set, part of the compressed file's flattener. | Doug |
| `.knf` | A sample's noise floor. | |
| `.ksh` | The flattened set: every segment of every sample as one number each (`train.ksh`). | |
| `.ans` | The answer file. | |

## Retired

| Extension | What it was |
|---|---|
| `.iapx` | The compressed format before `.kcr`. Not read; sets are re-ingested. |

## Offered, not adopted

| Extension | Offered for |
|---|---|
| `.kfc` `.kst` `.kgr` `.ksd` | The other apx files (flattened, OAPX history, BAPX bodies, IMP key); still open with Doug (build_plan.md). |
| `.khw` | A separate hardware constraints file. Withdrawn (Doug: file creep); the constraints are entries of the language's `.krs`. |
