# embedded_types - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational

include(FetchContent)

FetchContent_Declare(
  unity
  GIT_REPOSITORY https://github.com/ThrowTheSwitch/Unity.git
  GIT_TAG        v2.6.1
  GIT_SHALLOW    TRUE)
FetchContent_MakeAvailable(unity)

set(EMBEDDED_TYPES_UNITY_RB "${unity_SOURCE_DIR}/auto/generate_test_runner.rb")

find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(EMBEDDED_TYPES_HARNESS "${CMAKE_CURRENT_SOURCE_DIR}/harness.py")
set(EMBEDDED_TYPES_TEST_ROOT "${CMAKE_CURRENT_SOURCE_DIR}")

include(EmbeddedTypesSuite)

set_property(GLOBAL PROPERTY EMBEDDED_TYPES_SUITES_BUILT "")

add_subdirectory(unit)

get_property(EMBEDDED_TYPES_BUILT GLOBAL PROPERTY EMBEDDED_TYPES_SUITES_BUILT)
list(LENGTH EMBEDDED_TYPES_BUILT EMBEDDED_TYPES_BUILT_COUNT)
if(EMBEDDED_TYPES_BUILT_COUNT EQUAL 0)
  message(WARNING "embedded_types: no test suites were built")
endif()
message(STATUS "embedded_types: ${EMBEDDED_TYPES_BUILT_COUNT} test targets")
