// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#if !defined(_WIN32)
#define _GNU_SOURCE
#endif

#include "obsignatio.h"
#include "tessera_ledger.h"
#include "tessera_measure.h"
#include "tessera_text.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define NOMINMAX
#include <windows.h>
#include <direct.h>
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
#define TESSERA_TICKET_ROOM 4096u

#if defined(_WIN32)
#define TESSERA_DAEMON_SEPARATOR_TEXT "\\"
#else
#define TESSERA_DAEMON_SEPARATOR_TEXT "/"
#endif

_Alignas(8) static const char s_daemon_history_folder[] = "hst";
_Alignas(8) static const char s_daemon_history[] = "hst" TESSERA_DAEMON_SEPARATOR_TEXT "head.log";
_Alignas(8) static const char s_daemon_history_fresh[] = "hst" TESSERA_DAEMON_SEPARATOR_TEXT "tail.log";
_Alignas(8) static const char s_daemon_lock_file[] = "tessera.lock";
_Alignas(8) static const char s_daemon_identity[] = "identity ";
_Alignas(8) static const char s_daemon_pid[] = "\npid ";
_Alignas(8) static const char s_daemon_declared[] = "\ndeclared ";
_Alignas(8) static const char s_daemon_peak[] = "\npeak ";
_Alignas(8) static const char s_daemon_measured[] = "\nmeasured ";
_Alignas(8) static const char s_daemon_holding[] = "\nholding_microseconds ";
_Alignas(8) static const char s_daemon_sweep[] = "\nsweep_microseconds ";
_Alignas(8) static const char s_daemon_reason[] = "\nreason ";
_Alignas(8) static const char s_daemon_signum[] = "\nsignum ";
_Alignas(8) static const char s_daemon_precalc[] = "precalc kept\n";
_Alignas(8) static const char s_daemon_seal[] = "seal ";
_Alignas(8) static const char s_daemon_reason_held[] = "held past its holding time over its signum's last peak";
_Alignas(8) static const char s_daemon_reason_ended[] = "its process ended";
_Alignas(8) static const char s_daemon_reason_closed[] = "its connection closed";
_Alignas(8) static const char s_daemon_usage[] = "  tessera daemon: --device <32 hex digits> --luid <hex> --idle <microseconds>\n";
_Alignas(8) static const char s_daemon_no_state[] = "  tessera daemon: no state directory could be made for this device\n";
_Alignas(8) static const char s_daemon_long_socket[] = "  tessera daemon: the socket path is longer than a Unix socket holds: ";
_Alignas(8) static const char s_daemon_unbound[] = "  tessera daemon: this socket could not be bound: ";
_Alignas(8) static const char s_daemon_answered[] = "  tessera daemon: another daemon already answers at this socket: ";
_Alignas(8) static const char s_daemon_unmeasured[] = "  tessera daemon: the device's memory could not be measured by process (NVML, and under WDDM the GPU Process Memory counter)\n";
_Alignas(8) static const char s_daemon_history_bad[] = "  tessera daemon: the history did not read, or its seal did not hold: ";
_Alignas(8) static const char s_daemon_history_unsaved[] = "  tessera daemon: the history could not be sealed and saved in ";
#if defined(_WIN32)
_Alignas(8) static const char s_daemon_no_pipe[] = "  tessera daemon: the next pipe instance could not be made\n";
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
    char state[ENGINE_PATH_ROOM];
    char endpoint[ENGINE_PATH_ROOM];
    TesseraPeer *peers;
    unsigned long long peer_count;
    int socket_activated;
#if !defined(_WIN32)
    // the socket file this daemon bound; it removes that file and never one bound after it at the same path
    dev_t endpoint_device;
    ino_t endpoint_inode;
#endif
    int living;
} TesseraDaemon;

static TesseraDaemon s_daemon;

#if defined(_WIN32)
static SRWLOCK s_daemon_lock = SRWLOCK_INIT;
static CONDITION_VARIABLE s_daemon_changed = CONDITION_VARIABLE_INIT;
#else
static pthread_mutex_t s_daemon_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t s_daemon_changed;
#endif

static void daemon_lock(void)
{
#if defined(_WIN32)
    AcquireSRWLockExclusive(&s_daemon_lock);
#else
    pthread_mutex_lock(&s_daemon_lock);
#endif
}

static void daemon_unlock(void)
{
#if defined(_WIN32)
    ReleaseSRWLockExclusive(&s_daemon_lock);
#else
    pthread_mutex_unlock(&s_daemon_lock);
#endif
}

static void daemon_signal_changed(void)
{
#if defined(_WIN32)
    WakeAllConditionVariable(&s_daemon_changed);
#else
    pthread_cond_broadcast(&s_daemon_changed);
#endif
}

static unsigned long long daemon_now(void)
{
#if defined(_WIN32)
    LARGE_INTEGER counter;
    LARGE_INTEGER frequency;
    QueryPerformanceCounter(&counter);
    QueryPerformanceFrequency(&frequency);
    // a performance counter and its frequency are positive
    const unsigned long long ticks = (unsigned long long)counter.QuadPart;
    // a performance counter and its frequency are positive
    const unsigned long long rate = (unsigned long long)frequency.QuadPart;
    return ((ticks / rate) * TESSERA_DAEMON_MILLION) + (((ticks % rate) * TESSERA_DAEMON_MILLION) / rate);
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    // a monotonic clock's seconds and nanoseconds are not negative
    return ((unsigned long long)now.tv_sec * TESSERA_DAEMON_MILLION) + ((unsigned long long)now.tv_nsec / 1000ull);
#endif
}

