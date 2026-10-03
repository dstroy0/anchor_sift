// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// exponential_integral_engine.cu: the three series on the engine's record machine, each term a lane
#include "exponential_integral_internal.h"

// A term is a lane: field 0 is its k, and the lane takes its own chain from 2^W (exponential_integral_internal.h).
// The program is the chain unrolled to the deepest k the host's tail test reached. Step j stands for every lane, and a
// lane whose k is below j multiplies by 1 there: its flag [k >= j] is (c + |c|) / 2 of c = compare(k, j - 1), and the
// step's multiplier and divisor are 1 + flag (multiplier - 1) and 1 + flag (divisor - 1). Every step is floored in
// the low program and ceiled in the high one, as (n + d - 1) / d, and wrapped to the bits the host's span bounds the
// chain by, which leaves every value as it is. A tail program takes the high chain at the deepest k and bounds the
// terms past it. The lanes run on the device and on the host's interpreter, their records held to each other word for
// word, and each program's outputs are summed on the device by cycle_record_sum and on the host by
// cycle_record_sum_host. The sums are the host series' own: the engine's span must equal the host's end for end.

// one chain: its first step, its steps' multiplier and divisor base + rise j, its last division end + end_rise k, the
// deepest k it is unrolled to, and the bits every value in it stays below
typedef struct
{
    ExponentialWide first_top;
    ExponentialWide first_bottom;
    ExponentialWide multiplier;
    ExponentialWide base;
    ExponentialWide rise;
    unsigned long long end;
    unsigned long long end_rise;
    unsigned long long last;
    unsigned int scale;
    unsigned int bound_bits;
    // a tail: the high chain at `last` times tail_top / tail_bottom, ceiled; no tail where tail_bottom is 0
    ExponentialWide tail_top;
    ExponentialWide tail_bottom;
} ExponentialChain;

// one record program on the engine
typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    unsigned int output;
} ExponentialProgram;

// set where a program did not build or run, and where a device record or sum is not the host's
static int s_engine_failed = 0;
static int s_engine_differs = 0;
static ExponentialEngineCount s_engine_count;

void exponential_engine_reset(void)
{
    s_engine_failed = 0;
    s_engine_differs = 0;
    memset(&s_engine_count, 0, sizeof(s_engine_count));
}

ExponentialEngineCount exponential_engine_counted(void)
{
    return s_engine_count;
}

static unsigned int exponential_step(std::vector<EngineRecordStep> *steps, EngineRecordOperation operation,
                                     unsigned int left, unsigned int right)
{
    EngineRecordStep step;
    step.operation = operation;
    step.left = left;
    step.right = right;
    step.member = 0u;
    steps->push_back(step);
    // a program's steps are counted in an unsigned int, as keymath counts them
    return (unsigned int)(steps->size() - 1u);
}

// a register holding a non-negative integer: one constant below 2^64, and past it Horner's rule over the 32-bit limbs
// from the top, a product by 2^32 and a sum a limb
static unsigned int exponential_constant(std::vector<EngineRecordStep> *steps, const ExponentialWide &value)
{
    unsigned int used = ANCHOR_EXACT_LIMBS;
    while ((used > 1u) && (value.limb[used - 1u] == 0u))
    {
        used -= 1u;
    }
    if (used <= 2u)
    {
        return exponential_step(steps, ENGINE_RECORD_CONSTANT, value.limb[0], (used > 1u) ? value.limb[1] : 0u);
    }
    unsigned int last_step =
        exponential_step(steps, ENGINE_RECORD_CONSTANT, value.limb[used - 2u], value.limb[used - 1u]);
    for (unsigned int limb = used - 2u; limb > 0u; limb -= 1u)
    {
        const unsigned int shift = exponential_step(steps, ENGINE_RECORD_CONSTANT, 0u, 1u);
        last_step = exponential_step(steps, ENGINE_RECORD_PRODUCT, last_step, shift);
        if (value.limb[limb - 1u] != 0u)
        {
            const unsigned int low = exponential_step(steps, ENGINE_RECORD_CONSTANT, value.limb[limb - 1u], 0u);
            last_step = exponential_step(steps, ENGINE_RECORD_SUM, last_step, low);
        }
    }
    return last_step;
}

