// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cycle_compile_host.cu: a program's C source built by the host's compiler, and run resident on the host
//
// CYCLE_RECORD_HOST_C=1 builds each lane written as C source (CTarget::program) with the host's C++ compiler in
// place of NVRTC: the lane and its resident (program_unit) under a host prelude that reads the CUDA names they use as
// one thread of one thread block. The text is compiled to a shared library in the cache folder, kept there by its
// text, and loaded; its resident, cycle_program, runs every lane on the host's processor. The run copies the lane's
// inputs from the device and its records and errors back, so the check (CYCLE_RECORD_CHECK=1) holds it to the
// interpreter as it holds the device's. On Windows the compiler is nvcc handing the source to the host compiler
// alone, with -ccbin $CYCLE_HOST_CCBIN where it is set; elsewhere it is $CXX, else c++
#include "cycle_compile_internal.h"
#include "cycle_record_internal.h"

#if !defined(_WIN32)
#include <fcntl.h>
#include <spawn.h>
#include <sys/wait.h>
extern char **environ;
#endif

// The host's reading of the CUDA names a C lane and its resident use: one thread of one thread block, whose atomics
// are a plain read and write, exact where one thread makes them. The resident is the library's one export
static const char s_cycle_host_prelude[] = R"CYCLE(// a record program's lane, built by the host's compiler
#if defined(_WIN32)
#define __global__ __declspec(dllexport)
#else
#define __global__ __attribute__((visibility("default")))
#endif
#define __device__
#define __shared__
#define __forceinline__ inline
#define __launch_bounds__(threads_)
#define __syncthreads()
#define __threadfence()

struct CycleHostDimension
{
    unsigned int x;
};

static const CycleHostDimension threadIdx = {0u};
static const CycleHostDimension blockDim = {1u};
static const CycleHostDimension gridDim = {1u};

static inline unsigned int atomicAdd(unsigned int *address, unsigned int value)
{
    const unsigned int held = *address;
    *address = held + value;
    return held;
}

static inline unsigned long long atomicAdd(unsigned long long *address, unsigned long long value)
{
    const unsigned long long held = *address;
    *address = held + value;
    return held;
}

static inline unsigned long long atomicCAS(unsigned long long *address, unsigned long long compare,
                                           unsigned long long value)
{
    const unsigned long long held = *address;
    *address = (held == compare) ? value : held;
    return held;
}
)CYCLE";

#if defined(_WIN32)
#define CYCLE_HOST_LIBRARY ".dll"
#else
#define CYCLE_HOST_LIBRARY ".so"
#endif

// a program the host's compiler built in this process, found again by its whole text, and the records loaded that
// hold it: the last one released unloads it
struct CycleHostProgram
{
    std::string source;
    void *library;
    CycleHostEntry entry;
    unsigned long long holders;
};

static std::vector<CycleHostProgram> s_cycle_host_programs;

// a file's whole contents, empty where it cannot be read
static std::string cycle_host_file_read(const std::string &path)
{
    std::string contents;
    FILE *const file = fopen(path.c_str(), "rb");
    if (file == NULL)
    {
        return contents;
    }
    char block[65536];
    size_t read = fread(block, 1u, sizeof(block), file);
    while (read != 0u)
    {
        contents.append(block, read);
        read = fread(block, 1u, sizeof(block), file);
    }
    fclose(file);
    return contents;
}

static int cycle_host_file_write(const std::string &path, const std::string &contents)
{
    FILE *const file = fopen(path.c_str(), "wb");
    if (file == NULL)
    {
        return 0;
    }
    const int written = fwrite(contents.data(), 1u, contents.size(), file) == contents.size();
    return (fclose(file) == 0) && written;
}