static unsigned long long daemon_wall(void)
{
#if defined(_WIN32)
    FILETIME now;
    GetSystemTimeAsFileTime(&now);
    return ((((unsigned long long)now.dwHighDateTime) << 32u) | now.dwLowDateTime) / 10ull;
#else
    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    // a wall clock after the epoch has seconds and nanoseconds that are not negative
    return ((unsigned long long)now.tv_sec * TESSERA_DAEMON_MILLION) + ((unsigned long long)now.tv_nsec / 1000ull);
#endif
}

static void daemon_wait_until(unsigned long long when)
{
#if defined(_WIN32)
    DWORD milliseconds = INFINITE;
    if (when != TESSERA_DAEMON_FOREVER)
    {
        const unsigned long long now = daemon_now();
        const unsigned long long remaining = (when > now) ? (when - now) : 0ull;
        const unsigned long long whole = (remaining + 999ull) / 1000ull;
        // a wait below INFINITE fits a DWORD
        milliseconds = (whole < (unsigned long long)INFINITE) ? (DWORD)whole : (INFINITE - 1u);
    }
    SleepConditionVariableSRW(&s_daemon_changed, &s_daemon_lock, milliseconds, 0u);
#else
    if (when == TESSERA_DAEMON_FOREVER)
    {
        pthread_cond_wait(&s_daemon_changed, &s_daemon_lock);
        return;
    }
    struct timespec until;
    // a monotonic time in seconds fits a time_t
    until.tv_sec = (time_t)(when / TESSERA_DAEMON_MILLION);
    // a remainder below a million microseconds is below a billion nanoseconds
    until.tv_nsec = (long)((when % TESSERA_DAEMON_MILLION) * 1000ull);
    pthread_cond_timedwait(&s_daemon_changed, &s_daemon_lock, &until);
#endif
}

static int daemon_directories_make(const char *path)
{
    char walk[ENGINE_PATH_ROOM];
    const size_t length = strlen(path);
    if (length >= sizeof(walk))
    {
        return 0;
    }
    memcpy(walk, path, length + 1u);
    for (size_t at = 1u; at <= length; at += 1u)
    {
        const int separator = (walk[at] == '/') || (walk[at] == '\\') || (walk[at] == '\0');
        if (!separator || (walk[at - 1u] == ':'))
        {
            continue;
        }
        const char kept = walk[at];
        walk[at] = '\0';
#if defined(_WIN32)
        const int made = (_mkdir(walk) == 0) || (errno == EEXIST);
#else
        const int made = (mkdir(walk, 0700) == 0) || (errno == EEXIST);
#endif
        walk[at] = kept;
        if (!made)
        {
            return 0;
        }
    }
    return 1;
}

static int daemon_state_file(const char *name, char *path)
{
    const int written = snprintf(path, ENGINE_PATH_ROOM, "%s%s%s", s_daemon.state, TESSERA_DAEMON_SEPARATOR_TEXT, name);
    // a non-negative length is compared whole against the room
    return (written >= 0) && ((unsigned int)written < ENGINE_PATH_ROOM);
}

static void daemon_put_long(unsigned char *bytes, unsigned long long value)
{
    for (unsigned int byte = 0u; byte < 8u; byte += 1u)
    {
        // one byte of the long, taken from the bottom
        bytes[byte] = (unsigned char)((value >> (8u * byte)) & 0xFFull);
    }
}

static unsigned long long daemon_get_long(const unsigned char *bytes)
{
    unsigned long long value = 0ull;
    for (unsigned int byte = 0u; byte < 8u; byte += 1u)
    {
        value |= (unsigned long long)bytes[byte] << (8u * byte);
    }
    return value;
}

static int daemon_history_load(void)
{
    char path[ENGINE_PATH_ROOM];
    if (!daemon_state_file(s_daemon_history, path))
    {
        return 0;
    }
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return 1;
    }
    // the file is its whole records, then the seal over them; any other length is a broken history
    int held = fseek(file, 0L, SEEK_END) == 0;
    const long length = held ? ftell(file) : -1L;
    held = held && (length >= (long)OBSIGNATIO_SIGNUM_BYTES)
           && ((((unsigned long long)length - OBSIGNATIO_SIGNUM_BYTES) % TESSERA_HISTORY_RECORD) == 0ull)
           && (fseek(file, 0L, SEEK_SET) == 0);
    // a length checked non-negative above is the file's byte count
    const unsigned long long total = held ? (unsigned long long)length : 0ull;
    unsigned char *const bytes = held ? (unsigned char *)malloc((size_t)total) : NULL;
    held = held && (bytes != NULL) && (fread(bytes, 1u, (size_t)total, file) == (size_t)total);
    fclose(file);
    const unsigned long long sealed = total - OBSIGNATIO_SIGNUM_BYTES;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const ObsignatioSealRequest seal = {bytes, sealed, (bytes != NULL) ? bytes + sealed : NULL, &error};
    held = held && (obsignatio_seal_holds(&seal) == 1L);
    for (unsigned long long at = 0ull; held && (at < sealed); at += TESSERA_HISTORY_RECORD)
    {
        TesseraHistory kept;
        memcpy(kept.signum.bytes, bytes + at, ENGINE_SIGNUM_BYTES);
        kept.peak = daemon_get_long(bytes + at + ENGINE_SIGNUM_BYTES);
        kept.duration = daemon_get_long(bytes + at + ENGINE_SIGNUM_BYTES + 8u);
        held = tessera_ledger_remember(&s_daemon.ledger, &kept);
    }
    free(bytes);
    if (!held)
    {
        fprintf(stderr, "%s%s\n", s_daemon_history_bad, path);
    }
    return held;
}

