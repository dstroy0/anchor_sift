// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "cycle_shared.h"

// The record program compiled. Every record operation lives once, in the operator block: a function of its own, the
// interpreter's arithmetic with its widths taken as arguments, compiled by NVRTC once for this device and kept in the
// cache. A program's lane is written first as PTX (CycleEmitPtx::program): each step unrolled at its widths into
// straight-line assembly over registers the lane holds, or a call into the block for a step that loops on its values,
// and nvJitLink assembles it as it links it against the block, with no compiler between. Where the lane cannot be written
// so, or its PTX does not build, the lane is C source instead, its steps alone, each one call into the block with its
// places and widths as constants over the register file key_schedule laid, file_limbs the most it holds live at once,
// compiled by NVRTC as relocatable code and linked the same way. A program of any length builds either way. The block's
// registers lie in the thread block's shared memory, sized exactly from its widths, and a thread block holds as many
// threads as that shared memory fits; a PTX lane that calls nothing takes none. The interpreter above stays the oracle,
// and the fallback for a program neither way builds, this process cannot load or shared memory cannot hold one
// thread's registers for.
//
// The compiled program runs as a resident program with a block (EngineProgramBlock) in device memory. Its thread blocks
// take lanes a round at a time from one counter, check in to the block as they go, and leave once the launch has run
// its time to live or the block's command says to. The last one out writes where the program stands, and the run
// launches it again from there until every lane is done: a launch never outlives the display driver's watchdog, and no
// lane runs twice. The host reads the block only once a launch has ended. Six switches, read at each load or run:
// CYCLE_RECORD_INTERPRET=1 keeps every program on the interpreter, CYCLE_RECORD_CHECK=1 runs both on every launch and
// refuses the launch where their records or refusals differ, CYCLE_RECORD_REPORT=1 says on stderr where each program
// came from and how long each kernel ran, CYCLE_RECORD_TTL=<microseconds> sets a launch's time to live,
// CYCLE_RECORD_LTO=1 builds the block and the programs as LTO-IR and links them with link-time optimization, which
// writes no PTX, and CYCLE_RECORD_NVRTC=1 writes every lane as C source.

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

static CycleCompiler s_cycle_compiler;

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

static CycleLinker s_cycle_linker;

// the operator block for one device and one kind of link, built once a process: its source, and the relocatable
// cubin or LTO-IR every program is linked against. hash names the block in each program's source, so a program's
// cubin is found in the cache only against the block it was linked with
struct CycleOperatorBlock
{
    int tried;
    int ready;
    int major;
    int minor;
    unsigned long long hash;
    std::string source;
    std::vector<char> image;
};

// the block for relocatable cubin, then the block for LTO-IR
static CycleOperatorBlock s_cycle_operator_blocks[2];

// a program compiled in this process, found again by its whole source, and the records loaded that hold it: the last
// one released unloads it
struct CycleCompiledProgram
{
    std::string source;
    cudaLibrary_t library;
    cudaKernel_t kernel;
    unsigned long long holders;
};

static std::vector<CycleCompiledProgram> s_cycle_programs;

int cycle_environment_set(const char *name)
{
    const char *const value = getenv(name);
    return ((value != NULL) && (value[0] == '1')) ? 1 : 0;
}

// a count of microseconds the environment names, or `otherwise` where it names none or one that is not a whole number
unsigned long long cycle_environment_microseconds(const char *name, unsigned long long otherwise)
{
    const char *const value = getenv(name);
    if ((value == NULL) || (value[0] < '0') || (value[0] > '9'))
    {
        return otherwise;
    }
    char *end = NULL;
    const unsigned long long named = strtoull(value, &end, 10);
    return ((end != NULL) && (*end == '\0')) ? named : otherwise;
}

static void cycle_emit(std::string &text, const char *format, ...)
{
    char line[512];
    va_list arguments;
    va_start(arguments, format);
    const int written = vsnprintf(line, sizeof(line), format, arguments);
    va_end(arguments);
    // a line the room does not hold is cut, and the source then fails to compile rather than run wrong; written is
    // read as a size only once it is known positive
    text.append(line, ((written > 0) && ((size_t)written < sizeof(line))) ? (size_t)written : sizeof(line) - 1u);
}

static void *cycle_compiler_symbol(void *library, const char *name)
{
#if defined(_WIN32)
    // a symbol's address is the function it names, held as a plain pointer until it is cast back to that function
    return (void *)GetProcAddress((HMODULE)library, name);
#else
    return dlsym(library, name);
#endif
}

