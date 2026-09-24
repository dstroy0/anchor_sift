// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// tessera end to end: the client against the built daemon on this device. The client starts the daemon when no
// daemon answers. A job declaring less than it then holds is admitted on its declaration and told it grew; its peak
// is kept under its signum. The same signum declaring four times that peak is asked, and admitted on the override.
// Declaring within the peak it is admitted at once. Declaring over it again with no answer, it is held past its
// holding time and lost, its ticket naming hst/lnf.log; the precalc kept releases it, and lnf.log ends with the
// precalc note in a sealed block of its own. Once the daemon has gone, hst/head.log is damaged by one byte, cut
// short, and stripped of its seal, and each time no daemon will start on it; restored, it starts and the kept peak
// is still there. The damage is done in $TESSERA_STATE, which run.sh points at a scratch directory.
#include "obsignatio.h"
#include "tessera.h"

#include <cuda_runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#define NOMINMAX
#include <windows.h>
#else
#include <fcntl.h>
#include <sys/file.h>
#include <time.h>
#include <unistd.h>
#endif

#define JOB_TEST_DECLARED (64ull << 20u)
#define JOB_TEST_HELD (256ull << 20u)

static unsigned long long s_job_checks = 0ull;
static unsigned long long s_job_failed = 0ull;

static void job_check(int held, const char *what)
{
    s_job_checks += 1ull;
    if (!held)
    {
        s_job_failed += 1ull;
        printf("  FAILED: %s\n", what);
    }
}

static void job_sleep_milliseconds(unsigned int milliseconds)
{
#if defined(_WIN32)
    Sleep(milliseconds);
#else
    usleep(milliseconds * 1000u);
#endif
}

static unsigned long long job_wall(void)
{
#if defined(_WIN32)
    FILETIME now;
    GetSystemTimeAsFileTime(&now);
    return ((unsigned long long)now.dwHighDateTime << 32u) | now.dwLowDateTime;
#else
    struct timespec now;
    clock_gettime(CLOCK_REALTIME, &now);
    return ((unsigned long long)now.tv_sec * 1000000000ull) + (unsigned long long)now.tv_nsec;
#endif
}

static int job_daemon_gone(const unsigned char *device)
{
    char endpoint[ENGINE_PATH_ROOM];
#if defined(_WIN32)
    if (!tessera_path_endpoint(device, endpoint, ENGINE_PATH_ROOM))
    {
        return 0;
    }
#else
    // the daemon holds its state's lock while it lives; a socket systemd holds outlives it, so the lock is asked
    char state[ENGINE_PATH_ROOM];
    const int named = tessera_path_state(device, state, ENGINE_PATH_ROOM)
                   && (snprintf(endpoint, sizeof(endpoint), "%s/tessera.lock", state) < (int)sizeof(endpoint));
    if (!named)
    {
        return 0;
    }
#endif
    // the daemon ends once it has held no job for its idle time; ten seconds is five of them
    for (unsigned int tries = 0u; tries < 100u; tries += 1u)
    {
#if defined(_WIN32)
        const int gone = (WaitNamedPipeA(endpoint, 1u) == 0) && (GetLastError() == ERROR_FILE_NOT_FOUND);
#else
        const int lock = open(endpoint, O_RDWR);
        const int gone = (lock < 0) || (flock(lock, LOCK_EX | LOCK_NB) == 0);
        if (lock >= 0)
        {
            close(lock);
        }
#endif
        if (gone)
        {
            return 1;
        }
        job_sleep_milliseconds(100u);
    }
    return 0;
}

static unsigned char *job_file_read(const char *path, unsigned long long *length)
{
    *length = 0ull;
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return NULL;
    }
    unsigned char *bytes = NULL;
    const long size = (fseek(file, 0L, SEEK_END) == 0) ? ftell(file) : -1L;
    if ((size > 0L) && (fseek(file, 0L, SEEK_SET) == 0))
    {
        bytes = (unsigned char *)malloc((size_t)size);
        if ((bytes != NULL) && (fread(bytes, 1u, (size_t)size, file) == (size_t)size))
        {
            *length = (unsigned long long)size;
        }
    }
    fclose(file);
    if (*length == 0ull)
    {
        free(bytes);
        return NULL;
    }
    return bytes;
}

static int job_file_write(const char *path, const unsigned char *bytes, unsigned long long length)
{
    FILE *const file = fopen(path, "wb");
    if (file == NULL)
    {
        return 0;
    }
    const int written = fwrite(bytes, 1u, (size_t)length, file) == (size_t)length;
    return (fclose(file) == 0) && written;
}

