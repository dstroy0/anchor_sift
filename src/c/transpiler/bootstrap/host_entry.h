// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef HOST_ENTRY_H
#define HOST_ENTRY_H

// How a host is reached. Two relations.
//
//   put   a word at an address
//   read  a word at an address
//
// A store and a load. There is nothing under them and nothing between them and the part: no system is asked for
// permission, no library is called, and no header of anybody's is included. This file includes nothing at all. A
// compiler that has to be given an address and a word can be given them anywhere.
//
// A bus is any bus because a bus is these two. A window at an address is one writing of them, a serial line
// clocking bits is another, a fabric's aperture a third; each is a few stores and loads at the addresses that drive
// it, and each is found the same way as anything else here.
//
// What is on the bus is not a third relation. It is these two put to the bus's own addresses: read the word a part
// answers with, and read nothing where no part answers. Asking a system what it carries gets that system's opinion
// of what it carries, which puts a third party in the loop, and its opinion is not the part's answer. The bus says
// what is on it because the bus is asked.
//
// What an entry is not is a translator. A thing that turns a source into a coding is the part of the loop being
// derived, and a word that went through one is that translator's answer and not the host's.

// how wide a word is here. Every address is a word's worth apart, and how many places a word actually holds is a
// thing the part is asked and not a thing this decides
#define HOST_WORD 4u

// A read that comes back all ones is what a line gives a reader when nothing drove it: every wire floats and reads
// high. It is not a word a part said
#define HOST_NO_ANSWER 0xffffffffu

// the two words an address is put. They share no bits: an address fixed at either is then told from one that holds
#define HOST_ASKED_FIRST 0xa5a5a5a5u
#define HOST_ASKED_THEN 0x5a5a5a5au

// what an address turned out to be, once put words and read back
typedef enum
{
    // gave back every word it was given
    HOST_HOLDS,
    // gave back the same word whatever it was given
    HOST_FIXED,
    // gave back something else: something behind it decided the answer
    HOST_LIVE,
    // gave back nothing a reader here can tell from nothing
    HOST_NOTHING
} HostAddressKind;

// `word` put at `at`
static inline void host_put(unsigned long long at, unsigned int word)
{
    *(volatile unsigned int *)(unsigned long long)at = word;
}

// the word at `at`
static inline unsigned int host_read(unsigned long long at)
{
    return *(volatile unsigned int *)(unsigned long long)at;
}

// What the address at `at` turns out to be, through `read_back` holding what came back last. What was there first is
// put back before this returns, since an address that holds may be something the part is using
static inline unsigned int host_address_ask(unsigned long long at, unsigned int *read_back)
{
    const unsigned int held = host_read(at);
    host_put(at, HOST_ASKED_FIRST);
    const unsigned int first = host_read(at);
    host_put(at, HOST_ASKED_THEN);
    const unsigned int then = host_read(at);
    host_put(at, held);
    *read_back = then;
    if ((first == HOST_ASKED_FIRST) && (then == HOST_ASKED_THEN))
    {
        return HOST_HOLDS;
    }
    if ((first == HOST_NO_ANSWER) && (then == HOST_NO_ANSWER))
    {
        return HOST_NOTHING;
    }
    if (first == then)
    {
        return HOST_FIXED;
    }
    // it moved, and not to what it was given: something behind the address decided the answer
    return HOST_LIVE;
}

// whether a part answers at `at`: a word comes back that is not the word a line gives when nothing drove it
static inline int host_answers(unsigned long long at)
{
    return (host_read(at) != HOST_NO_ANSWER) ? 1 : 0;
}

#endif
