// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The crystal as a boundary, measured on itself. A 5/3 lifting tower T of four levels over 64 samples runs as record
// floors. Its crystal (the level-4 lows and every high, in Mallat order) is the boundary between the tower and its
// inverse, and everything here is read there, not from either end.
//
// Written onto the boundary and read back: arbitrary crystals run through T^-1 then T return exactly, so the boundary
// is a whole coordinate chart of Z^n. The precision the boundary reads: a flip of input bit b moves a crystal
// coefficient only at bit b - 3L and above, and for b >= 3L the move is exactly 2^b times a column of T's rational
// matrix M, whose 2-adic valuations give the reach per band (3l for the lows at level l, 3l - 2 for its highs). T^-1
// is held to the reach L + 2 the same way. What passes through T: a constant added to every sample lands on the
// crystal's lows alone, and a vector in 2^(3L) Z^n lands as M times it; negation and doubling do not pass. The heap
// and the ring at every floor of T then T^-1: the heap mirrors exactly, the ring is ring_0 + 6(n - n / 2^l) at floor
// l and its mirror one bit wider per wrapped low, and the heap's pinch at the crystal orders a ramp, a ramp +-8, a
// ramp +-1024 and noise. Last, the top projection x -> x / 2^k toward zero, the other end of the window from the
// 2-adic projection: nested quotients commute with it, it never reverses a comparison (the 8-bit wrap reverses
// many), and a sum through it is off by at most one. The count each crystal keeps: on a 4-sample tower every input
// quantum at level w + 3 is run, and T and T^-1 send exactly as many onto every output quantum at level w (Haar
// measure on Z_2^n); det M and det M^-1 are +-1 exactly, proved modulo primes past Hadamard's bound (volume on R^n).
// Every program runs on the device and the host, word for word.
#include "cycle.h"
#include "keymath.h"
#include "key_schedule.h"
#include "scriptura.h"

#include <cuda_runtime.h>

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define BOUNDARY_TEST_LINE 16384ull

#define BOUNDARY_TEST_SAMPLES 64u

#define BOUNDARY_TEST_LEVELS 4u

#define BOUNDARY_TEST_FIELD_BITS 24u

// T's precision bound in bits: three per level, from the floor shift by 1 a high reads through and the shift by 2 a
// low reads through after it
#define BOUNDARY_TEST_REACH (3u * BOUNDARY_TEST_LEVELS)

// T^-1's bound: one bit per level a low passes back through, and three at a high's own level
#define BOUNDARY_TEST_INVERSE_REACH (BOUNDARY_TEST_LEVELS + 2u)

#define BOUNDARY_TEST_FLOORS ((2u * BOUNDARY_TEST_LEVELS) + 1u)

#define BOUNDARY_TEST_STEPS 2560u

#define BOUNDARY_TEST_OUTPUTS 320u

#define BOUNDARY_TEST_PAIRS 8192u

#define BOUNDARY_TEST_CLASSES 4u

#define BOUNDARY_TEST_CLASS_LANES 1024u

#define BOUNDARY_TEST_TOP_LANES 65536u

#define BOUNDARY_TEST_TOP_SETTINGS 3u

// the highest bit a precision pair flips, below the field's sign bit so the flip moves the value by exactly 2^b
#define BOUNDARY_TEST_FLIP_TOP (BOUNDARY_TEST_FIELD_BITS - 2u)

// the tower counted whole: 4 samples and one level, whose reach each way is 3 bits
#define BOUNDARY_TEST_COUNT_SAMPLES 4u

#define BOUNDARY_TEST_COUNT_REACH 3u

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} BoundaryTally;

typedef struct
{
    EngineRecordStep steps[BOUNDARY_TEST_STEPS];
    unsigned int count;
    int overflow;
    unsigned int outputs[BOUNDARY_TEST_OUTPUTS];
    unsigned int output_count;
} BoundaryProgram;

// a tower's registers: low[l] the band at level l (low[0] the samples), and the crystal in Mallat order, the level-L
// lows first, then the highs of levels L, L - 1, ..., 1, the highs of level l at [n / 2^l, n / 2^(l - 1))
typedef struct
{
    unsigned int low[BOUNDARY_TEST_LEVELS + 1u][BOUNDARY_TEST_SAMPLES];
    unsigned int crystal[BOUNDARY_TEST_SAMPLES];
} BoundaryTower;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} BoundaryLoaded;

// the host's own T or T^-1 over n values
typedef void (*BoundaryMap)(const long long *in, long long *out);

static unsigned long long s_boundary_state = 0xB0DA7C0FFEE5EEDull;

// 2^REACH times T's matrix and T^-1's, column i the image of 2^REACH e_i: [output][input]
static long long s_boundary_forward_matrix[BOUNDARY_TEST_SAMPLES][BOUNDARY_TEST_SAMPLES];

static long long s_boundary_inverse_matrix[BOUNDARY_TEST_SAMPLES][BOUNDARY_TEST_SAMPLES];

static unsigned int boundary_random(void)
{
    s_boundary_state ^= s_boundary_state << 13u;
    s_boundary_state ^= s_boundary_state >> 7u;
    s_boundary_state ^= s_boundary_state << 17u;
    return (unsigned int)(s_boundary_state >> 16u);
}

static void boundary_check(BoundaryTally *tally, int held, const char *what)
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

// a ratio in hundredths, as whole.fraction
static void boundary_hundredths(ScripturaLine *line, unsigned long long top, unsigned long long bottom)
{
    const unsigned long long hundredths = (bottom == 0ull) ? 0ull : (((100ull * top) + (bottom / 2ull)) / bottom);
    scriptura_decimal(line, hundredths / 100ull, 1u);
    scriptura_character(line, '.');
    scriptura_decimal(line, hundredths % 100ull, 2u);
}

static unsigned int boundary_emit(BoundaryProgram *program, EngineRecordOperation operation, unsigned int left,
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

static void boundary_output(BoundaryProgram *program, unsigned int step)
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
    const unsigned int mask = boundary_emit(program, ENGINE_RECORD_CONSTANT, (1u << shift) - 1u, 0u);
    const unsigned int residue = boundary_emit(program, ENGINE_RECORD_AND, value, mask);
    const unsigned int whole = boundary_emit(program, ENGINE_RECORD_DIFFERENCE, value, residue);
    const unsigned int power = boundary_emit(program, ENGINE_RECORD_CONSTANT, 1u << shift, 0u);
    return boundary_emit(program, ENGINE_RECORD_EXACT_QUOTIENT, whole, power);
}

// T over the samples' registers in tower->low[0], `samples` of them over `levels` levels: each level splits its band
// into highs d_j = x_(2j+1) - floor((x_2j + x_(2j+2)) / 2) and lows s_i = x_2i + floor((d_(i-1) + d_i + 2) / 4), the
// edges repeating their neighbor, as tower.cu does
static void boundary_forward(BoundaryProgram *program, BoundaryTower *tower, unsigned int samples, unsigned int levels)
{
    unsigned int count = samples;
    for (unsigned int level = 1u; level <= levels; level += 1u)
    {
        const unsigned int *const band = tower->low[level - 1u];
        const unsigned int highs = count / 2u;
        const unsigned int lows = (count + 1u) / 2u;
        // this level's highs begin at n / 2^level, which is the band's half
        unsigned int *const high = &tower->crystal[highs];
        for (unsigned int j = 0u; j < highs; j += 1u)
        {
            const unsigned int left = band[2u * j];
            const unsigned int right = (((2u * j) + 2u) < count) ? band[(2u * j) + 2u] : left;
            const unsigned int pair = boundary_emit(program, ENGINE_RECORD_SUM, left, right);
            high[j] = boundary_emit(program, ENGINE_RECORD_DIFFERENCE, band[(2u * j) + 1u],
                                    boundary_floor_shift(program, pair, 1u));
        }
        const unsigned int two = boundary_emit(program, ENGINE_RECORD_CONSTANT, 2u, 0u);
        for (unsigned int i = 0u; i < lows; i += 1u)
        {
            const unsigned int before = (i > 0u) ? high[i - 1u] : high[0];
            const unsigned int after = (i < highs) ? high[i] : before;
            const unsigned int pair = boundary_emit(program, ENGINE_RECORD_SUM, before, after);
            const unsigned int rounded = boundary_emit(program, ENGINE_RECORD_SUM, pair, two);
            tower->low[level][i] = boundary_emit(program, ENGINE_RECORD_SUM, band[2u * i],
                                                 boundary_floor_shift(program, rounded, 2u));
        }
        count = lows;
    }
    for (unsigned int i = 0u; i < count; i += 1u)
    {
        tower->crystal[i] = tower->low[levels][i];
    }
}

