// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// The omega computer: Omega inside Omega inside Omega (Doug, 24 September: "Omega omega omega", the nesting chosen,
// and "build the omega computer"). The machine is Tromp's binary lambda calculus run on the empty input. It reads a
// closed term M, self-delimited in de Bruijn form (00 M is lambda M, 01 M N is M applied to N, 1^k 0 is the variable
// bound k lambdas out), applies it to the empty list, and halts where M nil has a normal form. Omega_nil, the sum of
// 2^-|M| over the M that halt, is bracketed between two exact dyadics, as chaitin_omega brackets its Omega.
// Tromp's universal machine U is itself such a term, of 190 bits (J. Tromp, the AIT repository, ait/uni.lam, with the
// improvements by 50_ft_lock and Sean Palmer; the bits are those of Tromp's `blc blc`, whose size optimizer was
// reproduced to read them off). Given the bits of a closed M and then the rest of its input, U reduces to M applied to
// the rest. So a machine made of the machine is U reading code(M), and the nesting d deep is U reading d - 1 copies of
// its own code and then code(M):
//   depth 0: M nil,  depth d: U (code(U)^(d-1) code(M) nil).
// Every depth is beta-equal to M nil, so by Church and Rosser each has M nil's normal form or none: one Omega, run d
// machines deep. The nested runs go to a lazy machine (call by need, and read back under every lambda and into every
// argument of a variable, so it reaches a normal form wherever one exists); the direct run goes to it and to the
// rewriting of chaitin_omega, which must agree.
// 1. U is 190 bits and closed, and Tromp's own test holds at every depth: U reading delimit (326 bits, ait/delimit.lam)
//    and then 1111000111001 gives the list 11010.
// 2. The direct run: every closed M through L bits run on nil by normal order rewriting, with Brent's watcher and the
//    growth proof of chaitin_omega deciding the runs that never halt. The lazy machine gives the rewriting's normal form
//    wherever both halt, and no run of either halts where the other proves it never does.
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

#define OMEGA_COMPUTER_LENGTH_MOST 40u

// the machines deep when the request names none, and the most it may name
#define OMEGA_COMPUTER_DEPTH_DEFAULT 3u

#define OMEGA_COMPUTER_DEPTH_MOST 8u

// the rewriting's budgets a run, chaitin_omega's defaults
#define OMEGA_COMPUTER_REWRITE_STEPS 2048u

#define OMEGA_COMPUTER_REWRITE_TOKENS 2048u

// the lazy machine's beta steps a run when the request names none
#define OMEGA_COMPUTER_STEPS_DEFAULT (1ull << 25u)

// the lazy machine's beta steps a run for a program the rewriting proves never halts: by Church and Rosser it halts at
// no depth, and the run only checks that it does not
#define OMEGA_COMPUTER_NEVER_STEPS (1ull << 16u)

// the lazy machine's cells a run: thunks, environment cells and spine cells together
#define OMEGA_COMPUTER_CELLS_MOST (1ull << 27u)

// the most tokens a normal form is read back to
#define OMEGA_COMPUTER_TOKENS_MOST 65536u

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

// Tromp's universal machine, 190 bits: (\1 (\(\\(\\1 (\\2 (1 4) (5 1 (1 1 1)))) (\3 (\2 (3 (\\3 (\\2 3 (1 4))))
// (4 (\4 (\3 1 (2 1))))))) (1 1)) (\1 (2 2))) (\1 1)
static const char s_omega_computer_universal[] =
    "0100010110000100000100000110000001011100110111100101111110100101101010000111100001011100111100000011110000001011"
    "101110011011110011111000011111000010111101001110100110100001100111011000011010";

// Tromp's delimit, 326 bits: reads a Levenshtein code and returns the number it codes as bits
static const char s_omega_computer_delimit[] =
    "0101000110100000000110000101100111100000100101111101111000010101100000000110000111110000001011111101100101111110"
    "1100101111010011101011110001000000101110010101000110100000000001011000010101111110111110000001010111101111101111"
    "110000101100000010111111101011011100000011111100001011011110111001111010000001011000001101100010000010";

// Tromp's test for uni.lam: this after delimit, and the list it must give
static const char s_omega_computer_delimit_input[] = "1111000111001";

static const char s_omega_computer_delimit_output[] = "11010";

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
    unsigned long long count[OMEGA_COMPUTER_LENGTH_MOST + 1u][OMEGA_COMPUTER_LENGTH_MOST + 2u];
} OmegaComputerCounts;

// the closed-under-k count of n-bit codes; k past n - 1 counts as n - 1
static unsigned long long omega_computer_count(const OmegaComputerCounts *counts, unsigned int length, unsigned int depth)
{
    if (length < 2u)
    {
        return 0ull;
    }
    const unsigned int reach = (depth < (length - 1u)) ? depth : (length - 1u);
    return counts->count[length][reach];
}

static void omega_computer_count_all(OmegaComputerCounts *counts, unsigned int most)
{
    memset(counts->count, 0, sizeof(counts->count));
    for (unsigned int length = 2u; length <= most; length += 1u)
    {
        for (unsigned int depth = 0u; depth < length; depth += 1u)
        {
            unsigned long long total = ((length - 1u) <= depth) ? 1ull : 0ull;
            total += omega_computer_count(counts, length - 2u, depth + 1u);
            for (unsigned int left = 2u; (left + 4u) <= length; left += 1u)
            {
                total += omega_computer_count(counts, left, depth) * omega_computer_count(counts, length - 2u - left, depth);
            }
            counts->count[length][depth] = total;
        }
    }
}

