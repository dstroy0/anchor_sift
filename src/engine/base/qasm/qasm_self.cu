// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "qasm.h"

#include "cycle.h"
#include "key_schedule.h"
#include "keymath.h"

#include <cuda_runtime.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

// The self run. A circuit becomes one program for the record machine: every gate is a floor of exact integer steps
// reading the floor below it, and with register reuse each lane runs the whole stack in one launch from its own input
// state. A lane's state is every amplitude's four integer parts, the rational and sqrt2 parts of its real half and then
// of its imaginary half, over one denominator the host keeps. A gate is the integer linear map its matrix makes over
// the least common denominator of its entries. Its columns are the dense port's own action on each basis state, so the
// lanes apply exactly the gates the port applies. No step divides and nothing rounds.

// __LINE__ is a positive int, which the unsigned site holds unchanged
#define QASM_HELD(held_, evacaddr_, error_, kind_)                                                                     \
    engine_error_check((held_) ? 1 : 0, (kind_), ENGINE_MODULE_QASM, (unsigned int)__LINE__,                           \
                       (const void *)(evacaddr_), (error_))

// a CUDA status is a small enumerator, which an int holds unchanged
#define QASM_TOOK(call_, evacaddr_, error_)                                                                            \
    engine_status_check((int)(call_), ENGINE_MODULE_QASM, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

// an exact integer's status: anything but OK is a value the width does not hold
#define QASM_FITS(status_, evacaddr_, error_)                                                                          \
    QASM_HELD((status_) == ANCHOR_EXACT_OK, (evacaddr_), (error_), ENGINE_ERROR_RESOURCE)

// an amplitude's integer parts: the real half's rational and sqrt2 parts, then the imaginary half's
#define QASM_SELF_PARTS 4u

// the distinct constants one floor keeps for reuse; a floor needing more builds the rest again
#define QASM_SELF_CONSTANTS_MOST 64u

// the most lanes one run takes: every count of numbers and limbs over them then stays within an unsigned long long
#define QASM_SELF_LANES_MOST (1ull << 32u)

static_assert(cudaSuccess == 0, "the engine reads a CUDA status of 0 as success");

static_assert((QASM_SELF_PARTS << QASM_SELF_QUBITS_MOST) <= ENGINE_RECORD_LIMBS_MOST,
              "qasm: the self run's widest state must fit the record machine's register file");

// an input field is at most one bit past the exact integer's width, so the widest record's bits fit an unsigned int
static_assert(((((unsigned long long)QASM_SELF_PARTS << QASM_SELF_QUBITS_MOST)
                * ((unsigned long long)ANCHOR_EXACT_BITS + 1ull))
               + 31ull)
                  <= 0xFFFFFFFFull,
              "qasm: the self run's widest input record must be counted in an unsigned int");

static const AnchorExactInteger qasm_self_one = {{1u}, 1};

// Part p of e x, for an entry e and an amplitude x, is the sum over x's parts q of e's part qasm_self_entry_part[p][q]
// times x's part q, doubled where qasm_self_doubled[p][q] and negated where qasm_self_negated[p][q]. With r = sqrt2,
// (a + b r)(c + d r) = (ac + 2bd) + (ad + bc) r, and i^2 = -1 carries the imaginary halves' product into the real half.
static const unsigned int qasm_self_entry_part[QASM_SELF_PARTS][QASM_SELF_PARTS] = {
    {0u, 1u, 2u, 3u}, {1u, 0u, 3u, 2u}, {2u, 3u, 0u, 1u}, {3u, 2u, 1u, 0u}};
static const int qasm_self_doubled[QASM_SELF_PARTS][QASM_SELF_PARTS] = {
    {0, 1, 0, 1}, {0, 0, 0, 0}, {0, 1, 0, 1}, {0, 0, 0, 0}};
static const int qasm_self_negated[QASM_SELF_PARTS][QASM_SELF_PARTS] = {
    {0, 0, 1, 1}, {0, 0, 1, 1}, {0, 0, 0, 0}, {0, 0, 0, 0}};

// part p of a number: 0 the real rational, 1 the real sqrt2, 2 the imaginary rational, 3 the imaginary sqrt2
static const QasmRational *qasm_self_part(const QasmNumber *value, unsigned int part)
{
    const QasmRational *const parts[QASM_SELF_PARTS] = {&value->real.rational, &value->real.sqrt2,
                                                        &value->imaginary.rational, &value->imaginary.sqrt2};
    return parts[part];
}

static QasmRational *qasm_self_part_slot(QasmNumber *value, unsigned int part)
{
    QasmRational *const parts[QASM_SELF_PARTS] = {&value->real.rational, &value->real.sqrt2, &value->imaginary.rational,
                                                  &value->imaginary.sqrt2};
    return parts[part];
}

typedef struct
{
    EngineRecordStep *steps;
    unsigned int count;
    unsigned int room;
    // the list could not grow, and every later step is refused with it
    int spent;
} QasmSelfSteps;

// appends one step and returns its number; once the list cannot grow it returns 0 and the list stays spent
static unsigned int qasm_self_step(QasmSelfSteps *list, EngineRecordOperation operation, unsigned int left,
                                   unsigned int right, unsigned int member)
{
    if ((list->spent == 0) && (list->count == list->room))
    {
        const unsigned int wanted = (list->room == 0u) ? 1024u : (list->room * 2u);
        // a doubling that wraps asks for less than it holds, and is refused as a list that cannot grow; the count is
        // widened to size_t, which holds any unsigned int
        EngineRecordStep *const grown =
            (wanted > list->room) ? (EngineRecordStep *)realloc(list->steps, (size_t)wanted * sizeof(EngineRecordStep))
                                  : NULL;
        list->spent = (grown == NULL) ? 1 : 0;
        list->steps = (grown != NULL) ? grown : list->steps;
        list->room = (grown != NULL) ? wanted : list->room;
    }
    if (list->spent != 0)
    {
        return 0u;
    }
    const unsigned int step = list->count;
    list->steps[step].operation = operation;
    list->steps[step].left = left;
    list->steps[step].right = right;
    list->steps[step].member = member;
    list->count += 1u;
    return step;
}

typedef struct
{
    QasmSelfSteps list;
    // the step holding 0, which a part no term reaches takes
    unsigned int zero;
    unsigned int amplitudes;
    // the registers of the floor below and of the floor being built, QASM_SELF_PARTS to an amplitude
    unsigned int *below;
    unsigned int *built;
    // the floor's constants: each magnitude and the step holding it
    AnchorExactInteger constant_value[QASM_SELF_CONSTANTS_MOST];
    unsigned int constant_step[QASM_SELF_CONSTANTS_MOST];
    unsigned int constant_count;
    // a gate's columns, column s from [s amplitudes], and each entry's parts over the gate's denominator
    QasmNumber *columns;
    AnchorExactInteger *numerators;
    // the state's denominator: the inputs', times every gate's
    AnchorExactInteger denominator;
    // a coefficient doubled past the width
    int past_width;
    EngineError *error;
} QasmSelfBuild;

// A magnitude of 2 or more as a register: one CONSTANT step up to 64 bits, and a wider one built a limb at a time from
// the top, times 2^32 and plus the next limb down.
static unsigned int qasm_self_constant(QasmSelfBuild *build, const AnchorExactInteger *magnitude)
{
    for (unsigned int at = 0u; at < build->constant_count; at += 1u)
    {
        if (anchor_exact_equal(&build->constant_value[at], magnitude) != 0)
        {
            return build->constant_step[at];
        }
    }
    unsigned int used = ANCHOR_EXACT_LIMBS;
    while ((used > 1u) && (magnitude->limb[used - 1u] == 0u))
    {
        used -= 1u;
    }
    unsigned int value = 0u;
    if (used <= 2u)
    {
        value = qasm_self_step(&build->list, ENGINE_RECORD_CONSTANT, magnitude->limb[0],
                               (used == 2u) ? magnitude->limb[1] : 0u, 0u);
    }
    else
    {
        const unsigned int word = qasm_self_step(&build->list, ENGINE_RECORD_CONSTANT, 0u, 1u, 0u);
        value = qasm_self_step(&build->list, ENGINE_RECORD_CONSTANT, magnitude->limb[used - 1u], 0u, 0u);
        for (unsigned int limb = used - 1u; limb > 0u; limb -= 1u)
        {
            const unsigned int low = qasm_self_step(&build->list, ENGINE_RECORD_CONSTANT, magnitude->limb[limb - 1u],
                                                    0u, 0u);
            const unsigned int shifted = qasm_self_step(&build->list, ENGINE_RECORD_PRODUCT, value, word, 0u);
            value = qasm_self_step(&build->list, ENGINE_RECORD_SUM, shifted, low, 0u);
        }
    }
    if (build->constant_count < QASM_SELF_CONSTANTS_MOST)
    {
        build->constant_value[build->constant_count] = *magnitude;
        build->constant_step[build->constant_count] = value;
        build->constant_count += 1u;
    }
    return value;
}

// one term: the register times the coefficient's magnitude, or the register itself where that is 1
static unsigned int qasm_self_term(QasmSelfBuild *build, unsigned int source, const AnchorExactInteger *magnitude)
{
    if (anchor_exact_equal(magnitude, &qasm_self_one) != 0)
    {
        return source;
    }
    const unsigned int factor = qasm_self_constant(build, magnitude);
    return qasm_self_step(&build->list, ENGINE_RECORD_PRODUCT, source, factor, 0u);
}

// Part `part` of amplitude `target` on the floor being built: every nonzero term over the floor below, summed from the
// first, the first taken from zero where it is negative, and zero where no term reaches the part.
static unsigned int qasm_self_sum(QasmSelfBuild *build, unsigned int target, unsigned int part)
{
    const unsigned int amplitudes = build->amplitudes;
    int started = 0;
    unsigned int sum = build->zero;
    for (unsigned int source = 0u; source < amplitudes; source += 1u)
    {
        const AnchorExactInteger *const entry = &build->numerators[QASM_SELF_PARTS * ((source * amplitudes) + target)];
        for (unsigned int from = 0u; from < QASM_SELF_PARTS; from += 1u)
        {
            const AnchorExactInteger *const coefficient = &entry[qasm_self_entry_part[part][from]];
            const unsigned int below = build->below[(QASM_SELF_PARTS * source) + from];
            if ((coefficient->sign == 0) || (below == build->zero))
            {
                continue;
            }
            AnchorExactInteger magnitude = *coefficient;
            magnitude.sign = 1;
            if (qasm_self_doubled[part][from] != 0)
            {
                const AnchorExactStatus doubled = anchor_exact_add(&magnitude, &magnitude, &magnitude);
                build->past_width = build->past_width || (doubled != ANCHOR_EXACT_OK);
            }
            const int negative = (coefficient->sign < 0) != (qasm_self_negated[part][from] != 0);
            const unsigned int term = qasm_self_term(build, below, &magnitude);
            if (started == 0)
            {
                sum = negative ? qasm_self_step(&build->list, ENGINE_RECORD_DIFFERENCE, build->zero, term, 0u) : term;
                started = 1;
            }
            else
            {
                sum = qasm_self_step(&build->list, negative ? ENGINE_RECORD_DIFFERENCE : ENGINE_RECORD_SUM, sum, term,
                                     0u);
            }
        }
    }
    return sum;
}

// common = lcm(common, denominator), both positive
static int qasm_self_lcm(AnchorExactInteger *common, const AnchorExactInteger *denominator, EngineError *error)
{
    AnchorExactInteger divisor;
    AnchorExactInteger share;
    return QASM_FITS(anchor_exact_gcd(common, denominator, &divisor), common, error)
        && QASM_FITS(anchor_exact_divide_exact(denominator, &divisor, &share), common, error)
        && QASM_FITS(anchor_exact_multiply(common, &share, common), common, error);
}

// a rational over a denominator it divides: its numerator times the denominator's share of it
static int qasm_self_over(const QasmRational *value, const AnchorExactInteger *common, AnchorExactInteger *numerator,
                          EngineError *error)
{
    AnchorExactInteger share;
    return QASM_FITS(anchor_exact_divide_exact(common, &value->denominator, &share), value, error)
        && QASM_FITS(anchor_exact_multiply(&value->numerator, &share, numerator), value, error);
}

// One gate as a floor: its columns from the dense port, its denominator, and every part of the floor above as the sum
// of the parts below times the integers its entries make over that denominator.
static int qasm_self_floor(QasmSelfBuild *build, unsigned int qubits, const QasmExactGate *gate)
{
    EngineError *const error = build->error;
    const unsigned int amplitudes = build->amplitudes;
    QasmDense basis = {0u, NULL};
    int good = (qasm_dense_alloc(&basis, qubits, error) == 0L);
    for (unsigned int source = 0u; good && (source < amplitudes); source += 1u)
    {
        for (unsigned int target = 0u; target < amplitudes; target += 1u)
        {
            basis.amplitudes[target] = (target == source) ? qasm_number_one : qasm_number_zero;
        }
        good = (qasm_dense_apply(&basis, gate, error) == 0L);
        for (unsigned int target = 0u; good && (target < amplitudes); target += 1u)
        {
            build->columns[(source * amplitudes) + target] = basis.amplitudes[target];
        }
    }
    qasm_dense_release(&basis);
    AnchorExactInteger common = qasm_self_one;
    const unsigned int entries = amplitudes * amplitudes;
    for (unsigned int entry = 0u; good && (entry < entries); entry += 1u)
    {
        for (unsigned int part = 0u; good && (part < QASM_SELF_PARTS); part += 1u)
        {
            good = qasm_self_lcm(&common, &qasm_self_part(&build->columns[entry], part)->denominator, error);
        }
    }
    for (unsigned int entry = 0u; good && (entry < entries); entry += 1u)
    {
        for (unsigned int part = 0u; good && (part < QASM_SELF_PARTS); part += 1u)
        {
            good = qasm_self_over(qasm_self_part(&build->columns[entry], part), &common,
                                  &build->numerators[(QASM_SELF_PARTS * entry) + part], error);
        }
    }
    build->constant_count = 0u;
    for (unsigned int target = 0u; good && (target < amplitudes); target += 1u)
    {
        for (unsigned int part = 0u; part < QASM_SELF_PARTS; part += 1u)
        {
            build->built[(QASM_SELF_PARTS * target) + part] = qasm_self_sum(build, target, part);
        }
    }
    good = good && QASM_HELD(build->past_width == 0, gate, error, ENGINE_ERROR_RESOURCE)
        && QASM_HELD(build->list.spent == 0, &build->list, error, ENGINE_ERROR_RESOURCE)
        && QASM_FITS(anchor_exact_multiply(&build->denominator, &common, &build->denominator), gate, error);
    // the floor just built is the floor the next gate reads
    unsigned int *const below = build->below;
    build->below = build->built;
    build->built = below;
    return good;
}

// the bits a magnitude uses, 0 for zero
static unsigned int qasm_self_bits(const AnchorExactInteger *value)
{
    for (unsigned int limb = ANCHOR_EXACT_LIMBS; limb > 0u; limb -= 1u)
    {
        const uint32_t word = value->limb[limb - 1u];
        if (word != 0u)
        {
            unsigned int bits = 32u;
            while (((word >> (bits - 1u)) & 1u) == 0u)
            {
                bits -= 1u;
            }
            return (32u * (limb - 1u)) + bits;
        }
    }
    return 0u;
}

// a value as `bits` bits of two's complement at bit `offset` of a zeroed record: a negative value is its magnitude's
// complement plus one, the carry walking up from bit 0
static void qasm_self_put(unsigned int *record, unsigned int offset, unsigned int bits, const AnchorExactInteger *value)
{
    const unsigned int negative = (value->sign < 0) ? 1u : 0u;
    unsigned int carry = negative;
    for (unsigned int at = 0u; at < bits; at += 1u)
    {
        const unsigned int limb = at >> 5u;
        const unsigned int magnitude_bit = (limb < ANCHOR_EXACT_LIMBS) ? ((value->limb[limb] >> (at & 31u)) & 1u) : 0u;
        const unsigned int flipped = magnitude_bit ^ negative;
        const unsigned int bit = flipped ^ carry;
        carry = flipped & carry;
        const unsigned int place = offset + at;
        record[place >> 5u] |= bit << (place & 31u);
    }
}

// an output of `bits` bits of two's complement at bit `offset`, as a signed magnitude; 0 where the width cannot hold it
static int qasm_self_get(const unsigned int *record, unsigned int offset, unsigned int bits, AnchorExactInteger *value)
{
    anchor_exact_zero(value);
    // widening: the width's bits are a power of two far below 2^32
    if ((bits == 0u) || ((unsigned long long)bits > (unsigned long long)ANCHOR_EXACT_BITS))
    {
        return 0;
    }
    const unsigned int top = offset + bits - 1u;
    const unsigned int negative = (record[top >> 5u] >> (top & 31u)) & 1u;
    unsigned int carry = negative;
    unsigned int any = 0u;
    for (unsigned int at = 0u; at < bits; at += 1u)
    {
        const unsigned int place = offset + at;
        const unsigned int flipped = ((record[place >> 5u] >> (place & 31u)) & 1u) ^ negative;
        const unsigned int bit = flipped ^ carry;
        carry = flipped & carry;
        value->limb[at >> 5u] |= bit << (at & 31u);
        any |= bit;
    }
    value->sign = (any == 0u) ? 0 : ((negative != 0u) ? -1 : 1);
    return 1;
}

// The inputs over their least common denominator, as records of fields `bits` wide. Without inputs lane j is |j>: its
// real rational part 1 at amplitude j and 0 elsewhere, over 1. The first pass finds the denominator and the widest
// numerator; with records set the second writes them.
static int qasm_self_inputs(const QasmSelfRequest *request, unsigned int amplitudes, AnchorExactInteger *denominator,
                            unsigned int *bits, unsigned int *records, unsigned int in_limbs)
{
    EngineError *const error = request->error;
    if (request->inputs == NULL)
    {
        *denominator = qasm_self_one;
        *bits = 2u;
        for (unsigned long long lane = 0ull; (records != NULL) && (lane < request->lanes); lane += 1ull)
        {
            // the lane is below 2^qubits, so its amplitude's field is below the fields' count
            const unsigned int field = QASM_SELF_PARTS * (unsigned int)lane;
            qasm_self_put(&records[lane * in_limbs], field * (*bits), *bits, &qasm_self_one);
        }
        return 1;
    }
    int good = 1;
    const unsigned long long numbers = request->lanes * amplitudes;
    if (records == NULL)
    {
        *denominator = qasm_self_one;
        for (unsigned long long number = 0ull; good && (number < numbers); number += 1ull)
        {
            for (unsigned int part = 0u; good && (part < QASM_SELF_PARTS); part += 1u)
            {
                good = qasm_self_lcm(denominator, &qasm_self_part(&request->inputs[number], part)->denominator, error);
            }
        }
        *bits = 2u;
    }
    for (unsigned long long number = 0ull; good && (number < numbers); number += 1ull)
    {
        for (unsigned int part = 0u; good && (part < QASM_SELF_PARTS); part += 1u)
        {
            AnchorExactInteger numerator;
            good = qasm_self_over(qasm_self_part(&request->inputs[number], part), denominator, &numerator, error);
            const unsigned int used = good ? (qasm_self_bits(&numerator) + 1u) : 0u;
            *bits = ((records == NULL) && (used > *bits)) ? used : *bits;
            if (good && (records != NULL))
            {
                const unsigned long long lane = number / amplitudes;
                // the amplitude is the number's place in its lane, below 2^qubits
                const unsigned int amplitude = (unsigned int)(number % amplitudes);
                const unsigned int field = (QASM_SELF_PARTS * amplitude) + part;
                qasm_self_put(&records[lane * in_limbs], field * (*bits), *bits, &numerator);
            }
        }
    }
    return good;
}

// the program laid on the host: its imprint and its layout, with each output's step
typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    unsigned int *outputs;
    unsigned int laid;
} QasmSelfProgram;

