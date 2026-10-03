// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// sha256_check.c: sha256 held to NIST's published SHA-256 vectors (CAVP, the SHAVS files vendored beside the qasm
// tests). Each message file gives a length, a message and its digest, the byte files a length in whole bytes and the
// bit files any count of bits; the Monte file gives a seed and the digest of every hundred-and-first link of a chain,
// each link the digest of the three before it laid end to end (SHAVS section 6.4).
//
//     sha256_check <message file>... --monte <monte file>
//
// One line a file with its counts, and a last line with the total. Exit 0 where every vector holds, 1 where any does
// not, 2 where a file did not read.
#include "../../../../../../../src/c/includes/codecs/sha256/sha256.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// the longest line a vector file holds, a long message's hex with its name
#define CHECK_LINE_BYTES 1048576u
// the links a Monte checkpoint is the last of, and the checkpoints the file holds
#define CHECK_MONTE_LINKS 1000u
#define CHECK_MONTE_POINTS 100u

static char s_line[CHECK_LINE_BYTES];
static unsigned char s_message[CHECK_LINE_BYTES / 2u];

// the hex digits at `text` up to the first character that is not one, into `bytes`: the bytes written
static size_t check_hex(const char *text, unsigned char *bytes, size_t room)
{
    size_t written = 0u;
    while ((written < room) && (text[0] != '\0') && (text[1] != '\0'))
    {
        unsigned int value = 0u;
        if (sscanf(text, "%2x", &value) != 1)
        {
            break;
        }
        bytes[written] = (unsigned char)value;
        written += 1u;
        text += 2;
    }
    return written;
}

// the text after `name = ` where `line` begins with it, or NULL
static const char *check_value(const char *line, const char *name)
{
    const size_t length = strlen(name);
    if ((strncmp(line, name, length) != 0) || (strncmp(&line[length], " = ", 3u) != 0))
    {
        return NULL;
    }
    return &line[length + 3u];
}

// every Len, Msg and MD triple of the file at `path` checked: the vectors that held through `held` and those that
// did not through `failed`. 1, or 0 where the file did not read
static int check_messages(const char *path, unsigned int *held, unsigned int *failed)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return 0;
    }
    // a byte file counts its length in bits too, every one a multiple of 8
    unsigned long long bits = 0ull;
    size_t message_bytes = 0u;
    int have_length = 0;
    int have_message = 0;
    while (fgets(s_line, sizeof(s_line), file) != NULL)
    {
        s_line[strcspn(s_line, "\r\n")] = '\0';
        const char *value = check_value(s_line, "Len");
        if (value != NULL)
        {
            bits = strtoull(value, NULL, 10);
            have_length = 1;
            have_message = 0;
            continue;
        }
        value = check_value(s_line, "Msg");
        if ((value != NULL) && have_length)
        {
            message_bytes = check_hex(value, s_message, sizeof(s_message));
            have_message = 1;
            continue;
        }
        value = check_value(s_line, "MD");
        if ((value != NULL) && have_message)
        {
            unsigned char expected[SHA256_BYTES];
            unsigned char digest[SHA256_BYTES];
            const int read = check_hex(value, expected, sizeof(expected)) == SHA256_BYTES;
            const int fits = (bits + 7ull) / 8ull <= (unsigned long long)message_bytes;
            if (fits)
            {
                sha256_bits(s_message, bits, digest);
            }
            if (read && fits && (memcmp(digest, expected, SHA256_BYTES) == 0))
            {
                *held += 1u;
            }
            else
            {
                *failed += 1u;
                printf("  %s: Len = %llu does not hold\n", path, bits);
            }
            have_length = 0;
            have_message = 0;
        }
    }
    fclose(file);
    return 1;
}

// the Monte file at `path` checked: the seed, then each checkpoint's digest the last of a chain of links each the
// digest of the three before it, the chain begun again from that digest. 1, or 0 where the file did not read
static int check_monte(const char *path, unsigned int *held, unsigned int *failed)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        return 0;
    }
    unsigned char seed[SHA256_BYTES];
    int have_seed = 0;
    unsigned int point = 0u;
    while (fgets(s_line, sizeof(s_line), file) != NULL)
    {
        s_line[strcspn(s_line, "\r\n")] = '\0';
        const char *value = check_value(s_line, "Seed");
        if (value != NULL)
        {
            have_seed = check_hex(value, seed, sizeof(seed)) == SHA256_BYTES;
            continue;
        }
        value = check_value(s_line, "MD");
        if ((value == NULL) || !have_seed || (point >= CHECK_MONTE_POINTS))
        {
            continue;
        }
        // the three links before the next, laid end to end, the oldest first
        unsigned char links[3u * SHA256_BYTES];
        memcpy(&links[0], seed, SHA256_BYTES);
        memcpy(&links[SHA256_BYTES], seed, SHA256_BYTES);
        memcpy(&links[2u * SHA256_BYTES], seed, SHA256_BYTES);
        unsigned char next[SHA256_BYTES];
        for (unsigned int link = 0u; link < CHECK_MONTE_LINKS; link += 1u)
        {
            sha256(links, sizeof(links), next);
            memmove(&links[0], &links[SHA256_BYTES], 2u * SHA256_BYTES);
            memcpy(&links[2u * SHA256_BYTES], next, SHA256_BYTES);
        }
        unsigned char expected[SHA256_BYTES];
        if ((check_hex(value, expected, sizeof(expected)) == SHA256_BYTES) &&
            (memcmp(next, expected, SHA256_BYTES) == 0))
        {
            *held += 1u;
        }
        else
        {
            *failed += 1u;
            printf("  %s: COUNT = %u does not hold\n", path, point);
        }
        memcpy(seed, next, SHA256_BYTES);
        point += 1u;
    }
    fclose(file);
    return 1;
}

int main(int count, char **words)
{
    unsigned int held_total = 0u;
    unsigned int failed_total = 0u;
    int monte = 0;
    for (int at = 1; at < count; at += 1)
    {
        if (strcmp(words[at], "--monte") == 0)
        {
            monte = 1;
            continue;
        }
        unsigned int held = 0u;
        unsigned int failed = 0u;
        const int read = monte ? check_monte(words[at], &held, &failed) : check_messages(words[at], &held, &failed);
        if (!read)
        {
            fprintf(stderr, "  %s did not read\n", words[at]);
            return 2;
        }
        printf("  %s: %u held, %u failed\n", words[at], held, failed);
        held_total += held;
        failed_total += failed;
        monte = 0;
    }
    printf("sha256 check: %u vectors held, %u failed\n", held_total, failed_total);
    return ((failed_total == 0u) && (held_total != 0u)) ? 0 : 1;
}
