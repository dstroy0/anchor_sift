// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "marginal.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define MARGINAL_BLOCK 128u

static_assert(MARGINAL_TARGETS_MOST <= 64u, "marginal: the targets taken must fit one 64 bit mask");

static_assert(sizeof(unsigned int) == 4u, "marginal: unsigned int must be 32 bits, a limb");

static_assert(MARGINAL_ARRANGEMENTS_MOST <= (1ull << 32u), "marginal: a sum of arrangements must grow by one limb at most");

typedef struct
{
    const MarginalQuestion *questions;
    unsigned int question_count;
    const MarginalSource *sources;
    const MarginalOption *options;
    unsigned int *question_sums;
    unsigned int *option_sums;
} MarginalLaunch;

__device__ static void marginal_scale(const unsigned int *from, unsigned int limbs, unsigned int weight, unsigned int *to)
{
    unsigned long long carry = 0ull;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        const unsigned long long total = ((unsigned long long)from[limb] * (unsigned long long)weight) + carry;
        to[limb] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
    to[limbs] = (unsigned int)carry;
}

__device__ static void marginal_gather(unsigned int *sum, const unsigned int *product, unsigned int limbs)
{
    unsigned long long carry = 0ull;
    for (unsigned int limb = 0u; limb < MARGINAL_LIMBS; limb += 1u)
    {
        const unsigned long long total = (unsigned long long)sum[limb]
                                       + (unsigned long long)((limb < limbs) ? product[limb] : 0u) + carry;
        sum[limb] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
}

__global__ static void marginal_kernel(MarginalLaunch launch)
{
    const unsigned int question = (blockIdx.x * blockDim.x) + threadIdx.x;
    if (question >= launch.question_count)
    {
        return;
    }
    const MarginalQuestion asked = launch.questions[question];
    const MarginalSource *const sources = &launch.sources[asked.source_first];
    unsigned int *const sums = &launch.question_sums[(unsigned long long)question * MARGINAL_SUMS * MARGINAL_LIMBS];
    for (unsigned int word = 0u; word < (MARGINAL_SUMS * MARGINAL_LIMBS); word += 1u)
    {
        sums[word] = 0u;
    }
    for (unsigned int option = 0u; option < sources[0].options; option += 1u)
    {
        unsigned int *const held = &launch.option_sums[(unsigned long long)(sources[0].option_first + option)
                                                       * MARGINAL_LIMBS];
        for (unsigned int limb = 0u; limb < MARGINAL_LIMBS; limb += 1u)
        {
            held[limb] = 0u;
        }
    }
    unsigned int product[MARGINAL_SOURCES_MOST + 1u][MARGINAL_LIMBS];
    unsigned long long taken[MARGINAL_SOURCES_MOST + 1u];
    unsigned int choice[MARGINAL_SOURCES_MOST + 1u];
    for (unsigned int limb = 0u; limb < MARGINAL_LIMBS; limb += 1u)
    {
        product[0][limb] = 0u;
    }
    product[0][0] = 1u;
    taken[0] = 0ull;
    choice[0] = 0u;
    unsigned int depth = 0u;
    for (;;)
    {
        if (depth == asked.sources)
        {
            marginal_gather(&sums[MARGINAL_TOTAL * MARGINAL_LIMBS], product[depth], depth + 1u);
            unsigned int *const outcome = (choice[0] == 0u)
                                        ? &sums[MARGINAL_ABSENT * MARGINAL_LIMBS]
                                        : &launch.option_sums[(unsigned long long)(sources[0].option_first + choice[0] - 1u)
                                                              * MARGINAL_LIMBS];
            marginal_gather(outcome, product[depth], depth + 1u);
            depth -= 1u;
            choice[depth] += 1u;
            continue;
        }
        const MarginalSource source = sources[depth];
        if (choice[depth] > source.options)
        {
            if (depth == 0u)
            {
                break;
            }
            depth -= 1u;
            choice[depth] += 1u;
            continue;
        }
        unsigned int weight = source.absent;
        unsigned long long mark = 0ull;
        if (choice[depth] != 0u)
        {
            const MarginalOption option = launch.options[source.option_first + choice[depth] - 1u];
            weight = option.weight;
            mark = 1ull << option.target;
        }
        if ((taken[depth] & mark) != 0ull)
        {
            choice[depth] += 1u;
            continue;
        }
        marginal_scale(product[depth], depth + 1u, weight, product[depth + 1u]);
        taken[depth + 1u] = taken[depth] | mark;
        depth += 1u;
        choice[depth] = 0u;
    }
}

extern "C" long marginal_run(const MarginalRequest *request)
{
    if ((request == NULL) || (request->questions == NULL) || (request->sources == NULL) || (request->options == NULL)
     || (request->question_sums == NULL) || (request->option_sums == NULL))
    {
        return MARGINAL_REFUSED;
    }
    for (unsigned int question = 0u; question < request->question_count; question += 1u)
    {
        if (marginal_arrangements(request, &request->questions[question]) == MARGINAL_REFUSED)
        {
            return MARGINAL_REFUSED;
        }
    }
    const size_t question_words = (size_t)request->question_count * MARGINAL_SUMS * MARGINAL_LIMBS;
    const size_t option_words = (size_t)request->option_count * MARGINAL_LIMBS;
    MarginalQuestion *questions = NULL;
    MarginalSource *sources = NULL;
    MarginalOption *options = NULL;
    unsigned int *question_sums = NULL;
    unsigned int *option_sums = NULL;
    int good = (cudaMalloc((void **)&questions, ((size_t)request->question_count + 1u) * sizeof(MarginalQuestion))
                == cudaSuccess)
            && (cudaMalloc((void **)&sources, ((size_t)request->source_count + 1u) * sizeof(MarginalSource))
                == cudaSuccess)
            && (cudaMalloc((void **)&options, ((size_t)request->option_count + 1u) * sizeof(MarginalOption))
                == cudaSuccess)
            && (cudaMalloc((void **)&question_sums, (question_words + 1u) * sizeof(unsigned int)) == cudaSuccess)
            && (cudaMalloc((void **)&option_sums, (option_words + 1u) * sizeof(unsigned int)) == cudaSuccess)
            && (cudaMemset(option_sums, 0, (option_words + 1u) * sizeof(unsigned int)) == cudaSuccess)
            && (cudaMemcpy(questions, request->questions, (size_t)request->question_count * sizeof(MarginalQuestion),
                           cudaMemcpyHostToDevice) == cudaSuccess)
            && (cudaMemcpy(sources, request->sources, (size_t)request->source_count * sizeof(MarginalSource),
                           cudaMemcpyHostToDevice) == cudaSuccess)
            && (cudaMemcpy(options, request->options, (size_t)request->option_count * sizeof(MarginalOption),
                           cudaMemcpyHostToDevice) == cudaSuccess);
    if (good && (request->question_count != 0u))
    {
        MarginalLaunch launch;
        memset(&launch, 0, sizeof(launch));
        launch.questions = questions;
        launch.question_count = request->question_count;
        launch.sources = sources;
        launch.options = options;
        launch.question_sums = question_sums;
        launch.option_sums = option_sums;
        const unsigned int blocks = (request->question_count + MARGINAL_BLOCK - 1u) / MARGINAL_BLOCK;
        marginal_kernel<<<blocks, MARGINAL_BLOCK>>>(launch);
        good = (cudaGetLastError() == cudaSuccess) && (cudaDeviceSynchronize() == cudaSuccess);
    }
    good = good && (cudaMemcpy(request->question_sums, question_sums, question_words * sizeof(unsigned int),
                               cudaMemcpyDeviceToHost) == cudaSuccess)
        && (cudaMemcpy(request->option_sums, option_sums, option_words * sizeof(unsigned int), cudaMemcpyDeviceToHost)
            == cudaSuccess);
    cudaFree(questions);
    cudaFree(sources);
    cudaFree(options);
    cudaFree(question_sums);
    cudaFree(option_sums);
    return good ? (long)request->question_count : MARGINAL_REFUSED;
}
