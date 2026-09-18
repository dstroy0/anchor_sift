#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# Catalog: PP-6-001
#
# The ideal Madelung filling held against the published ground states. The aufbau exceptions are read
# and not asserted.
#
#   Usage:  python examples/particle_physics/6_oracle/measured_configuration_vs_ideal.py
#
# The represent stage carries the ideal filling, Madelung order under Hund's rule, and says it is the
# model. This is the measurement it is held against: the ground-state configurations from the NIST
# Atomic Spectra Database, fetched by maint/data/fetch/fetch_nist_ground_states.py. Where a real atom
# fills against the order, the two disagree, and that disagreement is an aufbau exception the oracle
# reports and not a list this file carries.
#
# Two routes meet here. The ideal is derived from a rule; the measurement is someone else's number. The
# noble gases and most other elements agree, the positive control: a comparison where nothing
# agreed would be a broken reading and not a table of exceptions. The measured configuration is checked
# to account for exactly Z electrons before it is compared. A parse that lost an electron is refused
# and never counted as an exception.
#
# NIST measures neutral atoms to element 108, hassium. For 109 to 118 no neutral atom has been measured,
# only ions or nothing. Those ten carry the predicted relativistic configurations instead, marked
# predicted and kept apart from the measured ones. A check that covers all 118 has to say which rows are
# measured and which are predicted, or it reads a prediction as a measurement.

import io
import os
import re
import sys

# Walk up to the repository instead of counting directories to it, and stop at the filesystem root.
# A directory that is its own parent would otherwise loop the walk forever.
ROOT = os.path.dirname(os.path.abspath(__file__))
while ROOT != os.path.dirname(ROOT) and not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    ROOT = os.path.dirname(ROOT)
if not os.path.isdir(os.path.join(ROOT, "src", "engine")):
    raise SystemExit("could not find src/engine above %s" % os.path.abspath(__file__))
sys.path.insert(0, os.path.join(ROOT, "src", "engine", "python"))

from representation.atom import element  # noqa: E402

GROUND_STATES = os.path.join(ROOT, "build", "nist", "ground_states.csv")

# One subshell as written by NIST: a principal number, a letter, and a count that is one when omitted.
SUBSHELL = re.compile(r"^(\d)([spdfg])(\d*)$")

# The predicted ground-state configurations for elements 109 to 118, the ten with no measured neutral
# atom. These are calculated, not measured, and are kept apart from the NIST rows for that reason. Each
# is written in the same notation as a NIST row, and each sums to its atomic number, checked below the
# way a measured row is.
# Source: Wikipedia, Electron configurations of the elements (data page), which compiles the
# relativistic predictions past hassium.
PREDICTED = {
    109: "[Rn].5f14.6d7.7s2",
    110: "[Rn].5f14.6d8.7s2",
    111: "[Rn].5f14.6d9.7s2",
    112: "[Rn].5f14.6d10.7s2",
    113: "[Rn].5f14.6d10.7s2.7p",
    114: "[Rn].5f14.6d10.7s2.7p2",
    115: "[Rn].5f14.6d10.7s2.7p3",
    116: "[Rn].5f14.6d10.7s2.7p4",
    117: "[Rn].5f14.6d10.7s2.7p5",
    118: "[Rn].5f14.6d10.7s2.7p6",
}


