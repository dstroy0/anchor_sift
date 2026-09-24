// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "periodic_energy.h"

#define PATTERN_HEIGHT 8ull

#define PATTERN_WIDTH 8ull

#define PATTERN_FRAME (PATTERN_HEIGHT * PATTERN_WIDTH)

#define PATTERN_FRAMES 48ull

#define PATTERN_LENGTH (PATTERN_FRAME * PATTERN_FRAMES)

#define PATTERN_SWING 20ll

#define PATTERN_AMPLITUDE 40ll

#define PATTERN_DRAWS 8ull

#define PATTERN_KEY 0xF17Aull

#define PATTERN_DEPTHS 4u

typedef struct
{
    long long scene[PATTERN_LENGTH];
    long long pattern[PATTERN_FRAME];
    long long stack[PATTERN_LENGTH];
    long long arm[PATTERN_LENGTH];
    long long shuffled[PATTERN_LENGTH];
    long long target[PATTERN_LENGTH];
    long long sums[(PATTERN_FRAME * (PATTERN_FRAME + 1ull)) / 2ull];
    long long welford_numerator[PATTERN_FRAME];
    unsigned long long welford_denominator[PATTERN_FRAME];
} PatternWork;

static long long pattern_floor_divide(long long numerator, long long denominator)
{
    const long long quotient = numerator / denominator;
    return ((numerator % denominator) != 0ll) && ((numerator < 0ll) != (denominator < 0ll)) ? (quotient - 1ll) : quotient;
}

static void pattern_moving_scene(long long *scene, unsigned long long key)
{
    long long members[PATTERN_FRAMES];
    for (unsigned long long pixel = 0ull; pixel < PATTERN_FRAME; pixel += 1ull)
    {
        const unsigned long long half = PATTERN_FRAMES / 2ull;
        for (unsigned long long step = 0ull; step < half; step += 1ull)
        {
            // a draw below the swing is a small non-negative integer
            members[step] = 1ll + (long long)sim_draw_below(key, (pixel * PATTERN_FRAMES) + step, PATTERN_SWING);
            members[step + half] = -members[step];
        }
        for (unsigned long long at = PATTERN_FRAMES - 1ull; at > 0ull; at -= 1ull)
        {
            const unsigned long long other = sim_draw_below(key ^ 0x5348554Full, (pixel * PATTERN_FRAMES) + at, at + 1ull);
            const long long held = members[at];
            members[at] = members[other];
            members[other] = held;
        }
        for (unsigned long long step = 0ull; step < PATTERN_FRAMES; step += 1ull)
        {
            scene[pixel + (step * PATTERN_FRAME)] = members[step];
        }
    }
}

static void pattern_fixed(long long *pattern, unsigned long long key)
{
    long long total = 0ll;
    for (unsigned long long pixel = 0ull; pixel < PATTERN_FRAME; pixel += 1ull)
    {
        // the draw is below 2 A + 1, a small non-negative integer
        pattern[pixel] = (long long)sim_draw_below(key ^ 0x5A5Aull, pixel, (2ull * PATTERN_AMPLITUDE) + 1ull)
                       - PATTERN_AMPLITUDE;
        total += pattern[pixel];
    }
    // the frame is 64, far below 2^63
    const long long shift = pattern_floor_divide(total, (long long)PATTERN_FRAME);
    for (unsigned long long pixel = 0ull; pixel < PATTERN_FRAME; pixel += 1ull)
    {
        pattern[pixel] -= shift;
    }
}

static void pattern_impulses(long long *values, unsigned long long count, unsigned long long key)
{
    for (unsigned long long impulse = 0ull; impulse < count; impulse += 1ull)
    {
        const unsigned long long at = sim_draw_below(key, 2ull * impulse, PATTERN_LENGTH);
        // the draw is below 4 swing + 1, a small non-negative integer
        values[at] = (long long)sim_draw_below(key, (2ull * impulse) + 1ull, (4ull * PATTERN_SWING) + 1ull)
                   - (2ll * PATTERN_SWING);
    }
}

