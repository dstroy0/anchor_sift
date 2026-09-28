// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_tower_bbp_plan.cu: the BBP program laid out and planned
#include "pi_tower_internal.h"

// the four denominators' offsets, 8 i + j
static const unsigned int s_pi_tower_bbp_offset[4] = {1u, 4u, 5u, 6u};

// keymath encodes the program, its last step the output, and the scheduler lays out its registers, each reused once its
// last reader has run
static int pi_tower_program_build(PiTowerProgram *program, const std::vector<EngineRecordStep> &steps,
                                  const unsigned int *field_bits, unsigned int members, const unsigned int *in_limbs,
                                  const EngineRecordTable *tables, unsigned int table_count, EngineError *error)
{
    memset(program, 0, sizeof(*program));
    // a program's steps are counted in an unsigned int, as keymath counts them
    const unsigned int count = (unsigned int)steps.size();
    const unsigned int output = count - 1u;
    const unsigned int field_offset[1] = {0u};
    const KeymathRecordRequest encode_request = {steps.data(), count,       field_bits,    1u,   members, &output, 1u,
                                                 tables,       table_count, &program->key, error};
    if (keymath_record_encode(&encode_request) == KEYMATH_ERROR)
    {
        return 0;
    }
    const KeyScheduleRecordRequest layout_request = {&program->key,    field_offset, 1u, in_limbs, 1,
                                                     &program->layout, error};
    if (key_schedule_record_layout(&layout_request) == KEY_SCHEDULE_ERROR)
    {
        keymath_record_release(&program->key);
        return 0;
    }
    return 1;
}

static void pi_tower_program_free(PiTowerProgram *program)
{
    cycle_record_release(program->record);
    key_schedule_record_release(&program->layout);
    keymath_record_release(&program->key);
    program->record = NULL;
}

void pi_tower_bbp_free(PiTowerBbp *bbp)
{
    pi_tower_program_free(&bbp->term);
    pi_tower_program_free(&bbp->tail);
    pi_tower_program_free(&bbp->pair);
}

// the term lane: field 0 is i
static int pi_tower_bbp_term_build(PiTowerBbp *bbp, EngineError *error)
{
    std::vector<EngineRecordStep> steps;
    const unsigned int index = pi_tower_field(&steps, 0u, 0u);
    const unsigned int position = pi_tower_constant(&steps, bbp->position);
    const unsigned int exponent = pi_tower_step(&steps, ENGINE_RECORD_DIFFERENCE, position, index);
    const unsigned int nibbles = (bbp->position_bits + 3u) / 4u;
    // 16^nibbles stands above every exponent. A quotient by any lower power of 16 keeps a whole nibble to index by
    const unsigned int above = pi_tower_constant(&steps, pi_tower_power_two(4u * nibbles));
    const unsigned int guarded = pi_tower_step(&steps, ENGINE_RECORD_SUM, exponent, above);
    const unsigned int eight = pi_tower_step(&steps, ENGINE_RECORD_CONSTANT, 8u, 0u);
    const unsigned int eighth = pi_tower_step(&steps, ENGINE_RECORD_PRODUCT, eight, index);
    const unsigned int one = pi_tower_step(&steps, ENGINE_RECORD_CONSTANT, 1u, 0u);
    unsigned int modulus[4];
    unsigned int residue[4];
    for (unsigned int kind = 0u; kind < 4u; kind += 1u)
    {
        const unsigned int offset = pi_tower_step(&steps, ENGINE_RECORD_CONSTANT, s_pi_tower_bbp_offset[kind], 0u);
        modulus[kind] = pi_tower_step(&steps, ENGINE_RECORD_SUM, eighth, offset);
        residue[kind] = one;
    }
    // 16^e from the top nibble down: r becomes r^16 . 16^(the nibble), each square and product taken mod 8 i + j
    for (unsigned int nibble = nibbles; nibble > 0u; nibble -= 1u)
    {
        const unsigned int place = pi_tower_constant(&steps, pi_tower_power_two(4u * (nibble - 1u)));
        const unsigned int digit = pi_tower_step(&steps, ENGINE_RECORD_QUOTIENT, guarded, place);
        const unsigned int power = pi_tower_step(&steps, ENGINE_RECORD_TABLE, digit, 0u);
        for (unsigned int kind = 0u; kind < 4u; kind += 1u)
        {
            for (unsigned int square = 0u; square < 4u; square += 1u)
            {
                const unsigned int squared = pi_tower_step(&steps, ENGINE_RECORD_PRODUCT, residue[kind], residue[kind]);
                residue[kind] = pi_tower_step(&steps, ENGINE_RECORD_REMAINDER, squared, modulus[kind]);
            }
            const unsigned int raised = pi_tower_step(&steps, ENGINE_RECORD_PRODUCT, residue[kind], power);
            residue[kind] = pi_tower_step(&steps, ENGINE_RECORD_REMAINDER, raised, modulus[kind]);
        }
    }
    const unsigned int unit = pi_tower_constant(&steps, pi_tower_power_two(bbp->fraction_bits));
    unsigned int fraction[4];
    for (unsigned int kind = 0u; kind < 4u; kind += 1u)
    {
        const unsigned int scaled = pi_tower_step(&steps, ENGINE_RECORD_PRODUCT, residue[kind], unit);
        fraction[kind] = pi_tower_step(&steps, ENGINE_RECORD_QUOTIENT, scaled, modulus[kind]);
    }
    pi_tower_bbp_combine(&steps, fraction, bbp->fraction_bits);
    // 16^v for a nibble v, below 2^61
    unsigned int values[32];
    for (unsigned int row = 0u; row < 16u; row += 1u)
    {
        const unsigned long long power = 1ull << (4u * row);
        // the low and high halves of the word each fit a limb
        values[2u * row] = (unsigned int)(power & 0xFFFFFFFFull);
        values[(2u * row) + 1u] = (unsigned int)(power >> 32u);
    }
    const EngineRecordTable table = {4u, 61u, values};
    const unsigned int field_bits[1] = {bbp->position_bits};
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {bbp->in_limbs, 0u, 0u};
    return pi_tower_program_build(&bbp->term, steps, field_bits, 1u, in_limbs, &table, 1u, error);
}