// the compiler run on `source` into `library`, its output written to `log`; 1 where it ran and succeeded
static int cycle_host_compiler_run(const std::string &source, const std::string &library, const std::string &log)
{
    std::vector<std::string> arguments;
#if defined(_WIN32)
    const char *const bin = getenv("CYCLE_HOST_CCBIN");
    arguments.push_back("nvcc");
    if ((bin != NULL) && (bin[0] != '\0'))
    {
        arguments.push_back("-ccbin");
        arguments.push_back(bin);
    }
    for (const char *const flag : {"--shared", "--cudart", "none", "-O1", "-x", "c++"})
    {
        arguments.push_back(flag);
    }
#else
    const char *const compiler = getenv("CXX");
    arguments.push_back(((compiler != NULL) && (compiler[0] != '\0')) ? compiler : "c++");
    for (const char *const flag : {"-shared", "-fPIC", "-O1", "-x", "c++"})
    {
        arguments.push_back(flag);
    }
#endif
    arguments.push_back(source);
    arguments.push_back("-o");
    arguments.push_back(library);
#if defined(_WIN32)
    std::string command;
    for (size_t at = 0u; at < arguments.size(); at += 1u)
    {
        command += ((at == 0u) ? "\"" : " \"") + arguments[at] + "\"";
    }
    std::vector<char> line(command.begin(), command.end());
    line.push_back('\0');
    SECURITY_ATTRIBUTES inherited;
    memset(&inherited, 0, sizeof(inherited));
    inherited.nLength = sizeof(inherited);
    inherited.bInheritHandle = TRUE;
    const HANDLE output = CreateFileA(log.c_str(), GENERIC_WRITE, FILE_SHARE_READ, &inherited, CREATE_ALWAYS,
                                      FILE_ATTRIBUTE_NORMAL, NULL);
    if (output == INVALID_HANDLE_VALUE)
    {
        return 0;
    }
    STARTUPINFOA startup;
    memset(&startup, 0, sizeof(startup));
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    startup.hStdOutput = output;
    startup.hStdError = output;
    PROCESS_INFORMATION process;
    memset(&process, 0, sizeof(process));
    DWORD status = 1u;
    const BOOL started =
        CreateProcessA(NULL, line.data(), NULL, NULL, TRUE, CREATE_NO_WINDOW, NULL, NULL, &startup, &process);
    if (started)
    {
        WaitForSingleObject(process.hProcess, INFINITE);
        GetExitCodeProcess(process.hProcess, &status);
        CloseHandle(process.hThread);
        CloseHandle(process.hProcess);
    }
    CloseHandle(output);
    return started && (status == 0u);
#else
    std::vector<char *> argv;
    for (size_t at = 0u; at < arguments.size(); at += 1u)
    {
        argv.push_back(&arguments[at][0]);
    }
    argv.push_back(NULL);
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, 1, log.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0644);
    posix_spawn_file_actions_adddup2(&actions, 1, 2);
    pid_t child = 0;
    const int started = posix_spawnp(&child, argv[0], &actions, NULL, argv.data(), environ) == 0;
    posix_spawn_file_actions_destroy(&actions);
    int status = 1;
    const int waited = started && (waitpid(child, &status, 0) == child);
    return waited && WIFEXITED(status) && (WEXITSTATUS(status) == 0);
#endif
}

static void *cycle_host_library_open(const std::string &path)
{
#if defined(_WIN32)
    // a module handle is held as a plain pointer beside the Linux one
    return (void *)LoadLibraryA(path.c_str());
#else
    return dlopen(path.c_str(), RTLD_NOW | RTLD_LOCAL);
#endif
}

static void cycle_host_library_close(void *library)
{
#if defined(_WIN32)
    FreeLibrary((HMODULE)library);
#else
    dlclose(library);
#endif
}

