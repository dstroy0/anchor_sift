# tessera: submitting jobs and running the daemon

**Purpose:** how to start tessera's daemon, submit a device job to it, and read what it tells you back.

**Scope:** `engine/daemon`: the daemon (`tessera_daemon.c`), the client calls (`tessera.h`,
`tessera_client.c`), and the suite in `test/`. The theory (the accounting, backfill, the deadline heap) is in
[tessera_scheduler.md](../../../theory_bucket/cell_tracking/tessera_scheduler.md).

## What it does

One daemon runs for each device on a host. Every process that wants the device's memory submits a job to it and
declares how many bytes the job needs. The daemon admits jobs while their declarations fit the device's measured
headroom; several run at once. It measures each running job's process by pid on every sweep. A job that grows
past its declaration keeps running, and its client is told what it grew to. When a job is released, its measured
peak and run time are kept under its **signum**, and the next job with that signum is judged against that peak.

## Building

```bash
bash engine/daemon/test/run.sh
```

This builds and runs the whole suite, and builds the daemon into the run's build directory as
`tessera_daemon.exe` (Windows) or `tessera_daemon` (Linux). Run on Windows with an RTX 3070, 24 September:

| test | what it proves | result |
|---|---|---|
| `tessera_ledger_test` | the accounting, backfill with the head kept, the deadline heap | 0 failed |
| `tessera_frame_test` | the 128-byte frame, round trips and refused corruptions | 0 failed |
| `tessera_measure_test` | device bytes by pid (the PDH counter under WDDM) | 0 failed |
| `tessera_job_test` | the client against the built daemon, every path below | 24 checks, 0 failed |

A client links `tessera_client.c`, `tessera_paths.c`, `tessera_frame.c`, `tessera_self.c` and scriptura. The
daemon also links `tessera_ledger.c`, `tessera_measure.c` and obsignatio (`engine/base/obsignatio/obsignatio.cu`),
and `pdh` on Windows. On Linux both link `-ldl -lpthread`. It uses obsignatio's host seal (`obsignatio_seal`, `obsignatio_seal_holds`); it never makes a CUDA
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
(`FILE_FLAG_FIRST_PIPE_INSTANCE`). On Linux a second daemon can't take the lock file, `tessera.lock`.

## Where it lives

| | Windows | Linux |
|---|---|---|
| endpoint | `\\.\pipe\tessera-<uuid>` | `$TESSERA_RUNTIME`, else `$XDG_RUNTIME_DIR`, else `/tmp`, then `/tessera-<uuid>.sock` |
| state | `$TESSERA_STATE`, else `%LOCALAPPDATA%\tessera`, then `\<uuid>` | `$TESSERA_STATE`, else `$XDG_STATE_HOME/tessera`, else `$HOME/.local/state/tessera`, then `/<uuid>` |
| lock | none: the pipe keeps one daemon (`FILE_FLAG_FIRST_PIPE_INSTANCE`) | `<state>/tessera.lock` |
| history | `<state>\hst\head.log` | `<state>/hst/head.log` |
| history being saved | `<state>\hst\tail.log` | `<state>/hst/tail.log` |
| lost and found | `<state>\hst\lnf.log` | `<state>/hst/lnf.log` |

The state directory holds the lock file on Linux and the folder `hst`: the history (`head.log`), the copy a save
writes first (`tail.log`) and lost and found (`lnf.log`).

**The history is sealed.** It is every signum's peak and run time, one 48-byte record each, then a 32-byte seal
over all of them: obsignatio's keyed BLAKE3 at the file level. The daemon writes it whole to `hst/tail.log`, sealed,
then renames that over `hst/head.log`. A save that fails is reported on the daemon's stderr with the path. On start the daemon refuses
a history whose seal doesn't hold, whose length is not whole records plus the seal, or that has no seal at all. It
says so with the path and exits, and no job is admitted. A missing history is a fresh start. A refused history is
never rewritten: move it aside to start fresh, or put back a good copy.

**Tickets are sealed.** `hst/lnf.log` is one append-only file of sealed blocks. Each ticket is one block, and it
ends with a line `seal <64 hex digits>`, the seal over every byte of the block above it. When a lost job's client
says its precalc is kept, the daemon appends a note as a sealed block of its own: `identity <16 hex digits>`, then
`precalc kept`. It appends the note only when a ticket of that identity is in the log and its seal holds.