// the tail lane: field 0 is t, the term d + t
static int pi_tower_bbp_tail_build(PiTowerBbp *bbp, EngineError *error)
{
    std::vector<EngineRecordStep> steps;
    const unsigned int ahead = pi_tower_field(&steps, 0u, 0u);
    const unsigned int position = pi_tower_constant(&steps, bbp->position);
    const unsigned int index = pi_tower_step(&steps, ENGINE_RECORD_SUM, position, ahead);
    const unsigned int eight = pi_tower_step(&steps, ENGINE_RECORD_CONSTANT, 8u, 0u);
    const unsigned int eighth = pi_tower_step(&steps, ENGINE_RECORD_PRODUCT, eight, index);
    const unsigned int scale = pi_tower_step(&steps, ENGINE_RECORD_TABLE, ahead, 0u);
    const unsigned int unit = pi_tower_constant(&steps, pi_tower_power_two(bbp->fraction_bits));
    unsigned int fraction[4];
    for (unsigned int kind = 0u; kind < 4u; kind += 1u)
    {
        const unsigned int offset = pi_tower_step(&steps, ENGINE_RECORD_CONSTANT, s_pi_tower_bbp_offset[kind], 0u);
        const unsigned int modulus = pi_tower_step(&steps, ENGINE_RECORD_SUM, eighth, offset);
        const unsigned int below = pi_tower_step(&steps, ENGINE_RECORD_PRODUCT, modulus, scale);
        fraction[kind] = pi_tower_step(&steps, ENGINE_RECORD_QUOTIENT, unit, below);
    }
    pi_tower_bbp_combine(&steps, fraction, bbp->fraction_bits);
    // 16^v for every v the tail's field can hold
    const unsigned int rows = 1u << bbp->tail_bits;
    const unsigned int out_bits = (4u * (rows - 1u)) + 1u;
    const unsigned int row_limbs = (out_bits + 31u) / 32u;
    std::vector<unsigned int> values((size_t)rows * row_limbs, 0u);
    for (unsigned int row = 0u; row < rows; row += 1u)
    {
        values[((size_t)row * row_limbs) + ((4u * row) / 32u)] = 1u << ((4u * row) % 32u);
    }
    const EngineRecordTable table = {bbp->tail_bits, out_bits, values.data()};
    const unsigned int field_bits[1] = {bbp->tail_bits};
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {1u, 0u, 0u};
    return pi_tower_program_build(&bbp->tail, steps, field_bits, 1u, in_limbs, &table, 1u, error);
}

// the pair lane: two lanes' sums, members 0 and 1, added mod 2^W
static int pi_tower_bbp_pair_build(PiTowerBbp *bbp, EngineError *error)
{
    std::vector<EngineRecordStep> steps;
    const unsigned int left = pi_tower_field(&steps, 0u, 0u);
    const unsigned int right = pi_tower_field(&steps, 0u, 1u);
    const unsigned int sum = pi_tower_step(&steps, ENGINE_RECORD_SUM, left, right);
    pi_tower_step(&steps, ENGINE_RECORD_WRAP, sum, bbp->fraction_bits);
    const unsigned int field_bits[1] = {bbp->fraction_bits + 1u};
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {bbp->out_limbs, bbp->out_limbs, 0u};
    return pi_tower_program_build(&bbp->pair, steps, field_bits, 2u, in_limbs, NULL, 0u, error);
}

