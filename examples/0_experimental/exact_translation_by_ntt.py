#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-008
#
# A translation between two views recovered exactly by an integer number theoretic transform, its
# correlation agreeing to the digit with the direct O(N^2) count, and the single-prime floor drawn,
# not assumed.
#
#   Usage:  python examples/0_experimental/exact_translation_by_ntt.py
#
# This reads no corpus, so it sits in 0_experimental: a transform shown working on two synthetic views,
# not a stage reading. It is the translation transform proposed in the image_transforms exact-arithmetic
# chapter, built here atop the same exact-integer discipline as src/engine/c/no_rounding/ but not part
# of that kernel. The kernel counts exact-value agreements at a lag; this counts overlap of two views
# at every lag by convolution, which is a different operation and a new module.
#
# The shift between two views is the lag maximizing C(l) = sum_v a(v) b(v+l), the agreement of one view
# with the other slid by l. That correlation is a convolution, and a number theoretic transform
# computes a convolution exactly in the integers modulo a prime p, with no float and no rounding, when
# p carries a root of unity of the transform length. The prime is p = 998244353 = 119 * 2^23 + 1,
# primitive root 3, certified in ntt_twiddle_certificate.py and in theory_bucket/twiddle_constants_article.tex.
#
# Four things are shown. Positive control: the NTT correlation equals the direct O(N^2) correlation at
# EVERY lag, exactly, on binary views, and its peak is the true shift. Two routes able to disagree:
# with weighted views and a deliberately too-small prime the NTT route wraps and parts from the direct
# route, so their agreement above is an earned result. Drawn null: the true-shift peak is set
# against the best spurious peak between two INDEPENDENT views, so the separation is measured, not
# asserted. Stated floor: a single prime is exact only while every coefficient stays below it; for 0/1
# views the transform length caps the coefficient below p automatically, and weighting is what can
# breach it, whereupon the remedy is a larger prime or CRT over several, the device path in that paper.
#
# No bounding: view length, set-point count and the true shift are declared inputs, printed with the
# run. No threshold decides the shift; it is the argmax of an exact integer correlation.

import io
import sys

# Declared inputs.
VIEW_LENGTH = 48          # positions per view
SET_POINTS = 12           # set points in a view
TRUE_SHIFT = 9            # the translation planted between the two views
PRIME = 998244353         # 119 * 2^23 + 1, primitive root 3
GENERATOR = 3
SMALL_PRIME = 257         # 2^8 + 1, primitive root 3, order 256: valid NTT prime, too small to be exact here
SMALL_GENERATOR = 3
WEIGHT_MAX = 100          # weights drawn in 1..WEIGHT_MAX for the floor demonstration


def spread(count, length, seed):
    """`count` distinct positions in [0, length), from a declared seed. A drawn pattern, not a random one.

    A linear congruential step gives a reproducible spread with no seed-dependence anyone chose; the
    same inputs give the same views on every machine, so the agreement below is a property of the
    arithmetic and not of a lucky draw.
    """
    positions = []
    state = seed & 0x7FFFFFFF
    while len(positions) < count:
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        where = state % length
        if where not in positions:
            positions.append(where)
    return sorted(positions)


def binary_view(positions, length):
    """A 0/1 view with 1 at each set position."""
    view = [0] * length
    for where in positions:
        view[where] = 1
    return view


def weighted_view(positions, length, seed):
    """A view carrying an integer weight in 1..WEIGHT_MAX at each set position, 0 elsewhere."""
    view = [0] * length
    state = seed & 0x7FFFFFFF
    for where in positions:
        state = (1103515245 * state + 12345) & 0x7FFFFFFF
        view[where] = 1 + state % WEIGHT_MAX
    return view


def translate(view, shift):
    """`view` slid right by `shift`, zero-filled: the second view a registration is handed."""
    length = len(view)
    moved = [0] * length
    for index in range(length):
        source = index - shift
        if 0 <= source < length:
            moved[index] = view[source]
    return moved


def next_power_of_two(value):
    """The smallest power of two at least `value`."""
    size = 1
    while size < value:
        size <<= 1
    return size


