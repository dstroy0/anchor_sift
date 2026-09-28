// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef PERIODIC_ENERGY_H
#define PERIODIC_ENERGY_H

#include "sim.h"

#define ENERGY_THREADS 128ull

typedef struct
{
    int found;
    unsigned long long period;
    AnchorExactInteger numerator;
    AnchorExactInteger denominator;
} EnergyMeasurement;

typedef struct
{
    unsigned long long phase_count;
    long long *sums;
    unsigned long long *squares;
    unsigned long long *members;
} EnergyPhases;

static inline __host__ __device__ unsigned long long energy_phase_base(unsigned long long period)
{
    return ((period * (period - 1ull)) / 2ull) - 1ull;
}

static __global__ void energy_phase_kernel(const long long *values, unsigned long long length, unsigned long long range,
                                           long long *sums)
{
    const unsigned long long index = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    const unsigned long long slots = energy_phase_base(range + 1ull);
    if (index >= slots)
    {
        return;
    }
    unsigned long long period = 2ull;
    while (energy_phase_base(period + 1ull) <= index)
    {
        period += 1ull;
    }
    const unsigned long long phase = index - energy_phase_base(period);
    long long total = 0ll;
    for (unsigned long long at = phase; at < length; at += period)
    {
        total += values[at];
    }
    sums[index] = total;
}

static inline int energy_phase_sums(SimResults *results, const long long *values, unsigned long long length,
                                    unsigned long long range, long long *sums)
{
    const unsigned long long slots = energy_phase_base(range + 1ull);
    long long *device_values = NULL;
    long long *device_sums = NULL;
    int ok =
        sim_status_check(results, cudaMalloc((void **)&device_values, length * sizeof(long long)), "energy: values");
    ok = ok && sim_status_check(results, cudaMalloc((void **)&device_sums, slots * sizeof(long long)), "energy: sums");
    ok = ok && sim_status_check(results,
                                cudaMemcpy(device_values, values, length * sizeof(long long), cudaMemcpyHostToDevice),
                                "energy: upload");
    if (ok)
    {
        // the slot count is below 2^31 for every range here
        const unsigned int blocks = (unsigned int)sim_launch_blocks(slots, ENERGY_THREADS);
        energy_phase_kernel<<<blocks, (unsigned int)ENERGY_THREADS>>>(device_values, length, range, device_sums);
        ok = sim_status_check(results, cudaGetLastError(), "energy: launch");
        ok = ok && sim_status_check(results, cudaDeviceSynchronize(), "energy: run");
    }
    ok = ok &&
         sim_status_check(results, cudaMemcpy(sums, device_sums, slots * sizeof(long long), cudaMemcpyDeviceToHost),
                          "energy: sums read");
    cudaFree(device_sums);
    cudaFree(device_values);
    return ok;
}

static inline unsigned long long energy_members(unsigned long long length, unsigned long long period,
                                                unsigned long long phase)
{
    return (length / period) + ((phase < (length % period)) ? 1ull : 0ull);
}

static inline int energy_ratio(const long long *values, unsigned long long length, const long long *sums,
                               unsigned long long period, AnchorExactInteger *numerator,
                               AnchorExactInteger *denominator)
{
    if ((period < 2ull) || (period >= length))
    {
        return 0;
    }
    const unsigned long long fewer = length / period;
    const unsigned long long more = fewer + 1ull;
    AnchorExactInteger fewer_squares;
    AnchorExactInteger more_squares;
    AnchorExactInteger integer_sum;
    AnchorExactInteger integer_squares;
    AnchorExactInteger term;
    anchor_exact_zero(&fewer_squares);
    anchor_exact_zero(&more_squares);
    anchor_exact_zero(&integer_sum);
    anchor_exact_zero(&integer_squares);
    int ok = 1;
    for (unsigned long long phase = 0ull; ok && (phase < period); phase += 1ull)
    {
        AnchorExactInteger sum;
        sim_exact_signed(&sum, sums[energy_phase_base(period) + phase]);
        ok = sim_exact_sum(&integer_sum, &sum, &integer_sum) && sim_exact_product(&sum, &sum, &term);
        if (energy_members(length, period, phase) == more)
        {
            ok = ok && sim_exact_sum(&more_squares, &term, &more_squares);
        }
        else
        {
            ok = ok && sim_exact_sum(&fewer_squares, &term, &fewer_squares);
        }
    }
    for (unsigned long long at = 0ull; ok && (at < length); at += 1ull)
    {
        sim_exact_signed(&term, values[at]);
        ok = sim_exact_product(&term, &term, &term) && sim_exact_sum(&integer_squares, &term, &integer_squares);
    }
    AnchorExactInteger length_exact;
    AnchorExactInteger fewer_exact;
    AnchorExactInteger more_exact;
    sim_exact_unsigned(&length_exact, length);
    sim_exact_unsigned(&fewer_exact, fewer);
    sim_exact_unsigned(&more_exact, more);
    AnchorExactInteger counts;
    AnchorExactInteger between;
    AnchorExactInteger total;
    AnchorExactInteger part;
    ok = ok && sim_exact_product(&fewer_exact, &more_exact, &counts);
    ok = ok && sim_exact_product(&length_exact, &more_exact, &part) &&
         sim_exact_product(&part, &fewer_squares, &between);
    ok = ok && sim_exact_product(&length_exact, &fewer_exact, &part) &&
         sim_exact_product(&part, &more_squares, &part) && sim_exact_sum(&between, &part, &between);
    ok = ok && sim_exact_product(&integer_sum, &integer_sum, &part) && sim_exact_product(&part, &counts, &term) &&
         sim_exact_less(&between, &term, &between);
    ok = ok && sim_exact_product(&length_exact, &integer_squares, &total) && sim_exact_less(&total, &part, &total) &&
         sim_exact_product(&total, &counts, &total);
    AnchorExactInteger within;
    ok = ok && sim_exact_less(&total, &between, &within);
    if ((ok == 0) || (within.sign <= 0))
    {
        return 0;
    }
    return sim_exact_scaled(&between, length - period, numerator) &&
           sim_exact_scaled(&within, period - 1ull, denominator);
}

