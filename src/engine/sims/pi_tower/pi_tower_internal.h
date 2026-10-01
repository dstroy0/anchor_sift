// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the pi_tower_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef PI_TOWER_INTERNAL_H
#define PI_TOWER_INTERNAL_H

// Pi turning at the boundary, and the tower it builds.
// The boundary is the circle of length 1 and the turn is x -> x + pi, which on the circle is the rotation by
// alpha = pi - 3. The turn never closes. It never lands where it has been. Its returns near the start are its
// floors: the return map to the arc under a close return is again a rotation, by the Gauss map's angle, and the
// counts of turns on each floor are pi's partial quotients [3; 7, 15, 1, 292, ...] (H. Weyl, 1916; V. T. Sos, 1958,
// the three gap theorem; T. van Ravenstein, "The three gap theorem (Steinhaus conjecture)", J. Austral. Math. Soc. A
// 45, 1988). Cut the boundary into N = 2^k cells: the turn fills every cell at an exact step, and that step and the
// cell it fills are read here from the floors, without walking the turn.
// Everything is exact. pi is bracketed by Machin's formula in integers, and the turn is held as the integer rotation
// y_n = n A mod 2^P, A = floor(alpha 2^P). A first hit, the least n with y_n in a window, is Euclid's descent through
// the floors. Whether the integer turn is the real one, cell for cell, is itself a first hit, and is checked.
// 1. pi is bracketed: floor(pi 2^P) is one integer at both ends of Machin's bracket, and its first 64 bits after the
//    point are the published 0x243F6A8885A308D3.
// 2. The floors: pi's partial quotients, certified by the bracket, begin 7, 15, 1, 292, ... as published.
// 3. The turn's closest returns are the floors: the steps at which the turn comes nearer its start than ever before
//    are exactly the convergents' denominators q_j, every one up to 2^PI_TOWER_RECORD_BITS.
// 4. The integer turn is the real turn: at every resolution no step up to the one searched lands in a cell other
//    than the real one.
// 5. The step that fills the boundary, read from the floors, equals a walk of every step, at 2^1 to 2^PI_TOWER_WALK_MAX
//    cells, and so does the last cell filled.
// 6. At every resolution asked for, the last cell filled is first touched at that step.
// The resolutions come with the request: pi_tower [n] reads 2^n alone, pi_tower [from] [to] reads 2^from to 2^to, and
// no argument reads 2^1 to 2^100.
// The precision follows the largest, P = 3 n + 64 bits rounded up to a word and at least PI_TOWER_BITS, and a build
// whose exact width cannot hold 3 (P + PI_TOWER_GUARD) + 64 bits errors on it by name (SIM_EXACT_LIMBS sets the width).
// The arc. Roll the boundary into a cylinder whose cross-section is our disk: the turn is the helix of radius 1 / (2
// pi) rising 1 / pi a turn, and it pierces our disk at the marks {n pi}. Its bending plane stands at the angle
// phi = arctan(1 / pi) to our disk, and the ratio of its torsion to its curvature is tan phi (Lancret, 1806).
// 7. In Q(pi), where pi is a free variable because it is transcendental (Lindemann, 1882), the helix's Frenet frame
//    taken from its derivatives at the four quarter turns gives curvature 2 pi^3 / (pi^2 + 1), torsion
//    2 pi^2 / (pi^2 + 1), tau / kappa = 1 / pi = tan phi, and a Darboux vector tau T + kappa B along our disk's axis.
// 8. The same numbers from the bracket: kappa, tau and phi in degrees, each printed only where both ends agree.
// The balance and the boundary.
// 9. On the helix the pull points at our axis. The torque about it is zero, and the angular momentum about it at
//    unit speed is L_z^2 = 1 / (4 (pi^2 + 1)) at all four quarter turns, in Q(pi); L_z from the bracket to 12 places.
// 10. The billiard in the unit square from the corner at slope pi, unfolded: the segment in lattice cell (i, j) carries
//    L = (-1)^(i + j) ((j + 1/2) - pi (i + 1/2)) about the square's center, with p = (1, pi). L = 0 would need
//    pi = (2j + 1) / (2i + 1), and a corner would need pi (i + 1) whole: each tie is pi rational. Walked from the
//    integer turn over 2^PI_TOWER_BILLIARD_BITS columns, every floor decided with the turn's certainty: no wall hit is
//    a corner, no segment's L is zero, and the walk's record near-corners are exactly the q_j. Measured: how often the
//    lead changes hands, the longest lead, each side's share, and the nearest tie.
// 11. The residue: on every floor with q_j to 2^PI_TOWER_RESIDUE_BITS, pi's first q_j steps have the whole parts of the
//    permutation n -> n p_j mod q_j, and at step q_j pi stands delta_j = q_j pi - (3 q_j + p_j) off the whole.
// 12. The golden helix: the residues flip sign every floor, q_j >= F_(j+1), |delta_j| < 1 / q_(j+1), and the shrink
//    |delta_j| / |delta_(j-1)| is above 1/2 exactly where a_(j+1) = 1. Measured: each shrink against the golden 1/phi,
//    and the growth a floor q_J^(1/J) against phi.
// The tower's deepest turns, on the engine. The turn at depth n is bit n of alpha, pi's fraction, and the BBP
// formula (D. H. Bailey, P. B. Borwein and S. Plouffe, Math. Comp. 66, 1997) reads it where it stands, without the bits
// before it: {16^d pi} = {4 S_1 - 2 S_4 - S_5 - S_6}, S_j = sum over i of 16^(d - i) / (8 i + j). Each term is a lane
// of the engine's record machine, its power shrunk mod 8 i + j at every square; keymath sizes every register, the
// scheduler lays them out, and tessera admits the job.
// 13. On the engine, pi's first 64 bits after the point are 0x243F6A8885A308D3, and its hex digits at Bailey's
//     published positions are his.
// 14. The engine's cell at the deepest resolution asked for, its low 64 bits, is the exact turn's.
// A resolution past 2^20, n given whole or as base^exponent (10^100 for a googol), is held as (2, n): its precision
// and widths are printed exact, and the engine sums the depth-n terms sweep by sweep, printing the terms done and its
// rate. Its digits are printed only once every term is summed.
// 15. A segment: pi_tower segment d [digits], d whole or base^exponent, reads that many hex digits from position d + 1
//     as windows at d, d + 20, d + 40, ..., each its own run on the engine. Every window certifies at least 24 digits,
//     the 4 or more it certifies past the 20 it gives are the next window's first (D. H. Bailey, "The BBP Algorithm
//     for Pi", 2006: a result at position d is checked by repeating it at d - 1 or d + 1), and where the segment starts
//     at one of Bailey's published positions its head is his.

