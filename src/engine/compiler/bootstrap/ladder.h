// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef LADDER_H
#define LADDER_H

// What the compiler knows before it has met anything: relations.
//
// A relation is a tuple of words and the word that goes with them. 1,1 -> 2 is a relation. It is not an addition,
// because addition is a writing and this file holds none. Every system that computes at all agrees about 1,1 -> 2.
// Nothing else can be assumed about a system nobody has met. Arithmetic is the shared ground; the
// writing that reaches it is the part that differs, and finding that writing is the compiler's work.
//
// The names below are coherence anchors. That is all they are: they let the compiler say which relations it has
// found a writing for and compose them into larger ones. A target is never told a name and never asked about one.
//
// Two anchors are required. A system that holds IDENTITY and ADD can be given the rest: TAKE is ADD over a
// complement, PRODUCT is UP and ADD stacked, and the gates reach one another through rewrites. A system that holds
// neither cannot be spoken to.

// The anchors, the relations that fix each one, and how many words a question of it carries. The relations are
// written as cases and not as formulas, for one reason: a case is a thing a target can be asked, and a formula is
// not.
#define LADDER_ANCHORS(anchor_)                                                                                        \
    /* a word against itself. Says the channel carries an answer at all, and what this system answers with when */     \
    /* two things are the same. Required */                                                                            \
    anchor_(SAME, "same", 2u)                                                                                          \
    /* how many places a word holds, counted by moving a one until it is gone */                                       \
    anchor_(PLACES, "places", 1u)                                                                                      \
    /* 1,1 -> 2 and the rest of its cases. Required: nothing reaches it without a rank of gates for every place, */    \
    /* and the count of places is what PLACES measures */                                                              \
    anchor_(ADD, "add", 2u)                                                                                            \
    /* 3,1 -> 2 */                                                                                                     \
    anchor_(TAKE, "take", 2u)                                                                                          \
    /* 1,1 -> 2 as well, and 1,2 -> 4: a word moved toward the end it grows at */                                      \
    anchor_(UP, "up", 2u)                                                                                              \
    /* 4,1 -> 2 */                                                                                                     \
    anchor_(DOWN, "down", 2u)                                                                                          \
    /* 3,3 -> 9 */                                                                                                     \
    anchor_(PRODUCT, "product", 2u)

#define LADDER_NAMED(name_, text_, words_) LADDER_##name_,

typedef enum
{
    LADDER_ANCHORS(LADDER_NAMED) LADDER_ANCHOR_COUNT
} LadderAnchor;

#undef LADDER_NAMED

// the most words a question carries
#define LADDER_WORDS 4u

// One question: the words it is put with and the word that must come back. `anchor` is the compiler's own label for
// the relation and is never written into anything a target reads. `answered` is filled from what came back
typedef struct
{
    unsigned int anchor;
    unsigned int word[LADDER_WORDS];
    unsigned int words;
    unsigned int expected;
    unsigned int answered;
    int agreed;
} LadderQuestion;

// The width a relation is computed at before PLACES has come back. The first questions are put at this width and
// the answer to PLACES says whether the rest are put at another
#define LADDER_PLACES_ASSUMED 32u

#endif
