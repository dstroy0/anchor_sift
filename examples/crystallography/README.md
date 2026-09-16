# Crystallography

**Purpose:** Run a published cell from deposited text through to a checked answer, and see what each stage decides before the next one reads it.
**Scope:** `examples/crystallography/`

| stage | script | what it answers |
|---|---|---|
| `1_represent` | `a_cell_as_exact_points.py` | what the reader keeps and what it threw away |
| `2_partition` | `what_a_grid_costs.py` | what the voxel cost and what the scale recovered |
| `3_reference` | `what_a_grid_invents.py` | how much of a reading a shuffle also reaches |
| `4_measure` | `period_from_the_difference_set.py` | what the instrument returns, with no answer key |
| `4_measure` | `doping_from_shared_sites.py` | which sites hold two elements, read by incidence alone |
| `5_sift` | `lattice_breaks_the_product_rule.py` | how far the histogram bound is out on a lattice |
| `6_oracle` | `proof_positive_control.py` | whether it matches what somebody else published |
| `6_oracle` | `doping_against_deposited_occupancy.py` | whether the doping found agrees with a column it never read |

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

## Doping is in the motif, and the period never sees it

A substitutional dopant is two elements written at one crystallographic position. That is a
statement about incidence, so the instrument that reads it is the same one that reads everything
else here: `representation.exact.contested` returns the positions carrying more than one value, and
it is domain blind. In a text that is one index holding two symbols. In a structure it is a doped
site.

Nothing about the cell is read to find one. No edge, no angle, no tiling, no conversion to
angstroms. Two sites share a position when the deposit wrote the same three fractional coordinates
twice, and that is decided by equality on exact integers.

**Over 1200 deposits, 712 shared positions were found in 214 entries, and all 712 are physically
consistent with the occupancy column the detection never opened.** 625 sum to a full site, which is
pure substitution. 87 sum to less than a full site, which is substitution over a position that is
also partly vacant. None sums to more than a full site, which would be more atoms than the position
holds. Every one of the 1200 was readable; 17 individual sites were skipped for a coordinate that is
not plain decimal text.

The count that would have falsified the reading is zero: **no shared position has every element
published at full occupancy.** A deposit claiming two elements are both entirely present in one
place would contradict either the reading or itself, and none does.

The result did not soften as the corpus grew. At 758 entries it was 126 of 126, at 999 it was 408
of 408, and at 1200 it is 712 of 712. Tripling the detections moved nothing.

The converse is the half that is easy to lose. 1244 positions carry a single element under full
occupancy. Those are vacancies and not doping. Nothing substitutes there, the atom is simply
absent some of the time. A detector that called every occupancy under 1 a dopant would be wrong on
all 1244, and they outnumber the doped positions by nearly two to one.

What the substitutions are is not something the measure was told. Folding charge and case together,
the corpus is led by Al/Si at 444, then Ca/Na at 66, Fe/Mg at 30 and K/Na at 28. Al/Si with Ca/Na is
the plagioclase coupled substitution and Al/Si with K/Na is the alkali feldspar series, which is to
say the two most common substitutions in the crust came out on top of a reading that knows no
chemistry and never looked at a cell.

Doping does not disturb the recovered period, and the reason is structural rather than lucky. The
cell repeats whatever it contains, dopant included, so the lattice is untouched. An ideal doped
crystal is still exactly periodic, and stage four's two measures read two different things out of
one set of points.

### What that cost to learn

The first version of the doping measure went through `crystal.exact_points`, and inherited a
dependency it had no use for. `exact_points` refuses any cell that is not right angled, and the
minerals that carry doping are overwhelmingly monoclinic and triclinic, so 498 of 697 entries came
back unreadable. The measure looked like it was failing on three quarters of the corpus. It was
being handed three quarters less corpus. Reaching for the smallest reading that answers the
question fixed it, and the same run then read every entry.

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

Stage three is the slow one. Its grid arm compares a full 320 cubed volume at every lag, three times per entry. The exact arm does not have that cost.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-09
