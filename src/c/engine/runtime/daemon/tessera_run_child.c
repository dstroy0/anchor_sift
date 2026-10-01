// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tessera_run_child.c: the job's folders and records, the daemon channel, the wait and the child
#include "tessera_run_internal.h"

_Alignas(8) static const char s_run_unwatched[] =
    "  tessera_run: the command runs with no child to watch it: its records could not be made under the "
    "host's tessera state\n";
_Alignas(8) static const char s_run_children[] = "children";
#if (defined(_WIN32))
_Alignas(8) static const char s_run_wsl_unmeasured[] =
    "  tessera_run: only wsl.exe itself is measured: the Linux command needs -e or -- before it, and a Linux "
    "tessera_run ($TESSERA_RUN_WSL, or tessera_run beside this program)\n";
#endif

// every folder along the path made where it is not; 1 where the last is there
static int run_folders_make(char *path)
{
    for (size_t at = 1u; path[at] != '\0'; at += 1u)
    {
        const char character = path[at];
        if ((character == '/') || (character == RUN_SEPARATOR))
        {
            path[at] = '\0';
            run_folder_make(path);
            path[at] = character;
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
    char line[RUN_RECORD_CAPACITY];
    const int length = channel->bound ? snprintf(line, sizeof(line), "launched %llu child %llu keepalive %llu\n",
                                                 channel->launched, channel->child, channel->keepalive)
                                      : snprintf(line, sizeof(line), "launching %llu keepalive %llu\n",
                                                 channel->launched, channel->keepalive);
    // a record's length is positive and compared whole against its capacity
    if ((length > 0) && ((size_t)length < sizeof(line)))
    {
        // a record's length is positive. It converts exactly
        run_record_put(channel, line, (size_t)length);
    }
    channel->keepalive += 1ull;
}

void run_record_launched(RunChannel *channel, unsigned long long pid)
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
    const size_t capacity = sizeof(channel->records);
    // the capacity is a buffer size this file holds, which an unsigned int counts
    if (!tessera_path_state(host, records, (unsigned int)capacity))
    {
        return 0;
    }
    size_t at = strlen(records);
    const int folder = snprintf(records + at, capacity - at, "%c%s", RUN_SEPARATOR, s_run_children);
    // a non-negative length is compared whole against the capacity
    if ((folder <= 0) || ((size_t)folder >= (capacity - at)) || !run_folders_make(records))
    {
        return 0;
    }
    at = strlen(records);
    const int named = snprintf(records + at, capacity - at, "%c%016llx-", RUN_SEPARATOR, run_self_pid());
    // a non-negative length is compared whole against the capacity
    if ((named <= 0) || ((size_t)named >= (capacity - at)))
    {
        return 0;
    }
    at = strlen(records);
    for (unsigned int byte = 0u; byte < ENGINE_SIGNUM_BYTES; byte += 1u)
    {
        if ((at + 3u) > capacity)
        {
            return 0;
        }
        snprintf(records + at, capacity - at, "%02x", signum->bytes[byte]);
        at += 2u;
    }
    return 1;
}

// a child tessera_run is put between this process and the command where one is asked for (--child), and always for a
// WSL command, whose tree only a child inside the VM can measure. The words to start, NULL-ended, or NULL for the
// command as it is
char **run_channel_open(RunChannel *channel, const RunRequest *request, char *const *words, int count,
                        const EngineSignum *signum, int *started_count)
{
    int inside_at = 0;
#if defined(_WIN32)
    channel->across = run_names_wsl(words[0]);
    if (channel->across)
    {
        inside_at = 1;
        while ((inside_at < count) && (strcmp(words[inside_at], "-e") != 0) &&
               (strcmp(words[inside_at], "--exec") != 0) && (strcmp(words[inside_at], "--") != 0))
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
    char path[ENGINE_PATH_CAPACITY];
    const int placed = (channel->across || (run_own_path(channel->program, sizeof(channel->program)) != 0u)) &&
                       run_records_place(channel, signum) &&
                       run_path_joined(channel->records, ".parent", path, sizeof(path)) &&
                       run_record_make(channel, path);
#if defined(_WIN32)
    const int named =
        placed && (channel->across
                       ? run_mounted_path(channel->records, channel->named_records, sizeof(channel->named_records))
                       : run_path_joined(channel->records, "", channel->named_records, sizeof(channel->named_records)));
#else
    const int named =
        placed && run_path_joined(channel->records, "", channel->named_records, sizeof(channel->named_records));
#endif
    // a word count is positive. It converts exactly
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
    // the words before the command's own, a count at least 0. It converts exactly
    memcpy(watched, words, (size_t)inside_at * sizeof(char *));
    watched[inside_at] = channel->program;
    watched[inside_at + 1] = "--parent";
    watched[inside_at + 2] = channel->named_records;
    watched[inside_at + 3] = "--";
    // the command's own words, a positive count. It converts exactly
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
    char path[ENGINE_PATH_CAPACITY];
    char state[RUN_STATE_CAPACITY];
    unsigned long long numbers[RUN_NUMBERS] = {0ull, 0ull, 0ull, 0ull};
    const int fields =
        run_path_joined(channel->records, ".child", path, sizeof(path)) ? run_record_read(path, state, numbers) : -1;
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
void run_channel_close(RunChannel *channel)
{
    if (!channel->open)
    {
        return;
    }
    run_record_close(channel);
    char path[ENGINE_PATH_CAPACITY];
    const int ended = strcmp(channel->state, "ended") == 0;
    FILE *const logged =
        (!ended && run_path_joined(channel->records, ".log", path, sizeof(path))) ? fopen(path, "rb") : NULL;
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
void run_wait(RunChild *child, RunChannel *channel, TesseraClient *client, TesseraTicket *ticket, EngineError *error)
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
        const int complete = (spent != 0ull) && (!ended || ((2ull * spent) >= RUN_SWEEP_MICROSECONDS));
        if (reporting && (read || across) && complete)
        {
            // the processors used over the reading, in thousandths: the tree's processor time over the wall time
            const unsigned long long own =
                read ? ((((cpu > cpu_before) ? (cpu - cpu_before) : 0ull) * TESSERA_HOST_PROCESSOR) / spent) : 0ull;
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
    char path[ENGINE_PATH_CAPACITY];
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
int run_child(const RunRequest *request, char **arguments, int count, unsigned long long mask, const char *label)
{
    const char *const records = request->parent;
    const unsigned long long self = run_self_pid();
    const unsigned long long silent = run_limit("TESSERA_RUN_SILENT_MS", RUN_SILENT_MICROSECONDS);
    const unsigned long long unresponsive = run_limit("TESSERA_RUN_UNRESPONSIVE_MS", RUN_UNRESPONSIVE_MICROSECONDS);
    char parent[ENGINE_PATH_CAPACITY];
    char entry[RUN_ENTRY_CAPACITY];
    char state[RUN_STATE_CAPACITY];
    unsigned long long heard[RUN_NUMBERS] = {0ull, 0ull, 0ull, 0ull};
    if (!run_path_joined(records, ".parent", parent, sizeof(parent)) || (run_record_read(parent, state, heard) < 2))
    {
        snprintf(entry, sizeof(entry), "child %llu: no launch record at %s.parent; %s was not run", self, records,
                 label);
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
        const int alive = run_parent_alive(parent);
        snprintf(entry, sizeof(entry), "child %llu: its parent %s and did not record this pid; %s was not run", self,
                 alive ? "holds its record" : "is gone", label);
        run_log(records, entry);
        run_child_write(records, "orphaned", self, 0ull, 0ull, 1, RUN_ORPHANED);
        return RUN_ORPHANED;
    }
    // the parent's record names the child it launched: the command runs only where that is this process
    if (heard[1] != self)
    {
        snprintf(entry, sizeof(entry),
                 "child %llu: the parent's record names child %llu, launched as %llu, not this "
                 "process; %s was not run",
                 self, heard[1], heard[0], label);
        run_log(records, entry);
        return RUN_FAILED;
    }
    snprintf(entry, sizeof(entry),
             "child %llu, launched as %llu: its pid confirmed against the parent's record; %s runs "
             "on processors 0x%llx at below normal priority",
             self, heard[0], label, mask);
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
    int alive = 1;
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
            snprintf(entry, sizeof(entry), "child %llu: the parent's keepalive is heard again after %llu.%03llu s",
                     self, (now - heard_at) / RUN_MILLION, ((now - heard_at) % RUN_MILLION) / RUN_THOUSAND);
            run_log(records, entry);
        }
        looked = kept ? 0 : looked;
        heard_at = kept ? now : heard_at;
        keepalive = kept ? heard[2] : keepalive;
        const unsigned long long silence = now - heard_at;
        // a keepalive unchanged past the silent time: the parent is looked for, by whether it still holds its record
        alive = (silence < silent) || run_parent_alive(parent);
        orphaned = !ended && (!alive || (silence >= unresponsive));
        if (!ended && !orphaned && (silence >= silent) && !looked)
        {
            snprintf(entry, sizeof(entry),
                     "child %llu: no keepalive for %llu.%03llu s; the parent still holds its record, "
                     "and is given until %llu s",
                     self, silence / RUN_MILLION, (silence % RUN_MILLION) / RUN_THOUSAND, unresponsive / RUN_MILLION);
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
        snprintf(entry, sizeof(entry),
                 "child %llu: its parent %s, with no keepalive for %llu.%03llu s; %s was asked to "
                 "end, %llu of its processes ended by force, exit %d. The parent may relaunch or resume it",
                 self, alive ? "holds its record but is not responding" : "is gone", silence / RUN_MILLION,
                 (silence % RUN_MILLION) / RUN_THOUSAND, label, forced, code);
        run_log(records, entry);
        return RUN_ORPHANED;
    }
    const int code = run_finish(&child);
    run_child_write(records, "ended", self, cpu, run_now() - began, 1, code);
    snprintf(entry, sizeof(entry), "child %llu: %s ended, exit %d, after %llu.%03llu s of processor time", self, label,
             code, cpu / RUN_MILLION, (cpu % RUN_MILLION) / RUN_THOUSAND);
    run_log(records, entry);
    return code;
}