static int daemon_history_save(void)
{
    char path[ENGINE_PATH_ROOM];
    char fresh[ENGINE_PATH_ROOM];
    if (!daemon_state_file(s_daemon_history, path) || !daemon_state_file(s_daemon_history_fresh, fresh))
    {
        return 0;
    }
    // every record, then the seal over them all; a history that is not saved is said so, never dropped silently
    const unsigned long long sealed = s_daemon.ledger.history_count * TESSERA_HISTORY_RECORD;
    const unsigned long long total = sealed + OBSIGNATIO_SIGNUM_BYTES;
    unsigned char *const bytes = (unsigned char *)malloc((size_t)total);
    if (bytes == NULL)
    {
        fprintf(stderr, "%s%s\n", s_daemon_history_unsaved, path);
        return 0;
    }
    for (unsigned long long at = 0ull; at < s_daemon.ledger.history_count; at += 1ull)
    {
        const TesseraHistory *const kept = &s_daemon.ledger.history[at];
        unsigned char *const record = bytes + (at * TESSERA_HISTORY_RECORD);
        memcpy(record, kept->signum.bytes, ENGINE_SIGNUM_BYTES);
        daemon_put_long(record + ENGINE_SIGNUM_BYTES, kept->peak);
        daemon_put_long(record + ENGINE_SIGNUM_BYTES + 8u, kept->duration);
    }
    EngineError error;
    memset(&error, 0, sizeof(error));
    const ObsignatioSealRequest seal = {bytes, sealed, bytes + sealed, &error};
    int held = obsignatio_seal(&seal) == 0L;
    FILE *const file = held ? fopen(fresh, "wb") : NULL;
    held = held && (file != NULL) && (fwrite(bytes, 1u, (size_t)total, file) == (size_t)total);
    held = (file != NULL) && (fclose(file) == 0) && held;
    free(bytes);
#if defined(_WIN32)
    held = held && (MoveFileExA(fresh, path, MOVEFILE_REPLACE_EXISTING) != 0);
#else
    held = held && (rename(fresh, path) == 0);
#endif
    if (!held)
    {
        fprintf(stderr, "%s%s\n", s_daemon_history_unsaved, path);
    }
    return held;
}

static int daemon_ticket_seal_append(const char *path, const char *text, unsigned long long length)
{
    // one block of lost and found: its text, then a last line sealing every byte of the block above it
    static const char s_hex[] = "0123456789abcdef";
    unsigned char signum[OBSIGNATIO_SIGNUM_BYTES];
    EngineError error;
    memset(&error, 0, sizeof(error));
    const ObsignatioSealRequest seal = {(const unsigned char *)text, length, signum, &error};
    if (obsignatio_seal(&seal) != 0L)
    {
        return 0;
    }
    char line[(2u * OBSIGNATIO_SIGNUM_BYTES) + 1u];
    for (unsigned int byte = 0u; byte < OBSIGNATIO_SIGNUM_BYTES; byte += 1u)
    {
        line[2u * byte] = s_hex[signum[byte] >> 4u];
        line[(2u * byte) + 1u] = s_hex[signum[byte] & 0x0Fu];
    }
    line[2u * OBSIGNATIO_SIGNUM_BYTES] = '\0';
    FILE *const file = fopen(path, "ab");
    if (file == NULL)
    {
        return 0;
    }
    const int printed = (fwrite(text, 1u, (size_t)length, file) == (size_t)length)
                        && (fprintf(file, "%s%s\n", s_daemon_seal, line) > 0);
    return (fclose(file) == 0) && printed;
}

static int daemon_ticket_write(unsigned long long identity, const TesseraPeer *peer, unsigned long long peak,
                               unsigned long long measured, const char *reason)
{
    char path[ENGINE_PATH_ROOM];
    char text[TESSERA_TICKET_ROOM];
    if (!tessera_path_lost(s_daemon.device, path, ENGINE_PATH_ROOM))
    {
        return 0;
    }
    // the ticket names its job's signum whole; a lost job is found again by its request
    char signum[(2u * ENGINE_SIGNUM_BYTES) + 1u];
    for (unsigned int byte = 0u; byte < ENGINE_SIGNUM_BYTES; byte += 1u)
    {
        snprintf(signum + (2u * byte), 3u, "%02x", peer->signum.bytes[byte]);
    }
    const int written = snprintf(text, sizeof(text), "%s%016llx%s%s%s%llu%s%llu%s%llu%s%llu%s%llu%s%llu%s%s\n",
                                 s_daemon_identity, identity, s_daemon_signum, signum, s_daemon_pid, peer->pid,
                                 s_daemon_declared, peer->declared, s_daemon_peak, peak, s_daemon_measured, measured,
                                 s_daemon_holding, peer->holding_microseconds, s_daemon_sweep, peer->sweep_microseconds,
                                 s_daemon_reason, reason);
    // a non-negative length is compared whole against the room
    return (written >= 0) && ((unsigned int)written < TESSERA_TICKET_ROOM)
           && daemon_ticket_seal_append(path, text, (unsigned long long)written);
}

