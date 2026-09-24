// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "crc.h"
#include "cycle.h"
#include "fingerprint.h"
#include "flatten.h"
#include "link_objects.h"
#include "print_pair.h"
#include "velocity.h"
#include "division.h"
#include "contact_side.h"
#include "residual_survey.h"
#include "run_cfg.h"
#include "run_log.h"
#include "schedule.h"
#include "score_sample.h"
#include "track.h"
#include "engine.h"
#include "obsignatio.h"
#include "tessera.h"

#include <cuda_runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned int s_ingest = 0u;

typedef enum
{
    RUN_SCHEDULE = 0,
    RUN_IAPX_PROVE = 1,
    RUN_ENTROPY = 2,
    RUN_FLOOR = 3,
    RUN_FLATTEN = 4,
    RUN_TRACK = 5,
    RUN_FINGERPRINT = 6,
    RUN_PARTS = 7
} RunPart;

static const char *const RUN_PART_NAMES[RUN_PARTS] = {"schedule", "iapx-prove", "entropy", "floor", "flatten", "track",
                                                      "fingerprint"};

#define RUN_PART_ROOM 16u

static RunPart s_parts[RUN_PART_ROOM];

static unsigned int s_part_count = 0u;

static int run_part_named(const char *name, RunPart *part)
{
    for (unsigned int each = 0u; each < RUN_PARTS; each += 1u)
    {
        if (strcmp(name, RUN_PART_NAMES[each]) == 0)
        {
            *part = (RunPart)each;
            return 1;
        }
    }
    return 0;
}

#define RUN_JOB_HOLDING_MICROSECONDS 2000000ull
#define RUN_JOB_SWEEP_MICROSECONDS 20000ull
#define RUN_JOB_IDLE_MICROSECONDS 5000000ull

static unsigned int s_override = 0u;

typedef struct
{
    TesseraClient *client;
    TesseraTicket ticket;
    unsigned long long declared;
} RunJob;

static unsigned long long run_job_declared(const RunInputs *inputs, const char *name)
{
    // the largest sample's lattice in 16-bit lanes; the daemon measures the rest and keeps the peak under the signum
    unsigned long long most = 0ull;
    for (unsigned int at = 0u; at < inputs->count; at += 1u)
    {
        EngineError error;
        memset(&error, 0, sizeof(error));
        unsigned long long lanes = 0ull;
        unsigned long long extent[4] = {0ull, 0ull, 0ull, 0ull};
        if (s_ingest != 0u)
        {
            if (engine_source_lanes(inputs->source, inputs->samples[at], &lanes, &error) != 0L)
            {
                fprintf(stderr, "  tessera: %s: the source of %s could not be described\n", name, inputs->samples[at]);
                return 0ull;
            }
        }
        else if (engine_iapx_head(inputs->set, inputs->samples[at], extent, &error) == 0L)
        {
            lanes = extent[0] * extent[1] * extent[2] * extent[3];
        }
        most = (lanes > most) ? lanes : most;
    }
    return most * sizeof(unsigned short);
}

static int run_job_submit(const char *name, const CfgText *effective, const RunInputs *inputs, RunJob *job)
{
    // every part is one job on the device's tessera daemon, keyed by the part and the whole effective request
    memset(job, 0, sizeof(*job));
    EngineError error;
    memset(&error, 0, sizeof(error));
    int device = 0;
    cudaDeviceProp properties;
    if ((cudaGetDevice(&device) != cudaSuccess) || (cudaGetDeviceProperties(&properties, device) != cudaSuccess))
    {
        fprintf(stderr, "  tessera: %s: the device did not answer who it is\n", name);
        return 0;
    }
    TesseraJobAsk ask;
    memset(&ask, 0, sizeof(ask));
    memcpy(ask.device, properties.uuid.bytes, TESSERA_DEVICE_BYTES);
#if defined(_WIN32)
    memcpy(&ask.luid, properties.luid, sizeof(ask.luid));
#endif
    const size_t named = strlen(name) + 1u;
    const size_t request_bytes = named + effective->length;
    unsigned char *const request = (unsigned char *)malloc(request_bytes);
    if (request == NULL)
    {
        return 0;
    }
    memcpy(request, name, named);
    memcpy(request + named, effective->bytes, effective->length);
    const ObsignatioSignumRequest signum = {request, request_bytes, NULL, OBSIGNATIO_MODE_HASH, ask.signum.bytes,
                                            ENGINE_SIGNUM_BYTES, &error};
    const long hashed = obsignatio_signum(&signum);
    free(request);
    job->declared = run_job_declared(inputs, name);
    char daemon[ENGINE_PATH_ROOM];
    const int placed = engine_program_directory(daemon, sizeof(daemon))
                    && (strlen(daemon) + sizeof("/tessera_daemon.exe") <= sizeof(daemon));
    if ((hashed != 0L) || (job->declared == 0ull) || !placed)
    {
        fprintf(stderr, "  tessera: %s: no job could be asked (signum, declaration or the daemon's place)\n", name);
        return 0;
    }
#if defined(_WIN32)
    strcat(daemon, "\\tessera_daemon.exe");
#else
    strcat(daemon, "/tessera_daemon");
#endif
    ask.declared = job->declared;
    ask.holding_microseconds = RUN_JOB_HOLDING_MICROSECONDS;
    ask.sweep_microseconds = RUN_JOB_SWEEP_MICROSECONDS;
    ask.idle_microseconds = RUN_JOB_IDLE_MICROSECONDS;
    ask.daemon_path = daemon;
    ask.error = &error;
    if (tessera_job_submit(&ask, &job->client, &job->ticket) != 0L)
    {
        fprintf(stderr, "  tessera: %s: the daemon (%s) did not take the job\n", name, daemon);
        return 0;
    }
    if (job->ticket.asked != 0u)
    {
        printf("  tessera: %s declares %llu bytes over its kept peak of %llu\n", name, job->declared,
               job->ticket.last_peak);
        const long answered = (s_override != 0u) ? tessera_job_override(job->client, &job->ticket, &error)
                                                 : tessera_job_wait(job->client, &job->ticket, &error);
        if ((answered != 0L) || (job->ticket.lost != 0u))
        {
            fprintf(stderr, "  tessera: %s was held past its holding time and lost; --override admits it on its"
                            " declaration (ticket in %s)\n", name, job->ticket.lost_path);
            if (answered == 0L)
            {
                tessera_job_precalc_kept(job->client, &error);
            }
            job->client = NULL;
            return 0;
        }
    }
    printf("  tessera: %s admitted, %llu bytes reserved\n", name, job->ticket.granted);
    return 1;
}

static void run_job_release(const char *name, RunJob *job)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    if ((job->client == NULL) || (tessera_job_release(job->client, &job->ticket, &error) != 0L))
    {
        fprintf(stderr, "  tessera: %s did not release\n", name);
        return;
    }
    job->client = NULL;
    printf("  tessera: %s released, peak %llu bytes%s\n", name, job->ticket.last_peak,
           (job->ticket.last_peak > job->declared) ? ", more than it declared" : "");
}

static int run_part_named_already(RunPart part)
{
    for (unsigned int each = 0u; each < s_part_count; each += 1u)
    {
        if (s_parts[each] == part)
        {
            return 1;
        }
    }
    return 0;
}

#define RUN_VOCABULARY_STEPS 12u

#define RUN_VOCABULARY_OUTPUTS 3u

static const EngineRecordStep RUN_VOCABULARY_PROGRAM[RUN_VOCABULARY_STEPS] = {
    {ENGINE_RECORD_FIELD, MAX_TREE_FIELD_MASS, 0u, 0u},      {ENGINE_RECORD_FIELD, MAX_TREE_FIELD_SUM_Z, 0u, 0u},
    {ENGINE_RECORD_FIELD, MAX_TREE_FIELD_SUM_Y, 0u, 0u},     {ENGINE_RECORD_FIELD, MAX_TREE_FIELD_MOMENT_ZY, 0u, 0u},
    {ENGINE_RECORD_PRODUCT, 0u, 3u, 0u},                     {ENGINE_RECORD_PRODUCT, 1u, 2u, 0u},
    {ENGINE_RECORD_DIFFERENCE, 4u, 5u, 0u},                  {ENGINE_RECORD_CONSTANT, 0u, 0u, 0u},
    {ENGINE_RECORD_ABSOLUTE, 6u, 0u, 0u},                    {ENGINE_RECORD_COMPARE, 6u, 7u, 0u},
    {ENGINE_RECORD_COMPARE, 8u, 6u, 0u},                     {ENGINE_RECORD_COMPARE, 6u, 8u, 0u}};

