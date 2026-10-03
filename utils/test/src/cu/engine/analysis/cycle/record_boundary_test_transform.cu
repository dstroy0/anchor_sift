// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// record_boundary_test_transform.cu: the forward and inverse transforms
#include "record_boundary_test_internal.h"

#define BOUNDARY_TEST_SEED 0xB0DA7C0FFEE5EEDull

static unsigned long long s_boundary_state = BOUNDARY_TEST_SEED;

// 2^RANGE times T's matrix and T^-1's, column i the image of 2^RANGE e_i: [output][input]
long long g_boundary_forward_matrix[BOUNDARY_TEST_SAMPLES][BOUNDARY_TEST_SAMPLES];

long long g_boundary_inverse_matrix[BOUNDARY_TEST_SAMPLES][BOUNDARY_TEST_SAMPLES];

// the draws started again for part `part`: a part draws the same alone as among the others
void boundary_seed(unsigned int part)
{
    s_boundary_state = BOUNDARY_TEST_SEED + part;
}

unsigned int boundary_random(void)
{
    s_boundary_state ^= s_boundary_state << 13u;
    s_boundary_state ^= s_boundary_state >> 7u;
    s_boundary_state ^= s_boundary_state << 17u;
    return (unsigned int)(s_boundary_state >> 16u);
}

void boundary_check(BoundaryResults *results, int passed, const char *what)
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

// a ratio in hundredths, as whole.fraction
void boundary_hundredths(ScripturaLine *line, unsigned long long top, unsigned long long bottom)
{
    const unsigned long long hundredths = (bottom == 0ull) ? 0ull : (((100ull * top) + (bottom / 2ull)) / bottom);
    scriptura_decimal(line, hundredths / 100ull, 1u);
    scriptura_character(line, '.');
    scriptura_decimal(line, hundredths % 100ull, 2u);
}

unsigned int boundary_append(BoundaryProgram *program, EngineRecordOperation operation, unsigned int left,
                             unsigned int right)
{
    if (program->count >= BOUNDARY_TEST_STEPS)
    {
        program->overflow = 1;
        return 0u;
    }
    program->steps[program->count] = EngineRecordStep{operation, left, right, 0u};
    program->count += 1u;
    return program->count - 1u;
}

void boundary_output(BoundaryProgram *program, unsigned int step)
{
    if (program->output_count >= BOUNDARY_TEST_OUTPUTS)
    {
        program->overflow = 1;
        return;
    }
    program->outputs[program->output_count] = step;
    program->output_count += 1u;
}

// floor(v / 2^k), toward minus infinity, from record steps: the and with 2^k - 1 is v's residue, never negative, and
// v less it divides exactly
static unsigned int boundary_floor_shift(BoundaryProgram *program, unsigned int value, unsigned int shift)
{
    const unsigned int mask = boundary_append(program, ENGINE_RECORD_CONSTANT, (1u << shift) - 1u, 0u);
    const unsigned int residue = boundary_append(program, ENGINE_RECORD_AND, value, mask);
    const unsigned int difference = boundary_append(program, ENGINE_RECORD_DIFFERENCE, value, residue);
    const unsigned int power = boundary_append(program, ENGINE_RECORD_CONSTANT, 1u << shift, 0u);
    return boundary_append(program, ENGINE_RECORD_EXACT_QUOTIENT, difference, power);
}

// T over the samples' registers in tower->low[0], `samples` of them over `levels` levels: each level splits its band
// into highs d_j = x_(2j+1) - floor((x_2j + x_(2j+2)) / 2) and lows s_i = x_2i + floor((d_(i-1) + d_i + 2) / 4), the
// edges repeating their neighbor, as tower_*.cu does
void boundary_forward(BoundaryProgram *program, BoundaryTower *tower, unsigned int samples, unsigned int levels)
{
    unsigned int count = samples;
    for (unsigned int level = 1u; level <= levels; level += 1u)
    {
        const unsigned int *const band = tower->low[level - 1u];
        const unsigned int highs = count / 2u;
        const unsigned int lows = (count + 1u) / 2u;
        // this level's highs begin at n / 2^level, the band's half
        unsigned int *const high = &tower->crystal[highs];
        for (unsigned int j = 0u; j < highs; j += 1u)
        {
            const unsigned int left = band[2u * j];
            const unsigned int right = (((2u * j) + 2u) < count) ? band[(2u * j) + 2u] : left;
            const unsigned int pair = boundary_append(program, ENGINE_RECORD_SUM, left, right);
            high[j] = boundary_append(program, ENGINE_RECORD_DIFFERENCE, band[(2u * j) + 1u],
                                      boundary_floor_shift(program, pair, 1u));
        }
        const unsigned int two = boundary_append(program, ENGINE_RECORD_CONSTANT, 2u, 0u);
        for (unsigned int i = 0u; i < lows; i += 1u)
        {
            const unsigned int before = (i > 0u) ? high[i - 1u] : high[0];
            const unsigned int after = (i < highs) ? high[i] : before;
            const unsigned int pair = boundary_append(program, ENGINE_RECORD_SUM, before, after);
            const unsigned int rounded = boundary_append(program, ENGINE_RECORD_SUM, pair, two);
            tower->low[level][i] =
                boundary_append(program, ENGINE_RECORD_SUM, band[2u * i], boundary_floor_shift(program, rounded, 2u));
        }
        count = lows;
    }
    for (unsigned int i = 0u; i < count; i += 1u)
    {
        tower->crystal[i] = tower->low[levels][i];
    }
}

