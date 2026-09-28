// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the tessera_ledger_test_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef TESSERA_LEDGER_TEST_INTERNAL_H
#define TESSERA_LEDGER_TEST_INTERNAL_H

#include "tessera_ledger.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TEST_EVENTS 64u
#define TEST_SCENARIO_JOBS 12u
#define TEST_NEVER 0xFFFFFFFFFFFFFFFFull

typedef struct
{
    const char *name;
    unsigned long long cases;
    unsigned long long failed;
} TestResults;

unsigned long long test_below(unsigned long long bound);

void test_check(TestResults *results, int passed);

void test_report(const TestResults *results);

EngineSignum test_signum(unsigned long long seed);

TesseraJobRequest test_request(unsigned long long seed, unsigned long long declared);

void test_headroom(TestResults *results);

void test_heap_order(TestResults *results);

void test_budget(TestResults *results);

typedef struct
{
    unsigned long long declared;
    unsigned long long duration;
    unsigned long long arrival;
} TestScenarioJob;

#endif
