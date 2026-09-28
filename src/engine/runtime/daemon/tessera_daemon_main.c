// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tessera_daemon_main.c: the daemon's arguments and main
#include "tessera_daemon_internal.h"

_Alignas(8) static const char s_daemon_lock_file[] = "daemon.lock";
_Alignas(8) static const char s_daemon_usage[] = "  tessera daemon: --device <32 hex digits, all zero for the host's "
                                                 "processors> --luid <hex> --idle <microseconds>\n";
_Alignas(8) static const
    char s_daemon_no_state[] = "  tessera daemon: no state directory could be made for this device\n";
_Alignas(8) static const
    char s_daemon_long_socket[] = "  tessera daemon: the socket path is longer than a Unix socket holds: ";
_Alignas(8) static const char s_daemon_unbound[] = "  tessera daemon: this socket could not be bound: ";
_Alignas(8) static const char s_daemon_answered[] = "  tessera daemon: another daemon already answers at this socket: ";
_Alignas(8) static const char s_daemon_unmeasured[] = "  tessera daemon: the device's memory could not be measured by "
                                                      "process (NVML, and under WDDM the GPU Process Memory counter)\n";
_Alignas(8) static const char s_daemon_no_cores[] =
    "  tessera daemon: the host's cores could not be read, and no processor could be given to jobs\n";
#if defined(_WIN32)
_Alignas(8) static const char s_daemon_no_pipe[] = "  tessera daemon: the next pipe instance could not be made\n";
#endif