static const unsigned int RUN_VOCABULARY_OUTPUT[RUN_VOCABULARY_OUTPUTS] = {9u, 10u, 11u};

static_assert(PRINT_PAIR_BANDS == FINGERPRINT_OUTPUTS, "track_driver: the pair program reads every band the print writes");

typedef struct
{
    unsigned int offset[FINGERPRINT_OUTPUTS];
    unsigned int bits[FINGERPRINT_OUTPUTS];
    unsigned int limbs;
} RunPrintFields;

static void run_print_request(const RunInputs *inputs, FingerprintRequest *print)
{
    memset(print, 0, sizeof(*print));
    print->mass_field = MAX_TREE_FIELD_MASS;
    for (unsigned int axis = 0u; axis < 3u; axis += 1u)
    {
        print->sum_field[axis] = MAX_TREE_FIELD_SUM_Z + axis;
        print->voxel_pm[axis] = inputs->voxel_pm[axis];
    }
    for (unsigned int moment = 0u; moment < FINGERPRINT_MOMENTS; moment += 1u)
    {
        print->moment_field[moment] = MAX_TREE_FIELD_MOMENT_ZZ + moment;
    }
}

static int run_pair_request(const RunPrintFields *fields, EngineRecordStep program[PRINT_PAIR_STEPS],
                            unsigned int outputs[PRINT_PAIR_OUTPUTS], EngineRecordRequest *imprint)
{
    memset(imprint, 0, sizeof(*imprint));
    imprint->steps = program;
    imprint->count = PRINT_PAIR_STEPS;
    imprint->field_bits = fields->bits;
    imprint->field_offset = fields->offset;
    imprint->fields = PRINT_PAIR_BANDS;
    imprint->in_limbs[0] = fields->limbs;
    imprint->in_limbs[1] = fields->limbs;
    imprint->members = 2u;
    imprint->outputs = outputs;
    imprint->output_count = PRINT_PAIR_OUTPUTS;
    return print_pair_program(program, outputs) != PRINT_PAIR_REFUSED;
}

static long run_pair_imprint(const RunPrintFields *fields, CycleRecord **record, EngineError *error)
{
    EngineRecordStep program[PRINT_PAIR_STEPS];
    unsigned int outputs[PRINT_PAIR_OUTPUTS];
    EngineRecordRequest imprint;
    *record = NULL;
    const long out_bits = (run_pair_request(fields, program, outputs, &imprint) == 0)
                        ? ENGINE_REFUSED : engine_record_imprint(&imprint, record, error);
    return ((out_bits == ENGINE_REFUSED) || (cycle_record_out_limbs(*record) != 1u)) ? ENGINE_REFUSED : out_bits;
}

static int run_pair_proof(const FlattenHeld *held, const unsigned int *prints, const RunPrintFields *fields)
{
    CycleRecord *record = NULL;
    const size_t lanes = (size_t)held->bodies;
    unsigned int *const index = (unsigned int *)malloc((2u * lanes + 1u) * sizeof(unsigned int));
    unsigned int *const weight = (unsigned int *)malloc((2u * lanes + 1u) * sizeof(unsigned int));
    EngineError error;
    memset(&error, 0, sizeof(error));
    int good = (run_pair_imprint(fields, &record, &error) != ENGINE_REFUSED) && (index != NULL) && (weight != NULL)
            && (held->bodies <= 0xFFFFFFFFull);
    for (size_t lane = 0u; good && (lane < lanes); lane += 1u)
    {
        index[2u * lane] = (unsigned int)lane;
        index[(2u * lane) + 1u] = (unsigned int)lane;
    }
    unsigned long long sweep = 0ull;
    const EngineRecordSweep itself = {record,       {prints, prints}, {held->bodies, held->bodies}, index,
                                      held->bodies, weight,           &sweep,                       &error};
    good = good && (engine_record_sweep(&itself) == (long)held->bodies);
    unsigned long long short_of_ceiling = 0ull;
    for (size_t lane = 0u; good && (lane < lanes); lane += 1u)
    {
        short_of_ceiling += ((unsigned long long)weight[lane] != PRINT_PAIR_CEILING) ? 1ull : 0ull;
    }
    for (size_t lane = 0u; good && (lane < lanes); lane += 1u)
    {
        index[(2u * lane) + 1u] = (unsigned int)(lanes - 1u - lane);
    }
    unsigned int *const host = good ? (unsigned int *)malloc((lanes + 1u) * sizeof(unsigned int)) : NULL;
    EngineRecordStep program[PRINT_PAIR_STEPS];
    unsigned int outputs[PRINT_PAIR_OUTPUTS];
    EngineRecordRequest imprint;
    good = good && (run_pair_request(fields, program, outputs, &imprint) != 0);
    unsigned long long across_sweep = 0ull;
    const EngineRecordSweep across = {record,       {prints, prints}, {held->bodies, held->bodies}, index,
                                      held->bodies, weight,           &across_sweep,                &error};
    const EngineRecordSweep across_host = {NULL,         {prints, prints}, {held->bodies, held->bodies}, index,
                                           held->bodies, host,             NULL,                         &error};
    good = good && (host != NULL) && (engine_record_sweep(&across) == (long)held->bodies)
        && (engine_record_host(&imprint, &across_host) == (long)held->bodies);
    unsigned long long differ = 0ull;
    unsigned long long lightest = PRINT_PAIR_CEILING;
    for (size_t lane = 0u; good && (lane < lanes); lane += 1u)
    {
        differ += (weight[lane] != host[lane]) ? 1ull : 0ull;
        lightest = ((unsigned long long)weight[lane] < lightest) ? (unsigned long long)weight[lane] : lightest;
    }
    if (good)
    {
        printf("  print pairs: every body against itself weighs the ceiling %llu, %llu short of it, in %llu us; against"
               " the body across from it %llu us, lightest %llu, %llu differ from the host\n",
               PRINT_PAIR_CEILING, short_of_ceiling, sweep, across_sweep, lightest, differ);
    }
    else
    {
        fprintf(stderr, "  run fingerprint: the print pairs were refused\n");
        track_error_report("print pairs", &error);
    }
    free(index);
    free(weight);
    free(host);
    cycle_record_release(record);
    return (good && (short_of_ceiling == 0ull) && (differ == 0ull)) ? 0 : 1;
}

#define RUN_STEER_STEPS 7u

static int run_steer_proof(const FlattenHeld *held, const unsigned int *prints, const RunPrintFields *fields)
{
    unsigned int bits[MAX_TREE_FIELDS + FINGERPRINT_OUTPUTS];
    unsigned int offset[MAX_TREE_FIELDS + FINGERPRINT_OUTPUTS];
    memcpy(bits, held->layout.bits, MAX_TREE_FIELDS * sizeof(unsigned int));
    memcpy(offset, held->layout.offset, MAX_TREE_FIELDS * sizeof(unsigned int));
    memcpy(&bits[MAX_TREE_FIELDS], fields->bits, FINGERPRINT_OUTPUTS * sizeof(unsigned int));
    memcpy(&offset[MAX_TREE_FIELDS], fields->offset, FINGERPRINT_OUTPUTS * sizeof(unsigned int));
    const EngineRecordStep program[RUN_STEER_STEPS] = {
        {ENGINE_RECORD_FIELD, MAX_TREE_FIELD_MASS, 0u, 0u}, {ENGINE_RECORD_CONSTANT, 1u, 0u, 0u},
        {ENGINE_RECORD_LADDER, 0u, 1u, 0u},                 {ENGINE_RECORD_FIELD_SIGNED, MAX_TREE_FIELDS, 0u, 1u},
        {ENGINE_RECORD_COMPARE, 2u, 3u, 0u},                {ENGINE_RECORD_ABSOLUTE, 4u, 0u, 0u},
        {ENGINE_RECORD_DIFFERENCE, 1u, 5u, 0u}};
    const unsigned int output = RUN_STEER_STEPS - 1u;
    const EngineRecordRequest imprint = {program, RUN_STEER_STEPS, bits, offset, MAX_TREE_FIELDS + FINGERPRINT_OUTPUTS,
                                         {held->layout.limbs, fields->limbs}, 2u, &output, 1u};
    CycleRecord *record = NULL;
    const size_t lanes = (size_t)held->bodies;
    EngineError error;
    memset(&error, 0, sizeof(error));
    int good = (engine_record_imprint(&imprint, &record, &error) != ENGINE_REFUSED)
            && (cycle_record_out_limbs(record) == 1u);
    unsigned int *const verdict = good ? (unsigned int *)malloc((lanes + 1u) * sizeof(unsigned int)) : NULL;
    unsigned int *const host = good ? (unsigned int *)malloc((lanes + 1u) * sizeof(unsigned int)) : NULL;
    unsigned long long sweep = 0ull;
    const EngineRecordSweep run = {record,       {held->magnitudes, prints}, {held->bodies, held->bodies}, NULL,
                                   held->bodies, verdict,                    &sweep,                       &error};
    const EngineRecordSweep host_run = {NULL,         {held->magnitudes, prints}, {held->bodies, held->bodies}, NULL,
                                        held->bodies, host,                       NULL,                         &error};
    good = good && (verdict != NULL) && (host != NULL) && (engine_record_sweep(&run) == (long)held->bodies)
        && (engine_record_host(&imprint, &host_run) == (long)held->bodies);
    unsigned long long truthy = 0ull;
    unsigned long long differ = 0ull;
    for (size_t lane = 0u; good && (lane < lanes); lane += 1u)
    {
        truthy += (verdict[lane] != 0u) ? 1ull : 0ull;
        differ += (verdict[lane] != host[lane]) ? 1ull : 0ull;
    }
    if (good)
    {
        printf("  the body beside its own print, no index: the mass band read again agrees with the print's on %llu of"
               " %llu bodies, truthy; the sweep %llu us; %llu differ from the host\n", truthy, held->bodies, sweep,
               differ);
    }
    else
    {
        fprintf(stderr, "  run fingerprint: the body beside its print was refused\n");
        track_error_report("body beside its print", &error);
    }
    free(verdict);
    free(host);
    cycle_record_release(record);
    return (good && (truthy == held->bodies) && (differ == 0ull)) ? 0 : 1;
}

