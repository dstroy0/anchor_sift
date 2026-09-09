/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file exact_gpu.h
 * @brief The exact measure on a CUDA device, parallel over positions instead of over limbs.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-09
 *
 * @note The vectorized arms widen one comparison. This one does not widen a comparison at all: it
 *       gives one position to each thread and runs the whole search for that position there. The
 *       limb arithmetic on the device is the portable arithmetic, transcribed for the device and
 *       checked against the host the same way every other arm is.
 * @note A big integer is a fixed width limb array here exactly as it is on the host. A device can
 *       hold one for that reason alone. The representation is a transform of the value, and the
 *       device carries the same transform, one warp's worth of limbs at a time.
 * @note Only `agreement` is handed over. A single comparison is far too small to be worth a bus
 *       crossing, so the arm's `equal` and `compare` stay on the host and are the portable ones.
 */
#ifndef ANCHOR_EXACT_GPU_H
#define ANCHOR_EXACT_GPU_H

#include "exact_limbs.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Whether a usable CUDA device is present.
 *
 * @return 1 where at least one device answered, 0 otherwise.
 * @note Asked at run time. A binary built with CUDA still runs on machines with no device, and the
 *       arm has to report itself absent there instead of failing inside a launch.
 */
int anchor_exact_cuda_available(void);

/**
 * @brief The name and compute capability of the device this arm would use.
 *
 * @param[out] text  Where the description is written [BORROWS].
 * @param[in]  room  How many bytes `text` holds.
 * @return           1 where a description was written, 0 where no device answered.
 */
int anchor_exact_cuda_describe(char *text, size_t room);

/**
 * @brief Counts agreeing places over a sorted run, one position per thread.
 *
 * @param[in] positions Positions, ascending [BORROWS].
 * @param[in] values    The value standing at each position [BORROWS].
 * @param[in] count     How many positions.
 * @param[in] lag       The offset to test [BORROWS].
 * @return              How many positions agree with the place one lag above them, or SIZE_MAX
 *                      where the device refused the work.
 * @note Returns the same count the portable arm returns. Where it does not, one of the two has a
 *       defect and the difference is never a tradeoff.
 */
size_t anchor_exact_agreement_cuda(const AnchorExactInteger *positions, const uint64_t *values,
                                   size_t count, const AnchorExactInteger *lag);

#ifdef __cplusplus
}
#endif

#endif /* ANCHOR_EXACT_GPU_H */
