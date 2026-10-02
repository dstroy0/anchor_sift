// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// classify_walk.c: the program a classify walk runs as, inside a probe the interface can lose. It puts the kind ask
// at each address of a span and writes one line an address as it is answered:
//
//     classify_walk <from> <count> <stride>
//
// Every number is read as hexadecimal. A line is written before the next address is asked. An address that ends the
// process ends it with every line before it already written, and the interface reads where the walk stopped.
#include "host_entry.h"

#include <stdio.h>
#include <stdlib.h>

int main(int count_of_words, char **words)
{
    if (count_of_words != 4)
    {
        fprintf(stderr, "classify_walk <from> <count> <stride>, every number hexadecimal\n");
        return 2;
    }
    const unsigned long long from = strtoull(words[1], NULL, 16);
    const unsigned long long count = strtoull(words[2], NULL, 16);
    const unsigned long long stride = strtoull(words[3], NULL, 16);
    // nothing waits in a buffer: a line is in the file before the next ask can end the process
    setvbuf(stdout, NULL, _IONBF, 0);
    for (unsigned long long number = 0ull; number < count; number += 1ull)
    {
        const unsigned long long at = from + (number * stride);
        unsigned int read_back = 0u;
        const unsigned int kind = host_address_ask(at, &read_back);
        printf("%llx %x %x\n", at, kind, read_back);
    }
    return 0;
}
