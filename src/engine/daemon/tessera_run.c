// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#if !defined(_WIN32)
// fork, exec, the affinity mask, the pid descriptor, waitid, flock, gmtime_r and the clock are outside strict C11
#define _GNU_SOURCE
#endif
#include "obsignatio.h"
#include "tessera.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if defined(_WIN32)
#define NOMINMAX
#include <windows.h>
#else
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <sched.h>
#include <signal.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>
#endif

#define RUN_HOLDING_MICROSECONDS 2000000ull
#define RUN_SWEEP_MICROSECONDS 1000000ull
#define RUN_IDLE_MICROSECONDS 30000000ull
// until a parent and its child have greeted each other, each reads the other's record this often
#define RUN_GREETING_MICROSECONDS 20000ull
// a keepalive unchanged this long sends the child looking for its parent ($TESSERA_RUN_SILENT_MS)
#define RUN_SILENT_MICROSECONDS 10000000ull
// a parent that still holds its record and has kept no keepalive this long is not responding
// ($TESSERA_RUN_UNRESPONSIVE_MS)
#define RUN_UNRESPONSIVE_MICROSECONDS 60000000ull
// a command asked to end is given this long before what is left of it is ended by force
#define RUN_GRACE_MICROSECONDS 10000000ull
// how often a command asked to end is read for what is left of it
#define RUN_ENDING_MICROSECONDS 100000ull
#define RUN_MILLION 1000000ull
#define RUN_THOUSAND 1000ull
// the exit of a child that ended its command for want of a parent, as timeout(1) exits when it ends one
#define RUN_ORPHANED 124
#define RUN_FAILED 125
#define RUN_NOT_STARTED 127
#define RUN_NICER 10
#define RUN_PROCESSORS 64u
// the words put before a watched command: the child tessera_run, --parent, the records' path and --
#define RUN_WATCH_WORDS 4
#define RUN_RECORD_ROOM 160u
#define RUN_STATE_ROOM 16u
#define RUN_ENTRY_ROOM 2048u
#define RUN_NUMBERS 4

#if defined(_WIN32)
#define RUN_SEPARATOR '\\'
#else
#define RUN_SEPARATOR '/'
#endif

_Alignas(8) static const char s_run_usage[] = "  tessera_run: --processors <count> [--name <text>] [--child] -- <command> [arguments]\n"
                                              "  tessera_run: --parent <records> [--name <text>] -- <command> [arguments]\n";
_Alignas(8) static const char s_run_unasked[] = "  tessera_run: the job could not be asked (its signum, or the daemon's place)\n";
_Alignas(8) static const char s_run_unwatched[] = "  tessera_run: the command runs with no child to watch it: its records could not be made under the "
                                                  "host's tessera state\n";
_Alignas(8) static const char s_run_children[] = "children";
#if defined(_WIN32)
_Alignas(8) static const char s_run_unjoined[] = "  tessera_run: the command could not join a job object of its own; it runs on the processors given, unmeasured\n";
_Alignas(8) static const char s_run_wsl_unmeasured[] = "  tessera_run: only wsl.exe itself is measured: the Linux command needs -e or -- before it, and a Linux "
                                                       "tessera_run ($TESSERA_RUN_WSL, or tessera_run beside this program)\n";
_Alignas(8) static const char s_run_daemon[] = "tessera_daemon.exe";
#else
_Alignas(8) static const char s_run_daemon[] = "tessera_daemon";
#endif

typedef struct
{
    unsigned long long processors;
    const char *name;
    const char *parent;
    int child;
    int command;
} RunRequest;

typedef struct
{
#if defined(_WIN32)
    HANDLE job;
    HANDLE process;
#else
    pid_t pid;
    int watch;
#endif
} RunChild;

// the parent's side of a child tessera_run. Their records share one path, before .parent (the parent's, held open for
// the parent's whole life), .child (the child's) and .log (the child's entries); named_records is that path as the
// child names it. The parent records the pid it launched, then the pid the child says it has. Across the VM (a child
// in WSL) the child's record carries its command's processor time and the wall time it was read at, on the child's own
// clock, which no job here holds: the rate between two of its records is the command's processors
typedef struct
{
    char records[ENGINE_PATH_ROOM];
    char named_records[ENGINE_PATH_ROOM];
    char program[ENGINE_PATH_ROOM];
    int open;
    int across;
    int bound;
    unsigned long long launched;
    unsigned long long child;
    unsigned long long keepalive;
    unsigned long long reported;
    unsigned long long reported_wall;
    unsigned long long rate;
    char state[RUN_STATE_ROOM];
#if defined(_WIN32)
    HANDLE record;
#else
    int record;
#endif
} RunChannel;

static void run_record_launched(RunChannel *channel, unsigned long long pid);

static unsigned long long run_now(void)
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

static void run_pause(unsigned long long microseconds)
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

static unsigned long long run_self_pid(void)
{
#if defined(_WIN32)
    return GetCurrentProcessId();
#else
    // a process's own pid is positive, held whole
    return (unsigned long long)getpid();
#endif
}

static int run_arguments(int count, char **arguments, RunRequest *request)
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
static size_t run_own_path(char *path, size_t room)
{
#if defined(_WIN32)
    // the room is a buffer size this file holds, which a DWORD counts on every Windows target
    const size_t length = (size_t)GetModuleFileNameA(NULL, path, (DWORD)room);
#else
    const ssize_t read = readlink("/proc/self/exe", path, room - 1u);
    // a failed read is -1 and is held as no length at all
    const size_t length = (read > 0) ? (size_t)read : 0u;
#endif
    if ((length == 0u) || (length >= room))
    {
        return 0u;
    }
    path[length] = '\0';
    return length;
}

static int run_daemon_path(char *path, size_t room)
{
    // $TESSERA_DAEMON names the daemon; otherwise it is the tessera_daemon beside this program
    const char *const named = getenv("TESSERA_DAEMON");
    if ((named != NULL) && (named[0] != '\0'))
    {
        const int written = snprintf(path, room, "%s", named);
        // a non-negative length is compared whole against the room
        return (written > 0) && ((size_t)written < room);
    }
    size_t cut = run_own_path(path, room);
    while ((cut != 0u) && (path[cut - 1u] != '/') && (path[cut - 1u] != '\\'))
    {
        cut -= 1u;
    }
    if ((cut == 0u) || ((cut + sizeof(s_run_daemon)) > room))
    {
        return 0;
    }
    memcpy(path + cut, s_run_daemon, sizeof(s_run_daemon));
    return 1;
}

