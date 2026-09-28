// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The residual's odd orders (ruling (a)): an odd smooth order is held and an odd background order refused. The key's
// window for an order o on an axis starts floor((o + 1) / 2) before the voxel, over the input reflected at its edges.
// With the smooth order s odd, the narrow term's window starts (s + 1) / 2 before and the wide term's (s + b + 1) / 2;
// with b even the two stay centerd on one point, half a voxel before the voxel of the lane's index, and the residual
// sits there with them. An odd b would center them half a voxel apart. Every lane of the key's residual and of the
// unit sweeps' is checked against the residual counted here from that definition, on odd, even and mixed orders over
// extents that include a single voxel and an axis one voxel long, and an odd background order refuses at each of the
// three sites as a request error from its own module. The test is one job on the device's tessera daemon, submitted
// before its first device work.
#include "cycle.h"
#include "key_schedule.h"
#include "keymath.h"
#include "residual.h"
#include "sim.h"
#include "unit_sweep.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define ODD_TEST_EXTENTS 5u

#define ODD_TEST_ORDER_SETS 6u

#define ODD_TEST_VOXELS_MAX (5u * 9u * 11u)

#define ODD_TEST_KINDS 4ull

// the most the test puts on the device at once: the volume, the key's lanes, the sweep's lanes, the sweep's narrow and
// wide planes and the key's scratch, each at most ENGINE_RESIDUAL_LIMBS a voxel
#define ODD_TEST_DECLARED                                                                                              \
    ((unsigned long long)ODD_TEST_VOXELS_MAX * ((6ull * ENGINE_RESIDUAL_LIMBS) + 1ull) * sizeof(unsigned int))

static const unsigned int ODD_TEST_EXTENT[ODD_TEST_EXTENTS][ENGINE_AXES] = {
    {1u, 1u, 1u}, {3u, 1u, 7u}, {5u, 9u, 11u}, {4u, 6u, 5u}, {2u, 8u, 3u}};

static const unsigned int ODD_TEST_SMOOTH[ODD_TEST_ORDER_SETS][ENGINE_AXES] = {
    {1u, 1u, 1u}, {3u, 0u, 5u}, {5u, 3u, 1u}, {0u, 1u, 0u}, {1u, 2u, 3u}, {2u, 4u, 4u}};

static const unsigned int ODD_TEST_BACKGROUND[ODD_TEST_ORDER_SETS][ENGINE_AXES] = {
    {2u, 2u, 2u}, {4u, 2u, 0u}, {6u, 6u, 2u}, {0u, 2u, 0u}, {2u, 0u, 4u}, {6u, 6u, 6u}};

typedef struct
{
    unsigned short *volume;
    unsigned int *key_out;
    unsigned int *sweep_out;
} OddTestDevice;

typedef struct
{
    unsigned short volume[ODD_TEST_VOXELS_MAX];
    long long expected[ODD_TEST_VOXELS_MAX];
    unsigned long long along[ODD_TEST_VOXELS_MAX];
    unsigned long long across[ODD_TEST_VOXELS_MAX];
    unsigned int lanes[ODD_TEST_VOXELS_MAX * ENGINE_RESIDUAL_LIMBS];
} OddTestHost;

typedef struct
{
    unsigned long long lanes;
    unsigned long long nonzero;
    unsigned long long key_differ;
    unsigned long long sweep_differ;
} OddTestResults;

// the input position a tap reads, reflected at the edges as the key's fold table reflects it
static unsigned int odd_test_reflect(long long position, long long length)
{
    const long long period = 2ll * length;
    long long folded = position % period;
    folded += (folded < 0ll) ? period : 0ll;
    folded = (folded >= length) ? (period - 1ll - folded) : folded;
    // folded lies in [0, length), and length is an extent of at most 11
    return (unsigned int)folded;
}

static unsigned long long odd_test_binomial(unsigned int order, unsigned int tap)
{
    unsigned long long value = 1ull;
    for (unsigned int step = 0u; step < tap; step += 1u)
    {
        value = (value * (unsigned long long)(order - step)) / (unsigned long long)(step + 1u);
    }
    return value;
}

// one axis of one term: each voxel's weighted sum over the order's window along the axis, the window starting
// floor((order + 1) / 2) before the voxel
static void odd_test_axis(const unsigned int *extent, unsigned int axis, unsigned int order,
                          const unsigned long long *from, unsigned long long *to)
{
    const unsigned int voxels = extent[0] * extent[1] * extent[2];
    const unsigned int stride = (axis == 0u) ? (extent[1] * extent[2]) : ((axis == 1u) ? extent[2] : 1u);
    const long long start = (long long)((order + 1u) / 2u);
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        const unsigned int coordinate = (voxel / stride) % extent[axis];
        const unsigned int line = voxel - (coordinate * stride);
        unsigned long long sum = 0ull;
        for (unsigned int tap = 0u; tap <= order; tap += 1u)
        {
            const unsigned int read =
                odd_test_reflect((long long)coordinate - start + (long long)tap, (long long)extent[axis]);
            sum += odd_test_binomial(order, tap) * from[line + (read * stride)];
        }
        to[voxel] = sum;
    }
}