// the term of `length` bits closed under `depth` at `index` in the count's order: the variable, then the lambda, then
// the applications by the left part's length
static void omega_computer_unrank(const OmegaComputerCounts *counts, unsigned int length, unsigned int depth,
                                  unsigned long long index, std::vector<int> &term)
{
    if ((length - 1u) <= depth)
    {
        if (index == 0ull)
        {
            // an index below the length, which is at most 40
            term.push_back((int)(length - 1u));
            return;
        }
        index -= 1ull;
    }
    const unsigned long long bodies = omega_computer_count(counts, length - 2u, depth + 1u);
    if (index < bodies)
    {
        term.push_back(OMEGA_COMPUTER_LAMBDA);
        omega_computer_unrank(counts, length - 2u, depth + 1u, index, term);
        return;
    }
    index -= bodies;
    for (unsigned int left = 2u; (left + 4u) <= length; left += 1u)
    {
        const unsigned long long lefts = omega_computer_count(counts, left, depth);
        const unsigned long long rights = omega_computer_count(counts, length - 2u - left, depth);
        if (index < (lefts * rights))
        {
            term.push_back(OMEGA_COMPUTER_APPLY);
            omega_computer_unrank(counts, left, depth, index / rights, term);
            omega_computer_unrank(counts, length - 2u - left, depth, index % rights, term);
            return;
        }
        index -= lefts * rights;
    }
}

// a code read into tokens from `at`; 1 where it is one term with every variable bound
static int omega_computer_parse(const std::string &code, size_t *at, int depth, std::vector<int> &term)
{
    if ((*at + 2u) > code.size())
    {
        return 0;
    }
    if (code[*at] == '0')
    {
        const int lambda = code[*at + 1u] == '0';
        *at += 2u;
        if (lambda != 0)
        {
            term.push_back(OMEGA_COMPUTER_LAMBDA);
            return omega_computer_parse(code, at, depth + 1, term);
        }
        term.push_back(OMEGA_COMPUTER_APPLY);
        return omega_computer_parse(code, at, depth, term) && omega_computer_parse(code, at, depth, term);
    }
    int index = 0;
    while ((*at < code.size()) && (code[*at] == '1'))
    {
        index += 1;
        *at += 1u;
    }
    if (*at >= code.size())
    {
        return 0;
    }
    *at += 1u;
    term.push_back(index);
    return (index <= depth) ? 1 : 0;
}

static std::string omega_computer_code(const std::vector<int> &term)
{
    std::string code;
    for (size_t at = 0u; at < term.size(); at += 1u)
    {
        if (term[at] == OMEGA_COMPUTER_LAMBDA)
        {
            code += "00";
        }
        else if (term[at] == OMEGA_COMPUTER_APPLY)
        {
            code += "01";
        }
        else
        {
            // an index from 1, at most the lambdas above it
            code.append((size_t)term[at], '1');
            code += '0';
        }
    }
    return code;
}

// the bits as Tromp's list: cons b rest = \z. z b rest, a 0 the true \x\y. x, a 1 the false \x\y. y, and nil false
static void omega_computer_list_tokens(const std::string &bits, std::vector<int> &term)
{
    for (size_t at = 0u; at < bits.size(); at += 1u)
    {
        term.push_back(OMEGA_COMPUTER_LAMBDA);
        term.push_back(OMEGA_COMPUTER_APPLY);
        term.push_back(OMEGA_COMPUTER_APPLY);
        term.push_back(1);
        term.push_back(OMEGA_COMPUTER_LAMBDA);
        term.push_back(OMEGA_COMPUTER_LAMBDA);
        term.push_back((bits[at] == '0') ? 2 : 1);
    }
    term.push_back(OMEGA_COMPUTER_LAMBDA);
    term.push_back(OMEGA_COMPUTER_LAMBDA);
    term.push_back(1);
}

// The rewriting, as chaitin_omega's: one past the subterm starting at `at`
static size_t omega_computer_end(const int *term, size_t at)
{
    long need = 1;
    while (need > 0)
    {
        const int token = term[at];
        at += 1u;
        need += (token == OMEGA_COMPUTER_APPLY) ? 1 : ((token == OMEGA_COMPUTER_LAMBDA) ? 0 : -1);
    }
    return at;
}

// the argument copied under `lifted` more lambdas: a variable bound outside it moves out by that many
static size_t omega_computer_lift(const int *term, size_t at, int bound, int lifted, std::vector<int> &out)
{
    const int token = term[at];
    if (token == OMEGA_COMPUTER_LAMBDA)
    {
        out.push_back(OMEGA_COMPUTER_LAMBDA);
        return omega_computer_lift(term, at + 1u, bound + 1, lifted, out);
    }
    if (token == OMEGA_COMPUTER_APPLY)
    {
        out.push_back(OMEGA_COMPUTER_APPLY);
        const size_t right = omega_computer_lift(term, at + 1u, bound, lifted, out);
        return omega_computer_lift(term, right, bound, lifted, out);
    }
    out.push_back((token > bound) ? (token + lifted) : token);
    return at + 1u;
}

// the body with the argument put for the variable its lambda binds, and every variable bound past that lambda moved
// in by one
static size_t omega_computer_substitute(const int *term, size_t at, int depth, size_t argument, std::vector<int> &out)
{
    const int token = term[at];
    if (token == OMEGA_COMPUTER_LAMBDA)
    {
        out.push_back(OMEGA_COMPUTER_LAMBDA);
        return omega_computer_substitute(term, at + 1u, depth + 1, argument, out);
    }
    if (token == OMEGA_COMPUTER_APPLY)
    {
        out.push_back(OMEGA_COMPUTER_APPLY);
        const size_t right = omega_computer_substitute(term, at + 1u, depth, argument, out);
        return omega_computer_substitute(term, right, depth, argument, out);
    }
    if (token == (depth + 1))
    {
        (void)omega_computer_lift(term, argument, 0, depth, out);
    }
    else
    {
        out.push_back((token > (depth + 1)) ? (token - 1) : token);
    }
    return at + 1u;
}

// one normal order step: the leftmost outermost redex is the first application whose left part is a lambda, read in
// code order; 0 at a normal form
static int omega_computer_step(const std::vector<int> &term, std::vector<int> &next)
{
    for (size_t at = 0u; (at + 1u) < term.size(); at += 1u)
    {
        if ((term[at] == OMEGA_COMPUTER_APPLY) && (term[at + 1u] == OMEGA_COMPUTER_LAMBDA))
        {
            const size_t argument = omega_computer_end(term.data(), at + 1u);
            const size_t after = omega_computer_end(term.data(), argument);
            // the positions are within the term, so they fit its iterator's difference
            next.assign(term.begin(), term.begin() + (long)at);
            (void)omega_computer_substitute(term.data(), at + 2u, 0, argument, next);
            next.insert(next.end(), term.begin() + (long)after, term.end());
            return 1;
        }
    }
    return 0;
}

