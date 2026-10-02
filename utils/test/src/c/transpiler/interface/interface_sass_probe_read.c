// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// interface_sass_probe_read.c: running the disassembler through the interface and reading what it printed
#include "interface_sass_probe.h"

#include <stdlib.h>
#include <string.h>

// the output a process gives, a cubin's whole listing with its encodings
#define SASS_OUTPUT_CAPACITY (4u * 1024u * 1024u)
// a process's limit: one disassembly
#define SASS_LIMIT 120000000ull

static char s_sass_output[SASS_OUTPUT_CAPACITY];

int sass_run(char *const *command, const char *output_path)
{
    const InterfaceProbe probe = {command, output_path, SASS_LIMIT};
    InterfaceAnswer answer;
    memset(&answer, 0, sizeof(answer));
    answer.output = s_sass_output;
    answer.output_capacity = sizeof(s_sass_output);
    EngineError error;
    memset(&error, 0, sizeof(error));
    if (interface_probe_run(&probe, &answer, &error) != 0L)
    {
        printf("  %s: the interface failed, module %d site %u status %d\n", command[0], (int)error.module, error.site,
               error.status);
        return -1;
    }
    if (answer.output_bytes >= (unsigned long long)sizeof(s_sass_output))
    {
        printf("  %s: %llu bytes of output, more than the %u read\n", command[0], answer.output_bytes,
               SASS_OUTPUT_CAPACITY);
        return -1;
    }
    if (answer.ending != INTERFACE_ENDING_EXITED)
    {
        printf("  %s: %s, code %llu, fault %s\n", command[0], interface_ending_name(answer.ending), answer.code,
               interface_fault_name(answer.fault));
        return -1;
    }
    // an exit status the interface read as exited is a process's own, which fits an int
    return (int)answer.code;
}

const char *sass_output(void)
{
    return s_sass_output;
}

// the length of the address comment "/*0a50*/" at `text`, 0 where there is none
static size_t sass_address_length(const char *text)
{
    if ((text[0] != '/') || (text[1] != '*'))
    {
        return 0u;
    }
    size_t digits = 0u;
    while ((text[2u + digits] != '\0') && (strchr("0123456789abcdef", text[2u + digits]) != NULL))
    {
        digits += 1u;
    }
    return ((digits >= 4u) && (text[2u + digits] == '*') && (text[3u + digits] == '/')) ? (4u + digits) : 0u;
}

// the encoding word in the comment "/* 0x0000000500057210 */" at or after `text` on its line; 0 and `found` 0 where
// there is none
static unsigned long long sass_word_read(const char *text, const char *line_end, int *found)
{
    const char *const start = strstr(text, "/* 0x");
    *found = (start != NULL) && (start < line_end);
    return *found ? strtoull(start + 5, NULL, 16) : 0ull;
}

int sass_listing_read(const char *output, SassListing *listing)
{
    listing->count = 0u;
    int encoded = 0;
    const char *line = output;
    while (*line != '\0')
    {
        const char *const newline = strchr(line, '\n');
        const char *const line_end = (newline != NULL) ? newline : (line + strlen(line));
        const char *address = line;
        size_t address_length = 0u;
        while ((address < line_end) && (address_length == 0u))
        {
            address_length = sass_address_length(address);
            address += (address_length == 0u) ? 1 : 0;
        }
        if (address_length != 0u)
        {
            if (listing->count == SASS_LISTING_LIMIT)
            {
                return 0;
            }
            SassInstruction *const instruction = &listing->instructions[listing->count];
            listing->count += 1u;
            instruction->address = strtoull(address + 2, NULL, 16);
            const char *text = address + address_length;
            while ((text < line_end) && (*text == ' '))
            {
                text += 1;
            }
            const char *end = text;
            while ((end < line_end) && (*end != ';'))
            {
                end += 1;
            }
            const char *const semicolon = end;
            while ((end > text) && (end[-1] == ' '))
            {
                end -= 1;
            }
            // the text runs from its start to the ';', which lies past it
            size_t length = (size_t)(end - text);
            length = (length < (SASS_TEXT - 1u)) ? length : (SASS_TEXT - 1u);
            memcpy(instruction->text, text, length);
            instruction->text[length] = '\0';
            instruction->low = sass_word_read(semicolon, line_end, &encoded);
            instruction->high = 0ull;
        }
        else if (encoded && (listing->count != 0u))
        {
            int found = 0;
            const unsigned long long high = sass_word_read(line, line_end, &found);
            listing->instructions[listing->count - 1u].high = found ? high : 0ull;
            encoded = 0;
        }
        line = (newline != NULL) ? (newline + 1) : line_end;
    }
    return 1;
}

// `length` characters of `text` into `into`, cut to its capacity, spaces trimmed from both ends
static void sass_token_copy(char *into, const char *text, size_t length)
{
    while ((length != 0u) && (*text == ' '))
    {
        text += 1;
        length -= 1u;
    }
    while ((length != 0u) && (text[length - 1u] == ' '))
    {
        length -= 1u;
    }
    length = (length < (SASS_OPERAND_TEXT - 1u)) ? length : (SASS_OPERAND_TEXT - 1u);
    memcpy(into, text, length);
    into[length] = '\0';
}

