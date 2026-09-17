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
# A file belongs to a directory by what it is, not by the operating system that builds it:
#
#   engine/       the search, the steering and the scan. anchor_sift.{c,h} and one scan_<set> file
#                 per instruction set. A file belongs here when it decides which alignments survive.
#   no_rounding/  the exact arithmetic and the arms that read it. exact_integer.{c,h}, arm.h, and one
#                 arm_<set> file per instruction set. The name states what the arithmetic is for: it
#                 removes rounding, so a comparison is exact. A file belongs here when it is an
#                 implementation of that arithmetic.
#   render/       the direct renderer. anchor_raster.{c,h} and raster_cuda.cu. A file belongs here
#                 when it turns engine state into pixels or voxels.
#   bench/        the drivers that build corpora, count or time, and print rows.
#
# The portable arm is the reference in each family and every other arm is checked against it. An arm
# that disagrees with portable is wrong, whatever it measures, and the per instruction set files
# exist to be faster at an answer portable already fixed. An instruction set carried in one family
# is carried in the other where the operation exists there too, so a listing of engine/ and a
# listing of no_rounding/ name the same sets.
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

# The repository root, computed once. Tests live outside this directory, and a target naming one
# through an inline ../../../ chain breaks the moment either file moves. Guarded because
# test_arm_agreement introduced the same variable on another branch and the two must not collide
# when they meet.
if(NOT DEFINED ANCHOR_SIFT_ROOT)
    get_filename_component(ANCHOR_SIFT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)
endif()

# The exact integer as a fixed width limb array, which is the same value the python engine ingests
# and a different transform of it. Portable C11 with no intrinsic and no 128 bit type, so it builds
# anywhere and is the engine every vectorized one is checked against.
add_library(anchor_exact_portable STATIC no_rounding/exact_integer.c no_rounding/arm_portable.c)
target_include_directories(anchor_exact_portable PUBLIC no_rounding)
target_compile_options(anchor_exact_portable PRIVATE ${SIFT_WARNINGS})

# THE ENGINE. anchor_sift.c holds the search, the steering, the shared scan counters and the arm
# dispatch. They spell one primitive: byte equality at a shift, counted over positions. The search
# counts matches, the steering counts survivors, a scan arm counts those survivors at one offset.
#
# Each scan arm is its own file, engine/scan_<set>.c, one per instruction set. scan_portable.c is the
# C11 reference every other arm is graded against; a wide arm carries a compiler flag no other file
# may see, so it cannot share a translation unit. engine/ carries scan_portable.c, scan_avx2.c,
# scan_avx512.c, scan_neon.c and scan_sve.c, the same host sets no_rounding/ carries. The device arm
# matching no_rounding/arm_cuda.cu lands next.
set(ANCHOR_SIFT_SOURCES engine/anchor_sift.c engine/scan_portable.c)
set(ANCHOR_SIFT_DEFINES "")

