// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// monolith_run.c: the monolith's cubin (monolith.cu) loaded as it was built and run on the part. Nothing is compiled
// here: the driver is handed the cubin and asked for its entries.
//
// The first entry answers every precept for each case, held against precept_applied on the host, and the part's clock
// across it is read on every run. The second runs every costed precept as a chain of `turns` turns of MONOLITH_BLOCK
// steps, alone and then interleaved with every other, and the mean of `cost runs` runs is read a step. Every chain's
// last word is held against the same chain run through precept_applied on the host, which says every step ran.
//
//     monolith_run <cubin> [runs] [turns] [cost runs]
#include "../../../../../../src/c/transpiler/codegen/precept_value.h"
#include "../../../../../../src/cu/transpiler/bootstrap/monolith.h"

#include <cuda.h>
#include <stdio.h>
#include <stdlib.h>

// the words the first entry reads: the left word, the right word and the flag, which is 0 on every run
#define MONOLITH_IN_WORDS 3u
// the words it writes: every precept's answer, then the clock's two words
#define MONOLITH_OUT_WORDS (PRECEPT_COUNT + 2u)

// the words every costed chain is run with. The right word's low five bits, 25, are a shift's count, and the left
// word's, 15, are the count of a pair's second chain
#define MONOLITH_COST_LEFT 0xdeadbeefu
#define MONOLITH_COST_RIGHT 0x9e3779b9u

// a pair costs about the dearer of its two alone, past this share of the cheaper, where the part runs them side by
// side, and about both together, past the share below it, where the part runs them one after the other
#define MONOLITH_SIDE_BY_SIDE 0.25
#define MONOLITH_ONE_AFTER 0.75

#define MONOLITH_NAMED(name_, text_, arity_) text_,

static const char *const s_names[PRECEPT_COUNT] = {PRECEPTS(MONOLITH_NAMED)};

static unsigned int s_checks = 0u;
static unsigned int s_failed = 0u;

static void check_that(int held, const char *what, unsigned int precept, unsigned int left, unsigned int right)
{
    s_checks += 1u;
    if (held == 0)
    {
        s_failed += 1u;
        printf("  FAILED: %s, precept %u, left %08x, right %08x\n", what, precept, left, right);
    }
}

static unsigned char *monolith_file(const char *path)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return NULL;
    }
    fseek(file, 0L, SEEK_END);
    const long size = ftell(file);
    fseek(file, 0L, SEEK_SET);
    // a size the file reported is at least 0, and a byte past it ends the image
    unsigned char *const bytes = (size > 0L) ? (unsigned char *)malloc((size_t)size + 1u) : NULL;
    const int read = (bytes != NULL) && (fread(bytes, 1u, (size_t)size, file) == (size_t)size);
    fclose(file);
    if (read == 0)
    {
        free(bytes);
        return NULL;
    }
    return bytes;
}

// the word precept `precept` must answer for `left` and `right` with the flag 0: the host's precept_applied, except
// JCC, whose jump is not taken and whose last store is the left word
static unsigned int monolith_expected(unsigned int precept, unsigned int left, unsigned int right)
{
    return (precept == PRECEPT_JCC) ? left : precept_applied((unsigned char)precept, left, right);
}

// `word` put through `steps` steps of `precept` with `right` the right word, on the host
static unsigned int monolith_chain(unsigned int precept, unsigned int word, unsigned int right, unsigned long long steps)
{
    unsigned int held = word;
    for (unsigned long long step = 0ull; step < steps; step += 1ull)
    {
        held = precept_applied((unsigned char)precept, held, right);
    }
    return held;
}

// a count of the words given, read as at least one
static unsigned int monolith_count_given(int count_of_words, char **words, int place, long otherwise)
{
    const long asked = (count_of_words > place) ? strtol(words[place], NULL, 10) : otherwise;
    return (asked > 0L) ? (unsigned int)asked : 1u;
}