static int cycle_compiler_ready(void)
{
    CycleCompiler *const compiler = &s_cycle_compiler;
    if (compiler->tried != 0)
    {
        return compiler->ready;
    }
    compiler->tried = 1;
    char name[64];
#if defined(_WIN32)
    snprintf(name, sizeof(name), "nvrtc64_%d0_0.dll", CUDART_VERSION / 1000);
    // a module handle is held as a plain pointer beside the Linux one
    void *const library = (void *)LoadLibraryA(name);
#else
    snprintf(name, sizeof(name), "libnvrtc.so.%d", CUDART_VERSION / 1000);
    void *library = dlopen(name, RTLD_NOW);
    library = (library != NULL) ? library : dlopen("libnvrtc.so", RTLD_NOW);
#endif
    if (library == NULL)
    {
        return 0;
    }
    // each symbol's address is cast back to the function NVRTC's header gives it
    const decltype(&nvrtcVersion) version = (decltype(&nvrtcVersion))cycle_compiler_symbol(library, "nvrtcVersion");
    compiler->create = (decltype(&nvrtcCreateProgram))cycle_compiler_symbol(library, "nvrtcCreateProgram");
    compiler->compile = (decltype(&nvrtcCompileProgram))cycle_compiler_symbol(library, "nvrtcCompileProgram");
    compiler->cubin_size = (decltype(&nvrtcGetCUBINSize))cycle_compiler_symbol(library, "nvrtcGetCUBINSize");
    compiler->cubin = (decltype(&nvrtcGetCUBIN))cycle_compiler_symbol(library, "nvrtcGetCUBIN");
    compiler->ltoir_size = (decltype(&nvrtcGetLTOIRSize))cycle_compiler_symbol(library, "nvrtcGetLTOIRSize");
    compiler->ltoir = (decltype(&nvrtcGetLTOIR))cycle_compiler_symbol(library, "nvrtcGetLTOIR");
    compiler->ptx_size = (decltype(&nvrtcGetPTXSize))cycle_compiler_symbol(library, "nvrtcGetPTXSize");
    compiler->ptx = (decltype(&nvrtcGetPTX))cycle_compiler_symbol(library, "nvrtcGetPTX");
    compiler->log_size = (decltype(&nvrtcGetProgramLogSize))cycle_compiler_symbol(library, "nvrtcGetProgramLogSize");
    compiler->log = (decltype(&nvrtcGetProgramLog))cycle_compiler_symbol(library, "nvrtcGetProgramLog");
    compiler->destroy = (decltype(&nvrtcDestroyProgram))cycle_compiler_symbol(library, "nvrtcDestroyProgram");
    compiler->ready = (version != NULL) && (compiler->create != NULL) && (compiler->compile != NULL)
                   && (compiler->cubin_size != NULL) && (compiler->cubin != NULL) && (compiler->ltoir_size != NULL)
                   && (compiler->ltoir != NULL) && (compiler->log_size != NULL) && (compiler->log != NULL)
                   && (compiler->destroy != NULL) && (version(&compiler->major, &compiler->minor) == NVRTC_SUCCESS);
    return compiler->ready;
}

// one nvJitLink call by its versioned name, __nvJitLink<call>_<major>_<minor> of the toolkit built against
static void *cycle_linker_symbol(void *library, const char *call)
{
    char name[64];
    snprintf(name, sizeof(name), "__nvJitLink%s_%d_%d", call, CUDART_VERSION / 1000, (CUDART_VERSION % 1000) / 10);
    return cycle_compiler_symbol(library, name);
}

static int cycle_linker_ready(void)
{
    CycleLinker *const linker = &s_cycle_linker;
    if (linker->tried != 0)
    {
        return linker->ready;
    }
    linker->tried = 1;
    char name[64];
#if defined(_WIN32)
    snprintf(name, sizeof(name), "nvJitLink_%d0_0.dll", CUDART_VERSION / 1000);
    // a module handle is held as a plain pointer beside the Linux one
    void *const library = (void *)LoadLibraryA(name);
#else
    snprintf(name, sizeof(name), "libnvJitLink.so.%d", CUDART_VERSION / 1000);
    void *library = dlopen(name, RTLD_NOW);
    library = (library != NULL) ? library : dlopen("libnvJitLink.so", RTLD_NOW);
#endif
    if (library == NULL)
    {
        return 0;
    }
    // each symbol's address is cast back to the function nvJitLink's header gives it
    linker->create = (decltype(&nvJitLinkCreate))cycle_linker_symbol(library, "Create");
    linker->add = (decltype(&nvJitLinkAddData))cycle_linker_symbol(library, "AddData");
    linker->complete = (decltype(&nvJitLinkComplete))cycle_linker_symbol(library, "Complete");
    linker->cubin_size = (decltype(&nvJitLinkGetLinkedCubinSize))cycle_linker_symbol(library, "GetLinkedCubinSize");
    linker->cubin = (decltype(&nvJitLinkGetLinkedCubin))cycle_linker_symbol(library, "GetLinkedCubin");
    linker->log_size = (decltype(&nvJitLinkGetErrorLogSize))cycle_linker_symbol(library, "GetErrorLogSize");
    linker->log = (decltype(&nvJitLinkGetErrorLog))cycle_linker_symbol(library, "GetErrorLog");
    linker->destroy = (decltype(&nvJitLinkDestroy))cycle_linker_symbol(library, "Destroy");
    linker->ready = (linker->create != NULL) && (linker->add != NULL) && (linker->complete != NULL)
                 && (linker->cubin_size != NULL) && (linker->cubin != NULL) && (linker->log_size != NULL)
                 && (linker->log != NULL) && (linker->destroy != NULL);
    return linker->ready;
}

