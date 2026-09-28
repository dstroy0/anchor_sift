// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The unit sweep's planes (engine/analysis/unit_sweep): the residual of readings of any width, handed in as limb planes
// with their width declared. A reading built from 16-bit parts at chosen shifts has, the residual being linear, the
// residual of its parts shifted and added; each part's residual is the 16-bit volume path's, proved against the key.
// So every lane of the planes path is checked against those sums, at 16, 34, 64 and 116 bits of input, on extents that
// include a single voxel and a frame one voxel high, and on the tracker's own orders. Sixteen-bit planes give the
// volume path's lanes exactly, a constant added to every reading changes no lane, a bit past the declared width errors
// and leaves the sweep usable, and a malformed request errors. The test is one job on the device's tessera daemon,
// submitted before its first device work.
#include "sim.h"
#include "unit_sweep.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define PLANES_TEST_EXTENTS 4u

#define PLANES_TEST_ORDER_SETS 3u

#define PLANES_TEST_WIDTHS 4u

#define PLANES_TEST_PARTS_MAX 3u

#define PLANES_TEST_PART_BITS 16u

#define PLANES_TEST_INPUT_LIMBS_MAX 4u

#define PLANES_TEST_LIMBS_MAX 13u

#define PLANES_TEST_VOXELS_MAX (8u * 24u * 20u)

#define PLANES_TEST_KINDS 4ull

// the most the test puts on the device at once: the sweep's narrow and wide planes, the residual, the input planes
// and the 16-bit volume
#define PLANES_TEST_DECLARED                                                                                           \
    ((unsigned long long)PLANES_TEST_VOXELS_MAX *                                                                      \
     ((3ull * PLANES_TEST_LIMBS_MAX) + PLANES_TEST_INPUT_LIMBS_MAX + 1ull) * sizeof(unsigned int))

typedef struct
{
    unsigned int input_bits;
    unsigned int parts;
    unsigned int shift[PLANES_TEST_PARTS_MAX];
} PlanesTestWidth;

static const unsigned int PLANES_TEST_EXTENT[PLANES_TEST_EXTENTS][ENGINE_AXES] = {
    {5u, 9u, 11u}, {1u, 1u, 1u}, {3u, 1u, 7u}, {8u, 24u, 20u}};

static const unsigned int PLANES_TEST_SMOOTH[PLANES_TEST_ORDER_SETS][ENGINE_AXES] = {
    {2u, 4u, 4u}, {0u, 2u, 0u}, {2u, 34u, 34u}};

static const unsigned int PLANES_TEST_BACKGROUND[PLANES_TEST_ORDER_SETS][ENGINE_AXES] = {
    {6u, 8u, 8u}, {2u, 0u, 4u}, {6u, 96u, 96u}};

static const PlanesTestWidth PLANES_TEST_WIDTH[PLANES_TEST_WIDTHS] = {
    {16u, 1u, {0u, 0u, 0u}}, {34u, 3u, {0u, 16u, 32u}}, {64u, 3u, {0u, 24u, 48u}}, {116u, 3u, {0u, 50u, 100u}}};

typedef struct
{
    unsigned short *volume;
    unsigned int *planes;
    unsigned int *out;
} PlanesTestDevice;

typedef struct
{
    unsigned int extent[ENGINE_AXES];
    unsigned int voxels;
    unsigned int smooth[ENGINE_AXES];
    unsigned int background[ENGINE_AXES];
    unsigned int input_bits;
    unsigned int input_limbs;
    unsigned int limbs;
} PlanesTestCase;

typedef struct
{
    unsigned short *parts;
    unsigned int *planes;
    unsigned int *altered_planes;
    unsigned int *part_residual;
    unsigned int *expected;
    unsigned int *residual;
    unsigned int *cleared_residual;
    unsigned int *raised_residual;
    unsigned int *repeat_residual;
} PlanesTestHost;

typedef struct
{
    unsigned long long lanes;
    unsigned long long nonzero;
    unsigned long long against_parts;
    unsigned long long against_constant;
    unsigned long long after_error;
    unsigned long long error;
    unsigned long long over_width_asked;
} PlanesTestResults;

