#!/usr/bin/env python3
# BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The clock as an instrument: an arm, a co-arm, and the drag read off instead of assumed.
#
#   Usage:  python tools/dn_precision/calc/clock_arm.py --check
#           python tools/dn_precision/calc/clock_arm.py            the constants routes, timed properly
#
# WHY THIS EXISTS, AND WHAT IT REPLACES
#
# Douglas, 2026-09-12: "our clock can be an instrument, and it can have an instrumented coarm that
# CAN be drug back."
#
# Every timing reported in this family before this file was a single `time.time()` delta. Two of
# them were quoted as findings: a pair of scaling exponents for the gamma routes, and a claim that
# Lima's Catalan series runs about twenty five times faster than Ramanujan's, from 0.055 s against
# 0.002 s. Both are unsound as measured. `time.time()` is a wall clock with coarse granularity, a
# two millisecond reading sits at or under its resolution, and the machine was running a miner at
# 99 per cent device utilisation throughout.
#
# THE FIRST FIX WAS THE WRONG ONE AND IT IS WORTH RECORDING. The obvious repair is to repeat and
# take the MINIMUM, on the argument that scheduler noise only ever makes a measurement slower, so
# the minimum is the cleanest estimate. That argument is probably true and it is still the crude
# answer, because it DISCARDS the jitter and it depends on knowing the jitter's sign. If the
# machine is thermally throttling, or a background task is holding a lock, the drag is not
# one-sided and the minimum is then an estimate of nothing in particular.
#
# THE CO-ARM READS THE DRAG RATHER THAN ASSUMING IT. src/bench/bench_coarms.cpp sets out what a
# co-arm is in this tree: a pair whose win condition is RELATIONAL, satisfied by two arms agreeing
# with each other rather than by either one meeting an absolute threshold. Applied to a clock:
#
#     the ARM      is the work being measured
#     the CO-ARM   is a reference workload of fixed, deterministic cost, interleaved with it
#     the READING  is the RATIO of the two, which is relational and therefore immune to any
#                  slowdown that hits both
#     the DRAG     is the co-arm's own absolute time, which is a direct measurement of the jitter
#                  rather than an assumption about its direction
#
# A common-mode slowdown cancels in the ratio exactly. That is the whole content of "it can be drug
# back": the reading is pulled back into the reference frame instead of being filtered.
#
# WHAT THE CO-ARM CANNOT DO. A slowdown that hits the arm and not the co-arm does not cancel, and
# nothing here can separate that from a real cost difference. The interleave narrows the window in
# which that can happen but does not close it, so the co-arm's own spread is reported as the
# instrument's noise floor and a ratio inside that floor is not a result.

import argparse
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
FAMILY = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(FAMILY))
for _where in (HERE, os.path.join(FAMILY, "support"), os.path.join(ROOT, "examples", "proofing")):
    if _where not in sys.path:
        sys.path.insert(0, _where)

# perf_counter and not time(): monotonic, and the highest resolution the platform offers. time()
# is a wall clock, it can step, and on Windows its granularity is far too coarse for milliseconds.
CLOCK = time.perf_counter

REFERENCE_SIZE = 1 << 14          # bits in the co-arm's operands, fixed so its true cost is fixed
REPEATS = 9


