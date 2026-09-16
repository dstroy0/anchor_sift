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

**That figure was measured on twelve structures and it does not survive the whole cache.** Over 3639 structures it is 0.97, and the section below says why the two numbers are both correct and why neither should be quoted alone.

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

### Every figure below is measured at one moment, and the moment is named

**Corpus of 6727 to 6730 deposits, measured 2026-09-16 16:07 UTC.** The range is not sloppiness: the
fetch was still running and three entries arrived during the fourteen seconds the two measures took.
Every number in this section comes from that one snapshot, so they can be compared with each other.
None of them is final, and the growth series below says why that matters.

| | |
|---|---|
| entries read | 6659 |
| entries with no atom site loop | 68 |
| entries carrying at least one shared position | 2019, which is 30.3% |
| shared positions found by incidence | 6662 |
| of those, sum to a full site, pure substitution | 5479 |
| sum to less than a full site, substitution over a partly vacant position | 1117 |
| sum to **more** than a full site, more atoms than the position holds | **66** |
| physically consistent | 6596 of 6662, 99.0% |
| every element published at full occupancy | 9 |
| single-element positions under full occupancy, declined as vacancies | 10460 |

The detector and the oracle report 6655 and 6662 shared positions from the same corpus, and the
difference is the detector's early return: it treats an entry whose coordinates all fail to parse as
unreadable, and the oracle does not.

### The growth series, which is the point rather than a caveat

The same measurement over a growing corpus:

| corpus | shared positions | physically consistent |
|---|---|---|
| 758 | 126 | 126, all |
| 999 | 408 | 408, all |
| 1200 | 712 | 712, all |
| 3744 | 4352 | 4301, with 51 over a full site |
| 6730 | 6662 | 6596, with 66 over a full site |
| 7414 | 7208 | 7136, with 72 over a full site |

This section previously read "the result did not soften as the corpus grew ... tripling the
detections moved nothing", written at 1200. **It softened.** Perfect consistency held to 1200 entries
and stopped holding somewhere before 3744, and the honest statement is not that the earlier claim was
wrong but that it was a true measurement of a range, quoted as though the range were the world.

That is a stronger result than the original, not a retreat from it. A detector that holds across
1200 deposits and then meets 66 deposit defects at 6730 is an instrument meeting a real corpus. The
original framing had no room for that outcome, which is what was wrong with it.

### What the inconsistent positions are

A shared position where every element is published at full occupancy contradicts either this reading
or the deposit. Every one inspected has been the deposit. COD 1011256, from 1933, writes

    Si1 Si4+ 8 d 0.25 0.25 0.875 1.
    Al1 Al3+ 8 d 0.25 0.25 0.875 1.

Identical coordinates, identical Wyckoff letter, both at full occupancy: sixteen atoms on eight
places. It is how an older deposit describes a disordered site, naming both partners without
normalizing. The coordinates matching character for character is what rules out the reading and
leaves the deposit.

**That count was described here as the one that would falsify the reading, and that was a badly
built test.** A number whose appearance is supposed to settle a question cannot settle it when both
answers produce the same number. Naming a falsifier without naming what distinguishes it from the
alternative leaves a test that looks decisive and is not. What distinguishes them is reading the
deposit, and 1.0% of shared positions in this corpus are deposits disagreeing with themselves rather
than an instrument disagreeing with them.

The converse is the half that is easy to lose. 10460 positions carry a single element under full
occupancy. Those are vacancies and not doping: nothing substitutes there, the atom is simply absent
some of the time. A detector that called every occupancy under 1 a dopant would be wrong on all
10460, and they outnumber the shared positions by more than three to two.

What the substitutions are is not something the measure was told. Folding charge and case together,
the corpus is led by Al/Si at 1838, then Ca/Na at 403, Fe/Mg at 368, Al/Fe/Mg at 184 and Al/Fe/Mg/Ti
at 146. Al/Si with Ca/Na is the plagioclase coupled substitution, which is to say the most common
substitution in the crust came out on top of a reading that knows no chemistry and never looked at a
cell.

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

