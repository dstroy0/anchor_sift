# What the instruments cannot see

A night of measurement produced a stack of null results about SHA-256 and one finding that matters
more than any of them: **the digits of pi pass every test in this tree, and the digits of pi compress
to about a kilobyte.**

That is not a remark about pi. It means the battery assembled here - uniform bit shares, flat
autocorrelation, full algebraic degree, no co-variation between output positions, incompressible to
LZMA - is exactly the battery a sequence with a short generating program sails through. Reporting
"no structure found" on the strength of it says less than it appears to.

This document records what was measured, at what scope, and which instruments were found unable to
see what they were pointed at.

## The instrument faults, first

Five, all in the same direction, every one producing an apparent finding, every one caught by a
result being too clean rather than by care beforehand.

**A statistic read off the top of a sort.** The deepest timestamp reversals appeared to cluster near
280 seconds. They were the eight largest values of a sorted list, which are close together by
construction. The full population shows no band.

**Three noise floors derived rather than drawn.** A shuffle of hour LABELS that returned identical
counts every draw and printed a standard deviation of 0.00. A per-pool phase bar set at two Poisson
floors when the statistic was a maximum minus a minimum over twenty-four bins, which spans three and
a half to four and a half by construction - so every pool cleared a bar that sat below chance, and
twenty hours of random trough hours read as geography. And a window-scatter floor from chi-square's
variance carried through a logarithm, giving 0.0582 where shuffling gives 0.1015.

**A generator with a period.** Survey arms built as `at * (2*arm + 37) + 11 + 97*arm mod 256` are
linear in the arm index, so both terms wrap together every 256 arms: arm 0 and arm 256 produced
byte-identical headers. Nine hundred thirty one files held two hundred fifty six distinct arms, up
to four copies each, and the duplication inflated the summed squared z from 256 to 942 - which read
as a thirty sigma discovery and reproduced the duplication factor to within one per cent. Headers
are now hashed from the arm index rather than stepped from it.

**A test whose answer was geometry.** Reading a state through a mirrored helix appeared to test the
handedness of SHA-256, which is chiral by design: six rightward rotations and no leftward one. But
reflecting a point set negates every longitude, which conjugates every coefficient, which negates
every phase, for any data whatever. The result was fixed before the data was consulted and came back
at 1e-16, which is float64's floor.

**A scalar standing in for a structure.** Per-degree power is invariant under all of SO(3), and
reporting it alone implies that magnitude and phase separate cleanly. They separate only on rotations
about the reading axis. Under a general rotation the coefficients mix, magnitude redistributes across
orders inside a degree, and the summed power is preserved because that mixing cancels - not because
nothing moved. Summing over orders is precisely the operation that makes the mixing invisible.

## What was actually established, at its real scope

**On SHA-256, bounded rather than proven flat.** Across 550 billion evaluations spanning 256
genuinely distinct headers, the output bits are individually unbiased to about four parts in a
million and carry no co-variation a permutation null cannot produce. Exhaustive Walsh-Hadamard over
262144 input masks per output bit finds no linear approximation that survives on nonces it did not
see; every in-sample maximum sits below the null's own expected maximum. The algebraic degree in the
nonce bits saturates by round eight, so no transform has fewer coefficients than points to ride.
Reversing every rotation gives a function statistically identical to the standard one - avalanche
means differ by a third of a standard error and both reach half the output at round eighteen - so
handedness is cosmetic and the rotation amounts carry the diffusion.

Every one of those is a bound with a domain, not an absolute. A finite observation of an unbounded
input space can bound an effect and can never establish absence.

**On the block header, a real and large signal.** The sixteen bits BIP320 reserves for version
rolling give away 1.82 bits of collision entropy, which is 588 times the floor chance produces at
that width and depth, and 45.7 per cent of what the field could carry. Per-bit shares run from -5 to
-51 standard errors against a swept counter's prediction, and the whole distribution is bimodal with
spikes on exact powers of two: conventions, not a sweep. The leak also moves, at p = 0.010 against a
shuffle null, which is software being deployed and retired inside a forty eight day window.

**On the clocks, a physical effect cleanly separated.** Timestamps in 2.98 per cent of blocks precede
their own parent's, by up to 395 seconds. The clocks tick correctly - low-bit shares reach 3.10
against a calibrated null of 3.35, and residues mod ten give chi-square 9.9 on nine degrees of
freedom - and the mining process is a clean Poisson at sd/mean 0.9879. So the effect is offset, not
drift and not granularity, and the magnitudes are four orders past anything NTP produces.

