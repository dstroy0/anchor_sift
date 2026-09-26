// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// The root noise of an object's box. Each term the noise vector table names as shared is planted in turn at three
// strengths over a scene holding one standing body; the noise detector prices the body's box and every term's yank
// through the tower and compression's coder and names the root, the term whose yank saves the most bits. The null
// names none; a planted term is the root or there is none, never another term; at the strongest each is the root; and
// every yank returns the box exactly.
#include "sim_camera.h"

#include "compression.h"
#include "noise_detector.h"
#include "tower.h"

#define ROOT_KEY 0x524F4F544E4Full

#define ROOT_PIXEL_PURPOSE 0x504958454Cull

#define ROOT_STACK_PURPOSE 0x535441434Bull

// 16 frames of 16 x 64 x 64
#define ROOT_FRAMES 16ull

#define ROOT_DEPTH 16ull

#define ROOT_HEIGHT 64ull

#define ROOT_WIDTH 64ull

// an offset of 300 and 100 electrons at gain 1 with a read variance of 4: a voxel's independent variance is 104, and
// the offset keeps the strongest planted term inside the lane
#define ROOT_OFFSET 300ull

#define ROOT_BACKGROUND 100ull

#define ROOT_READ_SQUARE 4ull

// each term's planted variances, the strongest last, where the noise terms sim plants 4
#define ROOT_STRENGTHS 3u

static const unsigned long long ROOT_SQUARES[ROOT_STRENGTHS] = {64ull, 256ull, 1024ull};

// the object: one body standing at the view's middle, 300 electrons over the reaches 3, 7 and 7
#define ROOT_BRIGHTNESS 300ull

// the null, then each term planted alone at each strength
#define ROOT_RUNS ((NOISE_ROOT_TERMS * ROOT_STRENGTHS) + 1u)

static const unsigned long long ROOT_EXTENT[4] = {ROOT_FRAMES, ROOT_DEPTH, ROOT_HEIGHT, ROOT_WIDTH};

// the object's box: every frame, z 2 to 13, y and x 16 to 47
static const unsigned long long ROOT_LOW[4] = {0ull, 2ull, 16ull, 16ull};

static const unsigned long long ROOT_HIGH[4] = {ROOT_FRAMES, 14ull, 48ull, 48ull};

// the terms by NOISE_ROOT_*, then none
static const char *const ROOT_NAMES[NOISE_ROOT_TERMS + 1u] = {"rows", "columns", "planes", "pixels", "stacks", "none"};

// The crystal's price of a lattice of ints: lifted through the tower and coded, the coder's bits. Each lattice is
// copied to the device on its own; the tower's and the coder's pools are kept at the box's, the largest.
static long root_cost(const int *values, const unsigned long long extent[4], unsigned long long *bits,
                      EngineError *error)
{
    const unsigned long long lanes = extent[0] * extent[1] * extent[2] * extent[3];
    int *device_values = NULL;
    const int *coefficients = NULL;
    unsigned int *scratch = NULL;
    unsigned int floors = 0u;
    int good = (cudaMalloc((void **)&device_values, (size_t)lanes * sizeof(int)) == cudaSuccess)
            && (cudaMemcpy(device_values, values, (size_t)lanes * sizeof(int), cudaMemcpyHostToDevice) == cudaSuccess);
    if (good)
    {
        TowerLiftRequest lift;
        memset(&lift, 0, sizeof(lift));
        lift.device_values = device_values;
        memcpy(lift.extent, extent, sizeof(lift.extent));
        lift.coefficients = &coefficients;
        lift.scratch = &scratch;
        lift.floors = &floors;
        lift.error = error;
        good = tower_lift(&lift) == 0L;
    }
    if (good)
    {
        unsigned long long chunks = 0ull;
        const unsigned long long *offsets = NULL;
        const unsigned int *stream = NULL;
        CompressionEncodeRequest code;
        memset(&code, 0, sizeof(code));
        code.device_coefficients = coefficients;
        code.count = lanes;
        code.device_scratch = scratch;
        code.chunks = &chunks;
        code.bits = bits;
        code.offsets = &offsets;
        code.stream = &stream;
        code.error = error;
        good = compression_encode(&code) == 0L;
    }
    cudaFree(device_values);
    return good ? 0L : -1L;
}

