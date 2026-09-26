#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Sound as a subject: a waveform re-sliced to the scale its units occupy.

The arithmetic inside is generic blocking. What makes it a subject is the knowledge around it: that
a whale song unit runs one to three seconds, that a 10 ms window is about one phoneme, and that an
archival recording may be time compressed by a factor written into its file name. Reading a
vocalization at sample scale instead cost this work a published ordering.
"""
