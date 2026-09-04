# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
# negotiated commercial licensing contract or an educator's license issued to you personally.

# One profile, one translation unit. The table is file local to whichever of these is compiled,
# so the four that are not selected are not in the image and none of the five puts a 256 byte
# copy of itself into every module that asks what a byte costs.
if(DEFINED MMGR_ANCORAE_FORMA)
  string(TOLOWER "${MMGR_ANCORAE_FORMA}" _forma)
else()
  set(_forma generic)
endif()

mmgr_add_module(impensa_ancorae_acus
  SOURCES impensa_ancorae_acus_${_forma}.c
)
