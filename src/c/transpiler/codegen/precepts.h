// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// precepts.h: the alphabet every operation is defined in
#ifndef PRECEPTS_H
#define PRECEPTS_H

// The alphabet. Storing ops as a binary tree of primitives is the most lightweight you can make a language. The floor
// of universal operations, and what every math function is built out of, are quoted whole in
// src/engine_plan.md under The precepts; this file is that floor written down.
//
// Every operation the compiler decides is a binary tree whose leaves are operands and whose nodes are the precepts
// below. Nothing here comes apart further: each is a gate, a wire or a branch, and a target that lacks one of these
// lacks the means to be compiled to at all. Everything above this file - a multiply, a divide, a comparison, a
// carry chain - is a tree over these and carries no new primitive. A target's ruleset says which subtrees it has a
// single instruction for; the clock says which of those are worth taking. The alphabet itself is ours and no
// target's: it is the irreducible set, and a part is never asked whether it agrees with it.
//
// The arity is how many children a node takes. No precept takes three, and the tree is binary for that reason.
#define PRECEPTS(precept_)                                                                                             \
    /* the two the metalanguage needs before any gate: nothing to do, and cannot be done */                            \
    precept_(NOP, "nop", 0u)                                                                                           \
    precept_(ERR, "err", 0u)                                                                                           \
    /* the gates. NAND and NOR are each a tree over NOT and AND or OR, and are precepts anyway because a part that    \
       builds from them builds everything from them, which two nodes apiece would hide */                              \
    precept_(NOT, "not", 1u)                                                                                           \
    precept_(AND, "and", 2u)                                                                                           \
    precept_(OR, "or", 2u)                                                                                             \
    precept_(XOR, "xor", 2u)                                                                                           \
    precept_(NAND, "nand", 2u)                                                                                         \
    precept_(NOR, "nor", 2u)                                                                                           \
    /* the wires: a copy, and the four ways a word is moved along itself. ASR carries the sign in, ROL and ROR carry \
       the bit that left back in the other end */                                                                      \
    precept_(MOV, "mov", 1u)                                                                                           \
    precept_(SHL, "shl", 2u)                                                                                           \
    precept_(SHR, "shr", 2u)                                                                                           \
    precept_(ASR, "asr", 2u)                                                                                           \
    precept_(ROL, "rol", 2u)                                                                                           \
    precept_(ROR, "ror", 2u)                                                                                           \
    /* the one arithmetic node. A subtract is an add of the negation and is a precept anyway, since a compare is a   \
       subtract whose difference is thrown away and every part has one */                                              \
    precept_(ADD, "add", 2u)                                                                                           \
    precept_(SUB, "sub", 2u)                                                                                           \
    /* the two branches, and no others. Every reason a lane branches - an error, the top of a loop, the next state - \
       is a tree over these two and not a precept of its own */                                                        \
    precept_(BRA, "bra", 1u)                                                                                           \
    precept_(JCC, "jcc", 2u)

#define PRECEPT_NAMED(name_, text_, arity_) PRECEPT_##name_,

enum Precept
{
    PRECEPTS(PRECEPT_NAMED) PRECEPT_COUNT
};

// A child of a node is another node of the same tree, by its number, or a leaf. A tree's nodes are numbered from 0
// and its root is its last. A child below PRECEPT_ARG reads as a node and one at or above it as a leaf. The leaves
// are the operands the tree was given, by their place, and the two words a rewrite needs that no operand carries: a
// word of zeroes and a word of ones
#define PRECEPT_ARG 0xf0u
#define PRECEPT_ARG_AT(place_) ((unsigned char)(PRECEPT_ARG + (place_)))
#define PRECEPT_ZERO 0xfeu
#define PRECEPT_ONES 0xffu
// a node whose precept takes one child leaves the other here
#define PRECEPT_NONE 0xfdu
// the first two operands, which is every precept's own arity and how the alphabet web below reads
#define PRECEPT_LEFT PRECEPT_ARG_AT(0u)
#define PRECEPT_RIGHT PRECEPT_ARG_AT(1u)

typedef struct
{
    unsigned char precept;
    unsigned char left;
    unsigned char right;
} PreceptNode;

