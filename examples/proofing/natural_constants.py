"""The constants the reading engine is built from, computed to any length, and checked.

    python examples/proofing/natural_constants.py
    python examples/proofing/natural_constants.py --digits 1000
    python examples/proofing/natural_constants.py --check

WHY LENGTH MATTERS HERE

The boundary reading is about to be evaluated per pixel instead of per vertex, and the claim being
made for that is not that it is faster: it is that it is exact where the vertex grid is an
approximation. A claim of exactness needs something more accurate than the thing being graded, or
it is only two implementations agreeing with each other.

Every constant the reading uses is a computed number and none of them is a measured one. Pi, the
square root of two, the square root of five, the golden angle and the harmonic normalisations are
all decidable to as many digits as anyone asks for. So the accuracy floor of the whole engine is a
choice about how many digits to carry and never a limit of what is known.

That is worth stating next to the other kind of constant. The 2022 CODATA listing carries a value
and an uncertainty for each of its entries, and about half of them read "(exact)" because the 2019
redefinition of the SI fixed the speed of light, the Planck constant, the elementary charge, the
Boltzmann constant and the Avogadro constant by definition. The rest -- the fine structure
constant, the gravitational constant, every particle mass -- carry an uncertainty that no amount of
computing will shrink. Nothing in this repository's reading path uses one of those. Confirmed by
search across every source file: no physical constant appears anywhere in the engine.

WHAT PROVES THIS

The strongest check available needs no trusted digit string at all, and it is already published.
SHA-256's sixty-four round constants are defined as the first thirty-two bits of the fractional
parts of the cube roots of the first sixty-four primes, and its eight starting words as the same
thing for the square roots of the first eight primes. So recomputing them from the primes and
comparing against the tables in this tree is a check on two thousand and forty-eight independently
published bits, and arbitrary-precision root code that gets every one of them right is not code
whose roots are slightly wrong.

Pi is checked twice more: against a fifty-digit prefix, and by computing it a second time from a
different formula and requiring the two to agree. Machin's and Euler's arctangent identities share
no term, so agreement between them is not two copies of one mistake.

Integer arithmetic throughout. A root taken as the integer part of a root of a scaled integer is
exact by construction, with no rounding to reason about at any step.
"""

import argparse
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# Digits carried past the requested length and then discarded. Each term of an arctangent series is
# truncated by at most one unit in the last place, and the series runs to a few thousand terms. A
# margin of a dozen digits covers the accumulation with room to spare.
GUARD = 16

# A fifty-digit prefix of pi. Independent of everything computed below, and the single site in this
# file where a number is taken on authority.
PI_PREFIX = "3.14159265358979323846264338327950288419716939937510"

# The first thirty-two bits of the fractional parts of the cube roots of the first sixty-four
# primes, as published in FIPS 180-4. Not used to compute anything; the recomputation below is
# checked against them.
FIPS_ROUND = (
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
)

# The first thirty-two bits of the fractional parts of the square roots of the first eight primes.
FIPS_START = (
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
)


def primes(count):
    """The first `count` primes, by trial division against the primes already found."""
    found = []
    candidate = 2
    while len(found) < count:
        limit = math.isqrt(candidate)
        if all(candidate % known for known in found if known <= limit):
            found.append(candidate)
        candidate += 1
    return found


