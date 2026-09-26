// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The two towers as record floors the engine emits (engine_table.md item 8), each floor focused from a ruleset, the
// wave transform's math, rather than written out by hand. A lifting step moves one band of a line by a rounded sum
// over the other, target += sign floor((rounding + sum_k weight_k other[a + offset_k]) / 2^shift), and
// tower_record_lift and tower_record_lower pass a ruleset through a block's extent as record steps, one block of the
// lattice to a lane. The kernels' 5/3 is read against tower_lift and tower_lower lane for lane: on blocks of one to
// four axes, odd extents and even, every volume's T equals tower_lift's crystal at every coefficient, and T^-1 run on
// it equals tower_lower's rebuilt samples and the source, with no ruleset named and with the 5/3 named as its two
// steps. Two rulesets the kernels do not run, the S transform and a four-tap predict, are read against a host
// oracle, which itself equals the kernels on the 5/3. For every ruleset, T read through T^-1 as one program returns
// crystals drawn anywhere in the fields' widths. An operation F read through T^-1 (the block's sum, and its energy
// along x, the sum of the squared differences of x neighbours) equals F on tower_lower's samples. Every program runs
// on the device and the host, word for word. The emitter sizes a program before it is held, and it refuses a register
// that is not earlier, a room too small, an empty extent and a malformed step, leaving the program as it was.
// Every sweep gives back the stack its frame grew, so the limit after the blocks is the limit before them.
// The test is one job on the device's tessera daemon, submitted before its first device work.
#include "cycle.h"
#include "keymath.h"
#include "key_schedule.h"
#include "sim.h"
#include "tower.h"

#include <algorithm>
#include <vector>

#define TOWER_TEST_VOLUMES 256u

#define TOWER_TEST_BLOCKS 7u

#define TOWER_TEST_RULESETS 4u

#define TOWER_TEST_SAMPLE_BITS 16u

// the device holds one volume for the kernels and one program's records at a time, far below this
#define TOWER_TEST_DECLARED (16ull << 20u)

// t, z, y and x: a line of 64, a cube of 4, blocks with odd extents on every axis, a block on all four axes, and one
// sample, which no level lifts
static const unsigned long long s_tower_test_extent[TOWER_TEST_BLOCKS][4] = {
    {1ull, 1ull, 1ull, 64ull}, {1ull, 4ull, 4ull, 4ull}, {2ull, 3ull, 4ull, 4ull}, {1ull, 3ull, 5ull, 7ull},
    {3ull, 1ull, 2ull, 9ull},  {2ull, 2ull, 2ull, 2ull}, {1ull, 1ull, 1ull, 1ull}};

// the 5/3 as tower.h states it: the highs less floor((x_2j + x_(2j+2)) / 2), the lows plus floor((d_(j-1) + d_j + 2) /
// 4)
static const TowerLiftingStep s_tower_test_five_three[2] = {{TOWER_BAND_HIGH, -1, 2u, {0, 1}, {1, 1}, 0u, 1u},
                                                            {TOWER_BAND_LOW, 1, 2u, {-1, 0}, {1, 1}, 2u, 2u}};

// the S transform: the highs less their even neighbour, the lows plus half the high beside them, floored
static const TowerLiftingStep s_tower_test_s_transform[2] = {{TOWER_BAND_HIGH, -1, 1u, {0}, {1}, 0u, 0u},
                                                             {TOWER_BAND_LOW, 1, 1u, {0}, {1}, 0u, 1u}};

// a four-tap predict, the highs less floor((9 (x_2j + x_(2j+2)) - (x_(2j-2) + x_(2j+4)) + 8) / 16), then the 5/3's
// update
static const TowerLiftingStep s_tower_test_four_tap[2] = {{TOWER_BAND_HIGH, -1, 4u, {-1, 0, 1, 2}, {-1, 9, 9, -1}, 8u, 4u},
                                                          {TOWER_BAND_LOW, 1, 2u, {-1, 0}, {1, 1}, 2u, 2u}};

typedef struct
{
    const char *name;
    const TowerLiftingStep *rules;
    unsigned int rule_count;
    int kernels;
} TowerTestRuleset;

static const TowerTestRuleset s_tower_test_ruleset[TOWER_TEST_RULESETS] = {
    {"the kernels' 5/3, no ruleset named", NULL, 0u, 1},
    {"the 5/3 named as its two steps", s_tower_test_five_three, 2u, 1},
    {"the S transform", s_tower_test_s_transform, 2u, 0},
    {"a four-tap predict and the 5/3's update", s_tower_test_four_tap, 2u, 0}};

static unsigned long long s_tower_test_state = 0x243F6A8885A308D3ull;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} TowerTestLoaded;

static unsigned int tower_test_random(void)
{
    s_tower_test_state ^= s_tower_test_state << 13u;
    s_tower_test_state ^= s_tower_test_state >> 7u;
    s_tower_test_state ^= s_tower_test_state << 17u;
    // the state's high half is its best mixed, and it is exactly 32 bits
    return (unsigned int)(s_tower_test_state >> 32u);
}

