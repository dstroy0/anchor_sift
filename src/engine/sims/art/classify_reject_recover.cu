// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "periodic_energy.h"

#define CLASSIFY_HEIGHT 8ull

#define CLASSIFY_WIDTH 8ull

#define CLASSIFY_FRAME (CLASSIFY_HEIGHT * CLASSIFY_WIDTH)

#define CLASSIFY_FRAMES 48ull

#define CLASSIFY_LENGTH (CLASSIFY_FRAME * CLASSIFY_FRAMES)

#define CLASSIFY_SWING 20ll

#define CLASSIFY_AMPLITUDE 40ll

#define CLASSIFY_DRAWS 8ull

#define CLASSIFY_KEY 0xF17Aull

#define CLASSIFY_SUBJECT_MAX 200ull

#define CLASSIFY_IMPULSE_MAX 255ull

#define CLASSIFY_REPEAT_VARIANCE 144ull

typedef struct
{
    long long scene[CLASSIFY_LENGTH];
    long long pattern[CLASSIFY_FRAME];
    long long subject[CLASSIFY_FRAME];
    long long stack[CLASSIFY_LENGTH];
    long long truth[CLASSIFY_LENGTH];
    long long shuffled[CLASSIFY_LENGTH];
    long long sums[(CLASSIFY_FRAME * (CLASSIFY_FRAME + 1ull)) / 2ull];
    long long welford_numerator[CLASSIFY_FRAME];
    unsigned long long welford_denominator[CLASSIFY_FRAME];
    long long by_count[CLASSIFY_FRAME];
    long long by_median[CLASSIFY_FRAME];
} ClassifyWork;

static __global__ void classify_consensus_kernel(const long long *values, unsigned long long length,
                                                 unsigned long long period, long long *by_count, long long *by_median)
{
    const unsigned long long phase = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x;
    if (phase >= period)
    {
        return;
    }
    long long member[CLASSIFY_FRAMES];
    unsigned long long count = 0ull;
    for (unsigned long long at = phase; (at < length) && (count < CLASSIFY_FRAMES); at += period)
    {
        member[count] = values[at];
        count += 1ull;
    }
    unsigned long long maximum = 0ull;
    long long chosen = 0ll;
    for (unsigned long long one = 0ull; one < count; one += 1ull)
    {
        unsigned long long same = 0ull;
        for (unsigned long long other = 0ull; other < count; other += 1ull)
        {
            same += (member[other] == member[one]) ? 1ull : 0ull;
        }
        if ((same > maximum) || ((same == maximum) && (member[one] < chosen)))
        {
            maximum = same;
            chosen = member[one];
        }
    }
    by_count[phase] = chosen;
    for (unsigned long long at = 1ull; at < count; at += 1ull)
    {
        const long long key = member[at];
        unsigned long long place = at;
        while ((place > 0ull) && (member[place - 1ull] > key))
        {
            member[place] = member[place - 1ull];
            place -= 1ull;
        }
        member[place] = key;
    }
    by_median[phase] = member[(count - 1ull) / 2ull];
}

static int classify_consensus(SimResults *results, const long long *values, long long *by_count, long long *by_median)
{
    long long *device_values = NULL;
    long long *device_count = NULL;
    long long *device_median = NULL;
    int ok = sim_status_check(results, cudaMalloc((void **)&device_values, CLASSIFY_LENGTH * sizeof(long long)),
                              "consensus");
    ok = ok &&
         sim_status_check(results, cudaMalloc((void **)&device_count, CLASSIFY_FRAME * sizeof(long long)), "consensus");
    ok = ok && sim_status_check(results, cudaMalloc((void **)&device_median, CLASSIFY_FRAME * sizeof(long long)),
                                "consensus");
    ok = ok &&
         sim_status_check(
             results, cudaMemcpy(device_values, values, CLASSIFY_LENGTH * sizeof(long long), cudaMemcpyHostToDevice),
             "consensus: upload");
    if (ok)
    {
        classify_consensus_kernel<<<1u, (unsigned int)CLASSIFY_FRAME>>>(device_values, CLASSIFY_LENGTH, CLASSIFY_FRAME,
                                                                        device_count, device_median);
        ok = sim_status_check(results, cudaGetLastError(), "consensus: launch");
        ok = ok && sim_status_check(results, cudaDeviceSynchronize(), "consensus: run");
    }
    ok = ok &&
         sim_status_check(
             results, cudaMemcpy(by_count, device_count, CLASSIFY_FRAME * sizeof(long long), cudaMemcpyDeviceToHost),
             "consensus: read");
    ok = ok &&
         sim_status_check(
             results, cudaMemcpy(by_median, device_median, CLASSIFY_FRAME * sizeof(long long), cudaMemcpyDeviceToHost),
             "consensus: read");
    cudaFree(device_median);
    cudaFree(device_count);
    cudaFree(device_values);
    return ok;
}

