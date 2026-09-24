// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef MARGINAL_H
#define MARGINAL_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define MARGINAL_REFUSED (-1L)

#define MARGINAL_LIMBS 16u

#define MARGINAL_SOURCES_MOST (MARGINAL_LIMBS - 1u)

#define MARGINAL_TARGETS_MOST 64u

#define MARGINAL_ARRANGEMENTS_MOST (1ull << 16u)

#define MARGINAL_TOTAL 0u

#define MARGINAL_ABSENT 1u

#define MARGINAL_SUMS 2u

typedef struct
{
    unsigned int source_first;
    unsigned int sources;
} MarginalQuestion;

typedef struct
{
    unsigned int option_first;
    unsigned int options;
    unsigned int absent;
} MarginalSource;

typedef struct
{
    unsigned int target;
    unsigned int weight;
} MarginalOption;

typedef struct
{
    const MarginalQuestion *questions;
    unsigned int question_count;
    const MarginalSource *sources;
    unsigned int source_count;
    const MarginalOption *options;
    unsigned int option_count;
    unsigned int *question_sums;
    unsigned int *option_sums;
} MarginalRequest;

long marginal_arrangements(const MarginalRequest *request, const MarginalQuestion *asked);

long marginal_run(const MarginalRequest *request);

long marginal_run_host(const MarginalRequest *request);

#ifdef __cplusplus
}
#endif

#endif
