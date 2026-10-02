// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// interface_ptx_probe_main.cu: the header, the kernel, building, running and main
#include "interface_ptx_probe_internal.h"

// PTX's header for the device, asked of NVRTC by compiling an empty kernel to PTX: the .version, .target and
// .address_size lines. Empty where NVRTC does not answer
static std::string probe_header(int major, int minor)
{
    const char question[] = "extern \"C\" __global__ void interface_header(void)\n{\n}\n";
    nvrtcProgram program = NULL;
    std::string lines;
    if (nvrtcCreateProgram(&program, question, "interface_header.cu", 0, NULL, NULL) != NVRTC_SUCCESS)
    {
        return lines;
    }
    char architecture[48];
    snprintf(architecture, sizeof(architecture), "--gpu-architecture=compute_%d%d", major, minor);
    const char *const options[] = {architecture};
    size_t size = 0u;
    if ((nvrtcCompileProgram(program, 1, options) == NVRTC_SUCCESS) &&
        (nvrtcGetPTXSize(program, &size) == NVRTC_SUCCESS) && (size > 1u))
    {
        std::vector<char> ptx(size);
        if (nvrtcGetPTX(program, ptx.data()) == NVRTC_SUCCESS)
        {
            ptx[size - 1u] = '\0';
            const char *const wanted[] = {".version ", ".target ", ".address_size "};
            for (const char *const start : wanted)
            {
                const char *const found = strstr(ptx.data(), start);
                const char *const end = (found != NULL) ? strchr(found, '\n') : NULL;
                // a line ends past its start
                lines += (end != NULL) ? (std::string(found, (size_t)(end - found)) + "\n") : std::string();
            }
        }
    }
    nvrtcDestroyProgram(&program);
    return lines;
}

// the kernel: the header, then an entry of this probe's own that finds its case, loads its eight words into
// temporaries 0 to 7 through the ruleset's global_load, sets outputs 8 to 11 to 0, runs the body, and stores the
// outputs through the ruleset's record_store, the record register set to the case's output
static std::string probe_kernel(ProbeWriter *writer, const std::string &header, const std::string &body)
{
    std::string text = header;
    text += "\n.visible .entry interface_ask(\n\t.param .u64 interface_ask_in,\n\t.param .u64 interface_ask_out,\n\t.param .u32 "
            "interface_ask_count\n)\n{\n";
    text += "\t.reg .pred \t%interface_past;\n\t.reg .b32 \t%interface_word<4>;\n\t.reg .b64 \t%interface_wide<4>;\n";
    const std::string declared = std::to_string(PROBE_DECLARED);
    probe_form(writer, text, "declare_predicates", {declared});
    probe_form(writer, text, "declare_fixed_predicates", {});
    probe_form(writer, text, "declare_temporaries", {declared});
    probe_form(writer, text, "declare_wides", {declared});
    probe_form(writer, text, "declare_fixed_words", {});
    probe_form(writer, text, "declare_fixed_wides", {});
    probe_form(writer, text, "word_set", {ruleset_physreg(writer->rules, "zero"), "0"});
    text += "\tld.param.u64 \t%interface_wide0, [interface_ask_in];\n\tld.param.u64 \t%interface_wide1, [interface_ask_out];\n";
    text += "\tld.param.u32 \t%interface_word0, [interface_ask_count];\n\tmov.u32 \t%interface_word1, %ctaid.x;\n";
    text += "\tmov.u32 \t%interface_word2, %ntid.x;\n\tmov.u32 \t%interface_word3, %tid.x;\n";
    text += "\tmad.lo.u32 \t%interface_word1, %interface_word1, %interface_word2, %interface_word3;\n";
    text += "\tsetp.ge.u32 \t%interface_past, %interface_word1, %interface_word0;\n\t@%interface_past bra \t$Linterface_done;\n";
    text += "\tcvta.to.global.u64 \t%interface_wide0, %interface_wide0;\n\tcvta.to.global.u64 \t%interface_wide1, %interface_wide1;\n";
    text += "\tmul.wide.u32 \t%interface_wide2, %interface_word1, 32;\n\tadd.s64 \t%interface_wide2, %interface_wide0, %interface_wide2;\n";
    text += "\tmul.wide.u32 \t%interface_wide3, %interface_word1, 16;\n\tadd.s64 \t%interface_wide3, %interface_wide1, %interface_wide3;\n";
    for (unsigned int word = 0u; word < PROBE_IN_WORDS; word += 1u)
    {
        probe_form(writer, text, "global_load",
                   {probe_temporary(writer, word), "%interface_wide2", std::to_string(word * 4u)});
    }
    for (unsigned int word = 0u; word < PROBE_OUT_WORDS; word += 1u)
    {
        probe_form(writer, text, "word_set", {probe_temporary(writer, 8u + word), "0"});
    }
    text += body;
    text += "\tmov.b64 \t" + ruleset_physreg(writer->rules, "record") + ", %interface_wide3;\n";
    for (unsigned int word = 0u; word < PROBE_OUT_WORDS; word += 1u)
    {
        probe_form(writer, text, "record_store", {std::to_string(word * 4u), probe_temporary(writer, 8u + word)});
    }
    text += "$Linterface_done:\n";
    probe_form(writer, text, "return", {});
    text += "}\n";
    return text;
}

