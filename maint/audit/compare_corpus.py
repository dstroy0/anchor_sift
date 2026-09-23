"""Differences the clean survey against the contaminated chain, position by position.

The survey hashes synthetic headers on the device and counts every output bit. Nothing selects the
results and no operator touches them, so it is the construction's own distribution measured to a
depth no chain could reach. The chain corpus is the same function's output contaminated twice over:
every digest was SELECTED for sitting below a target, and every one was produced by a machine whose
conventions we spent the night measuring.

Having both makes a subtraction possible that neither supports alone.

THE TRAP

A real block's digest carries seventy-odd leading zeros by construction. Comparing those positions
against the survey measures the difficulty rule, not the miners, and would report an enormous and
entirely uninteresting difference. So the leading run is excluded and the question is asked only of
the positions past it:

    conditioning on the top k bits being zero leaves the remaining 256 - k uniform

That is what the theory says, it is not obvious, and it is exactly what a selected sample lets you
check. If tilt reaches past the zero run it shows here and nowhere else.

THE FLOOR

The survey's precision is irrelevant to the comparison. A few thousand real digests give a standard
error near one over twice the square root of that count, which is four parts in a thousand, so the
chain side sets the floor and the survey side is exact by comparison. The bar is the loudest of the
positions tested, not a single position's, and it is drawn from the same binomial.

    python maint/audit/compare_corpus.py
"""

import argparse
import glob
import io
import json
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ARM_DIR = os.path.join(os.path.expanduser("~"), ".claude", "jobs", "52b29cc3", "tmp")


def target_of(bits):
    """The difficulty target a compact nBits encodes, as a 256-bit integer."""
    exponent = (int(bits) >> 24) & 0xFF
    mantissa = int(bits) & 0x00FFFFFF
    if exponent <= 3:
        return mantissa >> (8 * (3 - exponent))
    return mantissa << (8 * (exponent - 3))


def load_digests():
    """Every distinct digest with the target it had to beat.

    The target matters and carrying only the digest is what went wrong twice. A digest is free in
    its lower bits only where its own leading run EXCEEDS its target's run: at equal depth the
    remaining bits are bounded by the target's remaining bits, so they are still selected. And the
    corpora span difficulty epochs whose targets differ, so the free region is per block and cannot
    be drawn once for the whole corpus.
    """
    seen = {}
    for name in ("blocks.json", "blocks_deep.json", "blocks_2021.json", "blocks_labelled.json"):
        path = os.path.join(ROOT, "maint", "chain", name)
        if not os.path.exists(path):
            continue
        with io.open(path, encoding="utf-8") as handle:
            for block in json.load(handle):
                target = target_of(block["bits"])
                seen[block["id"]] = (int(block["id"], 16), target)
    return list(seen.values())


def load_survey():
    """Pooled arm counts: the construction's own distribution, from synthetic headers."""
    counts = [0] * 256
    total = 0
    for path in sorted(glob.glob(os.path.join(ARM_DIR, "survey_arm_*.json"))):
        with io.open(path, encoding="utf-8") as handle:
            arm = json.load(handle)
        total += int(arm["nonces"])
        for position in range(256):
            counts[position] += int(arm["bits"][position])
    return counts, total


def main():
    parser = argparse.ArgumentParser(description="Difference the survey against the chain.")
    parser.add_argument("--skip", type=int, default=0,
                        help="positions to exclude from the top. 0 means work it out from the data.")
    given = parser.parse_args()

    digests = load_digests()
    survey_counts, survey_total = load_survey()
    if not digests or survey_total == 0:
        raise SystemExit("need both a chain corpus and at least one survey arm")

    print("  chain digests     %s distinct" % format(len(digests), ","))
    print("  survey samples    %s" % format(survey_total, ","))
    print()

    # The selected region: how deep does the zero run go in the shallowest real block?
    shallowest = min(256 - value.bit_length() for value, _ in digests)
    skip = given.skip if given.skip > 0 else shallowest
    print("=" * 76)
    print("  THE SELECTED REGION, EXCLUDED")
    print("=" * 76)
    print()
    print("    shallowest digest in the corpus carries %d leading zeros" % shallowest)
    print("    positions 0 to %d are therefore the difficulty rule, not the miners" % (skip - 1))
    print("    %d positions remain to be tested" % (256 - skip))

    # Conditioning is per digest, not per corpus. A digest whose leading run is L has bit L set by
    # the definition of a leading run and every bit past L unconstrained, so position p may only be
    # counted over digests with L < p. An earlier version excluded one region for the whole corpus,
    # using the SHALLOWEST run, which left most digests still inside their own constrained region
    # and reported position 76 at seventy-seven standard errors. That was the exclusion, not tilt.
    chain_counts = [0] * 256
    chain_at = [0] * 256
    freed = 0
    for value, target in digests:
        run = 256 - value.bit_length()
        target_run = 256 - target.bit_length()
        # Free only where the digest's own run beats its target's run. At equal depth the lower
        # bits are still bounded by the target and are selected, not free.
        if run <= target_run:
            continue
        freed += 1
        for position in range(run + 1, 256):
            chain_at[position] += 1
            if (value >> (255 - position)) & 1:
                chain_counts[position] += 1

    print("    digests whose own run beats their target's, so their lower bits are free: %d of %d"
          % (freed, len(digests)))

    print()
    print("=" * 76)
    print("  THE COMPARISON")
    print("=" * 76)
    print()
    # The survey's share at each position, as an exact rational, against the chain's count.
    # Testing is integer: chain_count * 2 * survey_total against survey_count * 2 * chain_total,
    # scaled so no division is needed for the decision.
    worst_at, worst_z = skip, 0.0
    squared = 0.0
    tested = 0
    for position in range(256):
        # Only digests that reach this position contribute, and a position too thin to measure is
        # skipped rather than reported with a floor it cannot support.
        reaching = chain_at[position]
        if reaching < 200:
            continue
        share = survey_counts[position] / float(survey_total)
        expected = reaching * share
        variance = reaching * share * (1.0 - share)
        if variance <= 0:
            continue
        z = (chain_counts[position] - expected) / math.sqrt(variance)
        squared += z * z
        tested += 1
        if abs(z) > abs(worst_z):
            worst_at, worst_z = position, z

    bar = math.sqrt(2.0 * math.log(max(tested, 2)))
    print("    positions tested        %d" % tested)
    print("    loudest                 position %d at %+.2f sd" % (worst_at, worst_z))
    print("    bar, loudest of %-3d     about %.2f sd" % (tested, bar))
    print("    sum of squared z        %.1f, expectation %d" % (squared, tested))
    print("    that sum as a chi-square  %+.2f sd from its own mean"
          % ((squared - tested) / math.sqrt(2.0 * tested)))
    print()
    if abs(worst_z) < bar:
        print("    Nothing clears. Selection for a low digest leaves every other position exactly")
        print("    where the construction puts it, and the operator tilt measured in the version")
        print("    and timestamp fields does not reach the digest at all.")
        print()
        print("    That is worth stating plainly: the tilt is real and large in the fields miners")
        print("    CHOOSE, and absent from the field the function PRODUCES. Those are different")
        print("    parts of the same eighty bytes, and only one of them is theirs to move.")
    else:
        print("    Position %d clears the loudest-of-%d bar. That would mean selection reaches"
              % (worst_at, tested))
        print("    past the zero run, which the theory says it cannot, so the first suspect is")
        print("    the corpus rather than the construction.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