static int daemon_seal_line_read(const char *line, unsigned char signum[OBSIGNATIO_SIGNUM_BYTES])
{
    // a seal line is "seal ", 64 lower hex digits and a newline
    if (memcmp(line, s_daemon_seal, sizeof(s_daemon_seal) - 1u) != 0)
    {
        return 0;
    }
    const char *const digits = line + (sizeof(s_daemon_seal) - 1u);
    for (unsigned int byte = 0u; byte < OBSIGNATIO_SIGNUM_BYTES; byte += 1u)
    {
        unsigned int value = 0u;
        for (unsigned int digit = 0u; digit < 2u; digit += 1u)
        {
            const char glyph = digits[(2u * byte) + digit];
            const int decimal = (glyph >= '0') && (glyph <= '9');
            const int letter = (glyph >= 'a') && (glyph <= 'f');
            if (!decimal && !letter)
            {
                return 0;
            }
            // a checked hex digit is one nibble
            value = (value << 4u) | (unsigned int)(decimal ? (glyph - '0') : (glyph - 'a' + 10));
        }
        // two nibbles are one byte
        signum[byte] = (unsigned char)value;
    }
    return digits[2u * OBSIGNATIO_SIGNUM_BYTES] == '\n';
}

static int daemon_ticket_note(unsigned long long identity, const char *note)
{
    // the note goes in only after a ticket of this identity whose seal holds, as its own sealed block
    char path[ENGINE_PATH_ROOM];
    if (!tessera_path_lost(s_daemon.device, path, ENGINE_PATH_ROOM))
    {
        return 0;
    }
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return 0;
    }
    int held = fseek(file, 0L, SEEK_END) == 0;
    const long length = held ? ftell(file) : -1L;
    held = held && (length > 0L) && (fseek(file, 0L, SEEK_SET) == 0);
    // a length checked positive above is the log's byte count
    const size_t total = held ? (size_t)length : 0u;
    char *const text = held ? (char *)malloc(total + 1u) : NULL;
    held = held && (text != NULL) && (fread(text, 1u, total, file) == total);
    fclose(file);
    char named[sizeof(s_daemon_identity) + 17u];
    snprintf(named, sizeof(named), "%s%016llx\n", s_daemon_identity, identity);
    const size_t seal_line = (sizeof(s_daemon_seal) - 1u) + (2u * OBSIGNATIO_SIGNUM_BYTES) + 1u;
    int found = 0;
    size_t block = 0u;
    for (size_t at = 0u; held && ((at + seal_line) <= total); at += 1u)
    {
        unsigned char signum[OBSIGNATIO_SIGNUM_BYTES];
        const int line_start = (at == 0u) || (text[at - 1u] == '\n');
        if (!line_start || !daemon_seal_line_read(text + at, signum))
        {
            continue;
        }
        EngineError error;
        memset(&error, 0, sizeof(error));
        const ObsignatioSealRequest seal = {(const unsigned char *)text + block, at - block, signum, &error};
        const int ours = ((at - block) >= strlen(named)) && (memcmp(text + block, named, strlen(named)) == 0);
        found = (ours && (obsignatio_seal_holds(&seal) == 1L)) ? 1 : found;
        block = at + seal_line;
        at = block - 1u;
    }
    free(text);
    char added[TESSERA_TICKET_ROOM];
    const int written = snprintf(added, sizeof(added), "%s%s", named, note);
    // a non-negative length is compared whole against the room
    return found && (written >= 0) && ((unsigned int)written < TESSERA_TICKET_ROOM)
           && daemon_ticket_seal_append(path, added, (unsigned long long)written);
}

static void daemon_frame_start(TesseraFrame *frame, unsigned int kind, unsigned long long identity)
{
    memset(frame, 0, sizeof(*frame));
    frame->magic = TESSERA_MAGIC;
    frame->version = TESSERA_VERSION;
    frame->kind = kind;
    memcpy(frame->device, s_daemon.device, TESSERA_DEVICE_BYTES);
    frame->identity = identity;
    frame->luid = s_daemon.luid;
}

static void daemon_peer_wake(TesseraPeer *peer)
{
#if defined(_WIN32)
    SetEvent(peer->wake);
#else
    const char byte = 1;
    const ssize_t woken = write(peer->wake[1], &byte, 1u);
    (void)woken;
#endif
}

static void daemon_post(TesseraPeer *peer, unsigned int kind, unsigned long long identity, unsigned long long bytes,
                        unsigned long long measured)
{
    daemon_frame_start(&peer->decisive, kind, identity);
    peer->decisive.signum = peer->signum;
    peer->decisive.bytes = bytes;
    peer->decisive.measured = measured;
    peer->has_decisive = 1;
    daemon_peer_wake(peer);
}

static TesseraPeer *daemon_peer_of(unsigned long long identity)
{
    for (TesseraPeer *peer = s_daemon.peers; peer != NULL; peer = peer->next)
    {
        if ((identity != 0ull) && (peer->identity == identity))
        {
            return peer;
        }
    }
    return NULL;
}