static void root_camera(SimCamera *camera, unsigned int planted, unsigned long long square)
{
    memset(camera, 0, sizeof(*camera));
    camera->key = ROOT_KEY;
    camera->offset = ROOT_OFFSET;
    camera->gain = 1ull;
    camera->read_square = ROOT_READ_SQUARE;
    camera->shot = SIM_SHOT_POISSON;
    camera->row_square = (planted == NOISE_ROOT_ROWS) ? square : 0ull;
    camera->column_square = (planted == NOISE_ROOT_COLUMNS) ? square : 0ull;
    camera->plane_square = (planted == NOISE_ROOT_PLANES) ? square : 0ull;
}

// The terms the camera law does not draw, added on the host: a value for each camera pixel, (y, x), shared by every
// frame and z plane, or a value for each frame and pixel, (t, y, x), shared by every z plane of the stack. Returns the
// voxel-frames the sum left outside the lane, held at its ends.
static unsigned long long root_plant(unsigned short *lanes, unsigned int planted, unsigned long long square)
{
    const unsigned long long plane = ROOT_HEIGHT * ROOT_WIDTH;
    const unsigned long long purpose = (planted == NOISE_ROOT_PIXELS) ? ROOT_PIXEL_PURPOSE : ROOT_STACK_PURPOSE;
    unsigned long long clipped = 0ull;
    unsigned long long at = 0ull;
    for (unsigned long long frame = 0ull; frame < ROOT_FRAMES; frame += 1ull)
    {
        for (unsigned long long z = 0ull; z < ROOT_DEPTH; z += 1ull)
        {
            for (unsigned long long pixel = 0ull; pixel < plane; pixel += 1ull)
            {
                const unsigned long long counter = (planted == NOISE_ROOT_PIXELS) ? pixel : ((frame * plane) + pixel);
                const long long value = (long long)lanes[at] + sim_centred(ROOT_KEY ^ purpose, counter, square);
                clipped += ((value < 0ll) || (value > SIM_LANE_MOST)) ? 1ull : 0ull;
                const long long held = (value < 0ll) ? 0ll : ((value > SIM_LANE_MOST) ? SIM_LANE_MOST : value);
                // held is clamped to the u16 lane's range just above
                lanes[at] = (unsigned short)held;
                at += 1ull;
            }
        }
    }
    return clipped;
}

// the box's voxels read from the scene into ints, frames, z, y and x, as the detector reads them
static void root_box_take(const unsigned short *lanes, int *values)
{
    unsigned long long at = 0ull;
    for (unsigned long long frame = ROOT_LOW[0]; frame < ROOT_HIGH[0]; frame += 1ull)
    {
        for (unsigned long long z = ROOT_LOW[1]; z < ROOT_HIGH[1]; z += 1ull)
        {
            for (unsigned long long y = ROOT_LOW[2]; y < ROOT_HIGH[2]; y += 1ull)
            {
                for (unsigned long long x = ROOT_LOW[3]; x < ROOT_HIGH[3]; x += 1ull)
                {
                    values[at] = lanes[(((((frame * ROOT_DEPTH) + z) * ROOT_HEIGHT) + y) * ROOT_WIDTH) + x];
                    at += 1ull;
                }
            }
        }
    }
}

// a signed value right-aligned in `columns`
static void root_signed_columns(ScripturaLine *line, long long value, unsigned int columns)
{
    // the magnitude of a negative value is its two's complement negation, taken unsigned
    unsigned long long magnitude = (value < 0ll) ? (0ull - (unsigned long long)value) : (unsigned long long)value;
    unsigned int width = (value < 0ll) ? 2u : 1u;
    while (magnitude >= 10ull)
    {
        magnitude /= 10ull;
        width += 1u;
    }
    for (unsigned int pad = width; pad < columns; pad += 1u)
    {
        scriptura_character(line, ' ');
    }
    scriptura_signed(line, value);
}

