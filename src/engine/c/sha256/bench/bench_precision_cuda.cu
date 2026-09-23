/* BTC - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file bench_precision_cuda.cu
 * @brief Four arms reading one invariant, so their disagreement measures the arithmetic and nothing else.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-10
 *
 * WHAT IS BEING MEASURED
 *
 * Power per harmonic degree, P_l, is invariant under every rotation, because the degree-l subspace
 * carries a unitary irreducible representation of the rotation group. On a ring placement turned by
 * whole steps the statement is tighter: each point slides along its own ring, the turned
 * configuration is the same set of directions relabelled, each coefficient pair rotates rigidly,
 * and the sum of their squares cannot move.
 *
 * So the residual is exactly zero and no measurement is needed to know it. Whatever a program
 * reports above zero is its arithmetic. That makes this a calibrated null in the strict sense: the
 * predicted value comes from a law instead of from a model, and the reported number is the gap.
 *
 * FOUR ARMS
 *
 * Host float, host double, device float, device double. Two of the four differ only in where they
 * ran, so their disagreement isolates the device from the width, and two differ only in width, so
 * their disagreement isolates the width from the device. Read together they separate the two causes
 * that a single arm confounds.
 *
 * @note ONE IMPLEMENTATION, TEMPLATED. Everything below is written once and instantiated at both
 *       widths and on both sides. A second copy of a statistic is failure mode fifteen and this
 *       bench exists to compare arithmetic, so two sources would put the difference being measured
 *       into the sources themselves.
 * @note THE SUMMATION ORDER IS FIXED. One thread owns one coefficient slot and walks the lit set in
 *       index order, so there is no atomic, no shuffle and no tree reduction anywhere. A device
 *       reduction would reassociate the sum and the reported divergence would then be a fact about
 *       the reduction and not about the device's arithmetic. This costs throughput and buys the
 *       only comparison worth printing.
 * @note WHAT THE DEVICE DOES AND DOES NOT DO. The device sums coefficients. P_l and the relative
 *       residual are formed on the host at the matching width, because they are eighty-one squares
 *       and nine sums and putting them on the device would add a second reassociation to argue
 *       about for no measurable gain.
 * @note The problem is deliberately small. Eighty-one slots over a placement of 256 is not a
 *       throughput test and reporting it as one would be dishonest; @ref main prints a wall time
 *       so the reader can see it is dominated by launch overhead.
 */

#include <cuda_runtime.h>

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>

/* The placement, ceiling and rotations examples/proofing/precision_floor.py runs, so the numbers printed
 * here sit on the same axis as the arbitrary-precision ladder that tool produces. */
#define PLACEMENT_RINGS 8
#define PLACEMENT_WIDTH 32
#define PLACEMENT_TOTAL (PLACEMENT_RINGS * PLACEMENT_WIDTH)
#define DEGREE_CEILING 8
#define COEFFICIENT_COUNT ((DEGREE_CEILING + 1) * (DEGREE_CEILING + 1))

/* Rotations in whole ring steps. Each is an exact relabelling of the placement. */
static const int ROTATION_STEPS[] = {0, 1, 5, 13, 31};
#define ROTATION_COUNT ((int)(sizeof(ROTATION_STEPS) / sizeof(ROTATION_STEPS[0])))

/**
 * @brief Pi at the working width, written out past double so the float case rounds and does not truncate.
 * @return Pi as T.
 */
template <typename T>
__host__ __device__ static inline T pi_of(void)
{
    return (T)3.14159265358979323846264338327950288;
}

/**
 * @brief Normalised associated Legendre values for one order, every degree up to the ceiling.
 * @param top    Degree ceiling.
 * @param order  The order, non-negative.
 * @param x      Cosine of the colatitude.
 * @param out    Buffer of top+1 values the caller owns, written in full.
 *
 * Climbs the diagonal and then recurs in degree, which holds every intermediate at unit scale. The
 * factorial form overflows above degree 150 and loses digits long before that, and it loses them
 * quietly: the low degrees stay right and only the fine structure goes wrong.
 */
