# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
# negotiated commercial licensing contract or an educator's license issued to you personally.

# The engine is inline inside this translation unit and a call from outside it. Header-only was
# right when one module converted numbers; at two, always_inline put a copy of the whole thing
# in each. See transformo.c.
mmgr_add_module(transformo
  SOURCES transformo.c
  DEPS
    clz
    fractio
    pow5
)