// the kernel's text assembled by nvJitLink for the device: 1 and its cubin, or 0 with the log printed
static int probe_assemble(const std::string &text, int major, int minor, std::vector<char> &cubin)
{
    char architecture[32];
    snprintf(architecture, sizeof(architecture), "-arch=sm_%d%d", major, minor);
    const char *options[] = {architecture};
    nvJitLinkHandle handle = NULL;
    if (nvJitLinkCreate(&handle, 1u, options) != NVJITLINK_SUCCESS)
    {
        printf("errored: nvJitLink could not be made\n");
        return 0;
    }
    size_t size = 0u;
    const int linked = (nvJitLinkAddData(handle, NVJITLINK_INPUT_PTX, text.c_str(), text.size() + 1u, "interface_ask") ==
                        NVJITLINK_SUCCESS) &&
                       (nvJitLinkComplete(handle) == NVJITLINK_SUCCESS) &&
                       (nvJitLinkGetLinkedCubinSize(handle, &size) == NVJITLINK_SUCCESS) && (size != 0u);
    cubin.assign(linked ? size : 0u, '\0');
    const int taken = linked && (nvJitLinkGetLinkedCubin(handle, cubin.data()) == NVJITLINK_SUCCESS);
    if (!taken)
    {
        size_t log_size = 0u;
        std::vector<char> log(1u, '\0');
        if ((nvJitLinkGetErrorLogSize(handle, &log_size) == NVJITLINK_SUCCESS) && (log_size > 1u))
        {
            log.assign(log_size, '\0');
            nvJitLinkGetErrorLog(handle, log.data());
        }
        printf("errored: nvJitLink did not assemble the kernel\n%s\n", log.data());
    }
    nvJitLinkDestroy(&handle);
    return taken;
}

// the kernel's text assembled and loaded: 1 and the kernel, or 0 with the log printed
static int probe_build(const std::string &text, int major, int minor, cudaLibrary_t *library, cudaKernel_t *kernel)
{
    std::vector<char> cubin;
    return probe_assemble(text, major, minor, cubin) &&
           (cudaLibraryLoadData(library, cubin.data(), NULL, NULL, 0u, NULL, NULL, 0u) == cudaSuccess) &&
           (cudaLibraryGetKernel(kernel, *library, "interface_ask") == cudaSuccess);
}

// the kernel's text assembled and written to `path`: 1, or 0 with the reason printed
static int probe_write(const std::string &text, int major, int minor, const std::string &path)
{
    std::vector<char> cubin;
    if (!probe_assemble(text, major, minor, cubin))
    {
        return 0;
    }
    FILE *const file = fopen(path.c_str(), "wb");
    const int written = (file != NULL) && (fwrite(cubin.data(), 1u, cubin.size(), file) == cubin.size());
    const int closed = (file != NULL) && (fclose(file) == 0);
    if (!written || !closed)
    {
        printf("errored: %s could not be written\n", path.c_str());
    }
    return written && closed;
}

