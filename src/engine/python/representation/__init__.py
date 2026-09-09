#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Any domain written as points carrying values.

Text is positions along a line holding symbols, sound is the same holding amplitudes, a picture is
positions on a plane, a structure is positions in space. Writing every domain that way lets
one instrument read all of them, and it is the only place in the engine that knows a domain exists.

What belongs here: readers that take a file and return points and values, and the re-seatings that
put one symbol in one place. What does not: anything that chooses a scale, which is partition, and
anything that scores, which is measure.
"""
