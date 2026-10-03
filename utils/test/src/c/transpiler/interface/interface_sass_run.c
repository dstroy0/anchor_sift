// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// interface_sass_run.c: a list of cubins run on the part in one process, one answer a cubin. Nothing is compiled here:
// the driver is handed each cubin as it was written and asked for its kernel.
//
//     interface_sass_run <machine file> <list> <first> <answers> [<cases>]
//
// The list holds one cubin a line, as `<path> <kernel>`. Each from line `first` on is read on the host first and held
// to cubin_safe against the machine file; one that breaks a rule is never handed to the driver and adds `<number>
// skipped cubin_safe_<verdict>`. Every other is loaded, its kernel run over the
// probe's case, and a line `<number> answered <w0> <w1> <w2> <w3>` added to the answers file. Given a cases file, one
// case a line as up to eight words in hex, the kernel is run once over every case, a thread a case, and the line holds
// the first word of each case's answer in the file's order. A cubin the part refuses
// kills the context past recovery: resetting the part's primary context in place leaves the next launch failing. A
// refusal adds `<number> refused <error>` and ends the process with exit 3, and the caller starts it again past that
// line. A pause after each launch keeps a run of launches from flooding the part and taking the display down with it.
// Exit 0 where every line ran, 2 where the list or the device was not reached.
#include "../../../../../../src/c/transpiler/cubin/cubin_safe.h"

#include <cuda.h>
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// the most bytes a cubin takes, and the longest line of the list
#define SASS_RUN_CUBIN 262144u
#define SASS_RUN_LINE 1024u
// the words of the case and of an answer, and the threads a launch gives the kernel, which leaves every thread past
// the case count at once
#define SASS_RUN_IN_WORDS 8u
#define SASS_RUN_OUT_WORDS 4u
#define SASS_RUN_THREADS 256u
// the wait after a launch, in milliseconds, which spaces the part's work and keeps a run of launches from flooding it
#define SASS_RUN_PAUSE_MS 25u

static unsigned char s_image[SASS_RUN_CUBIN];
static SassMachine s_machine;
// the cases every cubin is run over, the probe's one case where no cases file is given, and the answers they give
static unsigned int s_cases[SASS_RUN_THREADS][SASS_RUN_IN_WORDS] = {{0xbu, 0x7u, 0x3u, 0x5u, 0x2u, 0x9u, 0x1u, 0x4u}};
static unsigned int s_case_count = 1u;
static unsigned int s_answers[SASS_RUN_THREADS][SASS_RUN_OUT_WORDS];

// the cases file at `path` read into s_cases, one case a line as up to eight words in hex, the words a line leaves out
// zero: 1, or 0 where it does not read, holds no case or holds more than a launch's threads
static int sass_run_cases(const char *path)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return 0;
    }
    char line[SASS_RUN_LINE];
    unsigned int count = 0u;
    int fits = 1;
    while (fits && (fgets(line, sizeof(line), file) != NULL))
    {
        unsigned int words[SASS_RUN_IN_WORDS] = {0u, 0u, 0u, 0u, 0u, 0u, 0u, 0u};
        const int read = sscanf(line, "%x %x %x %x %x %x %x %x", &words[0], &words[1], &words[2], &words[3], &words[4],
                                &words[5], &words[6], &words[7]);
        if (read <= 0)
        {
            continue;
        }
        fits = (count < SASS_RUN_THREADS);
        if (fits)
        {
            memcpy(s_cases[count], words, sizeof(words));
            count += 1u;
        }
    }
    fclose(file);
    s_case_count = count;
    return fits && (count != 0u);
}

// `path` read whole into s_image: the bytes read, or 0 where it was not read or does not fit
static size_t sass_run_image(const char *path)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return 0u;
    }
    const size_t read = fread(s_image, 1u, sizeof(s_image), file);
    fclose(file);
    return (read < sizeof(s_image)) ? read : 0u;
}

