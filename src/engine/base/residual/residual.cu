// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "residual.h"

#include <stdlib.h>
#include <string.h>

#define RESIDUAL_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_RESIDUAL, (unsigned int)__LINE__, (const void *)(evacaddr_), \
                       (error_))

extern "C" long residual_program(const EngineResidualRequest *request, EngineStep program[RESIDUAL_STEPS])
{
    if ((request == NULL) || (request->error == NULL))
    {
        return RESIDUAL_REFUSED;
    }
    EngineError *const error = request->error;
    if (!RESIDUAL_HELD(program != NULL, &program, error, ENGINE_ERROR_REQUEST))
    {
        return RESIDUAL_REFUSED;
    }
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        if (!RESIDUAL_HELD(((request->smooth_orders[axis] & 1u) == 0u) && ((request->background_orders[axis] & 1u) == 0u),
                           &request->smooth_orders[axis], error, ENGINE_ERROR_REQUEST))
        {
            return RESIDUAL_REFUSED;
        }
    }
    const unsigned int gain = request->background_orders[0] + request->background_orders[1]
                            + request->background_orders[2];
    memset(program, 0, RESIDUAL_STEPS * sizeof(EngineStep));
    program[0].operation = ENGINE_SMOOTH;
    memcpy(program[0].orders, request->smooth_orders, sizeof(program[0].orders));
    program[1].operation = ENGINE_KEEP;
    program[2].operation = ENGINE_SMOOTH;
    memcpy(program[2].orders, request->background_orders, sizeof(program[2].orders));
    program[3].operation = ENGINE_SCALE_SUBTRACT;
    program[3].shift = gain;
    return (long)RESIDUAL_STEPS;
}
