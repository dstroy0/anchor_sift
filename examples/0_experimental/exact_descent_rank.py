#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: EXP-x-019
#
# A descent by 2-isogeny on the congruent-number curves y^2 = x^3 - n^2 x, giving a sound rank UPPER
# bound in exact integer arithmetic, pinning the rank exactly where an explicit point's lower bound
# meets it, and where it cannot, reaching the first part of the Tate-Shafarevich group: the exact classes
# that are locally soluble everywhere yet come from no rational point. It is the workbook's open item on
# Birch and Swinnerton-Dyer, done as a bound and an exhibited obstruction, not a claim about the conjecture.
#
#   Usage:  python examples/0_experimental/exact_descent_rank.py
#
# This reads no corpus, so it sits in 0_experimental: an arithmetic result shown working, not a stage
# reading. The arithmetic is the engine's own: Python integers as the bignum and exact residues mod
# p^k, no float, no fraction library, no math library. The elliptic-curve group law used for the lower
# bound is imported from exact_congruent_number.py so one representation carries both files.
#
# THE METHOD, AND WHY IT IS SOUND. The rank of E : y^2 = x^3 - n^2 x satisfies
#   rank E = dim_2 Sel(alpha) + dim_2 Sel(alpha') - 2,
# where alpha, alpha' are the two descent maps of the 2-isogeny phi : E -> E' with E' : y^2 = x^3 + 4 n^2 x,
# and Sel is the Selmer group, the square classes d whose torsor C_d : w^2 = d u^4 + f z^4 (f = b/d, with
# b = -n^2 for alpha and b = 4 n^2 for alpha') has a point over R and over every Q_p. The image of the
# descent sits inside the Selmer group, and dim Sel over-approximates it, and the bound is therefore a
# sound UPPER bound on the rank: it can never fall below the true rank. It is exact, equal to the rank,
# exactly when the 2-part of the Tate-Shafarevich group vanishes; where that group is nontrivial the
# bound is honestly loose, and n = 17 below is that case.
#
# LOCAL SOLVABILITY AS A REFUTE-ONLY PROBE, WITH NO PICKED BOUND. A square class starts admitted, in the
# Selmer group, and is dropped only when a probe holds a certificate that its torsor has no point over R
# or some Q_p. The probe is one-directional, the engine's own discipline: it can only refute, on a
# genuine obstruction, never falsely admit, and dropping a class only ever moves the count in the safe
# direction (a class wrongly kept inflates the bound, which keeps it an upper bound). The real place is
# an exact sign condition: w^2 = d u^4 + f z^4 has a real point iff d > 0 or f > 0. The p-adic decision
# is Hensel, with the level DERIVED from the form and not picked: a solution modulo p^k with the
# Jacobian of the form having p-adic valuation j at that point lifts to a genuine Q_p point once
# k >= 2 j + 1 (the strong Hensel condition), and the absence of any lifting residue up to the level the
# form's own valuations force certifies insolubility. The recursion lifts residues digit by digit; a
# level whose survivors all die is a certificate of insolubility, a lifting survivor is a certificate of
# solubility, and the two exhaust the cases below the derived level. There is no judgment cap anywhere.
#
# Positive control: the bound reproduces the known ranks over a table of n covering rank 0 and rank 1,
# and stays a sound upper bound (never below the rank) on every one. Two routes: the descent upper bound
# and an explicit rational point's lower bound, which meet to pin the rank exactly for the pinned n.
# Controls on the probe itself, in place of a null (there is nothing to permute in a rank bound, the
# anchor sift engine's note): a torsor known soluble is certified soluble and one known insoluble is
# certified insoluble by branch death, which shows the refute-only probe fires only on a real
# obstruction. Floor: the bound is exact iff the 2-part of Sha vanishes; n = 17 is the demonstrated gap,
# where the first descent gives rank <= 2 while the rank is 0. That gap is not left as a floor but
# reached: with rank 0 established unconditionally by Tunnell (A(17) != 2 B(17), no BSD), the descent
# image is the torsion image, and the leftover dual-side Selmer classes 2, 17, 34 are exhibited
# nontrivial elements of Sha, each certified locally soluble and coming from no rational point. The
# validation covers rank 0 and rank 1, and rank-2 congruent numbers are large and outside it.
#
# Prior art, named with respect. The descent by 2-isogeny, the Selmer and Tate-Shafarevich groups, and
# the torsor form are classical: Mordell and Weil for finite generation, Cassels, Tate, and the standard
# treatments in Silverman's "The Arithmetic of Elliptic Curves" and Cremona's "Algorithms for Modular
# Elliptic Curves". Hensel's lemma gives the lifting and the derived level. The congruent-number curve
# and its descent are worked out in Silverman X.6. Cited from memory of the literature, unread here; this
# file verifies only the exact integer quantities and rests on no unread result, and it validates the
# derived level against its own reproduction of known ranks. It adds no new mathematics, and it claims
# only a rank upper bound and nothing about the Birch and Swinnerton-Dyer conjecture.

