// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// query_walk.c: the program a walk of asks runs as, inside the cell
//
//     query_walk <qualifier> <from> <count> <stride> <turns> <word>
//
// Every number is read as hexadecimal. The program puts one ask at each address from `from`, `stride` bytes apart,
// `count` of them, and writes one line an address as it is answered:
//
//     <address> <bit> <kind>
//
// A line is written out before the next address is asked. An address that ends the process ends it with every
// answer before it already written, and the cell reads where the walk stopped from the last line. `turns` is how
// many reads ADVANCES puts at an address after its first before the address reads as not advancing: a counter that
// steps once a clock interrupt reads as still between two reads far more often than not.
#include "query_ask.h"

#include <stdio.h>
#include <stdlib.h>

int main(int count_of_words, char **words)
{
    if (count_of_words != 7)
    {
        fprintf(stderr, "query_walk <qualifier> <from> <count> <stride> <turns> <word>, every number hexadecimal\n");
        return 2;
    }
    // each is read as hexadecimal and kept at the width the ask carries
    const unsigned int qualifier = (unsigned int)strtoul(words[1], NULL, 16);
    const unsigned long long from = strtoull(words[2], NULL, 16);
    const unsigned long long count = strtoull(words[3], NULL, 16);
    const unsigned long long stride = strtoull(words[4], NULL, 16);
    const unsigned long long turns = strtoull(words[5], NULL, 16);
    const unsigned int word = (unsigned int)strtoul(words[6], NULL, 16);

    // nothing waits in a buffer: a line is in the file before the next ask can end the process
    setvbuf(stdout, NULL, _IONBF, 0);
    for (unsigned long long number = 0ull; number < count; number += 1ull)
    {
        QueryAsk asked = {0};
        asked.address = from + (number * stride);
        asked.qualifier = qualifier;
        asked.word = word;
        asked.turns = turns;
        query_ask(&asked);
        printf("%llx %u %u\n", asked.address, asked.bit, asked.kind);
    }
    return 0;
}
