// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cycle_sweep.cu: the key sweep's kernels
#include "cycle_internal.h"

unsigned long long cycle_reflect(long long position, long long length)
{
    if ((position >= 0ll) && (position < length))
    {
        return (unsigned long long)position;
    }
    if ((position < 0ll) && (position >= -length))
    {
        return (unsigned long long)(-1ll - position);
    }
    if ((position >= length) && (position < (2ll * length)))
    {
        return (unsigned long long)((2ll * length) - 1ll - position);
    }
    const long long period = 2ll * length;
    long long folded = position % period;
    if (folded < 0ll)
    {
        folded += period;
    }
    if (folded >= length)
    {
        folded = period - 1ll - folded;
    }
    return (unsigned long long)folded;
}