# Each wide arm's flag is set ON ITS SOURCE FILE and never on the target. A target level flag would
# let the compiler emit that instruction anywhere in the engine, the portable path included, and a
# machine without it would meet an illegal instruction instead of a slower answer. Confining the flag
# to the one file it belongs to is what leaves the run time check something to decide, and it is why
# each arm is its own translation unit. The set carried here matches no_rounding/: a listing of the
# two directories names the same instruction sets.
include(CheckCCompilerFlag)
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|i[3-6]86)$")
    list(APPEND ANCHOR_SIFT_SOURCES engine/scan_avx2.c)
    list(APPEND ANCHOR_SIFT_DEFINES ANCHOR_STEER_HAVE_AVX2=1)
    if(MSVC)
        set_source_files_properties(engine/scan_avx2.c PROPERTIES COMPILE_OPTIONS "/arch:AVX2")
    else()
        set_source_files_properties(engine/scan_avx2.c PROPERTIES COMPILE_OPTIONS "-mavx2")
    endif()

    # AVX-512 on the GCC and Clang builds that accept the flags. MSVC's AVX-512 handling differs and
    # no machine here runs the arm, so it is gated to the same compilers the exact avx512 arm gates
    # to and confirmed by maint/engine/verify_arm_asm.sh rather than by running.
    if(NOT MSVC)
        check_c_compiler_flag("-mavx512f -mavx512bw" ANCHOR_STEER_CC_TAKES_AVX512)
        if(ANCHOR_STEER_CC_TAKES_AVX512)
            list(APPEND ANCHOR_SIFT_SOURCES engine/scan_avx512.c)
            list(APPEND ANCHOR_SIFT_DEFINES ANCHOR_STEER_HAVE_AVX512=1)
            set_source_files_properties(engine/scan_avx512.c
                PROPERTIES COMPILE_OPTIONS "-mavx512f;-mavx512bw")
        endif()
    endif()
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64|armv[78].*)$")
    list(APPEND ANCHOR_SIFT_SOURCES engine/scan_neon.c)
    list(APPEND ANCHOR_SIFT_DEFINES ANCHOR_STEER_HAVE_NEON=1)
    # NEON is part of the base aarch64 architecture and needs no flag there. A 32 bit ARM build does
    # need one, and asks for the softfp ABI's NEON rather than assuming a hard float target.
    if(NOT CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
        set_source_files_properties(engine/scan_neon.c PROPERTIES COMPILE_OPTIONS "-mfpu=neon")
    endif()

    # SVE on the aarch64 compilers that accept it. No part here has SVE, so this is an unrun arm the
    # emission check reads, the same as the exact sve arm.
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
        check_c_compiler_flag("-march=armv8.2-a+sve" ANCHOR_STEER_CC_TAKES_SVE)
        if(ANCHOR_STEER_CC_TAKES_SVE)
            list(APPEND ANCHOR_SIFT_SOURCES engine/scan_sve.c)
            list(APPEND ANCHOR_SIFT_DEFINES ANCHOR_STEER_HAVE_SVE=1)
            set_source_files_properties(engine/scan_sve.c
                PROPERTIES COMPILE_OPTIONS "-march=armv8.2-a+sve")
        endif()
    endif()
endif()

# The engine as it ships. Nothing in here reads a clock or prints, so a driver change cannot move a
# measurement.
add_library(anchor_sift_kernel STATIC ${ANCHOR_SIFT_SOURCES})
target_include_directories(anchor_sift_kernel PUBLIC engine no_rounding)
target_compile_definitions(anchor_sift_kernel PUBLIC ${ANCHOR_SIFT_DEFINES})
target_link_libraries(anchor_sift_kernel PUBLIC anchor_exact_portable)
target_compile_options(anchor_sift_kernel PRIVATE ${SIFT_WARNINGS})

# The same source with the counters compiled in. ANCHOR_SIFT_COUNT_READS is PUBLIC so a driver
# linking this library sees the same value the library was built with, which is what keeps a driver
# from calling anchor_sift_counters_reset against a kernel that does not define it.
add_library(anchor_sift_kernel_counted STATIC ${ANCHOR_SIFT_SOURCES})
target_include_directories(anchor_sift_kernel_counted PUBLIC engine no_rounding)
target_compile_definitions(anchor_sift_kernel_counted PUBLIC ${ANCHOR_SIFT_DEFINES}
    ANCHOR_SIFT_COUNT_READS=1)
target_link_libraries(anchor_sift_kernel_counted PUBLIC anchor_exact_portable)
target_compile_options(anchor_sift_kernel_counted PRIVATE ${SIFT_WARNINGS})

# The direct renderer, WITH THE DEVICE ARM COMPILED IN WHERE A CUDA TOOLCHAIN IS PRESENT. A machine
# carrying a device renders on it by default and the caller does not ask. The two arms produce the
# same bytes, so this is a performance decision, and bench_raster grades them against each other on
# every configuration.
#
# The device arm is a .cu and this project is declared C, so CUDA is enabled only when found. Where
# it is absent the stub arms in anchor_raster.c are linked instead, anchor_raster_device_available
# returns 0, and anchor_raster_render falls back to the host. Both arms of that gate are defined.
# A caller that knows CUDA cannot work here says so, and the search below is skipped entirely. The
# shell script sets this where nvcc is installed but its host compiler is not on PATH, which is a
# configure that would fail rather than a device that is absent.
option(ANCHOR_SKIP_CUDA "Do not look for a CUDA toolchain" OFF)

include(CheckLanguage)
if(NOT ANCHOR_SKIP_CUDA)
    check_language(CUDA)
endif()

# check_language only looks on PATH, and a toolkit installed normally is often not on it. A machine
# with a device and a toolkit should get the device arm regardless, so the standard install
# locations are searched before giving up. Newest version first, since the directories sort that way.
if(NOT CMAKE_CUDA_COMPILER AND NOT ANCHOR_SKIP_CUDA)
    file(GLOB ANCHOR_CUDA_CANDIDATES
        "C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v*/bin/nvcc.exe"
        "/usr/local/cuda*/bin/nvcc")
    if(ANCHOR_CUDA_CANDIDATES)
        list(SORT ANCHOR_CUDA_CANDIDATES)
        list(REVERSE ANCHOR_CUDA_CANDIDATES)
        list(GET ANCHOR_CUDA_CANDIDATES 0 CMAKE_CUDA_COMPILER)
        message(STATUS "anchor_raster: nvcc found off PATH at ${CMAKE_CUDA_COMPILER}")
    endif()
endif()

set(ANCHOR_RASTER_SOURCES render/anchor_raster.c)
set(ANCHOR_RASTER_DEFINES "")
if(CMAKE_CUDA_COMPILER)
    enable_language(CUDA)
    set(CMAKE_CUDA_STANDARD 17)
    set(CMAKE_CUDA_STANDARD_REQUIRED ON)
    if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)
        # native asks the toolkit for the architecture this machine carries. A toolkit too old to
        # know the keyword falls back to a concrete one rather than failing the configure.
        if(CMAKE_CUDA_COMPILER_VERSION VERSION_GREATER_EQUAL 11.5)
            set(CMAKE_CUDA_ARCHITECTURES native)
        else()
            set(CMAKE_CUDA_ARCHITECTURES 86)
        endif()
    endif()
    list(APPEND ANCHOR_RASTER_SOURCES render/raster_cuda.cu)
    list(APPEND ANCHOR_RASTER_DEFINES ANCHOR_RASTER_HAVE_CUDA=1)
    message(STATUS "anchor_raster: device arm compiled in, architectures ${CMAKE_CUDA_ARCHITECTURES}")
