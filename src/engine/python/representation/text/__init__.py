#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Text as a subject: reading it off disk, and putting one symbol in one place.

Here because these know what a character encoding is and what a publisher's line wrapping is,
which is knowledge about one subject and not about points carrying values. `bit_volume` sits in
the parent because it reads any corpus and knows nothing about any of them.
"""
