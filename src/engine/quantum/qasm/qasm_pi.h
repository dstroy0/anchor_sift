// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// qasm_pi.h: pi to QASM_PI_PLACES places, for the fixed point at QASM_PI_BITS guard bits
//
// Written by utils/maint/engine/emit_qasm_pi.py from representation.constants.naturals.pi. Do not edit it: emit
// it again. 10^QASM_PI_PLACES is past 2^(QASM_PI_BITS + 1): the digits are within half a unit of pi at that
// width, and qasm_exact.c refuses to build where QASM_GUARD_BITS has grown past QASM_PI_BITS.
#ifndef QASM_PI_H
#define QASM_PI_H

#define QASM_PI_BITS 124u
#define QASM_PI_PLACES 38u
#define QASM_PI_TEXT \
    "3.14159265358979323846264338327950288419"

#endif
