// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// chaitin_omega_declarations.h: the first half of what chaitin_omega_*.cu's pieces share (chaitin_omega_internal.h
// includes it)
#ifndef CHAITIN_OMEGA_DECLARATIONS_H
#define CHAITIN_OMEGA_DECLARATIONS_H

//
// Chaitin's halting probability for Tromp's binary lambda calculus, bracketed exactly.
//
// The machine reads a closed lambda term from its input, self-delimited in de Bruijn form (00 M is
// lambda M, 01 M N is M applied to N, 1^k 0 is the variable bound k lambdas out), and halts where the
// term has a normal form. The codes are prefix free. Omega = sum of 2^-|t| over the halting terms
// is a probability. Its first n bits settle the halting of every program of n bits or fewer, and
// no machine therefore computes them all: Omega is approached from below and never reached.
//
// Every closed term of at most L bits is run by normal order reduction, which reaches a normal form
// whenever one exists. Reaching one proves the halt. A watcher holding a copy of the term at each
// power of two steps (Brent) sees every bit of it, and a term that comes back to a state it held
// is proven never to halt. Held to a bounded space, a term can only halt or repeat, since the space holds
// finitely many terms; so the runs are split by exit: halted, looped, out of steps (the space not yet
// searched), and outgrew the space, the one exit no bounded search closes. A grower is closed where it
// is proven to grow forever: a part of it returns at its own head (omega_grows_forever).
//
// The runs go to the device, one term to a thread, with the host running the few that pass the device's small
// budgets (omega_device); the host's own run of every term through 30 bits must give the same fates and busy
// beavers. Arguments: L, steps, tokens, and "cpu" to run every term on the host instead.
//
// The mass of the closed terms longer than L is bounded by counting, not running: the mass a(n) of
// every term code of n bits and the mass c(n, k) of those closed under k lambdas follow recurrences,
// summed in fixed point rounded toward the bound each side needs. Every code parses to its end with
// probability 1 (the parse is a subcritical branching process, and 1 is the smaller root of
// T^2 - 3T + 2 = 0). What the counted lengths leave of 1 bounds every longer length at once.
//
//   Omega >= the halted mass,
//   Omega <= the halted mass + the open mass + the closed mass past L,
//
// both exact dyadics, and each bit the two share is a bit of Omega.
#include "../../../../../c/engine/analysis/cycle/cycle.h"
#include "../../../../../c/engine/analysis/key_schedule/key_schedule.h"
#include "../../../../../c/engine/analysis/keymath/keymath.h"
#include "sim.h"

#include <cub/cub.cuh>

#include <atomic>
#include <chrono>
#include <map>
#include <thread>
#include <vector>

#define OMEGA_LENGTH_MAX 60u

#define OMEGA_LENGTH_DEFAULT 28u

#define OMEGA_STEPS_DEFAULT 2048u

#define OMEGA_TOKENS_DEFAULT 2048u

// the longest code whose mass the counting recurrences carry; every longer code is bounded by the parse's tail
#define OMEGA_COUNTED 1200u

// the brute-force parse checks the enumeration through this length
#define OMEGA_PARSED_MAX 22u

#define OMEGA_CHUNK 4096ull

// fixed point: 62 fraction bits. A mass of 1 and its sums fit a word
#define OMEGA_POINT 62u

#define OMEGA_ONE (1ull << OMEGA_POINT)

// tokens of a term in the order its code is read: a lambda, an application, or a variable's index from 1
#define OMEGA_LAMBDA 0

#define OMEGA_APPLY (-1)

typedef enum
{
    OMEGA_HALTS = 0,
    OMEGA_LOOPS = 1,
    OMEGA_OPEN = 2,
    OMEGA_GREW = 3,
    OMEGA_DIVERGES = 4,
    OMEGA_TYPED = 5
} OmegaFate;

typedef struct
{
    unsigned int length;
    unsigned int steps;
    unsigned int tokens;
    unsigned long long count[OMEGA_LENGTH_MAX + 1u][OMEGA_LENGTH_MAX + 2u];
} OmegaCounts;

// per length, the busy beavers among the halting terms: the most normal order steps to a normal form, and the
// largest normal form in bits (Tromp's BB lambda), each with the first term in rank order to reach it
typedef struct
{
    unsigned long long fate[6][OMEGA_LENGTH_MAX + 1u];
    unsigned long long contradictions;
    unsigned long long max_steps[OMEGA_LENGTH_MAX + 1u];
    unsigned long long steps_champion[OMEGA_LENGTH_MAX + 1u];
    unsigned long long max_bits[OMEGA_LENGTH_MAX + 1u];
    unsigned long long bits_champion[OMEGA_LENGTH_MAX + 1u];
} OmegaResults;

unsigned long long omega_count(const OmegaCounts *counts, unsigned int length, unsigned int depth);

void omega_count_all(OmegaCounts *counts);

void omega_unrank(const OmegaCounts *counts, unsigned int length, unsigned int depth, unsigned long long index,
                  std::vector<int> &term);

size_t omega_end(const int *term, size_t at);

unsigned long long omega_code_bits(const std::vector<int> &term);

void omega_code_text(ScripturaLine *line, const std::vector<int> &term);

// the spine position of the head redex, where the term is an application spine over a lambda; otherwise the
// step normal order takes is not a head step, and OMEGA_NOT_HEAD is returned
#define OMEGA_NOT_HEAD 0xFFFFFFFFu

OmegaFate omega_run(std::vector<int> &term, std::vector<int> &next, std::vector<int> &stored, unsigned int steps,
                    unsigned int tokens, unsigned int *taken);

int omega_parse(unsigned long long code, unsigned int length, unsigned int *at, unsigned int depth);

void omega_all_mass(std::vector<unsigned long long> &mass, int up);