// the operator block's source for the device and the kind of link, which names both: the block's words the kernel
// reads and writes and the command and states it compares, from the one layout, then the prelude and the operators
static std::string cycle_operator_source(int major, int minor, int lto)
{
    std::string text;
    cycle_emit(text, "// the operator block, for sm_%d%d, NVRTC %d.%d, as %s\n", major, minor, s_cycle_compiler.major,
               s_cycle_compiler.minor, (lto != 0) ? "LTO-IR" : "relocatable cubin");
    cycle_emit(text, "#define CYCLE_GOLDEN_RUNGS %uu\n", ENGINE_GOLDEN_RUNGS);
    cycle_emit(text, "#define CYCLE_BLOCK_OWNER %zuu\n", offsetof(EngineProgramBlock, owner) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_COMMAND %zuu\n", offsetof(EngineProgramBlock, command) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_STATE %zuu\n", offsetof(EngineProgramBlock, state) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_OFFSET %zuu\n", offsetof(EngineProgramBlock, offset) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_STEP %zuu\n", offsetof(EngineProgramBlock, step) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_LAUNCH_TIME %zuu\n", offsetof(EngineProgramBlock, launch_time) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_EXECTIME %zuu\n", offsetof(EngineProgramBlock, exectime) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_CHECKIN %zuu\n", offsetof(EngineProgramBlock, checkin) / 8u);
    cycle_emit(text, "#define CYCLE_BLOCK_CHECKIN_TIME %zuu\n", offsetof(EngineProgramBlock, checkin_time) / 8u);
    cycle_emit(text, "#define CYCLE_PROGRAM_RUN %uull\n", (unsigned int)ENGINE_PROGRAM_RUN);
    cycle_emit(text, "#define CYCLE_PROGRAM_STOP %uull\n", (unsigned int)ENGINE_PROGRAM_STOP);
    cycle_emit(text, "#define CYCLE_PROGRAM_YIELDED %uull\n", (unsigned int)ENGINE_PROGRAM_YIELDED);
    cycle_emit(text, "#define CYCLE_PROGRAM_DONE %uull\n", (unsigned int)ENGINE_PROGRAM_DONE);
    cycle_emit(text, "#define CYCLE_PROGRAM_STOPPED %uull\n", (unsigned int)ENGINE_PROGRAM_STOPPED);
    text += g_cycle_prelude;
    text += g_cycle_operators;
    return text;
}

// the folder compiled programs are kept in across processes: $CYCLE_CACHE, else the user's cache, then cycle
static std::string cycle_cache_folder(void)
{
    const char *const named = getenv("CYCLE_CACHE");
    if ((named != NULL) && (named[0] != '\0'))
    {
        return std::string(named);
    }
#if defined(_WIN32)
    const char *const local = getenv("LOCALAPPDATA");
    return (local != NULL) ? (std::string(local) + "\\cycle") : std::string();
#else
    const char *const cache = getenv("XDG_CACHE_HOME");
    const char *const home = getenv("HOME");
    if ((cache != NULL) && (cache[0] != '\0'))
    {
        return std::string(cache) + "/cycle";
    }
    if (home == NULL)
    {
        return std::string();
    }
    mkdir((std::string(home) + "/.cache").c_str(), 0755);
    return std::string(home) + "/.cache/cycle";
#endif
}

// a source's FNV-1a
static unsigned long long cycle_source_hash(const std::string &source)
{
    unsigned long long hash = 0xCBF29CE484222325ull;
    for (size_t at = 0u; at < source.size(); at += 1u)
    {
        // a source byte is read as its unsigned value
        hash = (hash ^ (unsigned long long)(unsigned char)source[at]) * 0x100000001B3ull;
    }
    return hash;
}

// a source's file in the cache, the image built from it (a program's linked cubin, the operator block's relocatable
// cubin or LTO-IR): its source's FNV-1a in hex. The name need not be unique: a file is used only where the source it
// holds is this source, byte for byte
static std::string cycle_cache_path(const std::string &folder, const std::string &source)
{
    char name[32];
    snprintf(name, sizeof(name), "%016llx.image", cycle_source_hash(source));
#if defined(_WIN32)
    return folder + "\\" + name;
#else
    return folder + "/" + name;
#endif
}

static const char s_cycle_cache_magic[] = "cycle image 2\n";

// the image a cache file holds for this very source; empty where there is none
static std::vector<char> cycle_cache_read(const std::string &path, const std::string &source)
{
    std::vector<char> image;
    FILE *const file = fopen(path.c_str(), "rb");
    if (file == NULL)
    {
        return image;
    }
    std::vector<char> whole;
    char block[65536];
    size_t read = fread(block, 1u, sizeof(block), file);
    while (read != 0u)
    {
        whole.insert(whole.end(), block, block + read);
        read = fread(block, 1u, sizeof(block), file);
    }
    fclose(file);
    const size_t magic = sizeof(s_cycle_cache_magic) - 1u;
    const size_t head = magic + sizeof(unsigned long long);
    unsigned long long length = 0ull;
    if (whole.size() >= head)
    {
        memcpy(&length, &whole[magic], sizeof(length));
    }
    const int held = (whole.size() >= head) && (memcmp(&whole[0], s_cycle_cache_magic, magic) == 0)
                  && (length == source.size()) && ((whole.size() - head) > length)
                  && (memcmp(&whole[head], source.data(), source.size()) == 0);
    if (held)
    {
        // a source length the file held whole is below its size, held whole
        image.assign(whole.begin() + (ptrdiff_t)(head + length), whole.end());
    }
    return image;
}

// the source and its image written beside the name and then renamed to it, and no reader finds half a file; a name
// already taken is left as it is
static void cycle_cache_write(const std::string &folder, const std::string &path, const std::string &source,
                              const std::vector<char> &image)
{
#if defined(_WIN32)
    _mkdir(folder.c_str());
    const int process = _getpid();
#else
    mkdir(folder.c_str(), 0755);
    // a pid is positive, held whole
    const int process = (int)getpid();
#endif
    char suffix[32];
    snprintf(suffix, sizeof(suffix), ".%d.partial", process);
    const std::string partial = path + suffix;
    FILE *const file = fopen(partial.c_str(), "wb");
    if (file == NULL)
    {
        return;
    }
    const unsigned long long length = source.size();
    const int whole = (fwrite(s_cycle_cache_magic, 1u, sizeof(s_cycle_cache_magic) - 1u, file)
                       == (sizeof(s_cycle_cache_magic) - 1u))
                   && (fwrite(&length, sizeof(length), 1u, file) == 1u)
                   && (fwrite(source.data(), 1u, source.size(), file) == source.size())
                   && (fwrite(image.data(), 1u, image.size(), file) == image.size());
    const int closed = fclose(file) == 0;
    if (!whole || !closed || (rename(partial.c_str(), path.c_str()) != 0))
    {
        remove(partial.c_str());
    }
}

// the source compiled by NVRTC as relocatable code for the device's architecture: a relocatable cubin, or LTO-IR where
// `lto`; empty where it refuses, its log then on stderr when reporting
static std::vector<char> cycle_program_compile(const std::string &source, const char *name, int major, int minor,
                                               int lto, int report)
{
    CycleCompiler *const compiler = &s_cycle_compiler;
    std::vector<char> image;
    nvrtcProgram program = NULL;
    if (compiler->create(&program, source.c_str(), name, 0, NULL, NULL) != NVRTC_SUCCESS)
    {
        return image;
    }
    char architecture[48];
    snprintf(architecture, sizeof(architecture), "--gpu-architecture=sm_%d%d", major, minor);
    const char *const options[] = {architecture, "--std=c++17", "--relocatable-device-code=true", "-dlto"};
    const nvrtcResult compiled = compiler->compile(program, (lto != 0) ? 4 : 3, options);
    size_t size = 0u;
    const nvrtcResult sized = (lto != 0) ? compiler->ltoir_size(program, &size) : compiler->cubin_size(program, &size);
    if ((compiled == NVRTC_SUCCESS) && (sized == NVRTC_SUCCESS) && (size != 0u))
    {
        image.resize(size);
        const nvrtcResult taken = (lto != 0) ? compiler->ltoir(program, image.data())
                                             : compiler->cubin(program, image.data());
        if (taken != NVRTC_SUCCESS)
        {
            image.clear();
        }
    }
    size_t log_size = 0u;
    if ((compiled != NVRTC_SUCCESS) && (report != 0) && (compiler->log_size(program, &log_size) == NVRTC_SUCCESS)
        && (log_size > 1u))
    {
        std::vector<char> log(log_size);
        if (compiler->log(program, log.data()) == NVRTC_SUCCESS)
        {
            fprintf(stderr, "  cycle: NVRTC refused %s (%d):\n%s\n", name, (int)compiled, log.data());
        }
    }
    compiler->destroy(&program);
    return image;
}

// a program's relocatable image linked against the operator block's by nvJitLink into one cubin, with link-time
// optimization where `lto`; where `ptx` the program is PTX's text, NUL and all, which nvJitLink assembles as it links.
// Empty where it refuses, its log then on stderr when reporting
static std::vector<char> cycle_program_link(const CycleOperatorBlock *operators, const std::vector<char> &object,
                                            int lto, int ptx, int report)
{
    CycleLinker *const linker = &s_cycle_linker;
    std::vector<char> cubin;
    char architecture[32];
    snprintf(architecture, sizeof(architecture), "-arch=sm_%d%d", operators->major, operators->minor);
    const char *options[] = {architecture, "-lto"};
    nvJitLinkHandle handle = NULL;
    if (linker->create(&handle, (lto != 0) ? 2u : 1u, options) != NVJITLINK_SUCCESS)
    {
        return cubin;
    }
    const nvJitLinkInputType kind = (lto != 0) ? NVJITLINK_INPUT_LTOIR : NVJITLINK_INPUT_CUBIN;
    const nvJitLinkInputType program_kind = (ptx != 0) ? NVJITLINK_INPUT_PTX : kind;
    size_t size = 0u;
    const int linked = (linker->add(handle, kind, operators->image.data(), operators->image.size(), "cycle_operators")
                        == NVJITLINK_SUCCESS)
                    && (linker->add(handle, program_kind, object.data(), object.size(), "cycle_program")
                        == NVJITLINK_SUCCESS)
                    && (linker->complete(handle) == NVJITLINK_SUCCESS)
                    && (linker->cubin_size(handle, &size) == NVJITLINK_SUCCESS) && (size != 0u);
    if (linked)
    {
        cubin.resize(size);
        if (linker->cubin(handle, cubin.data()) != NVJITLINK_SUCCESS)
        {
            cubin.clear();
        }
    }
    size_t log_size = 0u;
    if (!linked && (report != 0) && (linker->log_size(handle, &log_size) == NVJITLINK_SUCCESS) && (log_size > 1u))
    {
        std::vector<char> log(log_size);
        if (linker->log(handle, log.data()) == NVJITLINK_SUCCESS)
        {
            fprintf(stderr, "  cycle: nvJitLink refused a record program:\n%s\n", log.data());
        }
    }
    linker->destroy(&handle);
    return cubin;
}

// the operator block for the device and the kind of link, built once a process: found in the cache, else compiled and
// kept there. NULL where NVRTC refuses it
static const CycleOperatorBlock *cycle_operator_block(int major, int minor, int lto, int report)
{
    CycleOperatorBlock *const operators = &s_cycle_operator_blocks[(lto != 0) ? 1 : 0];
    if ((operators->tried != 0) && (operators->major == major) && (operators->minor == minor))
    {
        return (operators->ready != 0) ? operators : NULL;
    }
    operators->tried = 1;
    operators->major = major;
    operators->minor = minor;
    operators->source = cycle_operator_source(major, minor, lto);
    operators->hash = cycle_source_hash(operators->source);
    const auto began = std::chrono::steady_clock::now();
    const std::string folder = cycle_cache_folder();
    const std::string path = folder.empty() ? std::string() : cycle_cache_path(folder, operators->source);
    operators->image = path.empty() ? std::vector<char>() : cycle_cache_read(path, operators->source);
    const int found = !operators->image.empty();
    if (!found)
    {
        operators->image = cycle_program_compile(operators->source, "cycle_operators.cu", major, minor, lto, report);
        if (!operators->image.empty() && !path.empty())
        {
            cycle_cache_write(folder, path, operators->source, operators->image);
        }
    }
    const double milliseconds = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
    operators->ready = operators->image.empty() ? 0 : 1;
    if ((report != 0) && (operators->ready != 0))
    {
        fprintf(stderr, "  cycle: the operator block %016llx, %zu bytes of %s, %s for sm_%d%d in %.1f ms\n",
                operators->hash, operators->image.size(), (lto != 0) ? "LTO-IR" : "relocatable cubin",
                found ? "read from the cache" : "compiled", major, minor, milliseconds);
    }
    return (operators->ready != 0) ? operators : NULL;
}

// the .version, .target and .address_size lines of a PTX text, the first of each, in that order; empty where one is
// missing or the address size is not 64, which the lane's pointers are written for
static std::string cycle_ptx_header_lines(const char *ptx)
{
    std::string version;
    std::string target;
    std::string address_size;
    const char *line = ptx;
    while (*line != '\0')
    {
        const char *const end = strchr(line, '\n');
        // a line ends past its start, so its length is never negative
        const size_t length = (end != NULL) ? (size_t)(end - line) : strlen(line);
        const std::string held(line, length);
        if (version.empty() && (held.compare(0u, 9u, ".version ") == 0))
        {
            version = held;
        }
        else if (target.empty() && (held.compare(0u, 8u, ".target ") == 0))
        {
            target = held;
        }
        else if (address_size.empty() && (held.compare(0u, 14u, ".address_size ") == 0))
        {
            address_size = held;
        }
        line = (end != NULL) ? (end + 1) : (line + length);
    }
    const int whole = !version.empty() && !target.empty() && (address_size == ".address_size 64");
    return whole ? (version + "\n" + target + "\n" + address_size + "\n") : std::string();
}

// PTX's header as this toolkit writes it for the device, asked of NVRTC once a process by compiling an empty kernel to
// PTX, the answer kept in the cache against the question: the one part of PTX's rules the lane does not carry itself
struct CyclePtxHeader
{
    int tried;
    int major;
    int minor;
    std::string lines;
};

static CyclePtxHeader s_cycle_ptx_header;

// the header's three lines; empty where NVRTC cannot be asked or does not answer, which leaves programs to the C source
static const std::string &cycle_ptx_header(int major, int minor, int report)
{
    CyclePtxHeader *const header = &s_cycle_ptx_header;
    if ((header->tried != 0) && (header->major == major) && (header->minor == minor))
    {
        return header->lines;
    }
    header->tried = 1;
    header->major = major;
    header->minor = minor;
    header->lines.clear();
    CycleCompiler *const compiler = &s_cycle_compiler;
    if ((compiler->ptx_size == NULL) || (compiler->ptx == NULL))
    {
        return header->lines;
    }
    std::string question;
    cycle_emit(question, "// PTX's header, asked for sm_%d%d of NVRTC %d.%d\n", major, minor, compiler->major,
               compiler->minor);
    question += "extern \"C\" __global__ void cycle_probe(void)\n{\n}\n";
    const std::string folder = cycle_cache_folder();
    const std::string path = folder.empty() ? std::string() : cycle_cache_path(folder, question);
    const std::vector<char> kept = path.empty() ? std::vector<char>() : cycle_cache_read(path, question);
    std::string answer(kept.begin(), kept.end());
    const int found = !answer.empty();
    nvrtcProgram program = NULL;
    if (!found && (compiler->create(&program, question.c_str(), "cycle_probe.cu", 0, NULL, NULL) == NVRTC_SUCCESS))
    {
        char architecture[48];
        snprintf(architecture, sizeof(architecture), "--gpu-architecture=compute_%d%d", major, minor);
        const char *const options[] = {architecture};
        size_t size = 0u;
        if ((compiler->compile(program, 1, options) == NVRTC_SUCCESS)
            && (compiler->ptx_size(program, &size) == NVRTC_SUCCESS) && (size > 1u))
        {
            std::vector<char> ptx(size);
            if (compiler->ptx(program, ptx.data()) == NVRTC_SUCCESS)
            {
                ptx[size - 1u] = '\0';
                answer = cycle_ptx_header_lines(ptx.data());
            }
        }
        compiler->destroy(&program);
        if (!answer.empty() && !path.empty())
        {
            cycle_cache_write(folder, path, question, std::vector<char>(answer.begin(), answer.end()));
        }
    }
    header->lines = answer;
    if (report != 0)
    {
        fprintf(stderr, "  cycle: PTX's header for sm_%d%d %s: %s\n", major, minor,
                found ? "read from the cache" : "asked of NVRTC", answer.empty() ? "none" : answer.c_str());
    }
    return header->lines;
}

// the program found in this process by its text, else in the cache, else built and kept in both, then loaded as a
// library: PTX where `ptx`, which nvJitLink assembles as it links it against the operator block, else C source that
// NVRTC compiles first. `written` is the milliseconds the text took to write, for the report. 0 where the build or the
// load failed
static int cycle_program_hold(const EngineRecordLayout *layout, CycleRecord *record, const CycleOperatorBlock *operators,
                              const std::string &text, int ptx, int lto, double written, int report)
{
    const char *const kind = (ptx != 0) ? "PTX" : ((lto != 0) ? "LTO-IR" : "relocatable cubin");
    for (size_t at = 0u; at < s_cycle_programs.size(); at += 1u)
    {
        if (s_cycle_programs[at].source == text)
        {
            s_cycle_programs[at].holders += 1ull;
            record->kernel = s_cycle_programs[at].kernel;
            record->compiled = 1u;
            if (report != 0)
            {
                fprintf(stderr, "  cycle: a program of %u steps found in this process, as %s\n", layout->steps, kind);
            }
            return 1;
        }
    }
    const std::string folder = cycle_cache_folder();
    const std::string path = folder.empty() ? std::string() : cycle_cache_path(folder, text);
    std::vector<char> cubin = path.empty() ? std::vector<char>() : cycle_cache_read(path, text);
    const int found = !cubin.empty();
    size_t object_bytes = 0u;
    double compile_milliseconds = 0.0;
    double link_milliseconds = 0.0;
    if (!found)
    {
        const auto began = std::chrono::steady_clock::now();
        // PTX goes to nvJitLink as its text with the NUL that ends it
        const std::vector<char> object = (ptx != 0)
                                       ? std::vector<char>(text.c_str(), text.c_str() + text.size() + 1u)
                                       : cycle_program_compile(text, "cycle_program.cu", operators->major,
                                                               operators->minor, lto, report);
        const auto compiled = std::chrono::steady_clock::now();
        cubin = object.empty() ? std::vector<char>() : cycle_program_link(operators, object, lto, ptx, report);
        const auto linked = std::chrono::steady_clock::now();
        object_bytes = object.size();
        compile_milliseconds = std::chrono::duration<double, std::milli>(compiled - began).count();
        link_milliseconds = std::chrono::duration<double, std::milli>(linked - compiled).count();
        if (!cubin.empty() && !path.empty())
        {
            cycle_cache_write(folder, path, text, cubin);
        }
    }
    CycleCompiledProgram program;
    program.library = NULL;
    program.kernel = NULL;
    program.holders = 1ull;
    const int loaded = !cubin.empty()
                    && (cudaLibraryLoadData(&program.library, cubin.data(), NULL, NULL, 0u, NULL, NULL, 0u) == cudaSuccess)
                    && (cudaLibraryGetKernel(&program.kernel, program.library, "cycle_program") == cudaSuccess);
    if (!loaded)
    {
        if (program.library != NULL)
        {
            cudaLibraryUnload(program.library);
        }
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps as %s did not build (%s)\n", layout->steps, kind,
                    cubin.empty() ? ((ptx != 0) ? "nvJitLink refused it" : "NVRTC or nvJitLink refused it")
                                  : "its cubin did not load");
        }
        return 0;
    }
    program.source = text;
    s_cycle_programs.push_back(program);
    record->kernel = program.kernel;
    record->compiled = 1u;
    if ((report != 0) && found)
    {
        fprintf(stderr, "  cycle: a program of %u steps read from the cache, %zu bytes of cubin, as %s\n",
                layout->steps, cubin.size(), kind);
    }
    else if ((report != 0) && (ptx != 0))
    {
        fprintf(stderr, "  cycle: a program of %u steps for sm_%d%d as PTX: written in %.1f ms to %zu bytes, "
                        "assembled and linked in %.1f ms to %zu bytes of cubin\n",
                layout->steps, operators->major, operators->minor, written, object_bytes, link_milliseconds,
                cubin.size());
    }
    else if (report != 0)
    {
        fprintf(stderr, "  cycle: a program of %u steps for sm_%d%d as %s: written in %.1f ms, compiled in %.1f ms to "
                        "%zu bytes, linked in %.1f ms to %zu bytes of cubin\n",
                layout->steps, operators->major, operators->minor, kind, written, compile_milliseconds, object_bytes,
                link_milliseconds, cubin.size());
    }
    return 1;
}

