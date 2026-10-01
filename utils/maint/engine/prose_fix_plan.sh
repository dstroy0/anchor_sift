#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
# The banned constructions this hand wrote into the engine plan, rewritten in place. Each edit names the old text
# whole, and a line whose text has moved is left alone and reported
#
#     utils/maint/engine/prose_fix_plan.sh
set -u

TOP="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PLAN="$TOP/src/engine_plan.md"
mkdir -p "$TOP/build"

edit() {
    local old="$1"
    local new="$2"
    if grep -qF -- "$old" "$PLAN"; then
        python "$TOP/utils/maint/engine/prose_swap.py" "$PLAN" "$old" "$new" || true
    else
        echo "  the plan no longer holds \"$old\""
    fi
}

edit "ends on it: that is what kept 22 holes" "ends on it, and that kept 22 holes"
edit "bit-slices, not arithmetic," \
    "bit-slices and not arithmetic,"
edit "which is why a ruleset can write them at all." "and a ruleset can write them for that reason."
edit "target sitting in C++ rather than in the .krs" "target sitting in C++ and not in the .krs"
edit "The part answers right every time,
     so a form reached by turning one bit is not only decodable but runs." \
    "The part answers right every time:
     a form reached by turning one bit runs, and does not merely decode."
edit "which is why 968 of 976 match byte for byte" "and for that reason 968 of 976 match byte for byte"
edit "are not in the text, so code written from text needs a schedule" \
    "are not in the text, and code written from text needs a schedule"
edit "part is what makes it correct - without it" "part is the one that makes it correct - without it"
edit "refused
   rather than written over the fixed registers" "refused,
   in place of being written over the fixed registers"
edit "no lane here asks for one, so none is a blocker" "no lane here asks for one, and none is a blocker"
edit "alone but not an and, so an and pays one MOV" "alone but not an and, and an and pays one MOV"
edit "\`cell_ptx_probe run\`), so nothing in the machine file is needed" \
    "\`cell_ptx_probe run\`), and nothing in the machine file is needed"
edit "which is a bench and not an ask." "which is a bench, no longer an ask."
edit "answers 240, which is what the file holds and not what a lane can take and stay fast, and" \
    "answers 240, the count the file holds and not what a lane can take and stay fast, and"
edit "closed rather than lying" "closed in place of lying"
edit "(sass_machine_same), so S2R R2, SR_CLOCKLO finds no form" \
    "(sass_machine_same), and S2R R2, SR_CLOCKLO finds no form"
edit "share nothing, which is what says the reading is the" "share nothing, and that says the reading is the"
edit "on the next run, so the first reading of this kind was noise" \
    "on the next run, and the first reading of this kind was noise"
edit "hides it; real code with occupancy hides most of it," "hides it. Real code with occupancy hides most of it,"
edit "defeats its own purpose, so it can only be a pattern match" \
    "defeats its own purpose, and it can only be a pattern match"
edit "the easiest one there is - 400000 turns of one identical body in a tight loop, which is what a
bench looks like and nothing else does." \
    "the easiest one there is - 400000 turns of one identical body in a tight loop, the shape of a
bench and of no other code."
edit "which the widening round refuses on purpose" "which the widening round deliberately refuses"
edit "SASS has no declarations, so sass.krs" "SASS has no declarations, and sass.krs"
edit "a predicate in predicate_xor), so each form" "a predicate in predicate_xor), and each form"
edit "as a ruleset has, so 0 of 58 assembled" "as a ruleset has: 0 of 58 assembled"
edit "an nvdisasm listing, so nothing had" "an nvdisasm listing, and nothing had"
edit "where a predicate belongs, so no predicate operation" \
    "where a predicate belongs, and no predicate operation"
echo "done"