**And the separation that ties them together.** The tilt lives in the fields miners CHOOSE and is
absent from the field the function PRODUCES. Across 178 testable digest positions, conditioned per
block on its own target, the loudest reads +2.78 standard errors against a 3.22 bar. Same eighty
bytes, same blocks, same miners.

## What has no instrument

The gap between a description of about a thousand bits and a search costing two to the forty eight
is what a one-way function is, and nobody has proven one exists. SHA-256's hardness is conjectural.
Every measurement above assumed the gap and confirmed its local consequences, which is circular, and
the pi control is what exposed the circle.

Kolmogorov complexity is uncomputable, so no tool decides it. A compressor gives an upper bound:
compression proves structure, failure to compress proves nothing, because a compressor hunts
repetition and a generating program is not repetition. Measured directly, pi compresses to 1.0010
against random's 1.0001 - the positive control fails completely, and any claim of the form "it does
not compress, therefore no structure" is a statement about zlib.

What does separate pi from noise is neither distribution nor compression. It is reproducibility: an
independent method computes the same digits, and agreement between two programs sharing no arithmetic
is what demonstrates a generating program. That is a predictive test, and the predictive test for a
hash is the linear approximation search, which is the one axis above that pi would fail.

## Reading the interior instead of the boundary

Every measurement above reads a digest, which is the boundary of the computation. That is the right
shape for a physical system, where the interior cannot be reached and has to be inferred from what
escapes. It is the wrong shape here, and the reason is worth stating plainly: nothing about this
interior is hidden. The schedule words, the eight state words at every round, and the six values
built inside a round - s1, ch, t1 on one chain and s0, maj, t2 on the other - are all readable at
every instant. The boundary framing was self-imposed.

Read that way, one flipped input bit shows something the digest cannot.

| intermediate | first round it moves at all |
| --- | --- |
| s1, t1, s0, t2 | 2 |
| ch, maj | 3 |

The nonlinear functions lag the linear ones by a round, and the lag persists: at round seventeen the
linear values sit at 15.5 to 16.0 bits of difference while Choose and Majority sit at 14.3 and 14.8.

The mechanism is in their definitions. Choose is (e and f) xor (not e and g), so where f and g AGREE
at a bit position the result does not depend on e there at all. Majority cannot be moved by one of
three inputs either. So the nonlinear functions absorb the first arrival and pass it on only once a
second input has been reached. A digest sums all six paths into one number and cannot say which
carried what.

## The rules, which are a different kind of statement

Everything above is a frequency, and a frequency needs a null, a bar and an argument. The support
does not. For a single-bit input difference, an output position either moves or it never does, and a
position that never moves in six hundred excitations is not rare - it is forbidden, and every
trajectory requiring it is ruled out outright.

| rounds | reachable of 256 | forbidden | share |
| --- | --- | --- | --- |
| 1 | 0.0 | 256.0 | 100.0% |
| 3 | 7.3 | 248.7 | 97.1% |
| 5 | 24.4 | 231.6 | 90.5% |
| 7 | 42.0 | 214.0 | 83.6% |

At round seven, 214 of 256 positions are forbidden to a single input bit. The support grows about
nine positions a round after the third, which puts the grammar's closing near round thirty - and
that is consistent with the avalanche independently reaching 126 bits moved by round twenty. So the
function spends roughly its first thirty rounds before every input can reach every output, and its
remaining thirty-four past the point where the support constrains anything.

This is the sharpest result here and the only one that needs no statistics to stand up. Its limit is
equally sharp: forbidden transitions prune trajectory SEARCHES, which is what differential
cryptanalysis does. Mining evaluates forward and searches no trajectories, so the grammar does not
help there.

## Two response measurements whose verdicts were wrong

Recorded because the faults are the same shape as the others and both were caught after the fact.

**Susceptibility reported "clears" and did not.** The loudest cell of the real 512 by 256 table read
-4.33 standard errors against a null table's loudest of -4.11, and the code called that a clearance.
A maximum over 131072 cells is itself a random variable with real spread, so one draw of it is not a
bar. The seventh derived threshold in this work, again too low.