// with a twin, a rebuilt register wrapped to its forward twin's width and one bit more: the value is the twin's, so
// the wrap holds it exactly and the inverse stays as narrow as the forward
static unsigned int boundary_mirror(BoundaryProgram *program, unsigned int value, const BoundaryTower *twin,
                                    const EngineRecordKey *twin_key, unsigned int level, unsigned int at)
{
    if (twin == NULL)
    {
        return value;
    }
    return boundary_emit(program, ENGINE_RECORD_WRAP, value, twin_key->term[twin->low[level][at]].bits + 1u);
}

// T^-1 from a crystal's registers, `samples` of them over `levels` levels, level by level from the boundary out:
// x_2i = s_i - floor((d_(i-1) + d_i + 2) / 4), then x_(2j+1) = d_j + floor((x_2j + x_(2j+2)) / 2). back->low[l]
// holds the rebuilt band at level l.
static void boundary_inverse(BoundaryProgram *program, const unsigned int *crystal, const BoundaryTower *twin,
                             const EngineRecordKey *twin_key, BoundaryTower *back, unsigned int samples,
                             unsigned int levels)
{
    unsigned int count = samples >> levels;
    for (unsigned int i = 0u; i < count; i += 1u)
    {
        back->low[levels][i] = crystal[i];
    }
    for (unsigned int level = levels; level >= 1u; level -= 1u)
    {
        const unsigned int *const band = back->low[level];
        // this level's highs begin at n / 2^level, which is the band's count
        const unsigned int *const high = &crystal[count];
        const unsigned int two = boundary_emit(program, ENGINE_RECORD_CONSTANT, 2u, 0u);
        unsigned int even[BOUNDARY_TEST_SAMPLES];
        for (unsigned int i = 0u; i < count; i += 1u)
        {
            const unsigned int before = (i > 0u) ? high[i - 1u] : high[0];
            const unsigned int pair = boundary_emit(program, ENGINE_RECORD_SUM, before, high[i]);
            const unsigned int rounded = boundary_emit(program, ENGINE_RECORD_SUM, pair, two);
            const unsigned int rebuilt = boundary_emit(program, ENGINE_RECORD_DIFFERENCE, band[i],
                                                       boundary_floor_shift(program, rounded, 2u));
            even[i] = boundary_mirror(program, rebuilt, twin, twin_key, level - 1u, 2u * i);
        }
        for (unsigned int j = 0u; j < count; j += 1u)
        {
            const unsigned int left = even[j];
            const unsigned int right = ((j + 1u) < count) ? even[j + 1u] : left;
            const unsigned int pair = boundary_emit(program, ENGINE_RECORD_SUM, left, right);
            const unsigned int rebuilt = boundary_emit(program, ENGINE_RECORD_SUM, high[j],
                                                       boundary_floor_shift(program, pair, 1u));
            back->low[level - 1u][(2u * j) + 1u] = boundary_mirror(program, rebuilt, twin, twin_key, level - 1u,
                                                                   (2u * j) + 1u);
            back->low[level - 1u][2u * j] = even[j];
        }
        count *= 2u;
    }
}

// the tower's own floor shift, as tower.cu computes it on the device
static long long boundary_tower_shift(long long value, unsigned int shift)
{
    return (value >= 0ll) ? (value >> shift) : -(((-value) + (1ll << shift) - 1ll) >> shift);
}

// the host's T on long long, the oracle for the record floors
static void boundary_host_forward(const long long *samples, long long *crystal)
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
static void boundary_host_inverse(const long long *crystal, long long *samples)
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

// the matrices: the image of 2^REACH e_i under each map. Every floor divides a multiple of its power there, so the
// host's floors are exact and each column is 2^REACH times the rational map's.
static void boundary_matrices(void)
{
    for (unsigned int input = 0u; input < BOUNDARY_TEST_SAMPLES; input += 1u)
    {
        long long unit[BOUNDARY_TEST_SAMPLES];
        long long forward[BOUNDARY_TEST_SAMPLES];
        long long inverse[BOUNDARY_TEST_SAMPLES];
        memset(unit, 0, sizeof(unit));
        unit[input] = 1ll << BOUNDARY_TEST_REACH;
        boundary_host_forward(unit, forward);
        boundary_host_inverse(unit, inverse);
        for (unsigned int output = 0u; output < BOUNDARY_TEST_SAMPLES; output += 1u)
        {
            s_boundary_forward_matrix[output][input] = forward[output];
            s_boundary_inverse_matrix[output][input] = inverse[output];
        }
    }
}