// the cubin already read into s_image loaded and its kernel run over every case, a thread a case, each case's four
// words into s_answers: CUDA_SUCCESS, or the error the driver gave
static CUresult sass_run_one(const char *kernel)
{
    CUmodule module = NULL;
    CUfunction function = NULL;
    CUdeviceptr in = 0u;
    CUdeviceptr out = 0u;
    unsigned int count = s_case_count;
    const size_t in_bytes = (size_t)s_case_count * sizeof(s_cases[0]);
    const size_t out_bytes = (size_t)s_case_count * sizeof(s_answers[0]);
    CUresult status = cuModuleLoadData(&module, s_image);
    status = (status == CUDA_SUCCESS) ? cuModuleGetFunction(&function, module, kernel) : status;
    status = (status == CUDA_SUCCESS) ? cuMemAlloc(&in, in_bytes) : status;
    status = (status == CUDA_SUCCESS) ? cuMemAlloc(&out, out_bytes) : status;
    status = (status == CUDA_SUCCESS) ? cuMemcpyHtoD(in, s_cases, in_bytes) : status;
    status = (status == CUDA_SUCCESS) ? cuMemsetD8(out, 0u, out_bytes) : status;
    void *arguments[] = {&in, &out, &count};
    status = (status == CUDA_SUCCESS)
                 ? cuLaunchKernel(function, 1u, 1u, 1u, SASS_RUN_THREADS, 1u, 1u, 0u, NULL, arguments, NULL)
                 : status;
    status = (status == CUDA_SUCCESS) ? cuCtxSynchronize() : status;
    status = (status == CUDA_SUCCESS) ? cuMemcpyDtoH(s_answers, out, out_bytes) : status;
    if (status == CUDA_SUCCESS)
    {
        cuMemFree(in);
        cuMemFree(out);
        cuModuleUnload(module);
    }
    return status;
}

int main(int count, char **words)
{
    if ((count != 5) && (count != 6))
    {
        fprintf(stderr, "interface_sass_run <machine file> <list> <first> <answers> [<cases>]\n");
        return 2;
    }
    if ((count == 6) && !sass_run_cases(words[5]))
    {
        fprintf(stderr, "the cases %s did not read, or hold more than %u\n", words[5], SASS_RUN_THREADS);
        return 2;
    }
    if (!sass_machine_read(&s_machine, words[1]))
    {
        fprintf(stderr, "the machine file %s did not read, and nothing goes to the part unread\n", words[1]);
        return 2;
    }
    FILE *const list = fopen(words[2], "rb");
    FILE *const answers = fopen(words[4], "ab");
    CUdevice device = 0;
    CUcontext context = NULL;
    if ((list == NULL) || (answers == NULL) || (cuInit(0u) != CUDA_SUCCESS) ||
        (cuDeviceGet(&device, 0) != CUDA_SUCCESS) || (cuDevicePrimaryCtxRetain(&context, device) != CUDA_SUCCESS) ||
        (cuCtxSetCurrent(context) != CUDA_SUCCESS))
    {
        fprintf(stderr, "the list %s, the answers %s or the device was not reached\n", words[2], words[4]);
        return 2;
    }
    const unsigned long first = strtoul(words[3], NULL, 10);
    char line[SASS_RUN_LINE];
    unsigned long number = 0ul;
    while (fgets(line, sizeof(line), list) != NULL)
    {
        char path[SASS_RUN_LINE];
        char kernel[SASS_RUN_LINE];
        if ((number < first) || (sscanf(line, "%1023s %1023s", path, kernel) != 2))
        {
            number += 1ul;
            continue;
        }
        // a line the writer held off the part: its turned operation key holds a control transfer, a wait or no form,
        // and running it could loop or stall the part. It is answered without the device
        if (strcmp(path, "skip") == 0)
        {
            fprintf(answers, "%lu skipped %s\n", number, kernel);
            number += 1ul;
            continue;
        }
        // read on the host before the driver sees it: a cubin that does not read, or breaks a rule of cubin_safe, is
        // answered without the device
        const size_t size = sass_run_image(path);
        unsigned long long at = 0ull;
        const unsigned int verdict = (size == 0u) ? CUBIN_SAFE_SIZE : cubin_safe_image(&s_machine, s_image, size, &at);
        if (verdict != CUBIN_SAFE)
        {
            fprintf(answers, "%lu skipped cubin_safe_%u\n", number, verdict);
            printf("  %s held off the part: %s at byte %llu\n", path, cubin_safe_name(verdict), at);
            number += 1ul;
            continue;
        }
        const CUresult status = sass_run_one(kernel);
        if (status != CUDA_SUCCESS)
        {
            const char *name = NULL;
            cuGetErrorName(status, &name);
            fprintf(answers, "%lu refused %s\n", number, (name != NULL) ? name : "unnamed");
            fclose(answers);
            return 3;
        }
        if (count == 6)
        {
            fprintf(answers, "%lu answered", number);
            for (unsigned int at = 0u; at < s_case_count; at += 1u)
            {
                fprintf(answers, " %08x", s_answers[at][0]);
            }
            fprintf(answers, "\n");
        }
        else
        {
            fprintf(answers, "%lu answered %08x %08x %08x %08x\n", number, s_answers[0][0], s_answers[0][1],
                    s_answers[0][2], s_answers[0][3]);
        }
        // the pause spaces the launches and keeps a run of them from flooding the part
        Sleep(SASS_RUN_PAUSE_MS);
        number += 1ul;
    }
    fclose(answers);
    fclose(list);
    return 0;
}
