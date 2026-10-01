// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_tower_test_ruleset.cu: matches, rulesets, the operation stack, blocks, errors and main
#include "record_tower_test_internal.h"

// t, z, y and x: a line of 64, a cube of 4, blocks with odd extents on every axis, a block on all four axes, and one
// sample, which no level lifts
static const unsigned long long s_tower_test_extent[TOWER_TEST_BLOCKS][4] = {
    {1ull, 1ull, 1ull, 64ull}, {1ull, 4ull, 4ull, 4ull}, {2ull, 3ull, 4ull, 4ull}, {1ull, 3ull, 5ull, 7ull},
    {3ull, 1ull, 2ull, 9ull},  {2ull, 2ull, 2ull, 2ull}, {1ull, 1ull, 1ull, 1ull}};

// the S transform: the highs less their even neighbor, the lows plus half the high beside them, floored
static const TowerLiftingStep s_tower_test_s_transform[2] = {{TOWER_BAND_HIGH, -1, 1u, {0}, {1}, 0u, 0u},
                                                             {TOWER_BAND_LOW, 1, 1u, {0}, {1}, 0u, 1u}};

// a four-tap predict, the highs less floor((9 (x_2j + x_(2j+2)) - (x_(2j-2) + x_(2j+4)) + 8) / 16), then the 5/3's
// update
static const TowerLiftingStep s_tower_test_four_tap[2] = {
    {TOWER_BAND_HIGH, -1, 4u, {-1, 0, 1, 2}, {-1, 9, 9, -1}, 8u, 4u}, {TOWER_BAND_LOW, 1, 2u, {-1, 0}, {1, 1}, 2u, 2u}};

static const TowerTestRuleset s_tower_test_ruleset[TOWER_TEST_RULESETS] = {
    {"the kernels' 5/3, no ruleset named", NULL, 0u, 1},
    {"the 5/3 named as its two steps", s_tower_test_five_three, 2u, 1},
    {"the S transform", s_tower_test_s_transform, 2u, 0},
    {"a four-tap predict and the 5/3's update", s_tower_test_four_tap, 2u, 0}};

// how many volumes' records hold, at the registers named, the values expected of them
static unsigned int tower_test_matches(const TowerTestLoaded *loaded, const std::vector<unsigned int> &out,
                                       const std::vector<unsigned int> &registers,
                                       const std::vector<long long> &expected, unsigned int volumes)
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
            equal = equal && (tower_test_take(record, &loaded->layout.step_table[registers[position]]) ==
                              expected[((size_t)volume * lanes) + position]);
        }
        matched += (equal != 0) ? 1u : 0u;
    }
    return matched;
}