static void classify_scene(long long *scene, unsigned long long key)
{
    long long members[CLASSIFY_FRAMES];
    for (unsigned long long pixel = 0ull; pixel < CLASSIFY_FRAME; pixel += 1ull)
    {
        const unsigned long long half = CLASSIFY_FRAMES / 2ull;
        for (unsigned long long step = 0ull; step < half; step += 1ull)
        {
            // a draw below the swing is a small non-negative integer
            members[step] = 1ll + (long long)sim_draw_below(key, (pixel * CLASSIFY_FRAMES) + step, CLASSIFY_SWING);
            members[step + half] = -members[step];
        }
        for (unsigned long long at = CLASSIFY_FRAMES - 1ull; at > 0ull; at -= 1ull)
        {
            const unsigned long long other =
                sim_draw_below(key ^ 0x5348554Full, (pixel * CLASSIFY_FRAMES) + at, at + 1ull);
            const long long temporary = members[at];
            members[at] = members[other];
            members[other] = temporary;
        }
        for (unsigned long long step = 0ull; step < CLASSIFY_FRAMES; step += 1ull)
        {
            scene[pixel + (step * CLASSIFY_FRAME)] = members[step];
        }
    }
}

static void classify_pattern(long long *pattern, unsigned long long key)
{
    long long total = 0ll;
    for (unsigned long long pixel = 0ull; pixel < CLASSIFY_FRAME; pixel += 1ull)
    {
        // the draw is below 2 A + 1, a small non-negative integer
        pattern[pixel] =
            (long long)sim_draw_below(key ^ 0x5A5Aull, pixel, (2ull * CLASSIFY_AMPLITUDE) + 1ull) - CLASSIFY_AMPLITUDE;
        total += pattern[pixel];
    }
    // the frame is 64, far below 2^63
    const long long frame = (long long)CLASSIFY_FRAME;
    const long long quotient = total / frame;
    const long long shift = (((total % frame) != 0ll) && (total < 0ll)) ? (quotient - 1ll) : quotient;
    for (unsigned long long pixel = 0ull; pixel < CLASSIFY_FRAME; pixel += 1ull)
    {
        pattern[pixel] -= shift;
    }
}

static long long classify_noise(unsigned long long key, unsigned long long at, unsigned long long variance)
{
    // a head count of at most 4 v is far below 2^62
    return (long long)sim_binomial_half(key, at, 4ull * variance) - (2ll * (long long)variance);
}

// present where the live reading clears the top of 8 shuffles' band; each case is one keyed draw, and a null reading
// clears the top of 8 with chance 1/9 at most
static void classify_detect(SimResults *results, ClassifyWork *work, const char *name, int *present, int *ok)
{
    EnergyMeasurement live;
    EnergyMeasurement top;
    unsigned long long reached = 0ull;
    *ok = *ok && energy_recover(results, work->stack, CLASSIFY_LENGTH, CLASSIFY_FRAME, work->sums, &live);
    *ok = *ok && energy_band_top(results, work->stack, CLASSIFY_LENGTH, CLASSIFY_FRAME, CLASSIFY_DRAWS,
                                 CLASSIFY_KEY ^ 0x42414E44ull, work->shuffled, work->sums, &top, &reached);
    *present = *ok && (live.period == CLASSIFY_FRAME) && energy_above(&live, &top);
    ScripturaLine *const line = &results->line;
    scriptura_text(line, "  ");
    scriptura_text(line, name);
    scriptura_text(line, " mode fixed-pattern: coherent component present: ");
    scriptura_text(line, *present ? "yes" : "no");
    scriptura_text(line, " (live ");
    energy_print(line, &live);
    scriptura_text(line, " at period ");
    scriptura_decimal(line, live.period, 1u);
    scriptura_text(line, " / band top ");
    energy_print(line, &top);
    scriptura_text(line, ")\n");
}

