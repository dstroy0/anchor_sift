// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The loop rule's orders on the record machine, both ways. A floor G over four 32-bit words is made of shears, each
// adding to one word a function of the others and wrapping to 32 bits, so G is a bijection whatever the functions
// are, and G^-1 undoes the shears in reverse order. One word is the order's counter, n -> n + 1, so the orders load
// themselves as the naturals, and the inverse carries them below zero. One program runs the orders 0 -> K -> -K -> 0
// with every floor tapped: each visit to order k must hold the CPU's G^k(x), the counter must read k, and the return
// to 0 is exact. Then the order omega on a finite window: a floor is a table permutation of the 16-bit states, its
// inverse table runs the negative orders, a third table reads a halt set, and an or gathers every bit's lim sup beside
// the floor. A bijection of a finite set has no transient, so every orbit is a cycle, and +omega and -omega are one
// stage: each bit's or over the cycle, and the halt flag set exactly when the cycle meets the halt set. The device
// decides every lane whose cycle fits its run; past the run a set flag is a halt seen, and a clear one is open. The
// test is one job on the device's tessera daemon, submitted before its first device work.
#include "cycle.h"
#include "keymath.h"
#include "key_schedule.h"
#include "scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define ORDER_TEST_LINE 8192ull

// the orders both ways: four 32-bit words (a, b, d and the counter n), K floors each way, every floor tapped
#define ORDER_TEST_WORDS 4u

#define ORDER_TEST_DEPTH 256u

#define ORDER_TEST_FLOORS (4u * ORDER_TEST_DEPTH)

#define ORDER_TEST_FLOOR_STEPS 12u

#define ORDER_TEST_LANES 512u

// the order omega: a permutation of the 16-bit states, the floors a run reads, the lanes, and the halt set's size
#define ORDER_TEST_STATE_BITS 16u

#define ORDER_TEST_STATES 65536u

#define ORDER_TEST_RUN 2048u

#define ORDER_TEST_OMEGA_STEPS 8u

#define ORDER_TEST_OMEGA_LANES 1024u

#define ORDER_TEST_HALTS 48u

// the most the test puts on the device at once: the orders' lanes, their four words in and every floor's four words
// out at no more than 33 bits each
#define ORDER_TEST_DECLARED \
    ((unsigned long long)ORDER_TEST_LANES \
     * (ORDER_TEST_WORDS + (((ORDER_TEST_WORDS * ORDER_TEST_FLOORS * 33ull) + 31ull) / 32ull)) * sizeof(unsigned int))

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} OrderTally;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} OrderLoaded;

typedef struct
{
    EngineRecordStep *steps;
    unsigned int count;
} OrderStack;

typedef struct
{
    long long word[ORDER_TEST_WORDS];
} OrderState;

static unsigned long long s_order_state = 0x0DE7C0DE5EEDF00Dull;

static unsigned int order_random(void)
{
    s_order_state ^= s_order_state << 13u;
    s_order_state ^= s_order_state >> 7u;
    s_order_state ^= s_order_state << 17u;
    return (unsigned int)(s_order_state >> 16u);
}

static void order_check(OrderTally *tally, int held, const char *what)
{
    tally->checks += 1ull;
    if (held == 0)
    {
        tally->failures += 1ull;
        scriptura_text(&tally->line, "  FAILED: ");
        scriptura_text(&tally->line, what);
        scriptura_character(&tally->line, '\n');
    }
}

static unsigned int order_emit(OrderStack *stack, EngineRecordOperation operation, unsigned int left, unsigned int right)
{
    stack->steps[stack->count] = EngineRecordStep{operation, left, right, 0u};
    stack->count += 1u;
    return stack->count - 1u;
}

static unsigned int order_wrap_step(OrderStack *stack, unsigned int value)
{
    return order_emit(stack, ENGINE_RECORD_WRAP, value, 32u);
}