static int run_vocabulary_proof(const FlattenHeld *held, const unsigned int *prints, const RunPrintFields *fields)
{
    const unsigned int print_limbs = fields->limbs;
    CycleRecord *record = NULL;
    const EngineRecordRequest imprint = {RUN_VOCABULARY_PROGRAM, RUN_VOCABULARY_STEPS, held->layout.bits,
                                         held->layout.offset,    MAX_TREE_FIELDS,      {held->layout.limbs},
                                         1u,                     RUN_VOCABULARY_OUTPUT, RUN_VOCABULARY_OUTPUTS};
    EngineError error;
    memset(&error, 0, sizeof(error));
    if (engine_record_imprint(&imprint, &record, &error) == ENGINE_REFUSED)
    {
        fprintf(stderr, "  run fingerprint: absolute and compare did not imprint\n");
        track_error_report("absolute and compare", &error);
        return 1;
    }
    const unsigned int out_limbs = cycle_record_out_limbs(record);
    const size_t words = (size_t)held->bodies * out_limbs;
    unsigned int *const device = (unsigned int *)malloc((words + 1u) * sizeof(unsigned int));
    unsigned int *const host = (unsigned int *)malloc((words + 1u) * sizeof(unsigned int));
    unsigned long long sweep = 0ull;
    const EngineRecordSweep run = {record, {held->magnitudes}, {held->bodies}, NULL, held->bodies, device, &sweep,
                                   &error};
    const EngineRecordSweep host_run = {NULL, {held->magnitudes}, {held->bodies}, NULL, held->bodies, host, NULL,
                                        &error};
    const int good = (device != NULL) && (host != NULL) && (engine_record_sweep(&run) == (long)held->bodies)
                  && (engine_record_host(&imprint, &host_run) == (long)held->bodies);
    const unsigned int band_offset = fields->offset[1u + MAX_TREE_FIELD_MOMENT_ZY];
    const unsigned int band_bits = fields->bits[1u + MAX_TREE_FIELD_MOMENT_ZY];
    unsigned long long order[3] = {0ull, 0ull, 0ull};
    unsigned long long broken = 0ull;
    unsigned long long against_print = 0ull;
    unsigned long long differ = 0ull;
    for (unsigned long long body = 0ull; good && (body < held->bodies); body += 1ull)
    {
        const unsigned int *const lane = &device[body * out_limbs];
        const int sign = engine_packed_signed(lane, 0u, 2u);
        const int above = engine_packed_signed(lane, 2u, 2u);
        const int below = engine_packed_signed(lane, 4u, 2u);
        const int band = engine_packed_signed(&prints[body * print_limbs], band_offset, band_bits);
        order[sign + 1] += 1ull;
        broken += ((above != ((sign < 0) ? 1 : 0)) || (below != -above)) ? 1ull : 0ull;
        against_print += ((band != 0) && (((band < 0) ? -1 : 1) != sign)) ? 1ull : 0ull;
        differ += (memcmp(lane, &host[body * out_limbs], out_limbs * sizeof(unsigned int)) != 0) ? 1ull : 0ull;
    }
    if (good)
    {
        printf("  absolute and compare on K_zy of %llu bodies: %llu below zero, %llu at zero, %llu above; the sweep %llu"
               " us; %llu break |K| against K, %llu disagree with the print's band, %llu differ from the host\n",
               held->bodies, order[0], order[1], order[2], sweep, broken, against_print, differ);
    }
    else
    {
        fprintf(stderr, "  run fingerprint: absolute and compare were refused\n");
        track_error_report("absolute and compare", &error);
    }
    free(device);
    free(host);
    cycle_record_release(record);
    return (good && (broken == 0ull) && (against_print == 0ull) && (differ == 0ull)) ? 0 : 1;
}

