// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// bus_enum.c: the enumeration region found in a run of kinds, a FIXED identifier beside a LIVE sizing register
// recurring at one stride. The stride is the smallest gap between record starts, and every gap is held to a whole
// multiple of it, which lets an empty slot sit in the lattice without hiding the stride.
#include "bus_enum.h"

// 1 where the sample at `at` begins a record: a FIXED identifier with a LIVE sizing register in the next sample
static int bus_enum_record(const unsigned int *kinds, unsigned long long count, unsigned long long at)
{
    return (((at + 1ull) < count) && (kinds[at] == HOST_FIXED) && (kinds[at + 1ull] == HOST_LIVE)) ? 1 : 0;
}

int bus_enum_find(const unsigned int *kinds, unsigned long long count, unsigned long long *base,
                  unsigned long long *stride, unsigned long long *records)
{
    unsigned long long heads = 0ull;
    unsigned long long first = 0ull;
    unsigned long long previous = 0ull;
    unsigned long long step = 0ull;
    for (unsigned long long at = 0ull; at < count; at += 1ull)
    {
        if (bus_enum_record(kinds, count, at) == 0)
        {
            continue;
        }
        if (heads != 0ull)
        {
            const unsigned long long gap = at - previous;
            step = ((step == 0ull) || (gap < step)) ? gap : step;
        }
        else
        {
            first = at;
        }
        previous = at;
        heads += 1ull;
    }
    if ((heads < 2ull) || (step == 0ull))
    {
        return 0;
    }
    previous = first;
    for (unsigned long long at = first + 1ull; at < count; at += 1ull)
    {
        if (bus_enum_record(kinds, count, at) == 0)
        {
            continue;
        }
        if (((at - previous) % step) != 0ull)
        {
            return 0;
        }
        previous = at;
    }
    *base = first;
    *stride = step;
    *records = heads;
    return 1;
}

unsigned long long bus_enum_list(const unsigned int *kinds, const unsigned int *values, unsigned long long count,
                                 BusRecord *out, unsigned long long most)
{
    unsigned long long base = 0ull;
    unsigned long long stride = 0ull;
    unsigned long long records = 0ull;
    if (bus_enum_find(kinds, count, &base, &stride, &records) == 0)
    {
        return 0ull;
    }
    unsigned long long written = 0ull;
    for (unsigned long long at = base; (at < count) && (written < most); at += stride)
    {
        if (bus_enum_record(kinds, count, at) == 0)
        {
            continue;
        }
        out[written].sample = at;
        out[written].identifier = values[at];
        out[written].width = host_width(values[at + 1ull]);
        written += 1ull;
    }
    return written;
}
