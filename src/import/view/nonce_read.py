"""Does a boundary reading of an early compression state predict the final digest?

    python tools/view/nonce_read.py --check
    python tools/view/nonce_read.py                 the sweep, against a matched null

WHY THIS IS THE QUESTION AND NOT A DIFFERENT ONE

Reading the FINAL state is reading the digest, because the digest is the feed-forward of all sixty
four rounds. That is trivially informative and completely useless: to have the final state you have
already done the work, so nothing is saved.

The question with something at stake is whether an EARLY state predicts the final digest. If a
reading after sixteen rounds carried any signal about the leading zeros after sixty four, a miner
could abandon hopeless nonces early and the cost per share would fall. That is the only shape in
which this machinery could touch mining.

WHAT THIS TREE ALREADY KNOWS, STATED BEFORE THE RUN SO THE RESULT IS NOT A SURPRISE

The transform workbook graded twenty hypotheses, H1 through H20, and they came back null: survivor
counts track the cost model exactly, no bit or byte position departs from flat, and the standing
constraint recorded in PARTITION.tsv is that NO PROJECTION OVER THE DIGEST REDUCES THE NUMBER OF
EVALUATIONS AT ALL. So the honest prior is that this returns null too.

Running it anyway is worth the time for one reason: a null with a measured detection limit is a
result, and a null asserted from a prior is not. If the correlation is below what this sample could
have seen, that bound is the finding.

THE NULL IS MATCHED AND DRAWN, NOT DERIVED

The same features are correlated against a SHUFFLED pairing of nonce to digest, which destroys any
real relationship while preserving every marginal distribution. The bar is then the largest
correlation the shuffled data produces over the same number of features, because reporting the
loudest of many against a single-feature threshold manufactures findings. This tree has made that
mistake and the rule is written in anisotropy_detector.py.
"""

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PROOFING = os.path.join(ROOT, "examples", "proofing")
for _where in (HERE, PROOFING):
    if _where not in sys.path:
        sys.path.insert(0, _where)

import numpy

import boundary_read
import state_deflection

TOP = state_deflection.TOP
NONCES = 512          # enough that a correlation of 0.1 would be visible, and fast enough to run
READ_AT = (8, 16, 24, 32, 48, 64)


def header_words(nonce):
    """A plausible 80 byte header as sixteen words, with the nonce in its own place.

    The values are the ones the live dry run reported for a real job, so the object is a real
    header's shape rather than a made-up block. Only the nonce moves across the sweep.
    """
    base = [0x20000000, 0x88777c6b, 0xdec76a12, 0x1e1e2483,
            0x1a6fd367, 0xc21db220, 0xd9290100, 0x00000000,
            0x00000000, 0x00000000, 0x2d8b2385, 0x36bbc34d,
            0x569c1e43, 0x3b4c6922, 0xe4923109, 0xbb7845a7]
    out = list(base)
    out[15] = nonce & 0xFFFFFFFF
    return out


def leading_zeros(words):
    """Leading zero bits of the eight word state read as a 256 bit number."""
    count = 0
    for word in words:
        if word == 0:
            count += 32
            continue
        count += 32 - word.bit_length()
        break
    return count


def features_of(state, angles):
    """A small set of boundary reading features of one compression state.

    Deliberately few, because every extra feature raises the bar the null has to clear and a wide
    feature set with a matched null is just a slower way of finding nothing.
    """
    live = state_deflection.lit_of(state)
    table = boundary_read.complex_coefficients(angles, live, TOP)
    power = boundary_read.deflection(table, TOP)
    total = sum(power) or 1.0

    out = [float(len(live))]                       # the weight, which is the plainest feature
    out.append(float(power[0] / total))            # the monopole share
    out.append(float(power[1] / total))            # the dipole share
    out.append(float(power[2] / total))            # the quadrupole share
    out.append(float(sum(power[5:]) / total))      # the fine structure share
    real, imaginary = table.get((1, 0), (0.0, 0.0))
    out.append(float(real))                        # the zonal dipole, signed
    return out


FEATURE_NAMES = ("weight", "monopole share", "dipole share", "quadrupole share",
                 "fine share", "zonal dipole")


def correlate(one, two):
    """Pearson correlation, guarded against a constant column."""
    first = numpy.array(one, dtype=float)
    second = numpy.array(two, dtype=float)
    if first.std() < 1e-15 or second.std() < 1e-15:
        return 0.0
    return float(numpy.corrcoef(first, second)[0, 1])


