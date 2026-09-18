# Chemistry

**Purpose:** Read the building block and the rule the anchor_sift way, valence as a necessary
condition and the bond length as an oracle, using the primitives already in the tree.
**Scope:** `examples/chemistry/`

| stage         | script                                        | what it answers                                                                                                  |
| ------------- | --------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| `1_represent` | `build_molecules.py`                          | building a molecule as atoms and bonds, and that a formula does not fix a molecule                               |
| `3_reference` | `two_nulls_two_questions.py`                  | which null the octet departs from, and which it does not                                                         |
| `4_measure`   | `a_histogram_cannot_see_structure.py`         | what a histogram measure reads of a molecule, and what it cannot                                                 |
| `4_measure`   | `a_single_period_cannot_see_a_growing_one.py` | why a single-period reader misses a growing recurrence, and why the boundaries must be supplied                  |
| `5_sift`      | `valence_is_a_necessary_condition.py`         | whether the octet refuses no real molecule and prunes the rest, and whether a shuffle of the same atoms loses it |

Stages two and six are not present yet, and stage four is present only in the readings that need no geometry. The reason is a boundary, not an omission.

## The stages here run on what exists

Stage one builds molecules. A molecule is a set of points carrying values, each atom a point carrying
its element and each bond the vector between two of them, and `build_molecules.py` builds the
connectivity: a catalog of named molecules as atoms and bonds and their orders. It does not place the
atoms in space, because a bond's magnitude is its length and a length is an oracle fact that is not
entered yet. What is built is the molecular graph and the geometry is left to stage six. The octet
is the gate on the catalog. A mis-built bond is caught, and the reading it delivers is that a
formula does not fix a molecule: ethanol and dimethyl ether are both C2H6O and both close. The
formula is a label and not the structure. It holds only chemistry's own valence layer. It runs
before the element ledger lands and transcribes no element identity.

Stage three grades the null. A departure is only as good as the background it is read against. Permuting which element
sits on which site deletes the element-to-site match, and the octet departs from it: the real molecule
closes and most permutations do not. A degree-preserving rewire deletes the connectivity while holding
each atom's degree at its valence, and the octet does not depart from it at all, closing on every
rewire including the self-bonded graphs that are not molecules. So the octet carries which element sits
where and carries nothing about which atoms are joined, and telling one isomer from another is a
measure question, not a valence question.

Stage four measures, and it measures a limit. Collision entropy reads the atom counts alone. It is
permutation invariant, and `a_histogram_cannot_see_structure.py` shows a molecule and any rearrangement
of its atoms carry the identical value to machine precision, and the two isomers read the same number.
A histogram reads the formula and stops there. Arrangement is left to the sift and the choice
among isomers to a geometry the bond-length oracle carries. This is the measure that composition is not
structure, and it needs no coordinate to make the point.

The second stage-four reading is a different measure with a different limit.
`a_single_period_cannot_see_a_growing_one.py` reads a recurrence two ways. The engine's
`measure.periodicity` finds one period by scoring a candidate against its own multiples, and
`reference.periodic` builds the phase background at that period; both fix a single period. A periodic
property along Z is not one period, because the shell lengths 2, 8, 8, 18, 18, 32 grow. The
single-period reader goes flat on the growing recurrence while a reader handed the boundaries departs.
Those boundaries are a supervised partition, ground truth from outside the sample. They come from
the element ledger and not from the sequence. The sawtooth here is synthetic and writes no element
data; the real sequence and its boundaries are the ledger's to supply.

Stage five is the sift. The proposition is domain blind: any subset of a pattern's points is a
necessary condition. No selection rule loses a true occurrence, and the converse fails. Every
survivor is confirmed. Valence is that proposition in chemistry. Every atom of a real molecule closes
its octet. The octet refuses no molecule and prunes arrangements, and the error is one directional.
That runs today with `reference.shuffles` for a drawn null and needs no new engine part.

The script reads two routes and shows them able to disagree. The per-atom octet is the strong one; the
handshake sum, that the valences add to twice the bond count, is weaker and passes on a mis-wired
peroxide the octet refuses. It carries a positive control, eight real molecules that close every
atom, and a negative control, arrangements the octet must refuse, because a pass proves only that the
check is wired to say yes until something it should decline is declined. The null is drawn by
permuting which element sits at which atom over the same bond graph: most permutations put an element
where its valence does not fit the degree. The real assignment sits above the band the shuffles
occupy. No number here is a value; each is a departure from that band.

## Why the other stages wait

They wait on a boundary the engine is holding. The element ledger, the proton count, the electron set,
the Pauli behavior behind the shell counts and the periodic recurrence, is the atomic structure, and
it is authored once by the atomic-structure subject in a shared `representation/atom` home. Chemistry
consumes it and does not transcribe it, because a second element table is a second source of truth for
a fact chemistry did not establish. Stage two, and the geometric measures of stage four, need a molecule reader in
`representation/structure` beside the protein and crystal readers, that imports that ledger and places
atoms as points in space, and stage six needs `oracle/chemistry`, the bond lengths held as facts apart
from the language family trees, which the oracle README already reserves a directory for. Stage one
above stops at the connectivity precisely because the coordinate a stage-two reading needs is a bond
length, and a bond length is that oracle. Those are coordinated additions, not this subject's to write
alone, and until they land the remaining stages would be transcriptions of the plan.

What each stage will do, and the predictions each makes, is stated in `theory/chemistry` before the
readers exist, in the design-only posture the exact-arithmetic chapter of the image-transforms book
uses.

## Running one

```
python examples/chemistry/1_represent/build_molecules.py
python examples/chemistry/3_reference/two_nulls_two_questions.py
python examples/chemistry/4_measure/a_histogram_cannot_see_structure.py
python examples/chemistry/4_measure/a_single_period_cannot_see_a_growing_one.py
python examples/chemistry/5_sift/valence_is_a_necessary_condition.py
```

None of them reads a file or reaches a network. The molecules and their valences are in the scripts, a
bonding map that is chemistry's own layer and not the element ledger, and the periodic example's
sequence is a synthetic sawtooth with arbitrary segment lengths, not the shell counts.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-17
