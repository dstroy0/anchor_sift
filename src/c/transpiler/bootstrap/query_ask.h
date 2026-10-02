// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef QUERY_ASK_H
#define QUERY_ASK_H

// One ask of the query protocol: an address, a qualifier put to it, the cost of the answer, and a bit.
//
//     [ ADDRESS ] -> ( QUALIFIER ) -> [ MEASURED COST ] -> BINARY RESULT (1 or 0)
//
// Everything is learned this way and through nothing else. An ask is made of the two relations host_entry.h holds,
// a word put at an address and a word read at one, and of nothing between them and the part: no library is called
// and no system is asked. The qualifier asks for a state and never for a payload, and the answer to it is a bit.
//
// The cost is read off a clock, and a clock is an address too: a word that advances each time it is read is a
// counter, and the protocol finds one by asking the ADVANCES qualifier of an address. Nothing here assumes where one
// is. An ask given no clock reads its answer and reports its cost unread.
//
// An ask is put twice. Unbound, it returns the cost and no verdict. Bound, it returns 1 where the qualifier holds and
// the cost came in under the bound, and 0 otherwise; a qualifier that does not hold and a cost past the bound both
// read 0, and the kind says which.
//
// An address that refuses a read ends whatever read it. An ask put to an address nothing has said is safe is put
// from inside a cell, where an ending is the answer and the asker goes on.

#include "host_entry.h"

// what an ask asks of its address
typedef enum
{
    // given two words that share no bits, the address gives each back: it holds what it is given
    QUERY_HOLDS,
    // the word read at the address is the word the ask carries
    QUERY_EQUALS,
    // a later read of the address, inside `turns` reads, gives a word past the first, read as unsigned: it counts
    QUERY_ADVANCES
} QueryQualifier;

// what came of an ask
typedef enum
{
    // the qualifier held, and where a bound was given, inside it
    QUERY_HELD,
    // the qualifier did not hold
    QUERY_NOT_HELD,
    // the qualifier held, and the cost came in past the bound
    QUERY_PAST_BOUND,
    // the process the ask was put from ended before it answered, and the ending is the answer: `fault` says how
    QUERY_ENDED
} QueryKind;

// one ask, and what came back
typedef struct
{
    // where it is put
    unsigned long long address;
    // what is asked there, a QueryQualifier
    unsigned int qualifier;
    // the word QUERY_EQUALS compares against; unread by the other qualifiers
    unsigned int word;
    // the most reads QUERY_ADVANCES puts after its first before the address reads as not advancing, 0 or 1 for one;
    // unread by the other qualifiers
    unsigned long long turns;
    // the address of a counter found by QUERY_ADVANCES, or 0 for none: the cost is then unread
    unsigned long long clock;
    // 0 puts the ask unbound and returns its cost; any other value is the most the answer may cost
    unsigned long long bound;

    // the bit: 1 where the qualifier held inside the bound, 0 otherwise
    unsigned int bit;
    // what came of it, a QueryKind
    unsigned int kind;
    // the clock's advance across the ask, in the clock's own counts; 0 where no clock was given
    unsigned long long cost;
    // 1 where a clock was given and read
    unsigned int cost_read;
    // the rule the ending named where the kind is QUERY_ENDED, a InterfaceFault; 0 otherwise
    unsigned int fault;
} QueryAsk;

// `asked` put to its address. The bit, which is also written into `asked`
unsigned int query_ask(QueryAsk *asked);

#endif
