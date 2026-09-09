/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_arm.h
 * @brief One shape every implementation of the exact measure presents, letting a driver call any.
 * @author dstroy0 (Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note Every arm returns the same counts. Where two disagree one of them has a defect, and nothing
 *       about the difference is a tradeoff. This is the same contract AnchorSiftArm carries for the
 *       search kernel and it is kept for the same reason.
 * @note The portable arm is the reference. It is always present, uses no intrinsic and no compiler
 *       extension, and every other arm is graded against it on the same data.
 * @note An arm reports itself absent at run time where the machine cannot run it. A build that
 *       compiled an AVX2 arm still has to ask the processor before calling it, since the build
 *       machine and the running machine are not the same machine.
 */
#ifndef ANCHOR_EXACT_ARM_H
#define ANCHOR_EXACT_ARM_H

#include "exact_limbs.h"

#ifdef __cplusplus
/* The GPU arm is compiled as C++ by nvcc and defines its arm here, while every other arm is C. */
extern "C" {
#endif

/**
 * @brief One implementation of the operations a measure asks of an exact integer.
 *
 * @note `equal` and `compare` are the two the measure spends its time in. `agreement` is offered
 *       whole because an arm may parallelize across positions instead of across limbs. The GPU arm
 *       does exactly that, and neither vectorized arm does.
 */
typedef struct
{
    const char *name;               /**< What to print in a row. Never null. */
    int (*equal)(const AnchorExactInteger *left, const AnchorExactInteger *right);
    int (*compare)(const AnchorExactInteger *left, const AnchorExactInteger *right);
    size_t (*agreement)(const AnchorExactInteger *positions, const uint64_t *values, size_t count,
                        const AnchorExactInteger *lag);
} AnchorExactArm;

/**
 * @brief The portable C11 arm, the reference every other arm is graded against.
 *
 * @return A pointer to the arm. Never null, since this arm runs anywhere a C11 compiler built it.
 */
const AnchorExactArm *anchor_exact_portable_arm(void);

#if defined(ANCHOR_EXACT_HAVE_AVX2) && ANCHOR_EXACT_HAVE_AVX2

/**
 * @brief The AVX2 arm, comparing eight limbs per instruction.
 *
 * @return A pointer to the arm, or NULL where this processor does not carry AVX2.
 * @note Asks the processor instead of trusting the build. A binary compiled with AVX2 available
 *       runs on machines that do not have it, and calling in would raise an illegal instruction.
 */
const AnchorExactArm *anchor_exact_avx2_arm(void);

#endif

#if defined(ANCHOR_EXACT_HAVE_AVX512) && ANCHOR_EXACT_HAVE_AVX512

/**
 * @brief The AVX-512 arm, comparing sixteen limbs per instruction.
 *
 * @return A pointer to the arm, or NULL where this processor lacks AVX-512F and AVX-512BW.
 * @note Never run. No machine in this project carries AVX-512, so this arm is graded on the
 *       instructions it emits and not on any answer it produced. It calls itself avx512-unrun, which
 *       keeps a row of results from showing it beside a run arm with the difference invisible.
 */
const AnchorExactArm *anchor_exact_avx512_arm(void);

#endif

#if defined(ANCHOR_EXACT_HAVE_NEON) && ANCHOR_EXACT_HAVE_NEON

/**
 * @brief The NEON arm, comparing four limbs per instruction.
 *
 * @return A pointer to the arm, or NULL where this processor does not carry NEON.
 */
const AnchorExactArm *anchor_exact_neon_arm(void);

#endif

#if defined(ANCHOR_EXACT_HAVE_SVE) && ANCHOR_EXACT_HAVE_SVE

/**
 * @brief The SVE arm, comparing whatever vector length the part turns out to carry.
 *
 * @return A pointer to the arm, or NULL where the kernel does not report SVE.
 * @note Never run. The Raspberry Pi 5 is a Cortex-A76 and is NEON only, so this arm is graded on
 *       the instructions it emits and calls itself sve-unrun for the same reason the AVX-512 one
 *       does.
 */
const AnchorExactArm *anchor_exact_sve_arm(void);

#endif

#if defined(ANCHOR_EXACT_HAVE_CUDA) && ANCHOR_EXACT_HAVE_CUDA

/**
 * @brief The CUDA arm, taking one position per thread instead of one limb per lane.
 *
 * @return A pointer to the arm, or NULL where no usable device is present.
 * @note Its `equal` and `compare` run on the host and are the portable ones. A single comparison is
 *       far too small to be worth crossing the bus for, and only `agreement` is handed over.
 */
const AnchorExactArm *anchor_exact_cuda_arm(void);

#endif

#ifdef __cplusplus
}
#endif

#endif /* ANCHOR_EXACT_ARM_H */