static int run_fingerprint(const RunInputs *inputs)
{
    FlattenHeld held;
    EngineError error;
    memset(&error, 0, sizeof(error));
    if (flatten_read(inputs->set, &held, &error) == 0)
    {
        track_error_report("run fingerprint: flattened.iapx", &error);
        return 1;
    }
    FingerprintRequest print;
    run_print_request(inputs, &print);
    EngineRecordStep program[FINGERPRINT_STEPS];
    unsigned int outputs[FINGERPRINT_OUTPUTS];
    CycleRecord *record = NULL;
    RunPrintFields fields;
    memset(&fields, 0, sizeof(fields));
    const EngineRecordRequest imprint = {program,            FINGERPRINT_STEPS, held.layout.bits,
                                         held.layout.offset, MAX_TREE_FIELDS,   {held.layout.limbs},
                                         1u,                 outputs,           FINGERPRINT_OUTPUTS,
                                         fields.offset,      fields.bits};
    const long out_bits = (fingerprint_program(&print, program, outputs) == FINGERPRINT_REFUSED)
                        ? ENGINE_REFUSED : engine_record_imprint(&imprint, &record, &error);
    if (out_bits == ENGINE_REFUSED)
    {
        fprintf(stderr, "  run fingerprint: the program did not imprint; voxel_pm must name all three axes\n");
        track_error_report("fingerprint", &error);
        flatten_release(&held);
        return 1;
    }
    const unsigned int out_limbs = cycle_record_out_limbs(record);
    fields.limbs = out_limbs;
    printf("  the print's record as a vector magnitude, field at offset:bits:");
    for (unsigned int output = 0u; output < FINGERPRINT_OUTPUTS; output += 1u)
    {
        printf(" %u:%u", fields.offset[output], fields.bits[output]);
    }
    printf("\n");
    unsigned int *const records = (unsigned int *)malloc(((size_t)held.bodies * out_limbs + 1u) * sizeof(unsigned int));
    unsigned long long sweep = 0ull;
    const unsigned long long started = engine_clock_microseconds();
    const EngineRecordSweep run = {record, {held.magnitudes}, {held.bodies}, NULL, held.bodies, records, &sweep, &error};
    const int good = (records != NULL) && (engine_record_sweep(&run) == (long)held.bodies);
    const unsigned long long whole = engine_clock_microseconds() - started;
    unsigned long long crc = ~0ull;
    for (size_t limb = 0u; good && (limb < (size_t)held.bodies * out_limbs); limb += 1u)
    {
        for (unsigned int place = 0u; place < 4u; place += 1u)
        {
            crc = crc_step(CRC_TABLE, crc, (records[limb] >> (8u * place)) & 0xFFu);
        }
    }
    if (good)
    {
        printf("  fingerprint: %llu bodies, %u steps, %ld bits a print in %u limbs; the sweep %llu us, with the "
               "transfers %llu us; CRC-64 of the prints %016llx\n",
               held.bodies, FINGERPRINT_STEPS, out_bits, out_limbs, sweep, whole, ~crc);
    }
    else
    {
        fprintf(stderr, "  run fingerprint: the sweep was refused\n");
        track_error_report("fingerprint sweep", &error);
    }
    const int indexed = good && (held.bodies <= 0xFFFFFFFFull);
    unsigned int *const reversed = indexed ? (unsigned int *)malloc(((size_t)held.bodies + 1u) * sizeof(unsigned int))
                                           : NULL;
    unsigned int *const gathered = indexed ? (unsigned int *)malloc(((size_t)held.bodies * out_limbs + 1u)
                                                                    * sizeof(unsigned int)) : NULL;
    for (unsigned long long lane = 0ull; (reversed != NULL) && (lane < held.bodies); lane += 1ull)
    {
        reversed[lane] = (unsigned int)(held.bodies - 1ull - lane);
    }
    unsigned long long gather_sweep = 0ull;
    const EngineRecordSweep through = {record,      {held.magnitudes}, {held.bodies}, reversed,
                                       held.bodies, gathered,          &gather_sweep, &error};
    const int gather = (reversed != NULL) && (gathered != NULL) && (engine_record_sweep(&through) == (long)held.bodies);
    unsigned long long misplaced = 0ull;
    for (unsigned long long lane = 0ull; gather && (lane < held.bodies); lane += 1ull)
    {
        misplaced += (memcmp(&gathered[lane * out_limbs], &records[(held.bodies - 1ull - lane) * out_limbs],
                             out_limbs * sizeof(unsigned int)) != 0) ? 1ull : 0ull;
    }
    if (gather)
    {
        printf("  fingerprint through the index, every body read by the lane across from it: the sweep %llu us; %llu of"
               " %llu prints land away from their body\n", gather_sweep, misplaced, held.bodies);
    }
    else if (good)
    {
        fprintf(stderr, "  run fingerprint: the sweep through the index was refused\n");
        track_error_report("fingerprint through the index", &error);
    }
    free(reversed);
    free(gathered);
    unsigned int *const host = good ? (unsigned int *)malloc(((size_t)held.bodies * out_limbs + 1u)
                                                             * sizeof(unsigned int)) : NULL;
    const unsigned long long host_started = engine_clock_microseconds();
    const EngineRecordSweep host_run = {NULL, {held.magnitudes}, {held.bodies}, NULL, held.bodies, host, NULL, &error};
    const int ported = (host != NULL) && (engine_record_host(&imprint, &host_run) == (long)held.bodies);
    const unsigned long long host_whole = engine_clock_microseconds() - host_started;
    unsigned long long differ = 0ull;
    for (unsigned long long body = 0ull; ported && (body < held.bodies); body += 1ull)
    {
        differ += (memcmp(&host[body * out_limbs], &records[body * out_limbs], out_limbs * sizeof(unsigned int)) != 0)
                ? 1ull : 0ull;
    }
    if (ported)
    {
        printf("  fingerprint on the host, anchor_sift's exact integer: %llu us; %llu of %llu prints differ from the "
               "device\n", host_whole, differ, held.bodies);
    }
    else if (good)
    {
        fprintf(stderr, "  run fingerprint: the host port was refused\n");
        track_error_report("fingerprint host port", &error);
    }
    const int vocabulary = good ? run_vocabulary_proof(&held, records, &fields) : 1;
    const int paired = good ? run_pair_proof(&held, records, &fields) : 1;
    const int steered = good ? run_steer_proof(&held, records, &fields) : 1;
    free(host);
    free(records);
    cycle_record_release(record);
    flatten_release(&held);
    return (good && gather && (misplaced == 0ull) && ported && (differ == 0ull) && (vocabulary == 0) && (paired == 0)
            && (steered == 0)) ? 0 : 1;
}

static int run_flattened_prepare(const RunInputs *inputs, FlattenHeld *held, unsigned long long **starts,
                                 TreeRules *rules)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    if (flatten_read(inputs->set, held, &error) == 0)
    {
        track_error_report("flattened.iapx", &error);
        return 0;
    }
    const unsigned int sample_bits = held->layout.bits[MAX_TREE_FIELD_SAMPLE];
    const unsigned int sample_offset = held->layout.offset[MAX_TREE_FIELD_SAMPLE];
    *starts = (unsigned long long *)calloc((size_t)held->samples + 2u, sizeof(unsigned long long));
    int good = (*starts != NULL) && (sample_bits <= 32u);
    unsigned int previous = 0u;
    for (unsigned long long body = 0ull; good && (body < held->bodies); body += 1ull)
    {
        const unsigned int sample = engine_packed_unsigned(&held->magnitudes[body * held->layout.limbs], sample_offset,
                                                        sample_bits);
        good = (sample < held->samples) && (sample >= previous);
        previous = sample;
        (*starts)[good ? (sample + 1u) : 0u] += good ? 1ull : 0ull;
    }
    for (unsigned int sample = 0u; good && (sample < held->samples); sample += 1u)
    {
        (*starts)[sample + 1u] += (*starts)[sample];
    }
    if (good == 0)
    {
        fprintf(stderr, "  flattened.iapx in %s does not hold its samples in order\n", inputs->set);
        return 0;
    }
    rules->flattened = held->magnitudes;
    rules->flattened_limbs = held->layout.limbs;
    rules->flattened_samples = held->samples;
    rules->flattened_names = held->names;
    rules->flattened_start = *starts;
    return 1;
}

typedef struct
{
    EngineRecordStep program[VELOCITY_STEPS];
    unsigned int outputs[VELOCITY_OUTPUTS];
    unsigned int bits[MAX_TREE_FIELDS + ENGINE_AXES];
    unsigned int offset[MAX_TREE_FIELDS + ENGINE_AXES];
    unsigned int output_offset[VELOCITY_OUTPUTS];
    unsigned int output_bits[VELOCITY_OUTPUTS];
    EngineRecordRequest imprint;
} RunVelocity;

static int run_velocity_prepare(const FlattenHeld *held, RunVelocity *velocity, CycleRecord **record, TreeRules *rules)
{
    VelocityRequest request;
    memset(&request, 0, sizeof(request));
    request.mass_field = MAX_TREE_FIELD_MASS;
    memcpy(velocity->bits, held->layout.bits, MAX_TREE_FIELDS * sizeof(unsigned int));
    memcpy(velocity->offset, held->layout.offset, MAX_TREE_FIELDS * sizeof(unsigned int));
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        request.sum_field[axis] = MAX_TREE_FIELD_SUM_Z + axis;
        request.lag_field[axis] = MAX_TREE_FIELDS + axis;
        velocity->bits[MAX_TREE_FIELDS + axis] = 32u;
        velocity->offset[MAX_TREE_FIELDS + axis] = 32u * axis;
    }
    EngineRecordRequest *const imprint = &velocity->imprint;
    memset(imprint, 0, sizeof(*imprint));
    imprint->steps = velocity->program;
    imprint->count = VELOCITY_STEPS;
    imprint->field_bits = velocity->bits;
    imprint->field_offset = velocity->offset;
    imprint->fields = MAX_TREE_FIELDS + ENGINE_AXES;
    imprint->in_limbs[VELOCITY_EARLIER] = held->layout.limbs;
    imprint->in_limbs[VELOCITY_LATER] = held->layout.limbs;
    imprint->in_limbs[VELOCITY_LAG] = ENGINE_AXES;
    imprint->members = VELOCITY_MEMBERS;
    imprint->outputs = velocity->outputs;
    imprint->output_count = VELOCITY_OUTPUTS;
    imprint->output_offset = velocity->output_offset;
    imprint->output_bits = velocity->output_bits;
    *record = NULL;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const long out_bits = (velocity_program(&request, velocity->program, velocity->outputs) == VELOCITY_REFUSED)
                        ? ENGINE_REFUSED : engine_record_imprint(imprint, record, &error);
    if (out_bits == ENGINE_REFUSED)
    {
        fprintf(stderr, "  velocity: the program did not imprint\n");
        track_error_report("velocity", &error);
        return 0;
    }
    rules->velocity_record = *record;
    rules->velocity_imprint = imprint;
    printf("  velocity: %u steps, a record of %ld bits in %u limbs\n", VELOCITY_STEPS, out_bits,
           cycle_record_out_limbs(*record));
    return 1;
}

