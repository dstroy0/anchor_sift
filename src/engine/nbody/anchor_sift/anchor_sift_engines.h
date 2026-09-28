
// anchor_sift_engines.h: the steering engines of each arm (anchor_sift.h includes the parts in order)
#ifndef ANCHOR_SIFT_ENGINES_H
#define ANCHOR_SIFT_ENGINES_H

#include "anchor_sift_descent.h"

#ifdef __cplusplus
extern "C"
{
#endif

    /* ---- the scan: the engine interface, the shared counters, the dispatch, one arm per set ---- */

    /**
     * @brief One implementation of the steering scan.
     *
     * @note `count` takes the corpus, the alignment count, the survivor flags, the needle byte being
     *       tested and the offset it sits at, and returns how many still-standing alignments agree.
     *       A planner asks a scan engine for this operation alone.
     */
    typedef struct
    {
        const char *name; /**< What to print in a row. Never null. */
        size_t (*count)(const uint8_t *corpus, size_t alignments, const uint8_t *alive, uint8_t wanted, size_t offset);
    } AnchorSteerEngine;

    /**
     * @brief Scans served by any engine since the last reset.
     *
     * A CORRECTNESS SUITE CANNOT DETECT AN UNUSED IMPLEMENTATION. An engine that is compiled, graded
     * and never called produces no wrong answer. Every count stays identical and every test keeps
     * passing. That is not a hypothetical: the AVX2 engine here was built, graded against portable and
     * benched at 33 times its rate while the planner went on running its own scalar loop, and nothing in
     * the suite said so.
     *
     * These two counters make the wiring assertable. The claim is not that the engines agree, which the
     * differential already covers, but that the engine the machine carries actually RAN. A test reads
     * them after a planner run and requires the wide count to be non-zero wherever a wide engine
     * reports itself present.
     */
    extern uint64_t anchor_steer_scan_calls;

    /** @brief Scans served by a vectorized engine since the last reset. */
    extern uint64_t anchor_steer_wide_calls;

    /** @brief Sets both scan counters to zero. */
    void anchor_steer_scan_counters_reset(void);

    /**
     * @brief The widest engine this machine carries, the one the planner calls.
     *
     * @return The engine. Never null, since the portable one is always present.
     * @note Resolved on every call. A caller in a hot path holds the result instead of asking again,
     *       because the processor query costs more than a scan does.
     */
    const AnchorSteerEngine *anchor_steer_best_engine(void);

    /**
     * @brief The portable C11 engine, the reference every other engine is graded against.
     *
     * @return A pointer to the engine. Never null, since it runs anywhere a C11 compiler built it.
     */
    const AnchorSteerEngine *anchor_steer_portable_engine(void);

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
    size_t anchor_steer_truthy_after_portable(const uint8_t *corpus, size_t alignments, const uint8_t *alive,
                                              uint8_t wanted, size_t offset);

#if defined(ANCHOR_STEER_HAVE_AVX2) && ANCHOR_STEER_HAVE_AVX2

    /**
     * @brief The AVX2 engine, answering thirty-two alignments per compare.
     *
     * @return A pointer to the engine, or NULL where this processor does not carry AVX2.
     * @note Asks the processor instead of trusting the build.
     */
    const AnchorSteerEngine *anchor_steer_avx2_engine(void);

    /** @brief The scan under AVX2. Same contract as the portable one, same count. */
    size_t anchor_steer_truthy_after_avx2(const uint8_t *corpus, size_t alignments, const uint8_t *alive,
                                          uint8_t wanted, size_t offset);

#endif

#if defined(ANCHOR_STEER_HAVE_AVX512) && ANCHOR_STEER_HAVE_AVX512

    /**
     * @brief The AVX-512 engine, answering sixty-four alignments per compare.
     *
     * @return A pointer to the engine, or NULL where this processor does not carry AVX-512.
     * @note Asks the processor instead of trusting the build. No machine here runs it. The name it
     *       carries reads avx512-unrun.
     */
    const AnchorSteerEngine *anchor_steer_avx512_engine(void);

    /** @brief The scan under AVX-512. Same contract as the portable one, same count. */
    size_t anchor_steer_truthy_after_avx512(const uint8_t *corpus, size_t alignments, const uint8_t *alive,
                                            uint8_t wanted, size_t offset);

#endif

#if defined(ANCHOR_STEER_HAVE_NEON) && ANCHOR_STEER_HAVE_NEON

    /**
     * @brief The NEON engine, answering sixteen alignments per compare.
     *
     * @return A pointer to the engine. Never null on a build that reached it, since NEON is part of the
     *         base aarch64 architecture.
     */
    const AnchorSteerEngine *anchor_steer_neon_engine(void);

    /** @brief The scan under NEON. Same contract as the portable one, same count. */
    size_t anchor_steer_truthy_after_neon(const uint8_t *corpus, size_t alignments, const uint8_t *alive,
                                          uint8_t wanted, size_t offset);

#endif

#if defined(ANCHOR_STEER_HAVE_SVE) && ANCHOR_STEER_HAVE_SVE

    /**
     * @brief The SVE engine, answering a vector's worth of alignments per compare.
     *
     * @return A pointer to the engine, or NULL where the kernel does not report SVE. No machine here
     *         runs it. The name it carries reads sve-unrun.
     * @note Detection reads the kernel capability word, since ARM has no cpuid.
     */
    const AnchorSteerEngine *anchor_steer_sve_engine(void);

    /** @brief The scan under SVE. Same contract as the portable one, same count. */
    size_t anchor_steer_truthy_after_sve(const uint8_t *corpus, size_t alignments, const uint8_t *alive, uint8_t wanted,
                                         size_t offset);

#endif

#if defined(ANCHOR_STEER_HAVE_CUDA) && ANCHOR_STEER_HAVE_CUDA

    /**
     * @brief Whether a usable CUDA device is present.
     *
     * @return 1 where at least one device answered, 0 otherwise.
     * @note Asked at run time. A binary built with CUDA still runs on a machine with no device, and the
     *       arm reports itself absent there instead of failing inside a launch.
     */
    int anchor_steer_cuda_available(void);

    /**
     * @brief The name and compute capability of the device this arm would use.
     *
     * @param[out] text Where the description is written [BORROWS].
     * @param[in]  capacity How many bytes `text` holds.
     * @return          1 where a description was written, 0 where no device answered.
     */
    int anchor_steer_cuda_describe(char *text, size_t capacity);

    /**
     * @brief The CUDA engine, one alignment per thread over the whole object.
     *
     * @return A pointer to the engine, or NULL where no device answered.
     * @note Not in anchor_steer_best_engine. The scan is called once per candidate in a descent and the
     *       survivor vector changes each level. A per-call host to device copy would cost more than
     *       the scan saves on all but the largest objects. The arm is graded against portable and timed
     *       by the GPU build, and a caller that has already put the object on the device calls it
     *       directly.
     */
    const AnchorSteerEngine *anchor_steer_cuda_engine(void);

    /**
     * @brief The scan on a CUDA device. Same contract as the portable one, same count.
     *
     * @note Falls back to a host count where the device errors on the work. A driver comparing arms
     *       reads a count and never a sentinel it would misread as a disagreement.
     */
    size_t anchor_steer_truthy_after_cuda(const uint8_t *corpus, size_t alignments, const uint8_t *alive,
                                          uint8_t wanted, size_t offset);

#endif

#ifdef __cplusplus
}
#endif

#endif
