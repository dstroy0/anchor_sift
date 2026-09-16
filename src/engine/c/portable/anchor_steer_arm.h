/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file anchor_steer_arm.h
 * @brief One shape every implementation of the steering scan presents, letting a driver call any.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * THE SCAN IS WHERE THE STEERING ENGINE SPENDS ITS TIME. Placing a probe set means scoring
 * candidates, and scoring a candidate means asking, across every alignment still standing, whether
 * the corpus agrees with one needle byte at one offset. The needle byte is fixed for the whole
 * sweep and the corpus side is read at unit stride, so the question is a wide compare against a
 * broadcast register and nothing else.
 *
 * @note Every arm returns the same count. Where two disagree one of them has a defect, and nothing
 *       about the difference is a tradeoff. The count is an integer, so agreement is exact and a
 *       difference of one is a defect rather than a rounding.
 * @note The portable arm is the reference. It is always present, uses no intrinsic and no compiler
 *       extension, and every other arm is graded against it on the same data.
 * @note An arm reports itself absent at run time where the machine cannot run it. A build that
 *       compiled an AVX2 arm still has to ask the processor before calling it, since the build
 *       machine and the running machine are not the same machine.
 */
#ifndef ANCHOR_STEER_ARM_H
#define ANCHOR_STEER_ARM_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief One implementation of the steering scan.
 *
 * @note `count` takes the corpus, the alignment count, the survivor flags, the needle byte being
 *       tested and the offset it sits at, and returns how many still-standing alignments agree.
 *       That is the whole operation a planner asks of an arm.
 */
typedef struct
{
    const char *name; /**< What to print in a row. Never null. */
    size_t (*count)(const uint8_t *corpus, size_t alignments, const uint8_t *alive, uint8_t wanted,
                    size_t offset);
} AnchorSteerArm;

/**
 * @brief The portable C11 arm, the reference every other arm is graded against.
 *
 * @return A pointer to the arm. Never null, since this arm runs anywhere a C11 compiler built it.
 */
const AnchorSteerArm *anchor_steer_portable_arm(void);

/**
 * @brief The scan in portable C11.
 *
 * @param[in] corpus     Bytes under examination [BORROWS].
 * @param[in] alignments How many alignments the object has.
 * @param[in] alive      One flag per alignment, non-zero where still standing [BORROWS].
 * @param[in] wanted     The needle byte being tested.
 * @param[in] offset     Needle offset the probe sits at.
 * @return               How many still-standing alignments agree.
 */
size_t anchor_steer_truthy_after_portable(const uint8_t *corpus, size_t alignments,
                                          const uint8_t *alive, uint8_t wanted, size_t offset);

#if defined(ANCHOR_STEER_HAVE_AVX2) && ANCHOR_STEER_HAVE_AVX2

/**
 * @brief The AVX2 arm, answering thirty-two alignments per compare.
 *
 * @return A pointer to the arm, or NULL where this processor does not carry AVX2.
 * @note Asks the processor instead of trusting the build.
 */
const AnchorSteerArm *anchor_steer_avx2_arm(void);

/** @brief The scan under AVX2. Same contract as the portable one, same count. */
size_t anchor_steer_truthy_after_avx2(const uint8_t *corpus, size_t alignments,
                                      const uint8_t *alive, uint8_t wanted, size_t offset);

#endif

#ifdef __cplusplus
}
#endif

#endif /* ANCHOR_STEER_ARM_H */
