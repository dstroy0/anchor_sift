# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# The C implementation of the engine. It needs only a C11 compiler: no ESP-IDF, no
# device toolchain, no Python, and nothing from the vendored library.

cmake_minimum_required(VERSION 3.16)
project(anchor_sift_engine_c C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

set(SIFT_WARNINGS $<$<C_COMPILER_ID:GNU,Clang>:-O2 -Wall -Wextra>)

if(NOT DEFINED ANCHOR_SIFT_ROOT)
    get_filename_component(ANCHOR_SIFT_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
endif()


add_library(anchor_exact_portable STATIC base/no_rounding/exact_integer.c base/no_rounding/arm_portable.c)
target_include_directories(anchor_exact_portable PUBLIC base/no_rounding)
target_compile_options(anchor_exact_portable PRIVATE ${SIFT_WARNINGS})


set(ANCHOR_EXACT_LIMBS "" CACHE STRING "Limbs per exact integer, a power of two from 1 to 32768")
set(ANCHOR_EXACT_DIGITS "" CACHE STRING "Decimal digit floor the exact width must hold")
if(ANCHOR_EXACT_LIMBS)
    target_compile_definitions(anchor_exact_portable PUBLIC ANCHOR_EXACT_LIMBS=${ANCHOR_EXACT_LIMBS}u)
endif()
if(ANCHOR_EXACT_DIGITS)
    target_compile_definitions(anchor_exact_portable PUBLIC ANCHOR_EXACT_DIGITS=${ANCHOR_EXACT_DIGITS}u)
endif()

set(ANCHOR_SIFT_SOURCES nbody/anchor_sift/anchor_sift.c nbody/anchor_sift/scan_portable.c)
set(ANCHOR_SIFT_DEFINES "")


include(CheckCCompilerFlag)
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|i[3-6]86)$")
    list(APPEND ANCHOR_SIFT_SOURCES nbody/anchor_sift/scan_avx2.c)
    list(APPEND ANCHOR_SIFT_DEFINES ANCHOR_STEER_HAVE_AVX2=1)
    if(MSVC)
        set_source_files_properties(nbody/anchor_sift/scan_avx2.c PROPERTIES COMPILE_OPTIONS "/arch:AVX2")
    else()
        set_source_files_properties(nbody/anchor_sift/scan_avx2.c PROPERTIES COMPILE_OPTIONS "-mavx2")
    endif()

    # AVX-512 on the GCC and Clang builds that accept the flags. MSVC's AVX-512 handling differs and
    # no machine here runs the arm. It is gated to the same compilers the exact avx512 arm gates
    # to and confirmed by maint/engine/verify_arm_asm.sh.
    if(NOT MSVC)
        check_c_compiler_flag("-mavx512f -mavx512bw" ANCHOR_STEER_CC_TAKES_AVX512)
        if(ANCHOR_STEER_CC_TAKES_AVX512)
            list(APPEND ANCHOR_SIFT_SOURCES nbody/anchor_sift/scan_avx512.c)
            list(APPEND ANCHOR_SIFT_DEFINES ANCHOR_STEER_HAVE_AVX512=1)
            set_source_files_properties(nbody/anchor_sift/scan_avx512.c
                PROPERTIES COMPILE_OPTIONS "-mavx512f;-mavx512bw")
        endif()
    endif()
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64|armv[78].*)$")
    list(APPEND ANCHOR_SIFT_SOURCES nbody/anchor_sift/scan_neon.c)
    list(APPEND ANCHOR_SIFT_DEFINES ANCHOR_STEER_HAVE_NEON=1)
    # NEON is part of the base aarch64 architecture and needs no flag there. A 32 bit ARM build does
    # need one, and asks for the softfp ABI's NEON.
    if(NOT CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
        set_source_files_properties(nbody/anchor_sift/scan_neon.c PROPERTIES COMPILE_OPTIONS "-mfpu=neon")
    endif()

    # SVE on the aarch64 compilers that accept it. No part here has SVE. This is an unrun arm the
    # emission check reads, the same as the exact sve arm.
    if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
        check_c_compiler_flag("-march=armv8.2-a+sve" ANCHOR_STEER_CC_TAKES_SVE)
        if(ANCHOR_STEER_CC_TAKES_SVE)
            list(APPEND ANCHOR_SIFT_SOURCES nbody/anchor_sift/scan_sve.c)
            list(APPEND ANCHOR_SIFT_DEFINES ANCHOR_STEER_HAVE_SVE=1)
            set_source_files_properties(nbody/anchor_sift/scan_sve.c
                PROPERTIES COMPILE_OPTIONS "-march=armv8.2-a+sve")
        endif()
    endif()
endif()


add_library(anchor_sift_kernel STATIC ${ANCHOR_SIFT_SOURCES})
target_include_directories(anchor_sift_kernel PUBLIC nbody/anchor_sift base/no_rounding)
target_compile_definitions(anchor_sift_kernel PUBLIC ${ANCHOR_SIFT_DEFINES})
target_link_libraries(anchor_sift_kernel PUBLIC anchor_exact_portable)
target_compile_options(anchor_sift_kernel PRIVATE $<$<COMPILE_LANGUAGE:C>:${SIFT_WARNINGS}>)

add_library(anchor_sift_kernel_counted STATIC ${ANCHOR_SIFT_SOURCES})
target_include_directories(anchor_sift_kernel_counted PUBLIC nbody/anchor_sift base/no_rounding)
target_compile_definitions(anchor_sift_kernel_counted PUBLIC ${ANCHOR_SIFT_DEFINES}
    ANCHOR_SIFT_COUNT_READS=1)
target_link_libraries(anchor_sift_kernel_counted PUBLIC anchor_exact_portable)
target_compile_options(anchor_sift_kernel_counted PRIVATE $<$<COMPILE_LANGUAGE:C>:${SIFT_WARNINGS}>)

option(ANCHOR_SKIP_CUDA "Do not look for a CUDA toolchain" OFF)

include(CheckLanguage)
if(NOT ANCHOR_SKIP_CUDA)
    check_language(CUDA)
endif()

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
        # know the keyword falls back to a concrete one.
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

add_library(anchor_render SHARED ${ANCHOR_RASTER_SOURCES})
target_include_directories(anchor_render PUBLIC render)
target_compile_definitions(anchor_render PUBLIC ${ANCHOR_RASTER_DEFINES})
target_compile_options(anchor_render PRIVATE $<$<COMPILE_LANGUAGE:C>:${SIFT_WARNINGS}>)
set_target_properties(anchor_render PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)

if(CMAKE_CUDA_COMPILER)
    foreach(kernel anchor_sift_kernel anchor_sift_kernel_counted)
        target_sources(${kernel} PRIVATE nbody/anchor_sift/scan_cuda.cu)
        target_compile_definitions(${kernel} PUBLIC ANCHOR_STEER_HAVE_CUDA=1)
    endforeach()
endif()

set(ANCHOR_ARM_SOURCES "")
set(ANCHOR_ARM_DEFINES "")
set(ANCHOR_ARM_OPTIONS "")
set(ANCHOR_ARM_INCLUDES "")

if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64|i[3-6]86)$")
    # One AVX2 arm for every x86 build. It carries both detection paths, MSVC's cpuid and the
    # builtin GCC and Clang share. There is no per operating system copy to disagree with it.
    list(APPEND ANCHOR_ARM_SOURCES base/no_rounding/arm_avx2.c)
    list(APPEND ANCHOR_ARM_DEFINES ANCHOR_EXACT_HAVE_AVX2=1)
    # -mavx2 permits the intrinsics in this translation unit. It does not permit the compiler to
    # assume AVX2 anywhere else, because no other translation unit is built with it.
    if(NOT MSVC)
        list(APPEND ANCHOR_ARM_OPTIONS -mavx2)
    else()
        list(APPEND ANCHOR_ARM_OPTIONS /arch:AVX2)
    endif()
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64|armv[78].*)$")
    list(APPEND ANCHOR_ARM_SOURCES base/no_rounding/arm_neon.c)
    list(APPEND ANCHOR_ARM_DEFINES ANCHOR_EXACT_HAVE_NEON=1)
    # NEON is part of the base aarch64 architecture and needs no flag there. A 32 bit ARM build
    # does need one, and asks for the softfp ABI's NEON.
    if(NOT CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
        list(APPEND ANCHOR_ARM_OPTIONS -mfpu=neon)
    endif()
endif()


include(CheckCCompilerFlag)
if(CMAKE_SYSTEM_PROCESSOR MATCHES "^(x86_64|AMD64)$" AND NOT MSVC)
    check_c_compiler_flag("-mavx512f -mavx512bw -mavx512vl" ANCHOR_CC_TAKES_AVX512)
    if(ANCHOR_CC_TAKES_AVX512)
        add_library(anchor_exact_avx512 STATIC base/no_rounding/arm_avx512.c)
        target_link_libraries(anchor_exact_avx512 PUBLIC anchor_exact_portable)
        target_compile_definitions(anchor_exact_avx512 PUBLIC ANCHOR_EXACT_HAVE_AVX512=1)
        target_compile_options(anchor_exact_avx512
            PRIVATE ${SIFT_WARNINGS} -mavx512f -mavx512bw -mavx512vl)
        list(APPEND ANCHOR_EXTRA_ARMS anchor_exact_avx512)
    endif()
elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "^(aarch64|arm64|ARM64)$")
    check_c_compiler_flag("-march=armv8.2-a+sve" ANCHOR_CC_TAKES_SVE)
    if(ANCHOR_CC_TAKES_SVE)
        add_library(anchor_exact_sve STATIC base/no_rounding/arm_sve.c)
        target_link_libraries(anchor_exact_sve PUBLIC anchor_exact_portable)
        target_compile_definitions(anchor_exact_sve PUBLIC ANCHOR_EXACT_HAVE_SVE=1)
        target_compile_options(anchor_exact_sve PRIVATE ${SIFT_WARNINGS} -march=armv8.2-a+sve)
        list(APPEND ANCHOR_EXTRA_ARMS anchor_exact_sve)
    endif()
