// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// chain_build.c: every arrangement of primitives that produces a relation
#include "chain_build.h"

#include <stdio.h>
#include <string.h>

// The precepts a chain is built from: the ones that carry a word and take a child. NOP carries no child, ERR says a
// thing cannot be done, and the two branches go nowhere a word comes back from
static const unsigned char s_chain_precepts[] = {PRECEPT_NOT, PRECEPT_AND, PRECEPT_OR,  PRECEPT_XOR, PRECEPT_NAND,
                                                 PRECEPT_NOR, PRECEPT_MOV, PRECEPT_SHL, PRECEPT_SHR, PRECEPT_ASR,
                                                 PRECEPT_ROL, PRECEPT_ROR, PRECEPT_ADD, PRECEPT_SUB};

#define CHAIN_PRECEPT_COUNT (sizeof(s_chain_precepts) / sizeof(s_chain_precepts[0]))

#define PRECEPT_TEXT(name_, text_, arity_) text_,
static const char *const s_precept_text[] = {PRECEPTS(PRECEPT_TEXT)};
#undef PRECEPT_TEXT

#define PRECEPT_ARITY(name_, text_, arity_) arity_,
static const unsigned int s_precept_arity[] = {PRECEPTS(PRECEPT_ARITY)};
#undef PRECEPT_ARITY

// what a node's children may be: the operands the cases carry, a word of zeroes, a word of ones, and the nodes
// before it. The two words are here because a rewrite reaches a complement and a mask through them and through
// nothing else the cases supply
#define CHAIN_SOURCES (PRECEPT_OPERANDS + 2u + CHAIN_NODES)

// what is being built, and what it is being built against. The walk carries one pointer
typedef struct
{
    ChainSet *set;
    const LadderQuestion *cases;
    unsigned int count;
    PreceptCase given[LADDER_CASE_COUNT];
    unsigned char source[CHAIN_SOURCES];
    unsigned int leaves;
    int swept;
    Chain building;
} ChainWork;

// the word the subtree rooted at node `at` produces for case `which`, through `answered`. A chain is written with
// every node before its parent. The nodes up to and including `at` are a tree in their own right, and the walk that
// reads a whole chain reads a node of one by being given a shorter count
static int chain_node_value(const ChainWork *work, unsigned int at, unsigned int which, unsigned int *answered)
{
    return precept_value(work->building.node, at + 1u, &work->given[which], answered);
}

// the word child `child` stands for in case `which`, through `answered`. 1, or 0 where it is a node whose own walk
// refused
static int chain_child_value(const ChainWork *work, unsigned char child, unsigned int which, unsigned int *answered)
{
    if (child >= PRECEPT_ARG)
    {
        *answered = (child == PRECEPT_NONE) ? 0u : precept_leaf(child, &work->given[which]);
        return 1;
    }
    return chain_node_value(work, child, which, answered);
}

// Whether node `at` changes anything. A node that answers what one of its children already answered, in every case
// the relation carries, is the chain without it at greater length, and that shorter chain was found first. Without
// this test a set fills with one working arrangement wrapped in moves
static int chain_node_idle(const ChainWork *work, unsigned int at)
{
    const unsigned char child[2] = {work->building.node[at].left, work->building.node[at].right};
    for (unsigned int which = 0u; which < 2u; which += 1u)
    {
        if (child[which] == PRECEPT_NONE)
        {
            continue;
        }
        unsigned int idle = 1u;
        for (unsigned int at_case = 0u; (at_case < work->count) && (idle != 0u); at_case += 1u)
        {
            unsigned int held = 0u;
            unsigned int stood = 0u;
            if ((chain_node_value(work, at, at_case, &held) == 0) ||
                (chain_child_value(work, child[which], at_case, &stood) == 0))
            {
                return 1;
            }
            idle = (held == stood) ? 1u : 0u;
        }
        if (idle != 0u)
        {
            return 1;
        }
    }
    return 0;
}

