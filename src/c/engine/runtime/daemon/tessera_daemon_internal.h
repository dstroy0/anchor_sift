// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the tessera_daemon_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef TESSERA_DAEMON_INTERNAL_H
#define TESSERA_DAEMON_INTERNAL_H

#if !defined(_WIN32)
#define _GNU_SOURCE
#endif

#include "../obsignatio/obsignatio.h"
#include "tessera_ledger.h"
#include "tessera_measure.h"
#include "tessera_text.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define NOMINMAX
#include <direct.h>
#include <windows.h>
#else
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#endif

#define TESSERA_DAEMON_FOREVER 0xFFFFFFFFFFFFFFFFull
#define TESSERA_DAEMON_MILLION 1000000ull
#define TESSERA_HISTORY_RECORD (ENGINE_SIGNUM_BYTES + 16u)
#define TESSERA_TICKET_CAPACITY 4096u

#if defined(_WIN32)
#define TESSERA_DAEMON_SEPARATOR '\\'
#else
#define TESSERA_DAEMON_SEPARATOR '/'
#endif

typedef struct TesseraPeer
{
    struct TesseraPeer *next;
#if defined(_WIN32)
    HANDLE pipe;
    HANDLE wake;
#else
    int socket_descriptor;
    int wake[2];
#endif
    unsigned long long pid;
    TesseraProcess *process;
    unsigned long long identity;
    unsigned long long lost_identity;
    EngineSignum signum;
    unsigned long long declared;
    unsigned long long standing;
    unsigned long long holding_microseconds;
    unsigned long long sweep_microseconds;
    int has_decisive;
    TesseraFrame decisive;
    int has_grew;
    unsigned long long grew_to;
} TesseraPeer;

typedef struct
{
    TesseraLedger ledger;
    TesseraMeasure *measure;
    unsigned char device[TESSERA_DEVICE_BYTES];
    unsigned long long luid;
    char state[ENGINE_PATH_CAPACITY];
    char endpoint[ENGINE_PATH_CAPACITY];
    TesseraPeer *peers;
    unsigned long long peer_count;
    int socket_activated;
#if !defined(_WIN32)
    // the socket file this daemon bound: it removes that file and never one bound after it at the same path
    dev_t endpoint_device;
    ino_t endpoint_inode;
#endif
    int living;
} TesseraDaemon;

extern TesseraDaemon g_daemon;
#if (defined(_WIN32))

extern CONDITION_VARIABLE g_daemon_changed;
#endif
#if !(defined(_WIN32))

extern pthread_cond_t g_daemon_changed;
#endif

void daemon_lock(void);

void daemon_unlock(void);

void daemon_signal_changed(void);

unsigned long long daemon_now(void);

unsigned long long daemon_wall(void);

void daemon_wait_until(unsigned long long when);

int daemon_directories_make(const char *path);

int daemon_state_file(const char *name, char *path);

int daemon_history_load(void);

int daemon_history_save(void);

int daemon_ticket_write(unsigned long long identity, const TesseraPeer *peer, unsigned long long peak,
                        unsigned long long measured, const char *reason);

int daemon_ticket_note(unsigned long long identity, const TesseraPeer *peer, const char *note);

void daemon_frame_start(TesseraFrame *frame, unsigned int kind, unsigned long long identity);

void daemon_device_read(void);

void daemon_job_dropped(TesseraPeer *peer, unsigned long long now, const char *reason);

void daemon_handle(TesseraPeer *peer, const TesseraFrame *frame);

#if defined(_WIN32)
DWORD WINAPI daemon_timer(LPVOID unused);
#else
void *daemon_timer(void *unused);
#endif

int daemon_peer_start(TesseraPeer *peer, unsigned long long pid);

int daemon_arguments(int count, char **arguments, unsigned long long *idle);

int daemon_socket_handed(void);

int daemon_error(void);

#endif
