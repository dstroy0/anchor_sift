# Proteins

**Purpose:** Read a deposited protein through the ladder to a checked answer, where the check is a
rule somebody else published and applied to the same deposit before this instrument existed.
**Scope:** `examples/proteins/`

| stage | script | what it answers |
|---|---|---|
| `1_represent` | `protein_bonds.py`, `protein_chain.py` | what the reader keeps and what it threw away |
| `2_partition` | `protein_dimension.py` | what the dimension count reads off a real structure |
| `3_reference` | `what_a_shuffle_reaches.py` | how much of the favored fraction a shuffle also reaches |
| `4_measure` | `outlier_rate_from_the_rules.py` | what the rules return, with no answer key |
| `5_sift` | `protein_domain.py` | how far the anchor cascade survives on a real cloud of points |
| `6_oracle` | `published_outlier_rate.py` | whether it matches what wwPDB published for the same deposit |

The subject stood at three of the six stages: represent, partition and sift. It had no reference,
no measure and no oracle, and the reason that gap mattered is written into the crystallography
subject next door. Every control in this work until the crystals was a memoryless process, and a
memoryless process can only show that an instrument does not invent structure. It cannot show that
an instrument finds structure that is present, and the protein case is exactly where that bit: a
protein was reported as unstructured twice, and nothing here could tell an instrument that stayed
silent on real structure from one that was working.

Crystallography closed that for crystals by reading against a published cell edge. These three
stages close it for proteins, against a rule that is closer to the ideal than a single number is.

## Why this subject can carry a positive control at last

A crystal's periodicity is published because somebody measured the cell and wrote the edge down. A
protein has no single published number of that kind, and that is why the subject sat without an
oracle. The Ramachandran rules are what it has instead, and they are better suited than an edge.

Two backbone torsions, phi and psi, place each residue on a plane. The Richardson laboratory's
Top8000 percentile contours say what fraction of a large, clean reference of real proteins sits at
each place on that plane, and the wwPDB validation pipeline scores every deposit against those
contours and publishes the resulting outlier percentage for each entry. So both halves of the
check are somebody else's work: the rules, drawn from thousands of refereed models, and the answer,
computed and published per entry before this instrument read a single atom.

The reading here never sees where an atom is. It takes only the two torsions of each residue, and a
torsion is invariant to moving or turning the whole molecule. A protein's fold does not live in its
coordinates, which carry a position and an orientation the fold does not have. It lives in the
torsions, and those are what the rules are written over.

## The one place an irrational is unavoidable, named and not buried

Crystallography needs no tolerance: a lattice displacement lands on an occupied place or it does
not. A protein cannot be read that way. A torsion is an `atan2` of the backbone geometry, an
irrational the deposit never wrote, and the rules are published on a grid of two degrees rather
than as a formula. So there is a quantum here, and the discipline is to take it from the reference
rather than pick one.

`representation.structure.protein.phi_psi` computes each torsion as exact integer terms: the whole
of it is cross and dot products of integer coordinates, and it hands back the two integers whose
ratio the angle is, without ever taking the `atan2`. The single irrational step is taken once, in
`ramachandran_rules.angle`, in decimal and to forty digits, which is forty orders of magnitude
under the two-degree grid the answer is read against, so the precision decides nothing. The grid is
the only quantum in the reading, and it is the Richardson laboratory's, not this work's. The
favored and allowed cutoffs are MolProbity's own numbers, named in `ramachandran_rules.CONTOURS`
and printed by every stage that applies them.

The sign of the torsion is fixed by measurement, not assertion. With the IUPAC sign the corpus
reproduces each deposit's published outlier rate; with it negated every structure reads as its own
mirror image and almost nothing agrees. Stage six is what settled it.

## What the stages found

**Stage four** reads the rules with no answer key. A well-refined deposit sits almost entirely in
the favored regions, which is the prediction, since the rules were drawn from exactly such models.
The reading is the favored fraction and the outlier fraction, said plainly and left for stage six
to check.

**Stage three** deletes the pairing and asks how much of the favored fraction survives. Permuting
psi against phi keeps both marginal angle distributions exactly and destroys only which psi stood
with which phi. On every structure the favored fraction falls by ten to sixteen points, because the
favored regions are diagonal ridges on the plane and not a rectangle: a phi from a helix put beside
a psi from a sheet lands between them, where the reference is thin. That gap is the fraction of the
reading that rests on the pairing, which is the secondary structure. Drawing angles uniformly gives
the flat background, about a sixth of the plane, which is how much a structure with no preference at
all would reach. Live sits well above the shuffle, and the shuffle well above the flat floor, on
every entry.

