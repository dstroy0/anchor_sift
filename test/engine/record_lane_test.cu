// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// The lane's own number as a register, and the latch (vertical_time_compression.md, "The lane index and the latch").
// ENGINE_RECORD_LANE writes the number a sweep runs a lane as into a register, and a member of one record is read by
// every lane, so one shared record and the lanes enumerate a range, x = base + l, with nothing stored a lane. A hash of x
// against a threshold T, base and T both in the one record, runs over every lane on the host, on the device's
// interpreter and as the compiled program: the three must agree word for word, and each lane's l, x, hash and hit must
// equal the host's own 64-bit arithmetic. The latch is the first lane whose output holds, min{l : cond(l)}, infinity
// where none does. Read on the device by a tree over each warp and one atomic minimum, it must return the lane the
// host's serial scan over the same records returns and the first lane the host's own arithmetic finds, at every
// threshold from every lane hitting to none, and over 2^24 lanes on the device with only the lane brought back. Its
// edges: lane 0, the last lane, the least of many, a field across two limbs, a field of a whole limb, and bits outside
// the field that must not trip it. Under an index the lane register is still the lane, not the record it reads. A
// member of two records still refuses a sweep of three lanes, and the latch refuses a field past its record. The test is
// one job on the device's tessera daemon, submitted before its first device work.
#include "cycle.h"
#include "keymath.h"
#include "key_schedule.h"
#include "scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <stdlib.h>
#include <string.h>

#define LANE_TEST_LINE 8192ull

#define LANE_TEST_STEPS 32u

#define LANE_TEST_OUTPUTS 4u

// the enumerated lanes, run three ways
#define LANE_TEST_LANES 65536ull

// the lanes the latch reads on the device alone
#define LANE_TEST_SCALE_LANES (1ull << 24u)

// the threshold of the scale run, 2^32 / 2^22: a lane hits with chance 2^-22
#define LANE_TEST_SCALE_THRESHOLD (1ull << 10u)

// the scale run's base: its low word stays under 2^32 across all 2^24 lanes, so no lane's low word is 0, whose hash is 0
// and hits every threshold above it
#define LANE_TEST_SCALE_BASE 0x0000ABCD12345678ull

// the latch's edge records, two limbs each
#define LANE_TEST_EDGE_LANES (1ull << 20u)

#define LANE_TEST_EDGE_LIMBS 2u

// the lanes read under an index, each its own record
#define LANE_TEST_INDEXED_LANES 4096u

// the shared record: base at bit 0, 48 bits, and T at bit 48, 33 bits so that 2^32 fits, in three limbs
#define LANE_TEST_BASE_BITS 48u

#define LANE_TEST_THRESHOLD_OFFSET 48u

#define LANE_TEST_THRESHOLD_BITS 33u

#define LANE_TEST_SHARED_LIMBS 3u

// base's low word lies 2^15 under 2^32, so x = base + l carries into its high word at l = 32768, where x's low word is
// 0 and so is its hash: lane 32768 hits every threshold above 0
#define LANE_TEST_BASE 0x00001234FFFF8000ull

// the hash's two odd multipliers
#define LANE_TEST_FIRST_MULTIPLIER 0x9E3779B1u

#define LANE_TEST_SECOND_MULTIPLIER 0x85EBCA6Bu

#define LANE_TEST_THRESHOLDS 6u

// the small allocations beside the records, each on its own page of the device's allocator: a shared record, the
// latch's word, and each loaded program's steps, refusal count, block and counters. The first run's peak passed the
// records alone by one 2 MiB page
#define LANE_TEST_SMALL_BYTES (8ull << 20u)

// the most the test puts on the device at once: the scale run's records, a limb a lane, with the edge records and the
// small allocations beside
#define LANE_TEST_DECLARED \
    ((LANE_TEST_SCALE_LANES * sizeof(unsigned int)) \
     + (LANE_TEST_EDGE_LANES * LANE_TEST_EDGE_LIMBS * sizeof(unsigned int)) + LANE_TEST_SMALL_BYTES)

// every lane hits, one in 2^4, 2^8, 2^12 and 2^16, and none
static const unsigned long long s_lane_thresholds[LANE_TEST_THRESHOLDS] = {1ull << 32u, 1ull << 28u, 1ull << 24u,
                                                                           1ull << 20u, 1ull << 16u, 0ull};

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} LaneTally;

typedef struct
{
    EngineRecordStep steps[LANE_TEST_STEPS];
    unsigned int count;
    unsigned int outputs[LANE_TEST_OUTPUTS];
    unsigned int output_count;
} LaneProgram;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} LaneLoaded;

// the search's outputs, as places in its program's outputs; the hit alone where only it is written
typedef struct
{
    unsigned int lane;
    unsigned int value;
    unsigned int hash;
    unsigned int hit;
} LaneSearch;

static unsigned long long s_lane_state = 0x1A7E1A7C4E5EED01ull;