// a hold on a program loaded in this process given back, where `kernel` is one; the last hold released unloads it
void cycle_program_release(cudaKernel_t kernel)
{
    for (size_t at = 0u; (kernel != NULL) && (at < s_cycle_programs.size()); at += 1u)
    {
        if (s_cycle_programs[at].kernel == kernel)
        {
            s_cycle_programs[at].holders -= 1ull;
            if (s_cycle_programs[at].holders == 0ull)
            {
                cudaLibraryUnload(s_cycle_programs[at].library);
                s_cycle_programs.erase(s_cycle_programs.begin() + (std::ptrdiff_t)at);
            }
            break;
        }
    }
}

// the target the emitter writes a lane for: the operator block it is linked against, the device that block was built
// for, the NVRTC loaded, and the prelude
static CycleEmitTarget cycle_emit_target(const CycleOperatorBlock *operators)
{
    return CycleEmitTarget{operators->hash, operators->major, operators->minor, s_cycle_compiler.major,
                           s_cycle_compiler.minor, g_cycle_prelude};
}

// Rule (i): a program held as PTX routed between its two rulesets by its local frame against the device's stack limit.
// A frame past the limit has the runtime grow the stack for every resident thread at a run's first launch, and
// cycle_stack_return gives it back once the run is done: 7.449 to 10.130 ms a run on the record tests, against 0.127 to
// 1.630 ms for frames within the limit (26 September, engine_table item 11(f)). Past the limit the program is built as
// C source as well, and the smaller frame runs, which is the C source's wherever it fits and the PTX's does not; the
// other's hold is given back. Where the C source does not build, or its frame cannot be read, the PTX runs
static void cycle_record_route(const EngineRecordLayout *layout, CycleRecord *record,
                               const CycleOperatorBlock *operators, int lto, int report)
{
    cudaFuncAttributes attributes;
    size_t limit = 0u;
    if ((cudaDeviceGetLimit(&limit, cudaLimitStackSize) != cudaSuccess)
        || (cudaFuncGetAttributes(&attributes, (const void *)record->kernel) != cudaSuccess)
        || (attributes.localSizeBytes <= limit))
    {
        // an error the runtime still holds is the attempt's own, dropped before a run reads it as its own
        cudaGetLastError();
        return;
    }
    const cudaKernel_t ptx = record->kernel;
    const unsigned int ptx_places = record->places;
    const size_t ptx_frame = attributes.localSizeBytes;
    CycleEmitSource &emit = cycle_emit_source();
    const CycleRuleset *const rules = emit.ruleset(report);
    const auto began = std::chrono::steady_clock::now();
    const CycleEmitTarget target = cycle_emit_target(operators);
    unsigned int source_places = 0u;
    unsigned int source_live = 0u;
    const std::string source = (rules != NULL)
                                   ? emit.program(layout, &target, std::string(target.prelude), &source_places,
                                                  &source_live)
                                   : std::string();
    const double written = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
    const int built = !source.empty() && cycle_program_hold(layout, record, operators, source, 0, lto, written, report);
    const int read = built && (cudaFuncGetAttributes(&attributes, (const void *)record->kernel) == cudaSuccess);
    const size_t source_frame = (read != 0) ? attributes.localSizeBytes : 0u;
    const int source_runs = (read != 0) && (source_frame < ptx_frame);
    if (source_runs != 0)
    {
        cycle_program_release(ptx);
        record->places = source_places;
    }
    else
    {
        if (built != 0)
        {
            cycle_program_release(record->kernel);
        }
        record->kernel = ptx;
        record->places = ptx_places;
    }
    cudaGetLastError();
    if (report != 0)
    {
        char held[64];
        snprintf(held, sizeof(held), "a %zu-byte frame", source_frame);
        fprintf(stderr, "  cycle: a program of %u steps as PTX holds a %zu-byte local frame, past the %zu-byte stack "
                        "limit; as C source, %s: it runs as %s\n",
                layout->steps, ptx_frame, limit, (read != 0) ? held : "not built", (source_runs != 0) ? "C" : "PTX");
    }
}