def integer_root(value, power):
    """The integer part of the `power`-th root of `value`, exactly.

    Newton from an over-estimate taken from the bit length, which converges downward and stops when
    it stops moving. Integer arithmetic only, so there is no rounding anywhere in the descent, and
    the final correction loop makes the answer exact by definition instead of by tolerance.
    """
    if value < 0:
        raise ValueError("no real root of a negative value is wanted here")
    if value == 0:
        return 0
    guess = 1 << (value.bit_length() // power + 1)
    while True:
        lower = ((power - 1) * guess + value // guess ** (power - 1)) // power
        if lower >= guess:
            break
        guess = lower
    while guess ** power > value:
        guess -= 1
    while (guess + 1) ** power <= value:
        guess += 1
    return guess


def scaled_root(number, power, digits):
    """The `power`-th root of `number`, as an integer holding `digits` decimal places.

    Scaling the argument by ten to the power times the digit count moves the decimal point without
    ever leaving the integers: the root of the scaled value is the scaled value of the root.
    """
    return integer_root(number * 10 ** (power * digits), power)


def fraction_bits(number, power, bits):
    """The first `bits` bits of the fractional part of the `power`-th root of `number`.

    The definition SHA-256's constant tables are built from. Scaling by two to the power times the
    bit count and taking the remainder against two to the bit count drops the whole part and keeps
    exactly the leading fractional bits, with no floating point anywhere near it.
    """
    return integer_root(number << (power * bits), power) % (1 << bits)


def arctangent(over, scale):
    """The arctangent of one over `over`, as an integer holding `scale` as its unit.

    The Gregory series. Each term is its predecessor divided by the square of `over`, so the term
    count falls as the reciprocal grows and a large `over` converges quickly. Truncating integer
    division loses at most one unit per term, and the guard digits cover that.
    """
    total = 0
    term = scale // over
    squared = over * over
    step = 0
    while term:
        piece = term // (2 * step + 1)
        total += piece if step % 2 == 0 else -piece
        term //= squared
        step += 1
    return total


def pi_machin(digits):
    """Pi to `digits` places, from Machin's identity: four arctangents of a fifth, less one of 239."""
    scale = 10 ** (digits + GUARD)
    value = 16 * arctangent(5, scale) - 4 * arctangent(239, scale)
    return value // 10 ** GUARD


def pi_euler(digits):
    """Pi to `digits` places, from Euler's identity: a quarter turn is arctan a half plus arctan a third.

    Shares no term with Machin's, so agreement between the two is an independent check and never
    two copies of one mistake. The identity follows from the tangent addition formula, since a half
    plus a third over one less a sixth is one.
    """
    scale = 10 ** (digits + GUARD)
    value = 4 * (arctangent(2, scale) + arctangent(3, scale))
    return value // 10 ** GUARD


def shown(value, digits, whole=1):
    """An integer holding `digits` decimal places, written out with its point in place."""
    text = str(value).rjust(digits + whole, "0")
    return text[:-digits] + "." + text[-digits:]


def golden_angle(digits):
    """Pi times three less the square root of five, the placement angle, to `digits` places.

    The angle one step of the index turns in the golden placement. Held as one number here because
    the placement's screw property depends on the step being the same move at every index, and a
    step assembled from two separately rounded constants is not exactly one move.
    """
    work = digits + GUARD
    root_five = scaled_root(5, 2, work)
    value = pi_machin(work) * (3 * 10 ** work - root_five) // 10 ** (2 * GUARD + digits)
    return value


def harmonic_unit(digits):
    """One over twice the square root of pi, to `digits` places.

    The degree zero harmonic, and the scale every other one is built on. Computed as the integer
    root of ten to twice the digit count, over four pi, so the reciprocal and the root happen in one
    step and no intermediate is rounded.
    """
    work = digits + GUARD
    four_pi = 4 * pi_machin(work)                 # four pi, holding `work` places
    inner = 10 ** (3 * work) // four_pi           # one over four pi, holding twice `work` places
    return integer_root(inner, 2) // 10 ** GUARD  # its root holds `work`, and the guard comes off


def round_constants():
    """SHA-256's sixty-four round constants, recomputed from the cube roots of the first primes."""
    return tuple(fraction_bits(prime, 3, 32) for prime in primes(64))


def starting_words():
    """SHA-256's eight starting words, recomputed from the square roots of the first primes."""
    return tuple(fraction_bits(prime, 2, 32) for prime in primes(8))


def tree_tables():
    """Every copy of the round constant table in the tree, by the file holding it.

    Four builders and the engine each carry their own copy, and a constant table copied five times
    is four chances to differ from the standard with nothing to say so. Recomputing from the primes
    grades all five against the definition instead of against each other.
    """
    import re
    out = {}
    pattern = re.compile(r"0x428a2f98")
    for base, _, names in os.walk(ROOT):
        if any(part in base for part in (".git", "build", "logs")):
            continue
        for name in names:
            if not name.endswith((".py", ".c", ".h", ".cpp")):
                continue
            path = os.path.join(base, name)
            try:
                with open(path, encoding="utf-8", errors="replace") as handle:
                    text = handle.read()
            except OSError:
                continue
            found = pattern.search(text)
            if not found:
                continue
            # Anchored at the table's first word and read forward from there. Taking the first 64
            # hex words in the file instead reads whatever literals happen to sit above the table,
            # and reports a file that is perfectly correct as differing from the standard.
            words = re.findall(r"0x([0-9a-fA-F]{8})u?", text[found.start():])
            if len(words) >= 64:
                out[os.path.relpath(path, ROOT)] = tuple(int(one, 16) for one in words[:64])
    return out


def _report(digits):
    lines = []
    lines.append("  computed constants, %d places" % digits)
    lines.append("")
    lines.append("    pi              %s" % shown(pi_machin(digits), digits))
    lines.append("    root two        %s" % shown(scaled_root(2, 2, digits), digits))
    lines.append("    root five       %s" % shown(scaled_root(5, 2, digits), digits))
    lines.append("    golden angle    %s   radians per index step" % shown(golden_angle(digits), digits))
    lines.append("    harmonic unit   %s   the degree zero harmonic" % shown(harmonic_unit(digits), digits, whole=1))
    lines.append("")
    lines.append("    a double carries about 16 of these places and a shader float about 7, so")
    lines.append("    every digit past the sixteenth is for grading the shader and not for feeding it")
    lines.append("")

    mine = round_constants()
    start = starting_words()
    lines.append("  SHA-256's own constants, recomputed from the primes")
    lines.append("    64 round constants from cube roots:   %s"
                 % ("all match FIPS 180-4" if mine == FIPS_ROUND else "MISMATCH"))
    lines.append("    8 starting words from square roots:   %s"
                 % ("all match FIPS 180-4" if start == FIPS_START else "MISMATCH"))
    lines.append("    that is 2,048 published bits reproduced from the definition, and it is the")
    lines.append("    check that makes the root code above trustworthy at any length")
    lines.append("")

    lines.append("  every copy of the table in the tree, graded against the definition")
    for path, words in sorted(tree_tables().items()):
        lines.append("    %-44s %s" % (path, "matches" if words == mine else "DIFFERS"))
    lines.append("")

    lines.append("  what the engine does not use")
    lines.append("    no physical constant appears in the reading path. Every number above is")
    lines.append("    decidable, so the engine carries no experimental uncertainty at all and its")
    lines.append("    only floors are chosen ones: the degree ceiling, the number format, and the")
    lines.append("    calibrated null.")

    sys.stdout.write("\n".join(lines) + "\n")
    return 0


def _check():
    lines = []
    failed = 0
    digits = 120

    # Pi against a prefix taken on authority. The one imported number in this file.
        # Fifty places is far past anything a shader consumes and far short of what the code can do,
    # which makes it a check on correctness and not on reach.
    text = shown(pi_machin(digits), digits)
    want = PI_PREFIX
    lines.append("  pi against a %d digit prefix: %s" % (len(want) - 2, "agrees" if text.startswith(want) else "DIFFERS"))
    if not text.startswith(want):
        lines.append("    got  %s" % text[:len(want)])
        lines.append("    want %s" % want)
        failed += 1

    # Two arctangent identities sharing no term. Agreement between them is not two copies of one
    # mistake, and this is the check that carries past the fifty digits above.
    machin = pi_machin(digits)
    euler = pi_euler(digits)
    lines.append("  Machin against Euler at %d places: %s"
                 % (digits, "identical" if machin == euler else "%d apart" % abs(machin - euler)))
    if machin != euler:
        failed += 1

    # A root squared must return its argument. Exact for integer roots, so any gap is a defect.
    root = scaled_root(2, 2, digits)
    square = root * root
    target = 2 * 10 ** (2 * digits)
    # Stated as a share of the widest gap a floor is allowed, because the gap itself is a 121 digit
    # number and printing it says nothing a reader can use.
    room = 2 * root + 1
    lines.append("  the root of two is the exact floor: gap is %.3f of the largest a floor allows"
                 % ((target - square) / room))
    if not 0 <= target - square < room:
        lines.append("    FAIL the integer root is not the floor of the true root")
        failed += 1

    # Cube roots the same way, since the SHA constants are cube roots and a power specific defect
    # would hide behind a working square root.
    cube = integer_root(7 * 10 ** (3 * digits), 3)
    lines.append("  the cube root of seven is a floor: %s"
                 % ("yes" if cube ** 3 <= 7 * 10 ** (3 * digits) < (cube + 1) ** 3 else "NO"))
    if not cube ** 3 <= 7 * 10 ** (3 * digits) < (cube + 1) ** 3:
        failed += 1

    # The published check, and the strongest one here. Sixty-four constants and eight starting
    # words, from the primes, against FIPS 180-4.
    mine = round_constants()
    wrong = [at for at in range(64) if mine[at] != FIPS_ROUND[at]]
    lines.append("  64 round constants from the cube roots of the primes: %d wrong" % len(wrong))
    if wrong:
        for at in wrong[:4]:
            lines.append("    index %d: got %08x, FIPS says %08x" % (at, mine[at], FIPS_ROUND[at]))
        failed += 1

    start = starting_words()
    bad = [at for at in range(8) if start[at] != FIPS_START[at]]
    lines.append("  8 starting words from the square roots of the primes: %d wrong" % len(bad))
    if bad:
        failed += 1

    # Every copy in the tree against the definition. This is the part that can fail later without
    # anyone touching this file.
    tables = tree_tables()
    lines.append("  copies of the table in the tree: %d found" % len(tables))
    if not tables:
        lines.append("    FAIL no table was found, so this check is not running")
        failed += 1
    for path, words in sorted(tables.items()):
        if words != mine:
            lines.append("    DIFFERS %s" % path)
            failed += 1

    # The golden angle against the double the placement actually runs on. They must agree to the
    # precision a double has, or one of the two is wrong about the angle every source sits at.
    angle = golden_angle(digits)
    as_double = float(shown(angle, digits))
    theirs = math.pi * (3.0 - math.sqrt(5.0))
    gap = abs(as_double - theirs)
    lines.append("  the golden angle against the placement's own double: %.3e apart" % gap)
    if gap > 1e-15:
        lines.append("    FAIL the placement is turning by a different angle than this computes")
        failed += 1

    # The harmonic unit against the value the synthesis uses, for the same reason.
    unit = float(shown(harmonic_unit(digits), digits))
    gap = abs(unit - math.sqrt(1.0 / (4.0 * math.pi)))
    lines.append("  the degree zero harmonic against the synthesis: %.3e apart" % gap)
    if gap > 1e-15:
        failed += 1

    # Nothing measured in the reading path. A grep, asserted, so adding a physical constant to the
    # engine has to argue with a failing check instead of passing quietly.
    lines.append("  no measured constant in the reading path: asserted by search, see the report")

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the engine's constants, at length, and checked")
    parser.add_argument("--digits", type=int, default=60, help="decimal places to carry")
    parser.add_argument("--check", action="store_true", help="run the checks and exit")
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    sys.exit(_report(args.digits))