// a volume's sample at a position: all 0, all at the lane's top, the two alternating, a ramp, or drawn
static unsigned short tower_test_sample(unsigned int volume, unsigned int position)
{
    const unsigned int kind = volume % 8u;
    unsigned int value = tower_test_random() & 0xFFFFu;
    if (kind == 0u)
    {
        value = 0u;
    }
    else if (kind == 1u)
    {
        value = 0xFFFFu;
    }
    else if (kind == 2u)
    {
        value = ((position & 1u) != 0u) ? 0xFFFFu : 0u;
    }
    else if (kind == 3u)
    {
        value = (position * 977u) & 0xFFFFu;
    }
    // the value is masked to 16 bits, which an unsigned short holds exactly
    return (unsigned short)value;
}

// `bits` of a field's word read back signed
static long long tower_test_signed(unsigned int word, unsigned int bits)
{
    const unsigned long long raw = (bits < 32u) ? ((unsigned long long)word & ((1ull << bits) - 1ull)) : word;
    const unsigned long long top = 1ull << (bits - 1u);
    // the raw value is below 2^32, so it and 2 top widen to long long exactly
    return ((raw & top) != 0ull) ? ((long long)raw - (long long)(2ull * top)) : (long long)raw;
}

// one output's value from a lane's record: its out_bits of two's complement, the top written bit the sign; every
// output here is narrower than 64 bits
static long long tower_test_take(const unsigned int *record, const DeviceRecordStep *step)
{
    unsigned long long word = 0ull;
    for (unsigned int bit = 0u; bit < step->out_bits; bit += 1u)
    {
        const unsigned int from = step->out_offset + bit;
        word |= (unsigned long long)((record[from / 32u] >> (from % 32u)) & 1u) << bit;
    }
    if ((step->out_bits < 64u) && (((word >> (step->out_bits - 1u)) & 1ull) != 0ull))
    {
        word |= ~0ull << step->out_bits;
    }
    // the word is the value's two's complement, so the conversion reads it back signed
    return (long long)word;
}

// the oracle's floor of value / 2^shift: C's quotient toward zero, one less where a negative value leaves a remainder
static long long tower_test_floor(long long value, unsigned int shift)
{
    const long long divisor = 1ll << shift;
    const long long quotient = value / divisor;
    return ((value % divisor) != 0ll) && (value < 0ll) ? (quotient - 1ll) : quotient;
}

// the oracle: a ruleset run on the host over a block of long long values, level by level and axis by axis as the
// tower walks them, each line split into its evens and odds, or back
static void tower_test_oracle(const unsigned long long extent[4], const TowerLiftingStep *rules, unsigned int rule_count,
                              std::vector<long long> &values, int inverse)
{
    const unsigned long long stride[4] = {extent[1] * extent[2] * extent[3], extent[2] * extent[3], extent[3], 1ull};
    std::vector<std::vector<unsigned long long>> levels;
    std::vector<unsigned long long> active(extent, extent + 4);
    while ((active[0] > 1ull) || (active[1] > 1ull) || (active[2] > 1ull) || (active[3] > 1ull))
    {
        levels.push_back(active);
        for (unsigned int axis = 0u; axis < 4u; axis += 1u)
        {
            active[axis] = (active[axis] + 1ull) / 2ull;
        }
    }
    for (size_t walked = 0u; walked < levels.size(); walked += 1u)
    {
        const std::vector<unsigned long long> &level = levels[(inverse != 0) ? (levels.size() - 1u - walked) : walked];
        for (unsigned int turn = 0u; turn < 4u; turn += 1u)
        {
            const unsigned int axis = (inverse != 0) ? (3u - turn) : turn;
            const unsigned long long length = level[axis];
            if (length < 2ull)
            {
                continue;
            }
            const unsigned long long lows = (length + 1ull) / 2ull;
            for (unsigned long long first = 0ull; first < (level[0] * level[1] * level[2] * level[3]); first += 1ull)
            {
                unsigned long long rest = first;
                unsigned long long line = 0ull;
                int on_start = 1;
                for (unsigned int each = 4u; each > 0u; each -= 1u)
                {
                    const unsigned long long digit = rest % level[each - 1u];
                    rest /= level[each - 1u];
                    line += digit * stride[each - 1u];
                    on_start = on_start && (((each - 1u) != axis) || (digit == 0ull));
                }
                if (on_start == 0)
                {
                    continue;
                }
                std::vector<long long> band[2];
                for (unsigned long long along = 0ull; along < length; along += 1ull)
                {
                    const long long value = values[(size_t)(line + (along * stride[axis]))];
                    const int odd = (inverse != 0) ? (along >= lows) : ((along % 2ull) == 1ull);
                    band[odd].push_back(value);
                }
                for (unsigned int step = 0u; step < rule_count; step += 1u)
                {
                    const TowerLiftingStep &rule = rules[(inverse != 0) ? (rule_count - 1u - step) : step];
                    std::vector<long long> &target = band[(rule.target == TOWER_BAND_HIGH) ? 1 : 0];
                    const std::vector<long long> &other = band[(rule.target == TOWER_BAND_HIGH) ? 0 : 1];
                    const long long last = (long long)other.size() - 1ll;
                    for (size_t at = 0u; at < target.size(); at += 1u)
                    {
                        long long sum = (long long)rule.rounding;
                        for (unsigned int tap = 0u; tap < rule.taps; tap += 1u)
                        {
                            long long taken = (long long)at + rule.offset[tap];
                            taken = (taken < 0ll) ? 0ll : ((taken > last) ? last : taken);
                            sum += (long long)rule.weight[tap] * other[(size_t)taken];
                        }
                        const long long moved = tower_test_floor(sum, rule.shift);
                        target[at] += ((rule.sign > 0) != (inverse != 0)) ? moved : -moved;
                    }
                }
                for (unsigned long long along = 0ull; along < length; along += 1ull)
                {
                    long long value = 0ll;
                    if (inverse != 0)
                    {
                        value = band[along % 2ull][(size_t)(along / 2ull)];
                    }
                    else
                    {
                        value = (along < lows) ? band[0][(size_t)along] : band[1][(size_t)(along - lows)];
                    }
                    values[(size_t)(line + (along * stride[axis]))] = value;
                }
            }
        }
    }
}

