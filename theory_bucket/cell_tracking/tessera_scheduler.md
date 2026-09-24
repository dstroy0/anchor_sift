# The scheduler: tessera

**Purpose:** The theory of the engine's device-job scheduler: how jobs from separate processes share one device by memory, what is measured and how, what the accounting guarantees, and what is still open.
**Scope:** `tessera`, a daemon per host and device, with its client calls. The rows are M14 and A11 in [engine_table.md](engine_table.md). Statuses follow [README.md](README.md).

## What Doug ruled (23 September)

- "just a normal job scheduling function, super common for stuff like this".
- Jobs are packed by memory: several run at once while they fit.
- The byte budget is a request field. The engine chooses no share; schedule.cu's free/3·2 goes.
- One arbiter per host and device: "daemon or systemd on linux that self tears down/knocks up, single win pid, single docker hook ... this shit is getting deployed onto SaN".
- Clients reach it over a local socket.
- It measures each process's device memory by pid, "with periodic dead sweeps ... otherwise itll leak over time and lock down memory that is never used". Stale tickets "get dumped to lostandfound" (now `hst/lnf.log`).
- "caller declares, we measure, they overbudget it could be for a reason we ask they can override, they underbudget we grow and report via warn so accounting isnt perturbed".
- Over budget is judged at admission, against the last measured peak of the job's signum. An over-budget job is not thrown away: "it goes into holding before stalling and dumping to lostandfound" (now `hst/lnf.log`).
- Times (the holding time, the sweep and the idle time) are per-job fields.

## The accounting

Let the device hold C bytes. At time τ, the driver reports U(τ) bytes in use on the device, and each admitted job j has:
- d_j, its declared bytes;
- r_j, its reservation: r_j starts at d_j and only grows;
- u_j(τ), the bytes its process holds now, measured by pid.

The bytes held by processes outside tessera are

  O(τ) = U(τ) − Σ_j u_j(τ)

A job reserves room it may not have allocated yet; what it blocks is max(r_j, u_j(τ)). The headroom is

  H(τ) = C − O(τ) − Σ_j max(r_j, u_j(τ))

**Admission.** A waiting job k is admitted when d_k ≤ H(τ). Then r_k = d_k, and the headroom falls by d_k. Doug, 24 September: "We reserve what they ask for and then if it cost less we remember that for next time".

**Growth.** If u_j(τ) > r_j, then r_j becomes u_j(τ) and the client is warned: declared d_j, now r_j. Growth never refuses a job already running; a job can push H below zero. While H < 0, nothing new is admitted.

**Invariant.** Admission keeps H ≥ 0. Only growth or an outside process can drive H negative, and both are measured. So the sum the scheduler believes it has granted plus what it measured outside equals C − H(τ) at every sweep: the accounting is never perturbed, only corrected, and every correction is reported.

**Release.** When job j ends, r_j and u_j leave the sums. Its measured peak

  p_j = max over its sweeps of u_j(τ)

is kept under its signum σ_j, the BLAKE3 root of its request. The engine is deterministic in its request and its result; the same request needs about the same bytes again. The kept peak is a measurement at the sweep's resolution, though, not a byte-exact constant: identical requests have read peaks 4,194,304 bytes apart (below).

**Over budget.** At submission, a job whose signum has a kept peak p and whose declaration exceeds it (d_k > p) is asked. It waits in holding with its precalc intact. With the override set it is admitted on d_k. If no answer comes within its holding time, it is moved to lost and found. A signum never seen is admitted on its declaration and measured.

**Dead sweep.** A client that dies closes its socket, and the daemon sees the close at once. The periodic sweep is the backstop. Each ticket carries the pid and the process's start time; a pid reused by a new process is not mistaken for the old one. A ticket whose process is gone releases its reservation and moves to lost and found with its last measure.

## Measuring by pid