static int job_ticket_sealed(const char *lost_path, unsigned long long identity)
{
    // lnf.log is sealed blocks, each ending "seal " and 64 hex digits over every byte of its block; the last block is
    // the lost job's identity and the precalc note
    unsigned long long length = 0ull;
    unsigned char *const text = job_file_read(lost_path, &length);
    const unsigned long long line = 5ull + (2ull * OBSIGNATIO_SIGNUM_BYTES) + 1ull;
    int held = (text != NULL) && (length > line) && (memcmp(text + (length - line), "seal ", 5u) == 0);
    const unsigned long long body = held ? (length - line) : 0ull;
    unsigned long long block = 0ull;
    for (unsigned long long at = 0ull; held && ((at + line) <= body); at += 1ull)
    {
        const int line_start = (at == 0ull) || (text[at - 1ull] == '\n');
        const int sealing = line_start && (memcmp(text + at, "seal ", 5u) == 0) && (text[at + line - 1ull] == '\n');
        block = sealing ? (at + line) : block;
    }
    unsigned char signum[OBSIGNATIO_SIGNUM_BYTES];
    for (unsigned int byte = 0u; held && (byte < OBSIGNATIO_SIGNUM_BYTES); byte += 1u)
    {
        unsigned int value = 0u;
        char pair[3] = {(char)text[body + 5u + (2u * byte)], (char)text[body + 6u + (2u * byte)], '\0'};
        held = sscanf(pair, "%2x", &value) == 1;
        signum[byte] = (unsigned char)value;
    }
    char note[64];
    const int noted = snprintf(note, sizeof(note), "identity %016llx\nprecalc kept\n", identity);
    held = held && (noted > 0) && ((body - block) == (unsigned long long)noted)
        && (memcmp(text + block, note, (size_t)noted) == 0);
    EngineError error;
    memset(&error, 0, sizeof(error));
    const ObsignatioSealRequest seal = {text + block, body - block, signum, &error};
    held = held && (obsignatio_seal_holds(&seal) == 1L);
    free(text);
    return held;
}

