// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_order_test_omega.cu: permutations, the omega program and main
#include "record_order_test_internal.h"

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
        const unsigned int temporary = shuffled[state];
        shuffled[state] = shuffled[other];
        shuffled[other] = temporary;
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

// a or b as record steps: a xor b and a and b share no set bit. Their xor is the or
static unsigned int order_or(OrderStack *stack, unsigned int left, unsigned int right)
{
    const unsigned int either = order_append(stack, ENGINE_RECORD_XOR, left, right);
    const unsigned int both = order_append(stack, ENGINE_RECORD_AND, left, right);
    return order_append(stack, ENGINE_RECORD_XOR, either, both);
}

// the window of one run: s_0 from the record, s_f = table 0 of s_(f-1), every bit's or and the halt flag (table 1)
// gathered over s_0 .. s_(RUN - 1), and s_RUN one floor past the window. The outputs: the or, the flag, s_RUN.
static void order_omega_program(OrderStack *stack, unsigned int *outputs)
{
    unsigned int state = order_append(stack, ENGINE_RECORD_FIELD, 0u, 0u);
    unsigned int gathered = state;
    unsigned int flag = order_append(stack, ENGINE_RECORD_TABLE, state, 1u);
    for (unsigned int floor = 1u; floor < ORDER_TEST_RUN; floor += 1u)
    {
        state = order_append(stack, ENGINE_RECORD_TABLE, state, 0u);
        gathered = order_or(stack, gathered, state);
        flag = order_or(stack, flag, order_append(stack, ENGINE_RECORD_TABLE, state, 1u));
    }
    state = order_append(stack, ENGINE_RECORD_TABLE, state, 0u);
    outputs[0] = gathered;
    outputs[1] = flag;
    outputs[2] = state;
}

