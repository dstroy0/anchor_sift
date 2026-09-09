#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Pictures as a subject: a row major file of bytes that is really a plane.

The arithmetic inside is reshaping and thinning. What makes it a subject is the knowledge around it:
that a pixel and the pixel below it lie one width apart in the file, that a short read of such a file
is a thin strip and not a small picture, and what width each of these paintings was decoded at.

Nobody can measure that width without already having it. Two readings set out to recover a width
from the data and are scored against this table, so the table is written down and never derived.
"""