// A term's spine: k leading applications, then the head, then its k arguments. The spine subterm at position a runs
// from token a to ends[a]. Returns k.
static unsigned int omega_computer_spine(const std::vector<int> &term, std::vector<size_t> &ends)
{
    unsigned int reach = 0u;
    while ((reach < term.size()) && (term[reach] == OMEGA_COMPUTER_APPLY))
    {
        reach += 1u;
    }
    ends.resize((size_t)reach + 1u);
    size_t end = omega_computer_end(term.data(), reach);
    ends[reach] = end;
    for (unsigned int position = reach; position > 0u; position -= 1u)
    {
        end = omega_computer_end(term.data(), end);
        ends[position - 1u] = end;
    }
    return reach;
}

#define OMEGA_COMPUTER_NOT_HEAD 0xFFFFFFFFu

// the spine position of the head redex, where the term is an application spine over a lambda
static unsigned int omega_computer_head_redex(const std::vector<int> &term)
{
    unsigned int reach = 0u;
    while ((reach < term.size()) && (term[reach] == OMEGA_COMPUTER_APPLY))
    {
        reach += 1u;
    }
    return ((reach > 0u) && (reach < term.size()) && (term[reach] == OMEGA_COMPUTER_LAMBDA)) ? (reach - 1u)
                                                                                                : OMEGA_COMPUTER_NOT_HEAD;
}

// proven growth without end (chaitin_omega's omega_grows_forever): a spine subterm reduced only by head steps comes
// back deeper on the spine, so it has no head normal form and neither has the term
static int omega_computer_grows_forever(const std::vector<int> &held, const std::vector<size_t> &held_ends,
                                        unsigned int held_reach, const std::vector<int> &term, unsigned int least,
                                        std::vector<size_t> &ends)
{
    const unsigned int reach = omega_computer_spine(term, ends);
    const unsigned int deepest = (least < held_reach) ? least : held_reach;
    for (unsigned int from = 0u; from <= deepest; from += 1u)
    {
        const size_t size = held_ends[from] - from;
        for (unsigned int to = from + 1u; to <= reach; to += 1u)
        {
            if (((ends[to] - to) == size) && (memcmp(&held[from], &term[to], size * sizeof(int)) == 0))
            {
                return 1;
            }
        }
    }
    return 0;
}

// normal order under a step and a size budget, watched by Brent's cycle finder and the growth proof; on a halt `term`
// is left holding the normal form
static size_t s_omega_computer_peak = 0u;

static OmegaComputerFate omega_computer_rewrite(std::vector<int> &term, unsigned int steps, unsigned int tokens,
                                                unsigned long long *taken)
{
    s_omega_computer_peak = term.size();
    std::vector<int> next;
    std::vector<int> held = term;
    std::vector<size_t> held_ends;
    std::vector<size_t> ends;
    unsigned int held_reach = omega_computer_spine(held, held_ends);
    unsigned int least = OMEGA_COMPUTER_NOT_HEAD - 1u;
    unsigned int power = 1u;
    unsigned int since = 0u;
    *taken = steps;
    for (unsigned int step = 0u; step < steps; step += 1u)
    {
        const unsigned int redex = omega_computer_head_redex(term);
        if (omega_computer_step(term, next) == 0)
        {
            *taken = step;
            return OMEGA_COMPUTER_HALTS;
        }
        least = ((redex == OMEGA_COMPUTER_NOT_HEAD) || (least == OMEGA_COMPUTER_NOT_HEAD)) ? OMEGA_COMPUTER_NOT_HEAD
              : ((redex < least) ? redex : least);
        term.swap(next);
        s_omega_computer_peak = (term.size() > s_omega_computer_peak) ? term.size() : s_omega_computer_peak;
        if (term == held)
        {
            return OMEGA_COMPUTER_LOOPS;
        }
        if ((least != OMEGA_COMPUTER_NOT_HEAD)
            && (omega_computer_grows_forever(held, held_ends, held_reach, term, least, ends) != 0))
        {
            return OMEGA_COMPUTER_DIVERGES;
        }
        if (term.size() > (size_t)tokens)
        {
            return OMEGA_COMPUTER_GREW;
        }
        since += 1u;
        if (since == power)
        {
            held = term;
            held_reach = omega_computer_spine(held, held_ends);
            least = OMEGA_COMPUTER_NOT_HEAD - 1u;
            power *= 2u;
            since = 0u;
        }
    }
    return (omega_computer_step(term, next) == 0) ? OMEGA_COMPUTER_HALTS : OMEGA_COMPUTER_OPEN;
}

// The lazy machine: a node appended to the term arena
static int omega_computer_node(OmegaComputerMachine *machine, int kind, int left, int right)
{
    OmegaComputerNode node;
    node.kind = kind;
    node.left = left;
    node.right = right;
    machine->nodes.push_back(node);
    // the arena holds a program, its input and U, far below 2^31 nodes
    return (int)(machine->nodes.size() - 1u);
}

// the tokens from `at` as nodes; returns the root and leaves `at` one past the term
static int omega_computer_compile(OmegaComputerMachine *machine, const std::vector<int> &term, size_t *at)
{
    const int token = term[*at];
    *at += 1u;
    if (token == OMEGA_COMPUTER_LAMBDA)
    {
        const int body = omega_computer_compile(machine, term, at);
        return omega_computer_node(machine, OMEGA_COMPUTER_NODE_LAMBDA, body, 0);
    }
    if (token == OMEGA_COMPUTER_APPLY)
    {
        const int function = omega_computer_compile(machine, term, at);
        const int argument = omega_computer_compile(machine, term, at);
        return omega_computer_node(machine, OMEGA_COMPUTER_NODE_APPLY, function, argument);
    }
    return omega_computer_node(machine, OMEGA_COMPUTER_NODE_VARIABLE, token, 0);
}

