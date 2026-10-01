"""Does a BEAM reading of an early compression state predict the final digest?

    python tools/view/beam_read.py --check
    python tools/view/beam_read.py                  the sweep, both instruments, matched null

WHY THIS RUNS WHEN nonce_read.py ALREADY RETURNED NULL

nonce_read.py asked this exact question and came back null, and that null is real. But it was
measured with SIX SCALARS: weight, monopole share, dipole share, quadrupole share, fine-structure
share, and the zonal dipole. Five of those are POWER SHARES, and a power share is invariant under
rotation by construction. An instrument built out of rotation invariants cannot see orientation at
all, no matter how much orientation there is to see.

The state carries 256 numbers, one per bit, and that is not a guess: it is the rank bound this tree
has now measured four separate ways, most recently in beam_rows.py where 256 line integrals took
the stacked reading to rank 256 exactly. So the prior null covered a six-dimensional
rotation-averaged summary of a 256-dimensional object.

Douglas put it as the eyes seeing what is "invisible to you mathematically". That is the literal
situation: a region integral averages over a patch, and a line integral does not.

WHAT A BEAM IS AND WHY IT IS A DIFFERENT ROW TYPE

A harmonic row is a whole-sphere integral. An arm is a region integral. A BEAM is a LINE integral:
occlusion along a ray, weighted by perpendicular distance to it. beam_rows.py settled that a beam
is not in the span of the region rows, by closing the harmonic reading's entire 175-dimensional
kernel at degree 8 and taking the rank to the source count.

A beam also reads without perturbing: it is a passive occlusion measurement, which is the sense in
which it observes from outside without disturbing what it observes.

THE HONEST PRIOR, STATED BEFORE THE RUN

Null. The standing constraint in PARTITION.tsv is that no projection over the digest reduces the
number of evaluations, the transform workbook graded twenty hypotheses to null, and nonce_period.py
found no period across 75 tests. Nothing here contradicts that and this tool is not expected to.

What this tool adds is a null measured with a directional instrument and a stated detection limit,
rather than a null inherited from an instrument that was blind to direction. A null with a limit is
a result. A null asserted from a prior is not.

THE THREE CONTROLS, ALL OF WHICH MUST PASS FOR A NULL HERE TO MEAN ANYTHING

    1. THE BUILT-IN POSITIVE CONTROL IS FREE. The target is the leading zero count of state 64, so
       reading state 64 is reading the answer. That row MUST fire. If the loudest correlation at
       round 64 does not clear the null bar, the instrument is broken and every other row on the
       page is meaningless. This costs nothing and it is not optional.

    2. THE NULL IS DRAWN, NOT DERIVED. The bar is the 95th percentile of the LARGEST absolute
       correlation a shuffled pairing produces over the SAME number of features. Shuffling destroys
       any real relation while preserving every marginal. Taking the max in the null too is what
       makes 256 features and 81 features comparable: reporting the loudest of many against a
       single-feature threshold manufactures findings, and this tree has done that and written the
       rule down.

    3. THE LIMIT IS MEASURED BY INJECTION FADE. A correlation is blended into the target at a known
       strength and faded until it stops clearing the bar. The smallest strength still detected is
       what this sample could have seen, and it is the number that gives the null its meaning.

WHAT THIS TOOL DOES NOT CLAIM

It says nothing about qubits. The quantum representation question is a different one, answered in
exact_qubits.py and graph_machine.py, and bolting a qubit onto this measurement would be decoration
rather than apparatus. The eye is a classical line integral and that is the whole of it.
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PROOFING = os.path.join(ROOT, "examples", "proofing")
for _where in (HERE, PROOFING):
    if _where not in sys.path:
        sys.path.insert(0, _where)

import numpy

import beam_rows
import nonce_read
import state_deflection

COUNT = beam_rows.COUNT          # 256 sources, one per state bit
DEGREE = beam_rows.DEGREE        # 8, so the harmonic arm carries 81 coefficients
NONCES = 2048                    # more than nonce_read's 512: the limit scales as 1/sqrt(n)

# WHERE THE NONCE ENTERS, WHICH THE ROUND LIST IS BUILT AROUND. header_words puts the nonce in
# schedule word 15, and SHA-256 round r consumes schedule word r. So rounds 0 through 14 consume
# words 0 through 14, every one of which is identical across the sweep, and states[0] through
# states[15] are BIT-IDENTICAL for every nonce. states[16] is the first state the nonce has reached.
#
# Rounds 8 and 15 are therefore an EXACT NULL BY CONSTRUCTION and are in this list for that reason:
# they cost nothing, they must read exactly 0.0000, and any variance there is a wiring bug rather
# than a discovery. This is the same free control tail_bit.py documents for word 13.
NONCE_WORD = 15
FIRST_LIVE_ROUND = NONCE_WORD + 1
READ_AT = (8, 15, 16, 17, 20, 24, 32, 48, 64)
SHUFFLES = 200                   # the drawn null, matching nonce_read.py's count
CONFIDENCE = 95.0                # percentile of the shuffled max


def occupancy(state):
    """The 256 long indicator of which state bits are set, as a row of sources.

    This is the object the readings are taken OF. lit_of gives the set bits as indices and every
    index is in range 0..255 because the state is eight 32 bit words, so the vector is exactly the
    source count and the rank bound applies to it directly.
    """
    row = numpy.zeros(COUNT)
    for index in state_deflection.lit_of(state):
        row[index] = 1.0
    return row


def loudest(features, target):
    """The largest absolute Pearson correlation between any feature column and the target.

    Returns (value, column). Vectorised over columns on purpose: the null below needs this 200
    times per instrument per round, and a Python loop over 256 columns would make the drawn null
    expensive enough to tempt me into drawing fewer shuffles, which is the wrong economy.

    A constant column correlates with nothing and is excluded rather than producing a divide by
    zero that numpy would report as nan and argmax would then happily select.

    CONSTANCY IS TESTED EXACTLY AND NOT AGAINST A TOLERANCE, and this is a bug fix rather than a
    preference. The first version guarded with `spread > 1e-12`, an ABSOLUTE threshold on a quantity
    whose scale depends on how many sources are lit and how the rows are normalised. That produced a
    false positive with a very specific signature:

        at 2048 nonces, round 15 read exactly 0.0000
        at  192 nonces, round 15 read        0.0237

    Round 15 is before the nonce enters the state, so its columns are bit-identical and the answer
    has to be zero at every sample count. The difference was the sample count's factorisation. 2048
    is a power of two, so summing identical doubles pairwise is exact, the mean comes back exact,
    centring gives exactly zero and the column is excluded. 192 is not, so the mean lands a few ulp
    off, the residual noise on features of magnitude around 100 reaches about 1e-12, and it cleared
    the threshold and got correlated against the target like real data.

    A tolerance chosen by judgment is what made that possible. `max != min` needs no tolerance: it
    compares stored values, and rows computed from bit-identical inputs by identical arithmetic are
    bit-identical, a genuinely constant column is caught exactly at any sample count.
    """
    centred = features - features.mean(axis=0)
    spread = numpy.sqrt((centred * centred).sum(axis=0))
    aim = target - target.mean()
    aim_spread = float(numpy.sqrt((aim * aim).sum()))

    varies = features.max(axis=0) != features.min(axis=0)
    live = varies & (spread > 0.0)
    if float(target.max()) == float(target.min()) or aim_spread <= 0.0 or not live.any():
        return 0.0, -1

    correlations = (centred[:, live] * aim[:, None]).sum(axis=0) / (spread[live] * aim_spread)
    where = int(numpy.argmax(numpy.abs(correlations)))
    return float(abs(correlations[where])), int(numpy.flatnonzero(live)[where])


def null_bar(features, target, shuffles=SHUFFLES, seed=0):
    """The bar: the CONFIDENCE percentile of the loudest correlation under a shuffled pairing.

    The shuffle permutes the target and leaves the features untouched, which breaks the pairing
    while preserving both marginal distributions exactly. Drawing the bar this way rather than
    computing it from a t distribution is the rule in this tree, written down after three analytic
    floors in one session all came out too low.
    """
    generator = numpy.random.default_rng(seed)
    drawn = numpy.empty(shuffles)
    for at in range(shuffles):
        drawn[at] = loudest(features, generator.permutation(target))[0]
    return float(numpy.percentile(drawn, CONFIDENCE))


def sweep(nonces=NONCES):
    """Both readings of every read round, and the target, over `nonces` nonces on a real header.

    Batched into one matrix multiply per round rather than one per nonce. The occupancy matrix is
    (nonces x 256) and each reading map is (rows x 256), so the whole round is a single product.
    """
    points = beam_rows.source_points(COUNT)
    beams = beam_rows.beam_set(COUNT, points)
    harmonics = numpy.asarray(beam_rows.harmonic_rows(DEGREE, COUNT), dtype=float)

    filled = {round_at: numpy.empty((nonces, COUNT)) for round_at in READ_AT}
    target = numpy.empty(nonces)

    for at in range(nonces):
        states = state_deflection.states_of(nonce_read.header_words(at))
        target[at] = float(nonce_read.leading_zeros(states[64]))
        for round_at in READ_AT:
            filled[round_at][at] = occupancy(states[round_at])

    # THE MULTIPLY IS DONE OVER DISTINCT OCCUPANCY PATTERNS AND THEN MAPPED BACK, and that is a
    # correctness requirement rather than an optimisation.
    #
    # A plain `filled.dot(beams.T)` is a matrix-matrix product, and BLAS tiles those. Rows in
    # different tiles are summed in different orders, so two BIT-IDENTICAL input rows can come out
    # differing in the last ulp. At rounds before the nonce enters, every occupancy row is identical
    # and the readings should be too, but the tiling made them differ by rounding noise, `max !=
    # min` correctly reported that the column varied, and correlating that noise against the target
    # produced 0.207 at 192 nonces and 0.031 at 500 while 256 gave exactly 0.
    #
    # A tolerance would have papered over it at some sample counts and not others. Computing each
    # distinct pattern once makes identical states give identical readings by construction, so the
    # exact constancy test in loudest() is then reliable at every sample count. It is also never
    # slower: when every row is distinct this is the same work.
    readings = {}
    for round_at in READ_AT:
        block = filled[round_at]
        patterns, back = numpy.unique(block, axis=0, return_inverse=True)
        readings[round_at] = {
            "beam": patterns.dot(beams.T)[back],
            "harmonic": patterns.dot(harmonics.T)[back],
        }
    return readings, target, beams.shape[0], harmonics.shape[0]


def detection_limit(features, target, bar, seed=0):
    """The smallest injected correlation this sample still sees, found by fading it out.

    A null means nothing without this. The injection blends one real feature column into the target
    at strength `alpha` against independent noise, so the induced correlation is about alpha by
    construction, and the fade walks alpha down until the loudest reading stops clearing the bar.

    The blended column is a real reading column and not synthetic noise, so the injected signal has
    the same distributional shape as anything the instrument could genuinely find.
    """
    generator = numpy.random.default_rng(seed + 7717)
    centred = features - features.mean(axis=0)
    spread = numpy.sqrt((centred * centred).sum(axis=0))
    # Exact constancy test, for the same reason as in loudest(): a tolerance here would pick a
    # numerically dead column as the carrier and then the fade would measure nothing.
    live = numpy.flatnonzero((features.max(axis=0) != features.min(axis=0)) & (spread > 0.0))
    if live.size == 0:
        return None
    carrier = centred[:, live[0]] / spread[live[0]]

    noise = generator.standard_normal(features.shape[0])
    noise = (noise - noise.mean()) / numpy.sqrt((noise * noise).sum())

    for alpha in (0.50, 0.30, 0.20, 0.15, 0.10, 0.07, 0.05, 0.04, 0.03, 0.02, 0.015, 0.01):
        blended = alpha * carrier + numpy.sqrt(max(0.0, 1.0 - alpha * alpha)) * noise
        if loudest(features, blended)[0] <= bar:
            return alpha
    return 0.01


def _report(nonces=NONCES):
    print("  %d nonces on one real header shape, %d sources, one per state bit." % (nonces, COUNT))
    print("  The target is the leading zero count of state 64, so ROUND 64 IS THE POSITIVE CONTROL")
    print("  and it must fire. A null at round 64 means the instrument is broken.")
    print("")

    readings, target, beam_count, harmonic_count = sweep(nonces)
    print("  beam rows %d (line integrals), harmonic rows %d (degree %d region integrals)"
          % (beam_count, harmonic_count, DEGREE))
    print("  target spread %.4f over %d values, %d distinct"
          % (float(target.std()), target.size, int(numpy.unique(target).size)))
    print("")
    print("  %6s %11s %9s %9s %9s %9s" % ("round", "instrument", "loudest", "bar", "verdict", "limit"))

    fired = {}
    for round_at in READ_AT:
        for name in ("beam", "harmonic"):
            features = readings[round_at][name]
            value, column = loudest(features, target)
            bar = null_bar(features, target, seed=round_at)
            verdict = "FIRES" if value > bar else "null"
            limit = detection_limit(features, target, bar, seed=round_at)
            fired[(round_at, name)] = (value, bar, verdict)
            # A round before the nonce enters is labelled as construction, not as evidence. An
            # unlabelled 0.0000 in a results table reads as the strongest possible measurement when
            # it is in fact no measurement at all.
            note = "by construction" if round_at < FIRST_LIVE_ROUND else ""
            print("  %6d %11s %9.4f %9.4f %9s %9s   %s"
                  % (round_at, name, value, bar, verdict,
                     ("%.3f" % limit) if limit is not None else "-", note))
        print("")

    print("  READ THE TABLE, NOT THIS SENTENCE, and if they disagree the table is right.")
    print("")

    control = fired.get((64, "beam"), (0.0, 1.0, "null"))
    if control[2] != "FIRES":
        print("  THE POSITIVE CONTROL FAILED. Round 64 is the digest itself and the beam reading did")
        print("  not clear its own null bar (%.4f against %.4f). Every other row above is therefore"
              % (control[0], control[1]))
        print("  uninterpretable: a null from an instrument that cannot see a signal it is being")
        print("  handed directly is not evidence of absence. Fix this before reading anything else.")
        return 1

    # THE FREE EXACT NULL, CHECKED AND NOT ASSUMED. Every round before the nonce enters must read
    # exactly zero. If one of them does not, the sweep is reading a state the nonce never touched as
    # though it varied, which would mean the occupancy or the state indexing is wrong, and every
    # null below would be an artifact of that bug rather than a property of SHA-256.
    for (round_at, name), (value, _, _) in sorted(fired.items()):
        if round_at < FIRST_LIVE_ROUND and value != 0.0:
            print("  THE FREE NULL BROKE. Round %d is before the nonce reaches the state, so the" % round_at)
            print("  %s reading must be exactly 0.0000 and it read %.6f. That is a wiring bug in the"
                  % (name, value))
            print("  sweep, not a finding, and it invalidates the rest of this table.")
            return 1

    early = [(r, n) for (r, n), (_, _, v) in fired.items() if r != 64 and v == "FIRES"]
    if early:
        print("  SOMETHING FIRED EARLY, which is the outcome that would matter:")
        for round_at, name in sorted(early):
            value, bar, _ = fired[(round_at, name)]
            print("      round %d, %s reading: %.4f against a bar of %.4f" % (round_at, name, value, bar))
        print("  This needs a second header shape and a fresh seed before it is believed.")
    else:
        print("  Null at every round before 64, on both instruments, with the positive control")
        print("  firing. The beam reading is directional where the six scalars in nonce_read.py")
        print("  were rotation invariant, so this closes that gap rather than repeating it.")
        print("  The limit column is what the null is worth: a correlation below it would not have")
        print("  been seen by this sample.")

    # THE ONE POSITIVE RESULT, AND IT IS NOT ABOUT MINING. At round 64 there IS information, and the
    # two instruments do not read the same amount of it. The ratio is the measurement that supports
    # the claim the beams were built on: a line integral keeps directional information that a region
    # integral averages away. It says nothing about early rounds, where there is nothing to keep.
    beam_at_64 = fired.get((64, "beam"), (0.0, 0.0, ""))[0]
    harmonic_at_64 = fired.get((64, "harmonic"), (0.0, 0.0, ""))[0]
    if harmonic_at_64 > 0.0:
        print("")
        print("  WHERE THE EYES DO BEAT THE REGION ROWS, measured on the one round that carries a")
        print("  signal: at round 64 the beam reading reaches %.4f and the harmonic reading %.4f,"
              % (beam_at_64, harmonic_at_64))
        print("  a factor of %.2f on the same state, the same target and the same null."
              % (beam_at_64 / harmonic_at_64))
        print("  That is the directional information a power share averages away. It does not help")
        print("  a miner, because the early rounds have nothing for either instrument to find.")
    return 0


def _check():
    failed = 0
    print("")

    # THE ROW TYPES MUST ACTUALLY DIFFER, or this whole tool is nonce_read with more columns. The
    # claim inherited from beam_rows.py is that a beam is not in the span of the region rows, and it
    # is cheap to confirm here rather than trust across files.
    points = beam_rows.source_points(COUNT)
    beams = beam_rows.beam_set(COUNT, points)
    harmonics = numpy.asarray(beam_rows.harmonic_rows(DEGREE, COUNT), dtype=float)
    beam_rank = int(numpy.linalg.matrix_rank(beams))
    harmonic_rank = int(numpy.linalg.matrix_rank(harmonics))
    stacked = int(numpy.linalg.matrix_rank(numpy.vstack([harmonics, beams])))
    print("  beam rank %d, harmonic rank %d, stacked rank %d"
          % (beam_rank, harmonic_rank, stacked))
    if stacked <= harmonic_rank:
        print("    FAIL the beams add no rank, so they are inside the harmonic span")
        failed += 1
    if beam_rank < 2:
        print("    FAIL the beam set is degenerate")
        failed += 1

    # AN OCCUPANCY VECTOR MUST HAVE ONE ENTRY PER STATE BIT AND MUST BE AN INDICATOR.
    state = state_deflection.states_of(nonce_read.header_words(0))[16]
    row = occupancy(state)
    lit = len(state_deflection.lit_of(state))
    print("  occupancy length %d, %d lit, sum %.1f" % (row.size, lit, row.sum()))
    if row.size != COUNT or abs(row.sum() - lit) > 1e-9:
        print("    FAIL the occupancy vector does not match the lit set")
        failed += 1
    if set(numpy.unique(row).tolist()) - {0.0, 1.0}:
        print("    FAIL the occupancy vector is not an indicator")
        failed += 1

    # THE NULL MUST BE A REAL NULL. Correlating a reading against pure noise has to come back under
    # the bar; if it does not, the bar is wrong and every verdict above it is wrong with it.
    generator = numpy.random.default_rng(11)
    small, _, _, _ = sweep(192)
    features = small[16]["beam"]
    noise = generator.standard_normal(features.shape[0])
    value, _ = loudest(features, noise)
    bar = null_bar(features, noise, shuffles=60, seed=3)
    print("  reading against pure noise: %.4f against a bar of %.4f" % (value, bar))
    if value > bar:
        print("    FAIL noise cleared the null bar, so the bar does not hold")
        failed += 1

    # AND THE INSTRUMENT MUST FIRE ON A SIGNAL IT IS HANDED. The negative control above only proves
    # it is not credulous; this proves it is not blind, which is the failure that produces a
    # confident and worthless null.
    carrier = features[:, 0].copy()
    value, _ = loudest(features, carrier)
    bar = null_bar(features, carrier, shuffles=60, seed=5)
    print("  reading against one of its own columns: %.4f against a bar of %.4f" % (value, bar))
    if value <= bar:
        print("    FAIL the instrument cannot see a signal handed to it directly")
        failed += 1

    # THE SAMPLE COUNT MUST NOT CHANGE THE ANSWER FOR A CONSTANT COLUMN, and the cases here
    # deliberately straddle the property that caused the bug: 256 is a power of two and 192 and 500
    # are not. The absolute-tolerance version of loudest() passed the power of two and failed both
    # others, a single sample count would have hidden it either way.
    for count in (192, 256, 500):
        readings, target, _, _ = sweep(count)
        worst = 0.0
        for round_at in READ_AT:
            if round_at >= FIRST_LIVE_ROUND:
                continue
            for name in ("beam", "harmonic"):
                worst = max(worst, loudest(readings[round_at][name], target)[0])
        print("  %3d nonces: loudest reading before the nonce enters is %.6f" % (count, worst))
        if worst != 0.0:
            print("    FAIL a constant column produced a correlation at %d nonces" % count)
            failed += 1

    print("")
    print("  %d check(s) failed" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="a beam reading of the compression state")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--nonces", type=int, default=NONCES)
    args = parser.parse_args()

    if args.check:
        return 1 if _check() else 0
    return _report(args.nonces)


if __name__ == "__main__":
    sys.exit(main())
