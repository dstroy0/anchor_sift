// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cycle_compile_route.cu: holding programs, the route and the device's code generator
#include "../codegen/ruleset_reader.h"
#include "cycle_compile_internal.h"

static std::vector<CycleCompiledProgram> s_cycle_programs;

// the program found in this process by its text, else in the cache, else built and kept in both, then loaded as a
// library: PTX where `ptx`, which nvJitLink assembles as it links it alone, else C source that
// NVRTC compiles first. `written` is the milliseconds the text took to write, for the report. 0 where the build or the
// load failed
static int cycle_program_load(const EngineRecordLayout *layout, CycleRecord *record, const CycleTarget *lane_target,
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
        const std::vector<char> object =
            (ptx != 0)
                ? std::vector<char>(text.c_str(), text.c_str() + text.size() + 1u)
                : cycle_program_compile(text, "cycle_program.cu", lane_target->major, lane_target->minor, lto, report);
        const auto compiled = std::chrono::steady_clock::now();
        cubin = object.empty() ? std::vector<char>() : cycle_program_link(lane_target, object, lto, ptx, report);
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
    const int loaded =
        !cubin.empty() &&
        (cudaLibraryLoadData(&program.library, cubin.data(), NULL, NULL, 0u, NULL, NULL, 0u) == cudaSuccess) &&
        (cudaLibraryGetKernel(&program.kernel, program.library, "cycle_program") == cudaSuccess);
    if (!loaded)
    {
        if (program.library != NULL)
        {
            cudaLibraryUnload(program.library);
        }
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps as %s did not build (%s)\n", layout->steps, kind,
                    cubin.empty() ? ((ptx != 0) ? "nvJitLink errored on it" : "NVRTC or nvJitLink errored on it")
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
        fprintf(stderr,
                "  cycle: a program of %u steps for sm_%d%d as PTX: written in %.1f ms to %zu bytes, "
                "assembled and linked in %.1f ms to %zu bytes of cubin\n",
                layout->steps, lane_target->major, lane_target->minor, written, object_bytes, link_milliseconds,
                cubin.size());
    }
    else if (report != 0)
    {
        fprintf(stderr,
                "  cycle: a program of %u steps for sm_%d%d as %s: written in %.1f ms, compiled in %.1f ms to "
                "%zu bytes, linked in %.1f ms to %zu bytes of cubin\n",
                layout->steps, lane_target->major, lane_target->minor, kind, written, compile_milliseconds,
                object_bytes, link_milliseconds, cubin.size());
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

// the target the code generator writes a lane for: the target's hash, its device, the NVRTC loaded, and the prelude
static TargetInfo cycle_target_info(const CycleTarget *lane_target)
{
    return TargetInfo{lane_target->hash,      lane_target->major,     lane_target->minor,
                      g_cycle_compiler.major, g_cycle_compiler.minor, g_cycle_prelude};
}

// Rule (i): a program held as PTX routed between its two rulesets by its local frame against the device's stack limit.
// A frame past the limit has the runtime grow the stack for every resident thread at a run's first launch, and
// cycle_stack_return gives it back once the run is done: 7.449 to 10.130 ms a run on the record tests, against 0.127 to
// 1.630 ms for frames within the limit (26 September, engine_table item 11(f)). Past the limit the program is built as
// C source as well, and the smaller frame runs, the C source's wherever it fits and the PTX's does not; the
// other's hold is given back. Where the C source does not build, or its frame cannot be read, the PTX runs.
// CYCLE_RECORD_KEEP_PTX=1 turns the rule off: a program held as PTX runs as PTX
static void cycle_record_route(const EngineRecordLayout *layout, CycleRecord *record, const CycleTarget *lane_target,
                               int lto, int report)
{
    cudaFuncAttributes attributes;
    size_t limit = 0u;
    if ((cudaDeviceGetLimit(&limit, cudaLimitStackSize) != cudaSuccess) ||
        (cudaFuncGetAttributes(&attributes, (const void *)record->kernel) != cudaSuccess) ||
        (attributes.localSizeBytes <= limit))
    {
        // an error the runtime still holds is the attempt's own, dropped before a run reads it as its own
        cudaGetLastError();
        return;
    }
    const cudaKernel_t ptx = record->kernel;
    const unsigned int ptx_places = record->places;
    const size_t ptx_frame = attributes.localSizeBytes;
    CTarget &generator = c_target();
    const Ruleset *const rules = generator.ruleset(report);
    const auto began = std::chrono::steady_clock::now();
    const TargetInfo target = cycle_target_info(lane_target);
    unsigned int source_places = 0u;
    unsigned int source_live = 0u;
    const std::string source =
        (rules != NULL) ? generator.program(layout, &target, std::string(target.prelude), &source_places, &source_live)
                        : std::string();
    const double written = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
    const int built =
        !source.empty() && cycle_program_load(layout, record, lane_target, source, 0, lto, written, report);
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
        char character[64];
        snprintf(character, sizeof(character), "a %zu-byte frame", source_frame);
        fprintf(stderr,
                "  cycle: a program of %u steps as PTX holds a %zu-byte local frame, past the %zu-byte stack "
                "limit; as C source, %s: it runs as %s\n",
                layout->steps, ptx_frame, limit, (read != 0) ? character : "not built",
                (source_runs != 0) ? "C" : "PTX");
    }
}

// How deep the device's writing of lanes stands in this thread. 0 where none is under way. 1 while the device writes a
// lane: the assembly printer's own program is compiled then, and the device writes its lane too. 2 while the device
// writes the assembly printer's own lane: the assembly printer then runs on the interpreter, the one program not
// compiled, and the bootstrap closes there
static thread_local int s_cycle_codegen_depth = 0;

// the depth at which the assembly printer writes its own lane
#define CYCLE_CODEGEN_OWN_LANE 2

// the texts the device wrote in this process and the host's matched; each is written once
static std::vector<std::string> s_cycle_codegen_written;

// The lane as the device writes it from the step table (codegen_device.h), the path every lane takes: the ruleset's
// file read on the device and its written forms laid out once for the target and the header, the forms decided on the
// device a thread a step, laid out as the assembly printer's records there, written by the record machine a lane a byte
// and gathered. The host code generator's text is the check: the device's ruleset, its written forms and its text are
// held to the host's word for word and byte for byte. Returns 1 where the device's text is the one built, and 0, with
// the step that differed on stderr, where the device did not write it or any of the three is apart from the host's.
// The device splits the lane where `generator`'s program() splits it. A text the device wrote before in this process
// is not written again
static int cycle_codegen_on_device(const CodeGenerator &generator, const Ruleset *rules, const TargetInfo *target,
                                   const std::string &header, const EngineRecordLayout *layout, unsigned int places,
                                   int report, std::string &text)
{
    for (size_t at = 0u; at < s_cycle_codegen_written.size(); at += 1u)
    {
        if (s_cycle_codegen_written[at] == text)
        {
            if (report != 0)
            {
                fprintf(stderr, "  cycle: the device wrote a program of %u steps, %zu bytes, before in this process\n",
                        layout->steps, text.size());
            }
            return 1;
        }
    }
    AsmPrinterRuleset text_rules{};
    std::string error;
    std::string written;
    ScheduleCosts costs;
    const int has_costs = generator.program_schedule_costs(&costs);
    s_cycle_codegen_depth += 1;
    const int built = asm_printer_ruleset_build(rules, target, header, &text_rules, &error);
    // the ruleset's file read on the device as well, and the device's built from where it is the host's as read
    Ruleset device_read{};
    device_read.schema = rules->schema;
    std::string read_error;
    const int read_ran = built && ruleset_read_device(&device_read, rules->path, &read_error);
    const int read_same = read_ran && ruleset_same(&device_read, rules);
    if (read_same != 0)
    {
        device_read.tried = rules->tried;
        device_read.ready = rules->ready;
        if (report != 0)
        {
            fprintf(stderr, "  cycle: the device read the ruleset %s as the host did\n", rules->name.c_str());
        }
    }
    else if (read_ran != 0)
    {
        fprintf(stderr, "  cycle: the device read the ruleset %s apart from the host\n", rules->name.c_str());
    }
    else if (built != 0)
    {
        fprintf(stderr, "  cycle: the device did not read the ruleset %s (%s)\n", rules->name.c_str(),
                read_error.c_str());
    }
    // the ruleset built on the device as well, and the device's written from where it is the host's word for word
    AsmPrinterRuleset device_rules{};
    std::string device_error;
    const int device_built = built && asm_printer_ruleset_device((read_same != 0) ? &device_read : rules, target,
                                                                 header, &device_rules, &device_error);
    const int rules_same = device_built && asm_printer_ruleset_same(&device_rules, &text_rules);
    if ((rules_same != 0) && (report != 0))
    {
        fprintf(stderr, "  cycle: the device built the assembly printer's ruleset, word for word the host's\n");
    }
    else if ((rules_same == 0) && (device_built != 0))
    {
        fprintf(stderr, "  cycle: the device built the assembly printer's ruleset apart from the host's\n");
    }
    else if ((rules_same == 0) && (built != 0))
    {
        fprintf(stderr, "  cycle: the device did not build the assembly printer's ruleset (%s)\n",
                device_error.c_str());
    }
    // the lane is written only from the device's own ruleset, read and built where it is the host's
    if ((built != 0) && ((read_same == 0) || (rules_same == 0)))
    {
        error = "its ruleset on the device is not the host's";
    }
    const int ran = (read_same != 0) && (rules_same != 0) &&
                    codegen_device(layout, &device_rules, places, has_costs ? &costs : NULL, &written, &error);
    if (built)
    {
        asm_printer_ruleset_release(&text_rules);
    }
    if (device_built)
    {
        asm_printer_ruleset_release(&device_rules);
    }
    s_cycle_codegen_depth -= 1;
    size_t differs = 0u;
    while ((differs < written.size()) && (differs < text.size()) && (written[differs] == text[differs]))
    {
        differs += 1u;
    }
    const int same = (ran != 0) && (written == text);
    if ((same != 0) && (report != 0))
    {
        fprintf(stderr, "  cycle: the device wrote a program of %u steps, %zu bytes, byte for byte the host's\n",
                layout->steps, written.size());
    }
    else if ((same == 0) && (ran != 0))
    {
        fprintf(stderr,
                "  cycle: the device wrote a program of %u steps as %zu bytes against the host's %zu, apart "
                "from byte %zu\n",
                layout->steps, written.size(), text.size(), differs);
    }
    else if (same == 0)
    {
        fprintf(stderr, "  cycle: the device did not write a program of %u steps (%s)\n", layout->steps, error.c_str());
    }
    if (same != 0)
    {
        text = written;
        s_cycle_codegen_written.push_back(written);
    }
    return same;
}

// the program's lane written as PTX and built, else its C source compiled by NVRTC and built, found in this process or
// the cache where either was built before, and the places it holds in shared memory set. PTX is not written where the
// block is LTO-IR, CYCLE_RECORD_NVRTC=1 or CYCLE_RECORD_HOST_C=1, and a program held as PTX is routed by rule (i).
// Under CYCLE_RECORD_HOST_C=1 the C source is built by the host's compiler in place of NVRTC. 0 where it stays on the
// interpreter: no NVRTC or nvJitLink, a step neither holds, a C source whose ruleset c.krs errored, a compile, link
// or load that failed, or the assembly printer run while it writes its own lane. Every lane is written by the device
// (cycle_codegen_on_device) but the assembly printer's own: CYCLE_ERROR, with ENGINE_ERROR_LOGIC in `error`, where
// the device's lane is not the host code generator's
int cycle_record_compile(const EngineRecordLayout *layout, CycleRecord *record, EngineError *error)
{
    const int report = cycle_environment_set("CYCLE_RECORD_REPORT");
    const int lto = cycle_environment_set("CYCLE_RECORD_LTO");
    if (s_cycle_codegen_depth >= CYCLE_CODEGEN_OWN_LANE)
    {
        if (report != 0)
        {
            fprintf(stderr,
                    "  cycle: the assembly printer's program of %u steps runs on the interpreter to write its "
                    "own lane\n",
                    layout->steps);
        }
        return 0;
    }
    int device = 0;
    int major = 0;
    int minor = 0;
    if (!cycle_compiler_ready() || !cycle_linker_ready() || (cudaGetDevice(&device) != cudaSuccess) ||
        (cudaDeviceGetAttribute(&major, cudaDevAttrComputeCapabilityMajor, device) != cudaSuccess) ||
        (cudaDeviceGetAttribute(&minor, cudaDevAttrComputeCapabilityMinor, device) != cudaSuccess))
    {
        if (report != 0)
        {
            fprintf(stderr,
                    "  cycle: a program of %u steps runs on the interpreter (NVRTC, nvJitLink or the device "
                    "could not be read)\n",
                    layout->steps);
        }
        return 0;
    }
    const CycleTarget *const lane_target = cycle_target(major, minor, lto, report);
    const TargetInfo target = cycle_target_info(lane_target);
    const int host = cycle_environment_set("CYCLE_RECORD_HOST_C");
    if ((lto == 0) && (host == 0) && (cycle_environment_set("CYCLE_RECORD_NVRTC") == 0))
    {
        PtxTarget &generator = ptx_target();
        const Ruleset *const rules = generator.ruleset(report);
        const std::string &header = cycle_ptx_header(major, minor, report);
        unsigned int places = 0u;
        unsigned int live = 0u;
        const auto began = std::chrono::steady_clock::now();
        std::string ptx = ((rules == NULL) || header.empty())
                              ? std::string()
                              : generator.program(layout, &target, header, &places, &live);
        const double written =
            std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
        if (!ptx.empty() &&
            !CYCLE_CHECK(cycle_codegen_on_device(generator, rules, &target, header, layout, places, report, ptx),
                         layout, error, ENGINE_ERROR_LOGIC))
        {
            return (int)CYCLE_ERROR;
        }
        if ((report != 0) && !ptx.empty())
        {
            fprintf(stderr, "  cycle: a program of %u steps as PTX holds at most %u words live a lane\n", layout->steps,
                    live);
        }
        if (!ptx.empty() && cycle_program_load(layout, record, lane_target, ptx, 1, lto, written, report))
        {
            record->places = places;
            if (cycle_environment_set("CYCLE_RECORD_KEEP_PTX") == 0)
            {
                cycle_record_route(layout, record, lane_target, lto, report);
            }
            return 1;
        }
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps goes to NVRTC (%s)\n", layout->steps,
                    (rules == NULL)  ? "its ruleset, ptx.krs, errored"
                    : header.empty() ? "PTX's header could not be read"
                    : ptx.empty()    ? "a step the lane does not hold, or a form given other arguments than it takes"
                                     : "its PTX did not build");
        }
    }
    CTarget &source_generator = c_target();
    const Ruleset *const source_rules = source_generator.ruleset(report);
    const auto began = std::chrono::steady_clock::now();
    unsigned int source_places = 0u;
    unsigned int source_live = 0u;
    std::string source = (source_rules != NULL) ? source_generator.program(layout, &target, std::string(target.prelude),
                                                                           &source_places, &source_live)
                                                : std::string();
    const double written = std::chrono::duration<double, std::milli>(std::chrono::steady_clock::now() - began).count();
    if (!source.empty() &&
        !CYCLE_CHECK(cycle_codegen_on_device(source_generator, source_rules, &target, std::string(target.prelude),
                                             layout, source_places, report, source),
                     layout, error, ENGINE_ERROR_LOGIC))
    {
        return (int)CYCLE_ERROR;
    }
    if (source.empty())
    {
        if (report != 0)
        {
            fprintf(stderr, "  cycle: a program of %u steps runs on the interpreter (%s)\n", layout->steps,
                    (source_rules == NULL) ? "its C ruleset, c.krs, errored"
                                           : "a step it does not hold, or a form given other arguments than it takes");
        }
        return 0;
    }
    const int loaded = (host != 0) ? cycle_host_program_load(layout, record, source, source_places, written, report)
                                   : cycle_program_load(layout, record, lane_target, source, 0, lto, written, report);
    if (loaded == 0)
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
