
/* orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file orior.h
 * @brief The engine: the search, the steering that places its probes, and the scan underneath both.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 *
 * @note This is the kernel. Everything here is the thing being measured, and nothing here reads a
 *       clock, builds a corpus or prints a row. Those belong to the driver.
 * @note ONE PRIMITIVE, WRITTEN ONCE. Every loop below asks whether `corpus[at + offset]` equals
 *       `needle[offset]` and counts the positions where it does. The search counts matches, the
 *       steering counts survivors, and the scan counts the same survivors wider. They were three
 *       files until they were folded here. A reader looking for the engine now opens
 *       one file instead of a directory.
 * @note Every engine has the same signature and returns the same count, letting a driver call any
 *       of them through one pointer. Where two disagree, one of them has a defect. Nothing about
 *       the difference is a tradeoff.
 */
#ifndef ORIOR_H
#define ORIOR_H

#include "orior_engines.h"

#endif
