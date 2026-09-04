# embedded_types - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational

function(embedded_types_add_suite suite_name)
    set(suite_dir "${CMAKE_CURRENT_SOURCE_DIR}")
    set(suite_src "${suite_dir}/${suite_name}.c")
    set(runner "${suite_dir}/unity_runner.c")

    if(NOT EXISTS "${suite_src}")
        message(FATAL_ERROR
                "embedded_types: ${suite_name} has no ${suite_name}.c - a suite directory holds exactly one")
    endif()

    add_custom_command(
        OUTPUT "${runner}"
        COMMAND ${Python3_EXECUTABLE} "${EMBEDDED_TYPES_HARNESS}" runners gen "${suite_dir}"
                --unity "${EMBEDDED_TYPES_UNITY_RB}"
        DEPENDS "${suite_src}" "${EMBEDDED_TYPES_HARNESS}"
        COMMENT "embedded_types: generating Unity runner for ${suite_name}"
        VERBATIM
    )
    add_custom_target(${suite_name}_runner DEPENDS "${runner}")
    set_source_files_properties("${runner}" PROPERTIES GENERATED TRUE)

    add_executable(${suite_name}
        "${suite_src}"
        "${runner}"
        "${unity_SOURCE_DIR}/src/unity.c")
    add_dependencies(${suite_name} ${suite_name}_runner)
    target_include_directories(${suite_name} PRIVATE "${unity_SOURCE_DIR}/src")

    target_compile_options(${suite_name} PRIVATE ${EMBEDDED_TYPES_TEST_WARNINGS})
    target_link_libraries(${suite_name} PRIVATE embedded_types::embedded_types)
    set_target_properties(${suite_name} PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/test")

    add_test(NAME ${suite_name} COMMAND ${suite_name})
    set_property(GLOBAL APPEND PROPERTY EMBEDDED_TYPES_SUITES_BUILT "${suite_name}")
endfunction()