At the same snapshot, 6668 readable entries, the shared positions go from 6667 to 50188, **7.53 times
as many**, and nearly all of that rise is arithmetic: a symmetry copy of a site the asymmetric
reading already found. Nearly all. **Three entries hold a shared position that exists only after
expansion**, and they are worth more than the ratio is. Two are described below; the third appeared
with the corpus past 3744 and has not been inspected.

6612 of those entries publish symmetry operations, none was refused for a denominator not dividing
24, and none was held back by the placement bound.

`1001125` puts Ta at (1/2, 1/2, 0.238) and W at (1/2, 1/2, -0.238). An operation taking z to -z
carries one onto the other. Tantalum and tungsten substitute readily, so this is an ordinary solid
solution that the asymmetric unit does not show.

`1509166` puts O at (0, 1/2, 0) at full occupancy and Ag at (1/2, 0, 1/2) at half, in `I 4/m m m`.
The I centring carries the first exactly onto the second, so an anion and a cation share one orbit
summing to one and a half atoms on a site that holds one. That is not chemistry. It is a defect in a
published deposit, and nothing short of expansion surfaces it.

So expansion is a detection. A poor detector by rate, and the right tool for what it finds.

### The count is 3 as of a moment, and the moment is the point

**3 of 6668 entries, measured 2026-09-16 16:07 UTC, with the corpus still filling.** Not 3 as a
settled fact. The same measurement has read four values:

| corpus | count | why it was that |
|---|---|---|
| 1228 entries | 0 | the real cases were not in the corpus yet |
| 2801 entries | 5 | three of the five were a parser artefact |
| 2853 entries | 2 | artefact removed, two real cases remain |
| 6668 entries | 3 | a third arrived with the corpus, not yet inspected |

Each was correct for its corpus and its parser. A reader learns more from the sequence than from the
final value, because the sequence says what the measurement is sensitive to: corpus size found the
real cases, and a parser defect invented three others.

The artefact is worth naming. Deposits mark an undetermined position with the sentinel `-1` and the
flag `dum`, which reduces into the cell at the origin and collides with whatever real atom sits
there. Dickinson's 1920 wulfenite (`1011170`) writes its unsolved oxygen that way, and the reading
reported Mo and O sharing a site. A cation and an anion cannot occupy one place, and that
impossibility is the only thing that announced it: no consistency check and no schema would have.
`crystal.site_table` drops `dum` rows now.

Dropping them changed what every exact reading in this subject ingests, so both published figures
were re-read with `dum` kept and dropped over all six entries that carry one. No recovered period
moved and no agreement with a published edge flipped: **453 of 453 and 1455 of 1455 both stand.**
The reason is structural rather than lucky, and it is the boundary rather than the reassurance. A
spurious atom at the origin is tiled into every copy of the cell, so it shifts every plane the same
way and leaves the agreeing lags unchanged. A period is a statement about repetition and a defect
that repeats perfectly does not disturb it. A count, a density or any distance would have moved.

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

### The lesson was applied to stages four and six and not to stage five

Stages four and six read `crystal.exact_sites`, which works in fractional space and consults no cell
and no angle. Stage five still reads `crystal.exact_points`, at
`examples/crystallography/5_sift/lattice_breaks_the_product_rule.py:142`, so it still pays the cost
the section above describes. A refused entry returns `(None, None)` and the loop does `continue`, and
the closing line then reports a median over whatever survived with nothing on the page naming the
denominator.

`maint/analysis/survey/crystal_gate_census.py` counts what that costs. **Measured over `build/cod`
2026-09-16, 7459 entries at that moment:**

| verdict | entries | share |
|---|---|---|
| admitted to the exact reading | 3708 | 49.7% |
| refused, cell not right angled | 3747 | 50.2% |
| refused, no cell published | 4 | 0.1% |
| refused, no atom sites | 0 | 0.0% |
| refused, coordinate not plain decimal | 0 | 0.0% |

Half is the least interesting number here. The refusal is not spread evenly over the corpus, because
a right angle is a property of the crystal system and the crystal system is not independent of the
mineral family the fetch searched under:

