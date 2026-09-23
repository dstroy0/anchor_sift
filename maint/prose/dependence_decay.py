"""Does the text remember? Mutual information against lag, and the shape of its decay.

THE QUESTION, AND WHY THE AFTERNOON'S INSTRUMENTS COULD NOT ANSWER IT

`claudese_distance` places a file between a human pole and an assistant pole and prints its own
limit at the foot: every file-level distance is a bag of words, so it reads COMPOSITION and never
ARRANGEMENT. A bag of words is invariant under permutation - shuffle the corpus and every count is
identical - so it cannot separate a text from its own shuffle, and it cannot say WHICH sentences
carry the register. That is not a flaw in the tool, it is what a bag of words is.

The gap is the whole question. Generated text is close to MEMORYLESS: it is sampled token by token
from a context window, so its long-range structure is whatever that window carries and no more.
Human writing is not memoryless. A person holds a subject across paragraphs and returns to it, so
dependence survives to ranges no window covers.

So the discriminator is not a score, it is a SHAPE: how fast dependence dies as the gap grows.

THE STATISTIC

Mutual information between the token at t and the token at t+k, swept in k:

    I(k) = sum over (x, y) of p(x,y) log2( p(x,y) / (p(x) p(y)) )

I(k) is zero exactly when the two positions are independent. Lin and Tegmark measured this shape for
natural language against Markov sources and found the separation is in the DECAY LAW: natural
language falls off as a power law, while anything with a bounded context falls off exponentially and
hits the floor. A power law is straight on log-log; an exponential is straight on log-linear and
drops off a cliff. That is a shape a curve can show and a single number cannot.

This is the same instrument as `bench_walk`'s autocorrelation sweep over lags 1 to 1024, pointed at
text instead of nonces, and it answers the same question: does this thing carry anything across a
gap, or does it forget.

THE NULL IS FREE AND IT IS DRAWN, NOT DERIVED

Estimated MI is biased UPWARD at finite sample: with V*V cells and limited counts, independent data
still produces a positive number, and the bias grows as the table gets sparse. Deriving that bias is
possible and this tree has a rule about deriving things - seven derived bars in one session, every
one too low, always the same direction.

So it is measured. Shuffling the tokens destroys arrangement and keeps every count identical, which
makes a shuffle EXACTLY the memoryless surrogate for this statistic. The floor at each lag is what
the shuffle produces at that lag, drawn several times. What gets reported is the excess over that
floor, so a decay to zero means decay to the point where this corpus at this size can no longer tell.

THE POSITIVE CONTROL IS THE POINT, NOT AN EXTRA

Both poles already exist in the tree, which is what makes this worth building rather than renting.
Human research papers are one, the assistant's own transcript is the other. If the human corpus does
not show a heavier tail than the assistant corpus, the instrument is not measuring what it claims
and no reading from it means anything. That check runs first and its verdict gates the rest, the
same way pi in the compressor gates a compression claim.

WHAT IT MEASURED, 2026-09-11, AND THE ANSWER IS NO

Run as built, on the two poles this tree already holds, it does NOT separate them. Recorded here
rather than in a note, because the intermediate readings all looked like findings and each one would
have been quoted if the next check had not been run.

    reading                                               what it turned out to be
    human clear to lag 1024, assistant dead by lag 3      the corpora differ ELEVEN TIMES in
                                                          length and MI bias grows as a corpus
                                                          shrinks. At equal length: 4 against 2.
    at equal length, floors 0.3707 against 0.5194         29 per cent apart, so an excess over
                                                          them compares two ESTIMATORS. Length was
                                                          not the whole nuisance parameter; the
                                                          unigram distribution sets the bias too.
    decay shape, -0.619 against -0.576                    the right direction, and inside the noise

The last one is the one that needed the null, and drawing it settled the question. Twenty-four
DISJOINT human chunks cut to the assistant corpus's exact length give slopes from -0.857 to -0.234,
mean -0.483, sd 0.129. The assistant sits at -0.587, which is 0.80 sd from the human mean, with FOUR
OF TWENTY-FOUR human chunks decaying at least as fast. That is an ordinary value for a human text of
this size.

So the -0.619 against -0.576 was within the ordinary spread and was never a finding.

WHAT THAT DOES AND DOES NOT SETTLE

It does not refute the hypothesis. Long-range dependence is real in natural language and the decay
law is the right discriminator. What it settles is that THIS test at THIS size has no power to see
it, and the binding constraint is named: the assistant corpus is 39,516 words, so every comparison
has to be made at that length, and the human band at that length is 0.129 wide - far wider than any
separation on offer.

The way forward is more assistant text, not a better statistic. At ten times the length the human
band narrows by about root ten and the same gap would be worth testing again.

THE RE-RUN WITH THIRTY-FOUR TIMES THE ASSISTANT TEXT. STILL NO.

1,313,144 words of assistant prose later, both poles cut into disjoint 200,000-token chunks so each
side carries a measured spread instead of the assistant being a single point:

    human       slope -0.4595   sd 0.1286   n 36   top-256 mass share 0.5279
    assistant   slope -0.4834   sd 0.1761   n  6   top-256 mass share 0.6122
    gap -0.0239, standard error 0.0750, 0.32 sd apart
    17 of 36 human chunks decay at least as fast as the assistant mean

Three things make this a stronger null than a small p-value usually is.

THE GAP SHRANK AS THE DATA GREW. At 39,516 words it was 0.104; at 200,000 it is 0.024. An effect that
is real tightens around a stable value as n rises. One that is noise walks toward zero, which is what
this did.

THE ASSISTANT SPREAD IS WIDER THAN THE HUMAN ONE, 0.1761 against 0.1286. The hypothesis says
generated text is closer to memoryless, so its decay should be tighter and steeper. It is neither. A
wider spread is evidence against the proposed mechanism rather than a failure to detect it.

THE NUISANCE WAS MEASURED AND IS NOT HIDING ANYTHING. Slope against top-256 mass share across all 42
chunks gives r = +0.269, so the share difference between the poles cannot be producing a difference
in slope, and matching on it would change nothing. That was checked rather than assumed, because the
earlier floor mismatch proved the nuisance was real at the LEVEL and it had to be ruled out at the
SHAPE separately.

WHAT IS STILL OPEN. Every word of that assistant corpus was written under this tree's ban list, so
the register is suppressed in the direction that works against a separation. A positive result there
would have been conservative; a null is genuinely ambiguous about unsuppressed prose. But the
wider-spread finding does not depend on the suppression and argues against the mechanism directly,
so an unsuppressed pole is less promising than it looked before this run.

AND THE HUMAN TAIL WAS THE CORPUS BEING ASSEMBLED. RETRACTED.

Alongside the null above this file reported a human tail: excess over the shuffle at every lag out to
1024, decaying smoothly, 0.0304 against a floor of 0.0984. It was offered as support for the claim
that long-range structure lives in content-word recurrence. It is not dependence and the claim loses
that support.

`load_papers` concatenates about 120 separate documents. Different papers use different words at
different rates, so composition DRIFTS across the joins, and drift raises MI at every lag - knowing
where you are in the corpus tells you which document you are in, and therefore which words are
likely. That is a fact about how the corpus was built and not about anything in the writing.

The two are separable exactly. Scramble the tokens inside every window of 100 and all arrangement
shorter than 100 words is destroyed while composition above that scale is untouched. Real dependence
at lag 256 cannot survive it. Drift is unaffected by it. Measured, --scramble:

    lag        as-is     scrambled
     256    0.040025      0.035006     survived
     384    0.036914      0.031646     survived
     512    0.035449      0.030720     survived
     768    0.033085      0.027101     survived
    1024    0.030351      0.023921     survived

Every large lag survives, so the tail was drift the whole way.

WHAT THIS DOES AND DOES NOT TOUCH. The two-band null stands unchanged: the decay SHAPE does not
distinguish the poles at 200,000 tokens, and the assistant spread is the wider of the two. Those were
computed on chunks and never rested on the tail. What falls is the tail itself and the support it
was lending.

A THIRD NUISANCE PARAMETER, AND IT IS THE ONE NOBODY CONTROLLED. Length was the first, the unigram
distribution the second, and ASSEMBLY is the third: how many source documents went into a corpus
sets its large-lag excess. Cutting both poles to 200,000 tokens controls chunk size and controls
neither the document count nor the join rate. Any two corpora built from different numbers of
sources separate at the large-lag end for free, and the separation says nothing about who wrote them.

The inversion is worth stating plainly, because it reverses the premise the whole line started from.
A continuous single-author work is the arm with the LEAST large-lag excess. Concatenated corpora
have the most. Large-k excess tracks how a corpus was assembled and is close to silent about the
writing inside it.

    python maint/prose/dependence_decay.py --control
    python maint/prose/dependence_decay.py --band
    python maint/prose/dependence_decay.py --twoband --length 200000
    python maint/prose/dependence_decay.py --scramble
    python maint/prose/dependence_decay.py --file docs/aiming-the-engine.md
"""

