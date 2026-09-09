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
#   portable/          the arms and the dispatcher in C11 alone, which is the thing under test
#   vectorized_win/    the same operations under the widest SIMD an x86 Windows build detects
#   vectorized_linux/  the same, detected on an x86 Linux build
#   vectorized_rpi/    the same, on ARM NEON
#   bench/             the drivers that build corpora, count or time, and print rows
#
# The portable arm is the reference and every other arm is checked against it. An arm that disagrees
# with portable is wrong, whatever it measures, and the vectorized directories exist to be faster at
# an answer portable already fixed.
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
add_library(anchor_sift_kernel STATIC portable/anchor_sift.c)
target_include_directories(anchor_sift_kernel PUBLIC portable)
target_compile_options(anchor_sift_kernel PRIVATE ${SIFT_WARNINGS})

# The same source with the counters compiled in. ANCHOR_SIFT_COUNT_READS is PUBLIC so a driver
# linking this library sees the same value the library was built with, which is what keeps a driver
# from calling anchor_sift_counters_reset against a kernel that does not define it.
add_library(anchor_sift_kernel_counted STATIC portable/anchor_sift.c)
target_include_directories(anchor_sift_kernel_counted PUBLIC portable)
target_compile_definitions(anchor_sift_kernel_counted PUBLIC ANCHOR_SIFT_COUNT_READS=1)
target_compile_options(anchor_sift_kernel_counted PRIVATE ${SIFT_WARNINGS})

# The exact integer as a fixed width limb array, which is the same value the python engine ingests
# and a different transform of it. Portable C11 with no intrinsic and no 128 bit type, so it builds
# anywhere and is the arm every vectorized one is checked against.
add_library(anchor_exact_portable STATIC portable/exact_limbs.c portable/exact_arm_portable.c)
target_include_directories(anchor_exact_portable PUBLIC portable)
target_compile_options(anchor_exact_portable PRIVATE ${SIFT_WARNINGS})

# Which vectorized arm this target can carry. Decided from the processor the build targets, and
# every gate is defined on both arms so #if always has a value and an unset build is never a silent
# false. An arm that is compiled in still asks the processor at run time before it is used.
set(ANCHOR_ARM_SOURCES "")
set(ANCHOR_ARM_DEFINES "")
set(ANCHOR_ARM_OPTIONS "")
set(ANCHOR_ARM_INCLUDES "")

