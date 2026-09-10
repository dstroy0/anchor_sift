/* Greedy packing on a surface, on the device, so the count can be taken where sampling on a host
 * cannot reach.
 *
 * Prints one line: shape dims gap typical kept candidates
 *
 * WHAT IS ON THE DEVICE AND WHAT IS NOT
 *
 * Greedy packing is sequential by definition: whether a point is kept depends on every point kept
 * before it. What parallelises is the expensive half, which is asking one candidate whether it
 * clears every point already kept. So the device answers that for a batch at a time and the host
 * walks the batch in order, settling the few candidates that clear the kept set against each other.
 *
 * The answer is the same answer a purely sequential pass would give, and that is checked rather
 * than asserted: the driver runs this and the host version over the same shapes at low dimensions
 * where both can reach, and the counts have to agree.
 *
 * WHY THE GAP IS NOT PASSED IN
 *
 * A gap that means one thing on a sphere means another on a cube of nominally similar size, and a
 * fixed gap stops meaning anything at all as the dimension climbs. So the caller asks for a
 * fraction, the device measures the middle distance between two points on this surface, and the gap
 * is that fraction of it. The fraction is comparable across shapes and dimensions where an absolute
 * length is not.
 */

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <cstdint>
#include <vector>
#include <algorithm>

#define SPHERE 0
#define CUBE 1
#define ORTHOPLEX 2

#define MAX_DIMS 64

__host__ __device__ inline uint64_t stir(uint64_t value)
{
    value += 0x9E3779B97F4A7C15ULL;
    value = (value ^ (value >> 30)) * 0xBF58476D1CE4E5B9ULL;
    value = (value ^ (value >> 27)) * 0x94D049BB133111EBULL;
    return value ^ (value >> 31);
}

__host__ __device__ inline float next_unit(uint64_t *state)
{
    *state = stir(*state);
    return (float)((*state >> 11) & 0x1FFFFFFFFFFFFFULL) * (1.0f / 9007199254740992.0f);
}

__host__ __device__ inline float next_normal(uint64_t *state)
{
    /* Box-Muller. The log is guarded because a uniform of exactly zero is representable and its
     * logarithm is not, and one infinity in a coordinate poisons every distance it appears in. */
    float first = next_unit(state);
    if (first < 1e-7f)
    {
        first = 1e-7f;
    }
    float second = next_unit(state);
    return sqrtf(-2.0f * logf(first)) * cosf(6.2831853071795864f * second);
}

/** @brief One point on the named surface, written into `out`. */
__host__ __device__ inline void place(float *out, int dims, int shape, uint64_t *state)
{
    int at;
    if (shape == SPHERE)
    {
        float total = 0.0f;
        for (at = 0; at < dims; at++)
        {
            out[at] = next_normal(state);
            total += out[at] * out[at];
        }
        float length = sqrtf(total);
        if (length < 1e-20f)
        {
            length = 1.0f;
        }
        for (at = 0; at < dims; at++)
        {
            out[at] /= length;
        }
        return;
    }

    if (shape == CUBE)
    {
        /* A facet first and then a place on it. Drawing inside the solid and pushing outward
         * instead crowds the corners, which makes a cube look as though it holds more than it
         * does, and the error grows with the dimension. */
        int facet = (int)(next_unit(state) * dims);
        if (facet >= dims)
        {
            facet = dims - 1;
        }
        for (at = 0; at < dims; at++)
        {
            out[at] = 2.0f * next_unit(state) - 1.0f;
        }
        out[facet] = (next_unit(state) < 0.5f) ? 1.0f : -1.0f;
        return;
    }

    /* The cross-polytope: the surface where the coordinates sum to one in absolute value. Drawn by
     * taking exponentials and normalising their sum, which lands uniformly over each facet, then
     * giving every coordinate its own sign. */
    float total = 0.0f;
    for (at = 0; at < dims; at++)
    {
        float unit = next_unit(state);
        if (unit < 1e-7f)
        {
            unit = 1e-7f;
        }
        out[at] = -logf(unit);
        total += out[at];
    }
    if (total < 1e-20f)
    {
        total = 1.0f;
    }
    for (at = 0; at < dims; at++)
    {
        out[at] /= total;
        if (next_unit(state) < 0.5f)
        {
            out[at] = -out[at];
        }
    }
}

__global__ void make_points(float *points, int count, int dims, int shape, uint64_t seed)
{
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    if (index >= count)
    {
        return;
    }
    uint64_t state = stir(seed ^ ((uint64_t)index * 0x2545F4914F6CDD1DULL));
    place(points + (size_t)index * dims, dims, shape, &state);
}