// one term, B_orders applied to the volume axis by axis, into `along`
static void odd_test_term(const unsigned int *extent, const unsigned int *orders, OddTestHost *host)
{
    const unsigned int voxels = extent[0] * extent[1] * extent[2];
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        host->along[voxel] = (unsigned long long)host->volume[voxel];
    }
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        odd_test_axis(extent, axis, orders[axis], host->along, host->across);
        memcpy(host->along, host->across, (size_t)voxels * sizeof(unsigned long long));
    }
}

// the residual from its definition: the narrow term times 2^gain less the wide term
static void odd_test_expect(const unsigned int *extent, const unsigned int *smooth, const unsigned int *background,
                            OddTestHost *host)
{
    const unsigned int voxels = extent[0] * extent[1] * extent[2];
    unsigned int wide[ENGINE_AXES];
    unsigned int gain = 0u;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        wide[axis] = smooth[axis] + background[axis];
        gain += background[axis];
    }
    odd_test_term(extent, smooth, host);
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        // the narrow term is below 2^(16 + 15) and the gain at most 18: the shifted term is below 2^49
        host->expected[voxel] = (long long)(host->along[voxel] << gain);
    }
    odd_test_term(extent, wide, host);
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        // the wide term is below 2^(16 + 33), inside a signed word
        host->expected[voxel] -= (long long)host->along[voxel];
    }
}

// the lanes read back against the expected residual in ENGINE_RESIDUAL_LIMBS limbs of two's complement
static unsigned long long odd_test_differ(const OddTestHost *host, unsigned int voxels)
{
    unsigned long long differ = 0ull;
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        // the expected value's 64-bit two's complement
        const unsigned long long bits = (unsigned long long)host->expected[voxel];
        const unsigned int *const limbs = &host->lanes[(size_t)voxel * ENGINE_RESIDUAL_LIMBS];
        const unsigned int extension = (host->expected[voxel] < 0ll) ? 0xFFFFFFFFu : 0u;
        // the low and high halves of the 64-bit pattern
        int same = (limbs[0] == (unsigned int)(bits & 0xFFFFFFFFull)) && (limbs[1] == (unsigned int)(bits >> 32u));
        for (unsigned int limb = 2u; limb < ENGINE_RESIDUAL_LIMBS; limb += 1u)
        {
            same = same && (limbs[limb] == extension);
        }
        differ += (same != 0) ? 0ull : 1ull;
    }
    return differ;
}

static int odd_test_read(const unsigned int *device_lanes, unsigned int voxels, OddTestHost *host)
{
    return (cudaDeviceSynchronize() == cudaSuccess) &&
           (cudaMemcpy(host->lanes, device_lanes, (size_t)voxels * ENGINE_RESIDUAL_LIMBS * sizeof(unsigned int),
                       cudaMemcpyDeviceToHost) == cudaSuccess);
}

// the key's residual: the program residual_program writes, encoded, laid out and run on the one atom
static int odd_test_key(const unsigned int *extent, const unsigned int *smooth, const unsigned int *background,
                        const OddTestDevice *device, OddTestHost *host)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    EngineResidualRequest residual;
    memset(&residual, 0, sizeof(residual));
    memcpy(residual.smooth_orders, smooth, sizeof(residual.smooth_orders));
    memcpy(residual.background_orders, background, sizeof(residual.background_orders));
    residual.error = &error;
    EngineStep program[RESIDUAL_STEPS];
    EngineKey math;
    memset(&math, 0, sizeof(math));
    const KeymathEncodeRequest encode_request = {program, RESIDUAL_STEPS, &math, &error};
    int ok = (residual_program(&residual, program) == (long)RESIDUAL_STEPS) &&
             (keymath_encode(&encode_request) != KEYMATH_ERROR);
    EngineKeyLayout layout;
    memset(&layout, 0, sizeof(layout));
    ok = ok && (key_schedule_layout(&math, &layout, &error) != KEY_SCHEDULE_ERROR);
    keymath_key_release(&math);
    CycleKey *key = NULL;
    ok = ok && (cycle_key_load(&layout, &key, &error) != CYCLE_ERROR);
    key_schedule_release(&layout);
    Atom atom;
    memset(&atom, 0, sizeof(atom));
    atom.lanes = device->volume;
    atom.depth = extent[0];
    atom.height = extent[1];
    atom.width = extent[2];
    const CycleRunRequest run = {key, &atom, 1ull, ENGINE_RESIDUAL_LIMBS, device->key_out, &error};
    ok = ok && (cycle_run(&run) == 1L) && odd_test_read(device->key_out, extent[0] * extent[1] * extent[2], host);
    cycle_key_release(key);
    return ok;
}