static void daemon_device_read(void)
{
    unsigned long long capacity = 0ull;
    unsigned long long in_use = 0ull;
    if (tessera_measure_device(s_daemon.measure, &capacity, &in_use))
    {
        tessera_ledger_device(&s_daemon.ledger, capacity, in_use);
    }
}

static void daemon_admit(unsigned long long now)
{
    daemon_device_read();
    const unsigned long long room = s_daemon.ledger.job_count;
    if (room == 0ull)
    {
        return;
    }
    TesseraEvent *const events = (TesseraEvent *)calloc((size_t)room, sizeof(TesseraEvent));
    if (events == NULL)
    {
        return;
    }
    const unsigned long long made = tessera_ledger_admit(&s_daemon.ledger, now, events, room);
    for (unsigned long long at = 0ull; at < made; at += 1ull)
    {
        TesseraPeer *const peer = daemon_peer_of(events[at].identity);
        if (peer != NULL)
        {
            daemon_post(peer, TESSERA_TELL_ADMITTED, events[at].identity, events[at].bytes, events[at].measured);
        }
    }
    free(events);
    daemon_signal_changed();
}

static void daemon_job_dropped(TesseraPeer *peer, unsigned long long now, const char *reason)
{
    const TesseraJob *const job = tessera_ledger_job(&s_daemon.ledger, peer->identity);
    if (job == NULL)
    {
        return;
    }
    daemon_ticket_write(peer->identity, peer, job->peak, job->used, reason);
    tessera_ledger_release(&s_daemon.ledger, peer->identity, now, 0);
    peer->identity = 0ull;
    daemon_admit(now);
}

static void daemon_handle(TesseraPeer *peer, const TesseraFrame *frame)
{
    const unsigned long long now = daemon_now();
    if (frame->kind == TESSERA_ASK_SUBMIT)
    {
        const int acceptable = (peer->identity == 0ull) && (peer->lost_identity == 0ull)
                            && (memcmp(frame->device, s_daemon.device, TESSERA_DEVICE_BYTES) == 0)
                            && (frame->luid == s_daemon.luid) && (frame->declared != 0ull)
                            && (frame->sweep_microseconds != 0ull);
        TesseraJobRequest request;
        request.signum = frame->signum;
        request.declared = frame->declared;
        request.holding_microseconds = frame->holding_microseconds;
        request.sweep_microseconds = frame->sweep_microseconds;
        request.idle_microseconds = frame->idle_microseconds;
        request.override_budget = frame->override_budget;
        unsigned long long identity = 0ull;
        TesseraEvent event;
        if (!acceptable || !tessera_ledger_submit(&s_daemon.ledger, &request, now, &identity, &event))
        {
            daemon_post(peer, TESSERA_TELL_REFUSED, 0ull, frame->declared, 0ull);
            return;
        }
        peer->identity = identity;
        peer->signum = frame->signum;
        peer->declared = frame->declared;
        peer->holding_microseconds = frame->holding_microseconds;
        peer->sweep_microseconds = frame->sweep_microseconds;
        if (event.kind == TESSERA_EVENT_ASKED)
        {
            daemon_post(peer, TESSERA_TELL_ASKED, identity, event.bytes, event.measured);
        }
        daemon_admit(now);
        return;
    }
    if ((frame->kind == TESSERA_ASK_OVERRIDE) && (frame->identity == peer->identity)
        && tessera_ledger_override(&s_daemon.ledger, peer->identity, now))
    {
        daemon_admit(now);
        return;
    }
    if ((frame->kind == TESSERA_ASK_RELEASE) && (frame->identity == peer->identity) && (peer->identity != 0ull))
    {
        const TesseraJob *const job = tessera_ledger_job(&s_daemon.ledger, peer->identity);
        const unsigned long long reservation = (job != NULL) ? job->reservation : 0ull;
        const unsigned long long peak = (job != NULL) ? job->peak : 0ull;
        if ((job != NULL) && tessera_ledger_release(&s_daemon.ledger, peer->identity, now, 1))
        {
            daemon_history_save();
            daemon_post(peer, TESSERA_TELL_RELEASED, peer->identity, reservation, peak);
            peer->identity = 0ull;
            daemon_admit(now);
            return;
        }
    }
    if (frame->kind == TESSERA_ASK_MEASURED)
    {
        // a process's own report stands for its measure only where no pid is read from outside; it gets no answer
        TesseraEvent grew;
        if (tessera_measure_reported(s_daemon.measure) && (frame->identity == peer->identity) && (peer->identity != 0ull)
            && tessera_ledger_measure(&s_daemon.ledger, peer->identity, frame->measured, &grew)
            && (grew.kind == TESSERA_EVENT_GREW))
        {
            peer->grew_to = grew.measured;
            peer->has_grew = 1;
            daemon_peer_wake(peer);
        }
        daemon_admit(now);
        return;
    }
    if ((frame->kind == TESSERA_ASK_PRECALC_KEPT) && (peer->lost_identity != 0ull)
        && daemon_ticket_note(peer->lost_identity, s_daemon_precalc))
    {
        daemon_post(peer, TESSERA_TELL_RELEASED, peer->lost_identity, 0ull, 0ull);
        peer->lost_identity = 0ull;
        return;
    }
    daemon_post(peer, TESSERA_TELL_REFUSED, frame->identity, 0ull, 0ull);
}