else()
    message(STATUS "anchor_raster: no CUDA toolchain, host arm only")
endif()

add_library(anchor_raster STATIC ${ANCHOR_RASTER_SOURCES})
target_include_directories(anchor_raster PUBLIC render)
target_compile_definitions(anchor_raster PUBLIC ${ANCHOR_RASTER_DEFINES})
target_compile_options(anchor_raster PRIVATE $<$<COMPILE_LANGUAGE:C>:${SIFT_WARNINGS}>)

# The renderer as a shared library, so the Python arm can reach it through ctypes. It carries the
# same sources as anchor_raster, so on a CUDA build the device arm is present and a Python caller
# renders on the device through anchor_raster_render without owning a device path, which the tree's
# library ban forbids Python anyway. WINDOWS_EXPORT_ALL_SYMBOLS puts the C entries in the export
# table so ctypes can find them; every other platform exports them by default.
add_library(anchor_render SHARED ${ANCHOR_RASTER_SOURCES})
target_include_directories(anchor_render PUBLIC render)
target_compile_definitions(anchor_render PUBLIC ${ANCHOR_RASTER_DEFINES})
target_compile_options(anchor_render PRIVATE $<$<COMPILE_LANGUAGE:C>:${SIFT_WARNINGS}>)
set_target_properties(anchor_render PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)

# Which vectorized arm this target can carry. Decided from the processor the build targets, and
# every gate is defined on both arms so #if always has a value and an unset build is never a silent
# false. An arm that is compiled in still asks the processor at run time before it is used.
set(ANCHOR_ARM_SOURCES "")
set(ANCHOR_ARM_DEFINES "")
set(ANCHOR_ARM_OPTIONS "")
set(ANCHOR_ARM_INCLUDES "")