static unsigned long long lane_random(void)
{
    s_lane_state ^= s_lane_state << 13u;
    s_lane_state ^= s_lane_state >> 7u;
    s_lane_state ^= s_lane_state << 17u;
    return s_lane_state;
}

static void lane_check(LaneTally *tally, int held, const char *what)
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

// a lane, or "none" for the latch's infinity
static void lane_print(LaneTally *tally, unsigned long long lane)
{
    if (lane == CYCLE_LATCH_NONE)
    {
        scriptura_text(&tally->line, "none");
        return;
    }
    scriptura_decimal(&tally->line, lane, 1u);
}

// CYCLE_RECORD_INTERPRET, read by cycle_record_load: 1 keeps the next program loaded on the interpreter
static void lane_interpret(int interpret)
{
#if defined(_WIN32)
    _putenv_s("CYCLE_RECORD_INTERPRET", (interpret != 0) ? "1" : "0");
#else
    setenv("CYCLE_RECORD_INTERPRET", (interpret != 0) ? "1" : "0", 1);
#endif
}

static unsigned int lane_emit(LaneProgram *program, EngineRecordOperation operation, unsigned int left,
                              unsigned int right)
{
    program->steps[program->count] = EngineRecordStep{operation, left, right, 0u};
    program->count += 1u;
    return program->count - 1u;
}

static unsigned int lane_output(LaneProgram *program, unsigned int step)
{
    program->outputs[program->output_count] = step;
    program->output_count += 1u;
    return program->output_count - 1u;
}

// x = base + l and its hash: the low word of x times one odd multiplier, the xor with its own top half, and the low
// word of that times another; the hit is [hash < T], (c + |c|) / 2 with c the order of T against the hash. With
// `whole` the lane, x, the hash and the hit are written; otherwise the hit alone
static void lane_search_build(LaneProgram *program, int whole, LaneSearch *search)
{
    memset(program, 0, sizeof(*program));
    const unsigned int lane = lane_emit(program, ENGINE_RECORD_LANE, 0u, 0u);
    const unsigned int base = lane_emit(program, ENGINE_RECORD_FIELD, 0u, 0u);
    const unsigned int threshold = lane_emit(program, ENGINE_RECORD_FIELD, 1u, 0u);
    const unsigned int value = lane_emit(program, ENGINE_RECORD_SUM, base, lane);
    const unsigned int mask = lane_emit(program, ENGINE_RECORD_CONSTANT, 0xFFFFFFFFu, 0u);
    const unsigned int first = lane_emit(program, ENGINE_RECORD_CONSTANT, LANE_TEST_FIRST_MULTIPLIER, 0u);
    const unsigned int spread = lane_emit(program, ENGINE_RECORD_PRODUCT, value, first);
    const unsigned int low = lane_emit(program, ENGINE_RECORD_AND, spread, mask);
    const unsigned int half = lane_emit(program, ENGINE_RECORD_CONSTANT, 65536u, 0u);
    const unsigned int top = lane_emit(program, ENGINE_RECORD_QUOTIENT, low, half);
    const unsigned int mixed = lane_emit(program, ENGINE_RECORD_XOR, low, top);
    const unsigned int second = lane_emit(program, ENGINE_RECORD_CONSTANT, LANE_TEST_SECOND_MULTIPLIER, 0u);
    const unsigned int stirred = lane_emit(program, ENGINE_RECORD_PRODUCT, mixed, second);
    const unsigned int hash = lane_emit(program, ENGINE_RECORD_AND, stirred, mask);
    const unsigned int order = lane_emit(program, ENGINE_RECORD_COMPARE, threshold, hash);
    const unsigned int size = lane_emit(program, ENGINE_RECORD_ABSOLUTE, order, 0u);
    const unsigned int doubled = lane_emit(program, ENGINE_RECORD_SUM, order, size);
    const unsigned int two = lane_emit(program, ENGINE_RECORD_CONSTANT, 2u, 0u);
    const unsigned int hit = lane_emit(program, ENGINE_RECORD_QUOTIENT, doubled, two);
    memset(search, 0, sizeof(*search));
    if (whole != 0)
    {
        search->lane = lane_output(program, lane);
        search->value = lane_output(program, value);
        search->hash = lane_output(program, hash);
    }
    search->hit = lane_output(program, hit);
}

