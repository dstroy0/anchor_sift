// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_gaussian_test_main.cu: main
#include "record_gaussian_test_internal.h"

// (1 + i)^k for k = 0 to 8, read off its polar form 2^(k/2) e^(i k pi / 4)
static const long long s_gaussian_power_real[GAUSSIAN_TEST_FLOORS + 1u] = {1ll,  1ll, 0ll, -2ll, -4ll,
                                                                           -4ll, 0ll, 8ll, 16ll};

static const long long s_gaussian_power_imaginary[GAUSSIAN_TEST_FLOORS + 1u] = {0ll,  1ll,  2ll,  2ll, 0ll,
                                                                                -4ll, -8ll, -8ll, 0ll};

int main(int count, char **arguments)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);

    // z = a + b i in fields 0 and 1; floor k writes a_k = a_(k-1) - b_(k-1) at step 2k and b_k = a_(k-1) + b_(k-1)
    // at step 2k + 1
    EngineRecordStep steps[GAUSSIAN_TEST_STEPS];
    unsigned int outputs[GAUSSIAN_TEST_OUTPUTS];
    steps[0] = EngineRecordStep{ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u};
    steps[1] = EngineRecordStep{ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 0u};
    for (unsigned int level = 1u; level <= GAUSSIAN_TEST_FLOORS; level += 1u)
    {
        const unsigned int real_before = 2u * (level - 1u);
        const unsigned int imaginary_before = real_before + 1u;
        steps[2u * level] = EngineRecordStep{ENGINE_RECORD_DIFFERENCE, real_before, imaginary_before, 0u};
        steps[(2u * level) + 1u] = EngineRecordStep{ENGINE_RECORD_SUM, real_before, imaginary_before, 0u};
        outputs[2u * (level - 1u)] = 2u * level;
        outputs[(2u * (level - 1u)) + 1u] = (2u * level) + 1u;
    }
    const unsigned int field_bits[2] = {GAUSSIAN_TEST_FIELD_BITS, GAUSSIAN_TEST_FIELD_BITS};
    const unsigned int field_offset[2] = {0u, 32u};
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {2u, 0u, 0u};
    EngineError error;
    memset(&error, 0, sizeof(error));
    EngineRecordKey key;
    memset(&key, 0, sizeof(key));
    EngineRecordLayout layout;
    memset(&layout, 0, sizeof(layout));
    CycleRecord *record = NULL;
    const KeymathRecordRequest encode_request = {
        steps, GAUSSIAN_TEST_STEPS, field_bits, 2u, 1u, outputs, GAUSSIAN_TEST_OUTPUTS, NULL, 0u, &key, &error};
    int ok = keymath_record_encode(&encode_request) != KEYMATH_ERROR;
    const KeyScheduleRecordRequest layout_request = {&key, field_offset, 2u, in_limbs, 1, &layout, &error};
    ok = ok && (key_schedule_record_layout(&layout_request) != KEY_SCHEDULE_ERROR);
    // one inverse program for each count of floors, 1 to 8; inverse[0] is unused
    GaussianLoaded inverse[GAUSSIAN_TEST_FLOORS + 1u];
    memset(inverse, 0, sizeof(inverse));
    for (unsigned int floors = 1u; floors <= GAUSSIAN_TEST_FLOORS; floors += 1u)
    {
        ok = ok && gaussian_inverse_build(floors, &inverse[floors], &error);
    }
    // the job declares what the test puts on the device at once: the lanes' fields, their records and the step table,
    // for the wider of the forward floors and the eight inverse floors
    const unsigned int widest_out = (ok != 0) ? ((layout.out_limbs > inverse[GAUSSIAN_TEST_FLOORS].layout.out_limbs)
                                                     ? layout.out_limbs
                                                     : inverse[GAUSSIAN_TEST_FLOORS].layout.out_limbs)
                                              : 0u;
    const unsigned long long declared = ((unsigned long long)GAUSSIAN_TEST_LANES * 2ull * sizeof(unsigned int)) +
                                        ((unsigned long long)GAUSSIAN_TEST_LANES * widest_out * sizeof(unsigned int)) +
                                        ((unsigned long long)GAUSSIAN_TEST_INVERSE_STEPS * sizeof(DeviceRecordStep));
    ok = ok && sim_job_submit(&results, "record_gaussian_test", count, arguments, declared);
    ok = ok && (cycle_record_load(&layout, &record, &error) != CYCLE_ERROR);
    for (unsigned int floors = 1u; floors <= GAUSSIAN_TEST_FLOORS; floors += 1u)
    {
        ok = ok && (cycle_record_load(&inverse[floors].layout, &inverse[floors].record, &error) != CYCLE_ERROR);
    }
    sim_check(&results, ok, "the Gaussian floors and the inverse floors encode, lay out and load");

    // the pair's norm doubles a floor. Its registers widen a bit every second floor: floor k is 24 + ceil(k / 2)
    int widths = ok;
    for (unsigned int level = 1u; (widths != 0) && (level <= GAUSSIAN_TEST_FLOORS); level += 1u)
    {
        const unsigned int need = GAUSSIAN_TEST_FIELD_BITS + ((level + 1u) / 2u);
        widths = (key.term[2u * level].bits == need) && (key.term[(2u * level) + 1u].bits == need);
    }
    sim_check(&results, widths,
              "the encoding widens the pair a bit every second floor: floor k is 24 + ceil(k / 2) bits");

    const unsigned int out_limbs = layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)GAUSSIAN_TEST_LANES * 2u, sizeof(unsigned int));
    long long *const real = (long long *)malloc((size_t)GAUSSIAN_TEST_LANES * sizeof(long long));
    long long *const imaginary = (long long *)malloc((size_t)GAUSSIAN_TEST_LANES * sizeof(long long));
    unsigned int *const host_out =
        (unsigned int *)calloc((size_t)GAUSSIAN_TEST_LANES * out_limbs + 1u, sizeof(unsigned int));
    unsigned int *const device_out =
        (unsigned int *)calloc((size_t)GAUSSIAN_TEST_LANES * out_limbs + 1u, sizeof(unsigned int));
    ok = ok && (atoms != NULL) && (real != NULL) && (imaginary != NULL) && (host_out != NULL) && (device_out != NULL);
    for (unsigned int lane = 0u; (ok != 0) && (lane < GAUSSIAN_TEST_LANES); lane += 1u)
    {
        // every pair of edges meets once, and the rest are drawn
        real[lane] = gaussian_value(lane % 8u);
        imaginary[lane] = gaussian_value((lane / 8u) % 8u);
        atoms[2u * lane] = gaussian_word(real[lane]);
        atoms[(2u * lane) + 1u] = gaussian_word(imaginary[lane]);
    }

    unsigned int *device_atoms = NULL;
    unsigned int *device_record = NULL;
    ok = ok &&
         (cudaMalloc((void **)&device_atoms, (size_t)GAUSSIAN_TEST_LANES * 2u * sizeof(unsigned int)) == cudaSuccess) &&
         (cudaMalloc((void **)&device_record, (size_t)GAUSSIAN_TEST_LANES * out_limbs * sizeof(unsigned int)) ==
          cudaSuccess) &&
         (cudaMemcpy(device_atoms, atoms, (size_t)GAUSSIAN_TEST_LANES * 2u * sizeof(unsigned int),
                     cudaMemcpyHostToDevice) == cudaSuccess);
    if (ok != 0)
    {
        const CycleRecordRunRequest run = {record, {device_atoms, NULL, NULL}, {GAUSSIAN_TEST_LANES, 0ull, 0ull},
                                           NULL,   GAUSSIAN_TEST_LANES,        device_record,
                                           &error};
        ok = (cycle_record_run(&run) == (long)GAUSSIAN_TEST_LANES) &&
             (cudaMemcpy(device_out, device_record, (size_t)GAUSSIAN_TEST_LANES * out_limbs * sizeof(unsigned int),
                         cudaMemcpyDeviceToHost) == cudaSuccess);
    }
    const CycleRecordHostRequest host = {
        &layout, {atoms, NULL, NULL}, {GAUSSIAN_TEST_LANES, 0ull, 0ull}, NULL, GAUSSIAN_TEST_LANES, host_out, &error};
    const int host_ran = (ok != 0) && (cycle_record_run_host(&host) == (long)GAUSSIAN_TEST_LANES);
    sim_check(&results,
              host_ran &&
                  (memcmp(host_out, device_out, (size_t)GAUSSIAN_TEST_LANES * out_limbs * sizeof(unsigned int)) == 0),
              "the device's records equal the host's word for word");

    int product = host_ran;
    int sixteen = host_ran;
    int half_turn = host_ran;
    int parity = host_ran;
    int in_range = host_ran;
    int reached = 0;
    const long long range = 1ll << (GAUSSIAN_TEST_FIELD_BITS + 3u);
    // whether some lane's value at each floor needs every bit of the floor's width: a magnitude of 2^(bits - 1) or more
    int filled[GAUSSIAN_TEST_FLOORS + 1u] = {0};
    for (unsigned int lane = 0u; (host_ran != 0) && (lane < GAUSSIAN_TEST_LANES); lane += 1u)
    {
        const unsigned int *const lane_record = &device_out[(size_t)lane * out_limbs];
        for (unsigned int level = 1u; level <= GAUSSIAN_TEST_FLOORS; level += 1u)
        {
            const DeviceRecordStep *const real_step = &layout.step_table[2u * level];
            const DeviceRecordStep *const imaginary_step = &layout.step_table[(2u * level) + 1u];
            const long long real_at = gaussian_take(lane_record, real_step->out_offset, real_step->out_bits);
            const long long imaginary_at =
                gaussian_take(lane_record, imaginary_step->out_offset, imaginary_step->out_bits);
            // z (1 + i)^k = (a x - b y) + (a y + b x) i, with (1 + i)^k = x + y i
            const long long power_real = s_gaussian_power_real[level];
            const long long power_imaginary = s_gaussian_power_imaginary[level];
            product = product && (real_at == ((real[lane] * power_real) - (imaginary[lane] * power_imaginary))) &&
                      (imaginary_at == ((real[lane] * power_imaginary) + (imaginary[lane] * power_real)));
            // the image of a determinant-2 floor is the pairs of equal parity: one bit dropped a floor
            parity = parity && (((real_at - imaginary_at) % 2ll) == 0ll);
            const long long top = 1ll << (key.term[2u * level].bits - 1u);
            filled[level] = filled[level] || (real_at >= top) || (real_at <= -top) || (imaginary_at >= top) ||
                            (imaginary_at <= -top);
            if (level == 4u)
            {
                half_turn = half_turn && (real_at == (-4ll * real[lane])) && (imaginary_at == (-4ll * imaginary[lane]));
            }
            if (level == GAUSSIAN_TEST_FLOORS)
            {
                sixteen = sixteen && (real_at == (16ll * real[lane])) && (imaginary_at == (16ll * imaginary[lane])) &&
                          ((real_at % 16ll) == 0ll) && ((imaginary_at % 16ll) == 0ll);
                in_range = in_range && (real_at >= -range) && (real_at < range) && (imaginary_at >= -range) &&
                           (imaginary_at < range);
                reached = reached || (real_at == -range) || (imaginary_at == -range);
            }
        }
    }
    sim_check(&results, product, "every floor k is z (1 + i)^k on every lane, against the powers' polar form");
    sim_check(&results, half_turn, "four floors are -4 z on every lane: the turn has gone half way round");
    sim_check(&results, sixteen, "eight floors are 16 z on every lane: the turn closes and one hex digit is moved");
    sim_check(&results, parity,
              "every floor's two registers share their parity on every lane: one bit dropped a floor");
    sim_check(&results, in_range && (reached != 0),
              "floor 8's values lie in [-2^27, 2^27), 28 bits signed, and the most negative field reaches -2^27");
    int every_filled = host_ran;
    for (unsigned int level = 1u; level <= GAUSSIAN_TEST_FLOORS; level += 1u)
    {
        every_filled = every_filled && (filled[level] != 0);
    }
    sim_check(&results, every_filled, "some lane needs every bit of every floor's width: the norm's bound is tight");

    scriptura_text(&results.line, "  the encoding's widths, floors 1 to 8:");
    for (unsigned int level = 1u; (ok != 0) && (level <= GAUSSIAN_TEST_FLOORS); level += 1u)
    {
        scriptura_character(&results.line, ' ');
        scriptura_decimal(&results.line, (unsigned long long)key.term[2u * level].bits, 1u);
    }
    scriptura_text(&results.line, " bits, half a bit a floor, as the values grow\n");

    // eight inverse floors take floor 8's 16 z back through z (1 + i)^(8 - k) to z, on every lane
    const unsigned int inverse_limbs = (ok != 0) ? inverse[GAUSSIAN_TEST_FLOORS].layout.out_limbs : 0u;
    unsigned int *const eight = (unsigned int *)calloc((size_t)GAUSSIAN_TEST_LANES * 2u, sizeof(unsigned int));
    unsigned int *const inverse_host =
        (unsigned int *)calloc((size_t)GAUSSIAN_TEST_LANES * inverse_limbs + 1u, sizeof(unsigned int));
    unsigned int *const inverse_device =
        (unsigned int *)calloc((size_t)GAUSSIAN_TEST_LANES * inverse_limbs + 1u, sizeof(unsigned int));
    int returned = (host_ran != 0) && (eight != NULL) && (inverse_host != NULL) && (inverse_device != NULL);
    const DeviceRecordStep *const eighth_real = &layout.step_table[2u * GAUSSIAN_TEST_FLOORS];
    const DeviceRecordStep *const eighth_imaginary = &layout.step_table[(2u * GAUSSIAN_TEST_FLOORS) + 1u];
    for (unsigned int lane = 0u; (returned != 0) && (lane < GAUSSIAN_TEST_LANES); lane += 1u)
    {
        const unsigned int *const lane_record = &device_out[(size_t)lane * out_limbs];
        // floor 8's values lie in [-2^27, 2^27). Their low 32 bits of two's complement hold the whole value
        eight[2u * lane] = (unsigned int)(unsigned long long)gaussian_take(lane_record, eighth_real->out_offset,
                                                                           eighth_real->out_bits);
        eight[(2u * lane) + 1u] = (unsigned int)(unsigned long long)gaussian_take(
            lane_record, eighth_imaginary->out_offset, eighth_imaginary->out_bits);
    }
    returned = returned && (gaussian_inverse_run(&inverse[GAUSSIAN_TEST_FLOORS], eight, GAUSSIAN_TEST_LANES,
                                                 inverse_host, inverse_device, &error) == 1);
    for (unsigned int lane = 0u; (returned != 0) && (lane < GAUSSIAN_TEST_LANES); lane += 1u)
    {
        const unsigned int *const lane_record = &inverse_device[(size_t)lane * inverse_limbs];
        for (unsigned int level = 1u; level <= GAUSSIAN_TEST_FLOORS; level += 1u)
        {
            const unsigned int at = 3u + (GAUSSIAN_TEST_INVERSE_STEPS_PER_FLOOR * (level - 1u));
            const DeviceRecordStep *const real_step = &inverse[GAUSSIAN_TEST_FLOORS].layout.step_table[at + 2u];
            const DeviceRecordStep *const imaginary_step = &inverse[GAUSSIAN_TEST_FLOORS].layout.step_table[at + 3u];
            const long long real_at = gaussian_take(lane_record, real_step->out_offset, real_step->out_bits);
            const long long imaginary_at =
                gaussian_take(lane_record, imaginary_step->out_offset, imaginary_step->out_bits);
            // k inverse floors from 16 z leave z (1 + i)^(8 - k)
            const long long power_real = s_gaussian_power_real[GAUSSIAN_TEST_FLOORS - level];
            const long long power_imaginary = s_gaussian_power_imaginary[GAUSSIAN_TEST_FLOORS - level];
            returned = returned && (real_at == ((real[lane] * power_real) - (imaginary[lane] * power_imaginary))) &&
                       (imaginary_at == ((real[lane] * power_imaginary) + (imaginary[lane] * power_real)));
        }
    }
    sim_check(&results, returned,
              "eight inverse floors take 16 z back through z (1 + i)^(8 - k) to z on every lane, the host's and the "
              "device's records alike");

    // The chosen pairs, each run alone through j inverse floors for j from 1 to 8: refused exactly where its valuation
    // is below j, and otherwise its every level is z / (1 + i)^k, taken on the CPU by the Gaussian division.
    long long pair_real[GAUSSIAN_TEST_PAIRS];
    long long pair_imaginary[GAUSSIAN_TEST_PAIRS];
    int valued = 1;
    for (unsigned int unit = 0u; unit < GAUSSIAN_TEST_UNITS; unit += 1u)
    {
        // w = a + b i with a - b odd. 1 + i does not divide it: two drawn 20-bit values, b moved to a's other parity
        const long long a = (long long)(gaussian_random() & 0xFFFFFu) - 0x80000ll;
        long long b = (long long)(gaussian_random() & 0xFFFFFu) - 0x80000ll;
        b += (((a - b) % 2ll) == 0ll) ? 1ll : 0ll;
        long long real_part = a;
        long long imaginary_part = b;
        for (unsigned int power = 0u; power < GAUSSIAN_TEST_POWERS; power += 1u)
        {
            const unsigned int index = (unit * GAUSSIAN_TEST_POWERS) + power;
            pair_real[index] = real_part;
            pair_imaginary[index] = imaginary_part;
            valued = valued && (gaussian_valuation(real_part, imaginary_part, GAUSSIAN_TEST_POWERS) == power);
            // z (1 + i) = (a - b) + (a + b) i: below 2^25 in magnitude at the ninth power, inside the 32-bit fields
            const long long next_real = real_part - imaginary_part;
            imaginary_part = real_part + imaginary_part;
            real_part = next_real;
        }
    }
    pair_real[GAUSSIAN_TEST_PAIRS - 1u] = 0ll;
    pair_imaginary[GAUSSIAN_TEST_PAIRS - 1u] = 0ll;
    sim_check(&results, valued, "the chosen pairs w (1 + i)^k have valuation k on the CPU, for k from 0 to 9");
    int agreed = returned;
    int refusals = returned;
    int quotients = returned;
    unsigned long long ran_count = 0ull;
    unsigned long long refused_count = 0ull;
    for (unsigned int floors = 1u; (agreed != 0) && (floors <= GAUSSIAN_TEST_FLOORS); floors += 1u)
    {
        for (unsigned int pair = 0u; (agreed != 0) && (pair < GAUSSIAN_TEST_PAIRS); pair += 1u)
        {
            // each value lies below 2^25 in magnitude. Its low 32 bits of two's complement hold it whole
            const unsigned int atoms_pair[2] = {(unsigned int)(unsigned long long)pair_real[pair],
                                                (unsigned int)(unsigned long long)pair_imaginary[pair]};
            memset(&error, 0, sizeof(error));
            const int ran =
                gaussian_inverse_run(&inverse[floors], atoms_pair, 1u, inverse_host, inverse_device, &error);
            agreed = ran >= 0;
            const int divides =
                gaussian_valuation(pair_real[pair], pair_imaginary[pair], GAUSSIAN_TEST_FLOORS) >= floors;
            refusals = refusals && ((ran == 1) == (divides != 0));
            ran_count += (ran == 1) ? 1ull : 0ull;
            refused_count += (ran == 0) ? 1ull : 0ull;
            long long real_part = pair_real[pair];
            long long imaginary_part = pair_imaginary[pair];
            for (unsigned int level = 1u; (ran == 1) && (level <= floors); level += 1u)
            {
                // z / (1 + i) = z (1 - i) / 2, exact on the pairs of equal parity
                const long long next_real = (real_part + imaginary_part) / 2ll;
                imaginary_part = (imaginary_part - real_part) / 2ll;
                real_part = next_real;
                const unsigned int at = 3u + (GAUSSIAN_TEST_INVERSE_STEPS_PER_FLOOR * (level - 1u));
                const DeviceRecordStep *const real_step = &inverse[floors].layout.step_table[at + 2u];
                const DeviceRecordStep *const imaginary_step = &inverse[floors].layout.step_table[at + 3u];
                quotients = quotients &&
                            (gaussian_take(inverse_device, real_step->out_offset, real_step->out_bits) == real_part) &&
                            (gaussian_take(inverse_device, imaginary_step->out_offset, imaginary_step->out_bits) ==
                             imaginary_part);
            }
        }
    }
    sim_check(&results, agreed, "every run's host and device agree: both refuse the lane, or both run to one record");
    sim_check(&results, refusals,
              "j inverse floors refuse a pair exactly where (1 + i)^j does not divide it: a pair of mixed parity is a "
              "lane the machine refuses");
    sim_check(&results, quotients, "where they run, each level is z / (1 + i)^k, the Gaussian division on the CPU");
    scriptura_text(&results.line, "  the chosen pairs through 1 to 8 inverse floors: ");
    scriptura_decimal(&results.line, ran_count, 1u);
    scriptura_text(&results.line, " runs, ");
    scriptura_decimal(&results.line, refused_count, 1u);
    scriptura_text(&results.line, " refused\n");
    free(eight);
    free(inverse_host);
    free(inverse_device);
    for (unsigned int floors = 1u; floors <= GAUSSIAN_TEST_FLOORS; floors += 1u)
    {
        gaussian_inverse_release(&inverse[floors]);
    }

    cudaFree(device_atoms);
    cudaFree(device_record);
    free(atoms);
    free(real);
    free(imaginary);
    free(host_out);
    free(device_out);
    if (record != NULL)
    {
        cycle_record_release(record);
    }
    key_schedule_record_release(&layout);
    keymath_record_release(&key);
    return sim_close(&results, "record gaussian test");
}
