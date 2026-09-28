// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_self_run.cu: inputs, the device and the run
#include "qasm_self_internal.h"

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
            // the lane is below 2^qubits. Its amplitude's field is below the fields' count
            const unsigned int field = QASM_SELF_PARTS * (unsigned int)lane;
            qasm_self_put(&records[lane * in_limbs], field * (*bits), *bits, &qasm_self_one);
        }
        return 1;
    }
    int ok = 1;
    const unsigned long long numbers = request->lanes * amplitudes;
    if (records == NULL)
    {
        *denominator = qasm_self_one;
        for (unsigned long long number = 0ull; ok && (number < numbers); number += 1ull)
        {
            for (unsigned int part = 0u; ok && (part < QASM_SELF_PARTS); part += 1u)
            {
                ok = qasm_self_lcm(denominator, &qasm_self_part(&request->inputs[number], part)->denominator, error);
            }
        }
        *bits = 2u;
    }
    for (unsigned long long number = 0ull; ok && (number < numbers); number += 1ull)
    {
        for (unsigned int part = 0u; ok && (part < QASM_SELF_PARTS); part += 1u)
        {
            AnchorExactInteger numerator;
            ok = qasm_self_over(qasm_self_part(&request->inputs[number], part), denominator, &numerator, error);
            const unsigned int used = ok ? (qasm_self_bits(&numerator) + 1u) : 0u;
            *bits = ((records == NULL) && (used > *bits)) ? used : *bits;
            if (ok && (records != NULL))
            {
                const unsigned long long lane = number / amplitudes;
                // the amplitude is the number's place in its lane, below 2^qubits
                const unsigned int amplitude = (unsigned int)(number % amplitudes);
                const unsigned int field = (QASM_SELF_PARTS * amplitude) + part;
                qasm_self_put(&records[lane * in_limbs], field * (*bits), *bits, &numerator);
            }
        }
    }
    return ok;
}

