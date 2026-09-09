# Measure

**Purpose:** Read how far an object sits from its own reference, and know which of the two instruments here produced the number.
**Scope:** `src/engine/python/measure/`

| module | what it holds |
|---|---|
| `dispersion.py` | `dispersion_by_symbol`, `halves`, `rare_half`. The permutation null measure, which most findings rest on |
| `web.py` | `web`, `marginal`, `deep_web`, `structural`, `leave_one_out`. Which symbol follows which |
| `word_lengths.py` | `word_lengths`, `length_spread`, `marks_boundaries`. Twenty one numbers that match four thousand |
| `vocabulary.py` | `common_vocabulary`, `word_profile`. The unit where a writer is actually found |
| `entropy.py` | `collision_entropy`, `cut_per_anchor`, `uninformed_rate`, `cascade_depth` |
| `block_entropy.py` | `block_entropy`, `increments`, `undersampling_error`. Shannon entropy over blocks, and where it dies |
| `spectral.py` | `exponent`, `exponent_plane`, `exponent_volume`, `fit_bands`. The one quantity here carrying no scale of its own |
| `match_rate.py` | `match_rate`. Entropy per symbol by matching, which has no wall where counting has one |
| `periodicity.py` | `sequence_period`. The lag a sequence agrees with itself at, read at every lag |
| `point_cloud.py` | `reduce_sequence`, `reduce_cloud`, `nearest_nd`. One reduction for a cloud of points carrying values |
| `clustering.py` | `agglomerate`, `cophenetic_correlation`, `as_brackets`, `standardized`, `nearest_neighbors`, `separation` |
| `stays.py` | `mean_stay`, `band_for`, `noise_level`, `steady`, `abruptness` |
| `shift_agreement.py` | `strongest_lags`, `recover_period`, `against_a_shuffle`, `lattice_agreement`, `recover_lattice_period`. The second instrument, on a line and on a grid |

`web.py` holds four readings of one thing and the comparison between them is the finding. `marginal` is the square with its structure removed and comes within three points of it on three of four questions. `deep_web` extends it to runs of several symbols. `structural` divides the frequencies out, which turns out to compress every distance toward the average instead of isolating structure.

`point_cloud.py` replaced the separate reader each domain used to have. Every corpus here is already a cloud of points carrying values: text is positions along a line holding symbols, a picture is positions on a plane, a structure is positions in space. The orientation channel is undefined below two dimensions and is reported as absent, never as zero.

## Reading at the wrong lag sees nothing whatever the data does

`dimension_count.roughness` reads at 1, 2, 4, 8 and 16, because it was built for an interleaved index whose repeat counts bit positions. A period of three sits at lags 3, 6 and 9, and no power of two is a multiple of three. Two different quantities were both being called a period of n, and the instrument used on one of them was blind to it.

`periodicity.sequence_period` reads every lag and exists because of that. It was caught on protein backbones, where chemistry fixes the answer at three before any measurement. A reader returning anything else there is wrong, and no argument afterward can save it.

## Taking the tallest lag reports a harmonic

A sequence of period P agrees with itself just as well at 2P and 3P, so which of them stands tallest is settled by noise. Any detector that sorts the lags and takes the top one will report a harmonic about as often as it reports the period.

This has been found three separate times in this tree, in three modules that did not know about each other: `dimension_count` sampling away the powers of two, `periodicity` on protein backbones, and `shift_agreement.recover_lattice_period` on published crystal cell edges, where it returned almost exactly twice the published edge on ten of eighteen axes before it was fixed.

Score a candidate against its own multiples and against every lag outside that family. A sweep a little past 2P leaves 2P holding only itself. A candidate needing two multiples excludes the first harmonic.

**Reach for a period this way and never by sorting.** The failure looks like a clean result: a confident number, a high agreement, and a factor of exactly two that nothing in the output flags.

## Every family gets exactly two multiples, or the short candidate wins

Family scoring has a second failure and it is dimensional. Family size grows as the candidate shrinks, and the score is a mean over the family. A short wrong candidate can win by holding more members and catching one good lag among them.

The good lag comes from the period not being a whole number of lags. On herzenbergite's 4.148 angstrom axis at a voxel of 0.25 the period is 16.59 lags, so lag 16 sits 0.59 away from the fundamental while lag 33 sits 0.18 away from twice it. **Lag 33 therefore agrees better than the fundamental does.** A sweep to 2P + 6 puts 33 inside the family of candidate 11 and outside the family of candidate 16, and 11 wins an axis it has no business winning.

Three published cell edges came back short by a factor near two thirds this way, all three of them strongly anisotropic orthorhombic cells, which is where a non-integer period and a long sweep collide. Capping every family at its first two multiples equalizes the comparison, and the sweep went from 450 of 453 to **453 of 453**, mean absolute error 0.0330 to 0.0124.

`bench_recover_period` on the C side carries the same cap, so the two implementations cannot disagree about a recovered size.

## Every quantity here is a departure and none is a value

A dispersion of 0.28 says nothing. The same dispersion against a shuffle of the same bytes is 2.91 and says the positions carry something. A Zipf slope of -0.988 is inside the natural range and is also what independent draws give.

## Two instruments, and they are not interchangeable as evidence

The permutation null measure carries most of the findings in this work and has only ever been shown not to invent structure on memoryless input. It has no positive control with an answer from outside.

The shift agreement detector has external ground truth across 453 axes of published crystal cell edges, recovering every one inside one voxel. It also returned an image width and a Vigenère key length with nothing told to it.

Three separate claims in this work merged the two: a positive control was reported for the measure that never received one, a cross media claim was written for a measure that had not been run on two of the media, and an ordering of structure meters was drawn between them. Each was corrected after the fact. Read `theory/workbook` before quoting any row.

## What a histogram measure cannot see

Collision entropy is permutation invariant. A corpus and its own shuffle carry identical values, exactly and not approximately, so no entropy of this order separates a structured domain from a rearrangement of the same symbols.

The C bench measures that failing in the open. On a corpus of period sixteen the histogram predicts one alignment in 65536 survives four anchors, and one in sixteen actually does, a factor of 4096 that converges as the corpus grows. The permutation null exists for that reason, and a second instrument was never a convenience.

## Two cautions the numbers here have earned

**These quantities are heavy tailed by default.** A mean over a sample where one draw in twenty five carried 96% of it put figures three orders too large into several entries. Use the median, and print the maximum beside it.

**A rate is not a value until its sample size is fixed.** The frequent half's apparent signal tracked corpus size almost monotonically, from 1.01 at 106 KB to 0.72 at 2.4 MB, until every corpus was cut to one length.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-08