if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|i[3-6]86)$")
    # The AVX2 loops are one file for both x86 platforms. A second copy would be one edit away from
    # disagreeing, and a disagreement between two arms is a defect by definition. What each platform
    # directory holds is detection, which is the part that genuinely differs.
    list(APPEND ANCHOR_ARM_INCLUDES vectorized_win)
    if(WIN32)
        list(APPEND ANCHOR_ARM_SOURCES vectorized_win/exact_arm_avx2.c)
    else()
        list(APPEND ANCHOR_ARM_SOURCES vectorized_linux/exact_arm_avx2.c)
    endif()
    list(APPEND ANCHOR_ARM_DEFINES ANCHOR_EXACT_HAVE_AVX2=1)
    # -mavx2 permits the intrinsics in this translation unit. It does not permit the compiler to
    # assume AVX2 anywhere else, because no other translation unit is built with it.
    if(NOT MSVC)
        list(APPEND ANCHOR_ARM_OPTIONS -mavx2)
    else()
        list(APPEND ANCHOR_ARM_OPTIONS /arch:AVX2)
    endif()
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64|armv[78].*)$")
    list(APPEND ANCHOR_ARM_SOURCES vectorized_rpi/exact_arm_neon.c)
    list(APPEND ANCHOR_ARM_DEFINES ANCHOR_EXACT_HAVE_NEON=1)
    # NEON is part of the base aarch64 architecture and needs no flag there. A 32 bit ARM build
    # does need one, and asks for the softfp ABI's NEON rather than assuming a hard float target.
    if(NOT CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
        list(APPEND ANCHOR_ARM_OPTIONS -mfpu=neon)
    endif()
endif()

# The two arms with no hardware anywhere in this project. They are compiled where the compiler
# accepts the flags and are gated at run time like every other arm, so a machine without the feature
# reports them absent and never calls in. Their names carry that they have never been run.
#
# Compiled as their own targets, because -mavx512f and +sve let the compiler use those instructions
# anywhere in the translation unit carrying the flag. Confining each to one file is what keeps a
# build from emitting an instruction the running part cannot execute outside the detected path.
include(CheckCCompilerFlag)
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64)$" AND NOT MSVC)
    check_c_compiler_flag("-mavx512f -mavx512bw -mavx512vl" ANCHOR_CC_TAKES_AVX512)
    if(ANCHOR_CC_TAKES_AVX512)
        add_library(anchor_exact_avx512 STATIC vectorized_win/exact_arm_avx512.c)
        target_link_libraries(anchor_exact_avx512 PUBLIC anchor_exact_portable)
        target_include_directories(anchor_exact_avx512 PUBLIC vectorized_win)
        target_compile_definitions(anchor_exact_avx512 PUBLIC ANCHOR_EXACT_HAVE_AVX512=1)
        target_compile_options(anchor_exact_avx512
            PRIVATE ${SIFT_WARNINGS} -mavx512f -mavx512bw -mavx512vl)
        list(APPEND ANCHOR_EXTRA_ARMS anchor_exact_avx512)
    endif()
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
    check_c_compiler_flag("-march=armv8.2-a+sve" ANCHOR_CC_TAKES_SVE)
    if(ANCHOR_CC_TAKES_SVE)
        add_library(anchor_exact_sve STATIC vectorized_rpi/exact_arm_sve.c)
        target_link_libraries(anchor_exact_sve PUBLIC anchor_exact_portable)
        target_include_directories(anchor_exact_sve PUBLIC vectorized_rpi)
        target_compile_definitions(anchor_exact_sve PUBLIC ANCHOR_EXACT_HAVE_SVE=1)
        target_compile_options(anchor_exact_sve PRIVATE ${SIFT_WARNINGS} -march=armv8.2-a+sve)
        list(APPEND ANCHOR_EXTRA_ARMS anchor_exact_sve)
    endif()
endif()

if(ANCHOR_ARM_SOURCES)
    add_library(anchor_exact_arms STATIC ${ANCHOR_ARM_SOURCES})
    target_link_libraries(anchor_exact_arms PUBLIC anchor_exact_portable ${ANCHOR_EXTRA_ARMS})
    target_include_directories(anchor_exact_arms PUBLIC ${ANCHOR_ARM_INCLUDES})
    target_compile_definitions(anchor_exact_arms PUBLIC ${ANCHOR_ARM_DEFINES})
    target_compile_options(anchor_exact_arms PRIVATE ${SIFT_WARNINGS} ${ANCHOR_ARM_OPTIONS})
else()
    # No vectorized arm for this processor. The library still exists so the driver links the same
    # way everywhere, and it carries only the portable arm.
    add_library(anchor_exact_arms INTERFACE)
    target_link_libraries(anchor_exact_arms INTERFACE anchor_exact_portable)
endif()

# Grades every arm present against the portable one, then times them. A disagreement is a defect and
# a time is a cost, and the two are never traded against each other.
add_executable(bench_exact_arms bench/bench_exact_arms.c)
target_link_libraries(bench_exact_arms PRIVATE anchor_exact_arms anchor_exact_portable)
target_compile_options(bench_exact_arms PRIVATE ${SIFT_WARNINGS})

# Prints what the limb arithmetic produced and decides nothing about whether it is right.
# maint/check_exact_limbs.py recomputes every row with python integers and compares.
add_executable(bench_exact bench/bench_exact.c)
target_link_libraries(bench_exact PRIVATE anchor_exact_portable)
target_compile_options(bench_exact PRIVATE ${SIFT_WARNINGS})

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