static int odd_test_sweep(const unsigned int *extent, const unsigned int *smooth, const unsigned int *background,
                          const OddTestDevice *device, OddTestHost *host)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    UnitSweepRequest request;
    memset(&request, 0, sizeof(request));
    request.device_volume = device->volume;
    request.depth = extent[0];
    request.height = extent[1];
    request.width = extent[2];
    memcpy(request.smooth_orders, smooth, sizeof(request.smooth_orders));
    memcpy(request.background_orders, background, sizeof(request.background_orders));
    request.limbs = ENGINE_RESIDUAL_LIMBS;
    request.device_out = device->sweep_out;
    request.error = &error;
    return (unit_sweep_residual(&request) == 0L) &&
           odd_test_read(device->sweep_out, extent[0] * extent[1] * extent[2], host);
}

static void odd_test_case(SimResults *results, const unsigned int *extent, unsigned int orders, unsigned long long key,
                          const OddTestDevice *device, OddTestHost *host, OddTestResults *counts)
{
    const unsigned int voxels = extent[0] * extent[1] * extent[2];
    const unsigned int *const smooth = ODD_TEST_SMOOTH[orders];
    const unsigned int *const background = ODD_TEST_BACKGROUND[orders];
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        const unsigned long long draw = sim_draw(key, voxel);
        // a remainder below the kinds' count fits unsigned int
        const unsigned int kind = (unsigned int)(draw % ODD_TEST_KINDS);
        // the draw's bits past the kind, masked to 16, fit unsigned int
        const unsigned int value =
            (kind == 0u) ? 0u : ((kind == 1u) ? 0xFFFFu : (unsigned int)((draw >> 8u) & 0xFFFFull));
        // a value of at most 16 bits narrows to unsigned short exactly
        host->volume[voxel] = (unsigned short)value;
    }
    odd_test_expect(extent, smooth, background, host);
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        counts->nonzero += (host->expected[voxel] != 0ll) ? 1ull : 0ull;
    }
    counts->lanes += voxels;
    const int placed = (cudaMemcpy(device->volume, host->volume, (size_t)voxels * sizeof(unsigned short),
                                   cudaMemcpyHostToDevice) == cudaSuccess);
    const int keyed = placed && odd_test_key(extent, smooth, background, device, host);
    sim_check(results, keyed, "the key is encoded from the residual's program and run");
    const unsigned long long key_differ = keyed ? odd_test_differ(host, voxels) : voxels;
    sim_check(results, key_differ == 0ull, "every lane of the key's residual is the residual's definition");
    const int swept = placed && odd_test_sweep(extent, smooth, background, device, host);
    sim_check(results, swept, "the unit sweeps run on the same orders");
    const unsigned long long sweep_differ = swept ? odd_test_differ(host, voxels) : voxels;
    sim_check(results, sweep_differ == 0ull, "every lane of the unit sweeps' residual is the residual's definition");
    counts->key_differ += key_differ;
    counts->sweep_differ += sweep_differ;
}

static void odd_test_report(SimResults *results, unsigned int orders, const OddTestResults *counts)
{
    scriptura_text(&results->line, "  smooth ");
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        scriptura_character(&results->line, (axis == 0u) ? '{' : ',');
        scriptura_decimal(&results->line, ODD_TEST_SMOOTH[orders][axis], 1u);
    }
    scriptura_text(&results->line, "} background ");
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        scriptura_character(&results->line, (axis == 0u) ? '{' : ',');
        scriptura_decimal(&results->line, ODD_TEST_BACKGROUND[orders][axis], 1u);
    }
    scriptura_text(&results->line, "}: ");
    scriptura_decimal(&results->line, counts->lanes, 1u);
    scriptura_text(&results->line, " lanes over the extents, ");
    scriptura_decimal(&results->line, counts->nonzero, 1u);
    scriptura_text(&results->line, " of them not zero; the key differs on ");
    scriptura_decimal(&results->line, counts->key_differ, 1u);
    scriptura_text(&results->line, ", the unit sweeps on ");
    scriptura_decimal(&results->line, counts->sweep_differ, 1u);
    scriptura_character(&results->line, '\n');
    sim_flush(results);
}

