# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
# negotiated commercial licensing contract or an educator's license issued to you personally.

# The ring state and every entry are defined in the .c and only declared in the header, so a
# consumer compiles against no layout at all and <stdatomic.h> stays this file's problem. LTO is
# what folds a call back into its caller across that boundary, so the separation costs nothing at
# link time. No DEPS: the span mover, the bit index and the span type are all defined in the .c,
# so the module reaches nothing outside mmgr.h and what embedded_types puts behind it.
mmgr_add_module(memoria_anularis
  SOURCES memoria_anularis.c
  DEPS
)