// imprint, lay with register reuse, and load: one field a 32-bit word, one member
static int tower_test_load(const std::vector<EngineRecordStep> &steps, const std::vector<unsigned int> &outputs,
                           const std::vector<unsigned int> &field_bits, TowerTestLoaded *loaded)
{
    memset(loaded, 0, sizeof(*loaded));
    // a block's fields and a program's steps and outputs are far below 2^32
    const unsigned int fields = (unsigned int)field_bits.size();
    const KeymathRecordRequest imprint = {steps.data(),
                                          (unsigned int)steps.size(),
                                          field_bits.data(),
                                          fields,
                                          1u,
                                          outputs.data(),
                                          (unsigned int)outputs.size(),
                                          NULL,
                                          0u,
                                          &loaded->key,
                                          &loaded->error};
    if (keymath_record_imprint(&imprint) == KEYMATH_REFUSED)
    {
        return 0;
    }
    std::vector<unsigned int> field_offset(fields);
    for (unsigned int field = 0u; field < fields; field += 1u)
    {
        field_offset[field] = 32u * field;
    }
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {fields, 0u, 0u};
    const KeyScheduleRecordRequest lay = {&loaded->key, field_offset.data(), fields, in_limbs, 1, &loaded->layout,
                                          &loaded->error};
    if (key_schedule_record_lay(&lay) == KEY_SCHEDULE_REFUSED)
    {
        keymath_record_release(&loaded->key);
        return 0;
    }
    if (cycle_record_load(&loaded->layout, &loaded->record, &loaded->error) == CYCLE_REFUSED)
    {
        key_schedule_record_release(&loaded->layout);
        keymath_record_release(&loaded->key);
        return 0;
    }
    return 1;
}

static void tower_test_free(TowerTestLoaded *loaded)
{
    if (loaded->record != NULL)
    {
        cycle_record_release(loaded->record);
    }
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
    memset(loaded, 0, sizeof(*loaded));
}

// run a loaded program over the volumes' records on the host and on the device; 1 where both ran and agree word for
// word, with the device's records left in `out`
static int tower_test_run(TowerTestLoaded *loaded, const std::vector<unsigned int> &atoms, unsigned int volumes,
                          std::vector<unsigned int> &out)
{
    const unsigned int in_limbs = loaded->layout.in_limbs[0];
    const unsigned int out_limbs = loaded->layout.out_limbs;
    std::vector<unsigned int> host_out((size_t)volumes * out_limbs + 1u, 0u);
    out.assign((size_t)volumes * out_limbs + 1u, 0u);
    const CycleRecordHostRequest host = {&loaded->layout, {atoms.data(), NULL, NULL}, {volumes, 0ull, 0ull}, NULL,
                                         volumes, host_out.data(), &loaded->error};
    const int host_ran = cycle_record_run_host(&host) != CYCLE_REFUSED;
    unsigned int *device_atoms = NULL;
    unsigned int *device_record = NULL;
    int good = (cudaMalloc((void **)&device_atoms, (size_t)volumes * in_limbs * sizeof(unsigned int)) == cudaSuccess)
            && (cudaMalloc((void **)&device_record, (size_t)volumes * out_limbs * sizeof(unsigned int)) == cudaSuccess)
            && (cudaMemcpy(device_atoms, atoms.data(), (size_t)volumes * in_limbs * sizeof(unsigned int),
                           cudaMemcpyHostToDevice)
                == cudaSuccess);
    if (good != 0)
    {
        const CycleRecordRunRequest run = {loaded->record, {device_atoms, NULL, NULL}, {volumes, 0ull, 0ull}, NULL,
                                           volumes, device_record, &loaded->error};
        good = (cycle_record_run(&run) != CYCLE_REFUSED)
            && (cudaMemcpy(out.data(), device_record, (size_t)volumes * out_limbs * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost)
                == cudaSuccess);
    }
    cudaFree(device_atoms);
    cudaFree(device_record);
    return (host_ran != 0) && (good != 0)
        && (memcmp(host_out.data(), out.data(), (size_t)volumes * out_limbs * sizeof(unsigned int)) == 0);
}