import argparse
import glob
import io
import os
import random
import re
import sys

import numpy

HERE = os.path.dirname(os.path.abspath(__file__))


def _trees(start):
    """Walk up until a directory holding anchor_sift is found, rather than counting parents.

    A fixed number of dirname calls encodes how deep this file happens to sit, and this tree has
    already lost a day to a path that was written down and then moved. Searching upward for the
    sibling is the same move link_shared.ps1 makes for the same reason.
    """
    at = start
    while at != os.path.dirname(at):
        if os.path.isdir(os.path.join(at, "anchor_sift")):
            return at
        at = os.path.dirname(at)
    return start


TREES = _trees(HERE)
ANCHOR = os.path.join(TREES, "anchor_sift")
PAPERS = os.path.join(ANCHOR, "build", "papers")
SESSION = os.path.join(ANCHOR, "build", "corpora", "session_prose.txt")

WORD = re.compile(r"[a-z']+")

# Lags are log spaced because the expected law is a power law, so the interesting axis is
# multiplicative. Sampling 1..64 evenly would spend every point where the curve is steep and none
# where the two hypotheses separate.
LAGS = (1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024)


def tokens_of(text, vocabulary=256):
    """Words as integer symbols, the commonest `vocabulary` kept and the rest merged.

    A JOINT TABLE IS V SQUARED CELLS AND THE COUNTS HAVE TO FILL IT. With a full vocabulary the
    table is emptier than the data, every cell holds zero or one, and the estimate is almost pure
    bias - the shuffle floor then sits on top of the signal and nothing is visible above it. Keeping
    the commonest few hundred words trades resolution for a table the corpus can actually fill.
    That is a choice about the estimator and not about the text, so the same choice is made for
    every corpus compared here.
    """
    words = WORD.findall(text.lower())
    counts = {}
    for word in words:
        counts[word] = counts.get(word, 0) + 1
    common = sorted(counts, key=lambda w: -counts[w])[:vocabulary - 1]
    index = dict((word, number) for number, word in enumerate(common))
    # Everything outside the kept vocabulary shares the last symbol.
    other = vocabulary - 1
    return numpy.fromiter((index.get(w, other) for w in words), dtype=numpy.int32,
                          count=len(words)), vocabulary