static void qasm_self_program_release(QasmSelfProgram *program)
{
    if (program->laid != 0u)
    {
        key_schedule_record_release(&program->layout);
        keymath_record_release(&program->key);
        program->laid = 0u;
    }
    free(program->outputs);
    program->outputs = NULL;
}

// Every gate a floor over the input fields, then the last floor's parts as the outputs. A register named twice is
// named the second time through a sum with zero, since a step may be an output once.
static int qasm_self_program(const QasmSelfRequest *request, QasmSelfBuild *build, unsigned int bits,
                             QasmSelfProgram *program)
{
    EngineError *const error = request->error;
    const unsigned int fields = QASM_SELF_PARTS * build->amplitudes;
    build->zero = qasm_self_step(&build->list, ENGINE_RECORD_CONSTANT, 0u, 0u, 0u);
    for (unsigned int field = 0u; field < fields; field += 1u)
    {
        build->below[field] = qasm_self_step(&build->list, ENGINE_RECORD_FIELD_SIGNED, field, 0u, 0u);
    }
    int good = QASM_HELD(build->list.spent == 0, &build->list, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int gate = 0u; good && (gate < request->gate_count); gate += 1u)
    {
        good = qasm_self_floor(build, request->qubits, &request->gates[gate]);
    }
    program->outputs = good ? (unsigned int *)calloc(fields, sizeof(unsigned int)) : NULL;
    good = good && QASM_HELD(program->outputs != NULL, program, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int field = 0u; good && (field < fields); field += 1u)
    {
        unsigned int step = build->below[field];
        for (unsigned int earlier = 0u; earlier < field; earlier += 1u)
        {
            step = (program->outputs[earlier] == step)
                       ? qasm_self_step(&build->list, ENGINE_RECORD_SUM, step, build->zero, 0u)
                       : step;
        }
        program->outputs[field] = step;
    }
    good = good && QASM_HELD(build->list.spent == 0, &build->list, error, ENGINE_ERROR_RESOURCE);
    unsigned int *const field_bits = good ? (unsigned int *)calloc(fields, sizeof(unsigned int)) : NULL;
    unsigned int *const field_offset = good ? (unsigned int *)calloc(fields, sizeof(unsigned int)) : NULL;
    good = good && QASM_HELD((field_bits != NULL) && (field_offset != NULL), program, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int field = 0u; good && (field < fields); field += 1u)
    {
        field_bits[field] = bits;
        field_offset[field] = field * bits;
    }
    // the widest record is fields x bits bits, which the request's bounds keep below 2^32
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {((fields * bits) + 31u) / 32u, 0u, 0u};
    if (good)
    {
        const KeymathRecordRequest imprint = {build->list.steps, build->list.count, field_bits, fields, 1u,
                                              program->outputs, fields, NULL, 0u, &program->key, error};
        good = (keymath_record_imprint(&imprint) != KEYMATH_REFUSED);
    }
    if (good)
    {
        const KeyScheduleRecordRequest lay = {&program->key, field_offset, fields, in_limbs, 1, &program->layout,
                                              error};
        good = (key_schedule_record_lay(&lay) != KEY_SCHEDULE_REFUSED);
        if (!good)
        {
            keymath_record_release(&program->key);
        }
        program->laid = good ? 1u : 0u;
    }
    free(field_bits);
    free(field_offset);
    return good;
}

