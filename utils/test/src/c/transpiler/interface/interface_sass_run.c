// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// interface_sass_run.c: a list of cubins run on the part in one process, one answer a cubin. Nothing is compiled here:
// the driver is handed each cubin as it was written and asked for its kernel.
//
//     interface_sass_run <list> <first> <answers>
//
// The list holds one cubin a line, as `<path> <kernel>`. Each from line `first` on is loaded, its kernel run over the
// probe's case, and a line `<number> answered <w0> <w1> <w2> <w3>` added to the answers file. A cubin the part refuses
// leaves the process unable to run another. A refusal adds `<number> refused <error>` and ends the process with exit
// 3, and the caller starts it again past that line. Exit 0 where every line ran, 2 where the list or the device was
// not reached.
#include <cuda.h>
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

static unsigned char s_image[SASS_RUN_CUBIN];

// `path` read whole into s_image: 1, or 0 where it was not read
static int sass_run_image(const char *path)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return 0;
    }
    const size_t read = fread(s_image, 1u, sizeof(s_image), file);
    fclose(file);
    return (read != 0u) && (read < sizeof(s_image));
}

// the cubin at `path` loaded and its kernel run over the case, its four words into `answered`: CUDA_SUCCESS, or the
// error the driver gave
static CUresult sass_run_one(const char *path, const char *kernel, unsigned int *answered)
{
    // the case every question of the probe is asked over: none of its words past the first zero
    static const unsigned int s_case[SASS_RUN_IN_WORDS] = {0xbu, 0x7u, 0x3u, 0x5u, 0x2u, 0x9u, 0x1u, 0x4u};
    if (!sass_run_image(path))
    {
        return CUDA_ERROR_FILE_NOT_FOUND;
    }
    CUmodule module = NULL;
    CUfunction function = NULL;
    CUdeviceptr in = 0u;
    CUdeviceptr out = 0u;
    unsigned int count = 1u;
    CUresult status = cuModuleLoadData(&module, s_image);
    status = (status == CUDA_SUCCESS) ? cuModuleGetFunction(&function, module, kernel) : status;
    status = (status == CUDA_SUCCESS) ? cuMemAlloc(&in, sizeof(s_case)) : status;
    status = (status == CUDA_SUCCESS) ? cuMemAlloc(&out, SASS_RUN_OUT_WORDS * sizeof(unsigned int)) : status;
    status = (status == CUDA_SUCCESS) ? cuMemcpyHtoD(in, s_case, sizeof(s_case)) : status;
    status = (status == CUDA_SUCCESS) ? cuMemsetD8(out, 0u, SASS_RUN_OUT_WORDS * sizeof(unsigned int)) : status;
    void *arguments[] = {&in, &out, &count};
    status = (status == CUDA_SUCCESS)
                 ? cuLaunchKernel(function, 1u, 1u, 1u, SASS_RUN_THREADS, 1u, 1u, 0u, NULL, arguments, NULL)
                 : status;
    status = (status == CUDA_SUCCESS) ? cuCtxSynchronize() : status;
    status = (status == CUDA_SUCCESS) ? cuMemcpyDtoH(answered, out, SASS_RUN_OUT_WORDS * sizeof(unsigned int))
                                      : status;
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
    if (count != 4)
    {
        fprintf(stderr, "interface_sass_run <list> <first> <answers>\n");
        return 2;
    }
    FILE *const list = fopen(words[1], "rb");
    FILE *const answers = fopen(words[3], "ab");
    CUdevice device = 0;
    CUcontext context = NULL;
    if ((list == NULL) || (answers == NULL) || (cuInit(0u) != CUDA_SUCCESS) ||
        (cuDeviceGet(&device, 0) != CUDA_SUCCESS) || (cuDevicePrimaryCtxRetain(&context, device) != CUDA_SUCCESS) ||
        (cuCtxSetCurrent(context) != CUDA_SUCCESS))
    {
        fprintf(stderr, "the list %s, the answers %s or the device was not reached\n", words[1], words[3]);
        return 2;
    }
    const unsigned long first = strtoul(words[2], NULL, 10);
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
        unsigned int answered[SASS_RUN_OUT_WORDS] = {0u, 0u, 0u, 0u};
        const CUresult status = sass_run_one(path, kernel, answered);
        if (status != CUDA_SUCCESS)
        {
            const char *name = NULL;
            cuGetErrorName(status, &name);
            fprintf(answers, "%lu refused %s\n", number, (name != NULL) ? name : "unnamed");
            fclose(answers);
            return 3;
        }
        fprintf(answers, "%lu answered %08x %08x %08x %08x\n", number, answered[0], answered[1], answered[2],
                answered[3]);
        number += 1ul;
    }
    fclose(answers);
    fclose(list);
    return 0;
}