def mutual_information(symbols, lag, size):
    """I(X_t ; X_t+lag) in bits, from the joint counts at that lag."""
    if lag >= len(symbols):
        return 0.0
    left = symbols[:-lag]
    right = symbols[lag:]
    total = float(left.size)

    joint = numpy.bincount(left.astype(numpy.int64) * size + right,
                           minlength=size * size).astype(numpy.float64)
    joint /= total
    joint = joint.reshape(size, size)

    # The marginals are taken from the SAME pairing, not from the whole sequence, so that the
    # estimate is of the pair distribution actually observed and the shuffle floor is comparable.
    px = joint.sum(axis=1)
    py = joint.sum(axis=0)
    outer = numpy.outer(px, py)

    live = joint > 0.0
    return float(numpy.sum(joint[live] * numpy.log2(joint[live] / outer[live])))


def curve(symbols, size, draws=3, seed=0x5EED):
    """MI at each lag, the shuffle floor at each lag, and the excess."""
    rng = numpy.random.default_rng(seed)
    out = []
    shuffled = symbols.copy()
    for lag in LAGS:
        real = mutual_information(symbols, lag, size)
        floors = []
        for _ in range(draws):
            rng.shuffle(shuffled)
            floors.append(mutual_information(shuffled, lag, size))
        floor = sum(floors) / len(floors)
        out.append((lag, real, floor, real - floor))
    return out


def show(name, rows, words):
    print()
    print("  %s   %s words" % (name, format(words, ",")))
    print("    %6s %12s %12s %12s" % ("lag", "MI bits", "shuffle", "excess"))
    for lag, real, floor, excess in rows:
        mark = "" if excess > floor * 0.25 else "   <- at the floor"
        print("    %6d %12.6f %12.6f %12.6f%s" % (lag, real, floor, excess, mark))


