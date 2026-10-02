// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#include "sim.h"

#include "../../c/engine/runtime/obsignatio/obsignatio.h"
#include "../../c/engine/runtime/daemon/tessera.h"

#if defined(_WIN32)
#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <unistd.h>
#endif

#define SIM_JOB_RUNNING_MICROSECONDS 2000000ull
#define SIM_JOB_SWEEP_MICROSECONDS 20000ull
#define SIM_JOB_IDLE_MICROSECONDS 5000000ull

static int sim_job_daemon(char *path, size_t capacity)
{
    // $TESSERA_DAEMON names the daemon; otherwise it is the tessera_daemon beside this program
    const char *const named = getenv("TESSERA_DAEMON");
    if ((named != NULL) && (named[0] != '\0'))
    {
        const int written = snprintf(path, capacity, "%s", named);
        // a non-negative length is compared whole against the capacity
        return (written > 0) && ((size_t)written < capacity);
    }
#if defined(_WIN32)
    // the capacity is a buffer size this file holds, which a DWORD counts on every Windows target
    const size_t length = (size_t)GetModuleFileNameA(NULL, path, (DWORD)capacity);
    const char *const daemon = "tessera_daemon.exe";
#else
    const ssize_t read = readlink("/proc/self/exe", path, capacity - 1u);
    // a failed read is -1 and is held as no length at all
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

int sim_job_submit(SimResults *results, const char *name, int count, char *const *arguments,
                   unsigned long long declared)
{
    EngineError error;
    memset(&error, 0, sizeof(error));
    int device = 0;
    cudaDeviceProp properties;
    char daemon[ENGINE_PATH_CAPACITY];
    TesseraJobAsk ask;
    memset(&ask, 0, sizeof(ask));
    // the request is the sim's name and every argument, each ended by a zero byte
    unsigned long long bytes = strlen(name) + 1ull;
    for (int at = 1; at < count; at += 1)
    {
        bytes += strlen(arguments[at]) + 1ull;
    }
    unsigned char *const request = (unsigned char *)malloc((size_t)bytes);
    // the context is made before the job asks: the daemon measures it with the process and counts it beside the
    // declaration
    int ok = (request != NULL) && (declared != 0ull) && sim_job_daemon(daemon, sizeof(daemon)) &&
             (cudaGetDevice(&device) == cudaSuccess) && (cudaGetDeviceProperties(&properties, device) == cudaSuccess) &&
             (cudaFree(0) == cudaSuccess);
    if (ok)
    {
        unsigned long long at_byte = 0ull;
        memcpy(request, name, strlen(name) + 1u);
        at_byte += strlen(name) + 1ull;
        for (int at = 1; at < count; at += 1)
        {
            memcpy(request + at_byte, arguments[at], strlen(arguments[at]) + 1u);
            at_byte += strlen(arguments[at]) + 1ull;
        }
        const ObsignatioSignumRequest signum = {
            request, bytes, NULL, OBSIGNATIO_MODE_HASH, ask.signum.bytes, ENGINE_SIGNUM_BYTES, &error};
        ok = obsignatio_signum(&signum) == 0L;
    }
    free(request);
    if (!ok)
    {
        sim_check(results, 0,
                  "tessera: the sim's job is asked (its signum, declaration, device and the daemon's place)");
        return 0;
    }
    memcpy(ask.device, properties.uuid.bytes, TESSERA_DEVICE_BYTES);
#if defined(_WIN32)
    memcpy(&ask.luid, properties.luid, sizeof(ask.luid));
#endif
    ask.declared = declared;
    ask.holding_microseconds = SIM_JOB_RUNNING_MICROSECONDS;
    ask.sweep_microseconds = SIM_JOB_SWEEP_MICROSECONDS;
    ask.idle_microseconds = SIM_JOB_IDLE_MICROSECONDS;
    ask.override_budget = (getenv("TESSERA_OVERRIDE") != NULL) ? 1u : 0u;
    ask.daemon_path = daemon;
    ask.error = &error;
    TesseraTicket ticket;
    TesseraClient *client = NULL;
    ok = tessera_job_submit(&ask, &client, &ticket) == 0L;
    if (ok && (ticket.asked != 0u))
    {
        printf("  tessera: %s declares %llu bytes over its kept peak of %llu; TESSERA_OVERRIDE=1 admits it\n", name,
               declared, ticket.last_peak);
        ok = (tessera_job_wait(client, &ticket, &error) == 0L) && (ticket.lost == 0u);
        if (!ok && (ticket.lost != 0u))
        {
            printf("  tessera: %s was held past its holding time and lost (ticket in %s)\n", name, ticket.lost_path);
            tessera_job_precalc_kept(client, &error);
        }
    }
    sim_check(results, ok, "tessera: the device's daemon admits the sim's job");
    if (!ok)
    {
        return 0;
    }
    printf("  tessera: %s admitted, %llu bytes reserved; it declared %llu over the %llu its process held as it asked\n",
           name, ticket.granted, declared, ticket.standing);
    results->job = client;
    results->job_declared = declared + ticket.standing;
    return 1;
}

void sim_job_release(SimResults *results)
{
    if (results->job == NULL)
    {
        return;
    }
    EngineError error;
    memset(&error, 0, sizeof(error));
    TesseraTicket ticket;
    memset(&ticket, 0, sizeof(ticket));
    const int released = tessera_job_release(results->job, &ticket, &error) == 0L;
    results->job = NULL;
    sim_check(results, released, "tessera: the sim's job releases");
    if (released)
    {
        printf("  tessera: released, peak %llu bytes%s\n", ticket.last_peak,
               (ticket.last_peak > results->job_declared) ? ", more than it declared" : "");
    }
}