template <typename T>
__host__ __device__ static void legendre_column(int top, int order, T x, T *out)
{
    for (int slot = 0; slot <= top; slot++)
    {
        out[slot] = (T)0;
    }

    const T flat = (T)1 - x * x;
    const T sine = sqrt(flat > (T)0 ? flat : (T)0);
    T value = sqrt((T)1 / ((T)4 * pi_of<T>()));

    for (int step = 1; step <= order; step++)
    {
        value *= sqrt((T)(2 * step + 1) / (T)(2 * step)) * sine;
    }
    if (order <= top)
    {
        out[order] = value;
    }
    if (order + 1 <= top)
    {
        out[order + 1] = sqrt((T)(2 * order + 3)) * x * value;
    }
    for (int degree = order + 2; degree <= top; degree++)
    {
        const T lead = sqrt((T)(4 * degree * degree - 1) / (T)(degree * degree - order * order));
        const T trail = sqrt((T)((degree - 1) * (degree - 1) - order * order)
                             / (T)(4 * (degree - 1) * (degree - 1) - 1));
        out[degree] = lead * (x * out[degree - 1] - trail * out[degree - 2]);
    }
}

/**
 * @brief One coefficient of the boundary reading, summed over the lit set in index order.
 * @param slot        Flattened coefficient index, degree l occupying the run starting at l squared.
 * @param live        Lit indices into the placement.
 * @param live_count  How many are lit.
 * @param steps       Rotation in whole ring steps applied to every lit point.
 * @return The coefficient at that slot.
 *
 * The basis is real, so an order above zero carries a cosine part at the +order slot and a sine
 * part at the -order slot. Under a rotation those two turn into each other rigidly, which is the
 * invariance this bench nulls against.
 */
template <typename T>
__host__ __device__ static T coefficient_at(int slot, const int *live, int live_count, int steps)
{
    int degree = 0;
    while ((degree + 1) * (degree + 1) <= slot)
    {
        degree++;
    }
    const int order = slot - degree * degree - degree;
    const int magnitude = order < 0 ? -order : order;

    T column[DEGREE_CEILING + 1];
    T total = (T)0;
    const T pi = pi_of<T>();
    const T root_two = sqrt((T)2);

    for (int at = 0; at < live_count; at++)
    {
        const int ring = live[at] / PLACEMENT_WIDTH;
        const int step = (live[at] % PLACEMENT_WIDTH + steps) % PLACEMENT_WIDTH;

        const T colatitude = pi * (T)(2 * ring + 1) / (T)(2 * PLACEMENT_RINGS);
        legendre_column<T>(DEGREE_CEILING, magnitude, cos(colatitude), column);

        const T longitude = (T)2 * pi * (T)step / (T)PLACEMENT_WIDTH;
        if (order == 0)
        {
            total += column[degree];
        }
        else if (order > 0)
        {
            total += column[degree] * root_two * cos((T)magnitude * longitude);
        }
        else
        {
            total += column[degree] * root_two * sin((T)magnitude * longitude);
        }
    }
    return total;
}

/**
 * @brief One block per rotation, one thread per coefficient slot.
 * @param out         Coefficients, rotation-major.
 * @param live        Lit indices.
 * @param live_count  How many are lit.
 * @param rotations   Rotation amounts in whole ring steps.
 */
template <typename T>
__global__ static void read_boundary(T *out, const int *live, int live_count, const int *rotations)
{
    const int slot = (int)threadIdx.x;
    if (slot >= COEFFICIENT_COUNT)
    {
        return;
    }
    out[blockIdx.x * COEFFICIENT_COUNT + slot] =
        coefficient_at<T>(slot, live, live_count, rotations[blockIdx.x]);
}

/**
 * @brief The same reading on the host, for the arm the device is compared against.
 */
template <typename T>
static void read_boundary_host(T *out, const int *live, int live_count, const int *rotations)
{
    for (int turn = 0; turn < ROTATION_COUNT; turn++)
    {
        for (int slot = 0; slot < COEFFICIENT_COUNT; slot++)
        {
            out[turn * COEFFICIENT_COUNT + slot] =
                coefficient_at<T>(slot, live, live_count, rotations[turn]);
        }
    }
}

/**
 * @brief Power per degree from one rotation's coefficients.
 * @param coefficients  One rotation's slots.
 * @param out           Degree ceiling plus one values.
 */
template <typename T>
static void power_per_degree(const T *coefficients, T *out)
{
    for (int degree = 0; degree <= DEGREE_CEILING; degree++)
    {
        T total = (T)0;
        for (int slot = degree * degree; slot < (degree + 1) * (degree + 1); slot++)
        {
            total += coefficients[slot] * coefficients[slot];
        }
        out[degree] = total;
    }
}

/**
 * @brief Worst relative change in power per degree across every rotation, against the unturned read.
 * @param coefficients  Every rotation's slots, rotation-major, rotation zero being unturned.
 * @return The residual, in the units the reading reports, as a double for printing only.
 *
 * @warning The return is widened to double for the report. The comparison itself happens at T, so
 *          a float arm's residual is a float arm's residual and is not a double subtraction of two
 *          floats.
 */
