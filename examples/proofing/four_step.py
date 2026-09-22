"""The four-step fold: an N point transform folded into two passes of about root N.

    python examples/proofing/four_step.py --check      the fold against a direct transform

WHAT THE FOLD IS

A transform of length N = P * Q does not have to be run as one length-N pass. Splitting the index
turns it into P point transforms and Q point transforms with a layer of twiddles between them, and
each of those is small enough to sit in fast memory, and that alone is why a large transform is
fast on real hardware: the work never leaves the cache, or on a card the shared memory, because the
pieces are root N and not N.

THE DERIVATION, so the code is not a copied recipe

Write the transform X[k] = sum over n of x[n] w^(n k), with w a primitive N-th root of unity. Split
both indices with N = P * Q:

    n = Q*a + b     a in [0,P),  b in [0,Q)
    k = P*d + c     c in [0,P),  d in [0,Q)

Then n*k expands and the cross term PQ*a*d vanishes because w^(PQ) = w^N = 1, leaving

    w^(n k) = (w^Q)^(a c) · w^(b c) · (w^P)^(b d)

with w^Q a primitive P-th root and w^P a primitive Q-th root. So

    X[P*d + c] = sum over b of (w^P)^(b d) · [ w^(b c) · sum over a of x[Q*a + b] (w^Q)^(a c) ]

which reads off as three steps and a transposed placement:

    1. for each b, a P point transform over a of the strided slice x[b], x[Q+b], x[2Q+b], ...
    2. multiply entry (c, b) by the twiddle w^(b c)
    3. for each c, a Q point transform over b
    4. place the result at index P*d + c

WHAT IS CHECKED

The fold has to be the SAME map as the direct transform, bit for bit, at every length and on every
modulus. A direct transform is written here at O(N^2), slow and obviously correct, and the fold is
graded against it. Then a convolution taken through the fold is graded against Python's own multiply,
because a transform that round trips can still be the wrong transform, and only a convolution catches
a wrong twiddle. This is the reference the CUDA four-step is built to match; a bit that differs here
is a bug to fix before any of it reaches the card.
"""

import argparse
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import twiddle_proof

# A proven modulus and its proven generator, from twiddle_proof. Named here so the fold and its
# proof sit together.
PRIME = 2013265921          # 15 * 2^27 + 1, Proth witness 11
GENERATOR = 31