static int run_signum(const RunRequest *request, char **arguments, int count, EngineSignum *signum, EngineError *error)
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
    const ObsignatioSignumRequest hashed = {text, bytes, NULL, OBSIGNATIO_MODE_HASH, signum->bytes, ENGINE_SIGNUM_BYTES, error};
    const int good = obsignatio_signum(&hashed) == 0L;
    free(text);
    return good;
}

// a text and a suffix as one path, 0 where the room does not hold it
static int run_path_joined(const char *first, const char *second, char *path, size_t room)
{
    const int written = snprintf(path, room, "%s%s", first, second);
    // a non-negative length is compared whole against the room
    return (written > 0) && ((size_t)written < room);
}

// a limit in milliseconds from the environment, in microseconds; the fallback where it is not set or not a count
static unsigned long long run_limit(const char *name, unsigned long long fallback)
{
    const char *const text = getenv(name);
    char *end = NULL;
    const unsigned long long milliseconds = (text != NULL) ? strtoull(text, &end, 10) : 0ull;
    const int given = (text != NULL) && (end != text) && (*end == '\0') && (milliseconds != 0ull);
    return given ? (milliseconds * RUN_THOUSAND) : fallback;
}

// a record's line: its first word, then each number after it, a word naming each number after the first. The count of
// numbers read, or -1 for a line that is not whole
static int run_record_fields(const char *line, char state[RUN_STATE_ROOM], unsigned long long numbers[RUN_NUMBERS])
{
    const size_t length = strcspn(line, " \n");
    if ((length == 0u) || (length >= RUN_STATE_ROOM))
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
static int run_record_read(const char *path, char state[RUN_STATE_ROOM], unsigned long long numbers[RUN_NUMBERS])
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return -1;
    }
    char line[RUN_RECORD_ROOM];
    const int read = fgets(line, sizeof(line), file) != NULL;
    fclose(file);
    return read ? run_record_fields(line, state, numbers) : -1;
}

// the time now in UTC, as a log entry opens with it
static void run_stamp(char *text, size_t room)
{
    const time_t now = time(NULL);
    struct tm parts;
#if defined(_WIN32)
    const int good = gmtime_s(&parts, &now) == 0;
#else
    const int good = gmtime_r(&now, &parts) != NULL;
#endif
    if (!good || (strftime(text, room, "%Y-%m-%dT%H:%M:%SZ", &parts) == 0u))
    {
        text[0] = '\0';
    }
}

// an entry in the child's log, which outlives both processes where the parent did not end first, and on stderr
static void run_log(const char *records, const char *entry)
{
    char stamp[32];
    run_stamp(stamp, sizeof(stamp));
    char path[ENGINE_PATH_ROOM];
    FILE *const file = run_path_joined(records, ".log", path, sizeof(path)) ? fopen(path, "ab") : NULL;
    if (file != NULL)
    {
        fprintf(file, "%s %s\n", stamp, entry);
        fclose(file);
    }
    fprintf(stderr, "  tessera_run: %s\n", entry);
}

#if defined(_WIN32)
// the command's words as one command line, the program first, each quoted as the C runtime splits them back
static char *run_command_line(const char *program, char *const *words, int count)
{
    size_t room = 1u + (2u * strlen(program)) + 3u;
    for (int at = 1; at < count; at += 1)
    {
        room += (2u * strlen(words[at])) + 3u;
    }
    char *const line = (char *)malloc(room);
    if (line == NULL)
    {
        return NULL;
    }
    size_t length = 0u;
    for (int at = 0; at < count; at += 1)
    {
        const char *const word = (at == 0) ? program : words[at];
        if (at != 0)
        {
            line[length] = ' ';
            length += 1u;
        }
        const int quoted = (word[0] == '\0') || (strpbrk(word, " \t\n\v\"") != NULL);
        if (!quoted)
        {
            memcpy(line + length, word, strlen(word));
            length += strlen(word);
            continue;
        }
        line[length] = '"';
        length += 1u;
        size_t slashes = 0u;
        for (const char *walk = word; *walk != '\0'; walk += 1)
        {
            // the backslashes before a quote are doubled, and the quote is escaped by one more
            const size_t doubled = (*walk == '"') ? (slashes + 1u) : 0u;
            for (size_t added = 0u; added < doubled; added += 1u)
            {
                line[length] = '\\';
                length += 1u;
            }
            slashes = (*walk == '\\') ? (slashes + 1u) : 0u;
            line[length] = *walk;
            length += 1u;
        }
        // the backslashes before the closing quote are doubled
        for (size_t added = 0u; added < slashes; added += 1u)
        {
            line[length] = '\\';
            length += 1u;
        }
        line[length] = '"';
        length += 1u;
    }
    line[length] = '\0';
    return line;
}

// a program named with no folder, found along PATH as the shell that started this process finds it; CreateProcess
// alone looks in the system folders first, where "bash" is WSL's. The program as named where PATH does not hold it
static const char *run_program_found(const char *program, char *found, size_t room)
{
    const char *const path = getenv("PATH");
    if ((strpbrk(program, "\\/:") != NULL) || (path == NULL))
    {
        return program;
    }
    // the room is a buffer size this file holds, which a DWORD counts on every Windows target
    const DWORD length = SearchPathA(path, program, ".exe", (DWORD)room, found, NULL);
    return ((length != 0u) && (length < room)) ? found : program;
}

// an interrupt reaches the command too, which ends; this process waits for it, then releases its job
static BOOL WINAPI run_console_held(DWORD event)
{
    return (event == CTRL_C_EVENT) || (event == CTRL_BREAK_EVENT);
}

static void run_inheritable(HANDLE handle)
{
    if ((handle != NULL) && (handle != INVALID_HANDLE_VALUE))
    {
        SetHandleInformation(handle, HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT);
    }
}

// 1 where the command's program is wsl.exe (or wsl), whatever folder names it
static int run_names_wsl(const char *program)
{
    const char *base = program;
    for (const char *walk = program; *walk != '\0'; walk += 1)
    {
        base = ((*walk == '\\') || (*walk == '/')) ? (walk + 1) : base;
    }
    return (_stricmp(base, "wsl.exe") == 0) || (_stricmp(base, "wsl") == 0);
}

// a path on a drive as WSL mounts it, X:\a\b as /mnt/x/a/b; 0 for a path on no drive letter
static int run_mounted_path(const char *path, char *mounted, size_t room)
{
    const int upper = (path[0] >= 'A') && (path[0] <= 'Z');
    const int lower = (path[0] >= 'a') && (path[0] <= 'z');
    if ((!upper && !lower) || (path[1] != ':') || ((path[2] != '\\') && (path[2] != '/')))
    {
        return 0;
    }
    // a capital letter's lower case is the same letter 32 above it, still a char
    const char drive = upper ? (char)(path[0] + ('a' - 'A')) : path[0];
    const int written = snprintf(mounted, room, "/mnt/%c/%s", drive, path + 3);
    // a non-negative length is compared whole against the room
    if ((written <= 0) || ((size_t)written >= room))
    {
        return 0;
    }
    for (char *walk = mounted; *walk != '\0'; walk += 1)
    {
        *walk = (*walk == '\\') ? '/' : *walk;
    }
    return 1;
}

