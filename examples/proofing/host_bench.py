"""Every arithmetic the engine rests on, timed on the host alone, and checked while it is timed.

    python examples/proofing/host_bench.py            the full bench
    python examples/proofing/host_bench.py --quick    the small sizes only

WHY HOST ONLY

The card may be busy. This bench never opens a device context, so it runs while the miner holds the
GPU and measures the CPU arithmetic on its own terms. Every operation here has a substrate on the
card as well. The measurement is the host floor each of those sits above, the number that
says when the trip to the card is worth taking.

WHAT IS TIMED, AND WHY IT IS ALSO A GATE

A benchmark that does not check its answer is timing an unknown. So every operation is run against
the routine it is meant to match, at every size, and a disagreement fails the run instead of being
reported as a fast result. The pairs:

    native multiply        against itself at rising size, to read the Karatsuba exponent
    reciprocal, divide     against Python's floor division, exactly
    integer root           against math.isqrt, exactly
    power_mod              against pow(base, power, modulus), exactly
    Proth certification    against a deterministic Miller-Rabin, verdict for verdict
    Chudnovsky pi          against the module's own pi_machin and the published prefix

The point of the file is the timing. The checks are there so the timing means something.
"""

import argparse
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import digit_engine
import natural_constants as nc

sys.set_int_max_str_digits(0)