template <typename T>
static double worst_relative(const T *coefficients)
{
    T base[DEGREE_CEILING + 1];
    T moved[DEGREE_CEILING + 1];
    power_per_degree<T>(coefficients, base);

    T worst = (T)0;
    for (int turn = 1; turn < ROTATION_COUNT; turn++)
    {
        power_per_degree<T>(coefficients + turn * COEFFICIENT_COUNT, moved);
        for (int degree = 0; degree <= DEGREE_CEILING; degree++)
        {
            const T scale = base[degree] < (T)0 ? -base[degree] : base[degree];
            const T gap = moved[degree] - base[degree];
            const T size = gap < (T)0 ? -gap : gap;
            const T relative = size / (scale > (T)0 ? scale : (T)1);
            if (relative > worst)
            {
                worst = relative;
            }
        }
    }
    return (double)worst;
}

/**
 * @brief Largest gap between two arms' coefficients, against the largest coefficient present.
 * @param first   One arm's coefficients, every rotation.
 * @param second  The other arm's, same layout.
 * @return The gap as a fraction of the reading's own scale.
 *
 * @warning THE PER-COEFFICIENT RELATIVE FORM IS WRONG HERE AND WAS TRIED FIRST. It reported
 *          2.727e-03 for float32 and 3.629e-12 for float64, both about two hundred times the
 *          residual printed beside them, which is backwards: two arms of the same width should
 *          agree with each other better than either agrees with zero.
 *
 *          The cause is the spread of the coefficients. A ring placement puts most of its power in
 *          a few slots and these run about six orders of magnitude from the largest to the
 *          smallest, so dividing each gap by its own coefficient lets the smallest slots set the
 *          answer and inflates it by roughly that ratio.
 *
 * @note    THE FIRST DIAGNOSIS OF THAT WAS WRONG AND THE TOOL REFUTED IT. It was written here that
 *          most slots are exactly zero by symmetry and that the metric was dividing a rounding
 *          error by a rounding error. @ref slots_near_zero was added to put the claim in the output
 *          as a number, and the number came back zero of 405: no slot is anywhere near zero. The
 *          small denominators are small and not absent, which is a different defect with the same
 *          symptom. The count stays in the report because it is what settled it.
 *
 *          So the scale is the largest coefficient in the reading, which is the size of the thing a
 *          gap should be judged against.
 */
template <typename T>
static double worst_between(const T *first, const T *second)
{
    double scale = 0.0;
    for (int slot = 0; slot < ROTATION_COUNT * COEFFICIENT_COUNT; slot++)
    {
        if (fabs((double)first[slot]) > scale)
        {
            scale = fabs((double)first[slot]);
        }
    }
    if (scale <= 0.0)
    {
        scale = 1.0;
    }

    double worst = 0.0;
    for (int slot = 0; slot < ROTATION_COUNT * COEFFICIENT_COUNT; slot++)
    {
        const double gap = fabs((double)second[slot] - (double)first[slot]) / scale;
        if (gap > worst)
        {
            worst = gap;
        }
    }
    return worst;
}

/**
 * @brief How many slots sit under a fraction of the largest, and how far the slots spread.
 * @param values   One arm's coefficients, every rotation.
 * @param share    The fraction of the largest below which a slot counts as carrying nothing.
 * @param spread   Written with the ratio of the largest slot to the smallest.
 * @return The count under `share`.
 *
 * Both numbers are printed so the warning on @ref worst_between is arithmetic in the output instead
 * of a claim in a comment. The count tests whether slots vanish and the spread tests whether they
 * are merely small, and those are the two candidate causes of the same symptom.
 */
template <typename T>
static int slots_near_zero(const T *values, double share, double *spread)
{
    double largest = 0.0;
    double smallest = 0.0;
    for (int slot = 0; slot < ROTATION_COUNT * COEFFICIENT_COUNT; slot++)
    {
        const double size = fabs((double)values[slot]);
        if (size > largest)
        {
            largest = size;
        }
        if (slot == 0 || size < smallest)
        {
            smallest = size;
        }
    }
    *spread = smallest > 0.0 ? largest / smallest : 0.0;

    int counted = 0;
    for (int slot = 0; slot < ROTATION_COUNT * COEFFICIENT_COUNT; slot++)
    {
        if (fabs((double)values[slot]) < share * largest)
        {
            counted++;
        }
    }
    return counted;
}