// The host text of a C lane found in this process, else in the cache folder, else compiled there and kept, then
// loaded. The cache holds the text beside its library, and a library is used only where the text beside it is this
// text byte for byte; each is written beside its name and renamed to it, and no reader finds half a file. 0 where
// there is no cache folder, or the compile or the load failed
int cycle_host_program_load(const EngineRecordLayout *layout, CycleRecord *record, const std::string &source,
                            unsigned int places, double written, int report)
{
    // one thread's places: a word each, then a sign byte each
    std::string text = s_cycle_host_prelude + source;
    cycle_format(text, "\nu32 cycle_words[%u];\n", places + ((places + 3u) / 4u) + 1u);
    for (size_t at = 0u; at < s_cycle_host_programs.size(); at += 1u)
    {
        if (s_cycle_host_programs[at].source == text)
        {
            s_cycle_host_programs[at].holders += 1ull;
            record->host_program = s_cycle_host_programs[at].entry;
            record->compiled = 1u;
            if (report != 0)
            {
                fprintf(stderr, "  cycle: a program of %u steps found in this process, as a host library\n",
                        layout->steps);
            }
            return 1;
        }
    }
    const std::string folder = cycle_cache_folder();
    if (folder.empty())
    {
        return 0;
    }
#if defined(_WIN32)
    _mkdir(folder.c_str());
    const int process = _getpid();
    const char *const separator = "\\";
#else
    mkdir(folder.c_str(), 0755);
    // a pid is positive. It converts exactly
    const int process = (int)getpid();
    const char *const separator = "/";
#endif
    char name[64];
    snprintf(name, sizeof(name), "%016llx.host", cycle_source_hash(text));
    const std::string stem = folder + separator + name;
    const int found = cycle_host_file_read(stem + ".cpp") == text;
    double compile_milliseconds = 0.0;
    std::string log;
    if (!found)
    {
        char suffix[32];
        snprintf(suffix, sizeof(suffix), ".%d", process);
        const std::string partial = stem + suffix;
        log = partial + ".log";
        const auto began = std::chrono::steady_clock::now();
        const int built = cycle_host_file_write(partial + ".cpp", text) &&
                          cycle_host_compiler_run(partial + ".cpp", partial + CYCLE_HOST_LIBRARY, log);
        compile_milliseconds =
            std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
        // a name another process took first is left as it is, and its library is the one loaded
        if (built)
        {
            rename((partial + CYCLE_HOST_LIBRARY).c_str(), (stem + CYCLE_HOST_LIBRARY).c_str());
            rename((partial + ".cpp").c_str(), (stem + ".cpp").c_str());
        }
        for (const char *const left : {CYCLE_HOST_LIBRARY, ".cpp", ".lib", ".exp"})
        {
            remove((partial + left).c_str());
        }
        if (built)
        {
            remove(log.c_str());
        }
    }
    CycleHostProgram program;
    program.library = cycle_host_library_open(stem + CYCLE_HOST_LIBRARY);
    program.entry = NULL;
    program.holders = 1ull;
    if (program.library != NULL)
    {
#if defined(_WIN32)
        // the resident's address is cast back to the function the host prelude gives it
        program.entry = (CycleHostEntry)GetProcAddress((HMODULE)program.library, "cycle_program");
#else
        program.entry = (CycleHostEntry)dlsym(program.library, "cycle_program");
#endif
    }
    if ((program.entry == NULL) || (cycle_host_file_read(stem + ".cpp") != text))
    {
        if (program.library != NULL)
        {
            cycle_host_library_close(program.library);
        }
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps did not build on the host (%s%s)\n", layout->steps,
                    log.empty() ? "its library did not load" : "the compiler errored, its log ", log.c_str());
        }
        return 0;
    }
    program.source = text;
    s_cycle_host_programs.push_back(program);
    record->host_program = program.entry;
    record->compiled = 1u;
    if ((report != 0) && found)
    {
        fprintf(stderr, "  cycle: a program of %u steps read from the cache as a host library\n", layout->steps);
    }
    else if (report != 0)
    {
        fprintf(stderr,
                "  cycle: a program of %u steps as C source on the host: written in %.1f ms to %zu bytes, compiled "
                "in %.1f ms\n",
                layout->steps, written, text.size(), compile_milliseconds);
    }
    return 1;
}

// a hold on a host program loaded in this process given back, where `entry` is one; the last hold released unloads it
void cycle_host_program_release(CycleHostEntry entry)
{
    for (size_t at = 0u; (entry != NULL) && (at < s_cycle_host_programs.size()); at += 1u)
    {
        if (s_cycle_host_programs[at].entry == entry)
        {
            s_cycle_host_programs[at].holders -= 1ull;
            if (s_cycle_host_programs[at].holders == 0ull)
            {
                cycle_host_library_close(s_cycle_host_programs[at].library);
                s_cycle_host_programs.erase(s_cycle_host_programs.begin() + (std::ptrdiff_t)at);
            }
            break;
        }
    }
}

