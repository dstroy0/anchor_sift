// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// interface_sass_probe_class.c: the system's classification, written as <part>.ksc. Every other piece here learns what
// the system holds; this one records how that was learned - which channel each question went out on, and whether
// what came back was an answer, nothing, or a refusal
#include "../../../../../utils/test/src/c/transpiler/interface/interface_sass_probe.h"

#include <stdio.h>
#include <stdlib.h>
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

// the writings the system answers alike, two operations a side
#define SASS_EQUALS 256u
typedef struct
{
    char one[SASS_TEXT];
    char other[SASS_TEXT];
} SassEqual;
static SassEqual s_equal[SASS_EQUALS];
static unsigned int s_equal_count;

static void sass_text_copy(char *into, const char *from)
{
    unsigned int at = 0u;
    for (; (from[at] != '\0') && (at < (SASS_TEXT - 1u)); at += 1u)
    {
        into[at] = from[at];
    }
    into[at] = '\0';
}

int sass_equal_held(const char *one, const char *other)
{
    for (unsigned int number = 0u; number < s_equal_count; number += 1u)
    {
        const int straight = (strcmp(s_equal[number].one, one) == 0) && (strcmp(s_equal[number].other, other) == 0);
        const int crossed = (strcmp(s_equal[number].one, other) == 0) && (strcmp(s_equal[number].other, one) == 0);
        if (straight || crossed)
        {
            return 1;
        }
    }
    return 0;
}

void sass_equal_take(const char *one, const char *other)
{
    if ((s_equal_count >= SASS_EQUALS) || sass_equal_held(one, other))
    {
        return;
    }
    sass_text_copy(s_equal[s_equal_count].one, one);
    sass_text_copy(s_equal[s_equal_count].other, other);
    s_equal_count += 1u;
}

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

// the channel or class named `text`, or the count where none names it
static unsigned int sass_channel_of(const char *text)
{
    for (unsigned int channel = 0u; channel < SASS_CHANNEL_COUNT; channel += 1u)
    {
        if (strcmp(s_channel_text[channel], text) == 0)
        {
            return channel;
        }
    }
    return SASS_CHANNEL_COUNT;
}

static unsigned int sass_class_of(const char *text)
{
    for (unsigned int answered = 0u; answered < SASS_CLASS_COUNT; answered += 1u)
    {
        if (strcmp(s_class_text[answered], text) == 0)
        {
            return answered;
        }
    }
    return SASS_CLASS_COUNT;
}

int sass_class_read(const char *machines, const char *part)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.ksc", machines, part);
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return 0;
    }
    char line[SASS_TEXT * 2u];
    while (fgets(line, sizeof(line), file) != NULL)
    {
        char channel_text[16];
        char class_text[16];
        char question[SASS_TEXT];
        unsigned int word = 0u;
        unsigned int tally = 0u;
        if (sscanf(line, "count %15s %15s %u", channel_text, class_text, &tally) == 3)
        {
            const unsigned int channel = sass_channel_of(channel_text);
            const unsigned int answered = sass_class_of(class_text);
            // a compile pass's folds are its own and are regenerated, never read back as a count
            if ((channel < SASS_CHANNEL_COUNT) && (answered < SASS_CLASS_COUNT) && (answered != SASS_CLASS_FOLDS))
            {
                s_tally[channel][answered] = tally;
            }
            continue;
        }
        if (sscanf(line, "%15s %15s %8x %191[^\n]", channel_text, class_text, &word, question) == 4)
        {
            const unsigned int channel = sass_channel_of(channel_text);
            const unsigned int answered = sass_class_of(class_text);
            if ((channel < SASS_CHANNEL_COUNT) && (answered < SASS_CLASS_COUNT) && (answered != SASS_CLASS_FOLDS) &&
                (s_classed_count < SASS_CLASSED))
            {
                SassClassed *const one = &s_classed[s_classed_count];
                one->channel = (unsigned char)channel;
                one->answered = (unsigned char)answered;
                one->word = word;
                sass_text_copy(one->question, question);
                s_classed_count += 1u;
            }
        }
    }
    fclose(file);
    return 1;
}

int sass_class_write(const char *machines, const char *part)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.ksc", machines, part);
    FILE *const file = fopen(path, "wb");
    if (file == NULL)
    {
        printf("interface sass class: %s could not be written\n", path);
        return 0;
    }
    fprintf(file, "ksc %s\n", part);
    fprintf(file, "# How this system is asked, and what came back. A probe is not a thing of its own: it is a\n");
    fprintf(file, "# question put on one of the channels below and the answer read back. Written by the interface's\n");
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
    fprintf(file, "\n# writings the system answers alike: an operation written where the ruleset holds the other, each\n");
    fprintf(file, "# giving the same machine code. A reading in one is the ruleset's form in the other.\n");
    for (unsigned int number = 0u; number < s_equal_count; number += 1u)
    {
        fprintf(file, "equal %s %s\n", s_equal[number].one, s_equal[number].other);
    }
    const int closed = (fclose(file) == 0);
    printf("interface sass class: %s written, %u questions kept whole\n", path, s_classed_count);
    return closed;
}