// the CPU's walk of one window: the or, the flag and s_RUN, by the same table
static void order_window_cpu(const unsigned int *table, const unsigned int *halt, unsigned int start,
                             long long *gathered, long long *flag, long long *last)
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
static void order_omega(OrderResults *results)
{
    unsigned int *const shuffled = (unsigned int *)malloc((size_t)ORDER_TEST_STATES * sizeof(unsigned int));
    unsigned int *const forward = (unsigned int *)malloc((size_t)ORDER_TEST_STATES * sizeof(unsigned int));
    unsigned int *const inverse = (unsigned int *)malloc((size_t)ORDER_TEST_STATES * sizeof(unsigned int));
    unsigned int *const halt = (unsigned int *)calloc(ORDER_TEST_STATES, sizeof(unsigned int));
    const unsigned int count = 3u + ((ORDER_TEST_RUN - 1u) * ORDER_TEST_OMEGA_STEPS);
    OrderStack stack = {(EngineRecordStep *)calloc(count, sizeof(EngineRecordStep)), 0u};
    if ((shuffled == NULL) || (forward == NULL) || (inverse == NULL) || (halt == NULL) || (stack.steps == NULL))
    {
        order_check(results, 0, "the omega run is held");
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
    order_check(results,
                (covered == ORDER_TEST_STATES) && (undone == ORDER_TEST_STATES) && (images == ORDER_TEST_STATES),
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
    const int down_loads =
        order_load(&stack, field_bits, field_offset, 1u, 1u, outputs, 3u, backward_tables, 2u, &downward);
    order_check(results, (up_loads != 0) && (down_loads != 0), "the window's program loads with pi and with pi^-1");
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
    const int buffers =
        (atoms != NULL) && (up_host != NULL) && (up_device != NULL) && (down_host != NULL) && (down_device != NULL);
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
    unsigned int windows_ok = 0u;
    unsigned int cycles_closed = 0u;
    unsigned int decided = 0u;
    unsigned int decided_ok = 0u;
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
        windows_ok += ((up_gathered == gathered) && (up_flag == flag) && (up_last == last) &&
                       (down_gathered == back_gathered) && (down_flag == back_flag) && (down_last == back_last))
                          ? 1u
                          : 0u;
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
            decided_ok += ((up_gathered == (long long)cycle_or) && (up_flag == (long long)meets)) ? 1u : 0u;
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
    scriptura_text(&results->line, "  omega: pi of 2^16 states, a run of ");
    scriptura_decimal(&results->line, ORDER_TEST_RUN, 1u);
    scriptura_text(&results->line, " floors, ");
    scriptura_decimal(&results->line, stack.count, 1u);
    scriptura_text(&results->line, " steps, files ");
    scriptura_decimal(&results->line, upward.layout.file_limbs, 1u);
    scriptura_text(&results->line, " and ");
    scriptura_decimal(&results->line, downward.layout.file_limbs, 1u);
    scriptura_text(&results->line, " limbs, ");
    scriptura_decimal(&results->line, lanes, 1u);
    scriptura_text(&results->line, " lanes\n    every window equals the CPU's walk on ");
    scriptura_decimal(&results->line, windows_ok, 1u);
    scriptura_text(&results->line, "; every orbit returns to its start on ");
    scriptura_decimal(&results->line, cycles_closed, 1u);
    scriptura_text(&results->line, "\n    decided (the cycle fits the run): ");
    scriptura_decimal(&results->line, decided, 1u);
    scriptura_text(&results->line, ", +omega is the cycle's or and meeting on ");
    scriptura_decimal(&results->line, decided_ok, 1u);
    scriptura_text(&results->line, ", -omega equals +omega on ");
    scriptura_decimal(&results->line, mirrored, 1u);
    scriptura_text(&results->line, "; halts ");
    scriptura_decimal(&results->line, decided_halting, 1u);
    scriptura_text(&results->line, ", runs forever ");
    scriptura_decimal(&results->line, decided - decided_halting, 1u);
    scriptura_text(&results->line, "\n    open (the cycle is longer than the run): ");
    scriptura_decimal(&results->line, open, 1u);
    scriptura_text(&results->line, ", a halt seen on ");
    scriptura_decimal(&results->line, open_seen, 1u);
    scriptura_text(&results->line, ", clear and halting past the run on ");
    scriptura_decimal(&results->line, open_later, 1u);
    scriptura_text(&results->line, ", clear and never halting on ");
    scriptura_decimal(&results->line, open - open_seen - open_later, 1u);
    scriptura_character(&results->line, '\n');
    order_check(results, ran, "the window runs on the host and the device, both ways");
    order_check(results,
                (ran != 0) && (memcmp(up_host, up_device, (size_t)lanes * up_limbs * sizeof(unsigned int)) == 0) &&
                    (memcmp(down_host, down_device, (size_t)lanes * down_limbs * sizeof(unsigned int)) == 0),
                "the window's device records equal the host's word for word, both ways");
    order_check(results, windows_ok == lanes, "every window's or, flag and last state equal the CPU's walk, both ways");
    order_check(results, cycles_closed == lanes, "every orbit returns to its own start: a bijection has no transient");
    order_check(results, decided_ok == decided,
                "where the cycle fits the run, +omega is the or over the cycle, and the "
                "flag is set exactly when the cycle meets the halt set");
    order_check(results, mirrored == decided, "where the cycle fits the run, -omega equals +omega");
    order_check(results, (decided_halting != 0u) && (decided_halting != decided),
                "the decided lanes hold both answers, halting and running forever");
    order_check(results, seen_true == open, "past the run, every set flag is a halt on the lane's own cycle");
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
    OrderResults results;
    results.checks = 0ull;
    results.failures = 0ull;
    results.line.capacity = ORDER_TEST_LINE;
    results.line.out = (char *)malloc((size_t)ORDER_TEST_LINE);
    results.line.at = 0ull;
    if (results.line.out == NULL)
    {
        return 2;
    }
    char job_capacity[SIM_LINE_CAPACITY];
    SimResults job;
    sim_open(&job, job_capacity);
    const int admitted = sim_job_submit(&job, "record_order_test", count, arguments, ORDER_TEST_DECLARED);
    if (admitted != 0)
    {
        order_both_ways(&results);
        order_omega(&results);
    }
    sim_job_release(&job);
    sim_flush(&job);
    order_check(&results, (admitted != 0) && (job.failures == 0ull),
                "tessera: the device's daemon admits the test's job and it releases");
    scriptura_text(&results.line, "  record order test: ");
    scriptura_decimal(&results.line, results.checks, 1u);
    scriptura_text(&results.line, " checks, ");
    scriptura_decimal(&results.line, results.failures, 1u);
    scriptura_text(&results.line, " failed\n");
    scriptura_write(&results.line, stdout);
    free(results.line.out);
    return (results.failures == 0ull) ? 0 : 1;
}
