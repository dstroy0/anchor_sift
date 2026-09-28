// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// engine_config_key.h: atoms, steps, keys and the record machine's types (engine_config.h includes the parts in order)
#ifndef ENGINE_CONFIG_KEY_H
#define ENGINE_CONFIG_KEY_H

#include "engine_config_platform.h"

#ifdef __cplusplus
extern "C"
{
#endif

#define ENGINE_FROM_ATOM 0xFFFFFFFFu

    typedef struct
    {
        const unsigned short *lanes;
        unsigned long long depth;
        unsigned long long height;
        unsigned long long width;
    } Atom;

    typedef enum
    {
        ENGINE_SMOOTH = 1,
        ENGINE_KEEP = 2,
        ENGINE_SCALE_SUBTRACT = 3
    } EngineOperation;

    typedef struct
    {
        EngineOperation operation;
        unsigned int orders[3];
        unsigned int shift;
    } EngineStep;

    typedef struct
    {
        unsigned long long taps;
        unsigned long long limbs;
        unsigned long long first;
        unsigned long long growth_bits;
    } EngineKeyRow;

    typedef struct
    {
        unsigned int negative;
        unsigned long long shift;
        EngineKeyRow row[ENGINE_AXES];
    } EngineKeyTerm;

    typedef struct
    {
        unsigned int terms;
        EngineKeyTerm *term;
        unsigned int *limbs;
        unsigned long long limb_count;
    } EngineKey;

    typedef struct
    {
        unsigned int axis;
        unsigned int taps;
        unsigned int row_limbs;
        unsigned int in_limbs;
        unsigned int out_limbs;
        unsigned int in_plane;
        unsigned int out_plane;
        unsigned int reserved;
        unsigned long long weights;
    } DeviceSweep;

    typedef struct
    {
        unsigned int negative;
        unsigned int shift;
        DeviceSweep sweep[ENGINE_AXES];
    } DeviceTerm;

    typedef struct CycleKey CycleKey;

    typedef struct
    {
        unsigned int terms;
        unsigned int bits;
        unsigned int columns;
        unsigned int planes;
        unsigned long long range[3];
        DeviceTerm *term_table;
        unsigned int *weights;
        unsigned long long weight_count;
    } EngineKeyLayout;

    typedef enum
    {
        ENGINE_RECORD_FIELD = 1,
        ENGINE_RECORD_CONSTANT = 2,
        ENGINE_RECORD_PRODUCT = 3,
        ENGINE_RECORD_SUM = 4,
        ENGINE_RECORD_DIFFERENCE = 5,
        ENGINE_RECORD_LADDER = 6,
        ENGINE_RECORD_ABSOLUTE = 7,
        ENGINE_RECORD_COMPARE = 8,
        ENGINE_RECORD_FIELD_SIGNED = 9,
        ENGINE_RECORD_TABLE = 10,
        // the exact integer's division as register operations: the quotient rounds toward zero and the remainder
        // carries the numerator's sign (left = quotient . right + remainder); the gcd is never negative; the exact
        // quotient is the multiply-and-mask division, and a remainder errors on the lane. A zero divisor errors on the
        // lane.
        ENGINE_RECORD_QUOTIENT = 11,
        ENGINE_RECORD_REMAINDER = 12,
        ENGINE_RECORD_GCD = 13,
        ENGINE_RECORD_EXACT_QUOTIENT = 14,
        // the bitwise operations on the exact integers' two's complement, as though each were sign-extended without
        // end: the xor is negative where exactly one operand is, the and where both are. Each is one bit wider than its
        // wider operand, since -1 xor (2^n - 1) is -2^n.
        ENGINE_RECORD_XOR = 15,
        ENGINE_RECORD_AND = 16,
        // the two's complement wrap of the left register to `right` bits, ENGINE_RECORD_WRAP_BITS_LEAST or more: the
        // value modulo 2^right, read back signed, in [-2^(right - 1), 2^(right - 1)). The unsigned residue is the and
        // with the mask 2^right - 1.
        ENGINE_RECORD_WRAP = 17,
        // the lane's own number, the one a sweep runs the lane as, never negative and ENGINE_RECORD_LANE_BITS wide. It
        // reads no register and no field. One shared record and the lanes enumerate a range with nothing stored a
        // lane.
        ENGINE_RECORD_LANE = 18
    } EngineRecordOperation;

#define ENGINE_GOLDEN_RUNGS 92u

// The register file: ENGINE_RECORD_LIMBS_MAX limbs of live registers, each register's sign held beside it. It is
// the record machine's one binding resource. The step count is the scheduler's n and has no bound of its own: floors
// of steps stack in one step table, register reuse frees a register after its last reader, and a lane runs the whole
// stack in one launch.
#define ENGINE_RECORD_LIMBS_MAX 256u

// A lookup table's index is the low bits of one register. It fits a single limb.
#define ENGINE_RECORD_TABLE_INDEX_BITS_MAX 32u

// The narrowest two's complement wrap, a nibble.
#define ENGINE_RECORD_WRAP_BITS_LEAST 4u

// A lane's number is a sweep's 64-bit count, and its register is that wide: two limbs.
#define ENGINE_RECORD_LANE_BITS 64u

#define ENGINE_RECORD_MEMBERS_MAX 3u

    typedef struct
    {
        EngineRecordOperation operation;
        unsigned int left;
        unsigned int right;
        unsigned int member;
    } EngineRecordStep;

    // One lookup table: the low `index_bits` of the source register select one of `1 << index_bits`
    // entries, each `out_bits` wide, laid out as (1 << index_bits) rows of ((out_bits + 31) / 32) limbs.
    // This is the engine's nonlinear edge (kolmogorov_arnold.md): a general one-variable function over a
    // lane's alphabet, built once and composed with another table by reading one through the other.
    typedef struct
    {
        unsigned int index_bits;
        unsigned int out_bits;
        const unsigned int *values;
    } EngineRecordTable;

    typedef struct
    {
        EngineRecordOperation operation;
        unsigned int left;
        unsigned int right;
        unsigned int bits;
        unsigned int member;
        unsigned long long constant;
    } EngineRecordTerm;

    typedef struct
    {
        unsigned int steps;
        unsigned int members;
        EngineRecordTerm *term;
        unsigned int outputs;
        unsigned int *output;
        unsigned int tables;
        EngineRecordTable *table;
        unsigned int *table_values;
        unsigned long long table_word_count;
    } EngineRecordKey;

    typedef struct
    {
        unsigned int operation;
        unsigned int left;
        unsigned int right;
        unsigned int limbs;
        unsigned int place;
        unsigned int left_limbs;
        unsigned int right_limbs;
        unsigned int out_offset;
        unsigned int out_bits;
        unsigned int member;
        unsigned int table_offset;
        unsigned int index_bits;
        unsigned int wrap_bits;
    } DeviceRecordStep;

    typedef struct CycleRecord CycleRecord;

    typedef struct
    {
        unsigned int steps;
        unsigned int members;
        unsigned int file_limbs;
        unsigned int in_limbs[ENGINE_RECORD_MEMBERS_MAX];
        unsigned int out_bits;
        unsigned int out_limbs;
        DeviceRecordStep *step_table;
        unsigned int *table_values;
        unsigned long long table_word_count;
    } EngineRecordLayout;

#ifdef __cplusplus
}
#endif

#endif