// with a twin, a rebuilt register wrapped to its forward twin's width and one bit more: the value is the twin's. The
// wrap holds it exactly and the inverse stays as narrow as the forward
static unsigned int boundary_mirror(BoundaryProgram *program, unsigned int value, const BoundaryTower *twin,
                                    const EngineRecordKey *twin_key, unsigned int level, unsigned int at)
{
    if (twin == NULL)
    {
        return value;
    }
    return boundary_append(program, ENGINE_RECORD_WRAP, value, twin_key->term[twin->low[level][at]].bits + 1u);
}

// T^-1 from a crystal's registers, `samples` of them over `levels` levels, level by level from the boundary out:
// x_2i = s_i - floor((d_(i-1) + d_i + 2) / 4), then x_(2j+1) = d_j + floor((x_2j + x_(2j+2)) / 2). back->low[l]
// holds the rebuilt band at level l.
void boundary_inverse(BoundaryProgram *program, const unsigned int *crystal, const BoundaryTower *twin,
                      const EngineRecordKey *twin_key, BoundaryTower *back, unsigned int samples, unsigned int levels)
{
    unsigned int count = samples >> levels;
    for (unsigned int i = 0u; i < count; i += 1u)
    {
        back->low[levels][i] = crystal[i];
    }
    for (unsigned int level = levels; level >= 1u; level -= 1u)
    {
        const unsigned int *const band = back->low[level];
        // this level's highs begin at n / 2^level, the band's count
        const unsigned int *const high = &crystal[count];
        const unsigned int two = boundary_append(program, ENGINE_RECORD_CONSTANT, 2u, 0u);
        unsigned int even[BOUNDARY_TEST_SAMPLES];
        for (unsigned int i = 0u; i < count; i += 1u)
        {
            const unsigned int before = (i > 0u) ? high[i - 1u] : high[0];
            const unsigned int pair = boundary_append(program, ENGINE_RECORD_SUM, before, high[i]);
            const unsigned int rounded = boundary_append(program, ENGINE_RECORD_SUM, pair, two);
            const unsigned int rebuilt =
                boundary_append(program, ENGINE_RECORD_DIFFERENCE, band[i], boundary_floor_shift(program, rounded, 2u));
            even[i] = boundary_mirror(program, rebuilt, twin, twin_key, level - 1u, 2u * i);
        }
        for (unsigned int j = 0u; j < count; j += 1u)
        {
            const unsigned int left = even[j];
            const unsigned int right = ((j + 1u) < count) ? even[j + 1u] : left;
            const unsigned int pair = boundary_append(program, ENGINE_RECORD_SUM, left, right);
            const unsigned int rebuilt =
                boundary_append(program, ENGINE_RECORD_SUM, high[j], boundary_floor_shift(program, pair, 1u));
            back->low[level - 1u][(2u * j) + 1u] =
                boundary_mirror(program, rebuilt, twin, twin_key, level - 1u, (2u * j) + 1u);
            back->low[level - 1u][2u * j] = even[j];
        }
        count *= 2u;
    }
}

// the tower's own floor shift, as tower_*.cu computes it on the device
static long long boundary_tower_shift(long long value, unsigned int shift)
{
    return (value >= 0ll) ? (value >> shift) : -(((-value) + (1ll << shift) - 1ll) >> shift);
}