// whether every node before the root is read by a node after it. A node nothing reads is not part of the chain, and
// the chain without it was found at a shorter length
static int chain_whole(const Chain *chain)
{
    for (unsigned int at = 0u; (at + 1u) < chain->nodes; at += 1u)
    {
        unsigned int read = 0u;
        for (unsigned int later = at + 1u; later < chain->nodes; later += 1u)
        {
            read += ((chain->node[later].left == (unsigned char)at) || (chain->node[later].right == (unsigned char)at))
                        ? 1u
                        : 0u;
        }
        if (read == 0u)
        {
            return 0;
        }
    }
    return 1;
}

// whether the chain as it stands answers every case
static int chain_answers(const ChainWork *work)
{
    for (unsigned int at = 0u; at < work->count; at += 1u)
    {
        unsigned int answered = 0u;
        if (precept_value(work->building.node, work->building.nodes, &work->given[at], &answered) == 0)
        {
            return 0;
        }
        if (answered != work->cases[at].expected)
        {
            return 0;
        }
    }
    return 1;
}

// Whether the chain answers the relation on words the cases do not carry. A ladder's cases are its climbing order
// and are few and small; an arrangement right about those words and wrong about the rest passes them and comes back
// looking like a finding. The relation holds for every word there is and is asked for words the arrangement was
// never fitted to
static int chain_swept(const ChainWork *work)
{
    unsigned int state = 0x9e3779b9u + work->cases[0].anchor;
    for (unsigned int at = 0u; at < CHAIN_SWEEP; at += 1u)
    {
        PreceptCase given;
        memset(&given, 0, sizeof(given));
        given.operands = 2u;
        given.operand[0] = ladder_swept(&state);
        given.operand[1] = ladder_swept(&state);
        unsigned int wanted = 0u;
        unsigned int answered = 0u;
        if (ladder_answer(work->cases[0].anchor, given.operand, given.operands, &wanted) == 0)
        {
            return 0;
        }
        if (precept_value(work->building.node, work->building.nodes, &given, &answered) == 0)
        {
            return 0;
        }
        if (answered != wanted)
        {
            return 0;
        }
    }
    return 1;
}

// the chain as it stands put into the set, where it holds together and answers and there is room
static void chain_keep(ChainWork *work)
{
    work->set->tried += 1u;
    if (chain_whole(&work->building) == 0)
    {
        return;
    }
    if (chain_answers(work) == 0)
    {
        return;
    }
    for (unsigned int at = 0u; at < work->building.nodes; at += 1u)
    {
        if (chain_node_idle(work, at) != 0)
        {
            return;
        }
    }
    work->set->fitted += 1u;
    if ((work->swept != 0) && (chain_swept(work) == 0))
    {
        return;
    }
    if (work->set->chains == CHAIN_MOST)
    {
        work->set->over += 1u;
        return;
    }
    work->set->chain[work->set->chains] = work->building;
    work->set->chains += 1u;
}

// every arrangement of `nodes` nodes, filling node `at` and those after it
static void chain_walk(ChainWork *work, unsigned int nodes, unsigned int at)
{
    if (at == nodes)
    {
        chain_keep(work);
        return;
    }
    // the nodes before this one join the leaves as things it may read
    const unsigned int sources = work->leaves + at;
    for (unsigned int which = 0u; which < CHAIN_PRECEPT_COUNT; which += 1u)
    {
        const unsigned char precept = s_chain_precepts[which];
        work->building.node[at].precept = precept;
        for (unsigned int left = 0u; left < sources; left += 1u)
        {
            work->building.node[at].left =
                (left < work->leaves) ? work->source[left] : (unsigned char)(left - work->leaves);
            if (s_precept_arity[precept] == 1u)
            {
                work->building.node[at].right = PRECEPT_NONE;
                chain_walk(work, nodes, at + 1u);
                continue;
            }
            for (unsigned int right = 0u; right < sources; right += 1u)
            {
                work->building.node[at].right =
                    (right < work->leaves) ? work->source[right] : (unsigned char)(right - work->leaves);
                chain_walk(work, nodes, at + 1u);
            }
        }
    }
}