// the bits as Tromp's list, built from its end, sharing the true, the false and the variable nodes
static int omega_computer_list(OmegaComputerMachine *machine, const std::string &bits)
{
    int rest = machine->false_node;
    for (size_t at = bits.size(); at > 0u; at -= 1u)
    {
        const int bit = (bits[at - 1u] == '0') ? machine->true_node : machine->false_node;
        const int applied = omega_computer_node(machine, OMEGA_COMPUTER_NODE_APPLY, machine->variable_node, bit);
        const int pair = omega_computer_node(machine, OMEGA_COMPUTER_NODE_APPLY, applied, rest);
        rest = omega_computer_node(machine, OMEGA_COMPUTER_NODE_LAMBDA, pair, 0);
    }
    return rest;
}

static void omega_computer_machine_open(OmegaComputerMachine *machine, const std::vector<int> &universal)
{
    machine->nodes.clear();
    machine->variable_node = omega_computer_node(machine, OMEGA_COMPUTER_NODE_VARIABLE, 1, 0);
    const int second = omega_computer_node(machine, OMEGA_COMPUTER_NODE_VARIABLE, 2, 0);
    machine->true_node = omega_computer_node(
        machine, OMEGA_COMPUTER_NODE_LAMBDA, omega_computer_node(machine, OMEGA_COMPUTER_NODE_LAMBDA, second, 0), 0);
    machine->false_node = omega_computer_node(
        machine, OMEGA_COMPUTER_NODE_LAMBDA,
        omega_computer_node(machine, OMEGA_COMPUTER_NODE_LAMBDA, machine->variable_node, 0), 0);
    size_t at = 0u;
    machine->universal_node = omega_computer_compile(machine, universal, &at);
    machine->fixed_nodes = machine->nodes.size();
}

static int omega_computer_cells_left(const OmegaComputerMachine *machine)
{
    return (machine->thunks.size() + machine->environments.size() + machine->spines.size())
         < (size_t)OMEGA_COMPUTER_CELLS_MOST;
}

static int omega_computer_thunk(OmegaComputerMachine *machine, int term, int environment)
{
    OmegaComputerThunk thunk;
    thunk.term = term;
    thunk.environment = environment;
    thunk.state = OMEGA_COMPUTER_UNEVALUATED;
    thunk.neutral = 0;
    thunk.value = 0;
    thunk.value_cells = -1;
    machine->thunks.push_back(thunk);
    // the cells are held below OMEGA_COMPUTER_CELLS_MOST, 2^25
    return (int)(machine->thunks.size() - 1u);
}

static int omega_computer_cell(std::vector<OmegaComputerCell> &cells, int thunk, int next)
{
    OmegaComputerCell cell;
    cell.thunk = thunk;
    cell.next = next;
    cells.push_back(cell);
    // the cells are held below OMEGA_COMPUTER_CELLS_MOST, 2^25
    return (int)(cells.size() - 1u);
}

// the thunk the variable `index` (from 1) names in the environment
static int omega_computer_lookup(const OmegaComputerMachine *machine, int environment, int index)
{
    int cell = environment;
    for (int step = 1; step < index; step += 1)
    {
        cell = machine->environments[(size_t)cell].next;
    }
    return machine->environments[(size_t)cell].thunk;
}

// The thunk to its weak head normal form, by Krivine's machine with Sestoft's update frames: the stack holds arguments
// (a thunk, shifted up one) and updates (a thunk, shifted up one, with the low bit set). A lambda meeting an argument
// is a beta step; meeting an update, it becomes that thunk's value. A variable whose thunk is evaluated continues as
// its value; one not yet evaluated is entered under an update; one already entered is needed to make its own value,
// so it never has one, and nor has the term.
static OmegaComputerFate omega_computer_whnf(OmegaComputerMachine *machine, int root)
{
    if (machine->thunks[(size_t)root].state == OMEGA_COMPUTER_EVALUATED)
    {
        return OMEGA_COMPUTER_HALTS;
    }
    if (machine->thunks[(size_t)root].state == OMEGA_COMPUTER_ENTERED)
    {
        return OMEGA_COMPUTER_LOOPS;
    }
    std::vector<int> &stack = machine->stack;
    stack.clear();
    stack.push_back((root << 1) | 1);
    machine->thunks[(size_t)root].state = OMEGA_COMPUTER_ENTERED;
    int term = machine->thunks[(size_t)root].term;
    int environment = machine->thunks[(size_t)root].environment;
    for (;;)
    {
        const OmegaComputerNode node = machine->nodes[(size_t)term];
        if (node.kind == OMEGA_COMPUTER_NODE_APPLY)
        {
            if (omega_computer_cells_left(machine) == 0)
            {
                return OMEGA_COMPUTER_GREW;
            }
            const OmegaComputerNode argument = machine->nodes[(size_t)node.right];
            // a variable argument shares the thunk it names, so no chain of thunks forms
            const int thunk = (argument.kind == OMEGA_COMPUTER_NODE_VARIABLE)
                                ? omega_computer_lookup(machine, environment, argument.left)
                                : omega_computer_thunk(machine, node.right, environment);
            stack.push_back(thunk << 1);
            term = node.left;
            continue;
        }
        if (node.kind == OMEGA_COMPUTER_NODE_LAMBDA)
        {
            const int top = stack.back();
            if ((top & 1) == 0)
            {
                if (machine->steps >= machine->step_budget)
                {
                    return OMEGA_COMPUTER_OPEN;
                }
                if (omega_computer_cells_left(machine) == 0)
                {
                    return OMEGA_COMPUTER_GREW;
                }
                stack.pop_back();
                environment = omega_computer_cell(machine->environments, top >> 1, environment);
                term = node.left;
                machine->steps += 1ull;
                continue;
            }
            OmegaComputerThunk &updated = machine->thunks[(size_t)(top >> 1)];
            updated.state = OMEGA_COMPUTER_EVALUATED;
            updated.neutral = 0;
            updated.value = term;
            updated.value_cells = environment;
            stack.pop_back();
            if (stack.empty())
            {
                return OMEGA_COMPUTER_HALTS;
            }
            continue;
        }
        const int named = omega_computer_lookup(machine, environment, node.left);
        const OmegaComputerThunk thunk = machine->thunks[(size_t)named];
        if (thunk.state == OMEGA_COMPUTER_UNEVALUATED)
        {
            machine->thunks[(size_t)named].state = OMEGA_COMPUTER_ENTERED;
            stack.push_back((named << 1) | 1);
            term = thunk.term;
            environment = thunk.environment;
            continue;
        }
        if (thunk.state == OMEGA_COMPUTER_ENTERED)
        {
            return OMEGA_COMPUTER_LOOPS;
        }
        if (thunk.neutral == 0)
        {
            term = thunk.value;
            environment = thunk.value_cells;
            continue;
        }
        // a variable applied: every argument on the stack joins its spine, and every update takes the spine so far
        int spine = thunk.value_cells;
        while (!stack.empty())
        {
            const int entry = stack.back();
            stack.pop_back();
            if ((entry & 1) == 0)
            {
                if (omega_computer_cells_left(machine) == 0)
                {
                    return OMEGA_COMPUTER_GREW;
                }
                spine = omega_computer_cell(machine->spines, entry >> 1, spine);
                continue;
            }
            OmegaComputerThunk &updated = machine->thunks[(size_t)(entry >> 1)];
            updated.state = OMEGA_COMPUTER_EVALUATED;
            updated.neutral = 1;
            updated.value = thunk.value;
            updated.value_cells = spine;
        }
        return OMEGA_COMPUTER_HALTS;
    }
}