// the machine code of each membership question for the SASS probe (interface_sass_probe.c): the frame with no body
// assembled into `folder`/frame.cubin and each question's kernel into `folder`/form_<number>.cubin, a line
// "cubin <number> <name>" printed for each. Exit 0 where every cubin was written, 2 where one was not
// The program resident as its own module: an empty lane for the resident's call to reach, then program_unit with
// the launch's own layout in its 25 parameters. No question covers this part of a program, and no hand
// should write twice - the resident is 110 instructions of PTX that already runs, and the part's own compiler turns
// it into SASS that already runs. Asking for that is what the SASS probe does with every other form, and what comes
// back is the floor a rearrangement has to beat
static std::string probe_resident(ProbeWriter *writer, const std::string &header)
{
    std::string text = header;
    probe_form(writer, text, "lane_open", {});
    probe_form(writer, text, "return", {});
    probe_form(writer, text, "lane_close", {});
    std::vector<std::string> arguments;
    for (unsigned int at = 0u; at < PROGRAM_UNIT_PARAMETERS; at += 1u)
    {
        arguments.push_back(std::to_string(codegen_unit(at)));
    }
    probe_form(writer, text, "program_unit", arguments);
    return text;
}

static int probe_cubins(ProbeWriter *writer, const std::string &header, int major, int minor, const char *folder)
{
    const std::vector<ProbeQuestion> questions = probe_questions(writer);
    const std::string frame = probe_kernel(writer, header, std::string());
    if (writer->broken || !probe_write(frame, major, minor, std::string(folder) + "/frame.cubin"))
    {
        printf("frame: not written\n");
        return 2;
    }
    const std::string resident = probe_resident(writer, header);
    if (writer->broken || !probe_write(resident, major, minor, std::string(folder) + "/resident.cubin"))
    {
        printf("resident: not written\n");
        return 2;
    }
    for (size_t number = 0u; number < questions.size(); number += 1u)
    {
        const std::string text = probe_kernel(writer, header, questions[number].body);
        const std::string path = std::string(folder) + "/form_" + std::to_string(number) + ".cubin";
        if (writer->broken || !probe_write(text, major, minor, path))
        {
            printf("%s: not written\n", questions[number].name.c_str());
            return 2;
        }
        printf("cubin %zu %s\n", number, questions[number].name.c_str());
    }
    printf("cubins: %zu questions\n", questions.size());
    return 0;
}

// the kernel run over `count` cases of `in`, its outputs into `out`; the CUDA error the run gave
static cudaError_t probe_run(cudaKernel_t kernel, const unsigned int *in, unsigned int *out, unsigned int count)
{
    unsigned int *device_in = NULL;
    unsigned int *device_out = NULL;
    const size_t in_bytes = (size_t)count * PROBE_IN_WORDS * sizeof(unsigned int);
    const size_t out_bytes = (size_t)count * PROBE_OUT_WORDS * sizeof(unsigned int);
    cudaError_t status = cudaMalloc((void **)&device_in, in_bytes);
    status = (status == cudaSuccess) ? cudaMalloc((void **)&device_out, out_bytes) : status;
    status = (status == cudaSuccess) ? cudaMemcpy(device_in, in, in_bytes, cudaMemcpyHostToDevice) : status;
    void *arguments[] = {(void *)&device_in, (void *)&device_out, (void *)&count};
    const unsigned int blocks = (count + PROBE_THREADS - 1u) / PROBE_THREADS;
    status = (status == cudaSuccess)
                 ? cudaLaunchKernel((const void *)kernel, dim3(blocks), dim3(PROBE_THREADS), arguments, 0u, NULL)
                 : status;
    status = (status == cudaSuccess) ? cudaDeviceSynchronize() : status;
    status = (status == cudaSuccess) ? cudaMemcpy(out, device_out, out_bytes, cudaMemcpyDeviceToHost) : status;
    cudaFree(device_in);
    cudaFree(device_out);
    return status;
}

// the error a question the device errored gave, then the error the next allocation gives: whether the context
// survived the error
static int probe_error(cudaError_t status)
{
    printf("error %d %s\n", (int)status, cudaGetErrorName(status));
    void *after = NULL;
    const cudaError_t next = cudaMalloc(&after, 4u);
    printf("after %d %s\n", (int)next, cudaGetErrorName(next));
    return 3;
}

