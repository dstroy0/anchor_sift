// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_tower_test_oracle.cu: samples, the oracle, loading, running and building
#include "record_tower_test_internal.h"

static unsigned long long s_tower_test_state = 0x243F6A8885A308D3ull;

unsigned int tower_test_random(void)
{
    s_tower_test_state ^= s_tower_test_state << 13u;
    s_tower_test_state ^= s_tower_test_state >> 7u;
    s_tower_test_state ^= s_tower_test_state << 17u;
    // the state's high half is its best mixed, and it is exactly 32 bits
    return (unsigned int)(s_tower_test_state >> 32u);
}

// a volume's sample at a position: all 0, all at the lane's top, the two alternating, a ramp, or drawn
unsigned short tower_test_sample(unsigned int volume, unsigned int position)
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
long long tower_test_signed(unsigned int word, unsigned int bits)
{
    const unsigned long long raw = (bits < 32u) ? ((unsigned long long)word & ((1ull << bits) - 1ull)) : word;
    const unsigned long long top = 1ull << (bits - 1u);
    // the raw value is below 2^32. It and 2 top widen to long long exactly
    return ((raw & top) != 0ull) ? ((long long)raw - (long long)(2ull * top)) : (long long)raw;
}

// one output's value from a lane's record: its out_bits of two's complement, the top written bit the sign; every
// output here is narrower than 64 bits
long long tower_test_take(const unsigned int *record, const DeviceRecordStep *step)
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
    // the word is the value's two's complement. The conversion reads it back signed
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
void tower_test_oracle(const unsigned long long extent[4], const TowerLiftingStep *rules, unsigned int rule_count,
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

// encode, lay out with register reuse, and load: one field a 32-bit word, one member
int tower_test_load(const std::vector<EngineRecordStep> &steps, const std::vector<unsigned int> &outputs,
                    const std::vector<unsigned int> &field_bits, TowerTestLoaded *loaded)
{
    memset(loaded, 0, sizeof(*loaded));
    // a block's fields and a program's steps and outputs are far below 2^32
    const unsigned int fields = (unsigned int)field_bits.size();
    const KeymathRecordRequest encode_request = {steps.data(),
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
    if (keymath_record_encode(&encode_request) == KEYMATH_ERROR)
    {
        return 0;
    }
    std::vector<unsigned int> field_offset(fields);
    for (unsigned int field = 0u; field < fields; field += 1u)
    {
        field_offset[field] = 32u * field;
    }
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {fields, 0u, 0u};
    const KeyScheduleRecordRequest layout_request = {&loaded->key,    field_offset.data(), fields, in_limbs, 1,
                                                     &loaded->layout, &loaded->error};
    if (key_schedule_record_layout(&layout_request) == KEY_SCHEDULE_ERROR)
    {
        keymath_record_release(&loaded->key);
        return 0;
    }
    if (cycle_record_load(&loaded->layout, &loaded->record, &loaded->error) == CYCLE_ERROR)
    {
        key_schedule_record_release(&loaded->layout);
        keymath_record_release(&loaded->key);
        return 0;
    }
    return 1;
}

void tower_test_free(TowerTestLoaded *loaded)
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
int tower_test_run(TowerTestLoaded *loaded, const std::vector<unsigned int> &atoms, unsigned int volumes,
                   std::vector<unsigned int> &out)
{
    const unsigned int in_limbs = loaded->layout.in_limbs[0];
    const unsigned int out_limbs = loaded->layout.out_limbs;
    std::vector<unsigned int> host_out((size_t)volumes * out_limbs + 1u, 0u);
    out.assign((size_t)volumes * out_limbs + 1u, 0u);
    const CycleRecordHostRequest host = {
        &loaded->layout, {atoms.data(), NULL, NULL}, {volumes, 0ull, 0ull}, NULL, volumes, host_out.data(),
        &loaded->error};
    const int host_ran = cycle_record_run_host(&host) != CYCLE_ERROR;
    unsigned int *device_atoms = NULL;
    unsigned int *device_record = NULL;
    int ok = (cudaMalloc((void **)&device_atoms, (size_t)volumes * in_limbs * sizeof(unsigned int)) == cudaSuccess) &&
             (cudaMalloc((void **)&device_record, (size_t)volumes * out_limbs * sizeof(unsigned int)) == cudaSuccess) &&
             (cudaMemcpy(device_atoms, atoms.data(), (size_t)volumes * in_limbs * sizeof(unsigned int),
                         cudaMemcpyHostToDevice) == cudaSuccess);
    if (ok != 0)
    {
        const CycleRecordRunRequest run = {
            loaded->record, {device_atoms, NULL, NULL}, {volumes, 0ull, 0ull}, NULL, volumes, device_record,
            &loaded->error};
        ok = (cycle_record_run(&run) != CYCLE_ERROR) &&
             (cudaMemcpy(out.data(), device_record, (size_t)volumes * out_limbs * sizeof(unsigned int),
                         cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    cudaFree(device_atoms);
    cudaFree(device_record);
    return (host_ran != 0) && (ok != 0) &&
           (memcmp(host_out.data(), out.data(), (size_t)volumes * out_limbs * sizeof(unsigned int)) == 0);
}

// one volume through the kernels: tower_lift's crystal read back, then tower_lower's rebuilt samples; 1 where both ran
// and no lane of the source was missed
int tower_test_kernels(const unsigned long long extent[4], const unsigned short *source, unsigned short *device_volume,
                       int *crystal, unsigned short *rebuilt, unsigned int lanes)
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
    int ok = (cudaMemcpy(device_volume, source, (size_t)lanes * sizeof(unsigned short), cudaMemcpyHostToDevice) ==
              cudaSuccess) &&
             (tower_lift(&lift) == 0L) &&
             (cudaMemcpy(crystal, coefficients, (size_t)lanes * sizeof(int), cudaMemcpyDeviceToHost) == cudaSuccess);
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
    ok = ok && (tower_lower(&lower) == 0L) && (mismatches == 0ull);
    return ok && (error.kind == ENGINE_ERROR_NONE);
}

// the operation read through T^-1: the block's sum, and its energy along x, the sum of the squared differences of x
// neighbors, on the host from a block's samples
void tower_test_operation(const unsigned long long extent[4], const unsigned short *samples, unsigned int lanes,
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
// into a capacity of exactly that size; 1 where both calls ran and wrote as many steps as the first counted
int tower_test_build(const unsigned long long extent[4], const TowerTestRuleset *ruleset, int inverse,
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
    int ok = ((inverse != 0) ? tower_record_lower(&request) : tower_record_lift(&request)) == 0L;
    const unsigned int sized = count;
    steps.resize(sized);
    count = start;
    request.steps = steps.data();
    request.step_capacity = sized;
    ok =
        ok && (((inverse != 0) ? tower_record_lower(&request) : tower_record_lift(&request)) == 0L) && (count == sized);
    return ok && (error.kind == ENGINE_ERROR_NONE);
}

// a program's opening: one field for each position of the block, unsigned or signed
std::vector<EngineRecordStep> tower_test_fields(unsigned int lanes, EngineRecordOperation field)
{
    std::vector<EngineRecordStep> steps;
    for (unsigned int position = 0u; position < lanes; position += 1u)
    {
        steps.push_back(EngineRecordStep{field, position, 0u, 0u});
    }
    return steps;
}
