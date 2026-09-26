// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#ifndef TESSERA_H
#define TESSERA_H

#include "engine_config.h"

// the client's calls, exported where the engine library builds them in (build_engine.sh); a program that links the
// client's objects itself leaves TESSERA_BUILD_DLL undefined
#if defined(TESSERA_BUILD_DLL) && TESSERA_BUILD_DLL && defined(_WIN32)
#define TESSERA_EXPORT __declspec(dllexport)
#else
#define TESSERA_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

#define TESSERA_REFUSED (-1L)
#define TESSERA_FRAME_BYTES 128u
#define TESSERA_MAGIC 0x41525353u
#define TESSERA_VERSION 1u
#define TESSERA_DEVICE_BYTES 16u

// a device of sixteen zero bytes names the host's processors, which a job declares and reports in thousandths of one
// logical processor
#define TESSERA_HOST_PROCESSOR 1000ull

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

int tessera_path_lost(const unsigned char device[TESSERA_DEVICE_BYTES], unsigned long long identity,
                      const EngineSignum *signum, char *path, unsigned int room);

// a paravirtual device (WSL) measures no process from outside it; each job's process measures itself and says so
TESSERA_EXPORT int tessera_self_paravirtual(void);

TESSERA_EXPORT int tessera_self_measure(unsigned long long luid, unsigned long long *used);

TESSERA_EXPORT int tessera_device_names_host(const unsigned char device[TESSERA_DEVICE_BYTES]);

// the logical processors host jobs run on: every one but those of the host's last cores, kept for the desktop (two,
// or $TESSERA_HOST_KEPT_CORES, and never every core); 0 where the host's cores could not be read
TESSERA_EXPORT unsigned long long tessera_self_host_mask(void);

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

// `standing` is the bytes the job's process already held on the device as it asked (its CUDA context and whatever it
// kept from an earlier job), which the daemon measured and counted with its declaration; it is told on admission
typedef struct
{
    unsigned long long identity;
    unsigned long long granted;
    unsigned long long last_peak;
    unsigned long long grown_to;
    unsigned long long standing;
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

TESSERA_EXPORT long tessera_job_submit(const TesseraJobAsk *ask, TesseraClient **client, TesseraTicket *ticket);

TESSERA_EXPORT long tessera_job_override(TesseraClient *client, TesseraTicket *ticket, EngineError *error);

TESSERA_EXPORT long tessera_job_wait(TesseraClient *client, TesseraTicket *ticket, EngineError *error);

TESSERA_EXPORT long tessera_job_precalc_kept(TesseraClient *client, EngineError *error);

// an admitted job's own measure, where the daemon reads none from outside (the host's processors, or a device under
// WSL); any growth the daemon has told back is read into the ticket
TESSERA_EXPORT long tessera_job_report(TesseraClient *client, TesseraTicket *ticket, unsigned long long measured,
                                       EngineError *error);

TESSERA_EXPORT long tessera_job_release(TesseraClient *client, TesseraTicket *ticket, EngineError *error);

#ifdef __cplusplus
}
#endif

#endif