- **Linux:** NVML's per-process list gives each compute process's used bytes. The daemon learns a client's pid from the socket (`SO_PEERCRED`), translated into the daemon's pid namespace. A client inside a container is measured under its host pid, and a client cannot misstate its pid.
- **Windows:** under the WDDM driver model, NVML always reports per-process memory as not available, because Windows manages it. There the daemon reads the counter Task Manager uses, `\GPU Process Memory(pid_<pid>_luid_*_phys_*)\Dedicated Usage`, through PDH. It learns the pid from the pipe (`GetNamedPipeClientProcessId`). Confirmed on this machine, 23 September: the counter lists each process's dedicated bytes by pid and adapter.
- **Both:** the device's total and in-use bytes come from NVML's device memory query, which works under WDDM too. The daemon never creates a CUDA context of its own; it holds no device memory.

## The parts

- **The ledger** (`tessera_ledger.{c,h}`) is pure: the accounting, backfill and the deadline heap, with no socket, clock or device. Every rule above is a function of its inputs; the suite proves it without a GPU.
  - Proved 23 September: 143,808 cases, 0 failed. The headroom identity holds on 2,000 random states. The deadlines fire in time order. Budget, hold, override and lost pass their 18 checks. Idle teardown passes its 4. Backfill never moved the head's shadow later, over 121,586 admissions in 20,000 random scenarios, every one of which ran to completion.  - Found by the suite: a run released before its first measure had recorded a peak of 0; every later run of that signum was held as over budget. A peak now enters the history only if the run was measured at least once.
- **The frame** (`tessera.h`) is 128 bytes, little-endian, the same on every platform: magic, version, kind, the override, the device's UUID (16 bytes) and LUID, the request's signum, its declared bytes, its three times, and the bytes, measure and identity of a reply.
  - Asks: submit, override, release, precalc kept.
  - Tells: admitted, asked, grew, lost, released, refused.
- **The client** blocks in its submit until the daemon admits the job, asks about it, or loses it. A grew frame can arrive while the job runs; the client drains those at release and reports the largest in its ticket, for the caller to warn.
- **The daemon** is one program per device, named by the device's UUID: the pipe `\\.\pipe\tessera-<uuid>` on Windows, the socket `tessera-<uuid>.sock` in the runtime directory on Linux. Each client has its own thread, all behind one lock; one timer thread waits on the deadline heap's root.
  - On each sweep it reads the device's memory and the job's pid, and warns if the job grew.
  - After every change it runs admission and tells each admitted client.
  - It keeps each process's identity: a handle on Windows, a pidfd on Linux. A reused pid can never pass for the old process.
- **Its files** live in a state directory per device. The lock is `tessera.lock`. The rest sit under `hst/`: the history `hst/head.log` (signum, peak, duration), sealed with the host BLAKE3; `hst/tail.log`, the copy each save writes before it renames it over `hst/head.log`; and `hst/lnf.log`, one append-only file of sealed blocks, each a lost job's ticket or the note a client sends when it keeps that job's precalc.

## One daemon per host

- **Windows:** the daemon creates its pipe with `FILE_FLAG_FIRST_PIPE_INSTANCE`; a second daemon fails at birth. A client that finds no pipe starts the daemon detached and retries.
- **Linux:** `bind()` on the socket path refuses a second daemon. Under systemd the socket unit holds the listening socket and starts the daemon on the first connection (socket activation: the socket arrives as fd 3); the daemon can exit when idle and wake again. Without systemd, a client starts it as on Windows.
- **Docker:** the host's socket is bind-mounted into the container. The pid namespace translation above keeps the measure exact.
- **SAN:** device memory is local to a host; each host runs its own daemon, and nothing is shared across the SAN but the data.

## Order, time and loss (Doug, 23 September)

- **Order among waiting jobs: backfill with the head kept.** A job behind the head may go first only if it cannot delay the head's admission. The head never starves, and the room the head cannot use yet is not wasted.

  "Cannot delay" is a statement about time; it needs durations. The engine is deterministic in its request and its result; a signum's run time repeats about as its peak does (each a measurement, not a constant), and the history keeps both: (p_σ, t_σ), the peak bytes and the wall time of the last run. With the head h not fitting (d_h > H):
  - The head's shadow time S is the earliest moment at which the running jobs' releases, taken in order of their expected ends e_j = start_j + t_σj, free enough room: the least S with H + Σ_{e_j ≤ S} max(r_j, u_j) ≥ d_h.
  - The spare at S is X = H + Σ_{e_j ≤ S} max(r_j, u_j) − d_h: room the head will not need even when it starts.
  - A waiting job k behind the head is admitted now if d_k ≤ H and either it ends before the shadow (now + t_σk ≤ S) or it fits in the spare (d_k ≤ X, and then X falls by d_k).
  - A job whose signum has no history has no duration: it can never be proved not to delay the head; it is not backfilled. It waits its turn, and its first run records (p_σ, t_σ).
  - If a job overruns its expected end, the head's shadow moves later. That is measured and reported like a growth, never hidden.
