// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// noise_detector_lines.cu: line and plane noise sampled
#include "noise_detector_internal.h"

void noise_wide_add(NoiseWide *sum, unsigned long long low, unsigned long long high)
{
    const unsigned long long before = sum->low;
    sum->low += low;
    sum->high += high + ((sum->low < before) ? 1ull : 0ull);
}

// magnitude squared as (upper 2^32 + lower)^2 = upper^2 2^64 + upper lower 2^33 + lower^2, each part below 2^64
void noise_wide_add_square(NoiseWide *sum, unsigned long long magnitude)
{
    const unsigned long long upper = magnitude >> 32u;
    const unsigned long long lower = magnitude & 0xFFFFFFFFull;
    const unsigned long long cross = upper * lower;
    noise_wide_add(sum, lower * lower, upper * upper);
    noise_wide_add(sum, cross << 33u, cross >> 31u);
}

// the static voxels are the dimmest 1 / NOISE_STATIC_SHARE, by their mean over the frames, of those that change and
// never touch either end of the lane
#define NOISE_STATIC_SHARE 4ull

// One thread a line of one frame pair: its frame, its z plane, and its row (along x) or column (along y). The line's
// frame differences are summed, their squares are summed, and so are its values, which place it in a level bin; its
// static members are counted, and their frame differences summed and squared and their values summed apart.
__global__ static void noise_lines_kernel(const unsigned short *lanes, const unsigned char *mask,
                                          unsigned long long frame_pairs, unsigned long long depth,
                                          unsigned long long height, unsigned long long width, unsigned int along_x,
                                          long long *line_sums, unsigned long long *line_squares,
                                          unsigned long long *line_levels, long long *static_sums,
                                          unsigned long long *static_squares, unsigned long long *static_members,
                                          unsigned long long *static_levels)
{
    const unsigned long long across = (along_x != 0u) ? height : width;
    const unsigned long long length = (along_x != 0u) ? width : height;
    const unsigned long long step = (along_x != 0u) ? 1ull : width;
    const unsigned long long voxels = depth * height * width;
    const unsigned long long lines = frame_pairs * depth * across;
    const unsigned long long jump = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long line = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; line < lines;
         line += jump)
    {
        const unsigned long long frame = line / (depth * across);
        const unsigned long long plane = (line / across) % depth;
        const unsigned long long place = line % across;
        const unsigned long long first = (plane * height * width) + ((along_x != 0u) ? (place * width) : place);
        long long summed = 0ll;
        unsigned long long squared = 0ull;
        unsigned long long level = 0ull;
        long long static_summed = 0ll;
        unsigned long long static_squared = 0ull;
        unsigned long long static_counted = 0ull;
        unsigned long long static_level = 0ull;
        for (unsigned long long at = 0ull; at < length; at += 1ull)
        {
            const unsigned long long voxel = first + (at * step);
            const unsigned int before = lanes[(frame * voxels) + voxel];
            const unsigned int after = lanes[((frame + 1ull) * voxels) + voxel];
            const long long moved = (long long)after - (long long)before;
            // a square is never negative. It re-signs to unsigned long long exactly
            const unsigned long long square = (unsigned long long)(moved * moved);
            summed += moved;
            squared += square;
            level += (unsigned long long)before + after;
            if (mask[voxel] != 0u)
            {
                static_summed += moved;
                static_squared += square;
                static_counted += 1ull;
                static_level += (unsigned long long)before + after;
            }
        }
        line_sums[line] = summed;
        line_squares[line] = squared;
        line_levels[line] = level;
        static_sums[line] = static_summed;
        static_squares[line] = static_squared;
        static_members[line] = static_counted;
        static_levels[line] = static_level;
    }
}

