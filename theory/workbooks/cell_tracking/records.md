# Records

**Purpose:** The commit texts written for the cell program, dated, as they were written. The reasons for each change travel with the workbook.
**Scope:** commits to cell_tracking main, each with its hash and its time (UTC−4). A commit's subject is its heading and its message follows. The engine's texts are in the engine workbook's records.md.

## 25 September

### 08:26, 0523a6e: theory: the driver's stages, OrganoidTracker and Hawkins into them, and the residual at any width

The cell program's part of the commit's text. Its paragraph on the engine table's M2 is the engine's, in the engine workbook's records.md.

```text
The cell table's driver section now holds the walk-back rule and the
stages S0 to S11. S0 is the set's intensities: a per-sample affine
footing whose bounds converge by two-means from OrganoidTracker's 1% and
99%, and the set's cumulative count as the contrast. Neither clips, and
both walk back exactly. OrganoidTracker's techniques, O1 to O22, read
from the vendor reference, each go to the stage they land in, exact and
with nothing chosen. Hawkins et al. 2025 (the pronephros progenitor
kinetics) adds H1 to H6: asymmetric division, fate change without
division, near-zero death, the population balance, rates read from
counts, and the null in place of LRT and AIC.

S0 and S1 are built and measured on the 25: 10,485,760,000 readings,
the contrast 34 bits, the residual 10 limbs, 6,518,615 points. Every
.points holds the set's C and passes a separate reader.
```

Note, 26 September: the separate reader was not kept. `points_check` (`cell_tracking/src/check/points_check.c`) is kept in its place. Run on the 25 samples of `scan.set`, as `points_check D:/kaggle_project_data/biohub_cell_tracking_set_kcr/train 44b6_0113de3b ... 44b6_668e0cc7`, it rebuilt 10,485,760,000 readings and 34 bits from the summed `.readings`, the same as `scan.set`, and printed "checked 25 samples, 25 with no fault, 6518615 points" and "0 faults". `cell_tracking/test/check_test.sh` fires each of its 16 faults: 39 checks, 0 failed.
