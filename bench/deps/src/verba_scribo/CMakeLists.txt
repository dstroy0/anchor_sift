# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
# negotiated commercial licensing contract or an educator's license issued to you personally.

# -O3 adds 2272 bytes here, 21% on top of the 10812 this module takes at -O2, and buys
# about 1.5% on a render. The digit loops are short and already shaped; there is nothing
# for it to unroll that pays for itself. Sizes measured per translation unit with no LTO;
# see docs/quality/optimization.md for the table and the command.
#
# The pattern pass is off because verba_zeros writes a run of them with a plain loop, and at -O2
# that pass rewrites such a loop as a memset. The call costs about sixty cycles before it writes a
# byte and the runs this module produces are three at the leading end and about seventeen at the
# trailing one, so none of them is long enough to earn it back. Off, the loop measured 26 cycles
# against 32 at two zeros, 34 against 60 at six and 58 against 144 at eighteen, on an ESP32-S3.
mmgr_add_module(verba_scribo
  SOURCES verba_scribo.c
  DEPS
    cellularum_laboro
    clz
    fractio
    transformo
    proximus_operor
  OPTIMIZE "-O2;-fno-tree-loop-distribute-patterns"
)