// every precept answered for each case and held against the host, the clock across the program read
static int monolith_answers(CUfunction entry, CUdeviceptr in, CUdeviceptr out, unsigned int runs, const char *cubin)
{
    // small words, a shift of nothing, of one, of the width less one and of past the width, and the sign's end
    static const unsigned int cases[][2] = {
        {1u, 1u}, {0u, 0u}, {3u, 5u}, {0xdeadbeefu, 0u}, {0xdeadbeefu, 1u}, {0xdeadbeefu, 31u},
        {0xdeadbeefu, 33u}, {0x80000000u, 4u}, {0x7fffffffu, 1u}, {0xffffffffu, 0x12345678u},
    };
    const unsigned int case_count = (unsigned int)(sizeof(cases) / sizeof(cases[0]));
    unsigned long long least = ~0ull;
    unsigned long long most = 0ull;
    for (unsigned int at = 0u; at < case_count; at += 1u)
    {
        const unsigned int given[MONOLITH_IN_WORDS] = {cases[at][0], cases[at][1], 0u};
        unsigned int answered[MONOLITH_OUT_WORDS] = {0u};
        for (unsigned int run = 0u; run < runs; run += 1u)
        {
            void *arguments[2] = {&in, &out};
            const int ran = (cuMemcpyHtoD(in, given, sizeof(given)) == CUDA_SUCCESS) &&
                            (cuLaunchKernel(entry, 1u, 1u, 1u, 1u, 1u, 1u, 0u, NULL, arguments, NULL) == CUDA_SUCCESS) &&
                            (cuCtxSynchronize() == CUDA_SUCCESS) &&
                            (cuMemcpyDtoH(answered, out, sizeof(answered)) == CUDA_SUCCESS);
            if (ran == 0)
            {
                fprintf(stderr, "  monolith: a run of the answers did not complete on the part\n");
                return 0;
            }
            const unsigned long long spent =
                (unsigned long long)answered[PRECEPT_COUNT] | ((unsigned long long)answered[PRECEPT_COUNT + 1u] << 32u);
            least = (spent < least) ? spent : least;
            most = (spent > most) ? spent : most;
        }
        for (unsigned int precept = 0u; precept < PRECEPT_COUNT; precept += 1u)
        {
            check_that(answered[precept] == monolith_expected(precept, given[0], given[1]),
                       "the part's answer is the host's", precept, given[0], given[1]);
        }
    }
    printf("  monolith %s: %u cases, %u runs a case, the program %llu cycles at least, %llu at most\n", cubin,
           case_count, runs, least, most);
    return 1;
}

