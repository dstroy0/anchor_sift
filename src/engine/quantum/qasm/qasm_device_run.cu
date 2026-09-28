// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_device_run.cu: the sweep, the run and the job
#include "qasm_device_internal.h"

// one gate: its index, its program's sweep, and the outputs narrowed back into the state
static int qasm_sweep(QasmSpace *space, const QasmProgram *programs, const QasmGate *gate, EngineError *error)
{
    const QasmProgram *const program = &programs[gate->kind - 1u];
    const unsigned int members = qasm_gate_members(gate);
    unsigned int records[QASM_PAIR_ROWS * QASM_PAIR_ROW_LIMBS];
    unsigned int *const gate_records =
        (gate->kind == QASM_GATE_PAIR) ? space->pair_rows
                                       : ((gate->kind == QASM_GATE_DIAGONAL) ? space->diagonal_entries : space->phases);
    const size_t record_bytes = (gate->kind == QASM_GATE_PAIR)
                                    ? (QASM_PAIR_ROWS * QASM_PAIR_ROW_LIMBS * sizeof(unsigned int))
                                    : (QASM_DIAGONAL_ENTRIES * QASM_DIAGONAL_ENTRY_LIMBS * sizeof(unsigned int));
    const unsigned long long lanes = space->lanes;
    const unsigned int out_limbs = program->layout.out_limbs;
    if (space->on_host != 0)
    {
        if (gate->kind != QASM_GATE_PERMUTE)
        {
            qasm_gate_records(gate, records);
            memcpy(gate_records, records, record_bytes);
        }
        for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
        {
            qasm_lane_index(gate, lane, &space->index[lane * members]);
        }
        CycleRecordHostRequest run;
        memset(&run, 0, sizeof(run));
        run.layout = &program->layout;
        run.in[0] = space->state;
        run.bodies[0] = lanes;
        run.in[members - 1u] = gate_records;
        run.bodies[members - 1u] = qasm_gate_bodies(gate);
        if (members == 3u)
        {
            run.in[1] = space->state;
            run.bodies[1] = lanes;
        }
        run.index = space->index;
        run.count = lanes;
        run.out = space->out;
        run.error = error;
        if (!QASM_CHECK(cycle_record_run_host(&run) != CYCLE_ERROR, gate, error, ENGINE_ERROR_LOGIC))
        {
            return 0;
        }
        int fits = 1;
        for (unsigned long long lane = 0ull; lane < lanes; lane += 1ull)
        {
            fits &= qasm_repack_lane(space->out, out_limbs, program->out_offset[0], program->out_bits[0],
                                     program->out_offset[1], program->out_bits[1], lane, (long long *)space->state);
        }
        return QASM_CHECK(fits != 0, gate, error, ENGINE_ERROR_LOGIC);
    }
    if (gate->kind != QASM_GATE_PERMUTE)
    {
        qasm_gate_records(gate, records);
        if (!QASM_STATUS_CHECK(cudaMemcpy(gate_records, records, record_bytes, cudaMemcpyHostToDevice), gate_records,
                               error))
        {
            return 0;
        }
    }
    qasm_index_kernel<<<qasm_blocks(lanes), QASM_BLOCK>>>(*gate, lanes, members, space->index);
    if (!QASM_STATUS_CHECK(cudaGetLastError(), space->index, error))
    {
        return 0;
    }
    CycleRecordRunRequest run;
    memset(&run, 0, sizeof(run));
    run.record = program->record;
    run.device_in[0] = space->state;
    run.bodies[0] = lanes;
    run.device_in[members - 1u] = gate_records;
    run.bodies[members - 1u] = qasm_gate_bodies(gate);
    if (members == 3u)
    {
        run.device_in[1] = space->state;
        run.bodies[1] = lanes;
    }
    run.device_index = space->index;
    run.count = lanes;
    run.device_out = space->out;
    run.error = error;
    if (cycle_record_run(&run) == CYCLE_ERROR)
    {
        engine_error_frame(error);
        return 0;
    }
    qasm_repack_kernel<<<qasm_blocks(lanes), QASM_BLOCK>>>(
        space->out, out_limbs, program->out_offset[0], program->out_bits[0], program->out_offset[1],
        program->out_bits[1], lanes, (long long *)space->state, space->overflow);
    return QASM_STATUS_CHECK(cudaGetLastError(), space->out, error);
}