static void noise_line_add(NoiseLineCell *cells, unsigned int kind, unsigned long long length, long long summed,
                           unsigned long long squared, unsigned long long level)
{
    // the line's mean pair level, in bins of 8: the level sum holds 2 values a member
    const unsigned long long level_bin = level / (length * 16ull);
    NoiseLineCell *const cell =
        &cells[(kind * NOISE_LEVEL_BINS) + ((level_bin < NOISE_LEVEL_BINS) ? level_bin : (NOISE_LEVEL_BINS - 1u))];
    cell->lines += 1ull;
    cell->members += length;
    cell->member_squares += squared;
    // a line's sum is far from the most negative long long. Its negation is exact
    noise_wide_add_square(&cell->line_squares, (unsigned long long)((summed < 0ll) ? -summed : summed));
}

// sum gains left times right, less square, exactly
static int noise_exact_add_centerd(AnchorExactInteger *sum, unsigned long long left, unsigned long long right,
                                   const AnchorExactInteger *square)
{
    AnchorExactInteger term;
    AnchorExactInteger factor;
    noise_exact_word(&term, left);
    noise_exact_word(&factor, right);
    return (anchor_exact_multiply(&term, &factor, &term) == ANCHOR_EXACT_OK) &&
           (anchor_exact_subtract(&term, square, &term) == ANCHOR_EXACT_OK) &&
           (anchor_exact_add(sum, &term, sum) == ANCHOR_EXACT_OK);
}

static int noise_planes_pool(const NoisePlane *planes, unsigned long long count, unsigned long long height,
                             unsigned long long width, NoisePlanePool *pool)
{
    pool->planes = count;
    pool->height = height;
    pool->width = width;
    anchor_exact_zero(&pool->spread);
    anchor_exact_zero(&pool->rows);
    anchor_exact_zero(&pool->columns);
    anchor_exact_zero(&pool->plane_squares);
    int ok = 1;
    for (unsigned long long plane = 0ull; ok && (plane < count); plane += 1ull)
    {
        const NoisePlane *const one = &planes[plane];
        AnchorExactInteger square;
        // a plane's sum is far from the most negative long long. Its negation is exact
        noise_exact_word(&square, (unsigned long long)((one->summed < 0ll) ? -one->summed : one->summed));
        ok = (anchor_exact_multiply(&square, &square, &square) == ANCHOR_EXACT_OK) &&
             noise_exact_add_centerd(&pool->spread, height * width, one->squared, &square) &&
             noise_exact_add_centerd(&pool->rows, height, one->row_squares, &square) &&
             noise_exact_add_centerd(&pool->columns, width, one->column_squares, &square) &&
             (anchor_exact_add(&pool->plane_squares, &square, &pool->plane_squares) == ANCHOR_EXACT_OK);
    }
    return ok;
}

static int noise_planes_rows(FILE *table, const char *name, const NoisePlane *planes, unsigned long long count,
                             unsigned long long depth, unsigned long long members)
{
    int ok = 1;
    for (unsigned long long plane = 0ull; ok && (plane < count); plane += 1ull)
    {
        const NoisePlane *const one = &planes[plane];
        ok = fprintf(table, "%s\t%llu\t%llu\t%llu\t%llu\t%lld\t%llu\t%llu\t%llu\t%llu\t%lld\t%llu\t%llu\n", name,
                     plane / depth, plane % depth, members, one->level, one->summed, one->squared, one->row_squares,
                     one->column_squares, one->static_members, one->static_summed, one->static_squared,
                     one->static_level) > 0;
    }
    return ok;
}

// A quiet voxel's frame differences have a mean square of at most NOISE_QUIET_SLOPE times its mean plus
// NOISE_QUIET_FLOOR. A still voxel's is 2 (g L + R^2), and the set's transfer curves (compression_table.md) hold g at
// most 1.162 and the read variance near 2.5, at most 0.6 of this bound at every level; a voxel that structure moves
// through reads far past it.
#define NOISE_QUIET_SLOPE 4ull

#define NOISE_QUIET_FLOOR 32ull

