"""Watches a running miner against calibrated models instead of guessed thresholds.

Every miner watchdog sets its alarms by judgment - warn under so many megahashes, complain after so
many seconds without a share - and every one of those numbers is somebody's guess. The quantities
being watched here have known distributions, so the thresholds can be computed instead.

Four checks, each with its floor derived from the process rather than chosen:

  anchor rate     the anchor fires when one 32-bit word lands on zero, so survivors are Poisson
                  with mean hashes / 2^32. That makes the ratio the log already prints testable:
                  a deficit means the kernel is missing survivors, which is a CORRECTNESS fault
                  and not a performance one. This is the most valuable check here because a miner
                  that quietly computes the wrong thing looks exactly like one that is working.
  hashrate drift  the instantaneous rate wanders by timing jitter alone, and that spread is stable
                  on healthy hardware. A widening spread is thermal throttling before the mean has
                  moved far enough to notice.
  share arrivals  shares are Poisson at the pool's share difficulty, so the gaps are exponential
                  with a known mean. A drought is only meaningful against that mean, and the
                  probability of a drought this long is computable rather than alarming.
  job cadence     a pool sends work on its own rhythm. The gaps are what they are, and the alarm
                  belongs at a quantile of the observed distribution, not at a round number.

    python maint/audit/watchdog.py
    python maint/audit/watchdog.py --log build/miner_20260910_234344.log
    python maint/audit/watchdog.py --follow          watch a live miner

Read only. It parses the log and never touches the miner.
"""

import argparse
import glob
import math
import os
import re
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

# [2572s] now 2417  run 2399 MH/s  h 6170473398272  anc 1388 (0.99x due)  sh 2/2
SAMPLE = re.compile(
    r"\[(\d+)s\]\s+now\s+(\d+)\s+run\s+(\d+)\s+MH/s\s+h\s+(\d+)\s+anc\s+(\d+)"
    r"(?:\s+\(([\d.]+)x due\))?\s+sh\s+(\d+)/(\d+)")
JOB = re.compile(r"\[JOB\]\s+([0-9a-f]+)\s+branch\s+(\d+)\s+ntime\s+([0-9a-f]{8})")

ANCHOR_SPACE = 1 << 32


def newest_log():
    found = sorted(glob.glob(os.path.join(ROOT, "build", "miner_*.log")),
                   key=os.path.getmtime, reverse=True)
    found = [f for f in found if "token" not in os.path.basename(f)]
    return found[0] if found else None


def read(path):
    samples, jobs = [], []
    with open(path, "r", errors="replace") as handle:
        for line in handle:
            for piece in SAMPLE.finditer(line):
                samples.append({
                    "at": int(piece.group(1)),
                    "now": int(piece.group(2)),
                    "run": int(piece.group(3)),
                    "hashes": int(piece.group(4)),
                    "anchors": int(piece.group(5)),
                    "accepted": int(piece.group(7)),
                    "submitted": int(piece.group(8)),
                })
            for piece in JOB.finditer(line):
                jobs.append({"id": piece.group(1), "ntime": int(piece.group(3), 16)})
    return samples, jobs