// one volume through the kernels: tower_lift's crystal read back, then tower_lower's rebuilt samples; 1 where both ran
// and no lane of the source was missed
static int tower_test_kernels(const unsigned long long extent[4], const unsigned short *source,
                              unsigned short *device_volume, int *crystal, unsigned short *rebuilt, unsigned int lanes)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    const int *coefficients = NULL;
    unsigned int *scratch = NULL;
    unsigned int floors = 0u;
    TowerLiftRequest lift;
    memset(&lift, 0, sizeof(lift));
    lift.device_lanes = device_volume;
    memcpy(lift.extent, extent, sizeof(lift.extent));
    lift.coefficients = &coefficients;
    lift.scratch = &scratch;
    lift.floors = &floors;
    lift.error = &error;
    int good = (cudaMemcpy(device_volume, source, (size_t)lanes * sizeof(unsigned short), cudaMemcpyHostToDevice)
                == cudaSuccess)
            && (tower_lift(&lift) == 0L)
            && (cudaMemcpy(crystal, coefficients, (size_t)lanes * sizeof(int), cudaMemcpyDeviceToHost) == cudaSuccess);
    unsigned long long mismatches = 1ull;
    const unsigned short *device_rebuilt = NULL;
    TowerLowerRequest lower;
    memset(&lower, 0, sizeof(lower));
    lower.device_lanes = device_volume;
    memcpy(lower.extent, extent, sizeof(lower.extent));
    lower.mismatches = &mismatches;
    lower.device_rebuilt = &device_rebuilt;
    lower.rebuilt = rebuilt;
    lower.error = &error;
    good = good && (tower_lower(&lower) == 0L) && (mismatches == 0ull);
    return good && (error.kind == ENGINE_ERROR_NONE);
}

// the operation read through T^-1: the block's sum, and its energy along x, the sum of the squared differences of x
// neighbours, on the host from a block's samples
static void tower_test_operation(const unsigned long long extent[4], const unsigned short *samples, unsigned int lanes,
                                 long long *sum, long long *energy)
{
    *sum = 0ll;
    *energy = 0ll;
    for (unsigned int position = 0u; position < lanes; position += 1u)
    {
        *sum += (long long)samples[position];
        if ((position % extent[3]) < (extent[3] - 1ull))
        {
            const long long difference = (long long)samples[position + 1u] - (long long)samples[position];
            *energy += difference * difference;
        }
    }
}

// emit T or T^-1 under a ruleset into `steps` from the registers `in`: sized first with no steps held, then written
// into a room of exactly that size; 1 where both calls ran and wrote as many steps as the first counted
static int tower_test_emit(const unsigned long long extent[4], const TowerTestRuleset *ruleset, int inverse,
                           const std::vector<unsigned int> &in, std::vector<unsigned int> &out,
                           std::vector<EngineRecordStep> &steps)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    // a program's step count here is far below 2^32
    const unsigned int start = (unsigned int)steps.size();
    unsigned int count = start;
    out.assign(in.size(), 0u);
    TowerRecordRequest request;
    memset(&request, 0, sizeof(request));
    memcpy(request.extent, extent, sizeof(request.extent));
    request.rules = ruleset->rules;
    request.rule_count = ruleset->rule_count;
    request.in_registers = in.data();
    request.out_registers = out.data();
    request.count = &count;
    request.error = &error;
    int good = ((inverse != 0) ? tower_record_lower(&request) : tower_record_lift(&request)) == 0L;
    const unsigned int sized = count;
    steps.resize(sized);
    count = start;
    request.steps = steps.data();
    request.step_room = sized;
    good = good && (((inverse != 0) ? tower_record_lower(&request) : tower_record_lift(&request)) == 0L)
        && (count == sized);
    return good && (error.kind == ENGINE_ERROR_NONE);
}

// a program's opening: one field for each position of the block, unsigned or signed
static std::vector<EngineRecordStep> tower_test_fields(unsigned int lanes, EngineRecordOperation field)
{
    std::vector<EngineRecordStep> steps;
    for (unsigned int position = 0u; position < lanes; position += 1u)
    {
        steps.push_back(EngineRecordStep{field, position, 0u, 0u});
    }
    return steps;
}

// how many volumes' records hold, at the registers named, the values expected of them
static unsigned int tower_test_matches(const TowerTestLoaded *loaded, const std::vector<unsigned int> &out,
                                       const std::vector<unsigned int> &registers, const std::vector<long long> &expected,
                                       unsigned int volumes)
{
    // a block's register count is far below 2^32
    const unsigned int lanes = (unsigned int)registers.size();
    unsigned int matched = 0u;
    for (unsigned int volume = 0u; volume < volumes; volume += 1u)
    {
        const unsigned int *const record = &out[(size_t)volume * loaded->layout.out_limbs];
        int equal = 1;
        for (unsigned int position = 0u; position < lanes; position += 1u)
        {
            equal = equal
                 && (tower_test_take(record, &loaded->layout.step_table[registers[position]])
                     == expected[((size_t)volume * lanes) + position]);
        }
        matched += (equal != 0) ? 1u : 0u;
    }
    return matched;
}

