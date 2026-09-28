// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_plane_lag.cu: lag, spread and depth
#include "pi_plane_internal.h"

// the longest run of equal bits along the progressions of difference lag, one thread a lag, the bits in shared memory
static __global__ void plane_lag_kernel(const unsigned char *bits, unsigned int count, unsigned int *longest)
{
    extern __shared__ unsigned char plane_shared[];
    for (unsigned int index = threadIdx.x; index < count; index += blockDim.x)
    {
        plane_shared[index] = bits[index];
    }
    __syncthreads();
    const unsigned int lag = (blockIdx.x * blockDim.x) + threadIdx.x + 1u;
    if (lag >= count)
    {
        return;
    }
    unsigned int best = 1u;
    for (unsigned int residue = 0u; residue < lag; residue += 1u)
    {
        unsigned int run = 1u;
        for (unsigned int place = residue + lag; place < count; place += lag)
        {
            run = (plane_shared[place] == plane_shared[place - lag]) ? (run + 1u) : 1u;
            best = (run > best) ? run : best;
        }
    }
    longest[lag] = best;
}

void plane_lag_host(const unsigned char *bits, unsigned int count, unsigned int *longest)
{
    longest[0] = 0u;
    for (unsigned int lag = 1u; lag < count; lag += 1u)
    {
        unsigned int best = 1u;
        for (unsigned int residue = 0u; residue < lag; residue += 1u)
        {
            unsigned int run = 1u;
            for (unsigned int place = residue + lag; place < count; place += lag)
            {
                run = (bits[place] == bits[place - lag]) ? (run + 1u) : 1u;
                best = (run > best) ? run : best;
            }
        }
        longest[lag] = best;
    }
}

int plane_lag_device(SimResults *results, const unsigned char *bits, unsigned int count, unsigned char *device_bits,
                     unsigned int *device_longest, unsigned int *longest)
{
    int ok =
        sim_status_check(results, cudaMemcpy(device_bits, bits, count, cudaMemcpyHostToDevice), "bits to the device");
    ok = ok &&
         sim_status_check(results, cudaMemset(device_longest, 0, (size_t)count * sizeof(unsigned int)), "lag clear");
    if (ok)
    {
        // the block count is below 2^8 for the bits this sim holds
        const unsigned int blocks = (unsigned int)sim_launch_blocks(count - 1u, PLANE_THREADS);
        plane_lag_kernel<<<blocks, PLANE_THREADS, count>>>(device_bits, count, device_longest);
        ok = sim_status_check(results, cudaGetLastError(), "lag kernel launch");
    }
    ok = ok &&
         sim_status_check(
             results, cudaMemcpy(longest, device_longest, (size_t)count * sizeof(unsigned int), cudaMemcpyDeviceToHost),
             "lag read");
    return ok;
}

unsigned int plane_lag_max(const unsigned int *longest, unsigned int count, unsigned int *lag)
{
    unsigned int best = 0u;
    *lag = 0u;
    for (unsigned int each = 1u; each < count; each += 1u)
    {
        if (longest[each] > best)
        {
            best = longest[each];
            *lag = each;
        }
    }
    return best;
}

// the spread of the ones over 2^scale classes of the bits' index, sum over the classes of (2 ones - size)^2. By
// residue, a class is one place on every arm of the twindragon; by block, it is one whole sub-dragon.
unsigned long long plane_spread(const unsigned char *bits, unsigned int count, unsigned int scale, int by_block)
{
    const unsigned int classes = 1u << scale;
    const unsigned int size = count / classes;
    std::vector<long long> ones(classes, 0ll);
    for (unsigned int bit = 0u; bit < classes * size; bit += 1u)
    {
        const unsigned int place = (by_block != 0) ? (bit / size) : (bit % classes);
        ones[place] += (long long)bits[bit];
    }
    unsigned long long spread = 0ull;
    for (unsigned int place = 0u; place < classes; place += 1u)
    {
        // the size is below 2^15. It fits a signed word
        const long long excess = (2ll * ones[place]) - (long long)size;
        // a square is never negative
        spread += (unsigned long long)(excess * excess);
    }
    return spread;
}

// each pixel's depth, the fewest steps to a pixel no bit lands on or past the shape's edge, stepping to the four
// neighbors; 1 on the edge, and PLANE_DEPTHS for that depth and deeper. 0 where no bit lands.
std::vector<unsigned int> plane_depth(const PlaneExtent &extent)
{
    // the extents are below 2^16. They fit a signed word
    const long long height = (long long)extent.height;
    const long long width = (long long)extent.width;
    const long long step_row[4] = {-1ll, 1ll, 0ll, 0ll};
    const long long step_column[4] = {0ll, 0ll, -1ll, 1ll};
    std::vector<unsigned int> depth(extent.cell.size(), 0u);
    std::vector<long long> frontier;
    for (long long row = 0ll; row < height; row += 1ll)
    {
        for (long long column = 0ll; column < width; column += 1ll)
        {
            // the row and column are inside the shape. The index is never negative
            const size_t index = (size_t)((row * width) + column);
            if (extent.cell[index] < 0ll)
            {
                continue;
            }
            int edge = 0;
            for (unsigned int neighbor = 0u; neighbor < 4u; neighbor += 1u)
            {
                edge = edge || (plane_cell_at(extent, row + step_row[neighbor], column + step_column[neighbor]) < 0ll);
            }
            if (edge)
            {
                depth[index] = 1u;
                // the index is below 2^31. It fits a signed word
                frontier.push_back((long long)index);
            }
        }
    }
    for (unsigned int level = 2u; !frontier.empty(); level += 1u)
    {
        std::vector<long long> next;
        for (const long long index : frontier)
        {
            const long long row = index / width;
            const long long column = index % width;
            for (unsigned int neighbor = 0u; neighbor < 4u; neighbor += 1u)
            {
                const long long near_row = row + step_row[neighbor];
                const long long near_column = column + step_column[neighbor];
                if (plane_cell_at(extent, near_row, near_column) < 0ll)
                {
                    continue;
                }
                // the neighbor is inside the shape. Its index is never negative
                const size_t near = (size_t)((near_row * width) + near_column);
                if (depth[near] == 0u)
                {
                    depth[near] = level;
                    // the index is below 2^31. It fits a signed word
                    next.push_back((long long)near);
                }
            }
        }
        frontier.swap(next);
    }
    for (unsigned int &each : depth)
    {
        each = std::min(each, PLANE_DEPTHS);
    }
    return depth;
}

// the ones at each depth, and their spread over the depths, sum over the depths of (2 ones - size)^2
unsigned long long plane_depth_spread(const PlaneExtent &extent, const std::vector<unsigned int> &depth,
                                      const unsigned char *bits, unsigned long long *ones, unsigned long long *sizes)
{
    for (unsigned int level = 0u; level <= PLANE_DEPTHS; level += 1u)
    {
        ones[level] = 0ull;
        sizes[level] = 0ull;
    }
    for (size_t index = 0u; index < extent.cell.size(); index += 1u)
    {
        if (extent.cell[index] >= 0ll)
        {
            ones[depth[index]] += (unsigned long long)bits[extent.cell[index]];
            sizes[depth[index]] += 1ull;
        }
    }
    unsigned long long spread = 0ull;
    for (unsigned int level = 1u; level <= PLANE_DEPTHS; level += 1u)
    {
        // both counts are below 2^15. They fit a signed word
        const long long excess = (2ll * (long long)ones[level]) - (long long)sizes[level];
        // a square is never negative
        spread += (unsigned long long)(excess * excess);
    }
    return spread;
}
