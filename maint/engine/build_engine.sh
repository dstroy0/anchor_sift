#!/usr/bin/env sh
# Builds the C engine and runs the graders. One command, from a fresh clone, no arguments.
#
#     maint/engine/build_engine.sh              configure, build, grade
#     maint/engine/build_engine.sh --build-only configure and build, run nothing
#
# Needs cmake and a C11 compiler on PATH and nothing else. No network, no submodule, no generator
# run first. The engine links no library outside the C standard headers, so there is nothing to
# install before this works.
#
# Output lands in build/engine_c/ and is never read back by anything; delete it freely.

set -eu

here=$(dirname "$0")
root=$(cd "$here/../.." && pwd)
src="$root/src/engine/c"
build="$root/build/engine_c"

run_graders=1
if [ "${1:-}" = "--build-only" ]; then
    run_graders=0
fi

if ! command -v cmake >/dev/null 2>&1; then
    echo "cmake is not on PATH. Install it, or build the engine by hand from $src." >&2
    exit 1
fi

echo "[*] configuring $src"
cmake -S "$src" -B "$build" >/dev/null

# NAMED TARGETS AND NOT THE DEFAULT ALL, because two benches in this directory do not compile with
# MSVC and a bare `cmake --build` therefore fails on Windows with the engine itself built fine.
# Measured 2026-09-16 against MSVC 14.44:
#
#     bench_dispatch  bench/bench_dispatch.c:105 uses CLOCK_MONOTONIC, which is POSIX and absent
#     bench_lattice   bench/bench_lattice.c:500 onward does not parse; MSVC rejects the declarations
#
# Both predate this script and neither is on the path the engine needs. They are named here rather
# than silently skipped so nobody re-discovers them, and so that a reader on Linux knows they are
# expected to work there and are simply not built by this script.
echo "[*] building"
for target in anchor_sift_kernel anchor_steer anchor_exact_portable \
              bench_steer bench_steer_arms bench_raster bench_exact_arms bench_exact; do
    if ! cmake --build "$build" --target "$target" >/dev/null 2>&1; then
        echo "[!] target $target did not build" >&2
        exit 1
    fi
done

# A multi-config generator puts binaries under a per-config directory and a single-config one does
# not. Asking the filesystem is shorter than asking cmake which generator it picked.
if [ -d "$build/Debug" ]; then
    bin="$build/Debug"
else
    bin="$build"
fi

echo "[+] built into $bin"

if [ "$run_graders" -eq 0 ]; then
    exit 0
fi

# Every grader returns non-zero on a failed check, so the loop below reports the first one that
# fails and stops rather than printing a wall of output and exiting zero.
failed=0
for grader in bench_steer bench_steer_arms bench_raster bench_exact_arms; do
    exe="$bin/$grader"
    [ -f "$exe" ] || exe="$bin/$grader.exe"
    if [ ! -f "$exe" ]; then
        echo "[!] $grader was not built" >&2
        failed=$((failed + 1))
        continue
    fi

    echo ""
    echo "[*] $grader"
    if ! "$exe"; then
        echo "[!] $grader reported a failure" >&2
        failed=$((failed + 1))
    fi
done

echo ""
if [ "$failed" -ne 0 ]; then
    echo "[!] $failed grader(s) failed"
    exit 1
fi
echo "[+] all graders passed"
