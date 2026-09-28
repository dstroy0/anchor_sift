// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// engine_residual.cu: the residual: keys, planes and their growth
#include "engine_internal.h"

static EngineResidualResident s_residual_resident;

static EngineResidualResults s_residual_results;

static int engine_residual_key(const EngineResidualRequest *request)
{
    EngineResidualResident *const resident = &s_residual_resident;
    EngineError *const error = request->error;
    if ((resident->key != NULL) &&
        (memcmp(resident->smooth_orders, request->smooth_orders, sizeof(resident->smooth_orders)) == 0) &&
        (memcmp(resident->background_orders, request->background_orders, sizeof(resident->background_orders)) == 0))
    {
        return 1;
    }
    cycle_key_release(resident->key);
    resident->key = NULL;
    EngineStep program[RESIDUAL_STEPS];
    if (!ENGINE_CHECK(residual_program(request, program) != RESIDUAL_ERROR, request->smooth_orders, error,
                      ENGINE_ERROR_REQUEST))
    {
        return 0;
    }
    CycleKey *key = NULL;
    const long bits = engine_key_encode(program, RESIDUAL_STEPS, &key, error);
    // bits is checked non-negative before it re-signs to unsigned long
    const int imprinted = ENGINE_CHECK(bits >= 0L, program, error, ENGINE_ERROR_REQUEST) &&
                          ENGINE_CHECK((unsigned long)bits <= (32ul * ENGINE_RESIDUAL_LIMBS),
                                       request->background_orders, error, ENGINE_ERROR_REQUEST);
    if (imprinted == 0)
    {
        cycle_key_release(key);
        return 0;
    }
    resident->key = key;
    memcpy(resident->smooth_orders, request->smooth_orders, sizeof(resident->smooth_orders));
    memcpy(resident->background_orders, request->background_orders, sizeof(resident->background_orders));
    return 1;
}

static int engine_residual_reserve(size_t voxels, EngineError *error)
{
    EngineResidualResident *const resident = &s_residual_resident;
    if (resident->voxels == voxels)
    {
        return 1;
    }
    cudaFree(resident->volume);
    cudaFree(resident->residual);
    cudaFree(resident->check);
    resident->volume = NULL;
    resident->residual = NULL;
    resident->check = NULL;
    resident->voxels = 0u;
    const int ok = ENGINE_STATUS_CHECK(cudaMalloc((void **)&resident->volume, voxels * sizeof(unsigned short)),
                                       &resident->volume, error) &&
                   ENGINE_STATUS_CHECK(
                       cudaMalloc((void **)&resident->residual, voxels * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int)),
                       &resident->residual, error) &&
                   ENGINE_STATUS_CHECK(
                       cudaMalloc((void **)&resident->check, voxels * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int)),
                       &resident->check, error);
    resident->voxels = (ok != 0) ? voxels : 0u;
    return ok;
}

// an odd smooth order puts the residual half a voxel before its lane's voxel. It is allowed only where the request
// gives the place to say so.
static int engine_residual_placed(const unsigned int smooth_orders[ENGINE_AXES], int *const *offset_halves,
                                  EngineError *error)
{
    unsigned int odd = 0u;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        odd |= smooth_orders[axis] & 1u;
    }
    return ENGINE_CHECK((odd == 0u) || (*offset_halves != NULL), offset_halves, error, ENGINE_ERROR_REQUEST);
}

// the residual's place per axis in half voxels, written once the residual is made
static void engine_residual_offset(const unsigned int smooth_orders[ENGINE_AXES], int *offset_halves)
{
    for (unsigned int axis = 0u; (offset_halves != NULL) && (axis < ENGINE_AXES); axis += 1u)
    {
        // an order's parity is 0 or 1, which re-signs to int exactly
        offset_halves[axis] = -(int)(smooth_orders[axis] & 1u);
    }
}