// the probabilities swept, read to the host in chunks, and tallied
static int qasm_probabilities(QasmSpace *space, const QasmProgram *program, QasmResults *results, EngineError *error)
{
    const unsigned long long lanes = space->lanes;
    const unsigned int limbs = program->layout.out_limbs;
    const unsigned int bits = program->out_bits[0];
    if (!QASM_CHECK((program->out_offset[0] == 0u) && (limbs == 4u) && (bits <= 128u) && (bits > 64u), program, error,
                    ENGINE_ERROR_LOGIC))
    {
        return 0;
    }
    if (space->on_host != 0)
    {
        CycleRecordHostRequest run;
        memset(&run, 0, sizeof(run));
        run.layout = &program->layout;
        run.in[0] = space->state;
        run.bodies[0] = lanes;
        run.count = lanes;
        run.out = space->out;
        run.error = error;
        if (!QASM_CHECK(cycle_record_run_host(&run) != CYCLE_ERROR, space, error, ENGINE_ERROR_LOGIC))
        {
            return 0;
        }
        qasm_results_lanes(results, space->out, limbs, bits, 0ull, lanes);
        return 1;
    }
    CycleRecordRunRequest run;
    memset(&run, 0, sizeof(run));
    run.record = program->record;
    run.device_in[0] = space->state;
    run.bodies[0] = lanes;
    run.count = lanes;
    run.device_out = space->out;
    run.error = error;
    if (cycle_record_run(&run) == CYCLE_ERROR)
    {
        engine_error_frame(error);
        return 0;
    }
    const unsigned long long chunk = (lanes < QASM_CHUNK_LANES) ? lanes : QASM_CHUNK_LANES;
    unsigned int *const staging = (unsigned int *)malloc((size_t)(chunk * limbs * sizeof(unsigned int)));
    if (!QASM_CHECK(staging != NULL, space, error, ENGINE_ERROR_RESOURCE))
    {
        return 0;
    }
    int ok = 1;
    for (unsigned long long first = 0ull; ok && (first < lanes); first += chunk)
    {
        const unsigned long long count = ((lanes - first) < chunk) ? (lanes - first) : chunk;
        ok = QASM_STATUS_CHECK(cudaMemcpy(staging, &space->out[first * limbs],
                                          (size_t)(count * limbs * sizeof(unsigned int)), cudaMemcpyDeviceToHost),
                               staging, error);
        if (ok)
        {
            qasm_results_lanes(results, staging, limbs, bits, first, count);
        }
    }
    free(staging);
    return ok;
}