// the lanes on the device: the program loaded, the input records in, one launch, the output records back
static int qasm_self_device(const EngineRecordLayout *layout, const unsigned int *in, unsigned long long lanes,
                            unsigned int *out, EngineError *error)
{
    // the byte counts were bounded by the request's check against SIZE_MAX before any record was held
    const size_t in_bytes = (size_t)(lanes * layout->in_limbs[0] * sizeof(unsigned int));
    const size_t out_bytes = (size_t)(lanes * layout->out_limbs * sizeof(unsigned int));
    CycleRecord *record = NULL;
    unsigned int *device_in = NULL;
    unsigned int *device_out = NULL;
    int good = (cycle_record_load(layout, &record, error) != CYCLE_REFUSED)
            && QASM_TOOK(cudaMalloc((void **)&device_in, in_bytes), &device_in, error)
            && QASM_TOOK(cudaMalloc((void **)&device_out, out_bytes), &device_out, error)
            && QASM_TOOK(cudaMemcpy(device_in, in, in_bytes, cudaMemcpyHostToDevice), device_in, error);
    if (good)
    {
        CycleRecordRunRequest run;
        memset(&run, 0, sizeof(run));
        run.record = record;
        run.device_in[0] = device_in;
        run.bodies[0] = lanes;
        run.count = lanes;
        run.device_out = device_out;
        run.error = error;
        good = (cycle_record_run(&run) != CYCLE_REFUSED)
            && QASM_TOOK(cudaMemcpy(out, device_out, out_bytes, cudaMemcpyDeviceToHost), out, error);
    }
    cudaFree(device_in);
    cudaFree(device_out);
    if (record != NULL)
    {
        cycle_record_release(record);
    }
    return good;
}

