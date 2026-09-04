# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
# negotiated commercial licensing contract or an educator's license issued to you personally.

# A span is a value type with pure walks over it and no storage of its own, so this reaches nothing
# but mmgr.h. It sits below locus_carcerum, byteio and anything else that hands a buffer to a caller.
mmgr_add_module(spatium
  SOURCES spatium.c
  DEPS
)