// numerator / divisor floored, or ceiled where `high`, for a non-negative numerator and a positive divisor
static unsigned int exponential_rounded(std::vector<EngineRecordStep> *steps, unsigned int numerator,
                                        unsigned int divisor, int high, unsigned int one)
{
    unsigned int lifted = numerator;
    if (high != 0)
    {
        lifted = exponential_step(steps, ENGINE_RECORD_SUM, numerator,
                                  exponential_step(steps, ENGINE_RECORD_DIFFERENCE, divisor, one));
    }
    return exponential_step(steps, ENGINE_RECORD_QUOTIENT, lifted, divisor);
}

static unsigned int exponential_bit_length(unsigned long long value)
{
    unsigned int bits = 0u;
    while (value != 0ull)
    {
        bits += 1u;
        value >>= 1u;
    }
    return bits;
}

// the chain's program, its low or high end, with its tail where the chain holds one: keymath encodes it, its last step
// the output, and the scheduler lays out its registers
static int exponential_program_build(const ExponentialChain *chain, int high, int tail, ExponentialProgram *program)
{
    memset(program, 0, sizeof(*program));
    std::vector<EngineRecordStep> steps;
    const unsigned int index = exponential_step(&steps, ENGINE_RECORD_FIELD, 0u, 0u);
    const unsigned int one = exponential_step(&steps, ENGINE_RECORD_CONSTANT, 1u, 0u);
    const unsigned int two = exponential_step(&steps, ENGINE_RECORD_CONSTANT, 2u, 0u);
    const ExponentialWide unit = exponential_unsigned(1ull);
    unsigned int value = exponential_constant(&steps, exponential_power_two(chain->scale));
    if (exponential_compare(chain->first_top, chain->first_bottom) != 0)
    {
        const unsigned int raised =
            exponential_step(&steps, ENGINE_RECORD_PRODUCT, value, exponential_constant(&steps, chain->first_top));
        value = exponential_rounded(&steps, raised, exponential_constant(&steps, chain->first_bottom), high, one);
        value = exponential_step(&steps, ENGINE_RECORD_WRAP, value, chain->bound_bits);
    }
    const unsigned int multiplier_less =
        exponential_constant(&steps, exponential_difference(chain->multiplier, unit));
    for (unsigned long long place = 1ull; place <= chain->last; place += 1ull)
    {
        const unsigned int below = exponential_constant(&steps, exponential_unsigned(place - 1ull));
        const unsigned int order = exponential_step(&steps, ENGINE_RECORD_COMPARE, index, below);
        const unsigned int size = exponential_step(&steps, ENGINE_RECORD_ABSOLUTE, order, 0u);
        const unsigned int twice = exponential_step(&steps, ENGINE_RECORD_SUM, order, size);
        const unsigned int on = exponential_step(&steps, ENGINE_RECORD_QUOTIENT, twice, two);
        const unsigned int factor = exponential_step(
            &steps, ENGINE_RECORD_SUM, one, exponential_step(&steps, ENGINE_RECORD_PRODUCT, on, multiplier_less));
        const ExponentialWide divisor =
            exponential_sum(chain->base, exponential_product(chain->rise, exponential_unsigned(place)));
        const unsigned int divisor_less = exponential_constant(&steps, exponential_difference(divisor, unit));
        const unsigned int divided = exponential_step(
            &steps, ENGINE_RECORD_SUM, one, exponential_step(&steps, ENGINE_RECORD_PRODUCT, on, divisor_less));
        const unsigned int raised = exponential_step(&steps, ENGINE_RECORD_PRODUCT, value, factor);
        value = exponential_rounded(&steps, raised, divided, high, one);
        value = exponential_step(&steps, ENGINE_RECORD_WRAP, value, chain->bound_bits);
    }
    if ((chain->end != 1ull) || (chain->end_rise != 0ull))
    {
        const unsigned int end = exponential_constant(&steps, exponential_unsigned(chain->end));
        const unsigned int rise = exponential_constant(&steps, exponential_unsigned(chain->end_rise));
        const unsigned int last_divisor = exponential_step(&steps, ENGINE_RECORD_SUM, end,
                                                           exponential_step(&steps, ENGINE_RECORD_PRODUCT, rise, index));
        value = exponential_rounded(&steps, value, last_divisor, high, one);
        value = exponential_step(&steps, ENGINE_RECORD_WRAP, value, chain->bound_bits);
    }
    unsigned int bound = chain->bound_bits;
    if (tail != 0)
    {
        const unsigned int raised =
            exponential_step(&steps, ENGINE_RECORD_PRODUCT, value, exponential_constant(&steps, chain->tail_top));
        value = exponential_rounded(&steps, raised, exponential_constant(&steps, chain->tail_bottom), 1, one);
        bound = chain->bound_bits + (unsigned int)sim_exact_bits(&chain->tail_top) + 1u;
    }
    exponential_step(&steps, ENGINE_RECORD_WRAP, value, bound);
    const unsigned int count = (unsigned int)steps.size();
    program->output = count - 1u;
    const unsigned int field_bits[1] = {exponential_bit_length(chain->last) + 1u};
    const unsigned int field_offset[1] = {0u};
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {1u, 0u, 0u};
    EngineError error;
    memset(&error, 0, sizeof(error));
    const KeymathRecordRequest encode_request = {steps.data(), count, field_bits, 1u,   1u, &program->output, 1u,
                                                 NULL,         0u,    &program->key, &error};
    if (keymath_record_encode(&encode_request) == KEYMATH_ERROR)
    {
        return 0;
    }
    const KeyScheduleRecordRequest layout_request = {&program->key,    field_offset, 1u, in_limbs, 1,
                                                     &program->layout, &error};
    if (key_schedule_record_layout(&layout_request) == KEY_SCHEDULE_ERROR)
    {
        keymath_record_release(&program->key);
        return 0;
    }
    if (cycle_record_load(&program->layout, &program->record, &error) == CYCLE_ERROR)
    {
        key_schedule_record_release(&program->layout);
        keymath_record_release(&program->key);
        return 0;
    }
    s_engine_count.programs += 1ull;
    s_engine_count.steps += count;
    return 1;
}

