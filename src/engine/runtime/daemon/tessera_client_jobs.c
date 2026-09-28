// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tessera_client_jobs.c: self reports, submitting, waiting and releasing jobs
#include "tessera_client_internal.h"

#if !defined(_WIN32)
static int tessera_self_report(TesseraClient *client)
{
    unsigned long long used = 0ull;
    if (!tessera_self_measure(client->luid, &used))
    {
        return 0;
    }
    TesseraFrame frame;
    tessera_frame_start(client, &frame, TESSERA_ASK_MEASURED);
    frame.measured = used;
    return tessera_send(client, &frame);
}

static void *tessera_self_run(void *argument)
{
    TesseraClient *const client = (TesseraClient *)argument;
    int stop = 0;
    while (!stop)
    {
        tessera_self_report(client);
        struct timespec until;
        clock_gettime(CLOCK_REALTIME, &until);
        const unsigned long long nanoseconds =
            ((unsigned long long)until.tv_nsec) + (client->sweep_microseconds * 1000ull);
        // whole seconds of a sweep fit a time_t, and the remainder is below a billion nanoseconds
        until.tv_sec += (time_t)(nanoseconds / 1000000000ull);
        // the remainder is below a billion, which a long holds
        until.tv_nsec = (long)(nanoseconds % 1000000000ull);
        pthread_mutex_lock(&client->watch);
        int waited = 0;
        while (!client->stopping && (waited == 0))
        {
            waited = pthread_cond_timedwait(&client->woken, &client->watch, &until);
        }
        stop = client->stopping;
        pthread_mutex_unlock(&client->watch);
    }
    return NULL;
}
#endif

static void tessera_self_begin(TesseraClient *client, const TesseraTicket *ticket)
{
#if defined(_WIN32)
    (void)client;
    (void)ticket;
#else
    // an admitted job on a paravirtual device reports its own bytes from now until it is released; a host job reports
    // its processors itself (tessera_job_report)
    if ((ticket->asked == 0u) && (ticket->lost == 0u) && !client->measuring &&
        !tessera_device_names_host(client->device) && tessera_self_paravirtual())
    {
        client->stopping = 0;
        client->measuring = pthread_create(&client->measurer, NULL, tessera_self_run, client) == 0;
    }
#endif
}

static void tessera_self_end(TesseraClient *client)
{
#if defined(_WIN32)
    (void)client;
#else
    if (!client->measuring)
    {
        return;
    }
    pthread_mutex_lock(&client->watch);
    client->stopping = 1;
    pthread_cond_signal(&client->woken);
    pthread_mutex_unlock(&client->watch);
    pthread_join(client->measurer, NULL);
    client->measuring = 0;
    // the last reading goes in before the release: the peak kept holds the whole run
    tessera_self_report(client);
#endif
}

static void tessera_client_end(TesseraClient *client)
{
    if (client == NULL)
    {
        return;
    }
    tessera_self_end(client);
#if defined(_WIN32)
    if (client->pipe != INVALID_HANDLE_VALUE)
    {
        CloseHandle(client->pipe);
    }
#else
    if (client->socket_descriptor >= 0)
    {
        close(client->socket_descriptor);
    }
    pthread_cond_destroy(&client->woken);
    pthread_mutex_destroy(&client->watch);
    pthread_mutex_destroy(&client->sending);
#endif
    free(client);
}

static long tessera_decided(TesseraClient *client, TesseraTicket *ticket, EngineError *error)
{
    for (;;)
    {
        TesseraFrame frame;
        if (!TESSERA_CHECK(tessera_receive(client, &frame), client, error, ENGINE_ERROR_RESOURCE))
        {
            return TESSERA_ERROR;
        }
        if (frame.kind == TESSERA_TELL_GREW)
        {
            ticket->grown_to = (frame.measured > ticket->grown_to) ? frame.measured : ticket->grown_to;
            continue;
        }
        client->identity = frame.identity;
        ticket->identity = frame.identity;
        ticket->last_peak = frame.measured;
        if (frame.kind == TESSERA_TELL_ADMITTED)
        {
            ticket->asked = 0u;
            ticket->granted = frame.bytes;
            // the admission names the whole declaration: the bytes the process held as it asked, then the job's own
            ticket->standing = (frame.declared > client->declared) ? (frame.declared - client->declared) : 0ull;
            return 0L;
        }
        if (frame.kind == TESSERA_TELL_ASKED)
        {
            ticket->asked = 1u;
            return 0L;
        }
        if (frame.kind == TESSERA_TELL_LOST)
        {
            ticket->asked = 0u;
            ticket->lost = 1u;
            const int named = tessera_path_lost(client->device, frame.identity, &client->signum, ticket->lost_path,
                                                ENGINE_PATH_CAPACITY);
            return TESSERA_CHECK(named, ticket, error, ENGINE_ERROR_REQUEST) ? 0L : TESSERA_ERROR;
        }
        TESSERA_CHECK(0, &frame, error, ENGINE_ERROR_REQUEST);
        return TESSERA_ERROR;
    }
}

