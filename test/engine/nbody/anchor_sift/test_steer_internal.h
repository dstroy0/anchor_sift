
// What the test_steer_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef TEST_STEER_INTERNAL_H
#define TEST_STEER_INTERNAL_H

/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file test_steer_internal.h
 * @brief Grades the entropy-ordered rejection vector: same counts, fewer reads, exact dispatch.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * WHAT THIS PROVES, in the order it proves it.
 *
 *   1. THE ORDERING COSTS NO CORRECTNESS. The steered arm returns the same count as the reference
 *      arm at every needle length, at a residual of exactly zero. Not a tolerance: an alignment
 *      survives only when every anchor agrees, a conjunction is order independent, and the survivor
 *      is verified with a full memcmp either way. Anything but zero is a defect.
 *   2. THE ORDERING PAYS. The probe counter falls when the rarest symbol is tested first, measured
 *      on a skewed field where rarity actually varies.
 *   3. THE MEASUREMENT CAN FAIL. The negative control orders the probes the wrong way round,
 *      commonest symbol first, and must read MORE than the unsteered order. A negative control that
 *      reads the same says the ordering is a no-op and every number above it is worthless.
 *   4. THE DISPATCH IS EXACT. Three fields whose answers are derived by hand from the rule and
 *      not read off a run. The integer form is graded against arithmetic and not against the
 *      floating point form it replaced.
 *
 * @note No double, no float, no <math.h>, and nothing outside the C11 standard headers below.
 */

#include "anchor_sift.h"
#include "bench_corpora.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/** @brief Corpus bytes the graded runs use. */
#define STEER_CORPUS 65536u

void build_skewed_field(uint8_t *corpus, size_t length);

int check_counts_agree(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle);

int check_ordering_pays(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len);

int check_dispatch_exact(void);

int check_exact_matches_double(void);

void print_route_row(const char *label, size_t probes, size_t count, uint64_t reads, size_t alignments, int ok);

uint8_t *read_whole_file(const char *path, size_t *length);

int grade_field(const char *label, const uint8_t *corpus, size_t corpus_len);

int check_arm_is_wired(const uint8_t *corpus, size_t corpus_len, const uint8_t *needle, size_t needle_len);

/** @brief A byte field reached through the equality oracle, for the agreement check below. */
typedef struct
{
    const uint8_t *corpus;
    const uint8_t *needle;
} ByteField;

int byte_same_at(const void *field, size_t corpus_at, size_t needle_at);

/** @brief A field of 32 bit samples, which no byte engine can read. */
typedef struct
{
    const uint32_t *corpus;
    const uint32_t *needle;
} SampleField;

int sample_same_at(const void *field, size_t corpus_at, size_t needle_at);

int sample_same_in_field(const void *field, size_t left, size_t right);

int near_same_in_field(const void *field, size_t left, size_t right);

#endif
