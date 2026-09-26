# tessera: submitting jobs and running the daemon

**Purpose:** how to start tessera's daemon, submit a device job to it, and read what it tells you back.

**Scope:** `engine/daemon`: the daemon (`tessera_daemon.c`), the client calls (`tessera.h`,
`tessera_client.c`), and the suite in `test/`. The theory (the accounting, backfill, the deadline heap) is in
[tessera_scheduler.md](../../theory/workbook/tessera_scheduler.md).

## What it does

One daemon runs for each device on a host. Every process that wants the device's memory submits a job to it and
declares how many bytes the job needs. The daemon measures what the process already holds on the device as it asks,
its **standing** (its CUDA context, and anything it kept from an earlier job), and counts it beside the declaration.
It admits jobs while the bytes they have yet to find fit the device's measured headroom, so several run at once. It measures each running job's process by pid on every sweep. A job that grows
past its declaration keeps running, and its client is told what it grew to. When a job is released, its measured
peak and run time are kept under its **signum**, and the next job with that signum is judged against that peak.

## Building

```bash
bash engine/daemon/test/run.sh
```

This builds and runs the whole suite, and builds the daemon into the run's build directory as
`tessera_daemon.exe` (Windows) or `tessera_daemon` (Linux). Run on Windows with an RTX 3070, 25 September:

| test | what it proves | result |
|---|---|---|
| `tessera_ledger_test` | the accounting, the standing beside the declaration, backfill with the head kept, the deadline heap | 0 failed (8 standing cases) |
| `tessera_frame_test` | the 128-byte frame, round trips and refused corruptions | 0 failed |
| `tessera_measure_test` | device bytes by pid (the PDH counter under WDDM) | 0 failed |
| `tessera_job_test` | the client against the built daemon, every path below | 25 checks, 0 failed |
| `tessera_run_test.sh` | host jobs through `tessera_run` (below): the exit code handed on, the command on the jobs' processors at below normal priority, its processors measured, a job waiting for one that holds them all, two that fit at once, the refusals, a command watched by a child (confirmed, a parent killed, on Linux a parent stopped, no launch record) | 14 checks, 0 failed on Windows; 15 on Linux (25 September, 23:00) |

