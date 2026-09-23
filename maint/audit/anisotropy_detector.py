"""An anisotropy detector on a flat baseline, so a departure is one number and not a curve.

For a set of points with no preferred direction, every mode carries the same expected power, and a
degree holds (2l+1) of them. So the per-degree power rises linearly:

    E[P_l] = c (2l + 1)

Drawn rather than assumed: over three hundred draws at 256 positions the ratio P_l/(2l+1) is flat at
3.867 for a weight of 64 and 5.095 for 128, with spreads of 2.64 and 1.54 per cent across ten
degrees. The constant carries the finite-population correction too - weights of 64 and 128 predict a
ratio of 64/48 = 1.333 between their constants and deliver 1.318.

WHY NORMALISE

Plotted as P_l, the null RISES, and every spectrum drawn in this tree rises with it. That rise is
entirely the mode count, and eyeballing it as structure is the same error as reading a sorted list's
top as a cluster. Divided by (2l+1) the null is a horizontal line, so:

    the baseline is one number, not a curve
    a departure is a departure, with nothing to subtract by eye first
    the degree that departs NAMES the angular scale - 1 is a dipole, 2 a quadrupole, high is fine
      structure, and a high-end deficit is smoothness

THE THREE CONDITIONS A DETECTION MUST MEET

Stated as requirements because each one is a fault this work actually made:

    same statistic   the floor is this statistic at this sample size and this weight, drawn, never
                     derived. Six derived floors in one session, every one too low.
    max of N         the bar is the null's own LOUDEST over the same number of degrees, because
                     reporting the loudest of ten against a one-cell threshold manufactures
                     findings.
    matched null     the null holds the weight fixed, because an unmatched one reports the weight.

    python maint/audit/anisotropy_detector.py --check
    python maint/audit/anisotropy_detector.py --rounds
"""

import argparse
import math
import os
import random
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "examples", "00_blob_viz_tools"))
sys.path.insert(0, os.path.join(ROOT, "examples", "proofing"))

import boundary_read
import state_deflection

POINTS = 256


class Detector(object):
    """A flat-baseline anisotropy detector. Build once, then every read is cheap."""

    def __init__(self, top=10, seed=0xA150):
        self.top = top
        self.places = boundary_read.golden_place(POINTS)
        self.angles = boundary_read.as_angles(self.places)
        self.rng = random.Random(seed)
        self.floors = {}

    def ratios(self, live):
        """P_l divided by (2l+1): the quantity whose null is flat."""
        table = boundary_read.complex_coefficients(self.angles, live, self.top)
        power = [0.0] * (self.top + 1)
        for (degree, order), (re, im) in table.items():
            power[degree] += (1.0 if order == 0 else 2.0) * ((re * re) + (im * im))
        return [power[d] / (2 * d + 1) for d in range(self.top + 1)]

    def floor_at(self, weight, draws=300):
        """The baseline and the bar, both drawn at this weight. Cached per weight.

        The bar is the null's own largest departure across the degrees, at the ninety-fifth
        percentile of repeated draws - so it already carries the max-of-N correction instead of
        needing one applied afterwards.
        """
        held = self.floors.get(weight)
        if held is not None:
            return held

        rows = []
        for _ in range(draws):
            rows.append(self.ratios(self.rng.sample(range(POINTS), weight)))
        middle = [sum(r[d] for r in rows) / draws for d in range(self.top + 1)]
        spread = []
        for degree in range(self.top + 1):
            column = [r[degree] for r in rows]
            spread.append(math.sqrt(sum((v - middle[degree]) ** 2 for v in column) / draws) or 1.0)

        loudest = []
        for row in rows:
            loudest.append(max(abs((row[d] - middle[d]) / spread[d])
                               for d in range(1, self.top + 1)))
        loudest.sort()
        bar = loudest[int(0.95 * len(loudest))]
        self.floors[weight] = (middle, spread, bar)
        return self.floors[weight]

    def detect(self, live, label):
        """One reading. Returns the degree that departed furthest and whether it cleared."""
        weight = len(live)
        middle, spread, bar = self.floor_at(weight)
        ratios = self.ratios(live)
        best_degree, best_z = 0, 0.0
        for degree in range(1, self.top + 1):
            z = (ratios[degree] - middle[degree]) / spread[degree]
            if abs(z) > abs(best_z):
                best_degree, best_z = degree, z
        hit = abs(best_z) >= bar
        name = {1: "dipole", 2: "quadrupole"}.get(best_degree,
                                                  "fine" if best_degree > 6 else "mid-scale")
        print("    %-14s weight %3d   baseline %.3f   loudest degree %2d at %+6.2f  bar %.2f  %s"
              % (label, weight, middle[best_degree], best_degree, best_z, bar,
                 "DETECT (" + name + ")" if hit else "flat"))
        return hit, best_degree, best_z


def _check():
    """The detector must fire on planted anisotropy and stay quiet on none."""
    print("=" * 82)
    print("  CONTROL: planted anisotropy must fire, a flat set must not")
    print("=" * 82)
    print()
    detector = Detector(top=10)
    rng = random.Random(0xB1A5)
    weight = 96

    flat = rng.sample(range(POINTS), weight)
    quiet, _, _ = detector.detect(sorted(flat), "flat")

    # A dipole: over-light one hemisphere by height, which is degree one by construction.
    ordered = sorted(range(POINTS), key=lambda i: detector.places[i][1])
    half = ordered[: POINTS // 2]
    rest = ordered[POINTS // 2:]
    dipole = rng.sample(half, int(weight * 0.72)) + rng.sample(rest, weight - int(weight * 0.72))
    hit_one, degree_one, _ = detector.detect(sorted(dipole), "dipole")

    # A quadrupole: over-light BOTH poles, which cancels at degree one and shows at two.
    poles = ordered[: POINTS // 4] + ordered[-POINTS // 4:]
    belt = ordered[POINTS // 4: -POINTS // 4]
    take = int(weight * 0.72)
    quad = rng.sample(poles, take) + rng.sample(belt, weight - take)
    hit_two, degree_two, _ = detector.detect(sorted(quad), "quadrupole")

    print()
    ok = (not quiet) and hit_one and (degree_one == 1) and hit_two and (degree_two == 2)
    print("    flat stays quiet                 %s" % ("yes" if not quiet else "NO"))
    print("    dipole fires AND names degree 1  %s"
          % ("yes" if (hit_one and degree_one == 1) else "no, named %d" % degree_one))
    print("    quadrupole fires AND names 2     %s"
          % ("yes" if (hit_two and degree_two == 2) else "no, named %d" % degree_two))
    print()
    if ok:
        print("    VALIDATED. It fires on anisotropy, stays quiet without it, and NAMES the")
        print("    angular scale correctly, which is what makes it a detector and not an alarm.")
        return 0
    print("    NOT VALIDATED. A null from it means nothing yet.")
    return 1


def _rounds():
    print()
    print("=" * 82)
    print("  SHA-256 STATES, through the validated detector")
    print("=" * 82)
    print()
    detector = Detector(top=10)
    block = [0x80000000] + [0] * 15
    states = state_deflection.states_of(block)
    for step in (1, 4, 8, 16, 24, 32, 48, 64):
        live = sorted(state_deflection.lit_of(states[step]))
        detector.detect(live, "round %d" % step)
    return 0


def main():
    parser = argparse.ArgumentParser(description="Flat-baseline anisotropy detector.")
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--rounds", action="store_true")
    given = parser.parse_args()
    code = _check()
    if given.rounds and code == 0:
        code = _rounds()
    return code


if __name__ == "__main__":
    raise SystemExit(main())