def reference_work(size=REFERENCE_SIZE):
    """The co-arm: a deterministic big-integer workload whose true cost does not vary.

    A multiply and a division on operands of a fixed bit width. It uses the same machinery the
    constants routes use, big integer arithmetic, a slowdown that affects them affects this too.
    That is the property the cancellation depends on: a co-arm made of unrelated work would not be
    dragged by the same things.

    Deterministic, so the work cannot vary between calls. Nothing random, no allocation that depends
    on a previous result, and the return value is used so the call cannot be optimised away.
    """
    left = (1 << size) - 1
    right = (1 << (size // 2)) + 12345
    total = 0
    for _ in range(24):
        total += (left * right) // (right + 1)
    return total & 0xFFFF


def paired(target, repeats=REPEATS):
    """Time `target` against the co-arm, interleaved, and return the relational reading.

    Each repeat runs co-arm, then target, then co-arm. The two brackets straddle the target, a
    slowdown that arrives during the measurement shows up in them. The ratio target/co-arm is the
    reading; the co-arm's own absolute spread is the noise floor.
    """
    arm = []
    coarm = []
    for _ in range(repeats):
        start = CLOCK(); reference_work(); first = CLOCK() - start
        start = CLOCK(); target(); middle = CLOCK() - start
        start = CLOCK(); reference_work(); second = CLOCK() - start
        arm.append(middle)
        coarm.append((first + second) / 2.0)

    ratios = sorted(a / c for a, c in zip(arm, coarm))
    coarm_sorted = sorted(coarm)
    arm_sorted = sorted(arm)
    middle_at = len(ratios) // 2
    return {
        "ratio": ratios[middle_at],
        "ratio_low": ratios[0],
        "ratio_high": ratios[-1],
        "arm_median": arm_sorted[middle_at],
        "arm_min": arm_sorted[0],
        "coarm_median": coarm_sorted[middle_at],
        "coarm_min": coarm_sorted[0],
        "coarm_spread": (coarm_sorted[-1] - coarm_sorted[0]) / coarm_sorted[0],
    }


def _report():
    import dn_constants

    print("")
    print("  The constants routes timed against the co-arm. The ratio is the reading; the")
    print("  co-arm spread is the instrument's noise floor and a ratio inside it says nothing.")
    print("")

    cases = (
        ("gamma, Brent-McMillan", lambda: dn_constants.gamma_brent_mcmillan(1000)),
        ("gamma, Sweeney", lambda: dn_constants.gamma_sweeney(1000)),
        ("catalan, Ramanujan", lambda: dn_constants.catalan_ramanujan(1000)),
        ("catalan, Lima", lambda: dn_constants.catalan_lima(1000)),
        ("pi, Machin", lambda: dn_constants.pi_machin(1000)),
    )

    print("  %-24s %11s %11s %13s %11s"
          % ("route", "arm min s", "co-arm s", "ratio", "ratio span"))
    out = {}
    for name, fn in cases:
        got = paired(fn)
        out[name] = got
        print("  %-24s %11.6f %11.6f %13.3f %11s"
              % (name, got["arm_min"], got["coarm_min"], got["ratio"],
                 "%.3f-%.3f" % (got["ratio_low"], got["ratio_high"])))

    floor = max(got["coarm_spread"] for got in out.values())
    print("")
    print("  co-arm spread across all runs: %.1f%%, which is the noise floor" % (100.0 * floor))
    print("")

    # THE CLAIM THAT NEEDS RE-STATING, measured relationally this time.
    ram = out["catalan, Ramanujan"]["ratio"]
    lima = out["catalan, Lima"]["ratio"]
    print("  The claim made earlier from single wall-clock shots was that Lima runs about twenty")
    print("  five times faster than Ramanujan, from 0.055 s against 0.002 s.")
    print("  Measured relationally: Ramanujan is %.3f co-arms, Lima is %.3f, a factor of %.1f."
          % (ram, lima, ram / lima if lima else 0.0))
    if lima > 0 and out["catalan, Lima"]["coarm_spread"] > 0:
        if (ram / lima) > (1.0 + floor) * 2:
            print("  That is well outside the noise floor, so the direction of the claim holds even")
            print("  though the number it was quoted with did not deserve three digits.")
        else:
            print("  That is inside or near the noise floor, so the earlier factor was noise and the")
            print("  claim should not have been made.")
    return 0


def _check():
    failed = 0
    print("")

    # THE IDENTITY. The co-arm timed against itself must read 1, because it is the same work. This
    # is the clock's version of the identity permutation: run something that changes nothing and
    # read the residual. Anything far from 1 means the instrument is measuring its own overhead
    # rather than the work.
    got = paired(reference_work)
    print("  the co-arm against itself reads %.4f, span %.4f to %.4f"
          % (got["ratio"], got["ratio_low"], got["ratio_high"]))
    if abs(got["ratio"] - 1.0) > 0.35:
        print("    FAIL the co-arm does not read unity against itself")
        failed += 1

    # THE NOISE FLOOR, stated rather than assumed. Everything below it is not a measurement.
    print("  co-arm spread over %d repeats: %.1f%%, so that is the floor"
          % (REPEATS, 100.0 * got["coarm_spread"]))

    # THE POSITIVE CONTROL. A known multiple of the co-arm's work must read as that multiple. An
    # instrument that cannot see a factor it is handed directly cannot be trusted on a factor it
    # finds.
    for multiple in (2, 4):
        def heavier(times=multiple):
            for _ in range(times):
                reference_work()
        got = paired(heavier)
        ok = abs(got["ratio"] - multiple) / multiple < 0.35
        print("  %dx the co-arm's work reads %.3f (want %d): %s"
              % (multiple, got["ratio"], multiple, "ok" if ok else "FAIL"))
        if not ok:
            failed += 1

    # THE DRAG CONTROL, which is the whole reason the co-arm exists. A common-mode slowdown must
    # NOT change the ratio. It is simulated by loading the machine during the pair, so both the arm
    # and the co-arm are dragged, and the relational reading has to survive it.
    def busy(seconds=0.004):
        end = CLOCK() + seconds
        while CLOCK() < end:
            pass

    def arm_only():
        busy()
        reference_work()
        busy()

    clean = paired(reference_work)

    # CASE ONE, AN ARM-ONLY SLOWDOWN. This must NOT cancel, because it is a real cost difference
    # and an instrument that hid it would be useless.
    inside = paired(arm_only)
    print("  arm-only slowdown: co-arm %.6f -> %.6f, arm %.6f -> %.6f, ratio %.3f -> %.3f"
          % (clean["coarm_min"], inside["coarm_min"], clean["arm_min"], inside["arm_min"],
             clean["ratio"], inside["ratio"]))
    if inside["ratio"] <= clean["ratio"] * 1.5:
        print("    FAIL an arm-only slowdown did not move the ratio, so real costs are hidden")
        failed += 1

    # CASE TWO, A COMMON-MODE DRAG, WHICH IS THE ONE THE CO-ARM EXISTS FOR AND THE ONE THE FIRST
    # VERSION OF THIS CONTROL FAILED TO TEST. That version put the busy loops INSIDE the arm, so
    # the co-arm correctly did not move and the run was relabelled as common mode when it was
    # nothing of the kind. Real common mode has to come from OUTSIDE the pair, so it hits the arm
    # and both co-arm brackets alike.
    #
    # The claim under test is Douglas's: "then any error warp gets null." The absolute times must
    # both rise and the RATIO must not move.
    import threading
    stop = threading.Event()

    def hog():
        while not stop.is_set():
            reference_work()

    loaders = [threading.Thread(target=hog, daemon=True) for _ in range(4)]
    for one in loaders:
        one.start()
    try:
        outside = paired(reference_work)
    finally:
        stop.set()
        for one in loaders:
            one.join(timeout=2.0)

    arm_rise = outside["arm_min"] / clean["arm_min"] if clean["arm_min"] else 0.0
    coarm_rise = outside["coarm_min"] / clean["coarm_min"] if clean["coarm_min"] else 0.0
    ratio_move = abs(outside["ratio"] - clean["ratio"]) / clean["ratio"] if clean["ratio"] else 0.0
    print("  common-mode drag from outside the pair:")
    print("    arm    %.6f -> %.6f  (%.2fx)" % (clean["arm_min"], outside["arm_min"], arm_rise))
    print("    co-arm %.6f -> %.6f  (%.2fx)" % (clean["coarm_min"], outside["coarm_min"], coarm_rise))
    print("    ratio  %.4f -> %.4f  (moved %.1f%%)" % (clean["ratio"], outside["ratio"],
                                                       100.0 * ratio_move))
    if arm_rise < 1.15 or coarm_rise < 1.15:
        print("    INCONCLUSIVE the background load did not actually drag the pair, so common-mode")
        print("    rejection is untested rather than confirmed. Not counted as a pass.")
    elif ratio_move > 0.35:
        print("    FAIL the ratio moved under a drag that hit both arms, so it does not cancel")
        failed += 1
    else:
        print("    THE WARP WENT NULL: both absolutes rose and the relational reading did not.")

    # AND THE CLOCK MUST BE MONOTONIC, or a step backwards produces a negative interval that would
    # read as an impossibly fast arm.
    last = CLOCK()
    steps = 0
    for _ in range(200000):
        now = CLOCK()
        if now < last:
            steps += 1
        last = now
    print("  the clock stepped backwards %d times in 200000 reads" % steps)
    if steps:
        print("    FAIL the clock is not monotonic, so no interval from it is trustworthy")
        failed += 1

    # THE RESOLUTION, measured rather than looked up. This is the number that condemned the earlier
    # timings: an interval near the resolution carries no digits.
    deltas = []
    for _ in range(2000):
        first = CLOCK()
        second = CLOCK()
        if second > first:
            deltas.append(second - first)
    if deltas:
        print("  smallest resolvable interval: %.3e s, a 2e-03 s reading carries about %.1f digits"
              % (min(deltas), max(0.0, -__import__("math").log10(min(deltas) / 2e-3))))

    print("")
    print("  %d check(s) failed" % failed)
    return failed


def main():
    parser = argparse.ArgumentParser(description="the clock as an arm and a co-arm")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    if args.check:
        return 1 if _check() else 0
    return _report()


if __name__ == "__main__":
    sys.exit(main())
