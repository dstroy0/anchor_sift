// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef BUS_ENUM_WALK_H
#define BUS_ENUM_WALK_H

// The classify walk driven over a span in probes the interface can lose, and the enumeration region read from the
// kinds it collects. `walk->program` is the classify_walk program; its from, count, stride, output_path and limit
// are used, the qualifier, turns and word ignored.
#include "bus_enum.h"
#include "query_interface.h"

// the kind of each address of the walk read into `kinds` (walk->count of them), an address that ends its probe a
// NOTHING, then the enumeration region read into `base`, `stride_out` and `records`. 1 where a region is found, 0
// where none is, -1 where the interface or a probe failed, with `error` set.
int bus_enum_walk(const QueryWalk *walk, unsigned int *kinds, unsigned long long *base, unsigned long long *stride_out,
                  unsigned long long *records, EngineError *error);

#endif
