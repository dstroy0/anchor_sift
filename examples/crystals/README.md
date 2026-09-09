# Crystals

**Purpose:** Say why this subject is one stage deep, and what the missing stages would have to contain.
**Scope:** `examples/crystals/`

| stage | present |
|---|---|
| `1_represent` | no, and it is in the engine instead |
| `2_partition` | no |
| `3_reference` | no |
| `4_measure` | no |
| `5_sift` | no |
| `6_oracle` | `proof_positive_control.py` |

## Why the walk starts at the end

This subject exists for stage six. The Crystallography Open Database publishes the cell edge for every entry, so the periodicity is a number somebody else measured, refereed and wrote down before this instrument existed. It is the only positive control in this work with an answer nobody here produced.

**453 of 453 axes recovered inside one voxel of 0.25 angstroms, over 151 structures from 64 mineral names, at a mean absolute error of 0.0124 and a worst of 0.0554.**

Three of those axes missed at first, all short by a factor near two thirds, and the cause was worth keeping. The family scoring let candidates compete with families of different sizes, and family size grows as the candidate shrinks. A cell edge is not a whole number of voxels: on herzenbergite's 4.148 angstrom axis the period is 16.59 voxels, so lag 16 sits 0.59 away from it while lag 33 sits 0.18 away from twice it. Lag 33 therefore agreed better than the fundamental did, and it fell inside the family of candidate 11 and outside the family of candidate 16. The short wrong candidate won by holding more members and catching the one good lag among them.

All three failures were strongly anisotropic orthorhombic cells, which is where a non-integer period and a long sweep collide. Capping every family at two multiples equalized the comparison. The same rule now governs `bench_recover_period` on the C side, so the two implementations do not disagree about a recovered size.

Every other control in the tree is memoryless, and a memoryless control shows that an instrument does not invent structure. It cannot show that the instrument finds structure that is present. This work reported a protein as unstructured twice before that difference was drawn.

The representation belongs to the engine at `representation/structure/crystal.py`, because parsing a CIF and tiling a right angled cell is not a demonstration. It is the domain knowledge that has to exist before a reading can happen.

## What the missing stages would be

**A measure stage** would ask something of a crystal other than its period. Nothing here does, and until something does, the subject has one question and one answer.

**A sift stage** would run the anchor cascade over a voxelized cell and check the survivor rate against the histogram bound, as `proteins/5_sift` does for a deposited structure. A crystal is the case where that bound should fail hardest, since a lattice is the cleanest periodic arrangement there is, and `src/engine/c/bench/bench_coherence.c` measures exactly that failure on a synthetic period. Doing it on a real cell is the obvious next reading and it has not been done.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
