# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The C implementation of the engine. It needs a C11 compiler and nothing else: no ESP-IDF, no
# device toolchain, no Python, and nothing from the vendored library.
#
#     cmake -S src/engine/c -B build/engine_c -G Ninja -DCMAKE_BUILD_TYPE=Release
#     cmake --build build/engine_c
#     ./build/engine_c/bench_scaling_reads
#     ./build/engine_c/bench_scaling_cycles
#
# Built at -O2 whatever the build type says. A Debug bench measures the debug build, which is not a
# number anyone wants.
#
#   sift/    the arms and the dispatcher, which is the thing under test
#   bench/   the drivers that build corpora, count or time, and print rows
#
# The kernel is compiled twice from one source. The counted build carries probe and verification
# counters; the timed build is the same object it was without them. Two builds instead of one flag
# at run time, because counting perturbs the timing it would otherwise be reported beside, and
# because a compile time fact costs nothing on the path that does not want it.

cmake_minimum_required(VERSION 3.16)
project(anchor_sift_engine_c C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

set(SIFT_WARNINGS $<$<C_COMPILER_ID:GNU,Clang>:-O2 -Wall -Wextra>)

# The kernel as it ships. Nothing in here reads a clock or prints, so a driver change cannot move a
# measurement.
add_library(anchor_sift_kernel STATIC sift/anchor_sift.c)
target_include_directories(anchor_sift_kernel PUBLIC sift)
target_compile_options(anchor_sift_kernel PRIVATE ${SIFT_WARNINGS})

# The same source with the counters compiled in. ANCHOR_SIFT_COUNT_READS is PUBLIC so a driver
# linking this library sees the same value the library was built with, which is what keeps a driver
# from calling anchor_sift_counters_reset against a kernel that does not define it.
add_library(anchor_sift_kernel_counted STATIC sift/anchor_sift.c)
target_include_directories(anchor_sift_kernel_counted PUBLIC sift)
target_compile_definitions(anchor_sift_kernel_counted PUBLIC ANCHOR_SIFT_COUNT_READS=1)
target_compile_options(anchor_sift_kernel_counted PRIVATE ${SIFT_WARNINGS})

# The generated corpora and the two statistics a dispatch decision is made from. Shared so the
# scaling bench and the dispatch bench cannot disagree about what skewed means: one measures a rate
# against a prediction and the other scores a rule against a clock, and a rule scored on corpora the
# prediction never saw is a rule scored against nothing.
add_library(bench_corpora STATIC bench/bench_corpora.c)
target_include_directories(bench_corpora PUBLIC bench)
target_compile_options(bench_corpora PRIVATE ${SIFT_WARNINGS})

# Reads, which travel between machines and are what an asymptotic claim is made of.
add_executable(bench_scaling_reads bench/bench_scaling.c)
target_link_libraries(bench_scaling_reads PRIVATE anchor_sift_kernel_counted bench_corpora)
target_compile_options(bench_scaling_reads PRIVATE ${SIFT_WARNINGS})

# Cycles, which belong to the machine that produced them and are for the dispatch decision alone.
add_executable(bench_scaling_cycles bench/bench_scaling.c)
target_link_libraries(bench_scaling_cycles PRIVATE anchor_sift_kernel bench_corpora)
target_compile_options(bench_scaling_cycles PRIVATE ${SIFT_WARNINGS})

# Which arm the dispatcher should choose, scored against the clock. Links the uncounted kernel
# because counting perturbs the timing the whole question turns on, and the driver refuses to
# compile against the counted one rather than printing a number nobody should read.
add_executable(bench_dispatch bench/bench_dispatch.c)
target_link_libraries(bench_dispatch PRIVATE anchor_sift_kernel bench_corpora)
target_compile_options(bench_dispatch PRIVATE ${SIFT_WARNINGS})

# The ingestion reading: at what scale does the corpus agree with itself, and what does that cost
# the histogram bound. Links the counted kernel because the claim it checks is about probes and
# survivors, which are reads and not cycles.
add_executable(bench_coherence bench/bench_coherence.c)
target_link_libraries(bench_coherence PRIVATE anchor_sift_kernel_counted bench_corpora)
target_compile_options(bench_coherence PRIVATE ${SIFT_WARNINGS})

# Soundness where the claim actually lives. Its core takes a base list, a displacement list and a
# callback answering whether two positions carry the same symbol, so it has no dimension parameter
# and no symbol type, and it sweeps one to eight dimensions, a complex irrational alphabet compared
# over its storage, a rotated point set and a scatter no rectangle covers. It holds its own core
# rather than calling the kernel, because the kernel is the one dimensional byte specialization and
# what is under test here is the construction.
add_executable(bench_lattice bench/bench_lattice.c)
target_compile_options(bench_lattice PRIVATE ${SIFT_WARNINGS})
if(NOT WIN32)
    target_link_libraries(bench_lattice PRIVATE m)
endif()

foreach(one bench_scaling_reads bench_scaling_cycles bench_lattice)
    set_target_properties(${one} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
        INTERPROCEDURAL_OPTIMIZATION FALSE)
endforeach()

# The four older drivers still hold their arms inline and reach into the vendored library, so none
# of them builds against this kernel. They are not wired up here, and wiring them up means reading
# each one first. bench_ab.c alone is 105 KB.
#
# Three of them also include "mmgr_sha256.h", which is MMgr's test support and lives in MMgr, at
# deps/mmgr/test/support. Run `python maint/get_deps.py` to put the clone there, then add
# that directory to the target's include path and compile its .c beside the driver. Nothing built
# here needs it: the corpora are filled by splitmix64 in bench_corpora, and bench_lattice carries
# its own three line shim for the same reason.
