#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Letter case as a second channel carried on the same symbols.
#
#   Usage:  from representation.text.case import case_runs, long_run_share
#
# A byte slice keeps upper and lower case as separate symbols and treats them as unrelated, which is
# right for prose and loses something in source. In C the case of an identifier says which kind of
# thing it is: an upper snake name is a macro, a leading capital is a type, a lower snake name is a
# variable. That is legible from the run lengths alone, without reading any identifier.
#
# Prose uses a capital at the start of a sentence and inside a name, so its runs are almost all of
# length one. A community that names macros in upper case has long runs.
#
# What this measures and what it does not. The channel is real and it is not a formal language
# detector. An early version of the reading recorded a clean separation over ten languages and four
# more broke it: Lean sits below a novel, and Isabelle, Mathematica and Modelica sit inside the
# prose range, because theorem provers name by mathematical convention and have nothing to shout.
# What the measure orders is communities that name things in upper case above ones that do not.
#
# VHDL is the case worth keeping in view. The language is case insensitive, so ENTITY and entity are
# one token and no program can distinguish them. Its share of long runs is 0.495, third of eighteen.
# Nothing in the machine can read that 0.495, so all of it is a community holding a convention for
# other people, which makes it the cleanest instance in this work of a substrate being indifferent
# and the departure above it being entirely intention.

import statistics


def case_runs(text):
    """Lengths of maximal runs of upper case letters."""
    runs = []
    current = 0
    for character in text:
        if character.isalpha() and character.isupper():
            current += 1
            continue
        if current > 0:
            runs.append(current)
            current = 0
    if current > 0:
        runs.append(current)
    return runs


def long_run_share(text, least=3, floor=20):
    """Share of upper case runs at least `least` characters long. This column does the separating.

    Returns None where the text holds fewer than `floor` runs, since a share over a handful of runs
    is a reading of how few there were.
    """
    runs = case_runs(text)
    if len(runs) < floor:
        return None
    return sum(1 for value in runs if value >= least) / float(len(runs))


def run_profile(text, floor=20):
    """Count, share of singles, share of long runs, median and longest, as one tuple.

    The singles column identifies prose at a glance. A capital opening a sentence or a name is a run
    of one, and prose is almost all of them.
    """
    runs = case_runs(text)
    if len(runs) < floor:
        return None
    singles = sum(1 for value in runs if value == 1) / float(len(runs))
    longs = sum(1 for value in runs if value >= 3) / float(len(runs))
    return len(runs), singles, longs, statistics.median(runs), max(runs)
