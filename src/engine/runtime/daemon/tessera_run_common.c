// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tessera_run_common.c: tessera_run's clock, arguments, paths, limits, record and log
#include "tessera_run_internal.h"

#if (defined(_WIN32))
_Alignas(8) static const char s_run_daemon[] = "tessera_daemon.exe";
#endif
#if !(defined(_WIN32))
_Alignas(8) static const char s_run_daemon[] = "tessera_daemon";
#endif

unsigned long long run_now(void)
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
    return ((ticks / rate) * RUN_MILLION) + (((ticks % rate) * RUN_MILLION) / rate);
#else
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    // a monotonic clock's seconds and nanoseconds are not negative
    return ((unsigned long long)now.tv_sec * RUN_MILLION) + ((unsigned long long)now.tv_nsec / 1000ull);
#endif
}

void run_pause(unsigned long long microseconds)
{
#if defined(_WIN32)
    // a pause's milliseconds fit a DWORD
    Sleep((DWORD)(microseconds / RUN_THOUSAND));
#else
    struct timespec pause;
    // whole seconds of a pause fit a time_t
    pause.tv_sec = (time_t)(microseconds / RUN_MILLION);
    // the remainder is below a billion nanoseconds, which a long holds
    pause.tv_nsec = (long)((microseconds % RUN_MILLION) * 1000ull);
    nanosleep(&pause, NULL);
#endif
}

unsigned long long run_self_pid(void)
{
#if defined(_WIN32)
    return GetCurrentProcessId();
#else
    // a process's own pid is positive. It converts exactly
    return (unsigned long long)getpid();
#endif
}

int run_arguments(int count, char **arguments, RunRequest *request)
{
    int at = 1;
    while ((at < count) && (strcmp(arguments[at], "--") != 0))
    {
        if (strcmp(arguments[at], "--child") == 0)
        {
            request->child = 1;
            at += 1;
            continue;
        }
        const int valued = (at + 1) < count;
        char *end = NULL;
        if (valued && (strcmp(arguments[at], "--processors") == 0))
        {
            request->processors = strtoull(arguments[at + 1], &end, 10);
            if ((end == arguments[at + 1]) || (*end != '\0'))
            {
                return 0;
            }
        }
        else if (valued && (strcmp(arguments[at], "--name") == 0))
        {
            request->name = arguments[at + 1];
        }
        else if (valued && (strcmp(arguments[at], "--parent") == 0))
        {
            request->parent = arguments[at + 1];
        }
        else
        {
            return 0;
        }
        at += 2;
    }
    request->command = at + 1;
    // a job asks its processors, or is the child of a tessera_run that holds the ticket: one or the other
    const int asks = request->processors != 0ull;
    const int is_child = request->parent != NULL;
    return (at < count) && (request->command < count) && (asks != is_child) && !(is_child && request->child);
}

// this program's own path and its length, or 0 where it cannot be read whole
size_t run_own_path(char *path, size_t capacity)
{
#if defined(_WIN32)
    // the capacity is a buffer size this file holds, which a DWORD counts on every Windows target
    const size_t length = (size_t)GetModuleFileNameA(NULL, path, (DWORD)capacity);
#else
    const ssize_t read = readlink("/proc/self/exe", path, capacity - 1u);
    // a failed read is -1 and is held as no length at all
    const size_t length = (read > 0) ? (size_t)read : 0u;
#endif
    if ((length == 0u) || (length >= capacity))
    {
        return 0u;
    }
    path[length] = '\0';
    return length;
}

int run_daemon_path(char *path, size_t capacity)
{
    // $TESSERA_DAEMON names the daemon; otherwise it is the tessera_daemon beside this program
    const char *const named = getenv("TESSERA_DAEMON");
    if ((named != NULL) && (named[0] != '\0'))
    {
        const int written = snprintf(path, capacity, "%s", named);
        // a non-negative length is compared whole against the capacity
        return (written > 0) && ((size_t)written < capacity);
    }
    size_t directory_length = run_own_path(path, capacity);
    while ((directory_length != 0u) && (path[directory_length - 1u] != '/') && (path[directory_length - 1u] != '\\'))
    {
        directory_length -= 1u;
    }
    if ((directory_length == 0u) || ((directory_length + sizeof(s_run_daemon)) > capacity))
    {
        return 0;
    }
    memcpy(path + directory_length, s_run_daemon, sizeof(s_run_daemon));
    return 1;
}