// imprint, lay with reuse, and load one program of a single member
static int order_load(const OrderStack *stack, const unsigned int *field_bits, const unsigned int *field_offset,
                      unsigned int fields, unsigned int in_limbs, const unsigned int *outputs, unsigned int output_count,
                      const EngineRecordTable *tables, unsigned int table_count, OrderLoaded *loaded)
{
    memset(loaded, 0, sizeof(*loaded));
    unsigned int member_limbs[ENGINE_RECORD_MEMBERS_MAX] = {in_limbs, 0u, 0u};
    const KeymathRecordRequest imprint = {stack->steps, stack->count, field_bits, fields, 1u, outputs, output_count,
                                          tables, table_count, &loaded->key, &loaded->error};
    if (keymath_record_imprint(&imprint) == KEYMATH_REFUSED)
    {
        return 0;
    }
    const KeyScheduleRecordRequest lay = {&loaded->key, field_offset, fields, member_limbs, 1, &loaded->layout,
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

static void order_free(OrderLoaded *loaded)
{
    cycle_record_release(loaded->record);
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

// run a loaded program over `count` atoms on the host into host_out and on the device into device_out; each result
// is 1 run, 0 refused
static void order_run(OrderLoaded *loaded, const unsigned int *atoms, unsigned int count, unsigned int *host_out,
                      unsigned int *device_out, int *host_ran, int *device_ran)
{
    const unsigned int in_limbs = loaded->layout.in_limbs[0];
    const unsigned int out_limbs = loaded->layout.out_limbs;
    const CycleRecordHostRequest host = {&loaded->layout, {atoms, NULL, NULL}, {count, 0ull, 0ull}, NULL, count,
                                         host_out, &loaded->error};
    *host_ran = cycle_record_run_host(&host) != CYCLE_REFUSED;
    unsigned int *device_atoms = NULL;
    unsigned int *device_record = NULL;
    int good = (cudaMalloc((void **)&device_atoms, (size_t)count * in_limbs * sizeof(unsigned int)) == cudaSuccess)
            && (cudaMalloc((void **)&device_record, (size_t)count * out_limbs * sizeof(unsigned int)) == cudaSuccess)
            && (cudaMemcpy(device_atoms, atoms, (size_t)count * in_limbs * sizeof(unsigned int), cudaMemcpyHostToDevice)
                == cudaSuccess);
    if (good != 0)
    {
        const CycleRecordRunRequest run = {loaded->record, {device_atoms, NULL, NULL}, {count, 0ull, 0ull}, NULL,
                                           count, device_record, &loaded->error};
        good = cycle_record_run(&run) != CYCLE_REFUSED;
        good = good
            && (cudaMemcpy(device_out, device_record, (size_t)count * out_limbs * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost)
                == cudaSuccess);
    }
    cudaFree(device_atoms);
    cudaFree(device_record);
    *device_ran = good;
}

// one written output, `bits` of two's complement at `offset`, its top bit the sign; every output here is at most
// 33 bits, so it fits a long long
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
    // the 64-bit pattern read back as two's complement: the value fits, so the reinterpretation is exact
    return (long long)raw;
}

static long long order_output(const OrderLoaded *loaded, const unsigned int *record, unsigned int step)
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
// Every word lies in [-2^31, 2^31), so b times d is below 2^62 in magnitude and a long long holds each sum.
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
    const unsigned int product = order_emit(stack, ENGINE_RECORD_PRODUCT, word[1], word[2]);
    word[0] = order_wrap_step(stack, order_emit(stack, ENGINE_RECORD_SUM, word[0], product));
    const unsigned int shift = order_wrap_step(stack, order_emit(stack, ENGINE_RECORD_SUM, word[0], word[3]));
    word[1] = order_wrap_step(stack, order_emit(stack, ENGINE_RECORD_XOR, word[1], shift));
    const unsigned int both = order_emit(stack, ENGINE_RECORD_AND, word[0], word[1]);
    word[2] = order_wrap_step(stack, order_emit(stack, ENGINE_RECORD_SUM, word[2], both));
    word[3] = order_wrap_step(stack, order_emit(stack, ENGINE_RECORD_SUM, word[3], one));
}

// G^-1 as record steps
static void order_floor_inverse(OrderStack *stack, unsigned int *word, unsigned int one)
{
    word[3] = order_wrap_step(stack, order_emit(stack, ENGINE_RECORD_DIFFERENCE, word[3], one));
    const unsigned int both = order_emit(stack, ENGINE_RECORD_AND, word[0], word[1]);
    word[2] = order_wrap_step(stack, order_emit(stack, ENGINE_RECORD_DIFFERENCE, word[2], both));
    const unsigned int shift = order_wrap_step(stack, order_emit(stack, ENGINE_RECORD_SUM, word[0], word[3]));
    word[1] = order_wrap_step(stack, order_emit(stack, ENGINE_RECORD_XOR, word[1], shift));
    const unsigned int product = order_emit(stack, ENGINE_RECORD_PRODUCT, word[1], word[2]);
    word[0] = order_wrap_step(stack, order_emit(stack, ENGINE_RECORD_DIFFERENCE, word[0], product));
}

// one 32-bit field in an edge shape: random bits, zero, -1, the most negative, the most positive, or one
static unsigned int order_edge_word(void)
{
    const unsigned int kind = order_random() % 6u;
    const unsigned int shapes[5] = {0u, 0xFFFFFFFFu, 0x80000000u, 0x7FFFFFFFu, 1u};
    return (kind == 0u) ? order_random() : shapes[kind - 1u];
}

// a 32-bit field's two's complement read signed: 2^32 comes off where its top bit is set
static long long order_signed_word(unsigned int raw)
{
    return ((raw & 0x80000000u) != 0u) ? ((long long)raw - 4294967296ll) : (long long)raw;
}

// the orders 0 -> K -> -K -> 0 in one program, every floor's four words an output
static void order_both_ways(OrderTally *tally)
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
        order_check(tally, 0, "the orders' program is held");
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
        word[at] = order_emit(&stack, ENGINE_RECORD_FIELD_SIGNED, at, 0u);
    }
    const unsigned int one = order_emit(&stack, ENGINE_RECORD_CONSTANT, 1u, 0u);
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
    order_check(tally, loads, "the orders' stack imprints, lays with reuse and loads");
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
        // a, b and d in edge shapes; the counter starts at order 0
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
    unsigned int visits_held = 0u;
    unsigned int counters_held = 0u;
    unsigned int steps_held = 0u;
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
        steps_held += (step != 0) ? 1u : 0u;
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
            const long long read_counter
                = order_output(&loaded, record, outputs[(floor * ORDER_TEST_WORDS) + (ORDER_TEST_WORDS - 1u)]);
            counter = counter && (read_counter == (long long)floor_order[floor]);
        }
        visits_held += (visits != 0) ? 1u : 0u;
        counters_held += (counter != 0) ? 1u : 0u;
        int back = 1;
        for (unsigned int at = 0u; at < ORDER_TEST_WORDS; at += 1u)
        {
            const long long read
                = order_output(&loaded, record, outputs[((ORDER_TEST_FLOORS - 1u) * ORDER_TEST_WORDS) + at]);
            back = back && (read == origin->word[at]);
        }
        returned += (back != 0) ? 1u : 0u;
    }
    scriptura_text(&tally->line, "  orders: G of four shears over 32-bit words, 0 -> ");
    scriptura_decimal(&tally->line, ORDER_TEST_DEPTH, 1u);
    scriptura_text(&tally->line, " -> -");
    scriptura_decimal(&tally->line, ORDER_TEST_DEPTH, 1u);
    scriptura_text(&tally->line, " -> 0 in ");
    scriptura_decimal(&tally->line, ORDER_TEST_FLOORS, 1u);
    scriptura_text(&tally->line, " floors, ");
    scriptura_decimal(&tally->line, stack.count, 1u);
    scriptura_text(&tally->line, " steps, file ");
    scriptura_decimal(&tally->line, loaded.layout.file_limbs, 1u);
    scriptura_text(&tally->line, " limbs\n    ");
    scriptura_decimal(&tally->line, visits_held, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, lanes, 1u);
    scriptura_text(&tally->line, " lanes hold the CPU's G^k(x) at every visit to every order; the counter reads k on ");
    scriptura_decimal(&tally->line, counters_held, 1u);
    scriptura_text(&tally->line, "; ");
    scriptura_decimal(&tally->line, returned, 1u);
    scriptura_text(&tally->line, " return to x exactly; G carries each order to the next on ");
    scriptura_decimal(&tally->line, steps_held, 1u);
    scriptura_character(&tally->line, '\n');
    order_check(tally, (host_ran != 0) && (device_ran != 0), "the orders run on the host and the device");
    order_check(tally,
                (host_ran != 0) && (device_ran != 0)
                    && (memcmp(host_out, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0),
                "the orders' device records equal the host's word for word");
    order_check(tally, steps_held == lanes, "G carries every order to the next from -K to K, so G^-1 inverts it");
    order_check(tally, visits_held == lanes, "every visit to order k holds the CPU's G^k(x), whichever way it came");
    order_check(tally, counters_held == lanes, "the counter reads the order at every floor, below zero included");
    order_check(tally, returned == lanes, "the run returns to order 0 and to x exactly");
    free(atoms);
    free(host_out);
    free(device_out);
    order_free(&loaded);
    free(stack.steps);
    free(outputs);
    free(floor_order);
    free(states);
}

