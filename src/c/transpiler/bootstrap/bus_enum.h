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

#endif