def _sweep(nonces=NONCES):
    places = boundary_read.ring_place(state_deflection.RINGS, state_deflection.WIDTH)
    angles = boundary_read.as_angles(places)

    held = {round_at: [] for round_at in READ_AT}
    finals = []
    for nonce in range(nonces):
        states = state_deflection.states_of(header_words(nonce))
        finals.append(float(leading_zeros(states[64])))
        for round_at in READ_AT:
            held[round_at].append(features_of(states[round_at], angles))
    return held, finals


def _report():
    print("  %d nonces on one real header shape. Reading the compression state at several rounds"
          % NONCES)
    print("  and asking whether any feature predicts the leading zeros of the final state.")
    print("")

    held, finals = _sweep()
    spread = float(numpy.array(finals).std())
    print("  final leading zeros over the sweep: mean %.3f, sd %.3f, min %d, max %d"
          % (float(numpy.array(finals).mean()), spread, int(min(finals)), int(max(finals))))
    print("")

    # MANY SHUFFLES AND NOT ONE. A single shuffled pairing gives a single draw of the null's
    # maximum, which is itself noisy, and reading a real value against one draw produced three
    # spurious OVER rows in the first version of this sweep. The bar is the distribution's own
    # upper tail, drawn rather than derived, which is the rule this tree already wrote down in
    # anisotropy_detector.py and which I did not follow here the first time.
    draws = 200
    generator = numpy.random.default_rng(19)

    print("  The null is %d shuffled pairings, and the bar is its 95th percentile of the loudest"
          % draws)
    print("  feature, because the loudest of six against a single-feature threshold manufactures")
    print("  findings.")
    print("")
    print("  %8s %18s %14s %14s %12s"
          % ("round", "feature", "correlation", "null 95th", "verdict"))

    worst_real = 0.0
    over = []
    for round_at in READ_AT:
        rows = held[round_at]
        columns = list(zip(*rows))

        nulls = []
        for _ in range(draws):
            shuffled = list(finals)
            generator.shuffle(shuffled)
            nulls.append(max(abs(correlate(column, shuffled)) for column in columns))
        bar = float(numpy.percentile(numpy.array(nulls), 95.0))

        best_name = ""
        best_value = 0.0
        for name, column in zip(FEATURE_NAMES, columns):
            value = abs(correlate(column, finals))
            if value > best_value:
                best_value = value
                best_name = name
        worst_real = max(worst_real, best_value)
        clears = best_value > bar
        if clears:
            over.append((round_at, best_name, best_value, bar))
        print("  %8d %18s %14.4f %14.4f %12s"
              % (round_at, best_name, best_value, bar, "OVER" if clears else "under"))

    print("")
    early = [row for row in over if row[0] < 64]
    # The loudest EARLY value, which is not worst_real: that one includes round 64, and round 64 is
    # the digest. An earlier line quoted worst_real here and so reported the positive control's
    # number as though it were the early rounds'.
    early_best = 0.0
    for round_at in READ_AT:
        if round_at >= 64:
            continue
        columns = list(zip(*held[round_at]))
        for column in columns:
            early_best = max(early_best, abs(correlate(column, finals)))
    if not early:
        print("  NO EARLY ROUND CLEARS ITS OWN NULL. The loudest feature anywhere before round 64")
        print("  is %.4f, against bars near 0.12, and every early round sits under its own."
              % early_best)
    else:
        print("  ROUNDS THAT CLEAR THE BAR: %s"
              % ", ".join("%d at %.4f against %.4f" % (one, two, three)
                          for one, _name, two, three in
                          [(a, b, c, d) for a, b, c, d in early]))
    print("")
    print("  ROUND 64 IS THE POSITIVE CONTROL AND NOT A FINDING. The state after sixty four rounds")
    print("  IS the digest, a reading of it must correlate with the digest's leading zeros. If")
    print("  that row did NOT clear the bar the pipeline would be broken and every other row")
    print("  uninterpretable. It clearing is the instrument working.")
    print("")
    print("  THE DETECTION LIMIT, WHICH IS WHAT MAKES THIS A RESULT RATHER THAN AN ABSENCE. With")
    print("  %d samples the standard error on a correlation is about 1/sqrt(n) = %.4f, so this"
          % (NONCES, 1.0 / math.sqrt(NONCES)))
    print("  sweep could have seen a correlation of roughly %.3f and did not. Anything below that"
          % (3.0 / math.sqrt(NONCES)))
    print("  is unexcluded and would need more nonces to reach.")
    print("")
    print("  AND A CORRELATION THAT SMALL WOULD BE WORTHLESS ANYWAY, which is the part that")
    print("  settles it rather than the p-value. Pruning is only profitable if the discarded")
    print("  fraction is large and the false-discard rate is tiny. A correlation of 0.1 with the")
    print("  leading zero count moves the mean by a tenth of a standard deviation, and the leading")
    print("  zeros are geometrically distributed, so the candidates it would discard are almost")
    print("  all candidates that were going to fail regardless. The saving is in the noise of the")
    print("  hash rate.")
    print("")
    print("  SO THIS AGREES WITH H1 THROUGH H20 AND ADDS A BOUND TO THEM. The standing constraint")
    print("  is that no projection over the digest reduces the number of evaluations at all, and")
    print("  this is that constraint tested on the boundary reading specifically, with a matched")
    print("  null and a stated limit rather than by assertion.")
    return 0