// a permutation of the 2^16 states cut into cycles: the first half of a shuffled order on cycles no longer than the
// run, the second half on cycles longer than it
static void order_permutation(unsigned int *shuffled, unsigned int *forward, unsigned int *inverse)
{
    for (unsigned int state = 0u; state < ORDER_TEST_STATES; state += 1u)
    {
        shuffled[state] = state;
    }
    for (unsigned int state = ORDER_TEST_STATES - 1u; state > 0u; state -= 1u)
    {
        const unsigned int other = order_random() % (state + 1u);
        const unsigned int held = shuffled[state];
        shuffled[state] = shuffled[other];
        shuffled[other] = held;
    }
    unsigned int cursor = 0u;
    while (cursor < ORDER_TEST_STATES)
    {
        const unsigned int drawn = (cursor < (ORDER_TEST_STATES / 2u))
                                     ? (1u + (order_random() % ORDER_TEST_RUN))
                                     : (ORDER_TEST_RUN + 1u + (order_random() % (3u * ORDER_TEST_RUN)));
        const unsigned int length = (drawn < (ORDER_TEST_STATES - cursor)) ? drawn : (ORDER_TEST_STATES - cursor);
        for (unsigned int at = 0u; at < length; at += 1u)
        {
            forward[shuffled[cursor + at]] = shuffled[cursor + ((at + 1u) % length)];
        }
        cursor += length;
    }
    for (unsigned int state = 0u; state < ORDER_TEST_STATES; state += 1u)
    {
        inverse[forward[state]] = state;
    }
}

