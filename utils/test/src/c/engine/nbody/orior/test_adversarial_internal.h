
// What the test_adversarial_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef TEST_ADVERSARIAL_INTERNAL_H
#define TEST_ADVERSARIAL_INTERNAL_H

/* orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file test_adversarial_internal.h
 * @brief Attacks the steering guarantees instead of confirming them, and grades every arm present.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * WHY THIS SITS IN utils/test/. A driver in `utils/bench/` builds corpora, counts or times, and prints rows.
 * This file asks whether the engine is right, which is a different question. Douglas put the two
 * questions in two directories. Every case below names the guarantee it attacks and the
 * construction that should break it, and a case that cannot fail when its guarantee is false does
 * not belong here.
 *
 * IT HAS BEEN SEEN TO FAIL. Nothing else separates an adversarial suite from an empty
 * loop. Against the engine as written it passes seven of seven at exit 0. Against three deliberately
 * broken engines it rejects every one, and each mutation is caught by a different set of cases:
 * dropping the full compare so survivors are counted as matches trips the differential net and the
 * survivor case; an off by one in the alignment bound trips overlapping occurrences, the boundary
 * case and the survivor case's read count; and a probe comparing against a constant instead of the
 * needle trips six of the seven. `utils/test/engine/mutate.sh` reproduces all three.
 *
 * A CASE THAT CANNOT FAIL IS NOT A CHECK, and this file learned that about itself. The survivor
 * case was written so that every probe agrees and only the full compare refutes, and it never
 * fired. The steering defeats that construction: the odd byte is the rarest symbol the needle
 * carries. The ordering tests it FIRST, every alignment refutes at the first read, and the full
 * compare never runs. The case sat green and reading it would not have shown why. Mutating the
 * engine to drop the full compare, then watching the case stay green, is what exposed it.
 *
 * The repair is worth more than the catch. That case now runs UNSTEERED, places the difference at
 * an offset the spatial anchors never read, and CHECKS THE PREMISE IT DEPENDS ON: four surviving
 * probes is four reads an alignment and no fewer. A lower count means a probe is refuting and
 * the case has stopped testing what it claims. The premise check then caught the alignment off by
 * one on its own, four reads short of 16260, which is one alignment lost. A case asserting its own
 * preconditions is a different kind of object from one asserting only its conclusion, and every
 * case here that can be given a premise check should get one.
 *
 * FOUR OF THESE ARE DIFFERENTIAL. They compare two routes that must agree. No expected number is
 * written down in advance and none can be written down wrongly. Those are the strongest cases here,
 * and they double in value the moment a second implementation exists: a case passing the portable
 * arm and failing a vectorized one has found a vectorization defect, and a case passing both has
 * been checked twice.
 *
 * WHAT IT COVERS, in the order it runs.
 *
 *   1. EVERY ARM AGREES WITH THE REFERENCE, over many fields, skews, needle lengths and origins.
 *      The net that catches what the designed cases miss.
 *   2. OVERLAPPING OCCURRENCES, where counts classically break, and the first casualty of any shift
 *      rule added later.
 *   3. DEGENERATE LENGTHS AND BOTH BOUNDARIES, including a match at the final alignment, which is
 *      where an off-by-one in the alignment bound hides.
 *   4. A SYMBOL THE FIELD NEVER PRODUCES, graded on the count AND on the read count, because the
 *      cheapness is a separate claim from the answer.
 *   5. EVERY SURVIVOR FALSE. The count cannot be read off the survivor set.
 *   6. SHAPES OUTSIDE THE NECESSARY-CONDITION FAMILY, rejected by the guard instead of believed.
 *   7. WHAT SAMPLING COSTS, reported as a ratio instead of stated as a caveat.
 *
 * WHAT IT CANNOT COVER FROM OUTSIDE, and the entry each one needs, named so the gap is visible
 * instead of quietly absent. Probe order as a permutation null, and a census-derived predicate,
 * both need an entry that runs a search with a CALLER-SUPPLIED probe set. The destroy theorem's
 * consequence needs an entry that runs the descent with the stop condition disabled. The
 * monotonicity precondition needs a candidate set that grows with the level. None of those is
 * reachable through the public header, and each is one function away.
 *
 * @note No double, no float, no <math.h>, and nothing outside the C11 standard headers below.
 */

#include "../../../../../../../src/c/engine/nbody/orior/orior.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/** @brief Corpus bytes every generated field carries. */
#define ADVERSARIAL_CORPUS 4096u

/** @brief Longest needle any case draws. */
#define ADVERSARIAL_NEEDLE 64u

/** @brief Distinct byte values a census can record. */
#define ADVERSARIAL_SYMBOLS 256u

/** @brief Seeds the differential net walks. */
#define ADVERSARIAL_SEEDS 64u

/**
 * @brief Corpus symbols a projected case carries.
 *
 * @note Smaller than ADVERSARIAL_CORPUS because the projection's closure is quadratic in the joint
 *       field and the sweep runs it once per seed. 512 still reaches past 256 classes when the
 *       alphabet is wide, and case 13 checks that it does.
 */
#define ADVERSARIAL_PROJECTED 512u

/** @brief Longest needle a projected case draws. */
#define ADVERSARIAL_PROJECTED_NEEDLE 8u

uint32_t adversarial_next(uint64_t *const state);

void adversarial_fill_field(uint8_t *const corpus, const size_t corpus_len, const uint32_t alphabet,
                            uint64_t *const state);

int adversarial_case_differential_net(void);

int adversarial_case_overlapping(void);

int adversarial_case_boundaries(void);

int adversarial_case_absent_symbol(void);

int adversarial_case_all_survivors_false(void);

int adversarial_case_family_guard(void);

int adversarial_case_sampling_cost(void);

int adversarial_case_permutation_null(void);

int adversarial_case_empty_plan(void);

int adversarial_case_growing_plan(void);

int adversarial_case_stop_equals_continue(void);

int adversarial_case_trichotomy(void);

/** @brief A corpus and a needle of 32 bit symbols, addressed through one joint index space. */
typedef struct
{
    const uint32_t *corpus; /**< Corpus symbols [BORROWS]. */
    size_t corpus_length;   /**< How many. Joint positions below this are corpus positions. */
    const uint32_t *needle; /**< Needle symbols, at joint positions from corpus_length on [BORROWS]. */
} AdversarialJointSymbols;

/** @brief The three class arrays a projection writes, sized for the widest joint field used here. */
typedef struct
{
    uint32_t *class_of_position;     /**< Which class each position fell in [BORROWS]. */
    uint32_t *members_in_class;      /**< How many positions each class holds [BORROWS]. */
    uint32_t *rarity_place_of_class; /**< Where each class sits in the rarity order [BORROWS]. */
    size_t classes_length;           /**< Entries each of the three holds. */
} AdversarialClassBuffers;

size_t adversarial_count_symbols(const uint32_t *corpus, size_t corpus_length, const uint32_t *needle,
                                 size_t needle_length);

int adversarial_count_apart(const uint32_t *corpus, size_t corpus_length, const uint32_t *needle, size_t needle_length,
                            uint8_t *corpus_ranks, uint8_t *needle_ranks, const AdversarialClassBuffers *buffers,
                            size_t *count);

int adversarial_count_together(const uint32_t *corpus, size_t corpus_length, const uint32_t *needle,
                               size_t needle_length, uint8_t *corpus_ranks, uint8_t *needle_ranks,
                               const AdversarialClassBuffers *buffers, size_t *count, size_t *distinct);

#endif