def made(bits, seed):
    """A value near `bits` bits from a cheap recurrence, assembled as bytes so it is linear to build."""
    state = seed
    raw = bytearray()
    for _ in range((bits + 63) // 64):
        state = (state * 6364136223846793005 + 1442695040888963407) % (1 << 64)
        raw += state.to_bytes(8, "little")
    raw[0] |= 1
    return int.from_bytes(bytes(raw), "little")


def miller_rabin(value):
    """A deterministic primality answer for values inside this bench's range, to grade Proth against."""
    if value < 2:
        return False
    for small in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        if value % small == 0:
            return value == small
    d, r = value - 1, 0
    while d % 2 == 0:
        d //= 2
        r += 1
    for a in (2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37):
        x = pow(a, d, value)
        if x == 1 or x == value - 1:
            continue
        for _ in range(r - 1):
            x = x * x % value
            if x == value - 1:
                break
        else:
            return False
    return True


def timed(work):
    """Run `work` once, returning its result and the seconds it took."""
    start = time.perf_counter()
    out = work()
    return out, time.perf_counter() - start


def bench(quick):
    lines = []
    failed = 0

    mul_sizes = (10 ** 4, 10 ** 5, 10 ** 6) if quick else (10 ** 4, 10 ** 5, 10 ** 6, 3 * 10 ** 6)
    lines.append("  NATIVE MULTIPLY, and the exponent it climbs at")
    lines.append("  %14s %12s" % ("decimal digits", "seconds"))
    prev = None
    for digits in mul_sizes:
        left = made(int(digits * 3.3219), 0x51F7)
        right = made(int(digits * 3.3219), 0xA13D)
        _, spent = timed(lambda: left * right)
        rate = ""
        if prev is not None:
            grew = spent / prev[1]
            times = digits / prev[0]
            rate = "  exponent %.3f" % (math.log(grew) / math.log(times))
        lines.append("  %14s %11.4fs%s" % (format(digits, ","), spent, rate))
        prev = (digits, spent)
    lines.append("")

    lines.append("  DIVISION-FREE RECIPROCAL AND DIVIDE, timed and checked against floor division")
    lines.append("  %14s %12s %12s %10s" % ("bits", "Newton", "Python //", "agree"))
    for bits in ((1 << 14, 1 << 16) if quick else (1 << 14, 1 << 16, 1 << 18, 1 << 20)):
        top = made(2 * bits, 3)
        bottom = made(bits, 7)
        mine, mine_t = timed(lambda: digit_engine.divide(top, bottom, 0))
        theirs, theirs_t = timed(lambda: top // bottom)
        agree = mine == theirs
        lines.append("  %14s %11.4fs %11.4fs %10s"
                     % (format(bits, ","), mine_t, theirs_t, "yes" if agree else "NO"))
        if not agree:
            failed += 1
    lines.append("")

    lines.append("  DIVISION-FREE ROOT, timed and checked against math.isqrt")
    lines.append("  %14s %12s %12s %10s" % ("bits", "Newton", "isqrt", "agree"))
    for bits in ((1 << 14, 1 << 16) if quick else (1 << 14, 1 << 16, 1 << 18)):
        value = made(bits, 9)
        mine, mine_t = timed(lambda: digit_engine.root_scaled(value, 0))
        theirs, theirs_t = timed(lambda: math.isqrt(value))
        agree = mine == theirs
        lines.append("  %14s %11.4fs %11.4fs %10s"
                     % (format(bits, ","), mine_t, theirs_t, "yes" if agree else "NO"))
        if not agree:
            failed += 1
    lines.append("")

    lines.append("  MODULAR EXPONENTIATION, timed and checked against pow(b, e, m)")
    lines.append("  %14s %12s %12s %10s" % ("modulus bits", "power_mod", "pow", "agree"))
    for bits in ((256, 512) if quick else (256, 512, 1024, 2048)):
        modulus = made(bits, 5) | 1
        base = made(bits - 8, 11)
        power = made(bits - 4, 13)
        mine, mine_t = timed(lambda: digit_engine.power_mod(base, power, modulus))
        theirs, theirs_t = timed(lambda: pow(base, power, modulus))
        agree = mine == theirs
        lines.append("  %14s %11.4fs %11.4fs %10s"
                     % (format(bits, ","), mine_t, theirs_t, "yes" if agree else "NO"))
        if not agree:
            failed += 1
    lines.append("")

    lines.append("  PROTH CERTIFICATION, timed and checked against Miller-Rabin, verdict for verdict")
    lines.append("  %14s %12s %10s %10s" % ("decimal digits", "seconds", "verdict", "agree"))
    proth = ((27, 40), (7, 50), (31, 60)) if quick else ((27, 40), (7, 50), (31, 60), (5, 100), (3, 128))
    for multiplier, power in proth:
        value = multiplier * (1 << power) + 1
        (verdict, _), spent = timed(lambda: next(
            (digit_engine.proth_holds(multiplier, power, w) for w in range(2, 40)
             if digit_engine.proth_holds(multiplier, power, w)[0] is not None)))
        mine = "prime" if verdict else "composite"
        theirs = "prime" if miller_rabin(value) else "composite"
        agree = mine == theirs
        lines.append("  %14s %11.4fs %10s %10s"
                     % (format(len(str(value)), ","), spent, mine, "yes" if agree else "NO"))
        if not agree:
            failed += 1
    lines.append("")

    lines.append("  CHUDNOVSKY PI, host only, timed and checked three ways")
    lines.append("  %14s %12s %10s" % ("places", "seconds", "agree"))
    prefix = nc.PI_PREFIX.replace(".", "")
    for places in ((1000, 10000) if quick else (1000, 10000, 100000)):
        value, spent = timed(lambda: digit_engine.chudnovsky(places))
        against = nc.pi_machin(places) if places <= 20000 else None
        text = str(value)
        good = text[:len(prefix)] == prefix and (against is None or value == against)
        lines.append("  %14s %11.4fs %10s"
                     % (format(places, ","), spent, "yes" if good else "NO"))
        if not good:
            failed += 1
    lines.append("")

    lines.append("  Every operation above ran on the CPU alone. The card was never opened, so this")
    lines.append("  bench and the miner do not contend.")
    lines.append("")
    lines.append("  %d check(s) failed" % failed)
    sys.stdout.write("\n".join(lines) + "\n")
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the host arithmetic, timed and checked")
    parser.add_argument("--quick", action="store_true", help="small sizes only")
    args = parser.parse_args()
    sys.exit(1 if bench(args.quick) else 0)