// the Linux tessera_run as WSL names it: $TESSERA_RUN_WSL, or the tessera_run beside this program
static int run_wsl_program(char *mounted, size_t room)
{
    const char *const named = getenv("TESSERA_RUN_WSL");
    if ((named != NULL) && (named[0] != '\0'))
    {
        const int written = snprintf(mounted, room, "%s", named);
        // a non-negative length is compared whole against the room
        return (written > 0) && ((size_t)written < room);
    }
    char path[ENGINE_PATH_ROOM];
    const size_t length = run_own_path(path, sizeof(path));
    // the Linux program is this one's name without its extension
    if ((length < 4u) || (_stricmp(path + length - 4u, ".exe") != 0))
    {
        return 0;
    }
    path[length - 4u] = '\0';
    return (GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES) && run_mounted_path(path, mounted, room);
}

static int run_start(RunChild *child, char *const *words, int count, unsigned long long mask, RunChannel *channel)
{
    char found[ENGINE_PATH_ROOM];
    char *const line = run_command_line(run_program_found(words[0], found, sizeof(found)), words, count);
    if (line == NULL)
    {
        return 0;
    }
    // the command and every process it starts run in one job, on the processors given; the job's accounting is
    // what the command's tree has used
    child->job = CreateJobObjectA(NULL, NULL);
    JOBOBJECT_BASIC_LIMIT_INFORMATION limits;
    memset(&limits, 0, sizeof(limits));
    limits.LimitFlags = JOB_OBJECT_LIMIT_AFFINITY;
    // the mask holds the first sixty-four processors, which the machine word holds whole
    limits.Affinity = (ULONG_PTR)mask;
    const int limited = (child->job != NULL)
                     && SetInformationJobObject(child->job, JobObjectBasicLimitInformation, &limits, sizeof(limits));
    STARTUPINFOA startup;
    memset(&startup, 0, sizeof(startup));
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    startup.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    startup.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    run_inheritable(startup.hStdInput);
    run_inheritable(startup.hStdOutput);
    run_inheritable(startup.hStdError);
    PROCESS_INFORMATION started;
    memset(&started, 0, sizeof(started));
    // below normal is the class every process the command starts inherits
    const int made = CreateProcessA(NULL, line, NULL, NULL, TRUE, CREATE_SUSPENDED | BELOW_NORMAL_PRIORITY_CLASS, NULL,
                                    NULL, &startup, &started);
    free(line);
    if (!made)
    {
        if (child->job != NULL)
        {
            CloseHandle(child->job);
        }
        child->job = NULL;
        return 0;
    }
    // a job the command cannot join is not measured: the command still runs on the processors given
    if (!limited || !AssignProcessToJobObject(child->job, started.hProcess))
    {
        // the mask holds the first sixty-four processors, which the machine word holds whole
        SetProcessAffinityMask(started.hProcess, (DWORD_PTR)mask);
        if (child->job != NULL)
        {
            CloseHandle(child->job);
        }
        child->job = NULL;
        fputs(s_run_unjoined, stderr);
    }
    // a watched command's pid is recorded before it runs: its child reads that it was launched
    run_record_launched(channel, started.dwProcessId);
    ResumeThread(started.hThread);
    CloseHandle(started.hThread);
    child->process = started.hProcess;
    SetConsoleCtrlHandler(run_console_held, TRUE);
    return 1;
}

static int run_ended(RunChild *child, unsigned long long microseconds)
{
    // a sweep's milliseconds fit a DWORD
    const DWORD milliseconds = (DWORD)(microseconds / RUN_THOUSAND);
    return WaitForSingleObject(child->process, milliseconds) != WAIT_TIMEOUT;
}

static int run_finish(RunChild *child)
{
    DWORD code = RUN_FAILED;
    GetExitCodeProcess(child->process, &code);
    CloseHandle(child->process);
    if (child->job != NULL)
    {
        CloseHandle(child->job);
    }
    // an exit code is handed on whole, and a shell reads its low byte
    return (int)code;
}

static int run_cpu(const RunChild *child, unsigned long long *microseconds)
{
    JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting;
    memset(&accounting, 0, sizeof(accounting));
    if ((child->job == NULL)
        || !QueryInformationJobObject(child->job, JobObjectBasicAccountingInformation, &accounting, sizeof(accounting),
                                      NULL))
    {
        return 0;
    }
    // the job's user and kernel times are counts of 100-nanosecond ticks, never negative
    const unsigned long long user = (unsigned long long)accounting.TotalUserTime.QuadPart;
    // the job's user and kernel times are counts of 100-nanosecond ticks, never negative
    const unsigned long long kernel = (unsigned long long)accounting.TotalKernelTime.QuadPart;
    *microseconds = (user + kernel) / 10ull;
    return 1;
}

// a console command on Windows is given no signal it must heed: its job, or its process where it joined none, is
// ended by force at once. The count ended by force
static unsigned long long run_end_command(RunChild *child, unsigned long long grace)
{
    if (child->job != NULL)
    {
        // the exit code is small and positive
        TerminateJobObject(child->job, (UINT)RUN_ORPHANED);
    }
    else
    {
        // the exit code is small and positive
        TerminateProcess(child->process, (UINT)RUN_ORPHANED);
    }
    // a grace's milliseconds fit a DWORD
    WaitForSingleObject(child->process, (DWORD)(grace / RUN_THOUSAND));
    return 1ull;
}

static void run_folder_make(const char *path)
{
    CreateDirectoryA(path, NULL);
}