void sass_parts_read(const char *text, SassParts *parts)
{
    memset(parts, 0, sizeof(*parts));
    while (*text == ' ')
    {
        text += 1;
    }
    if (*text == '@')
    {
        const size_t length = strcspn(text, " ");
        sass_token_copy(parts->predicate, text, length);
        text += length;
        while (*text == ' ')
        {
            text += 1;
        }
    }
    const size_t operation_length = strcspn(text, " ");
    sass_token_copy(parts->operation, text, operation_length);
    text += operation_length;
    // the operands, split at each comma outside brackets
    int depth = 0;
    const char *start = text;
    for (const char *walk = text;; walk += 1)
    {
        const char character = *walk;
        depth += ((character == '[') || (character == '{') || (character == '(')) ? 1 : 0;
        depth -= ((character == ']') || (character == '}') || (character == ')')) ? 1 : 0;
        if ((character == '\0') || ((character == ',') && (depth == 0)))
        {
            // an operand runs from its start to the comma or the end past it
            const size_t length = (size_t)(walk - start);
            if ((parts->operands < SASS_OPERANDS) && (strspn(start, " ") < length))
            {
                sass_token_copy(parts->operand[parts->operands], start, length);
                parts->operands += 1u;
            }
            start = walk + 1;
        }
        if (character == '\0')
        {
            break;
        }
    }
}

// the encodings at `chosen` written to `path`, the low word then the high, each byte by byte from the lowest: 1, or 0
// where the file could not be written
static int sass_binary_write(const char *path, const unsigned long long *low, const unsigned long long *high,
                             const unsigned int *chosen, unsigned int count)
{
    FILE *const file = fopen(path, "wb");
    if (file == NULL)
    {
        return 0;
    }
    int written = 1;
    for (unsigned int number = 0u; number < count; number += 1u)
    {
        const unsigned long long words[2] = {low[chosen[number]], high[chosen[number]]};
        for (unsigned int word = 0u; word < 2u; word += 1u)
        {
            for (unsigned int byte = 0u; byte < 8u; byte += 1u)
            {
                // one byte of the word, the lowest first
                written = written && (fputc((int)((words[word] >> (8u * byte)) & 0xffull), file) != EOF);
            }
        }
    }
    return (fclose(file) == 0) && written;
}

static SassListing s_sass_decoded;

// the encodings at `chosen` decoded, their texts into `texts` at the same places: the disassembler's exit status, or
// -1 where it did not exit or printed a line at an address past them
static int sass_decode_pass(const char *architecture, const char *path, const unsigned long long *low,
                            const unsigned long long *high, const unsigned int *chosen, unsigned int count,
                            char (*texts)[SASS_TEXT])
{
    char binary[1024];
    char output[1024];
    snprintf(binary, sizeof(binary), "%s.bin", path);
    snprintf(output, sizeof(output), "%s.out", path);
    if (!sass_binary_write(binary, low, high, chosen, count))
    {
        printf("  %s could not be written\n", binary);
        return -1;
    }
    char *const command[] = {"nvdisasm", "--binary", (char *)architecture, binary, NULL};
    const int status = sass_run(command, output);
    if (status != 0)
    {
        return status;
    }
    if (!sass_listing_read(sass_output(), &s_sass_decoded))
    {
        printf("  %s: more than %u instructions\n", output, SASS_LISTING_LIMIT);
        return -1;
    }
    for (unsigned int number = 0u; number < count; number += 1u)
    {
        snprintf(texts[chosen[number]], SASS_TEXT, "unprinted");
    }
    // each line goes to the encoding at its address, 16 bytes to an encoding
    for (unsigned int number = 0u; number < s_sass_decoded.count; number += 1u)
    {
        const SassInstruction *const decoded = &s_sass_decoded.instructions[number];
        if (((decoded->address % 16ull) != 0ull) || ((decoded->address / 16ull) >= (unsigned long long)count))
        {
            printf("  %s: a line at address 0x%llx, past the %u encodings given\n", output, decoded->address, count);
            return -1;
        }
        memcpy(texts[chosen[decoded->address / 16ull]], decoded->text, SASS_TEXT);
    }
    return 0;
}

int sass_decode(const char *architecture, const char *path, const unsigned long long *low,
                const unsigned long long *high, unsigned int count, char (*texts)[SASS_TEXT])
{
    unsigned int chosen[SASS_LISTING_LIMIT];
    if (count > SASS_LISTING_LIMIT)
    {
        return 0;
    }
    for (unsigned int number = 0u; number < count; number += 1u)
    {
        chosen[number] = number;
        snprintf(texts[number], SASS_TEXT, "illegal");
    }
    const int status = sass_decode_pass(architecture, path, low, high, chosen, count, texts);
    if (status == 0)
    {
        return 1;
    }
    if (status < 0)
    {
        return 0;
    }
    // the disassembler refused the batch and named each encoding it refused by its address, 16 bytes to an encoding
    int refused[SASS_LISTING_LIMIT];
    memset(refused, 0, sizeof(refused));
    unsigned int named = 0u;
    for (const char *walk = strstr(sass_output(), "at address 0x"); walk != NULL;
         walk = strstr(walk + 1, "at address 0x"))
    {
        const unsigned long long place = strtoull(walk + 13, NULL, 16) / 16ull;
        if (place < (unsigned long long)count)
        {
            named += refused[place] ? 0u : 1u;
            refused[place] = 1;
        }
    }
    if (named == 0u)
    {
        printf("  nvdisasm exited %d naming no encoding it refused:\n%s", status, sass_output());
        return 0;
    }
    unsigned int legal = 0u;
    for (unsigned int number = 0u; number < count; number += 1u)
    {
        if (!refused[number])
        {
            chosen[legal] = number;
            legal += 1u;
        }
    }
    char second[1024];
    snprintf(second, sizeof(second), "%s_legal", path);
    return (legal == 0u) || (sass_decode_pass(architecture, second, low, high, chosen, legal, texts) == 0);
}
