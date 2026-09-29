// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// web_check.c: every tree of the alphabet web and the word web read once, and held to what a tree is. A node may
// reach only nodes below it, which is what makes the root reachable and keeps a tree from looping; a node's children
// must be as many as its precept takes; and a leaf must be an operand the word actually reads. None of this needs a
// device or a target: the webs are the compiler's own and are the same on every part
#include "word_web.h"

#include <stdio.h>

static const char *const s_precept_names[] = {
#define PRECEPT_TEXT(name_, text_, arity_) text_,
    PRECEPTS(PRECEPT_TEXT)
#undef PRECEPT_TEXT
};

static const unsigned char s_precept_arity[] = {
#define PRECEPT_ARITY(name_, text_, arity_) (unsigned char)(arity_),
    PRECEPTS(PRECEPT_ARITY)
#undef PRECEPT_ARITY
};

// every child of every node read once: a node number must lie below its own node, so the root is reachable and no
// tree loops, and a leaf must be an operand the word actually reads
static int checked(const char *what, const char *name, unsigned int reads, const PreceptNode *node, unsigned int nodes)
{
    int broken = 0;
    for (unsigned int at = 0u; at < nodes; at += 1u)
    {
        const unsigned int arity = s_precept_arity[node[at].precept];
        const unsigned char child[2] = {node[at].left, node[at].right};
        for (unsigned int side = 0u; side < 2u; side += 1u)
        {
            const unsigned char one = child[side];
            if (side >= arity)
            {
                if (one != PRECEPT_NONE)
                {
                    printf("  %s %s node %u: %s takes %u, and the other child is not none\n", what, name, at,
                           s_precept_names[node[at].precept], arity);
                    broken = 1;
                }
                continue;
            }
            if (one == PRECEPT_NONE)
            {
                printf("  %s %s node %u: %s takes %u and one child is none\n", what, name, at,
                       s_precept_names[node[at].precept], arity);
                broken = 1;
            }
            else if (one < PRECEPT_ARG)
            {
                if (one >= at)
                {
                    printf("  %s %s node %u reaches node %u, which is not below it\n", what, name, at, one);
                    broken = 1;
                }
            }
            else if ((one != PRECEPT_ZERO) && (one != PRECEPT_ONES) && ((one - PRECEPT_ARG) >= reads))
            {
                printf("  %s %s node %u reads operand %u of %u\n", what, name, at, one - PRECEPT_ARG, reads);
                broken = 1;
            }
        }
    }
    return broken;
}

int main(void)
{
    unsigned int broken = 0u;
    for (unsigned int at = 0u; at < PRECEPT_WEB_COUNT; at += 1u)
    {
        const PreceptRewrite *const one = &s_precept_web[at];
        broken += checked("precept", s_precept_names[one->precept], s_precept_arity[one->precept], one->node,
                          one->nodes)
                      ? 1u
                      : 0u;
    }
    for (unsigned int at = 0u; at < WORD_WEB_COUNT; at += 1u)
    {
        const Word *const one = &s_word_web[at];
        broken += checked("word", one->name, one->reads, one->node, one->nodes) ? 1u : 0u;
    }
    printf("%u precepts, %u of them written as a tree over the others, %u words: %u broken\n",
           (unsigned int)PRECEPT_COUNT, (unsigned int)PRECEPT_WEB_COUNT, (unsigned int)WORD_WEB_COUNT, broken);
    return (broken == 0u) ? 0 : 1;
}