**Stage six** is the positive control the subject lacked. It draws 1000 proteins at random from
every X-ray entry in the open Protein Data Bank, recovers each one's outlier rate from the torsions
alone, and compares it to the rate wwPDB published for that entry. The archive is open and keyless
the same way the Crystallography Open Database is, which is what let crystallography build its
control, and the draw is seeded so it repeats.

The corpus is random on purpose. Sorting by resolution and taking the top was the wrong control:
the best-resolved structures are almost all zero outliers, so an instrument that only ever answered
zero would have passed. A random protein spans the whole quality range and carries published rates
from zero to several percent, and reproducing that spread is the test.

**Of 1000 random proteins graded, 535 land on the published outlier rate exactly, and 149 more
within a single residue: 684 of 1000 agree to within one residue.** That is lower than a sorted
corpus reaches, and it is meant to be. The disagreement tracks resolution, cleanly and in one
direction:

| resolution | within one residue |
|---|---|
| 1.0 A | 42 of 46 (91%) |
| 1.5 A | 164 of 205 (80%) |
| 2.0 A | 304 of 410 (74%) |
| 2.5 A | 113 of 204 (55%) |
| 3.0 A | 50 of 91 (55%) |
| 3.5 A and worse | 11 of 44 (25%) |

At the resolution where the backbone is placed to a fraction of an angstrom, the reading reproduces
the published rate almost every time. Where the coordinates are uncertain, the two counts diverge.
And the divergence has a direction: of the 316 misses, 299 count more outliers than wwPDB, not
fewer. The reading is not finding structure that is absent; it is scoring residues the pipeline's
own count leaves out, and it does so more often exactly where the model is least certain. Nothing
was tuned to reach this: the contours and cutoffs are MolProbity's, the corpus is a seeded random
draw from every X-ray protein entry, and the sweep ran once through.

The agreement is not exact equality on every structure, and it was never going to be. Where the two
disagree the direction is the finding: this reading counts residues as outliers that the pipeline's
own count does not, almost never the reverse.
The angle is not in dispute, since the decimal `atan2` agrees with a double to fourteen places.
What differs is which residues each side scores at all. Chain ends, alternate locations and
residues at a break are counting conventions, and the last residue of disagreement lives there. The
geometry is exact; the residue bookkeeping is the tolerance, and it is small and named rather than
tuned away.

## The engine boundary this subject was careful about

The crystallography subject records being built wrong twice: first as a separate reader under
`data/` that reimplemented a parse the engine already did, then as a scratch script that fixed one
measurement and left the bound it came from sitting in the base primitive for every other domain.

This subject keeps to the corrected shape. The reusable reader, the exact-integer torsion, is one
function in the engine, `representation.structure.protein.phi_psi`, additive and domain-blind about
everything except that a protein backbone is `N`, `CA`, `C`. The Ramachandran rules, which are
reference data and not a reader, live beside the examples in `ramachandran_rules.py`, exactly as
the crystallography oracle keeps its COD fetch in the example rather than the engine. Nothing here
reimplements the backbone parse, and no bound sits under the engine waiting to charge the next
domain that reads through it.

## Running one

```
python examples/proteins/4_measure/outlier_rate_from_the_rules.py
python examples/proteins/3_reference/what_a_shuffle_reaches.py
python examples/proteins/6_oracle/published_outlier_rate.py 1000
```

The oracle takes how many proteins to grade, defaulting to 1000. It draws from a seeded shuffle of
every X-ray protein entry, so a smaller number is a prefix of the same corpus and a larger one
extends it; the draw is the same on every machine. The corpus is a target to reach, not a slice off
the top: an entry with no PDB-format file or no published number is skipped and the next id drawn,
until the target grades.

Stages three and four read the six curated structures in
`representation.structure.protein.WANTED` and cache them under `build/corpora`. The oracle fetches
its coordinate files and its published numbers from the open RCSB mirror of the Protein Data Bank,
which needs no account or key, and caches everything under `build/corpora` and `build/rama`; a
second run costs the archive nothing. The reference contours are fetched once from the Richardson
laboratory's public repository and cached beside them.

The rules are not this work's. The Top8000 Ramachandran contours are published by the Richardson
laboratory at <https://github.com/rlabduke/reference_data> under CC BY 4.0, and are the same
contours MolProbity and wwPDB validation score against.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
