#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""The unit and the scale the points are read at.

A reading is undetermined until its partition is fixed, and a partition is fixed in one of three
ways: stipulated, chosen in advance and held; estimated, by a sweep of the coarse graining, taking
the value where it stops moving; or supervised, supplied from outside the sample. Only the third
adds information the sample did not already carry.

What belongs here: symbol widths, window ladders, space filling curves that carry n dimensions
through one, and the sweeps that say where a choice stops mattering. What does not: the reference a
partition makes available, which is its own part.
"""