## Submitting a job

```c
#include "tessera.h"

TesseraJobAsk ask = {0};
memcpy(ask.device, properties.uuid.bytes, TESSERA_DEVICE_BYTES);   // cudaGetDeviceProperties
memcpy(&ask.luid, properties.luid, sizeof(ask.luid));             // Windows; 0 elsewhere
ask.signum = request_signum;          // the BLAKE3 root of the job's request: same request, same signum
ask.declared = bytes_needed;          // what the job says it needs; must not be 0
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
| `asked == 0`, `lost == 0` | **admitted.** `granted` is the bytes reserved for it | run the job, then release it |
| `asked == 1` | **held.** It declared more than its signum's last peak (`last_peak`) | override it, or wait |
| `lost == 1` | **lost.** It was held past its holding time; `lost_path` names `hst/lnf.log`, which holds its ticket | keep its precalc, then say so |

A job that doesn't fit the headroom yet waits inside the submit until it fits, with no ticket until then. A job
with a signum never seen before is admitted on its declaration and measured.

**Held.** If the job means to take more than last time, confirm it with `tessera_job_override(client, &ticket,
&error)`, which admits it on its declaration. Or wait with `tessera_job_wait(client, &ticket, &error)`: it
returns when the job is admitted or lost.

**Lost.** The daemon has appended the job's ticket to `hst/lnf.log`, the file `ticket.lost_path` names. Keep
whatever the job had already worked out, then call `tessera_job_precalc_kept(client, &error)`. The daemon appends
the precalc note to the log, releases the job, and the client ends. The ticket names the job's signum. A later run
finds the job again by its request instead of starting over.

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

If `last_peak` is larger than `declared`, the job underdeclared. Report it; the next declaration is right. Don't
use `grown_to` for that: a job whose reservation is already its kept peak is never told it grew, however far it
outruns its declaration.

If a process dies without releasing, its connection closes and the daemon sees it at once. The job's reservation
is freed and its ticket is appended to `hst/lnf.log`. The periodic sweep catches the same thing if the close is missed,
and a pid reused by a new process is never taken for the old one.

## What the job test shows

`test/tessera_job_test.cu` runs every path above against the real daemon, starting it through `daemon_path`:

1. A new signum declaring 64 MiB is admitted with 64 MiB granted. It then takes 256 MiB of device memory, and
   its release reports that it grew to 412,254,208 bytes, with a peak of 412,254,208. That is the process's whole
   dedicated memory, CUDA context included.
2. The same signum declaring four times that peak is held, and the ask names the kept peak. The override
   admits it on its declaration.
3. Declaring exactly the kept peak is admitted at once.
4. Declaring four times the peak with no answer is held for its 0.4 s holding time, then lost. The ticket names
   `hst/lnf.log`, and the precalc kept releases it. The log then ends with the precalc note in a sealed block of
   its own, and that seal holds.
5. Once the daemon has ended, the history it left (`hst/head.log`) is whole records and a seal. The test damages one byte of it,
   then cuts one byte off, then strips the seal. Each time the submit is refused because no daemon starts on it.
   With the file restored, the daemon starts and the same signum over its peak is asked with the kept peak; the
   history really was read.

The test runs in its own state directory (`run.sh` sets `TESSERA_STATE` to `<build>/tessera_state`), because
part 5 damages the history deliberately.

## The engine's runs

`track_driver` submits every run through tessera (`cell_tracking/src/track_driver/track_driver.cu`,
`run_job_submit`/`run_job_release`). `--ingest` is one job, and each `--run` part is one job:

- **Signum:** the host BLAKE3 of the part's name, a zero byte, then the effective .cfg.
- **Declaration:** the largest sample's lattice in 16-bit lanes. For ingest that comes from the source's shape
  (`engine_source_lanes`, which reads no voxel); for every other part, from the `.kcr` head.
- **Daemon:** `tessera_daemon` beside the driver, which `build_driver.sh` builds and publishes with it.
- **Times:** holding 2 s, sweep 20 ms, idle 5 s.
- **When held:** `--override` overrides; otherwise the job waits, is lost, and the part fails.
- **No daemon:** if the job can't be submitted, the part doesn't run.

Run on 24 September, on one sample (44b6_0113de3b) in a scratch set, with the daemon's real state:

| run | declared | peak measured |
|---|---|---|
| `--ingest` | 838,860,800 | 5,091,037,184 |
| `--run kcr-prove` | 838,860,800 | 3,962,761,216 |
| `--run kcr-prove` again | 838,860,800 | 3,958,566,912 |

The history then held both signa, two records and the seal (128 bytes).

**A job is reserved the larger of its declaration and its signum's kept peak** (`tessera_ledger_wants`, 24
September). The runs above found that a job used to be reserved only its declaration; the second prove held
839 MB of reservation while it used 3.96 GB. Until a sweep grew the reservation, another job could be admitted into
that room. Admission, the head's shadow, the backfill's spare and the reservation now all use the wanted bytes. A
declaration over the kept peak is still held and asked, as before. With the new rule, the same prove was admitted
with 3,958,566,912 reserved, its kept peak, and released at that peak. The ledger test checks it: declaring 100 under
a kept peak of 450, the job waits while the headroom is 300, and it is admitted with 450 reserved once the headroom
is 500.

### The sims

Every sim that uses the device is one job too (`engine/sims/sim_job.cu`). It calls `sim_job_submit` before its first
device allocation, and `sim_close` releases the job:

- **Signum:** the sim's name and its arguments.
- **Declaration:** the buffers the sim names for itself.
- **Daemon:** `$TESSERA_DAEMON`, else the `tessera_daemon` beside the sim, which `engine/sims/run.sh` builds there.
- **When held:** `TESSERA_OVERRIDE=1` admits a declaration over the kept peak.

`ask_state` and `ka_psi` never touch the device and submit nothing. Run on 24 September; each sim's count includes
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

Nothing in the repository loads the engine DLL (`build_engine.sh` builds it and nothing calls it); there is no
other caller to submit. `cell_tracking/src/cell_shift.c` runs on anchor_sift's engine, not this one.

## Linux

Run on 24 September on WSL 2: kernel 6.18, gcc 13.3, CUDA 13.3, on the RTX 3070. The sources were carried to
ext4 by git: a tree object from a scratch index, then `git archive`. The run found and fixed these:

- `PATH_MAX` is not in strict C11's `limits.h`; `engine_config.h` now takes it from `<linux/limits.h>`.
- `tessera_measure.c` needed `_GNU_SOURCE` for `syscall` and `pid_t`.
- The timer thread had no return. It now runs while the daemon lives.
- gcc warns on `noinline` together with `inline`; the error helpers use `ENGINE_NOINLINE_HELPER`.
- Platform-only strings were declared on both platforms. They are now behind their `#if`.
- The daemon printed literal copies of its own string table. It now uses the table, and each ticket names its
  signum.