extern "C" long engine_residual(const EngineResidualRequest *request, const unsigned int **device_residual)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return ENGINE_ERROR;
    }
    EngineError *const error = request->error;
    if (!ENGINE_CHECK(device_residual != NULL, &device_residual, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_ERROR;
    }
    *device_residual = NULL;
    const int asked = ENGINE_CHECK(request->volume != NULL, &request->volume, error, ENGINE_ERROR_REQUEST) &&
                      ENGINE_CHECK((request->depth != 0u) && (request->height != 0u) && (request->width != 0u),
                                   &request->depth, error, ENGINE_ERROR_REQUEST) &&
                      engine_residual_placed(request->smooth_orders, &request->offset_halves, error);
    if (asked == 0)
    {
        return ENGINE_ERROR;
    }
    const unsigned long long plane_voxels = (unsigned long long)request->height * request->width;
    const unsigned long long voxels = (plane_voxels <= 0xFFFFFFFFull) ? (plane_voxels * request->depth) : 0ull;
    const int sized = ENGINE_CHECK((voxels != 0ull) && (voxels <= (0xFFFFFFFFull / ENGINE_RESIDUAL_LIMBS)),
                                   &request->depth, error, ENGINE_ERROR_REQUEST) &&
                      engine_residual_key(request);
    if (sized == 0)
    {
        return ENGINE_ERROR;
    }
    EngineResidualResident *const resident = &s_residual_resident;
    int steps_succeeded =
        engine_residual_reserve((size_t)voxels, error) &&
        ENGINE_STATUS_CHECK(cudaMemcpy(resident->volume, request->volume, (size_t)voxels * sizeof(unsigned short),
                                       cudaMemcpyHostToDevice),
                            resident->volume, error);
    Atom atom;
    memset(&atom, 0, sizeof(atom));
    atom.lanes = resident->volume;
    atom.depth = request->depth;
    atom.height = request->height;
    atom.width = request->width;
    CycleRunRequest cycle_request;
    memset(&cycle_request, 0, sizeof(cycle_request));
    cycle_request.key = resident->key;
    cycle_request.atoms = &atom;
    cycle_request.count = 1ull;
    cycle_request.limbs = ENGINE_RESIDUAL_LIMBS;
    cycle_request.device_out = resident->residual;
    cycle_request.error = error;
    UnitSweepRequest sweep_request;
    memset(&sweep_request, 0, sizeof(sweep_request));
    sweep_request.device_volume = resident->volume;
    sweep_request.depth = request->depth;
    sweep_request.height = request->height;
    sweep_request.width = request->width;
    memcpy(sweep_request.smooth_orders, request->smooth_orders, sizeof(sweep_request.smooth_orders));
    memcpy(sweep_request.background_orders, request->background_orders, sizeof(sweep_request.background_orders));
    sweep_request.limbs = ENGINE_RESIDUAL_LIMBS;
    sweep_request.device_out =
        (request->unit_sweep == ENGINE_RESIDUAL_BOTH_PROVED) ? resident->check : resident->residual;
    sweep_request.error = error;
    const int key_runs = (request->unit_sweep != ENGINE_RESIDUAL_BY_UNIT_SWEEP) ? 1 : 0;
    const int sweep_runs = (request->unit_sweep != ENGINE_RESIDUAL_BY_KEY) ? 1 : 0;
    const int proving = (request->unit_sweep == ENGINE_RESIDUAL_BOTH_PROVED) ? 1 : 0;
    steps_succeeded = steps_succeeded && ENGINE_STATUS_CHECK(cudaDeviceSynchronize(), resident->volume, error);
    const unsigned long long key_started = engine_clock_microseconds();
    steps_succeeded = steps_succeeded &&
                      ((key_runs == 0) ||
                       (ENGINE_CHECK(cycle_run(&cycle_request) == 1L, resident->key, error, ENGINE_ERROR_RESOURCE) &&
                        ENGINE_STATUS_CHECK(cudaDeviceSynchronize(), resident->residual, error)));
    const unsigned long long sweep_started = engine_clock_microseconds();
    steps_succeeded =
        steps_succeeded &&
        ((sweep_runs == 0) || (ENGINE_CHECK(unit_sweep_residual(&sweep_request) == 0L, sweep_request.device_out, error,
                                            ENGINE_ERROR_RESOURCE) &&
                               ENGINE_STATUS_CHECK(cudaDeviceSynchronize(), sweep_request.device_out, error)));
    const unsigned long long sweep_finished = engine_clock_microseconds();
    unsigned long long differing_lanes = 0ull;
    const UnitSweepComparison comparison = {resident->residual,    resident->check,  voxels,
                                            ENGINE_RESIDUAL_LIMBS, &differing_lanes, error};
    steps_succeeded =
        steps_succeeded && ((proving == 0) || ENGINE_CHECK(unit_sweep_lanes_compare(&comparison) == 0L, resident->check,
                                                           error, ENGINE_ERROR_RESOURCE));
    if (steps_succeeded && (proving != 0))
    {
        s_residual_results.proved_frames += 1ull;
        s_residual_results.differing_frames += (differing_lanes != 0ull) ? 1ull : 0ull;
        s_residual_results.differing_lanes += differing_lanes;
        steps_succeeded = ENGINE_CHECK(differing_lanes == 0ull, resident->check, error, ENGINE_ERROR_LOGIC);
    }
    if (steps_succeeded == 0)
    {
        cudaFree(resident->volume);
        cudaFree(resident->residual);
        cudaFree(resident->check);
        resident->volume = NULL;
        resident->residual = NULL;
        resident->check = NULL;
        resident->voxels = 0u;
        return ENGINE_ERROR;
    }
    s_residual_results.frames += 1ull;
    s_residual_results.key_microseconds += (key_runs != 0) ? (sweep_started - key_started) : 0ull;
    s_residual_results.sweep_microseconds += (sweep_runs != 0) ? (sweep_finished - sweep_started) : 0ull;
    engine_residual_offset(request->smooth_orders, request->offset_halves);
    *device_residual = resident->residual;
    return 0L;
}