long tessera_job_submit(const TesseraJobAsk *ask, TesseraClient **client, TesseraTicket *ticket)
{
    *client = NULL;
    memset(ticket, 0, sizeof(*ticket));
    if (!TESSERA_CHECK((ask->declared != 0ull) && (ask->sweep_microseconds != 0ull) && (ask->override_budget <= 1u),
                       ask, ask->error, ENGINE_ERROR_REQUEST))
    {
        return TESSERA_ERROR;
    }
    TesseraClient *const made = (TesseraClient *)calloc(1u, sizeof(TesseraClient));
    if (!TESSERA_CHECK(made != NULL, ask, ask->error, ENGINE_ERROR_RESOURCE))
    {
        return TESSERA_ERROR;
    }
#if defined(_WIN32)
    made->pipe = INVALID_HANDLE_VALUE;
#else
    made->socket_descriptor = -1;
    pthread_mutex_init(&made->sending, NULL);
    pthread_mutex_init(&made->watch, NULL);
    pthread_cond_init(&made->woken, NULL);
#endif
    memcpy(made->device, ask->device, TESSERA_DEVICE_BYTES);
    made->luid = ask->luid;
    made->signum = ask->signum;
    made->declared = ask->declared;
    made->sweep_microseconds = ask->sweep_microseconds;
    _Alignas(8) char endpoint[ENGINE_PATH_CAPACITY];
    if (!TESSERA_CHECK(tessera_path_endpoint(ask->device, endpoint, ENGINE_PATH_CAPACITY), ask, ask->error,
                       ENGINE_ERROR_REQUEST))
    {
        tessera_client_end(made);
        return TESSERA_ERROR;
    }
    const TesseraConnect outcome = tessera_connect(made, endpoint);
    const int connected =
        (outcome == TESSERA_CONNECT_MADE) || ((outcome == TESSERA_CONNECT_ABSENT) && (ask->daemon_path != NULL) &&
                                              tessera_spawn_and_connect(made, ask, endpoint));
    if (!TESSERA_CHECK(connected, endpoint, ask->error, ENGINE_ERROR_RESOURCE))
    {
        tessera_client_end(made);
        return TESSERA_ERROR;
    }
    TesseraFrame frame;
    tessera_frame_start(made, &frame, TESSERA_ASK_SUBMIT);
    frame.override_budget = ask->override_budget;
    frame.declared = ask->declared;
    frame.holding_microseconds = ask->holding_microseconds;
    frame.sweep_microseconds = ask->sweep_microseconds;
    frame.idle_microseconds = ask->idle_microseconds;
    // where no pid is measured from outside, the process reports the bytes it already holds as it asks; a host job
    // stands on nothing, since the processors it uses are counted only once it runs
    unsigned long long standing = 0ull;
    if (!tessera_device_names_host(ask->device) && tessera_self_paravirtual() &&
        tessera_self_measure(ask->luid, &standing))
    {
        frame.measured = standing;
    }
    if (!TESSERA_CHECK(tessera_send(made, &frame), made, ask->error, ENGINE_ERROR_RESOURCE) ||
        (tessera_decided(made, ticket, ask->error) == TESSERA_ERROR))
    {
        tessera_client_end(made);
        return TESSERA_ERROR;
    }
    tessera_self_begin(made, ticket);
    *client = made;
    return 0L;
}