def report(path):
    samples, jobs = read(path)
    if len(samples) < 12:
        print("  too few samples in %s: %d" % (os.path.basename(path), len(samples)))
        return 1

    first, last = samples[0], samples[-1]
    span = last["at"] - first["at"]
    print("  %s" % os.path.basename(path))
    print("  %d samples over %d seconds, %d jobs" % (len(samples), span, len(jobs)))
    print()

    print("=" * 74)
    print("  1. ANCHOR RATE  -  a correctness check, not a health one")
    print("=" * 74)
    hashes = last["hashes"]
    anchors = last["anchors"]
    expected = hashes / float(ANCHOR_SPACE)
    spread = math.sqrt(expected) if expected > 0 else 1.0
    z = (anchors - expected) / spread if spread else 0.0
    print()
    print("    hashes computed     %s" % format(hashes, ","))
    print("    anchors observed    %s" % format(anchors, ","))
    print("    Poisson expectation %s   (hashes / 2^32)" % format(int(expected), ","))
    print("    spread              %.1f   (the square root of the mean)" % spread)
    print("    separation          %+.2f sd" % z)
    print()
    if abs(z) < 3.0:
        print("    OK. The kernel is finding survivors at the rate the arithmetic demands.")
    elif z < 0:
        print("    FAULT. The kernel is missing survivors. A deficit here is a correctness")
        print("    problem: the device is computing something other than SHA-256, and a miner")
        print("    that computes the wrong thing looks exactly like one that works.")
    else:
        print("    FAULT. More survivors than 2^32 allows, which means the anchor test itself")
        print("    is wrong, not the hashing.")
    print()
    print("    depth needed for a 1%% deficit to clear 3 sd: %s hashes"
          % format(int(9.0 / (0.01 ** 2) * ANCHOR_SPACE), ","))

    print()
    print("=" * 74)
    print("  2. HASHRATE DRIFT  -  throttling shows in the spread before the mean")
    print("=" * 74)
    rates = [s["now"] for s in samples]
    half = len(rates) // 2
    for name, part in (("first half", rates[:half]), ("second half", rates[half:])):
        mean = sum(part) / len(part)
        sd = (sum((v - mean) ** 2 for v in part) / len(part)) ** 0.5
        print("    %-12s mean %7.1f MH/s   spread %5.1f   (%.2f%% of mean)"
              % (name, mean, sd, 100.0 * sd / mean if mean else 0.0))
    a, b = rates[:half], rates[half:]
    ma, mb = sum(a) / len(a), sum(b) / len(b)
    sa = (sum((v - ma) ** 2 for v in a) / len(a)) ** 0.5
    sb = (sum((v - mb) ** 2 for v in b) / len(b)) ** 0.5
    se = math.sqrt(sa * sa / len(a) + sb * sb / len(b))
    print()
    print("    change in mean      %+.2f sd" % ((mb - ma) / se if se else 0.0))
    print("    change in spread    %.2fx" % (sb / sa if sa else 0.0))
    print()
    if se and abs((mb - ma) / se) >= 3.0:
        print("    The rate moved. On a card that was not reconfigured, that is thermal.")
    elif sa and sb / sa > 1.5:
        print("    The spread widened without the mean moving, which is throttling starting.")
    else:
        print("    OK. Rate and spread both steady.")

    print()
    print("=" * 74)
    print("  3. SHARES")
    print("=" * 74)
    print()
    print("    accepted %d of %d submitted, %d rejected"
          % (last["accepted"], last["submitted"], last["submitted"] - last["accepted"]))
    if last["submitted"] >= 1 and span > 0:
        gap = span / float(last["submitted"])
        print("    mean gap between submissions   %.0f s" % gap)
        quiet = span - (last["submitted"] * gap)
        print()
        print("    A drought is only meaningful against that mean: the chance of going t seconds")
        print("    with no share is exp(-t / %.0f), so" % gap)
        for t in (gap, 2 * gap, 3 * gap, 5 * gap):
            print("      %6.0f s with none   probability %.4f" % (t, math.exp(-t / gap)))
        print()
        print("    Alarm where that probability is small enough to act on, not at a round number.")
    if last["submitted"] > 0 and last["accepted"] < last["submitted"]:
        print()
        print("    REJECTS PRESENT. Rejected shares are stale work or a bad ntime, and both are")
        print("    connection faults rather than hashing faults.")

    print()
    print("=" * 74)
    print("  4. JOB CADENCE AND CLOCK")
    print("=" * 74)
    if len(jobs) >= 4:
        ntimes = [j["ntime"] for j in jobs]
        steps = [ntimes[i + 1] - ntimes[i] for i in range(len(ntimes) - 1)]
        forward = [s for s in steps if s > 0]
        print()
        print("    jobs seen            %d" % len(jobs))
        if forward:
            forward.sort()
            print("    ntime step, median   %d s" % forward[len(forward) // 2])
            print("    ntime step, 95th     %d s" % forward[int(0.95 * len(forward))])
            print()
            print("    Alarm at the 95th percentile of the observed gaps, which is %d seconds"
                  % forward[int(0.95 * len(forward))])
            print("    here, rather than at a guessed number of seconds.")
        backward = [s for s in steps if s < 0]
        if backward:
            print()
            print("    %d jobs carried an ntime EARLIER than the job before them, deepest %d s."
                  % (len(backward), -min(backward)))
            print("    The chain itself does this on 2.98%% of blocks, so a pool doing it is")
            print("    normal rather than alarming. It is only a fault if our OWN clock is what")
            print("    disagrees, which shows as rejects and not here.")
    else:
        print()
        print("    too few jobs to read a cadence")

    print()
    print("=" * 74)
    print("  5. AGAINST THIS MACHINE'S OWN DISTRIBUTION")
    print("=" * 74)
    against_baseline(path)

    print()
    print("=" * 74)
    print("  6. THE POOLED CONTROL  -  every hash this machine has ever computed")
    print("=" * 74)
    pooled_anchor_test()
    return 0


def pooled_anchor_test():
    """Sum every run's hashes into one control target and test the anchor rate against it.

    A single run cannot resolve a small deficit: at fifteen hundred anchors the spread is thirty
    nine, so anything under seven per cent hides inside it. Summing runs is the whole remedy, and
    it works here because the quantity is extensive - hashes add, anchors add, and the Poisson
    expectation adds with them. A deficit that is real grows as the square root of the total while
    one that is noise does not grow at all.

    This is the check that separates a kernel fault from an accounting mismatch, and the two need
    different fixes, so the distinction is drawn rather than guessed at.
    """
    logs = sorted(glob.glob(os.path.join(ROOT, "build", "miner_*.log")))
    logs = [f for f in logs if "token" not in os.path.basename(f)]
    total_hashes = 0
    total_anchors = 0
    used = 0
    print()
    print("    run                                hashes            anchors      due    ratio")
    for path in logs:
        samples, _ = read(path)
        if len(samples) < 12:
            continue
        last = samples[-1]
        due = last["hashes"] / float(ANCHOR_SPACE)
        if due < 30:
            continue
        used += 1
        total_hashes += last["hashes"]
        total_anchors += last["anchors"]
        print("    %-30s %18s %8d %8d   %.4f"
              % (os.path.basename(path)[:30], format(last["hashes"], ","),
                 last["anchors"], int(due), last["anchors"] / due))

    if used < 2:
        print()
        print("    fewer than two usable runs; nothing to pool yet.")
        return

    expected = total_hashes / float(ANCHOR_SPACE)
    spread = math.sqrt(expected)
    z = (total_anchors - expected) / spread
    print("    " + "-" * 70)
    print("    %-30s %18s %8d %8d   %.4f"
          % ("POOLED over %d runs" % used, format(total_hashes, ","),
             total_anchors, int(expected), total_anchors / expected))
    print()
    print("    pooled separation   %+.2f sd" % z)
    print("    deficit             %.2f%%" % (100.0 * (1.0 - total_anchors / expected)))
    print()
    if abs(z) < 3.0:
        shortfall = 1.0 - total_anchors / expected
        if shortfall > 0.005:
            need = int(9.0 / (shortfall ** 2) * ANCHOR_SPACE)
            print("    Not yet resolved. A deficit of %.2f%% clears three standard errors at"
                  % (100.0 * shortfall))
            print("    %s hashes; this machine has computed %s, which is %.0f%% of the way."
                  % (format(need, ","), format(total_hashes, ","),
                     100.0 * total_hashes / need))
        else:
            print("    OK pooled. The anchor rate matches 2^-32 across every run.")
    elif z < 0:
        print("    RESOLVED, AND IT IS A DEFICIT. Two causes fit and they need different fixes:")
        print()
        print("      accounting   the hash counter counts more nonces than the kernel scans. The")
        print("                   tail of each chunk returns early on index >= nonce_count, so if")
        print("                   the counter adds the full chunk the expectation is inflated and")
        print("                   the ratio sits below one while the hashing is perfectly correct.")
        print("      correctness  the kernel genuinely misses survivors, which means the device is")
        print("                   computing something other than SHA-256 on some lanes.")
        print()
        print("    They are told apart by counting scanned nonces directly instead of by chunk:")
        print("    if the ratio returns to one, it was accounting.")
    else:
        print("    RESOLVED, AND IT IS AN EXCESS. More survivors than 2^-32 permits means the")
        print("    anchor test itself is wrong, not the hashing.")


BASELINE = os.path.join(HERE, "watchdog_baseline.json")


def learn_baseline():
    """Build this machine's own distribution from every log it has ever written.

    A threshold derived from the process is right for any machine. A threshold learned from THIS
    machine is right for this one, and the two disagree for real reasons: a card in a warm room
    idles at a different spread than the same card in a cold one, and a pool sends work on its own
    rhythm rather than a standard one. So the process-derived checks above stay, and these sit
    beside them, alarming on departure from what this rig actually does.

    The quantiles are read off the pooled history rather than assumed, and the count of runs behind
    each one is reported, because a baseline from two sessions is a guess wearing a number.
    """
    import json

    logs = sorted(glob.glob(os.path.join(ROOT, "build", "miner_*.log")))
    logs = [f for f in logs if "token" not in os.path.basename(f)]
    rates, gaps, anchor_ratios = [], [], []
    runs = 0
    for path in logs:
        samples, jobs = read(path)
        if len(samples) < 12:
            continue
        runs += 1
        rates.extend(s["now"] for s in samples)
        last = samples[-1]
        if last["hashes"] > 0:
            due = last["hashes"] / float(ANCHOR_SPACE)
            if due > 30:
                anchor_ratios.append(last["anchors"] / due)
        ntimes = [j["ntime"] for j in jobs]
        gaps.extend(ntimes[i + 1] - ntimes[i] for i in range(len(ntimes) - 1)
                    if ntimes[i + 1] > ntimes[i])

    if runs == 0:
        return None
    rates.sort()
    gaps.sort()

    def quantile(values, q):
        if not values:
            return None
        return values[min(len(values) - 1, int(q * len(values)))]

    baseline = {
        "runs": runs,
        "rate_samples": len(rates),
        "rate_p01": quantile(rates, 0.01),
        "rate_p50": quantile(rates, 0.50),
        "rate_p99": quantile(rates, 0.99),
        "job_gap_p50": quantile(gaps, 0.50),
        "job_gap_p95": quantile(gaps, 0.95),
        "job_gap_p99": quantile(gaps, 0.99),
        "anchor_ratio_mean": (sum(anchor_ratios) / len(anchor_ratios)) if anchor_ratios else None,
        "anchor_runs": len(anchor_ratios),
    }
    with open(BASELINE, "w") as handle:
        json.dump(baseline, handle, indent=1)
    return baseline


def against_baseline(path):
    """Compare this run to what this machine usually does, and report the drift of the baseline."""
    import json

    if not os.path.exists(BASELINE):
        print("    no baseline yet. Run with --learn once there are a few logs.")
        return
    with open(BASELINE) as handle:
        base = json.load(handle)
    samples, jobs = read(path)
    if len(samples) < 12:
        return

    print()
    print("    baseline built from %d runs, %s rate samples"
          % (base["runs"], format(base["rate_samples"], ",")))
    if base["runs"] < 4:
        print("    WARNING: %d runs is thin. A baseline from a handful of sessions is a guess"
              % base["runs"])
        print("    wearing a number, and it will call normal variation a fault.")
    print()

    rates = sorted(s["now"] for s in samples)
    here = rates[len(rates) // 2]
    print("    this run's median rate   %d MH/s" % here)
    print("    usual range              %d to %d MH/s   (1st to 99th percentile)"
          % (base["rate_p01"], base["rate_p99"]))
    if here < base["rate_p01"]:
        print("    -> BELOW this machine's own first percentile. Something changed here, and no")
        print("       process-derived threshold would have caught it.")
    elif here > base["rate_p99"]:
        print("    -> above this machine's own 99th percentile, which is good news to explain.")
    else:
        print("    -> inside this machine's usual range.")

    if base.get("anchor_ratio_mean"):
        last = samples[-1]
        due = last["hashes"] / float(ANCHOR_SPACE)
        if due > 30:
            ratio = last["anchors"] / due
            print()
            print("    anchor ratio this run    %.4f" % ratio)
            print("    usual for this machine   %.4f   over %d runs"
                  % (base["anchor_ratio_mean"], base["anchor_runs"]))
            print("    tilt                     %+.4f" % (ratio - base["anchor_ratio_mean"]))

    if base.get("job_gap_p95") and len(jobs) >= 4:
        ntimes = [j["ntime"] for j in jobs]
        steps = sorted(s for s in (ntimes[i + 1] - ntimes[i] for i in range(len(ntimes) - 1))
                       if s > 0)
        if steps:
            print()
            print("    job gap, 95th this run   %d s" % steps[int(0.95 * len(steps))])
            print("    usual 95th               %d s" % base["job_gap_p95"])
            print("    alarm at                 %d s   (this pool's own 99th, not a round number)"
                  % base["job_gap_p99"])


def main():
    parser = argparse.ArgumentParser(description="Watch a miner against calibrated models.")
    parser.add_argument("--log", default=None)
    parser.add_argument("--follow", action="store_true",
                        help="re-read every 30 seconds instead of reporting once")
    parser.add_argument("--learn", action="store_true",
                        help="rebuild this machine's baseline from every log under build/")
    given = parser.parse_args()

    if given.learn:
        built = learn_baseline()
        if built is None:
            print("  no usable logs to learn from")
            return 1
        print("  baseline written to %s" % BASELINE)
        for key in sorted(built):
            print("    %-20s %s" % (key, built[key]))
        return 0

    path = given.log or newest_log()
    if not path or not os.path.exists(path):
        print("  no miner log found under build/")
        return 1

    if not given.follow:
        return report(path)
    while True:
        os.system("")
        print("\n" + "=" * 74)
        print("  %s" % time.strftime("%H:%M:%S"))
        report(path)
        sys.stdout.flush()
        time.sleep(30)


if __name__ == "__main__":
    raise SystemExit(main())