/**
 * @brief Marks which candidates in this batch sit clear of every point already kept.
 *
 * One thread per candidate, walking the kept set. The kept set is read by every thread in the
 * block in the same order, so it streams out of cache rather than being fetched per thread.
 */
__global__ void clear_of_kept(const float *kept, int kept_count, const float *batch, int batch_count,
                              int dims, float limit, int *ok)
{
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    if (index >= batch_count)
    {
        return;
    }
    const float *mine = batch + (size_t)index * dims;
    int clear = 1;
    for (int other = 0; other < kept_count && clear; other++)
    {
        const float *theirs = kept + (size_t)other * dims;
        float total = 0.0f;
        for (int at = 0; at < dims; at++)
        {
            float gap = mine[at] - theirs[at];
            total += gap * gap;
            if (total >= limit)
            {
                break;
            }
        }
        if (total < limit)
        {
            clear = 0;
        }
    }
    ok[index] = clear;
}

/**
 * @brief The same test with the running total kept in double.
 *
 * The points are the same points and only the accumulator changes. Nineteen squared differences
 * summed in single precision carry about a part in ten million of error, and the decision being
 * made is whether that total sits under a threshold, so a candidate landing within that of the
 * threshold could be decided either way. Whether any candidate ever does is a question about this
 * arrangement and not about floating point in general, and it is cheaper to answer than to argue:
 * run both and see whether the count moves.
 */
__global__ void clear_of_kept_wide(const float *kept, int kept_count, const float *batch,
                                   int batch_count, int dims, double limit, int *ok)
{
    int index = blockIdx.x * blockDim.x + threadIdx.x;
    if (index >= batch_count)
    {
        return;
    }
    const float *mine = batch + (size_t)index * dims;
    int clear = 1;
    for (int other = 0; other < kept_count && clear; other++)
    {
        const float *theirs = kept + (size_t)other * dims;
        double total = 0.0;
        for (int at = 0; at < dims; at++)
        {
            double gap = (double)mine[at] - (double)theirs[at];
            total += gap * gap;
            if (total >= limit)
            {
                break;
            }
        }
        if (total < limit)
        {
            clear = 0;
        }
    }
    ok[index] = clear;
}

static float apart(const float *one, const float *two, int dims)
{
    float total = 0.0f;
    for (int at = 0; at < dims; at++)
    {
        float gap = one[at] - two[at];
        total += gap * gap;
    }
    return total;
}