// the program imprinted, laid with reuse and loaded over one member of three limbs: base, then T; on the interpreter
// where `interpret`, else compiled where NVRTC and nvJitLink are found
static int lane_load(const LaneProgram *program, int interpret, LaneLoaded *loaded)
{
    memset(loaded, 0, sizeof(*loaded));
    const unsigned int field_bits[2] = {LANE_TEST_BASE_BITS, LANE_TEST_THRESHOLD_BITS};
    const unsigned int field_offset[2] = {0u, LANE_TEST_THRESHOLD_OFFSET};
    unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX] = {LANE_TEST_SHARED_LIMBS, 0u, 0u};
    const KeymathRecordRequest imprint = {program->steps, program->count, field_bits, 2u, 1u, program->outputs,
                                          program->output_count, NULL, 0u, &loaded->key, &loaded->error};
    if (keymath_record_imprint(&imprint) == KEYMATH_REFUSED)
    {
        return 0;
    }
    const KeyScheduleRecordRequest lay = {&loaded->key, field_offset, 2u, in_limbs, 1, &loaded->layout,
                                          &loaded->error};
    if (key_schedule_record_lay(&lay) == KEY_SCHEDULE_REFUSED)
    {
        keymath_record_release(&loaded->key);
        return 0;
    }
    lane_interpret(interpret);
    const long bits = cycle_record_load(&loaded->layout, &loaded->record, &loaded->error);
    lane_interpret(0);
    if (bits == CYCLE_REFUSED)
    {
        key_schedule_record_release(&loaded->layout);
        keymath_record_release(&loaded->key);
        return 0;
    }
    return 1;
}

static void lane_free(LaneLoaded *loaded)
{
    cycle_record_release(loaded->record);
    key_schedule_record_release(&loaded->layout);
    keymath_record_release(&loaded->key);
}

// `bits` of value laid into a record at `offset`
static void lane_put(unsigned int *record, unsigned int offset, unsigned int bits, unsigned long long value)
{
    for (unsigned int bit = 0u; bit < bits; bit += 1u)
    {
        const unsigned int to = offset + bit;
        const unsigned int held = (unsigned int)((value >> bit) & 1ull);
        record[to / 32u] = (record[to / 32u] & ~(1u << (to % 32u))) | (held << (to % 32u));
    }
}

// the shared record: base, then T
static void lane_shared(unsigned int *record, unsigned long long base, unsigned long long threshold)
{
    memset(record, 0, LANE_TEST_SHARED_LIMBS * sizeof(unsigned int));
    lane_put(record, 0u, LANE_TEST_BASE_BITS, base);
    lane_put(record, LANE_TEST_THRESHOLD_OFFSET, LANE_TEST_THRESHOLD_BITS, threshold);
}

// an output's low 64 bits, and whether every bit above them is 0: a never-negative output below 2^64 read whole
static unsigned long long lane_take(const unsigned int *record, const DeviceRecordStep *step, int *fits)
{
    unsigned long long low = 0ull;
    unsigned int high = 0u;
    for (unsigned int bit = 0u; bit < step->out_bits; bit += 1u)
    {
        const unsigned int from = step->out_offset + bit;
        const unsigned int held = (record[from / 32u] >> (from % 32u)) & 1u;
        if (bit < 64u)
        {
            low |= (unsigned long long)held << bit;
        }
        else
        {
            high |= held;
        }
    }
    *fits = (high == 0u) ? 1 : 0;
    return low;
}

// the host's own hash of x, in unsigned words, which wrap modulo 2^32: the low word of each product is the product
// of the low words
static unsigned int lane_hash(unsigned long long value)
{
    // the cast keeps x's low word, all the first product's low word reads
    const unsigned int low = (unsigned int)value * LANE_TEST_FIRST_MULTIPLIER;
    const unsigned int mixed = low ^ (low >> 16u);
    return mixed * LANE_TEST_SECOND_MULTIPLIER;
}

// the first of `lanes` lanes whose hash of base + l lies under T, by the host's own arithmetic; CYCLE_LATCH_NONE for
// none
static unsigned long long lane_native_first(unsigned long long base, unsigned long long threshold,
                                            unsigned long long lanes)
{
    for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
    {
        if ((unsigned long long)lane_hash(base + lane) < threshold)
        {
            return lane;
        }
    }
    return CYCLE_LATCH_NONE;
}

// the program over `lanes` lanes of one shared record in device memory, its records left in device_out
static int lane_sweep(LaneLoaded *loaded, const unsigned int *device_shared, unsigned long long lanes,
                      unsigned int *device_out)
{
    const CycleRecordRunRequest run = {loaded->record, {device_shared, NULL, NULL}, {1ull, 0ull, 0ull}, NULL, lanes,
                                       device_out, &loaded->error};
    return cycle_record_run(&run) != CYCLE_REFUSED;
}

// the latch over records in device memory, the hit's field of the program's layout; 1 where it ran
static int lane_latch_device(const LaneLoaded *loaded, const DeviceRecordStep *step, const unsigned int *device_out,
                             unsigned long long lanes, unsigned long long *first, EngineError *error)
{
    const CycleRecordLatchRequest latch = {device_out, lanes, loaded->layout.out_limbs, step->out_offset,
                                           step->out_bits, first, error};
    return cycle_record_latch(&latch) != CYCLE_REFUSED;
}

