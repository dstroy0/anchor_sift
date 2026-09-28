// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tessera_client_socket.c: connecting, spawning, sending and receiving
#include "tessera_client_internal.h"

#if defined(_WIN32)
_Alignas(8) static const char s_client_quote[] = "\"";
_Alignas(8) static const char s_client_device[] = "\" --device ";
_Alignas(8) static const char s_client_luid[] = " --luid ";
_Alignas(8) static const char s_client_idle[] = " --idle ";
#else
_Alignas(8) static const char s_client_lock[] = "/daemon.lock";
#endif

TesseraConnect tessera_connect(TesseraClient *client, const char *endpoint)
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
static int tessera_daemon_owns_lock(const unsigned char device[TESSERA_DEVICE_BYTES])
{
    _Alignas(8) char lock_path[ENGINE_PATH_CAPACITY];
    if (!tessera_path_state(device, lock_path, ENGINE_PATH_CAPACITY))
    {
        return 0;
    }
    ScripturaLine line = {lock_path, ENGINE_PATH_CAPACITY, strlen(lock_path)};
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

int tessera_spawn_and_connect(TesseraClient *client, const TesseraJobAsk *ask, const char *endpoint)
{
    _Alignas(8) char device_text[TESSERA_ARGUMENT_CAPACITY];
    _Alignas(8) char luid_text[TESSERA_ARGUMENT_CAPACITY];
    _Alignas(8) char idle_text[TESSERA_ARGUMENT_CAPACITY];
    ScripturaLine device_line = {device_text, TESSERA_ARGUMENT_CAPACITY, 0ull};
    ScripturaLine luid_line = {luid_text, TESSERA_ARGUMENT_CAPACITY, 0ull};
    ScripturaLine idle_line = {idle_text, TESSERA_ARGUMENT_CAPACITY, 0ull};
    tessera_bytes_hex(&device_line, ask->device, TESSERA_DEVICE_BYTES);
    scriptura_hex(&luid_line, ask->luid, 16u);
    scriptura_decimal(&idle_line, ask->idle_microseconds, 1u);
    if ((scriptura_finish(&device_line) == 0ull) || (scriptura_finish(&luid_line) == 0ull) ||
        (scriptura_finish(&idle_line) == 0ull))
    {
        return 0;
    }
#if defined(_WIN32)
    _Alignas(8) char command[ENGINE_PATH_CAPACITY];
    ScripturaLine line = {command, ENGINE_PATH_CAPACITY, 0ull};
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
        char *const arguments[] = {
            (char *)ask->daemon_path, (char *)"--device", device_text, (char *)"--luid", luid_text,
            (char *)"--idle",         idle_text,          NULL};
        execv(ask->daemon_path, arguments);
        _exit(127);
    }
    int ended = 0;
    TesseraConnect outcome = tessera_connect(client, endpoint);
    while (outcome == TESSERA_CONNECT_ABSENT)
    {
        int status = 0;
        ended = ended || (waitpid(daemon, &status, WNOHANG) == daemon);
        if (ended && !tessera_daemon_owns_lock(ask->device))
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

int tessera_send(TesseraClient *client, const TesseraFrame *frame)
{
    unsigned char bytes[TESSERA_FRAME_BYTES];
    if (!tessera_frame_pack(frame, bytes))
    {
        return 0;
    }
    unsigned int sent = 0u;
#if !defined(_WIN32)
    // the measuring thread and the caller share the socket, and each frame goes out whole under the lock
    pthread_mutex_lock(&client->sending);
#endif
    int ok = 1;
    while (ok && (sent < TESSERA_FRAME_BYTES))
    {
#if defined(_WIN32)
        DWORD moved = 0u;
        ok = WriteFile(client->pipe, bytes + sent, TESSERA_FRAME_BYTES - sent, &moved, NULL) && (moved != 0u);
#else
        const ssize_t moved = write(client->socket_descriptor, bytes + sent, TESSERA_FRAME_BYTES - sent);
        if ((moved < 0) && (errno == EINTR))
        {
            continue;
        }
        ok = moved > 0;
#endif
        // a count of bytes moved is positive and at most one frame
        sent += ok ? (unsigned int)moved : 0u;
    }
#if !defined(_WIN32)
    pthread_mutex_unlock(&client->sending);
#endif
    return ok;
}

int tessera_receive(TesseraClient *client, TesseraFrame *frame)
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

void tessera_frame_start(const TesseraClient *client, TesseraFrame *frame, unsigned int kind)
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
