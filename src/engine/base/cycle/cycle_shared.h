// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef CYCLE_SHARED_H
#define CYCLE_SHARED_H

// What the record machine's files share: the headers, the checks and the record a program is held as. The
// machine is cut into its functional chunks: cycle.cu the key sweep, cycle_record.cu the record interpreter
// and the record calls, cycle_operators.cu the prelude and operator block NVRTC compiles, and cycle_compile.cu
// NVRTC, nvJitLink, the cache and a program compiled. A kernel stays in the file that launches it

#include "cycle.h"

// the CRC that seals a program's block, and the signum that names its program
#include "../crc.h"
#include "obsignatio.h"

// the emitter, which writes a program's lane as PTX or C source for the target named here, and the launch it reads
#include "../emit/emit_ptx.h"
#include "../emit/emit_source.h"

#include <cooperative_groups.h>
#include <cuda_runtime.h>
// NVRTC's and nvJitLink's prototypes only: both libraries are loaded at run time, and a build links nothing more
#include <nvJitLink.h>
#include <nvrtc.h>

#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <chrono>
#include <initializer_list>
#include <string>
#include <vector>

#if defined(_WIN32)
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <direct.h>
#include <process.h>
#include <windows.h>
#else
#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>
#endif

#define CYCLE_BLOCK 256u

static_assert(sizeof(unsigned int) == 4u, "cycle: unsigned int must be 32 bits, a limb");
static_assert(sizeof(unsigned long long) == 8u, "cycle: unsigned long long must be 64 bits, a limb product");

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

// cudaError_t enumerates non-negative codes below INT_MAX, so the status converts to int exactly
#define CYCLE_TOOK(call_, evacaddr_, error_) \
    engine_status_check((int)(call_), ENGINE_MODULE_CYCLE, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define CYCLE_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_CYCLE, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

// compiled is 1 where the program runs as its own kernel (below, the record program compiled), whose library the
// process's cache holds; 0 where it runs on the interpreter. The block is the host's copy of the program's
// EngineProgramBlock, and device_block the one its thread blocks write; hot is what they share on the device; registers and
// local_bytes are the compiled kernel's registers a thread and local frame a thread, the grant it runs within. places
// are a thread's registers in shared memory and threads a thread block's; register_bytes is the shared memory a thread
// block's registers take, the launch's dynamic shared memory, and shared_bytes all a thread block holds, the kernel's
// own beside them; resident is the thread blocks the device holds at once
struct CycleRecord
{
    unsigned int steps;
    unsigned int members;
    unsigned int file_limbs;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
    unsigned int out_limbs;
    unsigned int divides;
    unsigned int compiled;
    cudaKernel_t kernel;
    DeviceRecordStep *device_steps;
    unsigned int *device_refused;
    unsigned int *device_tables;
    EngineProgramBlock *block;
    EngineProgramBlock *device_block;
    struct CycleHot *hot;
    unsigned long long registers;
    unsigned long long local_bytes;
    unsigned int places;
    unsigned int threads;
    unsigned long long thread_bytes;
    unsigned long long register_bytes;
    unsigned long long shared_bytes;
    unsigned long long resident;
    unsigned long long processors;
};

// a launch's time to live where CYCLE_RECORD_TTL names none, well inside Windows' 2 s watchdog
#define CYCLE_PROGRAM_TTL_MICROSECONDS 500000ull

// the check-in the scheduler holds a program to, and how often each of its thread blocks checks in within it
#define CYCLE_PROGRAM_WDT_MICROSECONDS 100000ull

#define CYCLE_PROGRAM_CHECKINS_PER_WDT 4ull

// the stack a launch grew past `before` given back (cycle.cu)
int cycle_stack_return(size_t before, const void *evacaddr, EngineError *error);

// 1 where the environment names `name` as 1, and the microseconds it names, else `otherwise` (cycle_compile.cu)
int cycle_environment_set(const char *name);

unsigned long long cycle_environment_microseconds(const char *name, unsigned long long otherwise);

// a program's lane compiled and held for `record`, 0 where it stays on the interpreter, and a held kernel's
// library given back (cycle_compile.cu)
int cycle_record_compile(const EngineRecordLayout *layout, CycleRecord *record);

void cycle_program_release(cudaKernel_t kernel);

// every program and the operator block open with the prelude; the operator block follows it
// (cycle_operators.cu)
extern const char g_cycle_prelude[];

extern const char g_cycle_operators[];

#endif
