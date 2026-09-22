"""The twiddle constants, proved, not copied, at whatever size is asked for.

    python examples/proofing/twiddle_proof.py --check          grade against known answers
    python examples/proofing/twiddle_proof.py --show 2113929217   prove one modulus and its root
    python examples/proofing/twiddle_proof.py --find 62 --order 32   find moduli nobody has tabled

WHAT WAS MISSING

A number theoretic transform is a sum of powers of one constant, the root of unity, and the powers
it is evaluated at are the twiddle constants. Every implementation of the transform in wide use
takes them from a table: Kyber's modulus is 3329, Dilithium's is 8380417, and the three thirty-two
bit moduli that general purpose libraries reach for are the same three everywhere. The tables are
copied, and a copied constant is a constant nobody checked.

Ravi, Yang, Bhasin, Zhang and Chattopadhyay show what that is worth. Their fault injection sets the
twiddle constants to zero with a single targeted fault, and the transform does not fail: it returns
a value of the ordinary shape carrying far less entropy than it should, which is enough to recover a
Kyber key and to forge a Dilithium signature. The attack works because nothing downstream can tell
a real root of unity from a fiddled one.

THIS TREE PRODUCED THAT FAULT CONDITION WITH NO ATTACKER. A modulus was taken on faith for the
transform underneath the constants module, its root was raised to the power that is supposed to give
an order 2^27 root of unity, and the result had no such order, because the modulus was not prime. A
generator check written next to it reported the root was fine, having tested trial division to one
hundred on a ten digit number. Wrong twiddles, output of the ordinary shape, and a check that said
yes. That is the paper's fault model arriving by carelessness instead of by electromagnetic pulse,
and it is the reason this file exists.

WHAT IS PROVED HERE, AND WHY IT CAN BE

Every modulus a transform can use has the form k * 2^n + 1, because having a root of
unity of order 2^n means. For that form two complete proofs are available, and neither is a test
that returns a probability.

    PRIMALITY, BY PROTH. For N = k * 2^n + 1 with k odd and k < 2^n, N is prime if and only if some
    a has a^((N-1)/2) congruent to -1 modulo N. A witness is a certificate of primality, not
    evidence of it. On the other side a single a with a^(N-1) not congruent to 1 is a certificate of
    compositeness by Fermat. So both verdicts are proofs and neither is a judgement call.

    THE ORDER OF THE ROOT, EXACTLY, WITHOUT FACTORING ANYTHING. The order of a root of unity of
    order dividing 2^m is itself a power of two. So it is enough that w^(2^m) is 1 and w^(2^(m-1))
    is not: the order divides 2^m and does not divide 2^(m-1), which leaves exactly 2^m. Two
    exponentiations settle it completely. This is the step the fault attack defeats and it costs
    almost nothing to run.

    THE GENERATOR, COMPLETELY. g generates the whole group if and only if g^((p-1)/q) is not 1 for
    each prime q dividing p-1. Here p-1 is k * 2^n with k small, so factoring it is factoring k, and
    the proof is complete instead of partial.

WHY THE SIZE IS OURS TO CHOOSE

The tabled moduli are small because they are sized to a machine word: a lane holds sixty four bits,
a product of two residues has to fit, and so the modulus stops below 2^32. That is a property of the
lane and not of the mathematics. The arithmetic here is on unbounded integers, so Proth's proof runs
at any width, and moduli far past anything tabled can be produced and proved on demand. The floor
belongs to the format, which is this tree's own finding, and the format is a choice.

WHAT IT REFUSES

A modulus outside Proth's range, where k is not below 2^n. The theorem's converse is the step that
makes a witness a proof and it does not hold there. A root whose order is short of the length asked
for, the fiddled twiddle exactly. And any verdict without its certificate: every answer
below carries the witness that establishes it, so the reader can recheck the claim without rerunning
this file.
"""

import argparse
import sys

# The constants in wide use, with the transform length each is chosen to support. Kept as known
# answers instead of as a source: nothing here reads them to compute with, and every one of them is
# put through the same proof as anything this file produces.
TABLED = (
    (3329, 256, "Kyber's modulus"),
    (8380417, 512, "Dilithium's modulus"),
    (2013265921, 1 << 27, "the thirty-one bit modulus libraries reach for first"),
    (2281701377, 1 << 27, "the second of that set"),
    (1610612737, 1 << 27, "the third, which this tree took on faith and should not have"),
    (18446744069414584321, 1 << 32, "the sixty-four bit modulus, 2^64 - 2^32 + 1"),
)


def proth_form(value):
    """`value` as k * 2^n + 1 with k odd, and whether Proth's theorem reaches it.

    The theorem needs k below 2^n. That condition promotes a single witness from an indication to a
    proof, and a value outside the range is therefore reported as out of range instead of being
    tested anyway and having its answer quietly mean something weaker.
    """
    if value < 3 or value % 2 == 0:
        return None, None, False
    odd = value - 1
    power = 0
    while odd % 2 == 0:
        odd //= 2
        power += 1
    return odd, power, odd < (1 << power)


