// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// web_check.c: every tree of the alphabet web and the word web read once, and held to what a tree is. A node may
// reach only nodes below it, which is what makes the root reachable and keeps a tree from looping; a node's children
// must be as many as its precept takes; and a leaf must be an operand the word actually reads. None of this needs a
// device or a target: the webs are the compiler's own and are the same on every part
#include "tree_number.h"
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

// A node list written out in prefix order as one number, and read back as a node list again. The walk is the tree's
// own: a node writes its symbol, then each child in turn, a child that is a leaf writing one symbol and a child that
// is a node walking into it. `place` carries how many symbols have been written, and the reading below runs the same
// walk against the number to build the list again
static void tree_number_write(const PreceptNode *node, unsigned int at, unsigned int arity_of[],
                              unsigned long long *number, unsigned int *place)
{
    *number = tree_written(*number, *place, node[at].precept);
    *place += 1u;
    const unsigned char child[2] = {node[at].left, node[at].right};
    for (unsigned int side = 0u; side < arity_of[node[at].precept]; side += 1u)
    {
        if (child[side] < PRECEPT_ARG)
        {
            tree_number_write(node, child[side], arity_of, number, place);
        }
        else
        {
            const unsigned int leaf = (child[side] == PRECEPT_ZERO)   ? TREE_LEAF_ZERO
                                      : (child[side] == PRECEPT_ONES) ? TREE_LEAF_ONES
                                                                      : TREE_LEAF_AT(child[side] - PRECEPT_ARG);
            *number = tree_written(*number, *place, leaf);
            *place += 1u;
        }
    }
}

// the same number read back into a node list, and the node it built returned. `place` walks the number's symbols and
// `made` counts the nodes put down, so the list comes out in the same order the writer walked
static unsigned char tree_number_read(unsigned long long number, unsigned int arity_of[], PreceptNode *node,
                                      unsigned int *place, unsigned int *made)
{
    const unsigned int symbol = tree_symbol(number, *place);
    *place += 1u;
    if (symbol >= (unsigned int)PRECEPT_COUNT)
    {
        const unsigned int leaf = symbol - (unsigned int)PRECEPT_COUNT;
        return (unsigned char)((leaf == 4u)   ? PRECEPT_ZERO
                               : (leaf == 5u) ? PRECEPT_ONES
                                              : PRECEPT_ARG_AT(leaf));
    }
    unsigned char child[2] = {PRECEPT_NONE, PRECEPT_NONE};
    for (unsigned int side = 0u; side < arity_of[symbol]; side += 1u)
    {
        child[side] = tree_number_read(number, arity_of, node, place, made);
    }
    const unsigned int mine = *made;
    node[mine].precept = (unsigned char)symbol;
    node[mine].left = child[0];
    node[mine].right = child[1];
    *made += 1u;
    return (unsigned char)mine;
}

// two trees walked together from a node of each: 1 where they are the same tree, whatever number each node sits at
// in its own list
static int tree_same(const PreceptNode *one, unsigned char at_one, const PreceptNode *other, unsigned char at_other,
                     unsigned int arity_of[])
{
    // a leaf is the same leaf or it is not, and a leaf never matches a node
    if ((at_one >= PRECEPT_ARG) || (at_other >= PRECEPT_ARG))
    {
        return at_one == at_other;
    }
    if (one[at_one].precept != other[at_other].precept)
    {
        return 0;
    }
    const unsigned char child_one[2] = {one[at_one].left, one[at_one].right};
    const unsigned char child_other[2] = {other[at_other].left, other[at_other].right};
    for (unsigned int side = 0u; side < arity_of[one[at_one].precept]; side += 1u)
    {
        if (!tree_same(one, child_one[side], other, child_other[side], arity_of))
        {
            return 0;
        }
    }
    return 1;
}

// one tree put through a number and back, and held to what it was. 0 where it came back the same
static int numbered(const char *what, const char *name, const PreceptNode *node, unsigned int nodes)
{
    unsigned int arity_of[256];
    for (unsigned int at = 0u; at < 256u; at += 1u)
    {
        arity_of[at] = 0u;
    }
    for (unsigned int at = 0u; at < (unsigned int)PRECEPT_COUNT; at += 1u)
    {
        arity_of[at] = s_precept_arity[at];
    }
    unsigned long long number = 0ull;
    unsigned int place = 0u;
    tree_number_write(node, nodes - 1u, arity_of, &number, &place);
    if (place > TREE_PLACES)
    {
        printf("  %s %s takes %u places, past the %u a number holds\n", what, name, place, TREE_PLACES);
        return 1;
    }
    PreceptNode again[16];
    unsigned int read_place = 0u;
    unsigned int made = 0u;
    const unsigned char root = tree_number_read(number, arity_of, again, &read_place, &made);
    if (made != nodes)
    {
        printf("  %s %s went out as %u nodes and came back as %u\n", what, name, nodes, made);
        return 1;
    }
    // the two walked together from their roots. Comparing the lists place by place would be wrong: which number a
    // node sits at is the list's business and not the tree's, and a tree read back comes out numbered in the order
    // its subtrees finish. That the lists differ and the trees do not is the redundancy the number does without
    if (!tree_same(node, nodes - 1u, again, root, arity_of))
    {
        printf("  %s %s came back a different tree\n", what, name);
        return 1;
    }
    return 0;
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
    // and every one of them out through a number and back. A tree that survives this is a tree the node list is
    // carrying no more of than the number does, which is what says the lists can go
    unsigned int numbers = 0u;
    unsigned int listed = 0u;
    for (unsigned int at = 0u; at < PRECEPT_WEB_COUNT; at += 1u)
    {
        const PreceptRewrite *const one = &s_precept_web[at];
        broken += numbered("precept", s_precept_names[one->precept], one->node, one->nodes) ? 1u : 0u;
        listed += one->nodes;
        numbers += 1u;
    }
    for (unsigned int at = 0u; at < WORD_WEB_COUNT; at += 1u)
    {
        const Word *const one = &s_word_web[at];
        broken += numbered("word", one->name, one->node, one->nodes) ? 1u : 0u;
        listed += one->nodes;
        numbers += 1u;
    }
    printf("%u precepts, %u of them written as a tree over the others, %u words: %u broken\n",
           (unsigned int)PRECEPT_COUNT, (unsigned int)PRECEPT_WEB_COUNT, (unsigned int)WORD_WEB_COUNT, broken);
    printf("%u trees through a number and back, %u nodes between them, %u symbols a digit, %u places to an unsigned "
           "long long: %u bytes of node list carry what %u bytes of number do\n",
           numbers, listed, TREE_SYMBOLS, TREE_PLACES, (unsigned int)(listed * sizeof(PreceptNode)),
           (unsigned int)(numbers * sizeof(unsigned long long)));
    return (broken == 0u) ? 0 : 1;
}
