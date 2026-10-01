"""Linear approximation: the predictive axis, which is neither distributional nor compressive.

The tests in this tree fall into two groups and pi passes both. Distributional tests - uniform bit
shares, flat autocorrelation, no co-variation - are satisfied by any sequence that looks fair.
Compression tests are satisfied by anything a compressor cannot find repetition in, and the digits
of pi defeat those completely despite having a kilobyte program.

What separates pi from noise is neither. It is that pi is REPRODUCIBLE: an independent method
computes the same digits, and agreement between two programs sharing no arithmetic is what proves
a generating program exists. That is a predictive test, not a statistical one.

The predictive test for a hash has a standard form. A linear approximation is a pair of masks with

    parity(alpha AND input)  XOR  parity(beta AND output)

biased away from one half. Any such bias is a PREDICTOR: it forecasts one parity of the output from
one parity of the input, better than chance, and that is the thing a distribution test cannot see
and a compressor cannot find. Matsui broke DES with approximations of this shape.

TRAINED AND TESTED ON DIFFERENT DATA

A bias measured on the same nonces it was selected from is a fit, not a finding, and over many mask
pairs the largest is always something. So masks are SELECTED on one range of nonces and their bias
is MEASURED on a disjoint range. Out-of-sample is the whole discipline: a real approximation holds
on nonces it never saw, an overfit one does not.

    python tools/audit/linear_bias.py
    python tools/audit/linear_bias.py --masks 40000 --train 200000 --test 200000
"""

import argparse
import hashlib
import math
import random
import struct


def digest_words(nonce):
    raw = hashlib.sha256(struct.pack("<Q", nonce)).digest()
    return int.from_bytes(raw, "big")


def parity(value):
    return bin(value).count("1") & 1


def bias_over(masks, first, count):
    """For each mask pair, how often the two parities agree over a nonce range."""
    agree = [0] * len(masks)
    for nonce in range(first, first + count):
        digest = digest_words(nonce)
        for index, (alpha, beta) in enumerate(masks):
            if parity(nonce & alpha) == parity(digest & beta):
                agree[index] += 1
    return agree


def main():
    parser = argparse.ArgumentParser(description="Out-of-sample linear approximation search.")
    parser.add_argument("--masks", type=int, default=6000)
    parser.add_argument("--train", type=int, default=60000)
    parser.add_argument("--test", type=int, default=60000)
    given = parser.parse_args()

    rng = random.Random(0x11BEA)
    masks = []
    for _ in range(given.masks):
        # Sparse masks on purpose: a dense mask's parity is a sum of many terms and averages out,
        # so the approximations worth finding are the thin ones.
        alpha = 0
        for _ in range(rng.randint(1, 3)):
            alpha |= 1 << rng.randrange(32)
        beta = 0
        for _ in range(rng.randint(1, 3)):
            beta |= 1 << rng.randrange(256)
        masks.append((alpha, beta))

    print("  %s mask pairs, %s training nonces, %s disjoint test nonces"
          % (format(given.masks, ","), format(given.train, ","), format(given.test, ",")))
    print()

    print("  selecting on the training range...")
    trained = bias_over(masks, 0, given.train)
    scored = []
    for index, agreed in enumerate(trained):
        deviation = (2 * agreed) - given.train
        scored.append((abs(deviation), index, deviation))
    scored.sort(reverse=True)

    se_train = math.sqrt(given.train)
    print("  loudest on training: %.2f sd  (selected from %s, so this number means nothing yet)"
          % (scored[0][0] / se_train, format(given.masks, ",")))
    print()

    keep = [scored[rank][1] for rank in range(min(12, len(scored)))]
    print("  measuring those same masks on nonces %s to %s, which they have never seen..."
          % (format(given.train, ","), format(given.train + given.test, ",")))
    tested = bias_over([masks[index] for index in keep], given.train, given.test)

    se_test = math.sqrt(given.test)
    print()
    print("    rank   alpha        beta (bit)   train sd   TEST sd")
    survived = 0
    for rank, index in enumerate(keep):
        alpha, beta = masks[index]
        train_sd = scored[rank][2] / se_train
        test_dev = (2 * tested[rank]) - given.test
        test_sd = test_dev / se_test
        if abs(test_sd) >= 4.0:
            survived += 1
        print("    %4d   0x%08x   %-10s %+8.2f   %+8.2f"
              % (rank, alpha, "0x%x" % beta if beta.bit_length() < 40 else "wide",
                 train_sd, test_sd))

    print()
    print("=" * 74)
    print("  READING")
    print("=" * 74)
    print()
    print("    A selected bias always looks large on the data it was selected from. The test")
    print("    column is the only one that carries information, and its bar is four standard")
    print("    errors because twelve masks are being reported.")
    print()
    if survived:
        print("    %d approximation(s) survived out of sample. That is a PREDICTOR: it forecasts" % survived)
        print("    one parity of the digest from one parity of the nonce, on data it never saw.")
    else:
        print("    None survived. Every bias that looked large on the training range collapsed on")
        print("    nonces it had not seen, which is what selection noise does and what a real")
        print("    approximation does not.")
        print()
        print("    This is the axis pi would FAIL. A sequence with a short program admits a")
        print("    predictor that holds out of sample, and that is why this test says something")
        print("    the compression test could not.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