static void daemon_fired(const TesseraEvent *event, unsigned long long now)
{
    if (event->kind == TESSERA_EVENT_IDLE)
    {
        if (s_daemon.peer_count == 0ull)
        {
            daemon_history_save();
#if !defined(_WIN32)
            struct stat endpoint;
            const int ours = !s_daemon.socket_activated && (stat(s_daemon.endpoint, &endpoint) == 0)
                          && (endpoint.st_dev == s_daemon.endpoint_device) && (endpoint.st_ino == s_daemon.endpoint_inode);
            if (ours)
            {
                unlink(s_daemon.endpoint);
            }
#endif
            exit(0);
        }
        return;
    }
    TesseraPeer *const peer = daemon_peer_of(event->identity);
    if (peer == NULL)
    {
        return;
    }
    if (event->kind == TESSERA_EVENT_LOST)
    {
        const TesseraHistory *const past = tessera_ledger_history(&s_daemon.ledger, &peer->signum);
        const unsigned long long last_peak = (past != NULL) ? past->peak : 0ull;
        daemon_ticket_write(peer->identity, peer, last_peak, 0ull, s_daemon_reason_held);
        daemon_post(peer, TESSERA_TELL_LOST, peer->identity, peer->declared, last_peak);
        peer->lost_identity = peer->identity;
        peer->identity = 0ull;
        daemon_admit(now);
        return;
    }
    if (event->kind == TESSERA_EVENT_SWEEP)
    {
        if (!tessera_process_lives(peer->process))
        {
            daemon_job_dropped(peer, now, s_daemon_reason_ended);
            return;
        }
        unsigned long long used = 0ull;
        TesseraEvent grew;
        if (tessera_measure_process(s_daemon.measure, peer->pid, &used)
            && tessera_ledger_measure(&s_daemon.ledger, peer->identity, used, &grew) && (grew.kind == TESSERA_EVENT_GREW))
        {
            peer->grew_to = grew.measured;
            peer->has_grew = 1;
            daemon_peer_wake(peer);
        }
        daemon_admit(now);
    }
}

#if defined(_WIN32)
static DWORD WINAPI daemon_timer(LPVOID unused)
#else
static void *daemon_timer(void *unused)
#endif
{
    (void)unused;
    daemon_lock();
    // the daemon's life: the idle teardown in daemon_fired ends the process from inside this loop
    while (s_daemon.living)
    {
        TesseraDeadline root;
        const int any = tessera_ledger_next(&s_daemon.ledger, &root);
        const unsigned long long now = daemon_now();
        if (!any || (root.when > now))
        {
            daemon_wait_until(any ? root.when : TESSERA_DAEMON_FOREVER);
            continue;
        }
        TesseraEvent event;
        while (tessera_ledger_fire(&s_daemon.ledger, now, &event))
        {
            daemon_fired(&event, now);
        }
    }
    daemon_unlock();
#if defined(_WIN32)
    return 0u;
#else
    return NULL;
#endif
}

static int daemon_write(TesseraPeer *peer, const TesseraFrame *frame)
{
    unsigned char bytes[TESSERA_FRAME_BYTES];
    if (!tessera_frame_pack(frame, bytes))
    {
        return 0;
    }
#if defined(_WIN32)
    OVERLAPPED writing;
    memset(&writing, 0, sizeof(writing));
    writing.hEvent = CreateEventA(NULL, TRUE, FALSE, NULL);
    if (writing.hEvent == NULL)
    {
        return 0;
    }
    DWORD moved = 0u;
    const int started = WriteFile(peer->pipe, bytes, TESSERA_FRAME_BYTES, NULL, &writing) || (GetLastError() == ERROR_IO_PENDING);
    const int done = started && GetOverlappedResult(peer->pipe, &writing, &moved, TRUE) && (moved == TESSERA_FRAME_BYTES);
    CloseHandle(writing.hEvent);
    return done;
#else
    unsigned int sent = 0u;
    while (sent < TESSERA_FRAME_BYTES)
    {
        const ssize_t moved = send(peer->socket_descriptor, bytes + sent, TESSERA_FRAME_BYTES - sent, MSG_NOSIGNAL);
        if ((moved < 0) && (errno == EINTR))
        {
            continue;
        }
        if (moved <= 0)
        {
            return 0;
        }
        // a count of bytes moved is positive and at most one frame
        sent += (unsigned int)moved;
    }
    return 1;
#endif
}

static int daemon_deliver(TesseraPeer *peer)
{
    daemon_lock();
    const int has_grew = peer->has_grew;
    const int has_decisive = peer->has_decisive;
    TesseraFrame grew;
    daemon_frame_start(&grew, TESSERA_TELL_GREW, peer->identity);
    grew.signum = peer->signum;
    grew.bytes = peer->declared;
    grew.measured = peer->grew_to;
    const TesseraFrame decisive = peer->decisive;
    peer->has_grew = 0;
    peer->has_decisive = 0;
    daemon_unlock();
    return (!has_grew || daemon_write(peer, &grew)) && (!has_decisive || daemon_write(peer, &decisive));
}