static EngineResidualPlanesResident s_residual_planes_resident;

static int engine_residual_planes_grow(unsigned int **words, size_t *capacity, size_t wanted, EngineError *error)
{
    if (wanted <= *capacity)
    {
        return 1;
    }
    cudaFree(*words);
    *words = NULL;
    *capacity = 0u;
    const int ok = ENGINE_STATUS_CHECK(cudaMalloc((void **)words, wanted * sizeof(unsigned int)), words, error);
    *capacity = (ok != 0) ? wanted : 0u;
    return ok;
}

extern "C" long engine_residual_planes(const EngineResidualPlanesRequest *request, const unsigned int **device_residual,
                                       unsigned int *limbs)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return ENGINE_ERROR;
    }
    EngineError *const error = request->error;
    if (!ENGINE_CHECK((device_residual != NULL) && (limbs != NULL), &device_residual, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_ERROR;
    }
    *device_residual = NULL;
    *limbs = 0u;
    unsigned long long residual_bits = (unsigned long long)request->input_bits + 1ull;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        residual_bits += (unsigned long long)request->smooth_orders[axis] + request->background_orders[axis];
    }
    const unsigned long long plane_voxels = (unsigned long long)request->height * request->width;
    const unsigned long long voxels = (plane_voxels <= 0xFFFFFFFFull) ? (plane_voxels * request->depth) : 0ull;
    const unsigned long long residual_limbs = (residual_bits + 31ull) / 32ull;
    const unsigned long long input_limbs = ((unsigned long long)request->input_bits + 31ull) / 32ull;
    const int asked =
        ENGINE_CHECK(request->planes != NULL, &request->planes, error, ENGINE_ERROR_REQUEST) &&
        ENGINE_CHECK(request->input_bits != 0u, &request->input_bits, error, ENGINE_ERROR_REQUEST) &&
        ENGINE_CHECK((voxels != 0ull) && (voxels <= 0xFFFFFFFFull), &request->depth, error, ENGINE_ERROR_REQUEST) &&
        ENGINE_CHECK(residual_limbs <= (0xFFFFFFFFull / 32ull), request->background_orders, error,
                     ENGINE_ERROR_REQUEST) &&
        engine_residual_placed(request->smooth_orders, &request->offset_halves, error);
    EngineResidualPlanesResident *const resident = &s_residual_planes_resident;
    int ok =
        asked &&
        engine_residual_planes_grow(&resident->planes, &resident->plane_words, (size_t)(voxels * input_limbs), error) &&
        engine_residual_planes_grow(&resident->residual, &resident->residual_words, (size_t)(voxels * residual_limbs),
                                    error) &&
        ENGINE_STATUS_CHECK(cudaMemcpy(resident->planes, request->planes,
                                       (size_t)(voxels * input_limbs) * sizeof(unsigned int), cudaMemcpyHostToDevice),
                            resident->planes, error);
    UnitSweepRequest sweep_request;
    memset(&sweep_request, 0, sizeof(sweep_request));
    sweep_request.device_planes = resident->planes;
    sweep_request.input_bits = request->input_bits;
    sweep_request.depth = request->depth;
    sweep_request.height = request->height;
    sweep_request.width = request->width;
    memcpy(sweep_request.smooth_orders, request->smooth_orders, sizeof(sweep_request.smooth_orders));
    memcpy(sweep_request.background_orders, request->background_orders, sizeof(sweep_request.background_orders));
    // the limbs are held at or below 2^32 / 32 above. They narrow to unsigned int exactly
    sweep_request.limbs = (unsigned int)residual_limbs;
    sweep_request.device_out = resident->residual;
    sweep_request.error = error;
    const unsigned long long sweep_started = engine_clock_microseconds();
    ok = ok &&
         ENGINE_CHECK(unit_sweep_residual(&sweep_request) == 0L, sweep_request.device_out, error,
                      ENGINE_ERROR_RESOURCE) &&
         ENGINE_STATUS_CHECK(cudaDeviceSynchronize(), resident->residual, error);
    if (ok == 0)
    {
        return ENGINE_ERROR;
    }
    s_residual_results.frames += 1ull;
    s_residual_results.sweep_microseconds += engine_clock_microseconds() - sweep_started;
    engine_residual_offset(request->smooth_orders, request->offset_halves);
    *device_residual = resident->residual;
    *limbs = sweep_request.limbs;
    return 0L;
}

