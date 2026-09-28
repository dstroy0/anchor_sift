// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the cycle_record_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef CYCLE_RECORD_INTERNAL_H
#define CYCLE_RECORD_INTERNAL_H

#include "cycle_record_arithmetic.h"

#include "cycle_record_operate.h"

// DIVIDES is 1 for a program holding a division operation, which alone carries the division scratch
template <unsigned int WIDE, unsigned int DIVIDES> __global__ static void cycle_record_kernel(CycleRecordLaunch launch)
{
    unsigned int file[WIDE];
    unsigned int scratch[(DIVIDES != 0u) ? CODEGEN_RECORD_SCRATCH(WIDE) : 1u];
    // a register's sign lies beside it, at its place in the file. The steps are bounded by nothing held per step
    signed char sign[WIDE];
    const DeviceRecordStep *const steps = launch.steps;
    const unsigned long long stride = (unsigned long long)gridDim.x * blockDim.x;
    for (unsigned long long lane = ((unsigned long long)blockIdx.x * blockDim.x) + threadIdx.x; lane < launch.count;
         lane += stride)
    {
        const unsigned int *atom[ENGINE_RECORD_MEMBERS_MAX];
        int ok = 1;
        for (unsigned int member = 0u; member < launch.members; member += 1u)
        {
            const unsigned long long body = (launch.index != NULL)
                                                ? (unsigned long long)launch.index[(lane * launch.members) + member]
                                                : ((launch.bodies[member] == 1ull) ? 0ull : lane);
            ok = ok && (body < launch.bodies[member]);
            atom[member] = &launch.in[member][((ok != 0) ? body : 0ull) * launch.in_limbs[member]];
        }
        unsigned int *const record = &launch.out[lane * launch.out_limbs];
        for (unsigned int limb = 0u; limb < launch.out_limbs; limb += 1u)
        {
            record[limb] = 0u;
        }
        for (unsigned int at = 0u; (ok != 0) && (at < launch.step_count); at += 1u)
        {
            const DeviceRecordStep step = steps[at];
            unsigned int *const value = &file[step.place];
            signed char *const sign_out = &sign[step.place];
            if (step.operation == ENGINE_RECORD_FIELD)
            {
                cycle_record_field(atom[step.member], launch.in_limbs[step.member], step.left, step.right, value,
                                   step.limbs);
                *sign_out = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : 1;
            }
            else if (step.operation == ENGINE_RECORD_FIELD_SIGNED)
            {
                cycle_record_field(atom[step.member], launch.in_limbs[step.member], step.left, step.right, value,
                                   step.limbs);
                const unsigned int top = step.right - 1u;
                const int negative = (((value[top / 32u] >> (top % 32u)) & 1u) != 0u) ? 1 : 0;
                if (negative != 0)
                {
                    cycle_record_negate(value, step.limbs, step.right);
                }
                *sign_out = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : ((negative != 0) ? -1 : 1);
            }
            else if (step.operation == ENGINE_RECORD_CONSTANT)
            {
                value[0] = step.left;
                if (step.limbs > 1u)
                {
                    value[1] = step.right;
                }
                *sign_out = (cycle_record_is_zero(value, step.limbs) != 0) ? 0 : 1;
            }
            else if (step.operation == ENGINE_RECORD_LANE)
            {
                for (unsigned int limb = 0u; limb < step.limbs; limb += 1u)
                {
                    value[limb] = (limb == 0u) ? (unsigned int)(lane & 0xFFFFFFFFull)
                                               : ((limb == 1u) ? (unsigned int)(lane >> 32u) : 0u);
                }
                *sign_out = (lane == 0ull) ? 0 : 1;
            }
            else
            {
                cycle_record_operate<WIDE, DIVIDES>(launch, step, file, sign, scratch, value, sign_out, &ok);
            }
            if ((ok != 0) && (step.out_bits != 0u))
            {
                cycle_record_put(record, step.out_offset, step.out_bits, value, step.limbs, *sign_out);
            }
        }
        if (ok == 0)
        {
            atomicAdd(launch.refused, 1u);
        }
    }
}

unsigned long long cycle_block_seal(const EngineProgramBlock *block);

static_assert((CYCLE_BLOCK % 32u) == 0u, "cycle: the latch's thread blocks are whole warps");

#endif
