// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// bus_enum_walk.c: the classify walk run over a span in probes the interface can lose, the kinds collected and the
// enumeration region read from them. An address that ends its probe answered nothing, and the walk goes on from the
// next address in a fresh probe.
#include "bus_enum_walk.h"

#include <stdio.h>
#include <stdlib.h>

// the most letters a line an address takes: a 16-letter address, a kind, a read-back word, two spaces and a newline
#define BUS_ENUM_WALK_LINE 48ull
static char s_bus_enum_walk_lines[(QUERY_INTERFACE_MOST * BUS_ENUM_WALK_LINE) + 1ull];

#define BUS_ENUM_WALK_CHECK(condition_, evacaddr_, error_, kind_)                                                       \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_INTERFACE, (unsigned int)__LINE__,                          \
                       (const void *)(evacaddr_), (error_))

// the kinds a probe wrote, read into `kinds` from `next` on. How many it answered in order; a line out of order, past
// the addresses it was given, or not three numbers ends the read where it stands
static unsigned long long bus_enum_walk_read(const QueryWalk *walk, unsigned long long next, unsigned long long given,
                                             unsigned int *kinds)
{
    unsigned long long read = 0ull;
    char *at = s_bus_enum_walk_lines;
    while (read < given)
    {
        char *end = NULL;
        const unsigned long long address = strtoull(at, &end, 16);
        if (end == at)
        {
            break;
        }
        at = end;
        const unsigned long kind = strtoul(at, &end, 16);
        if (end == at)
        {
            break;
        }
        at = end;
        // the read-back word, read past
        strtoul(at, &end, 16);
        if (end == at)
        {
            break;
        }
        at = end;
        if (address != (walk->from + ((next + read) * walk->stride)))
        {
            break;
        }
        kinds[next + read] = (unsigned int)kind;
        read += 1ull;
    }
    return read;
}

int bus_enum_walk(const QueryWalk *walk, unsigned int *kinds, unsigned long long *base, unsigned long long *stride_out,
                  unsigned long long *records, EngineError *error)
{
    unsigned long long next = 0ull;
    while (next < walk->count)
    {
        const unsigned long long left = walk->count - next;
        const unsigned long long given = (left < QUERY_INTERFACE_MOST) ? left : QUERY_INTERFACE_MOST;
        char from[24];
        char count[24];
        char stride[24];
        snprintf(from, sizeof(from), "%llx", walk->from + (next * walk->stride));
        snprintf(count, sizeof(count), "%llx", given);
        snprintf(stride, sizeof(stride), "%llx", walk->stride);
        // the interface's command is a list of words it does not write to; the cast only meets its declared type
        char *const command[] = {(char *)walk->program, from, count, stride, NULL};
        const InterfaceProbe probe = {command, walk->output_path, walk->limit_microseconds};
        InterfaceAnswer answer = {0};
        answer.output = s_bus_enum_walk_lines;
        answer.output_capacity = sizeof(s_bus_enum_walk_lines);
        if (interface_probe_run(&probe, &answer, error) != 0L)
        {
            return -1;
        }
        if (!BUS_ENUM_WALK_CHECK(answer.ending != INTERFACE_ENDING_NOT_STARTED, walk, error, ENGINE_ERROR_RESOURCE))
        {
            return -1;
        }
        const unsigned long long read = bus_enum_walk_read(walk, next, given, kinds);
        next += read;
        if ((answer.ending == INTERFACE_ENDING_EXITED) && (answer.code == 0ull))
        {
            // a probe that exited clean answered every address it was given
            if (!BUS_ENUM_WALK_CHECK(read == given, walk, error, ENGINE_ERROR_LOGIC))
            {
                return -1;
            }
            continue;
        }
        // the address that ended the probe is answered by the ending: nothing on the part drove it
        kinds[next] = HOST_NOTHING;
        next += 1ull;
    }
    return bus_enum_find(kinds, walk->count, base, stride_out, records);
}