static void planes_test_request(const PlanesTestCase *test_case, const PlanesTestDevice *device,
                                UnitSweepRequest *request, EngineError *error)
{
    memset(request, 0, sizeof(*request));
    memset(error, 0, sizeof(*error));
    request->depth = test_case->extent[0];
    request->height = test_case->extent[1];
    request->width = test_case->extent[2];
    memcpy(request->smooth_orders, test_case->smooth, sizeof(request->smooth_orders));
    memcpy(request->background_orders, test_case->background, sizeof(request->background_orders));
    request->limbs = test_case->limbs;
    request->device_out = device->out;
    request->error = error;
}

static long planes_test_sweep(const PlanesTestCase *test_case, const PlanesTestDevice *device,
                              const unsigned short *volume, const unsigned int *planes, unsigned int *residual,
                              EngineError *error)
{
    const size_t voxels = test_case->voxels;
    UnitSweepRequest request;
    planes_test_request(test_case, device, &request, error);
    request.device_volume = (volume != NULL) ? device->volume : NULL;
    request.device_planes = (planes != NULL) ? device->planes : NULL;
    request.input_bits = (planes != NULL) ? test_case->input_bits : 0u;
    const int placed =
        ((volume == NULL) || (cudaMemcpy(device->volume, volume, voxels * sizeof(unsigned short),
                                         cudaMemcpyHostToDevice) == cudaSuccess)) &&
        ((planes == NULL) || (cudaMemcpy(device->planes, planes, voxels * test_case->input_limbs * sizeof(unsigned int),
                                         cudaMemcpyHostToDevice) == cudaSuccess));
    const long swept = placed ? unit_sweep_residual(&request) : UNIT_SWEEP_ERROR;
    const int read = (swept == 0L) && (cudaDeviceSynchronize() == cudaSuccess) &&
                     (cudaMemcpy(residual, device->out, voxels * test_case->limbs * sizeof(unsigned int),
                                 cudaMemcpyDeviceToHost) == cudaSuccess);
    return read ? 0L : UNIT_SWEEP_ERROR;
}

static void planes_test_shift_add(const unsigned int *residual, unsigned int shift, unsigned int limbs,
                                  unsigned int *sum)
{
    const unsigned int limb_shift = shift / 32u;
    const unsigned int place = shift % 32u;
    unsigned long long carry = 0ull;
    for (unsigned int limb = 0u; limb < limbs; limb += 1u)
    {
        unsigned int shifted = 0u;
        if (limb >= limb_shift)
        {
            shifted = residual[limb - limb_shift] << place;
        }
        if ((place != 0u) && (limb > limb_shift))
        {
            shifted |= residual[limb - limb_shift - 1u] >> (32u - place);
        }
        const unsigned long long total = (unsigned long long)sum[limb] + shifted + carry;
        sum[limb] = (unsigned int)(total & 0xFFFFFFFFull);
        carry = total >> 32u;
    }
}

static void planes_test_parts(const PlanesTestCase *test_case, const PlanesTestWidth *width, unsigned long long key,
                              PlanesTestHost *host)
{
    const unsigned int voxels = test_case->voxels;
    memset(host->planes, 0, (size_t)voxels * test_case->input_limbs * sizeof(unsigned int));
    for (unsigned int part = 0u; part < width->parts; part += 1u)
    {
        const unsigned int shift = width->shift[part];
        const unsigned int remaining_bits = test_case->input_bits - shift;
        const unsigned int bits = (remaining_bits < PLANES_TEST_PART_BITS) ? remaining_bits : PLANES_TEST_PART_BITS;
        const unsigned int mask = (1u << bits) - 1u;
        const unsigned int limb = shift / 32u;
        const unsigned int place = shift % 32u;
        for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
        {
            const unsigned long long draw = sim_draw(key, ((unsigned long long)voxel * PLANES_TEST_PARTS_MAX) + part);
            // a remainder below the kinds' count fits unsigned int
            const unsigned int kind = (unsigned int)(draw % PLANES_TEST_KINDS);
            // the draw's bits past the kind, masked to the part's bits, fit unsigned int
            const unsigned int value = (kind == 0u) ? 0u : ((kind == 1u) ? mask : ((unsigned int)(draw >> 8u) & mask));
            // a part is masked to 16 bits or fewer, so it narrows to unsigned short exactly
            host->parts[((size_t)part * voxels) + voxel] = (unsigned short)value;
            host->planes[((size_t)limb * voxels) + voxel] |= value << place;
            if ((place + PLANES_TEST_PART_BITS) > 32u)
            {
                host->planes[((size_t)(limb + 1u) * voxels) + voxel] |= value >> (32u - place);
            }
        }
    }
}

