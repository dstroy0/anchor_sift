// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tessera_daemon_state.c: the daemon's lock, clocks, state file, history and tickets
#include "tessera_daemon_internal.h"

_Alignas(8) static const char s_daemon_history[] = "history";
_Alignas(8) static const char s_daemon_history_fresh[] = "history.fresh";
_Alignas(8) static const char s_daemon_ticket[] = "ticket";
_Alignas(8) static const char s_daemon_identity[] = "identity ";
_Alignas(8) static const char s_daemon_pid[] = "\npid ";
_Alignas(8) static const char s_daemon_declared[] = "\ndeclared ";
_Alignas(8) static const char s_daemon_peak[] = "\npeak ";
_Alignas(8) static const char s_daemon_measured[] = "\nmeasured ";
_Alignas(8) static const char s_daemon_holding[] = "\nholding_microseconds ";
_Alignas(8) static const char s_daemon_sweep[] = "\nsweep_microseconds ";
_Alignas(8) static const char s_daemon_reason[] = "\nreason ";
_Alignas(8) static const char s_daemon_signum[] = "\nsignum ";
_Alignas(8) static const char s_daemon_seal[] = "seal ";
_Alignas(8) static const
    char s_daemon_history_bad[] = "  tessera daemon: the history did not read, or its seal did not hold: ";
_Alignas(8) static const
    char s_daemon_history_unsaved[] = "  tessera daemon: the history could not be sealed and saved in ";

TesseraDaemon g_daemon;
#if (defined(_WIN32))
static SRWLOCK s_daemon_lock = SRWLOCK_INIT;
CONDITION_VARIABLE g_daemon_changed = CONDITION_VARIABLE_INIT;
#endif
#if !(defined(_WIN32))
static pthread_mutex_t s_daemon_lock = PTHREAD_MUTEX_INITIALIZER;
pthread_cond_t g_daemon_changed;
#endif

void daemon_lock(void)
{
#if defined(_WIN32)
    AcquireSRWLockExclusive(&s_daemon_lock);
#else
    pthread_mutex_lock(&s_daemon_lock);
#endif
}

void daemon_unlock(void)
{
#if defined(_WIN32)
    ReleaseSRWLockExclusive(&s_daemon_lock);
#else
    pthread_mutex_unlock(&s_daemon_lock);
#endif
}

void daemon_signal_changed(void)
{
#if defined(_WIN32)
    WakeAllConditionVariable(&g_daemon_changed);
#else
    pthread_cond_broadcast(&g_daemon_changed);
#endif
}

unsigned long long daemon_now(void)
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

unsigned long long daemon_wall(void)
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

void daemon_wait_until(unsigned long long when)
{
#if defined(_WIN32)
    DWORD milliseconds = INFINITE;
    if (when != TESSERA_DAEMON_FOREVER)
    {
        const unsigned long long now = daemon_now();
        const unsigned long long remaining = (when > now) ? (when - now) : 0ull;
        const unsigned long long wait_milliseconds = (remaining + 999ull) / 1000ull;
        // a wait below INFINITE fits a DWORD
        milliseconds = (wait_milliseconds < (unsigned long long)INFINITE) ? (DWORD)wait_milliseconds : (INFINITE - 1u);
    }
    SleepConditionVariableSRW(&g_daemon_changed, &s_daemon_lock, milliseconds, 0u);
#else
    if (when == TESSERA_DAEMON_FOREVER)
    {
        pthread_cond_wait(&g_daemon_changed, &s_daemon_lock);
        return;
    }
    struct timespec until;
    // a monotonic time in seconds fits a time_t
    until.tv_sec = (time_t)(when / TESSERA_DAEMON_MILLION);
    // a remainder below a million microseconds is below a billion nanoseconds
    until.tv_nsec = (long)((when % TESSERA_DAEMON_MILLION) * 1000ull);
    pthread_cond_timedwait(&g_daemon_changed, &s_daemon_lock, &until);
#endif
}

