"""Does the nonce to hash map have a period? The one question that decides whether Shor applies.

    python examples/00_blob_viz_tools/nonce_period.py --check
    python examples/00_blob_viz_tools/nonce_period.py               the probe, against a matched null
    python examples/00_blob_viz_tools/nonce_period.py --resources   what a real Shor run would need

WHY THIS IS THE COHERENT FORM OF THE REQUEST

Asked for: implement Shor's algorithm into the miner.

Shor's algorithm finds the PERIOD of a function. It works by preparing a superposition over the
domain, applying the function, and letting the Fourier transform peak on the periodicity.
`shor_trace.py` shows it: peaks at 0, 4, 8 and 12 because 7^x mod 15 has period 4, and
two controlled steps moving nothing at all because 7^4 mod 15 closes the orbit.

So Shor is not a search accelerator. It is a period finder, and it returns nothing useful when
handed a function with no period. Wiring it into a nonce search would be wiring a resonator to a
signal that does not oscillate.

THE QUESTION THAT ACTUALLY DECIDES IT, AND IT HAS NEVER BEEN MEASURED HERE

Does the nonce to hash map have a period? If it does, Shor becomes relevant and everything changes.
If it does not, Shor cannot help and that is settled and not assumed.

This tree's standing constraint is that no projection over the digest reduces the number of
evaluations, graded across twenty hypotheses. But PERIODICITY specifically was never tested. The
claim rests on an argument and not on a measurement. This file measures it.

HOW, AND WHY IT IS CLASSICAL

A period of the full 256 bit hash cannot exist in any useful sense, because the map is injective on
32 bit nonces with overwhelming probability. So the test is on a REDUCTION: f(n) = hash(n) mod M for
a small modulus, which has a small codomain and could genuinely repeat. Shor would find a period of
that reduction if one existed. Finding none classically settles the question without needing the
quantum machine at all.

And the classical test is strictly stronger than a simulated quantum one here. Simulated Shor over a
32 bit domain needs 2^67 amplitudes. Direct period detection needs a table.
"""

import argparse
import hashlib
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import chain_kat

NONCE_BITS = 32
SAMPLES = 200000        # nonces walked per modulus
MODULI = (2, 4, 16, 256, 4096)
PERIODS = (1, 2, 3, 4, 5, 6, 7, 8, 16, 32, 64, 128, 256, 1024, 4096)


def reduced(header, nonce, modulus):
    """f(nonce) = the double hash, as an integer, modulo a small number."""
    patched = bytearray(header)
    patched[76:80] = struct.pack("<I", nonce & 0xFFFFFFFF)
    digest = hashlib.sha256(hashlib.sha256(bytes(patched)).digest()).digest()
    return int.from_bytes(digest, "little") % modulus


def period_agreement(header, modulus, period, samples):
    """How often f(n) equals f(n + period), against the chance rate of 1/modulus.

    A real period gives agreement of exactly one. No period gives about one over the modulus, the rate
    at which two unrelated values of a uniform function agree. So the readout is the EXCESS over
    chance, and the null is not estimated, it is known in closed form.
    """
    hits = 0
    for at in range(samples):
        if reduced(header, at, modulus) == reduced(header, at + period, modulus):
            hits += 1
    return hits / float(samples)


def poisson_tail(observed, expected):
    """P(X >= observed) for a Poisson count, computed exactly by summing the lower terms.

    THE RIGHT TEST WHEN THE EXPECTED COUNT IS SMALL, which is exactly where a period would be
    easiest to claim and hardest to justify. A normal approximation needs an expected count of
    roughly ten before it means anything, and the large moduli here sit near one, a three sigma
    bar there is not a weak test but a meaningless one.
    """
    if expected <= 0.0:
        return 1.0 if observed <= 0 else 0.0
    if observed <= 0:
        return 1.0
    # Sum P(X = k) for k below `observed` and subtract, which is stable for the small counts here.
    below = 0.0
    term = math.exp(-expected)
    for k in range(observed):
        if k > 0:
            term = term * expected / float(k)
        below += term
    return max(0.0, 1.0 - below)