void omega_closed_mass(const std::vector<unsigned long long> &all_up, std::vector<unsigned long long> &closed);

void omega_normal_mass(std::vector<unsigned long long> &normal_closed);

// Simple types by unification (Hindley): a type is a variable or an arrow, held in a union-find. Every simply
// typable term is strongly normalizing (Tait 1967). A type found is a certificate that the term halts, with
// no step run and no normal form written: it settles terms whose normal forms outgrow any space.
typedef struct
{
    std::vector<unsigned int> parent;
    std::vector<unsigned int> from;
    std::vector<unsigned int> to;
    std::vector<unsigned char> arrow;
    std::vector<unsigned int> bound;
} OmegaTypes;

void omega_results_open(OmegaResults *results);

void omega_champion(unsigned long long *maximum, unsigned long long *champion, unsigned long long value,
                    unsigned long long index);

void omega_settle(const OmegaCounts *counts, unsigned int length, unsigned long long index, OmegaFate fate,
                  unsigned int taken, std::vector<int> &term, OmegaResults *results);

void omega_merge(OmegaResults *into, const OmegaResults *one);

void omega_host(const OmegaCounts *counts, unsigned int maximum, unsigned int workers, OmegaResults *fates);

// The same run on the device, one term to a thread, steered: the device takes the bulk under small budgets and
// the host the few that need its large ones. Each thread unranks its term from the counts and reduces it in its
// own buffers, taking every decision the host's omega_run takes, in the same order; the recursive walks become
// scans with an explicit stack. A run is deterministic and its budgets only stop it. A halt, a loop or a
// growth proof reached inside the small budgets is reached at the same step inside the large ones. A halt is
// tallied on the device. Every other term is handed back by rank: a loop or growth proof with its fate, for the
// type certificate, and a run that hit a small budget or outgrew the device's room for the host to run itself
// under the full budgets. No fate rests on the device's limits.
#define OMEGA_BLOCK 128u

// threads resident on a multiprocessor: each thread's buffers are read through the cache, and past this many they
// crowd one another out of it (timings on an RTX 3070 at 38 bits, 256/256, that no kept log holds: 384 took 0.91 s,
// 512 1.01 s, 768 1.34 s)
#define OMEGA_THREADS_PER_SM 384u

// the device's budgets, where the full ones are larger
#define OMEGA_DEVICE_STEPS 256u

#define OMEGA_DEVICE_TOKENS 256u

// a handed back term's code for a run the host must make itself
#define OMEGA_HOST_RUNS 7u

// a stack frame of the scans: the children still to start in the low two bits, and whether it is a lambda
#define OMEGA_FRAME_LAMBDA 4u

#define OMEGA_STEP_NORMAL 0u

#define OMEGA_STEP_TAKEN 1u

#define OMEGA_STEP_OVERFLOW 2u

// the most terms one launch takes. An offset fits the 32 bits of a busy beaver key and 56 of a handed code
#define OMEGA_BATCH_MAX (1ull << 24u)

// the device's fates are checked against the host's through this length
#define OMEGA_CROSS_MAX 30u

typedef struct
{
    unsigned long long next;
    unsigned long long halts;
    unsigned long long handed;
    // most steps and largest normal form, each the value over (2^32 - 1 - offset). The largest key is the
    // largest value at the lowest rank, and 0 is none
    unsigned long long steps_key;
    unsigned long long bits_key;
} OmegaBatch;

typedef struct
{
    short *term;
    short *next;
    short *stored;
    unsigned short *ends;
    unsigned short *stored_ends;
    unsigned char *stack;
} OmegaBuffers;

#include "chaitin_omega_device_terms.h"

typedef struct
{
    unsigned int steps;
    unsigned int tokens;
    unsigned int length;
    unsigned long long from;
    unsigned long long count;
    OmegaResults results;
} OmegaLedgerJob;

int omega_device(SimResults *results, const OmegaCounts *counts, unsigned int workers, const char *ledger,
                 unsigned int *threads_used, unsigned long long *host_runs, unsigned long long *jobs_run,
                 unsigned long long *jobs_kept, OmegaResults *fates);

// The run by the engine: every normal order step of every live term is one sweep of the engine's record machine,
// and nothing bounds it but the machine. A term is as many records as it has tokens. It grows by adding records
// and no register or field holds a whole term. The live terms stay on the device from admission to their fate. Each
// round, a thread a term finds its leftmost redex and lays out where every token of the reduct comes from: the
// prefix and the suffix copied, the body's tokens with the depth they sit at, and a copy of the argument for each
// variable the redex's lambda binds, with the depth it is put under and the lambdas above each of its tokens. The
// record machine gathers each source token through its index list and computes the reduct's token: a body variable
// bound past the redex moves in by one, an argument's variable bound outside it moves out by the depth, and the
// rest are copied. The record program is encoded for the widths the round's values need. No width is set
// anywhere. A thread a term then takes the same decisions as omega_run, in the same order: a normal form halts,
// Brent's watcher proves a loop, and omega_grows_forever's proof is made on the new term. Only a settled term
// leaves the device, as one record. There is no step budget and no token budget: a term runs until one of those
// settles it. A term the device's memory cannot hold for its next round is parked as outgrown, the only
// exit left open, and a stop leaves every live term open. The run is one tessera job.

// a job: one length's terms from `from`, at most this many, admitted to the live pool as the pool drains
#define OMEGA_ENGINE_JOB (1ull << 22u)

// the pool takes the next job once fewer terms than this are live
#define OMEGA_ENGINE_REFILL (1ull << 21u)

// a sweep of the record machine is at most this many lanes; the lane's plan index restarts at each sweep
#define OMEGA_ENGINE_SWEEP (1ull << 26u)

#endif