endif()

if(CMAKE_CUDA_COMPILER)
    list(APPEND ANCHOR_ARM_SOURCES base/no_rounding/arm_cuda.cu)
    list(APPEND ANCHOR_ARM_DEFINES ANCHOR_EXACT_HAVE_CUDA=1)
endif()

if(ANCHOR_ARM_SOURCES)
    add_library(anchor_exact_arms STATIC ${ANCHOR_ARM_SOURCES})
    target_link_libraries(anchor_exact_arms PUBLIC anchor_exact_portable ${ANCHOR_EXTRA_ARMS})
    target_include_directories(anchor_exact_arms PUBLIC ${ANCHOR_ARM_INCLUDES})
    target_compile_definitions(anchor_exact_arms PUBLIC ${ANCHOR_ARM_DEFINES})
    target_compile_options(anchor_exact_arms PRIVATE $<$<COMPILE_LANGUAGE:C>:${SIFT_WARNINGS} ${ANCHOR_ARM_OPTIONS}>)
else()
    # No vectorized arm for this processor. The library still exists so the driver links the same
    # way everywhere, and it carries only the portable arm.
    add_library(anchor_exact_arms INTERFACE)
    target_link_libraries(anchor_exact_arms INTERFACE anchor_exact_portable)
endif()

add_executable(bench_exact_arms ${ANCHOR_SIFT_ROOT}/bench/bench_exact_arms.c)
target_link_libraries(bench_exact_arms PRIVATE anchor_exact_arms anchor_exact_portable)
target_compile_options(bench_exact_arms PRIVATE ${SIFT_WARNINGS})

