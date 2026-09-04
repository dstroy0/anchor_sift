# embedded_types - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational

cmake_minimum_required(VERSION 3.16)

project(
  embedded_types
  VERSION 1.0.0
  DESCRIPTION "Fixed widths, a machine word, and the compile-time machinery a C11 embedded library is written in"
  LANGUAGES C)

add_library(embedded_types INTERFACE)
add_library(embedded_types::embedded_types ALIAS embedded_types)

target_include_directories(
  embedded_types INTERFACE $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
                           $<INSTALL_INTERFACE:include>)

target_compile_features(embedded_types INTERFACE c_std_11)

option(EMBEDDED_TYPES_BUILD_TESTS "Build the test suite" ${PROJECT_IS_TOP_LEVEL})
option(EMBEDDED_TYPES_WERROR "Treat warnings as errors in this project's own targets" OFF)

set(EMBEDDED_TYPES_WARNINGS
    $<$<C_COMPILER_ID:GNU,Clang,AppleClang>:-Wall;-Wextra;-Wpedantic;-Wshadow;-Wconversion;-Wsign-conversion;-Wcast-align;-Wcast-qual;-Wstrict-prototypes;-Wmissing-prototypes;-Wpointer-arith;-Wvla>
    $<$<AND:$<BOOL:${EMBEDDED_TYPES_WERROR}>,$<C_COMPILER_ID:GNU,Clang,AppleClang>>:-Werror>)

set(EMBEDDED_TYPES_TEST_WARNINGS
    $<$<C_COMPILER_ID:GNU,Clang,AppleClang>:-Wall;-Wextra;-Wpedantic;-Wshadow;-Wcast-align;-Wcast-qual;-Wstrict-prototypes;-Wpointer-arith;-Wvla>
    $<$<AND:$<BOOL:${EMBEDDED_TYPES_WERROR}>,$<C_COMPILER_ID:GNU,Clang,AppleClang>>:-Werror>)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

if(EMBEDDED_TYPES_BUILD_TESTS)
  enable_testing()
  add_subdirectory(test)
endif()