// E = 4 (N + T) + 1: each of the N + T lanes floors four fractions weighted 4, 2, 1 and 1, off by less than 4 units
// either way, and the terms past the tail add less than 1
PiWide pi_tower_bbp_error(const PiTowerBbp *bbp)
{
    const PiWide lanes = pi_tower_sum(bbp->terms, pi_tower_unsigned(bbp->tail_terms));
    return pi_tower_sum(pi_tower_product(lanes, pi_tower_unsigned(4ull)), pi_tower_unsigned(1ull));
}

// the run at hex position d, from d alone: W holds PI_TOWER_BBP_CERTIFIED bits past the error with PI_TOWER_BBP_GUARD
// to spare, and the tail runs until 16^T >= 2^(W + 8)
int pi_tower_bbp_plan(PiTowerBbp *bbp, const PiWide &position, unsigned long long lanes, EngineError *error)
{
    memset(bbp, 0, sizeof(*bbp));
    bbp->position = position;
    bbp->terms = pi_tower_sum(position, pi_tower_unsigned(1ull));
    const unsigned int position_bits = pi_tower_bit_length(position);
    bbp->position_bits = (position_bits == 0u) ? 1u : position_bits;
    bbp->lanes = lanes;
    for (unsigned int limbs = 2u;; limbs += 1u)
    {
        bbp->fraction_bits = (32u * limbs) - 1u;
        bbp->tail_terms = (bbp->fraction_bits + 11u) / 4u;
        bbp->out_limbs = limbs;
        if (bbp->fraction_bits >=
            (PI_TOWER_BBP_CERTIFIED + PI_TOWER_BBP_GUARD + pi_tower_bit_length(pi_tower_bbp_error(bbp))))
        {
            break;
        }
    }
    bbp->tail_bits = pi_tower_bit_length(pi_tower_unsigned(bbp->tail_terms));
    bbp->in_limbs = (bbp->position_bits + 31u) / 32u;
    if (pi_tower_bbp_term_build(bbp, error) == 0)
    {
        return 0;
    }
    if (pi_tower_bbp_tail_build(bbp, error) == 0)
    {
        pi_tower_program_free(&bbp->term);
        return 0;
    }
    if (pi_tower_bbp_pair_build(bbp, error) == 0)
    {
        pi_tower_program_free(&bbp->term);
        pi_tower_program_free(&bbp->tail);
        return 0;
    }
    return 1;
}

// the device bytes a run holds: its lanes' inputs, two buffers of sums, the pair program's index, the total, and the
// three programs' step tables and lookup tables
unsigned long long pi_tower_bbp_bytes(const PiTowerBbp *bbp)
{
    const unsigned long long buffer_words = (bbp->lanes + 1ull) * bbp->out_limbs;
    const unsigned long long steps =
        (unsigned long long)bbp->term.layout.steps + bbp->tail.layout.steps + bbp->pair.layout.steps;
    const unsigned long long tables = bbp->term.layout.table_word_count + bbp->tail.layout.table_word_count;
    return (((bbp->lanes * bbp->in_limbs) + (2ull * buffer_words) + (bbp->lanes + 1ull) + bbp->out_limbs + tables) *
            sizeof(unsigned int)) +
           (steps * sizeof(DeviceRecordStep));
}

// every lane's integer, first + lane, in limbs of 32 bits from the low
static __global__ void pi_tower_bbp_count(unsigned int *out, unsigned long long count, unsigned int limbs,
                                          unsigned long long first)
{
    const unsigned long long stride = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long lane = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; lane < count;
         lane += stride)
    {
        const unsigned long long value = first + lane;
        unsigned int *const place = &out[lane * limbs];
        // the low and high halves of the word each fit a limb
        place[0] = (unsigned int)(value & 0xFFFFFFFFull);
        for (unsigned int limb = 1u; limb < limbs; limb += 1u)
        {
            place[limb] = (limb == 1u) ? (unsigned int)(value >> 32u) : 0u;
        }
    }
}

int pi_tower_bbp_counted(SimResults *results, unsigned int *out, unsigned long long count, unsigned int limbs,
                         unsigned long long first)
{
    const unsigned long long blocks = sim_launch_blocks(count, 256ull);
    // at most 4096 blocks. The count fits an unsigned int
    pi_tower_bbp_count<<<(unsigned int)((blocks < 4096ull) ? blocks : 4096ull), 256u>>>(out, count, limbs, first);
    return sim_status_check(results, cudaGetLastError(), "engine: the lanes' integers");
}

