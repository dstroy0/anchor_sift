// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_lane_test_run.cu: interpretation, loading, the sweep and the latch
#include "record_lane_test_internal.h"

static unsigned long long s_lane_state = 0x1A7E1A7C4E5EED01ull;

unsigned long long lane_random(void)
{
    s_lane_state ^= s_lane_state << 13u;
    s_lane_state ^= s_lane_state >> 7u;
    s_lane_state ^= s_lane_state << 17u;
    return s_lane_state;
}

void lane_check(LaneResults *results, int passed, const char *what)
{
    results->checks += 1ull;
    if (passed == 0)
    {
        results->failures += 1ull;
        scriptura_text(&results->line, "  FAILED: ");
        scriptura_text(&results->line, what);
        scriptura_character(&results->line, '\n');
    }
}

// a lane, or "none" for the latch's infinity
void lane_print(LaneResults *results, unsigned long long lane)
{
    if (lane == CYCLE_LATCH_NONE)
    {
        scriptura_text(&results->line, "none");
        return;
    }
    scriptura_decimal(&results->line, lane, 1u);
}

// CYCLE_RECORD_INTERPRET, read by cycle_record_load: 1 keeps the next program loaded on the interpreter
static void lane_interpret(int interpret)
{
#if defined(_WIN32)
    _putenv_s("CYCLE_RECORD_INTERPRET", (interpret != 0) ? "1" : "0");
#else
    setenv("CYCLE_RECORD_INTERPRET", (interpret != 0) ? "1" : "0", 1);
#endif
}

static unsigned int lane_append(LaneProgram *program, EngineRecordOperation operation, unsigned int left,
                                unsigned int right)
{
    program->steps[program->count] = EngineRecordStep{operation, left, right, 0u};
    program->count += 1u;
    return program->count - 1u;
}

static unsigned int lane_output(LaneProgram *program, unsigned int step)
{
    program->outputs[program->output_count] = step;
    program->output_count += 1u;
    return program->output_count - 1u;
}

// x = base + l and its hash: the low word of x times one odd multiplier, the xor with its own top half, and the low
// word of that times another; the hit is [hash < T], (c + |c|) / 2 with c the order of T against the hash. With
// `write_all` the lane, x, the hash and the hit are written; otherwise the hit alone
void lane_search_build(LaneProgram *program, int write_all, LaneSearch *search)
{
    memset(program, 0, sizeof(*program));
    const unsigned int lane = lane_append(program, ENGINE_RECORD_LANE, 0u, 0u);
    const unsigned int base = lane_append(program, ENGINE_RECORD_FIELD, 0u, 0u);
    const unsigned int threshold = lane_append(program, ENGINE_RECORD_FIELD, 1u, 0u);
    const unsigned int value = lane_append(program, ENGINE_RECORD_SUM, base, lane);
    const unsigned int mask = lane_append(program, ENGINE_RECORD_CONSTANT, 0xFFFFFFFFu, 0u);
    const unsigned int first = lane_append(program, ENGINE_RECORD_CONSTANT, LANE_TEST_FIRST_MULTIPLIER, 0u);
    const unsigned int spread = lane_append(program, ENGINE_RECORD_PRODUCT, value, first);
    const unsigned int low = lane_append(program, ENGINE_RECORD_AND, spread, mask);
    const unsigned int half = lane_append(program, ENGINE_RECORD_CONSTANT, 65536u, 0u);
    const unsigned int top = lane_append(program, ENGINE_RECORD_QUOTIENT, low, half);
    const unsigned int mixed = lane_append(program, ENGINE_RECORD_XOR, low, top);
    const unsigned int second = lane_append(program, ENGINE_RECORD_CONSTANT, LANE_TEST_SECOND_MULTIPLIER, 0u);
    const unsigned int stirred = lane_append(program, ENGINE_RECORD_PRODUCT, mixed, second);
    const unsigned int hash = lane_append(program, ENGINE_RECORD_AND, stirred, mask);
    const unsigned int order = lane_append(program, ENGINE_RECORD_COMPARE, threshold, hash);
    const unsigned int size = lane_append(program, ENGINE_RECORD_ABSOLUTE, order, 0u);
    const unsigned int doubled = lane_append(program, ENGINE_RECORD_SUM, order, size);
    const unsigned int two = lane_append(program, ENGINE_RECORD_CONSTANT, 2u, 0u);
    const unsigned int hit = lane_append(program, ENGINE_RECORD_QUOTIENT, doubled, two);
    memset(search, 0, sizeof(*search));
    if (write_all != 0)
    {
        search->lane = lane_output(program, lane);
        search->value = lane_output(program, value);
        search->hash = lane_output(program, hash);
    }
    search->hit = lane_output(program, hit);
}

