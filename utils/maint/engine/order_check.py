#!/usr/bin/env python3
# orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""What a relation decides and what no cost reading can reach, measured instead of argued.

    python utils/maint/engine/order_check.py

The noiseless half of the query protocol. Seven checks, each one isolating a claim the method rests
on. Every number below is produced by the run and none is quoted from anywhere.

    7  gate-then-rank against one combined score
    8  how many arrangements a precept set leaves standing
    9  whether a precept set is independent
    10  whether agreement inside a floor defines a set at all
    11  what an answer costs when it is read outside what it was derived on
    12  whether two transitions in the document ever carry one name
    13  whether the two transition tables agree, and whether each reads alike from both sides

Nothing here is a measurement and nothing here carries noise. `utils/maint/engine/measure_check.py` holds
the noisy half as checks 1 through 6, and the separation between the two files is the separation the
two stages buy: a result in this file cannot be moved by anything in that one.

The numbering runs on from that file, which leaves every finding nameable by its number alone.

Nothing outside the standard library is reached for here, and the arithmetic wants nothing else.
"""

import itertools
import os
import re
import sys
from fractions import Fraction


def show(value):
    """An exact rational as it is: an integer, or numerator/denominator. Never a rounded decimal."""
    value = Fraction(value)
    if value.denominator == 1:
        return str(value.numerator)
    return "%d/%d" % (value.numerator, value.denominator)



# A candidate arrangement: its name, whether it computes the relation, and what it costs.
# PRECEPTS_HELD is the count of relations it satisfies out of PRECEPT_COUNT.
PRECEPT_COUNT = 3
ARRANGEMENTS = (
    ("arr_slow_right", 3, Fraction(100)),
    ("arr_fast_wrong", 2, Fraction(10)),
    ("arr_mid_right", 3, Fraction(140)),
    ("arr_cheap_wrong", 1, Fraction(4)),
)


def check_two_stage(say):
    """7. One combined score ships a wrong program. Two stages cannot."""
    say("7. GATE THEN RANK, AGAINST ONE SCORE")
    say("")
    say("   arrangement        precepts held    cost")
    for name, held, cost in ARRANGEMENTS:
        say("   %-18s %7d of %d    %6s" % (name, held, PRECEPT_COUNT, show(cost)))
    say("")

    # One score: trade a held precept against cost on any exchange rate at all.
    say("   one score, over every exchange rate between a precept and a cost:")
    shipped = set()
    for weight in (Fraction(1), Fraction(10), Fraction(50), Fraction(100), Fraction(200)):
        best = max(ARRANGEMENTS, key=lambda one: weight * one[1] - one[2])
        shipped.add(best[0])
        mark = "   WRONG" if best[1] < PRECEPT_COUNT else ""
        say("     a precept is worth %6s cost    picks %-18s%s" % (show(weight), best[0], mark))
    say("")

    admissible = [one for one in ARRANGEMENTS if one[1] == PRECEPT_COUNT]
    chosen = min(admissible, key=lambda one: one[2])
    say("   two stages:")
    say("     gate    %d of %d arrangements hold every precept" % (len(admissible), len(ARRANGEMENTS)))
    say("     rank    %s at %s" % (chosen[0], show(chosen[2])))
    say("")
    wrong = sorted(one for one in shipped if dict((a, b) for a, b, _ in ARRANGEMENTS)[one] < PRECEPT_COUNT)
    say("   one score ships a wrong program at %d of the 5 rates tried: %s"
        % (len(wrong), ", ".join(wrong) if wrong else "none"))
    say("   two stages ship a wrong program at no rate, because no rate exists to set.")
    say("")
    say("   This is the whole reason a noisy cost is safe. Noise moves the rank and never the")
    say("   gate, and so it can cost speed and can never cost correctness.")
    return len(wrong)


# Arrangements over two inputs, as the ladder's candidates are. Each is a closed form, and a
# precept is one input pair with the answer the relation gives.
def arrangement_space():
    """Every arrangement this check ranges over, as (name, function)."""
    held = []
    for first in ("a+b", "a-b", "b-a", "a*b", "max", "min", "a", "b"):
        for scale in (1, 2):
            for shift in (0, 1):
                name = "%s x%d +%d" % (first, scale, shift)
                held.append((name, _closed(first, scale, shift)))
    return held


def _closed(form, scale, shift):
    table = {
        "a+b": lambda a, b: a + b,
        "a-b": lambda a, b: a - b,
        "b-a": lambda a, b: b - a,
        "a*b": lambda a, b: a * b,
        "max": lambda a, b: max(a, b),
        "min": lambda a, b: min(a, b),
        "a": lambda a, b: a,
        "b": lambda a, b: b,
    }
    base = table[form]
    return lambda a, b: base(a, b) * scale + shift


# The relation under test, and the cases put for it. 1,1 -> 2 is the first.
CASES = (((1, 1), 2), ((2, 2), 4), ((3, 1), 4), ((0, 5), 5), ((7, 2), 9))


def check_survivors(say):
    """8. How many arrangements a precept set leaves standing is a reading, and it is kept."""
    say("8. WHAT A PRECEPT SET LEAVES STANDING")
    say("")
    space = arrangement_space()
    say("   %d candidate arrangements, over the relation a,b -> a+b." % len(space))
    say("")
    say("   cases put    survivors    decided")
    standing = space
    for upto in range(1, len(CASES) + 1):
        standing = [
            (name, form)
            for name, form in space
            if all(form(*given) == want for given, want in CASES[:upto])
        ]
        say("   %9d    %9d    %s"
            % (upto, len(standing), "yes" if len(standing) == 1 else "no"))
    say("")
    say("   names still standing: %s" % ", ".join(name for name, _ in standing))
    say("")
    say("   The count is the reading. One survivor means the precepts decide this operator.")
    say("   More than one means they do not, and the answer to that is another relation and")
    say("   never more measurement: no cost reading can separate two arrangements that both")
    say("   compute the relation.")
    return len(standing)


def check_independence(say):
    """9. A precept implied by the others double counts in any score that counts precepts."""
    say("9. WHETHER THE PRECEPT SET IS INDEPENDENT")
    say("")
    space = arrangement_space()

    def holds(form, case):
        given, want = case
        return form(*given) == want

    implied = []
    for drop in range(len(CASES)):
        rest = [one for at, one in enumerate(CASES) if at != drop]
        survivors = [form for _, form in space if all(holds(form, one) for one in rest)]
        if survivors and all(holds(form, CASES[drop]) for form in survivors):
            implied.append(drop)

    for at, case in enumerate(CASES):
        given, want = case
        mark = "IMPLIED by the rest" if at in implied else "independent"
        say("   case %d   %d,%d -> %-3d  %s" % (at + 1, given[0], given[1], want, mark))
    say("")
    smallest = None
    for size in range(1, len(CASES) + 1):
        for pick in itertools.combinations(range(len(CASES)), size):
            chosen = [CASES[at] for at in pick]
            if len([1 for _, form in space if all(holds(form, one) for one in chosen)]) == 1:
                smallest = pick
                break
        if smallest:
            break
    say("")
    if smallest:
        say("   %d of %d cases decide it on their own: %s"
            % (len(smallest), len(CASES), ", ".join("case %d" % (at + 1) for at in smallest)))
        say("   %d cases are surplus." % (len(CASES) - len(smallest)))
    else:
        say("   No subset of these cases decides it, and the whole set does not either.")
    say("")
    if implied:
        say("   %d of %d cases carry no information this set does not already hold. A set carrying"
            % (len(implied), len(CASES)))
        say("   surplus looks like that from the inside. Counting precepts held then weights one")
        say("   fact several times over, at weights nobody set. Here is the second reason a count")
        say("   of precepts cannot be a score: it is not even a count of independent facts.")
    else:
        say("   Every case constrains something the others do not. The count is a fair vote.")
    say("")
    say("   This check is mechanical and wants running whenever a case is added.")
    return len(implied)


# Three members, their fingerprints, and the floor each one carries.
MEMBERS = (("sm_86", Fraction(100), Fraction(3)), ("sm_87", Fraction(104), Fraction(5)),
           ("sm_89", Fraction(108), Fraction(5)))


def check_floor_sets(say):
    """10. Agreement inside a floor is neither symmetric nor transitive, and it names no set."""
    say("10. WHETHER AGREEMENT INSIDE A FLOOR DEFINES A SET")
    say("")
    for name, mark, floor in MEMBERS:
        say("   %-8s fingerprint %6s   floor %4s" % (name, show(mark), show(floor)))
    say("")

    def agree_asked(one, two):
        return abs(one[1] - two[1]) <= one[2]

    def agree_coarse(one, two):
        return abs(one[1] - two[1]) <= max(one[2], two[2])

    say("   asked from the first member's own floor:")
    broken = 0
    for one in MEMBERS:
        for two in MEMBERS:
            if one is two:
                continue
            there = agree_asked(one, two)
            back = agree_asked(two, one)
            if there != back:
                broken += 1
                say("     %s sees %s agreeing: %-5s   %s sees %s agreeing: %-5s   NOT SYMMETRIC"
                    % (one[0], two[0], there, two[0], one[0], back))
    if not broken:
        say("     symmetric on this set")
    say("")

    say("   taken at the coarser of the two floors:")
    links = []
    for at, one in enumerate(MEMBERS):
        for two in MEMBERS[at + 1:]:
            if agree_coarse(one, two):
                links.append((one[0], two[0]))
                say("     %s agrees with %s" % (one[0], two[0]))
    say("")

    held = set(links)
    chain_broken = []
    for one in MEMBERS:
        for two in MEMBERS:
            for three in MEMBERS:
                if len({one[0], two[0], three[0]}) != 3:
                    continue
                first = (one[0], two[0]) in held or (two[0], one[0]) in held
                second = (two[0], three[0]) in held or (three[0], two[0]) in held
                ends = (one[0], three[0]) in held or (three[0], one[0]) in held
                if first and second and not ends:
                    chain_broken.append((one[0], two[0], three[0]))
    if chain_broken:
        one, two, three = chain_broken[0]
        say("   NOT TRANSITIVE: %s agrees with %s, %s agrees with %s, %s does not agree with %s."
            % (one, two, two, three, one, three))
        say("")
        say("   So pairwise agreement names no set. Asking which members share a stem has no")
        say("   answer that does not depend on which member was asked first. A generic block")
        say("   covering 'any of these' has no membership test until one of two things is")
        say("   written: a representative each member is compared against, or a rule that")
        say("   builds the group and states which member it is anchored on.")
    else:
        say("   transitive on this set, which the next member added is free to break.")
    return len(chain_broken)


# Three arrangements producing one operator, each costed as a setup term plus a per-item term.
# None is wrong and none dominates: that is the normal case.
SHAPES = (
    ("arr_flat", Fraction(40), Fraction(1), Fraction(0)),
    ("arr_step", Fraction(6), Fraction(4), Fraction(0)),
    ("arr_fold", Fraction(2), Fraction(0), Fraction(3, 10)),
)

# Members, each scaling the setup and the per-item terms its own way. A part with cheap setup and
# slow throughput and a part with the reverse are both normal.
PARTS = (("one", Fraction(1), Fraction(1)), ("two", Fraction(1, 20), Fraction(6)),
         ("three", Fraction(5), Fraction(2, 5)))


def shape_cost(shape, part, size):
    _, setup, each, square = shape
    _, setup_scale, each_scale = part
    return setup * setup_scale + each_scale * (each * size + square * size * size)


def check_transplant(say):
    """11. An answer read outside what it was derived on, priced."""
    say("11. READING AN ANSWER OUTSIDE WHAT IT WAS DERIVED ON")
    say("")
    say("   A foundation that held up three stories is not a foundation for a tower, and it is not")
    say("   a floor of some other building either. Both transplants are priced here.")
    say("")

    say("   ACROSS SIZE, on part one:")
    say("   size      best        cost    the size-3 answer costs    penalty")
    small = min(SHAPES, key=lambda one: shape_cost(one, PARTS[0], 3))
    worst = Fraction(1)
    for size in (3, 8, 24, 80, 300):
        best = min(SHAPES, key=lambda one: shape_cost(one, PARTS[0], size))
        here = shape_cost(best, PARTS[0], size)
        held = shape_cost(small, PARTS[0], size)
        worst = max(worst, held / here)
        say("   %4d  %-10s %12s %22s %16sx"
            % (size, best[0], show(here), show(held), show(held / here)))
    say("")
    say("   %s wins at size 3 and costs %s times the best at size 300. The answer did not go"
        % (small[0], show(worst)))
    say("   stale and nothing drifted: it was only ever an answer at the size it was asked at.")
    say("")

    say("   ACROSS PARTS, at size 24:")
    native = {}
    for part in PARTS:
        best = min(SHAPES, key=lambda one: shape_cost(one, part, 24))
        native[part[0]] = best
        say("   part %-6s best %-10s %12s" % (part[0], best[0], show(shape_cost(best, part, 24))))
    say("")
    held = native[PARTS[0][0]]
    spread = Fraction(1)
    for part in PARTS[1:]:
        here = shape_cost(native[part[0]], part, 24)
        there = shape_cost(held, part, 24)
        spread = max(spread, there / here)
        mark = "agrees" if native[part[0]][0] == held[0] else "DISAGREES"
        say("   part one's answer on part %-6s %12s against %12s   %12sx   %s"
            % (part[0], show(there), show(here), show(there / here), mark))
    say("")
    say("   Some parts agree and some do not, and no reading on one part says which. Splicing the")
    say("   winner across costs up to %s times here, and across both axes at once the two" % show(spread))
    say("   penalties multiply to %sx." % show(worst * spread))
    say("")
    say("   An answer therefore carries the part and the size it was asked at, and a reader")
    say("   outside either one has nothing and has to ask. A generic block is the fallback for a")
    say("   member with nothing measured, and never a result borrowed from a member that has.")
    return worst, spread





# The matrices live in the document and are read from it. Nothing here can drift from what the
# document says, because nothing is copied here.
MATRIX_DOC = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))),
    "src", "engine", "compiler", "gnascor.md")
MATRIX_HEAD = re.compile(r"^\|\s*past \(N-1\)")


def read_matrices(path):
    """Every transition table in the document, as (heading, column names, rows)."""
    with open(path, encoding="utf-8", errors="replace") as handle:
        lines = handle.read().splitlines()
    held = []
    where = ""
    at = 0
    while at < len(lines):
        if lines[at].startswith("## "):
            where = lines[at][3:].strip()
        if MATRIX_HEAD.match(lines[at]):
            names = [one.strip() for one in lines[at].strip("|").split("|")][1:]
            rows = []
            at += 2
            while at < len(lines) and lines[at].startswith("|"):
                cells = [one.strip() for one in lines[at].strip("|").split("|")]
                rows.append((cells[0], cells[1:]))
                at += 1
            held.append((where, names, rows))
        at += 1
    return held


def check_mnemonics(say):
    """12. Whether the transition tables name every transition apart from every other."""
    say("12. WHETHER TWO TRANSITIONS EVER CARRY ONE NAME")
    say("")
    say("   Read from %s." % os.path.relpath(MATRIX_DOC).replace("\\", "/"))
    say("")
    worst = 0
    for where, names, rows in read_matrices(MATRIX_DOC):
        cells = {}
        for past, row in rows:
            for at, said in enumerate(row):
                if not said or said == "-":
                    continue
                name = said.split()[0]
                cells.setdefault(name, []).append("%s to %s" % (past, names[at].split()[0]))
        total = sum(len(one) for one in cells.values())
        shared = {name: one for name, one in cells.items() if len(one) > 1}
        say("   %s" % where)
        say("     %d transitions, %d names, %d names carrying more than one"
            % (total, len(cells), len(shared)))
        for name in sorted(shared, key=lambda one: -len(shared[one])):
            held = shared[name]
            worst = max(worst, len(held))
            say("       %-6s %3d transitions   %s%s"
                % (name, len(held), ", ".join(held[:3]), " ..." if len(held) > 3 else ""))
        say("     %d of %d transitions resolve to a name nothing else uses"
            % (total - sum(len(one) for one in shared.values()), total))
        say("")
    say("   A name covering many transitions can be a deliberate choice. It is a")
    say("   defect where the name is all a branch gets, because then the transitions under it")
    say("   are gone and no later reading brings them back. The same rule the cost bound follows")
    say("   applies: a missing address, a false qualifier and a timeout all read 0, and what")
    say("   separates them survives in the baseline instead of in the bit.")
    say("")
    say("   So each name above carrying more than one transition owes an answer to where the")
    say("   distinction is kept. The largest here covers %d." % worst)
    return worst


def table_cells(names, rows):
    """A table as {(past, now): name}, every state and every name read as its first word."""
    cells = {}
    for past, row in rows:
        for at, said in enumerate(row):
            if said and said != "-":
                cells[(past.split()[0], names[at].split()[0])] = said.split()[0]
    return cells


# The two addresses of a branch, which trade places when the branch is read from its other side.
SIDES = {"LEAD": "RITE", "RITE": "LEAD"}


def check_tables_agree(say):
    """13. Whether the two tables agree where they overlap, and whether either reads alike from both sides."""
    say("13. WHETHER THE TABLES AGREE WITH EACH OTHER AND WITH THEIR OWN MIRROR")
    say("")
    say("   A transition is its pair, the state it left and the state it reached, and a name is a")
    say("   label read off the pair. Kept that way, a name over many transitions loses none of them.")
    say("   What a label can still get wrong is checked here, from the tables alone.")
    say("")
    tables = [table_cells(names, rows) for _where, names, rows in read_matrices(MATRIX_DOC)]
    first, second = tables[0], tables[1]
    refined = []
    contradicted = []
    for pair in sorted(set(first) & set(second)):
        if first[pair] == second[pair]:
            continue
        if first[pair] == "SYNC":
            refined.append(pair)
        else:
            contradicted.append(pair)
    say("   where both tables name a transition:")
    say("     %d agree, %d the second names where the first says SYNC, %d named apart"
        % (len(set(first) & set(second)) - len(refined) - len(contradicted), len(refined),
           len(contradicted)))
    for pair in contradicted:
        say("       %s to %s: %s in the first, %s in the second"
            % (pair[0], pair[1], first[pair], second[pair]))
    say("")

    mirrored = []
    for number, cells in enumerate(tables):
        seen = set()
        for (past, now), name in sorted(cells.items()):
            mirror = (SIDES.get(past, past), SIDES.get(now, now))
            both = frozenset(((past, now), mirror))
            if mirror == (past, now) or mirror not in cells or both in seen:
                continue
            seen.add(both)
            other = cells[mirror]
            if other != SIDES.get(name, name):
                mirrored.append(((past, now), mirror, number, name, other))
    say("   read from the other side of the branch, LEAD and RITE trading places:")
    if not mirrored:
        say("     every transition reads alike")
    for pair, mirror, number, name, other in mirrored:
        say("     table %d: %s to %s is %s, and %s to %s is %s"
            % (number + 1, pair[0], pair[1], name, mirror[0], mirror[1], other))
    say("")
    say("   A pair named apart in the two tables is two candidates, and the asks that read the")
    say("   transition decide between them in that situation: a bit excludes, a magnitude ranks.")
    say("   A transition and its mirror named apart is a direction, which the part is asked for:")
    say("   utils/test/engine/compiler/bootstrap/branch_side_check.c reads whether a side leaves a mark.")
    return len(contradicted), len(mirrored)

def main():
    out = sys.stdout
    out.reconfigure(encoding="utf-8", errors="replace")

    def say(line=""):
        out.write("  " + line + "\n" if line else "\n")

    say("=" * 76)
    say("WHAT A RELATION DECIDES")
    say("=" * 76)
    say("Nothing below is measured and nothing below carries noise.")
    say()

    wrong = check_two_stage(say)
    say()
    standing = check_survivors(say)
    say()
    implied = check_independence(say)
    say()
    chains = check_floor_sets(say)
    say()
    stale, spliced = check_transplant(say)
    say()
    shared = check_mnemonics(say)
    say()
    apart, unmirrored = check_tables_agree(say)
    say()

    say("=" * 76)
    say("WHAT THIS RUN SAYS")
    say("=" * 76)
    say("7  one score ships a wrong program at %d of 5 exchange rates. Two stages cannot." % wrong)
    say("8  the gate leaves %d standing after every case is put, where one means decided."
        % standing)
    say("9  %d of %d cases carry nothing the rest do not, and a count of precepts is therefore"
        % (implied, len(CASES)))
    say("   not a count of independent facts.")
    say("10  agreement inside a floor is %s, and a set needs more than pairwise agreement."
        % ("not transitive" if chains else "transitive here"))
    say("11  an answer read at the wrong size costs %sx and on the wrong part %sx. It carries"
        % (show(stale), show(spliced)))
    say("   both, or it answers nothing.")
    say("12  one name in the document covers %d separate transitions. Each name covering more"
        % shared)
    say("   than one owes an answer to where the distinction is kept.")
    say("13  the two tables name %d transitions apart, and %d transitions read otherwise from the"
        % (apart, unmirrored))
    say("   other side of the branch.")
    say()
    say("Every finding above holds whatever a cost reading says. Keeping the two files apart is")
    say("worth it for that property alone.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
