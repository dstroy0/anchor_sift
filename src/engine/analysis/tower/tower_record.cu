// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tower_record.cu: the tower as record floors
#include "tower_internal.h"

// the ruleset tower_forward_kernel and tower_inverse_kernel run: the highs less floor((x_2j + x_(2j+2)) / 2), then the
// lows plus floor((d_(j-1) + d_j + 2) / 4)
static const TowerLiftingStep s_tower_five_three[2] = {{TOWER_BAND_HIGH, -1, 2u, {0, 1}, {1, 1}, 0u, 1u},
                                                       {TOWER_BAND_LOW, 1, 2u, {-1, 0}, {1, 1}, 2u, 2u}};

static unsigned int tower_record_append(TowerRecordBuilder *builder, EngineRecordOperation operation, unsigned int left,
                                        unsigned int right)
{
    if (builder->steps != NULL)
    {
        builder->steps[builder->count] = EngineRecordStep{operation, left, right, 0u};
    }
    builder->count += 1ull;
    // a program is written only once its count is bounded by 2^32 - 1, and a counted name past that errors unread
    return (unsigned int)(builder->count - 1ull);
}

static unsigned int tower_record_constant(TowerRecordBuilder *builder, unsigned long long value)
{
    for (const std::pair<unsigned long long, unsigned int> &constant : builder->constants)
    {
        if (constant.first == value)
        {
            return constant.second;
        }
    }
    // a constant step holds its value's low 32 bits in `left` and its high 32 in `right`
    const unsigned int step_index = tower_record_append(
        builder, ENGINE_RECORD_CONSTANT, (unsigned int)(value & 0xFFFFFFFFull), (unsigned int)(value >> 32u));
    builder->constants.push_back(std::pair<unsigned long long, unsigned int>(value, step_index));
    return step_index;
}

// floor(v / 2^shift), toward minus infinity as tower_floor_shift: v's residue, the and with 2^shift - 1, is never
// negative, and v less it divides exactly
static unsigned int tower_record_floor_shift(TowerRecordBuilder *builder, unsigned int value, unsigned int shift)
{
    if (shift == 0u)
    {
        return value;
    }
    const unsigned int mask = tower_record_constant(builder, (1ull << shift) - 1ull);
    const unsigned int residue = tower_record_append(builder, ENGINE_RECORD_AND, value, mask);
    const unsigned int difference = tower_record_append(builder, ENGINE_RECORD_DIFFERENCE, value, residue);
    return tower_record_append(builder, ENGINE_RECORD_EXACT_QUOTIENT, difference,
                               tower_record_constant(builder, 1ull << shift));
}

// one lifting step over a band: each value moves by sign * floor((rounding + sum_k weight_k * other[a + offset_k]) /
// 2^shift), an index past either end of the other band taken at that end, and `undo` turns the sign
static void tower_record_lifting_step(TowerRecordBuilder *builder, const TowerLiftingStep &rule, int undo,
                                      std::vector<unsigned int> &target, const std::vector<unsigned int> &other)
{
    // both bands of a lifted line hold at least one value, and far fewer than 2^31
    const long long last = (long long)other.size() - 1ll;
    for (size_t at = 0u; at < target.size(); at += 1u)
    {
        unsigned int sum = 0u;
        int summed = 0;
        if (rule.rounding != 0u)
        {
            sum = tower_record_constant(builder, rule.rounding);
            summed = 1;
        }
        for (unsigned int tap = 0u; tap < rule.taps; tap += 1u)
        {
            const long long wanted = (long long)at + (long long)rule.offset[tap];
            const long long taken = (wanted < 0ll) ? 0ll : ((wanted > last) ? last : wanted);
            unsigned int term = other[(size_t)taken];
            // a weight is never INT_MIN. Its magnitude is an int
            const unsigned int magnitude =
                (unsigned int)((rule.weight[tap] < 0) ? -rule.weight[tap] : rule.weight[tap]);
            if (magnitude != 1u)
            {
                term = tower_record_append(builder, ENGINE_RECORD_PRODUCT, term,
                                           tower_record_constant(builder, magnitude));
            }
            if (summed == 0)
            {
                sum = (rule.weight[tap] > 0) ? term
                                             : tower_record_append(builder, ENGINE_RECORD_DIFFERENCE,
                                                                   tower_record_constant(builder, 0ull), term);
                summed = 1;
            }
            else
            {
                sum = tower_record_append(
                    builder, (rule.weight[tap] > 0) ? ENGINE_RECORD_SUM : ENGINE_RECORD_DIFFERENCE, sum, term);
            }
        }
        const unsigned int moved = tower_record_floor_shift(builder, sum, rule.shift);
        const int adds = (rule.sign > 0) != (undo != 0);
        target[at] =
            tower_record_append(builder, adds ? ENGINE_RECORD_SUM : ENGINE_RECORD_DIFFERENCE, target[at], moved);
    }
}

