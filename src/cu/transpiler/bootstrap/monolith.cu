// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// monolith.cu: one program that holds every base primitive (precepts.h), each in its own block between two tags.
// NVIDIA's compiler builds it once, and its listing is the answer key: the instructions between tag n and tag n + 1
// are NVIDIA's writing of precept n, and our compiler's SASS for the same precept is held against them. A chain to a
// larger operator is built from these blocks per the plan.
//
// A tag is a performance-monitor event whose mask is the precept's number plus one, written in the listing as PMTRIG.
// It changes no word and the compiler keeps it in place. Every block loads its operands and stores its answer with
// volatile accesses, and a tag clobbers memory: nothing a block does is moved across a tag. A precept's answer
// follows precept_applied (precept_value.h): a shift takes its count from the low five bits of the right word.
//
//     in[0]   the left word
//     in[1]   the right word
//     in[2]   a flag, 0 on every run: JCC is taken on it and ERR raised on it, and neither is taken where it is 0
//     out[n]  precept n's answer, PRECEPT_COUNT words
//     out[PRECEPT_COUNT], out[PRECEPT_COUNT + 1]  the part's clock across the program, low word then high
//
// The second entry, monolith_cost, reads what each precept costs. A precept is run as a chain, every step taking the
// last one's answer, MONOLITH_BLOCK steps to a turn and `turns` turns, and the part's clock is read before and after.
// The longer the run, the nearer its mean is to what the part does. Every pair of precepts is then run interleaved, two
// chains apart from each other, one step of each in turn: a pair that costs about the dearer of the two alone is one
// the part runs side by side, and one that costs about both together is one it runs one after the other. The words
// come in as the entry's own parameters, and nothing between the two clock reads touches memory.
//
// A step is one PTX instruction put under a predicate read from `flag`, which is 1 on every run. The compiler cannot
// know the predicate, and it folds no chain of the same instruction into fewer: a chain written plainly, even with an
// empty fence after each step, comes out of the assembler as one instruction a turn. A predicated instruction costs
// what the bare one does. A step answers what precept_applied answers, and the runner holds every chain's last word to
// the host's. NOP is no instruction, and MOV a copy of a word onto itself, which the assembler drops: both read what
// the turns cost with nothing in them.
//
//     left, right  the two words; turns  the turns a section runs; flag  1, the predicate every step is put under
//     cycles[s]  section s's clock count, singles first in MONOLITH_COSTED order, then each pair i <= j
//     sink[s]    section s's last word, kept so no chain is dead
#include "monolith.h"

static_assert((PRECEPT_NOP == 0) && (PRECEPT_ERR == 1) && (PRECEPT_NOT == 2) &&
                  (PRECEPT_SUB == (int)MONOLITH_COSTED_COUNT),
              "monolith: the costed run is NOP, then NOT through SUB, with ERR alone left out");

// the tags are in the program where MONOLITH_TAGGED is 1, its default, and out of it where 0. The two builds are held
// against each other for what the tags cost: cycles, and the instructions the compiler keeps apart across a tag
#ifndef MONOLITH_TAGGED
#define MONOLITH_TAGGED 1
#endif

// the tag before precept `precept_`
#if MONOLITH_TAGGED
#define MONOLITH_TAG(precept_) asm volatile("pmevent.mask %0;" ::"n"((precept_) + 1) : "memory")
#else
#define MONOLITH_TAG(precept_) ((void)0)
#endif

// the tag after the last precept
#define MONOLITH_END MONOLITH_TAG(PRECEPT_COUNT)

static __device__ __forceinline__ unsigned int monolith_read(const unsigned int *in, unsigned int place)
{
    return *(volatile const unsigned int *)&in[place];
}

static __device__ __forceinline__ void monolith_write(unsigned int *out, unsigned int place, unsigned int word)
{
    *(volatile unsigned int *)&out[place] = word;
}

// the part's clock, read where it stands: it clobbers memory, and no access is moved across the read
static __device__ __forceinline__ unsigned long long monolith_clock(void)
{
    unsigned long long counted = 0ull;
    asm volatile("mov.u64 %0, %%clock64;" : "=l"(counted)::"memory");
    return counted;
}

