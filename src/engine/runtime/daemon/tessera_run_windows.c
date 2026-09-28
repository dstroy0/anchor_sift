// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tessera_run_windows.c: starting, timing and ending a job's process tree on Windows
#include "tessera_run_internal.h"

#if (defined(_WIN32))
_Alignas(8) static const char s_run_unjoined[] =
    "  tessera_run: the command could not join a job object of its own; it runs on the processors given, unmeasured\n";
#endif
#if (defined(_WIN32))
// the command's words as one command line, the program first, each quoted as the C runtime splits them back
static char *run_command_line(const char *program, char *const *words, int count)
{
    size_t capacity = 1u + (2u * strlen(program)) + 3u;
    for (int at = 1; at < count; at += 1)
    {
        capacity += (2u * strlen(words[at])) + 3u;
    }
    char *const line = (char *)malloc(capacity);
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
static const char *run_program_found(const char *program, char *found, size_t capacity)
{
    const char *const path = getenv("PATH");
    if ((strpbrk(program, "\\/:") != NULL) || (path == NULL))
    {
        return program;
    }
    // the capacity is a buffer size this file holds, which a DWORD counts on every Windows target
    const DWORD length = SearchPathA(path, program, ".exe", (DWORD)capacity, found, NULL);
    return ((length != 0u) && (length < capacity)) ? found : program;
}

// an interrupt reaches the command too, which ends; this process waits for it, then releases its job
static BOOL WINAPI run_console_interrupt(DWORD event)
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
int run_names_wsl(const char *program)
{
    const char *base = program;
    for (const char *walk = program; *walk != '\0'; walk += 1)
    {
        base = ((*walk == '\\') || (*walk == '/')) ? (walk + 1) : base;
    }
    return (_stricmp(base, "wsl.exe") == 0) || (_stricmp(base, "wsl") == 0);
}

// a path on a drive as WSL mounts it, X:\a\b as /mnt/x/a/b; 0 for a path on no drive letter
int run_mounted_path(const char *path, char *mounted, size_t capacity)
{
    const int upper = (path[0] >= 'A') && (path[0] <= 'Z');
    const int lower = (path[0] >= 'a') && (path[0] <= 'z');
    if ((!upper && !lower) || (path[1] != ':') || ((path[2] != '\\') && (path[2] != '/')))
    {
        return 0;
    }
    // a capital letter's lower case is the same letter 32 above it, still a char
    const char drive = upper ? (char)(path[0] + ('a' - 'A')) : path[0];
    const int written = snprintf(mounted, capacity, "/mnt/%c/%s", drive, path + 3);
    // a non-negative length is compared whole against the capacity
    if ((written <= 0) || ((size_t)written >= capacity))
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
int run_wsl_program(char *mounted, size_t capacity)
{
    const char *const named = getenv("TESSERA_RUN_WSL");
    if ((named != NULL) && (named[0] != '\0'))
    {
        const int written = snprintf(mounted, capacity, "%s", named);
        // a non-negative length is compared whole against the capacity
        return (written > 0) && ((size_t)written < capacity);
    }
    char path[ENGINE_PATH_CAPACITY];
    const size_t length = run_own_path(path, sizeof(path));
    // the Linux program is this one's name without its extension
    if ((length < 4u) || (_stricmp(path + length - 4u, ".exe") != 0))
    {
        return 0;
    }
    path[length - 4u] = '\0';
    return (GetFileAttributesA(path) != INVALID_FILE_ATTRIBUTES) && run_mounted_path(path, mounted, capacity);
}

int run_start(RunChild *child, char *const *words, int count, unsigned long long mask, RunChannel *channel)
{
    char found[ENGINE_PATH_CAPACITY];
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
    const int limited = (child->job != NULL) &&
                        SetInformationJobObject(child->job, JobObjectBasicLimitInformation, &limits, sizeof(limits));
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
    SetConsoleCtrlHandler(run_console_interrupt, TRUE);
    return 1;
}

int run_ended(RunChild *child, unsigned long long microseconds)
{
    // a sweep's milliseconds fit a DWORD
    const DWORD milliseconds = (DWORD)(microseconds / RUN_THOUSAND);
    return WaitForSingleObject(child->process, milliseconds) != WAIT_TIMEOUT;
}

int run_finish(RunChild *child)
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

int run_cpu(const RunChild *child, unsigned long long *microseconds)
{
    JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting;
    memset(&accounting, 0, sizeof(accounting));
    if ((child->job == NULL) || !QueryInformationJobObject(child->job, JobObjectBasicAccountingInformation, &accounting,
                                                           sizeof(accounting), NULL))
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
unsigned long long run_end_command(RunChild *child, unsigned long long grace)
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

void run_folder_make(const char *path)
{
    CreateDirectoryA(path, NULL);
}

int run_folder_exists(const char *path)
{
    const DWORD attributes = GetFileAttributesA(path);
    return (attributes != INVALID_FILE_ATTRIBUTES) && ((attributes & FILE_ATTRIBUTE_DIRECTORY) != 0u);
}

// the parent's record, shared only for reading: while this process lives no other opens it for writing, and by that
// its child finds that it lives, from Windows or from inside WSL
int run_record_make(RunChannel *channel, const char *path)
{
    channel->record =
        CreateFileA(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    return channel->record != INVALID_HANDLE_VALUE;
}

void run_record_put(RunChannel *channel, const char *line, size_t length)
{
    DWORD moved = 0u;
    SetFilePointer(channel->record, 0, NULL, FILE_BEGIN);
    // a record's line is under its capacity of a hundred and sixty bytes
    WriteFile(channel->record, line, (DWORD)length, &moved, NULL);
}

void run_record_close(RunChannel *channel)
{
    CloseHandle(channel->record);
}

// 1 while the parent lives: its record is refused to an open for writing until its handles close with it
int run_parent_alive(const char *parent)
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
#endif
#if !(defined(_WIN32))

int run_process_read(unsigned long long pid, RunProcess *process)
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
    if ((after_name == NULL) ||
        (sscanf(after_name + 1, " %c %llu %*s %*s %*s %*s %*s %*s %*s %*s %*s %llu %llu %llu %llu", &process->state,
                &process->parent, &user, &system, &children_user, &children_system) != 6))
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
RunProcess *run_tree(pid_t root, unsigned long long *count)
{
    DIR *const listing = opendir("/proc");
    if (listing == NULL)
    {
        return NULL;
    }
    RunProcess *processes = NULL;
    unsigned long long capacity = 0ull;
    int ok = 1;
    *count = 0ull;
    for (const struct dirent *entry = readdir(listing); ok && (entry != NULL); entry = readdir(listing))
    {
        char *end = NULL;
        const unsigned long long pid = strtoull(entry->d_name, &end, 10);
        RunProcess read;
        if ((end == entry->d_name) || (*end != '\0') || !run_process_read(pid, &read))
        {
            continue;
        }
        if (*count == capacity)
        {
            capacity = (capacity == 0ull) ? 256ull : (capacity * 2ull);
            RunProcess *const grown = (RunProcess *)realloc(processes, (size_t)capacity * sizeof(RunProcess));
            ok = grown != NULL;
            processes = ok ? grown : processes;
        }
        if (ok)
        {
            processes[*count] = read;
            *count += 1ull;
        }
    }
    closedir(listing);
    if (!ok || (processes == NULL))
    {
        free(processes);
        return NULL;
    }
    for (unsigned long long at = 0ull; at < *count; at += 1ull)
    {
        // a child's pid is positive. It converts exactly
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
#endif