// an odd background order at each of the three sites: residual_program, the key's encoding and the unit sweeps
static void odd_test_refusals(SimResults *results, const OddTestDevice *device)
{
    const unsigned int smooth[ENGINE_AXES] = {1u, 2u, 3u};
    const unsigned int background[ENGINE_AXES] = {2u, 3u, 2u};
    EngineError error;
    memset(&error, 0, sizeof(error));
    EngineResidualRequest residual;
    memset(&residual, 0, sizeof(residual));
    memcpy(residual.smooth_orders, smooth, sizeof(residual.smooth_orders));
    memcpy(residual.background_orders, background, sizeof(residual.background_orders));
    residual.error = &error;
    EngineStep program[RESIDUAL_STEPS];
    sim_check(results,
              (residual_program(&residual, program) == RESIDUAL_ERROR) && (error.kind == ENGINE_ERROR_REQUEST) &&
                  (error.module == ENGINE_MODULE_RESIDUAL),
              "an odd background order refuses the residual's program, a request error from residual");
    memset(program, 0, sizeof(program));
    program[0].operation = ENGINE_SMOOTH;
    memcpy(program[0].orders, smooth, sizeof(program[0].orders));
    program[1].operation = ENGINE_KEEP;
    program[2].operation = ENGINE_SMOOTH;
    memcpy(program[2].orders, background, sizeof(program[2].orders));
    program[3].operation = ENGINE_SCALE_SUBTRACT;
    program[3].shift = background[0] + background[1] + background[2];
    memset(&error, 0, sizeof(error));
    EngineKey math;
    memset(&math, 0, sizeof(math));
    const KeymathEncodeRequest encode_request = {program, RESIDUAL_STEPS, &math, &error};
    sim_check(results,
              (keymath_encode(&encode_request) == KEYMATH_ERROR) && (error.kind == ENGINE_ERROR_REQUEST) &&
                  (error.module == ENGINE_MODULE_KEYMATH),
              "a subtraction of terms half a voxel apart refuses the encoding, a request error from keymath");
    memset(&error, 0, sizeof(error));
    UnitSweepRequest request;
    memset(&request, 0, sizeof(request));
    request.device_volume = device->volume;
    request.depth = ODD_TEST_EXTENT[3][0];
    request.height = ODD_TEST_EXTENT[3][1];
    request.width = ODD_TEST_EXTENT[3][2];
    memcpy(request.smooth_orders, smooth, sizeof(request.smooth_orders));
    memcpy(request.background_orders, background, sizeof(request.background_orders));
    request.limbs = ENGINE_RESIDUAL_LIMBS;
    request.device_out = device->sweep_out;
    request.error = &error;
    sim_check(results,
              (unit_sweep_residual(&request) == UNIT_SWEEP_ERROR) && (error.kind == ENGINE_ERROR_REQUEST) &&
                  (error.module == ENGINE_MODULE_UNIT_SWEEP),
              "an odd background order refuses the unit sweeps, a request error from unit_sweep");
}

int main(int count, char **arguments)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    const int admitted = sim_job_submit(&results, "residual_odd_test", count, arguments, ODD_TEST_DECLARED);
    OddTestHost *const host = (OddTestHost *)malloc(sizeof(OddTestHost));
    OddTestDevice device;
    memset(&device, 0, sizeof(device));
    const size_t lane_words = (size_t)ODD_TEST_VOXELS_MAX * ENGINE_RESIDUAL_LIMBS;
    const int passed =
        (admitted != 0) && (host != NULL) &&
        (cudaMalloc((void **)&device.volume, (size_t)ODD_TEST_VOXELS_MAX * sizeof(unsigned short)) == cudaSuccess) &&
        (cudaMalloc((void **)&device.key_out, lane_words * sizeof(unsigned int)) == cudaSuccess) &&
        (cudaMalloc((void **)&device.sweep_out, lane_words * sizeof(unsigned int)) == cudaSuccess);
    if (admitted != 0)
    {
        sim_check(&results, passed, "the test's buffers are held on the host and the device");
    }
    for (unsigned int orders = 0u; passed && (orders < ODD_TEST_ORDER_SETS); orders += 1u)
    {
        OddTestResults counts;
        memset(&counts, 0, sizeof(counts));
        for (unsigned int extent = 0u; extent < ODD_TEST_EXTENTS; extent += 1u)
        {
            const unsigned long long key = 0x0DD5ull + ((unsigned long long)orders * ODD_TEST_EXTENTS) + extent;
            odd_test_case(&results, ODD_TEST_EXTENT[extent], orders, key, &device, host, &counts);
        }
        sim_check(&results, counts.nonzero != 0ull, "the residuals compared are not all zero");
        odd_test_report(&results, orders, &counts);
    }
    if (passed)
    {
        odd_test_refusals(&results, &device);
    }
    if (admitted != 0)
    {
        cudaFree(device.volume);
        cudaFree(device.key_out);
        cudaFree(device.sweep_out);
        unit_sweep_release();
    }
    free(host);
    return sim_close(&results, "residual odd test");
}