// every costed chain run alone and interleaved, `cost_runs` times, each its mean a step, and every last word held
// against the host's
static int monolith_costs(CUfunction entry, unsigned int turns, unsigned int cost_runs)
{
    CUdeviceptr cycles = 0u;
    CUdeviceptr sink = 0u;
    if ((cuMemAlloc(&cycles, MONOLITH_SECTIONS * sizeof(unsigned long long)) != CUDA_SUCCESS) ||
        (cuMemAlloc(&sink, MONOLITH_SECTIONS * sizeof(unsigned int)) != CUDA_SUCCESS))
    {
        fprintf(stderr, "  monolith: the costs' words were not allocated on the part\n");
        return 0;
    }
    // each section's counts over the runs: their sum, the least and the most
    static double s_spent[MONOLITH_SECTIONS];
    static unsigned long long s_least[MONOLITH_SECTIONS];
    static unsigned long long s_most[MONOLITH_SECTIONS];
    for (unsigned int section = 0u; section < MONOLITH_SECTIONS; section += 1u)
    {
        s_least[section] = ~0ull;
    }
    unsigned int last[MONOLITH_SECTIONS] = {0u};
    unsigned int left = MONOLITH_COST_LEFT;
    unsigned int right = MONOLITH_COST_RIGHT;
    unsigned int flag = 1u;
    for (unsigned int run = 0u; run < cost_runs; run += 1u)
    {
        unsigned long long counted[MONOLITH_SECTIONS] = {0ull};
        void *arguments[6] = {&left, &right, &turns, &flag, &cycles, &sink};
        const int ran = (cuLaunchKernel(entry, 1u, 1u, 1u, 1u, 1u, 1u, 0u, NULL, arguments, NULL) == CUDA_SUCCESS) &&
                        (cuCtxSynchronize() == CUDA_SUCCESS) &&
                        (cuMemcpyDtoH(counted, cycles, sizeof(counted)) == CUDA_SUCCESS) &&
                        (cuMemcpyDtoH(last, sink, sizeof(last)) == CUDA_SUCCESS);
        if (ran == 0)
        {
            fprintf(stderr, "  monolith: a run of the costs did not complete on the part\n");
            return 0;
        }
        for (unsigned int section = 0u; section < MONOLITH_SECTIONS; section += 1u)
        {
            s_spent[section] += (double)counted[section];
            s_least[section] = (counted[section] < s_least[section]) ? counted[section] : s_least[section];
            s_most[section] = (counted[section] > s_most[section]) ? counted[section] : s_most[section];
        }
    }
    cuMemFree(cycles);
    cuMemFree(sink);

    // every chain run on the host: each costed precept from the left word on the right word, which a single and a
    // pair's first chain run, and from the right word on the left word, which a pair's second chain runs
    const unsigned long long steps = (unsigned long long)turns * (unsigned long long)MONOLITH_BLOCK;
    unsigned int forward[MONOLITH_COSTED_COUNT];
    unsigned int backward[MONOLITH_COSTED_COUNT];
    for (unsigned int place = 0u; place < MONOLITH_COSTED_COUNT; place += 1u)
    {
        forward[place] = monolith_chain(MONOLITH_COSTED(place), left, right, steps);
        backward[place] = monolith_chain(MONOLITH_COSTED(place), right, left, steps);
        check_that(last[place] == forward[place], "a chain run alone ends on the host's word", MONOLITH_COSTED(place),
                   left, right);
    }
    for (unsigned int first = 0u; first < MONOLITH_COSTED_COUNT; first += 1u)
    {
        for (unsigned int second = first; second < MONOLITH_COSTED_COUNT; second += 1u)
        {
            check_that(last[MONOLITH_PAIR_SECTION(first, second)] == (forward[first] ^ backward[second]),
                       "two chains interleaved end on the host's words", MONOLITH_COSTED(first), left, right);
        }
    }

    // every section read a step, past NOP's turns read the same way: its mean, its least m, and its spread s, the most
    // less the least, over the runs (P6 in query_protocol_table.md)
    const double chain = (double)steps;
    const double bare_mean = (s_spent[0] / (double)cost_runs) / chain;
    const double bare_least = (double)s_least[0] / chain;
    static double s_mean[MONOLITH_SECTIONS];
    static double s_m[MONOLITH_SECTIONS];
    static double s_s[MONOLITH_SECTIONS];
    for (unsigned int section = 0u; section < MONOLITH_SECTIONS; section += 1u)
    {
        s_mean[section] = ((s_spent[section] / (double)cost_runs) / chain) - bare_mean;
        s_m[section] = ((double)s_least[section] / chain) - bare_least;
        s_s[section] = (double)(s_most[section] - s_least[section]) / chain;
    }
    printf("  monolith costs: %u turns of %u steps a section, %llu steps a chain, %u runs\n", turns, MONOLITH_BLOCK,
           steps, cost_runs);
    printf("  NOP's turns cost %.4f cycles a step with nothing in them, and every figure below is past that\n",
           bare_mean);
    printf("  alone, cycles a step     mean   least m  spread s\n");
    double spread_alone = 0.0;
    for (unsigned int place = 0u; place < MONOLITH_COSTED_COUNT; place += 1u)
    {
        printf("    %-5s           %8.4f  %8.4f  %8.4f\n", s_names[MONOLITH_COSTED(place)], s_mean[place], s_m[place],
               s_s[place]);
        spread_alone = (s_s[place] > spread_alone) ? s_s[place] : spread_alone;
    }
    printf("  s alone, the largest spread of the singles: %.4f\n", spread_alone);

    // The singles ranked by their least, each delta to the next read as a state of gnascor's branch pair. Inside s the
    // two are one cost, a slice inside the floor, DUAL or GRAY (which of the two is gnascor's Open 4). Past s the row's
    // precept is the cheaper side and holds: LEAD
    unsigned int order[MONOLITH_COSTED_COUNT];
    for (unsigned int place = 0u; place < MONOLITH_COSTED_COUNT; place += 1u)
    {
        unsigned int at = place;
        while ((at > 0u) && (s_m[order[at - 1u]] > s_m[place]))
        {
            order[at] = order[at - 1u];
            at -= 1u;
        }
        order[at] = place;
    }
    printf("  alone, ranked by least m, each delta to the next read against s: DUAL/GRAY inside it, LEAD past it\n");
    for (unsigned int rank = 0u; rank < MONOLITH_COSTED_COUNT; rank += 1u)
    {
        const unsigned int place = order[rank];
        if ((rank + 1u) == MONOLITH_COSTED_COUNT)
        {
            printf("    %-5s %8.4f\n", s_names[MONOLITH_COSTED(place)], s_m[place]);
            continue;
        }
        const unsigned int next = order[rank + 1u];
        const double delta = s_m[next] - s_m[place];
        printf("    %-5s %8.4f  +%.4f to %-5s %s\n", s_names[MONOLITH_COSTED(place)], s_m[place], delta,
               s_names[MONOLITH_COSTED(next)], (delta > spread_alone) ? "LEAD" : "DUAL/GRAY");
    }

    // the pairs by their least, against the singles' least
    const double *const alone = s_m;
    double spread_pairs = 0.0;
    printf("  interleaved, least m a step of each, the row's precept with the column's:\n       ");
    for (unsigned int second = 0u; second < MONOLITH_COSTED_COUNT; second += 1u)
    {
        printf(" %6s", s_names[MONOLITH_COSTED(second)]);
    }
    printf("\n");
    unsigned int side_by_side = 0u;
    unsigned int one_after = 0u;
    unsigned int between = 0u;
    for (unsigned int first = 0u; first < MONOLITH_COSTED_COUNT; first += 1u)
    {
        printf("    %-5s", s_names[MONOLITH_COSTED(first)]);
        for (unsigned int second = 0u; second < MONOLITH_COSTED_COUNT; second += 1u)
        {
            if (second < first)
            {
                printf(" %6s", "");
                continue;
            }
            const unsigned int section = MONOLITH_PAIR_SECTION(first, second);
            const double paired = s_m[section];
            spread_pairs = (s_s[section] > spread_pairs) ? s_s[section] : spread_pairs;
            printf(" %6.2f", paired);
            const double dearer = (alone[first] > alone[second]) ? alone[first] : alone[second];
            const double cheaper = (alone[first] > alone[second]) ? alone[second] : alone[first];
            // a pair is read only where both its precepts cost a cycle a step or more alone
            if (cheaper >= 1.0)
            {
                const double share = (paired - dearer) / cheaper;
                side_by_side += (share < MONOLITH_SIDE_BY_SIDE) ? 1u : 0u;
                one_after += (share > MONOLITH_ONE_AFTER) ? 1u : 0u;
                between += ((share >= MONOLITH_SIDE_BY_SIDE) && (share <= MONOLITH_ONE_AFTER)) ? 1u : 0u;
            }
        }
        printf("\n");
    }
    printf("  of the pairs whose precepts each cost a cycle a step or more: %u run side by side, %u one after the other, "
           "%u between\n",
           side_by_side, one_after, between);
    printf("  s interleaved, the largest spread of the pairs: %.4f\n", spread_pairs);
    return 1;
}