static int lane_latch_host(const LaneLoaded *loaded, const DeviceRecordStep *step, const unsigned int *out,
                           unsigned long long lanes, unsigned long long *first, EngineError *error)
{
    const CycleRecordLatchRequest latch = {out, lanes, loaded->layout.out_limbs, step->out_offset, step->out_bits,
                                           first, error};
    return cycle_record_latch_host(&latch) != CYCLE_REFUSED;
}

// The search over 2^16 lanes of one shared record at each threshold: the host, the interpreter and the compiled
// program word for word, every lane's l, x, hash and hit against the host's arithmetic, and the latch three ways
static void lane_enumerate(LaneTally *tally)
{
    const unsigned long long lanes = LANE_TEST_LANES;
    LaneProgram program;
    LaneSearch search;
    lane_search_build(&program, 1, &search);
    LaneLoaded interpreted;
    LaneLoaded compiled;
    const int interpreted_loads = lane_load(&program, 1, &interpreted);
    const int compiled_loads = interpreted_loads && lane_load(&program, 0, &compiled);
    lane_check(tally, interpreted_loads && compiled_loads, "the search program imprints, lays and loads twice");
    if (compiled_loads == 0)
    {
        if (interpreted_loads != 0)
        {
            lane_free(&interpreted);
        }
        return;
    }
    const int kernel = cycle_record_compiled(compiled.record);
    const int interpreter = (cycle_record_compiled(interpreted.record) == 0) ? 1 : 0;
    const DeviceRecordStep *const steps = compiled.layout.step_table;
    const unsigned int out_limbs = compiled.layout.out_limbs;
    const size_t words = (size_t)lanes * out_limbs;
    unsigned int *const host_out = (unsigned int *)calloc(words, sizeof(unsigned int));
    unsigned int *const interpreted_out = (unsigned int *)calloc(words, sizeof(unsigned int));
    unsigned int *const compiled_out = (unsigned int *)calloc(words, sizeof(unsigned int));
    unsigned int *device_shared = NULL;
    unsigned int *device_interpreted = NULL;
    unsigned int *device_compiled = NULL;
    int held = (host_out != NULL) && (interpreted_out != NULL) && (compiled_out != NULL)
            && (cudaMalloc((void **)&device_shared, LANE_TEST_SHARED_LIMBS * sizeof(unsigned int)) == cudaSuccess)
            && (cudaMalloc((void **)&device_interpreted, words * sizeof(unsigned int)) == cudaSuccess)
            && (cudaMalloc((void **)&device_compiled, words * sizeof(unsigned int)) == cudaSuccess);
    lane_check(tally, held, "the search's records are held on the host and the device");
    int ran_all = held;
    int words_all = held;
    unsigned long long lanes_right = 0ull;
    unsigned long long lanes_read = 0ull;
    int latched_all = held;
    scriptura_text(&tally->line, "  enumerate: x = base + l over ");
    scriptura_decimal(&tally->line, lanes, 1u);
    scriptura_text(&tally->line, " lanes of one shared record, base 0x");
    scriptura_hex(&tally->line, LANE_TEST_BASE, 1u);
    scriptura_text(&tally->line, "; the compiled program ran ");
    scriptura_text(&tally->line, (kernel != 0) ? "as its own kernel" : "on the interpreter");
    scriptura_text(&tally->line, "\n  latch, first lane with hash < T:\n");
    for (unsigned int pick = 0u; held && (pick < LANE_TEST_THRESHOLDS); pick += 1u)
    {
        const unsigned long long threshold = s_lane_thresholds[pick];
        unsigned int shared[LANE_TEST_SHARED_LIMBS];
        lane_shared(shared, LANE_TEST_BASE, threshold);
        const CycleRecordHostRequest host = {&compiled.layout, {shared, NULL, NULL}, {1ull, 0ull, 0ull}, NULL, lanes,
                                             host_out, &compiled.error};
        const int host_ran = cycle_record_run_host(&host) != CYCLE_REFUSED;
        int device_ran = (cudaMemcpy(device_shared, shared, sizeof(shared), cudaMemcpyHostToDevice) == cudaSuccess)
                      && lane_sweep(&interpreted, device_shared, lanes, device_interpreted)
                      && lane_sweep(&compiled, device_shared, lanes, device_compiled)
                      && (cudaMemcpy(interpreted_out, device_interpreted, words * sizeof(unsigned int),
                                     cudaMemcpyDeviceToHost)
                          == cudaSuccess)
                      && (cudaMemcpy(compiled_out, device_compiled, words * sizeof(unsigned int), cudaMemcpyDeviceToHost)
                          == cudaSuccess);
        ran_all = ran_all && host_ran && device_ran;
        words_all = words_all && host_ran && device_ran
                 && (memcmp(host_out, interpreted_out, words * sizeof(unsigned int)) == 0)
                 && (memcmp(host_out, compiled_out, words * sizeof(unsigned int)) == 0);
        for (unsigned long long lane = 0ull; host_ran && (lane < lanes); lane += 1ull)
        {
            const unsigned int *const record = &host_out[lane * out_limbs];
            int lane_fits = 0;
            int value_fits = 0;
            int hash_fits = 0;
            int hit_fits = 0;
            const unsigned long long read_lane = lane_take(record, &steps[program.outputs[search.lane]], &lane_fits);
            const unsigned long long value = lane_take(record, &steps[program.outputs[search.value]], &value_fits);
            const unsigned long long hash = lane_take(record, &steps[program.outputs[search.hash]], &hash_fits);
            const unsigned long long hit = lane_take(record, &steps[program.outputs[search.hit]], &hit_fits);
            const unsigned long long native = (unsigned long long)lane_hash(LANE_TEST_BASE + lane);
            lanes_read += 1ull;
            lanes_right += (lane_fits && value_fits && hash_fits && hit_fits && (read_lane == lane)
                            && (value == (LANE_TEST_BASE + lane)) && (hash == native)
                            && (hit == ((native < threshold) ? 1ull : 0ull)))
                         ? 1ull : 0ull;
        }
        const DeviceRecordStep *const hit_step = &steps[program.outputs[search.hit]];
        unsigned long long interpreted_first = 0ull;
        unsigned long long compiled_first = 0ull;
        unsigned long long host_first = 0ull;
        const int latched = device_ran && host_ran
                         && lane_latch_device(&interpreted, hit_step, device_interpreted, lanes, &interpreted_first,
                                              &interpreted.error)
                         && lane_latch_device(&compiled, hit_step, device_compiled, lanes, &compiled_first,
                                              &compiled.error)
                         && lane_latch_host(&compiled, hit_step, host_out, lanes, &host_first, &compiled.error);
        const unsigned long long native_first = lane_native_first(LANE_TEST_BASE, threshold, lanes);
        latched_all = latched_all && latched && (interpreted_first == native_first) && (compiled_first == native_first)
                   && (host_first == native_first);
        scriptura_text(&tally->line, "    T = ");
        scriptura_decimal(&tally->line, threshold, 1u);
        scriptura_text(&tally->line, ": device ");
        lane_print(tally, compiled_first);
        scriptura_text(&tally->line, ", interpreter ");
        lane_print(tally, interpreted_first);
        scriptura_text(&tally->line, ", host scan ");
        lane_print(tally, host_first);
        scriptura_text(&tally->line, ", host arithmetic ");
        lane_print(tally, native_first);
        scriptura_character(&tally->line, '\n');
    }
    scriptura_text(&tally->line, "  ");
    scriptura_decimal(&tally->line, lanes_right, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, lanes_read, 1u);
    scriptura_text(&tally->line, " lane-thresholds read l, base + l, the hash and the hit the host reckons\n");
    lane_check(tally, interpreter, "CYCLE_RECORD_INTERPRET=1 keeps the interpreted load on the interpreter");
    lane_check(tally, kernel, "the search program compiles to its own kernel (NVRTC and nvJitLink found)");
    lane_check(tally, ran_all, "every run of the search, host and device, runs every lane of one shared record");
    lane_check(tally, words_all, "the host, the interpreter and the compiled program agree word for word");
    lane_check(tally, (lanes_read != 0ull) && (lanes_right == lanes_read),
               "every lane reads its own number, base + l, the hash and the hit the host's arithmetic gives");
    lane_check(tally, latched_all,
               "the latch on the device, over the interpreter's and the compiled program's records, returns the lane "
               "the host's serial scan and the host's arithmetic find first, at every threshold");
    cudaFree(device_shared);
    cudaFree(device_interpreted);
    cudaFree(device_compiled);
    free(host_out);
    free(interpreted_out);
    free(compiled_out);
    lane_free(&interpreted);
    lane_free(&compiled);
}

