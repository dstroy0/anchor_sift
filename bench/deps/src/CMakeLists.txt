# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
# negotiated commercial licensing contract or an educator's license issued to you personally.

# src/ is the include root: a module header is reached as <module>/<module>.h. include/ is the other
# one a consumer adds, and it carries mmgr.h, which every module header includes.
set(MMGR_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}" CACHE INTERNAL "include root")

# One directory per module, each declaring only what it is and what it needs.
# Ordered so a dependency is defined before whatever links it.
add_subdirectory(clz)
add_subdirectory(impensa_ancorae_acus)
add_subdirectory(ascii_persona_bitorum)
add_subdirectory(bitorum_introitus_exitus)
add_subdirectory(endian)
add_subdirectory(pow5)
add_subdirectory(proximus_operor)
add_subdirectory(verbum_scrutor)
add_subdirectory(memoria_operor)
add_subdirectory(cellularum_laboro)
add_subdirectory(spatium)
add_subdirectory(octetus_introitus_exitus)
add_subdirectory(locus_carcerum)
add_subdirectory(memoria_anularis)
add_subdirectory(memoria_externa)
add_subdirectory(transformo)
add_subdirectory(memoriam_praetereo)
add_subdirectory(fractio)
add_subdirectory(verba_scribo)
add_subdirectory(numeros_scribo)

# One aggregate per environment, so a test or a consumer links `mmgr_<env>` rather than naming
# seventeen modules and getting the list wrong.
foreach(entry IN LISTS MMGR_ENVIRONMENTS)
  mmgr_env_name("${entry}" env defs)
  get_property(_mods GLOBAL PROPERTY MMGR_TARGETS_${env})
  add_library(mmgr_${env} INTERFACE)
  target_link_libraries(mmgr_${env} INTERFACE ${_mods})
endforeach()
