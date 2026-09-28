// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef CYCLE_SHARED_H
#define CYCLE_SHARED_H

// What the record machine's files share: the headers, the checks and the record a program is held as. The
// machine is cut into its functional chunks: cycle_{sweep,launch}.cu the key sweep, cycle_record_*.cu the record
// interpreter and the record calls, cycle_prelude.cu the prelude a C lane opens with, and cycle_compile_*.cu NVRTC,
// nvJitLink, the cache and a program compiled. A kernel stays in the file that launches it; a compiled program's
// kernel is its own text's (program_unit)

#include "cycle.h"

// the CRC that seals a program's block, and the signum that names its program
#include "../../codecs/crc/crc.h"
#include "obsignatio.h"

// the code generator, which writes a program's lane as PTX or C source for the target named here, and the launch it
// reads; and its assembly printer, which the device runs to write the lane's text again
#include "../codegen/asm_printer.h"
#include "../codegen/c_target.h"
#include "../codegen/codegen_device.h"
#include "../codegen/ptx_target.h"

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

// cudaError_t enumerates non-negative codes below INT_MAX; the status converts to int exactly
#define CYCLE_STATUS_CHECK(call_, evacaddr_, error_)                                                                   \
    engine_status_check((int)(call_), ENGINE_MODULE_CYCLE, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define CYCLE_CHECK(condition_, evacaddr_, error_, kind_)                                                              \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_CYCLE, (unsigned int)__LINE__, (const void *)(evacaddr_),  \
                       (error_))

// compiled is 1 where the program runs as its own kernel (below, the record program compiled), whose library the
// process's cache holds; 0 where it runs on the interpreter. The block is the host's copy of the program's
// EngineProgramBlock, and device_block the one its thread blocks write; hot is what they share on the device; registers
// and local_bytes are the compiled kernel's registers a thread and local frame a thread, the grant it runs within.
// places are a thread's registers in shared memory and threads a thread block's; register_bytes is the shared memory a
// thread block's registers take, the launch's dynamic shared memory, and shared_bytes all a thread block holds, the
// kernel's own beside them; resident is the thread blocks the device holds at once. host_program is the resident of a
// program the host's compiler built (CYCLE_RECORD_HOST_C=1), which runs on the host; NULL where the program is the
// device's. table_words is the words of the program's tables
typedef void (*CycleHostEntry)(CycleCompiledLaunch launch);

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
    unsigned int *device_error;
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
    CycleHostEntry host_program;
    unsigned long long table_words;
};

// a launch's time to live where CYCLE_RECORD_TTL names none, well inside Windows' 2 s watchdog
#define CYCLE_PROGRAM_TTL_MICROSECONDS 500000ull

// the check-in the scheduler holds a program to, and how often each of its thread blocks checks in within it
#define CYCLE_PROGRAM_WDT_MICROSECONDS 100000ull

#define CYCLE_PROGRAM_CHECKINS_PER_WDT 4ull

// the stack a launch grew past `before` given back (cycle_launch.cu)
int cycle_stack_return(size_t before, const void *evacaddr, EngineError *error);

// 1 where the environment names `name` as 1, and the microseconds it names, else `otherwise`
// (cycle_compile_toolchain.cu)
int cycle_environment_set(const char *name);

unsigned long long cycle_environment_microseconds(const char *name, unsigned long long otherwise);

// a program's lane compiled and kept for `record`, 0 where it stays on the interpreter, and a kept kernel's
// library given back (cycle_compile_route.cu)
int cycle_record_compile(const EngineRecordLayout *layout, CycleRecord *record);

void cycle_program_release(cudaKernel_t kernel);

// a program's C source built by the host's compiler and loaded for `record`, 0 where it did not build; a kept host
// program given back; and a host program run resident on the host (cycle_compile_host.cu)
int cycle_host_program_load(const EngineRecordLayout *layout, CycleRecord *record, const std::string &source,
                            unsigned int places, double written, int report);

void cycle_host_program_release(CycleHostEntry entry);

int cycle_host_resident(const CycleRecord *record, CycleCompiledLaunch program, EngineError *error);

// the prelude a C lane opens with, which names the launch and the lane's types (cycle_prelude.cu)
extern const char g_cycle_prelude[];

#endif