// the 2-adic valuation of a nonzero value: the index of its lowest set bit
static int boundary_valuation(long long value)
{
    // the magnitude's low bits are the value's, so the two's complement word is read as is
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
static int boundary_row_reach(const long long (*matrix)[BOUNDARY_TEST_SAMPLES], unsigned int output)
{
    int reach = -1000;
    for (unsigned int input = 0u; input < BOUNDARY_TEST_SAMPLES; input += 1u)
    {
        const long long entry = matrix[output][input];
        const int here = (entry == 0ll) ? -1000 : ((int)BOUNDARY_TEST_REACH - boundary_valuation(entry));
        reach = (here > reach) ? here : reach;
    }
    return reach;
}

static int boundary_imprint(const BoundaryProgram *program, unsigned int count, unsigned int fields,
                            EngineRecordKey *key, EngineError *error)
{
    unsigned int field_bits[BOUNDARY_TEST_SAMPLES];
    for (unsigned int at = 0u; at < fields; at += 1u)
    {
        field_bits[at] = BOUNDARY_TEST_FIELD_BITS;
    }
    const KeymathRecordRequest imprint = {program->steps, count, field_bits, fields, 1u, program->outputs,
                                          program->output_count, NULL, 0u, key, error};
    return keymath_record_imprint(&imprint) != KEYMATH_REFUSED;
}

// each field its own 32-bit word, `fields` words a lane, laid with register reuse
static int boundary_load(const BoundaryProgram *program, unsigned int fields, BoundaryLoaded *loaded)
{
    memset(loaded, 0, sizeof(*loaded));
    if ((program->overflow != 0) || (boundary_imprint(program, program->count, fields, &loaded->key, &loaded->error) == 0))
    {
        return 0;
    }
    unsigned int field_offset[BOUNDARY_TEST_SAMPLES];
    for (unsigned int at = 0u; at < fields; at += 1u)
    {
        field_offset[at] = 32u * at;
    }
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {fields, 0u, 0u};
    const KeyScheduleRecordRequest lay = {&loaded->key, field_offset, fields, in_limbs, 1, &loaded->layout,
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

static void boundary_free(BoundaryLoaded *loaded)
{
    cycle_record_release(loaded->record);
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

// run a loaded program over `count` atoms on the host and on the device; 1 where both ran and their records agree
// word for word
static int boundary_run(BoundaryLoaded *loaded, const unsigned int *atoms, unsigned int count, unsigned int *host_out,
                        unsigned int *device_out)
{
    const unsigned int in_limbs = loaded->layout.in_limbs[0];
    const unsigned int out_limbs = loaded->layout.out_limbs;
    const CycleRecordHostRequest host = {&loaded->layout, {atoms, NULL, NULL}, {count, 0ull, 0ull}, NULL, count,
                                         host_out};
    const int host_ran = cycle_record_run_host(&host) != CYCLE_REFUSED;
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
    return (host_ran != 0) && (good != 0)
        && (memcmp(host_out, device_out, (size_t)count * out_limbs * sizeof(unsigned int)) == 0);
}

// a field's word: the value's low 24 bits of two's complement
static unsigned int boundary_word(long long value)
{
    // the mask keeps the low 24 bits, which is the field's whole content
    return (unsigned int)((unsigned long long)value & ((1ull << BOUNDARY_TEST_FIELD_BITS) - 1ull));
}

// a field's word read back signed: 2^24 comes off where its top bit is set
static long long boundary_field(unsigned int word)
{
    const long long raw = (long long)word;
    return ((word >> (BOUNDARY_TEST_FIELD_BITS - 1u)) != 0u) ? (raw - (1ll << BOUNDARY_TEST_FIELD_BITS)) : raw;
}

// one output's value from a lane's record: its out_bits of two's complement, the top written bit the sign. Every
// output here is 64 bits or narrower, which the caller holds before reading.
static long long boundary_read(const unsigned int *record, const DeviceRecordStep *step)
{
    unsigned long long raw = 0ull;
    for (unsigned int bit = 0u; bit < step->out_bits; bit += 1u)
    {
        const unsigned int from = step->out_offset + bit;
        raw |= (unsigned long long)((record[from / 32u] >> (from % 32u)) & 1u) << bit;
    }
    if ((step->out_bits < 64u) && (((raw >> (step->out_bits - 1u)) & 1u) != 0ull))
    {
        raw |= ~0ull << step->out_bits;
    }
    // the word is the value's two's complement, so the conversion reads it back signed
    return (long long)raw;
}

// every output of a loaded program fits the oracle's 64-bit word
static int boundary_narrow_enough(const BoundaryLoaded *loaded, const BoundaryProgram *program)
{
    int held = 1;
    for (unsigned int output = 0u; output < program->output_count; output += 1u)
    {
        held = held && (loaded->layout.step_table[program->outputs[output]].out_bits <= 64u);
    }
    return held;
}

// flip one input bit b per lane pair and read the move at the first n outputs. For b >= REACH the move must be
// exactly 2^b times column i of the map's matrix; for every b it must lie at bit b - bound or above. Each lane must
// also equal the host's map, and with readback the next n outputs must return the inputs. The greatest reach met
// comes back in reach_seen.
static void boundary_precision(BoundaryTally *tally, BoundaryLoaded *loaded, const BoundaryProgram *program,
                               BoundaryMap map, const long long (*matrix)[BOUNDARY_TEST_SAMPLES], unsigned int bound,
                               int readback, const char *name, int *reach_seen)
{
    const unsigned int n = BOUNDARY_TEST_SAMPLES;
    const unsigned int lanes = 2u * BOUNDARY_TEST_PAIRS;
    const unsigned int out_limbs = loaded->layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * n, sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const flip_at = (unsigned int *)calloc(BOUNDARY_TEST_PAIRS, sizeof(unsigned int));
    unsigned int *const flip_bit = (unsigned int *)calloc(BOUNDARY_TEST_PAIRS, sizeof(unsigned int));
    const int buffers = (atoms != NULL) && (host_out != NULL) && (device_out != NULL) && (flip_at != NULL)
                     && (flip_bit != NULL);
    for (unsigned int pair = 0u; (buffers != 0) && (pair < BOUNDARY_TEST_PAIRS); pair += 1u)
    {
        unsigned int *const base = &atoms[(size_t)(2u * pair) * n];
        unsigned int *const moved = &atoms[(size_t)((2u * pair) + 1u) * n];
        for (unsigned int at = 0u; at < n; at += 1u)
        {
            base[at] = boundary_random() & ((1u << BOUNDARY_TEST_FIELD_BITS) - 1u);
            moved[at] = base[at];
        }
        flip_at[pair] = boundary_random() % n;
        flip_bit[pair] = boundary_random() % (BOUNDARY_TEST_FLIP_TOP + 1u);
        moved[flip_at[pair]] ^= 1u << flip_bit[pair];
    }
    const int ran = (buffers != 0) && (boundary_run(loaded, atoms, lanes, host_out, device_out) != 0);
    const int narrow = boundary_narrow_enough(loaded, program);
    unsigned int mapped = 0u;
    unsigned int returned = 0u;
    unsigned int lawful = 0u;
    unsigned int lawful_pairs = 0u;
    unsigned int bounded = 0u;
    int seen = -1000;
    for (unsigned int pair = 0u; (ran != 0) && (narrow != 0) && (pair < BOUNDARY_TEST_PAIRS); pair += 1u)
    {
        long long out[2][BOUNDARY_TEST_SAMPLES];
        for (unsigned int side = 0u; side < 2u; side += 1u)
        {
            const unsigned int lane = (2u * pair) + side;
            const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
            long long in[BOUNDARY_TEST_SAMPLES];
            long long expected[BOUNDARY_TEST_SAMPLES];
            for (unsigned int at = 0u; at < n; at += 1u)
            {
                in[at] = boundary_field(atoms[((size_t)lane * n) + at]);
            }
            map(in, expected);
            int equal = 1;
            int back = 1;
            for (unsigned int at = 0u; at < n; at += 1u)
            {
                out[side][at] = boundary_read(record, &loaded->layout.step_table[program->outputs[at]]);
                equal = equal && (out[side][at] == expected[at]);
                if (readback != 0)
                {
                    back = back
                        && (boundary_read(record, &loaded->layout.step_table[program->outputs[n + at]]) == in[at]);
                }
            }
            mapped += (equal != 0) ? 1u : 0u;
            returned += (back != 0) ? 1u : 0u;
        }
        const unsigned int input = flip_at[pair];
        const unsigned int bit = flip_bit[pair];
        // a set bit cleared moves the value down by 2^b, a clear bit set moves it up
        const long long sign = (((atoms[((size_t)(2u * pair) * n) + input] >> bit) & 1u) != 0u) ? -1ll : 1ll;
        const int in_law = bit >= BOUNDARY_TEST_REACH;
        int law = 1;
        int within = 1;
        for (unsigned int at = 0u; at < n; at += 1u)
        {
            const long long move = out[1][at] - out[0][at];
            if (in_law != 0)
            {
                law = law && (move == (sign * matrix[at][input] * (1ll << (bit - BOUNDARY_TEST_REACH))));
            }
            if (move != 0ll)
            {
                const int reach = (int)bit - boundary_valuation(move);
                within = within && (reach <= (int)bound);
                seen = (reach > seen) ? reach : seen;
            }
        }
        lawful_pairs += (in_law != 0) ? 1u : 0u;
        lawful += ((in_law != 0) && (law != 0)) ? 1u : 0u;
        bounded += (within != 0) ? 1u : 0u;
    }
    *reach_seen = seen;
    scriptura_text(&tally->line, "  ");
    scriptura_text(&tally->line, name);
    scriptura_text(&tally->line, ": ");
    scriptura_decimal(&tally->line, program->count, 1u);
    scriptura_text(&tally->line, " steps, file ");
    scriptura_decimal(&tally->line, loaded->layout.file_limbs, 1u);
    scriptura_text(&tally->line, " limbs; ");
    scriptura_decimal(&tally->line, mapped, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, lanes, 1u);
    scriptura_text(&tally->line, " lanes equal the host's map");
    if (readback != 0)
    {
        scriptura_text(&tally->line, ", ");
        scriptura_decimal(&tally->line, returned, 1u);
        scriptura_text(&tally->line, " return their crystal exactly");
    }
    scriptura_text(&tally->line, "\n    flips: ");
    scriptura_decimal(&tally->line, lawful, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, lawful_pairs, 1u);
    scriptura_text(&tally->line, " at bit 12 or above move by exactly 2^b M e_i; ");
    scriptura_decimal(&tally->line, bounded, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, BOUNDARY_TEST_PAIRS, 1u);
    scriptura_text(&tally->line, " reach no further than ");
    scriptura_decimal(&tally->line, bound, 1u);
    scriptura_text(&tally->line, " bits below the flip; the furthest reach met is ");
    scriptura_signed(&tally->line, seen);
    scriptura_character(&tally->line, '\n');
    boundary_check(tally, ran != 0, "the program runs on the host and the device, and the records agree word for word");
    boundary_check(tally, narrow != 0, "every output fits a 64-bit word");
    boundary_check(tally, mapped == lanes, "every lane equals the host's map");
    if (readback != 0)
    {
        boundary_check(tally, returned == lanes, "a crystal written onto the boundary is read back exactly: T . T^-1 = id");
    }
    boundary_check(tally, (lawful_pairs != 0u) && (lawful == lawful_pairs),
                   "a flip at bit 3L or above moves the outputs by exactly 2^b times the matrix's column");
    boundary_check(tally, bounded == BOUNDARY_TEST_PAIRS, "no flip reaches further below itself than the bound");
    free(atoms);
    free(host_out);
    free(device_out);
    free(flip_at);
    free(flip_bit);
}

// the crystal band a coefficient lies in: 0 for the level-L lows, l for the highs of level l
static unsigned int boundary_band(unsigned int at)
{
    if (at < (BOUNDARY_TEST_SAMPLES >> BOUNDARY_TEST_LEVELS))
    {
        return 0u;
    }
    unsigned int level = BOUNDARY_TEST_LEVELS;
    while (at >= (BOUNDARY_TEST_SAMPLES >> (level - 1u)))
    {
        level -= 1u;
    }
    return level;
}

// T's reach read off its matrix per band, against the count: 3L for the level-L lows, 3l - 2 for the highs of level l
static void boundary_bands(BoundaryTally *tally)
{
    int reach[BOUNDARY_TEST_LEVELS + 1u];
    for (unsigned int band = 0u; band <= BOUNDARY_TEST_LEVELS; band += 1u)
    {
        reach[band] = -1000;
    }
    int inverse_reach = -1000;
    for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        const unsigned int band = boundary_band(at);
        const int here = boundary_row_reach(s_boundary_forward_matrix, at);
        reach[band] = (here > reach[band]) ? here : reach[band];
        const int back = boundary_row_reach(s_boundary_inverse_matrix, at);
        inverse_reach = (back > inverse_reach) ? back : inverse_reach;
    }
    int counted = reach[0] == (int)(3u * BOUNDARY_TEST_LEVELS);
    scriptura_text(&tally->line, "  bands: T's matrix reaches ");
    scriptura_signed(&tally->line, reach[0]);
    scriptura_text(&tally->line, " bits from the level-4 lows, and from the highs of levels 4 to 1");
    for (unsigned int level = BOUNDARY_TEST_LEVELS; level >= 1u; level -= 1u)
    {
        scriptura_character(&tally->line, ' ');
        scriptura_signed(&tally->line, reach[level]);
        counted = counted && (reach[level] == ((3 * (int)level) - 2));
    }
    scriptura_text(&tally->line, "; T^-1's matrix reaches ");
    scriptura_signed(&tally->line, inverse_reach);
    scriptura_text(&tally->line, " bits\n");
    boundary_check(tally, counted, "T's reach is 3l at the level-l lows and 3l - 2 at its highs, on the matrix");
    boundary_check(tally, inverse_reach == (int)BOUNDARY_TEST_INVERSE_REACH, "T^-1's reach is L + 2, on the matrix");
}

// write onto the boundary and read back: the fields are a crystal, T^-1 rebuilds the samples and T the crystal again.
// Flips of the crystal's bits are T^-1's precision.
static void boundary_written(BoundaryTally *tally)
{
    BoundaryProgram *const program = (BoundaryProgram *)calloc(1u, sizeof(BoundaryProgram));
    BoundaryTower *const back = (BoundaryTower *)calloc(1u, sizeof(BoundaryTower));
    BoundaryTower *const again = (BoundaryTower *)calloc(1u, sizeof(BoundaryTower));
    if ((program == NULL) || (back == NULL) || (again == NULL))
    {
        boundary_check(tally, 0, "the written boundary is held");
        free(program);
        free(back);
        free(again);
        return;
    }
    unsigned int crystal[BOUNDARY_TEST_SAMPLES];
    for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        crystal[at] = boundary_emit(program, ENGINE_RECORD_FIELD_SIGNED, at, 0u);
    }
    boundary_inverse(program, crystal, NULL, NULL, back, BOUNDARY_TEST_SAMPLES, BOUNDARY_TEST_LEVELS);
    memcpy(again->low[0], back->low[0], sizeof(again->low[0]));
    boundary_forward(program, again, BOUNDARY_TEST_SAMPLES, BOUNDARY_TEST_LEVELS);
    for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        boundary_output(program, back->low[0][at]);
    }
    for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        boundary_output(program, again->crystal[at]);
    }
    BoundaryLoaded loaded;
    const int loads = boundary_load(program, BOUNDARY_TEST_SAMPLES, &loaded);
    boundary_check(tally, loads, "T^-1 then T over a written crystal imprints, lays with reuse and loads");
    if (loads != 0)
    {
        int reach = 0;
        boundary_precision(tally, &loaded, program, boundary_host_inverse, s_boundary_inverse_matrix,
                           BOUNDARY_TEST_INVERSE_REACH, 1, "written (T^-1 then T)", &reach);
        boundary_check(tally, reach == (int)BOUNDARY_TEST_INVERSE_REACH, "T^-1's reach L + 2 is met on the device");
        boundary_free(&loaded);
    }
    free(program);
    free(back);
    free(again);
}

