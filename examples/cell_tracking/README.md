# Cell tracking

**Purpose:** Run the cell tracking measurements end to end, and know what each one has and has not
established before quoting any number from it.
**Scope:** `examples/cell_tracking/`, `maint/data/fetch/fetch_ctc.py`,
`repos/external/datasets/`.

## What you need

Python 3 with `numpy`. Nothing else. No GPU, no CUDA, no build step. Every file here is a script
run by path and every figure below comes back in seconds on a laptop.

The dataset fetcher needs network access. The measurements below do not: they run on fields this
tree generates, whose answer is known before the measurement because this tree chose it.

## Run everything, in order

Each file answers one question and prints a table. Run them in this order, because each one corrects
the file above it and the corrections are the findings.

```sh
python examples/cell_tracking/2_partition/what_a_pixel_costs.py
python examples/cell_tracking/2_partition/where_the_floor_comes_from.py
python examples/cell_tracking/3_reference/what_a_shuffle_returns.py
python examples/cell_tracking/4_measure/where_the_coarms_stop_paying.py
```

| file | catalog | what it asks | what it reports |
|---|---|---|---|
| `1_represent/how_far_a_cell_moves.py` | CEL-1-001 | how big is a cell and how far does it move | 49 px across, 3.5 px a frame, 59 of 95 tracks born of division |
| `2_partition/what_a_pixel_costs.py` | CEL-2-001 | does a sub-pixel displacement survive the grid | 0.1479 px against 0.2222 px for rounding, at 6 px features |
| `2_partition/where_the_floor_comes_from.py` | CEL-2-002 | is the floor the feature width or the mechanism | error is about width/40, so the width |
| `3_reference/what_a_shuffle_returns.py` | CEL-3-001 | does the reading depart from a permutation null | moved axis concentrates 57x more than a still one |
| `4_measure/where_the_coarms_stop_paying.py` | CEL-4-001 | how many co-arms, and how far to sweep lags | 1.28x from co-arms, flat from 4 to 16, collapses at 64 |
| `4_measure/what_the_levels_buy.py` | CEL-4-002 | how many levels to read intensities at | optimum at 256, which is eight bits; 32 cost a factor of 2.2 |
| `6_oracle/entropy_before_a_division.py` | CEL-6-001 | does a division move a cell's own entropy | yes, and signed: the daughters together read 0.29 bits BELOW the parent, 89% of the time, 73.7 floors out |

`1_represent` and `6_oracle` need the dataset. The rest are synthetic and need nothing.

## The datasets

```sh
python maint/data/fetch/fetch_ctc.py                      # the manifest and the totals, fetches nothing
python maint/data/fetch/fetch_ctc.py --tier perfect       # the four with exact masks
python maint/data/fetch/fetch_ctc.py --fetch Fluo-N2DH-SIM+
python maint/data/fetch/fetch_ctc.py --tier all --test --skip Fluo-N3DL-TRIF
```

A bare run prints the table and downloads nothing, deliberately. The full set is 855.3 GB and
`Fluo-N3DL-TRIF` alone is 769 GB across both arms, which does not fit on a 500 GB volume. The
fetcher refuses a selection larger than the free space, and stops before any single file that would
leave under 20 GB of headroom.

Files land in `repos/external/datasets/` with flat names, outside every repository. That directory
is not a git repository, so nothing there can be committed by accident.

**No measurement in this directory has been run against those datasets yet.** Everything above is
synthetic.

## What is established, and what is not

**Established.** A sub-pixel displacement survives the pixel grid, in part. The residual is set by
feature width at roughly width/40 and is not scatter: it is largest at whole-number displacements
and near zero at the half. A displacement makes independent regions of one field agree on it, and a
permutation of the same field cannot make them agree, which separates an axis that moved from one
that did not by a factor of 57.

**Not established.** Anything about cells. Every field here is Gaussian blobs on a flat background
with no division, no occlusion, no intensity drift and no motility mode switching. A pass here is a
necessary condition for the method to work on microscopy and nowhere near a sufficient one.

**Withdrawn.** Three readings, kept in the files that made them because each looks like a result:

1. That the sub-pixel fraction transfers from `examples/crystallography` at full strength. It does
   not. The crystal mechanism accumulates a fraction over a tile series and two frames supply one
   displacement and no series, so the figure is 1.5x over rounding and not four hundred.
2. That the cross-axis reading of 0.47 px is a floor the method carries. It is what this measure
   returns when handed no arrangement, and the control was passing.
3. That co-arms buy 3.5x. They buy 1.28x. The 3.5x compared a single displacement of 3.4, which
   sits near the half where the fraction is most accurate, against a mean over nine displacements.
   The difference was the comparison and not the co-arms.

**Bounds that were swept and found to be doing nothing.** The lag reach, set to 8 and then 12 in two
files with no reason given for either, returns identical figures at 5, 8, 16 and 32.

## Reproducing a figure

Every number in the table above is printed by the file beside it, with no arguments and no
configuration. `SEED` is fixed at `0x51F7` in `2_partition/what_a_pixel_costs.py` and every other
file imports it, so two runs on two machines return the same digits.

To change what is swept rather than what is measured, edit the module-level tuples: `TRUTHS` and
`LEVELS` in `what_a_pixel_costs.py`, `WIDTHS` in `where_the_floor_comes_from.py`, `COUNTS` and
`REACHES` in `where_the_coarms_stop_paying.py`. They are tuples at the top of each file for that
reason.

## The book

`theory_bucket/cell_tracking/` holds the argument. It is authored there rather than here because
`theory/` in this repository is a dependency mount point with one owner, and reaches a checkout of
this repository as `theory/cell_tracking`.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