// One precept written as a tree over the others: what a target that lacks it is given instead. These rewrites are
// the difference between a web and a list. Every gate reaches every other gate, a part that answers yes to NAND
// alone can still be compiled to, and a part that answers yes to XOR is spared the three nodes XOR costs from NAND.
//
// The web is walked, never assumed: which of these a target has is a question the probes put to it, and a rewrite is
// taken only where the answer was no. The rewrites run both ways by design - NOT is written from NAND and NAND from
// NOT - which bounds the walk by what the target answered and never by the order written here.
typedef struct
{
    unsigned char precept;
    unsigned char nodes;
    PreceptNode node[8];
} PreceptRewrite;

// What this does not yet hold is the edge of the design, not an omission: ADD and SUB over gates. An adder is a rank
// of gates per bit, and its size is the register's width where a rewrite below has a fixed count of nodes. A
// width-counted rewrite is a second kind of node and is not decided. Every rewrite below is fixed arity and reads
// without a width
static const PreceptRewrite s_precept_web[] = {
    // NOT a = a NAND a
    {PRECEPT_NOT, 1u, {{PRECEPT_NAND, PRECEPT_LEFT, PRECEPT_LEFT}}},
    // a NAND b = NOT (a AND b)
    {PRECEPT_NAND, 2u, {{PRECEPT_AND, PRECEPT_LEFT, PRECEPT_RIGHT}, {PRECEPT_NOT, 0u, PRECEPT_NONE}}},
    // a NOR b = NOT (a OR b)
    {PRECEPT_NOR, 2u, {{PRECEPT_OR, PRECEPT_LEFT, PRECEPT_RIGHT}, {PRECEPT_NOT, 0u, PRECEPT_NONE}}},
    // a AND b = NOT (a NAND b)
    {PRECEPT_AND, 2u, {{PRECEPT_NAND, PRECEPT_LEFT, PRECEPT_RIGHT}, {PRECEPT_NOT, 0u, PRECEPT_NONE}}},
    // a OR b = (NOT a) NAND (NOT b)
    {PRECEPT_OR,
     3u,
     {{PRECEPT_NOT, PRECEPT_LEFT, PRECEPT_NONE},
      {PRECEPT_NOT, PRECEPT_RIGHT, PRECEPT_NONE},
      {PRECEPT_NAND, 0u, 1u}}},
    // a XOR b = (a AND NOT b) OR (NOT a AND b)
    {PRECEPT_XOR,
     5u,
     {{PRECEPT_NOT, PRECEPT_RIGHT, PRECEPT_NONE},
      {PRECEPT_AND, PRECEPT_LEFT, 0u},
      {PRECEPT_NOT, PRECEPT_LEFT, PRECEPT_NONE},
      {PRECEPT_AND, 2u, PRECEPT_RIGHT},
      {PRECEPT_OR, 1u, 3u}}},
    // MOV a = a OR a, the cheapest node that reads one word and writes it back unchanged
    {PRECEPT_MOV, 1u, {{PRECEPT_OR, PRECEPT_LEFT, PRECEPT_LEFT}}},
    // a SUB b = NOT ((NOT a) ADD b). The plainer reading of a subtraction is a plus the complement of b plus one,
    // and the one is a word no leaf here carries: a rewrite has a word of zeroes and a word of ones and reaching a
    // single set bit from either takes a shift by the width, the width-counted node this file does not
    // have. Complementing the other side instead needs no constant at all. ~(~a + b) is -(~a + b) - 1 against ~a of
    // -a - 1, leaving a - b with the same three nodes on every width
    {PRECEPT_SUB,
     3u,
     {{PRECEPT_NOT, PRECEPT_LEFT, PRECEPT_NONE},
      {PRECEPT_ADD, 0u, PRECEPT_RIGHT},
      {PRECEPT_NOT, 1u, PRECEPT_NONE}}},
    // BRA to a label is a JCC whose condition never fails
    {PRECEPT_BRA, 1u, {{PRECEPT_JCC, PRECEPT_ONES, PRECEPT_LEFT}}},
};

#define PRECEPT_WEB_COUNT (sizeof(s_precept_web) / sizeof(s_precept_web[0]))

#endif