static inline int energy_recover(SimResults *results, const long long *values, unsigned long long length,
                                 unsigned long long range, long long *sums, EnergyMeasurement *measurement)
{
    measurement->found = 0;
    measurement->period = 0ull;
    // a range below 2 holds no period to test, and is refused before the device is asked (the slot count at range 0
    // would wrap)
    if ((length < 4ull) || (range < 2ull))
    {
        return 0;
    }
    const unsigned long long top = (range < (length - 1ull)) ? range : (length - 1ull);
    if (energy_phase_sums(results, values, length, top, sums) == 0)
    {
        return 0;
    }
    for (unsigned long long period = 2ull; period <= top; period += 1ull)
    {
        AnchorExactInteger numerator;
        AnchorExactInteger denominator;
        if (energy_ratio(values, length, sums, period, &numerator, &denominator) == 0)
        {
            continue;
        }
        int order = 1;
        if (measurement->found != 0)
        {
            sim_ratio_compare(&numerator, &denominator, &measurement->numerator, &measurement->denominator, &order);
        }
        if (order > 0)
        {
            measurement->found = 1;
            measurement->period = period;
            measurement->numerator = numerator;
            measurement->denominator = denominator;
        }
    }
    return 1;
}

static inline void energy_shuffle(const long long *values, long long *shuffled, unsigned long long length,
                                  unsigned long long key)
{
    memcpy(shuffled, values, (size_t)length * sizeof(long long));
    // fewer than two values shuffle to themselves, and length - 1 would wrap at 0
    if (length < 2ull)
    {
        return;
    }
    for (unsigned long long at = length - 1ull; at > 0ull; at -= 1ull)
    {
        const unsigned long long other = sim_draw_below(key, at, at + 1ull);
        const long long temporary = shuffled[at];
        shuffled[at] = shuffled[other];
        shuffled[other] = temporary;
    }
}

static inline int energy_band_top(SimResults *results, const long long *values, unsigned long long length,
                                  unsigned long long range, unsigned long long draws, unsigned long long key,
                                  long long *shuffled, long long *sums, EnergyMeasurement *top,
                                  unsigned long long *reached)
{
    top->found = 0;
    *reached = 0ull;
    for (unsigned long long draw = 0ull; draw < draws; draw += 1ull)
    {
        energy_shuffle(values, shuffled, length, sim_draw(key, draw));
        EnergyMeasurement measurement;
        if (energy_recover(results, shuffled, length, range, sums, &measurement) == 0)
        {
            return 0;
        }
        if (measurement.found == 0)
        {
            continue;
        }
        *reached += 1ull;
        int order = 1;
        if (top->found != 0)
        {
            sim_ratio_compare(&measurement.numerator, &measurement.denominator, &top->numerator, &top->denominator,
                              &order);
        }
        if (order > 0)
        {
            *top = measurement;
        }
    }
    return 1;
}

static inline int energy_above(const EnergyMeasurement *live, const EnergyMeasurement *top)
{
    if (live->found == 0)
    {
        return 0;
    }
    if (top->found == 0)
    {
        return 1;
    }
    int order = 0;
    return sim_ratio_compare(&live->numerator, &live->denominator, &top->numerator, &top->denominator, &order) &&
           (order > 0);
}

static inline void energy_print(ScripturaLine *line, const EnergyMeasurement *measurement)
{
    if (measurement->found == 0)
    {
        scriptura_text(line, "none");
        return;
    }
    sim_ratio_print(line, &measurement->numerator, &measurement->denominator, 3u);
}