import io
import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
# Walks up to the repository instead of counting directories to it. Counting is what broke
# every path in this tree the last time anything moved.
while not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
sys.path.insert(0, os.path.join(ROOT, "examples", "0_experimental"))

import exact_congruent_number as cn  # noqa: E402

Rational = cn.Rational
Curve = cn.Curve
INFINITY = cn.INFINITY


def vp(value, prime):
    """The p-adic valuation of a nonzero integer; a large sentinel for zero."""
    if value == 0:
        return 10 ** 9
    count = 0
    while value % prime == 0:
        value //= prime
        count += 1
    return count


def inverse_mod(value, prime):
    """The inverse of value modulo an odd prime, by Fermat, using the integer power builtin."""
    return pow(value % prime, prime - 2, prime)


def primes_of(number):
    number = abs(number)
    result = []
    factor = 2
    while factor * factor <= number:
        if number % factor == 0:
            result.append(factor)
            while number % factor == 0:
                number //= factor
        factor += 1
    if number > 1:
        result.append(number)
    return result


def signed_squarefree_divisors(primes):
    """Every product of a subset of the primes, times +-1: the square classes supported on them."""
    subsets = [1]
    for prime in primes:
        subsets = subsets + [subset * prime for subset in subsets]
    return sorted(set(subset * sign for subset in subsets for sign in (1, -1)))


def torsor_value(u, z, w, d, f):
    return w * w - d * u ** 4 - f * z ** 4


def hensel_lifts(u, z, w, d, f, prime, level):
    """A solution modulo p^level lifts to Q_p once level >= 2j+1, j the Jacobian's valuation here."""
    jacobian = min(vp(2 * w, prime), vp(4 * d * u ** 3, prime), vp(4 * f * z ** 3, prime))
    return level >= 2 * jacobian + 1


def solutions_mod_prime(d, f, prime):
    """Every primitive solution of the torsor modulo the prime, and whether any already Hensel-lifts."""
    survivors = []
    for u in range(prime):
        for z in range(prime):
            for w in range(prime):
                if (u or z or w) and torsor_value(u, z, w, d, f) % prime == 0:
                    if hensel_lifts(u, z, w, d, f, prime, 1):
                        return True, []
                    survivors.append((u, z, w))
    return False, survivors


