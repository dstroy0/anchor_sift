// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef QUERY_INTERFACE_H
#define QUERY_INTERFACE_H

// Asks put from inside the interface, at addresses nothing has said are safe.
//
// An address that refuses a read or a put ends the process that asked, and from inside one process that ending is
// the last thing learned. The interface runs the asks in a probe it can lose: a walk of addresses goes to `query_walk`,
// which answers each address in turn until one ends it, and the ending is that address's answer. The walk is put
// again from the next address, in a fresh probe, until every address has an answer. Nothing is asked of a system
// about what lies at an address: the address is asked, and it answers, holds, reads as a word, advances or ends the
// asker.

#include "../interface/interface.h"
#include "query_ask.h"

// the most addresses one probe is given, which bounds the lines it writes back
#define QUERY_INTERFACE_MOST 1024ull

// one walk: the program it runs as, the file its probe writes to, the qualifier put at every address, the addresses,
// and how long a probe is given before the interface ends it
typedef struct
{
    // the built query_walk, and the file the interface has it write its lines to
    const char *program;
    const char *output_path;
    // a QueryQualifier, put at every address
    unsigned int qualifier;
    // the first address, how many, and the bytes between two
    unsigned long long from;
    unsigned long long count;
    unsigned long long stride;
    // how many reads ADVANCES puts at one address after its first before the address reads as not advancing
    unsigned long long turns;
    // the word QUERY_EQUALS compares against
    unsigned int word;
    // the most time one probe is given, 0 for no limit
    unsigned long long limit_microseconds;
} QueryWalk;

// `walk` put through the interface, one answer an address into `answers`, which holds `walk->count` of them. Every answer
// carries its address, its bit and its kind; an address that ended its probe reads QUERY_ENDED with the fault the
// interface named, and one whose probe ran out of time or exited on its own reads QUERY_ENDED with no fault. The count of probes the walk ran, or 0 with the error raised where the interface itself failed or a probe
// wrote something other than its lines
unsigned long long query_interface_walk(const QueryWalk *walk, QueryAsk *answers, EngineError *error);

#endif
