// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// What the omega_computer_*.cu pieces share: its includes, types and the functions one piece calls in another
#ifndef OMEGA_COMPUTER_INTERNAL_H
#define OMEGA_COMPUTER_INTERNAL_H

// The omega computer: Omega inside Omega inside Omega (Doug, 24 September: "Omega omega omega", the nesting chosen,
// and "build the omega computer"). The machine is Tromp's binary lambda calculus run on the empty input. It reads a
// closed term M, self-delimited in de Bruijn form (00 M is lambda M, 01 M N is M applied to N, 1^k 0 is the variable
// bound k lambdas out), applies it to the empty list, and halts where M nil has a normal form. Omega_nil, the sum of
// 2^-|M| over the M that halt, is bracketed between two exact dyadics, as chaitin_omega brackets its Omega.
// Tromp's universal machine U is itself such a term, of 190 bits (J. Tromp, the AIT repository, ait/uni.lam, with the
// improvements by 50_ft_lock and Sean Palmer; the bits are those of Tromp's `blc blc`, whose size optimizer was
// reproduced to read them off). uni.lam, read 26 September 2026, gives uni's text and its size, 190 bits, and not its
// bits: no translation of that text that only inlines its lets or lays them out as redexes comes to fewer than 209
// bits, since the optimizer also reduces. The bits here are checked by Tromp's test below and not against a published
// string. Given the bits of a closed M and then the rest of its input, U reduces to M applied to
// the rest. A machine made of the machine is therefore U reading code(M), and the nesting d deep is U reading d - 1
// copies of its own code and then code(M):
//   depth 0: M nil,  depth d: U (code(U)^(d-1) code(M) nil).
// Every depth is beta-equal to M nil. By Church and Rosser each has M nil's normal form or none: one Omega, run d
// machines deep. The nested runs go to a lazy machine (call by need, and read back under every lambda and into every
// argument of a variable. It reaches a normal form wherever one exists); the direct run goes to it and to the
// rewriting of chaitin_omega, which must agree.
// 1. U is 190 bits and closed, and Tromp's own test holds at every depth: U reading delimit (326 bits, ait/delimit.lam)
//    and then 1111000111001 gives the list 11010.
// 2. The direct run: every closed M through L bits run on nil by normal order rewriting, with Brent's watcher and the
//    growth proof of chaitin_omega deciding the runs that never halt. The lazy machine gives the rewriting's normal
//    form wherever both halt, and no run of either halts where the other proves it never does.
// 3. At every depth, every M whose nested run halts has the direct run's normal form, token for token, and none halts
//    where a run at any depth proves it never does.
// 4. Each depth's bracket holds the one outside it: every M the inner machine finishes, the outer machine finished, and
//    the non-halts, proven at any depth, hold at every depth by Church and Rosser.
// Measured: each depth's bracket and the bits of Omega_nil it proves, and the steps each depth takes against the one
// outside it.

#include "sim.h"

#include <string>
#include <vector>

// the longest program read when the request names none, and the most it may name
#define OMEGA_COMPUTER_LENGTH_DEFAULT 20u

#define OMEGA_COMPUTER_LENGTH_MAX 40u

// the machines deep when the request names none, and the most it may name
#define OMEGA_COMPUTER_DEPTH_DEFAULT 3u

#define OMEGA_COMPUTER_DEPTH_MAX 8u

// the rewriting's budgets a run, chaitin_omega's defaults
#define OMEGA_COMPUTER_REWRITE_STEPS 2048u

#define OMEGA_COMPUTER_REWRITE_TOKENS 2048u

// the lazy machine's beta steps a run when the request names none
#define OMEGA_COMPUTER_STEPS_DEFAULT (1ull << 25u)

// the lazy machine's beta steps a run for a program the rewriting proves never halts: by Church and Rosser it halts at
// no depth, and the run only checks that it does not
#define OMEGA_COMPUTER_NEVER_STEPS (1ull << 16u)

// the lazy machine's cells a run: thunks, environment cells and spine cells together
#define OMEGA_COMPUTER_CELLS_MAX (1ull << 27u)

// the most tokens a normal form is read back to
#define OMEGA_COMPUTER_TOKENS_MAX 65536u