int main(int count_of_words, char **words)
{
    if ((count_of_words < 2) || (count_of_words > 5))
    {
        fprintf(stderr, "monolith_run <cubin> [runs] [turns] [cost runs]\n");
        return 2;
    }
    const unsigned int runs = monolith_count_given(count_of_words, words, 2, 64L);
    const unsigned int turns = monolith_count_given(count_of_words, words, 3, 10000L);
    const unsigned int cost_runs = monolith_count_given(count_of_words, words, 4, 8L);
    unsigned char *const image = monolith_file(words[1]);
    CUdevice device = 0;
    CUcontext context = NULL;
    CUmodule module = NULL;
    CUfunction answers = NULL;
    CUfunction costs = NULL;
    CUdeviceptr in = 0u;
    CUdeviceptr out = 0u;
    const int opened = (image != NULL) && (cuInit(0u) == CUDA_SUCCESS) && (cuDeviceGet(&device, 0) == CUDA_SUCCESS) &&
                       (cuDevicePrimaryCtxRetain(&context, device) == CUDA_SUCCESS) &&
                       (cuCtxSetCurrent(context) == CUDA_SUCCESS) && (cuModuleLoadData(&module, image) == CUDA_SUCCESS) &&
                       (cuModuleGetFunction(&answers, module, "monolith") == CUDA_SUCCESS) &&
                       (cuModuleGetFunction(&costs, module, "monolith_cost") == CUDA_SUCCESS) &&
                       (cuMemAlloc(&in, MONOLITH_IN_WORDS * sizeof(unsigned int)) == CUDA_SUCCESS) &&
                       (cuMemAlloc(&out, MONOLITH_OUT_WORDS * sizeof(unsigned int)) == CUDA_SUCCESS);
    if (opened == 0)
    {
        fprintf(stderr, "  monolith: the cubin %s was not loaded on the part\n", words[1]);
        return 1;
    }
    const int answered = monolith_answers(answers, in, out, runs, words[1]);
    const int costed = (answered != 0) && monolith_costs(costs, turns, cost_runs);
    printf("  monolith: %u checks, %u failed\n", s_checks, s_failed);
    cuMemFree(in);
    cuMemFree(out);
    cuModuleUnload(module);
    cuDevicePrimaryCtxRelease(device);
    free(image);
    return ((costed != 0) && (s_failed == 0u)) ? 0 : 1;
}