- **Time: the soonest change is the root.** Doug: "what I want is the shortest time to change of anything to be the root because that is most likely event, in order". Every deadline goes into one min-heap keyed by the time until it changes something: each live job's next sweep, each held job's holding expiry, the idle teardown. The daemon waits on its socket for at most the root's remaining time, handles the root, pushes that item's next deadline and takes the new root. Events are handled strictly in time order, and nothing is polled on a fixed tick. The shortest sweep among live jobs falls out of the heap without being chosen.
- **Lost and found keeps the work.** When a held job stalls past its holding time, the daemon appends its ticket (identity, signum, pid, declared, peak, measured, times, reason) to `hst/lnf.log` as a sealed block and tells the client, with the log's path. The client keeps its precalc and says so; the daemon then appends a sealed note for that identity. The job can be resumed and not recomputed.

**The seal (24 September).** The seal is `obsignatio_seal`, BLAKE3 keyed at the file level (`OBSIGNATIO_LEVEL_FILE`), and it runs on the host; the daemon still makes no CUDA call and holds no device context.

- **The history file** is its records, 48 bytes each (the 32-byte signum, then the peak and the duration, 8 bytes each), followed by a 32-byte seal over them. The save builds the whole file, seals it, writes it whole as `hst/tail.log` and renames it over `hst/head.log`. Each failure on the way (the allocation, the seal, the open, the write, the close, the rename) is printed on stderr. The call sites still don't branch on the save's result, but a failed save is never silent.
- **The load** refuses a history shorter than the seal, one whose length less the seal is not a whole number of records (a short tail, or a file with no seal), and one whose seal does not hold. It names the file and the daemon exits. A missing history is a fresh start.
- **A ticket** is one block of `hst/lnf.log`: its text, starting `identity <16 hex digits>`, then a last line `seal <64 hex digits>` sealing every byte of the block above it. A note, such as "precalc kept", is appended as its own sealed block that starts `identity <16 hex digits>` and then the note text. It goes in only when the log holds a ticket of that identity whose seal holds. A job whose ticket's seal is broken takes no note, and the precalc kept is not answered.

That was the gap before this date: the history was raw records and the ticket plain text. A damaged history of whole records read without complaint, a short tail was dropped silently, and a failed save went unreported.

The daemon opens its ledger and loads its history before it makes any endpoint: the pipe on Windows, the lock and the socket on Linux. A refused history ends the daemon before any client can reach it. A daemon that loses the race to be the only one has only read the history, which is safe, because a save swaps the whole file in at once. The unsealed 192-byte history from before the seal was moved aside as `history.unsealed` in the state directory, not deleted.

## The driver submits (24 September)

`track_driver` runs every job through tessera. `--ingest` is one job, and so is each `--run` part.

- **The signum** is the BLAKE3 hash of the part's name, a NUL, and the whole effective request; a changed setting is a new signum.
- **The declaration** is the largest sample's lattice in 16-bit lanes. For `--ingest` it comes from the source's description (`engine_source_lanes`, which reads no voxel); for every other part, from the `.kcr` head.
- **The times** are 2 s holding, 20 ms sweep and 5 s idle.
- **The daemon** is `tessera_daemon` beside the driver, which the driver starts when none answers.
- **A part fails** if its job is not taken, or is held and lost; `--override` admits a held job on its declaration.

Measured on 44b6_0113de3b, in a scratch state directory:

| run | declared and granted | peak measured |
|---|---|---|
| `--ingest` | 838,860,800 | 5,091,037,184 |
| `--run kcr-prove` | 838,860,800 | 3,958,566,912 |
| `--run kcr-prove` again | 838,860,800 | 3,962,761,216 |

The history then held two records and the seal (128 bytes), and the daemon ended once idle. Anchor_sift's run on the real state gave the same declarations and ingest peak, with the two prove peaks in the other order.