// T alone over the samples: its precision, then what passes through it
static void boundary_through(BoundaryTally *tally, BoundaryLoaded *loaded, const BoundaryProgram *program);

static void boundary_read_off(BoundaryTally *tally)
{
    BoundaryProgram *const program = (BoundaryProgram *)calloc(1u, sizeof(BoundaryProgram));
    BoundaryTower *const tower = (BoundaryTower *)calloc(1u, sizeof(BoundaryTower));
    if ((program == NULL) || (tower == NULL))
    {
        boundary_check(tally, 0, "the forward tower is held");
        free(program);
        free(tower);
        return;
    }
    for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        tower->low[0][at] = boundary_emit(program, ENGINE_RECORD_FIELD_SIGNED, at, 0u);
    }
    boundary_forward(program, tower, BOUNDARY_TEST_SAMPLES, BOUNDARY_TEST_LEVELS);
    for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        boundary_output(program, tower->crystal[at]);
    }
    BoundaryLoaded loaded;
    const int loads = boundary_load(program, BOUNDARY_TEST_SAMPLES, &loaded);
    boundary_check(tally, loads, "T over 64 samples imprints, lays with reuse and loads");
    if (loads != 0)
    {
        int reach = 0;
        boundary_precision(tally, &loaded, program, boundary_host_forward, s_boundary_forward_matrix,
                           BOUNDARY_TEST_REACH, 0, "read off (T)", &reach);
        boundary_check(tally, reach == (int)BOUNDARY_TEST_REACH, "T's reach 3L is met on the device");
        boundary_through(tally, &loaded, program);
        boundary_free(&loaded);
    }
    free(program);
    free(tower);
}

// what passes through T, one kind per quarter of the pairs: a constant c added to every sample must move only the
// crystal's lows, each by c; a vector 2^(3L) z must move the crystal by M z exactly; negation and doubling are
// counted where they pass
static void boundary_through(BoundaryTally *tally, BoundaryLoaded *loaded, const BoundaryProgram *program)
{
    const unsigned int n = BOUNDARY_TEST_SAMPLES;
    const unsigned int lows = BOUNDARY_TEST_SAMPLES >> BOUNDARY_TEST_LEVELS;
    const unsigned int lanes = 2u * BOUNDARY_TEST_PAIRS;
    const unsigned int out_limbs = loaded->layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * n, sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    long long *const added = (long long *)calloc((size_t)BOUNDARY_TEST_PAIRS * n, sizeof(long long));
    const int buffers = (atoms != NULL) && (host_out != NULL) && (device_out != NULL) && (added != NULL);
    for (unsigned int pair = 0u; (buffers != 0) && (pair < BOUNDARY_TEST_PAIRS); pair += 1u)
    {
        const unsigned int kind = pair % 4u;
        // a constant below 2^19 in magnitude, shared by every sample
        const long long constant = (long long)(boundary_random() & 0xFFFFFu) - (1ll << 19u);
        for (unsigned int at = 0u; at < n; at += 1u)
        {
            // a base sample below 2^21 in magnitude, so every moved sample stays inside the field
            const long long base = (long long)(boundary_random() & 0x3FFFFFu) - (1ll << 21u);
            long long moved = base;
            if (kind == 0u)
            {
                added[((size_t)pair * n) + at] = constant;
                moved = base + constant;
            }
            else if (kind == 1u)
            {
                const long long lattice = (long long)(boundary_random() & 0xFFu) - 128ll;
                added[((size_t)pair * n) + at] = lattice;
                moved = base + (lattice * (1ll << BOUNDARY_TEST_REACH));
            }
            else if (kind == 2u)
            {
                moved = -base;
            }
            else
            {
                moved = 2ll * base;
            }
            atoms[((size_t)(2u * pair) * n) + at] = boundary_word(base);
            atoms[((size_t)((2u * pair) + 1u) * n) + at] = boundary_word(moved);
        }
    }
    const int ran = (buffers != 0) && (boundary_run(loaded, atoms, lanes, host_out, device_out) != 0);
    unsigned int passed[4] = {0u, 0u, 0u, 0u};
    for (unsigned int pair = 0u; (ran != 0) && (pair < BOUNDARY_TEST_PAIRS); pair += 1u)
    {
        const unsigned int kind = pair % 4u;
        const unsigned int *const base = &device_out[(size_t)(2u * pair) * out_limbs];
        const unsigned int *const moved = &device_out[(size_t)((2u * pair) + 1u) * out_limbs];
        int passes = 1;
        for (unsigned int at = 0u; at < n; at += 1u)
        {
            const DeviceRecordStep *const step = &loaded->layout.step_table[program->outputs[at]];
            const long long before = boundary_read(base, step);
            const long long after = boundary_read(moved, step);
            long long expected = 0ll;
            if (kind == 0u)
            {
                expected = before + ((at < lows) ? added[(size_t)pair * n] : 0ll);
            }
            else if (kind == 1u)
            {
                expected = before;
                for (unsigned int input = 0u; input < n; input += 1u)
                {
                    expected += s_boundary_forward_matrix[at][input] * added[((size_t)pair * n) + input];
                }
            }
            else if (kind == 2u)
            {
                expected = -before;
            }
            else
            {
                expected = 2ll * before;
            }
            passes = passes && (after == expected);
        }
        passed[kind] += (passes != 0) ? 1u : 0u;
    }
    const unsigned int each = BOUNDARY_TEST_PAIRS / 4u;
    scriptura_text(&tally->line, "  through T, of ");
    scriptura_decimal(&tally->line, each, 1u);
    scriptura_text(&tally->line, " pairs each: a constant lands on the lows alone on ");
    scriptura_decimal(&tally->line, passed[0], 1u);
    scriptura_text(&tally->line, ", 2^12 z lands as M z on ");
    scriptura_decimal(&tally->line, passed[1], 1u);
    scriptura_text(&tally->line, "; negation passes on ");
    scriptura_decimal(&tally->line, passed[2], 1u);
    scriptura_text(&tally->line, ", doubling on ");
    scriptura_decimal(&tally->line, passed[3], 1u);
    scriptura_character(&tally->line, '\n');
    boundary_check(tally, ran != 0, "the pairs run on the host and the device, word for word");
    boundary_check(tally, passed[0] == each, "a constant on every sample moves only the crystal's lows, each by it");
    boundary_check(tally, passed[1] == each, "a vector in 2^(3L) Z^n moves the crystal by M times it exactly");
    boundary_check(tally, (passed[2] < each) && (passed[3] < each), "negation and doubling do not pass through T");
    free(atoms);
    free(host_out);
    free(device_out);
    free(added);
}

