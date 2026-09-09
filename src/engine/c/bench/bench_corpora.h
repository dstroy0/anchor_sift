/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_corpora.h
 * @brief Generated corpora and the two statistics a dispatch decision is made from.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-08
 *
 * @note Shared by every driver so two benches cannot disagree about what skewed means. The scaling
 *       bench and the dispatch bench have to build the same bytes from the same seed, since one of
 *       them measures a rate against a prediction and the other scores a rule against a clock, and
 *       a rule scored on corpora the prediction never saw is a rule scored against nothing.
 * @note Nothing here is timed. These build a corpus and read a histogram, both outside every timed
 *       region, and a driver that inlines them differently cannot move a measurement.
 * @warning Corpora are generated. A generated corpus carries a distribution and no arrangement.
 *          Nothing built here bears on a measure that reads arrangement.
 */
#ifndef BENCH_CORPORA_H
#define BENCH_CORPORA_H

#include <stddef.h>
#include <stdint.h>

/** @brief How a corpus is built. */
typedef enum
{
    CORPUS_UNIFORM = 0,
    CORPUS_SKEWED = 1,
    CORPUS_PERIODIC = 2
} CorpusKind;

/**
 * @brief Builds bytes of a stated kind and length from a stated stream.
 *
 * @param[out] bytes  Where to write [BORROWS].
 * @param[in]  length How many bytes.
 * @param[in]  kind   Which distribution to draw from.
 * @param[in]  seed   Selects the stream, letting a corpus and a needle share a distribution while
 *                    sharing no content.
 * @note The seed is a parameter because the needles that are not taken from the corpus have to come
 *       from the same distribution as the corpus. Drawing them uniformly instead puts bytes in them
 *       that a skewed corpus never holds. The filter then rejects on the alphabet instead of at the
 *       rate the histogram predicts, reporting a filtration efficiency nothing earned.
 */
void bench_build_bytes(uint8_t *bytes, size_t length, CorpusKind kind, uint64_t seed);

/**
 * @brief Names a corpus kind for the output.
 *
 * @param[in] kind Which corpus.
 * @return         A static name, or "unknown" where the value is not one of the three.
 */
const char *bench_corpus_name(CorpusKind kind);

/**
 * @brief Collision entropy of a corpus and how many byte values it uses.
 *
 * @param[in]  corpus   Bytes to measure [BORROWS].
 * @param[in]  length   How many. Must be at least one.
 * @param[out] distinct Where the count of used byte values is written [BORROWS].
 * @return              H2 in bits, in [0, 8] for a byte corpus.
 * @note Computed without <math.h>, letting a driver link on a part with no libm, as the kernel does.
 */
double bench_collision_entropy(const uint8_t *corpus, size_t length, size_t *distinct);

/** @brief What a period search found in a corpus. */
typedef struct
{
    size_t period;    /**< The fundamental found, or zero where nothing stood out. */
    double agreement; /**< Share of positions equal to the position one period away. */
    double at_chance; /**< The agreement chance alone gives, namely the collision probability. */
    double margin;    /**< How far the fundamental's family beat the lags outside it. */
} BenchPeriod;

/**
 * @brief Recovers the size of whatever repeats in a corpus, with nothing supplied.
 *
 * @param[in] corpus Bytes to read [BORROWS].
 * @param[in] length How many. Must exceed twice BENCH_LONGEST_LAG.
 * @return           The fundamental and how far above chance it sits.
 * @note Scored on a candidate and all of its multiples, not on the single tallest lag. A sequence
 *       repeating every sixteen agrees with itself at 16, 32, 48 and 64 alike, so the tallest of
 *       those is settled by noise and taking it reports a harmonic as the period about as often as
 *       it reports the period.
 * @note This is the same reading `measure.periodicity.sequence_period` performs in the Python
 *       engine, where it was caught on protein backbones against a period chemistry fixes at three.
 *       The two share no code and are checked against each other by agreeing on a recovered size.
 */
BenchPeriod bench_recover_period(const uint8_t *corpus, size_t length);

/** @brief Longest lag the period search reads. A fundamental has to fit twice inside this. */
#define BENCH_LONGEST_LAG 64u

/**
 * @brief The uninformed candidate rate the histogram predicts for a full cascade.
 *
 * @param[in] entropy Collision entropy of the corpus, in bits.
 * @param[in] anchors How many anchors the arms place.
 * @return            2^(-anchors * entropy), the share of alignments expected to survive.
 * @note Computed from the histogram alone with nothing fitted. A measured rate that drifts with the
 *       corpus length while this one holds still is the bound failing. The length sweep exists to
 *       ask exactly that.
 */
double bench_predicted_rate(double entropy, double anchors);

#endif
