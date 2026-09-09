# Crystallography

**Purpose:** Run a published cell from deposited text through to a checked answer, and see what each stage decides before the next one reads it.
**Scope:** `examples/crystallography/`

| stage | script | what it answers |
|---|---|---|
| `1_represent` | `a_cell_as_exact_points.py` | what the reader keeps and what it threw away |
| `2_partition` | `what_a_grid_costs.py` | what the voxel cost and what the scale bought |
| `3_reference` | `what_a_grid_invents.py` | how much of a reading a shuffle also reaches |
| `4_measure` | `period_from_the_difference_set.py` | what the instrument returns, with no answer key |
| `5_sift` | `lattice_breaks_the_product_rule.py` | how far the histogram bound is out on a lattice |
| `6_oracle` | `proof_positive_control.py` | whether it matches what somebody else published |

The subject was called `crystals` and was one stage deep, holding only the oracle. The reason recorded for the other five being absent was that parsing a CIF and tiling a right angled cell is domain knowledge and not a demonstration, so it belonged in the engine.

That was right about where the reader belongs and wrong about there being nothing to show. The reader was deciding the result. It put every site on a grid of 0.25 angstroms on the way in, and every crystal number in the ledger carried that grid instead of the deposit.

## Why this subject is where that shows

The Crystallography Open Database publishes the cell edge for every entry, so the periodicity is a number somebody else measured, refereed and wrote down before this instrument existed. It is the only positive control in this work with an answer nobody here produced.

Every control in the tree until the protein structures was a memoryless process, and one of those can only show that an instrument does not invent structure. It cannot show that an instrument finds structure that is present, and this work reported a protein as unstructured twice before that difference was drawn.

The same property makes a reader's own error visible here and nowhere else. Everywhere else the rounding happens against nothing to check it with.

## What the stages found

**453 of 453 axes over 151 structures now equal the published edge exactly.** Not inside a tolerance. Equal, as integers.

The previous reading of the same corpus recovered 453 of 453 axes *inside one voxel* at a mean absolute error of 0.0124 angstroms and a worst of 0.0554. None of that error was in the deposit or in the detector. Stage two isolates it: over 111 axes the grid reading lands inside one voxel every time and lands **on** the published edge zero times.

Stage two also sweeps the scale the exact reading is carried at. Every scale from 16 digits to 4096 returns the same 111 of 111 axes, because this path multiplies a coordinate by an edge once and the decimal places of the two operands simply add. At 8 digits one entry will not fit and at 4 digits twenty seven will not. Those raise instead of rounding, which keeps the loss from ever being quiet. How many digits a path needs is a property of its arithmetic and not of its source, and one multiplication is the cheapest case there is.

Stage three gives the background. Scattered points and shuffled elements both return exactly zero against a live count of 6. The whole of an exact lattice reading is therefore the lattice. The grid returns 0.79 live, 0.003 scattered and 0.39 with the elements shuffled. A cell holds two or three elements, and a permutation of them agrees at about one in k by counting alone, leaving about half of what the grid reported as a number a shuffle also reaches. That floor was never subtracted from any grid result here.

Stage four shows what the measure considers. There is no sweep and no ceiling. Every difference between two occupied coordinates is a candidate, and that set is complete, since a period agreeing with anything is by construction a difference between two things that agree. Over 24 axes the winner beat every candidate that was not a multiple of it, and on 23 of them nothing else agreed at all.

Stage five is the reading the old README said had not been done. The anchor cascade over a published cell survives at **3.85 times** the product of its anchors' rates, up to 30 times on one entry. The product rule assumes anchors are positioned independently and a lattice is the arrangement where they are least so. It stays a necessary condition either way, since everything holding the pattern still survives.

The crystal case is also the only one where the cascade needs no tolerance. A protein is a cloud of real valued coordinates, so two occurrences of one motif never land on identical offsets, and `examples/proteins/5_sift` extends a tolerance of one voxel in each direction to get any match at all. Here a displacement either lands on an occupied place or does not.

## The first attempt at this was built wrong twice

The exact reading was first written as a separate file under `data/`, reimplementing the CIF parse and the tiling that `representation/structure/crystal.py` already did. That is a second copy of the reader, and a second copy is one edit away from disagreeing with the first about what a deposit says.

It was then a scratch script instead of an engine change. That fixed one measurement and left every other domain reading through the bound that caused it. The bound sat in the base primitive, making it every domain's.

Both are corrected. `representation/exact.py` is the ingestion primitive, domain blind, and `crystal.py` is a front end over it that knows what a CIF is.

## Running one

```
python examples/crystallography/6_oracle/proof_positive_control.py
python examples/crystallography/4_measure/period_from_the_difference_set.py 25
```

The oracle fills `build/cod` from the archive and everything else reads that cache. The archive is a public service run by people; a second run costs it nothing and the pause between requests is not negotiable.

Stage three is the slow one. Its grid arm compares a full 320 cubed volume at every lag, three times per entry. The exact arm does not pay that cost.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-09
