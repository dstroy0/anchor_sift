// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#if !defined(_WIN32)
// threads, their timed waits and the clock are outside strict C11
#define _GNU_SOURCE
#endif
#include "tessera_text.h"

#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define NOMINMAX
#include <windows.h>
#else
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <sched.h>
#include <time.h>
#include <unistd.h>
#endif

#define TESSERA_HELD(held_, evacaddr_, error_, kind_) \
    engine_error_check((held_), (kind_), ENGINE_MODULE_TESSERA, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define TESSERA_IO(held_, evacaddr_, error_) \
    engine_io_check((held_), ENGINE_MODULE_TESSERA, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define TESSERA_ARGUMENT_ROOM 128u

#if defined(_WIN32)
_Alignas(8) static const char s_client_quote[] = "\"";
_Alignas(8) static const char s_client_device[] = "\" --device ";
_Alignas(8) static const char s_client_luid[] = " --luid ";
_Alignas(8) static const char s_client_idle[] = " --idle ";
#else
_Alignas(8) static const char s_client_lock[] = "/daemon.lock";
#endif

struct TesseraClient
{
#if defined(_WIN32)
    HANDLE pipe;
#else
    int socket_descriptor;
#endif
    unsigned char device[TESSERA_DEVICE_BYTES];
    unsigned long long luid;
    EngineSignum signum;
    unsigned long long identity;
    unsigned long long declared;
    unsigned long long sweep_microseconds;
#if !defined(_WIN32)
    // where no pid is measured from outside (WSL), a thread reports this process's own bytes every sweep
    pthread_mutex_t sending;
    pthread_mutex_t watch;
    pthread_cond_t woken;
    pthread_t measurer;
    int measuring;
    int stopping;
#endif
};

typedef enum
{
    TESSERA_CONNECT_MADE = 0,
    TESSERA_CONNECT_ABSENT = 1,
    TESSERA_CONNECT_FAILED = 2
} TesseraConnect;

static TesseraConnect tessera_connect(TesseraClient *client, const char *endpoint)
{
#if defined(_WIN32)
    for (;;)
    {
        client->pipe = CreateFileA(endpoint, GENERIC_READ | GENERIC_WRITE, 0u, NULL, OPEN_EXISTING, 0u, NULL);
        if (client->pipe != INVALID_HANDLE_VALUE)
        {
            return TESSERA_CONNECT_MADE;
        }
        const DWORD failure = GetLastError();
        if (failure == ERROR_FILE_NOT_FOUND)
        {
            return TESSERA_CONNECT_ABSENT;
        }
        if ((failure != ERROR_PIPE_BUSY) || !WaitNamedPipeA(endpoint, NMPWAIT_WAIT_FOREVER))
        {
            return (GetLastError() == ERROR_FILE_NOT_FOUND) ? TESSERA_CONNECT_ABSENT : TESSERA_CONNECT_FAILED;
        }
    }
#else
    struct sockaddr_un address;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    if (strlen(endpoint) >= sizeof(address.sun_path))
    {
        return TESSERA_CONNECT_FAILED;
    }
    memcpy(address.sun_path, endpoint, strlen(endpoint) + 1u);
    // the connection closes on exec: a program this process starts never holds its job open
    client->socket_descriptor = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (client->socket_descriptor < 0)
    {
        return TESSERA_CONNECT_FAILED;
    }
    if (connect(client->socket_descriptor, (const struct sockaddr *)&address, sizeof(address)) == 0)
    {
        return TESSERA_CONNECT_MADE;
    }
    const int failure = errno;
    close(client->socket_descriptor);
    client->socket_descriptor = -1;
    return ((failure == ENOENT) || (failure == ECONNREFUSED)) ? TESSERA_CONNECT_ABSENT : TESSERA_CONNECT_FAILED;
#endif
}

#if !defined(_WIN32)
static int tessera_daemon_holds_lock(const unsigned char device[TESSERA_DEVICE_BYTES])
{
    _Alignas(8) char lock_path[ENGINE_PATH_ROOM];
    if (!tessera_path_state(device, lock_path, ENGINE_PATH_ROOM))
    {
        return 0;
    }
    ScripturaLine line = {lock_path, ENGINE_PATH_ROOM, strlen(lock_path)};
    scriptura_text(&line, s_client_lock);
    if (scriptura_finish(&line) == 0ull)
    {
        return 0;
    }
    const int lock = open(lock_path, O_RDONLY);
    if (lock < 0)
    {
        return 0;
    }
    const int free_now = flock(lock, LOCK_SH | LOCK_NB) == 0;
    close(lock);
    return !free_now;
}
#endif

static int tessera_spawn_and_connect(TesseraClient *client, const TesseraJobAsk *ask, const char *endpoint)
{
    _Alignas(8) char device_text[TESSERA_ARGUMENT_ROOM];
    _Alignas(8) char luid_text[TESSERA_ARGUMENT_ROOM];
    _Alignas(8) char idle_text[TESSERA_ARGUMENT_ROOM];
    ScripturaLine device_line = {device_text, TESSERA_ARGUMENT_ROOM, 0ull};
    ScripturaLine luid_line = {luid_text, TESSERA_ARGUMENT_ROOM, 0ull};
    ScripturaLine idle_line = {idle_text, TESSERA_ARGUMENT_ROOM, 0ull};
    tessera_bytes_hex(&device_line, ask->device, TESSERA_DEVICE_BYTES);
    scriptura_hex(&luid_line, ask->luid, 16u);
    scriptura_decimal(&idle_line, ask->idle_microseconds, 1u);
    if ((scriptura_finish(&device_line) == 0ull) || (scriptura_finish(&luid_line) == 0ull)
        || (scriptura_finish(&idle_line) == 0ull))
    {
        return 0;
    }
#if defined(_WIN32)
    _Alignas(8) char command[ENGINE_PATH_ROOM];
    ScripturaLine line = {command, ENGINE_PATH_ROOM, 0ull};
    scriptura_text(&line, s_client_quote);
    tessera_text_staged(&line, ask->daemon_path);
    scriptura_text(&line, s_client_device);
    scriptura_text(&line, device_text);
    scriptura_text(&line, s_client_luid);
    scriptura_text(&line, luid_text);
    scriptura_text(&line, s_client_idle);
    scriptura_text(&line, idle_text);
    if (scriptura_finish(&line) == 0ull)
    {
        return 0;
    }
    STARTUPINFOA startup;
    PROCESS_INFORMATION daemon;
    memset(&startup, 0, sizeof(startup));
    startup.cb = sizeof(startup);
    memset(&daemon, 0, sizeof(daemon));
    if (!CreateProcessA(NULL, command, NULL, NULL, FALSE, DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP, NULL, NULL,
                        &startup, &daemon))
    {
        return 0;
    }
    CloseHandle(daemon.hThread);
    TesseraConnect outcome = tessera_connect(client, endpoint);
    while (outcome == TESSERA_CONNECT_ABSENT)
    {
        if (WaitForSingleObject(daemon.hProcess, 0u) == WAIT_OBJECT_0)
        {
            outcome = tessera_connect(client, endpoint);
            break;
        }
        SwitchToThread();
        outcome = tessera_connect(client, endpoint);
    }
    CloseHandle(daemon.hProcess);
    return outcome == TESSERA_CONNECT_MADE;
#else
    const pid_t daemon = fork();
    if (daemon < 0)
    {
        return 0;
    }
    if (daemon == 0)
    {
        setsid();
        char *const arguments[] = {(char *)ask->daemon_path, (char *)"--device", device_text, (char *)"--luid",
                                   luid_text, (char *)"--idle", idle_text, NULL};
        execv(ask->daemon_path, arguments);
        _exit(127);
    }
    int ended = 0;
    TesseraConnect outcome = tessera_connect(client, endpoint);
    while (outcome == TESSERA_CONNECT_ABSENT)
    {
        int status = 0;
        ended = ended || (waitpid(daemon, &status, WNOHANG) == daemon);
        if (ended && !tessera_daemon_holds_lock(ask->device))
        {
            outcome = tessera_connect(client, endpoint);
            break;
        }
        sched_yield();
        outcome = tessera_connect(client, endpoint);
    }
    return outcome == TESSERA_CONNECT_MADE;
#endif
}

static int tessera_send(TesseraClient *client, const TesseraFrame *frame)
{
    unsigned char bytes[TESSERA_FRAME_BYTES];
    if (!tessera_frame_pack(frame, bytes))
    {
        return 0;
    }
    unsigned int sent = 0u;
#if !defined(_WIN32)
    // the measuring thread and the caller share the socket, so a frame goes out whole
    pthread_mutex_lock(&client->sending);
#endif
    int whole = 1;
    while (whole && (sent < TESSERA_FRAME_BYTES))
    {
#if defined(_WIN32)
        DWORD moved = 0u;
        whole = WriteFile(client->pipe, bytes + sent, TESSERA_FRAME_BYTES - sent, &moved, NULL) && (moved != 0u);
#else
        const ssize_t moved = write(client->socket_descriptor, bytes + sent, TESSERA_FRAME_BYTES - sent);
        if ((moved < 0) && (errno == EINTR))
        {
            continue;
        }
        whole = moved > 0;
#endif
        // a count of bytes moved is positive and at most one frame
        sent += whole ? (unsigned int)moved : 0u;
    }
#if !defined(_WIN32)
    pthread_mutex_unlock(&client->sending);
#endif
    return whole;
}

static int tessera_receive(TesseraClient *client, TesseraFrame *frame)
{
    unsigned char bytes[TESSERA_FRAME_BYTES];
    unsigned int got = 0u;
    while (got < TESSERA_FRAME_BYTES)
    {
#if defined(_WIN32)
        DWORD moved = 0u;
        if (!ReadFile(client->pipe, bytes + got, TESSERA_FRAME_BYTES - got, &moved, NULL) || (moved == 0u))
        {
            return 0;
        }
#else
        const ssize_t moved = read(client->socket_descriptor, bytes + got, TESSERA_FRAME_BYTES - got);
        if ((moved < 0) && (errno == EINTR))
        {
            continue;
        }
        if (moved <= 0)
        {
            return 0;
        }
#endif
        // a count of bytes moved is positive and at most one frame
        got += (unsigned int)moved;
    }
    return tessera_frame_unpack(bytes, frame);
}

static void tessera_frame_start(const TesseraClient *client, TesseraFrame *frame, unsigned int kind)
{
    memset(frame, 0, sizeof(*frame));
    frame->magic = TESSERA_MAGIC;
    frame->version = TESSERA_VERSION;
    frame->kind = kind;
    memcpy(frame->device, client->device, TESSERA_DEVICE_BYTES);
    frame->signum = client->signum;
    frame->identity = client->identity;
    frame->luid = client->luid;
}

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
        const unsigned long long nanoseconds = ((unsigned long long)until.tv_nsec) + (client->sweep_microseconds * 1000ull);
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
    if ((ticket->asked == 0u) && (ticket->lost == 0u) && !client->measuring && !tessera_device_names_host(client->device)
        && tessera_self_paravirtual())
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
    // the last reading goes in before the release, so the peak kept holds the whole run
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
        if (!TESSERA_HELD(tessera_receive(client, &frame), client, error, ENGINE_ERROR_RESOURCE))
        {
            return TESSERA_REFUSED;
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
                                                ENGINE_PATH_ROOM);
            return TESSERA_HELD(named, ticket, error, ENGINE_ERROR_REQUEST) ? 0L : TESSERA_REFUSED;
        }
        TESSERA_HELD(0, &frame, error, ENGINE_ERROR_REQUEST);
        return TESSERA_REFUSED;
    }
}

