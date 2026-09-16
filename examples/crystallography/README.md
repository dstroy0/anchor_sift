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
| `4_measure` | `doping_after_symmetry_expansion.py` | the same count over the whole cell, by mineral family |
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

### How complex the doping gets

Two elements on one position is the ordinary case and it is not the interesting one. Reading one
cell each across the corpus, 705 positions hold two elements, 34 hold three, and the tail runs to
**one position holding ten**: `Ce/Dy/Er/Gd/La/Nd/Pr/Sm/Y/Yb`, a rare earth site that took whichever
lanthanides were in the melt. Three separate spinels hold seven at once, `Al/Cr/Fe/Mg/Ni/Ti/V`.

Counting distinct substitution types per deposit rather than per position, 135 entries carry one and
**83 carry two at once**. Two at once is a coupled substitution, which is how a lattice swaps ions of
unequal charge and stays balanced: the plagioclase series runs Al for Si on one site against Ca for
Na on another, and neither half works alone. The measure was not told that and has no charges in it.

### Symmetry expansion counts more places and finds no more doping

A CIF publishes the asymmetric unit and the operations that generate the rest of the cell.
`doping_after_symmetry_expansion.py` applies them and counts again.

Over 2853 readable entries the shared positions go from 3424 to 20893, about six times as many, and
nearly all of that rise is arithmetic: a symmetry copy of a site the asymmetric reading already
found. Nearly all. **Two entries hold a shared position that exists only after expansion**, and they
are worth more than the ratio is.

`1001125` puts Ta at (1/2, 1/2, 0.238) and W at (1/2, 1/2, -0.238). An operation taking z to -z
carries one onto the other. Tantalum and tungsten substitute readily, so this is an ordinary solid
solution that the asymmetric unit does not show.

`1509166` puts O at (0, 1/2, 0) at full occupancy and Ag at (1/2, 0, 1/2) at half, in `I 4/m m m`.
The I centring carries the first exactly onto the second, so an anion and a cation share one orbit
summing to one and a half atoms on a site that holds one. That is not chemistry. It is a defect in a
published deposit, and nothing short of expansion surfaces it.

So expansion is a detection, on 2 entries in 2853. A poor detector by rate, and the right tool for
what it finds.

### This section said zero, and the corpus falsified it

At 1228 entries the count was 0 and this README asserted that expansion never detects, only counts.
At 2801 it was 5. Three of those five were an artefact: deposits mark an undetermined position with
the sentinel `-1` and the flag `dum`, which reduces into the cell at the origin and collides with
whatever real atom sits there. Dickinson's 1920 wulfenite (`1011170`) writes its unsolved oxygen that
way, and the reading reported Mo and O sharing a site. A cation and an anion cannot occupy one place,
and that impossibility is how the artefact announced itself. `crystal.site_table` now drops `dum`
rows and the two survivors above are the real answer.

Both halves are worth keeping. A claim of zero held for 1228 entries and was false. A count of five
looked like a finding and was mostly a parser reading a placeholder as an atom.

The expansion is exact, and that took a second scale. A translation of 1/3 is not a decimal at any
number of places, because 10^n factors into twos and fives and three divides neither. An R centred
operation is full of thirds and the corpus is full of R-3. Carrying those through the decimal scale
would displace every copy they generate, so a symmetry copy would land beside the atom it should
have landed on rather than on it, and the doping at that place would vanish silently. Coordinates in
`representation/structure/symmetry.py` are therefore integers in units of 1/(24 · 10^1024), and an
operation whose denominator does not divide 24 raises instead of rounding. Across the corpus nothing
raised: 24 held every operation the deposits published, eighths included.

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
