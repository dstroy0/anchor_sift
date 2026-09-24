// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef TESSERA_H
#define TESSERA_H

#include "engine_config.h"

#ifdef __cplusplus
extern "C" {
#endif

#define TESSERA_REFUSED (-1L)
#define TESSERA_FRAME_BYTES 128u
#define TESSERA_MAGIC 0x41525353u
#define TESSERA_VERSION 1u
#define TESSERA_DEVICE_BYTES 16u

typedef enum
{
    TESSERA_ASK_SUBMIT = 1,
    TESSERA_ASK_OVERRIDE = 2,
    TESSERA_ASK_RELEASE = 3,
    TESSERA_ASK_PRECALC_KEPT = 4,
    TESSERA_ASK_MEASURED = 5,
    TESSERA_TELL_ADMITTED = 16,
    TESSERA_TELL_ASKED = 17,
    TESSERA_TELL_GREW = 18,
    TESSERA_TELL_LOST = 19,
    TESSERA_TELL_RELEASED = 20,
    TESSERA_TELL_REFUSED = 21
} TesseraFrameKind;

typedef struct
{
    unsigned int magic;
    unsigned int version;
    unsigned int kind;
    unsigned int override_budget;
    unsigned char device[TESSERA_DEVICE_BYTES];
    EngineSignum signum;
    unsigned long long declared;
    unsigned long long holding_microseconds;
    unsigned long long sweep_microseconds;
    unsigned long long idle_microseconds;
    unsigned long long bytes;
    unsigned long long measured;
    unsigned long long identity;
    unsigned long long luid;
} TesseraFrame;

#if defined(__cplusplus)
static_assert(sizeof(TesseraFrame) == TESSERA_FRAME_BYTES, "tessera: a frame is 128 bytes on every platform");
#else
_Static_assert(sizeof(TesseraFrame) == TESSERA_FRAME_BYTES, "tessera: a frame is 128 bytes on every platform");
#endif

int tessera_frame_pack(const TesseraFrame *frame, unsigned char bytes[TESSERA_FRAME_BYTES]);

int tessera_frame_unpack(const unsigned char bytes[TESSERA_FRAME_BYTES], TesseraFrame *frame);

int tessera_path_endpoint(const unsigned char device[TESSERA_DEVICE_BYTES], char *path, unsigned int room);

int tessera_path_state(const unsigned char device[TESSERA_DEVICE_BYTES], char *path, unsigned int room);

int tessera_path_lost(const unsigned char device[TESSERA_DEVICE_BYTES], char *path, unsigned int room);

// a paravirtual device (WSL) measures no process from outside it; each job's process measures itself and says so
int tessera_self_paravirtual(void);

int tessera_self_measure(unsigned long long luid, unsigned long long *used);

typedef struct
{
    unsigned char device[TESSERA_DEVICE_BYTES];
    unsigned long long luid;
    EngineSignum signum;
    unsigned long long declared;
    unsigned long long holding_microseconds;
    unsigned long long sweep_microseconds;
    unsigned long long idle_microseconds;
    unsigned int override_budget;
    const char *daemon_path;
    EngineError *error;
} TesseraJobAsk;

typedef struct
{
    unsigned long long identity;
    unsigned long long granted;
    unsigned long long last_peak;
    unsigned long long grown_to;
    unsigned int asked;
    unsigned int lost;
    char lost_path[ENGINE_PATH_ROOM];
} TesseraTicket;

#if defined(__cplusplus)
static_assert((offsetof(TesseraTicket, lost_path) % 8u) == 0u, "tessera: a ticket's lost path is a word-aligned block");
#else
_Static_assert((offsetof(TesseraTicket, lost_path) % 8u) == 0u, "tessera: a ticket's lost path is a word-aligned block");
#endif

typedef struct TesseraClient TesseraClient;

long tessera_job_submit(const TesseraJobAsk *ask, TesseraClient **client, TesseraTicket *ticket);

long tessera_job_override(TesseraClient *client, TesseraTicket *ticket, EngineError *error);

long tessera_job_wait(TesseraClient *client, TesseraTicket *ticket, EngineError *error);

long tessera_job_precalc_kept(TesseraClient *client, EngineError *error);

long tessera_job_release(TesseraClient *client, TesseraTicket *ticket, EngineError *error);

#ifdef __cplusplus
}
#endif

#endif