static unsigned long long planes_test_differ(const unsigned int *one, const unsigned int *other, unsigned int voxels,
                                             unsigned int limbs)
{
    unsigned long long differ = 0ull;
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        differ +=
            (memcmp(&one[(size_t)voxel * limbs], &other[(size_t)voxel * limbs], limbs * sizeof(unsigned int)) != 0)
                ? 1ull
                : 0ull;
    }
    return differ;
}

static void planes_test_case(SimResults *results, const PlanesTestCase *test_case, const PlanesTestWidth *width,
                             unsigned long long key, const PlanesTestDevice *device, PlanesTestHost *host,
                             PlanesTestResults *counts)
{
    const unsigned int voxels = test_case->voxels;
    const unsigned int limbs = test_case->limbs;
    const size_t lane_words = (size_t)voxels * limbs;
    const size_t plane_words = (size_t)voxels * test_case->input_limbs;
    planes_test_parts(test_case, width, key, host);
    EngineError error;
    memset(host->expected, 0, lane_words * sizeof(unsigned int));
    int ok = 1;
    for (unsigned int part = 0u; ok && (part < width->parts); part += 1u)
    {
        ok = (planes_test_sweep(test_case, device, &host->parts[(size_t)part * voxels], NULL, host->part_residual,
                                &error) == 0L);
        for (unsigned int voxel = 0u; ok && (voxel < voxels); voxel += 1u)
        {
            planes_test_shift_add(&host->part_residual[(size_t)voxel * limbs], width->shift[part], limbs,
                                  &host->expected[(size_t)voxel * limbs]);
        }
    }
    sim_check(results, ok, "each part's residual is swept by the 16-bit volume path");
    ok = ok && (planes_test_sweep(test_case, device, NULL, host->planes, host->residual, &error) == 0L);
    sim_check(results, ok, "the planes are swept at their declared width");
    const unsigned long long against_parts =
        ok ? planes_test_differ(host->residual, host->expected, voxels, limbs) : voxels;
    sim_check(results, against_parts == 0ull, "every lane is the sum of its parts' residuals, shifted");
    for (unsigned int voxel = 0u; ok && (voxel < voxels); voxel += 1u)
    {
        unsigned int any = 0u;
        for (unsigned int limb = 0u; limb < limbs; limb += 1u)
        {
            any |= host->residual[((size_t)voxel * limbs) + limb];
        }
        counts->nonzero += (any != 0u) ? 1ull : 0ull;
    }
    counts->lanes += voxels;
    counts->against_parts += against_parts;
    const unsigned int top = test_case->input_bits - 1u;
    memcpy(host->altered_planes, host->planes, plane_words * sizeof(unsigned int));
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        host->altered_planes[((size_t)(top / 32u) * voxels) + voxel] &= ~(1u << (top % 32u));
    }
    const int cleared =
        (planes_test_sweep(test_case, device, NULL, host->altered_planes, host->cleared_residual, &error) == 0L);
    for (unsigned int voxel = 0u; voxel < voxels; voxel += 1u)
    {
        host->altered_planes[((size_t)(top / 32u) * voxels) + voxel] |= 1u << (top % 32u);
    }
    const int raised = cleared && (planes_test_sweep(test_case, device, NULL, host->altered_planes,
                                                     host->raised_residual, &error) == 0L);
    const unsigned long long against_constant =
        raised ? planes_test_differ(host->cleared_residual, host->raised_residual, voxels, limbs) : voxels;
    sim_check(results, raised && (against_constant == 0ull), "the top bit added to every reading changes no lane");
    counts->against_constant += against_constant;
    if ((test_case->input_bits % 32u) == 0u)
    {
        return;
    }
    memcpy(host->altered_planes, host->planes, plane_words * sizeof(unsigned int));
    host->altered_planes[((size_t)(test_case->input_bits / 32u) * voxels) + (voxels / 2u)] |=
        1u << (test_case->input_bits % 32u);
    const long over_limit =
        planes_test_sweep(test_case, device, NULL, host->altered_planes, host->repeat_residual, &error);
    const int errored = (over_limit == UNIT_SWEEP_ERROR) && (error.kind == ENGINE_ERROR_REQUEST) &&
                        (error.module == ENGINE_MODULE_UNIT_SWEEP);
    sim_check(results, errored, "a bit past the declared width errors as a request error from the unit sweep");
    counts->over_width_asked += 1ull;
    counts->error += errored ? 1ull : 0ull;
    const int swept = (planes_test_sweep(test_case, device, NULL, host->planes, host->repeat_residual, &error) == 0L);
    const unsigned long long after_error =
        swept ? planes_test_differ(host->repeat_residual, host->residual, voxels, limbs) : voxels;
    sim_check(results, swept && (after_error == 0ull), "after the error the same planes give the same lanes");
    counts->after_error += after_error;
}

