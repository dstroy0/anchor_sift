/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_seed.h
 * @brief The seed a bench draws with, overridable from outside, to tell a result from a draw.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note Failure mode fourteen in docs/failure-modes.md: a statistic that appears at one seed and
 *       not at others is a property of the draw. Thirty-two of the fixed seeds in this tree are
 *       the same constant, so nothing that has been measured here has ever been asked whether it
 *       moves when the draw does.
 * @note The three-arm compiler audit already establishes that these benches are deterministic, in
 *       that one seed gives one answer under three different builds. Determinism is not stability
 *       and the two are easy to confuse. This is what tests the second one.
 * @note The override is an environment variable and not an argument because the benches do not
 *       agree on an argument convention and inventing one across seventeen files would be a larger
 *       change than the thing being tested.
 */

#ifndef BENCH_SEED_H
#define BENCH_SEED_H

#include <cstdlib>

/**
 * @brief Returns the seed to draw with, from the environment where it is set.
 *
 * @param[in] when_unset The seed this bench was written with, used where nothing overrides it.
 * @return               The seed to hand the generator.
 * @note Returning the written seed when nothing is set keeps every recorded result reproducible
 *       exactly as recorded, and a sweep is an addition to the tree's history and not a break
 *       in it.
 */
static inline unsigned bench_seed(unsigned when_unset)
{
    const char *const requested = std::getenv("BENCH_SEED");
    if (requested == nullptr)
    {
        return when_unset;
    }

    const unsigned long parsed = std::strtoul(requested, nullptr, 10);
    // Zero is what strtoul returns for text that is not a number, and a bench seeded from a typo
    // would look like a run and not a mistake. Fail back to the written seed instead.
    return (parsed == 0ul) ? when_unset : (unsigned)parsed;
}

#endif
