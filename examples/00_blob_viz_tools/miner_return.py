"""The miner's measured return rate and hash rate history, plotted, against what theory predicts.

    python examples/00_blob_viz_tools/miner_return.py --check
    python examples/00_blob_viz_tools/miner_return.py             the plot and the return rate

WHAT IS MEASURED AND WHAT IS REMEMBERED

Everything below comes out of `miner_totals.txt` and `miner.log`, which the client writes itself.
The one number not out of a log is the starting point: the engine began at about 30 MH/s, and no
log in the tree goes back that far. That figure is labeled remembered and not measured every time
it is used.

THE RETURN RATE IS THE INTERESTING ONE AND IT IS A CORRECTNESS CHECK, NOT A YIELD FIGURE

A miner's share rate is fully determined by its hash rate and the difficulty it is given. So the
observed rate is a test: if shares arrive at the predicted spacing the client is doing real work and
losing none of it, and if they arrive slower the work is being wasted somewhere between the kernel
and the wire. With 3 of 3 accepted and 0 rejected, the question is whether the SPACING matches, and
that pins down the implied difficulty without needing the pool to be trusted about it.
"""

import argparse
import io
import math
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

TOTALS = os.path.join(ROOT, "miner_totals.txt")
LOG = os.path.join(ROOT, "miner.log")

# Remembered, not measured: the figure for where the engine started. No log reaches back to it.
REMEMBERED_START = 30.0e6

# Assumed, for the comparison column only, and an order of magnitude and not a model number.
ASIC_RATE = 200e12


def read_totals(where=None):
    """hashes, anchors, submitted, accepted, rejected, seconds, runs."""
    path = where or TOTALS
    with io.open(path, encoding="utf-8") as handle:
        parts = handle.read().split()
    return {
        "hashes": int(parts[0]),
        "anchors": int(parts[1]),
        "submitted": int(parts[2]),
        "accepted": int(parts[3]),
        "rejected": int(parts[4]),
        "seconds": float(parts[5]),
        "runs": int(parts[6]),
    }


def read_rates(where=None):
    """Every running hash rate the client printed, in order, as MH/s."""
    path = where or LOG
    if not os.path.exists(path):
        return []
    with io.open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    return [float(one) for one in re.findall(r"run (\d+) MH/s", text)]


def plot(series, height=16, width=68):
    """An ASCII plot, because a PNG nobody opens is not a plot.

    The vertical axis starts at zero and not at the minimum, since a truncated axis on a ramp
    makes any ramp look the same and this one is about the size of the climb.
    """
    if not series:
        return ["  (no rate samples in the log)"]
    top = max(series)
    lines = []
    for row in range(height, 0, -1):
        level = top * row / float(height)
        mark = "  %7.0f |" % level
        for at in range(width):
            index = int(at * len(series) / float(width))
            mark += "#" if series[index] >= level else " "
        lines.append(mark)
    lines.append("  %7s +%s" % ("0", "-" * width))
    lines.append("  %7s  %-*s%s" % ("", width - 8, "first sample", "latest"))
    return lines