// the hit alone over 2^24 lanes on the device, and the latch brings back only the lane
static void lane_scale(LaneTally *tally)
{
    const unsigned long long lanes = LANE_TEST_SCALE_LANES;
    LaneProgram program;
    LaneSearch search;
    lane_search_build(&program, 0, &search);
    LaneLoaded loaded;
    if (lane_load(&program, 0, &loaded) == 0)
    {
        lane_check(tally, 0, "the scale program imprints, lays and loads");
        return;
    }
    const DeviceRecordStep *const hit_step = &loaded.layout.step_table[program.outputs[search.hit]];
    unsigned int shared[LANE_TEST_SHARED_LIMBS];
    lane_shared(shared, LANE_TEST_SCALE_BASE, LANE_TEST_SCALE_THRESHOLD);
    unsigned int *device_shared = NULL;
    unsigned int *device_out = NULL;
    unsigned long long first = 0ull;
    const int ran = (cudaMalloc((void **)&device_shared, sizeof(shared)) == cudaSuccess)
                 && (cudaMalloc((void **)&device_out, (size_t)lanes * loaded.layout.out_limbs * sizeof(unsigned int))
                     == cudaSuccess)
                 && (cudaMemcpy(device_shared, shared, sizeof(shared), cudaMemcpyHostToDevice) == cudaSuccess)
                 && lane_sweep(&loaded, device_shared, lanes, device_out)
                 && lane_latch_device(&loaded, hit_step, device_out, lanes, &first, &loaded.error);
    const unsigned long long native_first = lane_native_first(LANE_TEST_SCALE_BASE, LANE_TEST_SCALE_THRESHOLD, lanes);
    scriptura_text(&tally->line, "  scale: ");
    scriptura_decimal(&tally->line, lanes, 1u);
    scriptura_text(&tally->line, " lanes, base 0x");
    scriptura_hex(&tally->line, LANE_TEST_SCALE_BASE, 1u);
    scriptura_text(&tally->line, ", T = ");
    scriptura_decimal(&tally->line, LANE_TEST_SCALE_THRESHOLD, 1u);
    scriptura_text(&tally->line, ", ");
    scriptura_decimal(&tally->line, loaded.layout.out_limbs, 1u);
    scriptura_text(&tally->line, " limb a record ");
    scriptura_text(&tally->line, (cycle_record_compiled(loaded.record) != 0) ? "compiled" : "interpreted");
    scriptura_text(&tally->line, ": the device latches ");
    lane_print(tally, first);
    scriptura_text(&tally->line, ", the host's arithmetic finds ");
    lane_print(tally, native_first);
    scriptura_character(&tally->line, '\n');
    lane_check(tally, ran, "the scale search runs and latches on the device");
    lane_check(tally, ran && (first == native_first), "over 2^24 lanes the device's latch is the host's first lane");
    cudaFree(device_shared);
    cudaFree(device_out);
    lane_free(&loaded);
}

