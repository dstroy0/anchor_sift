// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "tessera.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define NOMINMAX
#include <windows.h>
#else
#include <dlfcn.h>
#endif

#define TESSERA_SELF_ADAPTERS 16u
#define TESSERA_SELF_LOCAL_SEGMENTS 0
#define TESSERA_SELF_CORES 64u
#define TESSERA_SELF_KEPT_CORES 2ull

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

int tessera_device_names_host(const unsigned char device[TESSERA_DEVICE_BYTES])
{
    unsigned int named = 0u;
    for (unsigned int byte = 0u; byte < TESSERA_DEVICE_BYTES; byte += 1u)
    {
        named |= device[byte];
    }
    return named == 0u;
}

// each core's logical processors as one mask, the first sixty-four processors only; returns how many cores were read
static unsigned int tessera_self_cores(unsigned long long cores[TESSERA_SELF_CORES])
{
    unsigned int count = 0u;
#if defined(_WIN32)
    DWORD length = 0u;
    GetLogicalProcessorInformationEx(RelationProcessorCore, NULL, &length);
    unsigned char *const bytes = (length != 0u) ? (unsigned char *)malloc(length) : NULL;
    // the buffer is walked as the records it was filled with, each its own Size long
    if ((bytes == NULL)
        || !GetLogicalProcessorInformationEx(RelationProcessorCore, (SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX *)bytes,
                                             &length))
    {
        free(bytes);
        return 0u;
    }
    for (DWORD at = 0u; (at < length) && (count < TESSERA_SELF_CORES);)
    {
        // each record starts where the last one's Size ends
        const SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX *const core = (const SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX *)(bytes + at);
        if (core->Size == 0u)
        {
            break;
        }
        if ((core->Relationship == RelationProcessorCore) && (core->Processor.GroupMask[0].Group == 0u))
        {
            // a group's affinity is the machine word, which an unsigned long long holds whole
            cores[count] = (unsigned long long)core->Processor.GroupMask[0].Mask;
            count += 1u;
        }
        at += core->Size;
    }
    free(bytes);
#else
    for (unsigned int processor = 0u; (processor < TESSERA_SELF_CORES) && (count < TESSERA_SELF_CORES); processor += 1u)
    {
        char path[128];
        snprintf(path, sizeof(path), "/sys/devices/system/cpu/cpu%u/topology/thread_siblings", processor);
        FILE *const siblings = fopen(path, "r");
        if (siblings == NULL)
        {
            continue;
        }
        char line[256];
        const int read = fgets(line, sizeof(line), siblings) != NULL;
        fclose(siblings);
        // the mask is hex words split by commas, the highest processors first: shifting drops those past sixty-four
        unsigned long long mask = 0ull;
        for (const char *digit = line; read && (*digit != '\0'); digit += 1)
        {
            const int decimal = (*digit >= '0') && (*digit <= '9');
            const int lower = (*digit >= 'a') && (*digit <= 'f');
            if (decimal || lower)
            {
                // a hexadecimal digit's value is below sixteen
                mask = (mask << 4u) | (decimal ? (unsigned long long)(*digit - '0') : (unsigned long long)(*digit - 'a' + 10));
            }
        }
        int known = mask == 0ull;
        for (unsigned int at = 0u; !known && (at < count); at += 1u)
        {
            known = cores[at] == mask;
        }
        if (!known)
        {
            cores[count] = mask;
            count += 1u;
        }
    }
#endif
    return count;
}

unsigned long long tessera_self_host_mask(void)
{
    unsigned long long cores[TESSERA_SELF_CORES];
    const unsigned int count = tessera_self_cores(cores);
    if (count == 0u)
    {
        return 0ull;
    }
    unsigned long long kept = TESSERA_SELF_KEPT_CORES;
    const char *const named = getenv("TESSERA_HOST_KEPT_CORES");
    if ((named != NULL) && (named[0] != '\0'))
    {
        char *end = NULL;
        const unsigned long long value = strtoull(named, &end, 10);
        kept = (*end == '\0') ? value : kept;
    }
    // one core at least is always left to the jobs
    kept = (kept < count) ? kept : (count - 1u);
    unsigned long long mask = 0ull;
    for (unsigned int at = 0u; at < count; at += 1u)
    {
        mask |= cores[at];
    }
    // the kept cores are the last ones, by their lowest logical processor
    for (unsigned long long taken = 0ull; taken < kept; taken += 1ull)
    {
        unsigned int last = 0u;
        unsigned long long last_lowest = 0ull;
        for (unsigned int at = 0u; at < count; at += 1u)
        {
            const unsigned long long lowest = cores[at] & (~cores[at] + 1ull);
            if (lowest > last_lowest)
            {
                last = at;
                last_lowest = lowest;
            }
        }
        mask &= ~cores[last];
        cores[last] = 0ull;
    }
    return mask;
}