// The thunk's normal form read back as tokens: a lambda is read back by putting a fresh variable for its own and
// reading its body a lambda deeper; a variable applied to its spine is read back as the variable, its index from the
// depth and the level it was made at, and then each argument read back in turn. Every thunk read is first taken to
// its weak head normal form, which normal order needs too, so this reaches the normal form wherever one exists.
static OmegaComputerFate omega_computer_normal(OmegaComputerMachine *machine, int root, std::vector<int> &out)
{
    out.clear();
    std::vector<OmegaComputerWork> &work = machine->work;
    work.clear();
    OmegaComputerWork first;
    first.thunk = root;
    first.depth = 0;
    work.push_back(first);
    while (!work.empty())
    {
        const OmegaComputerWork item = work.back();
        work.pop_back();
        const OmegaComputerFate fate = omega_computer_whnf(machine, item.thunk);
        if (fate != OMEGA_COMPUTER_HALTS)
        {
            return fate;
        }
        if (out.size() > (size_t)OMEGA_COMPUTER_TOKENS_MOST)
        {
            return OMEGA_COMPUTER_GREW;
        }
        const OmegaComputerThunk thunk = machine->thunks[(size_t)item.thunk];
        if (omega_computer_cells_left(machine) == 0)
        {
            return OMEGA_COMPUTER_GREW;
        }
        if (thunk.neutral == 0)
        {
            out.push_back(OMEGA_COMPUTER_LAMBDA);
            const int fresh = omega_computer_thunk(machine, 0, -1);
            machine->thunks[(size_t)fresh].state = OMEGA_COMPUTER_EVALUATED;
            machine->thunks[(size_t)fresh].neutral = 1;
            machine->thunks[(size_t)fresh].value = item.depth;
            machine->thunks[(size_t)fresh].value_cells = -1;
            const int environment = omega_computer_cell(machine->environments, fresh, thunk.value_cells);
            OmegaComputerWork body;
            body.thunk = omega_computer_thunk(machine, machine->nodes[(size_t)thunk.value].left, environment);
            body.depth = item.depth + 1;
            work.push_back(body);
            continue;
        }
        std::vector<int> &arguments = machine->arguments;
        arguments.clear();
        for (int cell = thunk.value_cells; cell >= 0; cell = machine->spines[(size_t)cell].next)
        {
            arguments.push_back(machine->spines[(size_t)cell].thunk);
        }
        // the spine holds its last argument first
        out.insert(out.end(), arguments.size(), OMEGA_COMPUTER_APPLY);
        out.push_back(item.depth - thunk.value);
        for (size_t at = 0u; at < arguments.size(); at += 1u)
        {
            OmegaComputerWork argument;
            argument.thunk = arguments[at];
            argument.depth = item.depth;
            work.push_back(argument);
        }
    }
    return OMEGA_COMPUTER_HALTS;
}

// One run of the lazy machine: the program on its input bits `depth` machines deep, the direct run at depth 0
static OmegaComputerFate omega_computer_run(OmegaComputerMachine *machine, const std::vector<int> &program,
                                            const std::string &input, unsigned int depth,
                                            const std::string &universal_code, std::vector<int> &normal)
{
    machine->nodes.resize(machine->fixed_nodes);
    machine->thunks.clear();
    machine->environments.clear();
    machine->spines.clear();
    machine->steps = 0ull;
    int root = 0;
    if (depth == 0u)
    {
        size_t at = 0u;
        const int function = omega_computer_compile(machine, program, &at);
        root = omega_computer_node(machine, OMEGA_COMPUTER_NODE_APPLY, function, omega_computer_list(machine, input));
    }
    else
    {
        std::string bits;
        for (unsigned int copy = 1u; copy < depth; copy += 1u)
        {
            bits += universal_code;
        }
        bits += omega_computer_code(program);
        bits += input;
        root = omega_computer_node(machine, OMEGA_COMPUTER_NODE_APPLY, machine->universal_node,
                                   omega_computer_list(machine, bits));
    }
    return omega_computer_normal(machine, omega_computer_thunk(machine, root, -1), normal);
}

// the direct run by rewriting: the program applied to its input's list
static OmegaComputerFate omega_computer_direct(const std::vector<int> &program, const std::string &input,
                                               unsigned int steps, unsigned int tokens, std::vector<int> &normal,
                                               unsigned long long *taken)
{
    normal.clear();
    normal.push_back(OMEGA_COMPUTER_APPLY);
    normal.insert(normal.end(), program.begin(), program.end());
    omega_computer_list_tokens(input, normal);
    return omega_computer_rewrite(normal, steps, tokens, taken);
}

static void omega_computer_binary(ScripturaLine *line, unsigned long long numerator, unsigned int bits)
{
    scriptura_text(line, "0.");
    for (unsigned int bit = bits; bit > 0u; bit -= 1u)
    {
        scriptura_character(line, (((numerator >> (bit - 1u)) & 1ull) != 0ull) ? '1' : '0');
    }
}

