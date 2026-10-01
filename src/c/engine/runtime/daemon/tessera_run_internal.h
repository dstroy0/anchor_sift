// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the tessera_run_*.c pieces share: its includes, types and the functions one piece calls in another
#ifndef TESSERA_RUN_INTERNAL_H
#define TESSERA_RUN_INTERNAL_H

#if !defined(_WIN32)
// fork, exec, the affinity mask, the pid descriptor, waitid, flock, gmtime_r and the clock are outside strict C11
#define _GNU_SOURCE
#endif
#include "../obsignatio/obsignatio.h"
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

#define RUN_RUNNING_MICROSECONDS 2000000ull
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
#define RUN_RECORD_CAPACITY 160u
#define RUN_STATE_CAPACITY 16u
#define RUN_ENTRY_CAPACITY 2048u
#define RUN_NUMBERS 4

#if defined(_WIN32)
#define RUN_SEPARATOR '\\'
#else
#define RUN_SEPARATOR '/'
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
    char records[ENGINE_PATH_CAPACITY];
    char named_records[ENGINE_PATH_CAPACITY];
    char program[ENGINE_PATH_CAPACITY];
    int open;
    int across;
    int bound;
    unsigned long long launched;
    unsigned long long child;
    unsigned long long keepalive;
    unsigned long long reported;
    unsigned long long reported_wall;
    unsigned long long rate;
    char state[RUN_STATE_CAPACITY];
#if defined(_WIN32)
    HANDLE record;
#else
    int record;
#endif
} RunChannel;

unsigned long long run_now(void);

void run_pause(unsigned long long microseconds);

unsigned long long run_self_pid(void);

int run_arguments(int count, char **arguments, RunRequest *request);

size_t run_own_path(char *path, size_t capacity);

int run_daemon_path(char *path, size_t capacity);

int run_signum(const RunRequest *request, char **arguments, int count, EngineSignum *signum, EngineError *error);

int run_path_joined(const char *first, const char *second, char *path, size_t capacity);

unsigned long long run_limit(const char *name, unsigned long long fallback);

int run_record_read(const char *path, char state[RUN_STATE_CAPACITY], unsigned long long numbers[RUN_NUMBERS]);

void run_log(const char *records, const char *entry);
#if (defined(_WIN32))

int run_names_wsl(const char *program);

int run_mounted_path(const char *path, char *mounted, size_t capacity);

int run_wsl_program(char *mounted, size_t capacity);

int run_start(RunChild *child, char *const *words, int count, unsigned long long mask, RunChannel *channel);

int run_ended(RunChild *child, unsigned long long microseconds);

int run_finish(RunChild *child);

int run_cpu(const RunChild *child, unsigned long long *microseconds);

unsigned long long run_end_command(RunChild *child, unsigned long long grace);

void run_folder_make(const char *path);

int run_folder_exists(const char *path);

int run_record_make(RunChannel *channel, const char *path);

void run_record_put(RunChannel *channel, const char *line, size_t length);

void run_record_close(RunChannel *channel);

int run_parent_alive(const char *parent);
#endif
#if !(defined(_WIN32))
typedef struct
{
    unsigned long long pid;
    unsigned long long parent;
    unsigned long long ticks;
    char state;
    int in_tree;
} RunProcess;

int run_process_read(unsigned long long pid, RunProcess *process);

RunProcess *run_tree(pid_t root, unsigned long long *count);

int run_cpu(const RunChild *child, unsigned long long *microseconds);

int run_start(RunChild *child, char *const *words, int count, unsigned long long mask, RunChannel *channel);

int run_ended(RunChild *child, unsigned long long microseconds);

int run_finish(RunChild *child);

unsigned long long run_end_command(RunChild *child, unsigned long long grace);

void run_folder_make(const char *path);

int run_folder_exists(const char *path);

int run_record_make(RunChannel *channel, const char *path);

void run_record_put(RunChannel *channel, const char *line, size_t length);

void run_record_close(RunChannel *channel);

int run_parent_alive(const char *parent);
#endif

void run_record_launched(RunChannel *channel, unsigned long long pid);

char **run_channel_open(RunChannel *channel, const RunRequest *request, char *const *words, int count,
                        const EngineSignum *signum, int *started_count);

void run_channel_close(RunChannel *channel);

void run_wait(RunChild *child, RunChannel *channel, TesseraClient *client, TesseraTicket *ticket, EngineError *error);

int run_child(const RunRequest *request, char **arguments, int count, unsigned long long mask, const char *label);

#endif
