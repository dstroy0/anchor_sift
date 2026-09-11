# Reproducing the SHA-256 measurements

Every number in this book comes from a command in this repository. This maps them. A reader can
regenerate any figure or claim instead of taking it on trust.

Nothing here is stored as data. The measurement files are regenerated from source and gitignored:
they are large, they are derived, and a stale copy misleads where a missing one only stops you.
Regenerating all of them takes roughly an hour on one RTX 3070.

## The pieces, and where they live

The research artifact is not contained in `theory/`. It spans four places, and the split is worth
stating because `tools/` also holds miner tooling that has nothing to do with this work.

| what | where |
|---|---|
| measurement engine, ten arms | `src/bench/bench_sac.cu` |
| analysis and viewers | `tools/check/`, `tools/radar/`, `tools/view/build_*_view.py`, `tools/view/make_shadow_figure.py` |
| the book | `theory/cryptography/sha256/`, built by `tools/book/build_theory.sh` |
| the working ledger, with every refutation | `docs/sha256-topology.md` |
| **not part of this work** | `tools/audit/`, `tools/chain/`, `tools/check/language_of_nature.py` |

## Building

```
.\build_scope.ps1                 # builds bench_sac.exe and the other device benches
sh tools/book/build_theory.sh     # builds the book to build/theory/cryptography/sha256/main.pdf
```

The book build fails on a dropped glyph instead of shipping one. A clean exit means every character
in it rendered.

## The engine

```
src/bench/bench_sac.exe <trial_bits> <first_round> <last_round> [arm]
```

`trial_bits` is the log-2 of message pairs per cell; most results here use 18, and the ratio tests
use 20 or 22. With no arm it runs the strict-avalanche sweep between `first_round` and `last_round`.

| arm | what it measures | writes |
|---|---|---|
| `shadow` | the field collapsed along each axis, 64 rounds | `src/bench/shadows.csv` |
| `signed` | never / always / mixed counted apart, 40 rounds | `src/bench/signed.csv` |
| `cells` | identities of the probability-one cells at rounds 8, 10, 12 | stdout |
| `assay` | residue spectrum of each sub-function ablation | `src/bench/assay.csv` |
| `sources` | the same projections from SHA-256, pseudorandom, and two ablations | `src/bench/sources.csv` |
| `waves` | injected-wave calibration, field whiteness, and the Doppler scan | stdout |
| `dispersion` | drift and decay per spatial frequency, rounds 10-23 | stdout |
| `coherent` | phase-locked loop against a generated linear reference | stdout |
| `construct` | every weight-1 and weight-2 difference, swept for sparse linear characteristics | stdout |
| `conditional` | the field split on Choose's selector bit | stdout |
| `miner` | the client's two shared-work constants, against a real header | stdout |

## Claim to command

| claim in the book | how to reproduce |
|---|---|
| the soliton: 312 certain cells, 135 bits, 32 bits/round | `bench_sac.exe 18 45 64 signed` |
| 312 = 256 aligned + 56 skewed, all skew at residue 25 | `bench_sac.exe 18 45 64 cells` |
| probability-one propagation ends at round 21 | `bench_sac.exe 18 45 64 signed`, the row where never and always both reach 0 |
| the residue-26 ridge is refuted; residue 0 carries the structure | `bench_sac.exe 18 45 64 shadow` then `python tools/check/check_ridge_common_mode.py` |
| the transport channels are 0, 31 and Sigma1's amounts | `python tools/check/check_rotation_residues.py` |
| matched filter 19.16, Sigma1 12.61 against Sigma0 3.34 | `python tools/radar/radar_receive.py` |
| deep rounds suppressed at least 15x | `python tools/radar/radar_receive.py`, the table past the collapse |
| ablating Sigma1 removes 6, 11, 25; ablating addition removes 31 | `bench_sac.exe 18 45 64 assay` then `python tools/radar/radar_assay.py` |
| the knee at round 17 is the message schedule | `bench_sac.exe 18 45 64 assay`, compare `full` and `no_schedule` across round 16 to 17 |
| addition breaks the symmetry among Sigma1's rotations | `bench_sac.exe 18 45 64 sources` then `python tools/check/check_two_sources.py no_addition no_sigma1` |
| the field only desaturates; decrement is 2^16 per round | `python tools/check/check_monotone.py` |
| the diagonal at slope +32, forward only | `python tools/check/check_slant.py` |
| every message word collapses on the same schedule, span 5 | `python tools/check/check_word_collapse.py` |
| the linear model dies at round 7, halving per round | `bench_sac.exe 16 45 64 coherent` and again with 22 for the ratio test |
| no sparse linear characteristic past round 22 | `bench_sac.exe 16 45 64 construct` |
| the round constants leave no trace | `python tools/radar/sei_round_constants.py` |
| no drift at any spatial frequency | `bench_sac.exe 18 45 64 dispersion` |
| the field is white at every lag; the Doppler null | `bench_sac.exe 18 45 64 waves` |
| conditioning on Choose's selector finds nothing | `bench_sac.exe 18 45 64 conditional`, then 20 for the ratio test |
| the register chains a-b-c-d and e-f-g-h at equal delay | `python tools/check/check_word_pairs.py` |
| the miner's SHARED_ROUNDS 3 and SHARED_SCHEDULE 18 are tight | `bench_sac.exe 18 45 64 miner` |
| **a refuted claim, kept**: no deep periodic structure per input bit | `python tools/check/check_tilt.py`. This test cannot see a diagonal and is retained because it was the wrong instrument, which `check_slant.py` then corrected |

## Figures

| figure | how to regenerate |
|---|---|
| the two residue character maps in the shadows chapter | `python tools/view/make_shadow_figure.py` |
| the flat shadow viewer | `python tools/view/build_shadow_view.py` |
| the turnable voxel field | `python tools/view/build_voxel_view.py` |
| SHA-256 beside a pseudorandom field | `python tools/view/build_sources_view.py` |

The three viewers are self-contained HTML with the data embedded, because they are published as
artifacts and an artifact cannot fetch anything at run time.

## What a reader should check first

The controls, not the results. Every claim in this work is only worth what its null is worth, and
each null is measured through the same code as the measurement it bounds. None is computed from
theory:

- `bench_sac.exe 18 45 64 waves` carries an injected wave of known amplitude, faded until the
  readout loses it. That fixes the sensitivity of every residue reading by measurement.
- The `psrand` source in `sources` is binomial by construction and reads an rms deviation of exactly
  1.000. If it does not, the harness is broken and no other number in this book stands.
- `tools/radar/radar_assay.py` checks predictions written into `bench_sac.cu` before the run, so the
  ablation results cannot have been fitted afterwards.

Six claims in this work were killed by their own controls, and the ledger in
`docs/sha256-topology.md` records each with the measurement that ended it.
