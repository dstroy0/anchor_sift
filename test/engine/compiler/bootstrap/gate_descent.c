// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// gate_descent.c: the gate run as the engine's own sift descent, against every arrangement asked every case
//
// The gate decides which arrangements hold a relation. Here it is the descent anchor_sift already runs over any
// field it can ask equality of. Each arrangement chain_build keeps against a relation's ladder cases is an
// alignment, the needle is those cases and then the words chain_build's own sweep puts, and the oracle answers
// whether an arrangement gives a case the word the relation gives it.
//
// Three readings, each against a ground truth that does not depend on the descent:
//
//   survivors   what the descent leaves standing, verified case by case, equals what every arrangement asked every
//               case leaves standing, and both equal what chain_build keeps with its sweep on
//   depth       a descent with the destroy rule off leaves the same count as one with it on. Stopping where the best
//               case prunes nothing gives up nothing, and this holds the descent to that claim
//   cases       the cases the descent places, which are the ones that decide the relation
//
// The planning reads every case against every survivor at each level. That is the price of choosing well, and it is
// paid on this host against arithmetic every system that computes agrees about. A target is asked only the cases
// the descent placed.
#include "../../../../src/engine/compiler/bootstrap/chain_build.h"
#include "../../../../src/engine/nbody/anchor_sift/anchor_sift.h"

#include <stdio.h>
#include <string.h>

#define GATE_NEEDLE_MOST (LADDER_CASE_COUNT + CHAIN_SWEEP)
// a descent places at most ANCHOR_STEER_ANCHORS cases, and resume chains descents until one places none
#define GATE_DESCENTS_MOST 16u

#define LADDER_TEXT(name_, text_, words_, measured_) text_,
static const char *const s_anchor_text[] = {LADDER_ANCHORS(LADDER_TEXT)};
#undef LADDER_TEXT

// what the oracle reads: the arrangements, every case put to them, and a count of the questions asked
typedef struct
{
    const ChainSet *arrangements;
    PreceptCase given[GATE_NEEDLE_MOST];
    unsigned int expected[GATE_NEEDLE_MOST];
    unsigned int cases;
    unsigned int ladder_cases;
    unsigned long long asked;
} GateField;

static ChainSet s_fitted;
static ChainSet s_swept;
static GateField s_gate;
static uint8_t s_survivors[CHAIN_MOST];
static uint8_t s_full_depth[CHAIN_MOST];
static uint8_t s_one_descent[CHAIN_MOST];

// whether arrangement (corpus_at - needle_at) gives case needle_at the word the relation gives it
static int gate_same_at(const void *field, size_t corpus_at, size_t needle_at)
{
    GateField *const gate = (GateField *)field;
    const Chain *const chain = &gate->arrangements->chain[corpus_at - needle_at];
    unsigned int answered = 0u;
    gate->asked += 1ull;
    if (precept_value(chain->node, chain->nodes, &gate->given[needle_at], &answered) == 0)
    {
        return 0;
    }
    return (answered == gate->expected[needle_at]) ? 1 : 0;
}

// whether arrangement `at` gives every case the word the relation gives it
static unsigned int gate_holds_every_case(const GateField *gate, unsigned int at)
{
    const Chain *const chain = &gate->arrangements->chain[at];
    for (unsigned int which = 0u; which < gate->cases; which += 1u)
    {
        unsigned int answered = 0u;
        if ((precept_value(chain->node, chain->nodes, &gate->given[which], &answered) == 0) ||
            (answered != gate->expected[which]))
        {
            return 0u;
        }
    }
    return 1u;
}

static unsigned int gate_standing(const uint8_t *survivors, unsigned int length)
{
    unsigned int standing = 0u;
    for (unsigned int at = 0u; at < length; at += 1u)
    {
        standing += (survivors[at] != 0u) ? 1u : 0u;
    }
    return standing;
}

// the ladder's cases for `anchor` into the field, then the words chain_build's sweep puts, from its own seed
static void gate_cases(unsigned int anchor)
{
    memset(&s_gate, 0, sizeof(s_gate));
    s_gate.arrangements = &s_fitted;
    for (unsigned int at = 0u; at < LADDER_CASE_COUNT; at += 1u)
    {
        if (s_ladder_cases[at].anchor == anchor)
        {
            PreceptCase *const given = &s_gate.given[s_gate.ladder_cases];
            given->operands = s_ladder_cases[at].words;
            memcpy(given->operand, s_ladder_cases[at].word, sizeof(unsigned int) * s_ladder_cases[at].words);
            s_gate.expected[s_gate.ladder_cases] = s_ladder_cases[at].expected;
            s_gate.ladder_cases += 1u;
        }
    }
    unsigned int state = 0x9e3779b9u + anchor;
    for (unsigned int at = 0u; at < CHAIN_SWEEP; at += 1u)
    {
        PreceptCase *const given = &s_gate.given[s_gate.ladder_cases + at];
        given->operands = 2u;
        given->operand[0] = ladder_swept(&state);
        given->operand[1] = ladder_swept(&state);
        ladder_answer(anchor, given->operand, 2u, &s_gate.expected[s_gate.ladder_cases + at]);
    }
    s_gate.cases = s_gate.ladder_cases + CHAIN_SWEEP;
}

