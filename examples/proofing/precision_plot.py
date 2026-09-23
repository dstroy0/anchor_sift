"""One law, four arms and a decimal ladder on one axis, and the line they all sit on.

    python examples/proofing/precision_plot.py
    python examples/proofing/precision_plot.py --check

WHAT THIS DRAWS

Power per harmonic degree is invariant under rotation. A ring placement turned by whole ring
steps has a residual of exactly zero. Every number any arm reports for that residual is therefore
its own arithmetic, and the prediction that follows is a line: a format carrying `d` decimal digits
should report a residual near `10^-d`, so the log of the residual against the digit count has slope
minus one and no free parameter anywhere in it.

Eight readings go on that axis. Host and device float32, host and device float64, from
`src/engine/c/sha256/bench/bench_precision_cuda.cu`, and decimal at 20, 30, 40 and 50 places from
`precision_floor.py`. Between the ends they span about 43 decimal digits of precision and 55 orders
of magnitude of residual.

WHAT A POINT OFF THE LINE WOULD MEAN

A point above the line is an effect that does not shrink when digits are bought, and the only thing
that would produce one is an operation in the reading that fails to commute with the rotation. So
the plot tests instead of illustrating. The line is the null hypothesis in the strict sense of
a prediction with no fitted quantity, and a departure from it is where a real effect would appear.

WHY THE DEVICE ARM IS HERE

Two arms of the same width differ only in where they ran, so their disagreement separates the
device from the format. Two arms of the same side differ only in width, so their disagreement
separates the format from the device. One arm alone confounds them, and the confound is the failure
this tree keeps finding under new disguises.
"""

import argparse
import io
import math
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as pyplot

import precision_floor

DEVICE_BENCH = os.path.join(ROOT, "build", "bench", "bench_precision_cuda.exe")
LADDER = (20, 30, 40, 50)
# Under build/ with the book outputs, because it is generated and nothing generated is written
# beside the source. The chapter reaches it by a relative path and guards the include. A tree
# where this tool has not been run still builds its book.
PICTURE = os.path.join(ROOT, "build", "theory", "figures", "precision_floor.png")

# Colors chosen so the figure reads in print and in grey. The two arms differ in marker as well as
# in color, because a reader with a monochrome copy still has to tell them apart.
INK = {"host": "#1b3a5c", "device": "#a4471f", "decimal": "#2c6e49"}
MARK = {"host": "o", "device": "^", "decimal": "s"}


def device_readings():
    """Residuals from the CUDA bench, as (digits, arm, residual), or an empty list with a reason.

    A missing binary is reported and never treated as a pass. The build command lives in the bench's
    own header, and a reader who needs the arm can produce it.
    """
    if not os.path.exists(DEVICE_BENCH):
        return [], "not built at %s" % os.path.relpath(DEVICE_BENCH, ROOT)
    try:
        done = subprocess.run([DEVICE_BENCH], capture_output=True, text=True, timeout=300)
    except OSError as why:
        return [], "did not run: %s" % why
    if done.returncode != 0:
        return [], "exited %d" % done.returncode

    out = []
    for line in done.stdout.split("\n"):
        if line.startswith("#") or not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) != 4 or parts[0] == "width":
            continue
        width, arm, digits, residual = parts
        if arm == "between":
            continue
        out.append((float(digits), arm, float(residual), width))
    return out, ""


def ladder_readings(places=LADDER):
    """Residuals from the arbitrary-precision ladder, as (digits, arm, residual, name).

    The digits are the WORKING precision and never the requested one. A residual is a function of
    the arithmetic that produced it, the guard digits are part of that arithmetic, and plotting
    against the requested figure put a false 3.82 decade per digit segment in this line at the
    join between the float arms and the ladder.
    """
    return [(float(precision_floor.working_digits(one)), "decimal",
             float(precision_floor.residual_at(one)),
             "decimal %d" % precision_floor.working_digits(one))
            for one in places]


def fitted_slope(points):
    """Least squares slope and intercept of log10 residual against digits, and the worst departure.

    The slope is the quantity under test and the departure is what would show an effect. Both are
    reported, because a good slope with one point far off the line is not a clean result.
    """
    xs = [one[0] for one in points]
    ys = [math.log10(one[2]) for one in points]
    count = float(len(xs))
    mean_x = sum(xs) / count
    mean_y = sum(ys) / count
    top = sum((x - mean_x) * (y - mean_y) for x, y in zip(xs, ys))
    bottom = sum((x - mean_x) ** 2 for x in xs)
    slope = top / bottom if bottom else float("nan")
    intercept = mean_y - slope * mean_x
    worst = max(abs(y - (slope * x + intercept)) for x, y in zip(xs, ys))
    return slope, intercept, worst