// the program's lane written as PTX and built, else its C source compiled by NVRTC and built, found in this process or
// the cache where either was built before, and the places it holds in shared memory set. PTX is not written where the
// block is LTO-IR or CYCLE_RECORD_NVRTC=1, and a program held as PTX is routed by rule (i). 0 where it stays on the
// interpreter: no NVRTC or nvJitLink, a step neither holds, a C source whose ruleset c.krs was refused, or a compile,
// link or load that failed
int cycle_record_compile(const EngineRecordLayout *layout, CycleRecord *record)
{
    const int report = cycle_environment_set("CYCLE_RECORD_REPORT");
    const int lto = cycle_environment_set("CYCLE_RECORD_LTO");
    int device = 0;
    int major = 0;
    int minor = 0;
    if (!cycle_compiler_ready() || !cycle_linker_ready() || (cudaGetDevice(&device) != cudaSuccess)
        || (cudaDeviceGetAttribute(&major, cudaDevAttrComputeCapabilityMajor, device) != cudaSuccess)
        || (cudaDeviceGetAttribute(&minor, cudaDevAttrComputeCapabilityMinor, device) != cudaSuccess))
    {
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps runs on the interpreter (NVRTC, nvJitLink or the device "
                            "could not be read)\n",
                    layout->steps);
        }
        return 0;
    }
    const CycleOperatorBlock *const operators = cycle_operator_block(major, minor, lto, report);
    if (operators == NULL)
    {
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps runs on the interpreter (the operator block did not "
                            "compile)\n",
                    layout->steps);
        }
        return 0;
    }
    const CycleEmitTarget target = cycle_emit_target(operators);
    if ((lto == 0) && (cycle_environment_set("CYCLE_RECORD_NVRTC") == 0))
    {
        CycleEmitPtx &emit = cycle_emit_ptx();
        const CycleRuleset *const rules = emit.ruleset(report);
        const std::string &header = cycle_ptx_header(major, minor, report);
        unsigned int places = 0u;
        unsigned int live = 0u;
        const auto began = std::chrono::steady_clock::now();
        const std::string ptx = ((rules == NULL) || header.empty())
                                    ? std::string()
                                    : emit.program(layout, &target, header, &places, &live);
        const double written = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
        if ((report != 0) && !ptx.empty())
        {
            fprintf(stderr, "  cycle: a program of %u steps as PTX holds at most %u words live a lane\n", layout->steps,
                    live);
        }
        if (!ptx.empty() && cycle_program_hold(layout, record, operators, ptx, 1, lto, written, report))
        {
            record->places = places;
            cycle_record_route(layout, record, operators, lto, report);
            return 1;
        }
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps goes to NVRTC (%s)\n", layout->steps,
                    (rules == NULL)  ? "its ruleset, ptx.krs, was refused"
                    : header.empty() ? "PTX's header could not be read"
                    : ptx.empty()    ? "a step the lane does not hold, or a form given other arguments than it takes"
                                     : "its PTX did not build");
        }
    }
    CycleEmitSource &source_emit = cycle_emit_source();
    const CycleRuleset *const source_rules = source_emit.ruleset(report);
    const auto began = std::chrono::steady_clock::now();
    unsigned int source_places = 0u;
    unsigned int source_live = 0u;
    const std::string source = (source_rules != NULL)
                                   ? source_emit.program(layout, &target, std::string(target.prelude), &source_places,
                                                         &source_live)
                                   : std::string();
    const double written = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
    if (source.empty())
    {
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps runs on the interpreter (%s)\n", layout->steps,
                    (source_rules == NULL) ? "its C ruleset, c.krs, was refused"
                                           : "a step it does not hold, or a form given other arguments than it takes");
        }
        return 0;
    }
    if (!cycle_program_hold(layout, record, operators, source, 0, lto, written, report))
    {
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps runs on the interpreter\n", layout->steps);
        }
        return 0;
    }
    record->places = source_places;
    return 1;
}
