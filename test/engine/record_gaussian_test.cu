// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The Gaussian step as record floors. BBP's base is a power of the Gaussian prime 1 + i: (1 + i)^8 = 16. One step,
// z -> z (1 + i) on z = a + b i, is the floor (a, b) -> (a - b, a + b): one DIFFERENCE and one SUM. It turns z by
// pi / 4 and scales it by the square root of 2, and its determinant is 2, so each floor drops one bit: its image is
// the pairs of equal parity. Eight floors close the turn and leave 16 z. Every lane runs on the device and on the
// host, word for word, and every floor is checked against the Gaussian product z (1 + i)^k taken on the CPU from the
// powers' polar form, not from the floor. keymath carries every register as a linear form over the two fields and
// bounds it by the sum of |coefficient| 2^bits. After k floors the coefficients are the parts of (1 + i)^k, whose
// magnitudes sum to 2^ceil(k/2), so the widths are 24 + ceil(k/2): they grow half a bit a floor, as the values do, and
// some lane fills each one.
// The test is one job on the device's tessera daemon, submitted before the program is loaded onto the device.
#include "cycle.h"
#include "keymath.h"
#include "key_schedule.h"
#include "sim.h"

#define GAUSSIAN_TEST_LANES 4096u

#define GAUSSIAN_TEST_FLOORS 8u

#define GAUSSIAN_TEST_FIELD_BITS 24u

// the two fields, then a DIFFERENCE and a SUM a floor
#define GAUSSIAN_TEST_STEPS (2u + (2u * GAUSSIAN_TEST_FLOORS))

// both registers of every floor
#define GAUSSIAN_TEST_OUTPUTS (2u * GAUSSIAN_TEST_FLOORS)

// the kinds of field value: 0, -1, 1, the most negative and the most positive, then drawn
#define GAUSSIAN_TEST_EDGES 5u

// (1 + i)^k for k = 0 to 8, read off its polar form 2^(k/2) e^(i k pi / 4)
static const long long s_gaussian_power_real[GAUSSIAN_TEST_FLOORS + 1u] = {1ll, 1ll, 0ll, -2ll, -4ll, -4ll, 0ll, 8ll, 16ll};

static const long long s_gaussian_power_imaginary[GAUSSIAN_TEST_FLOORS + 1u] = {0ll, 1ll, 2ll, 2ll, 0ll, -4ll, -8ll, -8ll,
                                                                                0ll};

static unsigned long long s_gaussian_state = 0x6A09E667F3BCC908ull;

static unsigned int gaussian_random(void)
{
    s_gaussian_state ^= s_gaussian_state << 13u;
    s_gaussian_state ^= s_gaussian_state >> 7u;
    s_gaussian_state ^= s_gaussian_state << 17u;
    // the state's high half is its best mixed, and it is exactly 32 bits
    return (unsigned int)(s_gaussian_state >> 32u);
}

// a signed 24-bit field value of the given kind: an edge, or a drawn word's low 24 bits read back signed
static long long gaussian_value(unsigned int kind)
{
    const long long most = 1ll << (GAUSSIAN_TEST_FIELD_BITS - 1u);
    const long long edges[GAUSSIAN_TEST_EDGES] = {0ll, -1ll, 1ll, -most, most - 1ll};
    if (kind < GAUSSIAN_TEST_EDGES)
    {
        return edges[kind];
    }
    // the masked word is below 2^24, so it widens to long long exactly
    const long long drawn = (long long)(gaussian_random() & ((1u << GAUSSIAN_TEST_FIELD_BITS) - 1u));
    return (drawn >= most) ? (drawn - (2ll * most)) : drawn;
}

// a field's word: the value's low 24 bits of two's complement
static unsigned int gaussian_word(long long value)
{
    // the mask keeps the low 24 bits, which is the field's whole content
    return (unsigned int)((unsigned long long)value & ((1ull << GAUSSIAN_TEST_FIELD_BITS) - 1ull));
}

// `bits` of a record at `offset` as two's complement
static long long gaussian_take(const unsigned int *record, unsigned int offset, unsigned int bits)
{
    unsigned long long word = 0ull;
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int from = offset + bit;
        word |= (unsigned long long)((record[from / 32u] >> (from % 32u)) & 1u) << bit;
    }
    if (((word >> (bits - 1u)) & 1ull) != 0ull)
    {
        word |= ~0ull << bits;
    }
    // the word is the value's two's complement, so the conversion reads it back signed
    return (long long)word;
}

