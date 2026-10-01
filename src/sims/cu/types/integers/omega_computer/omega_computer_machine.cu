// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// omega_computer_machine.cu: rewriting, the machine and the run
#include "omega_computer_internal.h"

OmegaComputerFate omega_computer_rewrite(std::vector<int> &term, unsigned int steps, unsigned int tokens,
                                         unsigned long long *taken)
{
    g_omega_computer_peak = term.size();
    std::vector<int> next;
    std::vector<int> stored = term;
    std::vector<size_t> stored_ends;
    std::vector<size_t> ends;
    unsigned int stored_range = omega_computer_spine(stored, stored_ends);
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
        least = ((redex == OMEGA_COMPUTER_NOT_HEAD) || (least == OMEGA_COMPUTER_NOT_HEAD))
                    ? OMEGA_COMPUTER_NOT_HEAD
                    : ((redex < least) ? redex : least);
        term.swap(next);
        g_omega_computer_peak = (term.size() > g_omega_computer_peak) ? term.size() : g_omega_computer_peak;
        if (term == stored)
        {
            return OMEGA_COMPUTER_LOOPS;
        }
        if ((least != OMEGA_COMPUTER_NOT_HEAD) &&
            (omega_computer_grows_forever(stored, stored_ends, stored_range, term, least, ends) != 0))
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
            stored = term;
            stored_range = omega_computer_spine(stored, stored_ends);
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

void omega_computer_machine_open(OmegaComputerMachine *machine, const std::vector<int> &universal)
{
    machine->nodes.clear();
    machine->variable_node = omega_computer_node(machine, OMEGA_COMPUTER_NODE_VARIABLE, 1, 0);
    const int second = omega_computer_node(machine, OMEGA_COMPUTER_NODE_VARIABLE, 2, 0);
    machine->true_node = omega_computer_node(machine, OMEGA_COMPUTER_NODE_LAMBDA,
                                             omega_computer_node(machine, OMEGA_COMPUTER_NODE_LAMBDA, second, 0), 0);
    machine->false_node =
        omega_computer_node(machine, OMEGA_COMPUTER_NODE_LAMBDA,
                            omega_computer_node(machine, OMEGA_COMPUTER_NODE_LAMBDA, machine->variable_node, 0), 0);
    size_t at = 0u;
    machine->universal_node = omega_computer_compile(machine, universal, &at);
    machine->fixed_nodes = machine->nodes.size();
}

static int omega_computer_cells_left(const OmegaComputerMachine *machine)
{
    return (machine->thunks.size() + machine->environments.size() + machine->spines.size()) <
           (size_t)OMEGA_COMPUTER_CELLS_MAX;
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
    // the cells are held below OMEGA_COMPUTER_CELLS_MAX, 2^27
    return (int)(machine->thunks.size() - 1u);
}

static int omega_computer_cell(std::vector<OmegaComputerCell> &cells, int thunk, int next)
{
    OmegaComputerCell cell;
    cell.thunk = thunk;
    cell.next = next;
    cells.push_back(cell);
    // the cells are held below OMEGA_COMPUTER_CELLS_MAX, 2^27
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
// its value; one not yet evaluated is entered under an update; one already entered is needed to make its own value.
// It never has one, and nor has the term.
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
            // a variable argument shares the thunk it names. No chain of thunks forms
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
// its weak head normal form, which normal order needs too. This reaches the normal form wherever one exists.
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
        if (out.size() > (size_t)OMEGA_COMPUTER_TOKENS_MAX)
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
OmegaComputerFate omega_computer_run(OmegaComputerMachine *machine, const std::vector<int> &program,
                                     const std::string &input, unsigned int depth, const std::string &universal_code,
                                     std::vector<int> &normal)
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