static int probe_membership(ProbeWriter *writer, const std::string &header, int major, int minor)
{
    const std::vector<ProbeQuestion> questions = probe_questions(writer);
    if (writer->broken)
    {
        return 2;
    }
    std::vector<unsigned int> in((size_t)PROBE_CASES * PROBE_IN_WORDS);
    for (unsigned int number = 0u; number < PROBE_CASES; number += 1u)
    {
        probe_case(number, &in[(size_t)number * PROBE_IN_WORDS]);
    }
    std::vector<unsigned int> out((size_t)PROBE_CASES * PROBE_OUT_WORDS);
    unsigned int disagreed = 0u;
    for (const ProbeQuestion &question : questions)
    {
        const std::string text = probe_kernel(writer, header, question.body);
        cudaLibrary_t library = NULL;
        cudaKernel_t kernel = NULL;
        if (writer->broken || !probe_build(text, major, minor, &library, &kernel))
        {
            printf("%s: not built\n", question.name.c_str());
            return 2;
        }
        const cudaError_t status = probe_run(kernel, in.data(), out.data(), PROBE_CASES);
        cudaLibraryUnload(library);
        if (status != cudaSuccess)
        {
            printf("%s: ", question.name.c_str());
            return probe_error(status);
        }
        unsigned int agree = 0u;
        unsigned int differ = 0u;
        unsigned int undefined = 0u;
        std::vector<unsigned int> seen;
        for (unsigned int number = 0u; number < PROBE_CASES; number += 1u)
        {
            const unsigned int *const case_in = &in[(size_t)number * PROBE_IN_WORDS];
            const unsigned int *const case_out = &out[(size_t)number * PROBE_OUT_WORDS];
            unsigned int wanted[PROBE_OUT_WORDS] = {0u, 0u, 0u, 0u};
            if (!question.rule(case_in, wanted))
            {
                undefined += 1u;
                // the device's answer to a question the rule leaves undefined, each distinct word once, the first four
                for (unsigned int word = 0u; (word < question.outputs) && (seen.size() < 4u); word += 1u)
                {
                    int known = 0;
                    for (const unsigned int earlier : seen)
                    {
                        known = known || (earlier == case_out[word]);
                    }
                    if (!known)
                    {
                        seen.push_back(case_out[word]);
                    }
                }
                continue;
            }
            int agrees = 1;
            for (unsigned int word = 0u; word < question.outputs; word += 1u)
            {
                agrees = agrees && (case_out[word] == wanted[word]);
            }
            agree += agrees ? 1u : 0u;
            if (!agrees && (differ < 3u))
            {
                printf("  %s differs on case %u: in %08x %08x %08x %08x %08x %08x, device %08x %08x %08x %08x, host "
                       "%08x %08x %08x %08x\n",
                       question.name.c_str(), number, case_in[0], case_in[1], case_in[2], case_in[3], case_in[4],
                       case_in[5], case_out[0], case_out[1], case_out[2], case_out[3], wanted[0], wanted[1], wanted[2],
                       wanted[3]);
            }
            differ += agrees ? 0u : 1u;
        }
        disagreed += (differ != 0u) ? 1u : 0u;
        printf("form %s: %u cases, %u agree, %u differ", question.name.c_str(), agree + differ, agree, differ);
        if (undefined != 0u)
        {
            printf(", %u undefined, the device answering", undefined);
            for (const unsigned int word : seen)
            {
                printf(" %08x", word);
            }
        }
        printf("\n");
    }
    printf("membership: %zu questions, %u with a case that differs\n", questions.size(), disagreed);
    return (disagreed == 0u) ? 0 : 1;
}

// a kernel whose body is `body` alone, run over one case; `address` names the case's input, which the body may
// replace. Exit 0 where the device answers, 3 where it errors on the run, 4 where the toolchain errors on the kernel
static int probe_single(ProbeWriter *writer, const std::string &header, const std::string &body, int major, int minor)
{
    const std::string text = probe_kernel(writer, header, body);
    cudaLibrary_t library = NULL;
    cudaKernel_t kernel = NULL;
    if (writer->broken)
    {
        return 2;
    }
    if (!probe_build(text, major, minor, &library, &kernel))
    {
        return 4;
    }
    unsigned int in[PROBE_IN_WORDS] = {6u, 7u, 0u, 0u, 0u, 0u, 0u, 0u};
    unsigned int out[PROBE_OUT_WORDS] = {0u, 0u, 0u, 0u};
    const cudaError_t status = probe_run(kernel, in, out, 1u);
    if (status != cudaSuccess)
    {
        return probe_error(status);
    }
    printf("answered %08x %08x %08x %08x\n", out[0], out[1], out[2], out[3]);
    cudaLibraryUnload(library);
    return 0;
}