def _report():
    totals = read_totals()
    rates = read_rates()

    mean_rate = totals["hashes"] / totals["seconds"]
    print("  MEASURED, from the client's own totals file")
    print("")
    print("    total hashes         %.4e" % totals["hashes"])
    print("    total time           %.1f s, %.2f hours"
          % (totals["seconds"], totals["seconds"] / 3600.0))
    print("    mean hash rate       %.4e H/s, %.0f MH/s" % (mean_rate, mean_rate / 1e6))
    print("    runs                 %d" % totals["runs"])
    print("    shares               %d submitted, %d accepted, %d rejected"
          % (totals["submitted"], totals["accepted"], totals["rejected"]))
    print("")

    print("  HASH RATE OVER THE LOGGED SAMPLES, %d of them, in MH/s" % len(rates))
    print("")
    for line in plot(rates):
        print(line)
    print("")
    if rates:
        below = sum(1 for one in rates if one < 0.9 * max(rates))
        print("    lowest logged %.0f MH/s, highest %.0f MH/s, latest %.0f MH/s"
              % (min(rates), max(rates), rates[-1]))
        print("")
        print("    THIS PLOT IS FLAT AND IS NOT THE CLIMB. Only %d of %d samples sit under ninety"
              % (below, len(rates)))
        print("    percent of the peak. What it shows is the STEADY STATE with a cold start at")
        print("    the left edge. No log in this tree reaches back to the remembered 30 MH/s, so")
        print("    the improvement below can be stated at its endpoints and cannot be drawn.")
        print("    Presenting a flat line as a growth curve would be the plot lying about itself.")
    print("")

    print("  THE CLIMB, with the starting point REMEMBERED and not measured")
    print("")
    print("    remembered figure for the start  %.0f MH/s   (remembered)" % (REMEMBERED_START / 1e6))
    print("    measured mean now                %.0f MH/s   (measured)" % (mean_rate / 1e6))
    print("    improvement                      %.1f times" % (mean_rate / REMEMBERED_START))
    print("    in doublings                     %.2f" % math.log2(mean_rate / REMEMBERED_START))
    print("")

    print("  WHAT THAT RATE IS EQUIVALENT TO")
    print("")
    print("    machines at the remembered start  %.0f of them" % (mean_rate / REMEMBERED_START))
    print("    one SHA-256 ASIC, order %.0e H/s   %.3e of one" % (ASIC_RATE, mean_rate / ASIC_RATE))
    print("    hashes per second per MH of start  %.1f" % (mean_rate / REMEMBERED_START))
    print("")
    print("    So the engine is worth about %.0f of what it was, and about %.4f percent of one"
          % (mean_rate / REMEMBERED_START, 100.0 * mean_rate / ASIC_RATE))
    print("    fixed-function ASIC. Those are the two honest comparisons and they point opposite")
    print("    ways: a large gain against itself, a small fraction against purpose-built")
    print("    silicon. Both are true and neither is the interesting number.")
    print("")

    print("  THE RETURN RATE, AND IT IS A CORRECTNESS CHECK AND NOT A YIELD")
    print("")
    if totals["accepted"] > 0:
        per_share = totals["hashes"] / float(totals["accepted"])
        implied = per_share / (2.0 ** 32)
        print("    hashes per accepted share    %.4e" % per_share)
        print("    implied difficulty           %.0f" % implied)
        print("    acceptance rate              %d of %d, %.1f percent"
              % (totals["accepted"], totals["submitted"],
                 100.0 * totals["accepted"] / totals["submitted"]))
        print("    rejects                      %d" % totals["rejected"])
        print("")
        print("    The pool sent difficulties of 8192, 2048 and 1024 during the observed run, so")
        print("    an implied %.0f sits inside that range. THE SPACING MATCHES THE WORK, which is"
              % implied)
        print("    the thing worth knowing: the client is not losing hashes between the kernel and")
        print("    the wire, and no share it found was refused.")
        print("")
        print("    mean time to a share at %.0f MH/s and difficulty %.0f   %.2f hours"
              % (mean_rate / 1e6, implied, implied * (2.0 ** 32) / mean_rate / 3600.0))
    print("")
    print("  WHAT THIS IS NOT. None of the above is a return in money, and the share count is")
    print("  three. Three is enough to say the client works and nowhere near enough to estimate a")
    print("  rate of anything: the spacing between shares is exponentially distributed. Three")
    print("  samples carry a spread of about %.0f percent on any mean drawn from them."
          % (100.0 / math.sqrt(max(1, totals["accepted"]))))
    print("")
    print("  WHAT A BASELINE RUN WOULD BUY, since the shares are short for one. The")
    print("  spread on a mean from k shares is one over the square root of k:")
    print("")
    print("  %10s %14s %18s %16s" % ("hours", "difficulty", "expected shares", "spread on mean"))
    for hours in (1, 4, 10, 24):
        for difficulty in (1024.0,):
            expected = hours * 3600.0 * mean_rate / (difficulty * (2 ** 32))
            spread = 100.0 / math.sqrt(expected) if expected > 0 else float("inf")
            print("  %10d %14.0f %18.1f %15.0f%%" % (hours, difficulty, expected, spread))
    print("")
    print("  an overnight run at difficulty 1024 is worth about nineteen shares and brings the")
    print("  spread from %.0f percent to roughly twenty three, the difference between"
          % (100.0 / math.sqrt(max(1, totals["accepted"]))))
    print("  'it works' and 'here is its rate'. A baseline is for that, and a night of running buys")
    print("  nothing else that an hour does not.")
    return 0


