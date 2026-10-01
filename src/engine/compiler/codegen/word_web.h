// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// word_web.h: the compiler's operations as trees over the alphabet
#ifndef WORD_WEB_H
#define WORD_WEB_H

#include "precepts.h"

// The word web, the layer above precepts.h. The language's alphabet web comes first, then the word web, and then the
// coherence the clock measures.
//
// A word is an operation the compiler decides in, written as the tree it is over the alphabet. The schema names 99
// of them and a ruleset gives each a line of the target's text. What neither one says is what the operation *is*,
// which leaves nothing able to tell whether a target's single instruction for a word is worth taking, or to write a
// word out for a target that lacks it. The tree says both:
//
//  - A target with no instruction for a word is given the word's tree, each node a precept it does have, and the
//    alphabet web writes out any precept it lacks as well. Nothing has to be hand written for a target twice.
//  - A word the target does have an instruction for is weighed against its own tree in the part's clock. Where the
//    instruction beats the tree it is a word of that target's language; where it does not, the target writes that
//    word out node by node, and the .kdm records which. That reading is the coherence, and the part gives it.
//
// A word's leaves are its operands by place, PRECEPT_ARG_AT(0) first, in the order the schema's form takes them
// after the destination. word_and's form is `word_and to left right`, putting left at place 0 and right at place 1.
// The destination is where the root lands and is never a leaf.
typedef struct
{
    const char *name;
    unsigned char reads;
    unsigned char nodes;
    PreceptNode node[12];
} Word;

// Every word here is a tree of fixed arity: its operands are all that reading it takes. That is a hard line and most
// of the schema falls on the other side of it. The absences are listed below in place of being left to be found.
//
// Not here, and not an omission:
//
//  - The declarations and the notes (declare_file, program_note, step_note, the lane's opening and close). These
//    name no operation and have no tree; they are the frame a lane is written into.
//  - The words over memory and over the launch (global_load, record_store, launch_load, count_add). A load is not a
//    gate and reduces to nothing in the alphabet: a target either reaches memory or does not.
//  - Every word whose tree counts the register's width. This is the larger half, and one missing node accounts for
//    all of it. An adder is a rank of gates per bit; a multiply is one adder per bit again; a rotate is a shift left by
//    the amount ORed with a shift right by the width less the amount; a sign spread is a carry right by the width
//    less one; a test against zero is the word ORed down to a single bit, taking as many ranks as the width has
//    powers of two. Each of those is a real tree and none of them is fixed arity, because the width sets the count
//    of nodes. A width-counted node is a second kind of node and is not designed yet. Writing any of these as a
//    fixed tree in the meantime would put a wrong tree in the web, and a wrong tree is worse than a missing one.
//    ADD and SUB are precepts for this same reason: they are where the fixed-arity trees stop.
//
// This table is the floor of the word web and not all of it. What it does hold, it holds exactly.
static const Word s_word_web[] = {
    // the gates, each its own precept and one node
    {"word_and", 2u, 1u, {{PRECEPT_AND, PRECEPT_ARG_AT(0u), PRECEPT_ARG_AT(1u)}}},
    {"word_or", 2u, 1u, {{PRECEPT_OR, PRECEPT_ARG_AT(0u), PRECEPT_ARG_AT(1u)}}},
    {"word_xor", 2u, 1u, {{PRECEPT_XOR, PRECEPT_ARG_AT(0u), PRECEPT_ARG_AT(1u)}}},
    // a copy
    {"word_copy", 1u, 1u, {{PRECEPT_MOV, PRECEPT_ARG_AT(0u), PRECEPT_NONE}}},
    // the two shifts, whose amount is an operand and needs no width
    {"word_shift_left", 2u, 1u, {{PRECEPT_SHL, PRECEPT_ARG_AT(0u), PRECEPT_ARG_AT(1u)}}},
    {"word_shift_right", 2u, 1u, {{PRECEPT_SHR, PRECEPT_ARG_AT(0u), PRECEPT_ARG_AT(1u)}}},
    // one limb of arithmetic, the precept itself with nothing around it. The carry chains running these over limbs are
    // width counted and are not here
    {"add_alone", 2u, 1u, {{PRECEPT_ADD, PRECEPT_ARG_AT(0u), PRECEPT_ARG_AT(1u)}}},
    {"subtract_alone", 2u, 1u, {{PRECEPT_SUB, PRECEPT_ARG_AT(0u), PRECEPT_ARG_AT(1u)}}},
    // gates over words that carry one bit, which need no width because there is only the one bit
    {"predicate_xor", 2u, 1u, {{PRECEPT_XOR, PRECEPT_ARG_AT(0u), PRECEPT_ARG_AT(1u)}}},
    {"predicate_and", 2u, 1u, {{PRECEPT_AND, PRECEPT_ARG_AT(0u), PRECEPT_ARG_AT(1u)}}},
    // the lane's branches. Every other branch the schema has - the error, the top of a loop, the next state - is one
    // of these two with a reason written around it, and none is a word of its own
    {"loop_back", 2u, 1u, {{PRECEPT_JCC, PRECEPT_ARG_AT(0u), PRECEPT_ARG_AT(1u)}}},
    {"error", 2u, 1u, {{PRECEPT_JCC, PRECEPT_ARG_AT(0u), PRECEPT_ARG_AT(1u)}}},
};

#define WORD_WEB_COUNT (sizeof(s_word_web) / sizeof(s_word_web[0]))

#endif