// the latch's edges over records laid by hand: bits outside the field set in every record, and the field set at the
// lanes the case names; the device and the host must both return the case's lane
static void lane_edges(LaneTally *tally)
{
    const unsigned long long lanes = LANE_TEST_EDGE_LANES;
    const size_t words = (size_t)lanes * LANE_TEST_EDGE_LIMBS;
    unsigned int *const records = (unsigned int *)calloc(words, sizeof(unsigned int));
    unsigned int *device_records = NULL;
    const int held = (records != NULL)
                  && (cudaMalloc((void **)&device_records, words * sizeof(unsigned int)) == cudaSuccess);
    lane_check(tally, held, "the edge records are held");
    // each case: its field, and the lanes it sets in that field
    const unsigned int offsets[6] = {30u, 30u, 30u, 30u, 30u, 32u};
    const unsigned int widths[6] = {5u, 5u, 5u, 5u, 5u, 32u};
    const char *const names[6] = {"outside the field only", "lane 0 and others", "the last lane alone",
                                  "the least of many", "the field's bit in the second limb", "a field of a whole limb"};
    unsigned int matched = 0u;
    EngineError error;
    memset(&error, 0, sizeof(error));
    scriptura_text(&tally->line, "  latch edges over ");
    scriptura_decimal(&tally->line, lanes, 1u);
    scriptura_text(&tally->line, " records of two limbs:\n");
    for (unsigned int edge = 0u; held && (edge < 6u); edge += 1u)
    {
        const unsigned int offset = offsets[edge];
        const unsigned int bits = widths[edge];
        // every bit outside the field set, in every record
        for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
        {
            records[lane * LANE_TEST_EDGE_LIMBS] = 0xFFFFFFFFu;
            records[(lane * LANE_TEST_EDGE_LIMBS) + 1u] = 0xFFFFFFFFu;
            lane_put(&records[lane * LANE_TEST_EDGE_LIMBS], offset, bits, 0ull);
        }
        unsigned long long expected = CYCLE_LATCH_NONE;
        if (edge == 1u)
        {
            lane_put(&records[0], offset, bits, 1ull);
            lane_put(&records[777ull * LANE_TEST_EDGE_LIMBS], offset, bits, 3ull);
            lane_put(&records[(lanes - 1ull) * LANE_TEST_EDGE_LIMBS], offset, bits, 31ull);
            expected = 0ull;
        }
        else if (edge == 2u)
        {
            lane_put(&records[(lanes - 1ull) * LANE_TEST_EDGE_LIMBS], offset, bits, 16ull);
            expected = lanes - 1ull;
        }
        else if (edge == 3u)
        {
            for (unsigned int many = 0u; many < 64u; many += 1u)
            {
                const unsigned long long lane = lane_random() % lanes;
                lane_put(&records[lane * LANE_TEST_EDGE_LIMBS], offset, bits, 1ull + (lane_random() % 31ull));
                expected = (lane < expected) ? lane : expected;
            }
        }
        else if (edge == 4u)
        {
            // bit 33 of the record, the field's fourth, lies in the second limb
            const unsigned long long lane = 1ull + (lane_random() % (lanes - 1ull));
            lane_put(&records[lane * LANE_TEST_EDGE_LIMBS], offset, bits, 8ull);
            expected = lane;
        }
        else if (edge == 5u)
        {
            const unsigned long long lane = lanes / 2ull;
            lane_put(&records[lane * LANE_TEST_EDGE_LIMBS], offset, bits, 0x80000000ull);
            expected = lane;
        }
        const CycleRecordLatchRequest device = {device_records, lanes, LANE_TEST_EDGE_LIMBS, offset, bits,
                                                NULL, &error};
        unsigned long long device_first = 0ull;
        unsigned long long host_first = 0ull;
        CycleRecordLatchRequest device_latch = device;
        device_latch.first = &device_first;
        CycleRecordLatchRequest host_latch = device;
        host_latch.records = records;
        host_latch.first = &host_first;
        const int ran = (cudaMemcpy(device_records, records, words * sizeof(unsigned int), cudaMemcpyHostToDevice)
                         == cudaSuccess)
                     && (cycle_record_latch(&device_latch) != CYCLE_REFUSED)
                     && (cycle_record_latch_host(&host_latch) != CYCLE_REFUSED);
        const int right = ran && (device_first == expected) && (host_first == expected);
        matched += (right != 0) ? 1u : 0u;
        scriptura_text(&tally->line, "    ");
        scriptura_text(&tally->line, names[edge]);
        scriptura_text(&tally->line, ", field at bit ");
        scriptura_decimal(&tally->line, offset, 1u);
        scriptura_text(&tally->line, ", ");
        scriptura_decimal(&tally->line, bits, 1u);
        scriptura_text(&tally->line, " bits: device ");
        lane_print(tally, device_first);
        scriptura_text(&tally->line, ", host ");
        lane_print(tally, host_first);
        scriptura_text(&tally->line, ", laid ");
        lane_print(tally, expected);
        scriptura_character(&tally->line, '\n');
    }
    lane_check(tally, held && (matched == 6u),
               "the latch returns the laid lane on the device and the host at every edge, and none where only bits "
               "outside the field are set");
    // a field past the record, and no lanes, are refused
    unsigned long long refused_first = 0ull;
    const CycleRecordLatchRequest past = {device_records, lanes, LANE_TEST_EDGE_LIMBS, 60u, 5u, &refused_first,
                                          &error};
    CycleRecordLatchRequest past_host = past;
    past_host.records = records;
    const CycleRecordLatchRequest empty = {device_records, 0ull, LANE_TEST_EDGE_LIMBS, 0u, 1u, &refused_first,
                                           &error};
    lane_check(tally, held && (cycle_record_latch(&past) == CYCLE_REFUSED)
                          && (cycle_record_latch_host(&past_host) == CYCLE_REFUSED)
                          && (cycle_record_latch(&empty) == CYCLE_REFUSED),
               "the latch refuses a field past its record and a count of no lanes");
    cudaFree(device_records);
    free(records);
}