The suite's run on 25 September, 22:14, found another tree's daemon (the knee's) answering this device's endpoint.
The job test's client therefore reached that daemon, which keeps its own state. The three checks that read the test's
own state failed (the precalc note in the lost ticket, the daemon's idle end, the history on disk): 20 checks, 3
failed. The lost ticket was in `%LOCALAPPDATA%\tessera`, that daemon's state. The endpoint names the device, not the
state: the job test proved the daemon only when no other daemon held the device. `run.sh` now gives its tests an
endpoint of their own, `TESSERA_RUNTIME`, which Windows reads into the pipe's name as Linux reads it into the socket's
folder. The job test and the host test each start a daemon there, apart from the daemons real jobs are using.

A client links `tessera_client.c`, `tessera_paths.c`, `tessera_frame.c`, `tessera_self.c` and scriptura. The
daemon also links `tessera_ledger.c`, `tessera_measure.c` and obsignatio (`engine/base/obsignatio/obsignatio.cu`),
and `pdh` on Windows. On Linux both link `-ldl -lpthread`. It uses obsignatio's host seal (`obsignatio_seal`, `obsignatio_seal_holds`), so it never makes a CUDA
context of its own.

## Starting the daemon

**You normally don't start it.** A client that finds no daemon starts one itself, as long as its ask names the
daemon's path (`daemon_path`), then connects and carries on. The daemon ends itself once it has held no job for its
idle time. So the first job on a device starts the daemon and the last one lets it go.

To start it by hand:

```
tessera_daemon --device <32 lowercase hex digits> --luid <hex> --idle <microseconds>
```

- `--device`: the device's UUID, 16 bytes as 32 lowercase hex digits (`cudaDeviceProp::uuid`).
- `--luid`: the adapter's LUID in hex (`cudaDeviceProp::luid` on Windows; 0 elsewhere). Under WDDM it picks the
  adapter's per-process counter.
- `--idle`: how long the daemon waits with no job before it exits. Each submitted job's own idle time replaces
  it.

Only one daemon runs for each device. On Windows a second daemon's pipe fails at birth
(`FILE_FLAG_FIRST_PIPE_INSTANCE`). On Linux a second daemon can't take the lock file.

## Where it lives

| | Windows | Linux |
|---|---|---|
| endpoint | `\\.\pipe\tessera-<uuid>`, or `\\.\pipe\tessera-<$TESSERA_RUNTIME>-<uuid>` when it is set (a backslash in it written `_`) | `$TESSERA_RUNTIME`, else `$XDG_RUNTIME_DIR`, else `/tmp`, then `/tessera-<uuid>.sock` |
| state | `$TESSERA_STATE`, else `%LOCALAPPDATA%\tessera`, then `\<uuid>` | `$TESSERA_STATE`, else `$XDG_STATE_HOME/tessera`, else `$HOME/.local/state/tessera`, then `/<uuid>` |
| lost and found | `<state>\lostandfound\<identity>-<signum>\` | `<state>/lostandfound/<identity>-<signum>/` |

The state directory holds the history and lost and found.

**The history is sealed.** It is every signum's peak and run time, one 48-byte record each, then a 32-byte seal
over all of them: obsignatio's keyed BLAKE3 at the file level. The daemon writes it to `history.fresh` and renames
it over `history`. A save that fails is reported on the daemon's stderr with the path. On start the daemon refuses
a history whose seal doesn't hold, whose length is not whole records plus the seal, or that has no seal at all. It
says so with the path and exits, and no job is admitted. A missing history is a fresh start. A refused history is
never rewritten: move it aside to start fresh, or put back a good copy.

**Tickets are sealed.** Each ticket in lost and found ends with a line `seal <64 hex digits>`, the same seal over
every byte above it. The daemon adds "precalc kept" to a ticket only when its seal holds, then seals it again.

## Submitting a job

Make the process's CUDA context before asking (`cudaFree(0)`), so the daemon measures it as standing instead of
finding it later as growth:

```c
#include "tessera.h"

cudaFree(0);                          // the context, measured with the process as it asks
TesseraJobAsk ask = {0};
memcpy(ask.device, properties.uuid.bytes, TESSERA_DEVICE_BYTES);   // cudaGetDeviceProperties
memcpy(&ask.luid, properties.luid, sizeof(ask.luid));             // Windows; 0 elsewhere
ask.signum = request_signum;          // the BLAKE3 root of the job's request: same request, same signum
ask.declared = bytes_needed;          // what the job needs on top of what its process holds; must not be 0
ask.holding_microseconds = 2000000;   // how long it may wait held over budget before it is lost
ask.sweep_microseconds = 20000;       // how often its process is measured while it runs; must not be 0
ask.idle_microseconds = 5000000;      // how long the daemon lives on once no job is left
ask.override_budget = 0;              // 1 admits it on its declaration even over its signum's peak
ask.daemon_path = "path/to/tessera_daemon.exe";   // lets the client start the daemon; NULL if one is running
ask.error = &error;

TesseraClient *client = NULL;
TesseraTicket ticket;
if (tessera_job_submit(&ask, &client, &ticket) == TESSERA_REFUSED) { /* the error says why */ }
```

`tessera_job_submit` blocks until the daemon decides. The ticket then says which of three things happened.

| the ticket | what happened | what to do |
|---|---|---|
| `asked == 0`, `lost == 0` | **admitted.** `granted` is the bytes reserved for it, and `standing` the bytes its process held as it asked, which `granted` includes | run the job, then release it |
| `asked == 1` | **held.** It declared more than its signum's last peak (`last_peak`) | override it, or wait |
| `lost == 1` | **lost.** It was held past its holding time | keep its precalc in `lost_path`, then say so |

A job that doesn't fit the headroom yet waits inside the submit until it fits, with no ticket until then. A job
with a signum never seen before is admitted on its declaration over its standing, and measured.

**Held.** If the job means to take more than last time, confirm it with `tessera_job_override(client, &ticket,
&error)`, which admits it on its declaration. Or wait with `tessera_job_wait(client, &ticket, &error)`: it
returns when the job is admitted or lost.

**Lost.** Write whatever the job had already worked out into `ticket.lost_path`, beside the ticket the daemon
wrote there. Then call `tessera_job_precalc_kept(client, &error)`, which releases the job and ends the client.
A later run can resume from that directory instead of starting over.

## Running and releasing

Once admitted, the job uses the device as it normally would. The daemon measures its process every
`sweep_microseconds`. If the job holds more than its reservation, the reservation grows to match and the client
is told. Growth never stops a running job, but nothing new is admitted while the device is overcommitted.

```c
tessera_job_release(client, &ticket, &error);   // ends the client
// ticket.granted   the reservation at the end
// ticket.last_peak the peak measured by its pid, kept under its signum
// ticket.grown_to  the largest size it was told it grew to (0 if it never outgrew its declaration)
```

If `last_peak` is larger than its standing and `declared` together, the job underdeclared. Report it, so the next
declaration is right. Don't
use `grown_to` for that: a job whose reservation is already its kept peak is never told it grew, however far it
outruns its declaration.

If a process dies without releasing, its connection closes and the daemon sees it at once. The job's reservation
is freed and its ticket goes to lost and found. The periodic sweep catches the same thing if the close is missed,
and a pid reused by a new process is never taken for the old one.

## What the job test shows

`test/tessera_job_test.cu` runs every path above against the real daemon, starting it through `daemon_path`:

1. A new signum declaring 64 MiB is admitted with 64 MiB granted over its standing, which was 24,576 bytes: the test
   makes no context before it asks. It then takes 256 MiB of device memory, and its release reports that it grew to
   412,254,208 bytes, with a peak of 412,254,208. That is the process's whole dedicated memory, CUDA context
   included. The test keeps that memory to its end.
2. The same signum declaring four times that peak is held, and the ask names the kept peak. The override
   admits it on its declaration over its standing, which is the memory it kept: 412,254,208 bytes.
3. Declaring exactly the kept peak is admitted at once, over its standing.
4. Declaring four times the peak with no answer is held for its 0.4 s holding time, then lost. The ticket names
   its lost and found directory, and the precalc kept releases it. The ticket's seal holds with the note in it.
5. Once the daemon has ended, the history it left is whole records and a seal. The test damages one byte of it,
   then cuts one byte off, then strips the seal. Each time the submit is refused because no daemon starts on it.
   With the file restored, the daemon starts and the same signum over its peak is asked with the kept peak, so the
   history really was read.

The test runs in its own state directory (`run.sh` sets `TESSERA_STATE` to `<build>/tessera_state`), because
part 5 damages the history on purpose.

## The engine's runs

`track_driver` submits every run through tessera (`cell_tracking/src/track_driver/track_driver.cu`,
`run_job_submit`/`run_job_release`). `--ingest` is one job, and each `--run` part is one job:

- **Signum:** the host BLAKE3 of the part's name, a zero byte, then the effective .cfg.
- **Declaration:** what the part holds on the device for its largest sample (`run_job_lattice_bytes`). The lattice
  in 16-bit lanes, rounded to the 2 MiB page, for every part but iapx-prove, which holds none of its own. And, for
  every part that lifts or lowers a lattice (all but schedule and fingerprint), the tower's pool
  (`tower_hold_bytes`: the coefficients and scratch as ints, 8 bytes a voxel) and compression's chunk pool
  (`compression_hold_bytes`), each kept for the largest lattice. The stream, sized by the values, and the seal's
  passing buffers are left to the kept peak. The lanes come from the source's shape for ingest
  (`engine_source_lanes`, which reads no voxel), and from the `.iapx` head for every other part.
- **Standing:** the driver makes its context before its first job, so each job stands on it. The admitted line prints
  the standing, and the release compares the peak against the standing and the declaration together.
- **Daemon:** `tessera_daemon` beside the driver, which `build_driver.sh` builds and publishes with it.
- **Times:** holding 2 s, sweep 20 ms, idle 5 s.
- **When held:** `--override` overrides; otherwise the job waits, is lost, and the part fails.
- **No daemon:** if the job can't be submitted, the part doesn't run.

Run on 24 September, on one sample (44b6_0113de3b) in a scratch set, with the daemon's real state:

| run | declared | peak measured |
|---|---|---|
| `--ingest` | 838,860,800 | 5,091,037,184 |
| `--run iapx-prove` | 838,860,800 | 3,962,761,216 |
| `--run iapx-prove` again | 838,860,800 | 3,958,566,912 |

The history then held both signa, two records and the seal (128 bytes).

**A job is reserved the larger of its declaration and its signum's kept peak** (`tessera_ledger_wants`, 24
September). The runs above found that a job used to be reserved only its declaration, so the second prove held
839 MB of reservation while it used 3.96 GB. Until a sweep grew the reservation, another job could be admitted into
that room. Admission, the head's shadow, the backfill's spare and the reservation now all use the wanted bytes. A
declaration over the kept peak is still held and asked, as before. With the new rule, the same prove was admitted
with 3,958,566,912 reserved, its kept peak, and released at that peak. The ledger test checks it: declaring 100 under
a kept peak of 450, the job waits while the headroom is 300, and it is admitted with 450 reserved once the headroom
is 500.

**The declaration stands on what the process already holds** (25 September). The daemon measures the process as it
asks (by pid, or from the process's own report under WSL) and the job wants its standing and its declaration
together, or its kept peak when that is more. The device's measured use already counts the standing, so admission,
the head's shadow and the backfill weigh only what the job has yet to find: what it wants less its standing. An
admitted job's use starts at its standing until its first sweep, so the headroom owes the device only those bytes.
The held rule is unchanged: the declaration alone is weighed against the kept peak, which is the whole process's.
The ledger test checks it with a device of 1,000 bytes, 300 in use. A job standing on 200 and declaring 650 wants 850,
more than the 700 free. But it has only 650 to find, so it is admitted with 850 reserved, and the headroom left is 50.
Its peak of 900 is kept. The same signum standing on 300 and declaring 650 is not held, and wants 950. Declaring 950
is held.

### The sims

Every sim that uses the device is one job too (`engine/sims/sim_job.cu`). It calls `sim_job_submit` before its first
device allocation, and `sim_close` releases the job:

- **Signum:** the sim's name and its arguments.
- **Declaration:** the buffers the sim names for itself, on top of its standing: `sim_job_submit` makes the context
  before it asks, and prints the standing when admitted.
- **Daemon:** `$TESSERA_DAEMON`, else the `tessera_daemon` beside the sim, which `engine/sims/run.sh` builds there.
- **When held:** `TESSERA_OVERRIDE=1` admits a declaration over the kept peak.

`ask_state` and `ka_psi` never touch the device and submit nothing. Run on 24 September. Each sim's count includes
its two tessera checks:

| sim | declared | peak measured | checks |
|---|---|---|---|
| period_power | 262,144 | 145,915,904 | 601, 0 failed |
| nbody_lattice | 26,542,080 | 173,178,880 | 11, 0 failed |
| noise_floor | 9,142,272 | 187,858,944 | 13, 0 failed |
| root_universal | 339,510 | 152,207,360 | 1,270, 0 failed |
| fixed_pattern | 141,056 | 143,818,752 | 12, 0 failed |
| classify_reject_recover | 118,016 | 145,915,904 | 9, 0 failed |
| chaitin_omega (L 16, on the engine) | 30,256 | 286,425,088 | 16, 0 failed |

Nothing in the repository loads the engine DLL (`build_engine.sh` builds it and nothing calls it), so there is no
other caller to submit. `cell_tracking/src/cell_shift.c` runs on anchor_sift's engine, not this one.

## Host jobs: the host's processors

A device of sixteen zero bytes names the host's processors (`tessera_device_names_host`). Its daemon admits processor
jobs as a device's daemon admits memory jobs, and counts in thousandths of one logical processor
(`TESSERA_HOST_PROCESSOR`). The ledger is the device's own: admission, backfill, the kept peak per signum, growth and
the sealed history are unchanged.

- **Capacity.** Every logical processor but those of the host's last two cores, which are kept for the desktop
  (`tessera_self_host_mask`). `TESSERA_HOST_KEPT_CORES` changes the two, and one core is always left to jobs. The
  cores are read from `GetLogicalProcessorInformationEx` on Windows and from sysfs `thread_siblings` on Linux. On this
  machine (i7-5960X, 8 cores, 16 logical) that is logical 0 to 11, mask `0xfff`, 12,000 thousandths.
- **In use.** The running jobs' reports, summed. Nothing else on the host is counted: the desktop's work runs on the
  kept cores.
- **Measured.** Each job reports its own use (`tessera_job_report`), as a job under WSL reports its device bytes, and
  the daemon runs in reported mode. A host job stands on nothing. A report's growth is told back, and the next report
  reads it: no telling waits in the pipe.

**`tessera_run`** (`tessera_run.c`) wraps any command in a host job:

```
tessera_run --processors <count> [--name <text>] [--child] -- <command> [arguments]
```

- **Signum:** the name, then every word of the command.
- **Declaration:** the count times 1,000, with `override_budget` set: a count past the signum's kept peak is not held
  for asking. The job still reserves its kept peak where that is more than the count, as every job does (a build
  declaring 1 reserved nvcc's measured 3.430 on its next run). Sweep 1 s, idle 30 s. The daemon is
  `$TESSERA_DAEMON`, else the `tessera_daemon` beside it.
- **The command** starts once the job is admitted, pinned to the mask at below normal priority. On Windows it runs in a
  job object of its own (`JOB_OBJECT_LIMIT_AFFINITY`), created with `BELOW_NORMAL_PRIORITY_CLASS`, which every process
  it starts inherits. On Linux the child sets `sched_setaffinity` and at least nice 10 before its exec.
- **Its program**, named with no folder, is found along `PATH` as the shell that started `tessera_run` finds it.
  `CreateProcess` alone looks in the system folders first, where `bash` is WSL's launcher: the tracker's first builds
  under `tessera_run` ran WSL's bash on a Windows path and exited 127.
- **Readings.** Each second it reports the command tree's processors: the job object's user and kernel time on
  Windows, or on Linux the ticks of the command and every process descended from it, read from `/proc`, over the wall
  time. The last reading counts when it spans half a sweep.
- **Exit.** The command's own code. 125 when `tessera_run` refuses (its usage, more processors than the host gives
  jobs, no admission), 127 when the command does not start, 124 when a child ended the command for want of its parent
  (below). An interrupt or a hangup reaches the command; `tessera_run` waits for it to end, then releases.

`run.sh` publishes `tessera_run` and its daemon to `build/tessera_host/` once the host test holds. A copy that is
running is renamed aside first (`.replaced`): Windows lets a running program be renamed but not overwritten, and the
jobs already under it keep it. What the test printed on 25 September, 23:00, with the tracker's and the knee's builds
running beside it on the real host daemon:

| run | admitted after | processors reserved | peak |
|---|---|---|---|
| 2 threads for 1.5 s, exit 7 | 0.014 s | 2.000 of 12 | 1.997 |
| 1 thread, declaring all 12 | 0.000 s | 12.000 | 0.994 |
| 1 processor, started 0.5 s after it | 1.875 s | 1.000 | 0.000 (0.108 s, no whole reading) |
| 2 processors, then 2 more 0.5 s later | 0.000 s, 0.000 s | 2.000, 2.000 | 0.982, 0.000 |

### A child to watch the command

`--child`, and every WSL command, puts a second `tessera_run` (the child) between the job and its command. The
parent holds the ticket; the child runs the command and watches the parent. They share three records, named as a lost
ticket is, under the host's state: `<state>/children/<parent pid>-<signum>` then `.parent`, `.child` and `.log`.

1. **The launch is recorded first.** The parent makes its record and holds it open for its whole life, shared only for
   reading. It starts the child suspended (Windows) or waiting on a pipe (Linux), writes `launching <pid>`, then lets
   it run.
2. **The child says it lives and checks its pid.** It reads the launch record and writes `alive <pid>`. The parent
   records that pid (`launched <pid> child <pid>`): on one system only when it is the pid it launched, and across the
   VM the child's own. The child runs the command only once the record names its own pid, and a record naming another
   process leaves the command unrun (exit 125, logged). A child with no launch record runs nothing.
3. **Keepalive.** The parent rewrites its record every sweep with a keepalive one higher. The child writes its
   command's processor time and the wall time it read it at, on its own clock, every sweep.
4. **No keepalive: the child looks for the parent.** After 10 s with no keepalive (`TESSERA_RUN_SILENT_MS`) it tries to
   open the parent's record for writing. While the parent lives that is refused: Windows refuses it by the record's
   sharing, from Windows or from inside WSL, and on Linux the parent holds a lock on it. Once the parent is gone the open
   succeeds, and the child ends the command at once. A parent that still holds its record but keeps no keepalive for
   60 s (`TESSERA_RUN_UNRESPONSIVE_MS`) is not responding, and the child ends the command then.
5. **The command ends gracefully, and the log says so.** On Linux the command's tree is sent SIGTERM and given 10 s,
   then SIGKILL for what is left. On Windows a console command has no signal it must heed, and its job is ended at
   once. The child logs the parent's state, the silence, how many processes were ended by force and the command's exit,
   leaves its record at `orphaned`, and exits 124. The records are kept for whoever relaunches or resumes the job. A
   clean end removes them.

| run, 25 September | Windows | Linux (WSL 2) |
|---|---|---|
| 2 threads for 1.5 s under a child, exit 5 | confirmed, exit 5, 3.000 s of processor time, peak 1.991 | confirmed, exit 5, 2.990 s, peak 1.950 |
| the parent killed 3 s into a 60 s burn | gone after 10.056 s with no keepalive; ended by force; records kept | gone after 10.056 s; SIGTERM, exit 143, none by force |
| the parent stopped (SIGSTOP), limits 1 s and 3 s | not run: Windows has no stop to send it | holds its record at 1.005 s; not responding at 3.017 s; SIGTERM, exit 143; the parent, let go, handed on 124 |

**From WSL** the Windows `tessera_run` holds the ticket in the one budget:
`tessera_run.exe --processors N -- wsl.exe -e bash /mnt/<path>/script.sh`. Windows does see the VM's processors: the
performance counter `\Process(vmmemwsl)\% Processor Time`, readable without elevation, climbed to 443% of one processor
during a two-processor burn. But the counter is the whole VM, and the VM is not in the job object, which held only
`wsl.exe` (a peak of 0.061). Inside the VM each job's tree is readable from `/proc`, as `top` reads it. The Windows
`tessera_run` therefore puts the Linux one in front of the Linux command, after `-e`, `--exec` or `--`. The Linux `tessera_run`
is `$TESSERA_RUN_WSL` (a path inside WSL), else the `tessera_run` beside the Windows one, reached as
`/mnt/<drive>/...`. The Linux one pins the command to the host's mask inside the VM and makes it at least nice 10, then
reports its processors in its record, which the parent adds to its own reading. Without `-e` or `--`, or with no Linux
`tessera_run`, only `wsl.exe` is measured, and it says so.

| WSL run, 25 September | result |
|---|---|
| two `yes` for 8 s, 2 processors | the command at affinity `fff`, nice 10; child 758 (Linux) confirmed as launched 46716 (the Windows `wsl.exe`); 16.080 s of processor time; peak 2.032 |
| the same for 60 s, the Windows parent killed at 6 s | the child found it gone after 10.135 s with no keepalive; SIGTERM, exit 143, none by force; `wsl.exe` ended about 12 s after the kill; no `yes` left in the VM; its record `orphaned 776 cpu 34640000 wall 16315524 exit 143` |
| the Linux suite, `wsl.exe -e bash tessera_linux.sh` | watched by child 661: exit 0, 27.120 s of processor time |

A first run of the WSL burn peaked at 3.887. The parent read the child's cumulative time on its own clock, and a read
that caught the record mid-rewrite folded two seconds into one reading. The child now writes the wall time beside the
processor time, and the parent takes the rate between two records on the child's clock. The same run's orphaned record
read `cpu 0`: the command's tree had lost its processes to the signal. A child's processor time now never falls.

**Linux** (WSL 2, the whole suite carried to ext4, 25 September, 23:01): the host test held 15 checks, 0 failed, with
the mask read from sysfs as `0xfff` and two threads peaking at 1.989 processors. The same run's job test held 25
checks, 0 failed, on a device daemon of its own. A host daemon under WSL keeps a budget apart from the Windows one: a
job in WSL shares the Windows budget only through the Windows `tessera_run`.

## Linux

Run on 24 September on WSL 2: kernel 6.18, gcc 13.3, CUDA 13.3, on the RTX 3070. The sources were carried to
ext4 by git: a tree object from a scratch index, then `git archive`. The run found and fixed these:

- `PATH_MAX` is not in strict C11's `limits.h`, so `engine_config.h` now takes it from `<linux/limits.h>`.
- `tessera_measure.c` needed `_GNU_SOURCE` for `syscall` and `pid_t`.
- The timer thread had no return. It now runs while the daemon lives.
- gcc warns on `noinline` together with `inline`, so the error helpers use `ENGINE_NOINLINE_HELPER`.
- Platform-only strings were declared on both platforms. They are now behind their `#if`.
- The daemon printed literal copies of its own string table. It now uses the table, and each ticket names its
  signum.

**Under WSL each job reports its own bytes.** WSL reaches the device through the Windows driver, so its NVML lists
no process's memory, and dxcore's `D3DKMTQueryVideoMemoryInfo` answers only for the calling process (asked about
another it returns `0xC000000D`). So on a paravirtual kernel (`tessera_self_paravirtual`, from
`/proc/sys/kernel/osrelease`) the daemon's measure opens in **reported** mode and measures no pid. Each admitted
client starts a thread that reads its own process's device bytes through dxcore (`tessera_self_measure` in
`tessera_self.c`, `libdxcore.so` loaded at run time) and sends them every sweep as a `TESSERA_ASK_MEASURED` frame. It
sends one last reading before its release. The daemon applies each one exactly as it would a pid measurement:
growth, the peak kept, the wake. A daemon in reported mode ignores these frames from any job but the sender's own.

| test | Linux (WSL 2) |
|---|---|
| ledger | 0 failed |
| frame | 0 failed |
| measure | 9 cases, 0 failed: this process read 0 bytes, then 427,819,008 after allocating 256 MiB |
| job | 24 checks, 0 failed: declared 64 MiB, grew to and peaked at 427,819,008 |

gcc builds all of it with 0 warnings. On a native Linux driver the daemon measures each pid through NVML and
ignores reports. This machine has no native Linux NVIDIA driver, so that path has not run.

**One endpoint, one daemon.** The socket path names the device, not the state, so a daemon with another
`TESSERA_STATE` can reach the same path. Before binding, a daemon now connects to the path: if something answers,
it says so and exits. It removes the socket file at idle only if that file is still the one it bound. Before this
fix, a daemon left over from the suite removed systemd's socket file when it went idle, and every later connect
failed.

## Service files

**Windows needs none.** The first client starts the daemon, `FILE_FLAG_FIRST_PIPE_INSTANCE` keeps it to one per
device, and it ends once it has been idle.

**Linux, systemd user units** in `service/`. The instance is the device's UUID as 32 lowercase hex digits:

```bash
cp tessera_daemon ~/.local/bin/
cp engine/daemon/service/tessera@.socket engine/daemon/service/tessera@.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now tessera@<uuid>.socket
```

- `tessera@.socket` listens on `%t/tessera-%i.sock` (`$XDG_RUNTIME_DIR`), the path the client already looks for.
- On the first connection systemd starts `tessera@.service`, which hands the socket over as fd 3 (`LISTEN_FDS=1`).
  The daemon takes that socket instead of binding its own. When idle it exits without removing the socket, and the
  next connection starts it again.
- A daemon that refuses to start (its history's seal fails, or the device can't be measured) accepts and closes
  every connection waiting on the socket before it exits, so the client that started it is refused and systemd has
  nothing queued to start it for again. `StartLimitIntervalSec=0` stops systemd's start limit from turning away the
  next real client.

Run on 24 September in WSL 2 (systemd 255), with the socket at
`/run/user/1000/tessera-70fc945bd257269d3ffdb316ae03ace1.sock`. The whole job test ran with a daemon path that
doesn't exist, so systemd started every daemon, in a scratch `TESSERA_STATE` set through `systemctl --user
set-environment`. It passed 24 checks, 0 failed, on three runs in a row, each straight after the suite. Every
refused history made one failed start and one refused client, and the restored history started a daemon that asked
over the kept peak.

**Docker.** Mount the host's socket into the container and name its folder with `TESSERA_RUNTIME`:

```bash
docker run --gpus all -v "$XDG_RUNTIME_DIR/tessera-<uuid>.sock:/run/tessera/tessera-<uuid>.sock" \
    -e TESSERA_RUNTIME=/run/tessera ...
```

The daemon reads a client's pid with `SO_PEERCRED`, which the kernel gives in the daemon's pid namespace, the
host's, and that is the pid NVML reports.

Run on 24 September with Docker Engine 29.1.3 in WSL 2. `test/tessera_socket_probe.c` is a client with no device of
its own. It submits one 1-byte job for a named device, with no daemon path, so only a listening socket can answer.
Built static and run in a container with the socket mounted and `TESSERA_RUNTIME=/run/tessera`:

- It connected to `/run/tessera/tessera-70fc945bd257269d3ffdb316ae03ace1.sock`.
- systemd started `tessera@70fc945bd257269d3ffdb316ae03ace1.service` on the container's connection.
- The daemon admitted the job and it released. The container had no GPU mounted, so its client had no bytes to
  report. The history it left held no record, just the seal (32 bytes).

## Not built yet

- A native Linux run, measuring by pid through NVML, including a container's job. This machine has no native Linux
  NVIDIA driver.
- A container on WSL reports its own bytes only when dxcore is mounted into it (`--gpus`). The probe above had
  none.
- A job from WSL can't use the Windows daemon, which could measure it by the Windows pid.
