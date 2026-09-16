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

# MSVC NEEDS ITS ENVIRONMENT AND NINJA DOES NOT SUPPLY ONE. CMake finds cl.exe through vswhere even
# where it is absent from PATH, so a configure here succeeds and every compile then fails on
# "Cannot open include file: 'stddef.h'", because INCLUDE and LIB are set by vcvars and this shell
# has not run it. The Visual Studio generator imports them itself; Ninja does not.
#
# Caught here and named, because the failure it produces otherwise is a compiler error about a
# standard header, which reads as a broken toolchain rather than a missing environment.
#
# Naming the compiler is what fixes it, and testing for one is not enough. CMake prefers cl.exe on
# Windows even where gcc sits on PATH, so a check that merely finds gcc passes and the build still
# goes to an MSVC that cannot see its own headers.
compiler=""
case "$(uname -s 2>/dev/null)" in
    MINGW*|MSYS*|CYGWIN*)
        if [ -z "${INCLUDE:-}" ]; then
            for candidate in gcc clang cc; do
                if command -v "$candidate" >/dev/null 2>&1; then
                    compiler="-DCMAKE_C_COMPILER=$candidate"
                    echo "[*] no MSVC environment here, so the build is pinned to $candidate."
                    echo "    For an MSVC build run maint/engine/build_engine.ps1 from PowerShell,"
                    echo "    which imports vcvars, or run this from a Developer Command Prompt."
                    break
                fi
            done
            if [ -z "$compiler" ]; then
                echo "No C compiler this shell can drive." >&2
                echo "  MSVC is installed but its environment is not imported here, so cl.exe" >&2
                echo "  fails to find stddef.h, and no gcc or clang is on PATH either." >&2
                echo "  Run maint/engine/build_engine.ps1 from PowerShell, or run this from a" >&2
                echo "  Developer Command Prompt, or install gcc." >&2
                exit 1
            fi
        fi
        ;;
esac

# A cache naming a different compiler makes the configure fail outright, and the build tree is
# generated output this script's own header says to delete freely. Removing the two files CMake
# keys the toolchain on is cheaper than making a reader work out why a rerun refuses.
if [ -n "$compiler" ] && [ -f "$build/CMakeCache.txt" ]; then
    if ! grep -q "CMAKE_C_COMPILER:.*${compiler#-DCMAKE_C_COMPILER=}" "$build/CMakeCache.txt"; then
        echo "[*] cached toolchain differs, reconfiguring from scratch"
        rm -f "$build/CMakeCache.txt"
        rm -rf "$build/CMakeFiles"
    fi
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
    cmake -S "$src" -B "$build" $generator $compiler -DCMAKE_BUILD_TYPE=Release >/dev/null
else
    cmake -S "$src" -B "$build" $generator $compiler -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_DISABLE_FIND_PACKAGE_CUDAToolkit=ON -DANCHOR_SKIP_CUDA=ON >/dev/null
fi

# NAMED TARGETS AND NOT THE DEFAULT ALL, because one bench in this directory does not compile with
# MSVC and a bare `cmake --build` therefore fails on Windows with the engine itself built fine.
# Measured 2026-09-16 against MSVC 14.44:
#
#     bench_lattice   bench/bench_lattice.c:500 onward needs C99 _Complex arithmetic; MSVC supplies
#                     the types without the operators and rejects the declarations
#
# It predates this script and is not on the path the engine needs. It is named here rather than
# silently skipped so nobody re-discovers it, and so that a reader on Linux knows it is expected to
# work there and is simply not built by this script.
#
# bench_dispatch USED TO BE ON THIS LIST for the same reason and no longer belongs to it. It reached
# CLOCK_MONOTONIC because its cycle counter gate tested __x86_64__ alone, which GCC and Clang define
# and MSVC never does, sending every MSVC build to a POSIX substitute. The gate now carries the MSVC
# spelling and the driver builds and runs here.
#
# anchor_steer and anchor_steer_arms USED TO BE ON THIS LIST and no longer exist. Both folded into
# anchor_sift_kernel, which is the whole engine in one translation unit.
echo "[*] building"
for target in anchor_sift_kernel anchor_sift_kernel_counted anchor_raster anchor_render \
              anchor_exact_portable \
              test_steer test_adversarial test_arm_agreement bench_steer_arms bench_raster \
              bench_exact_arms bench_exact bench_dispatch bench_coherence \
              bench_scaling_reads bench_scaling_cycles; do
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
for grader in test_steer test_adversarial test_arm_agreement bench_steer_arms bench_raster bench_exact_arms; do
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
