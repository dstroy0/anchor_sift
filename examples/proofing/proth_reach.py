"""How large a Proth prime this engine can certify end to end, measured and not assumed.

    python examples/proofing/proth_reach.py --check       grade against twiddle_proof at small size
    python examples/proofing/proth_reach.py --reach        climb until one certificate is too slow
    python examples/proofing/proth_reach.py --k 5 --n 100000   certify one candidate, timed

WHAT THIS MEASURES

A Proth certificate is one modular exponentiation: `a^((N-1)/2) mod N`, which is prime exactly when
it is `-1`. So the size of prime this engine can prove is the size of exponentiation it can run,
and that size is set by the multiply underneath. Below about a thousand limbs the host's own
multiply is faster; above it the products go to the card. This file walks the candidate size upward
and reports the wall clock of one certificate at each, so the reach is a measured number and not a
projection.

The candidates are real. `k * 2^n + 1` with `k` small and odd is the exact form the record hunts
use, and the same form every NTT modulus has. The search is the same one anyone runs; the only
difference is the multiply it stands on.

WHAT IT IS NOT

It is not a record attempt. The record Proth primes are millions of digits and take a native GPU
exponentiation days to weeks; this engine still marshals each product through the host between
device calls, so it reaches far less. That gap is the honest state of the tool, and the number this
prints is where it actually stands today.
"""

import argparse
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import digit_engine
import gpu_multiply
import twiddle_proof

sys.set_int_max_str_digits(0)


def certify(multiplier, power, tries=64):
    """Certify `multiplier * 2^power + 1`, returning the verdict, the witness and the seconds.

    Tries small witnesses in turn, since a Proth witness is a quadratic non-residue and half of all
    candidates are one, so the first few almost always settle it. A composite is caught the moment a
    witness gives neither 1 nor -1, by Fermat, so this is fast to refuse as well as to prove.
    """
    start = time.perf_counter()
    for witness in range(2, tries):
        verdict, why = digit_engine.proth_holds(multiplier, power, witness)
        if verdict is not None:
            return verdict, witness, why, time.perf_counter() - start
    return None, None, "no witness settled it in %d tries" % tries, time.perf_counter() - start


def _check():
    lines = []
    failed = 0

    digit_engine.use_device()

    lines.append("  AGAINST twiddle_proof, at sizes both can reach")
    for value in (3329, 8380417, 2013265921, 2281701377, 3892314113, 1610612737):
        odd, power, _ = twiddle_proof.proth_form(value)
        theirs, _ = twiddle_proof.proth_prime(value)
        verdict, witness, why, _ = certify(odd, power)
        mine = "prime" if verdict else ("composite" if verdict is False else "inconclusive")
        agree = mine == theirs
        lines.append("    %-12d host says %-9s device says %-9s %s"
                     % (value, theirs, mine, "agree" if agree else "DISAGREE"))
        if not agree:
            failed += 1
    lines.append("")

    # Larger cases whose verdicts were DERIVED, not remembered: a deterministic Miller-Rabin found
    # each smallest odd k giving a prime and giving a composite at that power. A first version of
    # this gate invented "known primes" from memory and two of them were composite, so the engine
    # was right and the test was wrong; the answers here come from a computation instead.
    lines.append("  LARGER CASES, verdicts derived rather than remembered")
    known = ((27, 40, True), (1, 40, False), (7, 50, True), (1, 50, False),
             (31, 60, True), (1, 60, False))
    for multiplier, power, wanted in known:
        verdict, witness, why, spent = certify(multiplier, power)
        ok = verdict == wanted
        lines.append("    %-4d * 2^%-3d + 1  %-32s %.3fs  %s"
                     % (multiplier, power, why, spent, "as expected" if ok else "NOT AS EXPECTED"))
        if not ok:
            failed += 1
    lines.append("")

    gpu_multiply.shut_down()
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


def _reach(ceiling):
    digit_engine.use_device()
    sys.stdout.write("  HOW FAR ONE CERTIFICATE REACHES\n\n")
    sys.stdout.write("  %12s %14s %12s %s\n" % ("power n", "decimal digits", "seconds", "verdict"))
    sys.stdout.flush()

    # k = 5 is odd and small, so k < 2^n holds at every size here and Proth's criterion applies.
    multiplier = 5
    for power in (1000, 3000, 10000, 30000, 100000, 300000, 1000000):
        if power > ceiling:
            break
        value = multiplier * (1 << power) + 1
        verdict, witness, why, spent = certify(multiplier, power)
        digits = len(str(value))
        mark = why if verdict is not None else "no witness in range"
        sys.stdout.write("  %12s %14s %12.2f %s\n"
                         % (format(power, ","), format(digits, ","), spent, mark))
        sys.stdout.flush()
        if spent > 120.0:
            sys.stdout.write("\n  Stopped: one certificate crossed two minutes, and that marks the reach.\n")
            break

    gpu_multiply.shut_down()
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="how large a Proth prime this engine certifies")
    parser.add_argument("--check", action="store_true", help="grade against twiddle_proof")
    parser.add_argument("--reach", action="store_true", help="climb until a certificate is too slow")
    parser.add_argument("--ceiling", type=int, default=10 ** 7, help="stop --reach at this power")
    parser.add_argument("--k", type=int, default=5, help="the multiplier of one candidate")
    parser.add_argument("--n", type=int, default=0, help="the power of one candidate")
    args = parser.parse_args()

    if args.check:
        sys.exit(1 if _check() else 0)
    if args.reach:
        sys.exit(_reach(args.ceiling))
    if args.n:
        digit_engine.use_device()
        verdict, witness, why, spent = certify(args.k, args.n)
        value = args.k * (1 << args.n) + 1
        sys.stdout.write("%d * 2^%d + 1, %s digits\n" % (args.k, args.n, format(len(str(value)), ",")))
        sys.stdout.write("  %s in %.3f s\n" % (why, spent))
        gpu_multiply.shut_down()
        sys.exit(0)
    parser.print_help()