long qasm_run(const QasmRunRequest *request, QasmOutcome *outcome)
{
    if ((request == NULL) || (request->error == NULL))
    {
        return QASM_ERROR;
    }
    EngineError *const error = request->error;
    const QasmCircuit *const circuit = request->circuit;
    if (!QASM_CHECK((outcome != NULL) && (circuit != NULL) && (circuit->qubits != 0u) &&
                        (circuit->qubits <= QASM_QUBITS_MAX) && (circuit->measured != 0u) &&
                        ((circuit->gate_count == 0u) || (circuit->gates != NULL)),
                    request, error, ENGINE_ERROR_REQUEST))
    {
        return QASM_ERROR;
    }
    memset(outcome, 0, sizeof(*outcome));
    const auto started = std::chrono::steady_clock::now();
    const int on_host = (request->on_host != 0) ? 1 : 0;
    QasmProgram programs[QASM_PROGRAMS];
    memset(programs, 0, sizeof(programs));
    int ok = 1;
    for (unsigned int which = 0u; ok && (which < QASM_PROGRAMS); which += 1u)
    {
        ok = qasm_program_load(&programs[which], which, on_host, error);
    }
    QasmSpace space;
    memset(&space, 0, sizeof(space));
    ok = ok && qasm_space_reserve(&space, circuit, on_host, error);
    for (unsigned int gate = 0u; ok && (gate < circuit->gate_count); gate += 1u)
    {
        ok = qasm_sweep(&space, programs, &circuit->gates[gate], error);
    }
    if (ok && (on_host == 0))
    {
        unsigned int overflow = 1u;
        ok = QASM_STATUS_CHECK(cudaDeviceSynchronize(), space.state, error) &&
             QASM_STATUS_CHECK(cudaMemcpy(&overflow, space.overflow, sizeof(overflow), cudaMemcpyDeviceToHost),
                               space.overflow, error) &&
             QASM_CHECK(overflow == 0u, space.overflow, error, ENGINE_ERROR_LOGIC);
    }
    if (ok && (request->state_out != NULL))
    {
        const size_t bytes = (size_t)(space.lanes * QASM_STATE_LIMBS * sizeof(unsigned int));
        if (on_host != 0)
        {
            memcpy(request->state_out, space.state, bytes);
        }
        else
        {
            ok = QASM_STATUS_CHECK(cudaMemcpy(request->state_out, space.state, bytes, cudaMemcpyDeviceToHost),
                                   request->state_out, error);
        }
    }
    QasmResults results;
    memset(&results, 0, sizeof(results));
    results.circuit = circuit;
    for (unsigned int qubit = 0u; qubit < circuit->qubits; qubit += 1u)
    {
        if (circuit->measure[qubit] != 0u)
        {
            results.measured_qubit[results.measured_count] = qubit;
            results.measured_count += 1u;
        }
    }
    results.full = (results.measured_count == circuit->qubits);
    if (ok && (results.full == 0))
    {
        results.bins = (QasmWide *)calloc((size_t)(1ull << results.measured_count), sizeof(QasmWide));
        ok = QASM_CHECK(results.bins != NULL, &results, error, ENGINE_ERROR_RESOURCE);
    }
    ok = ok && qasm_probabilities(&space, &programs[QASM_PROGRAM_PROBABILITY], &results, error);
    if (ok && (results.full == 0))
    {
        for (unsigned long long bin = 0ull; bin < (1ull << results.measured_count); bin += 1ull)
        {
            qasm_top_two(&results.top, &results.bins[bin], bin);
        }
    }
    if (ok)
    {
        qasm_outcome_close(&results, outcome);
        outcome->sweeps = circuit->gate_count + 1u;
        outcome->lanes = space.lanes;
    }
    free(results.bins);
    qasm_space_release(&space);
    for (unsigned int which = 0u; which < QASM_PROGRAMS; which += 1u)
    {
        qasm_program_release(&programs[which]);
    }
    outcome->microseconds = (unsigned long long)std::chrono::duration_cast<std::chrono::microseconds>(
                                std::chrono::steady_clock::now() - started)
                                .count();
    if (!ok)
    {
        engine_error_frame(error);
        return QASM_ERROR;
    }
    return 0L;
}

// ---------------------------------------------------------------------------------------------------------------
// the tessera job

static int qasm_job_daemon(char *path, size_t capacity)
{
    // $TESSERA_DAEMON names the daemon; otherwise it is the tessera_daemon beside this program
    const char *const named = getenv("TESSERA_DAEMON");
    if ((named != NULL) && (named[0] != '\0'))
    {
        const int written = snprintf(path, capacity, "%s", named);
        return (written > 0) && ((size_t)written < capacity);
    }
#if defined(_WIN32)
    const size_t length = (size_t)GetModuleFileNameA(NULL, path, (DWORD)capacity);
    const char *const daemon = "tessera_daemon.exe";
#else
    const ssize_t read = readlink("/proc/self/exe", path, capacity - 1u);
    const size_t length = (read > 0) ? (size_t)read : 0u;
    const char *const daemon = "tessera_daemon";
#endif
    size_t directory_length = (length < capacity) ? length : 0u;
    while ((directory_length != 0u) && (path[directory_length - 1u] != '/') && (path[directory_length - 1u] != '\\'))
    {
        directory_length -= 1u;
    }
    if ((directory_length == 0u) || ((directory_length + strlen(daemon) + 1u) > capacity))
    {
        return 0;
    }
    memcpy(path + directory_length, daemon, strlen(daemon) + 1u);
    return 1;
}