int daemon_directories_make(const char *path)
{
    char walk[ENGINE_PATH_CAPACITY];
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

int daemon_state_file(const char *name, char *path)
{
    const int written = snprintf(path, ENGINE_PATH_CAPACITY, "%s%s%s", g_daemon.state,
#if defined(_WIN32)
                                 "\\",
#else
                                 "/",
#endif
                                 name);
    // a non-negative length is compared whole against the capacity
    return (written >= 0) && ((unsigned int)written < ENGINE_PATH_CAPACITY);
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

int daemon_history_load(void)
{
    char path[ENGINE_PATH_CAPACITY];
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
    int ok = fseek(file, 0L, SEEK_END) == 0;
    const long length = ok ? ftell(file) : -1L;
    ok = ok && (length >= (long)OBSIGNATIO_SIGNUM_BYTES) &&
         ((((unsigned long long)length - OBSIGNATIO_SIGNUM_BYTES) % TESSERA_HISTORY_RECORD) == 0ull) &&
         (fseek(file, 0L, SEEK_SET) == 0);
    // a length checked non-negative above is the file's byte count
    const unsigned long long total = ok ? (unsigned long long)length : 0ull;
    unsigned char *const bytes = ok ? (unsigned char *)malloc((size_t)total) : NULL;
    ok = ok && (bytes != NULL) && (fread(bytes, 1u, (size_t)total, file) == (size_t)total);
    fclose(file);
    const unsigned long long sealed = total - OBSIGNATIO_SIGNUM_BYTES;
    EngineError error;
    memset(&error, 0, sizeof(error));
    const ObsignatioSealRequest seal = {bytes, sealed, (bytes != NULL) ? bytes + sealed : NULL, &error};
    ok = ok && (obsignatio_seal_verify(&seal) == 1L);
    for (unsigned long long at = 0ull; ok && (at < sealed); at += TESSERA_HISTORY_RECORD)
    {
        TesseraHistory kept;
        memcpy(kept.signum.bytes, bytes + at, ENGINE_SIGNUM_BYTES);
        kept.peak = daemon_get_long(bytes + at + ENGINE_SIGNUM_BYTES);
        kept.duration = daemon_get_long(bytes + at + ENGINE_SIGNUM_BYTES + 8u);
        ok = tessera_ledger_remember(&g_daemon.ledger, &kept);
    }
    free(bytes);
    if (!ok)
    {
        fprintf(stderr, "%s%s\n", s_daemon_history_bad, path);
    }
    return ok;
}

int daemon_history_save(void)
{
    char path[ENGINE_PATH_CAPACITY];
    char fresh[ENGINE_PATH_CAPACITY];
    if (!daemon_state_file(s_daemon_history, path) || !daemon_state_file(s_daemon_history_fresh, fresh))
    {
        return 0;
    }
    // every record, then the seal over them all; a history that is not saved is said so, never dropped silently
    const unsigned long long sealed = g_daemon.ledger.history_count * TESSERA_HISTORY_RECORD;
    const unsigned long long total = sealed + OBSIGNATIO_SIGNUM_BYTES;
    unsigned char *const bytes = (unsigned char *)malloc((size_t)total);
    if (bytes == NULL)
    {
        fprintf(stderr, "%s%s\n", s_daemon_history_unsaved, path);
        return 0;
    }
    for (unsigned long long at = 0ull; at < g_daemon.ledger.history_count; at += 1ull)
    {
        const TesseraHistory *const kept = &g_daemon.ledger.history[at];
        unsigned char *const record = bytes + (at * TESSERA_HISTORY_RECORD);
        memcpy(record, kept->signum.bytes, ENGINE_SIGNUM_BYTES);
        daemon_put_long(record + ENGINE_SIGNUM_BYTES, kept->peak);
        daemon_put_long(record + ENGINE_SIGNUM_BYTES + 8u, kept->duration);
    }
    EngineError error;
    memset(&error, 0, sizeof(error));
    const ObsignatioSealRequest seal = {bytes, sealed, bytes + sealed, &error};
    int ok = obsignatio_seal(&seal) == 0L;
    FILE *const file = ok ? fopen(fresh, "wb") : NULL;
    ok = ok && (file != NULL) && (fwrite(bytes, 1u, (size_t)total, file) == (size_t)total);
    ok = (file != NULL) && (fclose(file) == 0) && ok;
    free(bytes);
#if defined(_WIN32)
    ok = ok && (MoveFileExA(fresh, path, MOVEFILE_REPLACE_EXISTING) != 0);
#else
    ok = ok && (rename(fresh, path) == 0);
#endif
    if (!ok)
    {
        fprintf(stderr, "%s%s\n", s_daemon_history_unsaved, path);
    }
    return ok;
}

static int daemon_ticket_path(unsigned long long identity, const TesseraPeer *peer, int make, char *path)
{
    char folder[ENGINE_PATH_CAPACITY];
    if (!tessera_path_lost(g_daemon.device, identity, &peer->signum, folder, ENGINE_PATH_CAPACITY) ||
        (make && !daemon_directories_make(folder)))
    {
        return 0;
    }
    const int written =
        snprintf(path, ENGINE_PATH_CAPACITY, "%s%c%s", folder, TESSERA_DAEMON_SEPARATOR, s_daemon_ticket);
    // a non-negative length is compared whole against the capacity
    return (written >= 0) && ((unsigned int)written < ENGINE_PATH_CAPACITY);
}

static int daemon_ticket_seal_write(const char *path, const char *text, unsigned long long length)
{
    // the ticket's text, then a last line sealing every byte above it
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
    FILE *const file = fopen(path, "wb");
    if (file == NULL)
    {
        return 0;
    }
    const int printed = (fwrite(text, 1u, (size_t)length, file) == (size_t)length) &&
                        (fprintf(file, "%s%s\n", s_daemon_seal, line) > 0);
    return (fclose(file) == 0) && printed;
}

int daemon_ticket_write(unsigned long long identity, const TesseraPeer *peer, unsigned long long peak,
                        unsigned long long measured, const char *reason)
{
    char path[ENGINE_PATH_CAPACITY];
    char text[TESSERA_TICKET_CAPACITY];
    if (!daemon_ticket_path(identity, peer, 1, path))
    {
        return 0;
    }
    // the ticket names its job's signum whole: a lost job is found again by its request
    char signum[(2u * ENGINE_SIGNUM_BYTES) + 1u];
    for (unsigned int byte = 0u; byte < ENGINE_SIGNUM_BYTES; byte += 1u)
    {
        snprintf(signum + (2u * byte), 3u, "%02x", peer->signum.bytes[byte]);
    }
    const int written =
        snprintf(text, sizeof(text), "%s%016llx%s%s%s%llu%s%llu%s%llu%s%llu%s%llu%s%llu%s%s\n", s_daemon_identity,
                 identity, s_daemon_signum, signum, s_daemon_pid, peer->pid, s_daemon_declared, peer->declared,
                 s_daemon_peak, peak, s_daemon_measured, measured, s_daemon_holding, peer->holding_microseconds,
                 s_daemon_sweep, peer->sweep_microseconds, s_daemon_reason, reason);
    // a non-negative length is compared whole against the capacity
    return (written >= 0) && ((unsigned int)written < TESSERA_TICKET_CAPACITY) &&
           daemon_ticket_seal_write(path, text, (unsigned long long)written);
}

int daemon_ticket_note(unsigned long long identity, const TesseraPeer *peer, const char *note)
{
    // the note goes in only on a ticket whose seal holds, and the ticket is sealed again with it
    char path[ENGINE_PATH_CAPACITY];
    char text[TESSERA_TICKET_CAPACITY];
    if (!daemon_ticket_path(identity, peer, 0, path))
    {
        return 0;
    }
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return 0;
    }
    const size_t length = fread(text, 1u, sizeof(text) - 1u, file);
    const int at_end = feof(file) != 0;
    fclose(file);
    const size_t seal_line = (sizeof(s_daemon_seal) - 1u) + (2u * OBSIGNATIO_SIGNUM_BYTES) + 1u;
    if (!at_end || (length < seal_line) || (text[length - 1u] != '\n') ||
        (memcmp(text + (length - seal_line), s_daemon_seal, sizeof(s_daemon_seal) - 1u) != 0))
    {
        return 0;
    }
    const size_t body = length - seal_line;
    unsigned char signum[OBSIGNATIO_SIGNUM_BYTES];
    for (unsigned int byte = 0u; byte < OBSIGNATIO_SIGNUM_BYTES; byte += 1u)
    {
        const char *const pair = text + body + (sizeof(s_daemon_seal) - 1u) + (2u * byte);
        unsigned int value = 0u;
        for (unsigned int digit = 0u; digit < 2u; digit += 1u)
        {
            const char glyph = pair[digit];
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
    EngineError error;
    memset(&error, 0, sizeof(error));
    const ObsignatioSealRequest seal = {(const unsigned char *)text, body, signum, &error};
    // the note is a whole line, its newline included
    const size_t added = strlen(note);
    if ((obsignatio_seal_verify(&seal) != 1L) || ((body + added) >= sizeof(text)))
    {
        return 0;
    }
    memcpy(text + body, note, added);
    return daemon_ticket_seal_write(path, text, body + added);
}