typedef struct
{
    EngineRecordStep program[DIVISION_STEPS];
    unsigned int outputs[DIVISION_OUTPUTS];
    unsigned int output_offset[DIVISION_OUTPUTS];
    unsigned int output_bits[DIVISION_OUTPUTS];
    EngineRecordRequest imprint;
} RunDivision;

static int run_division_prepare(const RunInputs *inputs, const FlattenHeld *held, RunDivision *division,
                                CycleRecord **record, TreeRules *rules)
{
    DivisionRequest request;
    memset(&request, 0, sizeof(request));
    request.mass_field = MAX_TREE_FIELD_MASS;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        request.sum_field[axis] = MAX_TREE_FIELD_SUM_Z + axis;
        request.voxel_pm[axis] = inputs->voxel_pm[axis];
    }
    for (unsigned int moment = 0u; moment < DIVISION_MOMENTS; moment += 1u)
    {
        request.moment_field[moment] = MAX_TREE_FIELD_MOMENT_ZZ + moment;
    }
    EngineRecordRequest *const imprint = &division->imprint;
    memset(imprint, 0, sizeof(*imprint));
    imprint->steps = division->program;
    imprint->count = DIVISION_STEPS;
    imprint->field_bits = held->layout.bits;
    imprint->field_offset = held->layout.offset;
    imprint->fields = MAX_TREE_FIELDS;
    for (unsigned int member = 0u; member < DIVISION_MEMBERS; member += 1u)
    {
        imprint->in_limbs[member] = held->layout.limbs;
    }
    imprint->members = DIVISION_MEMBERS;
    imprint->outputs = division->outputs;
    imprint->output_count = DIVISION_OUTPUTS;
    imprint->output_offset = division->output_offset;
    imprint->output_bits = division->output_bits;
    *record = NULL;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const long out_bits = (division_program(&request, division->program, division->outputs) == DIVISION_REFUSED)
                        ? ENGINE_REFUSED : engine_record_imprint(imprint, record, &error);
    if (out_bits == ENGINE_REFUSED)
    {
        fprintf(stderr, "  division: the program did not imprint; voxel_pm must name all three axes\n");
        track_error_report("division", &error);
        return 0;
    }
    rules->division_record = *record;
    rules->division_imprint = imprint;
    printf("  division: %u steps, a record of %ld bits in %u limbs\n", DIVISION_STEPS, out_bits,
           cycle_record_out_limbs(*record));
    return 1;
}

typedef struct
{
    EngineRecordStep difference_program[CONTACT_SIDE_DIFFERENCE_STEPS];
    unsigned int difference_outputs[CONTACT_SIDE_DIFFERENCE_OUTPUTS];
    unsigned int difference_offset[CONTACT_SIDE_DIFFERENCE_OUTPUTS];
    unsigned int difference_bits[CONTACT_SIDE_DIFFERENCE_OUTPUTS];
    EngineRecordRequest difference_imprint;
    EngineRecordStep kept_program[CONTACT_SIDE_KEPT_STEPS];
    unsigned int kept_outputs[CONTACT_SIDE_KEPT_OUTPUTS];
    unsigned int kept_offset[CONTACT_SIDE_KEPT_OUTPUTS];
    unsigned int kept_bits[CONTACT_SIDE_KEPT_OUTPUTS];
    EngineRecordRequest kept_imprint;
} RunContactSide;

static int run_contact_side_prepare(const RunInputs *inputs, const FlattenHeld *held, RunContactSide *side,
                                    CycleRecord **difference_record, CycleRecord **kept_record, TreeRules *rules)
{
    ContactSideDifferenceRequest difference;
    memset(&difference, 0, sizeof(difference));
    difference.mass_field = MAX_TREE_FIELD_MASS;
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        difference.sum_field[axis] = MAX_TREE_FIELD_SUM_Z + axis;
        difference.voxel_pm[axis] = inputs->voxel_pm[axis];
    }
    EngineRecordRequest *const apart = &side->difference_imprint;
    memset(apart, 0, sizeof(*apart));
    apart->steps = side->difference_program;
    apart->count = CONTACT_SIDE_DIFFERENCE_STEPS;
    apart->field_bits = held->layout.bits;
    apart->field_offset = held->layout.offset;
    apart->fields = MAX_TREE_FIELDS;
    apart->in_limbs[CONTACT_SIDE_ONE] = held->layout.limbs;
    apart->in_limbs[CONTACT_SIDE_OTHER] = held->layout.limbs;
    apart->members = CONTACT_SIDE_MEMBERS;
    apart->outputs = side->difference_outputs;
    apart->output_count = CONTACT_SIDE_DIFFERENCE_OUTPUTS;
    apart->output_offset = side->difference_offset;
    apart->output_bits = side->difference_bits;
    *difference_record = NULL;
    *kept_record = NULL;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const long apart_bits = (contact_side_difference_program(&difference, side->difference_program,
                                                             side->difference_outputs) == CONTACT_SIDE_REFUSED)
                          ? ENGINE_REFUSED : engine_record_imprint(apart, difference_record, &error);
    if (apart_bits == ENGINE_REFUSED)
    {
        fprintf(stderr, "  contact side: the difference program did not imprint; voxel_pm must name all three axes\n");
        track_error_report("contact side difference", &error);
        return 0;
    }
    ContactSideKeptRequest kept;
    memset(&kept, 0, sizeof(kept));
    for (unsigned int axis = 0u; axis < ENGINE_AXES; axis += 1u)
    {
        kept.difference_field[axis] = axis;
    }
    const unsigned int apart_limbs = cycle_record_out_limbs(*difference_record);
    EngineRecordRequest *const verdict = &side->kept_imprint;
    memset(verdict, 0, sizeof(*verdict));
    verdict->steps = side->kept_program;
    verdict->count = CONTACT_SIDE_KEPT_STEPS;
    verdict->field_bits = side->difference_bits;
    verdict->field_offset = side->difference_offset;
    verdict->fields = CONTACT_SIDE_DIFFERENCE_OUTPUTS;
    verdict->in_limbs[CONTACT_SIDE_BEFORE] = apart_limbs;
    verdict->in_limbs[CONTACT_SIDE_AFTER] = apart_limbs;
    verdict->members = CONTACT_SIDE_MEMBERS;
    verdict->outputs = side->kept_outputs;
    verdict->output_count = CONTACT_SIDE_KEPT_OUTPUTS;
    verdict->output_offset = side->kept_offset;
    verdict->output_bits = side->kept_bits;
    const long kept_bits = (contact_side_kept_program(&kept, side->kept_program, side->kept_outputs)
                            == CONTACT_SIDE_REFUSED)
                         ? ENGINE_REFUSED : engine_record_imprint(verdict, kept_record, &error);
    if (kept_bits == ENGINE_REFUSED)
    {
        fprintf(stderr, "  contact side: the verdict program did not imprint\n");
        track_error_report("contact side verdict", &error);
        return 0;
    }
    rules->contact_difference_record = *difference_record;
    rules->contact_difference_imprint = apart;
    rules->contact_kept_record = *kept_record;
    rules->contact_kept_imprint = verdict;
    printf("  contact side: the difference, %u steps, a record of %ld bits in %u limbs; the verdict, %u steps, %ld bits"
           " in %u limbs\n", CONTACT_SIDE_DIFFERENCE_STEPS, apart_bits, apart_limbs, CONTACT_SIDE_KEPT_STEPS, kept_bits,
           cycle_record_out_limbs(*kept_record));
    return 1;
}