// the cubin at `path` loaded and its kernel interface_ask run over one case, whose input words are `arguments`: the four
// output words printed. Exit 0 where the device answers, 3 where it errors on the run, 4 where it will not load
// Every clock the part will name, asked of it, not assumed. A part is a clocked thing and everything it does
// is transitions at some rate: what rates it has is a question it can answer, and the answer is the unit every
// cost is read in. The part's own clock register is not needed for that, and is not in the machine: the host's clock
// times a run from outside (probe_cubin_run), and these say what one tick is worth
static int probe_clocks(int device)
{
    static const struct
    {
        cudaDeviceAttr attribute;
        const char *name;
        const char *unit;
    } asked[] = {
        {cudaDevAttrClockRate, "the part's clock", "kHz"},
        {cudaDevAttrMemoryClockRate, "the memory's clock", "kHz"},
        {cudaDevAttrGlobalMemoryBusWidth, "the memory's bus", "bits"},
        {cudaDevAttrMultiProcessorCount, "the part's multiprocessors", ""},
        {cudaDevAttrWarpSize, "a warp", "lanes"},
        {cudaDevAttrMaxThreadsPerMultiProcessor, "a multiprocessor's threads", ""},
        // what the register file holds against what a thread may take: their ratio is how many registers a thread
        // can hold and still fill the part, and a lane past it loses threads in step. That is where a knee is
        {cudaDevAttrMaxRegistersPerMultiprocessor, "a multiprocessor's registers", ""},
        {cudaDevAttrMaxRegistersPerBlock, "a block's registers", ""},
        {cudaDevAttrL2CacheSize, "the second level cache", "bytes"},
    };
    for (unsigned int at = 0u; at < (sizeof(asked) / sizeof(asked[0])); at += 1u)
    {
        int value = 0;
        const cudaError_t got = cudaDeviceGetAttribute(&value, asked[at].attribute, device);
        printf("  %-28s %s", asked[at].name, (got == cudaSuccess) ? "" : "the part does not say\n");
        if (got == cudaSuccess)
        {
            printf("%d %s\n", value, asked[at].unit);
        }
    }
    return 0;
}

static int probe_cubin_run(const char *path, int count, char **arguments)
{
    std::vector<char> cubin;
    FILE *const file = fopen(path, "rb");
    if (file != NULL)
    {
        char block[4096];
        size_t read = fread(block, 1u, sizeof(block), file);
        while (read != 0u)
        {
            cubin.insert(cubin.end(), block, block + read);
            read = fread(block, 1u, sizeof(block), file);
        }
        fclose(file);
    }
    cudaLibrary_t library = NULL;
    cudaKernel_t kernel = NULL;
    if (cubin.empty())
    {
        printf("the cubin at %s was not read\n", path);
        return 4;
    }
    const cudaError_t loaded = cudaLibraryLoadData(&library, cubin.data(), NULL, NULL, 0u, NULL, NULL, 0u);
    if ((loaded != cudaSuccess) || (cudaLibraryGetKernel(&kernel, library, "interface_ask") != cudaSuccess))
    {
        printf("the cubin at %s did not load (%s)\n", path, cudaGetErrorName(loaded));
        return 4;
    }
    unsigned int in[PROBE_IN_WORDS] = {0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u};
    for (int word = 0; (word < (count - 3)) && (word < (int)PROBE_IN_WORDS); word += 1)
    {
        // a word the caller gives in hex, which fits an unsigned int
        in[word] = (unsigned int)strtoul(arguments[3 + word], NULL, 16);
    }
    unsigned int out[PROBE_OUT_WORDS] = {0u, 0u, 0u, 0u};
    const cudaError_t status = probe_run(kernel, in, out, 1u);
    if (status != cudaSuccess)
    {
        return probe_error(status);
    }
    printf("answered %08x %08x %08x %08x\n", out[0], out[1], out[2], out[3]);
    // The run timed by our own clock, which is all a cost needs: the part's clock register is not in the machine,
    // and a run measured from outside says what a kernel costs whatever the part will name. The run above is not
    // counted, since it carries the library load and the first launch
    const char *const repeats = getenv("PROBE_REPEATS");
    const unsigned long runs = (repeats != NULL) ? strtoul(repeats, NULL, 10) : 0ul;
    if (runs != 0ul)
    {
        const std::chrono::steady_clock::time_point opened = std::chrono::steady_clock::now();
        for (unsigned long run = 0ul; run < runs; run += 1ul)
        {
            probe_run(kernel, in, out, 1u);
        }
        const std::chrono::steady_clock::time_point closed = std::chrono::steady_clock::now();
        const double taken = std::chrono::duration<double, std::nano>(closed - opened).count();
        printf("timed %lu runs, %.1f ns a run\n", runs, taken / (double)runs);
    }
    cudaLibraryUnload(library);
    return 0;
}