// one lane's samples in a complexity class: 0 a ramp, 1 a ramp +-8, 2 a ramp +-1024, 3 noise over the field
static void boundary_class_fill(unsigned int *atom, unsigned int kind)
{
    const long long start = (long long)(boundary_random() & 0xFFFFFu) - (1ll << 19u);
    const long long slope = (long long)(boundary_random() & 0xFFFu) - 2048ll;
    for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        long long value = start + (slope * (long long)at);
        if (kind == 1u)
        {
            value += (long long)(boundary_random() % 17u) - 8ll;
        }
        else if (kind == 2u)
        {
            value += (long long)(boundary_random() % 2049u) - 1024ll;
        }
        atom[at] = (kind == 3u) ? (boundary_random() & ((1u << BOUNDARY_TEST_FIELD_BITS) - 1u)) : boundary_word(value);
    }
}

// a value's heap: its magnitude's bits and a sign bit where it is not zero
static unsigned int boundary_heap(long long value)
{
    // the magnitude of any value here is below 2^63
    unsigned long long magnitude = (value < 0ll) ? (unsigned long long)(-value) : (unsigned long long)value;
    unsigned int bits = 0u;
    while (magnitude != 0ull)
    {
        magnitude >>= 1u;
        bits += 1u;
    }
    return (bits == 0u) ? 0u : (bits + 1u);
}

// the registers standing at floor k of T then T^-1: at a forward floor l the level-l lows and the highs of levels 1
// to l, at the mirror floor 2L - l the rebuilt lows and the same highs
static unsigned int boundary_floor_registers(const BoundaryTower *tower, const BoundaryTower *back, unsigned int floor,
                                             unsigned int *registers)
{
    const unsigned int level = (floor <= BOUNDARY_TEST_LEVELS) ? floor : ((2u * BOUNDARY_TEST_LEVELS) - floor);
    const unsigned int lows = BOUNDARY_TEST_SAMPLES >> level;
    const BoundaryTower *const side = (floor <= BOUNDARY_TEST_LEVELS) ? tower : back;
    unsigned int count = 0u;
    for (unsigned int at = 0u; at < lows; at += 1u)
    {
        registers[count] = side->low[level][at];
        count += 1u;
    }
    for (unsigned int at = lows; at < BOUNDARY_TEST_SAMPLES; at += 1u)
    {
        registers[count] = tower->crystal[at];
        count += 1u;
    }
    return count;
}