// one ruleset on one block: T against the kernels or the oracle, T^-1 on that crystal against the source, and T read
// through T^-1 on drawn crystals
static void tower_test_ruleset(SimResults *results, const unsigned long long extent[4], const TowerTestRuleset *ruleset,
                               const std::vector<unsigned short> &source, const std::vector<int> &kernel_crystal)
{
    ScripturaLine *const line = &results->line;
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
    int ok = tower_test_build(extent, ruleset, 0, samples, coefficients, lift_steps) &&
             tower_test_load(lift_steps, coefficients, sample_bits, &lift);
    std::vector<unsigned int> atoms(source.begin(), source.end());
    std::vector<unsigned int> out;
    ok = ok && tower_test_run(&lift, atoms, volumes, out);
    sim_check(results, ok,
              "T is emitted as sized, encodes, lays out and loads, and the device's records equal the host's");
    const unsigned int lift_equal = (ok != 0) ? tower_test_matches(&lift, out, coefficients, crystal, volumes) : 0u;
    sim_check(results, lift_equal == volumes,
              (ruleset->kernels != 0) ? "T's record floors equal tower_lift's crystal at every coefficient"
                                      : "T's record floors equal the oracle's crystal at every coefficient");
    // each coefficient's field for T^-1: its register's width and a sign bit
    std::vector<unsigned int> crystal_bits(lanes, 32u);
    unsigned int widest = 0u;
    for (unsigned int position = 0u; (ok != 0) && (position < lanes); position += 1u)
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
    ok = tower_test_build(extent, ruleset, 1, samples, rebuilt_registers, lower_steps) &&
         tower_test_load(lower_steps, rebuilt_registers, crystal_bits, &lower);
    for (size_t at = 0u; at < atoms.size(); at += 1u)
    {
        // a coefficient's two's complement word, whose low field bits the signed field reads
        atoms[at] = (unsigned int)crystal[at];
    }
    ok = ok && tower_test_run(&lower, atoms, volumes, out);
    sim_check(results, ok,
              "T^-1 is emitted as sized, encodes, lays out and loads, and the device's records equal the host's");
    const unsigned int lower_equal =
        (ok != 0) ? tower_test_matches(&lower, out, rebuilt_registers, sample_values, volumes) : 0u;
    sim_check(results, lower_equal == volumes, "T^-1's record floors return the source at every sample");
    const unsigned int lower_limbs = lower.layout.file_limbs;
    // a program's step count here is far below 2^32
    const unsigned int lower_count = (unsigned int)(lower_steps.size() - lanes);
    tower_test_free(&lower);

    // T read through T^-1 as one stack, on crystals drawn anywhere in the fields' widths
    std::vector<EngineRecordStep> round_steps = tower_test_fields(lanes, ENGINE_RECORD_FIELD_SIGNED);
    std::vector<unsigned int> middle;
    std::vector<unsigned int> returned;
    TowerTestLoaded round = {};
    ok = tower_test_build(extent, ruleset, 1, samples, middle, round_steps) &&
         tower_test_build(extent, ruleset, 0, middle, returned, round_steps) &&
         tower_test_load(round_steps, returned, crystal_bits, &round);
    std::vector<long long> drawn(atoms.size());
    for (size_t at = 0u; at < atoms.size(); at += 1u)
    {
        atoms[at] = tower_test_random();
        drawn[at] = tower_test_signed(atoms[at], crystal_bits[at % lanes]);
    }
    ok = ok && tower_test_run(&round, atoms, volumes, out);
    sim_check(results, ok,
              "T . T^-1 encodes, lays out and loads as one program, and the device's records equal the host's");
    const unsigned int round_equal = (ok != 0) ? tower_test_matches(&round, out, returned, drawn, volumes) : 0u;
    sim_check(results, round_equal == volumes, "T . T^-1 returns every drawn crystal exactly, as one stack");
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
    scriptura_text(line,
                   (ruleset->kernels != 0) ? " volumes, T equals tower_lift on " : " volumes, T equals the oracle on ");
    scriptura_decimal(line, lift_equal, 1u);
    scriptura_text(line, ", T^-1 returns the source on ");
    scriptura_decimal(line, lower_equal, 1u);
    scriptura_text(line, ", T . T^-1 returns ");
    scriptura_decimal(line, round_equal, 1u);
    scriptura_text(line, " drawn crystals\n");
    sim_flush(results);
}