// device words read into the host's copy; nothing is read where there are none
static int cycle_host_words_read(std::vector<unsigned int> &words, const unsigned int *device, size_t count,
                                 EngineError *error)
{
    words.assign(count, 0u);
    return (device == NULL) || (count == 0u) ||
           CYCLE_STATUS_CHECK(cudaMemcpy(words.data(), device, count * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                              device, error);
}

// The host program run resident, as the device's is (cycle_record_resident): its block laid out for this run, then
// the program called again from where its block says it stands until every lane is done. The host's copy of the
// block is the one the program writes. The lanes' members, index and tables are read from the device first, and the
// records and the error count are written back to it last. The host has no clock the program reads, so its launch
// time is taken around each call
int cycle_host_resident(const CycleRecord *record, CycleCompiledLaunch program, EngineError *error)
{
    std::vector<unsigned int> in[ENGINE_RECORD_MEMBERS_MAX];
    std::vector<unsigned int> index;
    std::vector<unsigned int> tables;
    std::vector<unsigned int> out;
    std::vector<unsigned int> error_count;
    unsigned int *const device_out = program.out;
    unsigned int *const device_error = program.error;
    // a lane count and a record's limbs are the ones the device's buffers were allocated to, which fit in memory
    const size_t out_words = (size_t)(program.count * record->out_limbs);
    int ok = cycle_host_words_read(index, program.index, (size_t)(program.count * record->members), error) &&
             cycle_host_words_read(tables, program.tables, (size_t)record->table_words, error) &&
             cycle_host_words_read(error_count, program.error, 1u, error);
    for (unsigned int member = 0u; (ok != 0) && (member < record->members); member += 1u)
    {
        ok = cycle_host_words_read(in[member], program.in[member],
                                   (size_t)(program.bodies[member] * record->in_limbs[member]), error);
        program.in[member] = in[member].data();
    }
    out.assign(out_words, 0u);
    CycleHot hot;
    memset(&hot, 0, sizeof(hot));
    program.index = (program.index != NULL) ? index.data() : NULL;
    program.tables = (program.tables != NULL) ? tables.data() : NULL;
    program.out = out.data();
    program.error = error_count.data();
    EngineProgramBlock *const block = record->block;
    const unsigned long long ttl =
        1000ull * cycle_environment_microseconds("CYCLE_RECORD_TTL", CYCLE_PROGRAM_TTL_MICROSECONDS);
    const unsigned long long wdt = 1000ull * CYCLE_PROGRAM_WDT_MICROSECONDS;
    const EngineSignum signature = block->signature;
    const unsigned long long generation = block->generation + 1ull;
    memset(block, 0, sizeof(EngineProgramBlock));
    block->signature = signature;
    block->generation = generation;
    block->command = ENGINE_PROGRAM_RUN;
    block->grant_threads = 1ull;
    block->state = ENGINE_PROGRAM_PLACED;
    block->span = record->file_limbs;
    block->ttl = ttl;
    block->wdt = wdt;
    block->lanes = program.count;
    // the records' address is held as a 64-bit word, as every word of the block is
    block->result = (unsigned long long)(uintptr_t)out.data();
    block->result_words = out_words;
    block->checksum = cycle_block_seal(block);
    program.hot = &hot;
    // the block is 64-bit words throughout, and the program reads it as them
    program.block = (unsigned long long *)block;
    program.ttl = ttl;
    program.checkin_every = wdt / CYCLE_PROGRAM_CHECKINS_PER_WDT;
    program.places = record->places;
    int running = ok;
    while (running != 0)
    {
        ok = CYCLE_CHECK(block->checksum == cycle_block_seal(block), block, error, ENGINE_ERROR_LOGIC);
        if (ok == 0)
        {
            break;
        }
        block->launches += 1ull;
        block->owner = block->launches;
        block->state = ENGINE_PROGRAM_RUNNING;
        program.launch_number = block->launches;
        hot.launch_start = 0ull;
        hot.finished = 0ull;
        const auto began = std::chrono::steady_clock::now();
        record->host_program(program);
        const auto ended = std::chrono::steady_clock::now();
        const unsigned long long state = block->state;
        ok = CYCLE_CHECK((state == ENGINE_PROGRAM_YIELDED) || (state == ENGINE_PROGRAM_DONE), block, error,
                         ENGINE_ERROR_LOGIC);
        // a call's nanoseconds are never negative
        block->exectime =
            (unsigned long long)std::chrono::duration_cast<std::chrono::nanoseconds>(ended - began).count();
        block->error = error_count[0];
        block->runtime += block->exectime;
        if (ok == 0)
        {
            block->state = ENGINE_PROGRAM_FAULT;
            // an engine module and a site are small non-negative counts, which fit in a 64-bit word
            block->error_module = (unsigned long long)error->module;
            block->error_site = (unsigned long long)error->site;
        }
        block->checksum = cycle_block_seal(block);
        running = (ok != 0) && (state == ENGINE_PROGRAM_YIELDED);
    }
    ok = ok &&
         CYCLE_STATUS_CHECK(cudaMemcpy(device_error, error_count.data(), sizeof(unsigned int), cudaMemcpyHostToDevice),
                            device_error, error) &&
         ((out_words == 0u) || CYCLE_STATUS_CHECK(cudaMemcpy(device_out, out.data(), out_words * sizeof(unsigned int),
                                                             cudaMemcpyHostToDevice),
                                                  device_out, error));
    return ok;
}