add_executable(bench_exact ${ANCHOR_SIFT_ROOT}/bench/bench_exact.c)
target_link_libraries(bench_exact PRIVATE anchor_exact_portable)
target_compile_options(bench_exact PRIVATE ${SIFT_WARNINGS})

add_library(bench_corpora STATIC ${ANCHOR_SIFT_ROOT}/bench/bench_corpora.c)
target_include_directories(bench_corpora PUBLIC ${ANCHOR_SIFT_ROOT}/bench)
target_compile_options(bench_corpora PRIVATE ${SIFT_WARNINGS})

# Reads, which travel between machines and are what an asymptotic claim is made of.
add_executable(bench_scaling_reads ${ANCHOR_SIFT_ROOT}/bench/bench_scaling.c)
target_link_libraries(bench_scaling_reads PRIVATE anchor_sift_kernel_counted bench_corpora)
target_compile_options(bench_scaling_reads PRIVATE ${SIFT_WARNINGS})

# Cycles, which belong to the machine that produced them and are for the dispatch decision alone.
add_executable(bench_scaling_cycles ${ANCHOR_SIFT_ROOT}/bench/bench_scaling.c)
target_link_libraries(bench_scaling_cycles PRIVATE anchor_sift_kernel bench_corpora)
target_compile_options(bench_scaling_cycles PRIVATE ${SIFT_WARNINGS})