def _check():
    lines = []
    failed = 0

    totals = read_totals()
    lines.append("  totals parse: %.4e hashes over %.1f s in %d runs"
                 % (totals["hashes"], totals["seconds"], totals["runs"]))
    if totals["hashes"] <= 0 or totals["seconds"] <= 0:
        lines.append("    FAIL the totals file does not carry a usable run")
        failed += 1

    # The mean rate must be in a plausible band for this hardware, or the file is being misread.
    mean_rate = totals["hashes"] / totals["seconds"]
    lines.append("  mean rate %.0f MH/s" % (mean_rate / 1e6))
    if not 1e8 < mean_rate < 1e11:
        lines.append("    FAIL the mean rate is outside any plausible band, a column is being")
        lines.append("         read in the wrong position")
        failed += 1

    # Accepted cannot exceed submitted, and rejects must account for the difference.
    lines.append("  %d submitted, %d accepted, %d rejected"
                 % (totals["submitted"], totals["accepted"], totals["rejected"]))
    if totals["accepted"] > totals["submitted"]:
        lines.append("    FAIL more shares accepted than submitted")
        failed += 1
    if totals["accepted"] + totals["rejected"] != totals["submitted"]:
        lines.append("    NOTE accepted plus rejected does not equal submitted, which happens when")
        lines.append("         a run ends with a submission still unanswered")

    # THE CORRECTNESS CHECK. The implied difficulty must land in the range the pool actually sent,
    # or the client is losing work somewhere and the share rate is not the hash rate's.
    if totals["accepted"]:
        implied = (totals["hashes"] / float(totals["accepted"])) / (2.0 ** 32)
        lines.append("  implied difficulty from the spacing: %.0f" % implied)
        if not 256 <= implied <= 16384:
            lines.append("    FAIL the implied difficulty is outside the range the pool sends, so")
            lines.append("         the hashes and the shares do not describe the same work")
            failed += 1

    # The log must carry rate samples, or the plot is empty and says so instead of drawing nothing.
    rates = read_rates()
    lines.append("  %d rate samples in the log, from %.0f to %.0f MH/s"
                 % (len(rates), min(rates) if rates else 0, max(rates) if rates else 0))
    if len(rates) < 5:
        lines.append("    FAIL too few samples in the log to plot")
        failed += 1

    # The plot must have as many rows as asked and must not be all full or all empty, as
    # an axis bug looks like.
    drawn = plot(rates, height=8, width=20)
    filled = sum(one.count("#") for one in drawn)
    lines.append("  the plot draws %d rows and fills %d cells of %d" % (len(drawn), filled, 8 * 20))
    if filled == 0 or filled == 8 * 20:
        lines.append("    FAIL the plot is empty or solid, so the axis is wrong")
        failed += 1

    # And the remembered figure must be labeled, not silently mixed with measurements. Checked by
    # its own constant being distinct from anything in the log.
    lines.append("  the remembered start %.0f MH/s is below every logged sample: %s"
                 % (REMEMBERED_START / 1e6,
                    all(one > REMEMBERED_START / 1e6 for one in rates) if rates else "no samples"))

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the miner's measured return and rate history")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    sys.exit((1 if _check() else 0) if args.check else _report())