def root_of(length, prime, generator, inverse=False):
    """A primitive `length`-th root of unity modulo `prime`, or its inverse.

    Every argument is explicit. An earlier version defaulted `prime` and `generator` to module
    globals, which Python binds at definition time, so rebinding the globals to test a second
    modulus changed nothing and the fold ran on the wrong generator. The gate caught it at once.
    """
    root = pow(generator, (prime - 1) // length, prime)
    return pow(root, prime - 2, prime) if inverse else root


def direct(values, prime, root):
    """The transform by its definition, O(N^2), slow and beyond doubt. The reference the fold meets."""
    n = len(values)
    powers = [pow(root, k, prime) for k in range(n)]
    out = []
    for k in range(n):
        total = 0
        step = (k) % n
        for j in range(n):
            total += values[j] * powers[(j * k) % n]
        out.append(total % prime)
    return out


def fold(values, prime, generator, length, inverse=False):
    """The transform of `values` by the four-step fold, into P and Q point passes.

    P and Q are chosen as balanced powers of two, so each pass is about root N. The sub-passes use
    the direct transform here, because the point of this file is to prove the FOLD; on the card the
    sub-passes are the shared-memory butterflies, and they are graded against this.
    """
    if length & (length - 1):
        raise ValueError("the fold wants a power of two length")
    bits = length.bit_length() - 1
    p_bits = bits // 2
    outer = 1 << p_bits           # P
    inner = length // outer       # Q

    root = root_of(length, prime, generator, inverse=inverse)
    root_p = pow(root, inner, prime)   # a primitive P-th root, w^Q
    root_q = pow(root, outer, prime)   # a primitive Q-th root, w^P

    # Step 1: for each b in [0, Q), a P point transform over the strided slice x[Q*a + b].
    columns = []
    for b in range(inner):
        slice_b = [values[inner * a + b] for a in range(outer)]
        columns.append(direct(slice_b, prime, root_p))   # indexed by c in [0, P)

    # Step 2: twiddle entry (c, b) by w^(b c).
    for b in range(inner):
        for c in range(outer):
            columns[b][c] = columns[b][c] * pow(root, (b * c) % length, prime) % prime

    # Step 3: for each c in [0, P), a Q point transform over b.
    rows = []
    for c in range(outer):
        slice_c = [columns[b][c] for b in range(inner)]
        rows.append(direct(slice_c, prime, root_q))       # indexed by d in [0, Q)

    # Step 4: place at index P*d + c. The inverse also scales by 1/N at the end.
    out = [0] * length
    for c in range(outer):
        for d in range(inner):
            out[outer * d + c] = rows[c][d]

    if inverse:
        scale = pow(length, prime - 2, prime)
        out = [value * scale % prime for value in out]
    return out


def convolve(left, right, prime, generator):
    """The cyclic convolution of two sequences through the fold, for the multiply check."""
    length = 1
    while length < len(left) + len(right):
        length <<= 1
    a = list(left) + [0] * (length - len(left))
    b = list(right) + [0] * (length - len(right))
    fa = fold(a, prime, generator, length)
    fb = fold(b, prime, generator, length)
    product = [fa[i] * fb[i] % prime for i in range(length)]
    return fold(product, prime, generator, length, inverse=True)


def _check():
    lines = []
    failed = 0

    lines.append("  THE FOLD AGAINST A DIRECT TRANSFORM, bit for bit")
    state = 0x51F7
    for bits in (2, 4, 6, 8, 10):
        length = 1 << bits
        values = []
        for _ in range(length):
            state = (state * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
            values.append((state >> 33) % PRIME)
        root = root_of(length, PRIME, GENERATOR)
        want = direct(values, PRIME, root)
        got = fold(values, PRIME, GENERATOR, length)
        agree = want == got
        lines.append("    length %-5d %s" % (length, "identical" if agree else "DIFFERS"))
        if not agree:
            failed += 1
            first = next(i for i in range(length) if want[i] != got[i])
            lines.append("      first difference at index %d: direct %d, fold %d"
                         % (first, want[first], got[first]))
    lines.append("")

    lines.append("  THE FOLD ROUND TRIPS, forward then inverse returns the input")
    for bits in (4, 8, 10):
        length = 1 << bits
        values = [(i * 7 + 3) % PRIME for i in range(length)]
        forward = fold(values, PRIME, GENERATOR, length)
        back = fold(forward, PRIME, GENERATOR, length, inverse=True)
        agree = back == values
        lines.append("    length %-5d %s" % (length, "returns" if agree else "DOES NOT RETURN"))
        if not agree:
            failed += 1
    lines.append("")

    lines.append("  A CONVOLUTION THROUGH THE FOLD, against Python's own multiply")
    # Small limb arrays whose product is checkable directly. Base 2^16 so the coefficients stay well
    # inside the modulus and the carry is done here in Python.
    trouble = 0
    for size in (3, 8, 16):
        left = [(i * 97 + 11) % 65536 for i in range(size)]
        right = [(i * 41 + 7) % 65536 for i in range(size)]
        got = convolve(left, right, PRIME, GENERATOR)
        left_value = sum(left[i] << (16 * i) for i in range(size))
        right_value = sum(right[i] << (16 * i) for i in range(size))
        rebuilt = sum(got[i] << (16 * i) for i in range(len(got)))
        agree = rebuilt == left_value * right_value
        lines.append("    %2d by %2d limbs  %s" % (size, size, "agrees" if agree else "DISAGREES"))
        if not agree:
            trouble += 1
    failed += trouble
    lines.append("")

    lines.append("  THE FOLD ON ANOTHER MODULUS, so it is not tuned to one")
    # Its own proven generator, found and not assumed, so nothing is bound to one modulus.
    for other in (2281701377, 3892314113):
        generator, _ = twiddle_proof.generator_of(other)
        length = 256
        values = [(i * 13 + 5) % other for i in range(length)]
        want = direct(values, other, root_of(length, other, generator))
        got = fold(values, other, generator, length)
        agree = want == got
        lines.append("    length 256 on %-11d generator %-3d %s"
                     % (other, generator, "identical" if agree else "DIFFERS"))
        if not agree:
            failed += 1
    lines.append("")

    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the four-step fold, proved against a direct transform")
    parser.add_argument("--check", action="store_true", help="grade the fold")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    parser.print_help()