// Under an index the lane register is the lane: lane l reads record 4095 - l, whose base is (4095 - l) 2^20, and
// writes l and (4095 - l) 2^20 + l. A member of two records, with no index, still refuses three lanes
static void lane_indexed(LaneTally *tally)
{
    const unsigned int lanes = LANE_TEST_INDEXED_LANES;
    LaneProgram program;
    LaneSearch search;
    lane_search_build(&program, 1, &search);
    LaneLoaded loaded;
    if (lane_load(&program, 0, &loaded) == 0)
    {
        lane_check(tally, 0, "the indexed program imprints, lays and loads");
        return;
    }
    const DeviceRecordStep *const steps = loaded.layout.step_table;
    const unsigned int out_limbs = loaded.layout.out_limbs;
    unsigned int *const records = (unsigned int *)calloc((size_t)lanes * LANE_TEST_SHARED_LIMBS, sizeof(unsigned int));
    unsigned int *const index = (unsigned int *)calloc(lanes, sizeof(unsigned int));
    unsigned int *const host_out = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *const device_copy = (unsigned int *)calloc((size_t)lanes * out_limbs, sizeof(unsigned int));
    unsigned int *device_records = NULL;
    unsigned int *device_index = NULL;
    unsigned int *device_out = NULL;
    int ran = (records != NULL) && (index != NULL) && (host_out != NULL) && (device_copy != NULL);
    for (unsigned int lane = 0u; ran && (lane < lanes); lane += 1u)
    {
        lane_shared(&records[lane * LANE_TEST_SHARED_LIMBS], (unsigned long long)lane << 20u, 0ull);
        index[lane] = lanes - 1u - lane;
    }
    const CycleRecordHostRequest host = {&loaded.layout, {records, NULL, NULL}, {lanes, 0ull, 0ull}, index, lanes,
                                         host_out, &loaded.error};
    ran = ran && (cycle_record_run_host(&host) != CYCLE_REFUSED)
       && (cudaMalloc((void **)&device_records, (size_t)lanes * LANE_TEST_SHARED_LIMBS * sizeof(unsigned int))
           == cudaSuccess)
       && (cudaMalloc((void **)&device_index, (size_t)lanes * sizeof(unsigned int)) == cudaSuccess)
       && (cudaMalloc((void **)&device_out, (size_t)lanes * out_limbs * sizeof(unsigned int)) == cudaSuccess)
       && (cudaMemcpy(device_records, records, (size_t)lanes * LANE_TEST_SHARED_LIMBS * sizeof(unsigned int),
                      cudaMemcpyHostToDevice)
           == cudaSuccess)
       && (cudaMemcpy(device_index, index, (size_t)lanes * sizeof(unsigned int), cudaMemcpyHostToDevice) == cudaSuccess);
    if (ran)
    {
        const CycleRecordRunRequest run = {loaded.record, {device_records, NULL, NULL}, {lanes, 0ull, 0ull},
                                           device_index, lanes, device_out, &loaded.error};
        ran = (cycle_record_run(&run) != CYCLE_REFUSED)
           && (cudaMemcpy(device_copy, device_out, (size_t)lanes * out_limbs * sizeof(unsigned int),
                          cudaMemcpyDeviceToHost)
               == cudaSuccess);
    }
    unsigned int right = 0u;
    for (unsigned int lane = 0u; ran && (lane < lanes); lane += 1u)
    {
        const unsigned int *const record = &host_out[(size_t)lane * out_limbs];
        int lane_fits = 0;
        int value_fits = 0;
        const unsigned long long read_lane = lane_take(record, &steps[program.outputs[search.lane]], &lane_fits);
        const unsigned long long value = lane_take(record, &steps[program.outputs[search.value]], &value_fits);
        const unsigned long long body = (unsigned long long)(lanes - 1u - lane);
        right += (lane_fits && value_fits && (read_lane == lane) && (value == ((body << 20u) + lane))) ? 1u : 0u;
    }
    const int words = ran && (memcmp(host_out, device_copy, (size_t)lanes * out_limbs * sizeof(unsigned int)) == 0);
    // a member of two records and no index: three lanes are refused on the host and on the device
    const CycleRecordHostRequest short_host = {&loaded.layout, {records, NULL, NULL}, {2ull, 0ull, 0ull}, NULL, 3ull,
                                               host_out, &loaded.error};
    const CycleRecordRunRequest short_run = {loaded.record, {device_records, NULL, NULL}, {2ull, 0ull, 0ull}, NULL,
                                             3ull, device_out, &loaded.error};
    const int refused = ran && (cycle_record_run_host(&short_host) == CYCLE_REFUSED)
                     && (cycle_record_run(&short_run) == CYCLE_REFUSED);
    scriptura_text(&tally->line, "  indexed: ");
    scriptura_decimal(&tally->line, right, 1u);
    scriptura_text(&tally->line, " of ");
    scriptura_decimal(&tally->line, lanes, 1u);
    scriptura_text(&tally->line, " lanes reading record 4095 - l write l and its record's base + l\n");
    lane_check(tally, words, "the indexed program's device records equal the host's word for word");
    lane_check(tally, right == lanes, "under an index the lane register is the lane, not the record it reads");
    lane_check(tally, refused, "a member of two records with no index refuses three lanes, host and device");
    cudaFree(device_records);
    cudaFree(device_index);
    cudaFree(device_out);
    free(records);
    free(index);
    free(host_out);
    free(device_copy);
    lane_free(&loaded);
}