static void daemon_peer_gone(TesseraPeer *peer)
{
    daemon_lock();
    const unsigned long long now = daemon_now();
    if (peer->identity != 0ull)
    {
        daemon_job_dropped(peer, now, s_daemon_reason_closed);
    }
    TesseraPeer **link = &s_daemon.peers;
    while ((*link != NULL) && (*link != peer))
    {
        link = &(*link)->next;
    }
    if (*link == peer)
    {
        *link = peer->next;
    }
    s_daemon.peer_count -= 1ull;
    if ((s_daemon.peer_count == 0ull) && (s_daemon.ledger.job_count == 0ull))
    {
        tessera_ledger_idle(&s_daemon.ledger, now, s_daemon.ledger.idle_microseconds);
        daemon_signal_changed();
    }
    daemon_unlock();
    tessera_process_release(peer->process);
#if defined(_WIN32)
    DisconnectNamedPipe(peer->pipe);
    CloseHandle(peer->pipe);
    CloseHandle(peer->wake);
#else
    close(peer->socket_descriptor);
    close(peer->wake[0]);
    close(peer->wake[1]);
#endif
    free(peer);
}

static void daemon_frame_arrived(TesseraPeer *peer, const unsigned char bytes[TESSERA_FRAME_BYTES], int *open)
{
    TesseraFrame frame;
    if (!tessera_frame_unpack(bytes, &frame))
    {
        *open = 0;
        return;
    }
    daemon_lock();
    daemon_handle(peer, &frame);
    daemon_unlock();
}

#if defined(_WIN32)
static DWORD WINAPI daemon_peer(LPVOID argument)
{
    TesseraPeer *const peer = (TesseraPeer *)argument;
    OVERLAPPED reading;
    memset(&reading, 0, sizeof(reading));
    reading.hEvent = CreateEventA(NULL, TRUE, FALSE, NULL);
    unsigned char bytes[TESSERA_FRAME_BYTES];
    unsigned int got = 0u;
    int pending = 0;
    int open = reading.hEvent != NULL;
    while (open)
    {
        if (!pending)
        {
            ResetEvent(reading.hEvent);
            const int started = ReadFile(peer->pipe, bytes + got, TESSERA_FRAME_BYTES - got, NULL, &reading)
                             || (GetLastError() == ERROR_IO_PENDING);
            if (!started)
            {
                break;
            }
            pending = 1;
        }
        const HANDLE waits[2] = {reading.hEvent, peer->wake};
        const DWORD which = WaitForMultipleObjects(2u, waits, FALSE, INFINITE);
        if (which == (WAIT_OBJECT_0 + 1u))
        {
            open = daemon_deliver(peer);
            continue;
        }
        DWORD moved = 0u;
        if ((which != WAIT_OBJECT_0) || !GetOverlappedResult(peer->pipe, &reading, &moved, FALSE) || (moved == 0u))
        {
            break;
        }
        pending = 0;
        got += moved;
        if (got == TESSERA_FRAME_BYTES)
        {
            got = 0u;
            daemon_frame_arrived(peer, bytes, &open);
        }
    }
    if (pending)
    {
        CancelIoEx(peer->pipe, &reading);
        DWORD moved = 0u;
        GetOverlappedResult(peer->pipe, &reading, &moved, TRUE);
    }
    if (reading.hEvent != NULL)
    {
        CloseHandle(reading.hEvent);
    }
    daemon_peer_gone(peer);
    return 0u;
}
#else
static void *daemon_peer(void *argument)
{
    TesseraPeer *const peer = (TesseraPeer *)argument;
    unsigned char bytes[TESSERA_FRAME_BYTES];
    unsigned int got = 0u;
    int open = 1;
    while (open)
    {
        struct pollfd watch[2];
        watch[0].fd = peer->socket_descriptor;
        watch[0].events = POLLIN;
        watch[0].revents = 0;
        watch[1].fd = peer->wake[0];
        watch[1].events = POLLIN;
        watch[1].revents = 0;
        if (poll(watch, 2u, -1) < 0)
        {
            open = errno == EINTR;
            continue;
        }
        if (watch[1].revents != 0)
        {
            char drained[TESSERA_FRAME_BYTES];
            while (read(peer->wake[0], drained, sizeof(drained)) > 0)
            {
            }
            open = daemon_deliver(peer);
        }
        if (open && (watch[0].revents != 0))
        {
            const ssize_t moved = read(peer->socket_descriptor, bytes + got, TESSERA_FRAME_BYTES - got);
            if (moved <= 0)
            {
                open = (moved < 0) && (errno == EINTR);
                continue;
            }
            // a count of bytes moved is positive and at most one frame
            got += (unsigned int)moved;
            if (got == TESSERA_FRAME_BYTES)
            {
                got = 0u;
                daemon_frame_arrived(peer, bytes, &open);
            }
        }
    }
    daemon_peer_gone(peer);
    return NULL;
}
#endif

static int daemon_peer_start(TesseraPeer *peer, unsigned long long pid)
{
    peer->pid = pid;
    peer->process = tessera_process_hold(pid);
    if (peer->process == NULL)
    {
        return 0;
    }
    daemon_lock();
    peer->next = s_daemon.peers;
    s_daemon.peers = peer;
    s_daemon.peer_count += 1ull;
    daemon_unlock();
#if defined(_WIN32)
    const HANDLE thread = CreateThread(NULL, 0u, daemon_peer, peer, 0u, NULL);
    if (thread == NULL)
    {
        return 0;
    }
    CloseHandle(thread);
    return 1;
#else
    pthread_t thread;
    if (pthread_create(&thread, NULL, daemon_peer, peer) != 0)
    {
        return 0;
    }
    pthread_detach(thread);
    return 1;
#endif
}

