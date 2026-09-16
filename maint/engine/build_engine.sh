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

# A MACHINE WITH A GPU RENDERS ON IT, and getting that by default takes two things a stock configure
# does not do.
#
# The Visual Studio generator compiles .cu only where the CUDA toolkit installed its MSBuild
# integration, which a normal toolkit install often skips, and CMake then stops with "No CUDA toolset
# found". Ninja needs no integration, so it is used wherever it is available.
#
# And nvcc is frequently not on PATH even where the toolkit is installed, so the standard locations
# are searched and the newest is put on PATH for the configure. Without this the device arm is
# silently left out and the renderer falls back to the host on a machine that has a card.
if [ -z "${CUDA_PATH:-}" ] && ! command -v nvcc >/dev/null 2>&1; then
    for candidate in "/c/Program Files/NVIDIA GPU Computing Toolkit/CUDA"/v*/bin \
                     /usr/local/cuda*/bin; do
        if [ -x "$candidate/nvcc" ] || [ -x "$candidate/nvcc.exe" ]; then
            PATH="$candidate:$PATH"
            export PATH
        fi
    done
fi

generator=""
if command -v ninja >/dev/null 2>&1; then
    generator="-G Ninja"
fi

# nvcc drives a host compiler and cannot run without one. On Windows that host compiler is MSVC and
# it reaches PATH through vcvars, which this shell does not run, so nvcc is present and unusable
# here. Detecting that now and skipping CUDA is better than letting the configure fail: a failed
# configure builds nothing, where skipping builds the host arms and says what was skipped.
# The host compiler nvcc needs is platform specific and the wrong test passes on Windows. Git Bash
# carries gcc, nvcc there requires cl.exe, and accepting gcc lets the configure get as far as
# "Cannot find compiler 'cl.exe' in PATH" before failing.
want_cuda=0
if command -v nvcc >/dev/null 2>&1; then
    case "$(uname -s 2>/dev/null)" in
        MINGW*|MSYS*|CYGWIN*)
            if command -v cl.exe >/dev/null 2>&1; then
                want_cuda=1
            fi
            ;;
        *)
            if command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1; then
                want_cuda=1
            fi
            ;;
    esac
fi

echo "[*] configuring $src"
if [ "$want_cuda" -eq 1 ]; then
    echo "[*] nvcc and a host compiler found, the device arm will be compiled in"
elif command -v nvcc >/dev/null 2>&1; then
    echo "[*] nvcc found but no host compiler on PATH, so CUDA is skipped here."
    echo "    On Windows run maint/engine/build_engine.ps1 instead; it imports the MSVC"
    echo "    environment nvcc needs and compiles the device arm."
else
    echo "[*] no nvcc, host arms only"
fi

# Unquoted on purpose: empty must expand to no argument rather than to an empty one.
# shellcheck disable=SC2086
if [ "$want_cuda" -eq 1 ]; then
    cmake -S "$src" -B "$build" $generator -DCMAKE_BUILD_TYPE=Release >/dev/null
else
    cmake -S "$src" -B "$build" $generator -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_DISABLE_FIND_PACKAGE_CUDAToolkit=ON -DANCHOR_SKIP_CUDA=ON >/dev/null
fi

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
    if ! (cd "$bin" && "$exe"); then
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
