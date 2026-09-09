#!/usr/bin/env python3
# anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
"""The maximum entropy background under the constraints the object supplies.

Entropy is strictly concave and a constraint fixing counts or marginals is linear, so the
constrained maximum exists and sits at a single point. The background is therefore solved for and
never searched for. It carries no seed and no local optimum. Where the only constraints are single
symbol frequencies the maximizer factorizes, leaving a reference that is memoryless by construction
instead of by assumption.

What belongs here: permutation nulls, block shuffles that keep structure up to a stated span, and
the memoryless controls. What does not: the statistic read against them, which is measure.
"""
