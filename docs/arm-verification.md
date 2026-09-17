# Arm verification

**Purpose:** Know which steering scan arms have run against the portable reference and which have only been checked for the instructions they emit, and under what conditions each grade was taken. A claim about an arm then cites the measurement behind it.
**Scope:** `src/engine/c/engine/scan_portable.c`, `scan_avx2.c`, `scan_avx512.c`, `scan_neon.c`, `scan_sve.c`, `scan_cuda.cu`; the drivers `src/engine/c/bench/bench_steer_arms.c`, `maint/engine/build_engine.ps1`, `maint/engine/build_gpu_scan.sh`, `maint/engine/verify_arm_asm.sh`.

Every scan arm answers one question: held at one needle offset, how many still-standing alignments carry the wanted byte. The portable arm is the reference. An arm that returns a different count has a defect, whatever it measures, so correctness is graded first and timing second.

## The three grades, kept apart

A row here reads **agrees**, **emits**, or **builds**, and the three are not interchangeable.

- **agrees** means the arm ran on hardware that carries it and returned the reference count on every case, with zero disagreements. This is the only grade that speaks to behavior.
- **emits** means the arm was compiled for a target no machine here carries, and the emitted object was read to confirm the instructions the arm was written to use came out, ruling out a silent scalar fallback. It says nothing about behavior.
- **builds** means the source compiled clean for the target. It is the weakest grade and is implied by the other two.

## Arms that ran and agree

Graded across `bench_steer_arms`, which compares every present arm against portable over alignment counts 1, 2, 31, 32, 33, 63, 64, 65, 1000 and 65536, four survivor masks and two offsets, then times a 1048576-alignment sweep at 200 passes. The differential grid is the correctness claim; the rate is the machine's and is named with it.

| arm | machine | toolchain | disagreements | rate against portable |
|---|---|---|---|---|
| avx2 | Intel Core i7-5960X (AVX2, no AVX-512) | MSVC toolset 14.44, Release | 0 | 35.71x |
| avx2 | Intel Core i7-5960X, under WSL Ubuntu | gcc 13.3, Release | 0 | 40.66x |
| neon | Raspberry Pi 5, Cortex-A76 (aarch64) | gcc 14.2, Release | 0 | 6.53x |
| cuda | NVIDIA GeForce RTX 3070 (compute 8.6, 46 SMs), host i7-5960X | nvcc 13.3 with MSVC 14.44 | 0 | 1.74x |

The cuda rate is low against the vector arms because the whole object crosses the bus on every call. It wins on the object size measured and grows with it. The arm is graded and timed but not placed in `anchor_steer_best_engine`. The vector arm the planner actually calls is chosen there.

## Arms with no hardware here, graded on emission

Neither the i7-5960X nor the Cortex-A76 carries AVX-512 or SVE, so these arms have never run. `maint/engine/verify_arm_asm.sh` compiles each for its target and reads the object. Both also report themselves absent through their run-time detection on the machines above. A machine without the feature must get exactly that.

| arm | target | instructions confirmed | detection |
|---|---|---|---|
| avx512 | x86-64, gcc `-mavx512f -mavx512bw` | `vpcmpeqb` on a zmm operand | reports absent on the i7-5960X |
| sve | aarch64, gcc `-march=armv8.2-a+sve` | `whilelo`, `cmpeq`, `cntp`, `ld1b` | reports absent on the Cortex-A76 |

The names carry the grade. These two arms report as `avx512-unrun` and `sve-unrun`. A row of results cannot show one beside a run arm without the difference showing in the row itself.

## Reproducing each grade

The host arms, on Windows with the device compiled in where a CUDA toolchain is present:

```powershell
maint\engine\build_engine.ps1
```

The host arms on any C11 compiler, which compiles the AVX-512 arm where the compiler is not MSVC:

```sh
cmake -S src/engine/c -B build/engine_c -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build/engine_c
./build/engine_c/bench_steer_arms
```

The CUDA arm, graded against portable on the device:

```sh
bash maint/engine/build_gpu_scan.sh
```

The emission of every arm, which grades what came out and never behavior:

```sh
bash maint/engine/verify_arm_asm.sh
```

**Author:** dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
**Date:** 2026-09-16