def draw(points, slope, intercept, path):
    """Writes the figure. Nothing is drawn that the numbers above do not contain."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    figure, frame = pyplot.subplots(figsize=(7.2, 4.6), dpi=200)

    span = [min(one[0] for one in points) - 2, max(one[0] for one in points) + 2]
    frame.plot(span, [slope * x + intercept for x in span],
               color="#888888", linewidth=1.0, zorder=1,
               label="fitted, %.3f decades per digit" % -slope)

    # A label placed outward runs off the frame at the last point, so the right third labels
    # inward. Checked against the written figure and not assumed.
    turn = span[0] + 0.66 * (span[1] - span[0])
    seen = set()
    for digits, arm, residual, name in points:
        frame.scatter([digits], [math.log10(residual)],
                      color=INK[arm], marker=MARK[arm], s=46, zorder=3,
                      edgecolors="white", linewidths=0.6,
                      label=arm if arm not in seen else None)
        seen.add(arm)
        inward = digits > turn
        frame.annotate(name, (digits, math.log10(residual)),
                       textcoords="offset points",
                       xytext=(-10 if inward else 8, -14 if inward else 5),
                       ha="right" if inward else "left",
                       fontsize=7, color="#333333")
    frame.set_xlim(span[0], span[1])

    frame.set_xlabel("decimal digits the arithmetic carries")
    frame.set_ylabel("log10 of the residual, whose exact value is zero")
    frame.set_title("A null the law puts at zero, read at eight precisions")
    frame.grid(True, linewidth=0.4, color="#dddddd", zorder=0)
    frame.legend(loc="upper right", fontsize=8, framealpha=1.0)
    figure.tight_layout()
    figure.savefig(path, facecolor="white")
    pyplot.close(figure)
    return path


def _report():
    lines = []
    device, why = device_readings()
    if not device:
        lines.append("  the device arm is absent: %s" % why)
    points = device + ladder_readings()
    points.sort(key=lambda one: one[0])

    lines.append("  every arm on one axis")
    lines.append("    digits    arm        residual        name")
    for digits, arm, residual, name in points:
        lines.append("    %7.4f   %-9s  %.6e   %s" % (digits, arm, residual, name))
    lines.append("")

    slope, intercept, worst = fitted_slope(points)
    lines.append("  the line, against a prediction with no fitted quantity in it")
    lines.append("    measured   %.4f decades per digit" % -slope)
    lines.append("    predicted  1.0000, since a format with d digits rounds at 10^-d")
    lines.append("    worst departure from the line   %.3f decades" % worst)
    lines.append("")

    if device:
        by_width = {}
        for digits, arm, residual, name in device:
            by_width.setdefault(name, {})[arm] = residual
        lines.append("  the two arms at each width, which separates the device from the format")
        for name in sorted(by_width):
            pair = by_width[name]
            if "host" in pair and "device" in pair:
                lines.append("    %-8s host %.4e   device %.4e   ratio %.3f"
                             % (name, pair["host"], pair["device"], pair["device"] / pair["host"]))
        lines.append("    a ratio near one says the device's arithmetic is the host's at that width")
        lines.append("")

    path = draw(points, slope, intercept, PICTURE)
    lines.append("  written  %s" % os.path.relpath(path, ROOT))
    sys.stdout.write("\n".join(lines) + "\n")
    return 0


def _check():
    lines = []
    failed = 0

    # The fit has to recover a slope it is handed, or the number it reports about the real data
    # means nothing. Built on exact points, so the answer is known.
    made = [(float(d), "decimal", 10.0 ** (-1.0 * d), "made %d" % d) for d in (10, 20, 30, 40)]
    slope, _, worst = fitted_slope(made)
    lines.append("  a made ladder of exact slope one reads %.6f, departure %.2e" % (-slope, worst))
    if abs(-slope - 1.0) > 1e-9 or worst > 1e-9:
        lines.append("    FAIL the fit does not recover a slope it was given")
        failed += 1

    # And it has to report a slope that is not one when the data does not have one, or a flat
    # residual would be drawn as a clean result.
    flat = [(float(d), "decimal", 1e-12, "flat %d" % d) for d in (10, 20, 30, 40)]
    slope, _, _ = fitted_slope(flat)
    lines.append("  a residual that ignores precision reads %.6f decades per digit" % -slope)
    if abs(slope) > 1e-9:
        lines.append("    FAIL a flat ladder was not reported as flat")
        failed += 1

    # The ladder itself, at two places, so this tool is not trusted on a broken import.
    coarse = float(precision_floor.residual_at(20))
    lines.append("  the ladder at 20 places returns %.3e" % coarse)
    if not 0.0 < coarse < 1e-25:
        lines.append("    FAIL the ladder is not returning a residual near its own precision")
        failed += 1

    # The finding itself, gated. This is the check that fails if an arm stops rounding the way its
    # format says it should, or if a real effect appears that does not shrink when digits are bought.
    #
    # The band is deliberately narrow, because the prediction has no fitted quantity in it and the
    # measurement came in at 0.986 with a worst departure of 0.246 decades over 55 orders. A slope
    # outside this band is either an arithmetic change or a result, and both want reading.
    device, why = device_readings()
    points = device + ladder_readings()
    if not device:
        lines.append("  the device arm is absent, so the slope is gated on the ladder alone: %s" % why)
    slope, _, worst = fitted_slope(points)
    lines.append("  the measured line: %.4f decades per digit, worst departure %.3f decades"
                 % (-slope, worst))
    if not 0.90 < -slope < 1.10:
        lines.append("    FAIL the residual no longer falls one decade per digit of precision")
        failed += 1
    if worst > 1.0:
        lines.append("    FAIL a point sits over a decade off the line, which is where an effect")
        lines.append("      that precision cannot buy away would show")
        failed += 1

    lines.append("")
    sys.stdout.write("\n".join(lines) + "\n")
    sys.stdout.write("%d check(s) failed\n" % failed)
    return failed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="the precision line, drawn and fitted")
    parser.add_argument("--check", action="store_true", help="run the checks and exit")
    args = parser.parse_args()
    sys.exit((1 if _check() else 0) if args.check else _report())
