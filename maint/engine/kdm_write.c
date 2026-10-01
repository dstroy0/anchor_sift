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

// the longest cost a row carries: an exact rational, numerator/denominator, each a run of decimal digits
#define KDM_COST_LONGEST 128u

// One row as it stood in the file the last time: the arrangement, what it has cost, and over how many runs. A cost
// is an exact rational and is carried as the text it was written as. Nothing here computes with one, and a cost read
// into a number to be written back out would be rounded on the way
typedef struct
{
    char text[KDM_TEXT_LONGEST];
    char cost[KDM_COST_LONGEST];
    unsigned int runs;
} KdmRow;

static KdmRow s_held[KDM_ROWS];

// Whether `text` is an exact rational written in decimal: digits, an optional leading minus, and at most one /
// with digits after it
static int kdm_exact_text(const char *text)
{
    unsigned int at = (text[0] == '-') ? 1u : 0u;
    unsigned int digits = 0u;
    unsigned int slashes = 0u;
    for (; text[at] != '\0'; at += 1u)
    {
        if ((text[at] >= '0') && (text[at] <= '9'))
        {
            digits += 1u;
        }
        else if ((text[at] == '/') && (digits != 0u) && (slashes == 0u))
        {
            slashes = 1u;
            digits = 0u;
        }
        else
        {
            return 0;
        }
    }
    return (digits != 0u) ? 1 : 0;
}
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
        char *const cost = at + 1;
        char *const runs = strchr(cost, '\t');
        if (runs == NULL)
        {
            continue;
        }
        *runs = '\0';
        row->runs = (unsigned int)strtoul(runs + 1, NULL, 10);
        // a cost that is not an exact rational of decimal digits is not carried: it is refused, and the row reads
        // as never timed
        if ((kdm_exact_text(cost) == 0) || (strlen(cost) >= sizeof(row->cost)))
        {
            row->runs = 0u;
            row->cost[0] = '\0';
        }
        else
        {
            snprintf(row->cost, sizeof(row->cost), "%s", cost);
        }
        s_held_rows += 1u;
    }
    fclose(file);
}

// the row `text` stood in the last time, or NULL where nothing has timed it
static const KdmRow *kdm_cost(const char *text)
{
    for (unsigned int at = 0u; at < s_held_rows; at += 1u)
    {
        if ((strcmp(s_held[at].text, text) == 0) && (s_held[at].runs != 0u))
        {
            return &s_held[at];
        }
    }
    return NULL;
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
    fprintf(file, "# here. A cost is an exact rational, numerator/denominator in the part's clock count, and a cost\n");
    fprintf(file, "# of - over 0 runs has not been timed on anything.\n");
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
            chain_text(&set.chain[at], text, sizeof(text));
            const KdmRow *const held = kdm_cost(text);
            if (held == NULL)
            {
                fprintf(file, "%s\t%u\t%s\t-\t0\n", s_anchor_text[anchor], set.chain[at].nodes, text);
            }
            else
            {
                fprintf(file, "%s\t%u\t%s\t%s\t%u\n", s_anchor_text[anchor], set.chain[at].nodes, text, held->cost,
                        held->runs);
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