static int run_print_match_prepare(const RunInputs *inputs, const FlattenHeld *held, unsigned int **prints,
                                   CycleRecord **pair, TreeRules *rules)
{
    FingerprintRequest print;
    run_print_request(inputs, &print);
    EngineRecordStep program[FINGERPRINT_STEPS];
    unsigned int outputs[FINGERPRINT_OUTPUTS];
    CycleRecord *record = NULL;
    RunPrintFields fields;
    memset(&fields, 0, sizeof(fields));
    const EngineRecordRequest imprint = {program,             FINGERPRINT_STEPS, held->layout.bits,
                                         held->layout.offset, MAX_TREE_FIELDS,   {held->layout.limbs},
                                         1u,                  outputs,           FINGERPRINT_OUTPUTS,
                                         fields.offset,       fields.bits};
    EngineError error;
    memset(&error, 0, sizeof(error));
    int good = (fingerprint_program(&print, program, outputs) != FINGERPRINT_REFUSED)
            && (engine_record_imprint(&imprint, &record, &error) != ENGINE_REFUSED);
    const unsigned int limbs = good ? cycle_record_out_limbs(record) : 0u;
    fields.limbs = limbs;
    *prints = good ? (unsigned int *)malloc(((size_t)held->bodies * limbs + 1u) * sizeof(unsigned int)) : NULL;
    unsigned long long sweep = 0ull;
    const EngineRecordSweep run = {record, {held->magnitudes}, {held->bodies}, NULL, held->bodies, *prints, &sweep,
                                   &error};
    good = good && (*prints != NULL) && (engine_record_sweep(&run) == (long)held->bodies);
    cycle_record_release(record);
    good = good && (run_pair_imprint(&fields, pair, &error) != ENGINE_REFUSED);
    if (good == 0)
    {
        fprintf(stderr, "  print match: the prints or the pair program were refused\n");
        track_error_report("print match", &error);
        return 0;
    }
    rules->print_pair = *pair;
    rules->prints = *prints;
    rules->print_limbs = limbs;
    printf("  print match: %llu bodies of %u samples printed in one sweep of %llu us\n", held->bodies, held->samples,
           sweep);
    return 1;
}

static int run_track(const TreeRules *rules, const RunInputs *inputs)
{
    TreeRules matched = *rules;
    FlattenHeld held;
    memset(&held, 0, sizeof(held));
    unsigned int *prints = NULL;
    unsigned long long *starts = NULL;
    CycleRecord *pair = NULL;
    CycleRecord *velocity_record = NULL;
    CycleRecord *division_record = NULL;
    RunVelocity *const velocity = (RunVelocity *)calloc(1u, sizeof(RunVelocity));
    RunDivision *const division = (RunDivision *)calloc(1u, sizeof(RunDivision));
    CycleRecord *difference_record = NULL;
    CycleRecord *kept_record = NULL;
    RunContactSide *const side = (RunContactSide *)calloc(1u, sizeof(RunContactSide));
    int ready = (velocity != NULL) && (division != NULL) && (side != NULL)
             && (((rules->print_match == 0) && (rules->velocity == 0) && (rules->division == 0)
                  && (rules->contact_side == 0))
                 || (run_flattened_prepare(inputs, &held, &starts, &matched) != 0));
    ready = ready && ((rules->print_match == 0) || (run_print_match_prepare(inputs, &held, &prints, &pair, &matched) != 0));
    ready = ready && ((rules->velocity == 0) || (run_velocity_prepare(&held, velocity, &velocity_record, &matched) != 0));
    ready = ready && ((rules->division == 0)
                      || (run_division_prepare(inputs, &held, division, &division_record, &matched) != 0));
    ready = ready && ((rules->contact_side == 0)
                      || (run_contact_side_prepare(inputs, &held, side, &difference_record, &kept_record, &matched)
                          != 0));
    if (ready == 0)
    {
        free(prints);
        free(starts);
        cycle_record_release(pair);
        cycle_record_release(velocity_record);
        cycle_record_release(division_record);
        cycle_record_release(difference_record);
        cycle_record_release(kept_record);
        free(velocity);
        free(division);
        free(side);
        flatten_release(&held);
        return 1;
    }
    rules_line(rules, g_rules_line, sizeof(g_rules_line));
    printf("  rules:%s\n", g_rules_line);
    printf("  %-24s %-6s %s\n", "sample", "edges", "correct/branched/wrong/no link/missed");
    EdgeTally pooled;
    memset(&pooled, 0, sizeof(pooled));
    const unsigned long long started = engine_clock_microseconds() / 1000ull;
    int failures = 0;
    for (unsigned int sample = 0u; sample < inputs->count; sample += 1u)
    {
        EdgeTally tally;
        if (score_sample(inputs->set, inputs->source, inputs->samples[sample], &matched, &tally) == 0)
        {
            fprintf(stderr, "  %s failed\n", inputs->samples[sample]);
            failures += 1;
            continue;
        }
        pooled.correct += tally.correct;
        pooled.branched += tally.branched;
        pooled.wrong += tally.wrong;
        pooled.unlinked += tally.unlinked;
        pooled.missed += tally.missed;
    }
    const unsigned long long total = pooled.correct + pooled.branched + pooled.wrong + pooled.unlinked + pooled.missed;
    printf("\n  POOLED over %llu ground truth edges:\n", total);
    if (total > 0ULL)
    {
        const char *const names[5] = {"correct link", "target among branches", "wrong link", "no link made",
                                      "endpoint undetected"};
        const unsigned long long values[5] = {pooled.correct, pooled.branched, pooled.wrong, pooled.unlinked,
                                              pooled.missed};
        for (unsigned int row = 0u; row < 5u; row += 1u)
        {
            unsigned long long whole = 0ULL;
            unsigned long long tenth = 0ULL;
            engine_percent_of(values[row], total, &whole, &tenth);
            printf("    %-22s %5llu   %llu.%llu%%\n", names[row], values[row], whole, tenth);
        }
    }
    if ((g_web_asked + g_web_capped) > 0ULL)
    {
        printf("    web: asked of %llu objects, moved %llu, capped %llu over %u bodies\n",
               g_web_asked, g_web_moved, g_web_capped, WEB_MEMBERS);
    }
    if ((g_mutual_alone + g_mutual_split + g_mutual_empty) > 0ULL)
    {
        printf("    mutual: %llu cells, one survivor %llu, several %llu, none %llu, moved %llu\n",
               g_mutual_alone + g_mutual_split + g_mutual_empty,
               g_mutual_alone, g_mutual_split, g_mutual_empty, g_mutual_moved);
    }
    survey_report();
    EngineBodiesTally tally;
    engine_bodies_tally(&tally);
    if (tally.frames != 0ull)
    {
        printf("    bodies: proved on %llu of %llu frames, %llu bodies, %llu per frame, mean level index %llu\n",
               tally.held, tally.frames, tally.bodies, tally.bodies / tally.frames, tally.levels / tally.frames);
    }
    EngineResidualTally residual;
    engine_residual_tally(&residual);
    if (residual.frames != 0ull)
    {
        printf("    residual: %llu frames, the key %llu us, the unit sweeps %llu us; proved on %llu frames, %llu differ"
               " (%llu lanes)\n", residual.frames, residual.key_microseconds, residual.sweep_microseconds,
               residual.proved_frames, residual.differing_frames, residual.differing_lanes);
    }
    const unsigned long long wall = (engine_clock_microseconds() / 1000ull) - started;
    printf("\n  %llu ms\n", wall);
    FILE *const log = log_open();
    if (log != NULL)
    {
        char when[32];
        log_when(when, sizeof(when));
        fprintf(log, "%s\trun\t%s\t%u samples, %d failed\t0\t0\t0\t0\t0\t%llu\t%llu\t%llu\t%llu\t%llu\t%llu"
                     "\t0\t0\t0\t0\t0\t0\t0\t0\t%llu\t0\t%llu\t%llu\t%llu\t%u\t%llu\t%llu\t%llu\n",
                when, log_rules(), inputs->count, failures, total, pooled.correct, pooled.branched, pooled.wrong,
                pooled.unlinked, pooled.missed, wall, g_web_asked, g_web_moved, g_web_capped, WEB_MEMBERS,
                g_damp_leaves, g_damp_landings, (unsigned long long)DAMP_DEVIATIONS);
        fclose(log);
    }
    free(prints);
    free(starts);
    cycle_record_release(pair);
    cycle_record_release(velocity_record);
    cycle_record_release(division_record);
    cycle_record_release(difference_record);
    cycle_record_release(kept_record);
    free(velocity);
    free(division);
    free(side);
    flatten_release(&held);
    return failures;
}