static int planes_test_reserve(PlanesTestDevice *device, PlanesTestHost *host)
{
    memset(device, 0, sizeof(*device));
    memset(host, 0, sizeof(*host));
    const size_t lane_words = (size_t)PLANES_TEST_VOXELS_MAX * PLANES_TEST_LIMBS_MAX;
    const size_t plane_words = (size_t)PLANES_TEST_VOXELS_MAX * PLANES_TEST_INPUT_LIMBS_MAX;
    host->parts =
        (unsigned short *)malloc((size_t)PLANES_TEST_VOXELS_MAX * PLANES_TEST_PARTS_MAX * sizeof(unsigned short));
    host->planes = (unsigned int *)malloc(plane_words * sizeof(unsigned int));
    host->altered_planes = (unsigned int *)malloc(plane_words * sizeof(unsigned int));
    host->part_residual = (unsigned int *)malloc(lane_words * sizeof(unsigned int));
    host->expected = (unsigned int *)malloc(lane_words * sizeof(unsigned int));
    host->residual = (unsigned int *)malloc(lane_words * sizeof(unsigned int));
    host->cleared_residual = (unsigned int *)malloc(lane_words * sizeof(unsigned int));
    host->raised_residual = (unsigned int *)malloc(lane_words * sizeof(unsigned int));
    host->repeat_residual = (unsigned int *)malloc(lane_words * sizeof(unsigned int));
    return (host->parts != NULL) && (host->planes != NULL) && (host->altered_planes != NULL) &&
           (host->part_residual != NULL) && (host->expected != NULL) && (host->residual != NULL) &&
           (host->cleared_residual != NULL) && (host->raised_residual != NULL) && (host->repeat_residual != NULL) &&
           (cudaMalloc((void **)&device->volume, (size_t)PLANES_TEST_VOXELS_MAX * sizeof(unsigned short)) ==
            cudaSuccess) &&
           (cudaMalloc((void **)&device->planes, plane_words * sizeof(unsigned int)) == cudaSuccess) &&
           (cudaMalloc((void **)&device->out, lane_words * sizeof(unsigned int)) == cudaSuccess);
}

static void planes_test_release(PlanesTestDevice *device, PlanesTestHost *host)
{
    cudaFree(device->volume);
    cudaFree(device->planes);
    cudaFree(device->out);
    free(host->parts);
    free(host->planes);
    free(host->altered_planes);
    free(host->part_residual);
    free(host->expected);
    free(host->residual);
    free(host->cleared_residual);
    free(host->raised_residual);
    free(host->repeat_residual);
    memset(device, 0, sizeof(*device));
    memset(host, 0, sizeof(*host));
}

