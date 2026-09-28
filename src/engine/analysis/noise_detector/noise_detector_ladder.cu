// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_detector_ladder.cu: the ladder
#include "noise_detector_internal.h"

// A sample's quiet static voxels, their frames in blocks as the moment pass takes them, each kept block added to the
// ladder's sums at its voxel's level over the other blocks
static long noise_ladder_sample(const unsigned short *volume, const unsigned long long extent[4], NoiseLadderSums *sums,
                                unsigned long long *left_out, EngineError *error)
{
    const unsigned long long frames = extent[0];
    const unsigned long long voxels = extent[1] * extent[2] * extent[3];
    const unsigned long long blocks = frames / NOISE_MOMENT_BLOCK;
    const unsigned long long square = NOISE_MOMENT_RANGE * NOISE_MOMENT_RANGE;
    const unsigned long long fourth = square * square;
    const unsigned long long spread = ((voxels != 0ull) && (frames <= (~0ull / voxels))) ? (frames * voxels) : ~0ull;
    // the moment pass's bounds, and two whole blocks so every block has another to set its level
    const int bounded = (blocks >= 2ull) && (frames <= 65536ull) && (voxels != 0ull) && (spread != ~0ull) &&
                        (spread <= (NOISE_SIGNED_TOP / fourth)) && (spread <= (NOISE_SIGNED_TOP / NOISE_LANE_TOP));
    if (!NOISE_DETECTOR_CHECK(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_ERROR;
    }
    memset(sums, 0, sizeof(*sums));
    *left_out = 0ull;
    unsigned long long ceiling = 0ull;
    unsigned char *const mask = (unsigned char *)malloc((size_t)voxels);
    int ok = NOISE_DETECTOR_CHECK(mask != NULL, &mask, error, ENGINE_ERROR_RESOURCE) &&
             NOISE_DETECTOR_CHECK(noise_static_mask(volume, frames, voxels, 1u, mask, &ceiling) != 0, mask, error,
                                  ENGINE_ERROR_RESOURCE);
    unsigned long long members = 0ull;
    for (unsigned long long voxel = 0ull; ok && (voxel < voxels); voxel += 1ull)
    {
        members += mask[voxel];
    }
    // one more than the members. A sample with none still allocates
    unsigned long long *const places =
        (unsigned long long *)malloc((size_t)(members + 1ull) * sizeof(unsigned long long));
    unsigned long long *const totals =
        (unsigned long long *)calloc((size_t)(members + 1ull), sizeof(unsigned long long));
    ok = ok && NOISE_DETECTOR_CHECK((places != NULL) && (totals != NULL), &places, error, ENGINE_ERROR_RESOURCE);
    if (ok != 0)
    {
        unsigned long long member = 0ull;
        for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
        {
            if (mask[voxel] != 0u)
            {
                places[member] = voxel;
                member += 1ull;
            }
        }
        // each voxel's frames over its whole blocks: at most 65536 lanes, below 2^32
        for (unsigned long long frame = 0ull; frame < (blocks * NOISE_MOMENT_BLOCK); frame += 1ull)
        {
            const unsigned short *const lanes = &volume[frame * voxels];
            for (unsigned long long each = 0ull; each < members; each += 1ull)
            {
                totals[each] += lanes[places[each]];
            }
        }
    }
    const long long range = (long long)NOISE_MOMENT_RANGE;
    const long long n = (long long)NOISE_MOMENT_BLOCK;
    for (unsigned long long block = 0ull; ok && (block < blocks); block += 1ull)
    {
        const unsigned short *const first = &volume[block * NOISE_MOMENT_BLOCK * voxels];
        for (unsigned long long each = 0ull; each < members; each += 1ull)
        {
            const unsigned short *const lane = &first[places[each]];
            unsigned long long total = 0ull;
            for (unsigned long long frame = 0ull; frame < NOISE_MOMENT_BLOCK; frame += 1ull)
            {
                total += lane[frame * voxels];
            }
            // a mean of lanes rounded to the nearest is itself a lane
            const long long center = (long long)((total + (NOISE_MOMENT_BLOCK / 2ull)) / NOISE_MOMENT_BLOCK);
            long long power[NOISE_MOMENT_POWERS] = {0ll, 0ll, 0ll, 0ll};
            int within = 1;
            for (unsigned long long frame = 0ull; within && (frame < NOISE_MOMENT_BLOCK); frame += 1ull)
            {
                const long long apart = (long long)lane[frame * voxels] - center;
                within = (apart <= range) && (apart >= -range);
                if (within != 0)
                {
                    const long long apart_squared = apart * apart;
                    power[0] += apart;
                    power[1] += apart_squared;
                    power[2] += apart_squared * apart;
                    power[3] += apart_squared * apart_squared;
                }
            }
            if (within == 0)
            {
                *left_out += 1ull;
                continue;
            }
            // the block's own frames are part of its voxel's total. The rest is never negative
            const unsigned long long place = totals[each] - total;
            const long long s1 = power[0];
            const long long s2 = power[1];
            const long long s3 = power[2];
            const long long s4 = power[3];
            // |S1| is at most n / 2, S2 at most n reach^2, |S3| at most n reach^3 and S4 at most n reach^4. Each
            // term below is under 2^44 and each numerator under 2^46
            const long long readings[NOISE_LADDER_ORDERS] = {
                (n * s2) - (s1 * s1), (2ll * s1 * s1 * s1) - (3ll * n * s1 * s2) + (n * n * s3),
                (n * n * (n + 1ll) * s4) - (4ll * n * (n + 1ll) * s1 * s3) - (3ll * n * (n - 1ll) * s2 * s2) +
                    (12ll * n * s1 * s1 * s2) - (6ll * s1 * s1 * s1 * s1)};
            sums->blocks += 1ull;
            noise_wide_add(&sums->along, place, 0ull);
            noise_wide_add_square(&sums->along_square, place);
            for (unsigned int order = 0u; order < NOISE_LADDER_ORDERS; order += 1u)
            {
                noise_signed_wide_add(&sums->measured[order], 1ull, readings[order]);
                noise_signed_wide_add(&sums->cross[order], place, readings[order]);
            }
        }
    }
    free(mask);
    free(places);
    free(totals);
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}

extern "C" long noise_ladder_volume(const unsigned short *volume, const unsigned long long extent[4],
                                    NoiseLadderMeasurement *measurement, EngineError *error)
{
    if (error == NULL)
    {
        return NOISE_DETECTOR_ERROR;
    }
    if (!NOISE_DETECTOR_CHECK((volume != NULL) && (extent != NULL) && (measurement != NULL), volume, error,
                              ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_ERROR;
    }
    NoiseLadderSums *const sums = (NoiseLadderSums *)malloc(sizeof(NoiseLadderSums));
    unsigned long long left_out = 0ull;
    int ok = NOISE_DETECTOR_CHECK(sums != NULL, &sums, error, ENGINE_ERROR_RESOURCE) &&
             (noise_ladder_sample(volume, extent, sums, &left_out, error) == 0L);
    // a block's level is its voxel's frames over the other blocks. The level scale is those frames' count
    const unsigned long long other_frames = ((extent[0] / NOISE_MOMENT_BLOCK) - 1ull) * NOISE_MOMENT_BLOCK;
    NoiseLadderMeasurement read;
    memset(&read, 0, sizeof(read));
    unsigned long long falling = NOISE_MOMENT_BLOCK;
    for (unsigned int order = 0u; ok && (order < NOISE_LADDER_ORDERS); order += 1u)
    {
        // k of order j + 2 is its numerator over n (n - 1) down to n - j - 1
        falling *= NOISE_MOMENT_BLOCK - (unsigned long long)(order + 1u);
        NoiseLineSums line;
        noise_line_sums_zero(&line);
        noise_exact_word(&line.samples, sums->blocks);
        noise_exact_wide(&line.along, &sums->along);
        noise_exact_wide(&line.along_square, &sums->along_square);
        ok = NOISE_DETECTOR_CHECK(noise_exact_signed_wide(&line.measured, &sums->measured[order]) &&
                                      noise_exact_signed_wide(&line.cross, &sums->cross[order]),
                                  sums, error, ENGINE_ERROR_RESOURCE) &&
             (noise_line_fit(&line, other_frames, falling, &read.cumulant[order], error) == 0L);
    }
    read.blocks = (sums != NULL) ? sums->blocks : 0ull;
    read.left_out = left_out;
    free(sums);
    const NoiseLine *const second = &read.cumulant[0];
    const NoiseLine *const third = &read.cumulant[1];
    const NoiseLine *const fourth = &read.cumulant[2];
    if (ok == 0)
    {
        return NOISE_DETECTOR_ERROR;
    }
    AnchorExactInteger left;
    AnchorExactInteger right;
    AnchorExactInteger term;
    // s3 >= s2^2: S3 D2^2 >= S2^2 D3, every denominator positive
    int formed = (anchor_exact_multiply(&second->denominator, &second->denominator, &term) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&third->slope, &term, &left) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&second->slope, &second->slope, &term) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&term, &third->denominator, &right) == ANCHOR_EXACT_OK);
    read.rising = formed && (anchor_exact_compare(&left, &right) >= 0);
    // s2 s4 >= s3^2: S2 S4 D3^2 >= S3^2 D2 D4
    formed = formed && (anchor_exact_multiply(&second->slope, &fourth->slope, &term) == ANCHOR_EXACT_OK) &&
             (anchor_exact_multiply(&term, &third->denominator, &term) == ANCHOR_EXACT_OK) &&
             (anchor_exact_multiply(&term, &third->denominator, &left) == ANCHOR_EXACT_OK) &&
             (anchor_exact_multiply(&third->slope, &third->slope, &term) == ANCHOR_EXACT_OK) &&
             (anchor_exact_multiply(&term, &second->denominator, &term) == ANCHOR_EXACT_OK) &&
             (anchor_exact_multiply(&term, &fourth->denominator, &right) == ANCHOR_EXACT_OK);
    read.convex = formed && (anchor_exact_compare(&left, &right) >= 0);
    // C19: O = -C3 / S3 and R^2 = (C2 S3 - C3 S2) / (D2 S3), each turned to a positive denominator
    read.tail = formed && (third->slope.sign != 0);
    if (read.tail != 0)
    {
        anchor_exact_zero(&term);
        formed = (anchor_exact_subtract(&term, &third->intercept, &read.offset) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&second->intercept, &third->slope, &left) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&third->intercept, &second->slope, &right) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_subtract(&left, &right, &read.read_square) == ANCHOR_EXACT_OK) &&
                 (anchor_exact_multiply(&second->denominator, &third->slope, &read.read_square_denominator) ==
                  ANCHOR_EXACT_OK);
        read.offset_denominator = third->slope;
        if (third->slope.sign < 0)
        {
            read.offset.sign = -read.offset.sign;
            read.offset_denominator.sign = -read.offset_denominator.sign;
            read.read_square.sign = -read.read_square.sign;
            read.read_square_denominator.sign = -read.read_square_denominator.sign;
        }
    }
    if (!NOISE_DETECTOR_CHECK(formed, &read, error, ENGINE_ERROR_RESOURCE))
    {
        return NOISE_DETECTOR_ERROR;
    }
    *measurement = read;
    return 0L;
}