// one level along one line of `length` values, or its undoing. Lifting splits the line into its evens, the lows,
// and its odds, the highs, runs the ruleset's steps in order and lays out the lows first and the highs after them, as
// tower_forward_kernel lays them out; lowering reads the two bands back from there, runs the steps last first with each
// sign turned, and interleaves them again, as tower_inverse_kernel does.
static void tower_record_line(TowerRecordBuilder *builder, const TowerLiftingStep *rules, unsigned int rule_count,
                              std::vector<unsigned int> &registers, unsigned long long line, unsigned long long stride,
                              unsigned long long length, int inverse)
{
    const unsigned long long lows = (length + 1ull) / 2ull;
    const unsigned long long highs = length / 2ull;
    // a band's k-th value sits at 2k or 2k + 1 along the interleaved line, and at k or lows + k along the lifted one
    std::vector<unsigned int> low((size_t)lows);
    std::vector<unsigned int> high((size_t)highs);
    for (unsigned long long k = 0ull; k < lows; k += 1ull)
    {
        low[(size_t)k] = registers[(size_t)(line + (((inverse != 0) ? k : (2ull * k)) * stride))];
    }
    for (unsigned long long k = 0ull; k < highs; k += 1ull)
    {
        high[(size_t)k] = registers[(size_t)(line + (((inverse != 0) ? (lows + k) : ((2ull * k) + 1ull)) * stride))];
    }
    for (unsigned int walked = 0u; walked < rule_count; walked += 1u)
    {
        const TowerLiftingStep &rule = rules[(inverse != 0) ? (rule_count - 1u - walked) : walked];
        if (rule.target == TOWER_BAND_HIGH)
        {
            tower_record_lifting_step(builder, rule, inverse, high, low);
        }
        else
        {
            tower_record_lifting_step(builder, rule, inverse, low, high);
        }
    }
    for (unsigned long long k = 0ull; k < lows; k += 1ull)
    {
        registers[(size_t)(line + (((inverse != 0) ? (2ull * k) : k) * stride))] = low[(size_t)k];
    }
    for (unsigned long long k = 0ull; k < highs; k += 1ull)
    {
        registers[(size_t)(line + (((inverse != 0) ? ((2ull * k) + 1ull) : (lows + k)) * stride))] = high[(size_t)k];
    }
}

// the first position of every line along `axis` in a level's active region, in t, z, y, x order
static std::vector<unsigned long long> tower_record_lines(const TowerStep &step, unsigned int axis)
{
    unsigned long long across[4];
    unsigned long long lines = 1ull;
    for (unsigned int each = 0u; each < 4u; each += 1u)
    {
        across[each] = (each == axis) ? 1ull : step.extent[each];
        lines *= across[each];
    }
    std::vector<unsigned long long> first((size_t)lines);
    for (unsigned long long index = 0ull; index < lines; index += 1ull)
    {
        unsigned long long rest = index;
        unsigned long long offset = 0ull;
        for (unsigned int each = 4u; each > 0u; each -= 1u)
        {
            offset += (rest % across[each - 1u]) * step.stride[each - 1u];
            rest /= across[each - 1u];
        }
        first[(size_t)index] = offset;
    }
    return first;
}

// T, or T^-1 run from the last level and axis back, over a block's registers in place: the levels and axes
// tower_lift and tower_lower walk, each axis whose active extent is 2 or more
static void tower_record_build(TowerRecordBuilder *builder, const TowerLiftingStep *rules, unsigned int rule_count,
                               const std::vector<TowerStep> &floors, std::vector<unsigned int> &registers, int inverse)
{
    const size_t levels = floors.size();
    for (size_t walked = 0u; walked < levels; walked += 1u)
    {
        const TowerStep &step = floors[(inverse != 0) ? (levels - 1u - walked) : walked];
        for (unsigned int turn = 0u; turn < 4u; turn += 1u)
        {
            const unsigned int axis = (inverse != 0) ? (3u - turn) : turn;
            if (step.extent[axis] < 2ull)
            {
                continue;
            }
            for (const unsigned long long line : tower_record_lines(step, axis))
            {
                tower_record_line(builder, rules, rule_count, registers, line, step.stride[axis], step.extent[axis],
                                  inverse);
            }
        }
    }
}

