# Oracle

**Purpose:** Hold the answers that came from outside the sample, apart from everything the sample can supply on its own.
**Scope:** `src/engine/python/oracle/`

| module | subject | what it holds |
|---|---|---|
| `language/families.py` | language | `FAMILY`, `PARALLEL`, `DRAVIDIAN`, `INDO_ARYAN`, `every_family`, `scoreable`, `score_against`, `dravidian_check` |
| `language/typology.py` | language | `CAPITALIZES`, `MORPHOLOGY`, `SUBFAMILY`, `family_of`. How a word is built, and what takes a capital |
| `language/glosses.py` | language | `harvest`, `morphemes`, `is_gloss`, `is_translation`. A linguist's own analysis, read off the page |

Everything here is under a subject and the parent stays empty, because an oracle is by definition knowledge of a particular kind of thing. Crystallography's published cell edges and chemistry's bond lengths get their own directories when they arrive, and they should not share a namespace with a family tree: a cell edge is a fact and a family tree is a consensus.

`glosses.py` reads a file where the others hold a table, and it is still an oracle. The interlinear format prints the form, a morpheme by morpheme gloss, and a running translation. The second line is what the word composes and the third is what English keeps, so the difference between them is arrived at by subtraction. Every part of it was written down by the linguist who studied the language.

`dravidian_check` scores a reading against the family's ordered prediction and returns numbers with no formatting in them. Three examples printed that block from three copies of it, which is three places for a verdict to drift from the prediction it is supposed to be testing.

## Why this part exists at all

A partition is fixed by stipulation, by estimation, or by supervision. A stipulation adds no information and fixes a frame. An estimate extracts what the sample already carries and can reach nothing past it. Supervision is the only one of the three that adds information the sample did not contain.

Jaynes states it as the content of the second law: information about the state of a system may be lost by many routes, and "the only way in which it can be gained is by carrying out further measurements."

New information enters the engine here and nowhere else, and that is the boundary that does not bend. A permutation null is a reference built from the object itself and settles nothing from outside it, however carefully it is constructed.

## The two strongest results in this work are both supervised

Published cell edges from the Crystallography Open Database, tiled and voxelized and handed over with nothing told to the detector: 453 axes over 151 structures, every one recovered inside one voxel of 0.25 angstroms, at a mean absolute error of 0.0124 and a worst of 0.0554.

A dialect border inside Lushootseed, labeled by Mellesmoen and Kye and then held out, comes back as the stressed schwa, southern, beaten by 1 of 200 random borders. Neither answer was derivable from the corpus it was measured against.

## What agreement with a family tree is worth

Less than a cell edge, and the difference matters. A family tree is a reconstruction argued from cognates and sound correspondences, so agreement is agreement with a scholarly consensus and not a check against a fact, and where the two disagree nothing here can say whether the instrument or the reconstruction is wrong. Protein bond lengths are the other kind: valence fixes the answer whatever anyone believes. Those are an oracle. A family tree is a strong prior.

## One trap the table is written to avoid

A family holding one language in a run cannot have a neighbor inside it, so its nearest is outside its family whatever the instrument measures. Scoring those as errors turned an honest 15 of 22 into a misleading 15 of 28, and it is why Greek sitting nearest Hebrew was recorded as a script artifact when neither language had a relative in the set. `scoreable` returns only the names that can be scored.

## An absence is a reading

Reporting that something expected is missing needs no new object, because a hole is a departure from an occupancy the constraint already states. The oracle check's second direction is that reading: it asks which tokens a paper prints that no row holds, and finds what a person skipped by knowing what should have been there. Without the regularity there is no hole to see.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
