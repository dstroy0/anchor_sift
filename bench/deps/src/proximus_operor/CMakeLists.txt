# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
# negotiated commercial licensing contract or an educator's license issued to you personally.

# -O3 more than doubles this one, 640 bytes to 1332, and moves nothing measurable: the
# entries are single loads and stores that are already one instruction each. It is the
# widest -Os to -O3 spread in the library, 528 to 1332. Sizes measured per translation
# unit with no LTO; see docs/quality/optimization.md for the table and the command.
mmgr_add_module(proximus_operor
  SOURCES proximus_operor.c
  OPTIMIZE -O2
)