| family | entries | admitted | share |
|---|---|---|---|
| garnet | 393 | 385 | 98.0% |
| spinel | 592 | 569 | 96.1% |
| melilite | 131 | 125 | 95.4% |
| olivine | 450 | 429 | 95.3% |
| perovskite | 167 | 152 | 91.0% |
| carbonate | 154 | 8 | 5.2% |
| tourmaline | 283 | 13 | 4.6% |
| amphibole | 307 | 13 | 4.2% |
| apatite | 286 | 7 | 2.4% |
| feldspar | 128 | 3 | 2.3% |

So a stage five figure over this cache is a figure about its cubic and orthorhombic half. Feldspar
contributes 3 entries out of 128 and amphibole 13 out of 307, and neither absence appears anywhere in
the output. `DEVELOPMENT_RULES` names this case: a check that cannot fail closed has to be one whose
failure is distinguishable from its answer, and zero findings over a root that vanished is a defect
and not a pass. The census exists so the denominator can be quoted beside the result.

Whether the gate should be lifted is a separate question and it is argued in
`PROPOSALS/CRYSTAL_EXACT_PATH_RIGHT_ANGLE_GATE.md`. This measures the gate and does not answer that.

### The product rule fails in both directions, and the default limit only ever showed one

`examples/crystallography/5_sift/lattice_breaks_the_product_rule.py` stops at 12 structures unless a
count is passed. **Run over the whole cache 2026-09-16 it reads 3639 structures and draws 145560
needles, and its closing median is 0.97.** At 12 structures that median is 4.33 and at 40 it is 4.53.

3639 is the second denominator this stage drops quietly. The census above admits 3708 entries to the
exact reading, and the run reports 3639, because a structure from which no needle can be drawn hits
`if not ratios: continue` and leaves no trace in the output. The 69 entries between the two numbers
are not failures of the cascade and they are not successes either. They are entries it never asked a
question of.

The median did not drift. It is reporting a mixture of two populations that fail the product rule in
opposite directions, and `maint/analysis/survey/sift_ratio_by_elements.py` separates them:

| population | structures | median of per-structure medians | share above 1 |
|---|---|---|---|
| one element | 1959 | 0.32 | **0.0%** |
| more than one element | 1680 | 5.91 | **95.4%** |
| every structure | 3639 | 0.98 | 44.0% |

The separation is total. Not one of the 1959 single-element structures has a median above 1, and
95.4% of the multi-element ones do. By element count:

| elements | structures | median of medians |
|---|---|---|
| 1 | 1959 | 0.32 |
| 2 | 127 | 3.84 |
| 3 | 445 | 6.13 |
| 4 | 505 | 6.08 |
| 5 | 327 | 7.77 |
| 6 | 135 | 7.67 |
| 9 | 24 | 9.25 |
| 10 | 23 | 9.55 |

The mechanism is stated in that tool's header and it is two different faults wearing one number. An
anchor is `element E at displacement d` and the rule credits it with the rate at which E occurs. In
a structure holding one element every anchor matches compositionally at every occupied place, each
rate is 1, and the rule predicts nothing is filtered. What filters an alignment there is whether the
displacement lands on an occupied place at all, which is geometry the rule does not model, so it
over predicts and the ratio falls under 1. In a structure holding several elements the rates are
genuinely below 1 and the rule's other assumption fails instead: it takes the anchors to be
positioned independently, and a lattice is where they are least so, so it under predicts and the
ratio rises well above 1.

**The 3.85 in the section above is a true measurement of the multi-element population, quoted as
though it were the corpus.** It is the same fault the doping growth series records one section
earlier, found a second time in a different stage, and the default limit of 12 is what hid it.

The cache is walked in filename order and a COD identifier sorts as text, so the order is an
accident of how the archive numbers its entries and it is not random with respect to composition.
1920 of the 1959 single-element structures carry an identifier at or above 9000000, and the first
single-element structure of the run is its **345th** row. **Any limit under 345 sees none of them**,
which means every figure this stage has published was drawn from a pure multi-element sample without
anything saying so. 12 was not an unlucky draw. No reachable small limit would have been a lucky
one.

A closing median over the mixture describes neither population and moves with whatever the fetch
last gathered. The two rows are the result. The combined row is an artifact of this cache's
composition and should not be quoted at all.

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
