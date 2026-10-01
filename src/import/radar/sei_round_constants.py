"""Specific Emitter Identification: does the per-round modulation carry the round constants?

The common mode of the residue fold decrements by almost exactly 2048 sigmas per round. Almost is
the interesting part. Across rounds 10 to 16 the decrements are 2047.1, 2048.4, 2047.7, 2050.5,
2048.5 and 2046.3 - a scatter near 1.5 where the fold's own measurement error is nearer 0.25.

Rounds differ in exactly one thing. The round function is identical at every depth; only the round
constant K_t changes, and the schedule word. So if that modulation is larger than noise it has to
be carried by K_t, and this is the electronic-warfare question asked literally: an emitter is
identified not by its intended signal but by the unintentional modulation its hardware imposes.

Two things are needed and both are checked here. First, whether the scatter is real - which is
settled by comparing it to the error the fold actually has, estimated from the deep rounds where
there is no signal at all. Second, whether it correlates with anything about K_t.

    python tools/sei_round_constants.py

The constants are read from the tree and never retyped, because a transcription error here would
manufacture exactly the correlation being looked for.
"""

import csv
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SOURCE = os.path.join(ROOT, "src", "bench", "shadows.csv")
CONSTANTS = os.path.join(ROOT, "src", "bench", "bench_depth_cuda.cu")

CLEAN_FIRST = 8
CLEAN_LAST = 16


def load_constants():
    with open(CONSTANTS) as handle:
        text = handle.read()
    found = re.findall(r"0x([0-9a-fA-F]{8})u", text)
    seen = []
    for item in found:
        value = int(item, 16)
        if value not in seen:
            seen.append(value)
        if len(seen) == 64:
            break
    return seen


def load_fold():
    by_round = {}
    with open(SOURCE, newline="") as handle:
        for row in csv.DictReader(handle):
            if row["kind"] != "residue":
                continue
            by_round.setdefault(int(row["round"]), {})[int(row["a"])] = float(row["value"])
    return by_round


def correlate(left, right):
    count = len(left)
    if count < 3:
        return 0.0
    mean_left = sum(left) / count
    mean_right = sum(right) / count
    top = sum((left[i] - mean_left) * (right[i] - mean_right) for i in range(count))
    lower_left = sum((v - mean_left) ** 2 for v in left)
    lower_right = sum((v - mean_right) ** 2 for v in right)
    if lower_left <= 0 or lower_right <= 0:
        return 0.0
    return top / math.sqrt(lower_left * lower_right)


def main():
    if not os.path.exists(SOURCE):
        sys.stderr.write("no shadows.csv - run: src/bench/bench_sac.exe 18 45 64 shadow\n")
        return 1

    constants = load_constants()
    if len(constants) < 64:
        sys.stderr.write("only found %d constants; not proceeding\n" % len(constants))
        return 1
    print("Read %d round constants from the tree; K[0] = %08x, K[63] = %08x\n"
          % (len(constants), constants[0], constants[63]))

    by_round = load_fold()
    common = {}
    for at, classes in by_round.items():
        common[at] = sum(classes[k] for k in range(32)) / 32.0

    # -- is the scatter real? --------------------------------------------------------------------
    #
    # The honest error on the common mode is measured, not assumed: past round 23 there is no
    # signal, so the round-to-round variation there is what this statistic does when nothing is
    # happening.
    quiet = [common[r] for r in range(30, 65) if r in common]
    quiet_steps = [quiet[i + 1] - quiet[i] for i in range(len(quiet) - 1)]
    quiet_mean = sum(quiet_steps) / len(quiet_steps)
    quiet_spread = math.sqrt(sum((s - quiet_mean) ** 2 for s in quiet_steps)
                             / (len(quiet_steps) - 1))

    steps = []
    rounds = []
    for at in range(CLEAN_FIRST, CLEAN_LAST):
        if at in common and (at + 1) in common:
            steps.append(common[at] - common[at + 1])
            rounds.append(at)

    mean_step = sum(steps) / len(steps)
    spread = math.sqrt(sum((s - mean_step) ** 2 for s in steps) / (len(steps) - 1))

    print("Decrement of the common mode, rounds %d to %d:" % (CLEAN_FIRST, CLEAN_LAST))
    print("  " + "  ".join("%.1f" % s for s in steps))
    print("\n  mean            %8.2f" % mean_step)
    print("  scatter         %8.2f" % spread)
    print("  quiet-round scatter %8.4f   (measured past round 30, where nothing happens)"
          % quiet_spread)
    ratio = spread / quiet_spread if quiet_spread > 0 else 0.0
    print("  ratio           %8.2f" % ratio)
    if ratio < 3.0:
        print("\n  The scatter is not clearly above what this statistic does when nothing is")
        print("  happening. There is no modulation to identify, and the correlations below are")
        print("  being computed on noise. Reported anyway rather than dropped.")
    else:
        print("\n  The scatter stands above the quiet rounds, so there is something to explain.")

    # -- does it track anything about K_t? -------------------------------------------------------
    print("\nAgainst properties of the round constant. The decrement from round r to r+1 is")
    print("tested against K at r-1, since rounds here are one-based and K is zero-based.\n")

    features = {
        "popcount K": lambda k: float(bin(k).count("1")),
        "K low 16 bits": lambda k: float(k & 0xFFFF),
        "K high 16 bits": lambda k: float(k >> 16),
        "K top bit": lambda k: float((k >> 31) & 1),
        "popcount of K xor next": None,
    }

    print("  %-22s %8s %8s" % ("feature", "r", "t"))
    print("  %-22s %8s %8s" % ("-" * 22, "--------", "--------"))
    for name, getter in features.items():
        if getter is None:
            values = []
            for at in rounds:
                here = constants[at - 1]
                nxt = constants[at]
                values.append(float(bin(here ^ nxt).count("1")))
        else:
            values = [getter(constants[at - 1]) for at in rounds]
        r = correlate(steps, values)
        count = len(steps)
        t = r * math.sqrt(count - 2) / math.sqrt(1 - (r * r)) if abs(r) < 0.999 else float("inf")
        print("  %-22s %8.3f %8.2f" % (name, r, t))

    print("\n  With %d points, |r| must exceed about %.2f for two-sided significance at 0.05."
          % (len(steps), 2.31 / math.sqrt(len(steps))))
    print("  Five features were tried, so the threshold to clear is higher still.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