#include "sim.h"

#include "cycle.h"
#include "key_schedule.h"
#include "keymath.h"

#include <chrono>
#include <csignal>
#include <string>
#include <vector>

// the walks' turn's precision, in bits after the point, and the least precision of the searched turn
#define PI_TOWER_BITS 384u

// the guard bits Machin's bracket is taken at past the turn's precision
#define PI_TOWER_GUARD 32u

// the resolutions read when the request names none
#define PI_TOWER_RESOLUTION_FIRST 1u

#define PI_TOWER_RESOLUTION_LAST 100u

#define PI_TOWER_WALK_MAX 24u

// the floor table and the closest-return check reach 2^PI_TOWER_RECORD_BITS steps
#define PI_TOWER_RECORD_BITS 112u

// the searched turn's records reach PI_TOWER_RECORD_MARGIN bits past the largest resolution
#define PI_TOWER_RECORD_MARGIN 12u

// the residue check walks every floor whose q_j is at most 2^PI_TOWER_RESIDUE_BITS
#define PI_TOWER_RESIDUE_BITS 21u

#define PI_TOWER_WORDS (PI_TOWER_BITS / 64u)

// the first 64 bits of pi after the point
#define PI_TOWER_PUBLISHED_BITS 0x243F6A8885A308D3ull

#define PI_TOWER_PUBLISHED_FLOORS 21u

// the billiard is walked over 2^PI_TOWER_BILLIARD_BITS columns of its unfolded lattice
#define PI_TOWER_BILLIARD_BITS 24u

// the bits after the point the engine's sum holds past its error, and the guard past them that keeps a carry from
// leaving them undecided
#define PI_TOWER_BBP_CERTIFIED 96u

#define PI_TOWER_BBP_GUARD 16u

// a segment takes this many hex digits from each window, 4 fewer than the least a window must certify: the 4 or more
// past them are checked against the next window's first
#define PI_TOWER_SEGMENT_STEP ((PI_TOWER_BBP_CERTIFIED / 4u) - 4u)

// the hex digits a segment reads when the request names none, and the most it may name
#define PI_TOWER_SEGMENT_DIGITS 1000u

#define PI_TOWER_SEGMENT_MAX 65536u

// the deepest resolution the exact turn is held at; past it a resolution is read on the engine alone
#define PI_TOWER_EXACT_MAX (1ull << 20u)

extern int g_pi_tower_error;

extern int g_pi_tower_records_short;

