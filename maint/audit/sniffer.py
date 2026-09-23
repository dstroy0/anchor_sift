"""Two-stage sniffer: where to point an expensive measurement, and which class the target is in.

The bake-off settled what a single scan can do. On planted structure the harmonic expansion beat
every rival on anything with a shape - 328 standard errors against 14.8 for the next best on an
over-lit cap - and reported NOTHING on a forced parity, coming in at 2.43 against its own 3.75 floor.
It does not merely lose there; it is blind by construction, because the expansion is a linear map of
the lit set and a parity is not a linear property of which bits are lit.

So this runs two stages and reports which one fired, because they see disjoint classes:

    spatial     per-degree harmonic power. Cheap, complete over the whole spatial class, and it
                names the angular SCALE of what it found, which is what makes it a target and not
                just an alarm.
    algebraic   parity correlations over sparse masks. Sees exactly what the first cannot, and
                names the mask, which is a target of a different kind.

EVERY BAR IS DRAWN AND EVERY NULL IS WEIGHT-MATCHED

Each stage reports its loudest over many cells, which is large by construction, so the bar is the
null's own loudest over the same number of cells. And the null holds the popcount fixed, because a
lit set's spectrum depends heavily on how many bits are lit and an unmatched null reports the weight
and calls it structure.

IT VALIDATES ITSELF BEFORE IT IS BELIEVED

--validate plants one structure of each class and requires the matching stage to fire and the other
to stay quiet. A sniffer that has never been shown detecting anything cannot be trusted when it
reports nothing, which is the lesson every instrument in this tree learned the hard way.

    python maint/audit/sniffer.py --validate
    python maint/audit/sniffer.py --rounds
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
TOP = 8


class Sniffer(object):
    """Holds the placement and the basis, so a scan is an addition per lit bit."""

    def __init__(self, top=TOP, seed=0x51FF):
        self.top = top
        self.places = boundary_read.golden_place(POINTS)
        self.angles = boundary_read.as_angles(self.places)
        self.rng = random.Random(seed)
        self.masks = [tuple(sorted(self.rng.sample(range(POINTS), self.rng.randint(2, 5))))
                      for _ in range(600)]

    def power(self, live):
        table = boundary_read.complex_coefficients(self.angles, live, self.top)
        out = [0.0] * (self.top + 1)
        for (degree, order), (re, im) in table.items():
            out[degree] += (1.0 if order == 0 else 2.0) * ((re * re) + (im * im))
        return out

    def spatial(self, sets, draws=200):
        """Per-degree power against a weight-matched null. Names the degree it found."""
        weight = len(sets[0])
        real = [self.power(one) for one in sets]
        mean_real = [sum(row[d] for row in real) / len(real) for d in range(self.top + 1)]

        null = [self.power(self.rng.sample(range(POINTS), weight)) for _ in range(draws)]
        best_degree, best_z = 0, 0.0
        for degree in range(1, self.top + 1):
            column = [row[degree] for row in null]
            middle = sum(column) / len(column)
            spread = math.sqrt(sum((v - middle) ** 2 for v in column) / len(column)) or 1.0
            z = (mean_real[degree] - middle) / (spread / math.sqrt(len(sets)))
            if abs(z) > abs(best_z):
                best_degree, best_z = degree, z
        bar = math.sqrt(2.0 * math.log(max(self.top, 2)))
        return best_degree, best_z, bar

    def algebraic(self, sets):
        """Parity correlation over the mask set. Names the mask it found."""
        trials = len(sets)
        best_mask, best_z = None, 0.0
        for mask in self.masks:
            agree = 0
            for one in sets:
                lit = set(one)
                if sum(1 for index in mask if index in lit) % 2 == 0:
                    agree += 1
            z = ((2 * agree) - trials) / math.sqrt(trials)
            if abs(z) > abs(best_z):
                best_mask, best_z = mask, z
        bar = math.sqrt(2.0 * math.log(len(self.masks)))
        return best_mask, best_z, bar

    def draw_bars(self, weight, trials, rounds=40):
        """The bar each stage must clear, DRAWN from flat data rather than derived.

        The first version used root(2 ln N), which is the EXPECTED maximum of N standard normals -
        so about half of all nulls exceed it and the floor fired on its own validation. That is the
        sixth derived threshold in this work to come in too low, always in the same direction,
        because deriving a bar means enumerating the variance sources and the ones left out only
        ever add variance.

        So the bar is the ninety-fifth percentile of what this exact statistic produces on data with
        nothing in it, at this weight and this trial count. Nothing is assumed about its shape.
        """
        spatial_draws = []
        algebraic_draws = []
        for _ in range(rounds):
            flat = [sorted(self.rng.sample(range(POINTS), weight)) for _ in range(trials)]
            spatial_draws.append(abs(self.spatial(flat, draws=60)[1]))
            algebraic_draws.append(abs(self.algebraic(flat)[1]))
        spatial_draws.sort()
        algebraic_draws.sort()
        cut = int(0.95 * rounds)
        self.spatial_bar = spatial_draws[min(cut, rounds - 1)]
        self.algebraic_bar = algebraic_draws[min(cut, rounds - 1)]
        return self.spatial_bar, self.algebraic_bar

    def sniff(self, sets, label):
        # THE DRAWN BAR, AND NO SILENT FALLBACK TO THE DERIVED ONE. `spatial` and `algebraic` each
        # hand back root(2 ln N) as a third value, which is the EXPECTED maximum of N standard
        # normals - half of all nulls exceed it, so it fires on flat data about half the time.
        #
        # An earlier fix computed the drawn bars in `draw_bars` and then left this line reading the
        # derived ones, so the correct bar was calculated and thrown away on every call and the
        # tool went on reporting against the wrong threshold while looking fixed. That is worse than
        # never having drawn them, because the presence of `draw_bars` in the file reads as evidence
        # the fault was dealt with.
        #
        # So it is an error to sniff before drawing, rather than a quiet default. A tool that cannot
        # state its own floor has nothing to report.
        if not hasattr(self, "spatial_bar") or not hasattr(self, "algebraic_bar"):
            raise RuntimeError(
                "draw_bars() must run before sniff(): the bar has to come from flat data at this "
                "weight and trial count, and there is no correct value to assume")
        degree, sz, _ = self.spatial(sets)
        mask, az, _ = self.algebraic(sets)
        sbar = self.spatial_bar
        abar = self.algebraic_bar
        spatial_hit = abs(sz) >= sbar
        algebraic_hit = abs(az) >= abar
        print("    %-12s spatial %+7.2f (bar %.2f, degree %d)   algebraic %+7.2f (bar %.2f)%s"
              % (label, sz, sbar, degree, az, abar,
                 "   <-- " + ("both" if spatial_hit and algebraic_hit
                              else "spatial" if spatial_hit
                              else "algebraic" if algebraic_hit else "")
                 if (spatial_hit or algebraic_hit) else ""))
        return spatial_hit, algebraic_hit, degree, mask


def plant(kind, weight, rng):
    """One lit set carrying a known kind of structure, for the validation gate."""
    places = boundary_read.golden_place(POINTS)
    if kind == "flat":
        return sorted(rng.sample(range(POINTS), weight))
    if kind == "shape":
        ordered = sorted(range(POINTS), key=lambda i: places[i][1])
        head = ordered[: POINTS // 3]
        rest = [i for i in range(POINTS) if i not in set(head)]
        take = min(len(head), int(weight * 0.62))
        return sorted(rng.sample(head, take) + rng.sample(rest, weight - take))
    if kind == "algebra":
        chosen = rng.sample(range(POINTS), weight)
        mask = [3, 47, 91, 150, 203]
        if sum(1 for i in chosen if i in mask) % 2 == 1:
            for candidate in mask:
                if candidate in chosen:
                    chosen.remove(candidate)
                    spare = [i for i in range(POINTS) if i not in chosen and i not in mask]
                    chosen.append(rng.choice(spare))
                    break
        return sorted(chosen)
    raise ValueError(kind)


def validate(trials=300, weight=110):
    print("=" * 78)
    print("  VALIDATION: each stage must fire on its own class and stay quiet on the other")
    print("=" * 78)
    print()
    rng = random.Random(0x9A11)
    sniffer = Sniffer()
    print("    drawing the bars from flat data at weight %d, %d trials..." % (weight, trials))
    spatial_bar, algebraic_bar = sniffer.draw_bars(weight, trials)
    print("    spatial bar %.2f, algebraic bar %.2f, each the 95th percentile of flat runs"
          % (spatial_bar, algebraic_bar))
    print("    against the derived root(2 ln N): %.2f spatial, %.2f algebraic"
          % (math.sqrt(2.0 * math.log(max(sniffer.top, 2))),
             math.sqrt(2.0 * math.log(len(sniffer.masks)))))
    print()
    outcomes = {}
    for kind in ("flat", "shape", "algebra"):
        sets = [plant(kind, weight, rng) for _ in range(trials)]
        outcomes[kind] = sniffer.sniff(sets, kind)

    print()
    flat_s, flat_a = outcomes["flat"][0], outcomes["flat"][1]
    shape_s, shape_a = outcomes["shape"][0], outcomes["shape"][1]
    alg_s, alg_a = outcomes["algebra"][0], outcomes["algebra"][1]

    ok = (not flat_s and not flat_a) and shape_s and alg_a
    print("    flat fires nothing          %s" % ("yes" if (not flat_s and not flat_a) else "NO"))
    print("    shape fires the spatial arm %s" % ("yes" if shape_s else "NO"))
    print("    algebra fires the other arm %s" % ("yes" if alg_a else "NO"))
    print("    algebra is INVISIBLE to the spatial arm  %s"
          % ("yes, as the bake-off showed" if not alg_s else "no"))
    print()
    if ok:
        print("    VALIDATED. Both stages detect their own class and the floor stays quiet, so a")
        print("    null from this sniffer now means something it would not have meant before.")
        return 0
    print("    NOT VALIDATED. Do not believe a null from it until this passes.")
    return 1


def rounds(trials=300):
    """Point the validated sniffer at SHA-256's own states."""
    print()
    print("=" * 78)
    print("  SHA-256 STATES")
    print("=" * 78)
    print()
    sniffer = Sniffer()
    rng = random.Random(0x3ADE)
    block = [0x80000000] + [0] * 15
    states = state_deflection.states_of(block)

    for step in (1, 8, 16, 32, 48, 64):
        sets = []
        for _ in range(trials):
            varied = list(block)
            varied[rng.randrange(16)] ^= 1 << rng.randrange(32)
            walk = state_deflection.states_of(varied)
            sets.append(sorted(state_deflection.lit_of(walk[step])))
        weight = min(len(one) for one in sets)
        sets = [one[:weight] for one in sets]
        # THE BAR IS REDRAWN AT EACH ROUND'S OWN WEIGHT. A lit set's spectrum depends heavily on how
        # many bits are lit, and the weight wanders across the rounds being compared here - so one
        # bar drawn at one weight would report that wander as signal at every other round. The null
        # has to carry the nuisance parameter, which means drawing it where the parameter sits.
        sniffer.draw_bars(weight, len(sets))
        sniffer.sniff(sets, "round %d (weight %d)" % (step, weight))
    return 0


def main():
    parser = argparse.ArgumentParser(description="Two-stage structure sniffer.")
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--rounds", action="store_true")
    given = parser.parse_args()
    code = 0
    if given.validate or not given.rounds:
        code = validate()
    if given.rounds and code == 0:
        code = rounds()
    return code


if __name__ == "__main__":
    raise SystemExit(main())
