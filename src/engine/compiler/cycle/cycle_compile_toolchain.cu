// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cycle_compile_toolchain.cu: the environment, the compiler and linker, and the cache's names
#include "cycle_compile_internal.h"

CycleCompiler g_cycle_compiler;

CycleLinker g_cycle_linker;

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

void cycle_format(std::string &text, const char *format, ...)
{
    char line[512];
    va_list arguments;
    va_start(arguments, format);
    const int written = vsnprintf(line, sizeof(line), format, arguments);
    va_end(arguments);
    // a line the capacity does not hold is cut, and the source then fails to compile and never runs wrong; written is
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

int cycle_compiler_ready(void)
{
    CycleCompiler *const compiler = &g_cycle_compiler;
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
    compiler->ready = (version != NULL) && (compiler->create != NULL) && (compiler->compile != NULL) &&
                      (compiler->cubin_size != NULL) && (compiler->cubin != NULL) && (compiler->ltoir_size != NULL) &&
                      (compiler->ltoir != NULL) && (compiler->log_size != NULL) && (compiler->log != NULL) &&
                      (compiler->destroy != NULL) && (version(&compiler->major, &compiler->minor) == NVRTC_SUCCESS);
    return compiler->ready;
}

// one nvJitLink call by its versioned name, __nvJitLink<call>_<major>_<minor> of the toolkit built against
static void *cycle_linker_symbol(void *library, const char *call)
{
    char name[64];
    snprintf(name, sizeof(name), "__nvJitLink%s_%d_%d", call, CUDART_VERSION / 1000, (CUDART_VERSION % 1000) / 10);
    return cycle_compiler_symbol(library, name);
}

int cycle_linker_ready(void)
{
    CycleLinker *const linker = &g_cycle_linker;
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
    linker->ready = (linker->create != NULL) && (linker->add != NULL) && (linker->complete != NULL) &&
                    (linker->cubin_size != NULL) && (linker->cubin != NULL) && (linker->log_size != NULL) &&
                    (linker->log != NULL) && (linker->destroy != NULL);
    return linker->ready;
}

// the target's text for the device and the kind of link, which names both, then the prelude
std::string cycle_target_source(int major, int minor, int lto)
{
    std::string text;
    cycle_format(text, "// a record program's lane, for sm_%d%d, NVRTC %d.%d, as %s\n", major, minor,
                 g_cycle_compiler.major, g_cycle_compiler.minor, (lto != 0) ? "LTO-IR" : "relocatable cubin");
    text += g_cycle_prelude;
    return text;
}

// the folder compiled programs are kept in across processes: $CYCLE_CACHE, else the user's cache, then cycle
std::string cycle_cache_folder(void)
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
unsigned long long cycle_source_hash(const std::string &source)
{
    unsigned long long hash = 0xCBF29CE484222325ull;
    for (size_t at = 0u; at < source.size(); at += 1u)
    {
        // a source byte is read as its unsigned value
        hash = (hash ^ (unsigned long long)(unsigned char)source[at]) * 0x100000001B3ull;
    }
    return hash;
}

// a source's file in the cache, the image built from it (a program's linked cubin, or an answer asked of NVRTC): its
// source's FNV-1a in hex. The name need not be unique: a file is used only where the source it
// holds is this source, byte for byte
std::string cycle_cache_path(const std::string &folder, const std::string &source)
{
    char name[32];
    snprintf(name, sizeof(name), "%016llx.image", cycle_source_hash(source));
#if defined(_WIN32)
    return folder + "\\" + name;
#else
    return folder + "/" + name;
#endif
}