int main(int count, char **arguments)
{
    LaneTally tally;
    tally.checks = 0ull;
    tally.failures = 0ull;
    tally.line.room = LANE_TEST_LINE;
    tally.line.out = (char *)malloc((size_t)LANE_TEST_LINE);
    tally.line.at = 0ull;
    if (tally.line.out == NULL)
    {
        return 2;
    }
    char job_room[SIM_LINE_ROOM];
    SimTally job;
    sim_open(&job, job_room);
    const int admitted = sim_job_submit(&job, "record_lane_test", count, arguments, LANE_TEST_DECLARED);
    if (admitted != 0)
    {
        lane_enumerate(&tally);
        lane_scale(&tally);
        lane_edges(&tally);
        lane_indexed(&tally);
    }
    sim_job_release(&job);
    sim_flush(&job);
    lane_check(&tally, (admitted != 0) && (job.failures == 0ull),
               "tessera: the device's daemon admits the test's job and it releases");
    scriptura_text(&tally.line, "  record lane test: ");
    scriptura_decimal(&tally.line, tally.checks, 1u);
    scriptura_text(&tally.line, " checks, ");
    scriptura_decimal(&tally.line, tally.failures, 1u);
    scriptura_text(&tally.line, " failed\n");
    scriptura_write(&tally.line, stdout);
    free(tally.line.out);
    return (tally.failures == 0ull) ? 0 : 1;
}