unsigned int chain_build(ChainSet *set, const LadderQuestion *cases, unsigned int count)
{
    return chain_build_cases(set, cases, count, 1);
}

unsigned int chain_build_cases(ChainSet *set, const LadderQuestion *cases, unsigned int count, int swept)
{
    memset(set, 0, sizeof(*set));
    if ((count == 0u) || (count > LADDER_CASE_COUNT))
    {
        return 0u;
    }
    // a measure's answer is a property of the system and follows from no arrangement of its words. Built for
    // anyway, every arrangement that lands on the one answer by accident comes back looking like a finding
    if (s_ladder_measured[cases[0].anchor] != 0)
    {
        return 0u;
    }
    static ChainWork work;
    memset(&work, 0, sizeof(work));
    work.set = set;
    work.cases = cases;
    work.count = count;
    work.swept = swept;
    unsigned int words = 0u;
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        words = (cases[at].words > words) ? cases[at].words : words;
        work.given[at].operands = cases[at].words;
        for (unsigned int word = 0u; word < cases[at].words; word += 1u)
        {
            work.given[at].operand[word] = cases[at].word[word];
        }
    }
    for (unsigned int word = 0u; word < words; word += 1u)
    {
        work.source[work.leaves] = PRECEPT_ARG_AT(word);
        work.leaves += 1u;
    }
    work.source[work.leaves] = PRECEPT_ZERO;
    work.leaves += 1u;
    work.source[work.leaves] = PRECEPT_ONES;
    work.leaves += 1u;
    // shortest first: a set that fills holds the shortest arrangements there are
    for (unsigned int nodes = 1u; nodes <= CHAIN_NODES; nodes += 1u)
    {
        work.building.nodes = nodes;
        chain_walk(&work, nodes, 0u);
    }
    return set->chains;
}

void chain_shuffle(ChainSet *set, unsigned int seed)
{
    // a zero state never leaves zero, and a seed is free to be one
    unsigned int state = (seed != 0u) ? seed : 0x9e3779b9u;
    for (unsigned int at = set->chains; at > 1u; at -= 1u)
    {
        const unsigned int with = ladder_swept(&state) % at;
        const Chain held = set->chain[at - 1u];
        set->chain[at - 1u] = set->chain[with];
        set->chain[with] = held;
    }
}

// the subtree rooted at `child` written into `text` from `at`; the place the next write starts
static unsigned int chain_child_text(const Chain *chain, unsigned char child, char *text, unsigned int room,
                                     unsigned int at)
{
    if (child == PRECEPT_ZERO)
    {
        return at + (unsigned int)snprintf(&text[at], room - at, "zero");
    }
    if (child == PRECEPT_ONES)
    {
        return at + (unsigned int)snprintf(&text[at], room - at, "ones");
    }
    if (child >= PRECEPT_ARG)
    {
        return at + (unsigned int)snprintf(&text[at], room - at, "w%u", (unsigned int)(child - PRECEPT_ARG));
    }
    const PreceptNode *const node = &chain->node[child];
    at += (unsigned int)snprintf(&text[at], room - at, "%s(", s_precept_text[node->precept]);
    at = chain_child_text(chain, node->left, text, room, at);
    if (node->right != PRECEPT_NONE)
    {
        at += (unsigned int)snprintf(&text[at], room - at, ", ");
        at = chain_child_text(chain, node->right, text, room, at);
    }
    return at + (unsigned int)snprintf(&text[at], room - at, ")");
}

unsigned int chain_text(const Chain *chain, char *text, unsigned int room)
{
    text[0] = '\0';
    if ((chain->nodes == 0u) || (room < 2u))
    {
        return 0u;
    }
    return chain_child_text(chain, (unsigned char)(chain->nodes - 1u), text, room, 0u);
}