static long tower_record_run(const TowerRecordRequest *request, int inverse)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return TOWER_ERROR;
    }
    EngineError *const error = request->error;
    if (!TOWER_CHECK((request->in_registers != NULL) && (request->out_registers != NULL) && (request->count != NULL),
                     request, error, ENGINE_ERROR_REQUEST))
    {
        return TOWER_ERROR;
    }
    const unsigned long long lanes = tower_lanes(request->extent);
    if (!TOWER_CHECK((lanes != 0ull) && (lanes <= 0xFFFFFFFFull), request->extent, error, ENGINE_ERROR_REQUEST))
    {
        return TOWER_ERROR;
    }
    // no ruleset named is the kernels' 5/3
    const int named_rules = (request->rules != NULL) || (request->rule_count != 0u);
    const TowerLiftingStep *const rules = (named_rules != 0) ? request->rules : s_tower_five_three;
    const unsigned int rule_count = (named_rules != 0) ? request->rule_count : 2u;
    if (!TOWER_CHECK((rules != NULL) && (rule_count != 0u), request, error, ENGINE_ERROR_REQUEST))
    {
        return TOWER_ERROR;
    }
    for (unsigned int at = 0u; at < rule_count; at += 1u)
    {
        const TowerLiftingStep *const rule = &rules[at];
        int ok = ((rule->target == TOWER_BAND_LOW) || (rule->target == TOWER_BAND_HIGH)) &&
                 ((rule->sign == 1) || (rule->sign == -1)) && (rule->taps >= 1u) &&
                 (rule->taps <= TOWER_RULE_TAPS_MAX) && (rule->shift <= TOWER_RULE_SHIFT_MAX);
        for (unsigned int tap = 0u; (ok != 0) && (tap < rule->taps); tap += 1u)
        {
            // a weight's magnitude is an int. INT_MIN errors with 0
            ok = (rule->weight[tap] != 0) && (rule->weight[tap] != INT_MIN);
        }
        if (!TOWER_CHECK(ok, rule, error, ENGINE_ERROR_REQUEST))
        {
            return TOWER_ERROR;
        }
    }
    const unsigned int start = *request->count;
    std::vector<unsigned int> registers((size_t)lanes);
    for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
    {
        // a value the block reads is an earlier step's register
        if (!TOWER_CHECK(request->in_registers[lane] < start, &request->in_registers[lane], error,
                         ENGINE_ERROR_REQUEST))
        {
            return TOWER_ERROR;
        }
        registers[(size_t)lane] = request->in_registers[lane];
    }
    const std::vector<TowerStep> floors = tower_floors(request->extent);
    // counted first. A program its step names or the caller's capacity cannot hold errors before a step is written
    TowerRecordBuilder counted = {NULL, start, {}};
    std::vector<unsigned int> named = registers;
    tower_record_build(&counted, rules, rule_count, floors, named, inverse);
    if (!TOWER_CHECK((counted.count <= 0xFFFFFFFFull) &&
                         ((request->steps == NULL) || (counted.count <= (unsigned long long)request->step_capacity)),
                     request, error, ENGINE_ERROR_REQUEST))
    {
        return TOWER_ERROR;
    }
    if (request->steps != NULL)
    {
        TowerRecordBuilder written = {request->steps, start, {}};
        tower_record_build(&written, rules, rule_count, floors, registers, inverse);
    }
    memcpy(request->out_registers, named.data(), (size_t)lanes * sizeof(unsigned int));
    // the count was bounded by 2^32 - 1 above. It narrows to the program's next step exactly
    *request->count = (unsigned int)counted.count;
    return 0L;
}

extern "C" long tower_record_lift(const TowerRecordRequest *request)
{
    return tower_record_run(request, 0);
}

extern "C" long tower_record_lower(const TowerRecordRequest *request)
{
    return tower_record_run(request, 1);
}
