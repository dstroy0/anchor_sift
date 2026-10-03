// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the exponential_integral_*.cu pieces share: the span a value is held in, the three series, and where their sums
// come from
#ifndef EXPONENTIAL_INTEGRAL_INTERNAL_H
#define EXPONENTIAL_INTEGRAL_INTERNAL_H

#include "exponential_integral.h"

#include "../../../../../c/engine/analysis/cycle/cycle.h"
#include "../../../../../c/engine/analysis/key_schedule/key_schedule.h"
#include "../../../../../c/engine/analysis/keymath/keymath.h"

#include <vector>

typedef AnchorExactInteger ExponentialWide;

// a value v held as low <= v 2^W <= high
typedef struct
{
    ExponentialWide low;
    ExponentialWide high;
} ExponentialSpan;

// One series summed at 2^W, x = top / bottom, and the last term it took. Every term is a chain from 2^W: a first
// step times first_top / first_bottom, then step j for j = 1 .. k times multiplier / (base + rise j), and last a
// division by (end + end_rise k), each step floored for the low end and ceiled for the high. The host takes the steps in
// order and the engine takes each term as a lane of its own, and both give the same integers.
// - e^x: first 1/1, steps x / j (multiplier top, base 0, rise bottom), end 1. Terms 0 .. N, the tail past N at most
//   term N top / ((N + 1) bottom - top), added to the high end.
// - S(x): the same steps, end k. Terms 1 .. N + 1, odd terms added and even ones taken away.
// - artanh(c / d): first c / d, steps c^2 / d^2, end 2k + 1. Terms 0 .. N, the tail past N at most
//   term N c^2 / ((2N + 3) (d^2 - c^2)).
typedef struct
{
    ExponentialSpan (*rising)(const ExponentialWide &top, const ExponentialWide &bottom, unsigned int scale);
    ExponentialSpan (*alternating)(const ExponentialWide &top, const ExponentialWide &bottom, unsigned int scale);
    ExponentialSpan (*artanh)(const ExponentialWide &top, const ExponentialWide &bottom, unsigned int scale);
    // 1 where every sum this source gave is whole; the engine's is 0 once a program failed to build or run, or a lane's
    // record on the device differs from the host's
    int (*whole)(void);
} ExponentialSource;

extern const ExponentialSource g_exponential_host;

extern const ExponentialSource g_exponential_engine;

// an engine reading's verdict: a program did not build or run, or the device and the host gave different records or
// sums
#define EXPONENTIAL_INTEGRAL_ENGINE 3

// the function a reading brackets
enum
{
    EXPONENTIAL_READ_INTEGRAL = 0,
    EXPONENTIAL_READ_SERIES = 1,
    EXPONENTIAL_READ_NEGATIVE = 2,
    EXPONENTIAL_READ_LOGARITHM = 3,
    EXPONENTIAL_READ_GAMMA = 4
};

int exponential_read_from(const ExponentialSource *source, unsigned int read, const SimRational *x, unsigned int bits,
                          ExponentialIntegralBracket *bracket);

ExponentialWide exponential_unsigned(unsigned long long number);

ExponentialWide exponential_power_two(unsigned int bits);

ExponentialWide exponential_sum(const ExponentialWide &left, const ExponentialWide &right);

ExponentialWide exponential_difference(const ExponentialWide &left, const ExponentialWide &right);

ExponentialWide exponential_product(const ExponentialWide &left, const ExponentialWide &right);

int exponential_compare(const ExponentialWide &left, const ExponentialWide &right);

// floor and ceil of numerator / divisor for a positive divisor and a numerator of either sign
ExponentialWide exponential_floor(const ExponentialWide &numerator, const ExponentialWide &divisor);

ExponentialWide exponential_ceiling(const ExponentialWide &numerator, const ExponentialWide &divisor);

// top / bottom at 2^W, and 1 / v at 2^W for a span v > 0
ExponentialSpan exponential_scaled(const ExponentialWide &top, const ExponentialWide &bottom, unsigned int scale);

ExponentialSpan exponential_turned(const ExponentialSpan &value, unsigned int scale);

// ln(top / bottom) at 2^W for whole top, bottom >= 1
ExponentialSpan exponential_logarithm(const ExponentialSource *source, const ExponentialWide &top,
                                      const ExponentialWide &bottom, unsigned int scale);

// whether an operation since the last clear outgrew the build's exact width
void exponential_short_clear(void);

int exponential_short(void);

// the host's own sums, and the last term each took
ExponentialSpan exponential_rising_host(const ExponentialWide &top, const ExponentialWide &bottom, unsigned int scale,
                                        unsigned long long *last);

ExponentialSpan exponential_alternating_host(const ExponentialWide &top, const ExponentialWide &bottom,
                                             unsigned int scale, unsigned long long *last);

ExponentialSpan exponential_artanh_host(const ExponentialWide &top, const ExponentialWide &bottom, unsigned int scale,
                                        unsigned long long *last);

// the bytes the engine's programs for a reading at `bits` take on the device, at most
unsigned long long exponential_engine_bytes(const SimRational *x, unsigned int bits);

// what the engine's runs since the last reset did: programs built, lanes run, and the lanes whose device record was
// the host's word for word
typedef struct
{
    unsigned long long programs;
    unsigned long long lanes;
    unsigned long long same;
    unsigned long long sums_same;
    unsigned long long sums;
    unsigned long long steps;
} ExponentialEngineCount;

void exponential_engine_reset(void);

ExponentialEngineCount exponential_engine_counted(void);

#endif