static void classify_fixed_pattern(SimResults *results, ClassifyWork *work, const char *name, int expect_present)
{
    int present = 0;
    int ok = 1;
    classify_detect(results, work, name, &present, &ok);
    ScripturaLine *const line = &results->line;
    sim_check(results, ok && (present == expect_present),
              expect_present ? "the fixed pattern is classified present" : "incoherent noise is declined");
    if ((ok == 0) || (present == 0))
    {
        scriptura_text(line,
                       "                              declined: no fixed pattern above the null; nothing removed\n\n");
        return;
    }
    EnergyMeasurement phases;
    ok = energy_recover(results, work->stack, CLASSIFY_LENGTH, CLASSIFY_FRAME, work->sums, &phases);
    ok = ok && energy_welford(results, work->stack, CLASSIFY_LENGTH, CLASSIFY_FRAME, work->welford_numerator,
                              work->welford_denominator);
    const long long *const batch = &work->sums[energy_phase_base(CLASSIFY_FRAME)];
    unsigned long long flagged = 0ull;
    unsigned long long exact = 0ull;
    for (unsigned long long phase = 0ull; ok && (phase < CLASSIFY_FRAME); phase += 1ull)
    {
        // a phase's member count and the Welford denominator are both below 2^16
        const long long members = (long long)energy_members(CLASSIFY_LENGTH, CLASSIFY_FRAME, phase);
        const long long denominator = (long long)work->welford_denominator[phase];
        flagged += ((batch[phase] * denominator) != (work->welford_numerator[phase] * members)) ? 1ull : 0ull;
    }
    for (unsigned long long at = 0ull; ok && (at < CLASSIFY_LENGTH); at += 1ull)
    {
        // the member count is below 2^16
        const long long members = (long long)energy_members(CLASSIFY_LENGTH, CLASSIFY_FRAME, at % CLASSIFY_FRAME);
        exact +=
            (((members * work->stack[at]) - batch[at % CLASSIFY_FRAME]) == (members * work->truth[at])) ? 1ull : 0ull;
    }
    AnchorExactInteger share_numerator;
    AnchorExactInteger share_denominator;
    ok = ok && energy_reduction(work->stack, work->truth, CLASSIFY_LENGTH, CLASSIFY_FRAME, batch, &share_numerator,
                                &share_denominator);
    AnchorExactInteger percent;
    scriptura_text(line, "                              reject per-pixel mean: subject equals truth on ");
    scriptura_decimal(line, exact, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, CLASSIFY_LENGTH, 1u);
    scriptura_text(line, ", reduction ");
    if (ok && sim_exact_scaled(&share_numerator, 100ull, &percent))
    {
        sim_ratio_print(line, &percent, &share_denominator, 4u);
    }
    // both routes are exact means of the same values, so they agree on any input: the count checks the arithmetic
    scriptura_text(line, "%\n                              the batch and incremental routes disagree on ");
    scriptura_decimal(line, flagged, 1u);
    scriptura_text(line, " of 64 pixels\n\n");
    sim_check(results, ok && (exact == CLASSIFY_LENGTH) && (flagged == 0ull),
              "the subject is recovered bit-exact, and the batch and incremental routes agree");
}

static void classify_repeat(SimResults *results, ClassifyWork *work, const char *name, int expect_resolved_everywhere)
{
    const int ok = classify_consensus(results, work->stack, work->by_count, work->by_median);
    unsigned long long flagged = 0ull;
    unsigned long long resolved_exact = 0ull;
    for (unsigned long long phase = 0ull; ok && (phase < CLASSIFY_FRAME); phase += 1ull)
    {
        if (work->by_count[phase] != work->by_median[phase])
        {
            flagged += 1ull;
            continue;
        }
        resolved_exact += (work->by_count[phase] == work->subject[phase]) ? 1ull : 0ull;
    }
    ScripturaLine *const line = &results->line;
    scriptura_text(line, "  ");
    scriptura_text(line, name);
    scriptura_text(line, " mode repeat: subject by per-pixel consensus (greatest count, and the lower median of 48)\n");
    scriptura_text(line, "                              exact on ");
    scriptura_decimal(line, resolved_exact, 1u);
    scriptura_text(line, " of the ");
    scriptura_decimal(line, CLASSIFY_FRAME - flagged, 1u);
    scriptura_text(line, " pixels the two routes agree on; ");
    scriptura_decimal(line, flagged, 1u);
    scriptura_text(line, " of 64 flagged (the floor)\n\n");
    sim_check(results, ok, "the consensus ran");
    if (expect_resolved_everywhere)
    {
        sim_check(results, (flagged == 0ull) && (resolved_exact == CLASSIFY_FRAME),
                  "impulses on a repeat are recovered exactly on every pixel");
    }
}