int main(int count, char **arguments)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);

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
    const KeymathRecordRequest imprint = {steps,   GAUSSIAN_TEST_STEPS, field_bits, 2u,   1u,    outputs,
                                          GAUSSIAN_TEST_OUTPUTS, NULL, 0u,          &key, &error};
    int good = keymath_record_imprint(&imprint) != KEYMATH_REFUSED;
    const KeyScheduleRecordRequest lay = {&key, field_offset, 2u, in_limbs, 1, &layout, &error};
    good = good && (key_schedule_record_lay(&lay) != KEY_SCHEDULE_REFUSED);
    // the job declares what the test puts on the device: the lanes' fields, their records and the step table
    const unsigned long long declared = ((unsigned long long)GAUSSIAN_TEST_LANES * 2ull * sizeof(unsigned int))
                                      + ((unsigned long long)GAUSSIAN_TEST_LANES * layout.out_limbs * sizeof(unsigned int))
                                      + ((unsigned long long)GAUSSIAN_TEST_STEPS * sizeof(DeviceRecordStep));
    good = good && sim_job_submit(&tally, "record_gaussian_test", count, arguments, declared);
    good = good && (cycle_record_load(&layout, &record, &error) != CYCLE_REFUSED);
    sim_check(&tally, good, "the Gaussian floors imprint, lay and load");

    // the pair's norm doubles a floor, so its registers widen a bit every second floor: floor k is 24 + ceil(k / 2)
    int widths = good;
    for (unsigned int level = 1u; (widths != 0) && (level <= GAUSSIAN_TEST_FLOORS); level += 1u)
    {
        const unsigned int need = GAUSSIAN_TEST_FIELD_BITS + ((level + 1u) / 2u);
        widths = (key.term[2u * level].bits == need) && (key.term[(2u * level) + 1u].bits == need);
    }
    sim_check(&tally, widths, "the imprint widens the pair a bit every second floor: floor k is 24 + ceil(k / 2) bits");

    const unsigned int out_limbs = layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)GAUSSIAN_TEST_LANES * 2u, sizeof(unsigned int));
    long long *const real = (long long *)malloc((size_t)GAUSSIAN_TEST_LANES * sizeof(long long));
    long long *const imaginary = (long long *)malloc((size_t)GAUSSIAN_TEST_LANES * sizeof(long long));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)GAUSSIAN_TEST_LANES * out_limbs + 1u,
                                                          sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)GAUSSIAN_TEST_LANES * out_limbs + 1u,
                                                            sizeof(unsigned int));
    good = good && (atoms != NULL) && (real != NULL) && (imaginary != NULL) && (host_out != NULL)
        && (device_out != NULL);
    for (unsigned int lane = 0u; (good != 0) && (lane < GAUSSIAN_TEST_LANES); lane += 1u)
    {
        // every pair of edges meets once, and the rest are drawn
        real[lane] = gaussian_value(lane % 8u);
        imaginary[lane] = gaussian_value((lane / 8u) % 8u);
        atoms[2u * lane] = gaussian_word(real[lane]);
        atoms[(2u * lane) + 1u] = gaussian_word(imaginary[lane]);
    }

    unsigned int *device_atoms = NULL;
    unsigned int *device_record = NULL;
    good = good
        && (cudaMalloc((void **)&device_atoms, (size_t)GAUSSIAN_TEST_LANES * 2u * sizeof(unsigned int)) == cudaSuccess)
        && (cudaMalloc((void **)&device_record, (size_t)GAUSSIAN_TEST_LANES * out_limbs * sizeof(unsigned int))
            == cudaSuccess)
        && (cudaMemcpy(device_atoms, atoms, (size_t)GAUSSIAN_TEST_LANES * 2u * sizeof(unsigned int),
                       cudaMemcpyHostToDevice)
            == cudaSuccess);
    if (good != 0)
    {
        const CycleRecordRunRequest run = {record, {device_atoms, NULL, NULL}, {GAUSSIAN_TEST_LANES, 0ull, 0ull}, NULL,
                                           GAUSSIAN_TEST_LANES, device_record, &error};
        good = (cycle_record_run(&run) == (long)GAUSSIAN_TEST_LANES)
            && (cudaMemcpy(device_out, device_record, (size_t)GAUSSIAN_TEST_LANES * out_limbs * sizeof(unsigned int),
                           cudaMemcpyDeviceToHost)
                == cudaSuccess);
    }
    const CycleRecordHostRequest host = {&layout, {atoms, NULL, NULL}, {GAUSSIAN_TEST_LANES, 0ull, 0ull}, NULL,
                                         GAUSSIAN_TEST_LANES, host_out, &error};
    const int host_ran = (good != 0) && (cycle_record_run_host(&host) == (long)GAUSSIAN_TEST_LANES);
    sim_check(&tally, host_ran
                          && (memcmp(host_out, device_out, (size_t)GAUSSIAN_TEST_LANES * out_limbs * sizeof(unsigned int))
                              == 0),
              "the device's records equal the host's word for word");

    int product = host_ran;
    int sixteen = host_ran;
    int half_turn = host_ran;
    int parity = host_ran;
    int in_range = host_ran;
    int reached = 0;
    const long long reach = 1ll << (GAUSSIAN_TEST_FIELD_BITS + 3u);
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
            const long long imaginary_at = gaussian_take(lane_record, imaginary_step->out_offset,
                                                         imaginary_step->out_bits);
            // z (1 + i)^k = (a x - b y) + (a y + b x) i, with (1 + i)^k = x + y i
            const long long power_real = s_gaussian_power_real[level];
            const long long power_imaginary = s_gaussian_power_imaginary[level];
            product = product && (real_at == ((real[lane] * power_real) - (imaginary[lane] * power_imaginary)))
                   && (imaginary_at == ((real[lane] * power_imaginary) + (imaginary[lane] * power_real)));
            // the image of a determinant-2 floor is the pairs of equal parity: one bit dropped a floor
            parity = parity && (((real_at - imaginary_at) % 2ll) == 0ll);
            const long long top = 1ll << (key.term[2u * level].bits - 1u);
            filled[level] = filled[level] || (real_at >= top) || (real_at <= -top) || (imaginary_at >= top)
                         || (imaginary_at <= -top);
            if (level == 4u)
            {
                half_turn = half_turn && (real_at == (-4ll * real[lane])) && (imaginary_at == (-4ll * imaginary[lane]));
            }
            if (level == GAUSSIAN_TEST_FLOORS)
            {
                sixteen = sixteen && (real_at == (16ll * real[lane])) && (imaginary_at == (16ll * imaginary[lane]))
                       && ((real_at % 16ll) == 0ll) && ((imaginary_at % 16ll) == 0ll);
                in_range = in_range && (real_at >= -reach) && (real_at < reach) && (imaginary_at >= -reach)
                        && (imaginary_at < reach);
                reached = reached || (real_at == -reach) || (imaginary_at == -reach);
            }
        }
    }
    sim_check(&tally, product, "every floor k is z (1 + i)^k on every lane, against the powers' polar form");
    sim_check(&tally, half_turn, "four floors are -4 z on every lane: the turn has gone half way round");
    sim_check(&tally, sixteen, "eight floors are 16 z on every lane: the turn closes and one hex digit is moved");
    sim_check(&tally, parity, "every floor's two registers share their parity on every lane: one bit dropped a floor");
    sim_check(&tally, in_range && (reached != 0),
              "floor 8's values lie in [-2^27, 2^27), 28 bits signed, and the most negative field reaches -2^27");
    int every_filled = host_ran;
    for (unsigned int level = 1u; level <= GAUSSIAN_TEST_FLOORS; level += 1u)
    {
        every_filled = every_filled && (filled[level] != 0);
    }
    sim_check(&tally, every_filled, "some lane needs every bit of every floor's width: the norm's bound is tight");

    scriptura_text(&tally.line, "  the imprint's widths, floors 1 to 8:");
    for (unsigned int level = 1u; (good != 0) && (level <= GAUSSIAN_TEST_FLOORS); level += 1u)
    {
        scriptura_character(&tally.line, ' ');
        scriptura_decimal(&tally.line, (unsigned long long)key.term[2u * level].bits, 1u);
    }
    scriptura_text(&tally.line, " bits, half a bit a floor, as the values grow\n");

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
    return sim_close(&tally, "record gaussian test");
}
