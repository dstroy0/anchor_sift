# Examples

**Purpose:** Find the script that produced a figure in the ledger, or run one corpus from raw bytes through to a checked answer.
**Scope:** `examples/`

Every script lives at:

```
examples/<subject>/<stage>/<file>.py
```

The subject says what kind of corpus it reads. The stage says which step of the reading it does. So `language/4_measure/cross_corpus.py` performs a measurement on text.

Every script sits at that depth, and not one counts parent directories to locate the repository. They start at their own directory and walk up until they find `src/engine`. Counting parent directories breaks when a file moves: its distance from the root changes, its imports fail, and the breakage does not show up until somebody runs the script.

## Stages

A corpus goes through these in order.

| stage         | what it does                                                   |
| ------------- | -------------------------------------------------------------- |
| `1_represent` | turns the corpus into points that carry values                 |
| `2_partition` | picks the unit and the scale to read those points at           |
| `3_reference` | builds the maximum entropy background out of the corpus itself |
| `4_measure`   | reads how far the corpus sits from that background             |
| `5_sift`      | filters candidates using the necessary condition               |
| `6_oracle`    | compares the result against an answer published elsewhere      |

Where a subject has no script for a stage, the directory is absent. That means nobody has written one, not that the stage does not apply.

## Subjects

| subject            | corpus                                                                 | stages present   |
| ------------------ | ---------------------------------------------------------------------- | ---------------- |
| `any_corpus`       | anything. These read a corpus without knowing what it is               | 1, 2, 3, 4, 5    |
| `language`         | written text: books, encyclopedia articles, two parallel translations  | 1, 2, 3, 4, 6    |
| `art`              | paintings, stored as bytes that are really a plane                     | 1, 2, 4          |
| `proteins`         | structures from the Protein Data Bank                                  | 1, 2, 3, 4, 5, 6 |
| `crystallography`  | published cells from the Crystallography Open Database                 | 1, 2, 3, 4, 5, 6 |
| `chemistry`        | molecules as atoms and bonds, valence as a necessary condition         | 1, 3, 4, 5       |
| `molecules`        | atoms and formulae, read for the valence structure they can carry      | 1, 6             |
| `particle_physics` | atoms as electron shells, Standard Model particles as quantum numbers  | 1, 2, 3, 4, 5, 6 |
| `sound`            | animal and human vocalizations                                         | 1, 3, 4          |
| `source`           | programming languages, assembly, board layouts                         | 1, 4             |
| `game_theory`      | games with their own answer key, played boards and impartial games     | 1, 2, 3, 4, 5, 6 |

Start with `any_corpus`. Those scripts do not know what they are reading, and the rest of the work rests on that claim. Each other subject runs the same steps with domain knowledge added at stage one, and some of them can check the answer at stage six.

Four directories sit outside the subject and stage layout. `0_experimental` holds work that does not yet fit a subject or a stage. `00_blob_viz_tools` is the viewers, a Python generator plus an HTML template each, documented in its own README. `proofing` is the precision work the ledger rests on, the pi-digit reading and the device and host arithmetic engines. `cell_tracking` is a full implementation with its own build scripts, configs, source and tests, not a walk through a corpus.

The proofs of the posits the ledger cites are not under `examples/`. They are in `evidence/proofs/posits/`.

## Failures are kept

A reading that was tried and did not work stays in its subject, next to whatever came after it. Reading Dravidian languages at the codepoint put the family further apart than unrelated languages, and that script is still in `language/4_measure` beside the two that repaired it. Anyone who finds only the repair cannot tell what it repaired.

## Fetchers are not examples

Scripts that download or generate corpora do not sit here. They are in `maint/data/fetch/`. Getting a corpus is a separate job from reading one.

## Nothing in the engine imports from here

`src/engine/` does not import anything under `examples/`.

Two scripts import a sibling from the same directory. `cluster_branch.py` uses `report` from `cluster_profiles.py`, which uses a corpus reading from `positional_ambiguity.py`. All three sit in `language/4_measure` for that reason.

## Running one

```
python examples/any_corpus/4_measure/collision_entropy.py
python examples/crystallography/6_oracle/proof_positive_control.py
```

Most need corpora under `build/`, which comes to about 1.9 GB and is not in git. `maint/data/fetch/` fetches them. `python maint/deps/get_deps.py` clones what the C side needs.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