static unsigned int planes_test_limbs(const PlanesTestCase *test_case)
{
    unsigned int bits = test_case->input_bits + 1u;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        bits += test_case->smooth[axis] + test_case->background[axis];
    }
    return (bits + 31u) / 32u;
}

static void planes_test_report(SimResults *results, const PlanesTestCase *test_case, const PlanesTestResults *counts)
{
    scriptura_text(&results->line, "  ");
    scriptura_decimal(&results->line, test_case->input_bits, 1u);
    scriptura_text(&results->line, " bits in, smooth ");
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        scriptura_character(&results->line, (axis == 0u) ? '{' : ',');
        scriptura_decimal(&results->line, test_case->smooth[axis], 1u);
    }
    scriptura_text(&results->line, "} background ");
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        scriptura_character(&results->line, (axis == 0u) ? '{' : ',');
        scriptura_decimal(&results->line, test_case->background[axis], 1u);
    }
    scriptura_text(&results->line, "}, ");
    scriptura_decimal(&results->line, test_case->limbs, 1u);
    scriptura_text(&results->line, " limbs out: ");
    scriptura_decimal(&results->line, counts->lanes, 1u);
    scriptura_text(&results->line, " lanes over the extents, ");
    scriptura_decimal(&results->line, counts->nonzero, 1u);
    scriptura_text(&results->line, " of them not zero, ");
    scriptura_decimal(&results->line, counts->against_parts, 1u);
    scriptura_text(&results->line, " differ from their parts, ");
    scriptura_decimal(&results->line, counts->against_constant, 1u);
    scriptura_text(&results->line, " move under a constant; a bit past the width errored ");
    scriptura_decimal(&results->line, counts->error, 1u);
    scriptura_text(&results->line, " of ");
    scriptura_decimal(&results->line, counts->over_width_asked, 1u);
    scriptura_text(&results->line, ", ");
    scriptura_decimal(&results->line, counts->after_error, 1u);
    scriptura_text(&results->line, " lanes differ after it\n");
    sim_flush(results);
}

static void planes_test_widths(SimResults *results, const PlanesTestDevice *device, PlanesTestHost *host)
{
    for (unsigned int orders = 0u; orders < PLANES_TEST_ORDER_SETS; orders += 1u)
    {
        for (unsigned int width = 0u; width < PLANES_TEST_WIDTHS; width += 1u)
        {
            PlanesTestResults counts;
            memset(&counts, 0, sizeof(counts));
            PlanesTestCase test_case;
            memset(&test_case, 0, sizeof(test_case));
            for (unsigned int extent = 0u; extent < PLANES_TEST_EXTENTS; extent += 1u)
            {
                memcpy(test_case.extent, PLANES_TEST_EXTENT[extent], sizeof(test_case.extent));
                test_case.voxels = test_case.extent[0] * test_case.extent[1] * test_case.extent[2];
                memcpy(test_case.smooth, PLANES_TEST_SMOOTH[orders], sizeof(test_case.smooth));
                memcpy(test_case.background, PLANES_TEST_BACKGROUND[orders], sizeof(test_case.background));
                test_case.input_bits = PLANES_TEST_WIDTH[width].input_bits;
                test_case.input_limbs = (test_case.input_bits + 31u) / 32u;
                test_case.limbs = planes_test_limbs(&test_case);
                const int fits = (test_case.voxels <= PLANES_TEST_VOXELS_MAX) &&
                                 (test_case.input_limbs <= PLANES_TEST_INPUT_LIMBS_MAX) &&
                                 (test_case.limbs <= PLANES_TEST_LIMBS_MAX);
                sim_check(results, fits, "the case fits the test's buffers");
                const unsigned long long key =
                    0x9A7E5ull + ((((unsigned long long)orders * PLANES_TEST_WIDTHS) + width) * PLANES_TEST_EXTENTS) +
                    extent;
                if (fits)
                {
                    planes_test_case(results, &test_case, &PLANES_TEST_WIDTH[width], key, device, host, &counts);
                }
            }
            sim_check(results, counts.nonzero != 0ull, "the residuals compared are not all zero");
            planes_test_report(results, &test_case, &counts);
        }
    }
}