static void qasm_self_program_release(QasmSelfProgram *program)
{
    if (program->layout_built != 0u)
    {
        key_schedule_record_release(&program->layout);
        keymath_record_release(&program->key);
        program->layout_built = 0u;
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
    int ok = QASM_CHECK(build->list.spent == 0, &build->list, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int gate = 0u; ok && (gate < request->gate_count); gate += 1u)
    {
        ok = qasm_self_floor(build, request->qubits, &request->gates[gate]);
    }
    program->outputs = ok ? (unsigned int *)calloc(fields, sizeof(unsigned int)) : NULL;
    ok = ok && QASM_CHECK(program->outputs != NULL, program, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int field = 0u; ok && (field < fields); field += 1u)
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
    ok = ok && QASM_CHECK(build->list.spent == 0, &build->list, error, ENGINE_ERROR_RESOURCE);
    unsigned int *const field_bits = ok ? (unsigned int *)calloc(fields, sizeof(unsigned int)) : NULL;
    unsigned int *const field_offset = ok ? (unsigned int *)calloc(fields, sizeof(unsigned int)) : NULL;
    ok = ok && QASM_CHECK((field_bits != NULL) && (field_offset != NULL), program, error, ENGINE_ERROR_RESOURCE);
    for (unsigned int field = 0u; ok && (field < fields); field += 1u)
    {
        field_bits[field] = bits;
        field_offset[field] = field * bits;
    }
    // the widest record is fields x bits bits, which the request's bounds keep below 2^32
    const unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {((fields * bits) + 31u) / 32u, 0u, 0u};
    if (ok)
    {
        const KeymathRecordRequest encode_request = {build->list.steps,
                                                     build->list.count,
                                                     field_bits,
                                                     fields,
                                                     1u,
                                                     program->outputs,
                                                     fields,
                                                     NULL,
                                                     0u,
                                                     &program->key,
                                                     error};
        ok = (keymath_record_encode(&encode_request) != KEYMATH_ERROR);
    }
    if (ok)
    {
        const KeyScheduleRecordRequest layout_request = {&program->key,    field_offset, fields, in_limbs, 1,
                                                         &program->layout, error};
        ok = (key_schedule_record_layout(&layout_request) != KEY_SCHEDULE_ERROR);
        if (!ok)
        {
            keymath_record_release(&program->key);
        }
        program->layout_built = ok ? 1u : 0u;
    }
    free(field_bits);
    free(field_offset);
    return ok;
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
    int ok = (cycle_record_load(layout, &record, error) != CYCLE_ERROR) &&
             QASM_STATUS_CHECK(cudaMalloc((void **)&device_in, in_bytes), &device_in, error) &&
             QASM_STATUS_CHECK(cudaMalloc((void **)&device_out, out_bytes), &device_out, error) &&
             QASM_STATUS_CHECK(cudaMemcpy(device_in, in, in_bytes, cudaMemcpyHostToDevice), device_in, error);
    if (ok)
    {
        CycleRecordRunRequest run;
        memset(&run, 0, sizeof(run));
        run.record = record;
        run.device_in[0] = device_in;
        run.bodies[0] = lanes;
        run.count = lanes;
        run.device_out = device_out;
        run.error = error;
        ok = (cycle_record_run(&run) != CYCLE_ERROR) &&
             QASM_STATUS_CHECK(cudaMemcpy(out, device_out, out_bytes, cudaMemcpyDeviceToHost), out, error);
    }
    cudaFree(device_in);
    cudaFree(device_out);
    if (record != NULL)
    {
        cycle_record_release(record);
    }
    return ok;
}

// each lane's outputs over the state's denominator, reduced, into its amplitudes
static int qasm_self_decode(const QasmSelfRequest *request, const QasmSelfProgram *program, const unsigned int *out,
                            unsigned int amplitudes, const AnchorExactInteger *denominator)
{
    EngineError *const error = request->error;
    const QasmRational scale = {*denominator, qasm_self_one};
    const unsigned int out_limbs = program->layout.out_limbs;
    int ok = 1;
    for (unsigned long long lane = 0ull; ok && (lane < request->lanes); lane += 1ull)
    {
        const unsigned int *const record = &out[lane * out_limbs];
        for (unsigned int amplitude = 0u; ok && (amplitude < amplitudes); amplitude += 1u)
        {
            QasmNumber *const number = &request->outputs[(lane * amplitudes) + amplitude];
            for (unsigned int part = 0u; ok && (part < QASM_SELF_PARTS); part += 1u)
            {
                const DeviceRecordStep *const step =
                    &program->layout.step_table[program->outputs[(QASM_SELF_PARTS * amplitude) + part]];
                QasmRational fraction = {qasm_self_one, qasm_self_one};
                ok = QASM_CHECK(qasm_self_get(record, step->out_offset, step->out_bits, &fraction.numerator), step,
                                error, ENGINE_ERROR_RESOURCE) &&
                     (qasm_rational_divide(&fraction, &scale, qasm_self_part_slot(number, part), error) == 0L);
            }
        }
    }
    return ok;
}

long qasm_self_run(const QasmSelfRequest *request, QasmSelfMeasurement *measurement)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return QASM_ERROR;
    }
    EngineError *const error = request->error;
    const unsigned long long start = engine_clock_microseconds();
    const unsigned int qubits = request->qubits;
    const int shaped = (measurement != NULL) && (qubits != 0u) && (qubits <= QASM_SELF_QUBITS_MAX) &&
                       ((request->gate_count == 0u) || (request->gates != NULL)) && (request->outputs != NULL) &&
                       (request->lanes != 0ull) && (request->lanes <= QASM_SELF_LANES_MAX) &&
                       ((request->inputs != NULL) || (request->lanes == (1ull << qubits)));
    if (!QASM_CHECK(shaped, request, error, ENGINE_ERROR_REQUEST))
    {
        return QASM_ERROR;
    }
    memset(measurement, 0, sizeof(*measurement));
    const unsigned int amplitudes = 1u << qubits;
    AnchorExactInteger input_denominator;
    unsigned int bits = 0u;
    int ok = qasm_self_inputs(request, amplitudes, &input_denominator, &bits, NULL, 0u);
    QasmSelfBuild *const build = ok ? (QasmSelfBuild *)calloc(1u, sizeof(QasmSelfBuild)) : NULL;
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
    ok = ok && QASM_CHECK((build != NULL) && (build->below != NULL) && (build->built != NULL) &&
                              (build->columns != NULL) && (build->numerators != NULL),
                          request, error, ENGINE_ERROR_RESOURCE);
    QasmSelfProgram program;
    memset(&program, 0, sizeof(program));
    ok = ok && qasm_self_program(request, build, bits, &program);
    const unsigned int in_limbs = ok ? program.layout.in_limbs[0] : 0u;
    const unsigned int out_limbs = ok ? program.layout.out_limbs : 0u;
    // widening: the limb counts are unsigned ints, and with at most 2^32 lanes the product stays below 2^64
    const unsigned long long record_limbs = request->lanes * (unsigned long long)(in_limbs + out_limbs);
    ok = ok && QASM_CHECK(record_limbs <= (SIZE_MAX / sizeof(unsigned int)), request, error, ENGINE_ERROR_RESOURCE) &&
         QASM_CHECK((request->records == NULL) || (request->record_capacity >= (request->lanes * out_limbs)), request,
                    error, ENGINE_ERROR_REQUEST);
    // the limb counts were just bounded by SIZE_MAX over a limb's bytes
    unsigned int *const in =
        ok ? (unsigned int *)calloc((size_t)(request->lanes * in_limbs), sizeof(unsigned int)) : NULL;
    unsigned int *const out =
        ok ? (unsigned int *)calloc((size_t)(request->lanes * out_limbs), sizeof(unsigned int)) : NULL;
    ok = ok && QASM_CHECK((in != NULL) && (out != NULL), request, error, ENGINE_ERROR_RESOURCE) &&
         qasm_self_inputs(request, amplitudes, &input_denominator, &bits, in, in_limbs);
    if (ok && (request->on_host != 0))
    {
        CycleRecordHostRequest run;
        memset(&run, 0, sizeof(run));
        run.layout = &program.layout;
        run.in[0] = in;
        run.bodies[0] = request->lanes;
        run.count = request->lanes;
        run.out = out;
        run.error = error;
        ok = (cycle_record_run_host(&run) != CYCLE_ERROR);
    }
    else if (ok)
    {
        ok = qasm_self_device(&program.layout, in, request->lanes, out, error);
    }
    ok = ok && qasm_self_decode(request, &program, out, amplitudes, &build->denominator);
    if (ok && (request->records != NULL))
    {
        // the output limbs were bounded by SIZE_MAX over a limb's bytes with the input limbs
        memcpy(request->records, out, (size_t)(request->lanes * out_limbs) * sizeof(unsigned int));
    }
    if (ok)
    {
        measurement->steps = build->list.count;
        measurement->file_limbs = program.layout.file_limbs;
        measurement->in_limbs = in_limbs;
        measurement->out_limbs = out_limbs;
        measurement->lanes = request->lanes;
        // widening: the step count is an unsigned int
        measurement->device_bytes = (record_limbs * sizeof(unsigned int)) +
                                    ((unsigned long long)program.layout.steps * sizeof(DeviceRecordStep));
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
    measurement->microseconds = engine_clock_microseconds() - start;
    if (!ok)
    {
        engine_error_frame(error);
        return QASM_ERROR;
    }
    return 0L;
}