// one ruleset on one block: T against the kernels or the oracle, T^-1 on that crystal against the source, and T read
// through T^-1 on drawn crystals
static void tower_test_ruleset(SimTally *tally, const unsigned long long extent[4], const TowerTestRuleset *ruleset,
                               const std::vector<unsigned short> &source, const std::vector<int> &kernel_crystal)
{
    ScripturaLine *const line = &tally->line;
    // a block's sample count is far below 2^32
    const unsigned int lanes = (unsigned int)(source.size() / TOWER_TEST_VOLUMES);
    const unsigned int volumes = TOWER_TEST_VOLUMES;
    const TowerLiftingStep *const rules = (ruleset->rules != NULL) ? ruleset->rules : s_tower_test_five_three;
    const unsigned int rule_count = (ruleset->rules != NULL) ? ruleset->rule_count : 2u;
    std::vector<long long> sample_values(source.begin(), source.end());
    std::vector<long long> crystal = sample_values;
    if (ruleset->kernels != 0)
    {
        crystal.assign(kernel_crystal.begin(), kernel_crystal.end());
    }
    else
    {
        for (unsigned int volume = 0u; volume < volumes; volume += 1u)
        {
            std::vector<long long> block(crystal.begin() + ((size_t)volume * lanes),
                                         crystal.begin() + ((size_t)(volume + 1u) * lanes));
            tower_test_oracle(extent, rules, rule_count, block, 0);
            std::copy(block.begin(), block.end(), crystal.begin() + ((size_t)volume * lanes));
        }
    }
    std::vector<unsigned int> samples(lanes);
    for (unsigned int position = 0u; position < lanes; position += 1u)
    {
        samples[position] = position;
    }

    // T: a field for each sample, 16 bits unsigned, then the lift
    std::vector<EngineRecordStep> lift_steps = tower_test_fields(lanes, ENGINE_RECORD_FIELD);
    std::vector<unsigned int> coefficients;
    TowerTestLoaded lift = {};
    const std::vector<unsigned int> sample_bits(lanes, TOWER_TEST_SAMPLE_BITS);
    int good = tower_test_emit(extent, ruleset, 0, samples, coefficients, lift_steps)
            && tower_test_load(lift_steps, coefficients, sample_bits, &lift);
    std::vector<unsigned int> atoms(source.begin(), source.end());
    std::vector<unsigned int> out;
    good = good && tower_test_run(&lift, atoms, volumes, out);
    sim_check(tally, good, "T is emitted as sized, imprints, lays and loads, and the device's records equal the host's");
    const unsigned int lift_equal = (good != 0) ? tower_test_matches(&lift, out, coefficients, crystal, volumes) : 0u;
    sim_check(tally, lift_equal == volumes,
              (ruleset->kernels != 0) ? "T's record floors equal tower_lift's crystal at every coefficient"
                                      : "T's record floors equal the oracle's crystal at every coefficient");
    // each coefficient's field for T^-1: its register's width and a sign bit
    std::vector<unsigned int> crystal_bits(lanes, 32u);
    unsigned int widest = 0u;
    for (unsigned int position = 0u; (good != 0) && (position < lanes); position += 1u)
    {
        crystal_bits[position] = lift.key.term[coefficients[position]].bits + 1u;
        widest = ((crystal_bits[position] - 1u) > widest) ? (crystal_bits[position] - 1u) : widest;
    }
    const unsigned int lift_limbs = lift.layout.file_limbs;
    // a program's step count here is far below 2^32
    const unsigned int lift_count = (unsigned int)(lift_steps.size() - lanes);
    tower_test_free(&lift);

    // T^-1: a signed field for each coefficient, then the lower, on T's crystal
    std::vector<EngineRecordStep> lower_steps = tower_test_fields(lanes, ENGINE_RECORD_FIELD_SIGNED);
    std::vector<unsigned int> rebuilt_registers;
    TowerTestLoaded lower = {};
    good = tower_test_emit(extent, ruleset, 1, samples, rebuilt_registers, lower_steps)
        && tower_test_load(lower_steps, rebuilt_registers, crystal_bits, &lower);
    for (size_t at = 0u; at < atoms.size(); at += 1u)
    {
        // a coefficient's two's complement word, whose low field bits the signed field reads
        atoms[at] = (unsigned int)crystal[at];
    }
    good = good && tower_test_run(&lower, atoms, volumes, out);
    sim_check(tally, good,
              "T^-1 is emitted as sized, imprints, lays and loads, and the device's records equal the host's");
    const unsigned int lower_equal = (good != 0) ? tower_test_matches(&lower, out, rebuilt_registers, sample_values,
                                                                      volumes)
                                                 : 0u;
    sim_check(tally, lower_equal == volumes, "T^-1's record floors return the source at every sample");
    const unsigned int lower_limbs = lower.layout.file_limbs;
    // a program's step count here is far below 2^32
    const unsigned int lower_count = (unsigned int)(lower_steps.size() - lanes);
    tower_test_free(&lower);

    // T read through T^-1 as one stack, on crystals drawn anywhere in the fields' widths
    std::vector<EngineRecordStep> round_steps = tower_test_fields(lanes, ENGINE_RECORD_FIELD_SIGNED);
    std::vector<unsigned int> middle;
    std::vector<unsigned int> returned;
    TowerTestLoaded round = {};
    good = tower_test_emit(extent, ruleset, 1, samples, middle, round_steps)
        && tower_test_emit(extent, ruleset, 0, middle, returned, round_steps)
        && tower_test_load(round_steps, returned, crystal_bits, &round);
    std::vector<long long> drawn(atoms.size());
    for (size_t at = 0u; at < atoms.size(); at += 1u)
    {
        atoms[at] = tower_test_random();
        drawn[at] = tower_test_signed(atoms[at], crystal_bits[at % lanes]);
    }
    good = good && tower_test_run(&round, atoms, volumes, out);
    sim_check(tally, good, "T . T^-1 imprints, lays and loads as one program, and the device's records equal the host's");
    const unsigned int round_equal = (good != 0) ? tower_test_matches(&round, out, returned, drawn, volumes) : 0u;
    sim_check(tally, round_equal == volumes, "T . T^-1 returns every drawn crystal exactly, as one stack");
    const unsigned int round_limbs = round.layout.file_limbs;
    tower_test_free(&round);

    scriptura_text(line, "    ");
    scriptura_text(line, ruleset->name);
    scriptura_text(line, ": T ");
    scriptura_decimal(line, lift_count, 1u);
    scriptura_text(line, " steps in a file of ");
    scriptura_decimal(line, lift_limbs, 1u);
    scriptura_text(line, " limbs, the widest coefficient ");
    scriptura_decimal(line, widest, 1u);
    scriptura_text(line, " bits; T^-1 ");
    scriptura_decimal(line, lower_count, 1u);
    scriptura_text(line, " steps, ");
    scriptura_decimal(line, lower_limbs, 1u);
    scriptura_text(line, " limbs; T . T^-1 ");
    scriptura_decimal(line, round_limbs, 1u);
    scriptura_text(line, " limbs\n      of ");
    scriptura_decimal(line, volumes, 1u);
    scriptura_text(line, (ruleset->kernels != 0) ? " volumes, T equals tower_lift on " : " volumes, T equals the oracle on ");
    scriptura_decimal(line, lift_equal, 1u);
    scriptura_text(line, ", T^-1 returns the source on ");
    scriptura_decimal(line, lower_equal, 1u);
    scriptura_text(line, ", T . T^-1 returns ");
    scriptura_decimal(line, round_equal, 1u);
    scriptura_text(line, " drawn crystals\n");
    sim_flush(tally);
}