// F read through T^-1 as one stack, on the kernels' crystal: the block's sum, and its energy along x where x has
// neighbors, against F on tower_lower's samples
static void tower_test_operation_stack(SimResults *results, const unsigned long long extent[4],
                                       const std::vector<int> &kernel_crystal,
                                       const std::vector<unsigned short> &rebuilt,
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
    int ok = tower_test_build(extent, &s_tower_test_ruleset[0], 1, samples, read_back, steps);
    unsigned int sum = read_back[0];
    unsigned int energy = 0u;
    int energy_ok = 0;
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
            steps.push_back(
                EngineRecordStep{ENGINE_RECORD_DIFFERENCE, read_back[position + 1u], read_back[position], 0u});
            const unsigned int difference = (unsigned int)(steps.size() - 1u);
            steps.push_back(EngineRecordStep{ENGINE_RECORD_PRODUCT, difference, difference, 0u});
            const unsigned int square = (unsigned int)(steps.size() - 1u);
            if (energy_ok != 0)
            {
                steps.push_back(EngineRecordStep{ENGINE_RECORD_SUM, energy, square, 0u});
                energy = (unsigned int)(steps.size() - 1u);
            }
            else
            {
                energy = square;
                energy_ok = 1;
            }
        }
    }
    std::vector<unsigned int> outputs(1u, sum);
    if (energy_ok != 0)
    {
        outputs.push_back(energy);
    }
    TowerTestLoaded operation = {};
    ok = ok && tower_test_load(steps, outputs, crystal_bits, &operation);
    std::vector<unsigned int> atoms(kernel_crystal.size());
    for (size_t at = 0u; at < atoms.size(); at += 1u)
    {
        // a coefficient's two's complement word, whose low field bits the signed field reads
        atoms[at] = (unsigned int)kernel_crystal[at];
    }
    std::vector<unsigned int> out;
    ok = ok && tower_test_run(&operation, atoms, volumes, out);
    sim_check(results, ok,
              "F . T^-1 encodes, lays out and loads as one program, and the device's records equal the host's");
    unsigned int matched = 0u;
    for (unsigned int volume = 0u; (ok != 0) && (volume < volumes); volume += 1u)
    {
        const unsigned int *const record = &out[(size_t)volume * operation.layout.out_limbs];
        long long host_sum = 0ll;
        long long host_energy = 0ll;
        tower_test_operation(extent, &rebuilt[(size_t)volume * lanes], lanes, &host_sum, &host_energy);
        int equal = tower_test_take(record, &operation.layout.step_table[sum]) == host_sum;
        if (energy_ok != 0)
        {
            equal = equal && (tower_test_take(record, &operation.layout.step_table[energy]) == host_energy);
        }
        matched += (equal != 0) ? 1u : 0u;
    }
    sim_check(results, matched == volumes,
              "F . T^-1 equals F taken on tower_lower's samples: the block's sum and its energy along x");
    scriptura_text(&results->line, "    F . T^-1, the block's sum and its energy along x: ");
    scriptura_decimal(&results->line, steps.size(), 1u);
    scriptura_text(&results->line, " steps in one program, a file of ");
    scriptura_decimal(&results->line, operation.layout.file_limbs, 1u);
    scriptura_text(&results->line, " limbs; equal to F on tower_lower's samples on ");
    scriptura_decimal(&results->line, matched, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, volumes, 1u);
    scriptura_text(&results->line, " volumes\n");
    tower_test_free(&operation);
}

static void tower_test_block(SimResults *results, const unsigned long long extent[4], unsigned short *device_volume)
{
    ScripturaLine *const line = &results->line;
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
    sim_check(results, kernels, "tower_lift and tower_lower run every volume, and tower_lower rebuilds the source");

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
    sim_check(results, oracle_equal == volumes, "the oracle's 5/3 equals tower_lift's crystal and returns the source");
    scriptura_text(line, "    the oracle's 5/3 equals tower_lift and returns the source on ");
    scriptura_decimal(line, oracle_equal, 1u);
    scriptura_text(line, " of ");
    scriptura_decimal(line, volumes, 1u);
    scriptura_text(line, " volumes\n");

    for (unsigned int ruleset = 0u; (kernels != 0) && (ruleset < TOWER_TEST_RULESETS); ruleset += 1u)
    {
        tower_test_ruleset(results, extent, &s_tower_test_ruleset[ruleset], source, crystal);
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
    const int widths = (kernels != 0) &&
                       tower_test_build(extent, &s_tower_test_ruleset[0], 0, samples, coefficients, lift_steps) &&
                       tower_test_load(lift_steps, coefficients, sample_bits, &lift);
    std::vector<unsigned int> crystal_bits(lanes, 32u);
    for (unsigned int position = 0u; (widths != 0) && (position < lanes); position += 1u)
    {
        crystal_bits[position] = lift.key.term[coefficients[position]].bits + 1u;
    }
    if (widths != 0)
    {
        tower_test_free(&lift);
        tower_test_operation_stack(results, extent, crystal, rebuilt, crystal_bits);
    }
    sim_check(results, widths, "the 5/3's widths are read for F . T^-1");
    sim_flush(results);
}

// the emitter's errors: each leaves the count, and any step already in the capacity, as it was
static void tower_test_errors(SimResults *results)
{
    const unsigned long long pair[4] = {1ull, 1ull, 1ull, 2ull};
    const unsigned long long empty[4] = {1ull, 0ull, 1ull, 2ull};
    const unsigned int fields[2] = {0u, 1u};
    unsigned int out[2] = {0u, 0u};
    EngineRecordStep steps_out[3];
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        steps_out[at] = EngineRecordStep{ENGINE_RECORD_CONSTANT, 7u, 0u, 0u};
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
    const int later =
        (tower_record_lift(&request) == TOWER_ERROR) && (count == 1u) && (error.kind == ENGINE_ERROR_REQUEST);
    sim_check(results, later, "a register that is not an earlier step errors, and the count is left as it was");
    memset(&error, 0, sizeof(error));
    count = 2u;
    request.steps = steps_out;
    request.step_capacity = 3u;
    int kept = 1;
    const int small =
        (tower_record_lower(&request) == TOWER_ERROR) && (count == 2u) && (error.kind == ENGINE_ERROR_REQUEST);
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        kept = kept && (steps_out[at].operation == ENGINE_RECORD_CONSTANT) && (steps_out[at].left == 7u);
    }
    sim_check(results, small && kept, "a capacity too small errors before a step is written");
    memset(&error, 0, sizeof(error));
    memcpy(request.extent, empty, sizeof(request.extent));
    request.steps = NULL;
    const int nothing =
        (tower_record_lift(&request) == TOWER_ERROR) && (count == 2u) && (error.kind == ENGINE_ERROR_REQUEST);
    sim_check(results, nothing, "an extent with no samples errors");
    // a step with a zero weight, then one with no taps, then one whose sign is neither 1 nor -1
    TowerLiftingStep malformed[3] = {{TOWER_BAND_HIGH, -1, 1u, {0}, {0}, 0u, 0u},
                                     {TOWER_BAND_HIGH, -1, 0u, {0}, {1}, 0u, 0u},
                                     {TOWER_BAND_LOW, 2, 1u, {0}, {1}, 0u, 0u}};
    memcpy(request.extent, pair, sizeof(request.extent));
    int errored = 1;
    for (unsigned int at = 0u; at < 3u; at += 1u)
    {
        memset(&error, 0, sizeof(error));
        request.rules = &malformed[at];
        request.rule_count = 1u;
        errored = errored && (tower_record_lift(&request) == TOWER_ERROR) && (count == 2u) &&
                  (error.kind == ENGINE_ERROR_REQUEST);
    }
    sim_check(results, errored, "a step with a zero weight, no taps, or a sign other than 1 or -1 errors");
}