def ntt_transform(values, prime, root_of_length, invert):
    """The number theoretic transform of `values` modulo `prime`, in place on a copy.

    `root_of_length` is a primitive n-th root of unity where n is len(values), a power of two dividing
    prime-1. The forward and inverse transforms are the same butterfly with the inverse root and a final
    division by n. Every operation is an exact integer modulo the prime.
    """
    sequence = list(values)
    count = len(sequence)

    # bit-reversal permutation
    target = 0
    for source in range(1, count):
        bit = count >> 1
        while target & bit:
            target ^= bit
            bit >>= 1
        target ^= bit
        if source < target:
            sequence[source], sequence[target] = sequence[target], sequence[source]

    base_root = pow(root_of_length, prime - 2, prime) if invert else root_of_length
    span = 2
    while span <= count:
        step_root = pow(base_root, count // span, prime)
        for block in range(0, count, span):
            twiddle = 1
            for offset in range(span // 2):
                low = sequence[block + offset]
                high = (sequence[block + offset + span // 2] * twiddle) % prime
                sequence[block + offset] = (low + high) % prime
                sequence[block + offset + span // 2] = (low - high) % prime
                twiddle = (twiddle * step_root) % prime
        span <<= 1

    if invert:
        inverse_count = pow(count, prime - 2, prime)
        sequence = [(value * inverse_count) % prime for value in sequence]
    return sequence


def convolve(left, right, prime, generator):
    """The exact linear convolution of `left` and `right` modulo `prime`, by NTT.

    The result is padded to a power-of-two length at least len(left)+len(right)-1, so the cyclic
    transform computes the linear convolution with no wraparound between the ends.
    """
    result_length = len(left) + len(right) - 1
    size = next_power_of_two(result_length)
    root = pow(generator, (prime - 1) // size, prime)
    forward_left = ntt_transform(left + [0] * (size - len(left)), prime, root, False)
    forward_right = ntt_transform(right + [0] * (size - len(right)), prime, root, False)
    forward_product = [(one * two) % prime for one, two in zip(forward_left, forward_right)]
    product = ntt_transform(forward_product, prime, root, True)
    return product[:result_length]


def correlate_ntt(first, second, prime, generator):
    """C(l) = sum_v first(v) second(v+l) for every valid lag l, by NTT.

    Cross-correlation is the convolution of `first` with `second` reversed: reversing the second view
    turns the sliding sum into the convolution index k, and l = len(second)-1-k reads the lag back out.
    """
    length_second = len(second)
    reversed_second = second[::-1]
    product = convolve(first, reversed_second, prime, generator)
    correlation = {}
    for lag in range(-(len(first) - 1), length_second):
        correlation[lag] = product[length_second - 1 - lag] % prime
    return correlation


def correlate_direct(first, second):
    """The same C(l), by the direct O(N^2) sliding sum. The route the NTT has to match."""
    length_first = len(first)
    length_second = len(second)
    correlation = {}
    for lag in range(-(length_first - 1), length_second):
        total = 0
        for index in range(length_first):
            shifted = index + lag
            if 0 <= shifted < length_second:
                total += first[index] * second[shifted]
        correlation[lag] = total
    return correlation


def peak(correlation):
    """The (lag, height) of the largest correlation, ties broken by the smallest lag."""
    best_lag = min(correlation, key=lambda lag: (-correlation[lag], abs(lag), lag))
    return best_lag, correlation[best_lag]


def report_positive_control(out):
    """Binary views: NTT correlation equals the direct count exactly, and the peak is the true shift."""
    scene_positions = spread(SET_POINTS, VIEW_LENGTH, seed=0x5C3E)
    scene = binary_view(scene_positions, VIEW_LENGTH)
    view_two = translate(scene, TRUE_SHIFT)

    direct = correlate_direct(scene, view_two)
    transformed = correlate_ntt(scene, view_two, PRIME, GENERATOR)

    exact = all(direct[lag] == transformed[lag] for lag in direct)
    recovered_lag, recovered_height = peak(transformed)

    out.write("  positive control: binary views, NTT correlation vs direct O(N^2)\n")
    out.write("  view length %d, set points %d, planted shift %d\n"
              % (VIEW_LENGTH, SET_POINTS, TRUE_SHIFT))
    out.write("  every lag agrees exactly: %s   (%d lags compared)\n" % (exact, len(direct)))
    out.write("  recovered shift = argmax = %d, peak height = %d (overlapping set points)\n\n"
              % (recovered_lag, recovered_height))
    return exact and recovered_lag == TRUE_SHIFT


def report_drawn_null(out):
    """The true-shift peak against the best spurious peak between two independent views."""
    scene_positions = spread(SET_POINTS, VIEW_LENGTH, seed=0x5C3E)
    scene = binary_view(scene_positions, VIEW_LENGTH)
    view_two = translate(scene, TRUE_SHIFT)

    independent_positions = spread(SET_POINTS, VIEW_LENGTH, seed=0xA17E)
    independent = binary_view(independent_positions, VIEW_LENGTH)

    signal = correlate_direct(scene, view_two)
    null = correlate_direct(scene, independent)

    signal_lag, signal_height = peak(signal)
    null_lag, null_height = peak(null)

    out.write("  drawn null: the true shift against the best spurious overlap\n")
    out.write("  signal pair (a view and its translate): peak %d at lag %d\n" % (signal_height, signal_lag))
    out.write("  null pair (a view and an independent one): peak %d at lag %d\n" % (null_height, null_lag))
    out.write("  separation = %d. the null is the correlation of two unrelated views, drawn here, not a\n"
              % (signal_height - null_height))
    out.write("  threshold set by hand. a shift is real when its peak stands above this background.\n\n")
    return signal_height > null_height


def report_floor(out):
    """Weighted views: a too-small prime wraps and parts from the direct route; the real prime stays exact."""
    scene_positions = spread(SET_POINTS, VIEW_LENGTH, seed=0x5C3E)
    scene = weighted_view(scene_positions, VIEW_LENGTH, seed=0x1234)
    view_two = translate(scene, TRUE_SHIFT)

    direct = correlate_direct(scene, view_two)
    max_coefficient = max(direct.values())

    real = correlate_ntt(scene, view_two, PRIME, GENERATOR)
    small = correlate_ntt(scene, view_two, SMALL_PRIME, SMALL_GENERATOR)

    real_exact = all(direct[lag] == real[lag] for lag in direct)
    small_exact = all(direct[lag] == small[lag] for lag in direct)
    small_disagreements = sum(1 for lag in direct if direct[lag] != small[lag])

    out.write("  floor: weighted views, where a single prime can wrap\n")
    out.write("  max coefficient in the direct correlation: %d\n" % max_coefficient)
    out.write("  prime %d (>%d): every lag exact -> %s\n" % (PRIME, max_coefficient, real_exact))
    out.write("  prime %d (<%d): %d of %d lags wrong -> exact %s\n"
              % (SMALL_PRIME, max_coefficient, small_disagreements, len(direct), small_exact))
    out.write("\n  the small prime is a valid NTT prime and still wrong: two residues reduce past it and\n")
    out.write("  it counts modulo itself, silently. exactness needs max coefficient < p. for 0/1 views\n")
    out.write("  the coefficient is at most the transform length, which divides p-1 and so is below p\n")
    out.write("  for any valid prime: binary views are exact with no separate precondition. weighting\n")
    out.write("  is what can breach p, and the remedy is a larger prime or CRT over several, the three\n")
    out.write("  device primes of the twiddle paper reassembling a 94-bit product.\n")
    # The floor holds as a demonstration when the real prime is exact and the small one provably is not.
    return real_exact and (not small_exact)


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  exact translation by number theoretic transform, on p = 998244353 = 119 * 2^23 + 1\n")
    out.write("  the transform is proposed atop src/engine/c/no_rounding/, not part of that kernel\n\n")

    control = report_positive_control(out)
    null = report_drawn_null(out)
    floor = report_floor(out)
    out.flush()

    return 0 if (control and null and floor) else 1


if __name__ == "__main__":
    raise SystemExit(main())