**The pair response has no power at all.** Flipping two input bits and comparing against the
exclusive-or of the two single differences gives 128.012 bits, and the null arm gives 127.938. Both
are pinned at 128, which is half of 256 and therefore complete decorrelation - the statistic is
saturated in both arms and cannot discriminate. The commentary written alongside it called the
excess "the nonlinearity", which implies it carries information. It does not.

**And a lead that dissolved at depth.** At 1200 samples the per-bit batch-to-batch swing had a
loudest of 1.394 with the top swingers uniformly cold, which looked like a second channel invisible
to a heat map. At 60000 samples the null arm's own loudest is 1.3965, no bit clears it, and the
correlation between swing and heat is -0.0671 inside a band of 0.1250. The anticorrelation was the
artifact, not the signal.

## The tools

    tools/audit/compressibility.py   the pi arm, permanently, so no null here escapes it
    tools/audit/walsh_bias.py        every input mask by transform, not a sampled few
    tools/audit/handedness.py        SHA-256 against its mirror, rotations reversed
    tools/audit/spectral_bench.py    invariance shown alongside the mixing it cancels
    tools/audit/comb_arms.py         pooled depth and sign agreement, separated
    tools/audit/agglomerate.py       co-variation, which every other test here is blind to
    tools/audit/chirality.py         a placement validator, which is what it turned out to be
    tools/audit/compare_corpus.py    the clean survey against the contaminated chain
    tools/audit/collision_entropy.py every reading in one comparable unit
    tools/audit/watchdog.py          calibrated models instead of guessed thresholds
    tools/audit/propagation.py       one flip through every interior value, not just the digest
    tools/audit/grammar.py           the support: what is forbidden, which needs no null
    tools/audit/response.py          susceptibility, pair response, decay - two verdicts corrected
    tools/audit/anisotropy_detector.py  flat baseline, drawn bar, names the angular scale
    tools/audit/sniffer.py           two stages over disjoint classes, validated before believed
    tools/audit/sniffer_bakeoff.py   any new scanner proves itself on planted structure first
    examples/proofing/relation_search.py   integer relations, gated both directions
    examples/proofing/bbp_search.py        formula search, gated by rediscovering pi's

## The one that can return a discovery

Everything above returns a bound or a null. The relation search returns a statement: a closed form
either holds or it does not, and anyone can check it in an afternoon without repeating the work.

Its control is the 1996 BBP formula for pi. Pointed at base sixteen, power one, stride eight, the
pipeline returns an exact relation, and the known formula holds on the same values to 895 bits of
900 - the remainder being the series truncation. The relation is not unique: Bailey's compendium
notes in its Section 11 that the auxiliary sums satisfy zero relations among themselves, so the
exact relations form a lattice and the known formula is one member. Demanding a particular member was
the wrong control and reported a correct answer as a failure.

Two regions are closed and should not be searched. Borwein, Galway and Borwein proved in 2004 that pi
has no degree-one BBP formulas in a power-of-two base beyond the three already known.

## References

1. Bailey, D. H. (2023). *A Compendium of BBP-Type Formulas for Mathematical Constants.*
2. Bailey, D. H., Borwein, P. B. and Plouffe, S. (1997). "On the Rapid Computation of Various
   Polylogarithmic Constants." *Mathematics of Computation* 66(218), pp. 903-913.
3. Borwein, J. M., Galway, W. F. and Borwein, D. (2004), on the exhaustion of degree-one BBP
   formulas for pi in power-of-two bases.
4. Matsui, M. (1993). "Linear Cryptanalysis Method for DES Cipher." *EUROCRYPT '93.*
5. Webster, A. F. and Tavares, S. E. (1986). "On the Design of S-Boxes." *CRYPTO '85*, pp. 523-534.
6. Vaughn, R. and Borowczak, M. (2026). "Relaxation of Strict Avalanche Criterion on All SHA-256
   Sub-Function Combinations." *Cryptography* 10(3), 32.
7. Rohling, H. (1983). "Radar CFAR Thresholding in Clutter and Multiple Target Situations." *IEEE
   Transactions on Aerospace and Electronic Systems* 19, pp. 608-621.
8. BIP320, *nVersion bits for general purpose use*; BIP310, Moravec and Capek, *Stratum protocol
   extensions*.
9. National Institute of Standards and Technology (2015). *FIPS PUB 180-4: Secure Hash Standard.*