typedef AnchorExactInteger PiWide;

// one level of the descent: the rotation a on m, and the window's low end
typedef struct
{
    PiWide multiplier;
    PiWide modulus;
    PiWide low;
} PiTowerLevel;

// a step at which the turn sets a record, and where it stands then
typedef struct
{
    PiWide step;
    PiWide place;
} PiTowerRecord;

// the searched turn: A = floor(alpha 2^precision) on 2^precision, its records to 2^range steps
typedef struct
{
    PiWide multiplier;
    PiWide modulus;
    unsigned int precision;
    unsigned int range;
    std::vector<PiTowerRecord> lowest;
    std::vector<PiTowerRecord> highest;
} PiTowerTurn;

PiWide pi_tower_unsigned(unsigned long long number);

PiWide pi_tower_power_two(unsigned int bits);

PiWide pi_tower_sum(const PiWide &left, const PiWide &right);

PiWide pi_tower_difference(const PiWide &left, const PiWide &right);

PiWide pi_tower_product(const PiWide &left, const PiWide &right);

PiWide pi_tower_quotient(const PiWide &numerator, const PiWide &divisor);

PiWide pi_tower_remainder(const PiWide &numerator, const PiWide &divisor);

int pi_tower_compare(const PiWide &left, const PiWide &right);

unsigned long long pi_tower_word(const PiWide &value);

int pi_tower_first_hit(PiWide multiplier, PiWide modulus, PiWide low, PiWide high, PiWide *step);

int pi_tower_first_hit_from(const PiWide &multiplier, const PiWide &modulus, const PiWide &from, const PiWide &low,
                            const PiWide &high, PiWide *step);

int pi_tower_hit_between(const PiWide &multiplier, const PiWide &modulus, const PiWide &from, const PiWide &to,
                         const PiWide &low, const PiWide &high);

PiWide pi_tower_arctan(unsigned long long x, unsigned int bits, unsigned long long *terms);

std::vector<PiTowerRecord> pi_tower_records(const PiTowerTurn &turn, int lowest);

int pi_tower_covered(const PiTowerTurn &turn, const PiWide &cell, const PiWide &count);

void pi_tower_print_decimal(ScripturaLine *line, PiWide value);

void pi_tower_print_exponent(ScripturaLine *line, PiWide numerator, PiWide denominator);

int pi_tower_bracket(SimResults *results, unsigned int precision, PiWide *alpha, PiWide *low, PiWide *high);

void pi_tower_floors(SimResults *results, const PiTowerTurn &turn, std::vector<PiWide> *denominators,
                     std::vector<PiWide> *floors);

unsigned long long pi_tower_walk(const PiWide &alpha, unsigned int bits, unsigned long long *last,
                                 unsigned long long *stall, unsigned long long *again, unsigned long long *home,
                                 unsigned long long *closing);

// a polynomial in pi with integer coefficients, the coefficient of pi^i at i, with no zero at the top
typedef std::vector<PiWide> PiTowerPolynomial;

// a rational function of pi; pi is transcendental. Two are equal exactly where their cross products are equal as
// polynomials
typedef struct
{
    PiTowerPolynomial numerator;
    PiTowerPolynomial denominator;
} PiTowerFraction;

typedef struct
{
    PiTowerFraction axis[3];
} PiTowerVector;

PiWide pi_tower_root(const PiWide &value);

void pi_tower_arc(SimResults *results, const PiWide &low, const PiWide &high, unsigned int bits);

void pi_tower_billiard(SimResults *results, const PiWide &alpha, const std::vector<PiWide> &denominators);

void pi_tower_residues(SimResults *results, const PiWide &walk_alpha, const std::vector<PiWide> &denominators,
                       const std::vector<PiWide> &floors);

void pi_tower_golden(SimResults *results, const PiTowerTurn &turn, const std::vector<PiWide> &denominators,
                     const std::vector<PiWide> &floors);

// one record program on the engine: the key keymath encodes, the layout the scheduler lays out, and the record cycle
// loads
typedef struct
{
    EngineRecordKey key;
    EngineRecordLayout layout;
    CycleRecord *record;
} PiTowerProgram;

// pi's hex digits from position d + 1 on the engine. Term i <= d is a lane: 16^(d - i) mod 8 i + j by powering in base
// 16, each square taken mod 8 i + j, and that residue's fraction floored to W bits. Tail term d + t is a lane of its
// own, 2^W / ((8 (d + t) + j) 16^t) floored. The pair program adds two lanes' sums mod 2^W, and its rounds reduce a
// sweep to one. Every lane's sum is wrapped to W = 32 k - 1 bits. With its sign it fills k whole limbs.
typedef struct
{
    PiWide position;
    PiWide terms;
    unsigned int position_bits;
    unsigned int fraction_bits;
    unsigned int tail_terms;
    unsigned int tail_bits;
    unsigned int in_limbs;
    unsigned int out_limbs;
    unsigned long long lanes;
    PiTowerProgram term;
    PiTowerProgram tail;
    PiTowerProgram pair;
} PiTowerBbp;

