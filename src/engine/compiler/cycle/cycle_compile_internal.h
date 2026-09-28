// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the cycle_compile_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef CYCLE_COMPILE_INTERNAL_H
#define CYCLE_COMPILE_INTERNAL_H

#include "cycle_shared.h"

// The record program compiled. Nothing hand-written is linked with it: the language's own forms write every record
// operation into the lane and the resident kernel that runs the lanes after it (program_unit), and one text is the
// whole program. A program is written first as PTX (PtxTarget::program): each step unrolled at its widths into
// straight-line assembly over registers the lane holds, a step that loops on its values a loop of the same forms, and
// nvJitLink assembles and links it alone, with no compiler between. Where the lane cannot be written so, or its
// PTX does not build, the lane is C source instead (CTarget::program), the same lane in c.krs with its file and
// signs in the thread block's shared memory, file_limbs the most it holds live at once, compiled by NVRTC as
// relocatable code and linked alone the same way. A program of any length builds either way. A thread block holds as
// many threads as its shared memory fits of the C lane's places; a PTX lane takes none. The interpreter above stays the
// oracle, and the fallback for a program neither way builds, this process cannot load or shared memory cannot hold one
// thread's places for.
//
// The compiled program runs as a resident program with a block (EngineProgramBlock) in device memory. Its thread blocks
// take lanes a round at a time from one counter, check in to the block as they go, and leave once the launch has run
// its time to live or the block's command says to. The last one out writes where the program stands, and the run
// launches it again from there until every lane is done: a launch never outlives the display driver's watchdog, and no
// lane runs twice. The host reads the block only once a launch has ended. Eight switches, read at each load or run:
// CYCLE_RECORD_INTERPRET=1 keeps every program on the interpreter, CYCLE_RECORD_CHECK=1 runs both on every launch and
// errors on the launch where their records or errors differ, CYCLE_RECORD_REPORT=1 says on stderr where each program
// came from and how long each kernel ran, CYCLE_RECORD_TTL=<microseconds> sets a launch's time to live,
// CYCLE_RECORD_LTO=1 builds the programs as LTO-IR and links each with link-time optimization, which writes no PTX,
// CYCLE_RECORD_NVRTC=1 writes every lane as C source, and CYCLE_RECORD_HOST_C=1 writes it so and builds it with the
// host's compiler, to run on the host (cycle_compile_host.cu), and CYCLE_RECORD_KEEP_PTX=1 turns rule (i) off
// (cycle_record_route). No switch turns the device's writing off: the device writes each lane from its step table,
// and its text is held to the host code generator's (cycle_codegen_on_device), the assembly printer's own lane
// included: the assembly printer runs on the interpreter while it writes that one.

static_assert(ENGINE_RECORD_MEMBERS_MAX == 3u, "cycle: the compiled program's launch holds three members");

// NVRTC, loaded once a process first compiles
struct CycleCompiler
{
    int tried;
    int ready;
    int major;
    int minor;
    decltype(&nvrtcCreateProgram) create;
    decltype(&nvrtcCompileProgram) compile;
    decltype(&nvrtcGetCUBINSize) cubin_size;
    decltype(&nvrtcGetCUBIN) cubin;
    decltype(&nvrtcGetLTOIRSize) ltoir_size;
    decltype(&nvrtcGetLTOIR) ltoir;
    // PTX is read once a process, for its header alone (cycle_ptx_header); an NVRTC without it leaves every program's
    // lane to the C source
    decltype(&nvrtcGetPTXSize) ptx_size;
    decltype(&nvrtcGetPTX) ptx;
    decltype(&nvrtcGetProgramLogSize) log_size;
    decltype(&nvrtcGetProgramLog) log;
    decltype(&nvrtcDestroyProgram) destroy;
};

extern CycleCompiler g_cycle_compiler;

// nvJitLink, loaded once a process first links: each call by the versioned name the header was built against
struct CycleLinker
{
    int tried;
    int ready;
    decltype(&nvJitLinkCreate) create;
    decltype(&nvJitLinkAddData) add;
    decltype(&nvJitLinkComplete) complete;
    decltype(&nvJitLinkGetLinkedCubinSize) cubin_size;
    decltype(&nvJitLinkGetLinkedCubin) cubin;
    decltype(&nvJitLinkGetErrorLogSize) log_size;
    decltype(&nvJitLinkGetErrorLog) log;
    decltype(&nvJitLinkDestroy) destroy;
};

extern CycleLinker g_cycle_linker;

// what a lane is written for, one device and one kind of link, named once a process: the device, and the text that
// names it with the prelude a C lane opens with, whose hash each program's first line carries. Nothing is compiled
// for it: every program's text holds its own resident (program_unit), and a program is built alone
struct CycleTarget
{
    int tried;
    int ready;
    int major;
    int minor;
    unsigned long long hash;
    std::string source;
};

// a program compiled in this process, found again by its whole source, and the records loaded that hold it: the last
// one released unloads it
struct CycleCompiledProgram
{
    std::string source;
    cudaLibrary_t library;
    cudaKernel_t kernel;
    unsigned long long holders;
};

int cycle_environment_set(const char *name);

void cycle_format(std::string &text, const char *format, ...);

int cycle_compiler_ready(void);

int cycle_linker_ready(void);

std::string cycle_target_source(int major, int minor, int lto);

std::string cycle_cache_folder(void);

unsigned long long cycle_source_hash(const std::string &source);

std::string cycle_cache_path(const std::string &folder, const std::string &source);

std::vector<char> cycle_cache_read(const std::string &path, const std::string &source);

void cycle_cache_write(const std::string &folder, const std::string &path, const std::string &source,
                       const std::vector<char> &image);

std::vector<char> cycle_program_compile(const std::string &source, const char *name, int major, int minor, int lto,
                                        int report);

std::vector<char> cycle_program_link(const CycleTarget *lane_target, const std::vector<char> &object, int lto, int ptx,
                                     int report);

const CycleTarget *cycle_target(int major, int minor, int lto, int report);

// PTX's header as this toolkit writes it for the device, asked of NVRTC once a process by compiling an empty kernel to
// PTX, the answer kept in the cache against the question: the one part of PTX's rules the lane does not carry itself
struct CyclePtxHeader
{
    int tried;
    int major;
    int minor;
    std::string lines;
};

const std::string &cycle_ptx_header(int major, int minor, int report);

#endif
