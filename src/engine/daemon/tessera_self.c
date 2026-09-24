// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "tessera.h"

#include <stdio.h>
#include <string.h>

#if !defined(_WIN32)
#include <dlfcn.h>
#endif

#define TESSERA_SELF_ADAPTERS 16u
#define TESSERA_SELF_LOCAL_SEGMENTS 0

// dxcore's kernel-mode thunks, laid out as d3dkmthk.h lays them
typedef struct
{
    unsigned int low;
    int high;
} TesseraKmtLuid;

typedef struct
{
    unsigned int adapter;
    TesseraKmtLuid luid;
    unsigned int sources;
    int precise_present_regions;
} TesseraKmtAdapter;

typedef struct
{
    unsigned int count;
    TesseraKmtAdapter *adapters;
} TesseraKmtAdapters;

typedef struct
{
    void *process;
    unsigned int adapter;
    int segment_group;
    unsigned long long budget;
    unsigned long long usage;
    unsigned long long reservation;
    unsigned long long available;
    unsigned int physical_adapter;
} TesseraKmtVideoMemory;

typedef int (*TesseraKmtEnumerate)(TesseraKmtAdapters *adapters);
typedef int (*TesseraKmtQuery)(TesseraKmtVideoMemory *memory);

int tessera_self_paravirtual(void)
{
#if defined(_WIN32)
    return 0;
#else
    // WSL runs the device through the Windows driver: its NVML lists no process's memory, and its dxg driver answers
    // a process only about itself
    char release[256];
    FILE *const kernel = fopen("/proc/sys/kernel/osrelease", "r");
    const int read = (kernel != NULL) && (fgets(release, sizeof(release), kernel) != NULL);
    if (kernel != NULL)
    {
        fclose(kernel);
    }
    return read && ((strstr(release, "microsoft") != NULL) || (strstr(release, "WSL") != NULL));
#endif
}

int tessera_self_measure(unsigned long long luid, unsigned long long *used)
{
    *used = 0ull;
#if defined(_WIN32)
    (void)luid;
    return 0;
#else
    // the calling process's dedicated bytes on the adapter: the one whose LUID is given, or the only one there is
    void *library = dlopen("libdxcore.so", RTLD_NOW);
    library = (library != NULL) ? library : dlopen("/usr/lib/wsl/lib/libdxcore.so", RTLD_NOW);
    if (library == NULL)
    {
        return 0;
    }
    // each symbol is converted back to the type it was exported with
    const TesseraKmtEnumerate enumerate = (TesseraKmtEnumerate)dlsym(library, "D3DKMTEnumAdapters2");
    // each symbol is converted back to the type it was exported with
    const TesseraKmtQuery query = (TesseraKmtQuery)dlsym(library, "D3DKMTQueryVideoMemoryInfo");
    TesseraKmtAdapter adapters[TESSERA_SELF_ADAPTERS];
    memset(adapters, 0, sizeof(adapters));
    TesseraKmtAdapters listed = {TESSERA_SELF_ADAPTERS, adapters};
    int good = (enumerate != NULL) && (query != NULL) && (enumerate(&listed) == 0) && (listed.count != 0u);
    int chosen = -1;
    for (unsigned int at = 0u; good && (at < listed.count); at += 1u)
    {
        // the LUID's high part is a signed long whose bits form the upper word
        const unsigned long long named = ((unsigned long long)(unsigned int)adapters[at].luid.high << 32u)
                                       | adapters[at].luid.low;
        // an adapter index below sixteen fits an int
        chosen = ((luid != 0ull) && (named == luid)) ? (int)at : chosen;
    }
    chosen = ((chosen < 0) && (luid == 0ull) && (listed.count == 1u)) ? 0 : chosen;
    good = good && (chosen >= 0);
    if (good)
    {
        TesseraKmtVideoMemory memory;
        memset(&memory, 0, sizeof(memory));
        memory.process = NULL;
        memory.adapter = adapters[chosen].adapter;
        memory.segment_group = TESSERA_SELF_LOCAL_SEGMENTS;
        good = query(&memory) == 0;
        *used = good ? memory.usage : 0ull;
    }
    dlclose(library);
    return good;
#endif
}
