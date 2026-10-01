// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef BENCH_CORPORA_H
#define BENCH_CORPORA_H

#include <stddef.h>
#include <stdint.h>

typedef enum
{
    CORPUS_UNIFORM = 0,
    CORPUS_SKEWED = 1,
    CORPUS_PERIODIC = 2
} CorpusKind;

void bench_build_bytes(uint8_t *bytes, size_t length, CorpusKind kind, uint64_t seed);

const char *bench_corpus_name(CorpusKind kind);

double bench_collision_entropy(const uint8_t *corpus, size_t length, size_t *distinct);

typedef struct
{
    size_t period;
    double agreement;
    double at_chance;
    double margin;
} BenchPeriod;

BenchPeriod bench_recover_period(const uint8_t *corpus, size_t length);

#define BENCH_LONGEST_LAG 64u

double bench_predicted_rate(double entropy, double anchors);

#endif