// T then T^-1 with the mirror wraps, every floor's registers an output: the ring from the imprint's widths, the heap
// from the device's values, per floor, per class
static void boundary_floors(BoundaryTally *tally)
{
    BoundaryProgram *const program = (BoundaryProgram *)calloc(1u, sizeof(BoundaryProgram));
    BoundaryTower *const tower = (BoundaryTower *)calloc(1u, sizeof(BoundaryTower));
    BoundaryTower *const back = (BoundaryTower *)calloc(1u, sizeof(BoundaryTower));
    if ((program == NULL) || (tower == NULL) || (back == NULL))
    {
        boundary_check(tally, 0, "the floors are held");
        free(program);
        free(tower);
        free(back);
        return;
    }
    const unsigned int n = BOUNDARY_TEST_SAMPLES;
    for (unsigned int at = 0u; at < n; at += 1u)
    {
        tower->low[0][at] = boundary_emit(program, ENGINE_RECORD_FIELD_SIGNED, at, 0u);
    }
    boundary_forward(program, tower, BOUNDARY_TEST_SAMPLES, BOUNDARY_TEST_LEVELS);
    for (unsigned int at = 0u; at < n; at += 1u)
    {
        boundary_output(program, tower->crystal[at]);
    }
    // the forward's widths, imprinted alone, set the mirror wraps
    EngineRecordKey twin_key;
    EngineError twin_error;
    memset(&twin_key, 0, sizeof(twin_key));
    const int twin = boundary_imprint(program, program->count, n, &twin_key, &twin_error);
    boundary_check(tally, twin, "the forward tower imprints alone for its widths");
    if (twin == 0)
    {
        free(program);
        free(tower);
        free(back);
        return;
    }
    boundary_inverse(program, tower->crystal, tower, &twin_key, back, BOUNDARY_TEST_SAMPLES, BOUNDARY_TEST_LEVELS);
    keymath_record_release(&twin_key);
    program->output_count = 0u;
    for (unsigned int level = 0u; level < BOUNDARY_TEST_LEVELS; level += 1u)
    {
        for (unsigned int at = 0u; at < (n >> level); at += 1u)
        {
            boundary_output(program, tower->low[level][at]);
            boundary_output(program, back->low[level][at]);
        }
    }
    for (unsigned int at = 0u; at < n; at += 1u)
    {
        boundary_output(program, tower->crystal[at]);
    }
    BoundaryLoaded loaded;
    const int loads = boundary_load(program, n, &loaded);
    boundary_check(tally, loads, "T then T^-1 with mirror wraps, every floor an output, imprints and loads");
    if (loads == 0)
    {
        free(program);
        free(tower);
        free(back);
        return;
    }
    // each output register's place in the record, by register
    unsigned int *const place = (unsigned int *)calloc(program->count, sizeof(unsigned int));
    const unsigned int lanes = BOUNDARY_TEST_CLASSES * BOUNDARY_TEST_CLASS_LANES;
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * n, sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    const int buffers = (place != NULL) && (atoms != NULL) && (host_out != NULL) && (device_out != NULL);
    for (unsigned int lane = 0u; (buffers != 0) && (lane < lanes); lane += 1u)
    {
        boundary_class_fill(&atoms[(size_t)lane * n], lane / BOUNDARY_TEST_CLASS_LANES);
    }
    const int ran = (buffers != 0) && (boundary_run(&loaded, atoms, lanes, host_out, device_out) != 0);
    const int narrow = boundary_narrow_enough(&loaded, program);
    unsigned long long ring[BOUNDARY_TEST_FLOORS];
    unsigned long long heap[BOUNDARY_TEST_CLASSES][BOUNDARY_TEST_FLOORS];
    memset(heap, 0, sizeof(heap));
    unsigned int registers[BOUNDARY_TEST_FLOORS][BOUNDARY_TEST_SAMPLES];
    unsigned int counts[BOUNDARY_TEST_FLOORS];
    for (unsigned int floor = 0u; floor < BOUNDARY_TEST_FLOORS; floor += 1u)
    {
        counts[floor] = boundary_floor_registers(tower, back, floor, registers[floor]);
        ring[floor] = 0ull;
        for (unsigned int at = 0u; at < counts[floor]; at += 1u)
        {
            ring[floor] += (unsigned long long)loaded.key.term[registers[floor][at]].bits;
        }
    }
    unsigned int mirrored = 0u;
    unsigned int rebuilt = 0u;
    unsigned int within = 0u;
    for (unsigned int lane = 0u; (ran != 0) && (narrow != 0) && (lane < lanes); lane += 1u)
    {
        const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
        unsigned long long lane_heap[BOUNDARY_TEST_FLOORS];
        int fits = 1;
        for (unsigned int floor = 0u; floor < BOUNDARY_TEST_FLOORS; floor += 1u)
        {
            lane_heap[floor] = 0ull;
            unsigned long long nonzero = 0ull;
            for (unsigned int at = 0u; at < counts[floor]; at += 1u)
            {
                const long long value = boundary_read(record, &loaded.layout.step_table[registers[floor][at]]);
                lane_heap[floor] += boundary_heap(value);
                nonzero += (value != 0ll) ? 1ull : 0ull;
            }
            fits = fits && (lane_heap[floor] <= (ring[floor] + nonzero));
            heap[lane / BOUNDARY_TEST_CLASS_LANES][floor] += lane_heap[floor];
        }
        int mirror = 1;
        for (unsigned int floor = 0u; floor < BOUNDARY_TEST_FLOORS; floor += 1u)
        {
            mirror = mirror && (lane_heap[floor] == lane_heap[(2u * BOUNDARY_TEST_LEVELS) - floor]);
        }
        int samples = 1;
        for (unsigned int at = 0u; at < n; at += 1u)
        {
            const long long value = boundary_read(record, &loaded.layout.step_table[back->low[0][at]]);
            samples = samples && (value == boundary_field(atoms[((size_t)lane * n) + at]));
        }
        mirrored += (mirror != 0) ? 1u : 0u;
        rebuilt += (samples != 0) ? 1u : 0u;
        within += (fits != 0) ? 1u : 0u;
    }
    int ring_forward = 1;
    int ring_mirror = 1;
    int ring_widest = 1;
    for (unsigned int level = 0u; level <= BOUNDARY_TEST_LEVELS; level += 1u)
    {
        ring_forward = ring_forward && (ring[level] == (ring[0] + (6ull * (unsigned long long)(n - (n >> level)))));
        ring_widest = ring_widest && (ring[level] <= ring[BOUNDARY_TEST_LEVELS]);
        if (level < BOUNDARY_TEST_LEVELS)
        {
            ring_mirror = ring_mirror
                       && (ring[(2u * BOUNDARY_TEST_LEVELS) - level] == (ring[level] + (unsigned long long)(n >> level)));
            ring_widest = ring_widest && (ring[(2u * BOUNDARY_TEST_LEVELS) - level] <= ring[BOUNDARY_TEST_LEVELS]);
        }
    }
    scriptura_text(&tally->line, "  floors: ");
    scriptura_decimal(&tally->line, program->count, 1u);
    scriptura_text(&tally->line, " steps, file ");
    scriptura_decimal(&tally->line, loaded.layout.file_limbs, 1u);
    scriptura_text(&tally->line, " limbs, ");
    scriptura_decimal(&tally->line, program->output_count, 1u);
    scriptura_text(&tally->line, " outputs; ");
    scriptura_decimal(&tally->line, rebuilt, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, lanes, 1u);
    scriptura_text(&tally->line, " lanes rebuilt, ");
    scriptura_decimal(&tally->line, mirrored, 1u);
    scriptura_text(&tally->line, " with the heap mirrored at every floor, ");
    scriptura_decimal(&tally->line, within, 1u);
    scriptura_text(&tally->line, " inside the ring\n    ring by floor:");
    for (unsigned int floor = 0u; floor < BOUNDARY_TEST_FLOORS; floor += 1u)
    {
        scriptura_character(&tally->line, ' ');
        scriptura_decimal(&tally->line, ring[floor], 1u);
    }
    scriptura_character(&tally->line, '\n');
    const char *const names[BOUNDARY_TEST_CLASSES] = {"ramp", "ramp +-8", "ramp +-1024", "noise"};
    unsigned long long pinch_top[BOUNDARY_TEST_CLASSES];
    unsigned long long pinch_bottom[BOUNDARY_TEST_CLASSES];
    for (unsigned int kind = 0u; kind < BOUNDARY_TEST_CLASSES; kind += 1u)
    {
        scriptura_text(&tally->line, "    heap by floor, ");
        scriptura_text(&tally->line, names[kind]);
        scriptura_text(&tally->line, ":");
        for (unsigned int floor = 0u; floor < BOUNDARY_TEST_FLOORS; floor += 1u)
        {
            scriptura_character(&tally->line, ' ');
            scriptura_decimal(&tally->line, heap[kind][floor] / BOUNDARY_TEST_CLASS_LANES, 1u);
        }
        pinch_top[kind] = heap[kind][0];
        pinch_bottom[kind] = heap[kind][BOUNDARY_TEST_LEVELS];
        scriptura_text(&tally->line, "; pinch ");
        boundary_hundredths(&tally->line, pinch_top[kind], pinch_bottom[kind]);
        scriptura_character(&tally->line, '\n');
    }
    int ordered = 1;
    for (unsigned int kind = 1u; kind < BOUNDARY_TEST_CLASSES; kind += 1u)
    {
        // pinch[kind - 1] > pinch[kind], cross-multiplied; every sum is below 2^40
        ordered = ordered && ((pinch_top[kind - 1u] * pinch_bottom[kind]) > (pinch_top[kind] * pinch_bottom[kind - 1u]));
    }
    boundary_check(tally, ran != 0, "the floors run on the host and the device, word for word");
    boundary_check(tally, narrow != 0, "every floor's register fits a 64-bit word");
    boundary_check(tally, rebuilt == lanes, "the last floor returns every sample exactly");
    boundary_check(tally, mirrored == lanes, "the heap at floor 2L - k equals the heap at floor k, every lane");
    boundary_check(tally, within == lanes, "every floor's heap lies inside its ring and one sign bit per nonzero value");
    boundary_check(tally, ring_forward, "the ring at forward floor l is ring_0 + 6(n - n / 2^l)");
    boundary_check(tally, ring_mirror, "the ring at floor 2L - l is the ring at floor l and one bit per wrapped low");
    boundary_check(tally, ring_widest, "the ring is widest at the crystal");
    boundary_check(tally, ordered, "the heap's pinch at the crystal falls from ramp to +-8 to +-1024 to noise");
    free(place);
    free(atoms);
    free(host_out);
    free(device_out);
    free(program);
    free(tower);
    free(back);
    boundary_free(&loaded);
}