def small_factors(value):
    """The distinct primes dividing `value`, by trial division to its own square root.

    Complete, not partial. This is only ever called on the odd part of a modulus less one, which is
    small by the same condition that lets Proth's theorem apply, so dividing all the way up is
    cheap and there is no probable answer anywhere in it.
    """
    found = []
    rest = value
    divisor = 2
    while divisor * divisor <= rest:
        if rest % divisor == 0:
            found.append(divisor)
            while rest % divisor == 0:
                rest //= divisor
        divisor += 1
    if rest > 1:
        found.append(rest)
    return found


def proth_prime(value, tries=1000):
    """A proof that `value` is prime or that it is composite, with the witness for whichever it is.

    A witness a with a^((N-1)/2) congruent to -1 proves primality outright, by Proth. An a with
    a^(N-1) not congruent to 1 proves compositeness outright, by Fermat. Both directions are
    certificates, so the only inconclusive outcome is running out of candidates, which is reported
    as inconclusive instead of rounded to either verdict.
    """
    odd, power, reachable = proth_form(value)
    if odd is None:
        return "not of the form", None
    if not reachable:
        return "out of Proth's range", None

    half = (value - 1) // 2
    for candidate in range(2, tries):
        lifted = pow(candidate, half, value)
        if lifted == value - 1:
            return "prime", candidate
        if lifted != 1:
            # a^((N-1)/2) is neither 1 nor -1, leaving a^(N-1) short of 1, and Fermat refuses it.
            return "composite", candidate
    return "inconclusive", None