// a or b as record steps: a xor b and a and b share no set bit, so their xor is the or
static unsigned int order_or(OrderStack *stack, unsigned int left, unsigned int right)
{
    const unsigned int either = order_emit(stack, ENGINE_RECORD_XOR, left, right);
    const unsigned int both = order_emit(stack, ENGINE_RECORD_AND, left, right);
    return order_emit(stack, ENGINE_RECORD_XOR, either, both);
}

// the window of one run: s_0 from the record, s_f = table 0 of s_(f-1), every bit's or and the halt flag (table 1)
// gathered over s_0 .. s_(RUN - 1), and s_RUN one floor past the window. The outputs: the or, the flag, s_RUN.
static void order_omega_program(OrderStack *stack, unsigned int *outputs)
{
    unsigned int state = order_emit(stack, ENGINE_RECORD_FIELD, 0u, 0u);
    unsigned int gathered = state;
    unsigned int flag = order_emit(stack, ENGINE_RECORD_TABLE, state, 1u);
    for (unsigned int floor = 1u; floor < ORDER_TEST_RUN; floor += 1u)
    {
        state = order_emit(stack, ENGINE_RECORD_TABLE, state, 0u);
        gathered = order_or(stack, gathered, state);
        flag = order_or(stack, flag, order_emit(stack, ENGINE_RECORD_TABLE, state, 1u));
    }
    state = order_emit(stack, ENGINE_RECORD_TABLE, state, 0u);
    outputs[0] = gathered;
    outputs[1] = flag;
    outputs[2] = state;
}

// the CPU's walk of one window: the or, the flag and s_RUN, by the same table
static void order_window_cpu(const unsigned int *table, const unsigned int *halt, unsigned int start, long long *gathered,
                             long long *flag, long long *last)
{
    unsigned int state = start;
    unsigned int or_bits = 0u;
    unsigned int seen = 0u;
    for (unsigned int floor = 0u; floor < ORDER_TEST_RUN; floor += 1u)
    {
        or_bits |= state;
        seen |= halt[state];
        state = table[state];
    }
    *gathered = (long long)or_bits;
    *flag = (long long)seen;
    *last = (long long)state;
}

