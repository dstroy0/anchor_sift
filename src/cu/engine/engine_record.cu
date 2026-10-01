// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// engine_record.cu: the error kept for the caller, and the record layout on the device
#include "engine_internal.h"

extern "C" void engine_percent_of(unsigned long long numerator, unsigned long long denominator,
                                  unsigned long long *percent, unsigned long long *tenth)
{
    const unsigned long long scaled = (numerator * 1000ULL * 2ULL + denominator) / (2ULL * denominator);
    *percent = scaled / 10ULL;
    *tenth = scaled % 10ULL;
}

extern "C" int engine_order_keys(const void *left, const void *right)
{
    const unsigned long long first = *(const unsigned long long *)left;
    const unsigned long long second = *(const unsigned long long *)right;
    return (first < second) ? -1 : ((first > second) ? 1 : 0);
}

extern "C" unsigned int engine_sort_unique(unsigned long long *keys, unsigned int count)
{
    if (count == 0u)
    {
        return 0u;
    }
    qsort(keys, count, sizeof(unsigned long long), engine_order_keys);
    unsigned int kept = 1u;
    for (unsigned int position = 1u; position < count; position += 1u)
    {
        if (keys[position] != keys[kept - 1u])
        {
            keys[kept] = keys[position];
            kept += 1u;
        }
    }
    return kept;
}

static EngineError s_engine_error;

void engine_error_keep(const EngineError *error)
{
    if ((error->kind != ENGINE_ERROR_NONE) && (s_engine_error.kind == ENGINE_ERROR_NONE))
    {
        s_engine_error = *error;
    }
}

extern "C" void engine_error_read(EngineError *error)
{
    *error = s_engine_error;
}

extern "C" void engine_error_clear(void)
{
    memset(&s_engine_error, 0, sizeof(s_engine_error));
}