long tessera_job_submit(const TesseraJobAsk *ask, TesseraClient **client, TesseraTicket *ticket)
{
    *client = NULL;
    memset(ticket, 0, sizeof(*ticket));
    if (!TESSERA_HELD((ask->declared != 0ull) && (ask->sweep_microseconds != 0ull) && (ask->override_budget <= 1u), ask,
                      ask->error, ENGINE_ERROR_REQUEST))
    {
        return TESSERA_REFUSED;
    }
    TesseraClient *const made = (TesseraClient *)calloc(1u, sizeof(TesseraClient));
    if (!TESSERA_HELD(made != NULL, ask, ask->error, ENGINE_ERROR_RESOURCE))
    {
        return TESSERA_REFUSED;
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
    _Alignas(8) char endpoint[ENGINE_PATH_ROOM];
    if (!TESSERA_HELD(tessera_path_endpoint(ask->device, endpoint, ENGINE_PATH_ROOM), ask, ask->error,
                      ENGINE_ERROR_REQUEST))
    {
        tessera_client_end(made);
        return TESSERA_REFUSED;
    }
    const TesseraConnect outcome = tessera_connect(made, endpoint);
    const int connected = (outcome == TESSERA_CONNECT_MADE)
                       || ((outcome == TESSERA_CONNECT_ABSENT) && (ask->daemon_path != NULL)
                           && tessera_spawn_and_connect(made, ask, endpoint));
    if (!TESSERA_HELD(connected, endpoint, ask->error, ENGINE_ERROR_RESOURCE))
    {
        tessera_client_end(made);
        return TESSERA_REFUSED;
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
    if (!tessera_device_names_host(ask->device) && tessera_self_paravirtual() && tessera_self_measure(ask->luid, &standing))
    {
        frame.measured = standing;
    }
    if (!TESSERA_HELD(tessera_send(made, &frame), made, ask->error, ENGINE_ERROR_RESOURCE)
        || (tessera_decided(made, ticket, ask->error) == TESSERA_REFUSED))
    {
        tessera_client_end(made);
        return TESSERA_REFUSED;
    }
    tessera_self_begin(made, ticket);
    *client = made;
    return 0L;
}

long tessera_job_override(TesseraClient *client, TesseraTicket *ticket, EngineError *error)
{
    if (!TESSERA_HELD(ticket->asked != 0u, ticket, error, ENGINE_ERROR_REQUEST))
    {
        return TESSERA_REFUSED;
    }
    TesseraFrame frame;
    tessera_frame_start(client, &frame, TESSERA_ASK_OVERRIDE);
    frame.override_budget = 1u;
    if (!TESSERA_HELD(tessera_send(client, &frame), client, error, ENGINE_ERROR_RESOURCE))
    {
        return TESSERA_REFUSED;
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
    if (!TESSERA_HELD(ticket->asked != 0u, ticket, error, ENGINE_ERROR_REQUEST))
    {
        return TESSERA_REFUSED;
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
    const int sent = TESSERA_HELD(tessera_send(client, &frame), client, error, ENGINE_ERROR_RESOURCE);
    const int told = sent && TESSERA_HELD(tessera_receive(client, &frame), client, error, ENGINE_ERROR_RESOURCE)
                  && TESSERA_HELD(frame.kind == TESSERA_TELL_RELEASED, &frame, error, ENGINE_ERROR_REQUEST);
    tessera_client_end(client);
    return told ? 0L : TESSERA_REFUSED;
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
    if (!TESSERA_HELD(tessera_send(client, &frame), client, error, ENGINE_ERROR_RESOURCE))
    {
        return TESSERA_REFUSED;
    }
    // a report gets no answer, but the growth it shows is told back: each telling is read as it waits, and none is
    // left to fill the pipe while the daemon waits to write the next
    while (tessera_waiting(client))
    {
        if (!TESSERA_HELD(tessera_receive(client, &frame), client, error, ENGINE_ERROR_RESOURCE)
            || !TESSERA_HELD(frame.kind == TESSERA_TELL_GREW, &frame, error, ENGINE_ERROR_REQUEST))
        {
            return TESSERA_REFUSED;
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
    int held = TESSERA_HELD(tessera_send(client, &frame), client, error, ENGINE_ERROR_RESOURCE);
    while (held)
    {
        held = TESSERA_HELD(tessera_receive(client, &frame), client, error, ENGINE_ERROR_RESOURCE);
        if (held && (frame.kind == TESSERA_TELL_GREW))
        {
            ticket->grown_to = (frame.measured > ticket->grown_to) ? frame.measured : ticket->grown_to;
            continue;
        }
        held = held && TESSERA_HELD(frame.kind == TESSERA_TELL_RELEASED, &frame, error, ENGINE_ERROR_REQUEST);
        if (held)
        {
            ticket->granted = frame.bytes;
            ticket->last_peak = frame.measured;
            break;
        }
    }
    tessera_client_end(client);
    return held ? 0L : TESSERA_REFUSED;
}
