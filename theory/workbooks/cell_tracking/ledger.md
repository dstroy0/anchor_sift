# Ledger

**Purpose:** Every measurement, in the order it was taken, with the samples it ran on, the number, and what it settled, so no result is taken twice and none is quoted without its run.
**Scope:** runs of the tracker and its driver, and their scores. Samples are named by their id; "the 25" means the first 25 44b6 training samples by name. Logs are under `cell_tracking/logs/`.

## 2026-09-21

### The driver split

| what | samples | result | settles |
|---|---|---|---|
| the split driver (22 functionals, now under `engine/` and `cell_tracking/src/`) against the driver before the split | 44b6_0113de3b, 44b6_0b24845f | edges, object files and every score line byte identical | the split changed nothing (proved) |

## 2026-09-22

### The module move and the root layout

| what | samples | result | settles |
|---|---|---|---|
| the driver from the new layout, run from the root, against the driver before the split | 44b6_0113de3b, 44b6_0b24845f | edges and score rows identical; object files identical but for the embedded .cfg naming the new paths | the move changed nothing (proved) |

### The competition metric

The metric (`maint/score_submission.py`): nodes matched to key nodes within 7 µm, an edge a hit only where both ends match nodes the key joins, the edge Jaccard micro averaged over the split, times 1 − 0.1 × the node count's excess over the organisers' estimate, plus 0.1 × the division Jaccard. It is not the internal count the tracker prints under POOLED, which takes a key node as the object that holds its voxel.

| what | samples | result | settles |
|---|---|---|---|
| components mode dump (an older mode), best policy (the 400 largest per frame) | 13 of the 44b6 | SCORE 0.2376; edge Jaccard 0.238; TP 713, FP 467, FN 1,815 | the internal 98% does not carry over to the metric |
| same dump, every node | 13 of the 44b6 | 60.4% of key edges lost because the source key node has no predicted node within 7 µm; 1.5% land elsewhere | that dump's loss is detection, not linking; the dump is an older mode and must be redone on the current engine |

### The 6bba samples

The training set is 71 samples of 44b6 and 128 of 6bba; the test set holds both. Every run until now was on 44b6. 6bba's keys are far denser (345 to 1,183 edges a sample, against about 50 to 270 for 44b6), so under micro averaging 6bba carries most of the score.

| what | samples | result | settles |
|---|---|---|---|
| the current engine, internal count | 6bba_05b6850b, 05db0fb1, 062c8d37, 07477033, 07e24132 | 3,756 of 3,873 edges correct, 97.0%; 115 wrong; 2 endpoints undetected | the engine runs on 6bba as it is |
| the same run under the metric's matching, every node | the same five | 78.5% of key edges hit; 1.2% source unmatched; 19.6% land elsewhere, a median 6.7 µm from the target's match | on 6bba the loss is a link landing on a neighbouring node: the node set is far finer than the cells, and bodies, not finer pieces, are what should be linked |

### 44b6 on the current engine

| what | samples | result | settles |
|---|---|---|---|
| internal count | the 25 | 6,254 of 6,358 edges correct, 98.4%; 104 wrong | |
| the metric's matching, every node | the 25 | 87.1% of key edges hit; 1.1% source unmatched; 10.9% land elsewhere, a median 5.75 µm off | the older components dump's 60% unmatched was that dump, not the engine |
| SCORE, the 400 largest nodes a frame | the 25 | 0.661: edge Jaccard 0.670, node count factor 0.986 (1,000,000 nodes against 880,906 estimated) | the node count is the lever: every node gives Jaccard 0.635 but 5.8 million nodes, and the score falls to 0.279 |