int run_signum(const RunRequest *request, char **arguments, int count, EngineSignum *signum, EngineError *error)
{
    // the request is the name, then every word of the command, each ended by a zero byte
    const char *const name = (request->name != NULL) ? request->name : "";
    unsigned long long bytes = strlen(name) + 1ull;
    for (int at = request->command; at < count; at += 1)
    {
        bytes += strlen(arguments[at]) + 1ull;
    }
    unsigned char *const text = (unsigned char *)malloc((size_t)bytes);
    if (text == NULL)
    {
        return 0;
    }
    memcpy(text, name, strlen(name) + 1u);
    unsigned long long at_byte = strlen(name) + 1ull;
    for (int at = request->command; at < count; at += 1)
    {
        memcpy(text + at_byte, arguments[at], strlen(arguments[at]) + 1u);
        at_byte += strlen(arguments[at]) + 1ull;
    }
    const ObsignatioSignumRequest hashed = {text, bytes, NULL, OBSIGNATIO_MODE_HASH, signum->bytes, ENGINE_SIGNUM_BYTES,
                                            error};
    const int ok = obsignatio_signum(&hashed) == 0L;
    free(text);
    return ok;
}

// a text and a suffix as one path, 0 where the capacity does not hold it
int run_path_joined(const char *first, const char *second, char *path, size_t capacity)
{
    const int written = snprintf(path, capacity, "%s%s", first, second);
    // a non-negative length is compared whole against the capacity
    return (written > 0) && ((size_t)written < capacity);
}

// a limit in milliseconds from the environment, in microseconds; the fallback where it is not set or not a count
unsigned long long run_limit(const char *name, unsigned long long fallback)
{
    const char *const text = getenv(name);
    char *end = NULL;
    const unsigned long long milliseconds = (text != NULL) ? strtoull(text, &end, 10) : 0ull;
    const int given = (text != NULL) && (end != text) && (*end == '\0') && (milliseconds != 0ull);
    return given ? (milliseconds * RUN_THOUSAND) : fallback;
}

// a record's line: its first word, then each number after it, a word naming each number after the first. The count of
// numbers read, or -1 for a line that is not whole
static int run_record_fields(const char *line, char state[RUN_STATE_CAPACITY], unsigned long long numbers[RUN_NUMBERS])
{
    const size_t length = strcspn(line, " \n");
    if ((length == 0u) || (length >= RUN_STATE_CAPACITY))
    {
        return -1;
    }
    memcpy(state, line, length);
    state[length] = '\0';
    const char *walk = line + length;
    int count = 0;
    while ((count < RUN_NUMBERS) && (walk[0] == ' ') && (walk[1] >= '0') && (walk[1] <= '9'))
    {
        char *end = NULL;
        numbers[count] = strtoull(walk + 1, &end, 10);
        count += 1;
        // past the word that names the next number
        walk = (end[0] == ' ') ? (end + 1 + strcspn(end + 1, " \n")) : end;
    }
    return (walk[0] == '\n') ? count : -1;
}

// a record file's line as its fields; -1 where the file cannot be read or its line is not whole
int run_record_read(const char *path, char state[RUN_STATE_CAPACITY], unsigned long long numbers[RUN_NUMBERS])
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return -1;
    }
    char line[RUN_RECORD_CAPACITY];
    const int read = fgets(line, sizeof(line), file) != NULL;
    fclose(file);
    return read ? run_record_fields(line, state, numbers) : -1;
}

// the time now in UTC, as a log entry opens with it
static void run_stamp(char *text, size_t capacity)
{
    const time_t now = time(NULL);
    struct tm parts;
#if defined(_WIN32)
    const int ok = gmtime_s(&parts, &now) == 0;
#else
    const int ok = gmtime_r(&now, &parts) != NULL;
#endif
    if (!ok || (strftime(text, capacity, "%Y-%m-%dT%H:%M:%SZ", &parts) == 0u))
    {
        text[0] = '\0';
    }
}

// an entry in the child's log, which outlives both processes where the parent did not end first, and on stderr
void run_log(const char *records, const char *entry)
{
    char stamp[32];
    run_stamp(stamp, sizeof(stamp));
    char path[ENGINE_PATH_CAPACITY];
    FILE *const file = run_path_joined(records, ".log", path, sizeof(path)) ? fopen(path, "ab") : NULL;
    if (file != NULL)
    {
        fprintf(file, "%s %s\n", stamp, entry);
        fclose(file);
    }
    fprintf(stderr, "  tessera_run: %s\n", entry);
}
