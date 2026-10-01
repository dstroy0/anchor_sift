// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cell_sass_probe_cubin.c: a cubin written from text. The probe learns what the part holds by reading its tools;
// this is the other direction, putting instructions of the cell's own into a cubin the part will load and run, with
// a cubin the toolchain built standing as the pattern for everything an ELF carries that no instruction states
#include "cell_sass_probe.h"
#include "cubin_write.h"
#include "sass_assemble.h"

#include <stdio.h>
#include <string.h>

// the most bytes a cubin, its code and its text take
#define SASS_CUBIN_BYTES 262144u
#define SASS_CODE_BYTES 65536u
#define SASS_TEXT_BYTES 262144u
#define SASS_EXITS 256u

static unsigned char s_pattern[SASS_CUBIN_BYTES];
static unsigned char s_cubin[SASS_CUBIN_BYTES];
static unsigned char s_code[SASS_CODE_BYTES];
static char s_text[SASS_TEXT_BYTES];
static unsigned int s_exits[SASS_EXITS];

// `path` read whole into `bytes`, which holds `room` of them: how many were read, 0 where the file was not read
static unsigned long long sass_file_read(const char *path, unsigned char *bytes, unsigned long long room)
{
    FILE *const file = fopen(path, "rb");
    if (file == NULL)
    {
        printf("  cubin: %s could not be read\n", path);
        return 0ull;
    }
    const unsigned long long read = (unsigned long long)fread(bytes, 1u, (size_t)room, file);
    fclose(file);
    return read;
}

static int sass_file_write(const char *path, const unsigned char *bytes, unsigned long long size)
{
    FILE *const file = fopen(path, "wb");
    const int written = (file != NULL) && (fwrite(bytes, 1u, (size_t)size, file) == size);
    const int closed = (file != NULL) && (fclose(file) == 0);
    if (!written || !closed)
    {
        printf("  cubin: %s could not be written\n", path);
    }
    return written && closed;
}

unsigned int sass_cubin_text(const char *folder, const char *name, char *text, unsigned int room)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.sass", folder, name);
    static unsigned char s_listing[SASS_TEXT_BYTES];
    const unsigned long long listing_size = sass_file_read(path, s_listing, sizeof(s_listing) - 1u);
    if (listing_size == 0ull)
    {
        return 0u;
    }
    s_listing[listing_size] = '\0';
    const unsigned int text_size = sass_text_read((const char *)s_listing, "cell_ask", text, room);
    // the text the listing was turned back into, kept beside it for a reader
    snprintf(path, sizeof(path), "%s/%s.text", folder, name);
    sass_file_write(path, (const unsigned char *)text, text_size);
    return text_size;
}

int sass_cubin_kernel(const SassMachine *machine, const char *folder, const char *pattern, const char *text,
                      const char *into, const char *kernel)
{
    char path[1024];
    snprintf(path, sizeof(path), "%s/%s.cubin", folder, pattern);
    const unsigned long long pattern_size = sass_file_read(path, s_pattern, sizeof(s_pattern));
    if (pattern_size == 0ull)
    {
        return 0;
    }
    const unsigned int instructions = sass_assemble_lines(machine, text, SASS_CONTROL_SAFE, s_code, sizeof(s_code));
    if (instructions == 0u)
    {
        printf("  cubin: %s assembled nothing\n", into);
        return 0;
    }
    const unsigned long long code_size = 16ull * instructions;
    CubinWrite written;
    memset(&written, 0, sizeof(written));
    written.pattern = s_pattern;
    written.pattern_size = pattern_size;
    written.kernel = kernel;
    written.code = s_code;
    written.code_size = code_size;
    written.registers = cubin_registers_read(s_pattern, kernel);
    written.exit_count = cubin_exits_find(s_code, code_size, sass_exit_encoding(machine), s_exits, SASS_EXITS);
    written.exits = s_exits;
    unsigned long long size = 0ull;
    if (!cubin_write(&written, s_cubin, sizeof(s_cubin), &size))
    {
        return 0;
    }
    snprintf(path, sizeof(path), "%s/%s.cubin", folder, into);
    return sass_file_write(path, s_cubin, size);
}

int sass_cubin_from_text(const SassMachine *machine, const char *folder, const char *pattern, const char *text,
                         const char *into)
{
    return sass_cubin_kernel(machine, folder, pattern, text, into, "cell_ask");
}

int sass_cubin_round(const SassMachine *machine, const char *folder, const char *name)
{
    char into[256];
    snprintf(into, sizeof(into), "%s_written", name);
    return (sass_cubin_text(folder, name, s_text, sizeof(s_text)) != 0u) &&
           sass_cubin_from_text(machine, folder, name, s_text, into);
}

int sass_cubin_lane_into(const SassMachine *machine, const char *folder, const char *text, const char *into)
{
    return sass_cubin_kernel(machine, folder, "resident", text, into, "cycle_lane");
}
