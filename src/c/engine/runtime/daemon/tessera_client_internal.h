// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the tessera_client_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef TESSERA_CLIENT_INTERNAL_H
#define TESSERA_CLIENT_INTERNAL_H

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
#include <sched.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#endif

#define TESSERA_CHECK(condition_, evacaddr_, error_, kind_)                                                            \
    engine_error_check((condition_), (kind_), ENGINE_MODULE_TESSERA, (unsigned int)__LINE__,                           \
                       (const void *)(evacaddr_), (error_))

#define TESSERA_IO(condition_, evacaddr_, error_)                                                                      \
    engine_io_check((condition_), ENGINE_MODULE_TESSERA, (unsigned int)__LINE__, (const void *)(evacaddr_), (error_))

#define TESSERA_ARGUMENT_CAPACITY 128u

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

TesseraConnect tessera_connect(TesseraClient *client, const char *endpoint);

int tessera_spawn_and_connect(TesseraClient *client, const TesseraJobAsk *ask, const char *endpoint);

int tessera_send(TesseraClient *client, const TesseraFrame *frame);

int tessera_receive(TesseraClient *client, TesseraFrame *frame);

void tessera_frame_start(const TesseraClient *client, TesseraFrame *frame, unsigned int kind);

#endif