int main(void)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    ScripturaLine *const line = &tally.line;
    const unsigned long long count = ROOT_FRAMES * ROOT_DEPTH * ROOT_HEIGHT * ROOT_WIDTH;
    const unsigned long long lane_bytes = count * sizeof(unsigned short);
    unsigned long long box[4];
    for (unsigned int axis = 0u; axis < 4u; axis += 1u)
    {
        box[axis] = ROOT_HIGH[axis] - ROOT_LOW[axis];
    }
    const unsigned long long voxels = box[0] * box[1] * box[2] * box[3];
    // the scene's lanes, a priced lattice's copy, and the tower's and the coder's pools for the box
    const unsigned long long declared = lane_bytes + (voxels * sizeof(int)) + tower_hold_bytes(voxels)
                                      + compression_hold_bytes(voxels);
    int good = sim_job_submit(&tally, "noise_root", 0, NULL, declared);
    unsigned short *const lanes = (unsigned short *)malloc((size_t)lane_bytes);
    int *const values = (int *)malloc((size_t)voxels * sizeof(int));
    int *const residual = (int *)malloc((size_t)voxels * sizeof(int));
    int *const pattern = (int *)malloc((size_t)voxels * sizeof(int));
    int *const returned = (int *)malloc((size_t)voxels * sizeof(int));
    unsigned short *device_lanes = NULL;
    good = good && (lanes != NULL) && (values != NULL) && (residual != NULL) && (pattern != NULL)
        && (returned != NULL) && sim_took(&tally, cudaMalloc((void **)&device_lanes, (size_t)lane_bytes), "lanes");
    sim_check(&tally, good, "the scene's buffers");

    SimBody body;
    memset(&body, 0, sizeof(body));
    body.centre[0] = 8ll;
    body.centre[1] = 32ll;
    body.centre[2] = 32ll;
    body.reach[0] = 3ll;
    body.reach[1] = 7ll;
    body.reach[2] = 7ll;
    body.brightness = ROOT_BRIGHTNESS;
    body.ended = ROOT_FRAMES;
    body.parent = -1ll;
    SimScene scene;
    memset(&scene, 0, sizeof(scene));
    scene.frames = ROOT_FRAMES;
    scene.extent[0] = ROOT_DEPTH;
    scene.extent[1] = ROOT_HEIGHT;
    scene.extent[2] = ROOT_WIDTH;
    scene.background = ROOT_BACKGROUND;
    scene.bodies = 1u;
    scene.body = &body;

    scriptura_text(line, "  the root noise of an object's box: 16 frames x z 2 to 13 x y 16 to 47 x x 16 to 47 around one"
                         " standing body of 300 e, over 100 e at offset 300, read variance 4, a Poisson shot\n");
    scriptura_text(line, "  each term planted alone at variances 64, 256 and 1024, against a voxel's independent 104; a"
                         " term's saving is the box's coded bits less its residual's and its pattern's, through the"
                         " tower and compression's coder\n");
    scriptura_text(line, "  planted  variance    box bits      rows   columns    planes    pixels    stacks  root     per"
                         " mille  return\n");
    sim_flush(&tally);
    for (unsigned int run = 0u; good && (run < ROOT_RUNS); run += 1u)
    {
        const unsigned int planted = (run == 0u) ? NOISE_ROOT_TERMS : ((run - 1u) / ROOT_STRENGTHS);
        const unsigned int strength = (run == 0u) ? 0u : ((run - 1u) % ROOT_STRENGTHS);
        const unsigned long long square = (run == 0u) ? 0ull : ROOT_SQUARES[strength];
        SimCamera camera;
        root_camera(&camera, planted, square);
        unsigned long long clipped = 0ull;
        good = sim_render(&tally, &scene, &camera, device_lanes, NULL, NULL, &clipped)
            && sim_took(&tally, cudaMemcpy(lanes, device_lanes, (size_t)lane_bytes, cudaMemcpyDeviceToHost),
                        "lanes read");
        if (good && ((planted == NOISE_ROOT_PIXELS) || (planted == NOISE_ROOT_STACKS)))
        {
            clipped += root_plant(lanes, planted, square);
        }
        sim_check(&tally, good && (clipped == 0ull), "the scene rendered with no lane clipped");
        if (good == 0)
        {
            break;
        }
        root_box_take(lanes, values);
        EngineError error;
        memset(&error, 0, sizeof(error));
        NoiseRootReading reading;
        memset(&reading, 0, sizeof(reading));
        NoiseRootRequest request;
        memset(&request, 0, sizeof(request));
        request.volume = lanes;
        memcpy(request.extent, ROOT_EXTENT, sizeof(request.extent));
        memcpy(request.low, ROOT_LOW, sizeof(request.low));
        memcpy(request.high, ROOT_HIGH, sizeof(request.high));
        request.cost = root_cost;
        request.reading = &reading;
        request.residual = residual;
        request.pattern = pattern;
        request.error = &error;
        good = noise_root_box(&request) == 0L;
        sim_check(&tally, good, "the detector priced the box and every term's yank");
        if (good == 0)
        {
            break;
        }
        int exact = 0;
        if (reading.root < NOISE_ROOT_TERMS)
        {
            NoiseReturnRequest back;
            memset(&back, 0, sizeof(back));
            back.residual = residual;
            back.pattern = pattern;
            back.term = reading.root;
            memcpy(back.box, box, sizeof(back.box));
            back.values = returned;
            back.error = &error;
            exact = (noise_root_return(&back) == 0L)
                 && (memcmp(returned, values, (size_t)voxels * sizeof(int)) == 0);
        }
        else
        {
            exact = memcmp(residual, values, (size_t)voxels * sizeof(int)) == 0;
        }
        scriptura_text(line, "  ");
        scriptura_text_columns(line, ROOT_NAMES[planted], 7u);
        scriptura_decimal_columns(line, square, 10u);
        scriptura_decimal_columns(line, reading.box_bits, 12u);
        for (unsigned int term = 0u; term < NOISE_ROOT_TERMS; term += 1u)
        {
            root_signed_columns(line, reading.saved[term], 10u);
        }
        scriptura_text(line, "  ");
        scriptura_text_columns(line, ROOT_NAMES[reading.root], 7u);
        // a root saves more than 0 and less than the box's bits, which are a few million here, so the box's bits
        // convert to long long exactly and 1000 times the saving is far below 2^63
        const long long per_mille = (reading.root < NOISE_ROOT_TERMS)
                                      ? ((1000ll * reading.saved[reading.root]) / (long long)reading.box_bits)
                                      : 0ll;
        root_signed_columns(line, per_mille, 11u);
        scriptura_text(line, (exact != 0) ? "  exact\n" : "  differs\n");
        sim_flush(&tally);
        if (planted == NOISE_ROOT_TERMS)
        {
            sim_check(&tally, reading.root == NOISE_ROOT_TERMS, "the null names no root");
        }
        else
        {
            sim_check(&tally, (reading.root == planted) || (reading.root == NOISE_ROOT_TERMS),
                      "the root is the planted term or none, never another term");
        }
        if ((planted != NOISE_ROOT_TERMS) && (strength == (ROOT_STRENGTHS - 1u)))
        {
            sim_check(&tally, reading.root == planted, "at the strongest, the root is the planted term");
        }
        sim_check(&tally, exact != 0, "the root's residual and pattern return the box exactly");
    }
    cudaFree(device_lanes);
    free(lanes);
    free(values);
    free(residual);
    free(pattern);
    free(returned);
    return sim_close(&tally, "noise root");
}
