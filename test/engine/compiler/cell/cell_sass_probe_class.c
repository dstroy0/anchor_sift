// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cell_sass_probe_class.c: the system's classification, written as <part>.ksc. Every other piece here learns what
// the system holds; this one records how that was learned - which channel each question went out on, and whether
// what came back was an answer, nothing, or a refusal
#include "cell_sass_probe.h"

#include <stdio.h>
#include <string.h>

// the most questions kept whole. The decode channel puts one for every bit of every form, far past this, and is
// counted in place of being kept
#define SASS_CLASSED 512u

static const char *const s_channel_text[SASS_CHANNEL_COUNT] = {
#define SASS_CHANNEL_TEXT(name_, text_, why_) text_,
    SASS_CHANNELS(SASS_CHANNEL_TEXT)
#undef SASS_CHANNEL_TEXT
};

static const char *const s_channel_why[SASS_CHANNEL_COUNT] = {
#define SASS_CHANNEL_WHY(name_, text_, why_) why_,
    SASS_CHANNELS(SASS_CHANNEL_WHY)
#undef SASS_CHANNEL_WHY
};

static const char *const s_class_text[SASS_CLASS_COUNT] = {
#define SASS_CLASS_TEXT(name_, text_, why_) text_,
    SASS_CLASSES(SASS_CLASS_TEXT)
#undef SASS_CLASS_TEXT
};

static const char *const s_class_why[SASS_CLASS_COUNT] = {
#define SASS_CLASS_WHY(name_, text_, why_) why_,
    SASS_CLASSES(SASS_CLASS_WHY)
#undef SASS_CLASS_WHY
};

static SassClassed s_classed[SASS_CLASSED];
static unsigned int s_classed_count;
static unsigned int s_tally[SASS_CHANNEL_COUNT][SASS_CLASS_COUNT];

void sass_class_count(unsigned int channel, unsigned int answered)
{
    if ((channel < SASS_CHANNEL_COUNT) && (answered < SASS_CLASS_COUNT))
    {
        s_tally[channel][answered] += 1u;
    }
}

void sass_class_take(unsigned int channel, unsigned int answered, const char *question, unsigned int word)
{
    sass_class_count(channel, answered);
    if ((s_classed_count >= SASS_CLASSED) || (channel >= SASS_CHANNEL_COUNT) || (answered >= SASS_CLASS_COUNT))
    {
        return;
    }
    SassClassed *const one = &s_classed[s_classed_count];
    one->channel = (unsigned char)channel;
    one->answered = (unsigned char)answered;
    one->word = word;
    // a question of more than one instruction is kept on one line, its instructions joined by a semicolon
    unsigned int at = 0u;
    for (const char *walk = question; (*walk != '\0') && (at < (SASS_TEXT - 1u)); walk += 1)
    {
        one->question[at] = (*walk == '\n') ? ';' : *walk;
        at += 1u;
    }
    one->question[at] = '\0';
    s_classed_count += 1u;
}

int sass_class_write(const char *machines, const char *part)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.ksc", machines, part);
    FILE *const file = fopen(path, "wb");
    if (file == NULL)
    {
        printf("cell sass class: %s could not be written\n", path);
        return 0;
    }
    fprintf(file, "ksc %s\n", part);
    fprintf(file, "# How this system is asked, and what came back. A probe is not a thing of its own: it is a\n");
    fprintf(file, "# question put on one of the channels below and the answer read back. Written by the cell's\n");
    fprintf(file, "# SASS probe; every line here is something the system said, and nothing here was assumed.\n\n");
    fprintf(file, "# the channels this system answers on\n");
    for (unsigned int channel = 0u; channel < SASS_CHANNEL_COUNT; channel += 1u)
    {
        fprintf(file, "channel %-8s %s\n", s_channel_text[channel], s_channel_why[channel]);
    }
    fprintf(file, "\n# what an answer can be\n");
    for (unsigned int answered = 0u; answered < SASS_CLASS_COUNT; answered += 1u)
    {
        fprintf(file, "class %-8s %s\n", s_class_text[answered], s_class_why[answered]);
    }
    fprintf(file, "\n# every question put, counted by the channel it went out on and what came back\n");
    for (unsigned int channel = 0u; channel < SASS_CHANNEL_COUNT; channel += 1u)
    {
        for (unsigned int answered = 0u; answered < SASS_CLASS_COUNT; answered += 1u)
        {
            fprintf(file, "count %-8s %-8s %u\n", s_channel_text[channel], s_class_text[answered],
                    s_tally[channel][answered]);
        }
    }
    fprintf(file, "\n# every question the system was asked in its own code, one a line: the channel, what came\n");
    fprintf(file, "# back, the word it answered, and the question. These are the ones the system answered for\n");
    fprintf(file, "# itself, with no compiler and no disassembler standing between.\n");
    for (unsigned int number = 0u; number < s_classed_count; number += 1u)
    {
        const SassClassed *const one = &s_classed[number];
        fprintf(file, "%s %s %08x %s\n", s_channel_text[one->channel], s_class_text[one->answered], one->word,
                one->question);
    }
    const int closed = (fclose(file) == 0);
    printf("cell sass class: %s written, %u questions kept whole\n", path, s_classed_count);
    return closed;
}