static int run_folder_exists(const char *path)
{
    const DWORD attributes = GetFileAttributesA(path);
    return (attributes != INVALID_FILE_ATTRIBUTES) && ((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0u);
}

// the parent's record, shared only for reading: while this process lives no other opens it for writing, which is how
// its child finds that it lives, from Windows or from inside WSL
static int run_record_make(RunChannel *channel, const char *path)
{
    channel->record = CreateFileA(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    return channel->record != INVALID_HANDLE_VALUE;
}

static void run_record_put(RunChannel *channel, const char *line, size_t length)
{
    DWORD moved = 0u;
    SetFilePointer(channel->record, 0, NULL, FILE_BEGIN);
    // a record's line is under its room of a hundred and sixty bytes
    WriteFile(channel->record, line, (DWORD)length, &moved, NULL);
}

static void run_record_close(RunChannel *channel)
{
    CloseHandle(channel->record);
}

// 1 while the parent lives: its record is refused to an open for writing until its handles close with it
static int run_parent_holds(const char *parent)
{
    const HANDLE opened = CreateFileA(parent, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING,
                                      FILE_ATTRIBUTE_NORMAL, NULL);
    if (opened == INVALID_HANDLE_VALUE)
    {
        return GetLastError() == ERROR_SHARING_VIOLATION;
    }
    CloseHandle(opened);
    return 0;
}
#else
typedef struct
{
    unsigned long long pid;
    unsigned long long parent;
    unsigned long long ticks;
    char state;
    int in_tree;
} RunProcess;

static int run_process_read(unsigned long long pid, RunProcess *process)
{
    char path[64];
    snprintf(path, sizeof(path), "/proc/%llu/stat", pid);
    FILE *const stat = fopen(path, "r");
    if (stat == NULL)
    {
        return 0;
    }
    char line[1024];
    const int read = fgets(line, sizeof(line), stat) != NULL;
    fclose(stat);
    // the name may hold spaces and parentheses: the fields are read after its last ')', the state, the parent, nine
    // skipped, then the process's own user and system ticks and those of the children it waited for
    const char *const after_name = read ? strrchr(line, ')') : NULL;
    unsigned long long user = 0ull;
    unsigned long long system = 0ull;
    unsigned long long children_user = 0ull;
    unsigned long long children_system = 0ull;
    if ((after_name == NULL)
        || (sscanf(after_name + 1, " %c %llu %*s %*s %*s %*s %*s %*s %*s %*s %*s %llu %llu %llu %llu", &process->state,
                   &process->parent, &user, &system, &children_user, &children_system)
            != 6))
    {
        return 0;
    }
    process->pid = pid;
    process->ticks = user + system + children_user + children_system;
    process->in_tree = 0;
    return 1;
}

// every process /proc lists, the command's tree marked: its own process, then each whose parent is in it, until a pass
// adds none. NULL where /proc cannot be read
static RunProcess *run_tree(pid_t root, unsigned long long *count)
{
    DIR *const listing = opendir("/proc");
    if (listing == NULL)
    {
        return NULL;
    }
    RunProcess *processes = NULL;
    unsigned long long room = 0ull;
    int good = 1;
    *count = 0ull;
    for (const struct dirent *entry = readdir(listing); good && (entry != NULL); entry = readdir(listing))
    {
        char *end = NULL;
        const unsigned long long pid = strtoull(entry->d_name, &end, 10);
        RunProcess read;
        if ((end == entry->d_name) || (*end != '\0') || !run_process_read(pid, &read))
        {
            continue;
        }
        if (*count == room)
        {
            room = (room == 0ull) ? 256ull : (room * 2ull);
            RunProcess *const grown = (RunProcess *)realloc(processes, (size_t)room * sizeof(RunProcess));
            good = grown != NULL;
            processes = good ? grown : processes;
        }
        if (good)
        {
            processes[*count] = read;
            *count += 1ull;
        }
    }
    closedir(listing);
    if (!good || (processes == NULL))
    {
        free(processes);
        return NULL;
    }
    for (unsigned long long at = 0ull; at < *count; at += 1ull)
    {
        // a child's pid is positive, held whole
        processes[at].in_tree = processes[at].pid == (unsigned long long)root;
    }
    int added = 1;
    while (added)
    {
        added = 0;
        for (unsigned long long at = 0ull; at < *count; at += 1ull)
        {
            for (unsigned long long parent = 0ull; !processes[at].in_tree && (parent < *count); parent += 1ull)
            {
                processes[at].in_tree = processes[parent].in_tree && (processes[parent].pid == processes[at].parent);
                added = added || processes[at].in_tree;
            }
        }
    }
    return processes;
}

static int run_cpu(const RunChild *child, unsigned long long *microseconds)
{
    unsigned long long count = 0ull;
    RunProcess *const processes = run_tree(child->pid, &count);
    if (processes == NULL)
    {
        return 0;
    }
    unsigned long long ticks = 0ull;
    for (unsigned long long at = 0ull; at < count; at += 1ull)
    {
        ticks += processes[at].in_tree ? processes[at].ticks : 0ull;
    }
    free(processes);
    const long hertz = sysconf(_SC_CLK_TCK);
    // the clock's ticks a second are positive where it answers
    *microseconds = (hertz > 0L) ? ((ticks * RUN_MILLION) / (unsigned long long)hertz) : 0ull;
    return hertz > 0L;
}

static int run_start(RunChild *child, char *const *words, int count, unsigned long long mask, RunChannel *channel)
{
    (void)count;
    // the command waits on this pipe until its pid is recorded, as a Windows command waits suspended
    int go[2] = {-1, -1};
    if (pipe2(go, O_CLOEXEC) != 0)
    {
        return 0;
    }
    const pid_t made = fork();
    if (made < 0)
    {
        close(go[0]);
        close(go[1]);
        return 0;
    }
    if (made == 0)
    {
        close(go[1]);
        char word = 0;
        // a parent gone before it recorded this pid leaves nothing read, and nothing run
        if (read(go[0], &word, 1u) != 1)
        {
            _exit(RUN_NOT_STARTED);
        }
        cpu_set_t set;
        CPU_ZERO(&set);
        for (unsigned int processor = 0u; processor < RUN_PROCESSORS; processor += 1u)
        {
            if (((mask >> processor) & 1ull) != 0ull)
            {
                CPU_SET(processor, &set);
            }
        }
        sched_setaffinity(0, sizeof(set), &set);
        // below normal: at least ten nicer than normal, and no nicer again under a parent tessera_run that made it so
        const int current = nice(0);
        const int niced = (current < RUN_NICER) ? nice(RUN_NICER - current) : current;
        (void)niced;
        execvp(words[0], words);
        _exit(RUN_NOT_STARTED);
    }
    close(go[0]);
    child->pid = made;
    // a pid is positive, held whole
    run_record_launched(channel, (unsigned long long)made);
    const char word = 1;
    const ssize_t said = write(go[1], &word, 1u);
    (void)said;
    close(go[1]);
#if defined(SYS_pidfd_open)
    // a descriptor number fits an int
    child->watch = (int)syscall(SYS_pidfd_open, made, 0u);
#else
    child->watch = -1;
#endif
    // an interrupt or a hangup from the terminal reaches the command, which ends; this process waits for it, then
    // releases its job or writes its last record
    signal(SIGINT, SIG_IGN);
    signal(SIGQUIT, SIG_IGN);
    signal(SIGHUP, SIG_IGN);
    return 1;
}

// 1 once the command has ended; it is left unreaped, and its tree's last reading still counts its own ticks
static int run_ended(RunChild *child, unsigned long long microseconds)
{
    if (child->watch >= 0)
    {
        struct pollfd watch;
        watch.fd = child->watch;
        watch.events = POLLIN;
        watch.revents = 0;
        // a sweep's milliseconds fit an int
        poll(&watch, 1u, (int)(microseconds / RUN_THOUSAND));
    }
    else
    {
        run_pause(microseconds);
    }
    siginfo_t ended;
    memset(&ended, 0, sizeof(ended));
    const int asked = waitid(P_PID, (id_t)child->pid, &ended, WEXITED | WNOHANG | WNOWAIT);
    return ((asked == 0) && (ended.si_pid == child->pid)) || ((asked != 0) && (errno != EINTR));
}

static int run_finish(RunChild *child)
{
    int status = 0;
    pid_t reaped = waitpid(child->pid, &status, 0);
    while ((reaped < 0) && (errno == EINTR))
    {
        reaped = waitpid(child->pid, &status, 0);
    }
    if (child->watch >= 0)
    {
        close(child->watch);
    }
    if (reaped != child->pid)
    {
        return RUN_FAILED;
    }
    if (WIFEXITED(status))
    {
        return WEXITSTATUS(status);
    }
    return WIFSIGNALED(status) ? (128 + WTERMSIG(status)) : RUN_FAILED;
}

// the processes of the tree still living (not ended, not waiting to be reaped), each sent the signal where one is
// given; their count
static unsigned long long run_living(const RunProcess *processes, unsigned long long count, int signal_number)
{
    unsigned long long living = 0ull;
    for (unsigned long long at = 0ull; at < count; at += 1ull)
    {
        RunProcess now;
        const int alive = processes[at].in_tree && run_process_read(processes[at].pid, &now) && (now.state != 'Z');
        if (alive && (signal_number != 0))
        {
            // a pid read from /proc is positive, and a pid_t holds it
            kill((pid_t)processes[at].pid, signal_number);
        }
        living += alive ? 1ull : 0ull;
    }
    return living;
}

// the command's tree is asked to end (SIGTERM); what is left of it after the grace is ended by force (SIGKILL). The
// count ended by force
static unsigned long long run_end_command(RunChild *child, unsigned long long grace)
{
    unsigned long long count = 0ull;
    RunProcess *const processes = run_tree(child->pid, &count);
    if (processes == NULL)
    {
        kill(child->pid, SIGKILL);
        return 1ull;
    }
    unsigned long long living = run_living(processes, count, SIGTERM);
    const unsigned long long asked = run_now();
    while ((living != 0ull) && ((run_now() - asked) < grace))
    {
        run_pause(RUN_ENDING_MICROSECONDS);
        living = run_living(processes, count, 0);
    }
    const unsigned long long forced = (living != 0ull) ? run_living(processes, count, SIGKILL) : 0ull;
    free(processes);
    return forced;
}

static void run_folder_make(const char *path)
{
    mkdir(path, 0755);
}

static int run_folder_exists(const char *path)
{
    struct stat found;
    return (stat(path, &found) == 0) && S_ISDIR(found.st_mode);
}

// the parent's record, locked for this process's life and let go with it: how its child finds that it lives. The
// descriptor closes on exec: no child holds the lock with it
static int run_record_make(RunChannel *channel, const char *path)
{
    channel->record = open(path, O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0644);
    if (channel->record < 0)
    {
        return 0;
    }
    if (flock(channel->record, LOCK_EX | LOCK_NB) != 0)
    {
        close(channel->record);
        return 0;
    }
    return 1;
}

static void run_record_put(RunChannel *channel, const char *line, size_t length)
{
    const ssize_t written = pwrite(channel->record, line, length, 0);
    (void)written;
}

static void run_record_close(RunChannel *channel)
{
    close(channel->record);
}

// 1 while the parent lives. A Windows parent (this child runs in WSL) shares its record only for reading, and an open
// for writing is refused while it lives; a Linux parent holds a lock on it. Either is let go when the parent ends
static int run_parent_holds(const char *parent)
{
    const int opened = open(parent, O_WRONLY | O_CLOEXEC);
    if (opened < 0)
    {
        return errno != ENOENT;
    }
    const int locked = flock(opened, LOCK_EX | LOCK_NB) == 0;
    close(opened);
    return !locked;
}
#endif

// every folder along the path made where it is not; 1 where the last is there
static int run_folders_make(char *path)
{
    for (size_t at = 1u; path[at] != '\0'; at += 1u)
    {
        const char held = path[at];
        if ((held == '/') || (held == RUN_SEPARATOR))
        {
            path[at] = '\0';
            run_folder_make(path);
            path[at] = held;
        }
    }
    run_folder_make(path);
    return run_folder_exists(path);
}

// the parent's record rewritten from its start: the pid launched, the child's pid once it has said it, and the
// keepalive, one more at each write. A line never shortens, and none is left from the one before
static void run_record_write(RunChannel *channel)
{
    if ((channel == NULL) || !channel->open)
    {
        return;
    }
    char line[RUN_RECORD_ROOM];
    const int length = channel->bound ? snprintf(line, sizeof(line), "launched %llu child %llu keepalive %llu\n",
                                                 channel->launched, channel->child, channel->keepalive)
                                      : snprintf(line, sizeof(line), "launching %llu keepalive %llu\n", channel->launched,
                                                 channel->keepalive);
    // a record's length is positive and compared whole against its room
    if ((length > 0) && ((size_t)length < sizeof(line)))
    {
        // a record's length is positive, held whole
        run_record_put(channel, line, (size_t)length);
    }
    channel->keepalive += 1ull;
}

static void run_record_launched(RunChannel *channel, unsigned long long pid)
{
    if ((channel != NULL) && channel->open)
    {
        channel->launched = pid;
        run_record_write(channel);
    }
}

// the records' path: the host's tessera state, then children, then this process's pid and the job's signum, as a lost
// ticket's record is named; the folders are made where they are not
static int run_records_place(RunChannel *channel, const EngineSignum *signum)
{
    unsigned char host[TESSERA_DEVICE_BYTES];
    memset(host, 0, sizeof(host));
    char *const records = channel->records;
    const size_t room = sizeof(channel->records);
    // the room is a buffer size this file holds, which an unsigned int counts
    if (!tessera_path_state(host, records, (unsigned int)room))
    {
        return 0;
    }
    size_t at = strlen(records);
    const int folder = snprintf(records + at, room - at, "%c%s", RUN_SEPARATOR, s_run_children);
    // a non-negative length is compared whole against the room
    if ((folder <= 0) || ((size_t)folder >= (room - at)) || !run_folders_make(records))
    {
        return 0;
    }
    at = strlen(records);
    const int named = snprintf(records + at, room - at, "%c%016llx-", RUN_SEPARATOR, run_self_pid());
    // a non-negative length is compared whole against the room
    if ((named <= 0) || ((size_t)named >= (room - at)))
    {
        return 0;
    }
    at = strlen(records);
    for (unsigned int byte = 0u; byte < ENGINE_SIGNUM_BYTES; byte += 1u)
    {
        if ((at + 3u) > room)
        {
            return 0;
        }
        snprintf(records + at, room - at, "%02x", signum->bytes[byte]);
        at += 2u;
    }
    return 1;
}

// a child tessera_run is put between this process and the command where one is asked for (--child), and always for a
// WSL command, whose tree only a child inside the VM can measure. The words to start, NULL-ended, or NULL for the
// command as it is
static char **run_channel_open(RunChannel *channel, const RunRequest *request, char *const *words, int count,
                               const EngineSignum *signum, int *started_count)
{
    int inside_at = 0;
#if defined(_WIN32)
    channel->across = run_names_wsl(words[0]);
    if (channel->across)
    {
        inside_at = 1;
        while ((inside_at < count) && (strcmp(words[inside_at], "-e") != 0) && (strcmp(words[inside_at], "--exec") != 0)
               && (strcmp(words[inside_at], "--") != 0))
        {
            inside_at += 1;
        }
        inside_at += 1;
        if ((inside_at >= count) || !run_wsl_program(channel->program, sizeof(channel->program)))
        {
            fputs(s_run_wsl_unmeasured, stderr);
            return NULL;
        }
    }
#endif
    if (!channel->across && !request->child)
    {
        return NULL;
    }
    char path[ENGINE_PATH_ROOM];
    const int placed = (channel->across || (run_own_path(channel->program, sizeof(channel->program)) != 0u))
                    && run_records_place(channel, signum) && run_path_joined(channel->records, ".parent", path, sizeof(path))
                    && run_record_make(channel, path);
#if defined(_WIN32)
    const int named = placed
                   && (channel->across
                           ? run_mounted_path(channel->records, channel->named_records, sizeof(channel->named_records))
                           : run_path_joined(channel->records, "", channel->named_records, sizeof(channel->named_records)));
#else
    const int named = placed && run_path_joined(channel->records, "", channel->named_records, sizeof(channel->named_records));
#endif
    // a word count is positive, held whole
    char **const watched = named ? (char **)malloc(((size_t)count + RUN_WATCH_WORDS + 1u) * sizeof(char *)) : NULL;
    if (watched == NULL)
    {
        if (placed)
        {
            run_record_close(channel);
            remove(path);
        }
        fputs(s_run_unwatched, stderr);
        return NULL;
    }
    // records a child of an earlier process of the same pid left are not read as this child's
    remove(run_path_joined(channel->records, ".child", path, sizeof(path)) ? path : "");
    remove(run_path_joined(channel->records, ".log", path, sizeof(path)) ? path : "");
    // the words before the command's own, a count at least 0, held whole
    memcpy(watched, words, (size_t)inside_at * sizeof(char *));
    watched[inside_at] = channel->program;
    watched[inside_at + 1] = "--parent";
    watched[inside_at + 2] = channel->named_records;
    watched[inside_at + 3] = "--";
    // the command's own words, a positive count held whole
    memcpy(watched + inside_at + RUN_WATCH_WORDS, words + inside_at, (size_t)(count - inside_at) * sizeof(char *));
    watched[count + RUN_WATCH_WORDS] = NULL;
    channel->open = 1;
    *started_count = count + RUN_WATCH_WORDS;
    fprintf(stderr, "  tessera_run: the command runs under a child tessera_run (%s), their records at %s\n",
            channel->program, channel->records);
    return watched;
}

// the parent's side at each step: the child's record read, its pid recorded once it says it lives, and the keepalive
// rewritten
static void run_channel_keep(RunChannel *channel)
{
    if (!channel->open)
    {
        return;
    }
    char path[ENGINE_PATH_ROOM];
    char state[RUN_STATE_ROOM];
    unsigned long long numbers[RUN_NUMBERS] = {0ull, 0ull, 0ull, 0ull};
    const int fields = run_path_joined(channel->records, ".child", path, sizeof(path)) ? run_record_read(path, state, numbers)
                                                                                       : -1;
    if (fields >= 2)
    {
        // on one system the child is the process this one launched, its pid the same; across the VM it has its own
        if (!channel->bound && (channel->across || (numbers[0] == channel->launched)))
        {
            channel->bound = 1;
            channel->child = numbers[0];
            fprintf(stderr, "  tessera_run: child %llu, launched as %llu, says it lives; its pid is recorded\n",
                    channel->child, channel->launched);
        }
        // the command's processors between two of the child's records, on its clock, once they span half a sweep: a
        // record read late, or missed mid-write, shifts no time into the next reading
        const int spans = (fields >= 3) && (numbers[2] >= (channel->reported_wall + (RUN_SWEEP_MICROSECONDS / 2ull)));
        if (channel->bound && (numbers[0] == channel->child) && spans)
        {
            const unsigned long long grew = (numbers[1] > channel->reported) ? (numbers[1] - channel->reported) : 0ull;
            channel->rate = (grew * TESSERA_HOST_PROCESSOR) / (numbers[2] - channel->reported_wall);
            channel->reported = numbers[1];
            channel->reported_wall = numbers[2];
        }
        if (channel->bound && (numbers[0] == channel->child))
        {
            memcpy(channel->state, state, sizeof(channel->state));
        }
    }
    run_record_write(channel);
}

// a child that ended its command itself leaves nothing to relaunch or resume, and the records go; any other end keeps
// them where the child's log says why
static void run_channel_close(RunChannel *channel)
{
    if (!channel->open)
    {
        return;
    }
    run_record_close(channel);
    char path[ENGINE_PATH_ROOM];
    const int ended = strcmp(channel->state, "ended") == 0;
    FILE *const logged = (!ended && run_path_joined(channel->records, ".log", path, sizeof(path))) ? fopen(path, "rb") : NULL;
    if (logged != NULL)
    {
        fclose(logged);
        fprintf(stderr, "  tessera_run: the child's records are kept, its log at %s\n", path);
        return;
    }
    remove(run_path_joined(channel->records, ".parent", path, sizeof(path)) ? path : "");
    remove(run_path_joined(channel->records, ".child", path, sizeof(path)) ? path : "");
    remove(run_path_joined(channel->records, ".log", path, sizeof(path)) ? path : "");
}

// reports the command's processors each sweep until it ends, the last reading only when it spans half a sweep, since
// a shorter one is mostly the clock's own step. Across the VM the child's last rate is added to this job's own. A
// child not yet greeted is read, and kept alive, every greeting step
static void run_wait(RunChild *child, RunChannel *channel, TesseraClient *client, TesseraTicket *ticket,
                     EngineError *error)
{
    const int across = channel->open && channel->across;
    unsigned long long cpu_before = 0ull;
    int reporting = run_cpu(child, &cpu_before) || across;
    unsigned long long wall_before = run_now();
    int ended = 0;
    while (!ended)
    {
        const int greeting = channel->open && !channel->bound;
        ended = run_ended(child, greeting ? RUN_GREETING_MICROSECONDS : RUN_SWEEP_MICROSECONDS);
        run_channel_keep(channel);
        const unsigned long long wall = run_now();
        const unsigned long long spent = wall - wall_before;
        if (!ended && (spent < RUN_SWEEP_MICROSECONDS))
        {
            continue;
        }
        unsigned long long cpu = 0ull;
        const int read = reporting && run_cpu(child, &cpu);
        const int whole = (spent != 0ull) && (!ended || ((2ull * spent) >= RUN_SWEEP_MICROSECONDS));
        if (reporting && (read || across) && whole)
        {
            // the processors used over the reading, in thousandths: the tree's processor time over the wall time
            const unsigned long long own = read ? ((((cpu > cpu_before) ? (cpu - cpu_before) : 0ull)
                                                    * TESSERA_HOST_PROCESSOR) / spent)
                                                : 0ull;
            const unsigned long long used = own + (across ? channel->rate : 0ull);
            reporting = tessera_job_report(client, ticket, used, error) == 0L;
        }
        cpu_before = read ? cpu : cpu_before;
        wall_before = wall;
    }
}

// the child's record, rewritten whole: its state, its pid, its command's processor time and the wall time it was read
// at since the child began, then its exit once it has one
static void run_child_write(const char *records, const char *state, unsigned long long pid, unsigned long long cpu,
                            unsigned long long wall, int ended, int code)
{
    char path[ENGINE_PATH_ROOM];
    FILE *const file = run_path_joined(records, ".child", path, sizeof(path)) ? fopen(path, "wb") : NULL;
    if (file == NULL)
    {
        return;
    }
    if (ended)
    {
        // an exit code is written as the unsigned word a process ends with, which a reader parses as digits
        fprintf(file, "%s %llu cpu %llu wall %llu exit %u\n", state, pid, cpu, wall, (unsigned int)code);
    }
    else
    {
        fprintf(file, "%s %llu cpu %llu wall %llu\n", state, pid, cpu, wall);
    }
    fclose(file);
}

// the command's processor time read now, or the time read before where that is more: a tree that has lost processes
// no longer counts theirs, and the time it has used never falls
static unsigned long long run_child_cpu(const RunChild *child, unsigned long long before)
{
    unsigned long long read = 0ull;
    return (run_cpu(child, &read) && (read > before)) ? read : before;
}

// the child's side. It says it lives, reads that its parent launched it, checks its own pid against the one the parent
// recorded, and only then runs the command, its processor time in its record each sweep. A parent whose keepalive
// stops is looked for: one gone, or one that still holds its record and has not answered for the unresponsive time,
// has the child end the command, log it and exit, and whoever runs the parent may relaunch or resume it
static int run_child(const RunRequest *request, char **arguments, int count, unsigned long long mask, const char *label)
{
    const char *const records = request->parent;
    const unsigned long long self = run_self_pid();
    const unsigned long long silent = run_limit("TESSERA_RUN_SILENT_MS", RUN_SILENT_MICROSECONDS);
    const unsigned long long unresponsive = run_limit("TESSERA_RUN_UNRESPONSIVE_MS", RUN_UNRESPONSIVE_MICROSECONDS);
    char parent[ENGINE_PATH_ROOM];
    char entry[RUN_ENTRY_ROOM];
    char state[RUN_STATE_ROOM];
    unsigned long long heard[RUN_NUMBERS] = {0ull, 0ull, 0ull, 0ull};
    if (!run_path_joined(records, ".parent", parent, sizeof(parent)) || (run_record_read(parent, state, heard) < 2))
    {
        snprintf(entry, sizeof(entry), "child %llu: no launch record at %s.parent; %s was not run", self, records, label);
        run_log(records, entry);
        return RUN_FAILED;
    }
    run_child_write(records, "alive", self, 0ull, 0ull, 0, 0);
    // the parent reads this record and records this pid within its greeting step
    const unsigned long long greeted = run_now();
    int bound = 0;
    while (!bound && ((run_now() - greeted) < silent))
    {
        run_pause(RUN_GREETING_MICROSECONDS);
        const int fields = run_record_read(parent, state, heard);
        bound = (fields == 3) && (strcmp(state, "launched") == 0);
    }
    if (!bound)
    {
        const int holds = run_parent_holds(parent);
        snprintf(entry, sizeof(entry), "child %llu: its parent %s and did not record this pid; %s was not run", self,
                 holds ? "holds its record" : "is gone", label);
        run_log(records, entry);
        run_child_write(records, "orphaned", self, 0ull, 0ull, 1, RUN_ORPHANED);
        return RUN_ORPHANED;
    }
    // the parent's record names the child it launched: the command runs only where that is this process
    if (heard[1] != self)
    {
        snprintf(entry, sizeof(entry), "child %llu: the parent's record names child %llu, launched as %llu, not this "
                 "process; %s was not run", self, heard[1], heard[0], label);
        run_log(records, entry);
        return RUN_FAILED;
    }
    snprintf(entry, sizeof(entry), "child %llu, launched as %llu: its pid confirmed against the parent's record; %s runs "
             "on processors 0x%llx at below normal priority", self, heard[0], label, mask);
    run_log(records, entry);
    run_child_write(records, "confirmed", self, 0ull, 0ull, 0, 0);
    RunChild child;
    memset(&child, 0, sizeof(child));
    if (!run_start(&child, arguments + request->command, count - request->command, mask, NULL))
    {
        snprintf(entry, sizeof(entry), "child %llu: %s could not be started", self, label);
        run_log(records, entry);
        run_child_write(records, "ended", self, 0ull, 0ull, 1, RUN_NOT_STARTED);
        return RUN_NOT_STARTED;
    }
    unsigned long long keepalive = heard[2];
    const unsigned long long began = run_now();
    unsigned long long heard_at = began;
    unsigned long long cpu = 0ull;
    int ended = 0;
    int orphaned = 0;
    int holds = 1;
    int looked = 0;
    while (!ended && !orphaned)
    {
        ended = run_ended(&child, RUN_SWEEP_MICROSECONDS);
        cpu = run_child_cpu(&child, cpu);
        run_child_write(records, "confirmed", self, cpu, run_now() - began, 0, 0);
        const int fields = run_record_read(parent, state, heard);
        const unsigned long long now = run_now();
        const int kept = (fields == 3) && (heard[2] != keepalive);
        if (kept && looked)
        {
            snprintf(entry, sizeof(entry), "child %llu: the parent's keepalive is heard again after %llu.%03llu s", self,
                     (now - heard_at) / RUN_MILLION, ((now - heard_at) % RUN_MILLION) / RUN_THOUSAND);
            run_log(records, entry);
        }
        looked = kept ? 0 : looked;
        heard_at = kept ? now : heard_at;
        keepalive = kept ? heard[2] : keepalive;
        const unsigned long long silence = now - heard_at;
        // a keepalive unchanged past the silent time: the parent is looked for, by whether it still holds its record
        holds = (silence < silent) || run_parent_holds(parent);
        orphaned = !ended && (!holds || (silence >= unresponsive));
        if (!ended && !orphaned && (silence >= silent) && !looked)
        {
            snprintf(entry, sizeof(entry), "child %llu: no keepalive for %llu.%03llu s; the parent still holds its record, "
                     "and is given until %llu s", self, silence / RUN_MILLION, (silence % RUN_MILLION) / RUN_THOUSAND,
                     unresponsive / RUN_MILLION);
            run_log(records, entry);
            looked = 1;
        }
    }
    if (orphaned)
    {
        const unsigned long long silence = run_now() - heard_at;
        const unsigned long long forced = run_end_command(&child, RUN_GRACE_MICROSECONDS);
        cpu = run_child_cpu(&child, cpu);
        const int code = run_finish(&child);
        run_child_write(records, "orphaned", self, cpu, run_now() - began, 1, code);
        snprintf(entry, sizeof(entry), "child %llu: its parent %s, with no keepalive for %llu.%03llu s; %s was asked to "
                 "end, %llu of its processes ended by force, exit %d. The parent may relaunch or resume it", self,
                 holds ? "holds its record but is not responding" : "is gone", silence / RUN_MILLION,
                 (silence % RUN_MILLION) / RUN_THOUSAND, label, forced, code);
        run_log(records, entry);
        return RUN_ORPHANED;
    }
    const int code = run_finish(&child);
    run_child_write(records, "ended", self, cpu, run_now() - began, 1, code);
    snprintf(entry, sizeof(entry), "child %llu: %s ended, exit %d, after %llu.%03llu s of processor time", self, label, code,
             cpu / RUN_MILLION, (cpu % RUN_MILLION) / RUN_THOUSAND);
    run_log(records, entry);
    return code;
}

int main(int count, char **arguments)
{
    RunRequest request;
    memset(&request, 0, sizeof(request));
    if (!run_arguments(count, arguments, &request))
    {
        fputs(s_run_usage, stderr);
        return RUN_FAILED;
    }
    const unsigned long long mask = tessera_self_host_mask();
    // a processor count is at most sixty-four, held whole
    const unsigned long long given = (unsigned long long)engine_word_population(mask);
    if ((mask == 0ull) || (request.processors > given))
    {
        fprintf(stderr, "  tessera_run: asks %llu processors, and the host gives jobs %llu\n", request.processors, given);
        return RUN_FAILED;
    }
    const char *const label = (request.name != NULL) ? request.name : arguments[request.command];
    if (request.parent != NULL)
    {
        return run_child(&request, arguments, count, mask, label);
    }
    EngineError error;
    memset(&error, 0, sizeof(error));
    char daemon[ENGINE_PATH_ROOM];
    TesseraJobAsk ask;
    memset(&ask, 0, sizeof(ask));
    if (!run_daemon_path(daemon, sizeof(daemon)) || !run_signum(&request, arguments, count, &ask.signum, &error))
    {
        fputs(s_run_unasked, stderr);
        return RUN_FAILED;
    }
    ask.declared = request.processors * TESSERA_HOST_PROCESSOR;
    ask.holding_microseconds = RUN_HOLDING_MICROSECONDS;
    ask.sweep_microseconds = RUN_SWEEP_MICROSECONDS;
    ask.idle_microseconds = RUN_IDLE_MICROSECONDS;
    // processors named past the signum's kept peak are not held for asking: the job waits only for room. What it
    // reserves is still the kept peak where that is more than it named
    ask.override_budget = 1u;
    ask.daemon_path = daemon;
    ask.error = &error;
    const unsigned long long asked = run_now();
    TesseraClient *client = NULL;
    TesseraTicket ticket;
    if (tessera_job_submit(&ask, &client, &ticket) != 0L)
    {
        fprintf(stderr, "  tessera_run: %s was not admitted by the host's daemon (%s)\n", label, daemon);
        return RUN_FAILED;
    }
    const unsigned long long waited = run_now() - asked;
    fprintf(stderr,
            "  tessera_run: %s admitted after %llu.%03llu s, %llu.%03llu of %llu processors reserved, on processors "
            "0x%llx at below normal priority\n",
            label, waited / RUN_MILLION, (waited % RUN_MILLION) / RUN_THOUSAND, ticket.granted / TESSERA_HOST_PROCESSOR,
            ticket.granted % TESSERA_HOST_PROCESSOR, given, mask);
    RunChannel channel;
    memset(&channel, 0, sizeof(channel));
    int started_count = count - request.command;
    char **const watched = run_channel_open(&channel, &request, arguments + request.command, count - request.command,
                                            &ask.signum, &started_count);
    char *const *const words = (watched != NULL) ? watched : (arguments + request.command);
    RunChild child;
    memset(&child, 0, sizeof(child));
    int code = RUN_NOT_STARTED;
    const unsigned long long started = run_now();
    if (run_start(&child, words, started_count, mask, &channel))
    {
        run_wait(&child, &channel, client, &ticket, &error);
        code = run_finish(&child);
    }
    else
    {
        fprintf(stderr, "  tessera_run: %s could not be started\n", arguments[request.command]);
    }
    free(watched);
    run_channel_close(&channel);
    const unsigned long long ran = run_now() - started;
    if (tessera_job_release(client, &ticket, &error) == 0L)
    {
        fprintf(stderr, "  tessera_run: %s released after %llu.%03llu s, exit %d, peak %llu.%03llu processors\n", label,
                ran / RUN_MILLION, (ran % RUN_MILLION) / RUN_THOUSAND, code, ticket.last_peak / TESSERA_HOST_PROCESSOR,
                ticket.last_peak % TESSERA_HOST_PROCESSOR);
    }
    else
    {
        fprintf(stderr, "  tessera_run: %s ended with exit %d, and the daemon did not answer its release\n", label, code);
    }
    return code;
}