if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|i[3-6]86)$")
    # One AVX2 arm for every x86 build. It carries both detection paths, MSVC's cpuid and the
    # builtin GCC and Clang share, so there is no per operating system copy to disagree with it.
    list(APPEND ANCHOR_ARM_SOURCES no_rounding/arm_avx2.c)
    list(APPEND ANCHOR_ARM_DEFINES ANCHOR_EXACT_HAVE_AVX2=1)
    # -mavx2 permits the intrinsics in this translation unit. It does not permit the compiler to
    # assume AVX2 anywhere else, because no other translation unit is built with it.
    if(NOT MSVC)
        list(APPEND ANCHOR_ARM_OPTIONS -mavx2)
    else()
        list(APPEND ANCHOR_ARM_OPTIONS /arch:AVX2)
    endif()
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64|armv[78].*)$")
    list(APPEND ANCHOR_ARM_SOURCES no_rounding/arm_neon.c)
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
        add_library(anchor_exact_avx512 STATIC no_rounding/arm_avx512.c)
        target_link_libraries(anchor_exact_avx512 PUBLIC anchor_exact_portable)
        target_compile_definitions(anchor_exact_avx512 PUBLIC ANCHOR_EXACT_HAVE_AVX512=1)
        target_compile_options(anchor_exact_avx512
            PRIVATE ${SIFT_WARNINGS} -mavx512f -mavx512bw -mavx512vl)
        list(APPEND ANCHOR_EXTRA_ARMS anchor_exact_avx512)
    endif()
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
    check_c_compiler_flag("-march=armv8.2-a+sve" ANCHOR_CC_TAKES_SVE)
    if(ANCHOR_CC_TAKES_SVE)
        add_library(anchor_exact_sve STATIC no_rounding/arm_sve.c)
        target_link_libraries(anchor_exact_sve PUBLIC anchor_exact_portable)
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

# Its warnings used to be set fifty lines below, inside bench_steer_arms's block, by a line naming
# this target instead of that one. bench_dispatch was covered by accident and bench_raster and
# bench_steer_arms were covered by nothing, which is invisible because a target with no warning
# flags emits no warnings and reads exactly like a clean one. Every add_executable here now sets its
# own beside its own link line, so the pairing is checkable by reading down rather than by counting.

# Grades the entropy-ordered rejection vector. Three things in one run: the steered arm returns the
# reference arm's count at a residual of exactly zero, the ordering reduces probe reads on a field
# where rarity varies, and the exact dispatch agrees with answers derived from the rule by hand.
# Carries its own negative control, ordering commonest symbol first, which must read more.
# Grades the entropy-ordered rejection vector. In test/ and not bench/ because it answers whether the
# engine is correct and never how fast: it carries no timing call, and the probe reads it measures
# are assertions rather than reported costs. Ordering commonest symbol first must read MORE than the
# unsteered order or the run fails, which is what makes the steering testable at all.
#
# Resolved from a computed root rather than an inline relative chain, matching test_arm_agreement.
add_executable(test_steer ${ANCHOR_SIFT_ROOT}/test/engine/test_steer.c)
target_link_libraries(test_steer PRIVATE anchor_sift_kernel bench_corpora)

# The corpus family comes from bench_corpora and is not generated a second time here. One field is
# not a measurement: a route that reads fewer bytes on a skewed field can read more on a uniform one,
# and a grader that sees only the field it was tuned on reports the tuning. Linking the shared
# generator is also what keeps skewed meaning one thing across this tree.
#
# The natural field is opened by absolute path, resolved at configure time. It was opened through a
# relative chain before, which made the run directory decide whether the field existed, and the test
# printed a skip and passed. A check whose failure is indistinguishable from its answer is not a
# check, so the path is compiled in and the file being absent is now a reported failure.
target_compile_definitions(test_steer PRIVATE ANCHOR_SIFT_SOURCE_ROOT="${ANCHOR_SIFT_ROOT}")

# The adversarial suite. Seven cases, every one differential or graded against a count derived by
# hand, so none of them checks a number somebody wrote down. It attacks the engine from outside its
# public surface: overlapping occurrences, both boundary alignments, a field where every survivor is
# false, and the probe_fits guard including the widest line that must be ADMITTED, since a guard
# refusing the family is as wrong as one that does not bound it.
#
# Its file block records that it has been seen to reject three deliberately broken engines, with the
# mutations and their signatures. A suite nobody has watched fail is indistinguishable from an empty
# loop, so that record is part of the test rather than commentary on it.
add_executable(test_adversarial "${ANCHOR_SIFT_ROOT}/test/engine/test_adversarial.c")
target_link_libraries(test_adversarial PRIVATE anchor_sift_kernel)

