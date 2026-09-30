// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// kdm_write.c: writes a part's .kdm, the arrangements of primitives that produce each operator
//
//   kdm_write <part> <path>
//
// The arrangements are found from the relations and from nothing else: no ruleset is read, no machine file is read,
// and no target is asked. What a target can write of them, and what each costs it, is the other half and is filled
// by the part itself.
//
// Where the path already holds a .kdm, its costs come forward onto the arrangements found this time, matched by the
// arrangement and never by where it sat in the file. A cost is therefore kept across a rewrite, and a rewrite that
// finds an arrangement nobody has timed leaves it untimed.
#include "../../src/engine/compiler/bootstrap/chain_build.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define KDM_TEXT_LONGEST 160u
#define KDM_ROWS (LADDER_ANCHOR_COUNT * CHAIN_MOST)

#define LADDER_TEXT(name_, text_, words_, measured_) text_,
static const char *const s_anchor_text[] = {LADDER_ANCHORS(LADDER_TEXT)};
#undef LADDER_TEXT

// one row as it stood in the file the last time: the arrangement, what it has cost, and over how many runs
typedef struct
{
    char text[KDM_TEXT_LONGEST];
    double cost;
    unsigned int runs;
} KdmRow;

static KdmRow s_held[KDM_ROWS];
static unsigned int s_held_rows;

// the rows of `path` into s_held. A path that holds nothing is a first run and not a failure
static void kdm_read(const char *path)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return;
    }
    char line[512];
    while (fgets(line, sizeof(line), file) != NULL)
    {
        if ((line[0] == '#') || (line[0] == '\n') || (line[0] == '\r') || (s_held_rows == KDM_ROWS))
        {
            continue;
        }
        // operator, nodes, chain, cost, runs
        char *at = strchr(line, '\t');
        at = (at != NULL) ? strchr(at + 1, '\t') : NULL;
        if (at == NULL)
        {
            continue;
        }
        char *const chain = at + 1;
        at = strchr(chain, '\t');
        if (at == NULL)
        {
            continue;
        }
        *at = '\0';
        KdmRow *const row = &s_held[s_held_rows];
        snprintf(row->text, sizeof(row->text), "%s", chain);
        row->cost = strtod(at + 1, NULL);
        const char *const runs = strchr(at + 1, '\t');
        row->runs = (runs != NULL) ? (unsigned int)strtoul(runs + 1, NULL, 10) : 0u;
        s_held_rows += 1u;
    }
    fclose(file);
}

// what `text` has cost and over how many runs, through `cost` and `runs`; zeroes where nothing has timed it
static void kdm_cost(const char *text, double *cost, unsigned int *runs)
{
    *cost = 0.0;
    *runs = 0u;
    for (unsigned int at = 0u; at < s_held_rows; at += 1u)
    {
        if (strcmp(s_held[at].text, text) == 0)
        {
            *cost = s_held[at].cost;
            *runs = s_held[at].runs;
            return;
        }
    }
}

// the cases of `anchor`, into `held`; the count found
static unsigned int anchor_cases(unsigned int anchor, LadderQuestion *held)
{
    unsigned int found = 0u;
    for (unsigned int at = 0u; at < LADDER_CASE_COUNT; at += 1u)
    {
        if (s_ladder_cases[at].anchor == anchor)
        {
            held[found] = s_ladder_cases[at];
            found += 1u;
        }
    }
    return found;
}

// A seed the file's own state decides, from the part's name and the runs already folded into it. Nothing has to be
// timed for an order to be reproducible, and nothing stays in one order once timings come in
static unsigned int kdm_seed(const char *part)
{
    unsigned int seed = 0x9e3779b9u;
    for (unsigned int at = 0u; part[at] != '\0'; at += 1u)
    {
        seed = (seed * 131u) + (unsigned char)part[at];
    }
    for (unsigned int at = 0u; at < s_held_rows; at += 1u)
    {
        seed += s_held[at].runs;
    }
    return seed;
}

int main(int count, char **word)
{
    if (count < 3)
    {
        printf("kdm_write <part> <path>\n");
        return 2;
    }
    const char *const part = word[1];
    kdm_read(word[2]);
    const unsigned int seed = kdm_seed(part);
    FILE *const file = fopen(word[2], "wb");
    if (file == NULL)
    {
        printf("  kdm_write: %s could not be written\n", word[2]);
        return 1;
    }
    fprintf(file, "kdm %s\n", part);
    fprintf(file, "# Every arrangement of primitives that produces an operator, and what each costs this part.\n");
    fprintf(file, "# Found from the relations alone. No ruleset, no machine file and no naming went into a row\n");
    fprintf(file, "# here. A cost of - over 0 runs has not been timed on anything.\n");
    fprintf(file, "#\n");
    fprintf(file, "# The rows of an operator are in no order. Timed in the order they were found, a chain's\n");
    fprintf(file, "# reading carries where it sat and not what it costs; shuffled, that washes out over runs and\n");
    fprintf(file, "# what is left is the difference between the arrangements. The order moves whenever a run is\n");
    fprintf(file, "# folded in, which is why it moves and a cost does not.\n\n");
    fprintf(file, "# operator\tnodes\tchain\tcost\truns\n");

    static ChainSet set;
    static LadderQuestion cases[LADDER_CASE_COUNT];
    char text[KDM_TEXT_LONGEST];
    unsigned int written = 0u;
    unsigned int timed = 0u;
    for (unsigned int anchor = 0u; anchor < (unsigned int)LADDER_ANCHOR_COUNT; anchor += 1u)
    {
        const unsigned int found = anchor_cases(anchor, cases);
        if (found == 0u)
        {
            continue;
        }
        const unsigned int chains = chain_build(&set, cases, found);
        chain_shuffle(&set, seed + anchor);
        printf("  %-8s %2u cases  %5u chains  %8u tried", s_anchor_text[anchor], found, chains, set.tried);
        printf("%s\n", (set.over != 0u) ? "  and more than the set holds" : "");
        for (unsigned int at = 0u; at < chains; at += 1u)
        {
            double cost = 0.0;
            unsigned int runs = 0u;
            chain_text(&set.chain[at], text, sizeof(text));
            kdm_cost(text, &cost, &runs);
            if (runs == 0u)
            {
                fprintf(file, "%s\t%u\t%s\t-\t0\n", s_anchor_text[anchor], set.chain[at].nodes, text);
            }
            else
            {
                fprintf(file, "%s\t%u\t%s\t%.4f\t%u\n", s_anchor_text[anchor], set.chain[at].nodes, text, cost, runs);
                timed += 1u;
            }
            written += 1u;
        }
        if (chains == 0u)
        {
            // an operator no arrangement of this length reaches. Saying so is the point: it is what the part has to
            // be asked about outright, or what a longer chain has to be found for
            fprintf(file, "%s\t0\t-\t-\t0\n", s_anchor_text[anchor]);
        }
    }
    fclose(file);
    printf("  kdm_write: %u chains into %s, %u of them timed\n", written, word[2], timed);
    return 0;
}