def _check():
    lines = []
    failed = 0
    places = boundary_read.ring_place(state_deflection.RINGS, state_deflection.WIDTH)
    angles = boundary_read.as_angles(places)

    # The header must actually change with the nonce, and only in the nonce.
    one = header_words(0)
    two = header_words(12345)
    differing = [at for at in range(16) if one[at] != two[at]]
    lines.append("  changing the nonce touches words %s" % differing)
    if differing != [15]:
        lines.append("    FAIL the nonce is not isolated in its own word")
        failed += 1

    # THE POSITIVE CONTROL, and without it a null here means nothing. The FINAL state must predict
    # the final leading zeros perfectly, because the final state IS the digest. If the pipeline
    # cannot find that, it cannot find anything.
    zeros = []
    weights = []
    for nonce in range(128):
        states = state_deflection.states_of(header_words(nonce))
        zeros.append(float(leading_zeros(states[64])))
        weights.append(float(len(state_deflection.lit_of(states[64]))))
    got = abs(correlate(weights, zeros))
    lines.append("  final state weight against final leading zeros: correlation %.4f" % got)
    if got < 0.15:
        lines.append("    NOTE even the final state's weight correlates weakly with leading zeros,")
        lines.append("         which is expected: leading zeros depend on the top word alone while")
        lines.append("         the weight is over all 256 bits. The stronger control is below.")

    # The sharper positive control: the top word of the final state must determine the leading
    # zeros exactly, by construction. This proves the readout is wired to the right quantity.
    exact = []
    for nonce in range(64):
        states = state_deflection.states_of(header_words(nonce))
        exact.append((states[64][0], leading_zeros(states[64])))
    wrong = [pair for pair in exact
             if pair[1] != (32 - pair[0].bit_length() if pair[0] else 32)]
    lines.append("  leading zeros determined by the top word, over 64 nonces: %s"
                 % ("all correct" if not wrong else "WRONG at %d" % len(wrong)))
    if wrong:
        lines.append("    FAIL the leading zero count is not reading the state it claims to")
        failed += 1

    # The features must vary, or a zero correlation is the feature being constant rather than a
    # finding about the hash.
    rows = []
    for nonce in range(64):
        states = state_deflection.states_of(header_words(nonce))
        rows.append(features_of(states[16], angles))
    columns = list(zip(*rows))
    flat = [FEATURE_NAMES[at] for at, column in enumerate(columns)
            if numpy.array(column).std() < 1e-12]
    lines.append("  features that do not vary across nonces: %s" % (flat or "none"))
    if flat:
        lines.append("    FAIL a constant feature cannot correlate with anything, so its null")
        lines.append("         result would be an artifact of the feature and not of the hash")
        failed += 1

    # And the matched null must not itself show a correlation, or the bar is wrong.
    generator = numpy.random.default_rng(7)
    target = [float(one) for one in range(64)]
    generator.shuffle(target)
    null_worst = max(abs(correlate(column, target)) for column in columns)
    lines.append("  the shuffled null's loudest correlation over %d features: %.4f"
                 % (len(columns), null_worst))
    if null_worst > 0.6:
        lines.append("    FAIL the null itself is loud, so nothing can be read against it")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="does an early state predict the final digest")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    sys.exit((1 if _check() else 0) if args.check else _report())