int main(void)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    ClassifyWork *const work = (ClassifyWork *)calloc(1u, sizeof(ClassifyWork));
    sim_check(&results, work != NULL, "work buffers");
    if (work == NULL)
    {
        return sim_close(&results, "classify reject recover");
    }
    if (!sim_job_submit(&results, "classify_reject_recover", 0, NULL, sizeof(ClassifyWork)))
    {
        free(work);
        return sim_close(&results, "classify reject recover");
    }
    scriptura_text(&results.line, "  classify, reject, return the clean subject with the uncertainty stated exactly "
                                  "(ART-4-007, ported)\n  declared inputs: frame=8x8 frames=48 key=0x");
    scriptura_hex(&results.line, CLASSIFY_KEY, 1u);
    scriptura_text(&results.line, " draws=8\n\n");
    classify_scene(work->scene, CLASSIFY_KEY);
    classify_pattern(work->pattern, CLASSIFY_KEY);
    for (unsigned long long pixel = 0ull; pixel < CLASSIFY_FRAME; pixel += 1ull)
    {
        // the draw is at most 200, a small non-negative integer
        work->subject[pixel] =
            (long long)sim_draw_below(CLASSIFY_KEY ^ 0x53554Aull, pixel, CLASSIFY_SUBJECT_MAX + 1ull);
    }

    for (unsigned long long at = 0ull; at < CLASSIFY_LENGTH; at += 1ull)
    {
        work->stack[at] = work->scene[at] + work->pattern[at % CLASSIFY_FRAME];
        work->truth[at] = work->scene[at];
    }
    classify_fixed_pattern(&results, work, "fixed pattern, varies    ", 1);

    for (unsigned long long at = 0ull; at < CLASSIFY_LENGTH; at += 1ull)
    {
        // the amplitude is 40, so its square is 1,600
        work->stack[at] =
            work->scene[at] + classify_noise(CLASSIFY_KEY ^ 0x47415553ull, at,
                                             (unsigned long long)(CLASSIFY_AMPLITUDE * CLASSIFY_AMPLITUDE));
    }
    classify_fixed_pattern(&results, work, "incoherent, varies       ", 0);
    sim_flush(&results);

    for (unsigned long long at = 0ull; at < CLASSIFY_LENGTH; at += 1ull)
    {
        work->stack[at] = work->subject[at % CLASSIFY_FRAME];
    }
    for (unsigned long long impulse = 0ull; impulse < (CLASSIFY_LENGTH / 10ull); impulse += 1ull)
    {
        const unsigned long long at = sim_draw_below(CLASSIFY_KEY ^ 0x494D50ull, 2ull * impulse, CLASSIFY_LENGTH);
        // the draw is at most 255, a small non-negative integer
        work->stack[at] =
            (long long)sim_draw_below(CLASSIFY_KEY ^ 0x494D50ull, (2ull * impulse) + 1ull, CLASSIFY_IMPULSE_MAX + 1ull);
    }
    classify_repeat(&results, work, "impulses on a repeat     ", 1);

    for (unsigned long long at = 0ull; at < CLASSIFY_LENGTH; at += 1ull)
    {
        work->stack[at] = work->subject[at % CLASSIFY_FRAME] +
                          classify_noise(CLASSIFY_KEY ^ 0x52455045ull, at, CLASSIFY_REPEAT_VARIANCE);
    }
    classify_repeat(&results, work, "incoherent on a repeat   ", 0);

    scriptura_text(&results.line,
                   "  fixed-pattern removes a shared pattern from a varying subject to the bit and declines\n");
    scriptura_text(&results.line,
                   "  incoherent noise; repeat keeps a shared subject and recovers it exactly where a majority\n");
    scriptura_text(&results.line,
                   "  survives, flagging the rest. neither mode guesses which the shared component is.\n");
    free(work);
    return sim_close(&results, "classify reject recover");
}
