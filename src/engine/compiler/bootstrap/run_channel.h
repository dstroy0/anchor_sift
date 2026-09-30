// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef RUN_CHANNEL_H
#define RUN_CHANNEL_H

// The run channel: words put at a part's address, the part started, words read back.
//
// This is the only way anything is learned about a part. A question is put as the part's own code, the part runs it,
// and a word comes back. Nothing here reads a name, a listing or a source: a container goes in and four words come
// out, and what those words are is the part's answer and no software's opinion of it.
//
// What carries the bytes is whatever holds the part's bus mapping. On a part behind a driver that is the driver,
// which for a load and a start does what the channel says it does: it writes the container into the part's memory
// over its address window and rings the register that starts it. It is reached by name and by its own entry points,
// and nothing of its vendor's toolchain is compiled against or asked anything. A translator is not transport: a
// thing that turns a source into a coding is the part of the loop being derived, and a run that went through one
// would be reading that translator's answer instead of the part's.
//
// A part whose bus is addressed without a driver is the same channel with a shorter carrier, and the interface does
// not move.

#define RUN_IN_WORDS 8u
#define RUN_OUT_WORDS 4u

// what a run came to
typedef enum
{
    // the words came back
    RUN_ANSWERED,
    // the part took the container and the words are what it left
    RUN_NOTHING,
    // the part would not take the container as it stands
    RUN_ILLEGAL,
    // nothing carried the bytes: no part, or no mapping to it
    RUN_NO_CHANNEL
} RunOutcome;

// one question and what came of it
typedef struct
{
    // the container, and its size
    const unsigned char *container;
    unsigned long long container_size;
    // the name the part is entered at
    const char *entry;
    // the words put in
    unsigned int word[RUN_IN_WORDS];
    // the words that came back
    unsigned int answered[RUN_OUT_WORDS];
    unsigned int outcome;
    // what the carrier said where the outcome is not RUN_ANSWERED
    char refused[128];
} RunQuestion;

// The channel opened on part `which`. 1, or 0 with the reason printed. A channel is opened once and every question
// after goes through it: opening costs more than a question does
int run_channel_open(int which);

// `asked` put and answered. 1 where the outcome is RUN_ANSWERED, 0 otherwise, with `asked->outcome` saying which
int run_channel_ask(RunQuestion *asked);

// the channel closed, and what it held given back
void run_channel_close(void);

// what the channel is carried by, for a run to say where its words came from
const char *run_channel_carrier(void);

#endif
