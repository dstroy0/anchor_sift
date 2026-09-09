# Examples

**Purpose:** Find the script that produced a figure in the ledger, or run one corpus from raw bytes through to a checked answer.
**Scope:** `examples/`

Every script lives at:

```
examples/<subject>/<stage>/<file>.py
```

The subject says what kind of corpus it reads. The stage says which step of the reading it does. So `language/4_measure/cross_corpus.py` performs a measurement on text.

Every script sits at that depth, and none of them counts parent directories to locate the repository. They start at their own directory and walk up until they find `src/engine`. The previous layout counted, so moving a file changed its distance from the root and broke its imports. The breakage did not show up until somebody ran the script.

## Stages

A corpus goes through these in order.

| stage | what it does |
|---|---|
| `1_represent` | turns the corpus into points that carry values |
| `2_partition` | picks the unit and the scale to read those points at |
| `3_reference` | builds the maximum entropy background out of the corpus itself |
| `4_measure` | reads how far the corpus sits from that background |
| `5_sift` | filters candidates using the necessary condition |
| `6_oracle` | compares the result against an answer published elsewhere |

Where a subject has no script for a stage, the directory is absent. That means nobody has written one, not that the stage does not apply.

## Subjects

| subject | corpus | stages present |
|---|---|---|
| `any_corpus` | anything. These read a corpus without knowing what it is | 1, 2, 3, 4, 5 |
| `language` | written text: books, encyclopedia articles, two parallel translations | 1, 2, 3, 4, 6 |
| `art` | paintings, stored as bytes that are really a plane | 1, 2, 4 |
| `proteins` | structures from the Protein Data Bank | 1, 2, 5 |
| `crystallography` | published cells from the Crystallography Open Database | 1, 2, 3, 4, 5, 6 |
| `sound` | animal and human vocalizations | 1 |
| `source` | programming languages, assembly, board layouts | 1, 4 |
| `proofs` | proofs of the posits the ledger cites | `posits` |

Start with `any_corpus`. Those scripts do not know what they are reading, and the rest of the work rests on that claim. Each other subject runs the same steps with domain knowledge added at stage one, and some of them can check the answer at stage six.

`0_experimental` holds work that does not yet fit a subject or a stage. It is empty at the moment.

## Failures are kept

A reading that was tried and did not work stays in its subject, next to whatever came after it. Reading Dravidian languages at the codepoint put the family further apart than unrelated languages, and that script is still in `language/4_measure` beside the two that repaired it. Anyone who finds only the repair cannot tell what it repaired.

## Fetchers are not examples

Thirty three scripts that download or generate corpora used to sit in here, leaving one directory holding fifty three files. They are in `maint/data/fetch/` now. Getting a corpus is a separate job from reading one.

## Nothing in the engine imports from here

`src/engine/` does not import anything under `examples/`. This was broken for a while: `web_alphabet.py` had thirty two importers and lived under `examples/` while the tools reached into it.

Two scripts import a sibling from the same directory. `cluster_branch.py` uses `report` from `cluster_profiles.py`, which uses a corpus reading from `positional_ambiguity.py`. All three sit in `language/4_measure` for that reason.

## Running one

```
python examples/any_corpus/4_measure/collision_entropy.py
python examples/crystallography/6_oracle/proof_positive_control.py
```

Most need corpora under `build/`, which comes to about 1.9 GB and is not in git. `maint/data/fetch/` fetches them. `python maint/deps/get_deps.py` clones what the C side needs.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