Two findings, both measured:

- **The kept peak is not a constant.** Identical requests measured peaks 4,194,304 bytes (2^22) apart. The peak is the largest of samples taken every 20 ms; it is a measurement at that resolution. The rule above is qualified to say so (agreed with Anchor_sift). Whether the sampling is what moves it has not been tested.
- **A job reserves its declaration, not its kept peak.** The second prove declared less than its kept peak and was admitted on its declaration; until its sweeps grew it, its reservation stood 3,119,706,112 bytes below what it went on to use. That is Doug's rule: reserve what the job asks for, grow and warn when it takes more.
  - The same day, Anchor_sift changed the working tree's code, uncommitted and not approved by Doug, to reserve the larger of the declaration and the kept peak (`tessera_ledger_wants`). With it, two proves each reserved 3,962,761,216 bytes.

## The sims submit (24 September)

Every sim that uses the device is one job (`engine/sims/sim_job.cu`).

- **The signum** is the BLAKE3 hash of the sim's name and each argument, each ended by a NUL.
- **The declaration** is the bytes of the sim's first allocation, declared before it makes it.
- **The daemon** is `$TESSERA_DAEMON`, or `tessera_daemon` beside the sim, and `run.sh` builds it there.
- **The times** are the driver's, and `TESSERA_OVERRIDE=1` overrides.
- **The checks:** the job's admission and its release are two of the sim's checks; a sim that is not admitted fails.

Measured in a scratch state directory:

| sim | declared | peak measured | checks |
|---|---|---|---|
| `period_power` | 262,144 | 145,915,904 | 601, 0 failed |
| `nbody_lattice` | 26,542,080 | 175,276,032 | 11, 0 failed |
| `noise_floor` | 9,142,272 | 187,858,944 | 13, 0 failed |
| `root_universal` | 339,510 | 152,207,360 | 1,270, 0 failed |
| `fixed_pattern` | 141,056 | 145,915,904 | 12, 0 failed |
| `classify_reject_recover` | 118,016 | 145,915,904 | 9, 0 failed |
| `chaitin_omega 16`, on the engine | 30,256 | 286,425,088 | 16, 0 failed |

- **The history** was then seven records and the seal (368 bytes).
- **The host-only sims:** `ask_state` and `ka_psi` run on the host and submit no job.
- **Every peak is above its declaration.** The smallest peaks sit near 146 MB whatever was declared. The peak is the process's whole dedicated memory, its CUDA context included, and the context is likely most of that; not measured apart.
- **Two peaks differ from Anchor_sift's runs by 2,097,152 bytes (2^21):** `nbody_lattice` and `fixed_pattern`. That is the same finding as the driver's.
- **The engine DLL:** no program in the repo loads it; no other caller is left to submit.

## Linux (24 September, reported by Anchor_sift, not rerun here)

- **The build:** Linux built under WSL 2 (gcc 13.3.0, CUDA 13.3), and its suite passes with 0 warnings. The fixes it needed: `PATH_MAX` under strict C11, the noinline helpers under gcc, `_GNU_SOURCE`, the timer thread's missing return, and the Windows-only strings.
- **The measure refuses WSL:** WSL runs the device through the Windows driver, and its NVML read a process as 0 bytes before and after it allocated 256 MiB. So no pid can be measured there. The measure refuses to open on a paravirtual device (`tessera_measure_paravirtual`), and the daemon refuses to run. The measure test and the job test both check exactly that refusal.
- **Socket activation:** the systemd user units `tessera@.socket` and `tessera@.service` are in `engine/daemon/service`. Under WSL, a client's connection started the daemon, and the measure refusal then ended it. systemd restarted it until its own start limit stopped it.
- **Docker:** a static client with no CUDA (`engine/daemon/test/tessera_socket_probe.c`) ran in a container under Docker Engine 29.1.3 inside the WSL distro. The host's socket was bind-mounted and named by `TESSERA_RUNTIME`. The client's submit reached the host's socket-activated daemon, which the WSL refusal then ended; the submit was refused.
- **Not run** (this machine has no native NVIDIA Linux driver):
  - a native Linux host, where NVML measures a pid;
  - a daemon kept running on the activated socket;
  - a job admitted through the docker mount.