// Marks the static voxels: among those that change and never touch either end of the lane, and where quiet is set
// that pass the spread test above, the dimmest 1 / NOISE_STATIC_SHARE by their mean over the frames, rounded down.
// The ceiling is the highest mean kept. The pixel maps leave quiet unset: a hot pixel is loud and is what they seek.
int noise_static_mask(const unsigned short *volume, unsigned long long frames, unsigned long long voxels,
                      unsigned int quiet, unsigned char *mask, unsigned long long *ceiling)
{
    unsigned long long *const totals = (unsigned long long *)calloc((size_t)voxels, sizeof(unsigned long long));
    unsigned short *const least = (unsigned short *)malloc((size_t)voxels * sizeof(unsigned short));
    unsigned short *const maximum = (unsigned short *)calloc((size_t)voxels, sizeof(unsigned short));
    unsigned long long *const counted = (unsigned long long *)calloc(NOISE_VALUES, sizeof(unsigned long long));
    unsigned long long *const squares =
        (quiet != 0u) ? (unsigned long long *)calloc((size_t)voxels, sizeof(unsigned long long)) : NULL;
    // a voxel's squares times the frames is at most the frames squared times 65535 squared, a word to 65536 frames
    const int ok = (totals != NULL) && (least != NULL) && (maximum != NULL) && (counted != NULL) &&
                   ((quiet == 0u) || ((squares != NULL) && (frames <= 65536ull)));
    *ceiling = 0ull;
    if (ok != 0)
    {
        memset(least, 0xFF, (size_t)voxels * sizeof(unsigned short));
        for (unsigned long long frame = 0ull; frame < frames; frame += 1ull)
        {
            const unsigned short *const lanes = &volume[frame * voxels];
            for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
            {
                totals[voxel] += lanes[voxel];
                least[voxel] = (lanes[voxel] < least[voxel]) ? lanes[voxel] : least[voxel];
                maximum[voxel] = (lanes[voxel] > maximum[voxel]) ? lanes[voxel] : maximum[voxel];
            }
            for (unsigned long long voxel = 0ull; (quiet != 0u) && (frame != 0ull) && (voxel < voxels); voxel += 1ull)
            {
                // the same voxel one frame earlier sits a volume's voxels before it, inside the volume from frame 1
                const long long moved = (long long)lanes[voxel] - (long long)volume[((frame - 1ull) * voxels) + voxel];
                // a square is never negative. It re-signs to unsigned long long exactly
                squares[voxel] += (unsigned long long)(moved * moved);
            }
        }
        unsigned long long eligible = 0ull;
        for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
        {
            const unsigned long long bound = (NOISE_QUIET_SLOPE * totals[voxel]) + (NOISE_QUIET_FLOOR * frames);
            const int still = (quiet == 0u) || ((squares[voxel] * frames) <= ((frames - 1ull) * bound));
            mask[voxel] = ((least[voxel] != 0u) && (maximum[voxel] != NOISE_LANE_TOP) &&
                           (least[voxel] != maximum[voxel]) && still)
                              ? 1u
                              : 0u;
            if (mask[voxel] != 0u)
            {
                // a mean of values that are each below 2^16 is below 2^16
                counted[totals[voxel] / frames] += 1ull;
                eligible += 1ull;
            }
        }
        const unsigned long long wanted = (eligible + NOISE_STATIC_SHARE - 1ull) / NOISE_STATIC_SHARE;
        unsigned long long running = 0ull;
        for (unsigned long long mean = 0ull; (mean < NOISE_VALUES) && (running < wanted); mean += 1ull)
        {
            running += counted[mean];
            *ceiling = mean;
        }
        for (unsigned long long voxel = 0ull; voxel < voxels; voxel += 1ull)
        {
            mask[voxel] = ((mask[voxel] != 0u) && ((totals[voxel] / frames) <= *ceiling)) ? 1u : 0u;
        }
    }
    free(totals);
    free(least);
    free(maximum);
    free(counted);
    free(squares);
    return ok;
}