// each lane's outputs over the state's denominator, reduced, into its amplitudes
static int qasm_self_decode(const QasmSelfRequest *request, const QasmSelfProgram *program, const unsigned int *out,
                            unsigned int amplitudes, const AnchorExactInteger *denominator)
{
    EngineError *const error = request->error;
    const QasmRational scale = {*denominator, qasm_self_one};
    const unsigned int out_limbs = program->layout.out_limbs;
    int good = 1;
    for (unsigned long long lane = 0ull; good && (lane < request->lanes); lane += 1ull)
    {
        const unsigned int *const record = &out[lane * out_limbs];
        for (unsigned int amplitude = 0u; good && (amplitude < amplitudes); amplitude += 1u)
        {
            QasmNumber *const number = &request->outputs[(lane * amplitudes) + amplitude];
            for (unsigned int part = 0u; good && (part < QASM_SELF_PARTS); part += 1u)
            {
                const DeviceRecordStep *const step =
                    &program->layout.step_table[program->outputs[(QASM_SELF_PARTS * amplitude) + part]];
                QasmRational fraction = {qasm_self_one, qasm_self_one};
                good = QASM_HELD(qasm_self_get(record, step->out_offset, step->out_bits, &fraction.numerator), step,
                                 error, ENGINE_ERROR_RESOURCE)
                    && (qasm_rational_divide(&fraction, &scale, qasm_self_part_slot(number, part), error) == 0L);
            }
        }
    }
    return good;
}