static void exponential_program_free(ExponentialProgram *program)
{
    cycle_record_release(program->record);
    key_schedule_record_release(&program->layout);
    keymath_record_release(&program->key);
    program->record = NULL;
}

// a sum read from `limbs` limbs of two's complement
static ExponentialWide exponential_sum_read(const std::vector<unsigned int> &limbs)
{
    ExponentialWide value;
    anchor_exact_zero(&value);
    const unsigned int count = (unsigned int)limbs.size();
    const int negative = (limbs[count - 1u] >> 31u) != 0u;
    for (unsigned int limb = 0u; (limb < count) && (limb < ANCHOR_EXACT_LIMBS); limb += 1u)
    {
        value.limb[limb] = negative ? ~limbs[limb] : limbs[limb];
    }
    int zero = 1;
    for (unsigned int limb = 0u; limb < ANCHOR_EXACT_LIMBS; limb += 1u)
    {
        zero = zero && (value.limb[limb] == 0u);
    }
    value.sign = zero ? 0 : 1;
    if (negative)
    {
        // the magnitude of a negative two's complement word is its complement plus one
        value = exponential_sum(value, exponential_unsigned(1ull));
        value.sign = -1;
    }
    return value;
}

// the program run over the lanes `ks`, on the device and on the host's interpreter, and its outputs summed on both:
// the device's sum, with s_engine_differs set where a record or the sums disagree
static ExponentialWide exponential_lanes_sum(const ExponentialProgram *program, const std::vector<unsigned int> &ks)
{
    ExponentialWide total;
    anchor_exact_zero(&total);
    const unsigned long long count = ks.size();
    if (count == 0ull)
    {
        return total;
    }
    EngineError error;
    memset(&error, 0, sizeof(error));
    const unsigned int in_limbs = program->layout.in_limbs[0];
    const unsigned int out_limbs = program->layout.out_limbs;
    std::vector<unsigned int> inputs((size_t)(count * in_limbs), 0u);
    for (unsigned long long lane = 0ull; lane < count; lane += 1ull)
    {
        inputs[(size_t)(lane * in_limbs)] = ks[(size_t)lane];
    }
    std::vector<unsigned int> host_out((size_t)(count * out_limbs), 0u);
    std::vector<unsigned int> device_out((size_t)(count * out_limbs), 0u);
    unsigned int *device_in = NULL;
    unsigned int *device_records = NULL;
    const CycleRecordHostRequest host = {&program->layout, {inputs.data(), NULL, NULL}, {count, 0ull, 0ull}, NULL,
                                         count,            host_out.data(),             &error};
    int ok = (cycle_record_run_host(&host) != CYCLE_ERROR) &&
             (cudaMalloc((void **)&device_in, inputs.size() * sizeof(unsigned int)) == cudaSuccess) &&
             (cudaMalloc((void **)&device_records, device_out.size() * sizeof(unsigned int)) == cudaSuccess) &&
             (cudaMemcpy(device_in, inputs.data(), inputs.size() * sizeof(unsigned int), cudaMemcpyHostToDevice) ==
              cudaSuccess);
    if (ok != 0)
    {
        const CycleRecordRunRequest run = {program->record, {device_in, NULL, NULL}, {count, 0ull, 0ull}, NULL,
                                           count,           device_records,          &error};
        ok = (cycle_record_run(&run) != CYCLE_ERROR) &&
             (cudaMemcpy(device_out.data(), device_records, device_out.size() * sizeof(unsigned int),
                         cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    const DeviceRecordStep *const output = &program->layout.step_table[program->output];
    const unsigned int sum_limbs = ((output->out_bits + 64u) + 31u) / 32u;
    std::vector<unsigned int> device_sum(sum_limbs, 0u);
    std::vector<unsigned int> host_sum(sum_limbs, 0u);
    if (ok != 0)
    {
        const CycleRecordSumRequest on_device = {device_records, count,     count, out_limbs, output->out_offset,
                                                 output->out_bits, sum_limbs, device_sum.data(), &error};
        const CycleRecordSumRequest on_host = {host_out.data(), count,     count, out_limbs, output->out_offset,
                                               output->out_bits, sum_limbs, host_sum.data(), &error};
        ok = (cycle_record_sum(&on_device) != CYCLE_ERROR) && (cycle_record_sum_host(&on_host) != CYCLE_ERROR);
    }
    cudaFree(device_in);
    cudaFree(device_records);
    if (ok == 0)
    {
        s_engine_failed = 1;
        return total;
    }
    for (unsigned long long lane = 0ull; lane < count; lane += 1ull)
    {
        const int same = memcmp(&host_out[(size_t)(lane * out_limbs)], &device_out[(size_t)(lane * out_limbs)],
                                out_limbs * sizeof(unsigned int)) == 0;
        s_engine_count.same += same ? 1ull : 0ull;
        s_engine_differs = s_engine_differs || !same;
    }
    s_engine_count.lanes += count;
    const int sums_same = device_sum == host_sum;
    s_engine_count.sums += 1ull;
    s_engine_count.sums_same += sums_same ? 1ull : 0ull;
    s_engine_differs = s_engine_differs || !sums_same;
    return exponential_sum_read(device_sum);
}

// the low and high ends of a chain summed over the lanes `ks`
static ExponentialSpan exponential_chain_sum(const ExponentialChain *chain, const std::vector<unsigned int> &ks)
{
    ExponentialSpan span;
    anchor_exact_zero(&span.low);
    anchor_exact_zero(&span.high);
    for (int high = 0; (high <= 1) && (s_engine_failed == 0); high += 1)
    {
        ExponentialProgram program;
        if (exponential_program_build(chain, high, 0, &program) == 0)
        {
            s_engine_failed = 1;
            break;
        }
        const ExponentialWide sum = exponential_lanes_sum(&program, ks);
        exponential_program_free(&program);
        if (high != 0)
        {
            span.high = sum;
        }
        else
        {
            span.low = sum;
        }
    }
    return span;
}

// the chain's tail program run on its one lane, the deepest k
static ExponentialWide exponential_chain_tail(const ExponentialChain *chain)
{
    ExponentialWide tail;
    anchor_exact_zero(&tail);
    ExponentialProgram program;
    if ((s_engine_failed != 0) || (exponential_program_build(chain, 1, 1, &program) == 0))
    {
        s_engine_failed = 1;
        return tail;
    }
    const std::vector<unsigned int> deepest(1u, (unsigned int)chain->last);
    tail = exponential_lanes_sum(&program, deepest);
    exponential_program_free(&program);
    return tail;
}

// the lanes first, first + step, ... up to `last`
static std::vector<unsigned int> exponential_ks(unsigned long long first, unsigned long long last,
                                                unsigned long long step)
{
    std::vector<unsigned int> ks;
    for (unsigned long long k = first; k <= last; k += step)
    {
        // a series' deepest k is far below 2^32
        ks.push_back((unsigned int)k);
    }
    return ks;
}

static void exponential_held_to(const ExponentialSpan &engine, const ExponentialSpan &host)
{
    s_engine_differs = s_engine_differs || (exponential_compare(engine.low, host.low) != 0) ||
                       (exponential_compare(engine.high, host.high) != 0);
}

// e^x on the engine: terms 1 .. N as lanes, term 0 the unit, and the tail program at N
static ExponentialSpan exponential_rising_engine(const ExponentialWide &top, const ExponentialWide &bottom,
                                                 unsigned int scale)
{
    unsigned long long last = 0ull;
    const ExponentialSpan host = exponential_rising_host(top, bottom, scale, &last);
    if ((top.sign == 0) || (s_engine_failed != 0))
    {
        return host;
    }
    ExponentialChain chain;
    chain.first_top = exponential_unsigned(1ull);
    chain.first_bottom = chain.first_top;
    chain.multiplier = top;
    anchor_exact_zero(&chain.base);
    chain.rise = bottom;
    chain.end = 1ull;
    chain.end_rise = 0ull;
    chain.last = last;
    chain.scale = scale;
    chain.bound_bits = (unsigned int)sim_exact_bits(&host.high) + 2u;
    chain.tail_top = top;
    chain.tail_bottom = exponential_difference(exponential_product(bottom, exponential_unsigned(last + 1ull)), top);
    const ExponentialSpan terms = exponential_chain_sum(&chain, exponential_ks(1ull, last, 1ull));
    const ExponentialWide tail = exponential_chain_tail(&chain);
    const ExponentialWide unit = exponential_power_two(scale);
    ExponentialSpan span;
    span.low = exponential_sum(unit, terms.low);
    span.high = exponential_sum(exponential_sum(unit, terms.high), tail);
    exponential_held_to(span, host);
    return span;
}

// S(x) on the engine: the odd and the even terms through I - 1 summed apart, and term I, I the host's last; S lies
// between the partial sums through I - 1 and through I
static ExponentialSpan exponential_alternating_engine(const ExponentialWide &top, const ExponentialWide &bottom,
                                                      unsigned int scale)
{
    unsigned long long last = 0ull;
    const ExponentialSpan host = exponential_alternating_host(top, bottom, scale, &last);
    if ((top.sign == 0) || (s_engine_failed != 0) || (last == 0ull))
    {
        return host;
    }
    unsigned long long rising_last = 0ull;
    const ExponentialSpan rising = exponential_rising_host(top, bottom, scale, &rising_last);
    ExponentialChain chain;
    chain.first_top = exponential_unsigned(1ull);
    chain.first_bottom = chain.first_top;
    chain.multiplier = top;
    anchor_exact_zero(&chain.base);
    chain.rise = bottom;
    chain.end = 0ull;
    chain.end_rise = 1ull;
    chain.last = last;
    chain.scale = scale;
    chain.bound_bits = (unsigned int)sim_exact_bits(&rising.high) + 2u;
    anchor_exact_zero(&chain.tail_top);
    anchor_exact_zero(&chain.tail_bottom);
    const ExponentialSpan odd = exponential_chain_sum(&chain, exponential_ks(1ull, last - 1ull, 2ull));
    const ExponentialSpan even = exponential_chain_sum(&chain, exponential_ks(2ull, last - 1ull, 2ull));
    const ExponentialSpan term = exponential_chain_sum(&chain, exponential_ks(last, last, 1ull));
    ExponentialSpan before;
    before.low = exponential_difference(odd.low, even.high);
    before.high = exponential_difference(odd.high, even.low);
    ExponentialSpan through;
    const int adds = (last & 1ull) != 0ull;
    through.low = adds ? exponential_sum(before.low, term.low) : exponential_difference(before.low, term.high);
    through.high = adds ? exponential_sum(before.high, term.high) : exponential_difference(before.high, term.low);
    ExponentialSpan span;
    span.low = (exponential_compare(before.low, through.low) < 0) ? before.low : through.low;
    span.high = (exponential_compare(before.high, through.high) > 0) ? before.high : through.high;
    exponential_held_to(span, host);
    return span;
}

// artanh(c / d) on the engine: terms 0 .. N as lanes and the tail program at N
static ExponentialSpan exponential_artanh_engine(const ExponentialWide &top, const ExponentialWide &bottom,
                                                 unsigned int scale)
{
    unsigned long long last = 0ull;
    const ExponentialSpan host = exponential_artanh_host(top, bottom, scale, &last);
    if ((top.sign == 0) || (s_engine_failed != 0))
    {
        return host;
    }
    const ExponentialWide top_square = exponential_product(top, top);
    const ExponentialWide bottom_square = exponential_product(bottom, bottom);
    ExponentialChain chain;
    chain.first_top = top;
    chain.first_bottom = bottom;
    chain.multiplier = top_square;
    chain.base = bottom_square;
    anchor_exact_zero(&chain.rise);
    chain.end = 1ull;
    chain.end_rise = 2ull;
    chain.last = last;
    chain.scale = scale;
    chain.bound_bits = scale + 2u;
    chain.tail_top = top_square;
    chain.tail_bottom = exponential_product(exponential_unsigned((2ull * last) + 3ull),
                                            exponential_difference(bottom_square, top_square));
    const ExponentialSpan terms = exponential_chain_sum(&chain, exponential_ks(0ull, last, 1ull));
    const ExponentialWide tail = exponential_chain_tail(&chain);
    ExponentialSpan span;
    span.low = terms.low;
    span.high = exponential_sum(terms.high, tail);
    exponential_held_to(span, host);
    return span;
}

static int exponential_engine_whole(void)
{
    return (s_engine_failed == 0) && (s_engine_differs == 0);
}

const ExponentialSource g_exponential_engine = {exponential_rising_engine, exponential_alternating_engine,
                                                exponential_artanh_engine, exponential_engine_whole};

// The bytes one program at a time takes on the device, at most: the deepest chain any reading at `bits` unrolls, its
// steps a k at most 32, and its lanes' inputs and records, each record as wide as the chain's bound. The deepest is
// e^x's, S(x)'s or artanh's at x, at 1 and at 1/3, at the reading's first guard
unsigned long long exponential_engine_bytes(const SimRational *x, unsigned int bits)
{
    const unsigned int scale = bits + 32u;
    const ExponentialWide one = exponential_unsigned(1ull);
    const ExponentialWide three = exponential_unsigned(3ull);
    unsigned long long deepest = 0ull;
    unsigned long long last = 0ull;
    const ExponentialSpan rising = exponential_rising_host(x->numerator, x->denominator, scale, &last);
    deepest = (last > deepest) ? last : deepest;
    exponential_alternating_host(x->numerator, x->denominator, scale, &last);
    deepest = (last > deepest) ? last : deepest;
    exponential_alternating_host(one, one, scale, &last);
    deepest = (last > deepest) ? last : deepest;
    exponential_artanh_host(one, three, scale, &last);
    deepest = (last > deepest) ? last : deepest;
    const unsigned long long record_limbs = ((sim_exact_bits(&rising.high) + 2ull) / 32ull) + 2ull;
    const unsigned long long steps = 32ull * (deepest + 2ull);
    return (steps * sizeof(DeviceRecordStep)) + ((deepest + 2ull) * (record_limbs + 1ull) * sizeof(unsigned int));
}