long qasm_job_submit(const unsigned char *request, unsigned long long bytes, unsigned long long declared, QasmJob **job,
                     EngineError *error)
{
    if (error == NULL)
    {
        return QASM_ERROR;
    }
    if (!QASM_CHECK((request != NULL) && (bytes != 0ull) && (declared != 0ull) && (job != NULL), request, error,
                    ENGINE_ERROR_REQUEST))
    {
        return QASM_ERROR;
    }
    *job = NULL;
    static char daemon[ENGINE_PATH_CAPACITY];
    int device = 0;
    cudaDeviceProp properties;
    TesseraJobAsk ask;
    memset(&ask, 0, sizeof(ask));
    if (!QASM_CHECK(qasm_job_daemon(daemon, sizeof(daemon)), daemon, error, ENGINE_ERROR_RESOURCE) ||
        !QASM_STATUS_CHECK(cudaGetDevice(&device), &device, error) ||
        !QASM_STATUS_CHECK(cudaGetDeviceProperties(&properties, device), &properties, error))
    {
        return QASM_ERROR;
    }
    const ObsignatioSignumRequest signum = {
        request, bytes, NULL, OBSIGNATIO_MODE_HASH, ask.signum.bytes, ENGINE_SIGNUM_BYTES, error};
    if (obsignatio_signum(&signum) != 0L)
    {
        engine_error_frame(error);
        return QASM_ERROR;
    }
    memcpy(ask.device, properties.uuid.bytes, TESSERA_DEVICE_BYTES);
#if defined(_WIN32)
    memcpy(&ask.luid, properties.luid, sizeof(ask.luid));
#endif
    ask.declared = declared;
    ask.holding_microseconds = QASM_JOB_RUNNING_MICROSECONDS;
    ask.sweep_microseconds = QASM_JOB_SWEEP_MICROSECONDS;
    ask.idle_microseconds = QASM_JOB_IDLE_MICROSECONDS;
    ask.override_budget = (getenv("TESSERA_OVERRIDE") != NULL) ? 1u : 0u;
    ask.daemon_path = daemon;
    ask.error = error;
    TesseraTicket ticket;
    memset(&ticket, 0, sizeof(ticket));
    TesseraClient *client = NULL;
    if (tessera_job_submit(&ask, &client, &ticket) != 0L)
    {
        engine_error_frame(error);
        return QASM_ERROR;
    }
    if (ticket.asked != 0u)
    {
        fprintf(stderr,
                "tessera: the run declares %llu bytes over its kept peak of %llu; TESSERA_OVERRIDE=1 admits it\n",
                declared, ticket.last_peak);
        const int admitted = (tessera_job_wait(client, &ticket, error) == 0L) && (ticket.lost == 0u);
        if (!admitted)
        {
            if (ticket.lost != 0u)
            {
                fprintf(stderr, "tessera: the run was held past its holding time and lost (ticket in %s)\n",
                        ticket.lost_path);
                tessera_job_precalc_kept(client, error);
            }
            QASM_CHECK(0, client, error, ENGINE_ERROR_RESOURCE);
            return QASM_ERROR;
        }
    }
    QasmJob *const new_job = (QasmJob *)calloc(1u, sizeof(QasmJob));
    if (!QASM_CHECK(new_job != NULL, job, error, ENGINE_ERROR_RESOURCE))
    {
        TesseraTicket released;
        tessera_job_release(client, &released, error);
        return QASM_ERROR;
    }
    new_job->client = client;
    new_job->declared = declared;
    *job = new_job;
    fprintf(stderr, "tessera: admitted, %llu bytes reserved\n", ticket.granted);
    return 0L;
}

long qasm_job_release(QasmJob *job, EngineError *error)
{
    if ((job == NULL) || (error == NULL))
    {
        return 0L;
    }
    TesseraTicket ticket;
    memset(&ticket, 0, sizeof(ticket));
    const long released = tessera_job_release(job->client, &ticket, error);
    if (released == 0L)
    {
        fprintf(stderr, "tessera: released, peak %llu bytes%s\n", ticket.last_peak,
                (ticket.last_peak > job->declared) ? ", more than it declared" : "");
    }
    free(job);
    return (released == 0L) ? 0L : QASM_ERROR;
}