extern "C" __global__ void monolith(const unsigned int *in, unsigned int *out)
{
    const unsigned long long began = monolith_clock();

    MONOLITH_TAG(PRECEPT_NOP);
    monolith_write(out, PRECEPT_NOP, monolith_read(in, 0u));

    MONOLITH_TAG(PRECEPT_ERR);
    // raised only where the flag is set: the trap is in the program and no run takes it
    if (monolith_read(in, 2u) != 0u)
    {
        asm volatile("trap;" ::: "memory");
    }
    monolith_write(out, PRECEPT_ERR, 0u);

    MONOLITH_TAG(PRECEPT_NOT);
    monolith_write(out, PRECEPT_NOT, ~monolith_read(in, 0u));

    MONOLITH_TAG(PRECEPT_AND);
    monolith_write(out, PRECEPT_AND, monolith_read(in, 0u) & monolith_read(in, 1u));

    MONOLITH_TAG(PRECEPT_OR);
    monolith_write(out, PRECEPT_OR, monolith_read(in, 0u) | monolith_read(in, 1u));

    MONOLITH_TAG(PRECEPT_XOR);
    monolith_write(out, PRECEPT_XOR, monolith_read(in, 0u) ^ monolith_read(in, 1u));

    MONOLITH_TAG(PRECEPT_NAND);
    monolith_write(out, PRECEPT_NAND, ~(monolith_read(in, 0u) & monolith_read(in, 1u)));

    MONOLITH_TAG(PRECEPT_NOR);
    monolith_write(out, PRECEPT_NOR, ~(monolith_read(in, 0u) | monolith_read(in, 1u)));

    MONOLITH_TAG(PRECEPT_MOV);
    monolith_write(out, PRECEPT_MOV, monolith_read(in, 0u));

    MONOLITH_TAG(PRECEPT_SHL);
    {
        const unsigned int left = monolith_read(in, 0u);
        const unsigned int count = monolith_read(in, 1u) & 31u;
        monolith_write(out, PRECEPT_SHL, (count == 0u) ? left : (left << count));
    }

    MONOLITH_TAG(PRECEPT_SHR);
    {
        const unsigned int left = monolith_read(in, 0u);
        const unsigned int count = monolith_read(in, 1u) & 31u;
        monolith_write(out, PRECEPT_SHR, (count == 0u) ? left : (left >> count));
    }

    MONOLITH_TAG(PRECEPT_ASR);
    {
        const unsigned int left = monolith_read(in, 0u);
        const unsigned int count = monolith_read(in, 1u) & 31u;
        // ASR: the word read as signed carries its sign in from the top; the bits are unchanged
        monolith_write(out, PRECEPT_ASR, (count == 0u) ? left : (unsigned int)((int)left >> count));
    }

    MONOLITH_TAG(PRECEPT_ROL);
    {
        const unsigned int left = monolith_read(in, 0u);
        const unsigned int count = monolith_read(in, 1u) & 31u;
        monolith_write(out, PRECEPT_ROL, (count == 0u) ? left : ((left << count) | (left >> (32u - count))));
    }

    MONOLITH_TAG(PRECEPT_ROR);
    {
        const unsigned int left = monolith_read(in, 0u);
        const unsigned int count = monolith_read(in, 1u) & 31u;
        monolith_write(out, PRECEPT_ROR, (count == 0u) ? left : ((left >> count) | (left << (32u - count))));
    }

    MONOLITH_TAG(PRECEPT_ADD);
    monolith_write(out, PRECEPT_ADD, monolith_read(in, 0u) + monolith_read(in, 1u));

    MONOLITH_TAG(PRECEPT_SUB);
    monolith_write(out, PRECEPT_SUB, monolith_read(in, 0u) - monolith_read(in, 1u));

    MONOLITH_TAG(PRECEPT_BRA);
    // An unconditional jump stays in the program only where something jumps around it: the arm taken on the flag ends
    // in a jump over the other. Each arm holds four stores, more than the compiler writes as predicated stores in
    // place of a branch. With the flag 0 the second arm runs and its last store is the answer, 0
    if (monolith_read(in, 2u) != 0u)
    {
        monolith_write(out, PRECEPT_BRA, 1u);
        monolith_write(out, PRECEPT_BRA, 2u);
        monolith_write(out, PRECEPT_BRA, 3u);
        monolith_write(out, PRECEPT_BRA, 4u);
    }
    else
    {
        monolith_write(out, PRECEPT_BRA, 5u);
        monolith_write(out, PRECEPT_BRA, 6u);
        monolith_write(out, PRECEPT_BRA, 7u);
        monolith_write(out, PRECEPT_BRA, 0u);
    }

    MONOLITH_TAG(PRECEPT_JCC);
    // a jump taken on the flag over four stores, more than the compiler writes as predicated stores in place of a
    // branch. With the flag 0 the stores run and the last is the answer, the left word
    if (monolith_read(in, 2u) == 0u)
    {
        monolith_write(out, PRECEPT_JCC, 1u);
        monolith_write(out, PRECEPT_JCC, 2u);
        monolith_write(out, PRECEPT_JCC, 3u);
        monolith_write(out, PRECEPT_JCC, monolith_read(in, 0u));
    }

    MONOLITH_END;

    const unsigned long long spent = monolith_clock() - began;
    // the count split into its two words, the low word first
    monolith_write(out, PRECEPT_COUNT, (unsigned int)(spent & 0xffffffffull));
    monolith_write(out, PRECEPT_COUNT + 1u, (unsigned int)(spent >> 32u));
}