// the order omega on a finite window, forward by pi and backward by pi^-1, against each lane's whole cycle
static void order_omega(OrderTally *tally)
{
    unsigned int *const shuffled = (unsigned int *)malloc((size_t)ORDER_TEST_STATES * sizeof(unsigned int));
    unsigned int *const forward = (unsigned int *)malloc((size_t)ORDER_TEST_STATES * sizeof(unsigned int));
    unsigned int *const inverse = (unsigned int *)malloc((size_t)ORDER_TEST_STATES * sizeof(unsigned int));
    unsigned int *const halt = (unsigned int *)calloc(ORDER_TEST_STATES, sizeof(unsigned int));
    const unsigned int count = 3u + ((ORDER_TEST_RUN - 1u) * ORDER_TEST_OMEGA_STEPS);
    OrderStack stack = {(EngineRecordStep *)calloc(count, sizeof(EngineRecordStep)), 0u};
    if ((shuffled == NULL) || (forward == NULL) || (inverse == NULL) || (halt == NULL) || (stack.steps == NULL))
    {
        order_check(tally, 0, "the omega run is held");
        free(shuffled);
        free(forward);
        free(inverse);
        free(halt);
        free(stack.steps);
        return;
    }
    order_permutation(shuffled, forward, inverse);
    for (unsigned int at = 0u; at < ORDER_TEST_HALTS; at += 1u)
    {
        halt[order_random() % ORDER_TEST_STATES] = 1u;
    }
    unsigned int covered = 0u;
    unsigned int undone = 0u;
    for (unsigned int state = 0u; state < ORDER_TEST_STATES; state += 1u)
    {
        covered += (inverse[state] < ORDER_TEST_STATES) ? 1u : 0u;
        undone += (inverse[forward[state]] == state) ? 1u : 0u;
        shuffled[state] = 0u;
    }
    for (unsigned int state = 0u; state < ORDER_TEST_STATES; state += 1u)
    {
        shuffled[forward[state]] += 1u;
    }
    unsigned int images = 0u;
    for (unsigned int state = 0u; state < ORDER_TEST_STATES; state += 1u)
    {
        images += (shuffled[state] == 1u) ? 1u : 0u;
    }
    order_check(tally, (covered == ORDER_TEST_STATES) && (undone == ORDER_TEST_STATES) && (images == ORDER_TEST_STATES),
                "pi is a permutation of the 65,536 states and pi^-1 undoes it");
    unsigned int outputs[3];
    order_omega_program(&stack, outputs);
    const unsigned int field_bits[1] = {ORDER_TEST_STATE_BITS};
    const unsigned int field_offset[1] = {0u};
    EngineRecordTable forward_tables[2] = {{ORDER_TEST_STATE_BITS, ORDER_TEST_STATE_BITS, forward},
                                           {ORDER_TEST_STATE_BITS, 1u, halt}};
    EngineRecordTable backward_tables[2] = {{ORDER_TEST_STATE_BITS, ORDER_TEST_STATE_BITS, inverse},
                                            {ORDER_TEST_STATE_BITS, 1u, halt}};
    OrderLoaded upward;
    OrderLoaded downward;
    const int up_loads = order_load(&stack, field_bits, field_offset, 1u, 1u, outputs, 3u, forward_tables, 2u, &upward);
    const int down_loads
        = order_load(&stack, field_bits, field_offset, 1u, 1u, outputs, 3u, backward_tables, 2u, &downward);
    order_check(tally, (up_loads != 0) && (down_loads != 0), "the window's program loads with pi and with pi^-1");
    if ((up_loads == 0) || (down_loads == 0))
    {
        if (up_loads != 0)
        {
            order_free(&upward);
        }
        if (down_loads != 0)
        {
            order_free(&downward);
        }
        free(shuffled);
        free(forward);
        free(inverse);
        free(halt);
        free(stack.steps);
        return;
    }
    const unsigned int lanes = ORDER_TEST_OMEGA_LANES;
    const unsigned int up_limbs = upward.layout.out_limbs;
    const unsigned int down_limbs = downward.layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)malloc((size_t)lanes * sizeof(unsigned int));
    unsigned int *const up_host = (unsigned int *)calloc((size_t)lanes * up_limbs, sizeof(unsigned int));
    unsigned int *const up_device = (unsigned int *)calloc((size_t)lanes * up_limbs, sizeof(unsigned int));
    unsigned int *const down_host = (unsigned int *)calloc((size_t)lanes * down_limbs, sizeof(unsigned int));
    unsigned int *const down_device = (unsigned int *)calloc((size_t)lanes * down_limbs, sizeof(unsigned int));
    const int buffers = (atoms != NULL) && (up_host != NULL) && (up_device != NULL) && (down_host != NULL)
                     && (down_device != NULL);
    for (unsigned int lane = 0u; (buffers != 0) && (lane < lanes); lane += 1u)
    {
        atoms[lane] = order_random() % ORDER_TEST_STATES;
    }
    int up_host_ran = 0;
    int up_device_ran = 0;
    int down_host_ran = 0;
    int down_device_ran = 0;
    if (buffers != 0)
    {
        order_run(&upward, atoms, lanes, up_host, up_device, &up_host_ran, &up_device_ran);
        order_run(&downward, atoms, lanes, down_host, down_device, &down_host_ran, &down_device_ran);
    }
    const int ran = (up_host_ran != 0) && (up_device_ran != 0) && (down_host_ran != 0) && (down_device_ran != 0);
    unsigned int windows_held = 0u;
    unsigned int cycles_closed = 0u;
    unsigned int decided = 0u;
    unsigned int decided_held = 0u;
    unsigned int mirrored = 0u;
    unsigned int decided_halting = 0u;
    unsigned int open = 0u;
    unsigned int open_seen = 0u;
    unsigned int open_later = 0u;
    unsigned int seen_true = 0u;
    for (unsigned int lane = 0u; (ran != 0) && (lane < lanes); lane += 1u)
    {
        const unsigned int start = atoms[lane];
        long long gathered = 0ll;
        long long flag = 0ll;
        long long last = 0ll;
        long long back_gathered = 0ll;
        long long back_flag = 0ll;
        long long back_last = 0ll;
        order_window_cpu(forward, halt, start, &gathered, &flag, &last);
        order_window_cpu(inverse, halt, start, &back_gathered, &back_flag, &back_last);
        const unsigned int *const up = &up_device[(size_t)lane * up_limbs];
        const unsigned int *const down = &down_device[(size_t)lane * down_limbs];
        const long long up_gathered = order_output(&upward, up, outputs[0]);
        const long long up_flag = order_output(&upward, up, outputs[1]);
        const long long up_last = order_output(&upward, up, outputs[2]);
        const long long down_gathered = order_output(&downward, down, outputs[0]);
        const long long down_flag = order_output(&downward, down, outputs[1]);
        const long long down_last = order_output(&downward, down, outputs[2]);
        windows_held += ((up_gathered == gathered) && (up_flag == flag) && (up_last == last)
                         && (down_gathered == back_gathered) && (down_flag == back_flag) && (down_last == back_last))
                          ? 1u : 0u;
        // the whole cycle: its length, every bit's or over it, and whether it meets the halt set
        unsigned int length = 1u;
        unsigned int cycle_or = start;
        unsigned int meets = halt[start];
        unsigned int state = forward[start];
        while ((state != start) && (length <= ORDER_TEST_STATES))
        {
            cycle_or |= state;
            meets |= halt[state];
            state = forward[state];
            length += 1u;
        }
        cycles_closed += (state == start) ? 1u : 0u;
        if (length <= ORDER_TEST_RUN)
        {
            decided += 1u;
            decided_halting += meets;
            decided_held += ((up_gathered == (long long)cycle_or) && (up_flag == (long long)meets)) ? 1u : 0u;
            mirrored += ((down_gathered == up_gathered) && (down_flag == up_flag)) ? 1u : 0u;
        }
        else
        {
            open += 1u;
            open_seen += (up_flag != 0ll) ? 1u : 0u;
            open_later += ((up_flag == 0ll) && (meets != 0u)) ? 1u : 0u;
            seen_true += ((up_flag == 0ll) || (meets != 0u)) ? 1u : 0u;
        }
    }
    scriptura_text(&tally->line, "  omega: pi of 2^16 states, a run of ");
    scriptura_decimal(&tally->line, ORDER_TEST_RUN, 1u);
    scriptura_text(&tally->line, " floors, ");
    scriptura_decimal(&tally->line, stack.count, 1u);
    scriptura_text(&tally->line, " steps, files ");
    scriptura_decimal(&tally->line, upward.layout.file_limbs, 1u);
    scriptura_text(&tally->line, " and ");
    scriptura_decimal(&tally->line, downward.layout.file_limbs, 1u);
    scriptura_text(&tally->line, " limbs, ");
    scriptura_decimal(&tally->line, lanes, 1u);
    scriptura_text(&tally->line, " lanes\n    every window equals the CPU's walk on ");
    scriptura_decimal(&tally->line, windows_held, 1u);
    scriptura_text(&tally->line, "; every orbit returns to its start on ");
    scriptura_decimal(&tally->line, cycles_closed, 1u);
    scriptura_text(&tally->line, "\n    decided (the cycle fits the run): ");
    scriptura_decimal(&tally->line, decided, 1u);
    scriptura_text(&tally->line, ", +omega is the cycle's or and meeting on ");
    scriptura_decimal(&tally->line, decided_held, 1u);
    scriptura_text(&tally->line, ", -omega equals +omega on ");
    scriptura_decimal(&tally->line, mirrored, 1u);
    scriptura_text(&tally->line, "; halts ");
    scriptura_decimal(&tally->line, decided_halting, 1u);
    scriptura_text(&tally->line, ", runs forever ");
    scriptura_decimal(&tally->line, decided - decided_halting, 1u);
    scriptura_text(&tally->line, "\n    open (the cycle is longer than the run): ");
    scriptura_decimal(&tally->line, open, 1u);
    scriptura_text(&tally->line, ", a halt seen on ");
    scriptura_decimal(&tally->line, open_seen, 1u);
    scriptura_text(&tally->line, ", clear and halting past the run on ");
    scriptura_decimal(&tally->line, open_later, 1u);
    scriptura_text(&tally->line, ", clear and never halting on ");
    scriptura_decimal(&tally->line, open - open_seen - open_later, 1u);
    scriptura_character(&tally->line, '\n');
    order_check(tally, ran, "the window runs on the host and the device, both ways");
    order_check(tally,
                (ran != 0)
                    && (memcmp(up_host, up_device, (size_t)lanes * up_limbs * sizeof(unsigned int)) == 0)
                    && (memcmp(down_host, down_device, (size_t)lanes * down_limbs * sizeof(unsigned int)) == 0),
                "the window's device records equal the host's word for word, both ways");
    order_check(tally, windows_held == lanes, "every window's or, flag and last state equal the CPU's walk, both ways");
    order_check(tally, cycles_closed == lanes, "every orbit returns to its own start: a bijection has no transient");
    order_check(tally, decided_held == decided, "where the cycle fits the run, +omega is the or over the cycle, and the "
                                                "flag is set exactly when the cycle meets the halt set");
    order_check(tally, mirrored == decided, "where the cycle fits the run, -omega equals +omega");
    order_check(tally, (decided_halting != 0u) && (decided_halting != decided),
                "the decided lanes hold both answers, halting and running forever");
    order_check(tally, seen_true == open, "past the run, every set flag is a halt on the lane's own cycle");
    free(atoms);
    free(up_host);
    free(up_device);
    free(down_host);
    free(down_device);
    order_free(&upward);
    order_free(&downward);
    free(shuffled);
    free(forward);
    free(inverse);
    free(halt);
    free(stack.steps);
}

