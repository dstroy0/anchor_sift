// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the record_boundary_test_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef RECORD_BOUNDARY_TEST_INTERNAL_H
#define RECORD_BOUNDARY_TEST_INTERNAL_H

//
// The crystal as a boundary, measured on itself. A 5/3 lifting tower T of four levels over 64 samples runs as record
// floors. Its crystal (the level-4 lows and every high, in Mallat order) is the boundary between the tower and its
// inverse, and everything here is read there, not from either end.
//
// Written onto the boundary and read back: arbitrary crystals run through T^-1 then T return exactly. The boundary
// is a whole coordinate chart of Z^n. The precision the boundary reads: a flip of input bit b moves a crystal
// coefficient only at bit b - 3L and above, and for b >= 3L the move is exactly 2^b times a column of T's rational
// matrix M, whose 2-adic valuations give the range per band (3l for the lows at level l, 3l - 2 for its highs). T^-1
// is held to the range L + 2 the same way. What passes through T: a constant added to every sample lands on the
// crystal's lows alone, and a vector in 2^(3L) Z^n lands as M times it; negation and doubling do not pass. The
// identity of a lane's structure, taken with T and null permutations of its own samples: every structured lane's
// crystal heap stands below all its shuffles', and noise no more often than 1 / (draws + 1) allows. The heap
// and the ring at every floor of T then T^-1: the heap mirrors exactly, the ring is ring_0 + n + 2(n - n / 2^l) at
// floor l >= 1 (keymath's linear forms give every register at level l, low and high, w + l + 1 bits) and its mirror
// one bit wider per wrapped low, and the heap's pinch at the crystal orders a ramp, a ramp +-8, a
// ramp +-1024 and noise. Last, the top projection x -> x / 2^k toward zero, the other end of the window from the
// 2-adic projection: nested quotients commute with it, it never reverses a comparison (the 8-bit wrap reverses
// many), and a sum through it is off by at most one. The count each crystal keeps: on a 4-sample tower every input
// quantum at level w + 3 is run, and T and T^-1 send exactly as many onto every output quantum at level w (Haar
// measure on Z_2^n); det M and det M^-1 are +-1 exactly, proved modulo primes past Hadamard's bound (volume on R^n).
// T holds no error correction. A redundant residue code carries the crystal: each coefficient modulo four odd
// primes where two cover its range, decoded in the machine, catches two corrupted residues and corrects one, and T^-1
// of the corrected crystal returns the samples. Every program runs on the device and the host, word for word. The test
// is one job on the device's tessera daemon, submitted before its first device work.
#include "../../../../../../../src/c/engine/analysis/cycle/cycle.h"
#include "../../../../../../../src/c/engine/analysis/key_schedule/key_schedule.h"
#include "../../../../../../../src/c/engine/analysis/keymath/keymath.h"
#include "../../../../../../../src/c/engine/runtime/scriptura/scriptura.h"
#include "sim.h"

#include <cuda_runtime.h>

#include <math.h>
#include <stdlib.h>
#include <string.h>

#define BOUNDARY_TEST_LINE 16384ull

#define BOUNDARY_TEST_SAMPLES 64u

#define BOUNDARY_TEST_LEVELS 4u

#define BOUNDARY_TEST_FIELD_BITS 24u

// T's precision bound in bits: three per level, from the floor shift by 1 a high reads through and the shift by 2 a
// low reads through after it
#define BOUNDARY_TEST_RANGE (3u * BOUNDARY_TEST_LEVELS)

// T^-1's bound: one bit per level a low passes back through, and three at a high's own level
#define BOUNDARY_TEST_INVERSE_RANGE (BOUNDARY_TEST_LEVELS + 2u)

#define BOUNDARY_TEST_FLOORS ((2u * BOUNDARY_TEST_LEVELS) + 1u)

#define BOUNDARY_TEST_STEPS 2560u

#define BOUNDARY_TEST_OUTPUTS 320u

#define BOUNDARY_TEST_PAIRS 8192u

#define BOUNDARY_TEST_CLASSES 4u

#define BOUNDARY_TEST_CLASS_LANES 1024u

#define BOUNDARY_TEST_TOP_LANES 65536u

#define BOUNDARY_TEST_TOP_SETTINGS 3u

// the highest bit a precision pair flips, below the field's sign bit so the flip moves the value by exactly 2^b
#define BOUNDARY_TEST_FLIP_TOP (BOUNDARY_TEST_FIELD_BITS - 2u)

// the tower counted whole: 4 samples and one level, whose range each way is 3 bits
#define BOUNDARY_TEST_COUNT_SAMPLES 4u

#define BOUNDARY_TEST_COUNT_RANGE 3u

// the most the test puts on the device at once: the counted tower's 2^20 lanes at w = 2, under 8 words a lane
#define BOUNDARY_TEST_DECLARED                                                                                         \
    ((1ull << (BOUNDARY_TEST_COUNT_SAMPLES * (2u + BOUNDARY_TEST_COUNT_RANGE))) * 8ull * sizeof(unsigned int))

// the identity by null permutation: lanes drawn for each class, and the keyed shuffles drawn of each
#define BOUNDARY_TEST_IDENTITY_BASES 256u

