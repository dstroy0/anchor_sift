"""Tests a visual claim: periodic spikes in the input-bit shadow, aligned at a tilt.

Seen from the front at ground level the voxel field appears to hold distinct spikes running deep,
periodic across the input bits and leaning at a constant angle. A tilt is a fixed ratio of bits to
rounds, and the message schedule predicts exactly one: thirty-two bits per round, because a word is
thirty-two bits wide and each enters one round after the last. Anything else would be new.

Two questions, and the second only matters if the first survives.

  is anything there deep?   the excess per input bit past round 23, against its own scatter
  is it periodic?           autocorrelation of that profile in the bit index, where a period of
                            32 is the word structure and any other period is not accounted for

    python tools/check_tilt.py
"""

import csv
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SOURCE = os.path.join(os.path.dirname(os.path.dirname(HERE)), "src", "bench", "shadows.csv")

DEEP_FIRST = 24
DEEP_LAST = 48


def main():
    if not os.path.exists(SOURCE):
        sys.stderr.write("no shadows.csv\n")
        return 1

    field = {}
    with open(SOURCE, newline="") as handle:
        for row in csv.DictReader(handle):
            if row["kind"] == "inbit":
                field.setdefault(int(row["a"]), {})[int(row["round"])] = float(row["value"])

    bits = sorted(field.keys())
    rounds = [r for r in range(DEEP_FIRST, DEEP_LAST + 1) if r in field[bits[0]]]

    # One number per input bit: its mean excess across the deep rounds. Each round is its own seed,
    # so averaging gains sqrt(len(rounds)) on anything that persists and nothing on noise.
    profile = []
    for b in bits:
        each = [field[b][r] for r in rounds]
        profile.append(sum(each) / len(each))

    mean = sum(profile) / len(profile)
    spread = math.sqrt(sum((v - mean) ** 2 for v in profile) / (len(profile) - 1))

    print("Input-bit excess averaged over rounds %d to %d, %d rounds each on its own seed.\n"
          % (DEEP_FIRST, DEEP_LAST, len(rounds)))
    print("  mean    %10.2f" % mean)
    print("  scatter %10.2f" % spread)

    ranked = sorted(range(len(profile)), key=lambda i: abs(profile[i] - mean), reverse=True)
    peak = math.sqrt(2.0 * math.log(float(len(profile))))
    print("  largest of %d peaks near %.2f sigmas under a null\n" % (len(profile), peak))

    print("  %8s %10s %10s %8s %8s" % ("bit", "excess", "sigmas", "word", "in-word"))
    print("  %8s %10s %10s %8s %8s" % ("-" * 8, "-" * 10, "-" * 10, "-" * 8, "-" * 8))
    for i in ranked[:8]:
        z = (profile[i] - mean) / spread
        print("  %8d %10.2f %10.2f %8d %8d" % (i, profile[i], z, i // 32, i % 32))

    worst = abs(profile[ranked[0]] - mean) / spread
    if worst < peak:
        print("\n  Nothing stands above the null peak. There are no deep spikes in this profile,")
        print("  so the periodicity question below is being asked of noise. Reported anyway.")
    else:
        print("\n  Something stands above the null peak; the periodicity below is worth reading.")

    # -- periodicity ------------------------------------------------------------------------------
    print("\nAutocorrelation of the profile in the bit index. A period of 32 is the word")
    print("structure and expected; any other period is not accounted for.\n")

    centred = [v - mean for v in profile]
    power = sum(v * v for v in centred)
    print("  %8s %12s" % ("lag", "correlation"))
    print("  %8s %12s" % ("-" * 8, "-" * 12))
    best_lag = 0
    best_value = 0.0
    for lag in range(1, 65):
        total = 0.0
        for i in range(len(centred)):
            total += centred[i] * centred[(i + lag) % len(centred)]
        value = total / power if power > 0 else 0.0
        if abs(value) > abs(best_value):
            best_value = value
            best_lag = lag
        if lag in (1, 2, 4, 8, 16, 32, 48, 64):
            print("  %8d %12.4f" % (lag, value))

    error = 1.0 / math.sqrt(float(len(profile)))
    print("\n  strongest lag %d at %.4f, against a white-noise error of %.4f (%.2f sigmas)"
          % (best_lag, best_value, error, best_value / error))
    print("  Sixty-four lags were scanned, so the peak to clear is %.2f, not 2."
          % math.sqrt(2.0 * math.log(64.0)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
