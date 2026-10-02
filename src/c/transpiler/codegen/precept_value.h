// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef PRECEPT_VALUE_H
#define PRECEPT_VALUE_H

// A tree over the alphabet applied to words. This is a tree saying what a target should answer.
//
// Nothing here knows a language. A word of the web is a tree of precepts (word_web.h), and a precept is a gate, a
// wire or a shift whose meaning is fixed everywhere. Walking the tree over a case of operands gives the word the
// target must produce if it holds that word at all. The target is then asked and the two are compared. Where they
// agree the target has a word for that tree, and where they differ it does not. No person states the answer.
//
// This is the half of the derivation that needs no target. A form carries an operation's name and the kind of each
// operand and says nothing about what the operation means. A name therefore cannot be matched to a word. Running
// can: where an operand of a form is a truth table of eight bits, sweep its 256 values and keep whichever answers
// as the tree does, and the target's word for that tree is found with nobody naming the value.

#include "precepts.h"

// the widths a case is run at. A word is 32 bits here, as every ruleset's word bank is
#define PRECEPT_WORD_BITS 32u
#define PRECEPT_WORD_MASK 0xffffffffu
// the most operands a case carries, and the most nodes a tree holds, the Word's own count (word_web.h)
#define PRECEPT_OPERANDS 8u
#define PRECEPT_NODES 12u

// one case: the operands a tree is applied to, by their place
typedef struct
{
    unsigned int operand[PRECEPT_OPERANDS];
    unsigned int operands;
} PreceptCase;

// the word `leaf` stands for: an operand by its place, a word of zeroes, or a word of ones
static unsigned int precept_leaf(unsigned char leaf, const PreceptCase *given)
{
    if (leaf == PRECEPT_ZERO)
    {
        return 0u;
    }
    if (leaf == PRECEPT_ONES)
    {
        return PRECEPT_WORD_MASK;
    }
    const unsigned int place = (unsigned int)(leaf - PRECEPT_ARG);
    return (place < given->operands) ? given->operand[place] : 0u;
}

// `precept` applied to two words. A shift takes its count from the low bits of the right word, as every part this
// has been asked of does, and a count at or past the width answers zero in place of leaving it to the language
static unsigned int precept_applied(unsigned char precept, unsigned int left, unsigned int right)
{
    const unsigned int count = right & (PRECEPT_WORD_BITS - 1u);
    switch (precept)
    {
    case PRECEPT_NOP:
        return left;
    case PRECEPT_NOT:
        return (~left) & PRECEPT_WORD_MASK;
    case PRECEPT_AND:
        return left & right;
    case PRECEPT_OR:
        return left | right;
    case PRECEPT_XOR:
        return left ^ right;
    case PRECEPT_NAND:
        return (~(left & right)) & PRECEPT_WORD_MASK;
    case PRECEPT_NOR:
        return (~(left | right)) & PRECEPT_WORD_MASK;
    case PRECEPT_MOV:
        return left;
    case PRECEPT_SHL:
        return (count == 0u) ? left : ((left << count) & PRECEPT_WORD_MASK);
    case PRECEPT_SHR:
        return (count == 0u) ? left : (left >> count);
    case PRECEPT_ASR:
        // the sign spread by hand, since C leaves a signed right shift to the implementation
        return (count == 0u) ? left
                             : (((left >> count) |
                                 (((left & 0x80000000u) != 0u) ? (PRECEPT_WORD_MASK << (PRECEPT_WORD_BITS - count))
                                                               : 0u)) &
                                PRECEPT_WORD_MASK);
    case PRECEPT_ROL:
        return (count == 0u) ? left : (((left << count) | (left >> (PRECEPT_WORD_BITS - count))) & PRECEPT_WORD_MASK);
    case PRECEPT_ROR:
        return (count == 0u) ? left : (((left >> count) | (left << (PRECEPT_WORD_BITS - count))) & PRECEPT_WORD_MASK);
    case PRECEPT_ADD:
        return (left + right) & PRECEPT_WORD_MASK;
    case PRECEPT_SUB:
        return (left - right) & PRECEPT_WORD_MASK;
    default:
        // ERR, BRA and JCC carry no word: a tree holding one answers nothing and is never matched by running
        return 0u;
    }
}

// The word `nodes` of `node` produce for `given`, with the root the last node, through `answered`. 1, or 0 where a
// node names a child past the nodes before it or a precept that carries no word
static int precept_value(const PreceptNode *node, unsigned int nodes, const PreceptCase *given, unsigned int *answered)
{
    unsigned int held[PRECEPT_NODES];
    if ((nodes == 0u) || (nodes > PRECEPT_NODES))
    {
        return 0;
    }
    for (unsigned int at = 0u; at < nodes; at += 1u)
    {
        const unsigned char precept = node[at].precept;
        if ((precept == PRECEPT_ERR) || (precept == PRECEPT_BRA) || (precept == PRECEPT_JCC))
        {
            return 0;
        }
        unsigned int side[2];
        const unsigned char child[2] = {node[at].left, node[at].right};
        for (unsigned int which = 0u; which < 2u; which += 1u)
        {
            if (child[which] >= PRECEPT_ARG)
            {
                side[which] = (child[which] == PRECEPT_NONE) ? 0u : precept_leaf(child[which], given);
                continue;
            }
            // a child below the argument mark is a node, and a tree is written with every node before its parent
            if (child[which] >= at)
            {
                return 0;
            }
            side[which] = held[child[which]];
        }
        held[at] = precept_applied(precept, side[0], side[1]);
    }
    *answered = held[nodes - 1u];
    return 1;
}

#endif