// how far a run on the engine reached: the terms summed, the seconds it took, and where every term was summed, the sum
typedef struct
{
    unsigned long long done;
    unsigned long long sweeps;
    double seconds;
    int finished;
    PiWide sum;
} PiTowerBbpRun;

extern volatile sig_atomic_t g_pi_tower_stopped;

void pi_tower_stop(int signal_number);

unsigned int pi_tower_bit_length(const PiWide &value);

unsigned int pi_tower_step(std::vector<EngineRecordStep> *steps, EngineRecordOperation operation, unsigned int left,
                           unsigned int right);

unsigned int pi_tower_field(std::vector<EngineRecordStep> *steps, unsigned int field, unsigned int member);

unsigned int pi_tower_constant(std::vector<EngineRecordStep> *steps, const PiWide &value);

void pi_tower_bbp_combine(std::vector<EngineRecordStep> *steps, const unsigned int *fraction,
                          unsigned int fraction_bits);

void pi_tower_bbp_free(PiTowerBbp *bbp);

PiWide pi_tower_bbp_error(const PiTowerBbp *bbp);

int pi_tower_bbp_plan(PiTowerBbp *bbp, const PiWide &position, unsigned long long lanes, EngineError *error);

unsigned long long pi_tower_bbp_bytes(const PiTowerBbp *bbp);

int pi_tower_bbp_counted(SimResults *results, unsigned int *out, unsigned long long count, unsigned int limbs,
                         unsigned long long first);

unsigned int *pi_tower_bbp_reduce(SimResults *results, const PiTowerBbp *bbp, unsigned int *const *buffers,
                                  const unsigned int *index, unsigned long long count, EngineError *error);

int pi_tower_bbp_read(SimResults *results, const PiTowerBbp *bbp, const unsigned int *total, PiWide *sum);

void pi_tower_bbp_progress(SimResults *results, const PiTowerBbp *bbp, const PiTowerBbpRun *run);

int pi_tower_bbp_sum(SimResults *results, PiTowerBbp *bbp, int report, PiTowerBbpRun *run);

unsigned int pi_tower_bbp_certified(const PiTowerBbp *bbp, const PiWide &sum);

std::string pi_tower_bbp_hex(const PiTowerBbp *bbp, const PiWide &sum, unsigned int digits);

void pi_tower_bbp_print(SimResults *results, const PiTowerBbp *bbp, const PiTowerBbpRun *run, unsigned int certified);

unsigned long long pi_tower_bbp_lanes(void);

// Bailey's table of pi's hex digits, each at the position of its first digit (D. H. Bailey, "The BBP Algorithm for
// Pi", 2006, table 1), and the 23 digits his text gives from position 1,000,001
typedef struct
{
    unsigned long long position;
    const char *digits;
} PiTowerPublished;

static const PiTowerPublished s_pi_tower_published[] = {
    {1ull, "243F6A8885A308D3"},      {1000000ull, "26C65E52CB4593"},   {1000001ull, "6C65E52CB459350050E4BB1"},
    {10000000ull, "17AF5863EFED8D"}, {100000000ull, "ECB840E21926EC"},
};

#define PI_TOWER_PUBLISHED_COUNT (sizeof(s_pi_tower_published) / sizeof(s_pi_tower_published[0]))

PiWide pi_tower_depth_position(const PiWide &depth, unsigned int *window);

unsigned long long pi_tower_bbp_cell(const PiTowerBbp *bbp, const PiWide &sum, unsigned int window);

// how a segment went: whether every window ran, every window was summed, and every overlap agreed
typedef struct
{
    int ran;
    int finished;
    int certified;
    int overlapped;
    unsigned int windows;
} PiTowerSegment;

void pi_tower_segment_request(SimResults *results, int count, char **arguments, const PiWide &position,
                              unsigned int digits);

void pi_tower_engine(SimResults *results, int count, char **arguments, const PiTowerTurn &turn, unsigned int depth);

void pi_tower_deep(SimResults *results, int count, char **arguments, const PiWide &depth);

int pi_tower_request(const char *text, PiWide *value);

int pi_tower_resolution(const char *text, unsigned int *bits);

#endif