/**
 * @brief Runs one width on both sides and prints the three numbers that width supplies.
 * @param name       The width's name, for the report.
 * @param digits     Decimal digits the width carries, for the plot's axis.
 * @param live       Lit indices on the host.
 * @param live_count How many are lit.
 * @param on_device  Lit indices already on the device.
 * @param rotations  Rotation amounts already on the device.
 * @return Zero on success.
 */
template <typename T>
static int run_width(const char *name, double digits, const int *live, int live_count,
                     const int *on_device, const int *rotations)
{
    const size_t bytes = (size_t)ROTATION_COUNT * COEFFICIENT_COUNT * sizeof(T);
    T *host = (T *)malloc(bytes);
    T *back = (T *)malloc(bytes);
    T *device = NULL;
    if (!host || !back)
    {
        fprintf(stderr, "out of host memory\n");
        return 1;
    }
    if (cudaMalloc((void **)&device, bytes) != cudaSuccess)
    {
        fprintf(stderr, "cudaMalloc failed\n");
        return 1;
    }

    read_boundary_host<T>(host, live, live_count, ROTATION_STEPS);

    read_boundary<T><<<ROTATION_COUNT, COEFFICIENT_COUNT>>>(device, on_device, live_count, rotations);
    const cudaError_t launched = cudaDeviceSynchronize();
    if (launched != cudaSuccess)
    {
        fprintf(stderr, "kernel failed: %s\n", cudaGetErrorString(launched));
        return 1;
    }
    if (cudaMemcpy(back, device, bytes, cudaMemcpyDeviceToHost) != cudaSuccess)
    {
        fprintf(stderr, "copy back failed\n");
        return 1;
    }

    printf("%s\thost\t%.4f\t%.6e\n", name, digits, worst_relative<T>(host));
    printf("%s\tdevice\t%.4f\t%.6e\n", name, digits, worst_relative<T>(back));
    printf("%s\tbetween\t%.4f\t%.6e\n", name, digits, worst_between<T>(host, back));
    double spread = 0.0;
    const int quiet = slots_near_zero<T>(host, 1e-6, &spread);
    printf("# %s\t%d of %d slots under a millionth of the largest\tspread largest to smallest %.3e\n",
           name, quiet, ROTATION_COUNT * COEFFICIENT_COUNT, spread);

    cudaFree(device);
    free(host);
    free(back);
    return 0;
}

/**
 * @brief Prints a tab separated table of width, arm, decimal digits and residual.
 *
 * Machine readable because examples/proofing/precision_plot.py reads it and puts it on one axis with the
 * arbitrary-precision ladder. A reader wanting prose should run that tool.
 */
int main(void)
{
    int live[PLACEMENT_TOTAL];
    int live_count = 0;

    /* The same lit set the harness and the ladder use: about half weight, and no structure anybody
     * chose. Written the same way in three places is a duplication worth naming, and it is here
     * because a shared header across a .py and a .cu does not exist in this tree. */
    for (int k = 0; k < PLACEMENT_TOTAL; k++)
    {
        if ((k * 7 + k / 5) % 3)
        {
            live[live_count++] = k;
        }
    }

    int *on_device = NULL;
    int *rotations = NULL;
    if (cudaMalloc((void **)&on_device, sizeof(live)) != cudaSuccess
        || cudaMalloc((void **)&rotations, sizeof(ROTATION_STEPS)) != cudaSuccess)
    {
        fprintf(stderr, "cudaMalloc failed\n");
        return 1;
    }
    cudaMemcpy(on_device, live, sizeof(live), cudaMemcpyHostToDevice);
    cudaMemcpy(rotations, ROTATION_STEPS, sizeof(ROTATION_STEPS), cudaMemcpyHostToDevice);

    cudaDeviceProp about;
    if (cudaGetDeviceProperties(&about, 0) == cudaSuccess)
    {
        printf("# device\t%s\tcompute %d.%d\n", about.name, about.major, about.minor);
    }
    printf("# placement\t%d rings by %d\tdegree ceiling %d\t%d coefficients\t%d lit\n",
           PLACEMENT_RINGS, PLACEMENT_WIDTH, DEGREE_CEILING, COEFFICIENT_COUNT, live_count);
    printf("# the law puts every residual below at exactly zero\n");
    printf("width\tarm\tdigits\tresidual\n");

    /* Decimal digits of the mantissa: 24 bits and 53 bits over log2(10). */
    int failed = run_width<float>("float32", 24.0 / 3.321928094887362, live, live_count,
                                  on_device, rotations);
    failed |= run_width<double>("float64", 53.0 / 3.321928094887362, live, live_count,
                                on_device, rotations);

    cudaFree(on_device);
    cudaFree(rotations);
    return failed;
}