int main(int count, char **arguments)
{
    if (count < 2)
    {
        printf("  tessera job test: the daemon's path is the one argument\n");
        return 2;
    }
    cudaDeviceProp properties;
    if (cudaGetDeviceProperties(&properties, 0) != cudaSuccess)
    {
        printf("  tessera job test: no device\n");
        return 1;
    }
    EngineError error;
    memset(&error, 0, sizeof(error));
    TesseraJobAsk ask;
    memset(&ask, 0, sizeof(ask));
    memcpy(ask.device, properties.uuid.bytes, TESSERA_DEVICE_BYTES);
    unsigned long long luid = 0ull;
#if defined(_WIN32)
    memcpy(&luid, properties.luid, sizeof(luid));
#endif
    ask.luid = luid;
    // a signum of this run alone, so the history holds nothing for it before its first job
    const unsigned long long made = job_wall();
    for (unsigned int at = 0u; at < ENGINE_SIGNUM_BYTES; at += 1u)
    {
        ask.signum.bytes[at] = (unsigned char)((made >> (8u * (at % 8u))) ^ (0xA5u + at));
    }
    ask.declared = JOB_TEST_DECLARED;
    ask.holding_microseconds = 400000ull;
    ask.sweep_microseconds = 20000ull;
    ask.idle_microseconds = 2000000ull;
    ask.daemon_path = arguments[1];
    ask.error = &error;

    // 1: admitted on its declaration, then grows past it
    TesseraClient *client = NULL;
    TesseraTicket ticket;
    long answer = tessera_job_submit(&ask, &client, &ticket);
    job_check((answer == 0L) && (ticket.asked == 0u) && (ticket.lost == 0u) && (ticket.granted == JOB_TEST_DECLARED),
              "a job never seen is admitted on its declaration");
    void *held = NULL;
    job_check(cudaMalloc(&held, JOB_TEST_HELD) == cudaSuccess, "the job takes device memory");
    job_check(cudaMemset(held, 1, JOB_TEST_HELD) == cudaSuccess, "the job touches it");
    cudaDeviceSynchronize();
    job_sleep_milliseconds(400u);
    answer = (client != NULL) ? tessera_job_release(client, &ticket, &error) : -1L;
    job_check(answer == 0L, "the job releases");
    job_check(ticket.grown_to >= JOB_TEST_HELD, "a job holding more than it declared is told it grew");
    job_check(ticket.last_peak >= JOB_TEST_HELD, "its release reports the peak measured by its pid");
    const unsigned long long peak = ticket.last_peak;
    printf("  declared %llu, grew to %llu, peak %llu\n", JOB_TEST_DECLARED, ticket.grown_to, peak);

    // 2: over its signum's peak it is asked, and the override admits it
    ask.declared = 4ull * peak;
    answer = tessera_job_submit(&ask, &client, &ticket);
    job_check((answer == 0L) && (ticket.asked != 0u), "declaring four times the kept peak is asked");
    job_check((answer == 0L) && (ticket.last_peak == peak), "the ask names the kept peak");
    answer = (answer == 0L) ? tessera_job_override(client, &ticket, &error) : -1L;
    job_check((answer == 0L) && (ticket.asked == 0u) && (ticket.granted == (4ull * peak)),
              "the override admits it on its declaration");
    answer = (answer == 0L) ? tessera_job_release(client, &ticket, &error) : -1L;
    job_check(answer == 0L, "the overridden job releases");

    // 3: within its peak it is admitted at once
    ask.declared = peak;
    answer = tessera_job_submit(&ask, &client, &ticket);
    job_check((answer == 0L) && (ticket.asked == 0u) && (ticket.granted == peak), "declaring the kept peak is admitted");
    answer = (answer == 0L) ? tessera_job_release(client, &ticket, &error) : -1L;
    job_check(answer == 0L, "that job releases");

    // 4: over it with no answer, held past its holding time and lost, then released by the precalc kept
    ask.declared = 4ull * peak;
    answer = tessera_job_submit(&ask, &client, &ticket);
    job_check((answer == 0L) && (ticket.asked != 0u), "over the peak again is asked");
    answer = (answer == 0L) ? tessera_job_wait(client, &ticket, &error) : -1L;
    job_check((answer == 0L) && (ticket.lost != 0u) && (ticket.lost_path[0] != '\0'),
              "unanswered past its holding time, it is lost and its ticket names the lost and found place");
    printf("  lost and found: %s\n", ticket.lost_path);
    answer = (answer == 0L) ? tessera_job_precalc_kept(client, &error) : -1L;
    job_check(answer == 0L, "the precalc kept in lost and found releases the job");
    job_check((answer == 0L) && job_ticket_sealed(ticket.lost_path, ticket.identity),
              "lnf.log ends with the lost job's precalc note, sealed");

    // 5: the history is sealed; damaged, cut short or unsealed, no daemon starts on it; restored, the peak is kept
    char state[ENGINE_PATH_ROOM];
    char history[ENGINE_PATH_ROOM];
    const int placed = (getenv("TESSERA_STATE") != NULL) && tessera_path_state(ask.device, state, ENGINE_PATH_ROOM);
    const int named = placed ? snprintf(history, sizeof(history), "%s%shst%shead.log", state,
#if defined(_WIN32)
                                        "\\", "\\"
#else
                                        "/", "/"
#endif
                                        )
                             : -1;
    // a non-negative length is compared whole against the room
    const int scratch = placed && (named > 0) && ((size_t)named < sizeof(history));
    job_check(scratch, "the history checks run in a scratch $TESSERA_STATE");
    job_check(scratch && job_daemon_gone(ask.device), "the daemon ends once it has held no job for its idle time");
    unsigned long long length = 0ull;
    unsigned char *const sealed = scratch ? job_file_read(history, &length) : NULL;
    job_check((sealed != NULL) && (length > OBSIGNATIO_SIGNUM_BYTES)
                  && (((length - OBSIGNATIO_SIGNUM_BYTES) % (ENGINE_SIGNUM_BYTES + 16u)) == 0ull),
              "the history on disk is whole records and a seal");
    ask.declared = peak;
    if (sealed != NULL)
    {
        unsigned char *const damaged = (unsigned char *)malloc((size_t)length);
        memcpy(damaged, sealed, (size_t)length);
        // one byte of the first record's peak
        damaged[ENGINE_SIGNUM_BYTES] ^= 0x01u;
        job_check(job_file_write(history, damaged, length) && (tessera_job_submit(&ask, &client, &ticket) != 0L),
                  "a history damaged by one byte is refused, and no daemon starts on it");
        job_check(job_file_write(history, sealed, length - 1ull) && (tessera_job_submit(&ask, &client, &ticket) != 0L),
                  "a history cut short by one byte is refused");
        job_check(job_file_write(history, sealed, length - OBSIGNATIO_SIGNUM_BYTES)
                      && (tessera_job_submit(&ask, &client, &ticket) != 0L),
                  "a history with no seal is refused");
        free(damaged);
        // a signum the history had lost would be admitted on its declaration; only the kept peak asks this
        ask.declared = 4ull * peak;
        answer = job_file_write(history, sealed, length) ? tessera_job_submit(&ask, &client, &ticket) : -1L;
        job_check((answer == 0L) && (ticket.asked != 0u) && (ticket.last_peak == peak),
                  "restored, the daemon starts on it and asks over the peak it kept");
        if ((answer != 0L) || (ticket.last_peak != peak))
        {
            printf("  restored submit: answer %ld, asked %u, last peak %llu, error site %u status %d\n", answer,
                   ticket.asked, ticket.last_peak, error.site, error.status);
        }
        answer = (answer == 0L) ? tessera_job_override(client, &ticket, &error) : -1L;
        answer = (answer == 0L) ? tessera_job_release(client, &ticket, &error) : -1L;
        job_check(answer == 0L, "that job is overridden and releases");
        free(sealed);
    }

    cudaFree(held);
    printf("  tessera job test: %llu checks, %llu failed\n", s_job_checks, s_job_failed);
    return (s_job_failed == 0ull) ? 0 : 1;
}