// F read through T^-1 as one stack, on the kernels' crystal: the block's sum, and its energy along x where x has
// neighbours, against F on tower_lower's samples
static void tower_test_operation_stack(SimTally *tally, const unsigned long long extent[4],
                                       const std::vector<int> &kernel_crystal, const std::vector<unsigned short> &rebuilt,
                                       const std::vector<unsigned int> &crystal_bits)
{
    // a block's sample count is far below 2^32
    const unsigned int lanes = (unsigned int)(rebuilt.size() / TOWER_TEST_VOLUMES);
    const unsigned int volumes = TOWER_TEST_VOLUMES;
    std::vector<unsigned int> samples(lanes);
    for (unsigned int position = 0u; position < lanes; position += 1u)
    {
        samples[position] = position;
    }
    std::vector<EngineRecordStep> steps = tower_test_fields(lanes, ENGINE_RECORD_FIELD_SIGNED);
    std::vector<unsigned int> read_back;
    int good = tower_test_emit(extent, &s_tower_test_ruleset[0], 1, samples, read_back, steps);
    unsigned int sum = read_back[0];
    unsigned int energy = 0u;
    int energy_held = 0;
    for (unsigned int position = 0u; position < lanes; position += 1u)
    {
        if (position > 0u)
        {
            steps.push_back(EngineRecordStep{ENGINE_RECORD_SUM, sum, read_back[position], 0u});
            // a program's step count here is far below 2^32
            sum = (unsigned int)(steps.size() - 1u);
        }
        if ((position % extent[3]) < (extent[3] - 1ull))
        {
            steps.push_back(EngineRecordStep{ENGINE_RECORD_DIFFERENCE, read_back[position + 1u], read_back[position], 0u});
            const unsigned int difference = (unsigned int)(steps.size() - 1u);
            steps.push_back(EngineRecordStep{ENGINE_RECORD_PRODUCT, difference, difference, 0u});
            const unsigned int square = (unsigned int)(steps.size() - 1u);
            if (energy_held != 0)
            {
                steps.push_back(EngineRecordStep{ENGINE_RECORD_SUM, energy, square, 0u});
                energy = (unsigned int)(steps.size() - 1u);
            }
            else
            {
                energy = square;
                energy_held = 1;
            }
        }
    }
    std::vector<unsigned int> outputs(1u, sum);
    if (energy_held != 0)
    {
        outputs.push_back(energy);
    }
    TowerTestLoaded operation = {};
    good = good && tower_test_load(steps, outputs, crystal_bits, &operation);
    std::vector<unsigned int> atoms(kernel_crystal.size());
    for (size_t at = 0u; at < atoms.size(); at += 1u)
    {
        // a coefficient's two's complement word, whose low field bits the signed field reads
        atoms[at] = (unsigned int)kernel_crystal[at];
    }
    std::vector<unsigned int> out;
    good = good && tower_test_run(&operation, atoms, volumes, out);
    sim_check(tally, good, "F . T^-1 imprints, lays and loads as one program, and the device's records equal the host's");
    unsigned int matched = 0u;
    for (unsigned int volume = 0u; (good != 0) && (volume < volumes); volume += 1u)
    {
        const unsigned int *const record = &out[(size_t)volume * operation.layout.out_limbs];
        long long host_sum = 0ll;
        long long host_energy = 0ll;
        tower_test_operation(extent, &rebuilt[(size_t)volume * lanes], lanes, &host_sum, &host_energy);
        int equal = tower_test_take(record, &operation.layout.step_table[sum]) == host_sum;
        if (energy_held != 0)
        {
            equal = equal && (tower_test_take(record, &operation.layout.step_table[energy]) == host_energy);
        }
        matched += (equal != 0) ? 1u : 0u;
    }
    sim_check(tally, matched == volumes,
              "F . T^-1 equals F taken on tower_lower's samples: the block's sum and its energy along x");
    scriptura_text(&tally->line, "    F . T^-1, the block's sum and its energy along x: ");
    scriptura_decimal(&tally->line, steps.size(), 1u);
    scriptura_text(&tally->line, " steps in one program, a file of ");
    scriptura_decimal(&tally->line, operation.layout.file_limbs, 1u);
    scriptura_text(&tally->line, " limbs; equal to F on tower_lower's samples on ");
    scriptura_decimal(&tally->line, matched, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, volumes, 1u);
    scriptura_text(&tally->line, " volumes\n");
    tower_test_free(&operation);
}