// the program encoded, laid out with reuse and loaded over one member of three limbs: base, then T; on the interpreter
// where `interpret`, else compiled where NVRTC and nvJitLink are found
int lane_load(const LaneProgram *program, int interpret, LaneLoaded *loaded)
{
    memset(loaded, 0, sizeof(*loaded));
    const unsigned int field_bits[2] = {LANE_TEST_BASE_BITS, LANE_TEST_THRESHOLD_BITS};
    const unsigned int field_offset[2] = {0u, LANE_TEST_THRESHOLD_OFFSET};
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {LANE_TEST_SHARED_LIMBS, 0u, 0u};
    const KeymathRecordRequest encode_request = {program->steps,   program->count,        field_bits, 2u, 1u,
                                                 program->outputs, program->output_count, NULL,       0u, &loaded->key,
                                                 &loaded->error};
    if (keymath_record_encode(&encode_request) == KEYMATH_ERROR)
    {
        return 0;
    }
    const KeyScheduleRecordRequest layout_request = {&loaded->key,    field_offset,  2u, in_limbs, 1,
                                                     &loaded->layout, &loaded->error};
    if (key_schedule_record_layout(&layout_request) == KEY_SCHEDULE_ERROR)
    {
        keymath_record_release(&loaded->key);
        return 0;
    }
    lane_interpret(interpret);
    const long bits = cycle_record_load(&loaded->layout, &loaded->record, &loaded->error);
    lane_interpret(0);
    if (bits == CYCLE_ERROR)
    {
        key_schedule_record_release(&loaded->layout);
        keymath_record_release(&loaded->key);
        return 0;
    }
    return 1;
}

void lane_free(LaneLoaded *loaded)
{
    cycle_record_release(loaded->record);
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

// `bits` of value laid out into a record at `offset`
void lane_put(unsigned int *record, unsigned int offset, unsigned int bits, unsigned long long value)
{
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int to = offset + bit;
        const unsigned int bit_value = (unsigned int)((value >> bit) & 1ull);
        record[to / 32u] = (record[to / 32u] & ~(1u << (to % 32u))) | (bit_value << (to % 32u));
    }
}

// the shared record: base, then T
void lane_shared(unsigned int *record, unsigned long long base, unsigned long long threshold)
{
    memset(record, 0, LANE_TEST_SHARED_LIMBS * sizeof(unsigned int));
    lane_put(record, 0u, LANE_TEST_BASE_BITS, base);
    lane_put(record, LANE_TEST_THRESHOLD_OFFSET, LANE_TEST_THRESHOLD_BITS, threshold);
}

// an output's low 64 bits, and whether every bit above them is 0: a never-negative output below 2^64 read whole
unsigned long long lane_take(const unsigned int *record, const DeviceRecordStep *step, int *fits)
{
    unsigned long long low = 0ull;
    unsigned int high = 0u;
    for (unsigned int bit = 0u; bit < step->out_bits; bit += 1u)
    {
        const unsigned int from = step->out_offset + bit;
        const unsigned int bit_value = (record[from / 32u] >> (from % 32u)) & 1u;
        if (bit < 64u)
        {
            low |= (unsigned long long)bit_value << bit;
        }
        else
        {
            high |= bit_value;
        }
    }
    *fits = (high == 0u) ? 1 : 0;
    return low;
}

// the host's own hash of x, in unsigned words, which wrap modulo 2^32: the low word of each product is the product
// of the low words
unsigned int lane_hash(unsigned long long value)
{
    // the cast keeps x's low word, all the first product's low word reads
    const unsigned int low = (unsigned int)value * LANE_TEST_FIRST_MULTIPLIER;
    const unsigned int mixed = low ^ (low >> 16u);
    return mixed * LANE_TEST_SECOND_MULTIPLIER;
}

// the first of `lanes` lanes whose hash of base + l lies under T, by the host's own arithmetic; CYCLE_LATCH_NONE for
// none
unsigned long long lane_native_first(unsigned long long base, unsigned long long threshold, unsigned long long lanes)
{
    for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
    {
        if ((unsigned long long)lane_hash(base + lane) < threshold)
        {
            return lane;
        }
    }
    return CYCLE_LATCH_NONE;
}

// the program over `lanes` lanes of one shared record in device memory, its records left in device_out
int lane_sweep(LaneLoaded *loaded, const unsigned int *device_shared, unsigned long long lanes,
               unsigned int *device_out)
{
    const CycleRecordRunRequest run = {
        loaded->record, {device_shared, NULL, NULL}, {1ull, 0ull, 0ull}, NULL, lanes, device_out, &loaded->error};
    return cycle_record_run(&run) != CYCLE_ERROR;
}

// the latch over records in device memory, the hit's field of the program's layout; 1 where it ran
int lane_latch_device(const LaneLoaded *loaded, const DeviceRecordStep *step, const unsigned int *device_out,
                      unsigned long long lanes, unsigned long long *first, EngineError *error)
{
    const CycleRecordLatchRequest latch = {
        device_out, lanes, loaded->layout.out_limbs, step->out_offset, step->out_bits, first, error};
    return cycle_record_latch(&latch) != CYCLE_ERROR;
}

int lane_latch_host(const LaneLoaded *loaded, const DeviceRecordStep *step, const unsigned int *out,
                    unsigned long long lanes, unsigned long long *first, EngineError *error)
{
    const CycleRecordLatchRequest latch = {out,   lanes, loaded->layout.out_limbs, step->out_offset, step->out_bits,
                                           first, error};
    return cycle_record_latch_host(&latch) != CYCLE_ERROR;
}