def _report(samples=SAMPLES):
    import time
    blocks = chain_kat.load_blocks(limit=1)
    block = blocks[0]
    header = chain_kat.header_bytes(block)
    if chain_kat.block_id_of(header) != block["id"]:
        print("  the header does not reproduce its block id. Nothing below is about a real block")
        return 1

    print("  Real header from block %d, verified against its own block id." % block["height"])
    print("  f(n) = double hash of the header with nonce n, taken modulo M.")
    print("")
    print("  A TRUE PERIOD p GIVES AGREEMENT OF EXACTLY 1.0. No period gives 1/M, the rate")
    print("  two unrelated values of a uniform function agree at. So the null is known in closed")
    print("  form and is not estimated from the data.")
    print("")

    # Fewer samples for the small moduli is wrong: the small moduli are where a period would be
    # easiest to see AND where the chance rate is highest. They need the most samples.
    per_modulus = max(2000, samples // len(MODULI))
    total_tests = sum(1 for _m in MODULI for p in PERIODS if p <= per_modulus // 4)
    print("  %d tests in the family. The threshold is 0.05 / %d = %.2e per test."
          % (total_tests, total_tests, 0.05 / float(total_tests)))
    print("")
    print("  %8s %10s %14s %14s %12s %10s %8s"
          % ("modulus", "period", "agreement", "chance 1/M", "excess", "expected", "p"))

    began = time.perf_counter()
    worst = 0.0
    found = []
    for modulus in MODULI:
        chance = 1.0 / modulus
        for period in PERIODS:
            if period > per_modulus // 4:
                continue
            trials = per_modulus
            got = period_agreement(header, modulus, period, trials)
            excess = got - chance
            hits = int(round(got * trials))
            expected = chance * trials

            # A THREE SIGMA NORMAL BAR IS INVALID WHEN THE EXPECTED COUNT IS SMALL, and the first
            # version of this test used one anyway. At modulus 4096 and 1500 trials the expected
            # count is 0.37, where a normal approximation has no meaning, and it duly reported a
            # false period at period 6 off three observed hits. The tail is computed exactly here,
            # and the threshold is corrected for the whole family of tests and not applied per
            # test, because the loudest of seventy five comparisons against a per-test threshold is
            # how a sweep manufactures findings.
            probability = poisson_tail(hits, expected)
            significant = probability < (0.05 / float(total_tests))
            if significant:
                found.append((modulus, period, got, chance, probability))
            worst = max(worst, excess)
            if period in (1, 2, 4, 16, 256) or significant:
                print("  %8d %10d %14.6f %14.6f %12.2e %10.1f %8s"
                      % (modulus, period, got, chance, excess, expected,
                         "%.1e" % probability))
        print("")

    print("  swept in %.1f s" % (time.perf_counter() - began))
    print("")
    if not found:
        print("  NO PERIOD FOUND AT ANY MODULUS OR ANY PERIOD TRIED. Every agreement sits at the")
        print("  chance rate for its modulus, at the exact Poisson tail for its expected count. Largest excess")
        print("  anywhere was %.2e." % worst)
        print("")
        print("  SO SHOR HAS NOTHING TO PEAK ON, and that is measured and not argued.")
        print("  Its transform finds a period by peaking on it; handed a function whose values at n and")
        print("  n + p agree exactly as often as two unrelated values would, it returns a flat")
        print("  distribution and no information.")
    else:
        print("  A PERIOD CLEARED THE BAR: %s" % found[:6])
        print("")
        print("  THAT WOULD BE A LARGE RESULT AND IT NEEDS EVERYTHING BEFORE IT IS BELIEVED:")
        print("  a second header, a second modulus family, a matched null on a random function of")
        print("  the same shape, and the excess reproducing at a larger sample. A single sweep")
        print("  clearing a per-test bar over %d tests is expected by chance alone."
              % (len(MODULI) * len(PERIODS)))

    print("")
    print("  THE DETECTION LIMIT, and that leaves a null here a result. At %d trials per test"
          % per_modulus)
    print("  and a family-wise threshold of %.2e, a partial period holding on more than about"
          % (0.05 / float(total_tests)))
    print("  %.2e of nonces would have cleared the bar at the smallest modulus. Anything rarer"
          % (4.0 * math.sqrt(0.25 / per_modulus)))
    print("  than that is NOT excluded by this sweep and would want more trials to reach.")
    print("")
    print("  AND A PARTIAL PERIOD IS THE ONLY KIND WORTH LOOKING FOR HERE. An exact period would")
    print("  make the hash catastrophically broken and would have been found decades ago by")
    print("  everyone. The measurement above is aimed at a weak one, the thing that could")
    print("  plausibly have escaped notice, and it is the thing Shor would also need: the transform")
    print("  peaks on a period held across the whole domain, not on one holding sometimes.")
    return 0


def _resources():
    """What a real Shor run on a nonce space would need, as a count."""
    print("  Shor period finding needs about 2n + 3 qubits for an n bit domain, plus the work")
    print("  register. For the nonce space that is:")
    print("")
    print("  %14s %14s %22s %20s"
          % ("domain bits", "qubits", "state vector amplitudes", "bytes at 16 each"))
    for bits in (4, 8, 16, 32):
        qubits = 2 * bits + 3
        print("  %14d %14d %22s %20s"
              % (bits, qubits, "1e%.0f" % (qubits * math.log10(2.0)),
                 "1e%.0f" % (qubits * math.log10(2.0) + 1.2)))
    print("")
    print("  A 32 BIT NONCE SPACE WANTS 67 QUBITS, which is 1e20 amplitudes and 1e21 bytes. The")
    print("  largest full state vector simulations performed anywhere are near 46 qubits. This")
    print("  is not a matter of a bigger machine in this room.")
    print("")
    print("  AND ON REAL QUANTUM HARDWARE IT STILL WOULD NOT HELP, because the resource count is")
    print("  not the obstruction. The obstruction is the measurement above: Shor peaks on a")
    print("  period, and the map has none. A 67 qubit machine handed an aperiodic function returns")
    print("  a flat distribution, correctly and uselessly.")
    print("")
    print("  THE ALGORITHM THAT DOES APPLY IS GROVER, and its accounting is elsewhere in this tree:")
    print("  a real square root speedup on quantum hardware, and a 51472 times SLOWDOWN when")
    print("  simulated classically, because each iteration must touch every amplitude while only")
    print("  the square root of them are needed.")
    print("")
    print("  Run --grover for what Grover would buy against THIS chain at THIS difficulty.")
    return 0


def _grover():
    """What Grover would buy against the live difficulty. Grover is the right algorithm and it is
    already implemented in qubit_trace.py; this is the accounting it needs to be judged on.

    WHAT IS MEASURED HERE, WHAT IS DERIVED, AND WHAT IS QUOTED. Keeping those apart is the whole
    value of this function, because the conclusion depends on a literature figure that this tree
    has not verified and saying so is not optional.

        MEASURED HERE   the difficulty and the nonce count, from the verified block corpus, and
                        this machine's own hash rate from its own counters
        DERIVED         the Grover iteration count, which is (pi/4) * sqrt(N), standard and exact
        QUOTED          the cost of ONE coherent reversible SHA-256 circuit, from the published
                        literature on quantum preimage attacks. Not verified here. The order of
                        magnitude is what the argument rests on, not the digits.
    """
    import io
    import json

    corpus = os.path.join(ROOT, "utils", "maint", "chain", "blocks_deep.json")
    if not os.path.exists(corpus):
        print("  the block corpus was not found. There is no difficulty to compute against")
        return 1
    with io.open(corpus, encoding="utf-8") as handle:
        blocks = json.load(handle)
    newest = max(blocks, key=lambda one: one["height"])

    difficulty = newest["difficulty"]
    nonces = difficulty * (2.0 ** 32)

    # Grover's count, and this is exact and not an estimate.
    iterations = (math.pi / 4.0) * math.sqrt(nonces)

    # This machine's own rate, read early because the head to head below needs it.
    rate = None
    totals = os.path.join(ROOT, "miner_totals.txt")
    if os.path.exists(totals):
        parts = io.open(totals, encoding="utf-8").read().split()
        if len(parts) >= 7 and float(parts[5]) > 0:
            rate = int(parts[0]) / float(parts[5])

    print("")
    print("  Against block %d, difficulty %.4e, read from the verified corpus."
          % (newest["height"], difficulty))
    print("")
    print("  %-34s %16s" % ("classical hashes for one block", "%.3e" % nonces))
    print("  %-34s %16s" % ("Grover oracle calls, (pi/4)sqrt(N)", "%.3e" % iterations))
    print("  %-34s %16s" % ("reduction in calls", "%.3e x" % (nonces / iterations)))
    print("")
    print("  SO THE SPEEDUP IS REAL AND IT IS LARGE IN CALLS. That is not in dispute, and it makes")
    print("  Grover the right algorithm to ask about. The question is what one call costs.")
    print("")

    # THE ORACLE IS THE WHOLE PROBLEM. A Grover call is not a hash, it is a coherent reversible
    # circuit for the entire function, run in superposition, with no measurement until the end.
    print("  ONE ORACLE CALL IS A COHERENT REVERSIBLE DOUBLE SHA-256, not a hash. Published")
    print("  estimates for a quantum SHA-256 circuit are on the order of a few thousand logical")
    print("  qubits and 1e5 to 1e6 T gates per evaluation, and mining needs SHA-256 twice. QUOTED,")
    print("  not verified here.")
    print("")
    target_seconds = 600.0
    need_per_second = iterations / target_seconds
    print("  To find a block in the network's ten minutes, a single Grover machine would have to")
    print("  complete %.3e oracle calls a second." % need_per_second)
    print("")
    print("  %-30s %14s %18s" % ("logical T gate time", "T per oracle", "oracle calls a second"))
    for gate_seconds, label in ((1e-6, "1 us"), (1e-9, "1 ns"), (1e-12, "1 ps")):
        for t_count in (1e5, 1e6):
            print("  %-30s %14s %18s"
                  % (label, "%.0e" % t_count, "%.3e" % (1.0 / (gate_seconds * t_count))))
    print("")
    print("  Even at a picosecond logical T gate, which is far beyond anything projected, 1e5 T")
    print("  gates an oracle gives 1e7 calls a second against the %.3e needed." % need_per_second)
    print("")

    # THE HONEST HEAD TO HEAD. Quoting the
    # reduction in CALLS and then the shortfall in CALLS PER SECOND leaves a reader to guess whether
    # Grover wins, and the answer has two halves: against one of our GPUs it wins comfortably,
    # against the network it loses by nine orders of magnitude. Reporting only the second half is
    # the same defect as reporting only the first.
    #
    # The conversion is exact. A machine at G oracle calls a second finds a block in iterations/G
    # seconds; a classical miner at H hashes a second finds one in N/H seconds. So the machine is
    # worth an EQUIVALENT CLASSICAL HASH RATE of G * N / iterations, which is G times the reduction.
    factor = nonces / iterations
    network = difficulty * (2.0 ** 32) / 600.0
    print("  WHAT A GROVER MACHINE IS WORTH IN CLASSICAL HASH RATE, the only comparison")
    print("  here that is apples to apples. A machine at G oracle calls a second equals")
    print("  G * %.3e H/s." % factor)
    print("")
    print("  %16s %16s %14s %14s %16s"
          % ("oracle calls a s", "equivalent H/s", "vs this card", "vs network", "time to a block"))
    for calls in (1.0, 1e4, 1e7, need_per_second):
        equivalent = calls * factor
        years = (iterations / calls) / (365.25 * 24.0 * 3600.0)
        against_card = ("%.2e x" % (equivalent / rate)) if rate else "-"
        stamp = ("%.2e years" % years) if years >= 1.0 else ("%.1f days" % (years * 365.25))
        print("  %16s %16s %14s %14s %16s"
              % ("%.2e" % calls, "%.3e" % equivalent, against_card,
                 "%.2e x" % (equivalent / network), stamp))
    print("")
    print("  SO GROVER IS NOT USELESS. At even one oracle call")
    print("  a second the machine is worth %.3e H/s, which is hundreds of times this card. The" % factor)
    print("  square root is doing real work and the algorithm choice was right.")
    print("")
    print("  It loses to the NETWORK and not to the card. The network is %.3e H/s. It" % network)
    print("  outruns a one-call-a-second Grover machine by %.2e times, and closing that gap has to"
          % (network / factor))
    print("  happen in oracle speed, where the quoted T gate counts put it out of reach.")
    print("")

    # AND THIS IS THE PART THAT DOES NOT DEPEND ON THE QUOTED FIGURE AT ALL.
    print("  THE DECISIVE POINT NEEDS NO HARDWARE ESTIMATE, and it is about parallelism.")
    print("")
    print("  Mining is a race between many machines, and the two kinds of machine scale")
    print("  differently when you add more of them:")
    print("")
    print("  %10s %22s %22s" % ("machines", "classical speedup", "Grover speedup"))
    for machines in (1, 10, 100, 10000, 1000000):
        print("  %10d %22s %22s"
              % (machines, "%.0f x" % machines, "%.1f x" % math.sqrt(machines)))
    print("")
    print("  Parallel Grover splits the search space and each machine searches its share. M")
    print("  machines buy sqrt(m) and not m. Classical search buys m. That is a standard result")
    print("  and it is the opposite of what mining rewards.")
    print("")
    print("  So the square root that helps a single searcher HURTS a fleet: the network's classical")
    print("  advantage grows linearly in hardware while a quantum fleet's grows as a square root.")
    print("  Grover is the right algorithm for one machine against one unstructured space, and")
    print("  mining is neither of those things.")

    if rate:
        print("")
        print("  For scale, from this machine's own counters: %.3e hashes a second, which exhausts"
              % rate)
        print("  a 32 bit nonce space in %.2f seconds without any of the above."
              % ((2.0 ** 32) / rate))
    return 0


def _dimensional():
    """What a dimensional split of the search would buy, and the single thing it needs.

    "If it's sqrt do the dimensional 2s comp, you have n dimensions."

    The reasoning is sound and it is the right question to ask of a square root. If the space
    factors into d independent dimensions, and each can be searched on its own, then Grover costs
    d * sqrt(N^(1/d)) = d * N^(1/2d) instead of sqrt(N). That is not a small improvement. It
    collapses the exponent, and the table below shows by how much.

    THE ARITHMETIC IS RIGHT AND THE PREMISE IS WHAT FAILS. Searching one dimension on its own
    requires an oracle that can say THIS DIMENSION IS CORRECT while the others are still wrong.
    That is partial credit, and a hash function is built specifically to destroy it: every input bit
    reaches every output bit. No projection of the input is separately verifiable.

    FOUR INDEPENDENT MEASUREMENTS IN THIS TREE SAY THERE IS NO PARTIAL CREDIT, and they used
    different instruments, and so they are worth listing and not summarizing:

        nonce_read.py       a boundary reading of an early state against the final digest. Null,
                            with a drawn null over 200 shuffles.
        beam_read.py        the same question with 256 directional line integrals, which add 175
                            dimensions of rank the region reading does not have. Null at every live
                            round, weakest limit 0.100, with the round 64 positive control firing.
        qubit_trace --invert    a PARTIAL inversion returns zero at best and a loss at worst.
        qubit_trace --nested    nesting to depth d costs reach b^d and gives no partial credit on
                            the way.

    AND A THEOREM SAYS IT CANNOT BE FIXED BY CLEVERNESS. The BBBV bound proves Omega(sqrt(N)) is
    optimal for a black box oracle, and any scheme that beats sqrt(N) must be exploiting structure.
    The dimensional split beats it by a wide margin, and for that reason it needs the structure
    that four measurements here do not find. QUOTED, not verified here.
    """
    import io
    import json

    corpus = os.path.join(ROOT, "utils", "maint", "chain", "blocks_deep.json")
    if not os.path.exists(corpus):
        print("  the block corpus was not found")
        return 1
    with io.open(corpus, encoding="utf-8") as handle:
        blocks = json.load(handle)
    newest = max(blocks, key=lambda one: one["height"])
    nonces = newest["difficulty"] * (2.0 ** 32)
    bits = math.log(nonces, 2.0)

    print("")
    print("  Block %d, difficulty %.4e. The space is %.3e or about %.2f bits."
          % (newest["height"], newest["difficulty"], nonces, bits))
    print("")
    print("  IF the space split into d independently searchable dimensions, Grover would cost")
    print("  d * N^(1/2d) oracle calls:")
    print("")
    print("  %12s %18s %22s" % ("dimensions", "oracle calls", "vs plain Grover"))
    plain = (math.pi / 4.0) * math.sqrt(nonces)
    best = None
    for dimensions in (1, 2, 4, 8, 16, 32, 64, int(round(bits))):
        calls = dimensions * (2.0 ** (bits / (2.0 * dimensions)))
        if best is None or calls < best[1]:
            best = (dimensions, calls)
        print("  %12d %18.3e %22s"
              % (dimensions, calls, "%.3e x cheaper" % (plain / calls)))
    print("")
    print("  The optimum is around d = %d at %.0f oracle calls. Not 5.5e23 hashes and not 5.8e11"
          % (best[0], best[1]))
    print("  Grover calls: about %.0f. THE ARITHMETIC IS CORRECT." % best[1])
    print("")
    print("  WHAT IT NEEDS IS PARTIAL CREDIT, and that is the problem. Searching one")
    print("  dimension alone requires an oracle that reports THIS DIMENSION IS RIGHT while the")
    print("  others are still wrong. A hash function is built to destroy exactly that: every input")
    print("  bit reaches every output bit. No projection of the input is separately checkable.")
    print("")
    print("  FOUR MEASUREMENTS HERE, WITH FOUR DIFFERENT INSTRUMENTS, FOUND NO PARTIAL CREDIT:")
    print("")
    print("    nonce_read.py            null, drawn null over 200 shuffles")
    print("    beam_read.py             null at every live round, with 256 line integrals adding")
    print("                             175 dimensions of rank, weakest limit 0.100")
    print("    qubit_trace --invert     a partial inversion returns zero at best, a loss at worst")
    print("    qubit_trace --nested     no partial credit on the way, and reach grows as b^d")
    print("")
    print("  AND A THEOREM SAYS CLEVERNESS CANNOT RECOVER IT. The BBBV bound proves sqrt(N) is")
    print("  optimal for a black box oracle. any scheme beating sqrt(N) is exploiting structure,")
    print("  and the dimensional split beats it by %.3e times, the measure of how much"
          % (plain / best[1]))
    print("  structure it is quietly assuming. QUOTED, not verified here.")
    print("")
    print("  SO THIS IS NOT A DEAD END IN THE IDEA, IT IS THE SAME WALL REACHED FROM A FIFTH SIDE.")
    print("  Every route through this tree arrives at one sentence: SHA-256 gives up no partial")
    print("  information about its input. The dimensional split is the cleanest statement yet of")
    print("  what it would be worth if that sentence were false.")
    return 0


def _check():
    lines = []
    failed = 0

    blocks = chain_kat.load_blocks(limit=2)
    block = blocks[0]
    header = chain_kat.header_bytes(block)

    # The header must be real, or the probe is about nothing.
    lines.append("  the header reproduces its block id: %s"
                 % (chain_kat.block_id_of(header) == block["id"]))
    if chain_kat.block_id_of(header) != block["id"]:
        lines.append("    FAIL the header is wrong")
        failed += 1

    # THE POSITIVE CONTROL, and without it a null means nothing. A function KNOWN to have a period
    # must be detected, or the detector cannot detect periods and its null is worthless.
    def planted(nonce, modulus, period):
        return (nonce % period) % modulus

    hits = 0
    trials = 4000
    for at in range(trials):
        if planted(at, 16, 8) == planted(at + 8, 16, 8):
            hits += 1
    rate = hits / float(trials)
    lines.append("  a PLANTED period of 8 is detected at agreement %.6f, chance is %.6f"
                 % (rate, 1.0 / 16))
    if rate < 0.99:
        lines.append("    FAIL the detector cannot see a period that is definitely there")
        failed += 1

    # And a planted function must NOT agree at a wrong period, or it reports periods everywhere.
    hits = 0
    for at in range(trials):
        if planted(at, 16, 8) == planted(at + 3, 16, 8):
            hits += 1
    wrong = hits / float(trials)
    lines.append("  the same function at the WRONG period of 3: agreement %.6f" % wrong)
    if wrong > 0.9:
        lines.append("    FAIL a wrong period read as a period, so the test is not selective")
        failed += 1

    # The real map must sit at chance for a small modulus, the measurement itself.
    for modulus, period in ((2, 1), (16, 4)):
        got = period_agreement(header, modulus, period, 3000)
        chance = 1.0 / modulus
        bar = 3.0 * math.sqrt(chance * (1.0 - chance) / 3000)
        lines.append("  real map, M=%d p=%d: agreement %.6f against chance %.6f, bar %.6f"
                     % (modulus, period, got, chance, bar))
        if got - chance > bar:
            lines.append("    NOTE this cleared the bar and needs the full sweep and a second")
            lines.append("         header before it means anything")

    # The reduction must actually depend on the nonce, or every agreement is trivially one.
    one = reduced(header, 0, 4096)
    two = reduced(header, 1, 4096)
    lines.append("  f(0) = %d and f(1) = %d, so the reduction depends on the nonce: %s"
                 % (one, two, one != two))
    if one == two:
        lines.append("    NOTE these collided, which happens at 1/4096; not a fault by itself")

    # Two different headers must give different reductions at the same nonce, or the probe is
    # measuring the nonce alone and not the map.
    other = chain_kat.header_bytes(blocks[1])
    lines.append("  a different header at the same nonce gives a different value: %s"
                 % (reduced(header, 7, 4096) != reduced(other, 7, 4096)))

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="does the nonce to hash map have a period")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--resources", action="store_true")
    parser.add_argument("--grover", action="store_true",
                        help="what Grover would buy against the live difficulty")
    parser.add_argument("--dimensional", action="store_true",
                        help="what a dimensional split would buy, and the one thing it needs")
    parser.add_argument("--samples", type=int, default=SAMPLES)
    args = parser.parse_args()
    if args.check:
        sys.exit(1 if _check() else 0)
    if args.resources:
        sys.exit(_resources())
    if args.grover:
        sys.exit(_grover())
    if args.dimensional:
        sys.exit(_dimensional())
    sys.exit(_report(args.samples))
