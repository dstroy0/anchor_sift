# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Standalone host build for the search kernel and its drivers. It needs a C11 compiler and nothing
# else: no ESP-IDF, no device toolchain, no Python.
#
#     cmake -S bench -B build/bench -G Ninja -DCMAKE_BUILD_TYPE=Release
#     cmake --build build/bench
#     ./build/bench/bench_ancorae_cycles
#
# Built at -O2 whatever the build type says. A Debug bench measures the debug build, which is not a
# number anyone wants.
#
#   kernel/  the algorithm and the dispatcher, which is the thing under test
#   driver/  the mains that build corpora, read the clock and print rows
#   deps/    MMgr, vendored, keeping its own attribution because it is its code

cmake_minimum_required(VERSION 3.16)
project(anchor_sift_bench C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# The kernel. Nothing in here reads a clock or prints, so a driver change cannot move a measurement.
add_library(anchor_sift_kernel STATIC kernel/anchor_sift.c)
target_include_directories(anchor_sift_kernel PUBLIC kernel)
target_compile_options(anchor_sift_kernel PRIVATE
    $<$<C_COMPILER_ID:GNU,Clang>:-O2 -Wall -Wextra>)

# The corpus generator the drivers share. Vendored from MMgr's test support and left as its own.
add_library(anchor_sift_corpus STATIC driver/mmgr_sha256.c)
target_include_directories(anchor_sift_corpus PUBLIC driver)
# Its implementation reaches mmgr.h, which reaches the widths and the dispatch macros. Those are
# vendored under deps and are private to this target: a driver includes mmgr_sha256.h and no more.
target_include_directories(anchor_sift_corpus PRIVATE
    deps/include
    deps/src
    deps/embedded_types/include)
target_compile_options(anchor_sift_corpus PRIVATE
    $<$<C_COMPILER_ID:GNU,Clang>:-O2>)

# One executable per driver. Only the cycles driver is built against the kernel so far; the other
# four still hold their arms inline and reach into the vendored library, and lifting them is the
# next piece of work.
add_executable(bench_ancorae_cycles driver/bench_ancorae_cycles.c)
target_link_libraries(bench_ancorae_cycles PRIVATE anchor_sift_kernel anchor_sift_corpus)
target_compile_options(bench_ancorae_cycles PRIVATE
    $<$<C_COMPILER_ID:GNU,Clang>:-O2 -Wall -Wextra>)

if(NOT WIN32)
    target_link_libraries(bench_ancorae_cycles PRIVATE m)
endif()

set_target_properties(bench_ancorae_cycles PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
    INTERPROCEDURAL_OPTIMIZATION FALSE)