int main(int count, char **arguments)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    scriptura_text(&results.line,
                   "  the two towers as record floors focused from a ruleset, read against tower_lift and"
                   " tower_lower's kernels and a host oracle\n");
    int ok = sim_job_submit(&results, "record_tower_test", count, arguments, TOWER_TEST_DECLARED);
    unsigned long long maximum = 1ull;
    for (unsigned int block = 0u; block < TOWER_TEST_BLOCKS; block += 1u)
    {
        const unsigned long long *const extent = s_tower_test_extent[block];
        const unsigned long long lanes = extent[0] * extent[1] * extent[2] * extent[3];
        maximum = (lanes > maximum) ? lanes : maximum;
    }
    unsigned short *device_volume = NULL;
    ok = ok && sim_status_check(&results, cudaMalloc((void **)&device_volume, (size_t)maximum * sizeof(unsigned short)),
                                "the kernels' volume");
    // a sweep whose frame passes the stack limit grows it, and the local memory that reserves is held until the limit
    // is set back; cycle sets it back once each sweep ends. The limit after every block is the limit before them
    size_t stack_before = 0u;
    ok = ok &&
         sim_status_check(&results, cudaDeviceGetLimit(&stack_before, cudaLimitStackSize), "the stack limit, before");
    for (unsigned int block = 0u; (ok != 0) && (block < TOWER_TEST_BLOCKS); block += 1u)
    {
        tower_test_block(&results, s_tower_test_extent[block], device_volume);
    }
    size_t stack_after = 0u;
    ok = ok &&
         sim_status_check(&results, cudaDeviceGetLimit(&stack_after, cudaLimitStackSize), "the stack limit, after");
    sim_check(&results, (ok != 0) && (stack_after == stack_before),
              "every sweep gives its stack back: the limit after the blocks is the limit before them");
    scriptura_text(&results.line, "  the stack limit: ");
    scriptura_decimal(&results.line, stack_before, 1u);
    scriptura_text(&results.line, " bytes a thread before the blocks, ");
    scriptura_decimal(&results.line, stack_after, 1u);
    scriptura_text(&results.line, " after them\n");
    sim_flush(&results);
    tower_test_errors(&results);
    cudaFree(device_volume);
    return sim_close(&results, "record tower test");
}
