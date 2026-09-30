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

// The anchors, the relations that fix each one, how many words a question of it carries, and whether its answer is
// a function of those words. The relations are written as cases and not as formulas, for one reason: a case is a
// thing a target can be asked, and a formula is not.
//
// The last column separates the two kinds of question on the ladder. A relation's answer follows from the words it
// was put with, the same way on every system that has the relation at all. A chain of primitives can be found for
// it and checked before any system is asked. A measure's answer follows from the system: how many places a word
// holds is true of the part and of nothing else, no chain produces it, and the only way to it is to ask. Handing a
// measure to a chain builder gets arrangements that hit the one answer by accident.
#define LADDER_ANCHORS(anchor_)                                                                                        \
    /* a word against itself. Says the channel carries an answer at all, and what this system answers with when */     \
    /* two things are the same. Required */                                                                            \
    anchor_(SAME, "same", 2u, 0)                                                                                       \
    /* how many places a word holds, counted by moving a one until it is gone */                                       \
    anchor_(PLACES, "places", 1u, 1)                                                                                   \
    /* 1,1 -> 2 and the rest of its cases. Required: nothing reaches it without a rank of gates for every place, */    \
    /* and the count of places is what PLACES measures */                                                              \
    anchor_(ADD, "add", 2u, 0)                                                                                         \
    /* 3,1 -> 2 */                                                                                                     \
    anchor_(TAKE, "take", 2u, 0)                                                                                       \
    /* 1,1 -> 2 as well, and 1,2 -> 4: a word moved toward the end it grows at */                                      \
    anchor_(UP, "up", 2u, 0)                                                                                           \
    /* 4,1 -> 2 */                                                                                                     \
    anchor_(DOWN, "down", 2u, 0)                                                                                       \
    /* 3,3 -> 9 */                                                                                                     \
    anchor_(PRODUCT, "product", 2u, 0)

#define LADDER_NAMED(name_, text_, words_, measured_) LADDER_##name_,

typedef enum
{
    LADDER_ANCHORS(LADDER_NAMED) LADDER_ANCHOR_COUNT
} LadderAnchor;

#undef LADDER_NAMED

#define LADDER_MEASURED(name_, text_, words_, measured_) measured_,

// whether each anchor's answer is a property of the system and not of the words it was put with
static const int s_ladder_measured[] = {LADDER_ANCHORS(LADDER_MEASURED)};

#undef LADDER_MEASURED

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