def read_rows():
    """Every ground-shells string for each atomic number, in the order NIST lists them, keyed by Z.

    The neutral atom is the row that accounts for all Z electrons, and for the heaviest elements NIST
    carries only ions. The caller picks the neutral by the electron count and not by the order.
    Returns a dict from Z to a list of shells strings, cores not yet expanded.
    """
    rows = {}
    with io.open(GROUND_STATES, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            fields = re.findall(r'=""(.*?)""', line)
            if len(fields) < 3:
                continue
            try:
                atomic_number = int(fields[0])
            except ValueError:
                continue
            rows.setdefault(atomic_number, []).append(fields[2])
    return rows


def occupation(shells, neutral):
    """A shells string as a lookup from subshell to electron count, cores expanded.

    Parenthesized term symbols are stripped, and a bracketed core such as `[Rn]` or `[Cd]` is replaced
    by the shells of that element, read from the same table. NIST abbreviates with whichever element
    closes the core, not only the noble gases. Returns None where a token does not parse. The caller
    can refuse it and not compare a half-read configuration.
    """
    counts = {}
    for token in re.sub(r"\(.*?\)", "", shells).split("."):
        token = token.strip()
        if not token:
            continue
        if token.startswith("[") and token.endswith("]"):
            try:
                core = element.atomic_number(token[1:-1])
            except ValueError:
                return None
            if core not in neutral:
                return None
            inner = occupation(neutral[core], neutral)
            if inner is None:
                return None
            for subshell, count in inner.items():
                counts[subshell] = counts.get(subshell, 0) + count
            continue
        matched = SUBSHELL.match(token)
        if not matched:
            return None
        subshell = matched.group(1) + matched.group(2)
        counts[subshell] = counts.get(subshell, 0) + int(matched.group(3) or "1")
    return counts


def ideal_occupation(atomic_number):
    """The ideal Madelung filling of an element as a subshell-to-count lookup."""
    counts = {}
    for _, subshell in element.electrons(atomic_number):
        counts[subshell] = counts.get(subshell, 0) + 1
    return counts


def order_key(subshell):
    """Sort key for a subshell label, by principal then azimuthal. Two runs print one order."""
    return int(subshell[0]), element.SUBSHELL.index(subshell[1])


def differing(ideal, measured):
    """The subshells where the two configurations disagree, as text for each side."""
    subshells = sorted((set(ideal) | set(measured)), key=order_key)
    changed = [one for one in subshells if ideal.get(one, 0) != measured.get(one, 0)]
    ideal_text = " ".join("%s%d" % (one, ideal[one]) for one in changed if one in ideal)
    measured_text = " ".join("%s%d" % (one, measured[one]) for one in changed if one in measured)
    return ideal_text, measured_text


def neutral_states(rows):
    """The neutral configuration of every element, keyed by Z, with where each one came from.

    Built ascending, and a core resolves before a heavier element uses it. A measured neutral is the NIST
    row that accounts for all Z electrons; where NIST carries no such row, the predicted configuration
    stands in. Returns (neutral, source), source mapping Z to "measured" or "predicted".
    """
    neutral = {}
    source = {}
    for atomic_number in range(1, element.ELEMENT_COUNT + 1):
        chosen = None
        for shells in rows.get(atomic_number, []):
            counts = occupation(shells, neutral)
            if counts is not None and sum(counts.values()) == atomic_number:
                chosen = shells
                break
        if chosen is not None:
            neutral[atomic_number] = chosen
            source[atomic_number] = "measured"
        elif atomic_number in PREDICTED:
            neutral[atomic_number] = PREDICTED[atomic_number]
            source[atomic_number] = "predicted"
    return neutral, source


def main(argv):
    out = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace", newline="")
    if not os.path.isfile(GROUND_STATES):
        out.write("\n  no measured table at %s\n  run maint/data/fetch/fetch_nist_ground_states.py\n\n"
                  % GROUND_STATES.replace(os.sep, "/"))
        out.flush()
        return 1

    rows = read_rows()
    if not rows:
        out.write("\n  the table parsed to zero elements. It is present but unreadable.\n\n")
        out.flush()
        return 2

    neutral, source = neutral_states(rows)

    measured_agree = 0
    predicted_agree = 0
    exceptions = []
    refused = []
    for atomic_number in range(1, element.ELEMENT_COUNT + 1):
        if atomic_number not in neutral:
            refused.append(atomic_number)
            continue
        counts = occupation(neutral[atomic_number], neutral)
        if counts is None or sum(counts.values()) != atomic_number:
            refused.append(atomic_number)
            continue
        ideal = ideal_occupation(atomic_number)
        if ideal == counts:
            if source[atomic_number] == "measured":
                measured_agree += 1
            else:
                predicted_agree += 1
        else:
            exceptions.append((atomic_number, source[atomic_number], ideal, counts))

    measured_total = sum(1 for one in source if source[one] == "measured")
    predicted_total = sum(1 for one in source if source[one] == "predicted")
    covered = measured_total + predicted_total
    measured_differ = sum(1 for one in exceptions if one[1] == "measured")
    predicted_differ = sum(1 for one in exceptions if one[1] == "predicted")

    out.write("\n  THE IDEAL AGAINST THE GROUND STATES.\n\n")
    out.write("    %d of %d elements covered: %d measured through element 108, %d predicted for 109 to 118\n"
              % (covered, element.ELEMENT_COUNT, measured_total, predicted_total))
    out.write("    measured:  %d agree with the ideal filling, %d differ\n"
              % (measured_agree, measured_differ))
    out.write("    predicted: %d agree, %d differ\n" % (predicted_agree, predicted_differ))
    if refused:
        out.write("    %d without a configuration accounting for its electrons: %s\n"
                  % (len(refused), " ".join(element.symbol(one) for one in refused)))

    out.write("\n  THE EXCEPTIONS, read off the disagreement, not listed by hand.\n\n")
    out.write("    %-4s %-4s %-10s %-18s %s\n" % ("", "Z", "source", "ideal", "ground state"))
    for atomic_number, kind, ideal, counts in exceptions:
        ideal_text, ground_text = differing(ideal, counts)
        out.write("    %-4s %-4d %-10s %-18s %s\n"
                  % (element.symbol(atomic_number), atomic_number, kind, ideal_text, ground_text))

    out.write("\n  most elements agree, the control; the disagreements are where an atom fills against\n")
    out.write("  the order the ideal follows. The predicted configurations are calculated, not measured,\n")
    out.write("  and the source column keeps the two apart.\n\n")
    out.flush()
    return 0 if covered else 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
