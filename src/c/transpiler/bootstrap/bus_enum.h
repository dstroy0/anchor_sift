// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef BUS_ENUM_H
#define BUS_ENUM_H

// The enumeration region in a run of kinds a classify walk read, one kind a sampled address (`host_entry.h`). A
// record is a FIXED identifier with a LIVE sizing register next to it. Records recur at one stride over the region,
// an empty slot left as a gap that is a whole multiple of the stride. This is found with no address written in: the
// region is named by how the parts answered, not by where a standard says they lie.
#include "host_entry.h"

// 1 where a region of two or more records is found: its first record's sample into `base`, the samples between one
// record's start and the next into `stride`, the records counted into `records`. 0 where none is, the outputs left.
int bus_enum_find(const unsigned int *kinds, unsigned long long count, unsigned long long *base,
                  unsigned long long *stride, unsigned long long *records);

// one enumerated record: the sample it begins at, the identifier its FIXED register holds, and the address bits its
// LIVE sizing register decodes
typedef struct
{
    unsigned long long sample;
    unsigned int identifier;
    unsigned int width;
} BusRecord;

// the records of a found region read into `out`, which holds `most`: for each record the FIXED identifier's value and
// the LIVE sizing register's width, from the values a walk captured one a sample. `values[s]` is the FIXED register's
// constant at a FIXED sample and the sizing register's all-ones mask at a LIVE sample. The records written, or 0
// where no region is found; an empty slot on the stride is passed over.
unsigned long long bus_enum_list(const unsigned int *kinds, const unsigned int *values, unsigned long long count,
                                 BusRecord *out, unsigned long long most);

#endif