def decay_shape(rows):
    """The log-log slope of the excess against lag, which is the statistic the hypothesis is about.

    WHY SHAPE AND NOT LEVEL. The excess at any one lag carries the estimator's bias, and that bias
    depends on corpus size and on the unigram distribution, neither of which is register. Comparing
    levels across two corpora compares their estimators. But the HYPOTHESIS was never about level:
    a power law and an exponential differ in how they fall, and that difference survives an overall
    scale factor.

    So each curve is divided by its own value at lag one and the slope is taken in log-log. A power
    law is a straight line there, with the exponent as the slope. An exponential curves downward and
    runs off the bottom. Dividing by lag one is what removes the scale the bias sets, so this is the
    same normalisation as dividing per-degree power by (2l+1) to make a spectrum flat.

    Returned as (slope, points used). Lags whose excess has gone non-positive are dropped rather
    than clamped, because a logarithm of a negative number is not a small number, it is nothing.
    """
    import math
    base = rows[0][3]
    if base <= 0.0:
        return None, 0
    xs = []
    ys = []
    for lag, real, floor, excess in rows:
        if excess <= 0.0:
            continue
        xs.append(math.log(float(lag)) if lag > 0 else 0.0)
        ys.append(math.log(excess / base))
    if len(xs) < 4:
        return None, len(xs)
    n = float(len(xs))
    mx = sum(xs) / n
    my = sum(ys) / n
    top = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    bottom = sum((x - mx) ** 2 for x in xs)
    if bottom == 0.0:
        return None, len(xs)
    return top / bottom, len(xs)


def reach(rows):
    """The largest lag whose excess still stands clear of the shuffle floor.

    "Clear" is a quarter of the floor rather than a sigma, because the floor here is a bias and not
    a noise band: three shuffles agree with each other closely, so the spread understates how far
    the estimate can sit from truth. A fraction of the bias is the honest bar and it is stated
    rather than tuned.
    """
    best = 0
    for lag, real, floor, excess in rows:
        if excess > floor * 0.25:
            best = lag
    return best


def load_papers(limit_words=400000):
    parts = []
    have = 0
    for path in sorted(glob.glob(os.path.join(PAPERS, "*.txt"))):
        try:
            body = io.open(path, encoding="utf-8", errors="replace").read()
        except Exception:
            continue
        parts.append(body)
        have += len(body.split())
        if have >= limit_words:
            break
    return "\n".join(parts)


