// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// query_cell.c: a walk of asks put from inside the cell, every ending kept as the answer of the address that caused it
#include "query_cell.h"

#include <stdio.h>
#include <stdlib.h>

#define QUERY_CELL_CHECK(condition_, evacaddr_, error_, kind_)                                                         \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_CELL, (unsigned int)__LINE__, (const void *)(evacaddr_),   \
                       (error_))

// one line is an address, a bit and a kind, at most 16 + 1 + 10 + 1 + 10 + 1 characters; this holds every line of
// the most addresses a child is given
#define QUERY_CELL_LINE 48ull
static char s_query_cell_lines[(QUERY_CELL_MOST * QUERY_CELL_LINE) + 1ull];

// The lines a child wrote, read into `answers` from `next` on. How many it answered in order; a line out of order,
// past the addresses it was given, or not three numbers ends the read where it stands
static unsigned long long query_cell_read(const QueryWalk *walk, unsigned long long next, unsigned long long given,
                                          QueryAsk *answers)
{
    unsigned long long read = 0ull;
    char *at = s_query_cell_lines;
    while (read < given)
    {
        char *end = NULL;
        const unsigned long long address = strtoull(at, &end, 16);
        if (end == at)
        {
            break;
        }
        at = end;
        // a bit and a kind are each one small number, kept at the width of the fields that hold them
        const unsigned int bit = (unsigned int)strtoul(at, &end, 10);
        if (end == at)
        {
            break;
        }
        at = end;
        // as above
        const unsigned int kind = (unsigned int)strtoul(at, &end, 10);
        if ((end == at) || (address != (walk->from + ((next + read) * walk->stride))))
        {
            break;
        }
        at = end;
        QueryAsk *const answer = &answers[next + read];
        answer->address = address;
        answer->qualifier = walk->qualifier;
        answer->word = walk->word;
        answer->bit = bit;
        answer->kind = kind;
        answer->fault = 0u;
        read += 1ull;
    }
    return read;
}

unsigned long long query_cell_walk(const QueryWalk *walk, QueryAsk *answers, EngineError *error)
{
    unsigned long long children = 0ull;
    unsigned long long next = 0ull;
    while (next < walk->count)
    {
        const unsigned long long left = walk->count - next;
        const unsigned long long given = (left < QUERY_CELL_MOST) ? left : QUERY_CELL_MOST;
        char qualifier[24];
        char from[24];
        char count[24];
        char stride[24];
        char turns[24];
        char word[24];
        snprintf(qualifier, sizeof(qualifier), "%x", walk->qualifier);
        snprintf(from, sizeof(from), "%llx", walk->from + (next * walk->stride));
        snprintf(count, sizeof(count), "%llx", given);
        snprintf(stride, sizeof(stride), "%llx", walk->stride);
        snprintf(turns, sizeof(turns), "%llx", walk->turns);
        snprintf(word, sizeof(word), "%x", walk->word);
        // the cell's command is a list of words it does not write to; the cast only meets its declared type
        char *const command[] = {(char *)walk->program, qualifier, from, count, stride, turns, word, NULL};
        const CellProbe probe = {command, walk->output_path, walk->limit_microseconds};
        CellAnswer answer = {0};
        answer.output = s_query_cell_lines;
        answer.output_capacity = sizeof(s_query_cell_lines);
        if (cell_probe_run(&probe, &answer, error) != 0L)
        {
            return 0ull;
        }
        children += 1ull;
        if (!QUERY_CELL_CHECK(answer.ending != CELL_ENDING_NOT_STARTED, walk, error, ENGINE_ERROR_RESOURCE))
        {
            return 0ull;
        }
        const unsigned long long read = query_cell_read(walk, next, given, answers);
        next += read;
        if ((answer.ending == CELL_ENDING_EXITED) && (answer.code == 0ull))
        {
            // a child that exited clean answered every address it was given, or it wrote something else
            if (!QUERY_CELL_CHECK(read == given, walk, error, ENGINE_ERROR_LOGIC))
            {
                return 0ull;
            }
            continue;
        }
        // the child ended at the address after its last line: that address is answered by the ending
        QueryAsk *const ended = &answers[next];
        ended->address = walk->from + (next * walk->stride);
        ended->qualifier = walk->qualifier;
        ended->word = walk->word;
        ended->bit = 0u;
        ended->kind = QUERY_ENDED;
        ended->fault = (unsigned int)answer.fault;
        next += 1ull;
    }
    return children;
}