static int daemon_hex(const char *text, unsigned char *bytes, unsigned int count)
{
    if (strlen(text) != (2u * count))
    {
        return 0;
    }
    for (unsigned int byte = 0u; byte < count; byte += 1u)
    {
        unsigned int value = 0u;
        for (unsigned int half = 0u; half < 2u; half += 1u)
        {
            const char digit = text[(2u * byte) + half];
            const int decimal = (digit >= '0') && (digit <= '9');
            const int lower = (digit >= 'a') && (digit <= 'f');
            if (!decimal && !lower)
            {
                return 0;
            }
            // a hexadecimal digit's value is below sixteen
            value = (value << 4u) | (decimal ? (unsigned int)(digit - '0') : (unsigned int)(digit - 'a' + 10));
        }
        // two hexadecimal digits make one byte
        bytes[byte] = (unsigned char)value;
    }
    return 1;
}

static int daemon_arguments(int count, char **arguments, unsigned long long *idle)
{
    int have_device = 0;
    int have_luid = 0;
    int have_idle = 0;
    for (int at = 1; (at + 1) < count; at += 2)
    {
        char *end = NULL;
        if (strcmp(arguments[at], "--device") == 0)
        {
            have_device = daemon_hex(arguments[at + 1], s_daemon.device, TESSERA_DEVICE_BYTES);
        }
        else if (strcmp(arguments[at], "--luid") == 0)
        {
            s_daemon.luid = strtoull(arguments[at + 1], &end, 16);
            have_luid = (end != arguments[at + 1]) && (*end == '\0');
        }
        else if (strcmp(arguments[at], "--idle") == 0)
        {
            *idle = strtoull(arguments[at + 1], &end, 10);
            have_idle = (end != arguments[at + 1]) && (*end == '\0');
        }
        else
        {
            return 0;
        }
    }
    return have_device && have_luid && have_idle;
}

static int daemon_socket_handed(void)
{
#if defined(_WIN32)
    return 0;
#else
    // systemd hands one listening socket over as fd 3 and names this process as its receiver
    const char *const listen_pid = getenv("LISTEN_PID");
    const char *const listen_fds = getenv("LISTEN_FDS");
    return (listen_pid != NULL) && (listen_fds != NULL) && (strtoull(listen_pid, NULL, 10) == (unsigned long long)getpid())
        && (strcmp(listen_fds, "1") == 0);
#endif
}

static int daemon_refused(void)
{
#if !defined(_WIN32)
    // the connections that made systemd start this daemon wait on its socket: each is closed unanswered; its
    // client is refused and systemd has none left to start the daemon again for
    if (daemon_socket_handed())
    {
        const int flags = fcntl(3, F_GETFL);
        fcntl(3, F_SETFL, flags | O_NONBLOCK);
        for (int waiting = accept(3, NULL, NULL); waiting >= 0; waiting = accept(3, NULL, NULL))
        {
            close(waiting);
        }
    }
#endif
    return 1;
}

int main(int count, char **arguments)
{
    unsigned long long idle = 0ull;
    if (!daemon_arguments(count, arguments, &idle))
    {
        fputs(s_daemon_usage, stderr);
        return 2;
    }
    char history_folder[ENGINE_PATH_ROOM];
    if (!tessera_path_state(s_daemon.device, s_daemon.state, ENGINE_PATH_ROOM)
        || !daemon_state_file(s_daemon_history_folder, history_folder) || !daemon_directories_make(history_folder)
        || !tessera_path_endpoint(s_daemon.device, s_daemon.endpoint, ENGINE_PATH_ROOM))
    {
        fputs(s_daemon_no_state, stderr);
        return daemon_refused();
    }
    // the history is read before the endpoint exists; no client reaches a daemon that then refuses its history
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
    HANDLE listening = CreateNamedPipeA(s_daemon.endpoint,
                                        PIPE_ACCESS_DUPLEX | FILE_FLAG_OVERLAPPED | FILE_FLAG_FIRST_PIPE_INSTANCE,
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
    char lock_path[ENGINE_PATH_ROOM];
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
        if ((listening < 0) || (bind(listening, (const struct sockaddr *)&address, sizeof(address)) != 0)
            || (listen(listening, SOMAXCONN) != 0) || (stat(s_daemon.endpoint, &endpoint) != 0))
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
        fputs(s_daemon_unmeasured, stderr);
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
        const int connected = (connecting.hEvent != NULL)
                           && (ConnectNamedPipe(listening, &connecting) || (GetLastError() == ERROR_PIPE_CONNECTED)
                               || ((GetLastError() == ERROR_IO_PENDING)
                                   && GetOverlappedResult(listening, &connecting, &moved, TRUE)));
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
        const int named = (peer != NULL)
                       && (getsockopt(accepted, SOL_SOCKET, SO_PEERCRED, &credentials, &length) == 0)
                       && (pipe(peer->wake) == 0);
        if (named)
        {
            peer->socket_descriptor = accepted;
            fcntl(peer->wake[0], F_SETFL, O_NONBLOCK);
            fcntl(peer->wake[1], F_SETFL, O_NONBLOCK);
        }
        // a peer's pid is positive, held whole in an unsigned long long
        if (!named || !daemon_peer_start(peer, (unsigned long long)credentials.pid))
        {
            close(accepted);
            free(peer);
        }
    }
#endif
}