static void tower_test_block(SimTally *tally, const unsigned long long extent[4], unsigned short *device_volume)
{
    ScripturaLine *const line = &tally->line;
    // every block here holds at most 105 samples
    const unsigned int lanes = (unsigned int)(extent[0] * extent[1] * extent[2] * extent[3]);
    const unsigned int volumes = TOWER_TEST_VOLUMES;
    scriptura_text(line, "  t x z x y x x = ");
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        scriptura_decimal(line, extent[axis], 1u);
        scriptura_text(line, (axis < 3u) ? " x " : "\n");
    }

    // the kernels' crystal and rebuilt samples of every volume
    std::vector<unsigned short> source((size_t)volumes * lanes);
    std::vector<int> crystal((size_t)volumes * lanes);
    std::vector<unsigned short> rebuilt((size_t)volumes * lanes);
    for (unsigned int volume = 0u; volume < volumes; volume += 1u)
    {
        for (unsigned int position = 0u; position < lanes; position += 1u)
        {
            source[((size_t)volume * lanes) + position] = tower_test_sample(volume, position);
        }
    }
    int kernels = 1;
    for (unsigned int volume = 0u; (kernels != 0) && (volume < volumes); volume += 1u)
    {
        const size_t at = (size_t)volume * lanes;
        kernels = tower_test_kernels(extent, &source[at], device_volume, &crystal[at], &rebuilt[at], lanes);
    }
    sim_check(tally, kernels, "tower_lift and tower_lower run every volume, and tower_lower rebuilds the source");

    // the oracle is read against the kernels once, on the 5/3, before it grades the rulesets they do not run
    unsigned int oracle_equal = 0u;
    for (unsigned int volume = 0u; (kernels != 0) && (volume < volumes); volume += 1u)
    {
        std::vector<long long> block(source.begin() + ((size_t)volume * lanes),
                                     source.begin() + ((size_t)(volume + 1u) * lanes));
        tower_test_oracle(extent, s_tower_test_five_three, 2u, block, 0);
        int equal = 1;
        for (unsigned int position = 0u; position < lanes; position += 1u)
        {
            equal = equal && (block[position] == (long long)crystal[((size_t)volume * lanes) + position]);
        }
        tower_test_oracle(extent, s_tower_test_five_three, 2u, block, 1);
        for (unsigned int position = 0u; position < lanes; position += 1u)
        {
            equal = equal && (block[position] == (long long)source[((size_t)volume * lanes) + position]);
        }
        oracle_equal += (equal != 0) ? 1u : 0u;
    }
    sim_check(tally, oracle_equal == volumes, "the oracle's 5/3 equals tower_lift's crystal and returns the source");
    scriptura_text(line, "    the oracle's 5/3 equals tower_lift and returns the source on ");
    scriptura_decimal(line, oracle_equal, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, volumes, 1u);
    scriptura_text(line, " volumes\n");

    for (unsigned int ruleset = 0u; (kernels != 0) && (ruleset < TOWER_TEST_RULESETS); ruleset += 1u)
    {
        tower_test_ruleset(tally, extent, &s_tower_test_ruleset[ruleset], source, crystal);
    }

    // F . T^-1 reads the kernels' crystal through fields as wide as the 5/3's T makes each coefficient
    std::vector<unsigned int> samples(lanes);
    for (unsigned int position = 0u; position < lanes; position += 1u)
    {
        samples[position] = position;
    }
    std::vector<EngineRecordStep> lift_steps = tower_test_fields(lanes, ENGINE_RECORD_FIELD);
    std::vector<unsigned int> coefficients;
    TowerTestLoaded lift = {};
    const std::vector<unsigned int> sample_bits(lanes, TOWER_TEST_SAMPLE_BITS);
    const int widths = (kernels != 0) && tower_test_emit(extent, &s_tower_test_ruleset[0], 0, samples, coefficients,
                                                         lift_steps)
                    && tower_test_load(lift_steps, coefficients, sample_bits, &lift);
    std::vector<unsigned int> crystal_bits(lanes, 32u);
    for (unsigned int position = 0u; (widths != 0) && (position < lanes); position += 1u)
    {
        crystal_bits[position] = lift.key.term[coefficients[position]].bits + 1u;
    }
    if (widths != 0)
    {
        tower_test_free(&lift);
        tower_test_operation_stack(tally, extent, crystal, rebuilt, crystal_bits);
    }
    sim_check(tally, widths, "the 5/3's widths are read for F . T^-1");
    sim_flush(tally);
}