static int planes_test_error(const UnitSweepRequest *request, const EngineError *error)
{
    return (unit_sweep_residual(request) == UNIT_SWEEP_ERROR) && (error->kind == ENGINE_ERROR_REQUEST) &&
           (error->module == ENGINE_MODULE_UNIT_SWEEP);
}

static void planes_test_errors(SimResults *results, const PlanesTestDevice *device)
{
    PlanesTestCase test_case;
    memset(&test_case, 0, sizeof(test_case));
    memcpy(test_case.extent, PLANES_TEST_EXTENT[0], sizeof(test_case.extent));
    test_case.voxels = test_case.extent[0] * test_case.extent[1] * test_case.extent[2];
    memcpy(test_case.smooth, PLANES_TEST_SMOOTH[0], sizeof(test_case.smooth));
    memcpy(test_case.background, PLANES_TEST_BACKGROUND[0], sizeof(test_case.background));
    test_case.input_bits = 34u;
    test_case.input_limbs = 2u;
    test_case.limbs = planes_test_limbs(&test_case);
    const int cleared =
        (cudaMemset(device->volume, 0, (size_t)test_case.voxels * sizeof(unsigned short)) == cudaSuccess) &&
        (cudaMemset(device->planes, 0, (size_t)test_case.voxels * 2u * sizeof(unsigned int)) == cudaSuccess);
    sim_check(results, cleared, "the errors' inputs are cleared on the device");
    EngineError error;
    UnitSweepRequest request;
    planes_test_request(&test_case, device, &request, &error);
    request.device_volume = device->volume;
    request.device_planes = device->planes;
    request.input_bits = test_case.input_bits;
    sim_check(results, planes_test_error(&request, &error), "a volume and planes both given error");
    planes_test_request(&test_case, device, &request, &error);
    sim_check(results, planes_test_error(&request, &error), "no input errors");
    planes_test_request(&test_case, device, &request, &error);
    request.device_planes = device->planes;
    sim_check(results, planes_test_error(&request, &error), "planes of no declared width error");
    planes_test_request(&test_case, device, &request, &error);
    request.device_planes = device->planes;
    request.input_bits = 32u * test_case.limbs;
    sim_check(results, planes_test_error(&request, &error), "planes as wide as the residual's limbs error");
    planes_test_request(&test_case, device, &request, &error);
    request.device_planes = device->planes;
    request.input_bits = test_case.input_bits;
    request.limbs = test_case.limbs - 1u;
    sim_check(results, planes_test_error(&request, &error), "a residual one limb short of its width errors");
    planes_test_request(&test_case, device, &request, &error);
    request.device_planes = device->planes;
    request.input_bits = test_case.input_bits;
    request.background_orders[1] = 3u;
    sim_check(results, planes_test_error(&request, &error), "an odd background order errors");
    planes_test_request(&test_case, device, &request, &error);
    request.device_planes = device->planes;
    request.input_bits = test_case.input_bits;
    request.device_out = NULL;
    sim_check(results, planes_test_error(&request, &error), "no place for the residual errors");
    planes_test_request(&test_case, device, &request, &error);
    request.device_planes = device->planes;
    request.input_bits = test_case.input_bits;
    request.depth = 0u;
    sim_check(results, planes_test_error(&request, &error), "an empty extent errors");
}

int main(int count, char **arguments)
{
    char line_buffer[SIM_LINE_CAPACITY];
    SimResults results;
    sim_open(&results, line_buffer);
    const int admitted = sim_job_submit(&results, "unit_sweep_planes_test", count, arguments, PLANES_TEST_DECLARED);
    PlanesTestDevice device;
    PlanesTestHost host;
    const int passed = (admitted != 0) && planes_test_reserve(&device, &host);
    if (admitted != 0)
    {
        sim_check(&results, passed, "the test's buffers are held on the host and the device");
    }
    if (passed)
    {
        planes_test_widths(&results, &device, &host);
        planes_test_errors(&results, &device);
    }
    if (admitted != 0)
    {
        planes_test_release(&device, &host);
        unit_sweep_release();
    }
    return sim_close(&results, "unit sweep planes test");
}