// the top projection x -> x / 2^k toward zero, the machine's own quotient by a power of two, against the 2-adic
// projection's wrap: nested quotients by 2^k and by c commute, a comparison through it is never reversed, and a sum
// through it is off by at most one. The comparison through an 8-bit wrap is counted where it reverses.
static void boundary_top(BoundaryTally *tally)
{
    const unsigned int shifts[BOUNDARY_TEST_TOP_SETTINGS] = {3u, 7u, 5u};
    const unsigned int divisors[BOUNDARY_TEST_TOP_SETTINGS] = {3u, 5u, 12345u};
    const unsigned int lanes = BOUNDARY_TEST_TOP_LANES;
    unsigned long long commuted = 0ull;
    unsigned long long kept = 0ull;
    unsigned long long tied = 0ull;
    unsigned long long near = 0ull;
    unsigned long long carried = 0ull;
    unsigned long long reversed = 0ull;
    int ran_all = 1;
    for (unsigned int setting = 0u; setting < BOUNDARY_TEST_TOP_SETTINGS; setting += 1u)
    {
        BoundaryProgram *const program = (BoundaryProgram *)calloc(1u, sizeof(BoundaryProgram));
        if (program == NULL)
        {
            ran_all = 0;
            continue;
        }
        const unsigned int x = boundary_emit(program, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u);
        const unsigned int y = boundary_emit(program, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u);
        const unsigned int power = boundary_emit(program, ENGINE_RECORD_CONSTANT, 1u << shifts[setting], 0u);
        const unsigned int divisor = boundary_emit(program, ENGINE_RECORD_CONSTANT, divisors[setting], 0u);
        const unsigned int top_x = boundary_emit(program, ENGINE_RECORD_QUOTIENT, x, power);
        const unsigned int top_first = boundary_emit(program, ENGINE_RECORD_QUOTIENT, top_x, divisor);
        const unsigned int divided = boundary_emit(program, ENGINE_RECORD_QUOTIENT, x, divisor);
        const unsigned int top_last = boundary_emit(program, ENGINE_RECORD_QUOTIENT, divided, power);
        const unsigned int order = boundary_emit(program, ENGINE_RECORD_COMPARE, x, y);
        const unsigned int top_y = boundary_emit(program, ENGINE_RECORD_QUOTIENT, y, power);
        const unsigned int top_order = boundary_emit(program, ENGINE_RECORD_COMPARE, top_x, top_y);
        const unsigned int sum = boundary_emit(program, ENGINE_RECORD_SUM, x, y);
        const unsigned int top_sum = boundary_emit(program, ENGINE_RECORD_QUOTIENT, sum, power);
        const unsigned int sum_top = boundary_emit(program, ENGINE_RECORD_SUM, top_x, top_y);
        const unsigned int wrapped_x = boundary_emit(program, ENGINE_RECORD_WRAP, x, 8u);
        const unsigned int wrapped_y = boundary_emit(program, ENGINE_RECORD_WRAP, y, 8u);
        const unsigned int wrapped_order = boundary_emit(program, ENGINE_RECORD_COMPARE, wrapped_x, wrapped_y);
        const unsigned int outputs[7] = {top_first, top_last, order, top_order, top_sum, sum_top, wrapped_order};
        for (unsigned int at = 0u; at < 7u; at += 1u)
        {
            boundary_output(program, outputs[at]);
        }
        BoundaryLoaded loaded;
        if (boundary_load(program, 2u, &loaded) == 0)
        {
            ran_all = 0;
            free(program);
            continue;
        }
        const unsigned int out_limbs = loaded.layout.out_limbs;
        unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * 2u, sizeof(unsigned int));
        unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
        unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
        const int buffers = (atoms != NULL) && (host_out != NULL) && (device_out != NULL);
        for (unsigned int word = 0u; (buffers != 0) && (word < (2u * lanes)); word += 1u)
        {
            atoms[word] = boundary_random() & ((1u << BOUNDARY_TEST_FIELD_BITS) - 1u);
        }
        const int ran = (buffers != 0) && (boundary_run(&loaded, atoms, lanes, host_out, device_out) != 0);
        ran_all = ran_all && ran && boundary_narrow_enough(&loaded, program);
        for (unsigned int lane = 0u; (ran != 0) && (lane < lanes); lane += 1u)
        {
            const unsigned int *const record = &device_out[(size_t)lane * out_limbs];
            long long value[7];
            for (unsigned int at = 0u; at < 7u; at += 1u)
            {
                value[at] = boundary_read(record, &loaded.layout.step_table[outputs[at]]);
            }
            commuted += (value[0] == value[1]) ? 1ull : 0ull;
            kept += ((value[3] == 0ll) || (value[3] == value[2])) ? 1ull : 0ull;
            tied += ((value[3] == 0ll) && (value[2] != 0ll)) ? 1ull : 0ull;
            const long long off = value[4] - value[5];
            near += ((off >= -1ll) && (off <= 1ll)) ? 1ull : 0ull;
            carried += (off != 0ll) ? 1ull : 0ull;
            reversed += ((value[6] != 0ll) && (value[6] == -value[2])) ? 1ull : 0ull;
        }
        free(atoms);
        free(host_out);
        free(device_out);
        free(program);
        boundary_free(&loaded);
    }
    const unsigned long long total = (unsigned long long)BOUNDARY_TEST_TOP_SETTINGS * lanes;
    scriptura_text(&tally->line, "  top projection, x / 2^k for k = 3, 7, 5 and c = 3, 5, 12345 over ");
    scriptura_decimal(&tally->line, total, 1u);
    scriptura_text(&tally->line, " lanes: nested quotients agree on ");
    scriptura_decimal(&tally->line, commuted, 1u);
    scriptura_text(&tally->line, ", the order is kept on ");
    scriptura_decimal(&tally->line, kept, 1u);
    scriptura_text(&tally->line, " (tied on ");
    scriptura_decimal(&tally->line, tied, 1u);
    scriptura_text(&tally->line, "), the sum is within one on ");
    scriptura_decimal(&tally->line, near, 1u);
    scriptura_text(&tally->line, " (carried on ");
    scriptura_decimal(&tally->line, carried, 1u);
    scriptura_text(&tally->line, "); the 8-bit wrap reverses the order on ");
    scriptura_decimal(&tally->line, reversed, 1u);
    scriptura_character(&tally->line, '\n');
    boundary_check(tally, ran_all != 0, "the top projections run on the host and the device, word for word");
    boundary_check(tally, commuted == total, "the quotient by c passes through the top projection: (x / 2^k) / c = (x / c) / 2^k");
    boundary_check(tally, kept == total, "the top projection never reverses a comparison, it only ties");
    boundary_check(tally, (near == total) && (carried != 0ull),
                   "a sum through the top projection is off by the carry from below, at most one");
    boundary_check(tally, reversed != 0ull, "the 8-bit wrap reverses comparisons the top projection keeps");
}

// Haar measure counted: a tower of 4 samples and one level, whose reach each way is 3 bits. Every input quantum at
// level w + 3 runs through the map and the output's quantum at level w is tallied. The map's low w bits read only the
// inputs' low w + 3, so the map on quanta is well defined, and a map that keeps Haar measure sends exactly 2^(4 . 3)
// input quanta onto every output quantum, from any window of representatives.
static void boundary_counted(BoundaryTally *tally)
{
    const unsigned int samples = BOUNDARY_TEST_COUNT_SAMPLES;
    unsigned int runs = 0u;
    unsigned int balanced = 0u;
    int ran_all = 1;
    for (unsigned int inverse = 0u; inverse < 2u; inverse += 1u)
    {
        BoundaryProgram *const program = (BoundaryProgram *)calloc(1u, sizeof(BoundaryProgram));
        BoundaryTower *const tower = (BoundaryTower *)calloc(1u, sizeof(BoundaryTower));
        if ((program == NULL) || (tower == NULL))
        {
            ran_all = 0;
            free(program);
            free(tower);
            continue;
        }
        unsigned int fields[BOUNDARY_TEST_COUNT_SAMPLES];
        for (unsigned int at = 0u; at < samples; at += 1u)
        {
            fields[at] = boundary_emit(program, ENGINE_RECORD_FIELD_SIGNED, at, 0u);
            tower->low[0][at] = fields[at];
        }
        const unsigned int *mapped = tower->crystal;
        if (inverse == 0u)
        {
            boundary_forward(program, tower, samples, 1u);
        }
        else
        {
            boundary_inverse(program, fields, NULL, NULL, tower, samples, 1u);
            mapped = tower->low[0];
        }
        for (unsigned int at = 0u; at < samples; at += 1u)
        {
            boundary_output(program, mapped[at]);
        }
        BoundaryLoaded loaded;
        if (boundary_load(program, samples, &loaded) == 0)
        {
            ran_all = 0;
            free(program);
            free(tower);
            continue;
        }
        for (unsigned int width = 1u; width <= 2u; width += 1u)
        {
            const unsigned int digit = width + BOUNDARY_TEST_COUNT_REACH;
            const unsigned int lanes = 1u << (samples * digit);
            const unsigned int buckets = 1u << (samples * width);
            const unsigned int out_limbs = loaded.layout.out_limbs;
            for (unsigned int shifted = 0u; shifted < 2u; shifted += 1u)
            {
                // representatives from [0, 2^(w+3)) or from [-2^(w+2), 2^(w+2))
                const long long window = (shifted == 0u) ? 0ll : -(1ll << (digit - 1u));
                unsigned int *const atoms = (unsigned int *)calloc((size_t)lanes * samples, sizeof(unsigned int));
                unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
                unsigned int *const device_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
                unsigned int *const tallied = (unsigned int *)calloc(buckets, sizeof(unsigned int));
                const int buffers = (atoms != NULL) && (host_out != NULL) && (device_out != NULL) && (tallied != NULL);
                for (unsigned int lane = 0u; (buffers != 0) && (lane < lanes); lane += 1u)
                {
                    for (unsigned int at = 0u; at < samples; at += 1u)
                    {
                        const long long quantum = (long long)((lane >> (at * digit)) & ((1u << digit) - 1u));
                        atoms[((size_t)lane * samples) + at] = boundary_word(quantum + window);
                    }
                }
                const int ran = (buffers != 0) && (boundary_run(&loaded, atoms, lanes, host_out, device_out) != 0);
                ran_all = ran_all && ran && boundary_narrow_enough(&loaded, program);
                for (unsigned int lane = 0u; (ran != 0) && (lane < lanes); lane += 1u)
                {
                    unsigned int bucket = 0u;
                    for (unsigned int at = 0u; at < samples; at += 1u)
                    {
                        const long long value = boundary_read(&device_out[(size_t)lane * out_limbs],
                                                              &loaded.layout.step_table[program->outputs[at]]);
                        // the value's low w bits of two's complement are its quantum at level w
                        const unsigned int quantum = (unsigned int)((unsigned long long)value & ((1ull << width) - 1ull));
                        bucket |= quantum << (at * width);
                    }
                    tallied[bucket] += 1u;
                }
                int even = ran;
                for (unsigned int bucket = 0u; bucket < buckets; bucket += 1u)
                {
                    even = even && (tallied[bucket] == (lanes / buckets));
                }
                runs += 1u;
                balanced += (even != 0) ? 1u : 0u;
                free(atoms);
                free(host_out);
                free(device_out);
                free(tallied);
            }
        }
        boundary_free(&loaded);
        free(program);
        free(tower);
    }
    scriptura_text(&tally->line, "  counted: T and T^-1 over 4 samples and one level, every input quantum at level w + 3 for w = 1 "
                                 "and 2, from two windows; ");
    scriptura_decimal(&tally->line, balanced, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, runs, 1u);
    scriptura_text(&tally->line, " runs send exactly 4096 input quanta onto every output quantum\n");
    boundary_check(tally, ran_all != 0, "the counted towers run on the host and the device, word for word");
    boundary_check(tally, (runs == 8u) && (balanced == runs),
                   "T and T^-1 keep Haar measure: every output quantum at level w has 2^12 input quanta at level w + 3");
}