// a static line's squared sum and its n^2 - n, pooled
static void noise_static_line_add(NoiseWide *line_squares, unsigned long long *pairs, long long summed,
                                  unsigned long long members)
{
    // a line's sum is far from the most negative long long. Its negation is exact
    noise_wide_add_square(line_squares, (unsigned long long)((summed < 0ll) ? -summed : summed));
    // n^2 - n is 0 for no member, where the unsigned n - 1 wraps and the product is still 0
    *pairs += members * (members - 1ull);
}

// The sample's lines binned into cells, and every plane's sums written to the plane table under the sample's name and
// pooled for the two-way layout; the static voxels' lines pooled apart.
long noise_lines_sample(const unsigned short *volume, const unsigned long long extent[4],
                        NoiseLineCell cells[NOISE_LINE_CELLS], NoisePlanePool *pool, NoiseStaticPool *still,
                        FILE *plane_table, const char *name, EngineError *error)
{
    const unsigned long long frames = extent[0];
    const unsigned long long depth = extent[1];
    const unsigned long long height = extent[2];
    const unsigned long long width = extent[3];
    const unsigned long long voxels = depth * height * width;
    const unsigned long long plane_voxels = height * width;
    const unsigned long long longer = (height > width) ? height : width;
    // every member square sum fits a word, and a plane's sum and level sum fit theirs; a plane's squared row sums
    // total at most its voxels times its width times 65535 squared, its columns' at most its voxels times its height
    // times that, and the longer side bounds both; every n^2 - n pooled totals at most the sample's voxel-frames times
    // a plane's voxels, which a plane of at most 65535 squared voxels holds in a word
    const int bounded = (frames >= 2ull) && (voxels != 0ull) && (frames <= (~0ull / voxels)) &&
                        ((frames * voxels) <= (~0ull / (65535ull * 65535ull))) &&
                        (plane_voxels <= (0x7FFFFFFFFFFFFFFFull / 131070ull)) &&
                        (longer <= ((~0ull / (65535ull * 65535ull)) / plane_voxels)) &&
                        (plane_voxels <= (65535ull * 65535ull));
    if (!NOISE_DETECTOR_CHECK(bounded, extent, error, ENGINE_ERROR_REQUEST))
    {
        return NOISE_DETECTOR_ERROR;
    }
    memset(cells, 0, (size_t)NOISE_LINE_CELLS * sizeof(NoiseLineCell));
    memset(still, 0, sizeof(*still));
    const unsigned long long frame_pairs = frames - 1ull;
    const unsigned long long row_lines = frame_pairs * depth * height;
    const unsigned long long column_lines = frame_pairs * depth * width;
    const unsigned long long max_lines = (row_lines > column_lines) ? row_lines : column_lines;
    const size_t lane_bytes = (size_t)(frames * voxels) * sizeof(unsigned short);
    const size_t line_bytes = (size_t)max_lines * sizeof(unsigned long long);
    unsigned short *device_lanes = NULL;
    unsigned char *device_mask = NULL;
    long long *device_sums = NULL;
    unsigned long long *device_squares = NULL;
    unsigned long long *device_levels = NULL;
    long long *device_static_sums = NULL;
    unsigned long long *device_static_squares = NULL;
    unsigned long long *device_static_members = NULL;
    unsigned long long *device_static_levels = NULL;
    long long *const sums = (long long *)malloc(line_bytes);
    unsigned long long *const squares = (unsigned long long *)malloc(line_bytes);
    unsigned long long *const levels = (unsigned long long *)malloc(line_bytes);
    long long *const static_sums = (long long *)malloc(line_bytes);
    unsigned long long *const static_squares = (unsigned long long *)malloc(line_bytes);
    unsigned long long *const static_members = (unsigned long long *)malloc(line_bytes);
    unsigned long long *const static_levels = (unsigned long long *)malloc(line_bytes);
    unsigned char *const mask = (unsigned char *)malloc((size_t)voxels);
    const unsigned long long plane_count = frame_pairs * depth;
    NoisePlane *const planes = (NoisePlane *)malloc((size_t)plane_count * sizeof(NoisePlane));
    int ok =
        NOISE_DETECTOR_CHECK((sums != NULL) && (squares != NULL) && (levels != NULL) && (static_sums != NULL) &&
                                 (static_squares != NULL) && (static_members != NULL) && (static_levels != NULL) &&
                                 (mask != NULL) && (planes != NULL),
                             &sums, error, ENGINE_ERROR_RESOURCE) &&
        NOISE_DETECTOR_CHECK(noise_static_mask(volume, frames, voxels, 1u, mask, &still->ceiling) != 0, mask, error,
                             ENGINE_ERROR_RESOURCE) &&
        NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_lanes, lane_bytes), &device_lanes, error) &&
        NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_mask, (size_t)voxels), &device_mask, error) &&
        NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_sums, line_bytes), &device_sums, error) &&
        NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_squares, line_bytes), &device_squares, error) &&
        NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_levels, line_bytes), &device_levels, error) &&
        NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_static_sums, line_bytes), &device_static_sums, error) &&
        NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_static_squares, line_bytes), &device_static_squares,
                                    error) &&
        NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_static_members, line_bytes), &device_static_members,
                                    error) &&
        NOISE_DETECTOR_STATUS_CHECK(cudaMalloc((void **)&device_static_levels, line_bytes), &device_static_levels,
                                    error) &&
        NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(device_lanes, volume, lane_bytes, cudaMemcpyHostToDevice), device_lanes,
                                    error) &&
        NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(device_mask, mask, (size_t)voxels, cudaMemcpyHostToDevice), device_mask,
                                    error);
    for (unsigned int kind = NOISE_LINE_ROWS; ok && (kind <= NOISE_LINE_COLUMNS); kind += 1u)
    {
        const unsigned int along_x = (kind == NOISE_LINE_ROWS) ? 1u : 0u;
        const unsigned long long lines = (along_x != 0u) ? row_lines : column_lines;
        const unsigned long long length = (along_x != 0u) ? width : height;
        const unsigned long long needed = (lines + NOISE_DETECTOR_THREADS - 1ull) / NOISE_DETECTOR_THREADS;
        const unsigned int blocks = (unsigned int)((needed < 65536ull) ? needed : 65536ull);
        noise_lines_kernel<<<blocks, NOISE_DETECTOR_THREADS>>>(
            device_lanes, device_mask, frame_pairs, depth, height, width, along_x, device_sums, device_squares,
            device_levels, device_static_sums, device_static_squares, device_static_members, device_static_levels);
        const size_t taken = (size_t)lines * sizeof(unsigned long long);
        ok = NOISE_DETECTOR_STATUS_CHECK(cudaGetLastError(), device_sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(sums, device_sums, taken, cudaMemcpyDeviceToHost), sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(squares, device_squares, taken, cudaMemcpyDeviceToHost), squares,
                                         error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(levels, device_levels, taken, cudaMemcpyDeviceToHost), levels,
                                         error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(static_sums, device_static_sums, taken, cudaMemcpyDeviceToHost),
                                         static_sums, error) &&
             NOISE_DETECTOR_STATUS_CHECK(
                 cudaMemcpy(static_squares, device_static_squares, taken, cudaMemcpyDeviceToHost), static_squares,
                 error) &&
             NOISE_DETECTOR_STATUS_CHECK(
                 cudaMemcpy(static_members, device_static_members, taken, cudaMemcpyDeviceToHost), static_members,
                 error) &&
             NOISE_DETECTOR_STATUS_CHECK(cudaMemcpy(static_levels, device_static_levels, taken, cudaMemcpyDeviceToHost),
                                         static_levels, error);
        NoiseWide *const static_lines = (along_x != 0u) ? &still->row_squares : &still->column_squares;
        unsigned long long *const static_pairs = (along_x != 0u) ? &still->row_pairs : &still->column_pairs;
        for (unsigned long long line = 0ull; ok && (line < lines); line += 1ull)
        {
            noise_line_add(cells, kind, length, sums[line], squares[line], levels[line]);
            noise_static_line_add(static_lines, static_pairs, static_sums[line], static_members[line]);
        }
        // the rows of one frame pair and one z plane sit together, height of them, and together they are the plane
        for (unsigned long long plane = 0ull; ok && (along_x != 0u) && (plane < plane_count); plane += 1ull)
        {
            long long summed = 0ll;
            unsigned long long squared = 0ull;
            unsigned long long level = 0ull;
            unsigned long long row_squares = 0ull;
            long long static_summed = 0ll;
            unsigned long long static_squared = 0ull;
            unsigned long long static_counted = 0ull;
            unsigned long long static_level = 0ull;
            for (unsigned long long row = plane * height; row < ((plane + 1ull) * height); row += 1ull)
            {
                summed += sums[row];
                squared += squares[row];
                level += levels[row];
                // a row's sum is far from the most negative long long. Its negation is exact
                const unsigned long long magnitude = (unsigned long long)((sums[row] < 0ll) ? -sums[row] : sums[row]);
                row_squares += magnitude * magnitude;
                static_summed += static_sums[row];
                static_squared += static_squares[row];
                static_counted += static_members[row];
                static_level += static_levels[row];
            }
            noise_line_add(cells, NOISE_LINE_PLANES, plane_voxels, summed, squared, level);
            noise_static_line_add(&still->plane_squares, &still->plane_pairs, static_summed, static_counted);
            still->members += static_counted;
            still->squares += static_squared;
            planes[plane].summed = summed;
            planes[plane].squared = squared;
            planes[plane].row_squares = row_squares;
            planes[plane].level = level;
            planes[plane].static_members = static_counted;
            planes[plane].static_summed = static_summed;
            planes[plane].static_squared = static_squared;
            planes[plane].static_level = static_level;
        }
        // a plane's columns sit together in the same order, width of them
        for (unsigned long long plane = 0ull; ok && (along_x == 0u) && (plane < plane_count); plane += 1ull)
        {
            unsigned long long column_squares = 0ull;
            for (unsigned long long column = plane * width; column < ((plane + 1ull) * width); column += 1ull)
            {
                // a column's sum is far from the most negative long long. Its negation is exact
                const unsigned long long magnitude =
                    (unsigned long long)((sums[column] < 0ll) ? -sums[column] : sums[column]);
                column_squares += magnitude * magnitude;
            }
            planes[plane].column_squares = column_squares;
        }
    }
    // a sim reading one volume passes no plane table
    ok = ok &&
         NOISE_DETECTOR_CHECK(noise_planes_pool(planes, plane_count, height, width, pool) != 0, pool, error,
                              ENGINE_ERROR_RESOURCE) &&
         ((plane_table == NULL) ||
          NOISE_DETECTOR_IO(noise_planes_rows(plane_table, name, planes, plane_count, depth, plane_voxels) != 0,
                            plane_table, error));
    cudaFree(device_lanes);
    cudaFree(device_mask);
    cudaFree(device_sums);
    cudaFree(device_squares);
    cudaFree(device_levels);
    cudaFree(device_static_sums);
    cudaFree(device_static_squares);
    cudaFree(device_static_members);
    cudaFree(device_static_levels);
    free(sums);
    free(squares);
    free(levels);
    free(static_sums);
    free(static_squares);
    free(static_members);
    free(static_levels);
    free(mask);
    free(planes);
    return (ok != 0) ? 0L : NOISE_DETECTOR_ERROR;
}
