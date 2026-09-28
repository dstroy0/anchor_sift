// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// tessera_run_posix.c: starting, timing and ending a job's process tree on POSIX
#include "tessera_run_internal.h"

#if !(defined(_WIN32))

int run_cpu(const RunChild *child, unsigned long long *microseconds)
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

int run_start(RunChild *child, char *const *words, int count, unsigned long long mask, RunChannel *channel)
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
    // a pid is positive. It converts exactly
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
int run_ended(RunChild *child, unsigned long long microseconds)
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

int run_finish(RunChild *child)
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
unsigned long long run_end_command(RunChild *child, unsigned long long grace)
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

void run_folder_make(const char *path)
{
    mkdir(path, 0755);
}

int run_folder_exists(const char *path)
{
    struct stat found;
    return (stat(path, &found) == 0) && S_ISDIR(found.st_mode);
}

// the parent's record, locked for this process's life and let go with it: how its child finds that it lives. The
// descriptor closes on exec: no child holds the lock with it
int run_record_make(RunChannel *channel, const char *path)
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

void run_record_put(RunChannel *channel, const char *line, size_t length)
{
    const ssize_t written = pwrite(channel->record, line, length, 0);
    (void)written;
}

void run_record_close(RunChannel *channel)
{
    close(channel->record);
}

// 1 while the parent lives. A Windows parent (this child runs in WSL) shares its record only for reading, and an open
// for writing errors while it lives; a Linux parent holds a lock on it. Either is let go when the parent ends
int run_parent_alive(const char *parent)
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