// The cases, in the order the ladder climbs. SAME first, because until something comes back there is no channel and
// no reading of what this system says for true; then how many places a word holds, which every case after is
// computed at; then ADD, the other required one; then the rest, each of them reachable from those two and asked
// anyway because a system that has it outright is spared the chain.
//
// A case is put in its own right and never in the order written here. Put in this order a part can answer the
// second from having seen the first, and an answer arrived at that way says nothing about whether the part holds
// the relation.
//
// True is written here as a word of ones and false as a word of zeroes. That is this compiler's anchor and not a
// claim about any system: SAME is asked precisely because what comes back may be a one, a sign bit, or a word this
// has never seen, and whatever comes back is what that system's true is from then on.
static const LadderQuestion s_ladder_cases[] = {
    {LADDER_SAME, {1u, 1u}, 2u, 0xffffffffu, 0u, 0},
    {LADDER_SAME, {0u, 0u}, 2u, 0xffffffffu, 0u, 0},
    {LADDER_SAME, {1u, 0u}, 2u, 0u, 0u, 0},
    {LADDER_SAME, {0u, 1u}, 2u, 0u, 0u, 0},
    {LADDER_SAME, {5u, 5u}, 2u, 0xffffffffu, 0u, 0},
    {LADDER_SAME, {5u, 7u}, 2u, 0u, 0u, 0},
    // two that differ at the end of the word a system may read a sign from, which an arrangement that spreads one
    // place across the word answers wrongly and the cases above let through
    {LADDER_SAME, {0x80000000u, 0u}, 2u, 0u, 0u, 0},
    {LADDER_SAME, {0xffffffffu, 0x7fffffffu}, 2u, 0u, 0u, 0},
    {LADDER_SAME, {0x80000000u, 0x80000000u}, 2u, 0xffffffffu, 0u, 0},
    // a one moved until it is gone. The answer is the count of places, and no arrangement of gates produces it from
    // the word it is given: it is measured by asking and not computed
    {LADDER_PLACES, {1u}, 1u, 32u, 0u, 0},
    {LADDER_ADD, {1u, 1u}, 2u, 2u, 0u, 0},
    {LADDER_ADD, {1u, 0u}, 2u, 1u, 0u, 0},
    {LADDER_ADD, {0u, 1u}, 2u, 1u, 0u, 0},
    {LADDER_ADD, {0u, 0u}, 2u, 0u, 0u, 0},
    {LADDER_ADD, {3u, 5u}, 2u, 8u, 0u, 0},
    {LADDER_ADD, {7u, 9u}, 2u, 16u, 0u, 0},
    // the two that say what this system does at the end of a word: one place past the largest, and the largest
    // added to itself
    {LADDER_ADD, {0xffffffffu, 1u}, 2u, 0u, 0u, 0},
    {LADDER_ADD, {0x7fffffffu, 1u}, 2u, 0x80000000u, 0u, 0},
    {LADDER_TAKE, {3u, 1u}, 2u, 2u, 0u, 0},
    {LADDER_TAKE, {1u, 1u}, 2u, 0u, 0u, 0},
    {LADDER_TAKE, {5u, 0u}, 2u, 5u, 0u, 0},
    {LADDER_TAKE, {9u, 7u}, 2u, 2u, 0u, 0},
    // one taken from nothing, which says what this system does at the other end of a word
    {LADDER_TAKE, {0u, 1u}, 2u, 0xffffffffu, 0u, 0},
    {LADDER_TAKE, {0x80000000u, 1u}, 2u, 0x7fffffffu, 0u, 0},
    {LADDER_UP, {1u, 1u}, 2u, 2u, 0u, 0},
    {LADDER_UP, {1u, 2u}, 2u, 4u, 0u, 0},
    {LADDER_UP, {1u, 0u}, 2u, 1u, 0u, 0},
    {LADDER_UP, {3u, 4u}, 2u, 48u, 0u, 0},
    {LADDER_UP, {0x80000000u, 1u}, 2u, 0u, 0u, 0},
    {LADDER_DOWN, {4u, 1u}, 2u, 2u, 0u, 0},
    {LADDER_DOWN, {8u, 3u}, 2u, 1u, 0u, 0},
    {LADDER_DOWN, {5u, 0u}, 2u, 5u, 0u, 0},
    {LADDER_DOWN, {0xffffffffu, 4u}, 2u, 0x0fffffffu, 0u, 0},
    {LADDER_PRODUCT, {3u, 3u}, 2u, 9u, 0u, 0},
    {LADDER_PRODUCT, {0u, 5u}, 2u, 0u, 0u, 0},
    {LADDER_PRODUCT, {1u, 7u}, 2u, 7u, 0u, 0},
    {LADDER_PRODUCT, {6u, 7u}, 2u, 42u, 0u, 0},
    {LADDER_PRODUCT, {11u, 13u}, 2u, 143u, 0u, 0},
};

#define LADDER_CASE_COUNT (sizeof(s_ladder_cases) / sizeof(s_ladder_cases[0]))

// What `anchor` answers for `words` of them, through `answered`. 1, or 0 for a measure, whose answer is the
// system's and follows from no words at all.
//
// The cases above are the order the ladder climbs and not the whole of a relation. A relation holds for every word
// there is, and this says so for any of them. An arrangement can then be checked past the few small words a ladder
// starts with. It is arithmetic and it runs wherever this is compiled: the compiler knows 1,1 -> 2 because whatever
// it is running on computes, and every system that computes at all agrees. Nothing about a target is learned here
// and no target is asked.
//
// A count for UP and DOWN is read from the low places of the second word, the way precept_value.h reads one. A
// chain and the relation it is checked against are then asked the same question.
static int ladder_answer(unsigned int anchor, const unsigned int *word, unsigned int words, unsigned int *answered)
{
    if (words < 2u)
    {
        return 0;
    }
    const unsigned int count = word[1] & (LADDER_PLACES_ASSUMED - 1u);
    switch (anchor)
    {
    case LADDER_SAME:
        *answered = (word[0] == word[1]) ? 0xffffffffu : 0u;
        return 1;
    case LADDER_ADD:
        *answered = word[0] + word[1];
        return 1;
    case LADDER_TAKE:
        *answered = word[0] - word[1];
        return 1;
    case LADDER_UP:
        *answered = (count == 0u) ? word[0] : (word[0] << count);
        return 1;
    case LADDER_DOWN:
        *answered = (count == 0u) ? word[0] : (word[0] >> count);
        return 1;
    case LADDER_PRODUCT:
        *answered = word[0] * word[1];
        return 1;
    default:
        return 0;
    }
}

// the words a sweep is put with, from a generator written here so the same words come back on every run and two
// runs of the builder hold the same chains
static unsigned int ladder_swept(unsigned int *state)
{
    *state ^= *state << 13;
    *state ^= *state >> 17;
    *state ^= *state << 5;
    return *state;
}

#endif