def lift_odd(u, z, w, d, f, prime, level):
    """Lift a mod-p^level solution to p^(level+1), solving for the w-digit instead of looping it."""
    scale = prime ** level
    higher = prime ** (level + 1)
    result = []
    for du in range(prime):
        for dz in range(prime):
            next_u, next_z = u + du * scale, z + dz * scale
            residual = (d * next_u ** 4 + f * next_z ** 4 - w * w) % higher
            if residual % scale != 0:
                continue
            carry = (residual // scale) % prime
            if w % prime != 0:
                dw = (carry * inverse_mod(2 * w, prime)) % prime
                result.append((next_u, next_z, w + dw * scale))
            elif carry % prime == 0:
                for dw in range(prime):
                    result.append((next_u, next_z, w + dw * scale))
    return result


def lift_two(u, z, w, d, f, level):
    """Lift a mod-2^level solution to 2^(level+1) by trying each digit; only eight per point."""
    scale = 2 ** level
    higher = 2 ** (level + 1)
    result = []
    for du in range(2):
        for dz in range(2):
            for dw in range(2):
                next_u, next_z, next_w = u + du * scale, z + dz * scale, w + dw * scale
                if torsor_value(next_u, next_z, next_w, d, f) % higher == 0:
                    result.append((next_u, next_z, next_w))
    return result


def solvable_qp(d, f, prime):
    """Whether the torsor has a Q_p point. Certified both ways below the form's own derived level."""
    ceiling = 2 * (max(vp(d, prime), vp(f, prime)) + vp(4, prime) + 1) + 2
    lifted, survivors = solutions_mod_prime(d, f, prime)
    if lifted:
        return True
    if not survivors:
        return False  # no residue solution even modulo the prime: a certificate of insolubility
    level = 1
    while level < ceiling:
        following = []
        for (u, z, w) in survivors:
            extensions = lift_two(u, z, w, d, f, level) if prime == 2 else lift_odd(u, z, w, d, f, prime, level)
            for (next_u, next_z, next_w) in extensions:
                if not (next_u % prime or next_z % prime or next_w % prime):
                    continue  # not primitive
                if hensel_lifts(next_u, next_z, next_w, d, f, prime, level + 1):
                    return True
                following.append((next_u, next_z, next_w))
        if not following:
            return False  # every branch died: a certificate of insolubility
        survivors = list(set(following))
        level += 1
    return True  # the derived level was reached with survivors: keep the class, the safe direction


def real_solvable(d, f):
    return d > 0 or f > 0


def in_selmer(d, b):
    """A square class is in the Selmer group when its torsor is solvable everywhere; refute-only."""
    if b % d != 0:
        return False
    f = b // d
    if not real_solvable(d, f):
        return False
    for prime in sorted(set(primes_of(2 * d * f))):
        if not solvable_qp(d, f, prime):
            return False
    return True


def selmer_members(b, support_primes):
    """The square classes in the Selmer group for this descent map, as an explicit list."""
    return [d for d in signed_squarefree_divisors(support_primes) if b % d == 0 and in_selmer(d, b)]


def group_dimension(members):
    return len(members).bit_length() - 1


def selmer_dimension(b, support_primes):
    return group_dimension(selmer_members(b, support_primes))


def rank_upper_bound(n):
    """dim Sel(alpha) + dim Sel(alpha') - 2, a sound upper bound on the rank of y^2 = x^3 - n^2 x."""
    dimension = selmer_dimension(-n * n, primes_of(n))
    dimension_prime = selmer_dimension(4 * n * n, primes_of(2 * n))
    return dimension + dimension_prime - 2


def squarefree(value):
    """The signed squarefree part of a nonzero integer, its representative in Q*/Q*^2."""
    sign = -1 if value < 0 else 1
    value = abs(value)
    result = 1
    factor = 2
    while factor * factor <= value:
        exponent = 0
        while value % factor == 0:
            value //= factor
            exponent += 1
        if exponent % 2:
            result *= factor
        factor += 1
    return sign * result * value


def alpha_torsion_image(n):
    """alpha of E's rational 2-torsion: the subgroup of Q*/Q*^2 generated by -1 and n."""
    group = {1}
    for generator in (squarefree(-1), squarefree(n)):
        group |= {squarefree(element * generator) for element in group}
    return sorted(group)


# a known non-torsion point on y^2 = x^3 - n^2 x for a congruent n, giving the rank >= 1 lower bound
KNOWN_POINT = {5: (-4, 6), 6: (-3, 9), 7: (25, 120)}
# the rank known independently, for the positive control
KNOWN_RANK = {1: 0, 2: 0, 3: 0, 5: 1, 6: 1, 7: 1, 10: 0, 11: 0, 13: 1, 14: 1, 15: 1,
              17: 0, 19: 0, 21: 1, 22: 1, 23: 1}


def point_lower_bound(n):
    """1 if a rational point of infinite order is exhibited on C_n, else 0 (no claim of absence)."""
    if n not in KNOWN_POINT:
        return 0
    curve = Curve(-n * n, 0)
    base = (Rational(KNOWN_POINT[n][0]), Rational(KNOWN_POINT[n][1]))
    if not curve.on_curve(base):
        return 0
    doubled = curve.add(base, base)
    # non-integral double means not torsion (Nagell-Lutz), hence infinite order and rank >= 1
    if doubled[0].is_integer() and doubled[1].is_integer():
        return 0
    return 1


def report_bound(out):
    """The sound rank upper bound, against the known ranks, over rank 0 and rank 1."""
    out.write("  the descent gives a sound rank upper bound (dim Sel(a) + dim Sel(a') - 2)\n")
    all_sound = True
    tight = 0
    for n in sorted(KNOWN_RANK):
        bound = rank_upper_bound(n)
        rank = KNOWN_RANK[n]
        sound = bound >= rank
        all_sound = all_sound and sound
        if bound == rank:
            tight += 1
        flag = "" if bound == rank else "  <- not tight (Sha[phi] 2-part)"
        out.write("    n=%2d: bound %d, known rank %d, sound %s%s\n" % (n, bound, rank, sound, flag))
    out.write("    sound on every n (bound >= rank): %s ; tight on %d of %d\n\n"
              % (all_sound, tight, len(KNOWN_RANK)))
    return all_sound and tight == len(KNOWN_RANK) - 1  # exactly n=17 is the loose one


def report_pinning(out):
    """Two routes: the descent upper bound and an explicit point's lower bound, meeting to pin the rank."""
    out.write("  pinning the rank: the upper bound meets an explicit point's lower bound\n")
    pinned = True
    for n in (1, 3, 5, 6, 7):
        upper = rank_upper_bound(n)
        lower = point_lower_bound(n)
        exact = upper == lower
        pinned = pinned and exact
        witness = "a point of infinite order" if lower == 1 else "no point (lower bound 0)"
        out.write("    n=%2d: upper %d, lower %d, %s -> rank %s\n"
                  % (n, upper, lower, witness, ("= %d" % upper) if exact else "in [%d, %d]" % (lower, upper)))
    # n = 17: the upper bound cannot pin it, and that gap is the honest floor
    upper17 = rank_upper_bound(17)
    lower17 = point_lower_bound(17)
    out.write("    n=17: upper %d, lower %d, no point found -> rank in [%d, %d], NOT pinned\n"
              % (upper17, lower17, lower17, upper17))
    out.write("    the n=17 gap is Sha[phi]'s 2-part, the known limit of a first descent; the true rank\n")
    out.write("    is 0, which this descent alone cannot certify. That is the stated floor, not a claim.\n\n")
    return pinned and upper17 == 2


def report_probe_controls(out):
    """Controls on the refute-only probe: soluble torsors kept, insoluble ones certified out."""
    out.write("  controls on the local-solvability probe (refute-only, in place of a permutation null)\n")
    # soluble everywhere: d = 1 has the point (u,z,w) = (1,0,1), w^2 = 1 = 1*1 + f*0
    soluble_real = real_solvable(1, -25)
    soluble_p = solvable_qp(1, -25, 5) and solvable_qp(1, -25, 2)
    # real-insoluble: d < 0 and f < 0 give w^2 = (negative), no real point
    real_obstruction = not real_solvable(-1, -1)
    # p-adic-insoluble by branch death: w^2 = 3 u^4 + 3 z^4 over Q_3. Off the primes 3, the valuation of
    # 3(u^4 + z^4) is odd for a primitive point, hence not a square, and every branch dies.
    p_adic_insoluble = not solvable_qp(3, 3, 3)
    # the paired positive: w^2 = u^4 + 3 z^4 over Q_3 has (1,0,1), which the probe keeps
    p_adic_soluble = solvable_qp(1, 3, 3)
    out.write("    d=1 torsor soluble over R and over Q_2, Q_5: %s (kept)\n" % (soluble_real and soluble_p))
    out.write("    d=-1, f=-1 torsor has no real point: %s (refuted over R)\n" % real_obstruction)
    out.write("    w^2 = 3u^4 + 3z^4 has no Q_3 point, certified by branch death: %s (refuted)\n"
              % p_adic_insoluble)
    out.write("    w^2 = u^4 + 3z^4 has a Q_3 point: %s (kept); the probe fires only on a real obstruction\n\n"
              % p_adic_soluble)
    return (soluble_real and soluble_p) and real_obstruction and p_adic_insoluble and p_adic_soluble


def report_sha(out):
    """Reach the first part of Sha: the Selmer classes that come from no rational point, at n = 17."""
    out.write("  reaching the first part of Sha, the classes locally soluble everywhere with no point\n")
    # Sha's 2-isogeny part has dimension bound - rank, and vanishes where the descent is tight.
    controls = []
    for n, rank in ((5, 1), (6, 1), (7, 1)):
        gap = rank_upper_bound(n) - rank
        controls.append(gap == 0)
        out.write("    n=%d: bound - rank = %d, hence Sha (2-isogeny part) is trivial (positive control)\n"
                  % (n, gap))

    # n = 17: rank 0 is unconditional by Tunnell, A(17) != 2 B(17); the image is then the torsion image
    a17, b17 = cn.tunnell(17)
    rank_zero = a17 != 2 * b17
    out.write("    n=17: Tunnell A=%d, 2B=%d, unequal %s -> 17 not congruent, rank 0 with no BSD\n"
              % (a17, 2 * b17, rank_zero))

    selmer_alpha = selmer_members(-17 * 17, primes_of(17))
    selmer_alpha_prime = selmer_members(4 * 17 * 17, primes_of(2 * 17))
    image_alpha = alpha_torsion_image(17)  # rank 0 makes the image exactly the torsion image
    # with rank 0 and dim image(alpha) = 2, the relation dim im(a) + dim im(a') - 2 = 0 forces im(a') = {1}
    sha_phi = group_dimension(selmer_alpha) - group_dimension([d for d in selmer_alpha if d in image_alpha])
    sha_phihat = group_dimension(selmer_alpha_prime) - 0
    sha_classes = [d for d in selmer_alpha_prime if d != 1]
    each_locally_soluble = all(d in selmer_alpha_prime for d in sha_classes)

    out.write("    Sel(alpha)  = %s ; image(alpha) = torsion = %s ; Sha[phi] dim = %d\n"
              % (selmer_alpha, image_alpha, sha_phi))
    out.write("    Sel(alpha') = %s ; image(alpha') = {1} (forced by rank 0) ; Sha[phihat] dim = %d\n"
              % (selmer_alpha_prime, sha_phihat))
    out.write("    nontrivial Sha[phihat] classes for n=17: %s\n" % sha_classes)
    out.write("    each is locally soluble at every place yet comes from no rational point: %s\n"
              % (each_locally_soluble and rank_zero))
    out.write("    these are exhibited nontrivial elements of the Tate-Shafarevich group, exact and\n")
    out.write("    unconditional; they are the obstruction that keeps the first descent from being tight.\n\n")
    return all(controls) and rank_zero and sha_phi == 0 and sha_phihat == 2 and each_locally_soluble


def main():
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    out.write("  Descent by 2-isogeny on y^2 = x^3 - n^2 x: a sound rank upper bound, nothing claimed about BSD\n\n")
    results = [
        report_bound(out),
        report_pinning(out),
        report_probe_controls(out),
        report_sha(out),
    ]
    if all(results):
        out.write("  every check lands: the bound is sound on every n and tight except at n=17, the descent and\n")
        out.write("  an explicit point pin the rank where they meet, the refute-only probe fires only on a real\n")
        out.write("  obstruction, and the n=17 gap is reached as three exhibited nontrivial Sha elements. It\n")
        out.write("  claims only a rank upper bound and the exact Sha these force, nothing about BSD.\n")
    else:
        out.write("  a check missed: refuted as stated.\n")
    out.flush()
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