// a step's instruction put under the predicate the flag names: %0 the word, %1 the right word, %2 the flag, %3 the
// shift count, the right word's low five bits
#define MONOLITH_PREDICATED(instruction_)                                                                              \
    asm volatile("{\n\t.reg .pred taken;\n\tsetp.ne.u32 taken, %2, 0;\n\t" instruction_ "\n\t}"                        \
                 : "+r"(word)                                                                                          \
                 : "r"(right), "r"(flag), "r"(count))

// one step of precept `precept_` on `word`, its answer left in `word`, with `right` the right word and `count` its low
// five bits. A shift's count is masked before it is put, as precept_applied masks it, and a funnel shift of a word with
// itself is a rotate
template <unsigned int precept_>
static __device__ __forceinline__ void monolith_step(unsigned int &word, unsigned int right, unsigned int count,
                                                     unsigned int flag)
{
    switch (precept_)
    {
    case PRECEPT_NOT:
        MONOLITH_PREDICATED("@taken not.b32 %0, %0;");
        break;
    case PRECEPT_AND:
        MONOLITH_PREDICATED("@taken and.b32 %0, %0, %1;");
        break;
    case PRECEPT_OR:
        MONOLITH_PREDICATED("@taken or.b32 %0, %0, %1;");
        break;
    case PRECEPT_XOR:
        MONOLITH_PREDICATED("@taken xor.b32 %0, %0, %1;");
        break;
    case PRECEPT_NAND:
        MONOLITH_PREDICATED("@taken and.b32 %0, %0, %1;\n\t@taken not.b32 %0, %0;");
        break;
    case PRECEPT_NOR:
        MONOLITH_PREDICATED("@taken or.b32 %0, %0, %1;\n\t@taken not.b32 %0, %0;");
        break;
    case PRECEPT_MOV:
        MONOLITH_PREDICATED("@taken mov.b32 %0, %0;");
        break;
    case PRECEPT_SHL:
        MONOLITH_PREDICATED("@taken shl.b32 %0, %0, %3;");
        break;
    case PRECEPT_SHR:
        MONOLITH_PREDICATED("@taken shr.u32 %0, %0, %3;");
        break;
    case PRECEPT_ASR:
        MONOLITH_PREDICATED("@taken shr.s32 %0, %0, %3;");
        break;
    case PRECEPT_ROL:
        MONOLITH_PREDICATED("@taken shf.l.wrap.b32 %0, %0, %0, %3;");
        break;
    case PRECEPT_ROR:
        MONOLITH_PREDICATED("@taken shf.r.wrap.b32 %0, %0, %0, %3;");
        break;
    case PRECEPT_ADD:
        MONOLITH_PREDICATED("@taken add.u32 %0, %0, %1;");
        break;
    case PRECEPT_SUB:
        MONOLITH_PREDICATED("@taken sub.u32 %0, %0, %1;");
        break;
    default:
        // NOP is no instruction
        break;
    }
}