long tessera_job_override(TesseraClient *client, TesseraTicket *ticket, EngineError *error)
{
    if (!TESSERA_CHECK(ticket->asked != 0u, ticket, error, ENGINE_ERROR_REQUEST))
    {
        return TESSERA_ERROR;
    }
    TesseraFrame frame;
    tessera_frame_start(client, &frame, TESSERA_ASK_OVERRIDE);
    frame.override_budget = 1u;
    if (!TESSERA_CHECK(tessera_send(client, &frame), client, error, ENGINE_ERROR_RESOURCE))
    {
        return TESSERA_ERROR;
    }
    const long decided = tessera_decided(client, ticket, error);
    if (decided == 0L)
    {
        tessera_self_begin(client, ticket);
    }
    return decided;
}

long tessera_job_wait(TesseraClient *client, TesseraTicket *ticket, EngineError *error)
{
    if (!TESSERA_CHECK(ticket->asked != 0u, ticket, error, ENGINE_ERROR_REQUEST))
    {
        return TESSERA_ERROR;
    }
    const long decided = tessera_decided(client, ticket, error);
    if (decided == 0L)
    {
        tessera_self_begin(client, ticket);
    }
    return decided;
}

long tessera_job_precalc_kept(TesseraClient *client, EngineError *error)
{
    TesseraFrame frame;
    tessera_frame_start(client, &frame, TESSERA_ASK_PRECALC_KEPT);
    const int sent = TESSERA_CHECK(tessera_send(client, &frame), client, error, ENGINE_ERROR_RESOURCE);
    const int told = sent && TESSERA_CHECK(tessera_receive(client, &frame), client, error, ENGINE_ERROR_RESOURCE) &&
                     TESSERA_CHECK(frame.kind == TESSERA_TELL_RELEASED, &frame, error, ENGINE_ERROR_REQUEST);
    tessera_client_end(client);
    return told ? 0L : TESSERA_ERROR;
}

// 1 when a whole frame from the daemon waits to be read, read without blocking
static int tessera_waiting(TesseraClient *client)
{
#if defined(_WIN32)
    DWORD available = 0u;
    return PeekNamedPipe(client->pipe, NULL, 0u, NULL, &available, NULL) && (available >= TESSERA_FRAME_BYTES);
#else
    struct pollfd watch;
    watch.fd = client->socket_descriptor;
    watch.events = POLLIN;
    watch.revents = 0;
    return poll(&watch, 1u, 0) > 0;
#endif
}

long tessera_job_report(TesseraClient *client, TesseraTicket *ticket, unsigned long long measured, EngineError *error)
{
    TesseraFrame frame;
    tessera_frame_start(client, &frame, TESSERA_ASK_MEASURED);
    frame.measured = measured;
    if (!TESSERA_CHECK(tessera_send(client, &frame), client, error, ENGINE_ERROR_RESOURCE))
    {
        return TESSERA_ERROR;
    }
    // a report gets no answer, but the growth it shows is told back: each telling is read as it waits, and none is
    // left to fill the pipe while the daemon waits to write the next
    while (tessera_waiting(client))
    {
        if (!TESSERA_CHECK(tessera_receive(client, &frame), client, error, ENGINE_ERROR_RESOURCE) ||
            !TESSERA_CHECK(frame.kind == TESSERA_TELL_GREW, &frame, error, ENGINE_ERROR_REQUEST))
        {
            return TESSERA_ERROR;
        }
        ticket->grown_to = (frame.measured > ticket->grown_to) ? frame.measured : ticket->grown_to;
    }
    return 0L;
}

long tessera_job_release(TesseraClient *client, TesseraTicket *ticket, EngineError *error)
{
    tessera_self_end(client);
    TesseraFrame frame;
    tessera_frame_start(client, &frame, TESSERA_ASK_RELEASE);
    int ok = TESSERA_CHECK(tessera_send(client, &frame), client, error, ENGINE_ERROR_RESOURCE);
    while (ok)
    {
        ok = TESSERA_CHECK(tessera_receive(client, &frame), client, error, ENGINE_ERROR_RESOURCE);
        if (ok && (frame.kind == TESSERA_TELL_GREW))
        {
            ticket->grown_to = (frame.measured > ticket->grown_to) ? frame.measured : ticket->grown_to;
            continue;
        }
        ok = ok && TESSERA_CHECK(frame.kind == TESSERA_TELL_RELEASED, &frame, error, ENGINE_ERROR_REQUEST);
        if (ok)
        {
            ticket->granted = frame.bytes;
            ticket->last_peak = frame.measured;
            break;
        }
    }
    tessera_client_end(client);
    return ok ? 0L : TESSERA_ERROR;
}