static void pattern_print_share(ScripturaLine *line, const AnchorExactInteger *numerator,
                                const AnchorExactInteger *denominator)
{
    AnchorExactInteger percent;
    if (sim_exact_scaled(numerator, 100ull, &percent) != 0)
    {
        sim_ratio_print(line, &percent, denominator, 4u);
        scriptura_character(line, '%');
    }
}

static int pattern_remove(SimTally *tally, PatternWork *work, const long long *noisy, const long long *target,
                          unsigned long long period, AnchorExactInteger *numerator, AnchorExactInteger *denominator)
{
    EnergyReading unused;
    if (energy_recover(tally, noisy, PATTERN_LENGTH, period, work->sums, &unused) == 0)
    {
        return 0;
    }
    return energy_reduction(noisy, target, PATTERN_LENGTH, period, &work->sums[energy_phase_base(period)], numerator,
                            denominator);
}

int main(void)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    PatternWork *const work = (PatternWork *)calloc(1u, sizeof(PatternWork));
    sim_check(&tally, work != NULL, "work buffers");
    if (work == NULL)
    {
        return sim_close(&tally, "fixed pattern");
    }
    if (!sim_job_submit(&tally, "fixed_pattern", 0, NULL, sizeof(PatternWork)))
    {
        free(work);
        return sim_close(&tally, "fixed pattern");
    }
    ScripturaLine *const line = &tally.line;
    pattern_moving_scene(work->scene, PATTERN_KEY);
    pattern_fixed(work->pattern, PATTERN_KEY);
    for (unsigned long long at = 0ull; at < PATTERN_LENGTH; at += 1ull)
    {
        work->stack[at] = work->scene[at] + work->pattern[at % PATTERN_FRAME];
    }
    scriptura_text(line, "  fixed-pattern video noise removed to the bit (ART-4-005, ported)\n  declared inputs: frame=8x8 frames=48 swing=20 pattern=40 draws=8 key=0x");
    scriptura_hex(line, PATTERN_KEY, 1u);
    scriptura_text(line, "\n\n");

    EnergyReading live;
    int good = energy_recover(&tally, work->stack, PATTERN_LENGTH, PATTERN_FRAME, work->sums, &live);
    energy_shuffle(work->stack, work->shuffled, PATTERN_LENGTH, sim_draw(PATTERN_KEY, 0x4445414Full));
    AnchorExactInteger dead_numerator;
    AnchorExactInteger dead_denominator;
    int dead = 0;
    if (good && live.found)
    {
        EnergyReading ignored;
        good = energy_recover(&tally, work->shuffled, PATTERN_LENGTH, live.period, work->sums, &ignored);
        dead = good && energy_ratio(work->shuffled, PATTERN_LENGTH, work->sums, live.period, &dead_numerator,
                                    &dead_denominator);
    }
    scriptura_text(line, "  identify: detector period ");
    scriptura_decimal(line, live.period, 1u);
    scriptura_text(line, " (frame size 64)\n  identify: dispersion ratio live ");
    energy_print(line, &live);
    scriptura_text(line, " against its own shuffle ");
    if (dead)
    {
        sim_ratio_print(line, &dead_numerator, &dead_denominator, 3u);
    }
    else
    {
        scriptura_text(line, "none");
    }
    scriptura_character(line, '\n');
    sim_check(&tally, good && live.found && (live.period == PATTERN_FRAME), "the detector reads the frame period");

    good = good && (energy_recover(&tally, work->stack, PATTERN_LENGTH, PATTERN_FRAME, work->sums, &live) != 0);
    good = good && energy_welford(&tally, work->stack, PATTERN_LENGTH, PATTERN_FRAME, work->welford_numerator,
                                  work->welford_denominator);
    const long long *const batch = &work->sums[energy_phase_base(PATTERN_FRAME)];
    unsigned long long agree = 0ull;
    unsigned long long broken_from_batch = 0ull;
    unsigned long long broken_from_welford = 0ull;
    unsigned long long exact = 0ull;
    for (unsigned long long phase = 0ull; good && (phase < PATTERN_FRAME); phase += 1ull)
    {
        // a phase's member count and the Welford denominator are both below 2^16
        const long long members = (long long)energy_members(PATTERN_LENGTH, PATTERN_FRAME, phase);
        const long long denominator = (long long)work->welford_denominator[phase];
        agree += ((batch[phase] * denominator) == (work->welford_numerator[phase] * members)) ? 1ull : 0ull;
        broken_from_batch += ((batch[phase] * members) != (batch[phase] * (members + 1ll))) ? 1ull : 0ull;
        broken_from_welford += ((batch[phase] * denominator) != (work->welford_numerator[phase] * (members + 1ll))) ? 1ull
                                                                                                                      : 0ull;
    }
    for (unsigned long long at = 0ull; good && (at < PATTERN_LENGTH); at += 1ull)
    {
        // the member count is below 2^16
        const long long members = (long long)energy_members(PATTERN_LENGTH, PATTERN_FRAME, at % PATTERN_FRAME);
        exact += (((members * work->stack[at]) - batch[at % PATTERN_FRAME]) == (members * work->scene[at])) ? 1ull : 0ull;
    }
    AnchorExactInteger share_numerator;
    AnchorExactInteger share_denominator;
    good = good && pattern_remove(&tally, work, work->stack, work->scene, PATTERN_FRAME, &share_numerator,
                                  &share_denominator);
    scriptura_text(line, "  reject: batch and incremental (Welford) routes agree on ");
    scriptura_decimal(line, agree, 1u);
    scriptura_text(line, " of 64 phases\n  reject: the broken route splits from both on ");
    scriptura_decimal(line, broken_from_batch, 1u);
    scriptura_text(line, " and ");
    scriptura_decimal(line, broken_from_welford, 1u);
    scriptura_text(line, " phases\n  reject: residual equals the moving scene on ");
    scriptura_decimal(line, exact, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, PATTERN_LENGTH, 1u);
    scriptura_text(line, " values\n  reject: noise reduction ");
    pattern_print_share(line, &share_numerator, &share_denominator);
    scriptura_text(line, "\n\n");
    sim_check(&tally, agree == PATTERN_FRAME, "batch and incremental routes agree bit-exact");
    sim_check(&tally, (broken_from_batch != 0ull) && (broken_from_welford != 0ull), "the broken route splits from both");
    sim_check(&tally, exact == PATTERN_LENGTH, "the residual equals the moving scene as integers");
    sim_check(&tally, good && (anchor_exact_compare(&share_numerator, &share_denominator) == 0),
              "the noise reduction is exactly 1");

    EnergyReading null_reading;
    good = good && energy_recover(&tally, work->shuffled, PATTERN_LENGTH, PATTERN_FRAME, work->sums, &null_reading);
    AnchorExactInteger wrong_numerator;
    AnchorExactInteger wrong_denominator;
    good = good && pattern_remove(&tally, work, work->stack, work->scene, PATTERN_FRAME - 1ull, &wrong_numerator,
                                  &wrong_denominator);
    scriptura_text(line, "  null: the shuffled stack reads period ");
    scriptura_decimal(line, null_reading.period, 1u);
    scriptura_text(line, " at ");
    energy_print(line, &null_reading);
    scriptura_text(line, "\n  null: rejecting at the wrong period 63 reduces the noise by ");
    pattern_print_share(line, &wrong_numerator, &wrong_denominator);
    scriptura_text(line, "\n\n");
    sim_flush(&tally);

    EnergyReading top;
    unsigned long long reached = 0ull;
    good = good && energy_band_top(&tally, work->stack, PATTERN_LENGTH, PATTERN_FRAME, PATTERN_DRAWS,
                                   PATTERN_KEY ^ 0x42414E44ull, work->shuffled, work->sums, &top, &reached);
    scriptura_text(line, "  negative controls: the 100% is licensed by the 0% the wrong noise scores\n  null band over 8 shuffles (");
    scriptura_decimal(line, reached, 1u);
    scriptura_text(line, " reached a period), top ");
    energy_print(line, &top);
    scriptura_text(line, "\n  case                      live ratio   above band  outcome\n");
    const char *const case_name[3] = {"matched pattern         ", "no pattern              ", "wrong kind (impulses)   "};
    for (unsigned int arm = 0u; good && (arm < 3u); arm += 1u)
    {
        for (unsigned long long at = 0ull; at < PATTERN_LENGTH; at += 1ull)
        {
            work->arm[at] = (arm == 0u) ? work->stack[at] : work->scene[at];
        }
        if (arm == 2u)
        {
            pattern_impulses(work->arm, PATTERN_LENGTH / 12ull, PATTERN_KEY ^ 0x494D50ull);
        }
        EnergyReading seen;
        good = energy_recover(&tally, work->arm, PATTERN_LENGTH, PATTERN_FRAME, work->sums, &seen);
        const int present = good && energy_above(&seen, &top);
        scriptura_text(line, "  ");
        scriptura_text(line, case_name[arm]);
        energy_print(line, &seen);
        scriptura_text(line, present ? "   yes         " : "   no          ");
        if (present)
        {
            AnchorExactInteger got_numerator;
            AnchorExactInteger got_denominator;
            good = pattern_remove(&tally, work, work->arm, work->scene, seen.period, &got_numerator, &got_denominator);
            scriptura_text(line, "remove, reduction ");
            pattern_print_share(line, &got_numerator, &got_denominator);
        }
        else if (arm == 1u)
        {
            scriptura_text(line, "decline, returned untouched");
        }
        else
        {
            scriptura_text(line, "decline, the noise left intact (reduction 0%)");
        }
        scriptura_character(line, '\n');
        sim_check(&tally, present == (arm == 0u), "only the matched pattern clears the band");
    }
    scriptura_character(line, '\n');
    sim_flush(&tally);

    const long long depth[PATTERN_DEPTHS] = {0ll, 5ll, 15ll, 30ll};
    scriptura_text(line, "  floor: a static scene feature cannot be told from a fixed pattern\n  depth   reduction\n");
    int falling = 1;
    AnchorExactInteger last_numerator;
    AnchorExactInteger last_denominator;
    for (unsigned int level = 0u; good && (level < PATTERN_DEPTHS); level += 1u)
    {
        for (unsigned long long at = 0ull; at < PATTERN_LENGTH; at += 1ull)
        {
            work->target[at] = work->scene[at] + (((at % PATTERN_FRAME) == 0ull) ? depth[level] : 0ll);
            work->arm[at] = work->target[at] + work->pattern[at % PATTERN_FRAME];
        }
        AnchorExactInteger floor_numerator;
        AnchorExactInteger floor_denominator;
        good = pattern_remove(&tally, work, work->arm, work->target, PATTERN_FRAME, &floor_numerator, &floor_denominator);
        scriptura_text(line, "  ");
        // every depth is a small non-negative integer
        scriptura_decimal_columns(line, (unsigned long long)depth[level], 5u);
        scriptura_text(line, "   ");
        pattern_print_share(line, &floor_numerator, &floor_denominator);
        scriptura_text(line, (level == 0u) ? "  full rejection\n" : "  a static feature, removed with the pattern\n");
        if (level > 0u)
        {
            int order = 0;
            falling = falling && sim_ratio_compare(&floor_numerator, &floor_denominator, &last_numerator, &last_denominator,
                                                   &order)
                   && (order < 0);
        }
        last_numerator = floor_numerator;
        last_denominator = floor_denominator;
    }
    sim_check(&tally, good && falling, "the reduction falls with every deeper static feature");
    free(work);
    return sim_close(&tally, "fixed pattern");
}