static unsigned long long boundary_power_mod(unsigned long long base, unsigned long long exponent,
                                             unsigned long long modulus)
{
    unsigned long long result = 1ull % modulus;
    unsigned long long square = base % modulus;
    while (exponent != 0ull)
    {
        if ((exponent & 1ull) != 0ull)
        {
            result = (result * square) % modulus;
        }
        square = (square * square) % modulus;
        exponent >>= 1u;
    }
    return result;
}

// the greatest prime below `above`, by trial division
static unsigned long long boundary_prime_below(unsigned long long above)
{
    for (unsigned long long candidate = above - 1ull; candidate > 2ull; candidate -= 1ull)
    {
        int prime = (candidate & 1ull) != 0ull;
        for (unsigned long long divisor = 3ull; (prime != 0) && ((divisor * divisor) <= candidate); divisor += 2ull)
        {
            prime = (candidate % divisor) != 0ull;
        }
        if (prime != 0)
        {
            return candidate;
        }
    }
    return 2ull;
}

// a matrix's determinant modulo a prime below 2^31, by elimination over Z/p
static unsigned long long boundary_determinant_mod(const long long (*matrix)[BOUNDARY_TEST_SAMPLES],
                                                   unsigned long long prime)
{
    static unsigned long long s_work[BOUNDARY_TEST_SAMPLES][BOUNDARY_TEST_SAMPLES];
    const unsigned int n = BOUNDARY_TEST_SAMPLES;
    for (unsigned int row = 0u; row < n; row += 1u)
    {
        for (unsigned int column = 0u; column < n; column += 1u)
        {
            // the residue in [0, p): a prime below 2^31 fits a long long's range as is
            const long long residue = matrix[row][column] % (long long)prime;
            s_work[row][column] = (unsigned long long)((residue < 0ll) ? (residue + (long long)prime) : residue);
        }
    }
    unsigned long long determinant = 1ull;
    for (unsigned int column = 0u; column < n; column += 1u)
    {
        unsigned int pivot = column;
        while ((pivot < n) && (s_work[pivot][column] == 0ull))
        {
            pivot += 1u;
        }
        if (pivot == n)
        {
            return 0ull;
        }
        if (pivot != column)
        {
            for (unsigned int at = 0u; at < n; at += 1u)
            {
                const unsigned long long held = s_work[pivot][at];
                s_work[pivot][at] = s_work[column][at];
                s_work[column][at] = held;
            }
            determinant = (prime - determinant) % prime;
        }
        determinant = (determinant * s_work[column][column]) % prime;
        const unsigned long long inverse = boundary_power_mod(s_work[column][column], prime - 2ull, prime);
        for (unsigned int row = column + 1u; row < n; row += 1u)
        {
            const unsigned long long factor = (s_work[row][column] * inverse) % prime;
            for (unsigned int at = column; at < n; at += 1u)
            {
                s_work[row][at] = (s_work[row][at] + prime - ((factor * s_work[column][at]) % prime)) % prime;
            }
        }
    }
    return determinant;
}

// the determinant of 2^REACH M against +-2^(REACH . n), modulo enough primes that their product passes Hadamard's
// bound on |det - (+-2^(REACH . n))|: agreement modulo all of them is equality. The sign found comes back in `sign`.
static int boundary_unimodular(const long long (*matrix)[BOUNDARY_TEST_SAMPLES], int *sign, double *bound_bits)
{
    const unsigned int n = BOUNDARY_TEST_SAMPLES;
    double hadamard = 0.0;
    for (unsigned int column = 0u; column < n; column += 1u)
    {
        double norm = 0.0;
        for (unsigned int row = 0u; row < n; row += 1u)
        {
            norm += (double)matrix[row][column] * (double)matrix[row][column];
        }
        hadamard += 0.5 * log2(norm);
    }
    const double scale_bits = (double)(BOUNDARY_TEST_REACH * n);
    const double needed = ((hadamard > scale_bits) ? hadamard : scale_bits) + 2.0;
    *bound_bits = needed;
    double product_bits = 0.0;
    unsigned int plus = 0u;
    unsigned int minus = 0u;
    unsigned int primes = 0u;
    unsigned long long prime = 1ull << 31u;
    while (product_bits <= needed)
    {
        prime = boundary_prime_below(prime);
        const unsigned long long determinant = boundary_determinant_mod(matrix, prime);
        const unsigned long long scale = boundary_power_mod(2ull, (unsigned long long)BOUNDARY_TEST_REACH * n, prime);
        plus += (determinant == scale) ? 1u : 0u;
        minus += (determinant == ((prime - scale) % prime)) ? 1u : 0u;
        primes += 1u;
        product_bits += log2((double)prime);
    }
    *sign = (plus == primes) ? 1 : ((minus == primes) ? -1 : 0);
    return *sign != 0;
}

// the rational maps' volumes: det M and det M^-1 are +-1 exactly, and M times M^-1 is the identity
static void boundary_volume(BoundaryTally *tally)
{
    int forward_sign = 0;
    int inverse_sign = 0;
    double forward_bits = 0.0;
    double inverse_bits = 0.0;
    const int forward = boundary_unimodular(s_boundary_forward_matrix, &forward_sign, &forward_bits);
    const int inverse = boundary_unimodular(s_boundary_inverse_matrix, &inverse_sign, &inverse_bits);
    int identity = 1;
    for (unsigned int row = 0u; row < BOUNDARY_TEST_SAMPLES; row += 1u)
    {
        for (unsigned int column = 0u; column < BOUNDARY_TEST_SAMPLES; column += 1u)
        {
            long long entry = 0ll;
            for (unsigned int at = 0u; at < BOUNDARY_TEST_SAMPLES; at += 1u)
            {
                entry += s_boundary_forward_matrix[row][at] * s_boundary_inverse_matrix[at][column];
            }
            identity = identity && (entry == ((row == column) ? (1ll << (2u * BOUNDARY_TEST_REACH)) : 0ll));
        }
    }
    scriptura_text(&tally->line, "  volume: det M = ");
    scriptura_signed(&tally->line, forward_sign);
    scriptura_text(&tally->line, " and det M^-1 = ");
    scriptura_signed(&tally->line, inverse_sign);
    scriptura_text(&tally->line, " exactly, by primes past ");
    scriptura_decimal(&tally->line, (unsigned long long)forward_bits, 1u);
    scriptura_text(&tally->line, " and ");
    scriptura_decimal(&tally->line, (unsigned long long)inverse_bits, 1u);
    scriptura_text(&tally->line, " bits; M M^-1 = I ");
    scriptura_text(&tally->line, (identity != 0) ? "holds\n" : "fails\n");
    boundary_check(tally, (forward != 0) && (inverse != 0), "T and T^-1 keep volume: det M = det M^-1 = +-1 exactly");
    boundary_check(tally, identity, "T^-1's matrix is the inverse of T's");
}

int main(void)
{
    BoundaryTally tally;
    tally.checks = 0ull;
    tally.failures = 0ull;
    tally.line.room = BOUNDARY_TEST_LINE;
    tally.line.out = (char *)malloc((size_t)BOUNDARY_TEST_LINE);
    tally.line.at = 0ull;
    if (tally.line.out == NULL)
    {
        return 2;
    }
    boundary_matrices();
    boundary_bands(&tally);
    boundary_written(&tally);
    boundary_read_off(&tally);
    boundary_floors(&tally);
    boundary_top(&tally);
    boundary_counted(&tally);
    boundary_volume(&tally);
    scriptura_text(&tally.line, "  record boundary test: ");
    scriptura_decimal(&tally.line, tally.checks, 1u);
    scriptura_text(&tally.line, " checks, ");
    scriptura_decimal(&tally.line, tally.failures, 1u);
    scriptura_text(&tally.line, " failed\n");
    scriptura_write(&tally.line, stdout);
    free(tally.line.out);
    return (tally.failures == 0ull) ? 0 : 1;
}
