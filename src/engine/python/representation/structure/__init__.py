#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""Molecular structure as a subject: a deposited model turned into points, or into a chain.

The arithmetic inside is column slicing and vector differences. What makes it a subject is the
knowledge around it: that a PDB ATOM record puts its coordinates in fixed columns, that an alternate
location marker repeats an atom, that a backbone runs nitrogen to alpha carbon to carbon and around
again, and that those three bonds are fixed by chemistry near 1.46, 1.52 and 1.33 angstroms.

That last fact is why this subject is here at all. Every other set in this work was built to a known
answer or has no known answer, and a bond length is one nobody here chose.
"""