int main(int argc, char **argv)
{
    int shape = SPHERE;
    int dims = 3;
    float fraction = 0.40f;
    int candidates = 400000;
    uint64_t seed = 7;
    int wide_math = 0;

    for (int at = 1; at + 1 < argc; at += 2)
    {
        if (strcmp(argv[at], "--shape") == 0)
        {
            if (strcmp(argv[at + 1], "sphere") == 0) { shape = SPHERE; }
            else if (strcmp(argv[at + 1], "cube") == 0) { shape = CUBE; }
            else if (strcmp(argv[at + 1], "orthoplex") == 0) { shape = ORTHOPLEX; }
            else { fprintf(stderr, "shape takes sphere, cube or orthoplex\n"); return 2; }
        }
        else if (strcmp(argv[at], "--dims") == 0) { dims = atoi(argv[at + 1]); }
        else if (strcmp(argv[at], "--fraction") == 0) { fraction = (float)atof(argv[at + 1]); }
        else if (strcmp(argv[at], "--candidates") == 0) { candidates = atoi(argv[at + 1]); }
        else if (strcmp(argv[at], "--seed") == 0) { seed = strtoull(argv[at + 1], NULL, 10); }
        else if (strcmp(argv[at], "--wide") == 0) { wide_math = atoi(argv[at + 1]); }
    }

    if (dims < 2 || dims > MAX_DIMS)
    {
        fprintf(stderr, "dims sits between 2 and %d\n", MAX_DIMS);
        return 2;
    }

    /* Candidates are drawn a batch at a time and thrown away again, never held all at once. A pool
     * big enough to saturate a surface in nineteen dimensions is large and almost all of it is
     * refused, so holding it costs memory to store points that were only ever going to be rejected.
     * Drawing fresh ones against a kept set that is already growing does the same work, keeps the
     * footprint at one batch, and lets the run stop when it stops finding anything rather than when
     * a number chosen in advance runs out. */
    int block = 256;
    int batch = 4096;
    float *scratch = NULL;
    int *flags = NULL;
    float *kept = NULL;

    if (cudaMalloc(&scratch, (size_t)batch * dims * sizeof(float)) != cudaSuccess)
    {
        fprintf(stderr, "the device refused a batch at %d dimensions\n", dims);
        return 1;
    }
    cudaMalloc(&flags, (size_t)batch * sizeof(int));

    /* One batch first, to measure what the middle distance between two points on this surface is.
     * The gap is a fraction of that, measured on the same kind of points that are about to be
     * packed rather than on a fresh draw with its own character. */
    make_points<<<(batch + block - 1) / block, block>>>(scratch, batch, dims, shape, seed);
    if (cudaDeviceSynchronize() != cudaSuccess)
    {
        fprintf(stderr, "placing the candidates failed\n");
        return 1;
    }
    std::vector<float> some((size_t)batch * dims);
    cudaMemcpy(some.data(), scratch, some.size() * sizeof(float), cudaMemcpyDeviceToHost);
    std::vector<float> gaps;
    gaps.reserve(2000);
    for (int pair = 0; pair < 2000; pair++)
    {
        int one = (pair * 7919) % batch;
        int two = (pair * 104729 + 13) % batch;
        if (one == two) { continue; }
        gaps.push_back(sqrtf(apart(&some[(size_t)one * dims], &some[(size_t)two * dims], dims)));
    }
    std::sort(gaps.begin(), gaps.end());
    float typical = gaps.empty() ? 1.0f : gaps[gaps.size() / 2];
    float gap = fraction * typical;
    float limit = gap * gap;

    int room = 300000;
    if (cudaMalloc(&kept, (size_t)room * dims * sizeof(float)) != cudaSuccess)
    {
        fprintf(stderr, "the device refused room for the kept set\n");
        return 1;
    }

    std::vector<float> here((size_t)batch * dims);
    std::vector<int> clear((size_t)batch);
    std::vector<float> mine;
    mine.reserve((size_t)room * dims);
    int count = 0;
    int tried = 0;
    int quiet = 0;
    int rounds = (candidates + batch - 1) / batch;

    for (int round = 0; round < rounds; round++)
    {
        int wide = batch;
        make_points<<<(wide + block - 1) / block, block>>>(
            scratch, wide, dims, shape, stir(seed + 0x9E3779B9ULL * (uint64_t)(round + 1)));

        if (wide_math)
        {
            clear_of_kept_wide<<<(wide + block - 1) / block, block>>>(
                kept, count, scratch, wide, dims, (double)limit, flags);
        }
        else
        {
            clear_of_kept<<<(wide + block - 1) / block, block>>>(
                kept, count, scratch, wide, dims, limit, flags);
        }
        cudaMemcpy(clear.data(), flags, (size_t)wide * sizeof(int), cudaMemcpyDeviceToHost);
        cudaMemcpy(here.data(), scratch, (size_t)wide * dims * sizeof(float),
                   cudaMemcpyDeviceToHost);
        tried += wide;

        /* The device said which candidates clear everything kept before this batch began. What it
         * cannot say is which of them clear each other, because that depends on decisions being
         * made now. So they are settled here, in the order they arrived, which is what makes this
         * the same answer a sequential pass would reach. */
        int added = 0;
        int was = count;
        for (int index = 0; index < wide; index++)
        {
            if (!clear[index]) { continue; }
            const float *candidate = &here[(size_t)index * dims];
            bool good = true;
            for (int other = 0; other < added && good; other++)
            {
                const float *earlier = &mine[(size_t)(was + other) * dims];
                if (apart(candidate, earlier, dims) < limit) { good = false; }
            }
            if (!good) { continue; }
            if (count >= room) { break; }
            mine.insert(mine.end(), candidate, candidate + dims);
            count++;
            added++;
        }

        if (added > 0)
        {
            cudaMemcpy(kept + (size_t)was * dims, &mine[(size_t)was * dims],
                       (size_t)added * dims * sizeof(float), cudaMemcpyHostToDevice);
        }
        if (count >= room) { break; }

        /* Saturated when a whole batch of fresh candidates finds nowhere to sit, several batches
         * running. Stopping at the first empty batch would stop early, since a nearly full surface
         * still has room that a few thousand draws can miss by chance. */
        quiet = (added == 0) ? quiet + 1 : 0;
        if (quiet >= 12) { break; }
    }

    const char *name = shape == SPHERE ? "sphere" : (shape == CUBE ? "cube" : "orthoplex");
    printf("%s %d %.8f %.8f %d %d %s %s\n", name, dims, gap, typical, count, tried,
           quiet >= 12 ? "saturated" : "ranout", wide_math ? "double" : "single");

    cudaFree(scratch);
    cudaFree(kept);
    cudaFree(flags);
    return 0;
}