// the leading bits a value strictly between low and high over 2^bits is proven to have
static unsigned int omega_computer_proven(unsigned long long low, unsigned long long high, unsigned int bits)
{
    unsigned int proven = 0u;
    for (unsigned int place = 1u; place <= bits; place += 1u)
    {
        const unsigned int shift = bits - place;
        const unsigned long long floor_low = low >> shift;
        // the value is below high, so its first `place` bits are at most ceil(high / 2^shift) - 1
        const unsigned long long top = ((high + ((1ull << shift) - 1ull)) >> shift) - 1ull;
        if (floor_low != top)
        {
            break;
        }
        proven = place;
    }
    return proven;
}

static int omega_computer_request(const char *text, unsigned long long least, unsigned long long most,
                                  unsigned long long *value)
{
    unsigned long long read = 0ull;
    if ((text == NULL) || (text[0] == '\0'))
    {
        return 0;
    }
    for (const char *walk = text; *walk != '\0'; walk += 1)
    {
        if ((*walk < '0') || (*walk > '9') || (read > most))
        {
            return 0;
        }
        // one decimal digit, 0 to 9
        read = (read * 10ull) + (unsigned long long)(*walk - '0');
    }
    if ((read < least) || (read > most))
    {
        return 0;
    }
    *value = read;
    return 1;
}