long qasm_self_run(const QasmSelfRequest *request, QasmSelfReading *reading)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return QASM_REFUSED;
    }
    EngineError *const error = request->error;
    const unsigned long long start = engine_clock_microseconds();
    const unsigned int qubits = request->qubits;
    const int shaped = (reading != NULL) && (qubits != 0u) && (qubits <= QASM_SELF_QUBITS_MOST)
                    && ((request->gate_count == 0u) || (request->gates != NULL)) && (request->outputs != NULL)
                    && (request->lanes != 0ull) && (request->lanes <= QASM_SELF_LANES_MOST)
                    && ((request->inputs != NULL) || (request->lanes == (1ull << qubits)));
    if (!QASM_HELD(shaped, request, error, ENGINE_ERROR_REQUEST))
    {
        return QASM_REFUSED;
    }
    memset(reading, 0, sizeof(*reading));
    const unsigned int amplitudes = 1u << qubits;
    AnchorExactInteger input_denominator;
    unsigned int bits = 0u;
    int good = qasm_self_inputs(request, amplitudes, &input_denominator, &bits, NULL, 0u);
    QasmSelfBuild *const build = good ? (QasmSelfBuild *)calloc(1u, sizeof(QasmSelfBuild)) : NULL;
    // widening: at most 2^10 entries, held by any size_t
    const size_t entries = (size_t)amplitudes * amplitudes;
    if (build != NULL)
    {
        build->amplitudes = amplitudes;
        build->error = error;
        build->denominator = input_denominator;
        build->below = (unsigned int *)calloc(QASM_SELF_PARTS * amplitudes, sizeof(unsigned int));
        build->built = (unsigned int *)calloc(QASM_SELF_PARTS * amplitudes, sizeof(unsigned int));
        build->columns = (QasmNumber *)calloc(entries, sizeof(QasmNumber));
        build->numerators = (AnchorExactInteger *)calloc(QASM_SELF_PARTS * entries, sizeof(AnchorExactInteger));
    }
    good = good && QASM_HELD((build != NULL) && (build->below != NULL) && (build->built != NULL)
                                 && (build->columns != NULL) && (build->numerators != NULL),
                             request, error, ENGINE_ERROR_RESOURCE);
    QasmSelfProgram program;
    memset(&program, 0, sizeof(program));
    good = good && qasm_self_program(request, build, bits, &program);
    const unsigned int in_limbs = good ? program.layout.in_limbs[0] : 0u;
    const unsigned int out_limbs = good ? program.layout.out_limbs : 0u;
    // widening: the limb counts are unsigned ints, and with at most 2^32 lanes the product stays below 2^64
    const unsigned long long record_limbs = request->lanes * (unsigned long long)(in_limbs + out_limbs);
    good = good && QASM_HELD(record_limbs <= (SIZE_MAX / sizeof(unsigned int)), request, error, ENGINE_ERROR_RESOURCE)
        && QASM_HELD((request->records == NULL) || (request->record_room >= (request->lanes * out_limbs)), request,
                     error, ENGINE_ERROR_REQUEST);
    // the limb counts were just bounded by SIZE_MAX over a limb's bytes
    unsigned int *const in = good ? (unsigned int *)calloc((size_t)(request->lanes * in_limbs), sizeof(unsigned int))
                                  : NULL;
    unsigned int *const out = good ? (unsigned int *)calloc((size_t)(request->lanes * out_limbs), sizeof(unsigned int))
                                   : NULL;
    good = good && QASM_HELD((in != NULL) && (out != NULL), request, error, ENGINE_ERROR_RESOURCE)
        && qasm_self_inputs(request, amplitudes, &input_denominator, &bits, in, in_limbs);
    if (good && (request->on_host != 0))
    {
        CycleRecordHostRequest run;
        memset(&run, 0, sizeof(run));
        run.layout = &program.layout;
        run.in[0] = in;
        run.bodies[0] = request->lanes;
        run.count = request->lanes;
        run.out = out;
        run.error = error;
        good = (cycle_record_run_host(&run) != CYCLE_REFUSED);
    }
    else if (good)
    {
        good = qasm_self_device(&program.layout, in, request->lanes, out, error);
    }
    good = good && qasm_self_decode(request, &program, out, amplitudes, &build->denominator);
    if (good && (request->records != NULL))
    {
        // the output limbs were bounded by SIZE_MAX over a limb's bytes with the input limbs
        memcpy(request->records, out, (size_t)(request->lanes * out_limbs) * sizeof(unsigned int));
    }
    if (good)
    {
        reading->steps = build->list.count;
        reading->file_limbs = program.layout.file_limbs;
        reading->in_limbs = in_limbs;
        reading->out_limbs = out_limbs;
        reading->lanes = request->lanes;
        // widening: the step count is an unsigned int
        reading->device_bytes = (record_limbs * sizeof(unsigned int))
                              + ((unsigned long long)program.layout.steps * sizeof(DeviceRecordStep));
    }
    free(in);
    free(out);
    qasm_self_program_release(&program);
    if (build != NULL)
    {
        free(build->list.steps);
        free(build->below);
        free(build->built);
        free(build->columns);
        free(build->numerators);
        free(build);
    }
    reading->microseconds = engine_clock_microseconds() - start;
    if (!good)
    {
        engine_error_frame(error);
        return QASM_REFUSED;
    }
    return 0L;
}
