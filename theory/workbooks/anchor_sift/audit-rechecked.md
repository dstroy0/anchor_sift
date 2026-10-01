# Audit, rechecked

**Purpose:** Find out which findings of the audit are repaired, which are still owed, and which can
no longer be checked, each with the file and the text that shows it.

The check reads the documents against each other and against the code that produces their numbers.
It asks four questions. Is a retracted claim still asserted anywhere? Do the research papers quote
the same numbers as the ledgers? Do the instruments behind the largest claims have the controls
this tree requires of every other instrument? Can a reader tell which claims a document answers for?

Each section states one finding and its standing, in one of three words. **Repaired** means the
defect is gone and the section cites where. **Owed** means it is still in the tree. **Not checked**
means the evidence the finding rests on is no longer in any tree this record can read, and the
number is repeated.

## The lag sweep and the 3.81 figure have no script in the tree

**Owed.** `theory/workbooks/anchor_sift/aiming-the-engine.md` quotes two claims as a direct
measurement: distance-to-target autocorrelation inside the null band at every lag from 1 to 1024
over 200,000 nonces, and hill-climbing losing to random draw by 3.81 standard errors at equal
budget. The script its table names, `distance_landscape.py` at
`examples/00_blob_viz_tools/build_block_view.py`, appears in no tree, and neither number can be
reproduced.

## The ledger's closing count

**Repaired.** `theory/workbooks/anchor_sift/sha256-topology.md` says twenty hypotheses and records
twenty places it was looked for, matching the hypothesis table.

## Broken sentences from a deletion sweep

**Repaired.** The sentences a deletion sweep left ungrammatical read as whole sentences again;
`theory/workbooks/anchor_sift/failure-modes.md` reads *Mode 15 arrived last and deserves the most
weight*. The class is still open: `maint/prose/docs_check` matches tokens and has no grammar check,
and a sweep that deletes a banned token can break the next sentence, which then carries no banned
token for the checker to report.

## The rewrite table

**Repaired.** `maint/fix_prose.py` refuses any row whose replacement the checker flags, by running
the replacement through `maint/prose/docs_check`.

## Documents without a Purpose line

**Owed.** These documents under `theory/workbooks/anchor_sift/` open straight into prose, with no
Purpose and Scope block to state which claims each answers for: `aiming-the-engine.md`,
`arm-records.md`, `boundary-counting.md`, `boundary-reading.md`, `failure-modes.md`,
`finer-alphabet.md`, `index.md`, `information-theory.md`, `navier-stokes-prediction.md`,
`octant-lexicon.md`, `round-depth-experiment.md`, `sha256-boundary-deformation.md`,
`the-dimensional-transforms.md`, `twiddle-proof.md`, `version-rolling-signature.md`,
`viewer-survey.md` and `what-the-instruments-cannot-see.md`.

## What a boundary holds

**Repaired.** The chapter is included at `theory/theory/boundary/main.tex` and
`theory/thought_experiments/anchor_sift/main.tex`.

## The signed manifest and its timestamp proofs

**Owed, and the signature does not verify.** `gpg --verify maint/signing/manifest.tsv.asc
maint/signing/manifest.tsv` calls the signature BAD, and `python maint/signing/verify.py` agrees:
the signature covers bytes other than the manifest in the tree. The manifest that was signed and
stamped is in no tree this record can read. Whether either OpenTimestamps proof is confirmed on the
chain is **not checked**: `verify.py` prints *not yet verifiable* for both, because `ots` fails at
start-up on this machine before it reads a proof.

## The hour-of-day phase

**Repaired.** `theory/workbooks/anchor_sift/version-rolling-signature.md` tests the phase directly
with `maint/chain/phase_replication.py`: two splits of the corpus, even heights against odd and
first half against second, both put the trough at 22:00 UTC.

## The register reading is compositional

**Not checked.** The ban-list gate finds no banned tokens per 100k words, and
`maint/prose/machine_distance.py` places the files on the far side of a human band drawn from
366,833 words by `web_profile`. Passing the gate does not show the prose reads as human. The
placement is not checked: the tool reads its human corpus from a directory absent from this
checkout.

## The shift_agreement citation

**Repaired.** The warning in `src/engine/python/measure/shift_agreement.py` reads that it is not the
null permutation identity and the two are not interchangeable as evidence, and that it tests one
hypothesis, whether the sequence agrees with itself at a fixed offset.

## Retracted claims

**Not checked.** The check cannot be repeated from this record: the documents it rested on no longer
mark the retracted claims with the same words. The lag sweep above is one claim still quoted as live
without a script behind it.

## Transcribed chapters

Four documents are transcribed to LaTeX, `what-the-instruments-cannot-see.md`, `failure-modes.md`,
`aiming-the-engine.md` and `the-dimensional-transforms.md`, included at
`theory/theory/instruments/main.tex`. The markdown copies remain in
`theory/workbooks/anchor_sift/`, and the two copies of each can drift.

## Owed

1. Recover the manifest the signature and proofs commit to, or build a new manifest and sign and
   stamp it again, and upgrade both proofs with a working OpenTimestamps client.
2. Find `distance_landscape.py` or rerun its measurement, or withdraw the lag sweep and the 3.81
   figure from `theory/workbooks/anchor_sift/aiming-the-engine.md`.
3. Give the documents listed above a Purpose and Scope block.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