**Under WSL each job reports its own bytes.** WSL reaches the device through the Windows driver; its NVML lists
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

**One endpoint, one daemon.** The socket path names the device, not the state; a daemon with another
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
  every connection waiting on the socket before it exits; the client that started it is refused and systemd has
  nothing queued to start it for again. `StartLimitIntervalSec=0` stops systemd's start limit from turning away the
  next real client.

Run on 24 September in WSL 2 (systemd 255), with the socket at
`/run/user/1000/tessera-70fc945bd257269d3ffdb316ae03ace1.sock`. The whole job test ran with a daemon path that
doesn't exist; systemd started every daemon, in a scratch `TESSERA_STATE` set through `systemctl --user
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
its own. It submits one 1-byte job for a named device, with no daemon path; only a listening socket can answer.
Built static and run in a container with the socket mounted and `TESSERA_RUNTIME=/run/tessera`:

- It connected to `/run/tessera/tessera-70fc945bd257269d3ffdb316ae03ace1.sock`.
- systemd started `tessera@70fc945bd257269d3ffdb316ae03ace1.service` on the container's connection.
- The daemon admitted the job and it released. The container had no GPU mounted; its client had no bytes to
  report. The history it left held no record, just the seal (32 bytes).

## Not built yet

- A native Linux run, measuring by pid through NVML, including a container's job. This machine has no native Linux
  NVIDIA driver.
- A container on WSL reports its own bytes only when dxcore is mounted into it (`--gpus`). The probe above had
  none.
- A job from WSL can't use the Windows daemon, which could measure it by the Windows pid.