// what every costed section is run with: the two words, the turns, the flag the steps are predicated on, and where
// each section's count and last word are written
typedef struct
{
    unsigned int left;
    unsigned int right;
    unsigned int turns;
    unsigned int flag;
    unsigned long long *cycles;
    unsigned int *sink;
} MonolithRun;

static __device__ __forceinline__ void monolith_count(const MonolithRun &run, unsigned int section,
                                                      unsigned long long spent, unsigned int word)
{
    *(volatile unsigned long long *)&run.cycles[section] = spent;
    monolith_write(run.sink, section, word);
}

// costed place `place_` run alone: one chain, `turns` turns of MONOLITH_BLOCK steps
template <unsigned int place_> static __device__ __forceinline__ void monolith_single(const MonolithRun &run)
{
    const unsigned int right = run.right;
    const unsigned int count = right & 31u;
    unsigned int word = run.left;
    const unsigned long long began = monolith_clock();
    for (unsigned int turn = 0u; turn < run.turns; turn += 1u)
    {
#pragma unroll
        for (unsigned int step = 0u; step < MONOLITH_BLOCK; step += 1u)
        {
            monolith_step<MONOLITH_COSTED(place_)>(word, right, count, run.flag);
        }
    }
    const unsigned long long spent = monolith_clock() - began;
    monolith_count(run, place_, spent, word);
}

// costed places `first_` and `second_` interleaved: two chains apart from each other, a step of each in turn. The
// first chain begins at the left word and takes the right word, the second the other way about
template <unsigned int first_, unsigned int second_>
static __device__ __forceinline__ void monolith_pair(const MonolithRun &run)
{
    const unsigned int left = run.left;
    const unsigned int right = run.right;
    const unsigned int left_count = left & 31u;
    const unsigned int right_count = right & 31u;
    unsigned int one = left;
    unsigned int other = right;
    const unsigned long long began = monolith_clock();
    for (unsigned int turn = 0u; turn < run.turns; turn += 1u)
    {
#pragma unroll
        for (unsigned int step = 0u; step < MONOLITH_BLOCK; step += 1u)
        {
            monolith_step<MONOLITH_COSTED(first_)>(one, right, right_count, run.flag);
            monolith_step<MONOLITH_COSTED(second_)>(other, left, left_count, run.flag);
        }
    }
    const unsigned long long spent = monolith_clock() - began;
    monolith_count(run, MONOLITH_PAIR_SECTION(first_, second_), spent, one ^ other);
}

// every single from costed place `place_` on
template <unsigned int place_> struct MonolithSingles
{
    static __device__ __forceinline__ void run(const MonolithRun &run)
    {
        monolith_single<place_>(run);
        MonolithSingles<place_ + 1u>::run(run);
    }
};

template <> struct MonolithSingles<MONOLITH_COSTED_COUNT>
{
    static __device__ __forceinline__ void run(const MonolithRun &)
    {
    }
};

// every pair from (`first_`, `second_`) on, row by row, each i <= j once
template <unsigned int first_, unsigned int second_> struct MonolithPairs
{
    static __device__ __forceinline__ void run(const MonolithRun &run)
    {
        monolith_pair<first_, second_>(run);
        MonolithPairs<((second_ + 1u) < MONOLITH_COSTED_COUNT) ? first_ : (first_ + 1u),
                      ((second_ + 1u) < MONOLITH_COSTED_COUNT) ? (second_ + 1u) : (first_ + 1u)>::run(run);
    }
};

template <unsigned int second_> struct MonolithPairs<MONOLITH_COSTED_COUNT, second_>
{
    static __device__ __forceinline__ void run(const MonolithRun &)
    {
    }
};

extern "C" __global__ void monolith_cost(unsigned int left, unsigned int right, unsigned int turns, unsigned int flag,
                                         unsigned long long *cycles, unsigned int *sink)
{
    const MonolithRun run = {left, right, turns, flag, cycles, sink};
    MonolithSingles<0u>::run(run);
    MonolithPairs<0u, 0u>::run(run);
}