# Sweeps every render configuration, four layouts by four channels, writes each as a PGM, grades the
# host raster against the device one byte for byte where a device is present, and times the frame
# rate of a steered probe set against an unsteered one on the same object.
add_executable(bench_raster bench/bench_raster.c)
target_link_libraries(bench_raster PRIVATE anchor_raster anchor_sift_kernel)
target_compile_options(bench_raster PRIVATE ${SIFT_WARNINGS})

# Grades every steering scan against the portable one and then times them. The lengths it runs sit
# around the thirty-two lane boundary a wide scan works in, which is where a vectorized tail fails
# if it is going to.
add_executable(bench_steer_arms bench/bench_steer_arms.c)
target_link_libraries(bench_steer_arms PRIVATE anchor_sift_kernel)
target_compile_options(bench_steer_arms PRIVATE ${SIFT_WARNINGS})

# The ingestion reading: at what scale does the corpus agree with itself, and what does that cost
# the histogram bound. Links the counted kernel because the claim it checks is about probes and
# survivors, which are reads and not cycles.
# The oracle route against a counter table as the alphabet grows, and as it does not. Two axes,
# because one column is not a result: the oracle is flat in alphabet size and the table is linear in
# it, while at a fixed alphabet both are linear in the corpus and the table is several times faster.
# A reader shown only the first axis concludes the oracle is simply better, and below the crossover
# near six times the corpus length that conclusion is wrong.
#
# Contributed by the theorist session, read in full and committed here.
add_executable(bench_sigma bench/bench_sigma.c)
target_link_libraries(bench_sigma PRIVATE anchor_sift_kernel)
target_compile_options(bench_sigma PRIVATE ${SIFT_WARNINGS})

add_executable(bench_coherence bench/bench_coherence.c)
target_link_libraries(bench_coherence PRIVATE anchor_sift_kernel_counted bench_corpora)
target_compile_options(bench_coherence PRIVATE ${SIFT_WARNINGS})

# Every arm against the naive one at the lengths that bound the input: none, one, two. The kernel's
# contract is that no arm can lose a true occurrence, so an arm returning anything else is a defect
# whatever it measures, and this is the driver that says so. Links the uncounted kernel because what
# is under test is what the arms RETURN and not what they read.
#
# It is a negative control as much as a test: on a kernel whose choose_offsets clamps a zero length
# needle to needle_len - 1u, that wraps to SIZE_MAX and the run reads outside both pointers rather
# than printing a row.
#
# It lives under test/ and not under bench/, because bench/ answers how fast and test/ answers
# whether it is right, and those are two questions. It was written into bench/ and moved here on
# Douglas's ruling. The name moved with it: a file called bench_ anything, sitting in test/, keeps
# exactly the confusion the split was made to remove.
#
# The source sits outside this directory because the test tree is at the repository root, so the
# path is resolved from the root rather than written as a chain of parent directories. Counting
# directories to a destination is what broke every path in this tree the last time anything moved.
get_filename_component(ANCHOR_SIFT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../../.." ABSOLUTE)

add_executable(test_arm_agreement "${ANCHOR_SIFT_ROOT}/test/engine/test_arm_agreement.c")
target_link_libraries(test_arm_agreement PRIVATE anchor_sift_kernel)
target_compile_options(test_arm_agreement PRIVATE ${SIFT_WARNINGS})

# The O2 composition: a descent resuming from another descent's survivors, driven past one descent's
# cap. Answers whether the resume path is correct, so it lives in test/ and carries its controls, a
# planted target found past the cap, a flat field that refuses, an anytime superset and a cost report.
add_executable(test_o2_spawn "${ANCHOR_SIFT_ROOT}/test/engine/test_o2_spawn.c")
target_link_libraries(test_o2_spawn PRIVATE anchor_sift_kernel)
target_compile_options(test_o2_spawn PRIVATE ${SIFT_WARNINGS})

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
# All four of them include "mmgr_sha256.h", which is MMgr's test support and lives in MMgr, at
# deps/mmgr/test/support. This said three until it was counted: bench_ab.c, bench_cycles.c,
# bench_entropy.c and bench_sift.c all include it, and nothing checked the number against the
# files. Run `python maint/deps/get_deps.py` to put the clone there, then add
# that directory to the target's include path and compile its .c beside the driver. Nothing built
# here needs it: the corpora are filled by splitmix64 in bench_corpora, and bench_lattice carries
# its own three line shim for the same reason.