// the sums of count lanes in buffers[0], reduced to one by rounds of the pair program, the buffers taking turns; the
// buffer the one sum lands in, or NULL
unsigned int *pi_tower_bbp_reduce(SimResults *results, const PiTowerBbp *bbp, unsigned int *const *buffers,
                                  const unsigned int *index, unsigned long long count, EngineError *error)
{
    unsigned int from = 0u;
    unsigned long long left = count;
    while (left > 1ull)
    {
        const unsigned long long pairs = left / 2ull;
        // lane k reads index 2 k and 2 k + 1, lanes 2 k and 2 k + 1 of the buffer
        const CycleRecordRunRequest run = {bbp->pair.record,
                                           {buffers[from], buffers[from], NULL},
                                           {left, left, 0ull},
                                           index,
                                           pairs,
                                           buffers[1u - from],
                                           error};
        if (cycle_record_run(&run) == CYCLE_ERROR)
        {
            sim_check(results, 0, "engine: the pair program adds a sweep's lanes");
            return NULL;
        }
        // the odd lane out rides into the next round unpaired
        if (((left & 1ull) != 0ull) &&
            !sim_status_check(results,
                              cudaMemcpy(&buffers[1u - from][pairs * bbp->out_limbs],
                                         &buffers[from][(left - 1ull) * bbp->out_limbs],
                                         bbp->out_limbs * sizeof(unsigned int), cudaMemcpyDeviceToDevice),
                              "engine: the odd lane"))
        {
            return NULL;
        }
        left = pairs + (left & 1ull);
        from = 1u - from;
    }
    return buffers[from];
}

// the sum read from the device: the pair program's two's complement over W + 1 bits, taken mod 2^W
int pi_tower_bbp_read(SimResults *results, const PiTowerBbp *bbp, const unsigned int *total, PiWide *sum)
{
    std::vector<unsigned int> limbs(bbp->out_limbs, 0u);
    if (!sim_status_check(
            results, cudaMemcpy(limbs.data(), total, bbp->out_limbs * sizeof(unsigned int), cudaMemcpyDeviceToHost),
            "engine: the sum read back"))
    {
        return 0;
    }
    anchor_exact_zero(sum);
    int zero = 1;
    for (unsigned int limb = 0u; limb < bbp->out_limbs; limb += 1u)
    {
        sum->limb[limb] = limbs[limb];
    }
    // W = 32 k - 1. The sign's bit W is the top limb's top bit
    sum->limb[bbp->out_limbs - 1u] &= 0x7FFFFFFFu;
    for (unsigned int limb = 0u; limb < bbp->out_limbs; limb += 1u)
    {
        zero = zero && (sum->limb[limb] == 0u);
    }
    sum->sign = (zero != 0) ? 0 : 1;
    return 1;
}

// a progress line: the terms done, the rate, and what is left at that rate
void pi_tower_bbp_progress(SimResults *results, const PiTowerBbp *bbp, const PiTowerBbpRun *run)
{
    // a run's seconds are non-negative and far below 2^64 microseconds. The floor fits the word
    const unsigned long long micros = (unsigned long long)(run->seconds * 1000000.0);
    const PiWide left = pi_tower_difference(bbp->terms, pi_tower_unsigned(run->done));
    scriptura_text(&results->line, "    ");
    pi_tower_print_decimal(&results->line, pi_tower_unsigned(run->done));
    scriptura_text(&results->line, " of ");
    pi_tower_print_decimal(&results->line, bbp->terms);
    scriptura_text(&results->line, " terms in ");
    scriptura_decimal(&results->line, run->sweeps, 1u);
    scriptura_text(&results->line, " cycles and ");
    sim_fraction_print(&results->line, micros, 1000000ull, 3u);
    scriptura_text(&results->line, " s, ");
    pi_tower_print_exponent(&results->line,
                            pi_tower_product(pi_tower_unsigned(run->done), pi_tower_unsigned(1000000ull)),
                            pi_tower_unsigned((micros == 0ull) ? 1ull : micros));
    scriptura_text(&results->line, " terms a second");
    if ((left.sign != 0) && (run->done != 0ull))
    {
        // the years left: left . micros / (done . 10^6 . 31557600)
        scriptura_text(&results->line, "; ");
        pi_tower_print_exponent(&results->line, left, pi_tower_unsigned(1ull));
        scriptura_text(&results->line, " left, ");
        pi_tower_print_exponent(&results->line, pi_tower_product(left, pi_tower_unsigned(micros)),
                                pi_tower_product(pi_tower_unsigned(run->done), pi_tower_unsigned(31557600000000ull)));
        scriptura_text(&results->line, " years at this rate");
    }
    scriptura_character(&results->line, '\n');
    sim_flush(results);
}
