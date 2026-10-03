// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// gate_descent.c: the gate run as the engine's own sift descent, against every arrangement asked every case
//
// The gate decides which arrangements hold a relation. Here it is the descent orior already runs over any
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
//   asks        how many asks a target takes for every arrangement against those cases, by what one answer carries
//
// The planning reads every case against every survivor at each level. That is the price of choosing well, and it is
// paid on this host against arithmetic every system that computes agrees about. A target is asked only the cases
// the descent placed.
#include "../../../../../../src/c/transpiler/bootstrap/chain_build.h"
#include "../../../../../../src/c/transpiler/bootstrap/run_channel.h"
#include "../../../../../../src/c/engine/nbody/orior/orior.h"

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

// asks a set of checks takes when one bit answers whether every check in it holds and a 0 halves the set
static unsigned long long gate_split_asks(const unsigned char *checks, unsigned int first, unsigned int count)
{
    unsigned int every = 1u;
    for (unsigned int at = first; at < (first + count); at += 1u)
    {
        every &= checks[at];
    }
    if ((every != 0u) || (count == 1u))
    {
        return 1ull;
    }
    const unsigned int half = count / 2u;
    return 1ull + gate_split_asks(checks, first, half) + gate_split_asks(checks, first + half, count - half);
}

// How many asks a target takes for every arrangement against every case placed, by what one answer carries. One check
// an ask; one bit a check, as many as the channel's answer words hold; and one bit over a set, 1 where every check in
// it holds, halved on a 0. The last is also counted with the checks in an order drawn from a seed, because how the
// failing checks sit together changes what halving costs
static void gate_asks(unsigned int anchor, unsigned int alignments, const size_t *chosen, unsigned int placed)
{
    static unsigned char s_checks[CHAIN_MOST * GATE_DESCENTS_MOST * ANCHOR_STEER_ANCHORS];
    unsigned int checks = 0u;
    unsigned int failing = 0u;
    for (unsigned int arrangement = 0u; arrangement < alignments; arrangement += 1u)
    {
        for (unsigned int at = 0u; at < placed; at += 1u)
        {
            const size_t needle_at = chosen[at];
            // the oracle takes the arrangement as corpus_at - needle_at, and its answer is 0 or 1
            s_checks[checks] = (unsigned char)gate_same_at(&s_gate, (size_t)arrangement + needle_at, needle_at);
            failing += (s_checks[checks] == 0u) ? 1u : 0u;
            checks += 1u;
        }
    }
    if (checks == 0u)
    {
        return;
    }
    const unsigned int bits = RUN_OUT_WORDS * 32u;
    const unsigned long long halved = gate_split_asks(s_checks, 0u, checks);
    unsigned int state = 0x51a7u;
    for (unsigned int at = checks; at > 1u; at -= 1u)
    {
        const unsigned int with = ladder_swept(&state) % at;
        const unsigned char held = s_checks[at - 1u];
        s_checks[at - 1u] = s_checks[with];
        s_checks[with] = held;
    }
    const unsigned long long drawn = gate_split_asks(s_checks, 0u, checks);
    printf("  %-8s %4u checks, %u failing: %4u asks at one a check, %u at one bit a check (%u bits an answer), %llu "
           "at one bit a set halved on a 0, %llu with the checks in a drawn order\n",
           s_anchor_text[anchor], checks, failing, checks, (checks + bits - 1u) / bits, bits, halved, drawn);
}

// the folder a target's half is written to, or NULL where none was named
static const char *s_put_folder;

// What a target is asked for `anchor`, written to s_put_folder where one was named: <anchor>.kdm, every arrangement the
// descent ran over as a row of a .kdm with the descent's verdict last, 1 standing and 0 out, and <anchor>_cases.txt,
// the cases it placed, a line each as the two words and the word the relation gives them. A target that runs every
// arrangement over the placed cases alone leaves standing what the descent leaves standing
static void gate_put(unsigned int anchor, unsigned int alignments, const size_t *chosen, unsigned int placed)
{
    if (s_put_folder == NULL)
    {
        return;
    }
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.kdm", s_put_folder, s_anchor_text[anchor]);
    FILE *const rows = fopen(path, "wb");
    snprintf(path, sizeof(path), "%s/%s_cases.txt", s_put_folder, s_anchor_text[anchor]);
    FILE *const cases = fopen(path, "wb");
    if ((rows == NULL) || (cases == NULL))
    {
        printf("  %-8s the target's half was not written to %s\n", s_anchor_text[anchor], s_put_folder);
        return;
    }
    for (unsigned int at = 0u; at < alignments; at += 1u)
    {
        char text[256];
        chain_text(&s_fitted.chain[at], text, sizeof(text));
        fprintf(rows, "%s\t%u\t%s\t-\t0\t%u\n", s_anchor_text[anchor], s_fitted.chain[at].nodes, text,
                (s_survivors[at] != 0u) ? 1u : 0u);
    }
    for (unsigned int at = 0u; at < placed; at += 1u)
    {
        const size_t which = chosen[at];
        fprintf(cases, "%08x %08x %08x\n", s_gate.given[which].operand[0], s_gate.given[which].operand[1],
                s_gate.expected[which]);
    }
    fclose(rows);
    fclose(cases);
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
    size_t chosen[GATE_DESCENTS_MOST * ANCHOR_STEER_ANCHORS];
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
            chosen[placed + slot] = at;
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
    gate_put(anchor, alignments, chosen, placed);
    printf("  %-8s %4u fit the ladder, %4u hold every case, %4u kept by the sweep; %u case(s) placed, %4u standing, "
           "%4u verified, %u lost; stopped %u and full depth %u; %llu questions planned on this host; %s\n",
           s_anchor_text[anchor], alignments, truth, kept, placed, gate_standing(s_survivors, alignments), verified,
           lost, stopped, continued, planned, (agreed != 0u) ? "agrees" : "DISAGREES");
    gate_asks(anchor, alignments, chosen, placed);
    return agreed;
}

// Given a folder, each relation's arrangements, the descent's verdict on each and the cases it placed are written there
// for a target to be asked (gate_put)
int main(int count, char **words)
{
    s_put_folder = (count > 1) ? words[1] : NULL;
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