int main(int count, char **arguments)
{
    OrderTally tally;
    tally.checks = 0ull;
    tally.failures = 0ull;
    tally.line.room = ORDER_TEST_LINE;
    tally.line.out = (char *)malloc((size_t)ORDER_TEST_LINE);
    tally.line.at = 0ull;
    if (tally.line.out == NULL)
    {
        return 2;
    }
    char job_room[SIM_LINE_ROOM];
    SimTally job;
    sim_open(&job, job_room);
    const int admitted = sim_job_submit(&job, "record_order_test", count, arguments, ORDER_TEST_DECLARED);
    if (admitted != 0)
    {
        order_both_ways(&tally);
        order_omega(&tally);
    }
    sim_job_release(&job);
    sim_flush(&job);
    order_check(&tally, (admitted != 0) && (job.failures == 0ull),
                "tessera: the device's daemon admits the test's job and it releases");
    scriptura_text(&tally.line, "  record order test: ");
    scriptura_decimal(&tally.line, tally.checks, 1u);
    scriptura_text(&tally.line, " checks, ");
    scriptura_decimal(&tally.line, tally.failures, 1u);
    scriptura_text(&tally.line, " failed\n");
    scriptura_write(&tally.line, stdout);
    free(tally.line.out);
    return (tally.failures == 0ull) ? 0 : 1;
}