extern "C" long engine_key_encode(const EngineStep *steps, unsigned int count, CycleKey **key, EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_ERROR;
    }
    if (!ENGINE_CHECK(key != NULL, &key, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_ERROR;
    }
    *key = NULL;
    EngineKey math;
    const KeymathEncodeRequest encode_request = {steps, count, &math, error};
    if (!ENGINE_CHECK(keymath_encode(&encode_request) != KEYMATH_ERROR, steps, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_ERROR;
    }
    EngineKeyLayout layout;
    const long layout_status = key_schedule_layout(&math, &layout, error);
    keymath_key_release(&math);
    if (!ENGINE_CHECK(layout_status != KEY_SCHEDULE_ERROR, steps, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_ERROR;
    }
    const long bits = cycle_key_load(&layout, key, error);
    key_schedule_release(&layout);
    return (bits == CYCLE_ERROR) ? ENGINE_ERROR : bits;
}

extern "C" void engine_key_release(CycleKey *key)
{
    cycle_key_release(key);
}

// The program laid out on the device (layout_device_held, codegen_device.h), keymath's encoding and key_schedule's
// layout each in one thread, the path every program takes, and held to the host's layout word for word: 1 and the
// device's layout in `layout` where the two agree, else 0 with the reason on stderr, the host's layout left in `layout`
static int engine_record_layout_device(const EngineRecordRequest *request, EngineRecordLayout *layout)
{
    const LayoutRequest layout_request = {request->steps,        request->count,       request->field_bits,
                                          request->field_offset, request->fields,      request->members,
                                          request->in_limbs,     request->outputs,     request->output_count,
                                          request->tables,       request->table_count, request->reuse};
    const char *const report = getenv("CYCLE_RECORD_REPORT");
    return layout_device_held(&layout_request, layout, (report != NULL) && (report[0] == '1'));
}

extern "C" long engine_record_encode(const EngineRecordRequest *request, CycleRecord **record, EngineError *error)
{
    if (error == NULL)
    {
        return ENGINE_ERROR;
    }
    if (!ENGINE_CHECK((request != NULL) && (record != NULL), request, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_ERROR;
    }
    *record = NULL;
    EngineRecordKey math;
    const KeymathRecordRequest encode_request = {request->steps,
                                                 request->count,
                                                 request->field_bits,
                                                 request->fields,
                                                 request->members,
                                                 request->outputs,
                                                 request->output_count,
                                                 request->tables,
                                                 request->table_count,
                                                 &math,
                                                 error};
    if (!ENGINE_CHECK(keymath_record_encode(&encode_request) != KEYMATH_ERROR, request->steps, error,
                      ENGINE_ERROR_REQUEST))
    {
        return ENGINE_ERROR;
    }
    EngineRecordLayout layout;
    const KeyScheduleRecordRequest layout_request = {
        &math, request->field_offset, request->fields, request->in_limbs, request->reuse, &layout, error};
    const long layout_status = key_schedule_record_layout(&layout_request);
    keymath_record_release(&math);
    if (!ENGINE_CHECK(layout_status != KEY_SCHEDULE_ERROR, request->steps, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_ERROR;
    }
    if (!ENGINE_CHECK(engine_record_layout_device(request, &layout) != 0, request->steps, error, ENGINE_ERROR_LOGIC))
    {
        key_schedule_record_release(&layout);
        return ENGINE_ERROR;
    }
    for (unsigned int output = 0u;
         (request->output_offset != NULL) && (request->output_bits != NULL) && (output < request->output_count);
         output += 1u)
    {
        request->output_offset[output] = layout.step_table[request->outputs[output]].out_offset;
        request->output_bits[output] = layout.step_table[request->outputs[output]].out_bits;
    }
    const long bits = cycle_record_load(&layout, record, error);
    key_schedule_record_release(&layout);
    return (bits == CYCLE_ERROR) ? ENGINE_ERROR : bits;
}

extern "C" long engine_record_host(const EngineRecordRequest *request, const EngineRecordSweep *sweep)
{
    if ((sweep == NULL) || (sweep->error == NULL))
    {
        return ENGINE_ERROR;
    }
    EngineError *const error = sweep->error;
    if (!ENGINE_CHECK(request != NULL, request, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_ERROR;
    }
    EngineRecordKey math;
    const KeymathRecordRequest encode_request = {request->steps,
                                                 request->count,
                                                 request->field_bits,
                                                 request->fields,
                                                 request->members,
                                                 request->outputs,
                                                 request->output_count,
                                                 request->tables,
                                                 request->table_count,
                                                 &math,
                                                 error};
    if (!ENGINE_CHECK(keymath_record_encode(&encode_request) != KEYMATH_ERROR, request->steps, error,
                      ENGINE_ERROR_REQUEST))
    {
        return ENGINE_ERROR;
    }
    EngineRecordLayout layout;
    const KeyScheduleRecordRequest layout_request = {
        &math, request->field_offset, request->fields, request->in_limbs, request->reuse, &layout, error};
    const long layout_status = key_schedule_record_layout(&layout_request);
    keymath_record_release(&math);
    if (!ENGINE_CHECK(layout_status != KEY_SCHEDULE_ERROR, request->steps, error, ENGINE_ERROR_REQUEST))
    {
        return ENGINE_ERROR;
    }
    CycleRecordHostRequest run;
    memset(&run, 0, sizeof(run));
    run.layout = &layout;
    for (unsigned int member = 0u; member < ENGINE_RECORD_MEMBERS_MAX; member += 1u)
    {
        run.in[member] = sweep->magnitudes[member];
        run.bodies[member] = sweep->bodies[member];
    }
    run.index = sweep->index;
    run.count = sweep->count;
    run.out = sweep->records;
    run.error = error;
    const long ran = cycle_record_run_host(&run);
    key_schedule_record_release(&layout);
    return (ran == CYCLE_ERROR) ? ENGINE_ERROR : ran;
}

extern "C" long engine_record_sweep(const EngineRecordSweep *request)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return ENGINE_ERROR;
    }
    EngineError *const error = request->error;
    const unsigned int members = cycle_record_members(request->record);
    const size_t index_words = (request->index != NULL) ? (size_t)request->count * members : 0u;
    const size_t out_words = (size_t)request->count * cycle_record_out_limbs(request->record);
    CycleRecordRunRequest run;
    memset(&run, 0, sizeof(run));
    run.error = error;
    unsigned int *device_in[ENGINE_RECORD_MEMBERS_MAX];
    memset(device_in, 0, sizeof(device_in));
    unsigned int *device_index = NULL;
    unsigned int *device_out = NULL;
    int ok =
        ENGINE_CHECK((members != 0u) && (out_words != 0u) && (request->sweep_microseconds != NULL), request, error,
                     ENGINE_ERROR_REQUEST) &&
        ENGINE_STATUS_CHECK(cudaMalloc((void **)&device_out, out_words * sizeof(unsigned int)), &device_out, error);
    for (unsigned int member = 0u; ok && (member < members); member += 1u)
    {
        const unsigned int in_limbs = cycle_record_in_limbs(request->record, member);
        unsigned int shared = member;
        for (unsigned int earlier = 0u; earlier < member; earlier += 1u)
        {
            const int same = (request->magnitudes[earlier] == request->magnitudes[member]) &&
                             (request->bodies[earlier] == request->bodies[member]) &&
                             (cycle_record_in_limbs(request->record, earlier) == in_limbs);
            shared = ((shared == member) && (same != 0)) ? earlier : shared;
        }
        const size_t in_words = (size_t)request->bodies[member] * in_limbs;
        ok = (shared != member) ||
             (ENGINE_CHECK(in_words != 0u, &request->bodies[member], error, ENGINE_ERROR_REQUEST) &&
              ENGINE_STATUS_CHECK(cudaMalloc((void **)&device_in[member], in_words * sizeof(unsigned int)),
                                  &device_in[member], error) &&
              ENGINE_STATUS_CHECK(cudaMemcpy(device_in[member], request->magnitudes[member],
                                             in_words * sizeof(unsigned int), cudaMemcpyHostToDevice),
                                  device_in[member], error));
        run.device_in[member] = (shared != member) ? run.device_in[shared] : device_in[member];
        run.bodies[member] = request->bodies[member];
    }
    if (ok && (index_words != 0u))
    {
        ok = ENGINE_STATUS_CHECK(cudaMalloc((void **)&device_index, index_words * sizeof(unsigned int)), &device_index,
                                 error) &&
             ENGINE_STATUS_CHECK(
                 cudaMemcpy(device_index, request->index, index_words * sizeof(unsigned int), cudaMemcpyHostToDevice),
                 device_index, error);
    }
    ok = ok && ENGINE_STATUS_CHECK(cudaDeviceSynchronize(), device_out, error);
    const unsigned long long started = engine_clock_microseconds();
    run.record = request->record;
    run.device_index = device_index;
    run.count = request->count;
    run.device_out = device_out;
    ok = ok && (cycle_record_run(&run) == (long)request->count);
    *request->sweep_microseconds = engine_clock_microseconds() - started;
    ok = ok && ENGINE_STATUS_CHECK(
                   cudaMemcpy(request->records, device_out, out_words * sizeof(unsigned int), cudaMemcpyDeviceToHost),
                   request->records, error);
    for (unsigned int member = 0u; member < ENGINE_RECORD_MEMBERS_MAX; member += 1u)
    {
        cudaFree(device_in[member]);
    }
    cudaFree(device_index);
    cudaFree(device_out);
    return (ok != 0) ? (long)request->count : ENGINE_ERROR;
}