// one relation measured; 1 where every reading agrees with its ground truth
static unsigned int gate_relation(unsigned int anchor, const LadderQuestion *cases, unsigned int found)
{
    chain_build_cases(&s_fitted, cases, found, 0);
    const unsigned int kept = chain_build_cases(&s_swept, cases, found, 1);
    gate_cases(anchor);
    const unsigned int alignments = s_fitted.chains;
    if (alignments == 0u)
    {
        printf("  %-8s no arrangement fits the ladder's cases, nothing to descend over\n", s_anchor_text[anchor]);
        return 1u;
    }

    unsigned int truth = 0u;
    for (unsigned int at = 0u; at < alignments; at += 1u)
    {
        truth += gate_holds_every_case(&s_gate, at);
    }

    const AnchorField field = {gate_same_at, &s_gate, alignments, s_gate.cases};
    size_t offsets[ANCHOR_STEER_ANCHORS];
    unsigned int placed = 0u;
    int resume = 0;
    s_gate.asked = 0ull;
    for (unsigned int descent = 0u; descent < GATE_DESCENTS_MOST; descent += 1u)
    {
        const size_t depth = ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent, .offsets = offsets,
                                               .count = ANCHOR_STEER_ANCHORS, .survivors = s_survivors,
                                               .survivors_length = alignments, .sample_stride = 1u, .any = &field,
                                               .resume = resume);
        for (size_t slot = 0u; slot < depth; slot += 1u)
        {
            const size_t at = offsets[slot];
            printf("  %-8s places case %3zu, %s: 0x%08x 0x%08x -> 0x%08x\n", s_anchor_text[anchor], at,
                   (at < s_gate.ladder_cases) ? "a ladder case" : "a sweep word ", s_gate.given[at].operand[0],
                   s_gate.given[at].operand[1], s_gate.expected[at]);
        }
        placed += (unsigned int)depth;
        resume = 1;
        if (depth == 0u)
        {
            break;
        }
    }
    const unsigned long long planned = s_gate.asked;

    // the find step: every arrangement still standing checked against every case
    unsigned int verified = 0u;
    unsigned int lost = 0u;
    for (unsigned int at = 0u; at < alignments; at += 1u)
    {
        const unsigned int holds = gate_holds_every_case(&s_gate, at);
        verified += ((s_survivors[at] != 0u) && (holds != 0u)) ? 1u : 0u;
        lost += ((s_survivors[at] == 0u) && (holds != 0u)) ? 1u : 0u;
    }

    ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent, .offsets = offsets,
                      .count = ANCHOR_STEER_ANCHORS, .survivors = s_one_descent, .survivors_length = alignments,
                      .sample_stride = 1u, .any = &field);
    ANCHOR_STEER_CALL(anchor_steer_spawn_coarms, AnchorSteerDescent, .offsets = offsets,
                      .count = ANCHOR_STEER_ANCHORS, .survivors = s_full_depth, .survivors_length = alignments,
                      .sample_stride = 1u, .any = &field, .force_full_depth = 1);
    const unsigned int stopped = gate_standing(s_one_descent, alignments);
    const unsigned int continued = gate_standing(s_full_depth, alignments);

    const unsigned int agreed = ((lost == 0u) && (verified == truth) && (truth == kept) && (stopped == continued)) ? 1u
                                                                                                                 : 0u;
    printf("  %-8s %4u fit the ladder, %4u hold every case, %4u kept by the sweep; %u case(s) placed, %4u standing, "
           "%4u verified, %u lost; stopped %u and full depth %u; %llu questions planned on this host; %s\n",
           s_anchor_text[anchor], alignments, truth, kept, placed, gate_standing(s_survivors, alignments), verified,
           lost, stopped, continued, planned, (agreed != 0u) ? "agrees" : "DISAGREES");
    return agreed;
}

int main(void)
{
    static LadderQuestion cases[LADDER_CASE_COUNT];
    unsigned int agreed = 1u;
    for (unsigned int anchor = 0u; anchor < (unsigned int)LADDER_ANCHOR_COUNT; anchor += 1u)
    {
        unsigned int found = 0u;
        for (unsigned int at = 0u; at < LADDER_CASE_COUNT; at += 1u)
        {
            if (s_ladder_cases[at].anchor == anchor)
            {
                cases[found] = s_ladder_cases[at];
                found += 1u;
            }
        }
        if ((found == 0u) || (s_ladder_measured[anchor] != 0))
        {
            continue;
        }
        agreed = gate_relation(anchor, cases, found) & agreed;
    }
    printf("\n  every relation: the descent's survivors are the ground truth, and stopping gives up nothing: %s\n",
           (agreed != 0u) ? "yes" : "NO");
    return (agreed != 0u) ? 0 : 1;
}