int main(int count, char **arguments)
{
    unsigned long long idle = 0ull;
    if (!daemon_arguments(count, arguments, &idle))
    {
        fputs(s_daemon_usage, stderr);
        return 2;
    }
    if (!tessera_path_state(s_daemon.device, s_daemon.state, ENGINE_PATH_CAPACITY) ||
        !daemon_directories_make(s_daemon.state) ||
        !tessera_path_endpoint(s_daemon.device, s_daemon.endpoint, ENGINE_PATH_CAPACITY))
    {
        fputs(s_daemon_no_state, stderr);
        return daemon_refused();
    }
    // the history is read before the endpoint exists: no client reaches a daemon that then refuses its history
    if (!tessera_ledger_open(&s_daemon.ledger))
    {
        fprintf(stderr, "  tessera daemon: the ledger could not be opened\n");
        return daemon_refused();
    }
    s_daemon.ledger.next_identity = daemon_wall();
    if (!daemon_history_load() || !tessera_ledger_idle(&s_daemon.ledger, daemon_now(), idle))
    {
        fprintf(stderr, "  tessera daemon: the history in %s could not be read\n", s_daemon.state);
        return daemon_refused();
    }
#if defined(_WIN32)
    HANDLE listening =
        CreateNamedPipeA(s_daemon.endpoint, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
                         PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                         PIPE_UNLIMITED_INSTANCES, TESSERA_FRAME_BYTES, TESSERA_FRAME_BYTES, 0u, NULL);
    if (listening == INVALID_HANDLE_VALUE)
    {
        return 0;
    }
#else
    pthread_condattr_t attributes;
    pthread_condattr_init(&attributes);
    pthread_condattr_setclock(&attributes, CLOCK_MONOTONIC);
    pthread_cond_init(&s_daemon_changed, &attributes);
    char lock_path[ENGINE_PATH_CAPACITY];
    const int lock = daemon_state_file(s_daemon_lock_file, lock_path) ? open(lock_path, O_RDWR | O_CREAT, 0600) : -1;
    if ((lock < 0) || (flock(lock, LOCK_EX | LOCK_NB) != 0))
    {
        return 0;
    }
    s_daemon.socket_activated = daemon_socket_handed();
    int listening = 3;
    if (!s_daemon.socket_activated)
    {
        struct sockaddr_un address;
        memset(&address, 0, sizeof(address));
        address.sun_family = AF_UNIX;
        if (strlen(s_daemon.endpoint) >= sizeof(address.sun_path))
        {
            fprintf(stderr, "%s%s\n", s_daemon_long_socket, s_daemon.endpoint);
            return 1;
        }
        memcpy(address.sun_path, s_daemon.endpoint, strlen(s_daemon.endpoint) + 1u);
        // the path names the device, not the state: a daemon with another state, or systemd's socket, may hold it
        const int probe = socket(AF_UNIX, SOCK_STREAM, 0);
        const int answered = (probe >= 0) && (connect(probe, (const struct sockaddr *)&address, sizeof(address)) == 0);
        if (probe >= 0)
        {
            close(probe);
        }
        if (answered)
        {
            fprintf(stderr, "%s%s\n", s_daemon_answered, s_daemon.endpoint);
            return 1;
        }
        unlink(s_daemon.endpoint);
        listening = socket(AF_UNIX, SOCK_STREAM, 0);
        struct stat endpoint;
        if ((listening < 0) || (bind(listening, (const struct sockaddr *)&address, sizeof(address)) != 0) ||
            (listen(listening, SOMAXCONN) != 0) || (stat(s_daemon.endpoint, &endpoint) != 0))
        {
            fprintf(stderr, "%s%s\n", s_daemon_unbound, s_daemon.endpoint);
            return 1;
        }
        s_daemon.endpoint_device = endpoint.st_dev;
        s_daemon.endpoint_inode = endpoint.st_ino;
    }
#endif
    s_daemon.measure = tessera_measure_open(s_daemon.device, s_daemon.luid);
    if (s_daemon.measure == NULL)
    {
        fputs(tessera_device_names_host(s_daemon.device) ? s_daemon_no_cores : s_daemon_unmeasured, stderr);
        return daemon_refused();
    }
    daemon_device_read();
    s_daemon.living = 1;
#if defined(_WIN32)
    const HANDLE timer = CreateThread(NULL, 0u, daemon_timer, NULL, 0u, NULL);
    if (timer == NULL)
    {
        return 1;
    }
    CloseHandle(timer);
    for (;;)
    {
        OVERLAPPED connecting;
        memset(&connecting, 0, sizeof(connecting));
        connecting.hEvent = CreateEventA(NULL, TRUE, FALSE, NULL);
        DWORD moved = 0u;
        const int connected =
            (connecting.hEvent != NULL) &&
            (ConnectNamedPipe(listening, &connecting) || (GetLastError() == ERROR_PIPE_CONNECTED) ||
             ((GetLastError() == ERROR_IO_PENDING) && GetOverlappedResult(listening, &connecting, &moved, TRUE)));
        if (connecting.hEvent != NULL)
        {
            CloseHandle(connecting.hEvent);
        }
        ULONG pid = 0u;
        TesseraPeer *const peer = connected ? (TesseraPeer *)calloc(1u, sizeof(TesseraPeer)) : NULL;
        const int named = (peer != NULL) && GetNamedPipeClientProcessId(listening, &pid);
        if (named)
        {
            peer->pipe = listening;
            peer->wake = CreateEventA(NULL, FALSE, FALSE, NULL);
        }
        if (!named || (peer->wake == NULL) || !daemon_peer_start(peer, pid))
        {
            DisconnectNamedPipe(listening);
            CloseHandle(listening);
            free(peer);
        }
        listening = CreateNamedPipeA(s_daemon.endpoint, PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED,
                                     PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS,
                                     PIPE_UNLIMITED_INSTANCES, TESSERA_FRAME_BYTES, TESSERA_FRAME_BYTES, 0u, NULL);
        if (listening == INVALID_HANDLE_VALUE)
        {
            fputs(s_daemon_no_pipe, stderr);
            return 1;
        }
    }
#else
    pthread_t timer;
    if (pthread_create(&timer, NULL, daemon_timer, NULL) != 0)
    {
        return 1;
    }
    pthread_detach(timer);
    for (;;)
    {
        const int accepted = accept(listening, NULL, NULL);
        if (accepted < 0)
        {
            continue;
        }
        struct ucred credentials;
        socklen_t length = sizeof(credentials);
        TesseraPeer *const peer = (TesseraPeer *)calloc(1u, sizeof(TesseraPeer));
        const int named = (peer != NULL) &&
                          (getsockopt(accepted, SOL_SOCKET, SO_PEERCRED, &credentials, &length) == 0) &&
                          (pipe(peer->wake) == 0);
        if (named)
        {
            peer->socket_descriptor = accepted;
            fcntl(peer->wake[0], F_SETFL, O_NONBLOCK);
            fcntl(peer->wake[1], F_SETFL, O_NONBLOCK);
        }
        // a peer's pid is positive, which fits in an unsigned long long
        if (!named || !daemon_peer_start(peer, (unsigned long long)credentials.pid))
        {
            close(accepted);
            free(peer);
        }
    }
#endif
}