static __global__ void energy_welford_kernel(const long long *values, unsigned long long length,
                                             unsigned long long period, long long *numerators,
                                             unsigned long long *denominators)
{
    const unsigned long long phase = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (phase >= period)
    {
        return;
    }
    long long numerator = 0ll;
    unsigned long long denominator = 1ull;
    unsigned long long seen = 0ull;
    for (unsigned long long at = phase; at < length; at += period)
    {
        seen += 1ull;
        // d and seen are member counts below 2^16 here, so every product fits 64 bits
        const long long step_numerator = (values[at] * (long long)denominator) - numerator;
        const unsigned long long step_denominator = denominator * seen;
        numerator = (numerator * (long long)step_denominator) + (step_numerator * (long long)denominator);
        denominator = denominator * step_denominator;
        unsigned long long left =
            (numerator < 0ll) ? (0ull - (unsigned long long)numerator) : (unsigned long long)numerator;
        unsigned long long right = denominator;
        while (right != 0ull)
        {
            const unsigned long long rest = left % right;
            left = right;
            right = rest;
        }
        if (left > 1ull)
        {
            // the common divisor divides the numerator exactly and is below 2^63
            numerator /= (long long)left;
            denominator /= left;
        }
    }
    numerators[phase] = numerator;
    denominators[phase] = denominator;
}

static inline int energy_welford(SimResults *results, const long long *values, unsigned long long length,
                                 unsigned long long period, long long *numerators, unsigned long long *denominators)
{
    long long *device_values = NULL;
    long long *device_numerators = NULL;
    unsigned long long *device_denominators = NULL;
    int ok =
        sim_status_check(results, cudaMalloc((void **)&device_values, length * sizeof(long long)), "welford: values");
    ok = ok && sim_status_check(results, cudaMalloc((void **)&device_numerators, period * sizeof(long long)),
                                "welford: means");
    ok = ok && sim_status_check(results, cudaMalloc((void **)&device_denominators, period * sizeof(unsigned long long)),
                                "welford: means");
    ok = ok && sim_status_check(results,
                                cudaMemcpy(device_values, values, length * sizeof(long long), cudaMemcpyHostToDevice),
                                "welford: upload");
    if (ok)
    {
        // a period is far below 2^31
        const unsigned int blocks = (unsigned int)sim_launch_blocks(period, ENERGY_THREADS);
        energy_welford_kernel<<<blocks, (unsigned int)ENERGY_THREADS>>>(device_values, length, period,
                                                                        device_numerators, device_denominators);
        ok = sim_status_check(results, cudaGetLastError(), "welford: launch");
        ok = ok && sim_status_check(results, cudaDeviceSynchronize(), "welford: run");
    }
    ok = ok &&
         sim_status_check(results,
                          cudaMemcpy(numerators, device_numerators, period * sizeof(long long), cudaMemcpyDeviceToHost),
                          "welford: read");
    ok = ok && sim_status_check(results,
                                cudaMemcpy(denominators, device_denominators, period * sizeof(unsigned long long),
                                           cudaMemcpyDeviceToHost),
                                "welford: read");
    cudaFree(device_denominators);
    cudaFree(device_numerators);
    cudaFree(device_values);
    return ok;
}

static inline int energy_reduction(const long long *noisy, const long long *target, unsigned long long length,
                                   unsigned long long period, const long long *phase_sums,
                                   AnchorExactInteger *numerator, AnchorExactInteger *denominator)
{
    const unsigned long long fewer = length / period;
    const unsigned long long more = fewer + 1ull;
    unsigned long long injected = 0ull;
    AnchorExactInteger left_fewer;
    AnchorExactInteger left_more;
    AnchorExactInteger term;
    anchor_exact_zero(&left_fewer);
    anchor_exact_zero(&left_more);
    int ok = 1;
    for (unsigned long long at = 0ull; ok && (at < length); at += 1ull)
    {
        const long long apart = noisy[at] - target[at];
        // a squared difference of small integers is non-negative and far below 2^63
        injected += (unsigned long long)(apart * apart);
        const unsigned long long phase = at % period;
        const unsigned long long members = energy_members(length, period, phase);
        // the member count is below 2^16 and each value below 2^16, so the product fits
        const long long left = ((long long)members * (noisy[at] - target[at])) - phase_sums[phase];
        sim_exact_signed(&term, left);
        ok = sim_exact_product(&term, &term, &term);
        ok = ok && sim_exact_sum((members == more) ? &left_more : &left_fewer, &term,
                                 (members == more) ? &left_more : &left_fewer);
    }
    if (injected == 0ull)
    {
        sim_exact_unsigned(numerator, 1ull);
        sim_exact_unsigned(denominator, 1ull);
        return ok;
    }
    AnchorExactInteger fewer_square;
    AnchorExactInteger more_square;
    AnchorExactInteger energy;
    sim_exact_unsigned(&fewer_square, fewer * fewer);
    sim_exact_unsigned(&more_square, more * more);
    ok = ok && sim_exact_product(&left_fewer, &more_square, &left_fewer);
    ok = ok && sim_exact_product(&left_more, &fewer_square, &left_more);
    ok = ok && sim_exact_sum(&left_fewer, &left_more, &energy);
    AnchorExactInteger scale;
    ok =
        ok && sim_exact_product(&fewer_square, &more_square, &scale) && sim_exact_scaled(&scale, injected, denominator);
    ok = ok && sim_exact_less(denominator, &energy, numerator);
    return ok;
}

#endif