// tokens of a term in the order its code is read: a lambda, an application, or a variable's index from 1
#define OMEGA_COMPUTER_LAMBDA 0

#define OMEGA_COMPUTER_APPLY (-1)

// the lazy machine's term nodes
#define OMEGA_COMPUTER_NODE_VARIABLE 0

#define OMEGA_COMPUTER_NODE_LAMBDA 1

#define OMEGA_COMPUTER_NODE_APPLY 2

// a thunk's states: its term not yet evaluated, entered and under evaluation, or holding its value
#define OMEGA_COMPUTER_UNEVALUATED 0

#define OMEGA_COMPUTER_ENTERED 1

#define OMEGA_COMPUTER_EVALUATED 2

typedef enum
{
    OMEGA_COMPUTER_HALTS = 0,
    OMEGA_COMPUTER_LOOPS = 1,
    OMEGA_COMPUTER_OPEN = 2,
    OMEGA_COMPUTER_GREW = 3,
    OMEGA_COMPUTER_DIVERGES = 4
} OmegaComputerFate;

typedef struct
{
    int kind;
    // the body, the function, or the variable's index from 1
    int left;
    // the argument
    int right;
} OmegaComputerNode;

typedef struct
{
    int term;
    // the environment's first cell, -1 where empty
    int environment;
    int state;
    // 1 where the value is a variable applied to a spine, 0 where it is a lambda
    int neutral;
    // the lambda's node, or the variable's level
    int value;
    // the lambda's environment, or the spine's last cell
    int value_cells;
} OmegaComputerThunk;

// a cell of an environment or a spine: a thunk and the next cell, -1 at the end
typedef struct
{
    int thunk;
    int next;
} OmegaComputerCell;

typedef struct
{
    int thunk;
    int depth;
} OmegaComputerWork;

typedef struct
{
    std::vector<OmegaComputerNode> nodes;
    size_t fixed_nodes;
    int variable_node;
    int true_node;
    int false_node;
    int universal_node;
    std::vector<OmegaComputerThunk> thunks;
    std::vector<OmegaComputerCell> environments;
    std::vector<OmegaComputerCell> spines;
    std::vector<int> stack;
    std::vector<OmegaComputerWork> work;
    std::vector<int> arguments;
    unsigned long long steps;
    unsigned long long step_budget;
} OmegaComputerMachine;

typedef struct
{
    unsigned long long count[OMEGA_COMPUTER_LENGTH_MAX + 1u][OMEGA_COMPUTER_LENGTH_MAX + 2u];
} OmegaComputerCounts;

unsigned long long omega_computer_count(const OmegaComputerCounts *counts, unsigned int length, unsigned int depth);

void omega_computer_count_all(OmegaComputerCounts *counts, unsigned int maximum);

void omega_computer_unrank(const OmegaComputerCounts *counts, unsigned int length, unsigned int depth,
                           unsigned long long index, std::vector<int> &term);

int omega_computer_parse(const std::string &code, size_t *at, int depth, std::vector<int> &term);

std::string omega_computer_code(const std::vector<int> &term);

void omega_computer_list_tokens(const std::string &bits, std::vector<int> &term);

int omega_computer_step(const std::vector<int> &term, std::vector<int> &next);

unsigned int omega_computer_spine(const std::vector<int> &term, std::vector<size_t> &ends);

#define OMEGA_COMPUTER_NOT_HEAD 0xFFFFFFFFu

unsigned int omega_computer_head_redex(const std::vector<int> &term);

int omega_computer_grows_forever(const std::vector<int> &stored, const std::vector<size_t> &stored_ends,
                                 unsigned int stored_range, const std::vector<int> &term, unsigned int least,
                                 std::vector<size_t> &ends);

extern size_t g_omega_computer_peak;

OmegaComputerFate omega_computer_rewrite(std::vector<int> &term, unsigned int steps, unsigned int tokens,
                                         unsigned long long *taken);

void omega_computer_machine_open(OmegaComputerMachine *machine, const std::vector<int> &universal);

OmegaComputerFate omega_computer_run(OmegaComputerMachine *machine, const std::vector<int> &program,
                                     const std::string &input, unsigned int depth, const std::string &universal_code,
                                     std::vector<int> &normal);

#endif