static EngineBodiesResults s_bodies_results;

extern "C" long engine_frame_bodies(const EngineBodiesRequest *request, EngineLeaves *leaves)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return ENGINE_ERROR;
    }
    EngineError *const error = request->error;
    if (ENGINE_CHECK(leaves != NULL, &leaves, error, ENGINE_ERROR_REQUEST) == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    memset(leaves, 0, sizeof(*leaves));
    const unsigned int *device_residual = NULL;
    EngineResidualRequest residual = request->residual;
    residual.error = error;
    if (ENGINE_CHECK(engine_residual(&residual, &device_residual) == 0L, &request->residual, error,
                     ENGINE_ERROR_REQUEST) == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    unsigned int level_code = 0u;
    unsigned int proven = 0u;
    MaxTreeObjectsRequest objects;
    memset(&objects, 0, sizeof(objects));
    objects.error = error;
    objects.device_residual = device_residual;
    objects.depth = request->residual.depth;
    objects.height = request->residual.height;
    objects.width = request->residual.width;
    objects.capacity = request->capacity;
    objects.bodies = request->bodies;
    objects.labels = request->labels;
    objects.positive_words = request->positive_words;
    objects.level_code = &level_code;
    objects.proof_count = &proven;
    const long count = max_tree_objects(&objects);
    const int grown =
        (count >= 0L) && ENGINE_CHECK(grow_leaves(request->bodies, (unsigned int)count, leaves, error) != GROW_ERROR,
                                      leaves, error, ENGINE_ERROR_REQUEST);
    if (grown == 0)
    {
        engine_error_frame(error);
        engine_error_keep(error);
        return ENGINE_ERROR;
    }
    s_bodies_results.frames += 1ull;
    s_bodies_results.proven += (unsigned long long)proven;
    s_bodies_results.bodies += (unsigned long long)count;
    s_bodies_results.levels += (unsigned long long)level_code;
    return count;
}

extern "C" void engine_bodies_results(EngineBodiesResults *results)
{
    *results = s_bodies_results;
}

extern "C" void engine_residual_results(EngineResidualResults *results)
{
    *results = s_residual_results;
}

extern "C" void engine_group_voxels(const EngineGroupRequest *request)
{
    grow_group_voxels(request);
}
