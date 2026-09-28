// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_device_program.cu: the program loaded to the device
#include "qasm_device_internal.h"

static void qasm_step(EngineRecordStep *steps, unsigned int *count, EngineRecordOperation operation, unsigned int left,
                      unsigned int right, unsigned int member)
{
    steps[*count].operation = operation;
    steps[*count].left = left;
    steps[*count].right = right;
    steps[*count].member = member;
    *count += 1u;
}

void qasm_program_release(QasmProgram *program)
{
    if (program->record != NULL)
    {
        cycle_record_release(program->record);
        program->record = NULL;
    }
    if (program->layout_built != 0u)
    {
        key_schedule_record_release(&program->layout);
        keymath_record_release(&program->key);
        program->layout_built = 0u;
    }
}

// 2^QASM_FRACTION_BITS as a CONSTANT step: left + 2^32 right
static void qasm_step_scale(EngineRecordStep *steps, unsigned int *count)
{
    qasm_step(steps, count, ENGINE_RECORD_CONSTANT, 0u, 1u << (QASM_FRACTION_BITS - 32u), 0u);
}

int qasm_program_load(QasmProgram *program, unsigned int which, int on_host, EngineError *error)
{
    memset(program, 0, sizeof(*program));
    EngineRecordStep steps[32];
    unsigned int count = 0u;
    unsigned int field_bits[6] = {QASM_FIELD_BITS, QASM_FIELD_BITS, QASM_FIELD_BITS,
                                  QASM_FIELD_BITS, QASM_FIELD_BITS, QASM_FIELD_BITS};
    unsigned int field_offset[6] = {0u, 64u, 0u, 64u, 128u, 192u};
    unsigned int fields = 2u;
    unsigned int members = 1u;
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {QASM_STATE_LIMBS, 0u, 0u};
    unsigned int outputs[2] = {0u, 0u};
    unsigned int output_count = 2u;
    if (which == QASM_PROGRAM_PAIR)
    {
        // members: the amplitude with the target's bit clear (a), the one with it set (b), and the row (u, v)
        fields = 6u;
        members = 3u;
        in_limbs[1] = QASM_STATE_LIMBS;
        in_limbs[2] = QASM_PAIR_ROW_LIMBS;
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u); // 0 a re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 0u); // 1 a im
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 1u); // 2 b re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 1u); // 3 b im
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 2u, 0u, 2u); // 4 u re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 3u, 0u, 2u); // 5 u im
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 4u, 0u, 2u); // 6 v re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 5u, 0u, 2u); // 7 v im
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 4u, 0u, 0u);      // 8 u re a re
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 5u, 1u, 0u);      // 9 u im a im
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 6u, 2u, 0u);      // 10 v re b re
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 7u, 3u, 0u);      // 11 v im b im
        qasm_step(steps, &count, ENGINE_RECORD_DIFFERENCE, 8u, 9u, 0u);   // 12 re(u a)
        qasm_step(steps, &count, ENGINE_RECORD_DIFFERENCE, 10u, 11u, 0u); // 13 re(v b)
        qasm_step(steps, &count, ENGINE_RECORD_SUM, 12u, 13u, 0u);        // 14 re(u a + v b)
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 4u, 1u, 0u);      // 15 u re a im
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 5u, 0u, 0u);      // 16 u im a re
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 6u, 3u, 0u);      // 17 v re b im
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 7u, 2u, 0u);      // 18 v im b re
        qasm_step(steps, &count, ENGINE_RECORD_SUM, 15u, 16u, 0u);        // 19 im(u a)
        qasm_step(steps, &count, ENGINE_RECORD_SUM, 17u, 18u, 0u);        // 20 im(v b)
        qasm_step(steps, &count, ENGINE_RECORD_SUM, 19u, 20u, 0u);        // 21 im(u a + v b)
        qasm_step_scale(steps, &count);                                   // 22 2^F
        qasm_step(steps, &count, ENGINE_RECORD_QUOTIENT, 14u, 22u, 0u);   // 23 re, toward zero
        qasm_step(steps, &count, ENGINE_RECORD_QUOTIENT, 21u, 22u, 0u);   // 24 im, toward zero
        outputs[0] = 23u;
        outputs[1] = 24u;
    }
    else if (which == QASM_PROGRAM_DIAGONAL)
    {
        // members: the amplitude, and the entry d, which shares the amplitude's layout
        members = 2u;
        in_limbs[1] = QASM_DIAGONAL_ENTRY_LIMBS;
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u); // 0 s re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 0u); // 1 s im
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 1u); // 2 d re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 1u); // 3 d im
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 2u, 0u, 0u);      // 4
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 3u, 1u, 0u);      // 5
        qasm_step(steps, &count, ENGINE_RECORD_DIFFERENCE, 4u, 5u, 0u);   // 6 re(d s)
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 2u, 1u, 0u);      // 7
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 3u, 0u, 0u);      // 8
        qasm_step(steps, &count, ENGINE_RECORD_SUM, 7u, 8u, 0u);          // 9 im(d s)
        qasm_step_scale(steps, &count);                                   // 10 2^F
        qasm_step(steps, &count, ENGINE_RECORD_QUOTIENT, 6u, 10u, 0u);    // 11
        qasm_step(steps, &count, ENGINE_RECORD_QUOTIENT, 9u, 10u, 0u);    // 12
        outputs[0] = 11u;
        outputs[1] = 12u;
    }
    else if (which == QASM_PROGRAM_PERMUTE)
    {
        // members: the amplitude moved here, and i^q as (c, s) = (cos, sin) of q quarter turns, two bits each
        fields = 4u;
        members = 2u;
        in_limbs[1] = QASM_PHASE_LIMBS;
        field_bits[2] = 2u;
        field_bits[3] = 2u;
        field_offset[2] = 0u;
        field_offset[3] = 32u;
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u); // 0 s re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 0u); // 1 s im
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 2u, 0u, 1u); // 2 c
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 3u, 0u, 1u); // 3 s
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 2u, 0u, 0u);      // 4
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 3u, 1u, 0u);      // 5
        qasm_step(steps, &count, ENGINE_RECORD_DIFFERENCE, 4u, 5u, 0u);   // 6 re, exact
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 2u, 1u, 0u);      // 7
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 3u, 0u, 0u);      // 8
        qasm_step(steps, &count, ENGINE_RECORD_SUM, 7u, 8u, 0u);          // 9 im, exact
        outputs[0] = 6u;
        outputs[1] = 9u;
    }
    else
    {
        // |amplitude|^2 in units of 2^-2F, exact
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 0u, 0u, 0u); // 0 re
        qasm_step(steps, &count, ENGINE_RECORD_FIELD_SIGNED, 1u, 0u, 0u); // 1 im
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 0u, 0u, 0u);      // 2
        qasm_step(steps, &count, ENGINE_RECORD_PRODUCT, 1u, 1u, 0u);      // 3
        qasm_step(steps, &count, ENGINE_RECORD_SUM, 2u, 3u, 0u);          // 4
        outputs[0] = 4u;
        output_count = 1u;
    }
    const KeymathRecordRequest encode_request = {steps,        count, field_bits, fields,        members, outputs,
                                                 output_count, NULL,  0u,         &program->key, error};
    if (keymath_record_encode(&encode_request) == KEYMATH_ERROR)
    {
        engine_error_frame(error);
        return 0;
    }
    const KeyScheduleRecordRequest layout_request = {&program->key,    field_offset, fields, in_limbs, 1,
                                                     &program->layout, error};
    if (key_schedule_record_layout(&layout_request) == KEY_SCHEDULE_ERROR)
    {
        keymath_record_release(&program->key);
        engine_error_frame(error);
        return 0;
    }
    program->layout_built = 1u;
    program->outputs = output_count;
    for (unsigned int output = 0u; output < output_count; output += 1u)
    {
        program->out_offset[output] = program->layout.step_table[outputs[output]].out_offset;
        program->out_bits[output] = program->layout.step_table[outputs[output]].out_bits;
    }
    if (!QASM_CHECK(program->layout.out_limbs <= QASM_WIDE_LIMBS, &program->layout, error, ENGINE_ERROR_LOGIC))
    {
        qasm_program_release(program);
        return 0;
    }
    if ((on_host == 0) && (cycle_record_load(&program->layout, &program->record, error) == CYCLE_ERROR))
    {
        qasm_program_release(program);
        engine_error_frame(error);
        return 0;
    }
    return 1;
}

#define QASM_EACH(at_, count_)                                                                                         \
    for (unsigned long long at_ = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; at_ < (count_);         \
         at_ += (unsigned long long)gridDim.x * blockDim.x)

__global__ void qasm_index_kernel(QasmGate gate, unsigned long long count, unsigned int members, unsigned int *index)
{
    QASM_EACH(lane, count)
    {
        qasm_lane_index(&gate, lane, &index[lane * members]);
    }
}

__global__ void qasm_repack_kernel(const unsigned int *out, unsigned int out_limbs, unsigned int offset0,
                                   unsigned int bits0, unsigned int offset1, unsigned int bits1,
                                   unsigned long long count, long long *state, unsigned int *overflow)
{
    QASM_EACH(lane, count)
    {
        if (qasm_repack_lane(out, out_limbs, offset0, bits0, offset1, bits1, lane, state) == 0)
        {
            atomicOr(overflow, 1u);
        }
    }
}