add_executable(bench_dispatch ${ANCHOR_SIFT_ROOT}/bench/bench_dispatch.c)
target_link_libraries(bench_dispatch PRIVATE anchor_sift_kernel bench_corpora)
target_compile_options(bench_dispatch PRIVATE ${SIFT_WARNINGS})

# The engine's tests live in the anchor_sift tree this was forked from; a fork without them builds without them.
if(EXISTS "${ANCHOR_SIFT_ROOT}/test/engine/test_steer.c")
    add_executable(test_steer ${ANCHOR_SIFT_ROOT}/test/engine/test_steer.c)
    target_link_libraries(test_steer PRIVATE anchor_sift_kernel bench_corpora)
    target_compile_definitions(test_steer PRIVATE ANCHOR_SIFT_SOURCE_ROOT="${ANCHOR_SIFT_ROOT}")
    add_executable(test_adversarial "${ANCHOR_SIFT_ROOT}/test/engine/test_adversarial.c")
    target_link_libraries(test_adversarial PRIVATE anchor_sift_kernel)
endif()

add_executable(bench_raster ${ANCHOR_SIFT_ROOT}/bench/bench_raster.c)
target_link_libraries(bench_raster PRIVATE anchor_raster anchor_sift_kernel)
target_compile_options(bench_raster PRIVATE ${SIFT_WARNINGS})

add_executable(bench_steer_arms ${ANCHOR_SIFT_ROOT}/bench/bench_steer_arms.c)
target_link_libraries(bench_steer_arms PRIVATE anchor_sift_kernel)
target_compile_options(bench_steer_arms PRIVATE ${SIFT_WARNINGS})


add_executable(bench_sigma ${ANCHOR_SIFT_ROOT}/bench/bench_sigma.c)
target_link_libraries(bench_sigma PRIVATE anchor_sift_kernel)
target_compile_options(bench_sigma PRIVATE ${SIFT_WARNINGS})

add_executable(bench_coherence ${ANCHOR_SIFT_ROOT}/bench/bench_coherence.c)
target_link_libraries(bench_coherence PRIVATE anchor_sift_kernel_counted bench_corpora)
target_compile_options(bench_coherence PRIVATE ${SIFT_WARNINGS})

if(EXISTS "${ANCHOR_SIFT_ROOT}/test/engine/test_arm_agreement.c")
    add_executable(test_arm_agreement "${ANCHOR_SIFT_ROOT}/test/engine/test_arm_agreement.c")
    target_link_libraries(test_arm_agreement PRIVATE anchor_sift_kernel)
    target_compile_options(test_arm_agreement PRIVATE ${SIFT_WARNINGS})
    add_executable(test_o2_spawn "${ANCHOR_SIFT_ROOT}/test/engine/test_o2_spawn.c")
    target_link_libraries(test_o2_spawn PRIVATE anchor_sift_kernel)
    target_compile_options(test_o2_spawn PRIVATE ${SIFT_WARNINGS})
endif()


include(CheckCSourceCompiles)
check_c_source_compiles("#include <complex.h>
int main(void) { double _Complex held = 1.0 + (2.0 * I); return (int)creal(held * held) + 3; }"
    ANCHOR_CC_HAS_COMPLEX)
set(ANCHOR_UNTIMED_BENCHES bench_scaling_reads bench_scaling_cycles)
if(ANCHOR_CC_HAS_COMPLEX)
    add_executable(bench_lattice ${ANCHOR_SIFT_ROOT}/bench/bench_lattice.c)
    target_compile_options(bench_lattice PRIVATE ${SIFT_WARNINGS})
    if(NOT WIN32)
        target_link_libraries(bench_lattice PRIVATE m)
    endif()
    list(APPEND ANCHOR_UNTIMED_BENCHES bench_lattice)
else()
    message(STATUS "bench_lattice: this C compiler has no C99 _Complex, not built")
endif()

foreach(one ${ANCHOR_UNTIMED_BENCHES})
    set_target_properties(${one} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
        INTERPROCEDURAL_OPTIMIZATION FALSE)
endforeach()