int main(int argc, char **argv)
{
    TreeRules rules;
    memset(&rules, 0, sizeof(rules));
    rules.resolve = 1;
    RunInputs inputs;
    memset(&inputs, 0, sizeof(inputs));
    const char *cfg_out = NULL;
    int argument = 1;
    while ((argument < argc) && (strncmp(argv[argument], "--", 2u) == 0))
    {
        const char *const flag = argv[argument];
        if (strcmp(flag, "--pick") == 0)
        {
            rules.pick = 1;
        }
        else if (strcmp(flag, "--share") == 0)
        {
            rules.share = 1;
        }
        else if (strcmp(flag, "--agree") == 0)
        {
            rules.agree = 1;
        }
        else if (strcmp(flag, "--unbound") == 0)
        {
            rules.unbound = 1;
        }
        else if (strcmp(flag, "--cast") == 0)
        {
            rules.cast = 1;
        }
        else if (strcmp(flag, "--parallax") == 0)
        {
            rules.parallax = 1;
        }
        else if (strcmp(flag, "--arc") == 0)
        {
            rules.arc = 1;
        }
        else if (strcmp(flag, "--settle") == 0)
        {
            rules.settle = 1;
        }
        else if (strcmp(flag, "--web") == 0)
        {
            rules.web = 1;
        }
        else if (strcmp(flag, "--damp") == 0)
        {
            rules.damp = 1;
        }
        else if (strcmp(flag, "--dish") == 0)
        {
            rules.dish = 1;
        }
        else if (strcmp(flag, "--vote") == 0)
        {
            rules.vote = 1;
        }
        else if (strcmp(flag, "--mutual") == 0)
        {
            rules.mutual = 1;
        }
        else if (strcmp(flag, "--tower") == 0)
        {
            rules.tower = 1;
        }
        else if ((strcmp(flag, "--plan") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            g_schedule_path = argv[argument];
        }
        else if ((strcmp(flag, "--run") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            RunPart part = RUN_TRACK;
            if ((run_part_named(argv[argument], &part) == 0) || (s_part_count >= RUN_PART_ROOM))
            {
                fprintf(stderr, "  --run %s: the parts are schedule, iapx-prove, entropy, floor, flatten, track and"
                                " fingerprint,"
                                " at most %u of them\n", argv[argument], RUN_PART_ROOM);
                return 2;
            }
            s_parts[s_part_count] = part;
            s_part_count += 1u;
        }
        else if (strcmp(flag, "--survey") == 0)
        {
            g_survey = 1u;
        }
        else if (strcmp(flag, "--ingest") == 0)
        {
            s_ingest = 1u;
        }
        else if (strcmp(flag, "--override") == 0)
        {
            s_override = 1u;
        }
        else if (((strcmp(flag, "--source") == 0) || (strcmp(flag, "--set") == 0) || (strcmp(flag, "--axes") == 0))
                 && (argument + 1 < argc))
        {
            char **const held = (flag[2] == 's') ? ((flag[3] == 'o') ? &inputs.source : &inputs.set) : &inputs.axes;
            argument += 1;
            free(*held);
            *held = cfg_copy(argv[argument]);
        }
        else if (strcmp(flag, "--mass") == 0)
        {
            rules.mass = 1;
        }
        else if (strcmp(flag, "--forest") == 0)
        {
            rules.forest = 1;
        }
        else if (strcmp(flag, "--cohere") == 0)
        {
            rules.cohere = 1;
        }
        else if (strcmp(flag, "--accrue") == 0)
        {
            rules.accrue = 1;
        }
        else if ((strcmp(flag, "--spiral") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            rules.spiral = (unsigned int)strtoul(argv[argument], NULL, 10);
        }
        else if ((strcmp(flag, "--nodes") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            if (!open_output(&rules, &inputs, 6u, argv[argument]))
            {
                return 2;
            }
        }
        else if ((strcmp(flag, "--log") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            g_log_path = argv[argument];
        }
        else if (strcmp(flag, "--focus") == 0)
        {
            rules.focus = 1;
            rules.arms = (rules.arms == 0u) ? 1u : rules.arms;
            rules.climb = (rules.climb == 0) ? 1 : rules.climb;
        }
        else if (strcmp(flag, "--merge-split") == 0)
        {
            rules.merge_split = 1;
        }
        else if (strcmp(flag, "--merge-target") == 0)
        {
            rules.merge_target = 1;
        }
        else if (strcmp(flag, "--forward-only") == 0)
        {
            rules.forward_only = 1;
        }
        else if (strcmp(flag, "--keep-view") == 0)
        {
            rules.keep_view = 1;
        }
        else if (strcmp(flag, "--no-resolve") == 0)
        {
            rules.resolve = 0;
        }
        else if (strcmp(flag, "--climb") == 0)
        {
            rules.climb = 1;
        }
        else if (strcmp(flag, "--print-match") == 0)
        {
            rules.print_match = 1;
        }
        else if (strcmp(flag, "--velocity") == 0)
        {
            rules.velocity = 1;
            rules.climb = (rules.climb == 0) ? 1 : rules.climb;
        }
        else if (strcmp(flag, "--mass-band") == 0)
        {
            rules.mass_band = 1;
        }
        else if (strcmp(flag, "--division") == 0)
        {
            rules.division = 1;
            rules.climb = (rules.climb == 0) ? 1 : rules.climb;
        }
        else if (strcmp(flag, "--contact-side") == 0)
        {
            rules.contact_side = 1;
            rules.climb = (rules.climb == 0) ? 1 : rules.climb;
        }
        else if (strcmp(flag, "--box") == 0)
        {
            rules.box = 1;
            rules.climb = (rules.climb == 0) ? 1 : rules.climb;
        }
        else if (strcmp(flag, "--core") == 0)
        {
            rules.core = 1;
            rules.climb = (rules.climb == 0) ? 1 : rules.climb;
        }
        else if (strcmp(flag, "--residual-key") == 0)
        {
            rules.unit_sweep = ENGINE_RESIDUAL_BY_KEY;
        }
        else if (strcmp(flag, "--unit-sweep-prove") == 0)
        {
            rules.unit_sweep = ENGINE_RESIDUAL_BOTH_PROVED;
        }
        else if (strcmp(flag, "--box-history") == 0)
        {
            rules.box_history = 1;
            rules.climb = (rules.climb == 0) ? 1 : rules.climb;
        }
        else if (strcmp(flag, "--marginal") == 0)
        {
            rules.marginal = 1;
            rules.climb = (rules.climb == 0) ? 1 : rules.climb;
        }
        else if ((strcmp(flag, "--cfg") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            if (!apply_cfg(argv[argument], &rules, &inputs))
            {
                return 2;
            }
        }
        else if ((strcmp(flag, "--cfg-out") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            cfg_out = argv[argument];
        }
        else if ((strcmp(flag, "--edges") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            if (!open_output(&rules, &inputs, 0u, argv[argument]))
            {
                return 2;
            }
        }
        else if ((strcmp(flag, "--pool") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            if (!open_output(&rules, &inputs, 5u, argv[argument]))
            {
                return 2;
            }
        }
        else if ((strcmp(flag, "--export") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            open_output(&rules, &inputs, 2u, argv[argument]);
        }
        else if ((strcmp(flag, "--object") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            open_output(&rules, &inputs, 3u, argv[argument]);
        }
        else if ((strcmp(flag, "--vis") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            if (!open_output(&rules, &inputs, 4u, argv[argument]))
            {
                return 2;
            }
        }
        else if (strcmp(flag, "--sticky") == 0)
        {
            rules.sticky = 1;
            rules.climb = (rules.climb == 0) ? 1 : rules.climb;
        }
        else if (strcmp(flag, "--motion-check") == 0)
        {
            rules.motion_check = 1;
        }
        else if ((strcmp(flag, "--null") == 0) && ((argument + 1) < argc))
        {
            argument += 1;
            unsigned int draws = 0u;
            for (const char *digit = argv[argument]; (*digit >= '0') && (*digit <= '9') && (draws < 4096u); digit += 1u)
            {
                draws = (draws * 10u) + (unsigned int)(*digit - '0');
            }
            rules.null_draws = draws;
            rules.climb = (rules.climb == 0) ? 1 : rules.climb;
        }
        else if ((strcmp(flag, "--arms") == 0) && ((argument + 1) < argc))
        {
            argument += 1;
            unsigned int arms = 0u;
            for (const char *digit = argv[argument]; (*digit >= '0') && (*digit <= '9') && (arms < 64u); digit += 1u)
            {
                arms = (arms * 10u) + (unsigned int)(*digit - '0');
            }
            rules.arms = arms;
            rules.climb = (rules.climb == 0) ? 1 : rules.climb;
        }
        else if (strcmp(flag, "--climb-host") == 0)
        {
            rules.climb = 2;
        }
        else if (strcmp(flag, "--climb-check") == 0)
        {
            rules.climb = 3;
        }
        else if ((strcmp(flag, "--coherence") == 0) && (argument + 1 < argc))
        {
            argument += 1;
            if (!open_output(&rules, &inputs, 1u, argv[argument]))
            {
                return 2;
            }
        }
        else
        {
            fprintf(stderr, "  unknown flag %s\n", flag);
            return 2;
        }
        argument += 1;
    }
    if (argument < argc)
    {
        free(inputs.set);
        inputs.set = cfg_copy(argv[argument]);
        argument += 1;
    }
    if (argument < argc)
    {
        for (unsigned int slot = 0u; slot < inputs.count; slot += 1u)
        {
            free(inputs.samples[slot]);
        }
        free(inputs.samples);
        inputs.count = (unsigned int)(argc - argument);
        inputs.samples = (char **)calloc((size_t)inputs.count + 1u, sizeof(char *));
        for (unsigned int slot = 0u; inputs.samples && (slot < inputs.count); slot += 1u)
        {
            inputs.samples[slot] = cfg_copy(argv[argument + (int)slot]);
        }
    }
    if (!inputs.count && inputs.first)
    {
        first_samples(&inputs, s_ingest != 0u);
    }
    if ((s_ingest != 0u) && (s_part_count != 0u))
    {
        fprintf(stderr, "  --ingest is its own step: it prepares the set and runs nothing, so no --run part goes"
                        " with it\n");
        return 2;
    }
    if (!inputs.set || !inputs.count || ((s_ingest != 0u) && !inputs.source))
    {
        fprintf(stderr, "usage: track_driver --ingest --source directory [--axes tzyx] <set> [<sample> ...]\n"
                        "       track_driver [--cfg run.cfg] [--cfg-out effective.cfg] [--run part ...] [--plan path]"
                        " [--pick] [--merge-split] [--merge-target] [--forward-only] [--keep-view] [--no-resolve] [--climb]"
                        " [--edges path] [--object directory] [<set> [<sample> ...]]\n"
                        "  the source is the dataset as it came; the set holds one <sample>/<sample>.iapx per sample,"
                        " made from the source by --ingest and by nothing else\n"
                        "  --run names one part and repeats, the parts running in the order given: schedule, iapx-prove,"
                        " entropy, floor, flatten, track, fingerprint\n"
                        "  a .cfg names the source, the set and the samples in its input section; positional words"
                        " override it\n"
                        "  every part, and --ingest, is one job on the device's tessera daemon (tessera_daemon beside"
                        " this program); --override admits a job that declares more than its request's kept peak\n");
        return 2;
    }
    if ((s_ingest == 0u) && (s_part_count == 0u))
    {
        s_parts[0] = RUN_TRACK;
        s_part_count = 1u;
    }
    if (run_part_named_already(RUN_FLOOR) != 0)
    {
        inputs.floor_entropy = true;
    }
    if ((s_ingest == 0u) && inputs.floor_entropy && (run_part_named_already(RUN_FLOOR) == 0))
    {
        if (s_part_count >= RUN_PART_ROOM)
        {
            fprintf(stderr, "  the .cfg lays the floor first, and there is no room left for it among %u parts\n",
                    RUN_PART_ROOM);
            return 2;
        }
        memmove(&s_parts[1], &s_parts[0], (size_t)s_part_count * sizeof(s_parts[0]));
        s_parts[0] = RUN_FLOOR;
        s_part_count += 1u;
    }
    CfgText effective;
    if (!write_cfg(&rules, &inputs, &effective))
    {
        fprintf(stderr, "  could not write the effective .cfg\n");
        return 2;
    }
    rules.cfg_text = effective.bytes;
    rules.cfg_length = effective.length;
    rules.floor_entropy = inputs.floor_entropy;
    FILE *const cfg_file = cfg_out ? fopen(cfg_out, "wb") : NULL;
    if (cfg_out && (!cfg_file || (fwrite(effective.bytes, 1u, effective.length, cfg_file) != effective.length)))
    {
        fprintf(stderr, "  could not write %s\n", cfg_out);
        return 2;
    }
    cfg_file ? (void)fclose(cfg_file) : (void)0;
    const char *const directory = inputs.set;
    (void)cudaFree(NULL);

    if (s_ingest != 0u)
    {
        RunJob job;
        if (!run_job_submit("ingest", &effective, &inputs, &job))
        {
            return 2;
        }
        EngineError error;
        memset(&error, 0, sizeof(error));
        EngineSetReport report;
        memset(&report, 0, sizeof(report));
        report.samples = (EngineSampleRecord *)calloc((size_t)inputs.count + 1u, sizeof(EngineSampleRecord));
        const EngineIngestRequest ingest = {inputs.source, inputs.set, inputs.samples, inputs.count, inputs.axes, &error,
                                            &report};
        const long ingested = engine_ingest_set(&ingest);
        run_job_release("ingest", &job);
        engine_ingest_print(&ingest, stdout);
        free(report.samples);
        if (ingested != 0L)
        {
            track_error_report("ingest", &error);
            return 2;
        }
        return 0;
    }
    const EngineSetRequest iapx = {directory, inputs.samples, inputs.count};
    int failures = 0;
    for (unsigned int at = 0u; (failures == 0) && (at < s_part_count); at += 1u)
    {
        const RunPart part = s_parts[at];
        printf("  run %s\n", RUN_PART_NAMES[part]);
        RunJob job;
        if (!run_job_submit(RUN_PART_NAMES[part], &effective, &inputs, &job))
        {
            failures = 1;
        }
        else if (part == RUN_SCHEDULE)
        {
            failures = ((g_schedule_path != NULL) && (schedule_program(directory, inputs.samples, inputs.count) != 0))
                     ? 0 : 1;
            if (g_schedule_path == NULL)
            {
                fprintf(stderr, "  run schedule: --plan names where the plan is written\n");
            }
        }
        else if (part == RUN_IAPX_PROVE)
        {
            EngineError error;
            memset(&error, 0, sizeof(error));
            EngineSetReport report;
            memset(&report, 0, sizeof(report));
            report.samples = (EngineSampleRecord *)calloc((size_t)inputs.count + 1u, sizeof(EngineSampleRecord));
            EngineSetRequest prove = iapx;
            prove.error = &error;
            prove.report = &report;
            failures = (engine_iapx_prove_set(&prove) == 0L) ? 0 : 1;
            engine_prove_print(&prove, stdout);
            free(report.samples);
            if (failures != 0)
            {
                track_error_report("iapx prove", &error);
            }
        }
        else if ((part == RUN_ENTROPY) || (part == RUN_FLOOR))
        {
            EngineError error;
            memset(&error, 0, sizeof(error));
            EngineEntropySetRequest entropy = {iapx, (part == RUN_FLOOR) ? 1u : 0u};
            entropy.set.error = &error;
            failures = (engine_entropy_set(&entropy) == 0L) ? 0 : 1;
            if (failures != 0)
            {
                track_error_report("entropy", &error);
            }
        }
        else if (part == RUN_FLATTEN)
        {
            EngineError error;
            memset(&error, 0, sizeof(error));
            FlattenSetRequest flatten;
            memset(&flatten, 0, sizeof(flatten));
            flatten.set = directory;
            flatten.names = inputs.samples;
            flatten.count = inputs.count;
            memcpy(flatten.smooth_orders, SMOOTH_ORDERS, sizeof(flatten.smooth_orders));
            memcpy(flatten.background_orders, BACKGROUND_ORDERS, sizeof(flatten.background_orders));
            flatten.error = &error;
            failures = (flatten_set(&flatten) != 0) ? 0 : 1;
            if (failures != 0)
            {
                track_error_report("flatten", &error);
            }
        }
        else if (part == RUN_FINGERPRINT)
        {
            failures = run_fingerprint(&inputs);
        }
        else
        {
            failures = run_track(&rules, &inputs);
        }
        if (job.client != NULL)
        {
            run_job_release(RUN_PART_NAMES[part], &job);
        }
        if (failures != 0)
        {
            fprintf(stderr, "  run %s did not hold; the parts after it do not run\n", RUN_PART_NAMES[part]);
        }
    }
    if (rules.coherence != NULL)
    {
        fclose(rules.coherence);
    }
    if (rules.vis_index != NULL)
    {
        fclose(rules.vis_index);
    }
    if (rules.edges != NULL)
    {
        fclose(rules.edges);
    }
    for (unsigned int slot = 0u; slot < inputs.count; slot += 1u)
    {
        free(inputs.samples[slot]);
    }
    for (unsigned int slot = 0u; slot < 5u; slot += 1u)
    {
        free(inputs.outputs[slot]);
    }
    free(inputs.samples);
    free(inputs.source);
    free(inputs.set);
    free(inputs.axes);
    free(inputs.species);
    free(inputs.view);
    free(effective.bytes);
    return (failures == 0) ? 0 : 1;
}