#define BOUNDARY_TEST_IDENTITY_DRAWS 8u

typedef struct
{
    unsigned long long checks;
    unsigned long long failures;
    ScripturaLine line;
} BoundaryResults;

typedef struct
{
    EngineRecordStep steps[BOUNDARY_TEST_STEPS];
    unsigned int count;
    int overflow;
    unsigned int outputs[BOUNDARY_TEST_OUTPUTS];
    unsigned int output_count;
} BoundaryProgram;

// a tower's registers: low[l] the band at level l (low[0] the samples), and the crystal in Mallat order, the level-L
// lows first, then the highs of levels L, L - 1, ..., 1, the highs of level l at [n / 2^l, n / 2^(l - 1))
typedef struct
{
    unsigned int low[BOUNDARY_TEST_LEVELS + 1u][BOUNDARY_TEST_SAMPLES];
    unsigned int crystal[BOUNDARY_TEST_SAMPLES];
} BoundaryTower;

typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
    EngineError error;
} BoundaryLoaded;

// the host's own T or T^-1 over n values
typedef void (*BoundaryMap)(const long long *in, long long *out);

extern long long g_boundary_forward_matrix[BOUNDARY_TEST_SAMPLES][BOUNDARY_TEST_SAMPLES];

extern long long g_boundary_inverse_matrix[BOUNDARY_TEST_SAMPLES][BOUNDARY_TEST_SAMPLES];

unsigned int boundary_random(void);

void boundary_check(BoundaryResults *results, int passed, const char *what);

void boundary_hundredths(ScripturaLine *line, unsigned long long top, unsigned long long bottom);

unsigned int boundary_append(BoundaryProgram *program, EngineRecordOperation operation, unsigned int left,
                             unsigned int right);

void boundary_output(BoundaryProgram *program, unsigned int step);

void boundary_forward(BoundaryProgram *program, BoundaryTower *tower, unsigned int samples, unsigned int levels);

void boundary_inverse(BoundaryProgram *program, const unsigned int *crystal, const BoundaryTower *twin,
                      const EngineRecordKey *twin_key, BoundaryTower *back, unsigned int samples, unsigned int levels);

void boundary_host_forward(const long long *samples, long long *crystal);

void boundary_host_inverse(const long long *crystal, long long *samples);

void boundary_matrices(void);

int boundary_valuation(long long value);

int boundary_row_range(const long long (*matrix)[BOUNDARY_TEST_SAMPLES], unsigned int output);

int boundary_encode(const BoundaryProgram *program, unsigned int count, unsigned int fields, EngineRecordKey *key,
                    EngineError *error);

int boundary_load(const BoundaryProgram *program, unsigned int fields, BoundaryLoaded *loaded);

void boundary_free(BoundaryLoaded *loaded);

int boundary_run(BoundaryLoaded *loaded, const unsigned int *atoms, unsigned int count, unsigned int *host_out,
                 unsigned int *device_out);

unsigned int boundary_word(long long value);

long long boundary_field(unsigned int word);

long long boundary_read(const unsigned int *record, const DeviceRecordStep *step);

int boundary_narrow_enough(const BoundaryLoaded *loaded, const BoundaryProgram *program);

void boundary_precision(BoundaryResults *results, BoundaryLoaded *loaded, const BoundaryProgram *program,
                        BoundaryMap map, const long long (*matrix)[BOUNDARY_TEST_SAMPLES], unsigned int bound,
                        int readback, const char *name, int *range_seen);

void boundary_bands(BoundaryResults *results);

void boundary_written(BoundaryResults *results);

void boundary_read_off(BoundaryResults *results);

void boundary_class_fill(unsigned int *atom, unsigned int kind);

unsigned int boundary_heap(long long value);

void boundary_floors(BoundaryResults *results);

void boundary_top(BoundaryResults *results);

void boundary_counted(BoundaryResults *results);

unsigned long long boundary_prime_below(unsigned long long above);

void boundary_volume(BoundaryResults *results);

// the redundant residue code's moduli: odd primes in ascending order, the first two covering the crystal's legal range
// and the last two its redundancy
#define BOUNDARY_TEST_CODE_MODULI 4u

#define BOUNDARY_TEST_CODE_NEEDED 2u

// the legal range the code holds a crystal coefficient to, [-2^21, 2^21), carried shifted by 2^21 onto [0, 2^22)
#define BOUNDARY_TEST_CODE_BITS 22u

#define BOUNDARY_TEST_CODE_CRYSTALS 256u

// the decoder runs each crystal three ways: clean, one residue corrupted, two residues corrupted
#define BOUNDARY_TEST_CODE_KINDS 3u

// the samples are 16-bit signed, as a camera's are after its offset
#define BOUNDARY_TEST_CODE_SAMPLE_BITS 16u

static const unsigned int s_boundary_moduli[BOUNDARY_TEST_CODE_MODULI] = {2053u, 2063u, 2069u, 2081u};

unsigned int boundary_code_garner(BoundaryProgram *program, const unsigned int *residue, const unsigned int *chosen,
                                  unsigned int count);

unsigned int boundary_code_outside(BoundaryProgram *program, unsigned int value, unsigned int range, unsigned int zero);

#endif
