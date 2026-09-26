#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Constants the engine computes instead of storing. A natural constant is derivable from within, and here
# it is derived to whatever precision is asked and checked by two routes agreeing, never copied from a table.

from representation.constants.naturals import (
    pi,
    euler_e,
    root_two,
    ln_two,
    golden_ratio,
)

__all__ = ["pi", "euler_e", "root_two", "ln_two", "golden_ratio"]
