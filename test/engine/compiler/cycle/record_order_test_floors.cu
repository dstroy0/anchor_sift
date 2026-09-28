// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_order_test_floors.cu: wraps, forward and inverse, floors and edges
#include "record_order_test_internal.h"

static unsigned long long s_order_state = 0x0DE7C0DE5EEDF00Dull;

unsigned int order_random(void)
{
    s_order_state ^= s_order_state << 13u;
    s_order_state ^= s_order_state >> 7u;
    s_order_state ^= s_order_state << 17u;
    return (unsigned int)(s_order_state >> 16u);
}

void order_check(OrderResults *results, int passed, const char *what)
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

unsigned int order_append(OrderStack *stack, EngineRecordOperation operation, unsigned int left, unsigned int right)
{
    stack->steps[stack->count] = EngineRecordStep{operation, left, right, 0u};
    stack->count += 1u;
    return stack->count - 1u;
}

static unsigned int order_wrap_step(OrderStack *stack, unsigned int value)
{
    return order_append(stack, ENGINE_RECORD_WRAP, value, 32u);
}

// encode, lay out with reuse, and load one program of a single member
int order_load(const OrderStack *stack, const unsigned int *field_bits, const unsigned int *field_offset,
               unsigned int fields, unsigned int in_limbs, const unsigned int *outputs, unsigned int output_count,
               const EngineRecordTable *tables, unsigned int table_count, OrderLoaded *loaded)
{
    memset(loaded, 0, sizeof(*loaded));
    unsigned int member_limbs[ENGINE_RECORD_MEMBERS_MAX] = {in_limbs, 0u, 0u};
    const KeymathRecordRequest encode_request = {stack->steps, stack->count, field_bits,    fields,
                                                 1u,           outputs,      output_count,  tables,
                                                 table_count,  &loaded->key, &loaded->error};
    if (keymath_record_encode(&encode_request) == KEYMATH_ERROR)
    {
        return 0;
    }
    const KeyScheduleRecordRequest layout_request = {&loaded->key,    field_offset,  fields, member_limbs, 1,
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

void order_free(OrderLoaded *loaded)
{
    cycle_record_release(loaded->record);
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

// run a loaded program over `count` atoms on the host into host_out and on the device into device_out; each result
// is 1 run, 0 refused
void order_run(OrderLoaded *loaded, const unsigned int *atoms, unsigned int count, unsigned int *host_out,
               unsigned int *device_out, int *host_ran, int *device_ran)
{
    const unsigned int in_limbs = loaded->layout.in_limbs[0];
    const unsigned int out_limbs = loaded->layout.out_limbs;
    const CycleRecordHostRequest host = {&loaded->layout, {atoms, NULL, NULL}, {count, 0ull, 0ull}, NULL, count,
                                         host_out,        &loaded->error};
    *host_ran = cycle_record_run_host(&host) != CYCLE_ERROR;
    unsigned int *device_atoms = NULL;
    unsigned int *device_record = NULL;
    int ok = (cudaMalloc((void **)&device_atoms, (size_t)count * in_limbs * sizeof(unsigned int)) == cudaSuccess) &&
             (cudaMalloc((void **)&device_record, (size_t)count * out_limbs * sizeof(unsigned int)) == cudaSuccess) &&
             (cudaMemcpy(device_atoms, atoms, (size_t)count * in_limbs * sizeof(unsigned int),
                         cudaMemcpyHostToDevice) == cudaSuccess);
    if (ok != 0)
    {
        const CycleRecordRunRequest run = {
            loaded->record, {device_atoms, NULL, NULL}, {count, 0ull, 0ull}, NULL, count, device_record,
            &loaded->error};
        ok = cycle_record_run(&run) != CYCLE_ERROR;
        ok = ok && (cudaMemcpy(device_out, device_record, (size_t)count * out_limbs * sizeof(unsigned int),
                               cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    cudaFree(device_atoms);
    cudaFree(device_record);
    *device_ran = ok;
}

// one written output, `bits` of two's complement at `offset`, its top bit the sign; every output here is at most
// 33 bits. It fits a long long
static long long order_read(const unsigned int *record, unsigned int offset, unsigned int bits)
{
    unsigned long long raw = 0ull;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int from = offset + bit;
        raw |= (unsigned long long)((record[from / 32u] >> (from % 32u)) & 1u) << bit;
    }
    if (((raw >> (bits - 1u)) & 1ull) != 0ull)
    {
        raw |= ~0ull << bits;
    }
    // the 64-bit pattern read back as two's complement: the value fits. The reinterpretation is exact
    return (long long)raw;
}

long long order_output(const OrderLoaded *loaded, const unsigned int *record, unsigned int step)
{
    const DeviceRecordStep *const tapped = &loaded->layout.step_table[step];
    return order_read(record, tapped->out_offset, tapped->out_bits);
}

// a value's low `bits` read back signed, on the CPU's own two's complement
static long long order_wrap(long long value, unsigned int bits)
{
    const unsigned long long mask = (bits >= 64u) ? ~0ull : ((1ull << bits) - 1ull);
    const unsigned long long low = (unsigned long long)value & mask;
    const unsigned long long top = 1ull << (bits - 1u);
    // a set top kept bit means 2^bits comes off: low - top - top, taken apart so neither half leaves the signed range
    return ((low & top) != 0ull) ? ((long long)(low - top) - (long long)top) : (long long)low;
}

// G on the CPU: a by b times d, b by the xor of a + n, d by a and b, and the counter by one, each wrapped to 32 bits.
// Every word lies in [-2^31, 2^31). B times d is below 2^62 in magnitude and a long long holds each sum.
static void order_forward_cpu(OrderState *state)
{
    long long *const word = state->word;
    word[0] = order_wrap(word[0] + (word[1] * word[2]), 32u);
    word[1] = order_wrap(word[1] ^ order_wrap(word[0] + word[3], 32u), 32u);
    word[2] = order_wrap(word[2] + (word[0] & word[1]), 32u);
    word[3] = order_wrap(word[3] + 1ll, 32u);
}

// G^-1 on the CPU: the same shears taken off in reverse order, each reading the words its forward shear read
static void order_inverse_cpu(OrderState *state)
{
    long long *const word = state->word;
    word[3] = order_wrap(word[3] - 1ll, 32u);
    word[2] = order_wrap(word[2] - (word[0] & word[1]), 32u);
    word[1] = order_wrap(word[1] ^ order_wrap(word[0] + word[3], 32u), 32u);
    word[0] = order_wrap(word[0] - (word[1] * word[2]), 32u);
}

// G as record steps over the registers in `word`, which it moves to the new state's registers
static void order_floor_forward(OrderStack *stack, unsigned int *word, unsigned int one)
{
    const unsigned int product = order_append(stack, ENGINE_RECORD_PRODUCT, word[1], word[2]);
    word[0] = order_wrap_step(stack, order_append(stack, ENGINE_RECORD_SUM, word[0], product));
    const unsigned int shift = order_wrap_step(stack, order_append(stack, ENGINE_RECORD_SUM, word[0], word[3]));
    word[1] = order_wrap_step(stack, order_append(stack, ENGINE_RECORD_XOR, word[1], shift));
    const unsigned int both = order_append(stack, ENGINE_RECORD_AND, word[0], word[1]);
    word[2] = order_wrap_step(stack, order_append(stack, ENGINE_RECORD_SUM, word[2], both));
    word[3] = order_wrap_step(stack, order_append(stack, ENGINE_RECORD_SUM, word[3], one));
}

// G^-1 as record steps
static void order_floor_inverse(OrderStack *stack, unsigned int *word, unsigned int one)
{
    word[3] = order_wrap_step(stack, order_append(stack, ENGINE_RECORD_DIFFERENCE, word[3], one));
    const unsigned int both = order_append(stack, ENGINE_RECORD_AND, word[0], word[1]);
    word[2] = order_wrap_step(stack, order_append(stack, ENGINE_RECORD_DIFFERENCE, word[2], both));
    const unsigned int shift = order_wrap_step(stack, order_append(stack, ENGINE_RECORD_SUM, word[0], word[3]));
    word[1] = order_wrap_step(stack, order_append(stack, ENGINE_RECORD_XOR, word[1], shift));
    const unsigned int product = order_append(stack, ENGINE_RECORD_PRODUCT, word[1], word[2]);
    word[0] = order_wrap_step(stack, order_append(stack, ENGINE_RECORD_DIFFERENCE, word[0], product));
}

// one 32-bit field in an edge case: random bits, zero, -1, the most negative, the most positive, or one
static unsigned int order_edge_word(void)
{
    const unsigned int kind = order_random() % 6u;
    const unsigned int extents[5] = {0u, 0xFFFFFFFFu, 0x80000000u, 0x7FFFFFFFu, 1u};
    return (kind == 0u) ? order_random() : extents[kind - 1u];
}

// a 32-bit field's two's complement read signed: 2^32 comes off where its top bit is set
static long long order_signed_word(unsigned int raw)
{
    return ((raw & 0x80000000u) != 0u) ? ((long long)raw - 4294967296ll) : (long long)raw;
}

// the orders 0 -> K -> -K -> 0 in one program, every floor's four words an output
void order_both_ways(OrderResults *results)
{
    const unsigned int count = ORDER_TEST_WORDS + 1u + (ORDER_TEST_FLOORS * ORDER_TEST_FLOOR_STEPS);
    const unsigned int output_count = ORDER_TEST_WORDS * ORDER_TEST_FLOORS;
    const unsigned int span = (2u * ORDER_TEST_DEPTH) + 1u;
    OrderStack stack = {(EngineRecordStep *)calloc(count, sizeof(EngineRecordStep)), 0u};
    unsigned int *const outputs = (unsigned int *)malloc((size_t)output_count * sizeof(unsigned int));
    int *const floor_order = (int *)malloc((size_t)ORDER_TEST_FLOORS * sizeof(int));
    OrderState *const states = (OrderState *)malloc((size_t)span * sizeof(OrderState));
    if ((stack.steps == NULL) || (outputs == NULL) || (floor_order == NULL) || (states == NULL))
    {
        order_check(results, 0, "the orders' program is held");
        free(stack.steps);
        free(outputs);
        free(floor_order);
        free(states);
        return;
    }
    unsigned int field_bits[ORDER_TEST_WORDS];
    unsigned int field_offset[ORDER_TEST_WORDS];
    unsigned int word[ORDER_TEST_WORDS];
    for (unsigned int at = 0u; at < ORDER_TEST_WORDS; at += 1u)
    {
        field_bits[at] = 32u;
        field_offset[at] = 32u * at;
        word[at] = order_append(&stack, ENGINE_RECORD_FIELD_SIGNED, at, 0u);
    }
    const unsigned int one = order_append(&stack, ENGINE_RECORD_CONSTANT, 1u, 0u);
    int order = 0;
    unsigned int tapped = 0u;
    for (unsigned int floor = 0u; floor < ORDER_TEST_FLOORS; floor += 1u)
    {
        // up K, down 2K, up K: the orders run 0 -> K -> -K -> 0
        const int upward = (floor < ORDER_TEST_DEPTH) || (floor >= (3u * ORDER_TEST_DEPTH));
        if (upward != 0)
        {
            order_floor_forward(&stack, word, one);
            order += 1;
        }
        else
        {
            order_floor_inverse(&stack, word, one);
            order -= 1;
        }
        floor_order[floor] = order;
        for (unsigned int at = 0u; at < ORDER_TEST_WORDS; at += 1u)
        {
            outputs[tapped] = word[at];
            tapped += 1u;
        }
    }
    OrderLoaded loaded;
    const int loads = order_load(&stack, field_bits, field_offset, ORDER_TEST_WORDS, ORDER_TEST_WORDS, outputs,
                                 output_count, NULL, 0u, &loaded);
    order_check(results, loads, "the orders' stack encodes, lays out with reuse and loads");
    if (loads == 0)
    {
        free(stack.steps);
        free(outputs);
        free(floor_order);
        free(states);
        return;
    }
    const unsigned int lanes = ORDER_TEST_LANES;
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * ORDER_TEST_WORDS, sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    const int buffers = (atoms != NULL) && (host_out != NULL) && (device_out != NULL);
    for (unsigned int lane = 0u; (buffers != 0) && (lane < lanes); lane += 1u)
    {
        // a, b and d in edge cases; the counter starts at order 0
        for (unsigned int at = 0u; at < (ORDER_TEST_WORDS - 1u); at += 1u)
        {
            atoms[(lane * ORDER_TEST_WORDS) + at] = order_edge_word();
        }
    }
    int host_ran = 0;
    int device_ran = 0;
    if (buffers != 0)
    {
        order_run(&loaded, atoms, lanes, host_out, device_out, &host_ran, &device_ran);
    }
    unsigned int visits_ok = 0u;
    unsigned int counters_ok = 0u;
    unsigned int steps_ok = 0u;
    unsigned int returned = 0u;
    for (unsigned int lane = 0u; (host_ran != 0) && (device_ran != 0) && (lane < lanes); lane += 1u)
    {
        // the CPU's orbit: state k at states[K + k], forward from x for k > 0 and by G^-1 for k < 0
        OrderState *const origin = &states[ORDER_TEST_DEPTH];
        for (unsigned int at = 0u; at < ORDER_TEST_WORDS; at += 1u)
        {
            origin->word[at] = order_signed_word(atoms[(lane * ORDER_TEST_WORDS) + at]);
        }
        for (unsigned int k = 1u; k <= ORDER_TEST_DEPTH; k += 1u)
        {
            states[ORDER_TEST_DEPTH + k] = states[ORDER_TEST_DEPTH + k - 1u];
            order_forward_cpu(&states[ORDER_TEST_DEPTH + k]);
            states[ORDER_TEST_DEPTH - k] = states[ORDER_TEST_DEPTH - k + 1u];
            order_inverse_cpu(&states[ORDER_TEST_DEPTH - k]);
        }
        // the step of the induction: G carries every order to the next, across zero
        int step = 1;
        for (unsigned int at = 0u; at + 1u < span; at += 1u)
        {
            OrderState next = states[at];
            order_forward_cpu(&next);
            step = step && (memcmp(&next, &states[at + 1u], sizeof(OrderState)) == 0);
        }
        steps_ok += (step != 0) ? 1u : 0u;
        const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
        int visits = 1;
        int counter = 1;
        for (unsigned int floor = 0u; floor < ORDER_TEST_FLOORS; floor += 1u)
        {
            const OrderState *const expected = &states[(int)ORDER_TEST_DEPTH + floor_order[floor]];
            for (unsigned int at = 0u; at < ORDER_TEST_WORDS; at += 1u)
            {
                const long long read = order_output(&loaded, record, outputs[(floor * ORDER_TEST_WORDS) + at]);
                visits = visits && (read == expected->word[at]);
            }
            const long long read_counter =
                order_output(&loaded, record, outputs[(floor * ORDER_TEST_WORDS) + (ORDER_TEST_WORDS - 1u)]);
            counter = counter && (read_counter == (long long)floor_order[floor]);
        }
        visits_ok += (visits != 0) ? 1u : 0u;
        counters_ok += (counter != 0) ? 1u : 0u;
        int back = 1;
        for (unsigned int at = 0u; at < ORDER_TEST_WORDS; at += 1u)
        {
            const long long read =
                order_output(&loaded, record, outputs[((ORDER_TEST_FLOORS - 1u) * ORDER_TEST_WORDS) + at]);
            back = back && (read == origin->word[at]);
        }
        returned += (back != 0) ? 1u : 0u;
    }
    scriptura_text(&results->line, "  orders: G of four shears over 32-bit words, 0 -> ");
    scriptura_decimal(&results->line, ORDER_TEST_DEPTH, 1u);
    scriptura_text(&results->line, " -> -");
    scriptura_decimal(&results->line, ORDER_TEST_DEPTH, 1u);
    scriptura_text(&results->line, " -> 0 in ");
    scriptura_decimal(&results->line, ORDER_TEST_FLOORS, 1u);
    scriptura_text(&results->line, " floors, ");
    scriptura_decimal(&results->line, stack.count, 1u);
    scriptura_text(&results->line, " steps, file ");
    scriptura_decimal(&results->line, loaded.layout.file_limbs, 1u);
    scriptura_text(&results->line, " limbs\n    ");
    scriptura_decimal(&results->line, visits_ok, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, lanes, 1u);
    scriptura_text(&results->line,
                   " lanes hold the CPU's G^k(x) at every visit to every order; the counter reads k on ");
    scriptura_decimal(&results->line, counters_ok, 1u);
    scriptura_text(&results->line, "; ");
    scriptura_decimal(&results->line, returned, 1u);
    scriptura_text(&results->line, " return to x exactly; G carries each order to the next on ");
    scriptura_decimal(&results->line, steps_ok, 1u);
    scriptura_character(&results->line, '\n');
    order_check(results, (host_ran != 0) && (device_ran != 0), "the orders run on the host and the device");
    order_check(results,
                (host_ran != 0) && (device_ran != 0) &&
                    (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0),
                "the orders' device records equal the host's word for word");
    order_check(results, steps_ok == lanes, "G carries every order to the next from -K to K, so G^-1 inverts it");
    order_check(results, visits_ok == lanes, "every visit to order k holds the CPU's G^k(x), whichever way it came");
    order_check(results, counters_ok == lanes, "the counter reads the order at every floor, below zero included");
    order_check(results, returned == lanes, "the run returns to order 0 and to x exactly");
    free(atoms);
    free(host_out);
    free(device_out);
    order_free(&loaded);
    free(stack.steps);
    free(outputs);
    free(floor_order);
    free(states);
}
