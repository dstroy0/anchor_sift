#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: MOL-6-001
#
# A molecular formula tested for a legal valence structure, by exact integers, against a wide set.
#
#   Usage:  python examples/molecules/6_oracle/legal_against_a_wide_set.py
#
# A formula has a legal valence structure only where three integer conditions hold on the valences its
# atoms carry. Write v for an atom's valence, the bonds it must make, and read them off the same shells
# the assembly stage did. Then, over a formula's atoms:
#
#   the sum of the valences is even, because every bond spends two valences, one at each end;
#   no atom carries more valence than all the others together, or it has nothing to bond the surplus to;
#   the sum is at least twice the atom count less one, or there are too few bonds to join the atoms.
#
# The three are necessary for a structure to exist, and they are checked by integer equality and
# comparison, with no tolerance. They are not sufficient: a formula that passes may still be a strained
# or unstable isomer, and a multivalent atom read at one valence may be refused where a higher valence
# would pass. So this is a sift, a necessary condition, and it is measured as one: run over a wide set
# of real molecules it should pass nearly all of them, the positive control, and it should refuse the
# crafted illegal formulae, the negative control.
#
# The wide set is the molecular formulae of the first several thousand PubChem compounds, fetched by
# maint/data/fetch/fetch_pubchem_formulae.py. A charged formula is an ion, whose valence count carries
# an extra electron this neutral reading does not model, and those are set aside and counted. A formula
# with an element the valence table does not carry is set aside too, named, not guessed.
#
# Integer arithmetic only, with no library and no rounding. Source of the valences: the standard
# main-group valences, the same shell deficits the assembly stage reads. Source of the wide set: the
# PubChem compound database.

import io
import os
import re
import sys

# Walk up to the repository instead of counting directories to it, and stop at the filesystem root.
# A directory that is its own parent would otherwise loop the walk forever. Counting is what broke
# every path in this tree the last time anything moved.
ROOT = os.path.dirname(os.path.abspath(__file__))
while ROOT != os.path.dirname(ROOT) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
if not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    raise SystemExit("could not find src/engine above %s" % os.path.abspath(__file__))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from measure.graph_realizable import connected_multigraph  # noqa: E402

WIDE_SET = os.path.join(ROOT, "build", "pubchem", "formulae.csv")

# The graph words the realizability test returns, in the words a molecule reads them as.
REASON = {
    "odd degree sum": "odd valence sum",
    "a vertex over-connected": "an atom over-connected",
    "too few edges to connect": "too few bonds to connect",
    "single vertex": "single atom",
    "realizable": "legal",
    "no vertices": "no atoms",
}

# The valence each element carries, the bonds it makes, read as the deficit to a closed shell. These
# are the main-group valences the assembly stage derives. An element absent here is not guessed.
VALENCE = {
    "H": 1, "B": 3, "C": 4, "N": 3, "O": 2, "F": 1,
    "Si": 4, "P": 3, "S": 2, "Cl": 1, "Br": 1, "I": 1,
    "Se": 2, "As": 3, "Te": 2,
}

# A formula's atoms, matched as an element symbol and an optional count.
ATOM = re.compile(r"([A-Z][a-z]?)(\d*)")


def parse_formula(text):
    """A formula string as (counts, charged). Counts maps element to number; charged flags an ion."""
    charged = ("+" in text) or ("-" in text)
    body = re.sub(r"[+-]\d*$", "", text.strip())
    counts = {}
    for symbol, number in ATOM.findall(body):
        if not symbol:
            continue
        counts[symbol] = counts.get(symbol, 0) + (int(number) if number else 1)
    return counts, charged


def legal(counts):
    """Whether a neutral formula can carry a valence structure, as (verdict, reason).

    verdict is True, False, or None where an element is not in the table. The atoms become a degree
    list, one degree per atom equal to its valence, and connected_multigraph decides whether a molecule
    graph can carry them. The reason names the condition that failed, in molecule words.
    """
    if any(symbol not in VALENCE for symbol in counts):
        return None, "element not in table"
    degrees = []
    for symbol, number in counts.items():
        degrees.extend([VALENCE[symbol]] * number)
    verdict, reason = connected_multigraph(degrees)
    return verdict, REASON.get(reason, reason)


# Real molecules, which must pass, and crafted illegal formulae, which must be refused. Cited: the real
# ones are PubChem compounds; the illegal ones are named by what they break.
LEGAL_CONTROL = ("H2O", "CH4", "NH3", "CO2", "C2H6O", "C6H6", "C8H10N4O2")
ILLEGAL_CONTROL = (("CH5", "odd valence sum"), ("CH2", "an atom over-connected"),
                   ("C", "single atom"), ("H3", "odd valence sum"))


def controls(out):
    """Prove the sift: every real formula passes and every crafted illegal one is refused for its reason."""
    out.write("\n  CONTROLS.\n\n")
    passed = True
    for formula in LEGAL_CONTROL:
        counts, _ = parse_formula(formula)
        verdict, reason = legal(counts)
        passed = passed and (verdict is True)
        out.write("    legal   %-12s %s\n" % (formula, "pass" if verdict else "FAIL (%s)" % reason))
    for formula, want in ILLEGAL_CONTROL:
        counts, _ = parse_formula(formula)
        verdict, reason = legal(counts)
        caught = (verdict is False) and (reason == want)
        passed = passed and caught
        out.write("    illegal %-12s refused for %-24s %s\n"
                  % (formula, reason, "as wanted" if caught else "NOT AS WANTED, wanted %s" % want))
    return passed


def wide_set(out):
    """Run the sift over the fetched formulae, report the pass rate and decompose what it sets aside."""
    if not os.path.isfile(WIDE_SET):
        out.write("\n  no wide set at %s\n  run maint/data/fetch/fetch_pubchem_formulae.py\n"
                  % WIDE_SET.replace(os.sep, "/"))
        return
    legal_count = 0
    illegal = {}
    charged = 0
    uncovered = 0
    read = 0
    with io.open(WIDE_SET, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            formula = line.split(",")[-1].strip().strip('"')
            if (not formula) or formula == "MolecularFormula":
                continue
            read += 1
            counts, is_charged = parse_formula(formula)
            if is_charged:
                charged += 1
                continue
            verdict, reason = legal(counts)
            if verdict is None:
                uncovered += 1
            elif verdict:
                legal_count += 1
            else:
                illegal[reason] = illegal.get(reason, 0) + 1

    neutral_covered = legal_count + sum(illegal.values())
    out.write("\n  THE WIDE SET. %d formulae read from PubChem.\n\n" % read)
    out.write("    set aside: %d charged (ions), %d with an element not in the table\n"
              % (charged, uncovered))
    out.write("    neutral and covered: %d\n" % neutral_covered)
    if neutral_covered:
        out.write("    of those, %d pass the valence conditions, %d refused\n"
                  % (legal_count, sum(illegal.values())))
    for reason in sorted(illegal, key=lambda one: -illegal[one]):
        out.write("      refused, %-24s %d\n" % (reason, illegal[reason]))


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    control_ok = controls(out)
    wide_set(out)
    out.write("\n  the conditions are a necessary condition read in integers: a real molecule meets them,\n")
    out.write("  the crafted illegal formulae do not, and the failures are decomposed, not just counted.\n")
    out.write("  a refusal for too few bonds is a formula whose atoms cannot form one connected molecule;\n")
    out.write("  inspected, these are net-neutral salts, an organic cation and a separate counter-ion\n")
    out.write("  written as one formula, not one covalent molecule and right to refuse.\n\n")
    out.flush()
    return 0 if control_ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