// the host's T on long long, the oracle for the record floors
void boundary_host_forward(const long long *samples, long long *crystal)
{
    long long band[BOUNDARY_TEST_SAMPLES];
    memcpy(band, samples, sizeof(band));
    unsigned int count = BOUNDARY_TEST_SAMPLES;
    for (unsigned int level = 1u; level <= BOUNDARY_TEST_LEVELS; level += 1u)
    {
        const unsigned int highs = count / 2u;
        const unsigned int lows = (count + 1u) / 2u;
        long long *const high = &crystal[highs];
        for (unsigned int j = 0u; j < highs; j += 1u)
        {
            const long long left = band[2u * j];
            const long long right = (((2u * j) + 2u) < count) ? band[(2u * j) + 2u] : left;
            high[j] = band[(2u * j) + 1u] - boundary_tower_shift(left + right, 1u);
        }
        for (unsigned int i = 0u; i < lows; i += 1u)
        {
            const long long before = (i > 0u) ? high[i - 1u] : high[0];
            const long long after = (i < highs) ? high[i] : before;
            band[i] = band[2u * i] + boundary_tower_shift(before + after + 2ll, 2u);
        }
        count = lows;
    }
    memcpy(crystal, band, (size_t)count * sizeof(long long));
}

// the host's T^-1 on long long
void boundary_host_inverse(const long long *crystal, long long *samples)
{
    long long band[BOUNDARY_TEST_SAMPLES];
    unsigned int count = BOUNDARY_TEST_SAMPLES >> BOUNDARY_TEST_LEVELS;
    memcpy(band, crystal, (size_t)count * sizeof(long long));
    for (unsigned int level = BOUNDARY_TEST_LEVELS; level >= 1u; level -= 1u)
    {
        const long long *const high = &crystal[count];
        long long even[BOUNDARY_TEST_SAMPLES];
        for (unsigned int i = 0u; i < count; i += 1u)
        {
            const long long before = (i > 0u) ? high[i - 1u] : high[0];
            even[i] = band[i] - boundary_tower_shift(before + high[i] + 2ll, 2u);
        }
        for (unsigned int j = 0u; j < count; j += 1u)
        {
            const long long right = ((j + 1u) < count) ? even[j + 1u] : even[j];
            band[(2u * j) + 1u] = high[j] + boundary_tower_shift(even[j] + right, 1u);
            band[2u * j] = even[j];
        }
        count *= 2u;
    }
    memcpy(samples, band, sizeof(band));
}

// the matrices: the image of 2^RANGE e_i under each map. Every floor divides a multiple of its power there. The
// host's floors are exact and each column is 2^RANGE times the rational map's.
void boundary_matrices(void)
{
    for (unsigned int input = 0u; input < BOUNDARY_TEST_SAMPLES; input += 1u)
    {
        long long unit[BOUNDARY_TEST_SAMPLES];
        long long forward[BOUNDARY_TEST_SAMPLES];
        long long inverse[BOUNDARY_TEST_SAMPLES];
        memset(unit, 0, sizeof(unit));
        unit[input] = 1ll << BOUNDARY_TEST_RANGE;
        boundary_host_forward(unit, forward);
        boundary_host_inverse(unit, inverse);
        for (unsigned int output = 0u; output < BOUNDARY_TEST_SAMPLES; output += 1u)
        {
            g_boundary_forward_matrix[output][input] = forward[output];
            g_boundary_inverse_matrix[output][input] = inverse[output];
        }
    }
}

// the 2-adic valuation of a nonzero value: the index of its lowest set bit
int boundary_valuation(long long value)
{
    // the magnitude's low bits are the value's. The two's complement word is read as is
    unsigned long long word = (unsigned long long)value;
    int valuation = 0;
    while ((word & 1ull) == 0ull)
    {
        word >>= 1u;
        valuation += 1;
    }
    return valuation;
}

// how many bits below an input flip a row of the matrix reaches: REACH less the least valuation over its entries
int boundary_row_range(const long long (*matrix)[BOUNDARY_TEST_SAMPLES], unsigned int output)
{
    int range = -1000;
    for (unsigned int input = 0u; input < BOUNDARY_TEST_SAMPLES; input += 1u)
    {
        const long long entry = matrix[output][input];
        const int here = (entry == 0ll) ? -1000 : ((int)BOUNDARY_TEST_RANGE - boundary_valuation(entry));
        range = (here > range) ? here : range;
    }
    return range;
}

int boundary_encode(const BoundaryProgram *program, unsigned int count, unsigned int fields, EngineRecordKey *key,
                    EngineError *error)
{
    unsigned int field_bits[BOUNDARY_TEST_SAMPLES];
    for (unsigned int at = 0u; at < fields; at += 1u)
    {
        field_bits[at] = BOUNDARY_TEST_FIELD_BITS;
    }
    const KeymathRecordRequest encode_request = {
        program->steps, count, field_bits, fields, 1u, program->outputs, program->output_count, NULL, 0u, key, error};
    return keymath_record_encode(&encode_request) != KEYMATH_ERROR;
}