int main(int count, char **arguments)
{
    const char *const question = (count > 1) ? arguments[1] : "";
    int device = 0;
    cudaDeviceProp properties;
    if ((cudaGetDevice(&device) != cudaSuccess) || (cudaGetDeviceProperties(&properties, device) != cudaSuccess))
    {
        printf("no device\n");
        return 2;
    }
    const int major = properties.major;
    const int minor = properties.minor;
    const std::string header = probe_header(major, minor);
    ProbeWriter writer = {ptx_target().ruleset(1), 0, PROBE_TEMPORARIES, PROBE_WIDES, PROBE_PREDICATES};
    if ((writer.rules == NULL) || header.empty())
    {
        printf("the ruleset errored, or NVRTC gave no header\n");
        return 2;
    }
    printf("sm_%d%d, %s", major, minor, header.c_str());
    const std::string t8 = probe_temporary(&writer, 8u);
    const std::string t0 = probe_temporary(&writer, 0u);
    const std::string w0 = probe_wide(&writer, 0u);
    if (strcmp(question, "membership") == 0)
    {
        return probe_membership(&writer, header, major, minor);
    }
    if ((strcmp(question, "cubins") == 0) && (count > 2))
    {
        return probe_cubins(&writer, header, major, minor, arguments[2]);
    }
    if ((strcmp(question, "run") == 0) && (count > 2))
    {
        return probe_cubin_run(arguments[2], count, arguments);
    }
    if (strcmp(question, "clocks") == 0)
    {
        return probe_clocks(device);
    }
    if (strcmp(question, "alive") == 0)
    {
        std::string body;
        probe_form(&writer, body, "add_alone", {t8, t0, probe_temporary(&writer, 1u)});
        return probe_single(&writer, header, body, major, minor);
    }
    if (strcmp(question, "address") == 0)
    {
        // the load reads the sixteenth byte of the device's address space
        std::string body;
        probe_form(&writer, body, "word_set", {t0, "16"});
        probe_form(&writer, body, "wide_from_word", {w0, t0});
        probe_form(&writer, body, "global_load", {t8, w0, "0"});
        return probe_single(&writer, header, body, major, minor);
    }
    if (strcmp(question, "misaligned") == 0)
    {
        // the case's own input, one byte in: a 32-bit load from an address that is not a multiple of 4
        std::string body = "\tadd.s64 \t%interface_wide2, %interface_wide2, 1;\n";
        probe_form(&writer, body, "global_load", {t8, "%interface_wide2", "0"});
        return probe_single(&writer, header, body, major, minor);
    }
    if (strcmp(question, "trap") == 0)
    {
        return probe_single(&writer, header, "\ttrap;\n", major, minor);
    }
    if (strcmp(question, "lacking") == 0)
    {
        return probe_single(&writer, header,
                            "\t{\n\t.reg .pred \t%interface_elected;\n\t.reg .b32 \t%interface_leader;\n"
                            "\telect.sync \t%interface_leader|%interface_elected, 0xffffffff;\n\t}\n",
                            major, minor);
    }
    printf("no question \"%s\"\n", question);
    return 2;
}