// the emitter's refusals: each leaves the count, and any step already in the room, as it was
static void tower_test_refusals(SimTally *tally)
{
    const unsigned long long pair[4] = {1ull, 1ull, 1ull, 2ull};
    const unsigned long long empty[4] = {1ull, 0ull, 1ull, 2ull};
    const unsigned int fields[2] = {0u, 1u};
    unsigned int out[2] = {0u, 0u};
    EngineRecordStep room[3];
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        room[at] = EngineRecordStep{ENGINE_RECORD_CONSTANT, 7u, 0u, 0u};
    }
    EngineError error;
    memset(&error, 0, sizeof(error));
    unsigned int count = 1u;
    TowerRecordRequest request;
    memset(&request, 0, sizeof(request));
    memcpy(request.extent, pair, sizeof(request.extent));
    request.in_registers = fields;
    request.out_registers = out;
    request.count = &count;
    request.error = &error;
    // register 1 is not earlier than the count of 1
    const int later = (tower_record_lift(&request) == TOWER_REFUSED) && (count == 1u)
                   && (error.kind == ENGINE_ERROR_REQUEST);
    sim_check(tally, later, "a register that is not an earlier step is refused, and the count is left as it was");
    memset(&error, 0, sizeof(error));
    count = 2u;
    request.steps = room;
    request.step_room = 3u;
    int kept = 1;
    const int small = (tower_record_lower(&request) == TOWER_REFUSED) && (count == 2u)
                   && (error.kind == ENGINE_ERROR_REQUEST);
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        kept = kept && (room[at].operation == ENGINE_RECORD_CONSTANT) && (room[at].left == 7u);
    }
    sim_check(tally, small && kept, "a room too small is refused before a step is written");
    memset(&error, 0, sizeof(error));
    memcpy(request.extent, empty, sizeof(request.extent));
    request.steps = NULL;
    const int nothing = (tower_record_lift(&request) == TOWER_REFUSED) && (count == 2u)
                     && (error.kind == ENGINE_ERROR_REQUEST);
    sim_check(tally, nothing, "an extent with no samples is refused");
    // a step with a zero weight, then one with no taps, then one whose sign is neither 1 nor -1
    TowerLiftingStep malformed[3] = {{TOWER_BAND_HIGH, -1, 1u, {0}, {0}, 0u, 0u},
                                     {TOWER_BAND_HIGH, -1, 0u, {0}, {1}, 0u, 0u},
                                     {TOWER_BAND_LOW, 2, 1u, {0}, {1}, 0u, 0u}};
    memcpy(request.extent, pair, sizeof(request.extent));
    int refused = 1;
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        memset(&error, 0, sizeof(error));
        request.rules = &malformed[at];
        request.rule_count = 1u;
        refused = refused && (tower_record_lift(&request) == TOWER_REFUSED) && (count == 2u)
               && (error.kind == ENGINE_ERROR_REQUEST);
    }
    sim_check(tally, refused, "a step with a zero weight, no taps, or a sign other than 1 or -1 is refused");
}

int main(int count, char **arguments)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    scriptura_text(&tally.line, "  the two towers as record floors focused from a ruleset, read against tower_lift and"
                                " tower_lower's kernels and a host oracle\n");
    int good = sim_job_submit(&tally, "record_tower_test", count, arguments, TOWER_TEST_DECLARED);
    unsigned long long most = 1ull;
    for (unsigned int block = 0u; block < TOWER_TEST_BLOCKS; block += 1u)
    {
        const unsigned long long *const extent = s_tower_test_extent[block];
        const unsigned long long lanes = extent[0] * extent[1] * extent[2] * extent[3];
        most = (lanes > most) ? lanes : most;
    }
    unsigned short *device_volume = NULL;
    good = good && sim_took(&tally, cudaMalloc((void **)&device_volume, (size_t)most * sizeof(unsigned short)),
                            "the kernels' volume");
    // a sweep whose frame passes the stack limit grows it, and the local memory that reserves is held until the limit
    // is set back; cycle sets it back once each sweep ends, so the limit after every block is the one before them
    size_t stack_before = 0u;
    good = good && sim_took(&tally, cudaDeviceGetLimit(&stack_before, cudaLimitStackSize), "the stack limit, before");
    for (unsigned int block = 0u; (good != 0) && (block < TOWER_TEST_BLOCKS); block += 1u)
    {
        tower_test_block(&tally, s_tower_test_extent[block], device_volume);
    }
    size_t stack_after = 0u;
    good = good && sim_took(&tally, cudaDeviceGetLimit(&stack_after, cudaLimitStackSize), "the stack limit, after");
    sim_check(&tally, (good != 0) && (stack_after == stack_before),
              "every sweep gives its stack back: the limit after the blocks is the limit before them");
    scriptura_text(&tally.line, "  the stack limit: ");
    scriptura_decimal(&tally.line, stack_before, 1u);
    scriptura_text(&tally.line, " bytes a thread before the blocks, ");
    scriptura_decimal(&tally.line, stack_after, 1u);
    scriptura_text(&tally.line, " after them\n");
    sim_flush(&tally);
    tower_test_refusals(&tally);
    cudaFree(device_volume);
    return sim_close(&tally, "record tower test");
}