int main(int count, char **arguments)
{
    char room[SIM_LINE_ROOM];
    SimTally tally;
    sim_open(&tally, room);
    unsigned long long length = OMEGA_COMPUTER_LENGTH_DEFAULT;
    unsigned long long deepest = OMEGA_COMPUTER_DEPTH_DEFAULT;
    unsigned long long budget = OMEGA_COMPUTER_STEPS_DEFAULT;
    const int understood = ((count < 2) || omega_computer_request(arguments[1], 2ull, OMEGA_COMPUTER_LENGTH_MOST, &length))
                        && ((count < 3) || omega_computer_request(arguments[2], 1ull, OMEGA_COMPUTER_DEPTH_MOST, &deepest))
                        && ((count < 4) || omega_computer_request(arguments[3], 1ull, 1ull << 40u, &budget)) && (count <= 4);
    if (understood == 0)
    {
        scriptura_text(&tally.line, "  usage: omega_computer [L, 2 to 40] [depth, 1 to 8] [steps a run]\n");
        sim_check(&tally, 0, "the request names its length, its depth and its steps");
        return sim_close(&tally, "omega computer");
    }
    // the request's values are at most 40 and 8
    const unsigned int most = (unsigned int)length;
    const unsigned int depths = (unsigned int)deepest;

    // 1. U, and Tromp's test at every depth
    const std::string universal_code = s_omega_computer_universal;
    std::vector<int> universal;
    size_t universal_at = 0u;
    const int universal_closed = omega_computer_parse(universal_code, &universal_at, 0, universal)
                              && (universal_at == universal_code.size());
    std::vector<int> delimit;
    size_t delimit_at = 0u;
    const std::string delimit_code = s_omega_computer_delimit;
    const int delimit_closed = omega_computer_parse(delimit_code, &delimit_at, 0, delimit)
                            && (delimit_at == delimit_code.size());
    scriptura_text(&tally.line, "  U, Tromp's universal machine: ");
    scriptura_decimal(&tally.line, universal_code.size(), 1u);
    scriptura_text(&tally.line, " bits, ");
    scriptura_decimal(&tally.line, universal.size(), 1u);
    scriptura_text(&tally.line, " tokens; delimit: ");
    scriptura_decimal(&tally.line, delimit_code.size(), 1u);
    scriptura_text(&tally.line, " bits\n");
    sim_check(&tally, universal_closed && (universal_code.size() == 190u) && (omega_computer_code(universal) == universal_code),
              "U is one closed term of 190 bits, and its code reads back to itself");
    sim_flush(&tally);
    OmegaComputerMachine machine;
    omega_computer_machine_open(&machine, universal);
    machine.step_budget = budget;
    std::vector<int> expected;
    omega_computer_list_tokens(s_omega_computer_delimit_output, expected);
    std::vector<int> normal;
    int tromp_held = delimit_closed;
    scriptura_text(&tally.line, "  Tromp's test, delimit then 1111000111001: depth, fate, beta steps, and the list\n");
    for (unsigned int depth = 0u; depth <= depths; depth += 1u)
    {
        const OmegaComputerFate fate = omega_computer_run(&machine, delimit, s_omega_computer_delimit_input, depth,
                                                          universal_code, normal);
        const int held = (fate == OMEGA_COMPUTER_HALTS) && (normal == expected);
        tromp_held = tromp_held && held;
        scriptura_text(&tally.line, "    ");
        scriptura_decimal(&tally.line, depth, 1u);
        scriptura_text(&tally.line, (fate == OMEGA_COMPUTER_HALTS) ? "  halts  " : "  does not halt  ");
        scriptura_decimal(&tally.line, machine.steps, 1u);
        scriptura_text(&tally.line, "  cells ");
        scriptura_decimal(&tally.line, machine.thunks.size() + machine.environments.size() + machine.spines.size(), 1u);
        scriptura_text(&tally.line, (held != 0) ? "  11010\n" : "  NOT 11010\n");
        sim_flush(&tally);
    }
    std::vector<int> rewritten;
    unsigned long long rewrite_taken = 0ull;
    const OmegaComputerFate delimit_direct = omega_computer_direct(delimit, s_omega_computer_delimit_input, 1u << 20u,
                                                                   1u << 19u, rewritten, &rewrite_taken);
    tromp_held = tromp_held && (delimit_direct == OMEGA_COMPUTER_HALTS) && (rewritten == expected);
    scriptura_text(&tally.line, "    the rewriting, directly: fate ");
    scriptura_decimal(&tally.line, (unsigned long long)delimit_direct, 1u);
    scriptura_text(&tally.line, ", ");
    scriptura_decimal(&tally.line, rewrite_taken, 1u);
    scriptura_text(&tally.line, " steps, ");
    scriptura_decimal(&tally.line, rewritten.size(), 1u);
    scriptura_text(&tally.line, " tokens\n");
    sim_check(&tally, tromp_held,
              "U reading delimit and 1111000111001 gives the list 11010 at every depth, and the rewriting gives it directly");
    // diagnostic: normal order rewriting of U nested, its steps and its largest live term
    {
        std::vector<int> identity;
        identity.push_back(OMEGA_COMPUTER_LAMBDA);
        identity.push_back(1);
        const std::vector<int> *const tried[2] = {&identity, &delimit};
        const char *const inputs[2] = {"", s_omega_computer_delimit_input};
        for (unsigned int which = 0u; which < 2u; which += 1u)
        {
            for (unsigned int depth = 1u; depth <= 2u; depth += 1u)
            {
                std::string bits;
                for (unsigned int copy = 1u; copy < depth; copy += 1u)
                {
                    bits += universal_code;
                }
                bits += omega_computer_code(*tried[which]);
                bits += inputs[which];
                std::vector<int> nested;
                nested.push_back(OMEGA_COMPUTER_APPLY);
                nested.insert(nested.end(), universal.begin(), universal.end());
                omega_computer_list_tokens(bits, nested);
                const size_t start = nested.size();
                unsigned long long nested_taken = 0ull;
                const OmegaComputerFate nested_fate = omega_computer_rewrite(nested, 1u << 18u, 1u << 17u, &nested_taken);
                scriptura_text(&tally.line, "    rewriting ");
                scriptura_text(&tally.line, (which == 0u) ? "identity" : "delimit");
                scriptura_text(&tally.line, " depth ");
                scriptura_decimal(&tally.line, depth, 1u);
                scriptura_text(&tally.line, ": fate ");
                scriptura_decimal(&tally.line, (unsigned long long)nested_fate, 1u);
                scriptura_text(&tally.line, ", steps ");
                scriptura_decimal(&tally.line, nested_taken, 1u);
                scriptura_text(&tally.line, ", start ");
                scriptura_decimal(&tally.line, start, 1u);
                scriptura_text(&tally.line, " tokens, peak ");
                scriptura_decimal(&tally.line, s_omega_computer_peak, 1u);
                scriptura_text(&tally.line, " tokens\n");
                sim_flush(&tally);
            }
        }
    }

    // 2 to 4. every closed M through L bits, run on nil at every depth
    OmegaComputerCounts counts;
    omega_computer_count_all(&counts, most);
    std::vector<unsigned long long> halted(depths + 1u, 0ull);
    std::vector<unsigned long long> looped(depths + 1u, 0ull);
    std::vector<unsigned long long> open(depths + 1u, 0ull);
    std::vector<unsigned long long> grew(depths + 1u, 0ull);
    std::vector<unsigned long long> halted_mass(depths + 1u, 0ull);
    std::vector<unsigned long long> steps_total(depths + 1u, 0ull);
    unsigned long long proven_mass = 0ull;
    unsigned long long programs = 0ull;
    unsigned long long direct_halted = 0ull;
    unsigned long long direct_proven = 0ull;
    unsigned long long agree_direct = 0ull;
    unsigned long long lazy_missed = 0ull;
    unsigned long long settled_everywhere = 0ull;
    unsigned long long contradictions = 0ull;
    unsigned long long unnested = 0ull;
    std::vector<unsigned long long> depth_steps(depths + 1u, 0ull);
    std::vector<OmegaComputerFate> fates(depths + 1u, OMEGA_COMPUTER_OPEN);
    std::vector<std::vector<int>> normals(depths + 1u);
    for (unsigned int bits = 2u; bits <= most; bits += 1u)
    {
        const unsigned long long terms = omega_computer_count(&counts, bits, 0u);
        const unsigned long long mass = 1ull << (most - bits);
        for (unsigned long long index = 0ull; index < terms; index += 1ull)
        {
            std::vector<int> program;
            omega_computer_unrank(&counts, bits, 0u, index, program);
            programs += 1ull;
            unsigned long long taken = 0ull;
            std::vector<int> direct_normal;
            const OmegaComputerFate direct = omega_computer_direct(program, "", OMEGA_COMPUTER_REWRITE_STEPS,
                                                                   OMEGA_COMPUTER_REWRITE_TOKENS, direct_normal, &taken);
            const int proven_by_rewriting = (direct == OMEGA_COMPUTER_LOOPS) || (direct == OMEGA_COMPUTER_DIVERGES);
            machine.step_budget = (proven_by_rewriting && (budget > OMEGA_COMPUTER_NEVER_STEPS)) ? OMEGA_COMPUTER_NEVER_STEPS
                                                                                                  : budget;
            for (unsigned int depth = 0u; depth <= depths; depth += 1u)
            {
                fates[depth] = omega_computer_run(&machine, program, "", depth, universal_code, normals[depth]);
                depth_steps[depth] = machine.steps;
            }
            // the direct run halts where the rewriting or the lazy machine at depth 0 halts, and never halts where either
            // proves it
            const int rewrite_halts = direct == OMEGA_COMPUTER_HALTS;
            const int rewrite_never = (direct == OMEGA_COMPUTER_LOOPS) || (direct == OMEGA_COMPUTER_DIVERGES);
            const std::vector<int> &reference = rewrite_halts ? direct_normal : normals[0];
            const int reference_halts = rewrite_halts || (fates[0] == OMEGA_COMPUTER_HALTS);
            int never = rewrite_never;
            for (unsigned int depth = 0u; depth <= depths; depth += 1u)
            {
                never = never || (fates[depth] == OMEGA_COMPUTER_LOOPS);
            }
            if (rewrite_halts && (fates[0] == OMEGA_COMPUTER_HALTS))
            {
                agree_direct += (direct_normal == normals[0]) ? 1ull : 0ull;
                contradictions += (direct_normal == normals[0]) ? 0ull : 1ull;
            }
            lazy_missed += (rewrite_halts && (fates[0] != OMEGA_COMPUTER_HALTS)) ? 1ull : 0ull;
            direct_halted += (reference_halts != 0) ? 1ull : 0ull;
            direct_proven += (never != 0) ? 1ull : 0ull;
            contradictions += ((reference_halts != 0) && (never != 0)) ? 1ull : 0ull;
            proven_mass += (never != 0) ? mass : 0ull;
            int everywhere = reference_halts;
            for (unsigned int depth = 0u; depth <= depths; depth += 1u)
            {
                const int halts = (depth == 0u) ? reference_halts : (fates[depth] == OMEGA_COMPUTER_HALTS);
                if (halts != 0)
                {
                    halted[depth] += 1ull;
                    halted_mass[depth] += mass;
                    // a halt at any depth has the direct run's normal form, and no run proves it never halts
                    if ((depth > 0u) && (((reference_halts != 0) && (normals[depth] != reference)) || (never != 0)))
                    {
                        contradictions += 1ull;
                    }
                    // every M the inner machine finishes, the outer machine finished
                    if (depth > 0u)
                    {
                        const int outer = (depth == 1u) ? reference_halts : (fates[depth - 1u] == OMEGA_COMPUTER_HALTS);
                        unnested += (outer != 0) ? 0ull : 1ull;
                    }
                }
                else
                {
                    everywhere = 0;
                    const OmegaComputerFate fate = (depth == 0u) ? (rewrite_never ? direct : fates[0]) : fates[depth];
                    looped[depth] += ((fate == OMEGA_COMPUTER_LOOPS) || (fate == OMEGA_COMPUTER_DIVERGES)) ? 1ull : 0ull;
                    open[depth] += (fate == OMEGA_COMPUTER_OPEN) ? 1ull : 0ull;
                    grew[depth] += (fate == OMEGA_COMPUTER_GREW) ? 1ull : 0ull;
                }
            }
            if (everywhere != 0)
            {
                settled_everywhere += 1ull;
                for (unsigned int depth = 0u; depth <= depths; depth += 1u)
                {
                    steps_total[depth] += depth_steps[depth];
                }
            }
        }
    }

    // the mass of every code through L bits, closed or not, over 2^L; what it leaves of 1 bounds every longer code
    std::vector<unsigned long long> all_codes(most + 1u, 0ull);
    unsigned long long counted = 0ull;
    unsigned long long closed_mass = 0ull;
    for (unsigned int bits = 2u; bits <= most; bits += 1u)
    {
        unsigned long long codes = 1ull + all_codes[bits - 2u];
        for (unsigned int left = 2u; (left + 4u) <= bits; left += 1u)
        {
            codes += all_codes[left] * all_codes[bits - 2u - left];
        }
        all_codes[bits] = codes;
        counted += codes << (most - bits);
        closed_mass += omega_computer_count(&counts, bits, 0u) << (most - bits);
    }
    const unsigned long long whole = 1ull << most;
    // the upper bound: everything but the proven non-halts and the codes through L that are not closed
    const unsigned long long upper = whole - proven_mass - (counted - closed_mass);

    scriptura_text(&tally.line, "  ");
    scriptura_decimal(&tally.line, programs, 1u);
    scriptura_text(&tally.line, " closed programs through ");
    scriptura_decimal(&tally.line, most, 1u);
    scriptura_text(&tally.line, " bits, run on nil; the direct run halts ");
    scriptura_decimal(&tally.line, direct_halted, 1u);
    scriptura_text(&tally.line, " and proves ");
    scriptura_decimal(&tally.line, direct_proven, 1u);
    scriptura_text(&tally.line, " never halt; the rewriting and the lazy machine agree on ");
    scriptura_decimal(&tally.line, agree_direct, 1u);
    scriptura_text(&tally.line, " normal forms\n  depth  halted  proven never  out of steps  outgrew  Omega_nil at least  proven bits  steps (settled everywhere)\n");
    unsigned long long previous_mass = 0ull;
    int nested = 1;
    for (unsigned int depth = 0u; depth <= depths; depth += 1u)
    {
        nested = nested && ((depth == 0u) || (halted_mass[depth] <= previous_mass));
        previous_mass = halted_mass[depth];
        scriptura_text(&tally.line, "    ");
        scriptura_decimal(&tally.line, depth, 1u);
        scriptura_text(&tally.line, "  ");
        scriptura_decimal(&tally.line, halted[depth], 1u);
        scriptura_text(&tally.line, "  ");
        scriptura_decimal(&tally.line, looped[depth], 1u);
        scriptura_text(&tally.line, "  ");
        scriptura_decimal(&tally.line, open[depth], 1u);
        scriptura_text(&tally.line, "  ");
        scriptura_decimal(&tally.line, grew[depth], 1u);
        scriptura_text(&tally.line, "  ");
        omega_computer_binary(&tally.line, halted_mass[depth], most);
        scriptura_text(&tally.line, "  ");
        scriptura_decimal(&tally.line, omega_computer_proven(halted_mass[depth], upper, most), 1u);
        scriptura_text(&tally.line, "  ");
        scriptura_decimal(&tally.line, steps_total[depth], 1u);
        if (depth > 0u)
        {
            scriptura_text(&tally.line, " (x");
            sim_fraction_print(&tally.line, steps_total[depth], (steps_total[depth - 1u] == 0ull) ? 1ull : steps_total[depth - 1u], 2u);
            scriptura_character(&tally.line, ')');
        }
        scriptura_character(&tally.line, '\n');
        sim_flush(&tally);
    }
    scriptura_text(&tally.line, "  Omega_nil at most ");
    omega_computer_binary(&tally.line, upper, most);
    scriptura_text(&tally.line, " at every depth; ");
    scriptura_decimal(&tally.line, settled_everywhere, 1u);
    scriptura_text(&tally.line, " programs halt at every depth\n");
    sim_check(&tally, contradictions == 0ull,
              "every normal form at every depth is the direct run's, token for token, and no run halts that any run proves never halts");
    sim_check(&tally, (unnested == 0ull) && nested,
              "each depth's bracket holds the one outside it: every program the inner machine finishes, the outer finished");
    sim_check(&tally, (lazy_missed == 0ull) && (agree_direct > 0ull),
              "the lazy machine reaches every normal form the rewriting reaches, run directly");
    return sim_close(&tally, "omega computer");
}
