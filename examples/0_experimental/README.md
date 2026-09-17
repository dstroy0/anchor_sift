# Experimental

**Purpose:** Hold work that has no walk through a corpus yet, keeping it visible without being mistaken for a stage.
**Scope:** `examples/0_experimental/`

Twenty. Six take a filter from another field and run it on this engine's terms. Thirteen carry
the exact arithmetic behind the precision work: the number theoretic transform's precision constants, a
translation recovered by it, the identity spread that multiplies precision across the constants, a
redundant residue code that detects uncertainty on exact integers, a ladder of checks each catching what
the one below it misses, the last digit of pi at any floor, the transform's wave inversion at its
boundary, the zeta values at the even integers, the symmetry group of the zeta zeros, the
Navier-Stokes equations on the unit torus with their sets run against the boundary function, the
Navier-Stokes energy cascade and coefficient growth of one datum, the congruent number problem on
Birch and Swinnerton-Dyer, and a descent bounding the rank of those curves. One carries a payload machine
to machine as a vector of exact magnitudes read like a Turing-machine tape. None reads a corpus, and none
sits at a subject stage.

| file | field | what it shows |
|---|---|---|
| `bloom_is_the_sift_theorem.py` | databases | a Bloom filter is the anchor cascade's theorem, with the same one-directional error |
| `hamming_corrects_by_selecting.py` | coding theory | a parity syndrome corrects by selecting the codeword its necessary conditions leave standing |
| `collaborative_filter.py` | recommender systems | a missing entry predicted from the neighborhood that shares its known values |
| `morphology_opening_and_closing.py` | image morphology | erosion and dilation rejecting a speckle by rank, with no threshold |
| `invariant_consensus_rejects_outliers.py` | robust estimation | the inliers are mutually compatible and form a clique, and rejecting outliers is finding it |
| `theil_sen_robust_trend.py` | robust statistics | a median over pairwise slopes recovers the trend exactly where least squares is dragged off it |
| `ntt_twiddle_certificate.py` | computer arithmetic | the transform's precision constants re-derived from the factorization of p-1, and a composite, a false root and a root of half the order each refused |
| `exact_translation_by_ntt.py` | image registration | a translation recovered exactly by an integer transform, its correlation agreeing to the digit with the direct O(N^2) count, the single-prime floor drawn on weighted views |
| `exact_identities_spread_precision.py` | computer arithmetic | exact identities carry precision from a few seed constants to over a million derived ones at the same scale, each checked by a second route, with a false identity refused and the per-identity floor measured |
| `exact_residue_code_detects_uncertainty.py` | coding theory | a redundant residue number system on exact integers corrects one error and detects two, raises no false alarm on clean codewords, and widens the exact range past a googol as moduli are added |
| `exact_check_ladder.py` | coding theory | four checks stacked, casting out nines, mod eleven, a cyclic redundancy check and Hamming (7,4), each catching a fault the one below misses, every detection exact and never a rounding |
| `pi_has_no_last_digit.py` | number theory | pi's digit at any floor, computed to any depth by the natural constants module where Machin and Euler agree, shown to have no last digit because the scale has no floor |
| `ntt_double_transform_inverts.py` | signal processing | the transform applied twice reflects the sequence exactly, a wave inversion (the DFT's order-four structure over a finite field), and its cyclic length is the format boundary |
| `exact_zeta_values.py` | analytic number theory | the Riemann zeta function at the even integers, exact from the Bernoulli numbers, cross-checked by Euler's pi-free convolution identity, touching the values and never the zeros |
| `zeta_zero_symmetry.py` | analytic number theory | the Klein four-group symmetry of the zeta zeros verified exactly on Gaussian rationals, with the critical line as its fixed set; records structure, computes no zero, claims nothing about the hypothesis |
| `exact_navier_stokes_on_torus.py` | fluid dynamics | the Navier-Stokes equations on the unit torus in the engine's exact integer arithmetic, Gaussian integers times powers of pi over one integer denominator per field: the Arnold-Beltrami-Childress solution reproduced by a velocity route and a vorticity route to the integer, a generic datum's Taylor coefficients outrunning any fixed mode horizon, the viscosity moved by an exact scaling, the two removals shown on instances, and the countable island of nameable fields in the data class; claims nothing about any of Fefferman's four alternatives |
| `exact_navier_stokes_cascade.py` | fluid dynamics | the same solution map made visible: a generic datum's energy front advancing one mode shell per order while the Arnold-Beltrami-Childress datum stays in one shell, the shell energies summing to the total by Parseval and agreeing across the velocity and vorticity routes, and the coefficient growth whose limit is the reciprocal of the analyticity time, an exact constant for ABC and a completeness horizon for the generic datum; claims nothing about any of Fefferman's four alternatives |
| `exact_congruent_number.py` | number theory | the congruent number problem on Birch and Swinnerton-Dyer, in exact integers and rationals: Tunnell's theta count reproducing Fermat's non-congruent 1 unconditionally and refusing 3, the elliptic-curve group law over Q exact, and the n=5 witness where Fibonacci's triangle (3/2, 20/3, 41/6) and the infinite-order point on y^2=x^3-25x are one certificate; the analytic side (the L-value, period, regulator) left as the stated floor, and the Tunnell converse flagged as conditional on the conjecture; claims nothing about BSD |
| `exact_descent_rank.py` | number theory | a descent by 2-isogeny on y^2=x^3-n^2x giving a sound rank upper bound in exact integers, with local solvability as a refute-only probe whose Hensel level is derived from the form and never picked; it reproduces the known ranks over rank 0 and rank 1, pins the rank where an explicit point's lower bound meets the bound, and at n=17 reaches the first part of the Tate-Shafarevich group, exhibiting the classes 2, 17, 34 as nontrivial Sha elements that are locally soluble everywhere yet come from no rational point (rank 0 unconditional by Tunnell); claims only a rank upper bound and the exact Sha it exhibits |
| `magnitude_vector_transfer.py` | data transfer | a payload carried machine to machine as a vector of exact integer magnitudes read like a Turing-machine tape, where one small tape stands for an output too large to hold and any byte of it is reached without building it, dense where the payload repeats and at source size where it does not |

The robust-estimation pair, `invariant_consensus_rejects_outliers.py` and `theil_sen_robust_trend.py`,
share a floor and it is the same floor. A necessary condition cannot refuse a large enough accident:
outliers that conspire into a consistent set bigger than the truth take the clique, and a conspiracy
whose pairs outnumber the clean ones takes the median. Both files sweep that floor in place of quoting
it, and both also sweep the benign case where the outliers merely scatter, because a method with two
ways to fail has two floors and one figure is the wrong shape for that.

Each carries a positive control, two routes shown able to disagree, a drawn null, and a stated floor.
A file earns a subject stage once it reads that subject's corpus; until then it earns this directory.

Everything in `examples/` sits at `<subject>/<stage>/`, and a file only earns that path once it is clear which corpus it reads and where in the walk it sits. Something that reads no corpus in particular, or sits between two stages, or was written to try an idea that has not been placed yet, goes here until one of those is settled.

## What belongs here

A script that answers a question nobody has assigned to a subject. A first attempt at a stage that does not exist for any subject yet. A reading whose corpus has not been fetched.

## What does not

**A failure does not belong here.** A stage that was tried and did not work is evidence and it stays in its subject beside the readings that came after it. The Dravidian family failing to appear under a codepoint reading sits in `language/4_measure`, next to the two readings that repaired it, because a reader who finds only the repair does not know what it repaired.

**A fetcher does not belong here.** Acquiring a corpus is not a stage of reading one. Those are in `maint/data/fetch/`.

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