def generator_of(prime, tries=1000):
    """The smallest proven generator of the group modulo `prime`, with the factors proving it.

    Complete because p-1 factors completely: it is k * 2^n and k is small. A candidate is a
    generator exactly when it is not killed by any maximal divisor, so the test is one exponentiation
    per prime factor and there are only ever a handful.
    """
    factors = small_factors(prime - 1)
    for candidate in range(2, tries):
        if all(pow(candidate, (prime - 1) // factor, prime) != 1 for factor in factors):
            return candidate, factors
    return None, factors


def order_is(root, length, prime):
    """Whether `root` has order exactly `length`, where `length` is a power of two.

    The whole proof, and the step a fault attack removes. An order dividing a power of two is a
    power of two, so failing to divide the half is the same as being the whole. Two exponentiations,
    no factoring, and it catches a zeroed twiddle, a wrong modulus and a root of short order alike.
    """
    if length & (length - 1):
        raise ValueError("a transform length is a power of two, not %d" % length)
    return pow(root, length, prime) == 1 and pow(root, length // 2, prime) != 1


def twiddle_of(prime, length):
    """The root of unity of order `length` modulo `prime`, and the proof that it has that order.

    Raising a generator to (p-1)/length gives a root of that order whenever length divides p-1, and
    the result is checked instead of assumed, because the whole point of this file is that the
    step from a generator to a twiddle is where the constant stops being checked.
    """
    if (prime - 1) % length:
        return None, "modulus admits no root of order %d" % length
    generator, _ = generator_of(prime)
    if generator is None:
        return None, "no generator found"
    root = pow(generator, (prime - 1) // length, prime)
    if not order_is(root, length, prime):
        return None, "the root does not have order %d" % length
    return root, "order %d proved" % length


def examined(value, length):
    """Everything provable about one candidate modulus, as a record instead of a print."""
    odd, power, reachable = proth_form(value)
    verdict, witness = proth_prime(value)
    out = {
        "value": value,
        "odd": odd,
        "power": power,
        "in_range": reachable,
        "verdict": verdict,
        "witness": witness,
        "generator": None,
        "factors": None,
        "length": length,
        "root": None,
        "why": None,
    }
    if verdict != "prime":
        return out
    out["generator"], out["factors"] = generator_of(value)
    if length and (value - 1) % length == 0:
        out["root"], out["why"] = twiddle_of(value, length)
    elif length:
        out["why"] = "order %d does not divide the group" % length
    return out


def search(bits, order, want=3):
    """Moduli of at least `bits` bits admitting a transform of length 2^`order`, each proved prime.

    Walks k upward at fixed n, the only shape a modulus of this kind can have, and keeps
    the ones Proth proves. Nothing here is tabled and nothing is looked up: the size is an argument
    because the arithmetic is unbounded, and the difference lies between choosing a modulus and
    being handed one.
    """
    found = []
    power = order
    while len(found) < want:
        low = max(1, (1 << (bits - power - 1)) // 1 if bits > power else 1)
        multiplier = low | 1
        ceiling = 1 << power
        while multiplier < ceiling and len(found) < want:
            value = multiplier * (1 << power) + 1
            if value.bit_length() >= bits:
                verdict, witness = proth_prime(value)
                if verdict == "prime":
                    root, why = twiddle_of(value, 1 << order)
                    if root is not None:
                        found.append((value, multiplier, power, witness, root))
            multiplier += 2
        power += 1
        if power > bits:
            break
    return found


def _line(record):
    """One examined modulus, written out with its certificate beside its verdict."""
    value = record["value"]
    if record["odd"] is None:
        return "  %-22d not of the form k * 2^n + 1" % value
    shape = "%d * 2^%d + 1" % (record["odd"], record["power"])
    if record["verdict"] == "prime":
        head = "PRIME, witness %d" % record["witness"]
    elif record["verdict"] == "composite":
        head = "COMPOSITE, Fermat witness %d" % record["witness"]
    else:
        head = record["verdict"].upper()
    out = ["  %-22d %-20s %s" % (value, shape, head)]
    if record["verdict"] == "prime":
        out.append("      generator %d, group factors %s"
                   % (record["generator"], ", ".join(str(one) for one in record["factors"])))
        if record["root"] is not None:
            out.append("      twiddle for length %d is %d, %s"
                       % (record["length"], record["root"], record["why"]))
        elif record["why"]:
            out.append("      no twiddle: %s" % record["why"])
    return "\n".join(out)


def _check():
    lines = []
    failed = 0

    lines.append("  THE TABLED CONSTANTS, put through the same proof as anything produced here")
    verdicts = {}
    for value, length, note in TABLED:
        record = examined(value, length)
        verdicts[value] = record["verdict"]
        lines.append(_line(record))
        lines.append("      %s" % note)
    lines.append("")

    # Known answers. Kyber's and Dilithium's moduli are prime and published, and a proof here that
    # disagreed would be a defect in this file, never a discovery.
    lines.append("  AGAINST WHAT IS ALREADY KNOWN")
    for value, wanted in ((3329, "prime"), (8380417, "prime"),
                          (2013265921, "prime"), (2281701377, "prime")):
        got = verdicts.get(value)
        agree = got == wanted
        lines.append("    %-12d expected %-9s proved %-9s %s"
                     % (value, wanted, got, "ok" if agree else "DISAGREES"))
        if not agree:
            failed += 1

    # The one this tree used without checking. Its verdict is the finding, whichever way it falls.
    lines.append("    %-12d the modulus taken on faith, proved %s"
                 % (1610612737, verdicts.get(1610612737)))
    lines.append("")

    lines.append("  THE ORDER PROOF, on cases whose answers are known in advance")
    trouble = 0
    prime = 2013265921
    generator, _ = generator_of(prime)
    good = pow(generator, (prime - 1) // 1024, prime)
    checks = (
        ("a root of order 1024 has order 1024", order_is(good, 1024, prime), True),
        ("that root does not have order 2048", order_is(good, 2048, prime), False),
        ("its square has order 512, not 1024", order_is(good * good % prime, 1024, prime), False),
        ("a zeroed twiddle is refused", order_is(0, 1024, prime), False),
        ("the identity is refused", order_is(1, 1024, prime), False),
    )
    for what, got, wanted in checks:
        agree = got == wanted
        lines.append("    %-42s %-5s %s" % (what, got, "ok" if agree else "WRONG"))
        if not agree:
            trouble += 1
    failed += trouble
    lines.append("")

    lines.append("  MODULI LARGER THAN ANYTHING TABLED, found and proved here")
    for bits, order in ((64, 32), (96, 32)):
        got = search(bits, order, want=2)
        if not got:
            lines.append("    none found at %d bits with order 2^%d" % (bits, order))
            failed += 1
            continue
        for value, multiplier, power, witness, root in got:
            lines.append("    %-32d = %d * 2^%d + 1" % (value, multiplier, power))
            lines.append("        %d bits, Proth witness %d, twiddle %d" % (value.bit_length(), witness, root))
            if not order_is(root, 1 << order, value):
                lines.append("        THE ORDER DOES NOT HOLD")
                failed += 1
    lines.append("")

    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the twiddle constants, proved, not copied")
    parser.add_argument("--check", action="store_true", help="grade against known answers")
    parser.add_argument("--show", type=int, default=0, help="prove one modulus")
    parser.add_argument("--length", type=int, default=0, help="the transform length --show wants")
    parser.add_argument("--find", type=int, default=0, help="find moduli of this many bits")
    parser.add_argument("--order", type=int, default=32, help="the two adic order --find wants")
    args = parser.parse_args()

    if args.check:
        sys.exit(1 if _check() else 0)
    if args.show:
        sys.stdout.write(_line(examined(args.show, args.length)) + "\n")
        sys.exit(0)
    if args.find:
        for value, multiplier, power, witness, root in search(args.find, args.order):
            sys.stdout.write("%d = %d * 2^%d + 1, %d bits, witness %d, twiddle %d\n"
                             % (value, multiplier, power, value.bit_length(), witness, root))
        sys.exit(0)
    parser.print_help()