def main():
    parser = argparse.ArgumentParser(description="Dependence decay against lag.")
    parser.add_argument("--control", action="store_true", help="human pole against assistant pole")
    parser.add_argument("--band", action="store_true",
                        help="draw the human slope band from disjoint equal-size chunks")
    parser.add_argument("--scramble", action="store_true",
                        help="is the human tail dependence, or document boundaries?")
    parser.add_argument("--twoband", action="store_true",
                        help="a band for each pole, both cut to --length, with the confound measured")
    parser.add_argument("--length", type=int, default=200000,
                        help="tokens per chunk; see the note on why longer is not better")
    parser.add_argument("--file", default=None)
    parser.add_argument("--vocabulary", type=int, default=256)
    given = parser.parse_args()

    print("=" * 78)
    print("  DOES THE TEXT REMEMBER? Mutual information against lag.")
    print("=" * 78)

    if given.scramble:
        # IS THE HUMAN TAIL DEPENDENCE, OR IS IT DOCUMENT BOUNDARIES?
        #
        # load_papers concatenates about 120 separate documents. Different papers use different
        # words at different rates, so the COMPOSITION drifts across the joins - and drift raises MI
        # at every lag, because knowing where you are in the corpus tells you which document you are
        # in and therefore which words are likely. That is not dependence at a distance. It is the
        # corpus having been assembled.
        #
        # The two are separable and the test is exact. Scramble the tokens INSIDE each window of 100
        # and every arrangement shorter than 100 words is destroyed, while composition above that
        # scale is untouched. Real dependence at lag 256 cannot survive that. Drift is unaffected by
        # it. So if the large-lag excess stands up after scrambling, the curve was never reading
        # dependence.
        span = 100
        human, size = tokens_of(load_papers(limit_words=400000), given.vocabulary)
        plain = curve(human, size, draws=3)

        rng = numpy.random.default_rng(0xA55E)
        mixed = human.copy()
        for at in range(0, mixed.size - span, span):
            piece = mixed[at:at + span]
            rng.shuffle(piece)
            mixed[at:at + span] = piece
        scrambled = curve(mixed, size, draws=3)

        print()
        print("  human pole, %s tokens, scrambled within every %d" % (format(human.size, ","), span))
        print()
        print("    %6s %12s %12s %12s %12s"
              % ("lag", "as-is", "its floor", "scrambled", "its floor"))
        for (lag, r1, f1, e1), (_, r2, f2, e2) in zip(plain, scrambled):
            print("    %6d %12.6f %12.6f %12.6f %12.6f" % (lag, e1, f1, e2, f2))

        print()
        print("=" * 78)
        print("  WHAT THE TAIL WAS")
        print("=" * 78)
        print()
        big = [(lag, e1, e2) for (lag, _, _, e1), (_, _, _, e2) in zip(plain, scrambled) if lag >= 256]
        survived = sum(1 for lag, e1, e2 in big if e2 >= e1 * 0.5)
        for lag, e1, e2 in big:
            print("    lag %4d   as-is %.6f   scrambled %.6f   %s"
                  % (lag, e1, e2, "SURVIVED" if e2 >= e1 * 0.5 else "destroyed"))
        print()
        if survived >= len(big) - 1:
            print("    The large-lag excess survives having every arrangement below %d words" % span)
            print("    destroyed, so it is not dependence at a distance. It is composition drift")
            print("    across the documents this corpus was concatenated from.")
            print()
            print("    So the human tail reported earlier is an artifact of corpus ASSEMBLY, and")
            print("    the claim it supported - that long-range structure lives in content-word")
            print("    recurrence - loses that support. Retracted here rather than elsewhere.")
        else:
            print("    The large-lag excess is destroyed by scrambling, so it was dependence at a")
            print("    distance after all and survives this check.")
        return 0

    if given.twoband:
        # BOTH POLES GET A BAND, WHICH IS A DIFFERENT TEST FROM THE ONE BEFORE.
        #
        # At 39,516 words the assistant side was ONE number against a human distribution. A point
        # cannot say whether it is a typical value for its own population or a draw from a wide one,
        # so that test could never have distinguished "the assistant decays faster" from "the
        # assistant sample happened to". With both bands measured the question becomes the one worth
        # asking, and it can also come back saying the assistant spread is as wide as the human one,
        # which would sink the hypothesis whatever the means do.
        #
        # WHY NOT SIMPLY USE EVERY WORD. The band narrows as 1/sqrt(L) and the number of DISJOINT
        # chunks available to estimate it falls as 1/L, and those fight. At the full 1.3M there are
        # three human chunks and the spread cannot be measured at all - which would print a large
        # separation against an unmeasurable band and look like the best result of the night. The
        # default sits where both are adequate.
        assistant_path = os.path.join(os.path.dirname(os.path.dirname(HERE)),
                                      "build", "corpora", "assistant_suppressed.txt")
        if not os.path.exists(assistant_path):
            print("  no assistant corpus at %s" % assistant_path)
            return 1

        length = given.length
        human, size = tokens_of(load_papers(limit_words=7000000), given.vocabulary)
        assistant, size = tokens_of(io.open(assistant_path, encoding="utf-8",
                                            errors="replace").read(), given.vocabulary)

        def bands(symbols, label, cap):
            out = []
            at = 0
            while at + length <= symbols.size and len(out) < cap:
                piece = symbols[at:at + length]
                # The top-256 mass share is the nuisance the floors exposed: it sets how the joint
                # table fills and therefore the bias. Recorded per chunk so its influence can be
                # MEASURED below instead of corrected for on faith.
                share = float(numpy.count_nonzero(piece != size - 1)) / float(piece.size)
                slope, _ = decay_shape(curve(piece, size, draws=2, seed=0x5EED + at))
                if slope is not None:
                    out.append((slope, share))
                at += length
            print("    %-10s %2d chunks of %s tokens" % (label, len(out), format(length, ",")))
            return out

        print()
        print("  cutting both poles into disjoint chunks")
        human_rows2 = bands(human, "human", 40)
        assistant_rows2 = bands(assistant, "assistant", 40)
        print()

        if len(human_rows2) < 4 or len(assistant_rows2) < 3:
            print("  NOT ENOUGH DISJOINT CHUNKS at this length to measure a spread. Lower --length.")
            return 1

        def summarise(rows):
            values = [v for v, _ in rows]
            mean = sum(values) / len(values)
            sd = (sum((v - mean) ** 2 for v in values) / max(len(values) - 1, 1)) ** 0.5
            shares = [s for _, s in rows]
            return mean, sd, len(values), sum(shares) / len(shares)

        hm, hs, hn, hshare = summarise(human_rows2)
        am, asd, an, ashare = summarise(assistant_rows2)

        print("    %-10s slope %+.4f  sd %.4f  n %2d   top-%d mass share %.4f"
              % ("human", hm, hs, hn, size, hshare))
        print("    %-10s slope %+.4f  sd %.4f  n %2d   top-%d mass share %.4f"
              % ("assistant", am, asd, an, size, ashare))
        print()

        # DOES THE NUISANCE ACTUALLY DRIVE THE SLOPE? Measured across every chunk of both poles
        # pooled, because if mass share and slope are uncorrelated then the difference in share
        # between the poles cannot be what produces a difference in slope, and no matching is needed.
        pooled = human_rows2 + assistant_rows2
        xs = [s for _, s in pooled]
        ys = [v for v, _ in pooled]
        mx = sum(xs) / len(xs)
        my = sum(ys) / len(ys)
        sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
        sxx = sum((x - mx) ** 2 for x in xs)
        syy = sum((y - my) ** 2 for y in ys)
        r = sxy / ((sxx * syy) ** 0.5) if sxx > 0 and syy > 0 else 0.0
        print("    slope against mass share, across all %d chunks:  r = %+.3f" % (len(pooled), r))
        if abs(r) < 0.3:
            print("      weak, so the share difference between the poles is not what moves the")
            print("      slope and matching on it would change nothing")
        else:
            print("      STRONG. The nuisance tracks the statistic, so any separation below may be")
            print("      the mass share talking. Match on it before believing the comparison.")
        print()

        # Welch, because the two bands have different sizes and different spreads and pooling them
        # would assume the thing being tested.
        se = ((hs * hs / hn) + (asd * asd / an)) ** 0.5
        gap = am - hm
        print("=" * 78)
        print("  RESULT")
        print("=" * 78)
        print()
        print("    gap %+.4f, standard error %.4f, so %.2f sd apart"
              % (gap, se, abs(gap) / se if se > 0 else 0.0))
        print()
        overlap = sum(1 for v, _ in human_rows2 if v <= am)
        print("    %d of %d human chunks decay at least as fast as the assistant MEAN"
              % (overlap, hn))
        print()
        if se > 0 and abs(gap) / se >= 3.0 and gap < 0 and abs(r) < 0.3:
            print("    The assistant pole decays faster, the separation is %.1f sd on two measured"
                  % (abs(gap) / se))
            print("    bands, and the nuisance does not track the statistic. That is a result.")
            print()
            print("    And it is CONSERVATIVE: every word of the assistant corpus was written under")
            print("    the ban list, so the register is suppressed in the direction that works")
            print("    against this separation. The unsuppressed pole would only widen it.")
        elif gap < 0 and se > 0 and abs(gap) / se >= 2.0:
            print("    Suggestive in the predicted direction at %.1f sd, which is not enough to"
                  % (abs(gap) / se))
            print("    call on a statistic with this much machinery under it. More assistant text")
            print("    or a larger --length is the move, subject to the chunk-count tradeoff.")
        else:
            print("    NO SEPARATION. The two bands overlap, so the decay shape does not")
            print("    distinguish these corpora at this length and this is a null.")
        return 0

    if given.band:
        # THE SLOPE COMPARISON NEEDED A NULL AND THIS DRAWS IT.
        #
        # One human slope against one assistant slope is two numbers, and the gap between them
        # (-0.576 against -0.619) means nothing without knowing how much a human slope varies from
        # one sample to the next. So the human corpus is cut into DISJOINT chunks of exactly the
        # assistant corpus's length and a slope is taken from each. That is the band a human text of
        # this size produces, drawn rather than argued, and the assistant's slope either sits inside
        # it or it does not.
        session_text = io.open(SESSION, encoding="utf-8", errors="replace").read()
        session, size = tokens_of(session_text, given.vocabulary)
        chunk = int(session.size)

        human_text = load_papers(limit_words=2000000)
        human, size = tokens_of(human_text, given.vocabulary)

        slopes = []
        at = 0
        while at + chunk <= human.size and len(slopes) < 24:
            piece = human[at:at + chunk]
            slope, _ = decay_shape(curve(piece, size, draws=2, seed=0x5EED + at))
            if slope is not None:
                slopes.append(slope)
            at += chunk

        session_slope, _ = decay_shape(curve(session, size, draws=2))

        slopes.sort()
        middle = sum(slopes) / len(slopes)
        spread = (sum((v - middle) ** 2 for v in slopes) / len(slopes)) ** 0.5
        below = sum(1 for v in slopes if v <= session_slope)

        print()
        print("  %d disjoint human chunks of %s words each" % (len(slopes), format(chunk, ",")))
        print()
        print("    human slopes    %.3f to %.3f, mean %.3f, sd %.3f"
              % (slopes[0], slopes[-1], middle, spread))
        print("    assistant slope %.3f" % session_slope)
        print()
        z = (session_slope - middle) / spread if spread > 0 else 0.0
        print("    the assistant sits %.2f sd from the human mean, and %d of %d human chunks"
              % (z, below, len(slopes)))
        print("    fall at or below it")
        print()
        if below == 0:
            print("    OUTSIDE THE BAND. No human chunk of this size decays as fast as the")
            print("    assistant corpus does. That is a real separation on a drawn null.")
        elif below <= max(1, len(slopes) // 20):
            print("    AT THE EDGE. Only %d of %d human chunks reach it, so this is suggestive"
                  % (below, len(slopes)))
            print("    and would want a larger human sample before it is called.")
        else:
            print("    INSIDE THE BAND. %d of %d human chunks decay at least as fast, so the"
                  % (below, len(slopes)))
            print("    assistant slope is an ordinary value for a human text of this length and")
            print("    the shape does NOT separate the poles. The -0.619 against -0.576 seen")
            print("    earlier was within the ordinary spread and is not a finding.")
        return 0

    if given.control or not given.file:
        if not os.path.isdir(PAPERS):
            print("  no human corpus at %s" % PAPERS)
            return 1
        human_text = load_papers()
        human, size = tokens_of(human_text, given.vocabulary)
        human_rows = curve(human, size)
        show("HUMAN POLE, research papers", human_rows, human.size)

        if not os.path.exists(SESSION):
            print("  no assistant corpus at %s" % SESSION)
            return 1
        session_text = io.open(SESSION, encoding="utf-8", errors="replace").read()
        session, size = tokens_of(session_text, given.vocabulary)
        session_rows = curve(session, size)
        show("ASSISTANT POLE, own transcript", session_rows, session.size)

        # SIZE IS THE NUISANCE PARAMETER AND IT HAS TO BE HELD FIXED.
        #
        # The poles differ by eleven times in length and their shuffle floors differ by five times -
        # 0.098 bits against 0.519 - because MI bias grows as a corpus shrinks and its joint table
        # empties. A comparison across that gap would report the LENGTH of the two corpora and call
        # it register, which is the fault this tree has caught more than once.
        #
        # So the human pole is cut to the assistant pole's exact token count and the comparison is
        # made there. The full-length human curve above is kept only to show what the instrument can
        # see when it is not starved; it is not what the verdict rests on.
        matched = human[:session.size]
        matched_rows = curve(matched, size)
        show("HUMAN POLE, cut to the assistant pole's length", matched_rows, matched.size)

        human_reach = reach(matched_rows)
        session_reach = reach(session_rows)
        print()
        print("=" * 78)
        print("  THE CONTROL, AT EQUAL LENGTH")
        print("=" * 78)
        print()
        print("    both corpora cut to %s words" % format(int(session.size), ","))
        human_floor = matched_rows[0][2]
        session_floor = session_rows[0][2]
        apart = abs(human_floor - session_floor) / max(human_floor, session_floor)
        print("    human floor %.4f, assistant floor %.4f, %.0f%% apart"
              % (human_floor, session_floor, apart * 100.0))
        print()

        # REFUSE, RATHER THAN PRINT THE WARNING AND CARRY ON.
        #
        # An earlier version of this file stated the floor-match requirement and then reported a
        # verdict regardless, which is a gate that advises instead of stopping - the same fail-open
        # shape as a linker that reports "created" without checking the link resolves.
        #
        # The floors are the estimator's bias at each corpus, and equal length does NOT equalise
        # them: bias depends on how the joint table fills, which is set by the unigram distribution.
        # Two corpora whose commonest words carry different mass produce different bias at identical
        # token counts. Comparing an excess-over-floor across mismatched floors compares two
        # different estimators and reports the difference between THEM.
        # THE SHAPE IS COMPARABLE EVEN WHERE THE LEVEL IS NOT, so it is computed either way and it
        # is what the verdict rests on when the floors refuse to match.
        human_slope, human_points = decay_shape(matched_rows)
        session_slope, session_points = decay_shape(session_rows)
        print("    decay shape, log-log slope of the excess normalised to its own lag one:")
        print("      human      %s  over %d lags"
              % (("%+.3f" % human_slope) if human_slope is not None else "  n/a", human_points))
        print("      assistant  %s  over %d lags"
              % (("%+.3f" % session_slope) if session_slope is not None else "  n/a", session_points))
        print()

        if apart > 0.10:
            print("    THE LEVELS ARE NOT COMPARABLE. The floors sit %.0f%% apart, so an excess"
                  % (apart * 100.0))
            print("    over them measures the two estimators and not the two corpora, and no")
            print("    verdict is returned from the lag-reach numbers.")
            print()
            if human_slope is not None and session_slope is not None:
                if session_slope < human_slope:
                    print("    THE SHAPE STILL SEPARATES THEM, and it is the statistic the hypothesis")
                    print("    was about. The assistant curve falls away faster, %+.3f against %+.3f,"
                          % (session_slope, human_slope))
                    print("    which is the direction predicted: bounded context forgets sooner. The")
                    print("    normalisation divides each curve by its own lag one, so the bias scale")
                    print("    cancels to first order and this survives the mismatch above.")
                    print()
                    print("    Treat it as SUGGESTIVE and not settled. The cancellation is first")
                    print("    order only, and the shape has no drawn null yet - fade a known-register")
                    print("    sample past it before it carries a verdict, the way bench_walk's")
                    print("    injection floor turned an unbounded null into 0.0625.")
                else:
                    print("    AND THE SHAPE DOES NOT SEPARATE THEM EITHER, %+.3f against %+.3f."
                          % (session_slope, human_slope))
                    print("    The instrument has nothing to say about these two corpora yet.")
            print()
            print("    Length is matched and this persists, so length was not the whole nuisance")
            print("    parameter. The remaining one is the unigram distribution: the assistant")
            print("    corpus concentrates more mass in its commonest words, which fills the joint")
            print("    table differently and moves the bias. Matching that - by sampling both to a")
            print("    common unigram distribution, or by using an estimator whose bias does not")
            print("    depend on it - is the work this instrument still needs.")
            print()
            print("    WHAT THE FULL-LENGTH RUN ABOVE IS AND IS NOT. Human dependence reaching lag")
            print("    1024 against the assistant's lag 2 is almost entirely the size difference,")
            print("    eleven times, and it is not evidence of anything about register. It is")
            print("    reported here so nobody quotes it later as though it were.")
            return 1
        print()
        print("    human dependence stands clear of its floor out to lag      %d" % human_reach)
        print("    assistant dependence stands clear of its floor out to lag  %d" % session_reach)
        print()
        if human_reach > session_reach:
            print("    The human corpus carries dependence further AT THE SAME LENGTH, so the")
            print("    separation is a property of the writing and not of how much of it there is.")
            print("    The instrument separates the poles in the direction the hypothesis")
            print("    predicts, and a reading from it means something.")
        else:
            print("    THE INSTRUMENT DOES NOT SEPARATE THE POLES. Every reading from it is void")
            print("    until that is fixed. Do not interpret any file with it.")
            print()
            print("    The corpora differ enormously in size, and MI bias grows as a corpus")
            print("    shrinks, so the likeliest cause is the comparison and not the text.")
            return 1
        return 0

    text = io.open(given.file, encoding="utf-8", errors="replace").read()
    symbols, size = tokens_of(text, given.vocabulary)
    rows = curve(symbols, size)
    show(given.file, rows, symbols.size)
    print()
    print("    dependence stands clear of the floor out to lag %d" % reach(rows))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
